local IR = require(script.Parent.Parent.IR)

local TYPE_NAMES = {
    [0] = "nil", [1] = "boolean", [2] = "number", [3] = "string",
    [4] = "table", [5] = "function", [6] = "thread", [7] = "userdata",
    [8] = "vector", [9] = "buffer", [10] = "any",
}

local function annotateAssign(node, typeInfo)
    if node.type ~= "Assign" or not node.isLocal then return node end
    local reg = node.target
    if type(reg) == "table" and reg.type == "Expr" and reg.kind == IR.E.Local then
        local regId = reg.args[1]
        local typeEntry = typeInfo and typeInfo.locals and typeInfo.locals[regId]
        if typeEntry and TYPE_NAMES[typeEntry.type] then
            node.typeAnnotation = TYPE_NAMES[typeEntry.type]
        end
    end
    return node
end

local function walkAndAnnotate(node, typeInfo)
    if type(node) ~= "table" then return node end

    if node.type == "Block" then
        for i, child in ipairs(node.children) do
            node.children[i] = walkAndAnnotate(child, typeInfo)
        end
    elseif node.type == "Assign" then
        node.value = walkAndAnnotate(node.value, typeInfo)
        annotateAssign(node, typeInfo)
    elseif node.type == "If" then
        node.condition = walkAndAnnotate(node.condition, typeInfo)
        node.thenBlock = walkAndAnnotate(node.thenBlock, typeInfo)
        if node.elseBlock then node.elseBlock = walkAndAnnotate(node.elseBlock, typeInfo) end
    elseif node.type == "While" then
        node.condition = walkAndAnnotate(node.condition, typeInfo)
        node.body = walkAndAnnotate(node.body, typeInfo)
    end

    return node
end

return function(irTree, context)
    local typeInfo = context and context.typeInfo
    if not typeInfo then return irTree end
    return walkAndAnnotate(irTree, typeInfo)
end
