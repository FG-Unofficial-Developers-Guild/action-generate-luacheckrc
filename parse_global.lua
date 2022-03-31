local datapath = './.fg/'

-- Dependencies
local lfs = require('lfs') -- luafilesystem
local parseXmlFile = require('xmlparser').parseFile

-- Datatypes
local packages = {
	['rulesets'] = {
		['path'] = datapath .. 'rulesets/',
		['baseFile'] = 'base.xml',
		['definitions'] = {},
		['packageList'] = {},
	},
	['extensions'] = {
		['path'] = datapath .. 'extensions/',
		['baseFile'] = 'extension.xml',
		['definitions'] = {},
		['packageList'] = {},
	},
}

--
-- General Functions (called from multiple places)
--

-- Opens a file and returns the contents as a string
local function loadFile(file)
	local fhandle = io.open(file, 'r')
	local string

	if fhandle then
		string = fhandle:read('*a')
		fhandle:close()
	end

	return string
end

-- Calls luac and find included SETGLOBAL commands
-- Adds them to supplied table 'globals'
local function findGlobals(globals, directory, file)

	local function executeCapture(command)
		local file = assert(io.popen(command, 'r'))
		local str = assert(file:read('*a'))
		str = string.gsub(str, '^%s+', '')
		str = string.gsub(str, '%s+$', '')

		file:close()
		return str
	end

	local concatPath = table.concat(directory) .. '/' .. file

	if lfs.touch(concatPath) then
		executeCapture('perl -e \'s/\\xef\\xbb\\xbf//;\' -pi ' .. concatPath)
		local content = executeCapture(string.format('%s -l -p ' .. concatPath, 'luac'))

		for line in content:gmatch('[^\r\n]+') do
			if line:match('SETGLOBAL%s+') and not line:match('%s+;%s+(_)%s*') then
				local globalName = line:match('\t; (.+)%s*')
				globals[globalName] = true
			end
		end

		return true
	end
end

-- Checks next level of XML data table for  elements matching a supplied tag name
-- If found, returns the XML data table of that child element
local function findXmlElement(root, searchStrings)
	if root and root.children then
		for _, xmlElement in ipairs(root.children) do
			for _, searchString in ipairs(searchStrings) do if xmlElement.tag == searchString then return xmlElement end end
		end
	end
end

-- Calls findGlobals for lua functions in XML-formatted string
-- Creates temp file, writes string to it, calls findGlobals, deletes temp file
local function getFnsFromLuaInXml(fns, string)

	-- Converts XML escaped strings into the base characters.
	-- &gt; to >, for example. This allows the lua parser to handle it correctly.
	local function convertXmlEscapes(string)
		string = string:gsub('&amp;', '&')
		string = string:gsub('&quot;', '"')
		string = string:gsub('&apos;', '\'')
		string = string:gsub('&lt;', '<')
		string = string:gsub('&gt;', '>')
		return string
	end

	local tempFilePath = datapath .. 'xmlscript.tmp'
	tempFile = assert(io.open(tempFilePath, 'w'), 'Error opening file ' .. tempFilePath)

	local script = convertXmlEscapes(string)

	tempFile:write(script)
	tempFile:close()

	findGlobals(fns, { datapath }, 'xmlscript.tmp')

	os.remove(tempFilePath)
end

-- Searches other rulesets for provided lua file name.
-- If found, adds to provided table. Package path is prepended to file path.
local function findAltScriptLocation(templateFunctions, packagePath, filePath)
	for _, packageName in ipairs(packages.rulesets.packageList) do
		if packageName ~= packagePath[4] then
			local altPackagePath = packagePath
			altPackagePath[4] = packageName
			findGlobals(templateFunctions, altPackagePath, filePath)
		end
	end
end

--
-- Main Functions (called from Main Chunk)
--

-- 
local function writeDefinitionsToFile(defintitions, package)

	-- 
	local function gatherChildFunctions(output)

		-- 
		local function writeSubdefintions(fns)
			local output = ''

			for fn, _ in pairs(fns) do
				output = output .. '\t\t' .. fn .. ' = {\n\t\t\t\tread_only = false,\n\t\t\t\tother_fields = false,\n\t\t\t},\n\t'
			end

			return output
		end

		for parent, fns in pairs(defintitions[package]) do
			local global = (parent .. ' = {\n\t\tread_only = false,\n\t\tfields = {\n\t' .. writeSubdefintions(fns) ..
							               '\t},\n\t},')
			table.insert(output, global)
		end
		table.sort(output)
	end

	local output = {}
	gatherChildFunctions(output)

	local dir = datapath .. 'globals/'
	lfs.mkdir(dir)
	local filePath = dir .. package .. '.luacheckrc_std'
	local destFile = assert(io.open(filePath, 'w'), 'Error opening file ' .. filePath)
	destFile:write('globals = {\n')
	for _, var in ipairs(output) do destFile:write('\t' .. var .. '\n') end

	destFile:write('\n},\n')
	destFile:close()
end

-- Search through a supplied fantasygrounds xml file to find other defined xml files.
local function findNamedLuaScripts(definitions, baseXmlFile, packagePath)

	local function callFindGlobals(element)
		if element.tag == 'script' then
			local fns = {}
			findGlobals(fns, packagePath, element.attrs.file)
			definitions[element.attrs.name] = fns
			
			return true
		end
	end

	local root = findXmlElement(parseXmlFile(baseXmlFile), { 'root' })
	if root then
		for _, element in ipairs(root.children) do
			if not callFindGlobals(element) then
				for _, child in ipairs(element.children) do
					callFindGlobals(child)
				end
			end
		end
	end
end

-- Searches a provided table of XML files for script definitions.
-- If element is windowclass, call getWindowclassScript.
-- If element is not a template, call xmlScriptSearch
local function findInterfaceScripts(packageDefinitions, templates, xmlFiles, packagePath, shortPackageName)

	-- Checks the first level of the provided xml data table for an element with the
	-- tag 'script'. If found, it calls getScriptFromXml to map its globals and then calls
	-- insertTableKeys to add any inherited template functions.
	local function xmlScriptSearch(sheetdata)

		-- Copies keys from sourceTable to destinationTable with boolean value true
		local function insertTableKeys(sourceTable, destinationTable)
			for fn, _ in pairs(destinationTable) do sourceTable[fn] = true end
		end

		-- When supplied with a lua-xmlparser table for the <script> element,
		-- this function adds any functions from it into a supplied table.
		local function getScriptFromXml(parent, script)
			local fns = {}
			if script.attrs.file then
				if not findGlobals(fns, packagePath, script.attrs.file) then
					findAltScriptLocation(fns, packagePath, script.attrs.file)
				end
			elseif script.children[1].text then
				getFnsFromLuaInXml(fns, script.children[1].text)
			end
			packageDefinitions[parent.attrs.name] = fns
		end

		print(string.format('Integrating templates into interface object definitions in %s.', shortPackageName))
		for _, element in ipairs(sheetdata.children) do
			local script = findXmlElement(element, { 'script' })
			if script then
				getScriptFromXml(element, script)
				if templates[element.tag] and packageDefinitions[element.attrs.name] then
					insertTableKeys(packageDefinitions[element.attrs.name], templates[element.tag])
				end
			end
		end
	end

	-- Searches provided element for lua script definition and adds to provided table
	-- If file search within package is unsuccessful, it calls findAltScriptLocation to search all rulesets
	-- Finally, it adds the discovered functions to PackageDefintions under the key of the UI object name.
	local function getWindowclassScript(element)
		local script = findXmlElement(element, { 'script' })
		if script then
			local fns = {}
			if script.attrs.file then
				if not findGlobals(fns, packagePath, script.attrs.file) then
					findAltScriptLocation(fns, packagePath, script.attrs.file)
				end
			elseif script.children[1] and script.children[1].text then
				getFnsFromLuaInXml(fns, script.children[1].text)
			end
			packageDefinitions[element.attrs.name] = fns
		end
	end

	for _, xmlPath in pairs(xmlFiles) do -- iterate through provided files
		local root = findXmlElement(parseXmlFile(xmlPath), { 'root' }) -- use first root element
		for _, element in ipairs(root.children) do
			if element.tag == 'windowclass' then -- iterate through each windowclass
				getWindowclassScript(element)
				local sheetdata = findXmlElement(element, { 'sheetdata' }) -- use first sheetdata element
				if element.attrs.name == 'npc_spells' and sheetdata then xmlScriptSearch(sheetdata) end
			end
		end
	end
end

local function matchRelationshipScripts(templates)
	for name, data in pairs(templates) do
		local inheritedTemplate = templates[data['inherit']]
		if inheritedTemplate and inheritedTemplate['functions'] then
			for functionName, _ in pairs(inheritedTemplate['functions']) do templates[name]['functions'][functionName] = true end
		end
	end
end

-- Finds template definitions in supplied table of XML files.
-- If found, calls findTemplateScript to extract a list of globals.
local function findTemplateRelationships(templates, packagePath, xmlFiles)

	-- When supplied with a lua-xmlparser table for the <script> element of a template,
	-- this function adds any functions from it into a supplied table.
	local function findTemplateScript(templates, packagePath, parent, element)
		local script = findXmlElement(parent, { 'script' })
		if script then
			local templateFunctions = {}
			if script.attrs.file then
				if not findGlobals(templateFunctions, packagePath, script.attrs.file) then
					findAltScriptLocation(templateFunctions, packagePath, script.attrs.file)
				end
			elseif script.children[1].text then
				getFnsFromLuaInXml(templateFunctions, script.children[1].text)
			end
			templates[element.attrs.name] = { ['inherit'] = parent.tag, ['functions'] = templateFunctions }
		end
	end

	for _, xmlPath in pairs(xmlFiles) do
		local root = findXmlElement(parseXmlFile(xmlPath), { 'root' })
		for _, element in ipairs(root.children) do
			if element.tag == 'template' then
				for _, template in ipairs(element.children) do findTemplateScript(templates, packagePath, template, element) end
			end
		end
	end
end

-- Search through a supplied fantasygrounds xml file to find other defined xml files.
local function findXmls(xmlFiles, xmlDefinitionsPath, packagePath)
	local data = loadFile(xmlDefinitionsPath)

	for line in data:gmatch('[^\r\n]+') do
		if line:match('<includefile.+/>') and not line:match('<!--.*<includefile.+/>.*-->') then
			local sansRuleset = line:gsub('ruleset=".-"%s+', '')
			local filePath = sansRuleset:match('<includefile%s+source="(.+)"%s*/>') or ''
			local fileName = filePath:match('.+/(.-).xml') or filePath:match('(.-).xml')
			if fileName then xmlFiles[fileName] = table.concat(packagePath) .. '/' .. filePath end
		end
	end
end

-- Determine best package name
-- Returns as a lowercase string
local function getPackageName(baseXmlFile, packageName)

	-- Reads supplied XML file to find name and author definitions.
	-- Returns a simplified string to identify the extension
	local function getSimpleName()

		-- Trims package name to prevent issues with luacheckrc
		local function simplifyText(text)
			text = text:gsub('.+:', '') -- remove prefix
			text = text:gsub('%(.+%)', '') -- remove parenthetical
			text = text:gsub('%W', '') -- remove non alphanumeric
			return text
		end

		local altName = { '' }
		local xmlProperties = findXmlElement(findXmlElement(parseXmlFile(baseXmlFile), { 'root' }), { 'properties' })
		if xmlProperties then
			for _, element in ipairs(xmlProperties.children) do
				if element.tag == 'author' then
					table.insert(altName, 2, simplifyText(element.children[1]['text']))
				elseif element.tag == 'name' then
					table.insert(altName, 1, simplifyText(element.children[1]['text']))
				end
			end
		end

		return table.concat(altName)
	end
	local shortPackageName = getSimpleName()

	if shortPackageName == '' then shortPackageName = packageName end

	-- prepend 'def' if 1st character isn't a-z
	if string.sub(shortPackageName, 1, 1):match('%A') then shortPackageName = 'def' .. shortPackageName end

	return shortPackageName:lower()
end

-- Searches for file by name in supplied directory
-- Returns string in format of 'original_path/file_result'
local function findBaseXml(path, searchName)
	local concatPath = table.concat(path)
	for file in lfs.dir(concatPath) do
		local filePath = concatPath .. '/' .. file
		local fileType = lfs.attributes(filePath, 'mode')
		if fileType == 'file' and string.find(file, searchName) then return filePath end
	end
end

-- Searches for directories in supplied path
-- Adds them to supplied table 'list' and sorts the table
local function findAllPackages(list, path)
	lfs.mkdir(path) -- if not found, create path to avoid errors

	for file in lfs.dir(path) do
		if lfs.attributes(path .. '/' .. file, 'mode') == 'directory' then
			if file ~= '.' and file ~= '..' then table.insert(list, file) end
		end
	end

	table.sort(list)
end

--
-- MAIN CHUNK
--

local templates = {}
-- Iterate through package types defined in packageTypes
for packageTypeName, packageTypeData in pairs(packages) do
	print(string.format('Searching for %s', packageTypeName))
	findAllPackages(packageTypeData.packageList, packageTypeData['path'])

	for _, packageName in ipairs(packageTypeData.packageList) do
		print(string.format('Found %s. Getting details.', packageName))
		local packagePath = { datapath, packageTypeName, '/', packageName }
		local baseXmlFile = findBaseXml(packagePath, packageTypeData['baseFile'])
		local shortPackageName = getPackageName(baseXmlFile, packageName)

		print(string.format('Creating definition entry %s.', shortPackageName))
		packageTypeData['definitions'][shortPackageName] = {}

		print(string.format('Finding interface XML files in %s.', shortPackageName))
		local interfaceXmlFiles = {}
		findXmls(interfaceXmlFiles, baseXmlFile, packagePath)

		print(string.format('Determining templates for %s.', shortPackageName))
		findTemplateRelationships(templates, packagePath, interfaceXmlFiles)
		matchRelationshipScripts(templates)

		print(string.format('Finding scripts attached to interface objects for %s.', shortPackageName))
		findInterfaceScripts(packageTypeData['definitions'][shortPackageName], templates, interfaceXmlFiles, packagePath, shortPackageName)

		print(string.format('Finding named scripts in %s.', shortPackageName))
		findNamedLuaScripts(packageTypeData['definitions'][shortPackageName], baseXmlFile, packagePath)

		print(string.format('Writing definitions for %s.\n', shortPackageName))
		writeDefinitionsToFile(packageTypeData['definitions'], shortPackageName)
	end
end
