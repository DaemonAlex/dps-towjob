-- Runs every tests/test_*.lua. Run from the repo root: lua5.4 tests/run.lua
package.path = 'tests/?.lua;' .. package.path
local T = require('stubs')

local files = {}
local pipe = io.popen('ls tests/test_*.lua 2>/dev/null')
for line in pipe:lines() do files[#files + 1] = line end
pipe:close()
table.sort(files)

for i = 1, #files do dofile(files[i]) end

os.exit(T.report() and 0 or 1)
