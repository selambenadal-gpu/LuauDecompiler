local Reader = require(script.Parent.Parent.Parent.Decompiler.parser.Reader)
local Chunk = require(script.Parent.Parent.Parent.Decompiler.parser.Chunk)
local Version = require(script.Parent.Parent.Parent.Decompiler.parser.Version)

local function makeBytecode(version)
	return string.char(
		0x1B, 0x4C, 0x75, 0x61,
		version
	)
end

local reader = Reader.new(makeBytecode(9))
local chunk = Chunk.read(reader, Version)

assert(chunk.version == 9, "Version should be 9")

print("TestChunk: PASS")
