-- Game calls that never raise: every helper gives nil when the object, the method or the type is
-- missing or the call fails (each call runs under pcall).
-- Read-only on purpose: the mod only asks the game, it never sets anything.
local Safe = {}

function Safe.try(fn, ...)
    local ok, v = pcall(fn, ...)
    if ok then return v end
    return nil
end

local function m_call(obj, name, ...) return obj:call(name, ...) end
local function m_field(obj, name) return obj:get_field(name) end
local function m_addr(obj) return obj:get_address() end
local function m_elements(arr) return arr:get_elements() end
local function m_static(method, ...) return method:call(nil, ...) end
local function t_method(td, sig) return td:get_method(sig) end
local function s_singleton(name) return sdk.get_managed_singleton(name) end
local function s_type(name) return sdk.find_type_definition(name) end

function Safe.call(obj, name, ...)
    if obj == nil then return nil end
    return Safe.try(m_call, obj, name, ...)
end

function Safe.field(obj, name)
    if obj == nil then return nil end
    return Safe.try(m_field, obj, name)
end

-- An enum value as an integer: a number, or the value__ of a boxed enum (the game gives either); nil for anything else.
function Safe.enum(v)
    if type(v) == "table" or type(v) == "userdata" then v = Safe.field(v, "value__") end
    if type(v) ~= "number" then return nil end
    return math.tointeger(v)
end

-- The object's address as an integer, nil when it has none.
function Safe.address(obj)
    if obj == nil then return nil end
    local addr = Safe.try(m_addr, obj)
    if type(addr) ~= "number" then return nil end
    return math.tointeger(addr) or addr
end

-- Name of the object's GameObject ("ch220003_00_15"), nil when empty or unreadable.
function Safe.go_name(obj)
    local go = Safe.call(obj, "get_GameObject")
    local name = Safe.call(go, "get_Name")
    if type(name) == "string" and name ~= "" then return name end
    return nil
end

function Safe.singleton(name)
    return Safe.try(s_singleton, name)
end

function Safe.type(name)
    return Safe.try(s_type, name)
end

-- A static method called as `type:get_method(sig):call(nil, ...)`; `sig` needs ", " between parameter types.
function Safe.static(type_name, sig, ...)
    local td = Safe.type(type_name)
    if td == nil then return nil end
    local method = Safe.try(t_method, td, sig)
    if method == nil then return nil end
    return Safe.try(m_static, method, ...)
end

local function c_len(c) return #c end
local function c_at(c, i) return c[i] end

-- A container the game returned (td:get_fields(), arr:get_elements(): sol userdata, not a Lua table) as a plain Lua
-- sequence: anything with a length and 1-based indexes, else (no length, or 0) whatever ipairs walks. A null entry,
-- or one that cannot be read, is `false` so that positions hold. At most `max` items (all when nil); nothing for any
-- other value.
function Safe.items(c, max)
    local out = {}
    if c == nil then return out end
    max = max or math.huge
    local n = Safe.try(c_len, c)
    if math.type(n) == "integer" and n > 0 then
        for i = 1, math.min(n, max) do
            local v = Safe.try(c_at, c, i)
            if v == nil then v = false end
            out[i] = v
        end
        return out
    end
    pcall(function()
        for i, v in ipairs(c) do
            if i > max then break end
            out[i] = v
        end
    end)
    return out
end

-- Items of a List (get_Count, get_Item) as a Lua sequence, else of what get_elements gives; a null entry is `false` so
-- that positions hold. At most `max` items. Not for the game's arrays (T[]): they answer get_Count but give nil from
-- get_Item, so read them with Safe.items(arr:get_elements()) (game/hidden_stats.lua, checked live on 2026-11-06).
function Safe.list(list, max)
    if list == nil then return {} end
    max = max or 256
    local n = Safe.call(list, "get_Count")
    if math.type(n) == "integer" then
        local out = {}
        for i = 0, math.min(n, max) - 1 do out[i + 1] = Safe.call(list, "get_Item", i) or false end
        return out
    end
    return Safe.items(Safe.try(m_elements, list), max)
end

return Safe
