local Opcode = {}

Opcode.names = {
	"NOP", "BREAK", "LOADNIL", "LOADB", "LOADN", "LOADK", "MOVE",
	"GETGLOBAL", "SETGLOBAL", "GETUPVAL", "SETUPVAL", "CLOSEUPVALS",
	"GETIMPORT", "GETTABLE", "SETTABLE", "GETTABLEKS", "SETTABLEKS",
	"GETTABLEN", "SETTABLEN", "NEWCLOSURE", "NAMECALL", "CALL", "RETURN",
	"JUMP", "JUMPBACK", "JUMPIF", "JUMPIFNOT", "JUMPIFEQ", "JUMPIFLE",
	"JUMPIFLT", "JUMPIFNOTEQ", "JUMPIFNOTLE", "JUMPIFNOTLT", "ADD", "SUB",
	"MUL", "DIV", "MOD", "POW", "ADDK", "SUBK", "MULK", "DIVK", "MODK",
	"POWK", "AND", "OR", "ANDK", "ORK", "CONCAT", "NOT", "MINUS", "LENGTH",
	"NEWTABLE", "DUPTABLE", "SETLIST", "FORNPREP", "FORNLOOP", "FORGLOOP",
	"FORGPREP_INEXT", "FASTCALL3", "FORGPREP_NEXT", "NATIVECALL", "GETVARARGS",
	"DUPCLOSURE", "PREPVARARGS", "LOADKX", "JUMPX", "FASTCALL", "COVERAGE",
	"CAPTURE", "SUBRK", "DIVRK", "FASTCALL1", "FASTCALL2", "FASTCALL2K",
	"FORGPREP", "JUMPXEQKNIL", "JUMPXEQKB", "JUMPXEQKN", "JUMPXEQKS",
	"IDIV", "IDIVK", "GETUDATAKS", "SETUDATAKS", "NAMECALLUDATA",
	"NEWCLASSMEMBER", "CALLFB", "CMPPROTO",
}

Opcode.id = {}
for i, name in ipairs(Opcode.names) do
	Opcode.id[name] = i - 1
end

-- YENİ: IR Pass'leri için operand sınıflandırma
-- Pass'ler bu metadata'yı okuyarak hangi opcode'un ne yaptığını anlar
Opcode.Category = {
	Nop = "Nop", Load = "Load", Store = "Store", Move = "Move",
	BinaryOp = "BinaryOp", UnaryOp = "UnaryOp", Compare = "Compare",
	Jump = "Jump", Call = "Call", Return = "Return",
	Table = "Table", Closure = "Closure", Loop = "Loop",
	Capture = "Capture", FastCall = "FastCall", Debug = "Debug",
	Unknown = "Unknown",
}

local categories = {
	NOP = "Nop", BREAK = "Debug", COVERAGE = "Debug", PREPVARARGS = "Nop",
	LOADNIL = "Load", LOADB = "Load", LOADN = "Load", LOADK = "Load",
	LOADKX = "Load", MOVE = "Move", GETVARARGS = "Load",
	GETGLOBAL = "Load", SETGLOBAL = "Store",
	GETUPVAL = "Load", SETUPVAL = "Store", CLOSEUPVALS = "Nop",
	GETIMPORT = "Load", GETTABLE = "Load", SETTABLE = "Store",
	GETTABLEKS = "Load", SETTABLEKS = "Store", GETTABLEN = "Load",
	SETTABLEN = "Store", GETUDATAKS = "Load", SETUDATAKS = "Store",
	NEWTABLE = "Table", DUPTABLE = "Table", SETLIST = "Table",
	NEWCLOSURE = "Closure", DUPCLOSURE = "Closure", CAPTURE = "Capture",
	NAMECALL = "Call", NAMECALLUDATA = "Call", CALL = "Call",
	CALLFB = "Call", NATIVECALL = "Call", RETURN = "Return",
	ADD = "BinaryOp", SUB = "BinaryOp", MUL = "BinaryOp", DIV = "BinaryOp",
	MOD = "BinaryOp", POW = "BinaryOp", IDIV = "BinaryOp", AND = "BinaryOp",
	OR = "BinaryOp", ADDK = "BinaryOp", SUBK = "BinaryOp", MULK = "BinaryOp",
	DIVK = "BinaryOp", MODK = "BinaryOp", POWK = "BinaryOp", IDIVK = "BinaryOp",
	ANDK = "BinaryOp", ORK = "BinaryOp", SUBRK = "BinaryOp", DIVRK = "BinaryOp",
	CONCAT = "BinaryOp", NOT = "UnaryOp", MINUS = "UnaryOp", LENGTH = "UnaryOp",
	JUMP = "Jump", JUMPBACK = "Jump", JUMPX = "Jump",
	JUMPIF = "Compare", JUMPIFNOT = "Compare", JUMPIFEQ = "Compare",
	JUMPIFLE = "Compare", JUMPIFLT = "Compare", JUMPIFNOTEQ = "Compare",
	JUMPIFNOTLE = "Compare", JUMPIFNOTLT = "Compare",
	JUMPIFEQK = "Compare", JUMPIFNOTEQK = "Compare",
	JUMPXEQKNIL = "Compare", JUMPXEQKB = "Compare",
	JUMPXEQKN = "Compare", JUMPXEQKS = "Compare", CMPPROTO = "Compare",
	FORNPREP = "Loop", FORNLOOP = "Loop", FORGPREP = "Loop",
	FORGLOOP = "Loop", FORGPREP_INEXT = "Loop", FORGPREP_NEXT = "Loop",
	FASTCALL = "FastCall", FASTCALL1 = "FastCall", FASTCALL2 = "FastCall",
	FASTCALL2K = "FastCall", FASTCALL3 = "FastCall",
	NEWCLASSMEMBER = "Store",
}

function Opcode.getCategory(opname)
	return categories[opname] or "Unknown"
end

-- YENİ: Constant-foldable binary op mapping (PassManager kullanır)
Opcode.FoldableBinaryOps = {
	ADD = "+", SUB = "-", MUL = "*", DIV = "/", MOD = "%", POW = "^", IDIV = "//",
	ADDK = "+", SUBK = "-", MULK = "*", DIVK = "/", MODK = "%", POWK = "^", IDIVK = "//",
	SUBRK = "-", DIVRK = "/",
}

-- YENİ: Commutative op tespiti (ConstantFold pass'i için)
Opcode.CommutativeOps = {
	ADD = true, MUL = true, AND = true, OR = true,
	ADDK = true, MULK = true, ANDK = true, ORK = true,
}

local twoWord = {
	GETGLOBAL = true, SETGLOBAL = true, GETIMPORT = true, GETTABLEKS = true,
	SETTABLEKS = true, NAMECALL = true, JUMPIFEQ = true, JUMPIFLE = true,
	JUMPIFLT = true, JUMPIFNOTEQ = true, JUMPIFNOTLE = true, JUMPIFNOTLT = true,
	NEWTABLE = true, SETLIST = true, FORGLOOP = true, LOADKX = true,
	FASTCALL2 = true, FASTCALL2K = true, FASTCALL3 = true, JUMPIFEQK = true,
	JUMPIFNOTEQK = true, JUMPXEQKNIL = true, JUMPXEQKB = true, JUMPXEQKN = true,
	JUMPXEQKS = true, GETUDATAKS = true, SETUDATAKS = true, NAMECALLUDATA = true,
	NEWCLASSMEMBER = true, CALLFB = true, CMPPROTO = true,
}

local jumpD = {
	JUMP = true, JUMPIF = true, JUMPIFNOT = true, JUMPIFEQ = true, JUMPIFLE = true,
	JUMPIFLT = true, JUMPIFNOTEQ = true, JUMPIFNOTLE = true, JUMPIFNOTLT = true,
	FORNPREP = true, FORNLOOP = true, FORGPREP = true, FORGLOOP = true,
	FORGPREP_INEXT = true, FORGLOOP_INEXT = true, FORGPREP_NEXT = true,
	FORGLOOP_NEXT = true, JUMPBACK = true, JUMPIFEQK = true, JUMPIFNOTEQK = true,
	JUMPXEQKNIL = true, JUMPXEQKB = true, JUMPXEQKN = true, JUMPXEQKS = true,
	CMPPROTO = true,
}

local fastCall = {
	FASTCALL = true, FASTCALL1 = true, FASTCALL2 = true, FASTCALL2K = true, FASTCALL3 = true,
}

function Opcode.name(op)
	return Opcode.names[op + 1] or ("OP_" .. tostring(op))
end

function Opcode.lengthByName(opname)
	return twoWord[opname] and 2 or 1
end

function Opcode.length(op)
	return Opcode.lengthByName(Opcode.name(op))
end

function Opcode.isJumpD(op)
	return jumpD[Opcode.name(op)] == true
end

function Opcode.isFastCall(op)
	return fastCall[Opcode.name(op)] == true
end

function Opcode.jumpTarget(insn)
	local op = insn.opname
	if jumpD[op] then return insn.pc + insn.D + 1 end
	if fastCall[op] then return insn.pc + insn.C + 2 end
	if op == "LOADB" and insn.C ~= 0 then return insn.pc + insn.C + 1 end
	if op == "JUMPX" then return insn.pc + insn.E + 1 end
	return nil
end

function Opcode.decodeWord(word, opOverride)
	local rawOp = word & 0xff
	local op = opOverride or rawOp
	local a = (word >> 8) & 0xff
	local b = (word >> 16) & 0xff
	local c = (word >> 24) & 0xff
	local d = word >> 16
	if d >= 32768 then d -= 65536 end
	local e = word >> 8
	if e >= 8388608 then e -= 16777216 end
	return op, a, b, c, d, e, rawOp
end

function Opcode.decodeImportId(value)
	local count = value >> 30
	local id0 = count > 0 and ((value >> 20) & 1023) or nil
	local id1 = count > 1 and ((value >> 10) & 1023) or nil
	local id2 = count > 2 and (value & 1023) or nil
	return count, id0, id1, id2
end

return Opcode
