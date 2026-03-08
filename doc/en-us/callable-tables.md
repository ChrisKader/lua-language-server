# Callable Tables (`setmetatable` + `__call`)

This guide explains how callable tables are inferred when a metatable provides `__call`.

## Basic pattern

```lua
---@class CallableThing
local obj = setmetatable({}, {
    ---@param self CallableThing
    ---@param a string
    ---@param b number
    ---@return boolean
    __call = function(self, a, b)
        return true
    end,
})

local ok = obj("hello", 42) -- boolean
```

## Hidden `self` behavior

For `obj(...)`, `self` is treated as hidden and injected automatically for `__call(self, ...)`.

- User-visible call: `obj("hello", 42)`
- Internal match: `__call(obj, "hello", 42)`

This is used consistently for:

- return inference
- missing/redundant parameter diagnostics
- parameter type mismatch diagnostics
- signature help active-parameter indexing
- call argument completion hints

## Supported sources of callability

1. Class overloads (`---@overload`) that define callable signatures.
2. Metatable `__call` discovered through `setmetatable`.
3. Deep chains through `__index` / inheritance when statically resolvable.

## Metatable variable form

```lua
---@class MT
local mt = {}

---@param self table
---@param x integer
---@return string
function mt.__call(self, x)
    return tostring(x)
end

local t = setmetatable({}, mt)
local s = t(1) -- string
```

## Notes

- Resolution is best-effort static analysis.
- Ambiguous or highly dynamic patterns remain conservative (`unknown`) to avoid false positives.
- Existing `@operator call` behavior remains unchanged.
