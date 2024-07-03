-- Lua (Keep this comment, this is an indication for editor's 'run' command)

--------------------------------
-- Global Paths              ---
--------------------------------
    
-- root
local project_root = gom.get_environment_value("PROJECT_ROOT")

--------------------------------
-- Utils                     ---
--------------------------------

-- Recursively search in directory files that match with the pattern 
function search(dir, pattern)
   local files = {}

   for i, path in pairs(FileSystem.get_files(dir)) do
      local file = FileSystem.base_name(path,false)
      if string.match(file, pattern) ~= nil then
         table.insert(files, path)
      end
   end
   for i, path in pairs(FileSystem.get_subdirectories(dir)) do
      local rec_files = search(path, pattern)
      for _, f in pairs(rec_files) do 
         table.insert(files, f)
      end
   end

   return files
end

function to_table(it)
   local t = {}
   for x in it do 
      table.insert(t, x)
   end 
   return t
end

-- Remove some characters that graphite doesn't support
function string.clean(str)
   return str:gsub("%-", "_"):gsub("% ", "_"):gsub("%/", "_"):gsub("%.", "_")
end

-- Check whether a string is empty or not
function string.empty(str)
   return str == nil or str == ""
end

-- Join strings with a given character
function string.join(lines, c)
   if not lines then 
      return nil 
   end
   local s = ""
   for line in lines do 
      s = s .. line .. c
   end 
   return string.sub(s, 0, string.len(s) - string.len(c))
end

-- Count number of element in a table
function table_count(t)
   local count = 0
   for _ in pairs(t) do 
      count = count + 1
   end
   return count
end

-- Concat two tables
function concat_table(t1, t2) 
   local t = {}
   for _, v in pairs(t1) do 
      table.insert(t, v)
   end
   for _, v in pairs(t2) do
      table.insert(t, v)
   end  
   return t
end 

--------------------------------
-- Graphite utils            ---
--------------------------------

-- Get attribute data of a mesh
function get_attributes_data(object)
   local str_attrs = string.split(object.attributes, ';')

   S = scene_graph.find_or_create_object('OGF::MeshGrob', object.name)
   E = S.I.Editor

   local attr = {}
   for str_attr in str_attrs do 
      local primitive, name = table.unpack(to_table(string.split(str_attr, '.')))
      local attr_data  = E.find_attribute(str_attr)
      attr[str_attr] = {name = name, primitive = primitive, dim = attr_data.dimension, type = attr_data.element_meta_type.name}
   end

   return attr
end

-- Check whether the parameter type belong to an attribute type (vertices, facets, edges...)
function is_param_is_type_attribute(param_type)
   return (string.starts_with(param_type, 'vertices') 
   or string.starts_with(param_type, 'facets') 
   or string.starts_with(param_type, 'edges')
   or string.starts_with(param_type, 'cells')
   or string.starts_with(param_type, 'facet_corners'))
end

-- Extract attribute name long name (e.g: vertices.my_attr -> my_attr)
function get_attribute_shortname(attr_name)
   return to_table(string.split(attr_name, '.'))[2]
end

--------------------------------
-- Global                    ---
--------------------------------

--------------------------------
-- Serialization/Format      ---
--------------------------------

-- Get structured parameters object by parsing lines
function parameters_from_lines(lines)
   local parameters = {}
   
   for line in lines do 
      
      -- skip comments
      if string.sub(line, 0, 1) ~= '#' then 
         -- get chunks
         chunks = string.split(line, ';')
         local t = {}
         for chunk in chunks do 
            local kv = to_table(string.split(chunk, '='))
            t[kv[1]] = kv[2]
         end
         
         -- local p = parameters_from_chunks(t)
         table.insert(parameters, t)
         
      end 
      
   end

   return parameters
end

-- Check arg value is well formed and well typed
function check_arg(param, val)

   local success = true 

   -- If parameter is of attribute type
   if is_param_is_type_attribute(param.type) then
      
      local actual_attrs_data = get_attributes_data(scene_graph.current())

      -- Check attribute existence
      if actual_attrs_data[val] == nil then 
         print("Attribute " .. val .. " doesn't exists.")
         success = false
      else 
         local actual_attr_data = actual_attrs_data[val]
         local actual_param_type = actual_attr_data['primitive'] .. "." .. actual_attr_data['type'] .. "." .. actual_attr_data['dim']

         -- Bruno have renammed vertices.bool type to vertices.OGF::Numeric::uint8 for example between two versions of graphite...
         -- so I have to check the new name and old name to be sure it works
         local actual_param_type_renamed = actual_attr_data['primitive'] .. "." .. t_attr_reverse_map[actual_attr_data['type']] .. "." .. actual_attr_data['dim']

         -- Check attribute type consistency between expected and actual
         if not (param.type == actual_param_type or param.type == actual_param_type_renamed) then 
            print(
               "Parameter '".. param.name .. 
               "' expect an attribute of type '" .. param.type .. 
               "', but attribute '" .. val .. 
               "' of type '" ..  actual_param_type .. "' was given."
            )
            success = false
         end
         
      end

   end 

   return success
end

-- Check arg values are well formed and well typed
function check_args(params, args)
   
   for _, param in pairs(params) do 
      local clean_param_name = string.clean(param.name)
      if not check_arg(param, args[clean_param_name]) then 
         return false
      end
   end 

   return true
end

function map_param(input_path, output_model_path, param, val)
   
   local str_val = ""
   if val == nil then 
      str_val = ""
   end 

   -- Set automatically special parameters
   if param.type == 'input' then
      str_val = input_path
   elseif param.name == 'result_path' then 
      str_val = output_model_path
   elseif param.name == 'run_from' then 
      str_val = "graphite"
   -- Attribute parameters
   elseif is_param_is_type_attribute(param.type) then 
      str_val = get_attribute_shortname(val)
   else
      -- Set value or default value
      if val ~= nil then 
         str_val = tostring(val)
      else 
         str_val = param.value
      end
   end

   return param.name .. "=" .. str_val
end

-- format parameters into a string key1=value1 key2=value2 ...
function format_args(input_path, output_model_path, params, args)
   
   local str = ""
   for _, param in pairs(params) do 
      local clean_param_name = string.clean(param.name)      
      str = str.." "..map_param(input_path, output_model_path, param, args[clean_param_name])
   end 

   return str
end

function load_outputs(sandbox_dir)
   -- Load outputs
   local obj_models = search(sandbox_dir, ".*%.obj")
   local geogram_models = search(sandbox_dir, ".*%.geogram")
   local mesh_models = search(sandbox_dir, ".*%.mesh")

   local models = concat_table(obj_models, geogram_models)
   local models = concat_table(models, mesh_models)

   local prev_current_object = scene_graph.current_object

   for _, model in pairs(models) do 
      print('Load: '..model)
      scene_graph.load_object(model)
   end
   
   scene_graph.current_object = prev_current_object
      
end

-- Remove sandbox dir if empty
function cleanup_sandbox(sandbox_dir)
   local entries = FileSystem.get_directory_entries(sandbox_dir)
   if table_count(entries) == 0 then 
      FileSystem.delete_directory(sandbox_dir)
      print("Sandbox '" .. sandbox_dir .. "' is empty, cleanup...")
   end
end

-- Execute program
function exec_addon(addon)

   -- Curryfied
   local exec = function(args)
      print('args='..tostring(args))
      
      -- Check whether a model selected
      if addon.is_mesh_expected and scene_graph.current() == nil then
         print('No object selected.')
         return
      end

      local object = scene_graph.current()

      -- Get plugin to execute
      local plug_name = args['method']
      
      print("Add-on: "..addon.name)

      -- Check arguments
      if not check_args(addon.parameters, args) then 
         print("Abort add-on call.")
         return
      end

      -- Create a sandbox
      -- Get document root
      -- TODO replace by tmp dir
      local project_root = FileSystem.documents_directory()
      local sandbox_dir = project_root .. "/" .. "sandbox_" .. os.clock()
      FileSystem.create_directory(sandbox_dir)
      print("Sandbox dir created: "..sandbox_dir)

      -- Save & Copy current model (in order to keep last changes that occurred to the model !)
      -- TODO UUID here !
      local input_model_path = ""
      if addon.is_mesh_expected then 
         local file_extension = FileSystem.extension(object.filename)
         print(file_extension)
         input_model_path = sandbox_dir .. '/' .. object.name .. "_" .. os.clock() .. "." .. file_extension
         if not object.save(input_model_path) then
            print('An error occurred when transfering the current model to add-on.')
            return
         end
      end 

      local output_model_path = sandbox_dir .. "/output"

      -- exec bin in sandbox
      -- local wd = FileSystem.get_current_working_directory()
      -- FileSystem.set_current_working_directory(sandbox_dir)

      -- Create output directory
      FileSystem.create_directory(output_model_path)

      local str_args = format_args(input_model_path, output_model_path, addon.parameters, args)
      local cmd = addon.path .. " " .. str_args
      
      print('call: ' .. cmd)
      -- Run command
      os.execute(cmd)

      -- Reset working dir
      -- FileSystem.set_current_working_directory(wd)

      -- Load models found into sandbox
      print('Load outputs...')
      load_outputs(output_model_path)

      -- Clean up if empty
      cleanup_sandbox(sandbox_dir)
   end 

   return exec
end

-- map table of types to gom types
t_map = { 
   double = gom.meta_types.double,
   float = gom.meta_types.float,
   int = gom.meta_types.int, 
   bool = gom.meta_types.bool, 
   string = gom.meta_types.std.string, 
   file = gom.meta_types.OGF.FileName,
   input = gom.meta_types.OGF.FileName,
}

t_attr_map = {
   double = 'OGF::Numeric::float64',
   float = 'OGF::Numeric::float64',
   int = 'OGF::Numeric::int32',
   uint = 'OGF::Numeric::uint32',
   bool = 'OGF::Numeric::uint8',
}

t_attr_reverse_map = {}
t_attr_reverse_map['OGF::Numeric::float64'] = 'double'
t_attr_reverse_map['OGF::Numeric::int32'] = 'int'
t_attr_reverse_map['OGF::Numeric::uint32'] = 'uint'
t_attr_reverse_map['OGF::Numeric::uint8'] = 'bool'
-- Note: for facet corners, type are returned by graphite in normal form 'int', 'double' instead of 'OGF::Numeric::int32', 'OGF::Numeric::float64'
-- I don't know why this is different between facet_corners attributes and other attributes, should ask to Bruno L.
-- That's why I added this mapping below
t_attr_reverse_map['double'] = 'double'
t_attr_reverse_map['int'] = 'int'
t_attr_reverse_map['uint'] = 'uint'
t_attr_reverse_map['bool'] = 'bool'

function draw_addon_menu(addon)

   -- Choose the menu to add the add-on
   -- If add-on expect a mesh as input it goes to MeshGrob menu, else to SceneGraph menu
   -- Contrary to SceneGraph menu, MeshGrob menu is only visible when a mesh is loaded
   local mclass = nil
   if addon.is_mesh_expected then 
      mclass = mclass_mesh_grob_command 
   else 
      mclass = mclass_scene_graph_command
   end

   local parameters = addon.parameters   
   
   -- And another command, also created in the 'Foobars' submenu
   m = mclass.add_slot(addon.name, exec_addon(addon))
   -- Add add-on help as tooltip text
   if not string.empty(addon.help) then 
      m.create_custom_attribute('help', addon.help)
   end
   
   for _, param in pairs(parameters) do

      local clean_param_name = string.clean(param.name)

      -- Map string param type to gom type
      local param_type = t_map[param.type]
      if param_type == nil then 
         param_type = gom.meta_types.std.string
      end

      -- Doesn't display special parameters that will be automatically filled by graphite !
      -- - parameters with 'input' type
      -- - parameter of type 'system'
      if param.type ~= 'input' and param.type_of_param ~= 'system' then
         if param.value ~= "undefined" then
            m.add_arg(clean_param_name, param_type, param.value)
         else
            m.add_arg(clean_param_name, param_type)
         end 

         -- Add description as tooltip text
         m.create_arg_custom_attribute(clean_param_name, 'help', param.description)


         -- # Attribute management !

         -- If parameter type is an attribute type, add attribute combobox to UI
         if is_param_is_type_attribute(param.type) then 
            m.create_arg_custom_attribute(clean_param_name, 'handler','combo_box')

            -- Filter by attribute type / primitive
            primitive, type, dim = table.unpack(to_table(string.split(param.type, '.')))
            m.create_arg_custom_attribute(clean_param_name, 'values', '$grob.list_attributes("' .. primitive .. '","' .. t_attr_map[type] .. '","' .. tostring(dim) .. '")')
         end
         
         -- # Enum management !

         -- Possible values is set ! So should display a combo box with all choices
         if (not (string.empty(param.possible_values) or param.possible_values == 'undefined')) then 
            local values = param.possible_values:gsub(",", ";")
            m.create_arg_custom_attribute(clean_param_name, 'handler','combo_box')
            m.create_arg_custom_attribute(clean_param_name, 'values', values)
         end

      end 



   end 
   

   m.create_custom_attribute('menu','/Externals')

   return m
   
end

function draw_addons_menus(addons)
   for _, addon in pairs(addons) do 
      draw_addon_menu(addon)
   end
end

-- We are going to create a subclass of OGF::MeshGrobCommands,
-- let us first get the metaclass associated with OGF::MeshGrobCommands
mclass_mesh_grob_superclass = gom.meta_types.OGF.MeshGrobCommands 

-- Create our subclass, that we name OGF::MeshGrobCustomCommands
-- By default, our commands will land in a new menu 'Custom'
-- (name your class OGF::MeshGrobZorglubCommands if you want a 'Zorglub'
-- menu, or use custom attributes, see below).
mclass_mesh_grob_command = mclass_mesh_grob_superclass.create_subclass('OGF::LuaGrobCustomCommands')

-- Create a constructor for our new class.
-- For Commands classes, we just create the default constructor
-- (one can also create constructors with arguments, but we do not need that here)
mclass_mesh_grob_command.add_constructor()

mclass_scene_graph_command_superclass = gom.meta_types.OGF.SceneGraphCommands
mclass_scene_graph_command = mclass_scene_graph_command_superclass.create_subclass('OGF::SceneGraphExternalCommands')
mclass_scene_graph_command.add_constructor()

--------------------------------
-- Draw menus                ---
--------------------------------

-- Make our new Commands visible from MeshGrob
scene_graph.register_grob_commands(gom.meta_types.OGF.MeshGrob, mclass_mesh_grob_command)


local addon_loader_file = project_root .. "/addon_loader.txt"

function load_addon_directory()

   if not FileSystem.is_file(addon_loader_file) then 
      return project_root
   end 

   local f = io.open(addon_loader_file, "r")
   local data = f:read("*all")
   f:close()
   return data
end

function save_addon_directory(directory)
   add_ons_directory = directory
   local f = io.open(addon_loader_file, "w")
   f:write(directory)
   f:close()
end

add_ons_directory = load_addon_directory()
print("addons directory: " .. add_ons_directory)


function search_addons(directory)
   -- return search(directory, ".*_addon[%.exe]?$")
   return search(directory, ".*_addon.*")
end

function search_params_files(directory)
   return search(directory, ".*%.params")
end

function search_help_files(directory)
   return search(directory, ".*%.help")
end

function scan_directory(directory)

   -- Search for addons programs
   local addons = search_addons(directory)

   for _, addon in pairs(addons) do 

      local param_file = addon .. ".params"
      local help_file = addon .. ".help"
      
      -- Call program to get its parameters
      -- Call program to get its help string
      os.execute(addon .. " --show-params > " .. param_file)
      os.execute(addon .. " -h > " .. help_file)

      
      -- Check params file
      local f = io.open(param_file, "r")
      local data = f:read("*all")
      f:close()

      -- No content ? Not an addon !
      if string.empty(data) then 
         FileSystem.delete_file(param_file)
         FileSystem.delete_file(help_file)
      end



   end

end

function sync()

   if not FileSystem.is_directory(add_ons_directory) then 
      print(add_ons_directory .. " is not a directory. Add-on loader expect to load add-ons from a directory.")
      return
   end

   local param_files = search_params_files(add_ons_directory)
   local help_files = search_help_files(add_ons_directory)

   for _, param_file in pairs(param_files) do 
      FileSystem.delete_file(param_file)
   end
   for _, help_file in pairs(help_files) do 
      FileSystem.delete_file(help_file)
   end

   scan_directory(add_ons_directory)
   local addons = load_addons(add_ons_directory)
   draw_addons_menus(addons)

end

function load_addons(directory)

   local param_files = search_params_files(directory)

   local addons = {}

   for _, param_file in pairs(param_files) do 
      -- read
      local lines = io.lines(param_file)
      local parameters = parameters_from_lines(lines)
   
      -- Extract addon name
      local addon_name = FileSystem.base_name(param_file, true)
      local clean_addon_name = string.clean(addon_name)

      -- Search for an input parameter
      local is_mesh_expected = false
      for k, p in pairs(parameters) do 
         if p.type == 'input' then 
            is_mesh_expected = true 
         end
      end

      -- Create a new addon object
      local addon = {
         name = clean_addon_name,
         path = param_file:gsub(".params", ""),
         parameters = parameters,
         help = "",
         is_mesh_expected = is_mesh_expected
      }

      -- local lines = io.lines(help_file)
      -- local help = string.join(lines, '\n')

      -- Keep plugin object in a associative map
      addons[addon.name] = addon
   end

   return addons
end

-- Make our new commands visible from MeshGrob
scene_graph.register_grob_commands(gom.meta_types.OGF.SceneGraph, mclass_scene_graph_command)

-- Add menus to manage external plugins

-- Add plugin menu
local m_add_plugin = mclass_scene_graph_command.add_slot("Parameters", function(args) 

   save_addon_directory(args.add_ons_directory)
   sync()
   
end)


-- Add menu to add addons directory
m_add_plugin.add_arg("add_ons_directory", gom.meta_types.OGF.FileName, add_ons_directory)
m_add_plugin.create_custom_attribute('menu','/Externals/Manage add ons')

-- Add menu to sync addons
m_clean_plugin = mclass_scene_graph_command.add_slot("Syncronize_and_Quit", function() 
   sync() 
   main.stop()
end)
m_clean_plugin.create_custom_attribute('menu','/Externals/Manage add ons')

-- Load addons
local addons = load_addons(add_ons_directory)
draw_addons_menus(addons)
