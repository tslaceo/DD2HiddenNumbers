package.path = "mod/reframework/autorun/?.lua;tests/?.lua;" .. package.path

local T = require("testlib")
local test, eq = T.test, T.eq
local R = require("stubs/reframework")
local EnemyTable = require("DD2DamageMeter/game/enemy_table")

local ACTIVE = "getActiveRegionParam(System.Int32)"
local PYS = "getDamageAdjustRatePys(app.AttackUserData.AttrPhysicsEnum)"
local MGC = "getDamageAdjustRateMgc(app.AttackUserData.ElementType)"
local HEAD, BODY, OTHER = 0, 1, 2   -- app.IntermediateRegionParam.RegionTypeEnum
local WEAK = 256                    -- IntermediateRegionParam.AttributeFlags.WeakRegion_SE_Effect_Ability

local function world()
    R.new()
    EnemyTable.reset()
end

-- A Single[] field as the game gives it: an array whose elements are boxed, their ToString the number (the fields
-- were read so in the game).
local function singles(values)
    local arr = R.object("System.Single[]", {}, {})
    arr.items = {}
    for i, v in ipairs(values) do
        arr.items[i] = R.object("System.Single", {}, { ToString = function() return tostring(v) end })
    end
    return arr
end

-- A part (app.IntermediateRegionParam): o.no, o.type, o.attr, o.pys { Slash, Blow, Shoot }, o.mgc { Magic, Fire, Ice,
-- Thunder, Light }, in its fields and through its getters; o.fields_only: the getters give nothing.
local function part(o)
    local methods = {}
    if not o.fields_only then
        methods.get_RegionNo = function() return o.no end
        methods.get_RegionType = function() return o.type end
        methods[PYS] = function(_, i) return o.pys[i + 1] end
        methods[MGC] = function(_, i) return o.mgc[i + 1] end
    end
    return R.object("app.IntermediateRegionParam", {
        _RegionNo = o.no, _RegionType = o.type, _Attr = o.attr or 0,
        _DamageAdjustRatePys = singles(o.pys), _DamageAdjustRateMgc = singles(o.mgc),
    }, methods)
end

local function same_mgc(v) return { v, v, v, v, v } end

-- A RegionStatusCtrl in the state o.prio: get_RegionStatusDataProp lists o.states ({ id, parts }), and
-- getActiveRegionParam(no) answers with the part numbered `no` of the state o.prio; when it has none, with that of the
-- state o.fallback (a lookup that falls back to a base state, not known in the game), else nil. o.template is its
-- Data field (the prefab's template).
local function control(o)
    local states = {}
    for i, s in ipairs(o.states) do
        local list = R.list(s.parts, "System.Collections.Generic.List`1<app.IntermediateRegionParam>")
        states[i] = R.object("app.IntermediateRegionStatusParam", { _StatusId = s.id }, {
            get_StatusId = function() return s.id end,
            get_IntermediateRegionParams = function() return list end,
        })
    end
    local list = R.list(states, "System.Collections.Generic.List`1<app.IntermediateRegionStatusParam>")
    local data = R.object("app.IntermediateRegionStatusData", {}, {
        get_IntermediateRegionStatusParams = function() return list end,
    })
    return R.object("app.RegionStatusCtrl", { Data = o.template }, {
        get_PrioStatusId = function() return o.prio end,
        get_RegionStatusDataProp = function() return data end,
        [ACTIVE] = function(_, no)
            for _, id in ipairs({ o.prio, o.fallback }) do
                for _, s in ipairs(o.states) do
                    if s.id == id then
                        for _, p in ipairs(s.parts) do
                            if p.fields._RegionNo == no then return p end
                        end
                    end
                end
            end
            return nil
        end,
    })
end

-- An enemy as the game gives it: a character whose damage calculator has the RegionStatusCtrl `rsc`.
local function enemy(id, rsc)
    local c = R.character{ go = "ch227001_50_1", chara_id = id }
    local calc = R.object("app.ExceptPlayerDamageCalculator", {}, {
        get_RegionStatusCtrl = function() return rsc end,
    })
    c.methods.get_DamageCalculator = function() return calc end
    return c
end

-- One state, "Normal", with these parts.
local function normal(parts) return control{ prio = "Normal", states = { { id = "Normal", parts = parts } } } end

-- The Wight (Vurdalak) as read in the game: body and head.
local WIGHT_MGC = { 0.7, 0.7, 0.7, 0.5, 1.5 }
local function wight_parts()
    return {
        part{ no = 0, type = BODY, pys = { 0.75, 0.75, 0.6 }, mgc = WIGHT_MGC },
        part{ no = 1, type = HEAD, pys = { 1, 1, 0.8 }, mgc = WIGHT_MGC },
    }
end

local function reads() return #R.calls_of("get_DamageCalculator") end

-- Only plain tables, numbers and strings.
local function plain(v, where)
    if type(v) == "table" then
        eq(getmetatable(v), nil, where .. " is a plain table")
        for k, x in pairs(v) do
            plain(k, where .. " key")
            plain(x, where .. "." .. tostring(k))
        end
    else
        eq(type(v) == "number" or type(v) == "string", true, where .. " is a number or a string")
    end
end

test("reads the Wight's body", function()
    world()
    local c = enemy(2270, normal(wight_parts()))
    local t = EnemyTable.read(c, 2270, 10)
    eq(t.chara_id, 2270, "the CharaID")
    eq(t.state, "Normal", "the state is get_PrioStatusId")
    eq(t.body.Slash, 0.75, "body Slash")
    eq(t.body.Blow, 0.75, "body Blow")
    eq(t.body.Shoot, 0.6, "body Shoot")
    eq(t.body.Magic, 0.7, "body Magic")
    eq(t.body.Fire, 0.7, "body Fire")
    eq(t.body.Ice, 0.7, "body Ice")
    eq(t.body.Thunder, 0.5, "body Thunder")
    eq(t.body.Light, 1.5, "body Light")
    eq(t.body.Dark, nil, "Dark has no column")
    eq(#t.parts, 1, "one part kind")
    eq(t.parts[1].kind, "head", "the head")
    eq(t.parts[1].mult.Slash, 1, "head Slash")
    eq(t.parts[1].mult.Shoot, 0.8, "head Shoot")
    eq(t.parts[1].mult.Light, 1.5, "head Light")
    plain(t, "Table")
    eq(EnemyTable.cached(2270), t, "cached")
end)

test("the body is the Body part with the smallest RegionNo", function()
    world()
    local c = enemy(2270, normal({
        part{ no = 2, type = BODY, attr = 128, pys = { 0.5, 0.5, 0.5 }, mgc = same_mgc(0.5) },
        part{ no = 0, type = BODY, pys = { 0.75, 0.75, 0.6 }, mgc = WIGHT_MGC },
    }))
    local t = EnemyTable.read(c, 2270, 10)
    eq(t.body.Slash, 0.75, "r0, not r2")
    eq(t.body.Thunder, 0.5, "r0's elements")
    eq(t.body.Light, 1.5, "r0's Light")
    eq(#t.parts, 0, "Body parts are no part line")
end)

test("a weak-region part is weak even when it is a head", function()
    world()
    local c = enemy(2270, normal({
        part{ no = 0, type = BODY, pys = { 1, 1, 1 }, mgc = same_mgc(1) },
        part{ no = 1, type = HEAD, attr = WEAK, pys = { 1.5, 1.5, 1.2 }, mgc = same_mgc(1) },
    }))
    local t = EnemyTable.read(c, 2270, 10)
    eq(#t.parts, 1, "one part kind")
    eq(t.parts[1].kind, "weak", "the flag wins over the head")
    eq(t.parts[1].mult.Slash, 1.5, "its values")
    -- the flag is one bit of _Attr: the real Wight's r3 has 384 (256 + 128); 128 alone is no weak spot
    world()
    c = enemy(2270, normal({
        part{ no = 0, type = BODY, attr = 128, pys = { 1, 1, 1 }, mgc = same_mgc(1) },
        part{ no = 3, type = HEAD, attr = 384, pys = { 2, 1, 1 }, mgc = same_mgc(1) },
        part{ no = 4, type = HEAD, attr = 128, pys = { 1.3, 1, 1 }, mgc = same_mgc(1) },
    }))
    t = EnemyTable.read(c, 2270, 10)
    eq(t.body.Slash, 1, "a Body part with 128 is the body")
    eq(#t.parts, 2, "weak and head")
    eq(t.parts[1].kind, "weak", "384 is weak")
    eq(t.parts[1].mult.Slash, 2, "r3")
    eq(t.parts[2].kind, "head", "128 is a plain head")
    eq(t.parts[2].mult.Slash, 1.3, "r4")
end)

test("parts of one kind merge by the largest value per type", function()
    world()
    local c = enemy(2530, normal({
        part{ no = 0, type = BODY, pys = { 1, 1, 1 }, mgc = same_mgc(1) },
        part{ no = 1, type = HEAD, pys = { 1, 1, 1.2 }, mgc = { 1, 0.8, 1, 1.2, 1 } },
        part{ no = 3, type = HEAD, pys = { 1.3, 0.9, 1 }, mgc = { 1, 1.5, 1, 1, 1 } },
        part{ no = 5, type = OTHER, attr = WEAK, pys = { 0.4, 0.3, 0.25 }, mgc = { 0.9, 1, 0.45, 0.2, 0.9 } },
        part{ no = 6, type = OTHER, attr = WEAK, pys = { 0.35, 0.35, 0.25 }, mgc = { 0.7, 0.8, 0.5, 0.15, 0.7 } },
    }))
    local t = EnemyTable.read(c, 2530, 10)
    eq(#t.parts, 2, "two kinds, one entry each")
    local weak, head = t.parts[1], t.parts[2]
    eq(weak.kind, "weak", "weak first")
    eq(head.kind, "head", "then the head")
    eq(head.mult.Slash, 1.3, "Slash of r3")
    eq(head.mult.Blow, 1, "Blow of r1")
    eq(head.mult.Shoot, 1.2, "Shoot of r1")
    eq(head.mult.Fire, 1.5, "Fire of r3")
    eq(head.mult.Thunder, 1.2, "Thunder of r1")
    eq(weak.mult.Slash, 0.4, "Slash of r5")
    eq(weak.mult.Blow, 0.35, "Blow of r6")
    eq(weak.mult.Ice, 0.5, "Ice of r6")
    eq(weak.mult.Thunder, 0.2, "Thunder of r5")
    eq(t.body.Slash, 1, "the body is not merged in")
end)

test("Other parts without the weak flag are left out", function()
    world()
    local c = enemy(2530, normal({
        part{ no = 0, type = BODY, pys = { 1, 1, 1 }, mgc = same_mgc(1) },
        part{ no = 4, type = OTHER, attr = 512, pys = { 2, 1.8, 1.2 }, mgc = { 1, 2.5, 1.5, 0.9, 1 } },
        part{ no = 8, type = OTHER, pys = { 0.1, 0.1, 0.1 }, mgc = same_mgc(0.1) },
    }))
    local t = EnemyTable.read(c, 2530, 10)
    eq(#t.parts, 0, "no part line")
    eq(t.body.Slash, 1, "the body only")
end)

test("no Body part: the body is the Other part, parts as read", function()
    world()
    -- a Griffin-like table: heads and others, no Body part
    local c = enemy(2530, normal({
        part{ no = 1, type = OTHER, attr = 512, pys = { 0.2, 0.15, 0.1 }, mgc = { 0.2, 0.4, 0.15, 0.1, 0.2 } },
        part{ no = 7, type = HEAD, attr = 268, pys = { 0.5, 0.4, 0.3 }, mgc = { 0.6, 1.2, 0.5, 0.2, 0.6 } },
        part{ no = 12, type = HEAD, pys = { 1, 0.8, 0.35 }, mgc = { 1, 2, 1.5, 0.6, 1 } },
    }))
    local t = EnemyTable.read(c, 2530, 10)
    eq(t.body.Slash, 0.2, "r1: 512 is no weak bit")
    eq(t.body.Fire, 0.4, "r1 Fire")
    eq(#t.parts, 2, "parts as read")
    eq(t.parts[1].kind, "weak", "r7: 268 has the weak bit")
    eq(t.parts[1].mult.Fire, 1.2, "r7 Fire")
    eq(t.parts[2].kind, "head", "r12")
    eq(t.parts[2].mult.Fire, 2, "r12 Fire")
    plain(t, "Table")
end)

test("no Body or Other part: body is empty, parts as read", function()
    world()
    local c = enemy(2530, normal({
        part{ no = 7, type = HEAD, attr = 268, pys = { 0.5, 0.4, 0.3 }, mgc = { 0.6, 1.2, 0.5, 0.2, 0.6 } },
        part{ no = 12, type = HEAD, pys = { 1, 0.8, 0.35 }, mgc = { 1, 2, 1.5, 0.6, 1 } },
    }))
    local t = EnemyTable.read(c, 2530, 10)
    eq(next(t.body), nil, "body is empty")
    eq(#t.parts, 2, "parts as read")
    eq(t.parts[1].kind, "weak", "r7")
    eq(t.parts[2].kind, "head", "r12")
    plain(t, "Table")
end)

-- The Ghoul of the probe (a live ghoul, state Normal only): r0 and r2 Other, r1 and r3 Head with _Attr 4
-- (ShootOnRankUp); no Body part at all.
test("the Ghoul: its body is its Other r0, the head as before", function()
    world()
    local ghoul_mgc = { 1, 1, 1, 1, 1.2 }
    local c = enemy(221427977, normal({
        part{ no = 0, type = OTHER, pys = { 1, 1, 1 }, mgc = ghoul_mgc },
        part{ no = 1, type = HEAD, attr = 4, pys = { 1, 1, 1.2 }, mgc = ghoul_mgc },
        part{ no = 2, type = OTHER, pys = { 1, 1, 1 }, mgc = ghoul_mgc },
        part{ no = 3, type = HEAD, attr = 4, pys = { 1, 1, 1.2 }, mgc = ghoul_mgc },
    }))
    local t = EnemyTable.read(c, 221427977, 10)
    for _, jt in ipairs({ "Slash", "Blow", "Shoot", "Magic", "Fire", "Ice", "Thunder" }) do
        eq(t.body[jt], 1, "body " .. jt)
    end
    eq(t.body.Light, 1.2, "body Light")
    eq(#t.parts, 1, "one part kind")
    eq(t.parts[1].kind, "head", "the head")
    eq(t.parts[1].mult.Shoot, 1.2, "head Shoot")
    eq(t.parts[1].mult.Slash, 1, "head Slash")
    eq(t.parts[1].mult.Light, 1.2, "head Light")
    plain(t, "Table")
end)

test("no Body part: the Other part with the smallest RegionNo", function()
    world()
    local c = enemy(2530, normal({
        part{ no = 2, type = OTHER, pys = { 0.5, 0.5, 0.5 }, mgc = same_mgc(0.5) },
        part{ no = 0, type = OTHER, pys = { 0.8, 0.9, 1.1 }, mgc = same_mgc(1.3) },
    }))
    local t = EnemyTable.read(c, 2530, 10)
    eq(t.body.Slash, 0.8, "r0, not r2")
    eq(t.body.Shoot, 1.1, "r0's Shoot")
    eq(t.body.Fire, 1.3, "r0's elements")
    eq(#t.parts, 0, "plain Other parts are no part line")
end)

test("no Body part: a plain Other part before a weak one", function()
    world()
    local c = enemy(2530, normal({
        part{ no = 0, type = OTHER, attr = WEAK, pys = { 2, 2, 2 }, mgc = same_mgc(2) },
        part{ no = 1, type = OTHER, pys = { 0.7, 0.7, 0.7 }, mgc = same_mgc(0.9) },
    }))
    local t = EnemyTable.read(c, 2530, 10)
    eq(t.body.Slash, 0.7, "r1, not the weak r0")
    eq(t.body.Ice, 0.9, "r1's elements")
    eq(#t.parts, 1, "the weak part stays")
    eq(t.parts[1].kind, "weak", "r0 is weak")
    eq(t.parts[1].mult.Slash, 2, "r0's values")
end)

test("no Body part and only weak Other parts: the smallest weak one", function()
    world()
    local c = enemy(2530, normal({
        part{ no = 5, type = OTHER, attr = WEAK, pys = { 1.5, 1.5, 1.5 }, mgc = same_mgc(1.5) },
        part{ no = 3, type = OTHER, attr = WEAK, pys = { 1.2, 1.1, 1 }, mgc = same_mgc(0.6) },
        part{ no = 8, type = HEAD, pys = { 1, 1, 1 }, mgc = same_mgc(1) },
    }))
    local t = EnemyTable.read(c, 2530, 10)
    eq(t.body.Slash, 1.2, "r3, not r5")
    eq(t.body.Blow, 1.1, "r3's Blow")
    eq(t.body.Magic, 0.6, "r3's elements")
    eq(#t.parts, 2, "weak and head")
    eq(t.parts[1].kind, "weak", "the weak parts as before")
    eq(t.parts[1].mult.Slash, 1.5, "merged: r5's Slash")
    eq(t.parts[1].mult.Magic, 1.5, "merged: r5's Magic")
    eq(t.parts[2].kind, "head", "r8")
end)

test("a Body part still wins over Other parts", function()
    world()
    local c = enemy(2530, normal({
        part{ no = 0, type = OTHER, pys = { 0.3, 0.3, 0.3 }, mgc = same_mgc(0.3) },
        part{ no = 1, type = OTHER, attr = WEAK, pys = { 1.8, 1.8, 1.8 }, mgc = same_mgc(1.8) },
        part{ no = 4, type = BODY, pys = { 0.75, 0.75, 0.6 }, mgc = WIGHT_MGC },
    }))
    local t = EnemyTable.read(c, 2530, 10)
    eq(t.body.Slash, 0.75, "r4, the Body part")
    eq(t.body.Shoot, 0.6, "r4's Shoot")
    eq(t.body.Light, 1.5, "r4's Light")
    eq(#t.parts, 1, "the weak part stays")
    eq(t.parts[1].mult.Slash, 1.8, "r1")
end)

-- The Fallen dragon of the collector (ch258002_20): no Body part, twelve Other parts; 0 and 1 ×0 for every type, 2
-- ×1.2, 3 and 4 ×1, 5 and 6 ×0.75, 7-11 ×0.
local DRAGON = 2785844815
local function dragon_parts()
    local by_no = { [0] = 0, 0, 1.2, 1, 1, 0.75, 0.75, 0, 0, 0, 0, 0 }
    local out = {}
    for no = 0, 11 do
        local v = by_no[no]
        out[#out + 1] = part{ no = no, type = OTHER, pys = { v, v, v }, mgc = same_mgc(v) }
    end
    return out
end

test("the Fallen dragon: the body skips the parts that take no damage, its part 2", function()
    world()
    local t = EnemyTable.read(enemy(DRAGON, normal(dragon_parts())), DRAGON, 10)
    for _, jt in ipairs({ "Slash", "Blow", "Shoot", "Magic", "Fire", "Ice", "Thunder", "Light" }) do
        eq(t.body[jt], 1.2, "r2 " .. jt .. ", not the ×0 of r0")
    end
    eq(#t.parts, 0, "plain Other parts are no part line")
    plain(t, "Table")
    -- one type above 0 is damage taken: such a part is no part to skip
    world()
    t = EnemyTable.read(enemy(2530, normal({
        part{ no = 0, type = OTHER, pys = { 0, 0, 0 }, mgc = { 0, 0, 0, 0, 0.5 } },
        part{ no = 1, type = OTHER, pys = { 1, 1, 1 }, mgc = same_mgc(1) },
    })), 2530, 10)
    eq(t.body.Light, 0.5, "r0: its Light is taken")
    eq(t.body.Slash, 0, "r0's Slash")
    -- the skip comes first: a weak Other part that takes damage before a plain one that takes none
    world()
    t = EnemyTable.read(enemy(2530, normal({
        part{ no = 0, type = OTHER, pys = { 0, 0, 0 }, mgc = same_mgc(0) },
        part{ no = 4, type = OTHER, attr = WEAK, pys = { 1.5, 1.4, 1.3 }, mgc = same_mgc(1.1) },
    })), 2530, 10)
    eq(t.body.Slash, 1.5, "the weak r4, not the ×0 r0")
    eq(t.body.Fire, 1.1, "r4's elements")
    eq(#t.parts, 1, "the weak part stays")
    eq(t.parts[1].mult.Slash, 1.5, "r4 as the weak line")
end)

test("every Other part takes no damage: the body as if none were skipped, the smallest plain one", function()
    world()
    -- the dragon with every part at ×0; only r0 gives the elements, so the parts can be told apart
    local parts = {}
    for no = 0, 11 do
        parts[#parts + 1] = part{ no = no, type = OTHER, pys = { 0, 0, 0 }, mgc = no == 0 and same_mgc(0) or {} }
    end
    local t = EnemyTable.read(enemy(DRAGON, normal(parts)), DRAGON, 10)
    eq(t.body.Slash, 0, "×0")
    eq(t.body.Light, 0, "r0: the only part with the elements")
    -- and the plain one before the weak one: the body is a plain Other part first
    world()
    t = EnemyTable.read(enemy(2530, normal({
        part{ no = 0, type = OTHER, attr = WEAK, pys = { 0, 0, 0 }, mgc = same_mgc(0) },
        part{ no = 3, type = OTHER, pys = { 0, 0, 0 }, mgc = {} },
    })), 2530, 10)
    eq(t.body.Slash, 0, "×0")
    eq(t.body.Light, nil, "r3, not the weak r0")
end)

test("a Body part that takes no damage is still the body", function()
    world()
    local t = EnemyTable.read(enemy(2530, normal({
        part{ no = 0, type = OTHER, pys = { 1.2, 1.2, 1.2 }, mgc = same_mgc(1.2) },
        part{ no = 5, type = BODY, pys = { 0, 0, 0 }, mgc = same_mgc(0) },
    })), 2530, 10)
    eq(t.body.Slash, 0, "r5, the Body part, ×0")
    eq(t.body.Light, 0, "r5's elements")
end)

test("read at most once a second per kind", function()
    world()
    local c = enemy(2270, normal(wight_parts()))
    local t1 = EnemyTable.read(c, 2270, 10)
    eq(reads(), 1, "the first read")
    eq(EnemyTable.read(c, 2270, 10.5), t1, "half a second later: the same Table")
    eq(reads(), 1, "one game read")
    local t2 = EnemyTable.read(c, 2270, 11.0)
    eq(reads(), 2, "a second later: read again")
    eq(t2 ~= t1, true, "a new Table")
    eq(t2.body.Slash, 0.75, "with the values")
    eq(EnemyTable.cached(2270), t2, "the newest is cached")
    -- another kind is read on its own
    local c2 = enemy(2271, normal(wight_parts()))
    eq(EnemyTable.read(c2, 2271, 11.2).chara_id, 2271, "another kind")
    eq(reads(), 3, "read at once")
    -- a clock that went back reads again
    EnemyTable.read(c, 2270, 5)
    eq(reads(), 4, "an earlier t")
end)

test("a character that raises keeps the cached table", function()
    world()
    local c = enemy(2270, normal(wight_parts()))
    local t = EnemyTable.read(c, 2270, 10)
    c.methods.get_DamageCalculator = function() error("boom") end
    eq(EnemyTable.read(c, 2270, 11), t, "the same Table")
    eq(EnemyTable.cached(2270), t, "still cached")
    c.poison = true   -- every call on it raises (a despawned enemy)
    eq(EnemyTable.read(c, 2270, 12), t, "a poisoned character")
    -- a failed read waits its second too
    local n = reads()
    eq(EnemyTable.read(c, 2270, 12.5), t, "between")
    eq(reads(), n, "nothing asked")
end)

test("an unreadable first read gives nil and cached nil", function()
    world()
    local c = enemy(2270, nil)   -- a calculator without its RegionStatusCtrl
    eq(EnemyTable.read(c, 2270, 10), nil, "no control")
    eq(EnemyTable.cached(2270), nil, "nothing cached")
    local c2 = R.character{ go = "ch227001_50_2", chara_id = 2271 }   -- no damage calculator
    eq(EnemyTable.read(c2, 2271, 10), nil, "no calculator")
    eq(EnemyTable.cached(2271), nil, "nothing cached")
    local c3 = enemy(2272, control{ prio = "Normal", states = {} })
    eq(EnemyTable.read(c3, 2272, 10), nil, "no state in the table")
    -- no state of that name in the table
    local c4 = enemy(2273, control{ prio = "Angry", states = { { id = "Normal", parts = wight_parts() } } })
    eq(EnemyTable.read(c4, 2273, 10), nil, "no state Angry")
    eq(EnemyTable.cached(2273), nil, "nothing cached")
    -- the state is listed, but getActiveRegionParam answers none of its numbers
    local rsc = normal(wight_parts())
    rsc.methods[ACTIVE] = function() return nil end
    eq(EnemyTable.read(enemy(2274, rsc), 2274, 10), nil, "no part read")
    -- no state at all
    eq(EnemyTable.read(enemy(2275, control{ prio = nil, states = { { id = "Normal", parts = wight_parts() } } }),
        2275, 10), nil, "no PrioStatusId")
    -- a later read that works counts
    local c5 = enemy(2270, normal(wight_parts()))
    eq(EnemyTable.read(c5, 2270, 11).body.Slash, 0.75, "read a second later")
end)

test("the table in use, never the prefab's Data", function()
    world()
    local template = R.object("app.IntermediateRegionStatusData", {}, {
        get_IntermediateRegionStatusParams = function() error("the template was read") end,
    })
    -- the Succubus of the «Ловушка»: Data says ice 0.1, the table in use 0.5; here as two states
    local c = enemy(2220, control{ prio = "Angry", template = template, states = {
        { id = "Normal", parts = { part{ no = 0, type = BODY, pys = { 1, 1, 1 }, mgc = { 1, 1, 0.5, 1.2, 1 } } } },
        { id = "Angry", parts = { part{ no = 0, type = BODY, pys = { 0.8, 0.8, 0.8 }, mgc = { 1, 1, 0.4, 1, 1 } } } },
    } })
    local t = EnemyTable.read(c, 2220, 10)
    eq(t.state, "Angry", "the state")
    eq(t.body.Slash, 0.8, "the state in use")
    eq(t.body.Ice, 0.4, "its Ice")
    for _, call in ipairs(R.calls) do eq(call.this ~= template, true, "nothing asked of Data") end
end)

-- The real Wight's shape: Normal lists r0..r1 here (r0..r3 in the game), Down only r2 and r3. `fallback`: the control's
-- getActiveRegionParam falls back to Normal's part for a number Down does not list.
local function downed_wight(fallback)
    return control{ prio = "Down", fallback = fallback, states = {
        { id = "Normal", parts = {
            part{ no = 0, type = BODY, pys = { 0.75, 0.75, 0.6 }, mgc = WIGHT_MGC },
            part{ no = 1, type = HEAD, attr = WEAK, pys = { 1.6, 1.6, 1.6 }, mgc = same_mgc(1.6) },
        } },
        { id = "Down", parts = {
            part{ no = 2, type = BODY, pys = { 0.9, 0.9, 0.9 }, mgc = WIGHT_MGC },
            part{ no = 3, type = HEAD, attr = WEAK, pys = { 1.1, 1.1, 1.1 }, mgc = WIGHT_MGC },
        } },
    } }
end

local function asked_numbers()
    local asked = {}
    for _, call in ipairs(R.calls_of(ACTIVE)) do asked[#asked + 1] = call.args[1] end
    table.sort(asked)
    return table.concat(asked, " ")
end

test("the region numbers come from the state in use only", function()
    world()
    local t = EnemyTable.read(enemy(2270, downed_wight()), 2270, 10)
    eq(asked_numbers(), "2 3", "only Down's numbers asked")
    eq(t.state, "Down", "the state")
    eq(t.body.Slash, 0.9, "r2 is the body")
    eq(t.body.Light, 1.5, "r2's Light")
    eq(#t.parts, 1, "one part kind")
    eq(t.parts[1].kind, "weak", "r3")
    eq(t.parts[1].mult.Slash, 1.1, "r3's values")
end)

test("a lookup that falls back to another state brings none of its values", function()
    world()
    local rsc = downed_wight("Normal")
    eq(rsc:call(ACTIVE, 0).fields._RegionNo, 0, "the stub does fall back to Normal's r0")
    world()
    local t = EnemyTable.read(enemy(2270, rsc), 2270, 10)
    eq(asked_numbers(), "2 3", "Normal's numbers are not asked")
    eq(t.body.Slash, 0.9, "not Normal's r0 (0.75)")
    eq(t.body.Shoot, 0.9, "not Normal's r0 Shoot (0.6)")
    eq(t.parts[1].mult.Slash, 1.1, "not Normal's r1 (1.6)")
    eq(t.parts[1].mult.Magic, 0.7, "not Normal's r1 Magic (1.6)")
end)

test("a state that is not in the table fails the read, the cached Table stays", function()
    world()
    local o = { prio = "Normal", states = { { id = "Normal", parts = wight_parts() } } }
    local c = enemy(2270, control(o))
    local t = EnemyTable.read(c, 2270, 10)
    o.prio = "Flight"   -- a state the table in use does not list
    eq(EnemyTable.read(c, 2270, 11), t, "the cached Table")
    eq(asked_numbers(), "0 1", "nothing asked in Flight")
    o.prio = nil
    eq(EnemyTable.read(c, 2270, 12), t, "no state: the cached Table")
    o.prio = "Normal"
    local t2 = EnemyTable.read(c, 2270, 13)
    eq(t2 ~= t and t2.state == "Normal", true, "read again once the state is listed")
end)

test("the field arrays when the getters give nothing; no number is left out", function()
    world()
    local c = enemy(2270, normal({
        part{ no = 0, type = BODY, fields_only = true, pys = { 0.75, 0.75, 0.6 }, mgc = WIGHT_MGC },
        part{ no = 1, type = HEAD, fields_only = true, pys = { 1, 1, 0.8 }, mgc = WIGHT_MGC },
    }))
    local t = EnemyTable.read(c, 2270, 10)
    eq(t.body.Shoot, 0.6, "Shoot from _DamageAdjustRatePys[2]")
    eq(t.body.Light, 1.5, "Light from _DamageAdjustRateMgc[4]")
    eq(t.parts[1].kind, "head", "the type from _RegionType")
    eq(t.parts[1].mult.Shoot, 0.8, "the head's Shoot")
    plain(t, "Table")
    -- a value that is no finite number is left out, never made up
    world()
    local odd = part{ no = 0, type = BODY, pys = { 0 / 0, 0.75, 0.6 }, mgc = WIGHT_MGC }
    odd.methods[MGC] = function(_, i) if i == 4 then return math.huge end return WIGHT_MGC[i + 1] end
    odd.fields._DamageAdjustRatePys.items[1] = R.object("System.Single", {}, { ToString = function() return "x" end })
    odd.fields._DamageAdjustRateMgc = nil
    t = EnemyTable.read(enemy(2270, normal({ odd })), 2270, 10)
    eq(t.body.Slash, nil, "NaN in the getter, no number in the field")
    eq(t.body.Blow, 0.75, "the rest is read")
    eq(t.body.Light, nil, "an infinite value")
    eq(t.body.Thunder, 0.5, "the other elements")
end)

test("no CharaID, no character or no time: nothing is read", function()
    world()
    local c = enemy(2270, normal(wight_parts()))
    eq(EnemyTable.read(c, nil, 10), nil, "no CharaID")
    eq(EnemyTable.read(c, 2270.5, 10), nil, "not an integer")
    eq(EnemyTable.read(nil, 2270, 10), nil, "no character, nothing cached")
    eq(EnemyTable.read(c, 2270, nil), nil, "no time")
    eq(#R.calls, 0, "nothing was read")
    eq(EnemyTable.cached(nil), nil, "cached without a CharaID")
    local t = EnemyTable.read(c, 2270, 10)
    eq(EnemyTable.read(nil, 2270, 20), t, "no character: the cached Table")
    eq(reads(), 1, "and nothing read")
end)

test("EnemyTable.part: one part as the table in use is read, also one that gives no number", function()
    world()
    local p = EnemyTable.part(part{ no = 3, type = HEAD, attr = 384, pys = { 2, 1, 1.2 }, mgc = { 1, 1.5, 1, 1, 0.8 } })
    eq(p.no, 3, "RegionNo"); eq(p.type, HEAD, "RegionType"); eq(p.attr, 384, "_Attr"); eq(p.weak, true, "the weak bit")
    eq(p.mult.Slash, 2, "Slash"); eq(p.mult.Shoot, 1.2, "Shoot"); eq(p.mult.Fire, 1.5, "Fire")
    eq(p.mult.Light, 0.8, "Light")
    p = EnemyTable.part(part{ no = 1, type = OTHER, attr = 128, fields_only = true, pys = { 0.5, 0.5, 0.4 },
        mgc = same_mgc(0.3) })
    eq(p.type, OTHER, "the type from _RegionType"); eq(p.no, 1, "the number from _RegionNo")
    eq(p.mult.Shoot, 0.4, "from the field array"); eq(p.weak, false, "128 is no weak bit")
    -- a part with no number and no RegionNo: the part all the same, the number asked for it
    p = EnemyTable.part(R.object("app.IntermediateRegionParam", { _RegionType = BODY }, {}), 7)
    eq(p.no, 7, "the number asked"); eq(p.type, BODY, "its type"); eq(next(p.mult), nil, "no multiplier")
    eq(p.attr, nil, "no _Attr"); eq(p.weak, false, "not weak")
    eq(EnemyTable.part(nil, 1), nil, "no part")
end)

test("EnemyTable.peek: the Table read now, kept nowhere", function()
    world()
    local c = enemy(2270, normal(wight_parts()))
    local t = EnemyTable.peek(c, 2270)
    eq(t.body.Slash, 0.75, "read"); eq(t.state, "Normal", "its state"); eq(t.chara_id, 2270, "its kind")
    eq(EnemyTable.cached(2270), nil, "nothing cached")
    eq(EnemyTable.read(c, 2270, 10) ~= t, true, "the plate's read reads for itself"); eq(reads(), 2, "two reads")
    local kept = EnemyTable.cached(2270)
    EnemyTable.peek(c, 2270)
    eq(EnemyTable.cached(2270), kept, "a peek after it leaves the cache")
    eq(EnemyTable.read(c, 2270, 10.5), kept, "and its read time"); eq(reads(), 3, "only the peek read")
    eq(EnemyTable.peek(c, nil), nil, "no CharaID"); eq(EnemyTable.peek(nil, 2270), nil, "no character")
    eq(EnemyTable.peek(enemy(2271, nil), 2271), nil, "a failed read")
    eq(reads(), 4, "the failed one read; no CharaID or character: nothing")
end)

-- The plate reads nothing more of a part that gives no number.
test("a part that gives no number: nothing of its type, flags or number read after its multipliers", function()
    world()
    local fields_read = {}
    local blank = R.object("app.IntermediateRegionParam", setmetatable({}, { __index = function(_, k)
        fields_read[#fields_read + 1] = k
        return nil
    end }), { get_RegionNo = function() return 1 end, get_RegionType = function() return BODY end,
        [PYS] = function() return nil end, [MGC] = function() return nil end })
    local list = { part{ no = 0, type = BODY, pys = { 0.75, 0.75, 0.6 }, mgc = WIGHT_MGC }, blank }
    local rsc = normal(list)
    rsc.methods[ACTIVE] = function(_, no) return list[no + 1] end
    local t = EnemyTable.read(enemy(2270, rsc), 2270, 10)
    eq(t.body.Slash, 0.75, "the part with numbers read")
    local after, calls = false, {}
    for _, call in ipairs(R.calls) do
        if call.this == blank then
            if call.sig == PYS or call.sig == MGC then after = true
            elseif after then calls[#calls + 1] = call.sig end
        end
    end
    eq(after, true, "its multipliers asked"); eq(table.concat(calls, " "), "", "no call after them")
    for _, k in ipairs(fields_read) do
        eq(k == "_Attr" or k == "_RegionType" or k == "_RegionNo", false, "no field " .. k)
    end
end)

test("reset forgets", function()
    world()
    local c = enemy(2270, normal(wight_parts()))
    local t = EnemyTable.read(c, 2270, 10)
    EnemyTable.reset()
    eq(EnemyTable.cached(2270), nil, "nothing cached")
    local t2 = EnemyTable.read(c, 2270, 10)
    eq(reads(), 2, "read again at once")
    eq(t2 ~= t, true, "a new Table")
    eq(t.body.Slash, 0.75, "the old one is untouched")
end)

T.finish()
