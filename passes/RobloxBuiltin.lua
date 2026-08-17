local IR = require(script.Parent.Parent.IR)

-- Bilinen Roblox import path'leri → kısa isimler
local KNOWN_IMPORTS = {
    ["game:GetService"] = true,
    ["workspace"] = true,
    ["script"] = true,
    ["task"] = true,
    ["math"] = true,
    ["table"] = true,
    ["string"] = true,
    ["coroutine"] = true,
    ["bit32"] = true,
    ["utf8"] = true,
    ["os"] = true,
    ["debug"] = true,
}

local function resolveImport(node)
    if node.type ~= "Expr" or node.kind ~= IR.E.Import then return node end
    local parts = node.args[1]
    if type(parts) == "table" then
        local path = table.concat(parts, ":")
        if KNOWN_IMPORTS[path] then
            return IR.Expr(IR.E.Global, path)
        end
    end
    return node
end

local function walkAndResolve(node)
    if type(node) ~= "table" then return node end

    if node.type == "Block" then
        for i, child in ipairs(node.children) do
            node.children[i] = walkAndResolve(child)
        end
    elseif node.type == "Assign" then
        node.value = walkAndResolve(node.value)
    elseif node.type == "Expr" then
        for i, arg in ipairs(node.args) do
            node.args[i] = walkAndResolve(arg)
        end
        return resolveImport(node)
    elseif node.type == "If" then
        node.condition = walkAndResolve(node.condition)
        node.thenBlock = walkAndResolve(node.thenBlock)
        if node.elseBlock then node.elseBlock = walkAndResolve(node.elseBlock) end
    elseif node.type == "While" then
        node.condition = walkAndResolve(node.condition)
        node.body = walkAndResolve(node.body)
    elseif node.type == "Return" then
        for i, v in ipairs(node.values) do node.values[i] = walkAndResolve(v) end
    end

    return node
end

return function(irTree, _context)
    return walkAndResolve(irTree)
end
