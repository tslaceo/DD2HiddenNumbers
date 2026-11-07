-- Fake REFramework for the standalone Lua 5.4 tests.
--
--   local R = require("stubs/reframework")
--   R.new()                                   -- fresh game world; installs sdk, re, imgui, draw, Vector3f, json,
--                                             -- fs, thread, reframework and log as globals (io too: R.new{ io = true });
--                                             -- R.new{ containers = true }: td:get_fields(), td:get_methods() and
--                                             -- obj:get_elements() answer with R.container, as in the game
--
-- A world holds type definitions, managed objects, singletons, captured hooks and an in-memory data folder:
--   R.method(type, "name(T1, T2)", fn[, { static = true }])  declares the type and a method on it (instance
--                                             fn(this, ...), static fn(...)); a type without any declaration is
--                                             missing: sdk.find_type_definition returns nil, like the game
--   R.enum(type, { Name = value })            static fields, read by td:get_fields() / field:get_data(nil)
--   R.object(type, fields, methods)           managed object; `methods` are per-object overrides keyed by the
--                                             exact string that is passed to obj:call
--   R.list(items)                             System.Collections.Generic.List: get_Count, get_Item
--   R.array(items, type)                      a managed array (T[]) as the game gives it: get_Count answers,
--                                             get_Item gives nil (seen in game 2026-11-06), get_elements gives the
--                                             items (a container with containers = true)
--   R.container(items)                        a sol container like the game's std::vector returns: `#c` and
--                                             1-based `c[i]` (ipairs too), no raw entries, type(c) == "userdata"
--   R.singleton(name, obj)                    sdk.get_managed_singleton(name)
--   R.native(name, obj)                       sdk.get_native_singleton(name) (sdk.call_native_func(obj, td, name)
--                                             calls td's static method `name`)
--   R.character{ go = "ch220003_00_15", hp =, max_hp =, chara_id = }   app.Character with a GameObject
--   R.calls                                   every game call made, in order: { owner, sig, this, args }
--   R.hooks, R.fire(hook, args, ret), R.advance(n), R.files, R.json_files, R.logs
--   R.enter(hook, args) / R.leave(ret)        one hooked call in two halves, so that other calls can run inside
--                                             it (R.fire = enter + leave); R.leave ends the innermost entered call
--   R.obj_slot(o), R.null_slot(), R.int_slot(i), R.f32_slot(x)   raw argument slots
--   R.state.drawing_ui, R.state.keys_down[vk]   what reframework:is_drawing_ui() / is_key_down(vk) answer
--   R.state.project(p) -> { x, y } | nil       what draw.world_to_screen(p) answers (none: nil, off screen)
--
-- Rules the fake keeps from the real thing: a method signature needs ", " between parameter types (td:get_method
-- with "name(T1,T2)" gives nil, a method of a parent type is found too, method:get_declaring_type() tells);
-- an unknown method on an object gives nil; a static method is called with nil as `this`;
-- sdk.to_managed_object accepts only a reference-type slot (a null reference gives nil); sdk.to_int64 of a
-- reference slot is the object's address; thread.get_hook_storage() is the table of the call whose pre- or
-- post-hook runs, nil once a call nested in it has ended (ScriptRunner.cpp push/pop_hook_storage).
local R = {}

local W -- the current world

-- sol containers are userdata; a Lua proxy can only pretend, so the stub's type() says "userdata" for them.
local raw_type = type
local containers = setmetatable({}, { __mode = "k" })  -- proxy -> its items
local CONTAINER = {
    __len = function(c) return #containers[c] end,
    __index = function(c, i) if math.type(i) == "integer" then return containers[c][i] end end,
    __newindex = function() error("container is read-only in the stub") end,
}
function R.container(items)
    local c = setmetatable({}, CONTAINER)
    containers[c] = items
    return c
end
type = function(v)
    if containers[v] then return "userdata" end
    return raw_type(v)
end

local function as_game(items)
    if W.containers then return R.container(items) end
    return items
end

local TD = {}
TD.__index = TD
function TD:get_full_name() return self.name end
function TD:get_name() return self.name:match("[^.]+$") end
function TD:get_methods() return as_game(self.methods) end
function TD:get_fields() return as_game(self.fields) end
function TD:get_parent_type() return self.parent end
function TD:is_value_type() return self.vt end
function TD:is_enum() return self.enum == true end
function TD:is_by_ref() return false end
function TD:is_pointer() return false end

-- The method called `sig` ("name(T1, T2)" exactly, or the bare name) on the type or its parents.
local function find_method(td, sig)
    local bare = not sig:find("(", 1, true)
    while td do
        for _, m in ipairs(td.methods) do
            if m.sig == sig or (bare and m.name == sig) then return m end
        end
        td = td.parent
    end
    return nil
end
function TD:get_method(sig) return find_method(self, sig) end

local function record(owner, sig, this, ...)
    W.calls[#W.calls + 1] = { owner = owner, sig = sig, this = this, args = table.pack(...) }
end

local MD = {}
MD.__index = MD
function MD:get_name() return self.name end
function MD:is_static() return self.static == true end
function MD:get_declaring_type() return W.types[self.owner] end
function MD:call(this, ...)
    record(self.owner, self.sig, this, ...)
    if self.static then return self.fn(...) end
    if this == nil then error("instance method " .. self.sig .. " called without this") end
    return self.fn(this, ...)
end

local FD = {}
FD.__index = FD
function FD:get_name() return self.name end
function FD:is_static() return self.static == true end
function FD:get_data(obj)
    if self.static then return self.value end
    return obj.fields[self.name]
end

local MO = {}
MO.__index = MO
function MO:call(name, ...)
    if self.poison then error("poisoned call " .. name) end
    local fn = self.methods[name]
    if fn then
        record(self.td.name, name, self, ...)
        return fn(self, ...)
    end
    local m = find_method(self.td, name)
    if m then return m:call(self, ...) end
    return nil -- like REFramework: an unknown method gives nil
end
function MO:get_field(name)
    if self.poison then error("poisoned field " .. name) end
    return self.fields[name]
end
function MO:get_address()
    if self.poison then error("poisoned address") end
    return self.addr
end
function MO:get_type_definition() return self.td end
function MO:get_elements() return as_game(self.items or {}) end

local function ty(name)
    local td = W.types[name]
    if not td then
        td = setmetatable({ name = name, methods = {}, fields = {}, vt = false, enum = false }, TD)
        W.types[name] = td
    end
    return td
end

function R.type(name, parent)
    local td = ty(name)
    if parent then td.parent = ty(parent) end
    return td
end

-- A type is missing again (existing objects keep their definition).
function R.undeclare(name) W.types[name] = nil end

function R.method(type_name, sig, fn, opts)
    local td = ty(type_name)
    local m = setmetatable({ owner = type_name, sig = sig, name = sig:match("^[^(]+"), fn = fn,
                             static = opts and opts.static or false }, MD)
    for i, old in ipairs(td.methods) do
        if old.sig == sig then table.remove(td.methods, i) break end
    end
    td.methods[#td.methods + 1] = m
    return m
end

function R.enum(type_name, values)
    local td = ty(type_name)
    td.enum, td.vt = true, true
    td.fields = {}
    local names = {}
    for name in pairs(values) do names[#names + 1] = name end
    table.sort(names)
    td.fields[1] = setmetatable({ name = "value__", static = false }, FD)
    for _, name in ipairs(names) do
        td.fields[#td.fields + 1] = setmetatable({ name = name, static = true, value = values[name] }, FD)
    end
    return td
end

function R.object(type_name, fields, methods)
    W.next_addr = W.next_addr + 0x100
    return setmetatable({ td = ty(type_name), fields = fields or {}, methods = methods or {}, addr = W.next_addr }, MO)
end

function R.list(items, type_name)
    local list = R.object(type_name or "System.Collections.Generic.List`1<app.Character>", {}, {
        get_Count = function() return #items end,
        get_Item = function(_, i) return items[i + 1] end,
    })
    list.items = items
    return list
end

function R.array(items, type_name)
    local arr = R.object(type_name or "System.Object[]", {}, {
        get_Count = function() return #items end,
        get_Item = function() return nil end,
    })
    arr.items = items
    return arr
end

function R.singleton(name, obj) W.singletons[name] = obj end

function R.native(name, obj) W.natives[name] = obj end

function R.character(o)
    o = o or {}
    local go = R.object("via.GameObject", {}, { get_Name = function() return o.go end })
    local c
    c = R.object("app.Character", {}, {
        get_GameObject = function() return go end,
        get_Hp = function() return c.hp end,
        get_OriginalMaxHp = function() return c.max_hp end,
        get_CharaID = function() return c.chara_id end,
    })
    c.hp, c.max_hp, c.chara_id = o.hp, o.max_hp, o.chara_id
    c.go = go
    return c
end

-- The game's raw hook slots (lightuserdata in REFramework).
function R.obj_slot(o) return { obj = o, i = o and o.addr or 0 } end
function R.null_slot() return { null = true, i = 0 } end
function R.int_slot(i) return { i = i } end
function R.f32_slot(x) return { f = x } end
local CTX = { ctx = true }
R.CTX = CTX

-- Like ScriptRunner: the pre-hook pushes a fresh storage table, the post-hook sees the top one again and the
-- storage is popped after it; in between, a nested call that ended leaves no current storage.
function R.enter(hook, args)
    local st = {}
    W.storage[#W.storage + 1] = st
    W.entered[#W.entered + 1] = hook
    W.current = st
    if hook.pre then hook.pre(args or { CTX }) end
end

function R.leave(ret)
    local hook = table.remove(W.entered)
    assert(hook, "R.leave without R.enter")
    W.current = W.storage[#W.storage]
    local r = ret
    if hook.post then r = hook.post(ret) end
    W.storage[#W.storage] = nil
    W.current = nil
    return r
end

function R.fire(hook, args, ret)
    R.enter(hook, args)
    return R.leave(ret)
end

function R.advance(n)
    for _ = 1, n or 1 do
        for _, fn in ipairs(W.frame_fns) do fn() end
    end
end

function R.hook_of(type_name, method)
    for _, hk in ipairs(W.hooks) do
        if hk.m.owner == type_name and hk.m.name == method then return hk end
    end
    return nil
end

-- Calls recorded for `sig` (all calls when nil).
function R.calls_of(sig)
    local out = {}
    for _, c in ipairs(W.calls) do
        if sig == nil or c.sig == sig then out[#out + 1] = c end
    end
    return out
end

local function data_path(path)
    assert(not path:find("%.%.") and not path:find("^%a:") and not path:find("^[/\\]"), "path outside data: " .. path)
    return path
end

local File = {}
File.__index = File
function File:write(...)
    for _, s in ipairs({ ... }) do W.files[self.path] = (W.files[self.path] or "") .. s end
    return self
end
function File:flush() return true end
function File:close() return true end
-- Only seek("end") is faked: the file's size, as on a handle opened for appending.
function File:seek(whence, offset)
    if whence ~= "end" then return nil, "only seek(\"end\") is faked" end
    return #(W.files[self.path] or "") + (offset or 0)
end

local function install()
    sdk = {
        find_type_definition = function(name) return W.types[name] end,
        get_managed_singleton = function(name) return W.singletons[name] end,
        get_native_singleton = function(name) return W.natives[name] end,
        call_native_func = function(obj, td, name, ...)
            local m = find_method(td, name)
            return m and m:call(nil, ...) or nil
        end,
        typeof = function(name) return W.types[name] and { runtime_type = name } or nil end,
        hook = function(m, pre, post) W.hooks[#W.hooks + 1] = { m = m, pre = pre, post = post } end,
        to_managed_object = function(p)
            if type(p) == "table" and p.null then return nil end
            if type(p) ~= "table" or p.obj == nil then
                W.bad[#W.bad + 1] = "to_managed_object on a non-reference slot"
                return nil
            end
            return p.obj
        end,
        to_float = function(p)
            if type(p) ~= "table" or p.f == nil then W.bad[#W.bad + 1] = "to_float on a non-float slot"; return 0.0 end
            return p.f
        end,
        to_double = function(p) return p.f or 0.0 end,
        to_int64 = function(p)
            if type(p) ~= "table" or p.i == nil then W.bad[#W.bad + 1] = "to_int64 on a non-integer slot"; return 0 end
            return p.i
        end,
    }

    re = {
        on_frame = function(fn) W.frame_fns[#W.frame_fns + 1] = fn end,
        on_draw_ui = function(fn) W.draw_ui_fns[#W.draw_ui_fns + 1] = fn end,
        on_pre_application_entry = function(name, fn) W.entry_fns[#W.entry_fns + 1] = { name = name, fn = fn } end,
        on_application_entry = function(name, fn) W.entry_fns[#W.entry_fns + 1] = { name = name, fn = fn } end,
        CallbackNextAction = { CONTINUE = 0, STOP = 1 },
    }

    thread = {
        get_hash = function() return 1 end,
        get_hook_storage = function() return W.current end,
    }

    reframework = {
        is_drawing_ui = function() return W.state.drawing_ui end,
        is_key_down = function(_, vk) return W.state.keys_down[vk] == true end,
        get_commit_hash = function() return "d4611aef1d63effd3a736bdf9404ea702428017d" end,
        get_tag = function() return "v1.5.9.1" end,
        get_commits_past_tag = function() return 515 end,
    }

    fs = {
        write = function(path, data) W.files[data_path(path)] = data end,
        read = function(path) return W.files[data_path(path)] or "" end,
    }

    json = {
        dump_file = function(path, t) W.json_files[data_path(path)] = t; return true end,
        load_file = function(path) return W.json_files[data_path(path)] end,
    }

    log = {
        info = function(msg) W.logs[#W.logs + 1] = msg end,
        warn = function(msg) W.logs[#W.logs + 1] = msg end,
        error = function(msg) W.logs[#W.logs + 1] = msg end,
    }

    -- Drawing is tests/stubs/ui.lua's business (it records it); here the calls only have to exist.
    -- draw.world_to_screen(p) answers R.state.project(p) ({ x, y } on the screen), nil without one, as off screen.
    local function noop() end
    imgui = { text = noop, begin_window = function() return true end, end_window = noop, button = function() return false end,
              same_line = noop, separator = noop, progress_bar = noop, push_style_color = noop, pop_style_color = noop,
              set_next_window_pos = noop, set_next_window_size = noop }
    -- REFramework's vector type: Vector3f.new(x, y, z) -> { x, y, z }
    Vector3f = { new = function(x, y, z) return { x = x, y = y, z = z } end }
    draw = { text = noop, filled_rect = noop, outline_rect = noop,
             world_to_screen = function(p)
                 local project = W.state.project
                 if project then return project(p) end
                 return nil
             end }
end

-- A fresh world. `opts.io` also replaces io.open with the in-memory data folder.
function R.new(opts)
    W = { types = {}, singletons = {}, natives = {}, hooks = {}, frame_fns = {}, draw_ui_fns = {}, entry_fns = {},
          files = {}, json_files = {}, logs = {}, calls = {}, storage = {}, entered = {}, bad = {},
          next_addr = 0x10000, state = { drawing_ui = false, keys_down = {} }, containers = opts and opts.containers }
    R.calls, R.hooks, R.files, R.json_files, R.logs, R.bad = W.calls, W.hooks, W.files, W.json_files, W.logs, W.bad
    R.state = W.state
    install()
    if opts and opts.io then
        io = {
            open = function(path, mode)
                path = data_path(path)
                mode = mode or "r"
                if mode:find("w") then W.files[path] = "" end
                if mode:find("r") and W.files[path] == nil then return nil end
                return setmetatable({ path = path }, File)
            end,
        }
    end
    return R
end

return R
