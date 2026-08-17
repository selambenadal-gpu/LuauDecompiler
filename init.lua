local PassManager = require(script.PassManager)
local BackendLua = require(script.BackendLua)
local IR = require(script.IR)
local BytecodeParser = require(script.BytecodeParser)
local Util = require(script.Util)

-- Pass'leri lazy load et
local function loadPasses()
	return {
		{ name = "ConstantFold", fn = require(script.passes.ConstantFold) },
		{ name = "TypeAnnotate", fn = require(script.passes.TypeAnnotate) },
		{ name = "RobloxBuiltin", fn = require(script.passes.RobloxBuiltin) },
	}
end

local Decompiler = {}

--- IR ağacını optimize edip Luau source code'a çevirir
--- @param irTree table - IR.Block node
--- @param context table? - { params, typeInfo }
--- @param options table? - { disablePasses = {"ConstantFold"} }
--- @return string source, table stats
function Decompiler.decompile(irTree, context, options)
	options = options or {}

	-- Build pass pipeline
	local pm = PassManager.new()
	local passes = loadPasses()
	for _, pass in ipairs(passes) do
		local enabled = true
		if options.disablePasses then
			for _, disabled in ipairs(options.disablePasses) do
				if disabled == pass.name then
					enabled = false
					break
				end
			end
		end
		pm:addPass(pass.name, pass.fn, { enabled = enabled })
	end

	-- Run optimization passes
	local optimizedIR, stats = pm:run(irTree, context)

	-- Emit source code
	local source = BackendLua.emit(optimizedIR, context and context.params)

	return source, stats
end

--- Raw bytecode string'den direkt source code üretir (Full Pipeline)
--- @param bytecodeData string - Raw Luau bytecode bytes
--- @param options table? - { encoding, disablePasses }
--- @return string source
function Decompiler.decompileBytecode(bytecodeData, options)
	local ok, result = pcall(function()
		options = options or {}

		-- 1. Parse bytecode → Chunk
		local chunk = BytecodeParser.parse(bytecodeData, {
			encoding = options.encoding or "auto",
		})

		-- 2. Main proto'yu bul
		local mainProto = chunk.protos[(chunk.mainProto or 0) + 1] or chunk.protos[1]
		if not mainProto then
			return "-- [Decompiler Error] No main proto found\nreturn nil"
		end

		-- 3. Proto → IR tree
		local irTree, irContext = BytecodeParser.protoToIR(chunk, mainProto)

		-- 4. Optimize + Emit
		local source, _stats = Decompiler.decompile(irTree, irContext, options)
		return source
	end)

	if not ok then
		return "-- [Decompiler Error] " .. tostring(result) .. "\nreturn nil"
	end
	return result
end

--- Script instance veya bytecode string kabul eden executor-friendly API
--- @param input Instance|string - LuaSourceContainer veya raw bytecode
--- @param options table? - { encoding, disablePasses }
--- @return string source
function Decompiler.decompileScript(input, options)
	local bytecode

	if typeof(input) == "Instance" and input:IsA("LuaSourceContainer") then
		if getscriptbytecode then
			bytecode = getscriptbytecode(input)
		elseif getbytecode then
			bytecode = getbytecode(input)
		else
			error("getscriptbytecode veya getbytecode bulunamadı. Executor'unuz bu API'yi desteklemiyor.")
		end
	elseif type(input) == "string" then
		bytecode = input
	else
		error("Geçersiz input. Script instance veya bytecode string bekleniyor.")
	end

	return Decompiler.decompileBytecode(bytecode, options)
end

-- ========== EXECUTOR BOOTSTRAP ==========
if getgenv then
	getgenv().decompile = Decompiler.decompileScript
	getgenv().Decompiler = Decompiler
	getgenv().IR = IR
end

return Decompiler
