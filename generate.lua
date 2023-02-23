-- Equivalent of the pairs() function on tables. Allows to iterate in order
function orderedPairs(t)
	local function orderedNext(t, state)
		local key
		if not state then
			local function __genOrderedIndex(t)
				local orderedIndex = {}
				for k in pairs(t) do
					table.insert(orderedIndex, k)
				end
				table.sort(orderedIndex)
				return orderedIndex
			end

			-- the first time, generate the index
			t.__orderedIndex = __genOrderedIndex(t)
			key = t.__orderedIndex[1]
		else
			-- fetch the next value
			for i = 1, table.getn(t.__orderedIndex) do
				if t.__orderedIndex[i] == state then key = t.__orderedIndex[i + 1] end
			end
		end

		if key then return key, t[key] end

		-- no more value to return, cleanup
		t.__orderedIndex = nil
		return
	end

	return orderedNext, t, nil
end

-- Config
local dataPath = './.fg/'

local stdBase = 'lua51+fg+fgfunctions'
local stdString = arg[1] or ''
local headerFileName = arg[2] or '.luacheckrc_header'
local outputFile = arg[3] or '.luacheckrc'

-- Core
local lfs = require('lfs')

-- open new luachecrc file for writing and post error if not possible
local destFile = assert(io.open(outputFile, 'w'), 'Error opening file ' .. outputFile)

-- open header file and add to top of new config file
local headerFile = io.open(headerFileName, 'r')
if headerFile then
	destFile:write(headerFile:read('*a'))
	headerFile:close()
end

-- returns a list of files ending in globals.lua
local function findPackageFiles(path)
	local result = {}

	for file in lfs.dir(path) do
		local fileType = lfs.attributes(path .. '/' .. file, 'mode')
		local packageName = string.match(file, '(.*).luacheckrc_std')
		if packageName and fileType == 'file' then
			if file ~= '.' and file ~= '..' then result[packageName] = path .. '/' .. file end
		end
	end

	return result
end

local packageFiles = findPackageFiles(dataPath .. 'globals/')

-- add std config to luachecrc file
destFile:write("\nstd = '" .. stdBase)
for packageName, _ in orderedPairs(packageFiles) do
	destFile:write('+' .. packageName)
end
destFile:write(stdString)
destFile:write("'\n")

-- looks through each package type's detected globals
-- it then appends them to the config file
for packageName, file in orderedPairs(packageFiles) do
	local stdsName = ('\nstds.' .. packageName .. ' = {\n')
	destFile:write(stdsName)
	local fhandle = io.open(file, 'r')
	local content = fhandle:read('*a')
	for line in string.gmatch(content, '[^\r\n]+') do
		destFile:write('\t' .. line .. '\n')
	end
	destFile:write('}\n')
end

destFile:close()
