local Chunk = {}

local function readSignature(reader)
	local signature = reader:bytes(4)

	return signature == string.char(0x1B, 0x4C, 0x75, 0x61)
end

function Chunk.read(reader, Version)
	assert(reader, "reader is required")
	assert(Version, "version module is required")

	if not readSignature(reader) then
		error("Invalid Luau bytecode signature")
	end

	local version = reader:u8()

	if not Version.isSupported(version) then
		error(("Unsupported Luau bytecode version: %d"):format(version))
	end

	return {
		version = version,
	}
end

return Chunk
