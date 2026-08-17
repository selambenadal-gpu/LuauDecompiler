local Opcode = require(script.Parent.Opcode)
local Versions = require(script.Parent.Versions)

local Encodings = {}

-- ========== ROBLOX ENCODING MAP ==========
local function buildRobloxMap()
	local map = {}
	for id = 0, #Opcode.names - 1 do
		map[(id * 227) & 0xff] = id
	end
	return map
end

local function buildReverseMap(map)
	local reverse = {}
	for rawOp, officialOp in pairs(map or {}) do reverse[officialOp] = rawOp end
	return reverse
end

local stock = { name = "stock" }
local roblox = { name = "roblox", map = buildRobloxMap() }
roblox.reverseMap = buildReverseMap(roblox.map)

Encodings.registry = { stock = stock, roblox = roblox }

function Encodings.get(name) return Encodings.registry[name or "stock"] end

function Encodings.decodeRawOp(rawOp, encoding)
	if encoding and encoding.map then return encoding.map[rawOp] end
	return rawOp
end

function Encodings.encodeOp(op, encoding)
	if encoding and encoding.reverseMap then return encoding.reverseMap[op] end
	return op
end

-- ========== SCORING SYSTEM (IR Metadata Uyumlu) ==========
local function addIssue(score, field, amount)
	score[field] = score[field] + (amount or 1)
end

local function constantAt(proto, index)
	if not proto or index == nil or index < 0 then return nil end
	return proto.constants and proto.constants[index + 1] or nil
end

local function kindMatches(kind, expected)
	if expected == nil then return true end
	if type(expected) == "string" then return kind == expected end
	for _, item in ipairs(expected) do if kind == item then return true end end
	return false
end

local function checkConstant(score, proto, index, expected)
	if not proto then return end
	local constant = constantAt(proto, index)
	if not constant or not kindMatches(constant.kind, expected) then
		addIssue(score, "constantIssues")
	end
end

local function checkImportAux(score, proto, aux)
	if not proto or aux == nil then return end
	local count, id0, id1, id2 = Opcode.decodeImportId(aux)
	if count < 1 or count > 3 then addIssue(score, "constantIssues"); return end
	for _, index in ipairs({ id0, id1, id2 }) do
		if index ~= nil then checkConstant(score, proto, index, "string") end
	end
end

local function checkReg(score, proto, reg)
	if not proto or type(proto.maxstacksize) ~= "number" then return end
	if reg == nil or reg < 0 or reg >= proto.maxstacksize then
		addIssue(score, "registerIssues")
	end
end

local function checkRegRange(score, proto, firstReg, lastReg)
	if not proto or firstReg == nil or lastReg == nil then return end
	for reg = firstReg, lastReg do checkReg(score, proto, reg) end
end

local function checkUpvalue(score, proto, index)
	if not proto or type(proto.numupvalues) ~= "number" then return end
	if index == nil or index < 0 or index >= proto.numupvalues then
		addIssue(score, "upvalueIssues")
	end
end

local function checkChild(score, proto, index)
	if not proto or not proto.children then return end
	if index == nil or index < 0 or index >= #proto.children then
		addIssue(score, "childIssues")
	end
end

local function checkFeedback(score, proto, aux)
	if not proto or aux == nil or aux == 0xffffffff then return end
	if not proto.feedback or aux < 0 or aux >= #proto.feedback then
		addIssue(score, "feedbackIssues")
	end
end

local function checkTarget(score, pcStarts, sizecode, target)
	if target == nil then return end
	if target < 0 or target > sizecode or (target < sizecode and not pcStarts[target]) then
		addIssue(score, "jumpIssues")
	end
end

-- YENİ: Opcode.Category kullanarak operand validation
local function checkInstructionOperands(score, proto, insn)
	if not proto then return end
	local op = insn.opname
	local a, b, c, d = insn.A, insn.B, insn.C, insn.D
	local aux = insn.aux
	local cat = Opcode.getCategory(op)

	-- Category-based validation (eski devasa if-else zinciri yerine)
	if cat == "Load" then
		checkReg(score, proto, a)
		if op == "LOADK" or op == "LOADKX" then
			checkConstant(score, proto, op == "LOADKX" and aux or d)
		elseif op == "GETGLOBAL" or op == "SETGLOBAL" then
			checkConstant(score, proto, aux, "string")
		elseif op == "GETIMPORT" then
			checkConstant(score, proto, d, "import")
			checkImportAux(score, proto, aux)
		elseif op == "GETUPVAL" then
			checkUpvalue(score, proto, b)
		elseif op == "GETTABLE" then
			checkReg(score, proto, b); checkReg(score, proto, c)
		elseif op == "GETTABLEKS" or op == "GETUDATAKS" then
			checkReg(score, proto, b)
			local kIdx = op == "GETUDATAKS" and (aux & 0xffff) or aux
			checkConstant(score, proto, kIdx, "string")
		elseif op == "GETTABLEN" then
			checkReg(score, proto, b)
		elseif op == "MOVE" then
			checkReg(score, proto, b)
		end

	elseif cat == "Store" then
		if op == "SETUPVAL" then
			checkReg(score, proto, a); checkUpvalue(score, proto, b)
		elseif op == "SETTABLE" then
			checkReg(score, proto, a); checkReg(score, proto, b); checkReg(score, proto, c)
		elseif op == "SETTABLEKS" or op == "SETUDATAKS" then
			checkReg(score, proto, a); checkReg(score, proto, b)
			local kIdx = op == "SETUDATAKS" and (aux & 0xffff) or aux
			checkConstant(score, proto, kIdx, "string")
		elseif op == "SETTABLEN" then
			checkReg(score, proto, a); checkReg(score, proto, b)
		end

	elseif cat == "BinaryOp" then
		checkReg(score, proto, a)
		if op == "SUBRK" or op == "DIVRK" then
			checkConstant(score, proto, b); checkReg(score, proto, c)
		elseif op:match("K$") then
			checkReg(score, proto, b); checkConstant(score, proto, c)
		else
			checkReg(score, proto, b); checkReg(score, proto, c)
		end

	elseif cat == "UnaryOp" then
		checkReg(score, proto, a); checkReg(score, proto, b)

	elseif cat == "Call" then
		checkReg(score, proto, a)
		if op == "NAMECALL" or op == "NAMECALLUDATA" then
			checkReg(score, proto, a + 1); checkReg(score, proto, b)
			local kIdx = op == "NAMECALLUDATA" and (aux & 0xffff) or aux
			checkConstant(score, proto, kIdx, "string")
		elseif op == "CALL" or op == "CALLFB" then
			if b > 0 then checkRegRange(score, proto, a + 1, a + b - 1) end
			if c > 1 then checkRegRange(score, proto, a, a + c - 2) end
			if op == "CALLFB" then checkFeedback(score, proto, aux) end
		end

	elseif cat == "Return" then
		if b == 0 then checkReg(score, proto, a)
		elseif b > 1 then checkRegRange(score, proto, a, a + b - 2) end

	elseif cat == "Compare" then
		checkReg(score, proto, a)
		if aux ~= nil then checkReg(score, proto, aux) end

	elseif cat == "Closure" then
		checkReg(score, proto, a)
		if op == "NEWCLOSURE" then checkChild(score, proto, d)
		elseif op == "DUPCLOSURE" then checkConstant(score, proto, d, "closure") end

	elseif cat == "Table" then
		checkReg(score, proto, a)
		if op == "DUPTABLE" then
			checkConstant(score, proto, d, { "table", "table_with_constants" })
		elseif op == "SETLIST" then
			if c > 1 then checkRegRange(score, proto, b, b + c - 2) end
		end

	elseif cat == "Loop" then
		if op == "FORNPREP" or op == "FORNLOOP" then
			checkRegRange(score, proto, a, a + 2)
		elseif op:match("^FORG") then
			checkRegRange(score, proto, a, a + 2)
		end

	elseif cat == "Capture" then
		if a == 0 or a == 1 then checkReg(score, proto, b)
		elseif a == 2 then checkUpvalue(score, proto, b)
		else addIssue(score, "operandIssues") end

	elseif cat == "FastCall" then
		if op == "FASTCALL1" then checkReg(score, proto, b)
		elseif op == "FASTCALL2" then checkReg(score, proto, b)
		elseif op == "FASTCALL2K" then checkReg(score, proto, b); checkConstant(score, proto, aux)
		elseif op == "FASTCALL3" then checkReg(score, proto, b) end
	end
end

function Encodings.score(words, encoding, versionInfo, proto)
	local score = {
		encoding = encoding.name, unknownOps = 0, disallowedOps = 0, truncatedAux = 0,
		registerIssues = 0, constantIssues = 0, jumpIssues = 0, childIssues = 0,
		upvalueIssues = 0, feedbackIssues = 0, operandIssues = 0, decodedInstructions = 0,
		rawOps = {},
	}
	local index = 1
	local version = versionInfo and versionInfo.version or 0
	local decoded = {}
	local pcStarts = {}

	while index <= #words do
		local rawOp = words[index] & 0xff
		local decodedOp = Encodings.decodeRawOp(rawOp, encoding)
		local opcodeName = decodedOp ~= nil and (Versions.opcodeName(version, decodedOp) or Opcode.name(decodedOp)) or nil
		score.rawOps[rawOp] = (score.rawOps[rawOp] or 0) + 1

		if decodedOp == nil or not Opcode.names[decodedOp + 1] then
			score.unknownOps = score.unknownOps + 1
			index = index + 1
		else
			if not Versions.opcodeAllowed(version, opcodeName) then
				score.disallowedOps = score.disallowedOps + 1
			end
			local length = Opcode.lengthByName(opcodeName)
			local op, a, b, c, d, e = Opcode.decodeWord(words[index], decodedOp)
			local insn = {
				pc = index - 1, rawOp = rawOp, op = op, opname = opcodeName,
				A = a, B = b, C = c, D = d, E = e, length = length,
			}
			if length == 2 and index == #words then
				score.truncatedAux = score.truncatedAux + 1
				index = index + 1
			else
				insn.aux = length == 2 and words[index + 1] or nil
				insn.target = Opcode.jumpTarget(insn)
				pcStarts[insn.pc] = true
				decoded[#decoded + 1] = insn
				checkInstructionOperands(score, proto, insn)
				index = index + length
			end
			score.decodedInstructions = score.decodedInstructions + 1
		end
	end

	for _, insn in ipairs(decoded) do
		checkTarget(score, pcStarts, #words, insn.target)
	end

	score.penalty = score.unknownOps * 1000 + score.truncatedAux * 200 +
		score.jumpIssues * 120 + score.constantIssues * 80 + score.childIssues * 70 +
		score.registerIssues * 60 + score.upvalueIssues * 60 + score.feedbackIssues * 50 +
		score.operandIssues * 25 + score.disallowedOps * 20
	return score
end

local function mergeScore(total, score)
	for _, field in ipairs({ "unknownOps", "disallowedOps", "truncatedAux", "registerIssues",
		"constantIssues", "jumpIssues", "childIssues", "upvalueIssues", "feedbackIssues",
		"operandIssues", "decodedInstructions" }) do
		total[field] = total[field] + score[field]
	end
	for rawOp, count in pairs(score.rawOps) do
		total.rawOps[rawOp] = (total.rawOps[rawOp] or 0) + count
	end
end

function Encodings.scoreProtos(protos, encoding, versionInfo)
	local total = {
		encoding = encoding.name, unknownOps = 0, disallowedOps = 0, truncatedAux = 0,
		registerIssues = 0, constantIssues = 0, jumpIssues = 0, childIssues = 0,
		upvalueIssues = 0, feedbackIssues = 0, operandIssues = 0,
		decodedInstructions = 0, rawOps = {},
	}
	for _, proto in ipairs(protos or {}) do
		local score = Encodings.score(proto.code or {}, encoding, versionInfo, proto)
		mergeScore(total, score)
	end
	total.penalty = total.unknownOps * 1000 + total.truncatedAux * 200 +
		total.jumpIssues * 120 + total.constantIssues * 80 + total.childIssues * 70 +
		total.registerIssues * 60 + total.upvalueIssues * 60 + total.feedbackIssues * 50 +
		total.operandIssues * 25 + total.disallowedOps * 20
	return total
end

function Encodings.choose(words, versionInfo, options)
	local requested = type(options) == "string" and options or (type(options) == "table" and options.encoding or "auto")
	if requested ~= "auto" then
		local encoding = Encodings.get(requested)
		if not encoding then error("unknown bytecode instruction encoding: " .. tostring(requested), 2) end
		return encoding, Encodings.score(words, encoding, versionInfo)
	end
	local bestEncoding = stock
	local bestScore = Encodings.score(words, stock, versionInfo)
	for name, encoding in pairs(Encodings.registry) do
		if name ~= "stock" then
			local score = Encodings.score(words, encoding, versionInfo)
			if score.penalty < bestScore.penalty then bestEncoding = encoding; bestScore = score end
		end
	end
	return bestEncoding, bestScore
end

function Encodings.chooseForProtos(protos, versionInfo, options)
	local requested = type(options) == "string" and options or (type(options) == "table" and options.encoding or "auto")
	if requested ~= "auto" then
		local encoding = Encodings.get(requested)
		if not encoding then error("unknown bytecode instruction encoding: " .. tostring(requested), 2) end
		return encoding, Encodings.scoreProtos(protos, encoding, versionInfo)
	end
	local bestEncoding = stock
	local bestScore = Encodings.scoreProtos(protos, stock, versionInfo)
	for name, encoding in pairs(Encodings.registry) do
		if name ~= "stock" then
			local score = Encodings.scoreProtos(protos, encoding, versionInfo)
			if score.penalty < bestScore.penalty then bestEncoding = encoding; bestScore = score end
		end
	end
	return bestEncoding, bestScore
end

return Encodings
