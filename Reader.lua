local Reader = {}
Reader.__index = Reader

function Reader.new(data)
	return setmetatable({
		data = data,
		pos = 1,
		size = #data,
	}, Reader)
end

function Reader:offset() return self.pos - 1 end
function Reader:left() return self.size - self.pos + 1 end

-- YENİ: Position save/restore (IR builder backtracking için)
function Reader:save() return self.pos end
function Reader:restore(savedPos) self.pos = savedPos end

-- YENİ: İleriye bak ama pozisyonu ilerletme
function Reader:peekU8(offset)
	offset = offset or 0
	local p = self.pos + offset
	if p > self.size then return nil end
	return string.byte(self.data, p)
end

function Reader:need(count)
	if self.pos + count - 1 > self.size then
		error(("unexpected end of bytecode at byte %d while reading %d byte(s)"):format(self:offset(), count), 3)
	end
end

-- YENİ: Hata fırlatmak yerine nil döndüren safe read
function Reader:tryReadU8()
	if self.pos > self.size then return nil end
	local value = string.byte(self.data, self.pos)
	self.pos = self.pos + 1
	return value
end

function Reader:readBytes(count)
	self:need(count)
	local value = self.data:sub(self.pos, self.pos + count - 1)
	self.pos = self.pos + count
	return value
end

function Reader:readU8()
	self:need(1)
	local value = string.byte(self.data, self.pos)
	self.pos = self.pos + 1
	return value
end

function Reader:readU32()
	local pos = self.pos
	if pos + 3 > self.size then error("unexpected end of bytecode", 2) end
	local b1, b2, b3, b4 = string.byte(self.data, pos, pos + 3)
	self.pos = pos + 4
	return b1 | (b2 << 8) | (b3 << 16) | (b4 << 24)
end

function Reader:readI32()
	local value = self:readU32()
	if value >= 2147483648 then return value - 4294967296 end
	return value
end

function Reader:readF32()
	self:need(4)
	local value, nextPos = string.unpack("<f", self.data, self.pos)
	self.pos = nextPos
	return value
end

function Reader:readF64()
	self:need(8)
	local value, nextPos = string.unpack("<d", self.data, self.pos)
	self.pos = nextPos
	return value
end

function Reader:readVarInt()
	local result = 0
	local shift = 0
	local pos = self.pos
	local data = self.data
	local size = self.size
	while true do
		if pos > size then error("unexpected end of bytecode", 2) end
		local byte = string.byte(data, pos)
		pos += 1
		result |= (byte & 127) << shift
		shift += 7
		if byte < 128 then break end
		if shift >= 63 then error("varint is too large", 2) end
	end
	self.pos = pos
	return result
end

local function decimalMulSmall(parts, factor)
	local carry = 0
	for i = 1, #parts do
		local value = parts[i] * factor + carry
		parts[i] = value % 1000000000
		carry = math.floor(value / 1000000000)
	end
	while carry > 0 do
		parts[#parts + 1] = carry % 1000000000
		carry = math.floor(carry / 1000000000)
	end
end

local function decimalAddSmall(parts, addend)
	local carry = addend
	local i = 1
	while carry > 0 do
		if i > #parts then parts[i] = 0 end
		local value = parts[i] + carry
		parts[i] = value % 1000000000
		carry = math.floor(value / 1000000000)
		i = i + 1
	end
end

local function decimalToString(parts)
	local top = #parts
	while top > 1 and parts[top] == 0 do top = top - 1 end
	local out = {tostring(parts[top] or 0)}
	for i = top - 1, 1, -1 do out[#out + 1] = ("%09d"):format(parts[i]) end
	return table.concat(out)
end

function Reader:readVarInt64Decimal()
	local payloads = {}
	while true do
		local byte = self:readU8()
		payloads[#payloads + 1] = byte % 128
		if byte < 128 then break end
		if #payloads > 10 then error("varint64 is too large", 2) end
	end
	local parts = {0}
	for i = #payloads, 1, -1 do
		decimalMulSmall(parts, 128)
		decimalAddSmall(parts, payloads[i])
	end
	return decimalToString(parts)
end

Reader.readVarInt64 = Reader.readVarInt

return Reader
