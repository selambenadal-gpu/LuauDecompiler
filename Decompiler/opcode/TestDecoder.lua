local Reader = require(script.Parent.Parent.Parent.Decompiler.parser.Reader)

local data = string.char(
	5, 0, 0, 0
)

local reader = Reader.new(data)

local instructions = Decoder.decodeReader(
	reader,
	Definitions,
	1
)

assert(#instructions == 1, "Should decode one instruction")
assert(instructions[1].opcode == 5, "Reader opcode should be 5")
assert(instructions[1].name == "LOADK", "Reader opcode should be LOADK")

print("TestDecoder Reader: PASS")
