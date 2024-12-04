local cpm_root_path = ".cpm"
local sources_path = cpm_root_path.."/sources.json"
local packages_path = cpm_root_path.."/packages.json"
local installed_packages_path = cpm_root_path.."/installed_packages"

---------------- UTILS ----------------

local function read_file(path)
  local file = fs.open(path, "r")
  local content = file.readAll()
  file.close()
  return content
end


local function write_file(path, content)
  local file = fs.open(path, "w")
  file.write(content)
  file.close()
end


local function is_url(url)
  return string.match(url, "^https?://") ~= nil
end


local function is_local_package(package_path)
  return fs.exists(package_path)  -- TODO: Might need something more sofisticated
end


local function remove_non_matching_files(path, pattern)
  for _, file in pairs(fs.list(path)) do
      if not string.match(file, pattern) then
          io.write("Removing "..path..file.."... ")
          fs.delete(path..file)
          io.write("done!\n")
      end
  end
end


local function unpack_folder(folder_path)
  for _, file in pairs(fs.list(folder_path)) do
    io.write("Unpacking "..folder_path..file.."... ")
    fs.move(folder_path..file, folder_path.."../"..file)
    io.write("done!\n")
  end
end

----------------------------------------



---------------- SOURCES ----------------

local function get_sources()
  if not fs.exists(sources_path) then
    return {}
  end

  return json.decode(read_file(sources_path))
end


local function write_sources(sources)
  write_file(sources_path, json.encode(sources))
end


local function has_source(source)
  local sources = get_sources()

  for _, existing_source in ipairs(sources) do
    if existing_source == source then
      return true
    end
  end

  return false
end


function remove_source(path)
  local sources = get_sources()

  for i, source in ipairs(sources) do
    if source == path then
      table.remove(sources.local_sources, i)
      break
    end
  end

  write_sources(sources)
end


function add_source(source_path)
  if has_source(source_path) then
    return
  end

  local sources = get_sources()
  table.insert(sources, source_path)
  write_sources(sources)
end


local function get_packages_from_source(source)
  if is_url(source) then
    return json.decode(http.get(source).readAll())
  else
    return json.decode(read_file(source))
  end
end


local function get_package_url_from_source(source, package_name)
  local packages = get_packages_from_source(source)

  for _, package in ipairs(packages) do
    if package.name == package_name then
      return package.url
    end
  end

  return nil
end

----------------------------------------



---------------- APIS ----------------

local function load_api(api_path)
  io.write("Loading "..api_path.."... ")
  os.loadAPI(api_path)
  io.write("done!\n")
end

local function load_apis(apis_path)
  for _, api in ipairs(fs.list(apis_path)) do
    load_api(apis_path..api)
  end
end

--------------------------------------



---------------- PROGRAMS ----------------

local function get_program_alias(program_path)
  if fs.exists(program_path.."/.alias") then
      return read_file(program_path.."/.alias")
  else
      return fs.getName(program_path)
  end
end

local function load_program(program_path)
  local program_file = program_path.."/main.lua"
  assert(fs.exists(program_file), "Invalid program structure! Missing: "..program_file)

  local program_name = get_program_alias(program_path)

  io.write("Loading "..program_path.." ("..program_name..")...")
  shell.setAlias(program_name, program_file)
  io.write("done!\n")
end

local function load_programs(programs_path)
  for _, program in pairs(fs.list(programs_path)) do
      load_program(programs_path..program)
  end
end

-------------------------------------------



---------------- INSTALL ----------------

function minify(files_path)
  print("Minify not implemented yet!")  -- TODO: Implement minify
end


function load(package_path)
  print("Loading package "..package_path.."...")

  assert(fs.exists(package_path), "Package not found!")

  if fs.exists(package_path.."/apis") then
    print("Loading APIs...")
    load_apis(package_path.."/apis")
  end

  if fs.exists(package_path.."/programs") then
    print("Loading programs...")
    load_programs(package_path.."/programs")
  end

  print("Package loaded!")
end


function build(package_path)
  print("Building package "..package_path.."...")

  local src_path = package_path .. "/src"
  assert(fs.exists(src_path), "Invalid package structure! Missing: "..src_path)

  print("Removing non-source files...")
  remove_non_matching_files(package_path, "^src$")
  print("Minifying source files...")
  minify(src_path)
  print("Unpacking source files...")
  unpack_folder(src_path)

  print("Build complete!")
end


function get_installed_packages()
  if not fs.exists(installed_packages_path) then
    return {}
  end

  return json.decode(read_file(installed_packages_path))
end


local function write_installed_packages(installed_packages)
  write_file(installed_packages_path, json.encode(installed_packages))
end


local function has_installed_package(package_name)
  local installed_packages = get_installed_packages()
  return installed_packages[package_name] ~= nil
end


local function add_install_path(package_name, install_path)
  local installed_packages = get_installed_packages()
  installed_packages[package_name] = install_path
  write_installed_packages(installed_packages)
end


local function install_local_package(package_name, package_path, local_path)
  local install_path = local_path.."/"..package_name
  fs.move(package_path, install_path)

  print("Installing package "..install_path.."...")

  add_install_path(package_name, install_path)
  build(install_path)
  load(install_path)

  print("Installation complete!")
end


local function install_from_url(package_name, package_url, local_path)
  github.download(package_url, local_path)
  install_local_package(package_name, local_path.."/"..package_name, local_path)
end


local function install_from_sources(package_name, local_path)
  local sources = get_sources()

  for _, source in ipairs(sources) do
    local package_url = get_package_url_from_source(source, package_name)

    if package_url then
      install_from_url(package_name, package_url, local_path)
      return
    end
  end

  error("Package "..package_name.." found in sources!")
end


local function uninstall_package(package_name)
  local installed_packages = get_installed_packages()
  local install_path = installed_packages[package_name]

  fs.delete(install_path)
  installed_packages[package_name] = nil
  write_installed_packages(installed_packages)
end


function uninstall(package_name)
  if not has_installed_package(package_name) then
    error("Package "..package_name.." not installed!")
  end

  print("Uninstalling package "..package_name.."...")

  uninstall_package(package_name)

  print("Uninstallation complete!")
end


function install(package_path, local_path)
  local_path = local_path or installed_packages_path

  if is_url(package_path) then
    install_from_url(package_path, local_path)
  elseif is_local_package(package_path) then
    install_local_package(fs.getName(package_path), package_path, local_path)
  else
    install_from_sources(package_path, local_path)
  end
end

----------------------------------------