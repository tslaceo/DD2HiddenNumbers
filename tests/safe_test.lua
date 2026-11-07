package.path = "mod/reframework/autorun/?.lua;tests/?.lua;" .. package.path

local T = require("testlib")
local test, eq = T.test, T.eq
local R = require("stubs/reframework")
local Safe = require("DD2DamageMeter/game/safe")

local function joined(list)
    local out = {}
    for i, v in ipairs(list) do out[i] = tostring(v) end
    return table.concat(out, " ")
end

test("items: a plain table and a game container give the same sequence", function()
    R.new()
    eq(joined(Safe.items({ "a", "b", "c" })), "a b c", "plain table")
    eq(joined(Safe.items(R.container({ "a", "b", "c" }))), "a b c", "container")
    eq(rawlen(Safe.items(R.container({ "a" }))), 1, "a plain Lua table comes back")
end)

test("items: at most max, a null entry is false", function()
    R.new()
    eq(joined(Safe.items(R.container({ "a", "b", "c" }), 2)), "a b", "capped")
    eq(joined(Safe.items(R.container({ "a", nil, "c" }))), "a false c", "null keeps its place")
end)

test("items: nothing for a value without a length or indexes", function()
    R.new()
    eq(#Safe.items(nil), 0, "nil")
    eq(#Safe.items(5), 0, "a number")
    eq(#Safe.items(true), 0, "a boolean")
    local broken = setmetatable({}, { __len = function() error("boom") end })
    eq(#Safe.items(broken), 0, "a length that raises")
    local half = setmetatable({}, {
        __len = function() return 3 end,
        __index = function(_, i) if i == 2 then error("boom") end return "x" .. i end,
    })
    eq(joined(Safe.items(half)), "x1 false x3", "an index that raises is a null entry")
end)

test("items: a container without a length is still walked by its indexes", function()
    R.new()
    local no_len = setmetatable({}, { __index = function(_, i) if i <= 2 then return "v" .. i end end })
    eq(joined(Safe.items(no_len)), "v1 v2", "ipairs")
end)

test("list: an array without get_Count is read from its elements container", function()
    R.new({ containers = true })
    local arr = R.object("app.HumanSkillContext.EquipedSkill[]")
    arr.items = { "s1", "s2", "s3" }
    eq(joined(Safe.list(arr)), "s1 s2 s3", "elements")
    eq(joined(Safe.list(arr, 2)), "s1 s2", "capped")
    eq(joined(Safe.list(R.list({ "p1", "p2" }))), "p1 p2", "a List still by get_Count/get_Item")
end)

test("enum: a number, or the value__ of a boxed enum, as an integer", function()
    R.new()
    eq(Safe.enum(3), 3, "a number")
    eq(math.type(Safe.enum(3.0)), "integer", "a float from the game is an integer")
    eq(Safe.enum(-1), -1, "negative")
    eq(Safe.enum(R.object("app.AttackUserData.ElementType", { value__ = 64 })), 64, "a boxed enum")
    eq(math.type(Safe.enum(R.object("x", { value__ = 4.0 }))), "integer", "a boxed float")
    eq(Safe.enum("x"), nil, "a string")
    eq(Safe.enum(nil), nil, "nothing")
    eq(Safe.enum(true), nil, "a boolean")
    eq(Safe.enum(2.5), nil, "not a whole number")
    eq(Safe.enum(0 / 0), nil, "NaN")
    eq(Safe.enum(math.huge), nil, "infinity")
    eq(Safe.enum(R.object("x", {})), nil, "an object without value__")
    eq(Safe.enum(R.object("x", { value__ = "3" })), nil, "a value__ that is no number")
    local poisoned = R.object("x", { value__ = 3 })
    poisoned.poison = true
    eq(Safe.enum(poisoned), nil, "an object that raises")
end)

T.finish()
