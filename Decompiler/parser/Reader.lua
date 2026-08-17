local Reader = {}
Reader.__index = Reader

function Reader.new(data)
	assert(type(data) == "string", "Reader expects binary string")

	return setmetatable({
		data = data,
		position = 1,
		length = #data,
	}, Reader)
end

function Reader:remaining()
	return self.length - self.position + 1
end

function Reader:position()
	return self.position
end

function Reader:check(size)
	if self.position + size - 1 > self.length then
		error(("Unexpected end of data at offset %d"):format(self.position))
	end
end

function Reader:u8()
	self:check(1)

	local value = string.byte(self.data, self.position)
	self.position = self.position + 1

	return value
end

function Reader:u16()
	local lo = self:u8()
	local hi = self:u8()

	return lo + hi * 256
end

function Reader:u32()
	local b1 = self:u8()
	local b2 = self:u8()
	local b3 = self:u8()
	local b4 = self:u8()

	return b1
		+ b2 * 256
		+ b3 * 65536
		+ b4 * 16777216
end

function Reader:i16()
	local value = self:u16()

	if value >= 32768 then
		value = value - 65536
	end

	return value
end

function Reader:i32()
	local value = self:u32()

	if value >= 2147483648 then
		value = value - 4294967296
	end

	return value
end

function Reader:bytes(count)
	assert(count >= 0, "count must be non-negative")
	self:check(count)

	local value = self.data:sub(self.position, self.position + count - 1)
	self.position = self.position + count

	return value
end

function Reader:string(count)
	return self:bytes(count)
end

function Reader:skip(count)
	assert(count >= 0, "count must be non-negative")
	self:check(count)

	self.position = self.position + count
end

function Reader:eof()
	return self.position > self.length
end

return Reader
