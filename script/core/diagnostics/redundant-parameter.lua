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
        local callArgs = vm.countList(source.args)
        if callArgs == 0 then
            return
        end

        local candidates = vm.getCallableCandidates(source.node, source.args)
        if not candidates then
            return
        end
        local funcArgs
        for _, candidate in ipairs(candidates) do
            local _, cmax = vm.countParamsOfFunction(candidate.func)
            if cmax ~= math.huge then
                cmax = math.max(0, cmax - candidate.shift)
            end
            if not funcArgs or cmax > funcArgs then
                funcArgs = cmax
            end
        end
        if not funcArgs then
            return
        end

        if callArgs <= funcArgs then
            return
        end
        if callArgs == 1 and source.node.type == 'getmethod' then
            return
        end
        if funcArgs + 1 > #source.args then
            local lastArg = source.args[#source.args]
            if lastArg.type == 'call' and funcArgs > 0 then
                -- 如果函数接收至少一个参数，那么调用方最后一个参数是函数调用
                -- 导致的参数数量太多可以忽略。
                -- 如果函数不接收任何参数，那么任何参数都是错误的。
                return
            end
            callback {
                start   = lastArg.start,
                finish  = lastArg.finish,
                message = lang.script('DIAG_OVER_MAX_ARGS', funcArgs, callArgs)
            }
        else
            for i = funcArgs + 1, #source.args do
                local arg = source.args[i]
                callback {
                    start   = arg.start,
                    finish  = arg.finish,
                    message = lang.script('DIAG_OVER_MAX_ARGS', funcArgs, callArgs)
                }
            end
        end
    end)

    ---@async
    guide.eachSourceType(state.ast, 'function', function (source)
        await.delay()
        if not source.args then
            return
        end
        local _, funcArgs = vm.countParamsOfSource(source)
        local myArgs = #source.args
        for i = funcArgs + 1, myArgs do
            local arg = source.args[i]
            callback {
                start   = arg.start,
                finish  = arg.finish,
                message = lang.script('DIAG_OVER_MAX_ARGS', funcArgs, myArgs),
            }
        end
    end)
end
