local files  = require 'files'
local guide  = require 'parser.guide'
local vm     = require 'vm'
local lang   = require 'language'
local await  = require 'await'

---@async
return function (uri, callback)
    local state = files.getState(uri)
    if not state then
        return
    end

    ---@async
    guide.eachSourceType(state.ast, 'call', function (source)
        await.delay()
        local _, callArgs = vm.countList(source.args)
        local candidates = vm.getCallableCandidates(source.node, source.args)
        if not candidates then
            return
        end
        local minArgs
        for _, candidate in ipairs(candidates) do
            local cmin = vm.countParamsOfFunction(candidate.func)
            cmin = math.max(0, cmin - candidate.shift)
            if not minArgs or cmin < minArgs then
                minArgs = cmin
            end
        end
        if not minArgs or callArgs >= minArgs then
            return
        end

        callback {
            start  = source.start,
            finish = source.finish,
            message = lang.script('DIAG_MISS_ARGS', minArgs, callArgs),
        }
    end)
end
