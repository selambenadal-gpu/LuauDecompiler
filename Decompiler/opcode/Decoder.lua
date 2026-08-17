local Decoder = {}

local function u8(word, shift)
	return math.floor(word / 2 ^ shift) % 256
end

local function s16(word)
	local value = math.floor(word / 65536) % 65536

	if value >= 32768 then
		value = value - 65536
	end

	return value
end

local function s24(word)
	local value = math.floor(word / 256) % 16777216

	if value >= 8388608 then
		value = value - 16777216
	end

	return value
end

function Decoder.decodeWord(word, Definitions)
	assert(type(word) == "number", "instruction word must be a number")
	assert(Definitions, "Definitions is required")

	local opcodeId = u8(word, 0)
	local definition = Definitions.get(opcodeId)

	local instruction = {
		raw = word,
		opcode = opcodeId,

		A = u8(word, 8),
		B = u8(word, 16),
		C = u8(word, 24),

		D = s16(word),
		E = s24(word),

		definition = definition,
	}

	if definition then
		instruction.name = definition.name
		instruction.format = definition.format
	else
		instruction.name = "UNKNOWN"
		instruction.format = nil
	end

	return instruction
end

function Decoder.decode(words, Definitions)
	assert(type(words) == "table", "words must be a table")
	assert(Definitions, "Definitions is required")

	local instructions = {}

	for pc, word in ipairs(words) do
		local instruction = Decoder.decodeWord(word, Definitions)

		instruction.pc = pc

		instructions[pc] = instruction
	end

	return instructions
end

return Decoder
