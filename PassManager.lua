local PassManager = {}
PassManager.__index = PassManager

function PassManager.new()
    return setmetatable({ passes = {} }, PassManager)
end

function PassManager:addPass(name, transformFn, options)
    table.insert(self.passes, {
        name = name,
        transform = transformFn,
        enabled = options and options.enabled ~= false,
    })
    return self
end

function PassManager:run(irTree, context)
    local stats = { totalPasses = 0, modifiedPasses = 0, details = {} }

    for _, pass in ipairs(self.passes) do
        if pass.enabled then
            stats.totalPasses += 1
            local before = irTree -- reference comparison
            local result = pass.transform(irTree, context)
            local modified = result ~= before

            if modified then
                irTree = result
                stats.modifiedPasses += 1
            end

            table.insert(stats.details, {
                name = pass.name,
                modified = modified,
            })
        end
    end

    return irTree, stats
end

return PassManager
