local IR = require(script.Parent.IR)
local Util = require(script.Parent.Util)

local BackendLua = {}

local BINARY_OPS = {
    add = "+", sub = "-", mul = "*", div = "/", mod = "%", pow = "^",
    idiv = "//", and_ = "and", or_ = "or", concat = "..",
}

local UNARY_OPS = { not_ = "not ", minus = "-", len = "#" }

local function emitExpr(buf, node)
    if type(node) ~= "table" then
        buf:write(tostring(node))
        return
    end

    local k = node.kind
    if k == IR.E.Nil then buf:write("nil")
    elseif k == IR.E.Bool then buf:write(tostring(node.args[1]))
    elseif k == IR.E.Number then buf:write(Util.formatNumber(node.args[1]))
    elseif k == IR.E.Integer then buf:write(tostring(node.args[1]) .. "i")
    elseif k == IR.E.String then buf:write(Util.quoteString(node.args[1]))
    elseif k == IR.E.VarArg then buf:write("...")
    elseif k == IR.E.Local or k == IR.E.Upvalue or k == IR.E.Global then
        buf:write(tostring(node.args[1]))
    elseif k == IR.E.Field then
        emitExpr(buf, node.args[1])
        buf:write(".")
        buf:write(tostring(node.args[2]))
    elseif k == IR.E.Index then
        emitExpr(buf, node.args[1])
        buf:write("[")
        emitExpr(buf, node.args[2])
        buf:write("]")
    elseif k == IR.E.BinaryOp then
        buf:write("(")
        emitExpr(buf, node.args[2])
        buf:write(" " .. (BINARY_OPS[node.args[1]] or node.args[1]) .. " ")
        emitExpr(buf, node.args[3])
        buf:write(")")
    elseif k == IR.E.UnaryOp then
        buf:write(UNARY_OPS[node.args[1]] or node.args[1])
        emitExpr(buf, node.args[2])
    elseif k == IR.E.Concat then
        buf:write("(")
        for i, arg in ipairs(node.args) do
            if i > 1 then buf:write(" .. ") end
            emitExpr(buf, arg)
        end
        buf:write(")")
    elseif k == IR.E.CallExpr or k == IR.E.MethodCall then
        if k == IR.E.MethodCall then
            emitExpr(buf, node.args[1])
            buf:write(":")
            buf:write(tostring(node.args[2]))
        else
            emitExpr(buf, node.args[1])
        end
        buf:write("(")
        local callArgs = k == IR.E.MethodCall and node.args[3] or node.args[2]
        if callArgs then
            for i, arg in ipairs(callArgs) do
                if i > 1 then buf:write(", ") end
                emitExpr(buf, arg)
            end
        end
        buf:write(")")
    elseif k == IR.E.Select then
        buf:write("select(")
        buf:write(tostring(node.args[1]))
        buf:write(", ")
        emitExpr(buf, node.args[2])
        buf:write(")")
    elseif k == IR.E.TableConst then buf:write("{}")
    elseif k == IR.E.Closure then buf:write("function() end")
    elseif k == IR.E.Vector then
        buf:write(("Vector3.new(%s, %s, %s)"):format(
            Util.formatNumber(node.args[1]),
            Util.formatNumber(node.args[2]),
            Util.formatNumber(node.args[3])
        ))
    elseif k == IR.E.Import then
        local parts = node.args[1]
        buf:write(type(parts) == "table" and table.concat(parts, ".") or tostring(parts))
    else
        buf:write("/* unknown expr */")
    end
end

local function emitNode(buf, node, indentLevel)
    if type(node) ~= "table" then return end

    if node.type == "Nop" then
        -- skip
    elseif node.type == "Assign" then
        buf:indent(indentLevel)
        if node.isLocal then
            buf:write("local ")
        end
        if type(node.target) == "string" then
            buf:write(node.target)
        else
            emitExpr(buf, node.target)
        end
        if node.typeAnnotation then
            buf:write(": ")
            buf:write(node.typeAnnotation)
        end
        buf:write(" = ")
        emitExpr(buf, node.value)
        buf:writeln("")
    elseif node.type == "Block" then
        for _, child in ipairs(node.children) do
            emitNode(buf, child, indentLevel)
        end
    elseif node.type == "If" then
        buf:indent(indentLevel)
        buf:write("if ")
        emitExpr(buf, node.condition)
        buf:writeln(" then")
        emitNode(buf, node.thenBlock, indentLevel + 1)
        if node.elseBlock then
            buf:indent(indentLevel)
            buf:writeln("else")
            emitNode(buf, node.elseBlock, indentLevel + 1)
        end
        buf:indent(indentLevel)
        buf:writeln("end")
    elseif node.type == "While" then
        buf:indent(indentLevel)
        buf:write("while ")
        emitExpr(buf, node.condition)
        buf:writeln(" do")
        emitNode(buf, node.body, indentLevel + 1)
        buf:indent(indentLevel)
        buf:writeln("end")
    elseif node.type == "Repeat" then
        buf:indent(indentLevel)
        buf:writeln("repeat")
        emitNode(buf, node.body, indentLevel + 1)
        buf:indent(indentLevel)
        buf:write("until ")
        emitExpr(buf, node.condition)
        buf:writeln("")
    elseif node.type == "ForNum" then
        buf:indent(indentLevel)
        buf:write(("for %s = "):format(node.var))
        emitExpr(buf, node.start)
        buf:write(", ")
        emitExpr(buf, node.limit)
        if node.step then
            buf:write(", ")
            emitExpr(buf, node.step)
        end
        buf:writeln(" do")
        emitNode(buf, node.body, indentLevel + 1)
        buf:indent(indentLevel)
        buf:writeln("end")
    elseif node.type == "ForGen" then
        buf:indent(indentLevel)
        buf:write("for ")
        buf:write(table.concat(node.vars, ", "))
        buf:write(" in ")
        emitExpr(buf, node.iterator)
        buf:writeln(" do")
        emitNode(buf, node.body, indentLevel + 1)
        buf:indent(indentLevel)
        buf:writeln("end")
    elseif node.type == "Return" then
        buf:indent(indentLevel)
        if #node.values == 0 then
            buf:writeln("return")
        else
            buf:write("return ")
            for i, v in ipairs(node.values) do
                if i > 1 then buf:write(", ") end
                emitExpr(buf, v)
            end
            buf:writeln("")
        end
    elseif node.type == "Call" then
        buf:indent(indentLevel)
        emitExpr(buf, node.func)
        buf:write("(")
        for i, arg in ipairs(node.args) do
            if i > 1 then buf:write(", ") end
            emitExpr(buf, arg)
        end
        buf:writeln(")")
    end
end

function BackendLua.emit(irTree, params)
    local buf = Util.Buffer.new(8192)

    -- Function header
    buf:write("function(")
    if params then
        buf:write(table.concat(params, ", "))
    end
    buf:writeln(")")

    emitNode(buf, irTree, 1)

    buf:writeln("end")
    return buf:toString()
end

return BackendLua
