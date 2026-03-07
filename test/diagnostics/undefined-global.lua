TEST [[
local print, _G
print(<!x!>)
print(<!log!>)
print(<!X!>)
print(<!Log!>)
print(<!y!>)
print(Z)
print(_G)
Z = 1
]]

TEST [[
X = table[<!x!>]
]]
TEST [[
T1 = 1
_ENV.T2 = 1
_G.T3 = 1
_ENV._G.T4 = 1
_G._G._G.T5 = 1
rawset(_G, 'T6', 1)
rawset(_ENV, 'T7', 1)
print(T1)
print(T2)
print(T3)
print(T4)
print(T5)
print(T6)
print(T7)
]]

TEST [[
---@class c
c = {}
]]

TEST [[
---@class myenv : _G
---@field custom_var number

---@env myenv
print(1)
custom_var = 1
]]

TEST [[
---@class myenv2
---@field custom_var number

---@env myenv2
local x = custom_var
local y = <!undefined_thing!>
-- print is not in myenv2 and myenv2 does not inherit _G, so it is undefined
local z = <!print!>
]]

TEST [[
---@class myenv3
---@field foo number

local function test()
    ---@env myenv3
    local function inner()
        local x = foo
    end
end
]]

TEST [[
---@class myenv4
---@field foo number

-- setfenv semantics: annotation applies to the whole enclosing function,
-- not just the lexical do block. print is undefined in test() because
-- myenv4 has no _G inheritance. test2() has no annotation so print is fine.
local function test()
    do
        ---@env myenv4
        local x = foo
    end
    local y = <!print!>
end

local function test2()
    print("ok")
end
]]

TEST [[
---@class myenv5
---@field foo number

-- Annotation bound directly to an anonymous function node (bindDoc matches
-- source.type == 'function'). The env must NOT bleed to the outer file scope.
local f = (function()
    ---@env myenv5
    local x = foo
    local y = <!print!>
end)

print("outer - ok")
]]

TEST [[
---@class myenv6
---@field foo number

-- When the only statement in the function body is a bare call (not bindable),
-- the annotation must still scope to the anonymous function and not bleed to
-- file scope (e.g. _G and outer globals must remain defined).
local _G_ref = _G
setfenv((function()
    ---@env myenv6
    foo()
    local x = <!print!>
end), {})()

print("outer2 - ok")
_G_ref = _G
]]
