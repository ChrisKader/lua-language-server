local files      = require 'files'
local vm         = require 'vm'
local hoverLabel = require 'core.hover.label'
local hoverDesc  = require 'core.hover.description'
local guide      = require 'parser.guide'
local lookback   = require 'core.look-backward'

local function findNearCall(uri, ast, pos)
    local text  = files.getText(uri)
    local state = files.getState(uri)
    if not state or not text then
        return nil
    end
    local nearCall
    guide.eachSourceContain(ast.ast, pos, function (src)
        if src.type == 'call'
        or src.type == 'table'
        or src.type == 'function' then
            local finishOffset = guide.positionToOffset(state, src.finish)
            -- call(),$
            if  src.finish <= pos
            and text:sub(finishOffset, finishOffset) == ')' then
                return
            end
            -- {},$
            if  src.finish <= pos
            and text:sub(finishOffset, finishOffset) == '}' then
                return
            end
            if not nearCall or nearCall.start <= src.start then
                nearCall = src
            end
        end
    end)
    if not nearCall then
        return nil
    end
    if nearCall.type ~= 'call' then
        return nil
    end
    return nearCall
end

---@async
local function makeOneSignature(source, oop, index, hiddenArgs)
    local label = hoverLabel(source, oop, 0)
    if not label then
        return nil
    end
    -- 去掉返回值
    label = label:gsub('%s*->.+', '')

    if hiddenArgs and hiddenArgs > 0 then
        local argStart, argLabel = label:match '()(%b())$'
        if argStart and argLabel then
            local raw = argLabel:sub(2, -2)
            local converted = raw
                :gsub('%b<>', function (str)
                    return ('_'):rep(#str)
                end)
                :gsub('%b()', function (str)
                    return ('_'):rep(#str)
                end)
                :gsub('%b{}', function (str)
                    return ('_'):rep(#str)
                end)
                :gsub ('%b[]', function (str)
                    return ('_'):rep(#str)
                end)
            local parts = {}
            local last = 1
            for i = 1, #converted do
                if converted:sub(i, i) == ',' then
                    parts[#parts+1] = raw:sub(last, i - 1):match('^%s*(.-)%s*$')
                    last = i + 1
                end
            end
            if #raw > 0 then
                parts[#parts+1] = raw:sub(last):match('^%s*(.-)%s*$')
            end
            if #parts > 0 then
                for _ = 1, hiddenArgs do
                    table.remove(parts, 1)
                end
                local newArgLabel = '(' .. table.concat(parts, ', ') .. ')'
                label = label:sub(1, argStart - 1) .. newArgLabel
            end
        end
        if index then
            index = math.max(1, index - hiddenArgs)
        end
    end

    local params = {}
    local i = 0
    local argStart, argLabel = label:match '()(%b())$'
    local converted = argLabel
        : sub(2, -2)
        : gsub('%b<>', function (str)
            return ('_'):rep(#str)
        end)
        : gsub('%b()', function (str)
            return ('_'):rep(#str)
        end)
        : gsub('%b{}', function (str)
            return ('_'):rep(#str)
        end)
        : gsub ('%b[]', function (str)
            return ('_'):rep(#str)
        end)
        : gsub('[%(%)]', '_')

    for start, finish in converted:gmatch '%s*()[^,]+()' do
        i = i + 1
        params[i] = {
            label = {start + argStart - 1, finish - 1 + argStart},
        }
    end
    -- 不定参数
    if index and index > i and i > 0 then
        local lastLabel = params[i].label
        local text = label:sub(lastLabel[1] + 1, lastLabel[2])
        if text:sub(1, 3) == '...' then
            index = i
        end
    end
    if #params < (index or 0) then
        return nil
    end
    return {
        label       = label,
        params      = params,
        index       = index or 1,
        description = hoverDesc(source),
    }
end

local function isEventNotMatch(callArgs, src)
    if not callArgs or not src.args then
        return false
    end
    local literal, index
    for i = 1, #callArgs do
        literal = guide.getLiteral(callArgs[i])
        if literal then
            index = i
            break
        end
    end
    if not literal then
        return false
    end
    local event = src.args[index]
    if not event or event.type ~= 'doc.type.arg' then
        return false
    end
    if not event.extends
    or #event.extends.types ~= 1 then
        return false
    end
    local eventLiteral = event.extends.types[1] and guide.getLiteral(event.extends.types[1])
    if eventLiteral == nil then
        -- extra checking when function param is not pure literal
        -- eg: it maybe an alias type with literal values
        local eventMap = vm.getLiterals(event.extends.types[1])
        if not eventMap then
            return false
        end
        return not eventMap[literal]
    end
    return eventLiteral ~= literal
end

---@async
local function makeSignatures(text, call, pos)
    local func = call.node
    local oop = func.type == 'method'
             or func.type == 'getmethod'
             or func.type == 'setmethod'
    local index
    if call.args then
        local args = {}
        for _, arg in ipairs(call.args) do
            if arg.type ~= 'self' then
                args[#args+1] = arg
            end
        end
        local uri   = guide.getUri(call)
        local state = files.getState(uri)
        for i, arg in ipairs(args) do
            local startOffset = guide.positionToOffset(state, arg.start)
            startOffset =  lookback.findTargetSymbol(text, startOffset, '(')
                        or lookback.findTargetSymbol(text, startOffset, ',')
                        or startOffset
            local startPos = guide.offsetToPosition(state, startOffset)
            if startPos > pos then
                index = i - 1
                break
            end
            if pos <= arg.finish then
                index = i
                break
            end
        end
        if not index then
            local offset     = guide.positionToOffset(state, pos)
            local backSymbol = lookback.findSymbol(text, offset)
            if backSymbol == ','
            or backSymbol == '(' then
                index = #args + 1
            else
                index = #args
            end
        end
    end
    local signs = {}
    local mark = {}
    local candidates = vm.getCallableCandidates(func, call.args, true)
    if not candidates then
        return signs
    end
    for _, candidate in ipairs(candidates) do
        local src = candidate.func
        local shiftMark = mark[candidate.shift]
        if not shiftMark then
            shiftMark = {}
            mark[candidate.shift] = shiftMark
        end
        if  not shiftMark[src]
        and not isEventNotMatch(candidate.args or call.args, src)
        and ((src.type ~= 'function') or not vm.isVarargFunctionWithOverloads(src)) then
            shiftMark[src] = true
            signs[#signs+1] = makeOneSignature(
                src,
                oop and candidate.shift == 0,
                index and (index + candidate.shift) or index,
                candidate.shift
            )
        end
    end
    return signs
end

---@async
return function (uri, pos)
    local state = files.getState(uri)
    local text  = files.getText(uri)
    if not state or not text then
        return nil
    end
    local offset = guide.positionToOffset(state, pos)
    pos = guide.offsetToPosition(state, lookback.skipSpace(text, offset))
    local call = findNearCall(uri, state, pos)
    if not call then
        return nil
    end
    local signs = makeSignatures(text, call, pos)
    if not signs or #signs == 0 then
        return nil
    end
    table.sort(signs, function (a, b)
        return #a.params < #b.params
    end)
    return signs
end
