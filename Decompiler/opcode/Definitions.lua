local Definitions = {}

Definitions.VERSION = {
	MIN = 3,
	MAX = 12,
	TARGET = 9,
}

Definitions.FORMAT = {
	ABC = "ABC",
	AD = "AD",
	E = "E",
	AUX = "AUX",
}

Definitions.OPCODES = {}

function Definitions.register(id, name, format, info)
	Definitions.OPCODES[id] = {
		id = id,
		name = name,
		format = format,
		info = info,
	}
end

return Definitions
