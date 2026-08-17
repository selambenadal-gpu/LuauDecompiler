local Versions = {}

Versions.MIN_SUPPORTED = 1
Versions.MAX_KNOWN = 11
Versions.TYPE_VERSION_MIN = 1
Versions.TYPE_VERSION_MAX = 3

-- YENİ: Type tag → Luau type name mapping (TypeAnnotate pass kullanır)
Versions.TypeNames = {
	[0] = "nil", [1] = "boolean", [2] = "number", [3] = "string",
	[4] = "table", [5] = "function", [6] = "thread", [7] = "userdata",
	[8] = "vector", [9] = "buffer", [10] = "any",
}

function Versions.resolveTypeName(typeTag)
	return Versions.TypeNames[typeTag] or "any"
end

-- YENİ: Versiyona göre mevcut olan IR-relevant feature'ları döndürür
function Versions.getIRCapabilities(version)
	local info = Versions.get(version)
	return {
		hasIntegerConstants = info.hasIntegerConstants or false,
		hasVectorConstants = info.hasVectorConstants or false,
		hasTableWithConstants = info.hasTableWithConstants or false,
		hasUserdataOps = info.hasUserdataOps or false,
		hasClassShape = info.hasClassShape or false,
		hasFeedback = info.hasFeedback or false,
		hasTypeInfo = info.hasTypeInfo or false,
		typeVersionMax = info.typeVersionMax or 0,
	}
end

local capabilityDefaults = {
	hasLineDefined = false, hasTypeVersion = false, hasProtoFlags = false,
	hasTypeInfo = false, hasFeedback = false, hasVectorConstants = false,
	hasTableWithConstants = false, hasIntegerConstants = false,
	hasUserdataOps = false, hasClassShape = false, hasUserdataTypeNames = false,
	typeVersionMin = nil, typeVersionMax = nil,
}

local v1OpcodeIds = {
	"NOP", "BREAK", "LOADNIL", "LOADB", "LOADN", "LOADK", "MOVE",
	"GETGLOBAL", "SETGLOBAL", "GETUPVAL", "SETUPVAL", "CLOSEUPVALS",
	"GETIMPORT", "GETTABLE", "SETTABLE", "GETTABLEKS", "SETTABLEKS",
	"GETTABLEN", "SETTABLEN", "NEWCLOSURE", "NAMECALL", "CALL", "RETURN",
	"JUMP", "JUMPBACK", "JUMPIF", "JUMPIFNOT", "JUMPIFEQ", "JUMPIFLE",
	"JUMPIFLT", "JUMPIFNOTEQ", "JUMPIFNOTLE", "JUMPIFNOTLT", "ADD", "SUB",
	"MUL", "DIV", "MOD", "POW", "ADDK", "SUBK", "MULK", "DIVK", "MODK",
	"POWK", "AND", "OR", "ANDK", "ORK", "CONCAT", "NOT", "MINUS", "LENGTH",
	"NEWTABLE", "DUPTABLE", "SETLIST", "FORNPREP", "FORNLOOP", "FORGLOOP",
	"FORGPREP_INEXT", "FORGLOOP_INEXT", "FORGPREP_NEXT", "FORGLOOP_NEXT",
	"GETVARARGS", "DUPCLOSURE", "PREPVARARGS", "LOADKX", "JUMPX", "FASTCALL",
	"COVERAGE", "CAPTURE", "JUMPIFEQK", "JUMPIFNOTEQK", "FASTCALL1",
	"FASTCALL2", "FASTCALL2K",
}

local v2OpcodeIds = {}
for i, v in ipairs(v1OpcodeIds) do v2OpcodeIds[i] = v end
v2OpcodeIds[77] = "FORGPREP"
v2OpcodeIds[78] = "JUMPXEQKNIL"
v2OpcodeIds[79] = "JUMPXEQKB"
v2OpcodeIds[80] = "JUMPXEQKN"
v2OpcodeIds[81] = "JUMPXEQKS"

local versionDeltas = {
	[1] = { description = "open-source baseline", constants = {0,1,2,3,4,5,6}, opcodes = v1OpcodeIds, opcodeIds = v1OpcodeIds },
	[2] = { description = "Proto::linedefined", features = {hasLineDefined = true}, opcodes = {"FORGPREP","JUMPXEQKNIL","JUMPXEQKB","JUMPXEQKN","JUMPXEQKS"}, opcodeIds = v2OpcodeIds },
	[3] = { description = "FORGPREP/JUMPXEQK formal", opcodes = {"NATIVECALL"}, removeOpcodes = {"FORGLOOP_INEXT","FORGLOOP_NEXT","JUMPIFEQK","JUMPIFNOTEQK"}, resetOpcodeIds = true },
	[4] = { description = "proto flags, typeinfo, IDIV", features = {hasTypeVersion=true,hasProtoFlags=true,hasTypeInfo=true,typeVersionMin=1,typeVersionMax=2}, opcodes = {"IDIV","IDIVK"} },
	[5] = { description = "SUBRK/DIVRK and vector", features = {hasVectorConstants=true,hasUserdataTypeNames=true,typeVersionMax=3}, constants = {7}, opcodes = {"SUBRK","DIVRK"} },
	[6] = { description = "FASTCALL3", opcodes = {"FASTCALL3"} },
	[7] = { description = "table constants", features = {hasTableWithConstants=true}, constants = {8} },
	[8] = { description = "integer constants", features = {hasIntegerConstants=true}, constants = {9} },
	[9] = { description = "userdata field", features = {hasUserdataOps=true}, opcodes = {"GETUDATAKS","SETUDATAKS","NAMECALLUDATA"} },
	[10] = { description = "class shape", features = {hasClassShape=true}, constants = {10}, opcodes = {"NEWCLASSMEMBER"} },
	[11] = { description = "call feedback", features = {hasFeedback=true}, opcodes = {"CALLFB","CMPPROTO"} },
}

local byVersion = {}
local constantMinVersion = {}
local opcodeMinVersion = {}

local function copyMap(source)
	local result = {}
	for key, value in pairs(source or {}) do result[key] = value end
	return result
end

local function copyList(source)
	local result = {}
	for i, value in ipairs(source or {}) do result[i] = value end
	return result
end

local function highestTag(tags)
	local highest = nil
	for tag in pairs(tags or {}) do
		if highest == nil or tag > highest then highest = tag end
	end
	return highest
end

local function baseInfo(version)
	local info = copyMap(capabilityDefaults)
	info.version = version
	info.known = false
	info.description = "future/unknown"
	info.constantTags = {}
	info.opcodeNames = {}
	info.opcodeIds = {}
	info.introducedConstants = {}
	info.introducedOpcodes = {}
	info.removedOpcodes = {}
	info.maxConstantTag = nil
	return info
end

local current = baseInfo(Versions.MIN_SUPPORTED)
for version = Versions.MIN_SUPPORTED, Versions.MAX_KNOWN do
	local delta = versionDeltas[version]
	local info = copyMap(current)
	info.version = version
	info.known = true
	info.description = delta.description
	info.constantTags = copyMap(current.constantTags)
	info.opcodeNames = copyMap(current.opcodeNames)
	if delta.resetOpcodeIds then
		info.opcodeIds = {}
	else
		info.opcodeIds = delta.opcodeIds and copyList(delta.opcodeIds) or copyList(current.opcodeIds)
	end
	info.introducedConstants = copyList(delta.constants)
	info.introducedOpcodes = copyList(delta.opcodes)
	info.removedOpcodes = copyList(delta.removeOpcodes)
	for key, value in pairs(delta.features or {}) do info[key] = value end
	for _, tag in ipairs(delta.constants or {}) do
		info.constantTags[tag] = true
		constantMinVersion[tag] = version
	end
	for _, opcodeName in ipairs(delta.opcodes or {}) do
		info.opcodeNames[opcodeName] = true
		if opcodeMinVersion[opcodeName] == nil then opcodeMinVersion[opcodeName] = version end
	end
	for _, opcodeName in ipairs(delta.removeOpcodes or {}) do info.opcodeNames[opcodeName] = nil end
	info.maxConstantTag = highestTag(info.constantTags)
	byVersion[version] = info
	current = info
end

local function unknownInfo(version)
	if type(version) == "number" and version > Versions.MAX_KNOWN then
		local info = copyMap(byVersion[Versions.MAX_KNOWN])
		info.version = version
		info.known = false
		info.description = "future/unknown"
		info.constantTags = copyMap(info.constantTags)
		info.opcodeNames = copyMap(info.opcodeNames)
		info.opcodeIds = copyList(info.opcodeIds)
		info.introducedConstants = {}
		info.introducedOpcodes = {}
		info.removedOpcodes = {}
		return info
	end
	return baseInfo(version or 0)
end

function Versions.get(version) return byVersion[version] or unknownInfo(version) end
function Versions.isSourceTextMarker(version) return version == 0 end
function Versions.bytecodeVersionSupported(version) return type(version) == "number" and version >= Versions.MIN_SUPPORTED and version <= Versions.MAX_KNOWN end
function Versions.unsupportedBytecodeVersionMessage(version) return ("unsupported Luau bytecode version v%d; supported versions are v%d-v%d"):format(version or -1, Versions.MIN_SUPPORTED, Versions.MAX_KNOWN) end
function Versions.hasTypeVersion(version) return Versions.get(version).hasTypeVersion end
function Versions.hasLineDefined(version) return Versions.get(version).hasLineDefined end
function Versions.hasProtoFlags(version) return Versions.get(version).hasProtoFlags end
function Versions.hasTypeInfo(version) return Versions.get(version).hasTypeInfo end
function Versions.hasFeedback(version) return Versions.get(version).hasFeedback end
function Versions.hasUserdataTypeNames(version, typeVersion) local info = Versions.get(version); return info.hasUserdataTypeNames == true and typeVersion == 3 end
function Versions.typeInfoPayloadEncoding(typeVersion) if typeVersion == 1 then return "legacy-v1-function" end; if typeVersion == 2 or typeVersion == 3 then return "v2-v3-envelope" end; return "unknown" end
function Versions.typeVersionAllowed(typeVersion) return type(typeVersion) == "number" and typeVersion >= Versions.TYPE_VERSION_MIN and typeVersion <= Versions.TYPE_VERSION_MAX end
function Versions.typeVersionAllowedForBytecode(version, typeVersion) local info = Versions.get(version); if not info.hasTypeVersion then return typeVersion == nil or typeVersion == 0 end; return type(typeVersion) == "number" and typeVersion >= (info.typeVersionMin or Versions.TYPE_VERSION_MIN) and typeVersion <= (info.typeVersionMax or Versions.TYPE_VERSION_MAX) end
function Versions.bytecodeHeaderLooksValid(version, typeVersion) if Versions.isSourceTextMarker(version) then return true end; if not Versions.bytecodeVersionSupported(version) then return false end; local info = Versions.get(version); if not info.hasTypeVersion then return true end; return Versions.typeVersionAllowedForBytecode(version, typeVersion) end
function Versions.bytecodeHeaderLooksLikeLuau(version, typeVersion) if Versions.isSourceTextMarker(version) then return true end; if type(version) ~= "number" or version < Versions.MIN_SUPPORTED then return false end; if version > Versions.MAX_KNOWN then return Versions.typeVersionAllowed(typeVersion) end; return Versions.bytecodeHeaderLooksValid(version, typeVersion) end
function Versions.constantTagAllowed(version, tag) return Versions.get(version).constantTags[tag] == true end
function Versions.constantMinVersion(tag) return constantMinVersion[tag] end
function Versions.opcodeName(version, op) if type(op) ~= "number" then return nil end; local info = Versions.get(version); return info.opcodeIds and info.opcodeIds[op + 1] or nil end
function Versions.opcodeAllowed(version, opcodeName) if type(opcodeName) == "string" and opcodeName:match("^OP_%d+$") then return false end; local minVersion = opcodeMinVersion[opcodeName]; if minVersion == nil then return false end; return Versions.get(version).opcodeNames[opcodeName] == true end
function Versions.opcodeMinVersion(opcodeName) return opcodeMinVersion[opcodeName] end

return Versions
