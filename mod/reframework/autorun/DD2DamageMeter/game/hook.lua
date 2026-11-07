-- Hooks on game methods (as REFramework's HookManager.cpp and ScriptRunner.cpp work). sdk.hook keeps its closures
-- for the life of the Lua state and a hook cannot be removed, so each method is hooked once per Lua state (registry in
-- the global DD2DM_HOOKS) and its closures only forward to the handlers stored there, which every install replaces:
-- a reloaded mod drives the hooks of the first load.
--
-- Handlers: pre(args, storage) and post(retval, storage), `storage` being the call's thread.get_hook_storage() table,
-- read before anything else (a game call made by a handler can run nested hooks, after which there is no current
-- storage). Handlers run under pcall. The pre-hook returns nothing, so the game's method always runs; the post-hook
-- returns the retval it got, untouched (ScriptRunner.cpp writes the post-hook's result back as the return value).
-- Handlers never write into `args` (ScriptRunner.cpp copies the table back into the call) and never keep it.
local Safe = require("DD2DamageMeter/game/safe")

local Hook = {}

local function state()
    local S = rawget(_G, "DD2DM_HOOKS")
    if type(S) ~= "table" then
        S = {}
        rawset(_G, "DD2DM_HOOKS", S)
    end
    S.hooked = S.hooked or {}     -- "Type.sig" -> true once hooked, false when sdk.hook refused it
    S.handlers = S.handlers or {} -- "Type.sig" -> { pre = fn|nil, post = fn|nil }
    S.errors = S.errors or 0
    S.errors_at = S.errors_at or {} -- where -> count
    return S
end

local REPORT_FIRST, REPORT_EVERY = 10, 1000  -- a handler failing on every call is reported now and then only

-- Counts a caught error; the last one is kept for DD2DM.info() and the debug log.
function Hook.fail(where, err)
    local S = state()
    where = tostring(where)
    S.errors = S.errors + 1
    S.last_error = where .. ": " .. tostring(err)
    local n = (S.errors_at[where] or 0) + 1
    S.errors_at[where] = n
    local report = S.on_error
    if report and (n <= REPORT_FIRST or n % REPORT_EVERY == 0) then pcall(report, where, err, n) end
end

-- fn(where, err, count) is told about caught errors (e.g. the debug log): the first ones of each place, then every
-- 1000th; nil stops it.
function Hook.on_error(fn)
    state().on_error = fn
end

function Hook.info()
    local S = state()
    return { errors = S.errors, last_error = S.last_error }
end

local function run_pre(key, args)
    local storage = thread.get_hook_storage()
    if storage == nil then return end
    local S = rawget(_G, "DD2DM_HOOKS")
    local h = type(S) == "table" and S.handlers and S.handlers[key]
    local fn = h and h.pre
    if fn == nil then return end
    local ok, err = pcall(fn, args, storage)
    if not ok then Hook.fail(key, err) end
end

local function run_post(key, retval)
    local storage = thread.get_hook_storage()
    if storage == nil then return end
    local S = rawget(_G, "DD2DM_HOOKS")
    local h = type(S) == "table" and S.handlers and S.handlers[key]
    local fn = h and h.post
    if fn == nil then return end
    local ok, err = pcall(fn, retval, storage)
    if not ok then Hook.fail(key, err) end
end

local function t_method(td, sig) return td:get_method(sig) end
local function m_declaring(m) return m:get_declaring_type() end
local function t_name(td) return td:get_full_name() end

-- Points `type_name`'s method `sig` (exact, ", " between parameter types) at pre/post, hooking it first if this Lua
-- state has not yet. False when the type or the method is missing, when only a parent type has it (hooking the
-- parent's method would catch its other subtypes too) or when sdk.hook refused it.
function Hook.install(type_name, sig, pre, post)
    local S = state()
    local key = type_name .. "." .. sig
    -- registered before sdk.hook, so a call that arrives at once finds its handler
    S.handlers[key] = { pre = pre, post = post }
    if S.hooked[key] ~= nil then return S.hooked[key] end
    local td = Safe.type(type_name)
    local method = td and Safe.try(t_method, td, sig)
    if method == nil then return false end
    local declaring = Safe.try(m_declaring, method)
    local declared_by = declaring and Safe.try(t_name, declaring)
    if declared_by ~= nil and declared_by ~= type_name then
        Hook.fail("hook refused " .. key, "declared by " .. tostring(declared_by))
        return false
    end
    local ok, err = pcall(sdk.hook, method,
        function(args) pcall(run_pre, key, args) end,
        function(retval)
            pcall(run_post, key, retval)
            return retval
        end)
    if not ok then
        S.hooked[key] = false
        Hook.fail("hook " .. key, err)
        return false
    end
    S.hooked[key] = true
    return true
end

-- Installs { { type, sig, pre = fn, post = fn }, ... }: how many are hooked, and "Type.sig" of the others.
function Hook.install_all(list)
    local n, missing = 0, {}
    for _, h in ipairs(list) do
        if Hook.install(h[1], h[2], h.pre, h.post) then
            n = n + 1
        else
            missing[#missing + 1] = h[1] .. "." .. h[2]
        end
    end
    return n, missing
end

-- Raw argument slots (lightuserdata). key_of reads a reference argument's address without touching the object;
-- obj only on parameters whose declared type is a reference type.
function Hook.key_of(slot)
    if slot == nil then return nil end
    local key = sdk.to_int64(slot)
    if math.type(key) ~= "integer" or key == 0 then return nil end
    return key
end

function Hook.obj(slot)
    if slot == nil then return nil end
    return sdk.to_managed_object(slot)
end

-- A finite number, else nil.
function Hook.number(x)
    if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge then return nil end
    return x
end

function Hook.float(slot)
    if slot == nil then return nil end
    return Hook.number(sdk.to_float(slot))
end

function Hook.int32(slot)
    if slot == nil then return nil end
    local i = sdk.to_int64(slot)
    if math.type(i) ~= "integer" then return nil end
    i = i & 0xffffffff
    if i >= 0x80000000 then i = i - 0x100000000 end
    return i
end

return Hook
