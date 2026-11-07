package.path = "mod/reframework/autorun/?.lua;tests/?.lua;" .. package.path

local T = require("testlib")
local test, eq = T.test, T.eq
local R = require("stubs/reframework")
local enemies = require("DD2DamageMeter/game/enemies")

local PARAM = "getActiveRegionParam(System.Int32)"

local function world()
    R.new()
    enemies.reset()
end

local function boxed(type_name, v) return R.object(type_name, { value__ = v }, {}) end

-- An enemy as the game gives it: a character whose damage calculator answers with `o` (weak, resist, defence,
-- magic_defence, rsc) and whose status condition control has the enabled mask `o.enabled`; and its Actor.
local function enemy(id, o)
    o = o or {}
    local c = R.character{ go = "ch227001_50_1", chara_id = id }
    local calc = R.object("app.ExceptPlayerDamageCalculator", {}, {
        get_WeakPointSettings = function() return o.weak end,
        get_ResistSettings = function() return o.resist end,
        get_Defence = function() return o.defence end,
        get_MagicDefence = function() return o.magic_defence end,
        get_RegionStatusCtrl = function() return o.rsc end,
    })
    local sc = R.object("app.StatusConditionCtrl", { EnableStatusConditionFlag = o.enabled }, {})
    c.methods.get_DamageCalculator = function()
        if o.no_calc then return nil end
        return calc
    end
    c.methods.get_StatusConditionCtrl = function() return sc end
    return c, { key = "a" .. c.addr, kind = "enemy", chara_id = id }
end

-- The Vurdalak as read in the game.
local function vurdalak(id)
    return enemy(id or 2270, { weak = 130, resist = 0, defence = 300, magic_defence = 300, enabled = 8395888 })
end

local function count_of(sig) return #R.calls_of(sig) end

test("reads the Vurdalak once", function()
    world()
    local c, a = vurdalak()
    local d = enemies.data(c, a)
    eq(d.chara_id, 2270, "the CharaID")
    eq(d.weak, 130, "weak: Blow + Light")
    eq(d.resist, 0, "resist")
    eq(d.defence, 300, "defence")
    eq(d.magic_defence, 300, "magic defence")
    eq(d.enabled, 8395888, "the status mask")
    eq(math.type(d.weak), "integer", "flags are integers")
    for k, v in pairs(d) do eq(type(v), "number", k .. " is plain data") end
    local n = #R.calls
    eq(enemies.data(c, a), d, "the same table")
    eq(#R.calls, n, "the second call makes no game call")
    -- another Vurdalak is the same kind
    local c2, a2 = vurdalak()
    n = #R.calls
    eq(enemies.data(c2, a2), d, "another instance, the same record")
    eq(#R.calls, n, "nothing read")
end)

test("two hobgoblin variants are two records", function()
    world()
    local c1, a1 = enemy(5201, { weak = 64, resist = 16, defence = 250, magic_defence = 250 })
    local c2, a2 = enemy(5301, { weak = 64, resist = 16, defence = 150, magic_defence = 150 })
    local d1, d2 = enemies.data(c1, a1), enemies.data(c2, a2)
    eq(d1.defence, 250, "5201")
    eq(d2.defence, 150, "5301")
    eq(d1.chara_id, 5201, "its own id")
    eq(d2.chara_id, 5301, "its own id")
    eq(d1 ~= d2, true, "two records")
    eq(enemies.data(c1, a1), d1, "each is kept")
    eq(enemies.data(c2, a2), d2, "each is kept")
end)

test("boxed flags read value__", function()
    world()
    local c, a = enemy(5201, {
        weak = boxed("app.CharacterWeakpointType", 64), resist = boxed("app.CharacterWeakpointType", 16),
        defence = 250, magic_defence = 250,
        enabled = boxed("app.StatusConditionDef.StatusConditionFlag", 8395888),
    })
    local d = enemies.data(c, a)
    eq(d.weak, 64, "boxed weak")
    eq(d.resist, 16, "boxed resist")
    eq(d.enabled, 8395888, "boxed mask")
end)

test("what the game does not give stays nil, the flags count", function()
    world()
    local c, a = enemy(5201, { weak = 64, resist = 16 })
    local d = enemies.data(c, a)
    eq(d.weak, 64, "flags read")
    eq(d.defence, nil, "no defence")
    eq(d.magic_defence, nil, "no magic defence")
    eq(d.enabled, nil, "no mask")
    eq(enemies.data(c, a), d, "it counts as read")
    -- not numbers: nothing is made up
    local c2, a2 = enemy(5202, { weak = 64, resist = 16, defence = "x", magic_defence = 0 / 0 })
    local d2 = enemies.data(c2, a2)
    eq(d2.defence, nil, "a defence that is no number")
    eq(d2.magic_defence, nil, "NaN")
end)

test("unreadable calculator: nil, tried at most 3 times", function()
    world()
    local c, a = enemy(5201, { no_calc = true })
    for i = 1, 4 do eq(enemies.data(c, a), nil, "call " .. i) end
    eq(count_of("get_DamageCalculator"), 3, "the calculator was asked 3 times")
    -- flags that are not integers do not count either
    local c2, a2 = enemy(5202, { weak = 64, resist = nil, defence = 100 })
    for i = 1, 5 do eq(enemies.data(c2, a2), nil, "no resist " .. i) end
    eq(count_of("get_DamageCalculator"), 6, "3 more for the other kind")
    local c3, a3 = enemy(5203, { weak = 2.5, resist = "x" })
    eq(enemies.data(c3, a3), nil, "not integers")
    -- the tries belong to the CharaID, not to the character
    local c4, a4 = enemy(5201, { weak = 64, resist = 16 })
    eq(enemies.data(c4, a4), nil, "5201 gave up")
    -- reset gives it another go
    enemies.reset()
    eq(enemies.data(c4, a4).weak, 64, "after a reset")
end)

test("a read that fails and then works counts once it works", function()
    world()
    local o = { weak = nil, resist = 16, defence = 90 }
    local c, a = enemy(5201, o)
    eq(enemies.data(c, a), nil, "first try")
    o.weak = 64
    local d = enemies.data(c, a)
    eq(d.weak, 64, "second try")
    eq(d.defence, 90, "with the rest")
    local n = #R.calls
    eq(enemies.data(c, a), d, "kept")
    eq(#R.calls, n, "no game call")
end)

test("no CharaID: nil, nothing read", function()
    world()
    local c = vurdalak()
    eq(enemies.data(c, { key = "a1", kind = "enemy" }), nil, "an actor without a CharaID")
    eq(enemies.data(c, nil), nil, "no actor")
    eq(#R.calls, 0, "nothing was read")
    eq(enemies.data(nil, { key = "a1", chara_id = 2270 }), nil, "no character")
    eq(#R.calls, 0, "nothing was read")
    -- a missing character is no try: the next hit may bring one
    local c2, a2 = vurdalak(2271)
    for _ = 1, 5 do enemies.data(nil, a2) end
    eq(enemies.data(c2, a2).weak, 130, "still readable")
end)

test("a character missing later still gets the record that is known", function()
    world()
    local c, a = vurdalak()
    local d = enemies.data(c, a)
    eq(enemies.data(nil, a), d, "the attacker's character could not be named, the kind is known")
end)

test("reset forgets", function()
    world()
    local c, a = vurdalak()
    local d = enemies.data(c, a)
    enemies.reset()
    local n = count_of("get_DamageCalculator")
    local d2 = enemies.data(c, a)
    eq(count_of("get_DamageCalculator"), n + 1, "read again")
    eq(d2 ~= d, true, "a new record")
    eq(d2.weak, 130, "with the same values")
    eq(d.weak, 130, "the old one is untouched")
end)

-- A RegionStatusCtrl whose parts are `params[region number]`.
local function with_parts(params)
    return R.object("app.RegionStatusCtrl", {}, {
        [PARAM] = function(_, no) return params[no] end,
    })
end

local function region(type_by_getter, type_by_field)
    local methods = {}
    if type_by_getter ~= nil then methods.get_RegionType = function() return type_by_getter end end
    return R.object("app.IntermediateRegionParam", { _RegionType = type_by_field }, methods)
end

test("part types", function()
    world()
    local rsc = with_parts({
        [0] = region(0), [1] = region(1), [2] = region(2),
        [4] = region(boxed("app.IntermediateRegionParam.RegionTypeEnum", 0)),
        [5] = region(nil, 1),   -- the getter is missing: the field
        [6] = region(nil, nil), -- nothing to read
        [7] = region(9),        -- a type the mod has no word for
    })
    local c, a = enemy(2270, { rsc = rsc })
    eq(enemies.part(c, a, 0), "head", "0 is the head")
    eq(enemies.part(c, a, 1), "body", "1 is the body")
    eq(enemies.part(c, a, 2), "other", "2 is the rest")
    eq(enemies.part(c, a, 3), nil, "no param for the region")
    eq(enemies.part(c, a, 4), "head", "a boxed type")
    eq(enemies.part(c, a, 5), "body", "the field when there is no getter")
    eq(enemies.part(c, a, 6), nil, "a type that cannot be read")
    eq(enemies.part(c, a, 7), nil, "an unknown type")
    eq(enemies.part(c, a, nil), nil, "no region number")
    eq(enemies.part(c, a, 1.5), nil, "not a whole number")
    -- remembered: nothing is asked again, the unanswered regions included
    local n = #R.calls
    for no = 0, 7 do enemies.part(c, a, no) end
    eq(#R.calls, n, "the second call makes no game call")
    eq(enemies.part(c, a, 0), "head", "and still the same")
    -- the game's answer is for the kind: another instance asks nothing either
    local c2, a2 = enemy(2270, { rsc = rsc })
    eq(enemies.part(c2, a2, 2), "other", "another instance of the kind")
    eq(#R.calls, n, "nothing asked")
    -- the same region of another kind is read on its own
    local c3, a3 = enemy(2271, { rsc = with_parts({ [0] = region(2) }) })
    eq(enemies.part(c3, a3, 0), "other", "another kind, its own table")
end)

test("part: no CharaID or no character is nil, a control that cannot be reached is tried 3 times", function()
    world()
    local rsc = with_parts({ [0] = region(0) })
    local c, a = enemy(2270, { rsc = rsc })
    eq(enemies.part(c, { key = "a1", kind = "enemy" }, 0), nil, "no CharaID")
    eq(enemies.part(c, nil, 0), nil, "no actor")
    eq(#R.calls, 0, "nothing read")
    eq(enemies.part(nil, a, 0), nil, "no character")
    eq(#R.calls, 0, "no character, nothing asked, no try used")
    -- the control cannot be reached now (an enemy still loading), and is later
    local o = { rsc = nil }
    local c2, a2 = enemy(2271, o)
    eq(enemies.part(c2, a2, 0), nil, "no control")
    o.rsc = with_parts({ [0] = region(1) })
    eq(enemies.part(c2, a2, 0), "body", "asked again and found")
    -- a character without a calculator, or a control that never comes: 3 tries per region, then it is left alone
    local c3, a3 = enemy(2272, { no_calc = true })
    for _ = 1, 5 do eq(enemies.part(c3, a3, 0), nil, "no calculator") end
    eq(count_of("get_DamageCalculator"), 2 + 3, "the first two above, then 3 for this one")
    for _ = 1, 4 do eq(enemies.part(c3, a3, 1), nil, "another region, its own tries") end
    eq(count_of("get_DamageCalculator"), 2 + 3 + 3, "3 more")
    -- a control that answers "no such region" is an answer
    local c4, a4 = enemy(2273, { rsc = with_parts({}) })
    local asked = count_of(PARAM)
    for _ = 1, 4 do eq(enemies.part(c4, a4, 0), nil, "no such region") end
    eq(count_of(PARAM), asked + 1, "asked once")
end)

test("part: remembered entries are bounded", function()
    world()
    local head = region(0)
    local c, a = enemy(2270, { rsc = R.object("app.RegionStatusCtrl", {}, { [PARAM] = function() return head end }) })
    for no = 0, 4095 do eq(enemies.part(c, a, no), "head", "region " .. no) end
    local n = count_of(PARAM)
    eq(enemies.part(c, a, 0), "head", "4096 entries are all kept")
    eq(count_of(PARAM), n, "nothing asked")
    eq(enemies.part(c, a, 4096), "head", "one more")
    -- past the cap the memory starts afresh
    eq(enemies.part(c, a, 1), "head", "an older one")
    eq(count_of(PARAM), n + 2, "was read again")
    eq(enemies.part(c, a, 1), "head", "and is kept again")
    eq(count_of(PARAM), n + 2, "nothing more")
end)

test("reset forgets the parts too", function()
    world()
    local c, a = enemy(2270, { rsc = with_parts({ [0] = region(0) }) })
    eq(enemies.part(c, a, 0), "head", "read")
    local n = count_of(PARAM)
    enemies.reset()
    eq(enemies.part(c, a, 0), "head", "read again")
    eq(count_of(PARAM), n + 1, "asked again after a reset")
end)

test("nothing raises when the game does", function()
    world()
    local c, a = vurdalak()
    c.methods.get_DamageCalculator = function() error("boom") end
    eq(enemies.data(c, a), nil, "data")
    eq(enemies.part(c, a, 0), nil, "part")
    local poisoned = R.object("app.Character", {}, {})
    poisoned.poison = true
    eq(enemies.data(poisoned, { chara_id = 1 }), nil, "a poisoned character")
    eq(enemies.part(poisoned, { chara_id = 1 }, 0), nil, "a poisoned character, part")
end)

T.finish()
