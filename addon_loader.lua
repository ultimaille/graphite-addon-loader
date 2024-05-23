-- Lua (Keep this comment, this is an indication for editor's 'run' command)

--------------------------------
-- Global Paths              ---
--------------------------------
    
-- root
local project_root = gom.get_environment_value("PROJECT_ROOT")

--------------------------------
-- Utils                     ---
--------------------------------

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

function os.capture(cmd, raw)
   local f = assert(io.popen(cmd, 'r'))
   local s = assert(f:read('*a'))
   f:close()
   if raw then return s end
   s = string.gsub(s, '^%s+', '')
   s = string.gsub(s, '%s+$', '')
   s = string.gsub(s, '[\n\r]+', ' ')
   return s
end

function os.capture2(name, cmd)
   local param_file = project_root .. "/" .. name .. "_params.epf"
   -- Execute and redirect stdout out into a file (cannot use popen, not crossplatform !)
   os.execute(cmd .. " > " .. param_file)
   -- Return param file name
   return param_file
end

function to_table(it)
   local t={}
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

-- Check whether a name is valid
function is_name_valid(name)
   for i = 1, #name do 
      local c = name:sub(i,i)
      if c == "-" or c == " " or c == "/" or c == "." or c == "\\" then 
         return false
      end
   end
   return true
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
   or string.starts_with(param_type, 'cells'))
end

-- Extract attribute name long name (e.g: vertices.my_attr -> my_attr)
function get_attribute_shortname(attr_name)
   return to_table(string.split(attr_name, '.'))[2]
end

--------------------------------
-- Global                    ---
--------------------------------

-- Load external processes
local ext_plugins = {}

--------------------------------
-- Serialization/Format      ---
--------------------------------

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

   if param.type == 'input' then
      str_val = input_path
   elseif param.name == 'result_path' then 
      str_val = output_model_path
   elseif is_param_is_type_attribute(param.type) then 
      str_val = get_attribute_shortname(val)
   else
      str_val = tostring(val)
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

   for _, model in pairs(models) do 
      print('Load: '..model)
      scene_graph.load_object(model)
   end

   -- -- Camera go back to home
   -- graphite_main_window.home()
end

function cleanup_sandbox(sandbox_dir)
   local entries = FileSystem.get_directory_entries(sandbox_dir)
   if table_count(entries) == 0 then 
      FileSystem.delete_directory(sandbox_dir)
      print("Sandbox '"..sandbox_dir.."' is empty, cleanup...")
   end
end

-- Execute program
function exec_bin(args)
   print('args='..tostring(args))
   
   -- Check whether a model selected
   if scene_graph.current() == nil then
      print('No object selected.')
      return
   end

   local object = scene_graph.current()

   -- Get plugin to execute
   local plug_name = args['method']
   ext_plugin = ext_plugins[plug_name]
   print("Add-on: "..ext_plugin.name)

   -- Check arguments
   if not check_args(ext_plugin.parameters, args) then 
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
   local file_extension = FileSystem.extension(object.filename)
   print(file_extension)
   local input_model_path = sandbox_dir .. '/' .. object.name .. "_" .. os.clock() .. "." .. file_extension
   if not object.save(input_model_path) then
      print('An error occurred when transfering the current model to add-on.')
      return
   end

   local output_model_path = sandbox_dir .. "/output"

   -- exec bin in sandbox
   local wd = FileSystem.get_current_working_directory()
   FileSystem.set_current_working_directory(sandbox_dir)

   local str_args = format_args(input_model_path, output_model_path, ext_plugin.parameters, args)
   local cmd = ext_plugin.call_cmd .. " " .. str_args
   
   print('call: ' .. cmd)
   -- Run command
   os.execute(cmd)

   -- Reset working dir
   FileSystem.set_current_working_directory(wd)

   -- Clean up model used as input
   FileSystem.delete_file(input_model_path)

   -- Load models found into sandbox
   object.selections = {}
   load_outputs(output_model_path)

   -- Clean up if empty
   cleanup_sandbox(sandbox_dir)
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

-- -- -- -- Create a new enum type
-- m_attr_enum = gom.meta_types.OGF.MetaEnum.create('Yop')
-- -- local str_attributes = scene_graph.current().scalar_attributes
-- -- local str_attributes_list = string.split(';', str_attributes)
-- -- local t_attr_enum = to_table(str_attributes_list)
-- -- -- Declare enum values
-- m_attr_enum.add_values({a = "a", b = "b"})
-- -- -- Make new enum visible from GOM type system
-- gom.bind_meta_type(m_attr_enum)


function draw_menu(mclass, ext_plugin)

   local parameters = ext_plugin.parameters   
   -- filter parameters to exclude not visible
   local filtered_parameters = {}
   for i, param in pairs(parameters) do 
      if param.visible == nil or param.visible == 'true' then 
         table.insert(filtered_parameters, param)
      end
   end
   
   -- And another command, also created in the 'Foobars' submenu
   m = mclass.add_slot(ext_plugin.name, exec_bin)
   
   for _, param in pairs(filtered_parameters) do

      local clean_param_name = string.clean(param.name)

      -- Map string param type to gom type
      local param_type = t_map[param.type]
      if param_type == nil then 
         param_type = gom.meta_types.std.string
      end

      -- Doesn't display special parameters that will be automatically filled by graphite !
      -- - parameters with 'input' type
      -- - parameter named 'result_path'
      if param.type ~= 'input' and param.name ~= 'result_path' then
         if param.value ~= "undefined" then
            m.add_arg(clean_param_name, param_type, param.value)
         else
            m.add_arg(clean_param_name, param_type)
         end 

         -- Add description as tooltip text
         m.create_arg_custom_attribute(clean_param_name, 'help', param.description)
      end 




      -- If parameter type is an attribute type, add attribute combobox to UI
      if is_param_is_type_attribute(param.type) then 
         m.create_arg_custom_attribute(clean_param_name, 'handler','combo_box')
         -- m.create_arg_custom_attribute(clean_param_name, 'values', '$grob.attributes')
         -- Filter by attribute type / primitive
         primitive, type, dim = table.unpack(to_table(string.split(param.type, '.')))
         m.create_arg_custom_attribute(clean_param_name, 'values', '$grob.list_attributes("' .. primitive .. '","' .. t_attr_map[type] .. '","' .. tostring(dim) .. '")')
      end

      -- Possible values is set ! So should display a combo box with all choices
      if (not (string.empty(param.possible_values) or param.possible_values == 'undefined')) then 
         local values = param.possible_values:gsub(",", ";")
         m.create_arg_custom_attribute(clean_param_name, 'handler','combo_box')
         m.create_arg_custom_attribute(clean_param_name, 'values', values)
      end

   end 

   m.create_custom_attribute('menu','/Externals')

   return m
   
end

-- We are going to create a subclass of OGF::MeshGrobCommands,
-- let us first get the metaclass associated with OGF::MeshGrobCommands
superclass = gom.meta_types.OGF.MeshGrobCommands 

-- Create our subclass, that we name OGF::MeshGrobCustomCommands
-- By default, our commands will land in a new menu 'Custom'
-- (name your class OGF::MeshGrobZorglubCommands if you want a 'Zorglub'
-- menu, or use custom attributes, see below).
mclass = superclass.create_subclass('OGF::LuaGrobCustomCommands')

-- Create a constructor for our new class.
-- For Commands classes, we just create the default constructor
-- (one can also create constructors with arguments, but we do not need that here)
mclass.add_constructor()

mclass_scene_graph_command_superclass = gom.meta_types.OGF.SceneGraphCommands
mclass_scene_graph_command = mclass_scene_graph_command_superclass.create_subclass('OGF::SceneGraphExternalCommands')
mclass_scene_graph_command.add_constructor()

--------------------------------
-- Draw menus                ---
--------------------------------

-- Draw each menu for each plugin found
for _, ext_plugin in pairs(ext_plugins) do
   draw_menu(mclass, ext_plugin)
end

-- Make our new Commands visible from MeshGrob
scene_graph.register_grob_commands(gom.meta_types.OGF.MeshGrob, mclass)


local ext_plugin_list_file = project_root .. "/ext_addon_list.txt"

-- Load all external plugins from the ext_plugin_list.txt file
function load_ext_plugins_from_file()

   local plug_list = {}

   -- Check if there is a file that list external plugins
   -- If doesn't, nothing to load
   if FileSystem.is_file(ext_plugin_list_file) then 

      local plug_config = parameters_from_lines(io.lines(ext_plugin_list_file))
      

      for _, x in pairs(plug_config) do 

         local plug_ext = load_ext_plugin(x.name, x.program, x.interpreter)
         -- Draw menu
         draw_menu(mclass, plug_ext)
         -- Print
         print('External add-on ' .. x.name .. ' was loaded.')
         print(' - Program: ' .. x.program)
         if not string.empty(x.interpreter) then
            print(' - Interpreter: ' .. x.interpreter)
         end
         if not string.empty(x.mode) then 
            print(' - Mode: ' .. x.mode)
         end 

         table.insert(plug_list, x)
      end

   end 

   return plug_list
end

function list_ext_plugins()
   for _, plug_ext in pairs(ext_plugins) do 
      print(plug_ext.name .. "," .. plug_ext.call_cmd)
   end
end

function load_ext_plugin(name, program, interpreter)
   -- Clean up name, if needed
   local clean_program_name = string.clean(name)

   -- Call bin to get parameters
   local call_cmd = ""
   if interpreter then 
      call_cmd = call_cmd .. interpreter .. " "
   end
   call_cmd = call_cmd .. program

   local param_file = os.capture2(clean_program_name, call_cmd .. " --show-params")

   if not FileSystem.is_file(param_file) then 
      return nil
   end

   local lines = io.lines(param_file)
   
   local parameters = parameters_from_lines(lines)
   
   -- Create a new plugin object
   local plug_ext = {
      name = clean_program_name,
      call_cmd = call_cmd,
      program = program,
      interpreter = interpreter,
      parameters = parameters
   }
 
   -- Keep plugin object in a associative map
   ext_plugins[plug_ext.name] = plug_ext
   
   return plug_ext
end

function add_ext_plugin(program, interpreter, update)

   local program_name = FileSystem.base_name(program, false)
   local clean_program_name = string.clean(program_name)

   if program == nil or program == "" then 
      print("Program shouldn't be empty.")
   else
      -- Try to load plugin
      local plug_ext = load_ext_plugin(clean_program_name, program, interpreter)

      if not plug_ext then 
         print("Unable to load " .. program .. " as an add-on.")
         return 
      end

      -- Draw menu
      if not update then draw_menu(mclass, plug_ext) end
      -- Overwrite file
      overwrite_ext_plugin_list_file()

      print(clean_program_name .. " was added to external add-ons list. " .. ext_plugin_list_file)
   end

   return clean_program_name
end

function overwrite_ext_plugin_list_file()
   -- Hard overwrite plugin list file
   local f = io.open(ext_plugin_list_file, "w")
   for _, plug_ext in pairs(ext_plugins) do
      
      local line = "name="..plug_ext.name..";program="..plug_ext.program..";mode="..tostring(false)
      if not string.empty(plug_ext.interpreter) then 
         line = line .. ";interpreter=" .. plug_ext.interpreter
      end

      f:write(line.."\n")
   end
   f:close()
end

function clean_ext_plugin()
   print("Clean up external add-ons list file '" .. ext_plugin_list_file .. "'")
   FileSystem.delete_file(ext_plugin_list_file)
end

function remove_ext_plugin(name)
   ext_plugins[name] = nil
   overwrite_ext_plugin_list_file()
   print(name .. " was removed from external add-on list.")
end

function modify_plugin(name, args)
   -- Function is curryfied
   local modify_plugin_exec = function(args)
      add_ext_plugin(args.program, args.interpreter, true)
   end
   return modify_plugin_exec
end

-- Make our new commands visible from MeshGrob
scene_graph.register_grob_commands(gom.meta_types.OGF.SceneGraph, mclass_scene_graph_command)

-- Load external plugin reading the list file
local plug_list = load_ext_plugins_from_file()

-- Add menus to manage external plugins

-- Add plugin menu
m_add_plugin = mclass_scene_graph_command.add_slot("Add", function(args) 

   local name = add_ext_plugin(args.program, args.interpreter) 
   
   m_list_plugin_2_config = mclass_scene_graph_command.add_slot(name, modify_plugin(name))

   m_list_plugin_2_config.add_arg("program", gom.meta_types.OGF.FileName, args.program)
   m_list_plugin_2_config.create_arg_custom_attribute('program', 'help', 'Program to call (e.g: path to an executable / script)')
   
   m_list_plugin_2_config.add_arg("interpreter", gom.meta_types.OGF.FileName, args.interpreter)
   m_list_plugin_2_config.create_arg_custom_attribute('interpreter', 'help', 'Interpreter used to execute the program (optional, e.g: python3)')
   
   m_list_plugin_2_config.create_custom_attribute('menu','/Externals/Manage add ons/Modify')

end)

m_add_plugin.add_arg("program", gom.meta_types.OGF.FileName, "")
m_add_plugin.create_arg_custom_attribute('program', 'help', 'Program to call (e.g: path to an executable / script)')

m_add_plugin.add_arg("interpreter", gom.meta_types.OGF.FileName, "")
m_add_plugin.create_arg_custom_attribute('interpreter', 'help', 'Interpreter used to execute the program (optional, e.g: python3)')

m_add_plugin.create_custom_attribute('menu','/Externals/Manage add ons')

-- Modify plugins menus
for _, x in pairs(plug_list) do 
   m_list_plugin_2_config = mclass_scene_graph_command.add_slot(x.name, modify_plugin(x.name))

   -- m_list_plugin_2_config.add_arg("name", gom.meta_types.std.string, x.name)
   -- m_list_plugin_2_config.create_arg_custom_attribute('name','help','Choose a plugin name')

   m_list_plugin_2_config.add_arg("program", gom.meta_types.OGF.FileName, x.program)
   m_list_plugin_2_config.create_arg_custom_attribute('program', 'help', 'Program to call (e.g: path to an executable / script)')
   
   m_list_plugin_2_config.add_arg("interpreter", gom.meta_types.OGF.FileName, x.interpreter)
   m_list_plugin_2_config.create_arg_custom_attribute('interpreter', 'help', 'Interpreter used to execute the program (optional, e.g: python3)')
   
   m_list_plugin_2_config.create_custom_attribute('menu','/Externals/Manage add ons/Modify')
   
end 

-- Remove plugin menu
m_remove_plugin = mclass_scene_graph_command.add_slot("Remove", function(args) remove_ext_plugin(args.name) end)
m_remove_plugin.add_arg("name", gom.meta_types.std.string, "")
m_remove_plugin.create_arg_custom_attribute('name','help','Name of the add-on to remove')
m_remove_plugin.create_custom_attribute('menu','/Externals/Manage add ons')

-- Clean list plugin file menu
m_clean_plugin = mclass_scene_graph_command.add_slot("Clean_list", function(args) if args.sure == "yes" then clean_ext_plugin() end end)
m_clean_plugin.add_arg("sure", gom.meta_types.std.string, "no")
m_clean_plugin.create_arg_custom_attribute('sure','help','Type yes if you are sure')
m_clean_plugin.create_custom_attribute('menu','/Externals/Manage add ons')



