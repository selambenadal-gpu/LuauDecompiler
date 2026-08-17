-- Bu dosyayı projenin root'unda çalıştır: lua tools/build.lua
local modules = {
    "Util", "Opcode", "Versions", "Encodings", "Reader",
    "IR", "PassManager", "BackendLua", "BytecodeParser",
    "passes/ConstantFold", "passes/TypeAnnotate", "passes/RobloxBuiltin"
}

local output = {"-- Auto-generated bundle, DO NOT EDIT\n"}
output[#output+1] = "local __modules = {}\n"
output[#output+1] = "local __cache = {}\n"
output[#output+1] = "local function require(path)\n"
output[#output+1] = "  if __cache[path] then return __cache[path] end\n"
output[#output+1] = "  local fn = __modules[path]\n"
output[#output+1] = "  if not fn then error('Module not found: ' .. path) end\n"
output[#output+1] = "  local result = fn()\n"
output[#output+1] = "  __cache[path] = result\n"
output[#output+1] = "  return result\n"
output[#output+1] = "end\n\n"

for _, name in ipairs(modules) do
   local filepath = name .. ".lua"
    local f = assert(io.open(filepath, "r"), "Cannot open: " .. filepath)
    local content = f:read("*a")
    f:close()

    -- script.Parent.X referanslarını string path'e çevir
    content = content:gsub('require%(script%.Parent%.([%w_]+)%)', 'require("%1")')
    content = content:gsub('require%(script%.Parent%.passes%.([%w_]+)%)', 'require("passes/%1")')
    content = content:gsub('require%(script%.Parent%)', 'require("BytecodeParser")')

    output[#output+1] = ('__modules["%s"] = function()\n'):format(name)
    output[#output+1] = content
    output[#output+1] = "\nend\n\n"
end

-- init.lua'yı son olarak ekle ve çalıştır
local initFile = assert(io.open("init.lua", "r"))
local initContent = initFile:read("*a")
initFile:close()
initContent = initContent:gsub('require%(script%.([%w_]+)%)', 'require("%1")')
initContent = initContent:gsub('require%(script%.passes%.([%w_]+)%)', 'require("passes/%1")')

output[#output+1] = "-- Entry point\n"
output[#output+1] = initContent

local outFile = assert(io.open("dist/bundle.lua", "w"))
outFile:write(table.concat(output))
outFile:close()
print("✅ dist/bundle.lua generated successfully!")
