local Definitions = require(script.Parent.Parent.Parent.Decompiler.opcode.Definitions)
local Decoder = require(script.Parent.Parent.Parent.Decompiler.opcode.Decoder)

-- opcode 5 = LOADK
-- A = 3
-- D = 42
local word =
	5
	+ 3 * 2 ^ 8
	+ 42 * 2 ^ 16

local instruction = Decoder.decodeWord(word, Definitions)

assert(instruction.opcode == 5, "Opcode should be 5")
assert(instruction.name == "LOADK", "Opcode name should be LOADK")
assert(instruction.A == 3, "A should be 3")
assert(instruction.D == 42, "D should be 42")

print("TestDecoder: PASS")
