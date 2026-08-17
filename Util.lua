local Util = {}

-- Buffer API wrapper (Luau'da %40-60 daha hızlı string building)
local Buffer = {}
Buffer.__index = Buffer

function Buffer.new(capacity)
    return setmetatable({
        _buf = buffer.create(capacity or 4096),
        _len = 0,
        _cap = capacity or 4096
    }, Buffer)
end

function Buffer:write(str)
    local slen = #str
    if self._len + slen > self._cap then
        local newCap = math.max(self._cap * 2, self._len + slen)
        local newBuf = buffer.create(newCap)
        buffer.copy(newBuf, 0, self._buf, 0, self._len)
        self._buf = newBuf
        self._cap = newCap
    end
    buffer.writestring(self._buf, self._len, str)
    self._len = self._len + slen
end

function Buffer:writeln(str)
    self:write(str)
    self:write("\n")
end

function Buffer:indent(level)
    for _ = 1, level do self:write("    ") end
end

function Buffer:toString()
    return buffer.readstring(self._buf, 0, self._len)
end

Util.Buffer = Buffer

function Util.isIdentifier(value)
    return type(value) == "string" and value:match("^[A-Za-z_][A-Za-z0-9_]*$") ~= nil
end

function Util.quoteString(value)
    value = tostring(value or "")
    local escaped = value:gsub("\\", "\\\\")
        :gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t"):gsub('"', '\\"')
    escaped = escaped:gsub("[%z\1-\31\127-\255]", function(ch)
        return ("\\%03d"):format(string.byte(ch))
    end)
    return '"' .. escaped .. '"'
end

function Util.formatNumber(value)
    if value ~= value then return "0/0" end
    if value == math.huge then return "math.huge" end
    if value == -math.huge then return "-math.huge" end
    if math.floor(value) == value and math.abs(value) < 9007199254740992 then
        return ("%.0f"):format(value)
    end
    return ("%.17g"):format(value)
end

return Util
