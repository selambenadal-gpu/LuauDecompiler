local Proto = {}
Proto.__index = Proto

function Proto.new()
	return setmetatable({
		maxstacksize = 0,
		numparams = 0,
		isvararg = false,

		code = {},
		constants = {},
		children = {},

		lineinfo = {},
		locvars = {},
		upvalues = {},

		flags = 0,
		typeinfo = nil,

		-- v11+
		feedback = nil,

		-- v12+
		cost = nil,
		size = nil,
	}, Proto)
end

function Proto:addInstruction(instruction)
	self.code[#self.code + 1] = instruction
end

function Proto:addConstant(constant)
	self.constants[#self.constants + 1] = constant
end

function Proto:addChild(child)
	self.children[#self.children + 1] = child
end

function Proto:addUpvalue(upvalue)
	self.upvalues[#self.upvalues + 1] = upvalue
end

function Proto:isMain()
	return self.parent == nil
end

return Proto
