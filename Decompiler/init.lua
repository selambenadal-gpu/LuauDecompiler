local Reader = require(script.parser.Reader)
local Chunk = require(script.parser.Chunk)
local Version = require(script.parser.Version)

local Decompiler = {}

function Decompiler.parse(bytecode)
	assert(type(bytecode) == "string", "bytecode must be a string")

	local reader = Reader.new(bytecode)
	local chunk = Chunk.read(reader, Version)

	return chunk
end

return Decompiler
