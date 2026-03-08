# `@env` Annotation Guide

This guide explains how to use `---@env` for custom function/file environments and how it interacts with typed table functions.

## What `@env` does

`@env` changes how unresolved global names are looked up.

- Without `@env`: unresolved globals come from normal `_ENV` / globals.
- With `@env MyEnv`: unresolved globals inside that scope are resolved from class `MyEnv`.
- If `MyEnv` inherits `_G`, normal globals are still available as fallback.
- If `MyEnv` does not inherit `_G`, only fields from `MyEnv` are allowed.

## Scope semantics

`@env` is function/file scoped (setfenv-like), not statement-scoped.

- Function annotation affects the whole enclosing function.
- File-level annotation affects the whole file.
- Inline annotation inside a function (including function literals) is treated as that function's environment.
- It does not leak to outer scope.

## Supported forms

1. Standard line annotation
   - This should be defined within the scope you want it to impact (function/file). If you want it to impact the function scope then you do like below.

   ```lua
    local function run()
      ---@env testenv4
      return test3
    end
   ```
   - However, if you do this, it will be scoped to whatever level is the parent of the function, such as file level.
   ```lua
    ---@env testenv4
    local function run()
      return test3
    end
   ```

2. Inline long-comment annotation (inside function body/literal)
   ```lua
   local f = function() --[=[@env testenv4]=]
       return test3
   end
   ```

   ***This is useful for table function literals where you want local, per-function env control.***

3. Field function type shorthand (self + env, best-effort)
   ```lua
   ---@field f1 fun<MyEnv>(): integer
   ---@field f2 function<MyEnv>
   ```

When a table function implementation has a first parameter named `self`, these field
signatures are used as best-effort hints for unresolved global lookup inside that
function body (as `MyEnv`).

`self` type is inferred from the owning table/class (`---@class` + assignment target)
first. It only falls back to env/function-type hints when no owner type is available.

## Example

  ```lua
  ---@class testenv4
  local testenv4 = setmetatable({
    test1 = 1,
    test2 = "2",
    test3 = false,
  }, { __index = _G })
  ```
  
  - `testenv4` is the environment class.
  - `__index = _G` means unresolved lookups can still fall back to   global builtins.
  - This could also take the form of `---@class testenv4 : _G`

  ```lua
  ---@class testenv4Class
  ---@field test_table_fun1 fun<testenv4>(self, a: string, b: string):integer
  ---@field test_table_fun2 function<testenv4>
  local testtable1 = {
    test_table_fun1 = function(self, a, b) return test1 end,
    test_table_fun2 = function(self) return test2 end,
    test_table_fun3 = function() --[=[@env testenv4]=] return test3 end,
  }
  ```

- `test_table_fun1`
  - `fun<testenv4>(self, a: string, b: string):integer` is the strict   typed contract for `test_table_fun1`.
  - This is the recommended form when return type precision is required.
  - With a `self` first parameter in the implementation, it provides env lookup hints.
  - Explicit field access, independent of `@env`.
  - Return is `integer` (`1`).

- `test_table_fun2`
  - "generic" `function` type

- `test_table_fun3`
  - Inline `@env` binds this whole function to `testenv4`.
  - `test3` resolves from `testenv4.test3`.
  - Return is `boolean` (`false`).

## Recommended usage patterns

1. Use `fun<Env>(...): ReturnType` for field contracts that must be precise.
3. Use inline `--[=[@env Env]=]` for table function literals that need env lookup.
4. Use `---@class Env : _G` when you want sandbox additions plus normal globals.

## Common pitfalls

1. Expecting `@env` on a line/block to affect only that statement.
   - Actual behavior: function/file scoped.
2. Forgetting `_G` inheritance in env class, then `print/type/...` become undefined.
3. Using unresolved names in functions without `@env` and expecting env resolution.
