--
-- src/project/project.lua
-- Premake project object API
-- Copyright (c) 2011-2012 Jason Perkins and the Premake project
--

	premake5.project = { }
	local project = premake5.project


--
-- Returns an iterator function for the configuration objects contained by
-- the project. Each configuration corresponds to a build configuration/
-- platform pair (i.e. "Debug|x32") as specified in the solution.
--
-- @param prj
--    The project object to query.
-- @param field
--    An optional field name. If specified, only that field will be 
--    included in the resulting configuration object.
-- @param filename
--    An optional file name. If specified, only configuration blocks 
--    with a keyword matching the filename will be considered.
-- @return
--    An iterator function returning configuration objects.
--

	function project.eachconfig(prj, field, filename)
		local buildconfigs = prj.solution.configurations or {}
		local platforms = prj.solution.platforms or {}

		local i = 0
		local j = #platforms

		return function ()
			j = j + 1
			if j > #platforms then
				i = i + 1
				j = 1
			end

			if i > #buildconfigs then
				return nil
			end

			return project.getconfig(prj, buildconfigs[i], platforms[j], field, filenamae)
		end
	end


--
-- Return an iterator for the list of source code files contained by a project.
-- Note that this only returns the files specified at the project level; I'm
-- not supported configuration level file lists, yet.
--
-- @param prj
--    The project to query.
-- @return
--    A source code file iterator, which returns file configuration objects.
--    These file configurations contain:
--
--      fullpath  - the relative path from the project to the file
--      vpath     - the file's virtual path, if specified, or fullpath if not
--

	function project.eachfile(prj)
		cfg = project.getconfig(prj, nil, nil, "files")
		local files = cfg.files
		local i = 0
		return function()
			i = i + 1
			if i <= #files then
				local fcfg = {}
				fcfg.fullpath = project.getrelative(prj, files[i])

				local vpath = project.getvpath(prj, files[i])
				if vpath ~= files[i] then
					fcfg.vpath = vpath
				else
					fcfg.vpath = fcfg.fullpath
				end

				return fcfg
			end
		end
	end


-- 
-- Locate a project by name; case insensitive.
--
-- @param name
--    The name of the project for which to search.
-- @return
--    The corresponding project, or nil if no matching project could be found.
--

	function project.findproject(name)
		for sln in premake.solution.each() do
			for _, prj in ipairs(sln.projects) do
				if (prj.name == name) then
					return  prj
				end
			end
		end
	end


--
-- Retrieve the project's configuration information for a particular build 
-- configuration/platform pair.
--
-- @param prj
--    The project object to query.
-- @param buildcfg
--    The name of the build configuration on which to filter.
-- @param platform
--    Optional; the name of the platform on which to filter.
-- @param field
--    An optional field name. If specified, only that field will be 
--    included in the resulting configuration object.
-- @param filename
--    An optional file name. If specified, only configuration blocks 
--    with a keyword matching the filename will be considered.
-- @return
--    A configuration object.
--

	function project.getconfig(prj, buildcfg, platform, field, filename)
		local system
		local architecture

		-- For backward compatibility with the old platforms API, use platform
		-- as the default system or architecture if it would be a valid value.
		if platform then
			system = premake.checkvalue(platform, premake.fields.system.allowed)
			architecture = premake.checkvalue(platform, premake.fields.architecture.allowed)
		end

		-- Figure out the target operating environment for this configuration
		local cfg = premake5.oven.bake(prj, { buildcfg, platform, _ACTION }, "system")
		system = cfg.system or system or premake.action.current().os or os.get()

		cfg = premake5.oven.bake(prj, { buildcfg, platform, _ACTION, system }, field)
		cfg.project = prj
		cfg.buildcfg = buildcfg
		cfg.platform = platform
		cfg.system = system
		cfg.architecture = cfg.architecture or architecture
		return cfg
	end


--
-- Returns a list of sibling projects on which the specified project depends. 
-- This is used to list dependencies within a solution or workspace. Must 
-- consider all configurations because Visual Studio does not support per-config
-- project dependencies.
--
-- @param prj
--    The project to query.
-- @return
--    A list of dependent projects, as an array of project objects.
--

	function project.getdependencies(prj)
		local result = {}

		for cfg in project.eachconfig(prj, nil, "links") do
			for _, link in ipairs(cfg.links) do
				local dep = project.findproject(link)
				if dep and not table.contains(result, dep) then
					table.insert(result, dep)
				end
			end
		end

		return result
	end


--
-- Retrieve the project's file system location.
--
-- @param prj
--    The project object to query.
-- @param relativeto
--    Optional; if supplied, the project location will be made relative
--    to this path.
-- @return
--    The path to the project's file system location.
--

	function project.getlocation(prj, relativeto)
		local location = prj.location or prj.solution.location or prj.basedir
		if relativeto then
			location = path.getrelative(relativeto, location)
		end
		return location
	end


--
-- Return the relative path from the project to the specified file.
--
-- @param prj
--    The project object to query.
-- @param filename
--    The file path, or an array of file paths, to convert.
-- @return
--    The relative path, or array of paths, from the project to the file.
--

	function project.getrelative(prj, filename)
		if type(filename) == "table" then
			local result = {}
			for i, name in ipairs(filename) do
				result[i] = project.getrelative(prj, name)
			end
			return result
		else
			if filename then
				return path.getrelative(project.getlocation(prj), filename)
			end
		end
	end


--
-- Create a tree from a project's list of source files.
--
-- @param prj
--    The project to query.
-- @return
--    A tree object containing the source file hierarchy. Each leaf
--    node contains a file configuration object at node.cfg; see
--    project.eachfile() for a description of this object.
--

	function project.getsourcetree(prj)
		local tr = premake.tree.new(prj.name)

		for fcfg in project.eachfile(prj) do
			local node = premake.tree.add(tr, fcfg.vpath)
			node.cfg = fcfg
		end

		premake.tree.sort(tr)
		return tr
	end


--
-- Given a source file path, return a corresponding virtual path based on
-- the vpath entries in the project. If no matching vpath entry is found,
-- the original path is returned.
--

	function project.getvpath(prj, filename)
		-- if there is no match, return the input filename
		local vpath = filename
		
		-- file are always specified relative to the script, so the vpath
		-- patterns do too. Get the script relative path
		local relpath = path.getrelative(prj.basedir, filename)
		
		for replacement,patterns in pairs(prj.vpaths or {}) do
			for _,pattern in ipairs(patterns) do
				-- does the filename match this vpath pattern?
				local i = relpath:find(path.wildcards(pattern))
				if i == 1 then				
					-- yes; trim the leading portion of the path
					i = pattern:find("*", 1, true) or (pattern:len() + 1)
					local leaf = relpath:sub(i)
					if leaf:startswith("/") then
						leaf = leaf:sub(2)
					end
					
					-- check for (and remove) stars in the replacement pattern.
					-- If there are none, then trim all path info from the leaf
					-- and use just the filename in the replacement (stars should
					-- really only appear at the end; I'm cheating here)
					local stem = ""
					if replacement:len() > 0 then
						stem, stars = replacement:gsub("%*", "")
						if stars == 0 then
							leaf = path.getname(leaf)
						end
					end
					
					vpath = path.join(stem, leaf)
				end
			end
		end
				
		-- remove any dot ("./", "../") patterns from the start of the path
		local changed
		repeat
			changed = true
			if vpath:startswith("./") then
				vpath = vpath:sub(3)
			elseif vpath:startswith("../") then
				vpath = vpath:sub(4)
			else
				changed = false
			end
		until not changed
		
		return vpath
	end