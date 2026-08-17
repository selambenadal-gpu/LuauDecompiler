local Operands = {}

function Operands.A(instruction)
	return instruction.A
end

function Operands.ABC(instruction)
	return instruction.A, instruction.B, instruction.C
end

function Operands.AD(instruction)
	return instruction.A, instruction.D
end

function Operands.E(instruction)
	return instruction.E
end

return Operands
