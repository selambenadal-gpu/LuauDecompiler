local Reader = require(script.Parent.Reader)
local Opcode = require(script.Parent.Opcode)
local Versions = require(script.Parent.Versions)
local Encodings = require(script.Parent.Encodings)
local IR = require(script.Parent.IR)
local Util = require(script.Parent.Util)

local BytecodeParser = {}

-- ========== BYTECODE INPUT NORMALIZATION ==========
local function byteAt(data, offset)
	if offset < 1 or offset > #data then return nil end
	return string.byte(data, offset)
end

local function headerLooksValidAt(data, offset)
	local version = byteAt(data, offset)
	if not version then return false end
	local info = Versions.get(version)
	local typeVersion = info.hasTypeVersion and byteAt(data, offset + 1) or nil
	return Versions.bytecodeHeaderLooksValid(version, typeVersion)
end

local function rzEnvelopeLooksValid(data)
	return data:sub(1, 2) == "Rz" and headerLooksValidAt(data, 9)
end

local function normalizeInput(data)
	if headerLooksValidAt(data, 1) then return data, { format = "raw" } end
	if rzEnvelopeLooksValid(data) then return data:sub(9), { format = "roblox-envelope", prefixBytes = 8 } end
	return data, { format = "raw" }
end

-- ========== CONSTANT READING ==========
local CONSTANT_NAMES = {
	[0] = "nil", [1] = "boolean", [2] = "number", [3] = "string",
	[4] = "import", [5] = "table", [6] = "closure", [7] = "vector",
	[8] = "table_with_constants", [9] = "integer", [10] = "class_shape",
}

local function readStringRef(reader, strings)
	local id = reader:readVarInt()
	if id == 0 then return nil, 0 end
	return strings[id], id
end

local function parseConstants(reader, versionInfo)
	local constants = {}
	local count = reader:readVarInt()

	for i = 0, count - 1 do
		local tag = reader:readU8()
		local constant = { index = i, tag = tag, kind = CONSTANT_NAMES[tag] or ("unknown_" .. tostring(tag)) }

		if tag == 0 then constant.value = nil
		elseif tag == 1 then constant.value = reader:readU8() ~= 0
		elseif tag == 2 then constant.value = reader:readF64()
		elseif tag == 3 then constant.stringId = reader:readVarInt()
		elseif tag == 4 then constant.value = reader:readU32()
		elseif tag == 5 then
			constant.keys = {}
			local keyCount = reader:readVarInt()
			for _ = 1, keyCount do constant.keys[#constant.keys + 1] = reader:readVarInt() end
		elseif tag == 6 then constant.proto = reader:readVarInt()
		elseif tag == 7 then constant.value = { reader:readF32(), reader:readF32(), reader:readF32(), reader:readF32() }
		elseif tag == 8 then
			constant.entries = {}
			local keyCount = reader:readVarInt()
			for _ = 1, keyCount do constant.entries[#constant.entries + 1] = { key = reader:readVarInt(), value = reader:readI32() } end
		elseif tag == 9 then
			local negative = reader:readU8() ~= 0
			local magnitudeText = reader:readVarInt64Decimal()
			constant.valueText = negative and ("-" .. magnitudeText) or magnitudeText
			constant.value = tonumber(constant.valueText)
		elseif tag == 10 then
			constant.className = reader:readVarInt()
			constant.propertyNames = {}
			constant.methodNames = {}
			local propCount = reader:readVarInt()
			local methCount = reader:readVarInt()
			for _ = 1, propCount do constant.propertyNames[#constant.propertyNames + 1] = reader:readVarInt() end
			for _ = 1, methCount do constant.methodNames[#constant.methodNames + 1] = reader:readVarInt() end
		else
			error(("unknown constant tag %d at byte %d"):format(tag, reader:offset()), 2)
		end

		constants[i + 1] = constant
	end

	return constants
end

local function patchConstantStrings(constants, strings)
	for _, c in ipairs(constants) do
		if c.kind == "string" then c.value = strings[c.stringId] end
	end
end

-- ========== DEBUG INFO (Hash Map) ==========
local function parseDebugInfo(reader, strings)
	local info = { locals = {}, upvalues = {} }
	if reader:readU8() == 0 then return info end

	local localCount = reader:readVarInt()
	for i = 1, localCount do
		local name = readStringRef(reader, strings)
		info.locals[i] = {
			name = name,
			startpc = reader:readVarInt(),
			endpc = reader:readVarInt(),
			reg = reader:readU8(),
		}
	end

	local upvalueCount = reader:readVarInt()
	for i = 1, upvalueCount do
		info.upvalues[i] = { name = readStringRef(reader, strings) }
	end

	return info
end

-- ========== LINE INFO ==========
local function parseLineInfo(reader, sizecode)
	local lineinfo = { lines = {} }
	if reader:readU8() == 0 then return lineinfo end
	lineinfo.linegaplog2 = reader:readU8()
	local span = 2 ^ lineinfo.linegaplog2
	local intervals = math.floor((sizecode - 1) / span) + 1
	local deltas = {}
	local lastOffset = 0
	for i = 1, sizecode do
		lastOffset = (lastOffset + reader:readU8()) % 256
		deltas[i] = lastOffset
	end
	local baselines = {}
	local lastLine = 0
	for i = 1, intervals do
		lastLine = lastLine + reader:readI32()
		baselines[i] = lastLine
	end
	for pc = 0, sizecode - 1 do
		local baseline = baselines[math.floor(pc / span) + 1] or 0
		lineinfo.lines[pc + 1] = baseline + (deltas[pc + 1] or 0)
	end
	return lineinfo
end

-- ========== FULL BYTECODE PARSER ==========
function BytecodeParser.parse(data, options)
	options = options or {}
	local normalized, inputMeta = normalizeInput(data)
	local reader = Reader.new(normalized)
	local version = reader:readU8()

	if Versions.isSourceTextMarker(version) then
		error("source text marker, not bytecode")
	end
	if not Versions.bytecodeVersionSupported(version) then
		error(Versions.unsupportedBytecodeVersionMessage(version))
	end

	local versionInfo = Versions.get(version)
	local chunk = {
		version = version,
		versionInfo = versionInfo,
		typeVersion = 0,
		strings = {},
		protos = {},
		mainProto = nil,
		inputMeta = inputMeta,
	}

	if versionInfo.hasTypeVersion then
		chunk.typeVersion = reader:readU8()
	end

	-- Strings
	local stringCount = reader:readVarInt()
	for i = 1, stringCount do
		local length = reader:readVarInt()
		chunk.strings[i] = reader:readBytes(length)
	end

	-- Userdata types (skip for now, IR doesn't need them directly)
	if Versions.hasUserdataTypeNames(version, chunk.typeVersion) then
		while true do
			local index = reader:readU8()
			if index == 0 then break end
			readStringRef(reader, chunk.strings) -- consume
		end
	end

	-- Protos
	local protoCount = reader:readVarInt()
	for protoIndex = 0, protoCount - 1 do
		local proto = {
			id = protoIndex,
			maxstacksize = reader:readU8(),
			numparams = reader:readU8(),
			numupvalues = reader:readU8(),
			isvararg = reader:readU8() ~= 0,
			flags = 0,
			typeinfo = nil,
			code = {},
			constants = {},
			children = {},
			debugName = nil,
			lineinfo = nil,
			debuginfo = nil,
		}

		if versionInfo.hasProtoFlags then
			proto.flags = reader:readU8()
			-- Skip typeinfo payload for now (TypeAnnotate pass uses parsed form)
			local typeSize = reader:readVarInt()
			if typeSize > 0 then
				proto.typeinfoRaw = reader:readBytes(typeSize)
			end
		end

		local sizecode = reader:readVarInt()
		for _ = 1, sizecode do
			proto.code[#proto.code + 1] = reader:readU32()
		end

		proto.constants = parseConstants(reader, versionInfo)
		patchConstantStrings(proto.constants, chunk.strings)

		local childCount = reader:readVarInt()
		for _ = 1, childCount do
			proto.children[#proto.children + 1] = reader:readVarInt()
		end

		if versionInfo.hasLineDefined then
			proto.debugLineDefined = reader:readVarInt()
		end

		proto.debugName = readStringRef(reader, chunk.strings)
		proto.lineinfo = parseLineInfo(reader, sizecode)
		proto.debuginfo = parseDebugInfo(reader, chunk.strings)

		if versionInfo.hasFeedback then
			local feedbackCount = reader:readVarInt()
			proto.feedback = {}
			for _ = 1, feedbackCount do
				proto.feedback[#proto.feedback + 1] = { kind = reader:readU8(), pc = reader:readVarInt() }
			end
		end

		chunk.protos[protoIndex + 1] = proto
	end

	chunk.mainProto = reader:readVarInt()

	-- Encoding detection
	local encoding, _score = Encodings.chooseForProtos(chunk.protos, versionInfo, options)
	chunk.encoding = encoding

	return chunk
end

-- ========== PROTO → IR CONVERTER ==========
-- Bu fonksiyon Opcode, Versions ve Reader çıktısını IR node'larına çevirir

local BINARY_OP_MAP = {
	ADD = "add", SUB = "sub", MUL = "mul", DIV = "div", MOD = "mod", POW = "pow",
	IDIV = "idiv", AND = "and_", OR = "or_",
	ADDK = "add", SUBK = "sub", MULK = "mul", DIVK = "div", MODK = "mod",
	POWK = "pow", IDIVK = "idiv", ANDK = "and_", ORK = "or_",
	SUBRK = "sub", DIVRK = "div",
}

local UNARY_OP_MAP = { NOT = "not_", MINUS = "minus", LENGTH = "len" }

local function constToIRExpr(proto, index)
	local c = proto.constants[index + 1]
	if not c then return IR.Expr(IR.E.Nil) end

	if c.kind == "nil" then return IR.Expr(IR.E.Nil)
	elseif c.kind == "boolean" then return IR.Expr(IR.E.Bool, c.value)
	elseif c.kind == "number" then return IR.Expr(IR.E.Number, c.value)
	elseif c.kind == "integer" then return IR.Expr(IR.E.Integer, c.value)
	elseif c.kind == "string" then return IR.Expr(IR.E.String, c.value)
	elseif c.kind == "vector" then return IR.Expr(IR.E.Vector, c.value[1], c.value[2], c.value[3])
	elseif c.kind == "import" then
		local count, id0, id1, id2 = Opcode.decodeImportId(c.value)
		local parts = {}
		for _, id in ipairs({ id0, id1, id2 }) do
			if id ~= nil then
				local kc = proto.constants[id + 1]
				if kc and kc.kind == "string" then parts[#parts + 1] = kc.value end
			end
		end
		return IR.Expr(IR.E.Import, parts)
	elseif c.kind == "table" or c.kind == "table_with_constants" then return IR.Expr(IR.E.TableConst)
	elseif c.kind == "closure" then return IR.Expr(IR.E.Closure)
	end
	return IR.Expr(IR.E.Nil)
end

local function buildLocalMap(proto)
	local map = {}
	if not proto.debuginfo then return map end
	for _, loc in ipairs(proto.debuginfo.locals or {}) do
		if loc.name then
			for pc = loc.startpc, loc.endpc - 1 do
				if not map[pc] then map[pc] = {} end
				if not map[pc][loc.reg] or loc.startpc > map[pc][loc.reg].startpc then
					map[pc][loc.reg] = loc
				end
			end
		end
	end
	return map
end

local function localNameAt(localMap, reg, pc)
	local pcMap = localMap[pc]
	return pcMap and pcMap[reg] and pcMap[reg].name or nil
end

function BytecodeParser.protoToIR(chunk, proto)
	local localMap = buildLocalMap(proto)
	local nodes = {}
	local regNames = {}

	-- Initialize param names
	local params = {}
	for reg = 0, proto.numparams - 1 do
		local name = localNameAt(localMap, reg, 0) or ("arg" .. tostring(reg + 1))
		params[#params + 1] = name
		regNames[reg] = name
	end
	if proto.isvararg then params[#params + 1] = "..." end

	local function regExpr(regId, pc)
		local name = regNames[regId] or localNameAt(localMap, regId, pc or 0) or ("r" .. tostring(regId))
		return IR.Expr(IR.E.Local, name)
	end

	local function upvalExpr(index)
		local uv = proto.debuginfo and proto.debuginfo.upvalues and proto.debuginfo.upvalues[index + 1]
		local name = uv and uv.name or ("up" .. tostring(index))
		return IR.Expr(IR.E.Upvalue, name)
	end

	-- Decode instructions using Opcode module
	local instructions = {}
	local index = 1
	while index <= #proto.code do
		local word = proto.code[index]
		local rawOp = word & 0xff
		local op, a, b, c, d, e = Opcode.decodeWord(word)
		local opname = Versions.opcodeName(chunk.version, op) or Opcode.name(op)
		local length = Opcode.lengthByName(opname)
		local aux = length == 2 and proto.code[index + 1] or nil

		instructions[#instructions + 1] = {
			pc = index - 1, opname = opname,
			A = a, B = b, C = c, D = d, E = e, aux = aux, length = length,
		}
		index = index + length
	end

	-- Build IR nodes from instructions
	for _, insn in ipairs(instructions) do
		local op = insn.opname
		local a, b, c, d = insn.A, insn.B, insn.C, insn.D
		local aux = insn.aux
		local cat = Opcode.getCategory(op)

		if cat == "Nop" or cat == "Debug" then
			-- skip

		elseif cat == "Load" then
			local value
			if op == "LOADNIL" then value = IR.Expr(IR.E.Nil)
			elseif op == "LOADB" then value = IR.Expr(IR.E.Bool, b ~= 0)
			elseif op == "LOADN" then value = IR.Expr(IR.E.Number, d)
			elseif op == "LOADK" then value = constToIRExpr(proto, d)
			elseif op == "LOADKX" then value = constToIRExpr(proto, aux)
			elseif op == "MOVE" then value = regExpr(b, insn.pc)
			elseif op == "GETGLOBAL" then
				local kc = proto.constants[(aux or 0) + 1]
				local name = kc and kc.kind == "string" and kc.value or "_G"
				value = IR.Expr(IR.E.Global, name)
			elseif op == "GETIMPORT" then value = constToIRExpr(proto, d)
			elseif op == "GETUPVAL" then value = upvalExpr(b)
			elseif op == "GETTABLE" then value = IR.Expr(IR.E.Index, regExpr(b, insn.pc), regExpr(c, insn.pc))
			elseif op == "GETTABLEKS" or op == "GETUDATAKS" then
				local kIdx = op == "GETUDATAKS" and (aux & 0xffff) or aux
				local kc = proto.constants[(kIdx or 0) + 1]
				local key = kc and kc.kind == "string" and kc.value or "?"
				value = IR.Expr(IR.E.Field, regExpr(b, insn.pc), key)
			elseif op == "GETTABLEN" then value = IR.Expr(IR.E.Index, regExpr(b, insn.pc), IR.Expr(IR.E.Number, c + 1))
			elseif op == "GETVARARGS" then value = IR.Expr(IR.E.VarArg)
			end
			if value then
				local name = localNameAt(localMap, a, insn.pc + 1)
				if name then regNames[a] = name end
				nodes[#nodes + 1] = IR.Assign(name or ("r" .. tostring(a)), value, true)
			end

		elseif cat == "Store" then
			if op == "SETGLOBAL" then
				local kc = proto.constants[(aux or 0) + 1]
				local name = kc and kc.kind == "string" and kc.value or "_G"
				nodes[#nodes + 1] = IR.Assign(IR.Expr(IR.E.Global, name), regExpr(a, insn.pc), false)
			elseif op == "SETUPVAL" then
				nodes[#nodes + 1] = IR.Assign(upvalExpr(b), regExpr(a, insn.pc), false)
			elseif op == "SETTABLE" then
				nodes[#nodes + 1] = IR.Assign(IR.Expr(IR.E.Index, regExpr(b, insn.pc), regExpr(c, insn.pc)), regExpr(a, insn.pc), false)
			elseif op == "SETTABLEKS" or op == "SETUDATAKS" then
				local kIdx = op == "SETUDATAKS" and (aux & 0xffff) or aux
				local kc = proto.constants[(kIdx or 0) + 1]
				local key = kc and kc.kind == "string" and kc.value or "?"
				nodes[#nodes + 1] = IR.Assign(IR.Expr(IR.E.Field, regExpr(b, insn.pc), key), regExpr(a, insn.pc), false)
			elseif op == "SETTABLEN" then
				nodes[#nodes + 1] = IR.Assign(IR.Expr(IR.E.Index, regExpr(b, insn.pc), IR.Expr(IR.E.Number, c + 1)), regExpr(a, insn.pc), false)
			end

		elseif cat == "BinaryOp" then
			local irOp = BINARY_OP_MAP[op]
			local left, right
			if op == "SUBRK" or op == "DIVRK" then
				left = constToIRExpr(proto, b)
				right = regExpr(c, insn.pc)
			elseif op:match("K$") then
				left = regExpr(b, insn.pc)
				right = constToIRExpr(proto, c)
			else
				left = regExpr(b, insn.pc)
				right = regExpr(c, insn.pc)
			end
			local value = IR.Expr(IR.E.BinaryOp, irOp, left, right)
			local name = localNameAt(localMap, a, insn.pc + 1)
			if name then regNames[a] = name end
			nodes[#nodes + 1] = IR.Assign(name or ("r" .. tostring(a)), value, true)

		elseif cat == "UnaryOp" then
			local irOp = UNARY_OP_MAP[op]
			local value = IR.Expr(IR.E.UnaryOp, irOp, regExpr(b, insn.pc))
			local name = localNameAt(localMap, a, insn.pc + 1)
			if name then regNames[a] = name end
			nodes[#nodes + 1] = IR.Assign(name or ("r" .. tostring(a)), value, true)

		elseif op == "CONCAT" then
			local parts = {}
			for r = b, c do parts[#parts + 1] = regExpr(r, insn.pc) end
			local value = IR.Expr(IR.E.Concat, table.unpack(parts))
			local name = localNameAt(localMap, a, insn.pc + 1)
			if name then regNames[a] = name end
			nodes[#nodes + 1] = IR.Assign(name or ("r" .. tostring(a)), value, true)

		elseif op == "NEWTABLE" or op == "DUPTABLE" then
			local value = op == "DUPTABLE" and constToIRExpr(proto, d) or IR.Expr(IR.E.TableConst)
			local name = localNameAt(localMap, a, insn.pc + 1)
			if name then regNames[a] = name end
			nodes[#nodes + 1] = IR.Assign(name or ("r" .. tostring(a)), value, true)

		elseif op == "CALL" or op == "CALLFB" then
			local funcExpr = regExpr(a, insn.pc)
			local args = {}
			local argCount = b == 0 and 0 or b - 1
			for r = a + 1, a + argCount do args[#args + 1] = regExpr(r, insn.pc) end
			local resultCount = c == 0 and 1 or c - 1

			if resultCount <= 0 then
				nodes[#nodes + 1] = IR.Call(funcExpr, args, false)
			elseif resultCount == 1 then
				local name = localNameAt(localMap, a, insn.pc + 1)
				if name then regNames[a] = name end
				nodes[#nodes + 1] = IR.Assign(name or ("r" .. tostring(a)), IR.Expr(IR.E.CallExpr, funcExpr, args), true)
			else
				for i = 0, resultCount - 1 do
					local expr = i == 0 and IR.Expr(IR.E.CallExpr, funcExpr, args) or IR.Expr(IR.E.Select, i + 1, IR.Expr(IR.E.CallExpr, funcExpr, args))
					local rn = localNameAt(localMap, a + i, insn.pc + 1)
					if rn then regNames[a + i] = rn end
					nodes[#nodes + 1] = IR.Assign(rn or ("r" .. tostring(a + i)), expr, true)
				end
			end

		elseif op == "RETURN" then
			local count = b == 0 and 1 or b - 1
			local values = {}
			for r = a, a + count - 1 do values[#values + 1] = regExpr(r, insn.pc) end
			nodes[#nodes + 1] = IR.Return(values)

		elseif op == "NAMECALL" or op == "NAMECALLUDATA" then
			-- Method call setup: store method base + name for next CALL
			local kIdx = op == "NAMECALLUDATA" and (aux & 0xffff) or aux
			local kc = proto.constants[(kIdx or 0) + 1]
			local methodName = kc and kc.kind == "string" and kc.value or "?"
			regNames[a] = "__method_" .. methodName
			regNames[a + 1] = regNames[b] or localNameAt(localMap, b, insn.pc) or ("r" .. tostring(b))
		end
	end

	local context = {
		params = params,
		typeInfo = proto.typeinfo and proto.typeinfo.parsed or nil,
		encoding = chunk.encoding and chunk.encoding.name or "stock",
		version = chunk.version,
	}

	return IR.Block(nodes), context
end

return BytecodeParser
