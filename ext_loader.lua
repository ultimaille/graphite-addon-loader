-- Lua (Keep this comment, this is an indication for editor's 'run' command)

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

function to_table(it)
   local t={}
   for x in it do 
      table.insert(t, x)
   end 
   return t
end

function string.clean(str)
   return str:gsub("%-", "_"):gsub("% ", "_"):gsub("%/", "_"):gsub("%.", "_")
end

function string.empty(str)
   return str == nil or str == ""
end

function table_count(t)
   local count = 0
   for _ in pairs(t) do 
      count = count + 1
   end
   return count
end

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

function map_param(param, val)
   
   if val == nil then 
      val = ""
   end

   -- should apply a target format ?
   if param.type == 'input' and scene_graph.current() ~= nil then
      return param.name.."="..scene_graph.current().filename
   else
      return param.name.."="..tostring(val)
   end
end 

-- format parameters into a string key1=value1 key2=value2 ...
function format_args(params, args)
   
   local str = ""
   for _, param in pairs(params) do 
      local clean_param_name = string.clean(param.name)
      str = str.." "..map_param(param, args[clean_param_name])
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

function exec_bin(args)
   print('args='..tostring(args))
   print('self='..tostring(args.self))
   
   -- Get plugin to execute
   local plug_name = args['method']
   ext_plugin = ext_plugins[plug_name]
   print("Plugin: "..ext_plugin.name)

   -- Create a sandbox
   -- Get document root
   -- TODO replace by tmp dir
   local project_root = FileSystem.documents_directory()
   local sandbox_dir = project_root .. "/" .. "sandbox_" .. os.clock()
   FileSystem.create_directory(sandbox_dir)
   print("Sandbox dir created: "..sandbox_dir)
   -- exec bin in sandbox
   
   local wd = FileSystem.get_current_working_directory()
   FileSystem.set_current_working_directory(sandbox_dir)

   local cmd = ext_plugin.call_cmd .. " " .. format_args(ext_plugin.parameters, args)
   
   print('call: ' .. cmd)
   -- Run command
   os.execute(cmd)

   FileSystem.set_current_working_directory(wd)

   load_outputs(sandbox_dir)

   cleanup_sandbox(sandbox_dir)
end

-- map table of types to gom types
t_map = { 
   double = gom.meta_types.double,
   float = gom.meta_types.float,
   int = gom.meta_types.int, 
   bool = gom.meta_types.bool, 
   string = gom.meta_types.std.string, 
   file = gom.meta_types.OGF.FileName
}

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

      if t_map[param.type] ~= nil then
         if param.value ~= "undefined" then
            m.add_arg(clean_param_name, t_map[param.type], param.value)
         else
            m.add_arg(clean_param_name, t_map[param.type])
         end 
      else 
         print(
            "Error: type '"
            ..param.type
            .."' for field '"
            ..param.name
            .."' isn't managed by 'external_processes.lua'. Maybe type is missing in t_map variable."
         )
      end 
   end 

   m.create_custom_attribute('menu','/Externals')

   return m
   
end


-- -- Create a new enum type
-- menum = gom.meta_types.OGF.MetaEnum.create('Titi')
-- -- Declare enum values
-- menum.add_values({tutu=0,tata=1,toto=2})
-- -- Make new enum visible from GOM type system
-- gom.bind_meta_type(menum)

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

-- Our new class is a subclass of OGF::SceneGraphCommands
yop = gom.meta_types.OGF.SceneGraphCommands
yopi    = yop.create_subclass('OGF::SceneGraphShapesCommands')
yopi.add_constructor()

msquare = yopi.add_slot('square', nil)
msquare.add_arg('name',gom.meta_types.OGF.NewMeshGrobName,'shape')
msquare.create_arg_custom_attribute('name','help','name of the object to create')
msquare.add_arg('size',gom.meta_types.double,1.0)
msquare.create_arg_custom_attribute('size','help','edge length of the square')
msquare.add_arg('center',gom.meta_types.bool,false)
msquare.create_arg_custom_attribute('center','help','if set, dimensions go from -size/2 to size/2 instead of [0,size]')
msquare.create_custom_attribute('menu','/Shapes')
msquare.create_custom_attribute('help','guess what ? it creates a square (what an informative help bubble !!)')

--------------------------------
-- Get plugin paths          ---
--------------------------------
    
-- plugins paths
local project_root = gom.get_environment_value("PROJECT_ROOT")
local bin_path = project_root.."/plugins/external/binaries/"
local scripts_path = project_root.."/plugins/external/scripts/"

--------------------------------
-- Draw menus                ---
--------------------------------

-- Draw each menu for each plugin found
for _, ext_plugin in pairs(ext_plugins) do
   draw_menu(mclass, ext_plugin)
end

-- Make our new Commands visible from MeshGrob
scene_graph.register_grob_commands(gom.meta_types.OGF.MeshGrob, mclass)


local ext_plugin_list_file = project_root .. "/ext_plugin_list.txt"

-- Load all external plugins from the ext_plugin_list.txt file
function load_ext_plugins_from_file()

   local plug_list = {}

   -- Check if there is a file that list external plugins
   -- If doesn't, nothing to load
   if FileSystem.is_file(ext_plugin_list_file) then 

      local plug_config = parameters_from_lines(io.lines(project_root .. "/ext_plugin_list.txt"))
      

      for _, x in pairs(plug_config) do 

         load_ext_plugin(x.name, x.program, x.interpreter)

         -- Print
         print('External plugin ' .. x.name .. ' was loaded.')
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

   local str_params = os.capture(call_cmd .. " --show-params", true)
   -- Split lines and map string parameters to object parameters
   lines = string.split(str_params, "\r\n")
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
   -- Draw menu
   draw_menu(mclass, plug_ext)
end

function add_ext_plugin(name, program, interpreter)

   -- if ext_plugins[name] ~= nil then
   --    print("Plugin " .. name .. " already exist in external plugin list, please choose another name.")
   if program == nil or program == "" then 
      print("Program shouldn't be empty.")
   else
      -- Load plugin
      load_ext_plugin(name, program, interpreter)
      -- Overwrite file
      overwrite_ext_plugin_list_file()

      print(name .. " was added to external plugin list. " .. ext_plugin_list_file)
   end
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
   print("Clean up external plugins list file '" .. ext_plugin_list_file .. "'")
   FileSystem.delete_file(ext_plugin_list_file)
end

function remove_ext_plugin(name)
   ext_plugins[name] = nil
   overwrite_ext_plugin_list_file()
   print(name .. " was removed from external plugin list.")
end

function modify_plugin(args)
   -- TODO checkings
   add_ext_plugin(args.name, args.program, args.interpreter)
end

-- Make our new commands visible from MeshGrob
scene_graph.register_grob_commands(gom.meta_types.OGF.SceneGraph, mclass_scene_graph_command)

-- Load external plugin reading the list file
local plug_list = load_ext_plugins_from_file()

-- Add menus to manage external plugins

-- Add plugin menu
m_add_plugin = mclass_scene_graph_command.add_slot("Add", function(args) 

   add_ext_plugin(args.name, args.program, args.interpreter) 
   
   m_list_plugin_2_config = mclass_scene_graph_command.add_slot(args.name, modify_plugin)

   m_list_plugin_2_config.add_arg("program", gom.meta_types.OGF.FileName, args.program)
   m_list_plugin_2_config.create_arg_custom_attribute('program', 'help', 'Program to call (e.g: path to an executable / script)')
   
   m_list_plugin_2_config.add_arg("interpreter", gom.meta_types.OGF.FileName, args.interpreter)
   m_list_plugin_2_config.create_arg_custom_attribute('interpreter', 'help', 'Interpreter used to execute the program (optional, e.g: python3)')
   
   m_list_plugin_2_config.create_custom_attribute('menu','/Externals/Manage plugins/Modify')

end)

m_add_plugin.add_arg("name", gom.meta_types.std.string, "")
m_add_plugin.create_arg_custom_attribute('name','help','Choose a plugin name')

m_add_plugin.add_arg("program", gom.meta_types.OGF.FileName, "")
m_add_plugin.create_arg_custom_attribute('program', 'help', 'Program to call (e.g: path to an executable / script)')

m_add_plugin.add_arg("interpreter", gom.meta_types.OGF.FileName, "")
m_add_plugin.create_arg_custom_attribute('interpreter', 'help', 'Interpreter used to execute the program (optional, e.g: python3)')

m_add_plugin.create_custom_attribute('menu','/Externals/Manage plugins')

-- Modify plugins menus
for _, x in pairs(plug_list) do 
   m_list_plugin_2_config = mclass_scene_graph_command.add_slot(x.name, modify_plugin)

   -- m_list_plugin_2_config.add_arg("name", gom.meta_types.std.string, x.name)
   -- m_list_plugin_2_config.create_arg_custom_attribute('name','help','Choose a plugin name')

   m_list_plugin_2_config.add_arg("program", gom.meta_types.OGF.FileName, x.program)
   m_list_plugin_2_config.create_arg_custom_attribute('program', 'help', 'Program to call (e.g: path to an executable / script)')
   
   m_list_plugin_2_config.add_arg("interpreter", gom.meta_types.OGF.FileName, x.interpreter)
   m_list_plugin_2_config.create_arg_custom_attribute('interpreter', 'help', 'Interpreter used to execute the program (optional, e.g: python3)')
   
   m_list_plugin_2_config.create_custom_attribute('menu','/Externals/Manage plugins/Modify')
   
end 

-- Remove plugin menu
m_remove_plugin = mclass_scene_graph_command.add_slot("Remove", function(args) remove_ext_plugin(args.name) end)
m_remove_plugin.add_arg("name", gom.meta_types.std.string, "")
m_remove_plugin.create_arg_custom_attribute('name','help','Name of the plugin to remove')
m_remove_plugin.create_custom_attribute('menu','/Externals/Manage plugins')

-- Clean list plugin file menu
m_clean_plugin = mclass_scene_graph_command.add_slot("Clean_list", function(args) if args.sure == "yes" then clean_ext_plugin() end end)
m_clean_plugin.add_arg("sure", gom.meta_types.std.string, "no")
m_clean_plugin.create_arg_custom_attribute('sure','help','Type yes if you are sure')
m_clean_plugin.create_custom_attribute('menu','/Externals/Manage plugins')

