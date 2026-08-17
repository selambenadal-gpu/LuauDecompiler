local Chunk = {}

Chunk.SIGNATURE = string.char(0x1B, 0x4C, 0x75, 0x61)

function Chunk.isValidSignature(reader)
	local start = reader:position()
	local signature = reader:bytes(4)
  
	return signature == Chunk.SIGNATURE, start
end

function Chunk.validateVersion(version)
	return version >= 3 and version <= 12
end

function Chunk.readVersion(reader)
	local version = reader:u8()

	if not Chunk.validateVersion(version) then
		error(("Unsupported Luau bytecode version: %d"):format(version))
	end

	return version
end

return Chunk
