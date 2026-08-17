local REPO = "https://raw.githubusercontent.com/selambenadal-gpu/LuauDecompiler/main/"

local function fetch(url)
    local ok, res = pcall(http.request, { Url = url, Method = "GET" })
    if not ok then error("http.request failed: " .. tostring(res)) end
    if type(res) == "table" and res.Body then
        if res.Success == false then error("HTTP " .. tostring(res.StatusCode) .. ": " .. url) end
        return res.Body
    end
    -- Bazı executor'lar direkt string döndürür
    if type(res) == "string" then return res end
    error("Unexpected http.request response type: " .. type(res))
end

local modules = {
    "Util", "Opcode", "Versions", "Encodings", "Reader",
    "IR", "PassManager", "BackendLua", "BytecodeParser",
    "passes/ConstantFold", "passes/TypeAnnotate", "passes/RobloxBuiltin"
}

local output = {"-- Auto-generated bundle, DO NOT EDIT\n"}
output[#output+1] = "local __modules = {}\nlocal __cache = {}\n"
output[#output+1] = "local function require(path)\n"
output[#output+1] = "  if __cache[path] then return __cache[path] end\n"
output[#output+1] = "  local fn = __modules[path]\n"
output[#output+1] = "  if not fn then error('Module not found: ' .. path) end\n"
output[#output+1] = "  local result = fn()\n  __cache[path] = result\n  return result\nend\n\n"

for _, name in ipairs(modules) do
    print("Fetching: " .. name)
    local content = fetch(REPO .. name .. ".lua")
    content = content:gsub('require%(script%.Parent%.([%w_]+)%)', 'require("%1")')
    content = content:gsub('require%(script%.Parent%.passes%.([%w_]+)%)', 'require("passes/%1")')
    content = content:gsub('require%(script%.Parent%)', 'require("BytecodeParser")')
    output[#output+1] = ('__modules["%s"] = function()\n%s\nend\n\n'):format(name, content)
end

print("Fetching: init.lua")
local initContent = fetch(REPO .. "init.lua")
initContent = initContent:gsub('require%(script%.([%w_]+)%)', 'require("%1")')
initContent = initContent:gsub('require%(script%.passes%.([%w_]+)%)', 'require("passes/%1")')
output[#output+1] = "-- Entry point\n" .. initContent

local bundle = table.concat(output)
setclipboard(bundle)
print("✅ Bundle copied to clipboard! (" .. #bundle .. " bytes)")
