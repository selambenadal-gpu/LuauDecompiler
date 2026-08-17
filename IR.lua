--[[
    IR Node Types:
    - Assign: target, value, isLocal
    - Expr: kind, ...args
    - Block: children[]
    - If: condition, thenBlock, elseBlock
    - While: condition, body
    - Repeat: body, condition
    - ForNum: var, start, limit, step, body
    - ForGen: vars[], iterator, body
    - Return: values[]
    - Call: func, args[], multret
    - Nop: (dead code placeholder)
]]

local IR = {}

function IR.Assign(target, value, isLocal)
    return { type = "Assign", target = target, value = value, isLocal = isLocal }
end

function IR.Expr(kind, ...)
    return { type = "Expr", kind = kind, args = {...} }
end

function IR.Block(children)
    return { type = "Block", children = children or {} }
end

function IR.If(condition, thenBlock, elseBlock)
    return { type = "If", condition = condition, thenBlock = thenBlock, elseBlock = elseBlock }
end

function IR.While(condition, body)
    return { type = "While", condition = condition, body = body }
end

function IR.Repeat(body, condition)
    return { type = "Repeat", body = body, condition = condition }
end

function IR.ForNum(var, start, limit, step, body)
    return { type = "ForNum", var = var, start = start, limit = limit, step = step, body = body }
end

function IR.ForGen(vars, iterator, body)
    return { type = "ForGen", vars = vars, iterator = iterator, body = body }
end

function IR.Return(values)
    return { type = "Return", values = values or {} }
end

function IR.Call(func, args, multret)
    return { type = "Call", func = func, args = args or {}, multret = multret }
end

function IR.Nop()
    return { type = "Nop" }
end

-- Expression kinds
IR.E = {
    Nil = "Nil", Bool = "Bool", Number = "Number", String = "String",
    Integer = "Integer", Vector = "Vector", VarArg = "VarArg",
    Local = "Local", Upvalue = "Upvalue", Global = "Global",
    Index = "Index", Field = "Field", Import = "Import",
    BinaryOp = "BinaryOp", UnaryOp = "UnaryOp", Concat = "Concat",
    TableConst = "TableConst", Closure = "Closure", CallExpr = "CallExpr",
    Select = "Select", MethodCall = "MethodCall",
}

return IR
