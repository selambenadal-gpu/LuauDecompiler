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
	A = "A",
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

Definitions.register(0, "NOP", "ABC")
Definitions.register(1, "BREAK", "ABC")
Definitions.register(2, "LOADNIL", "A")
Definitions.register(3, "LOADB", "ABC")
Definitions.register(4, "LOADN", "AD")
Definitions.register(5, "LOADK", "AD")
Definitions.register(6, "MOVE", "ABC")
Definitions.register(7, "GETGLOBAL", "AUX")
Definitions.register(8, "SETGLOBAL", "AUX")
Definitions.register(9, "GETUPVAL", "ABC")
Definitions.register(10, "SETUPVAL", "ABC")
Definitions.register(11, "CLOSEUPVALS", "ABC")
Definitions.register(12, "GETIMPORT", "AUX")
Definitions.register(13, "GETTABLE", "ABC")
Definitions.register(14, "SETTABLE", "ABC")
Definitions.register(15, "GETTABLEKS", "AUX")
Definitions.register(16, "SETTABLEKS", "AUX")
Definitions.register(17, "GETTABLEN", "ABC")
Definitions.register(18, "SETTABLEN", "ABC")
Definitions.register(19, "NEWCLOSURE", "AD")
Definitions.register(20, "NAMECALL", "AUX")
Definitions.register(21, "CALL", "ABC")
Definitions.register(22, "RETURN", "ABC")
Definitions.register(23, "JUMP", "AD")
Definitions.register(24, "JUMPBACK", "AD")
Definitions.register(25, "JUMPIF", "AD")
Definitions.register(26, "JUMPIFNOT", "AD")

return Definitions
