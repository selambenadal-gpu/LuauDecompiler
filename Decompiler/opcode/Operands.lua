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

function Operands.AUX(instruction)
	return instruction.A, instruction.aux
end

function Operands.decode(instruction)
	local format = instruction.format

	if format == "A" then
		return Operands.A(instruction)
	elseif format == "ABC" then
		return Operands.ABC(instruction)
	elseif format == "AD" then
		return Operands.AD(instruction)
	elseif format == "E" then
		return Operands.E(instruction)
	elseif format == "AUX" then
		return Operands.AUX(instruction)
	end

	error(("Unsupported operand format: %s"):format(tostring(format)))
end

return Operands
