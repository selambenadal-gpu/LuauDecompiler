local IR = require(script.Parent.Parent.IR)

local FOLDABLE_BINARY = {
    ["+"] = function(a, b) return a + b end,
    ["-"] = function(a, b) return a - b end,
    ["*"] = function(a, b) return a * b end,
    ["/"] = function(a, b) return a / b end,
    ["%"] = function(a, b) return a % b end,
    ["^"] = function(a, b) return a ^ b end,
    ["//"] = function(a, b) return math.floor(a / b) end,
}

local function isConstLit(node)
    return node.type == "Expr" and
        (node.kind == IR.E.Number or node.kind == IR.E.String or
         node.kind == IR.E.Bool or node.kind == IR.E.Nil or
         node.kind == IR.E.Integer)
end

local function getLitValue(node)
    if node.kind == IR.E.Number or node.kind == IR.E.Integer then return node.args[1]
    elseif node.kind == IR.E.String then return node.args[1]
    elseif node.kind == IR.E.Bool then return node.args[1]
    elseif node.kind == IR.E.Nil then return nil
    end
end

local function foldNode(node)
    if node.type == "Expr" and node.kind == IR.E.BinaryOp then
        local op, left, right = node.args[1], node.args[2], node.args[3]
        if isConstLit(left) and isConstLit(right) and FOLDABLE_BINARY[op] then
            local ok, result = pcall(FOLDABLE_BINARY[op], getLitValue(left), getLitValue(right))
            if ok and type(result) == "number" then
                return IR.Expr(IR.E.Number, result)
            end
        end
    end
    return node
end

local function walkAndFold(node)
    if type(node) ~= "table" then return node end

    -- Recurse into children first (bottom-up)
    if node.type == "Block" then
        for i, child in ipairs(node.children) do
            node.children[i] = walkAndFold(child)
        end
    elseif node.type == "Assign" then
        node.value = walkAndFold(node.value)
    elseif node.type == "If" then
        node.condition = walkAndFold(node.condition)
        node.thenBlock = walkAndFold(node.thenBlock)
        if node.elseBlock then node.elseBlock = walkAndFold(node.elseBlock) end
    elseif node.type == "While" then
        node.condition = walkAndFold(node.condition)
        node.body = walkAndFold(node.body)
    elseif node.type == "Return" then
        for i, v in ipairs(node.values) do node.values[i] = walkAndFold(v) end
    elseif node.type == "Expr" then
        for i, arg in ipairs(node.args) do
            node.args[i] = walkAndFold(arg)
        end
    end

    return foldNode(node)
end

return function(irTree, _context)
    return walkAndFold(irTree)
end
