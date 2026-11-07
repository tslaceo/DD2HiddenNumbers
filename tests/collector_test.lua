package.path = "mod/reframework/autorun/?.lua;tests/?.lua;" .. package.path

local T = require("testlib")
local test, eq = T.test, T.eq
local R = require("stubs/reframework")
local decode = require("json_decode")
local EnemyTable = require("DD2DamageMeter/game/enemy_table")
local Weapon = require("DD2DamageMeter/game/weapon")
local enemies = require("DD2DamageMeter/game/enemies")
local Collector = require("DD2DamageMeter/game/collector")

local ACTIVE = "getActiveRegionParam(System.Int32)"
local PYS = "getDamageAdjustRatePys(app.AttackUserData.AttrPhysicsEnum)"
local MGC = "getDamageAdjustRateMgc(app.AttackUserData.ElementType)"
local HEAD, BODY, OTHER = 0, 1, 2   -- app.IntermediateRegionParam.RegionTypeEnum
local WEAK = 256                    -- IntermediateRegionParam.AttributeFlags.WeakRegion_SE_Effect_Ability
local LEFT, RIGHT = 0, 1            -- WeaponElementInfo.<WeaponType>k__BackingField
local NONE = -1                     -- app.AttackUserData.ElementType of a weapon without an element

local W

-- A fresh game, and the collector's lines in W.lines.
local function world()
    R.new()
    EnemyTable.reset()
    Weapon.reset()
    enemies.reset()
    Collector.reset()
    W = { lines = {} }
    Collector.output(function(text) W.lines[#W.lines + 1] = text end)
end

-- The records written so far, decoded; of `kind` only when given.
local function records(kind)
    local out = {}
    for _, line in ipairs(W.lines) do
        local r = decode(line)
        if kind == nil or r.kind == kind then out[#out + 1] = r end
    end
    return out
end

-- A part (app.IntermediateRegionParam) as enemy_table_test.lua makes it: o.no, o.type, o.attr, o.pys { Slash, Blow,
-- Shoot }, o.mgc { Magic, Fire, Ice, Thunder, Light }, in its getters and fields.
local function part(o)
    return R.object("app.IntermediateRegionParam", { _RegionNo = o.no, _RegionType = o.type, _Attr = o.attr or 0 }, {
        get_RegionNo = function() return o.no end,
        get_RegionType = function() return o.type end,
        [PYS] = function(_, i) return o.pys[i + 1] end,
        [MGC] = function(_, i) return o.mgc[i + 1] end,
    })
end

local function same_mgc(v) return { v, v, v, v, v } end

-- A RegionStatusCtrl in the state o.prio (read again at each call): get_RegionStatusDataProp lists o.states
-- ({ id, parts }), getActiveRegionParam(no) answers with the part numbered `no` of the state o.prio, else of the state
-- o.fallback, else nil.
local function control(o)
    local states = {}
    for i, s in ipairs(o.states) do
        local list = R.list(s.parts, "System.Collections.Generic.List`1<app.IntermediateRegionParam>")
        states[i] = R.object("app.IntermediateRegionStatusParam", {}, {
            get_StatusId = function() return s.id end,
            get_IntermediateRegionParams = function() return list end,
        })
    end
    local list = R.list(states, "System.Collections.Generic.List`1<app.IntermediateRegionStatusParam>")
    local data = R.object("app.IntermediateRegionStatusData", {}, {
        get_IntermediateRegionStatusParams = function() return list end,
    })
    return R.object("app.RegionStatusCtrl", {}, {
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

-- An enemy character of the kind `id` whose damage calculator has the RegionStatusCtrl `rsc` and the enemy data o
-- (weak, resist, defence, magic_defence, enabled), and its Actor.
local function enemy(id, rsc, o)
    o = o or {}
    local c = R.character{ go = o.go or "ch231000_00_7", chara_id = id }
    local calc = R.object("app.ExceptPlayerDamageCalculator", {}, {
        get_RegionStatusCtrl = function() return rsc end,
        get_WeakPointSettings = function() return o.weak or 0 end,
        get_ResistSettings = function() return o.resist or 0 end,
        get_Defence = function() return o.defence end,
        get_MagicDefence = function() return o.magic_defence end,
    })
    local status = R.object("app.StatusConditionCtrl", { EnableStatusConditionFlag = o.enabled }, {})
    c.methods.get_DamageCalculator = function() return calc end
    c.methods.get_StatusConditionCtrl = function() return status end
    local actor = { key = "a" .. c.addr, name = o.name or "Гуль", kind = "enemy", base_id = "ch231000_00",
        chara_id = id }
    return c, actor
end

-- The Ghoul of the probe (a live ghoul, state Normal only): r0 and r2 Other, r1 and r3 Head with _Attr 4
-- (ShootOnRankUp); no Body part at all (its full table as read in the game).
local GHOUL = 221427977
local function ghoul()
    local mgc = { 1, 1, 1, 1, 1.2 }
    local rsc = control{ prio = "Normal", states = { { id = "Normal", parts = {
        part{ no = 0, type = OTHER, pys = { 1, 1, 1 }, mgc = mgc },
        part{ no = 1, type = HEAD, attr = 4, pys = { 1, 1, 1.2 }, mgc = mgc },
        part{ no = 2, type = OTHER, pys = { 1, 1, 1 }, mgc = mgc },
        part{ no = 3, type = HEAD, attr = 4, pys = { 1, 1, 1.2 }, mgc = mgc },
    } } } }
    return enemy(GHOUL, rsc, { defence = 600, magic_defence = 600, enabled = 32762 })
end

-- The Wight's shape (enemy_table_test.lua): Normal lists r0 and r1, Down only r2 and r3; o.prio its state now.
local WIGHT_MGC = { 0.7, 0.7, 0.7, 0.5, 1.5 }
local function wight_states()
    return {
        { id = "Normal", parts = {
            part{ no = 0, type = BODY, pys = { 0.75, 0.75, 0.6 }, mgc = WIGHT_MGC },
            part{ no = 1, type = HEAD, attr = WEAK, pys = { 1.6, 1.6, 1.6 }, mgc = same_mgc(1.6) },
        } },
        { id = "Down", parts = {
            part{ no = 2, type = BODY, pys = { 0.9, 0.9, 0.9 }, mgc = WIGHT_MGC },
            part{ no = 3, type = HEAD, attr = WEAK, pys = { 1.1, 1.1, 1.1 }, mgc = WIGHT_MGC },
        } },
    }
end

local function part_of(list, no)
    for _, p in ipairs(list or {}) do
        if p.no == no then return p end
    end
    return nil
end

test("the Ghoul: every part of its state, no Body part, the body EnemyTable chose and its enemy data", function()
    world()
    local c, actor = ghoul()
    enemies.data(c, actor)               -- the hit path and the plate read it first
    Collector.enemy(c, actor, 10)
    local list = records("enemy")
    eq(#list, 1, "one record")
    local r = list[1]
    eq(r.name, "Гуль", "the name"); eq(r.base_id, "ch231000_00", "the base id"); eq(r.chara_id, GHOUL, "the CharaID")
    eq(r.state, "Normal", "the state in use")
    eq(#r.states, 1, "every state of the table"); eq(r.states[1].id, "Normal", "its id")
    eq(#r.states[1].parts, 4, "every part")
    local r1 = part_of(r.states[1].parts, 1)
    eq(r1.type, HEAD, "r1 RegionType"); eq(r1.attr, 4, "r1 _Attr"); eq(r1.mult.Shoot, 1.2, "r1 Shoot")
    eq(r1.mult.Slash, 1, "r1 Slash"); eq(r1.mult.Light, 1.2, "r1 Light")
    local r0 = part_of(r.states[1].parts, 0)
    eq(r0.type, OTHER, "r0 Other"); eq(r0.attr, 0, "r0 _Attr")
    for _, jt in ipairs({ "Slash", "Blow", "Shoot", "Magic", "Fire", "Ice", "Thunder" }) do
        eq(r0.mult[jt], 1, "r0 " .. jt)
    end
    eq(r.has_body, false, "no Body part")
    eq(r.table.state, "Normal", "EnemyTable's state"); eq(r.table.body.Light, 1.2, "its Other body: Light")
    eq(r.table.body.Shoot, 1, "an Other part's Shoot, not the head's"); eq(#r.table.parts, 1, "its head line")
    eq(r.data.weak, 0, "weak tags"); eq(r.data.resist, 0, "resist tags")
    eq(r.data.defence, 600, "defence"); eq(r.data.magic_defence, 600, "magic defence")
    eq(r.data.enabled, 32762, "the enabled status mask")
    eq(#r.active, 4, "what getActiveRegionParam answers for each number")
    eq(r.active[1].asked, 0, "asked r0"); eq(r.active[1].part.no, 0, "answered r0")
    eq(r.active[4].asked, 3, "asked r3"); eq(r.active[4].part.mult.Shoot, 1.2, "with r3's values")
end)

test("a state with its own parts each; what getActiveRegionParam answers for a number of another state", function()
    world()
    local c, actor = enemy(2270, control{ prio = "Down", fallback = "Normal", states = wight_states() },
        { name = "Вурдалак" })
    Collector.enemy(c, actor, 10)
    local r = records("enemy")[1]
    eq(r.state, "Down", "the state in use")
    eq(#r.states, 2, "both states"); eq(r.states[1].id, "Normal", "Normal"); eq(r.states[2].id, "Down", "Down")
    eq(part_of(r.states[1].parts, 0).mult.Shoot, 0.6, "Normal's own r0")
    eq(part_of(r.states[1].parts, 1).attr, WEAK, "Normal's weak r1")
    eq(part_of(r.states[2].parts, 2).mult.Slash, 0.9, "Down's own r2")
    eq(r.has_body, true, "Down lists a Body part")
    eq(r.table.body.Slash, 0.9, "EnemyTable's body: Down's r2")
    local asked = {}
    for _, a in ipairs(r.active) do asked[#asked + 1] = a.asked end
    eq(table.concat(asked, " "), "0 1 2 3", "every number any state lists")
    eq(r.active[1].part.mult.Shoot, 0.6, "r0 in Down: this control falls back to Normal's")
    eq(r.active[3].part.mult.Slash, 0.9, "r2: Down's own")
    -- a control without the fall-back: the numbers Down does not list get none
    world()
    c, actor = enemy(2270, control{ prio = "Down", states = wight_states() })
    Collector.enemy(c, actor, 10)
    r = records("enemy")[1]
    eq(r.active[1].none, true, "r0: none"); eq(r.active[1].part, nil, "no part")
    eq(r.active[4].part.no, 3, "r3 answered")
end)

test("the collector's read leaves the plate's table cache as it was", function()
    world()
    local c, actor = enemy(2270, control{ prio = "Normal", states = wight_states() })
    Collector.enemy(c, actor, 10)
    eq(records("enemy")[1].table.body.Slash, 0.75, "the record has EnemyTable's Table")
    eq(EnemyTable.cached(2270), nil, "the plate's cache untouched")
    local n = #R.calls_of("get_RegionStatusDataProp")
    EnemyTable.read(c, 2270, 10)
    eq(#R.calls_of("get_RegionStatusDataProp"), n + 1, "the plate's own read at the same time reads")
end)

test("a kind is read once per state: its state at most once a second, nothing else while its key is seen", function()
    world()
    local o = { prio = "Normal", states = wight_states() }
    local c, actor = enemy(2270, control(o))
    Collector.enemy(c, actor, 10)
    eq(#records("enemy"), 1, "the first one")
    local n = #R.calls
    Collector.enemy(c, actor, 10.5)
    eq(#R.calls, n, "half a second later: nothing read")
    Collector.enemy(c, actor, 11)
    eq(#records("enemy"), 1, "a second later, the same state: no record")
    eq(#R.calls_of("get_PrioStatusId") > 0, true, "its state read")
    eq(#R.calls_of("get_RegionStatusDataProp"), 2, "the table not read again (the collector's and EnemyTable's)")
    -- another enemy of the kind in between: nothing read
    local c2 = enemy(2270, control(o))
    n = #R.calls
    Collector.enemy(c2, actor, 11.5)
    eq(#R.calls, n, "per kind: nothing read")
    -- a new state: a record of its own
    o.prio = "Down"
    Collector.enemy(c, actor, 12)
    local list = records("enemy")
    eq(#list, 2, "Down: a new record"); eq(list[2].state, "Down", "its state")
    Collector.enemy(c, actor, 13)
    o.prio = "Normal"
    Collector.enemy(c, actor, 14)
    eq(#records("enemy"), 2, "Down again and Normal again: none")
    -- a clock that went back reads the state again
    n = #R.calls_of("get_PrioStatusId")
    Collector.enemy(c, actor, 5)
    eq(#R.calls_of("get_PrioStatusId"), n + 1, "an earlier t")
    -- no CharaID, or no character: nothing read, no record
    n = #R.calls
    Collector.enemy(c, { key = "x", name = "?", kind = "enemy" }, 20)
    Collector.enemy(nil, actor, 30)
    eq(#R.calls, n, "nothing read"); eq(#records("enemy"), 2, "no record")
end)

test("an enemy whose state cannot be read is one record without a state, then one per state", function()
    world()
    local o = { prio = nil, states = wight_states() }
    local c, actor = enemy(2270, control(o))
    Collector.enemy(c, actor, 10)
    local list = records("enemy")
    eq(#list, 1, "a record"); eq(list[1].state, nil, "no state"); eq(#list[1].states, 2, "the table all the same")
    eq(list[1].has_body, nil, "no state in use: no Body flag"); eq(list[1].table, nil, "and no EnemyTable answer")
    Collector.enemy(c, actor, 11)
    eq(#records("enemy"), 1, "no state again: none")
    o.prio = "Normal"
    Collector.enemy(c, actor, 12)
    eq(#records("enemy"), 2, "Normal: one more")
    -- a character that raises everywhere writes one record with what it has and raises nothing
    world()
    local bad = R.character{ go = "ch231000_00_9", chara_id = 3001 }
    bad.poison = true
    Collector.enemy(bad, { key = "b", name = "?", kind = "enemy", chara_id = 3001 }, 10)
    eq(#records("enemy"), 1, "one record"); eq(#records("enemy")[1].states, 0, "nothing in it")
end)

-- An app.Weapon (weapon_test.lua's) with a GameObject named o.id.
local function weapon(o)
    local go = R.object("via.GameObject", {}, { get_Name = function() return o.id end })
    local methods = { get_GameObject = function() return go end }
    methods.get_OriginalElementType = function() return o.element end
    return R.object("app.Weapon", { IsBlunt = o.blunt, ElementType = o.element, Job = o.job or 4 }, methods)
end

local function info(hand, now)
    return R.object("app.WeaponElementControllerBase.WeaponElementInfo",
        { ["<WeaponType>k__BackingField"] = hand, NowElementType = now },
        { isLeft = function() return hand == LEFT end })
end

-- The player's character: o.right, o.left its weapons, o.infos its WeaponElementInfos (read again at each call).
local function player(o)
    local c = R.character{ go = "ch000000_00" }
    c.methods.get_RightWeapon = function() return o.right end
    c.methods.get_LeftWeapon = function() return o.left end
    c.methods.get_WeaponElementController = function()
        local arr = R.object("app.WeaponElementControllerBase.WeaponElementInfo[]", {}, {})
        arr.items = o.infos
        return R.object("app.WeaponElementController", { WeaponElementInfos = arr }, {})
    end
    return c
end

test("weapons: one record per weapon and hand, an enchant at each change, a look at most once a second", function()
    world()
    local o = { right = weapon{ id = "wp04_002_00", blunt = false, element = NONE, job = 4 },
                infos = { info(LEFT, NONE), info(RIGHT, NONE) } }
    local c = player(o)
    local asked = 0
    local function who()
        asked = asked + 1
        return c
    end
    Collector.weapons(10, who)
    local list = records("weapon")
    eq(#list, 1, "the right hand's dagger")
    local r = list[1]
    eq(r.hand, "right", "the hand"); eq(r.id, "wp04_002_00", "its id: the GameObject's name"); eq(r.job, 4, "Job")
    eq(r.blunt, false, "IsBlunt"); eq(r.element_type, NONE, "ElementType"); eq(r.original_element, NONE, "its own")
    eq(r.answer.phys, "Slash", "Weapon.read's answer"); eq(r.answer.enchant, nil, "no enchant")
    local e = records("enchant")
    eq(#e, 1, "the hand's NowElementType as first seen"); eq(e[1].hand, "right", "its hand"); eq(e[1].value, NONE, "-1")
    -- within the second: the player is not even asked for
    local n = #R.calls
    Collector.weapons(10.5, who)
    eq(asked, 1, "not looked at"); eq(#R.calls, n, "nothing read")
    -- the fire enchant: a record of its hand's value
    o.infos = { info(LEFT, 1), info(RIGHT, 1) }
    Collector.weapons(11, who)
    eq(#records("weapon"), 1, "the same weapon: no record")
    e = records("enchant")
    eq(#e, 2, "the right hand's change"); eq(e[2].value, 1, "Fire")
    eq(e[2].hand, "right", "only the hand with a weapon")
    Collector.weapons(12, who)
    eq(#records("enchant"), 2, "no change: none")
    -- a second dagger in the left hand
    o.left = weapon{ id = "wp04_002_00", blunt = false, element = NONE, job = 4 }
    Collector.weapons(13, who)
    list = records("weapon")
    eq(#list, 2, "the left hand's"); eq(list[2].hand, "left", "left")
    e = records("enchant")
    eq(#e, 3, "its first value"); eq(e[3].hand, "left", "left"); eq(e[3].value, 1, "Fire")
    -- the same weapon as a new object (a new area): no record; another weapon: one
    o.right = weapon{ id = "wp04_002_00", blunt = false, element = NONE, job = 4 }
    Collector.weapons(14, who)
    eq(#records("weapon"), 2, "the same weapon id and hand: none")
    o.right = weapon{ id = "wp09_001_00", blunt = true, element = NONE, job = 9 }
    Collector.weapons(15, who)
    list = records("weapon")
    eq(#list, 3, "the censer"); eq(list[3].blunt, true, "blunt"); eq(list[3].answer.phys, "Blow", "read as Blow now")
    -- a weapon of the same name that is another weapon (a generic name): a record of its own
    o.right = weapon{ id = "wp09_001_00", blunt = true, element = 1, job = 9 }
    Collector.weapons(15.5, who)
    eq(#records("weapon"), 3, "not looked at within the second")
    Collector.weapons(16, who)
    o.right = weapon{ id = "wp09_001_00", blunt = false, element = NONE, job = 4 }
    Collector.weapons(17, who)
    list = records("weapon")
    eq(#list, 5, "the name with its Job, IsBlunt and ElementType is the key")
    eq(list[4].element_type, 1, "another ElementType"); eq(list[5].job, 4, "another Job")
    -- the enchant over on the right, the left hand stale
    o.infos = { info(LEFT, 1), info(RIGHT, NONE) }
    Collector.weapons(18, who)
    e = records("enchant")
    eq(#e, 4, "the right hand's end"); eq(e[4].value, NONE, "-1")
    -- no player: nothing
    Collector.weapons(20, function() return nil end)
    eq(#W.lines, 9, "nothing more")
end)

local GOBLIN = { key = "a1", name = "Гоблин", kind = "enemy", base_id = "ch220003_00", chara_id = 1101 }
local PLAYER = { key = "a2", name = "Guts", kind = "player", base_id = "ch000000_00", chara_id = 2891076981 }
local PAWN = { key = "a3", name = "Casca", kind = "pawn", base_id = "ch100000_00", chara_id = 2283028347 }

-- The player's blow on the goblin, its fields changed by `o` (NIL: none).
local NIL = {}
local function blow(o)
    local h = { t = 10, attacker = PLAYER, victim = GOBLIN, skill = { attack = "強攻撃", id = "Job04_Cutthroat" },
        final = 300, hp0 = 1000, hp1 = 700, before = 400, after = 300, target_bonus = 2, target_rate = 1 }
    for k, v in pairs(o or {}) do
        if v == NIL then h[k] = nil else h[k] = v end
    end
    return h
end

test("hits: a bonus record per attack and bonus, a sourceless one per DamageType and Flag; no game read", function()
    world()
    Collector.hit(blow())
    local list = records("bonus")
    eq(#list, 1, "a bonus")
    local r = list[1]
    eq(r.attack, "強攻撃", "the attack"); eq(r.skill, "Job04_Cutthroat", "its skill"); eq(r.attacker_kind, "player", "who")
    eq(r.attacker, "Guts", "his name"); eq(r.before, 400, "damage before the defence"); eq(r.after, 300, "after it")
    eq(r.rate_before, 1, "the DamageRate before the enemy step"); eq(r.rate_after, 3, "after it"); eq(r.bonus, 2, "+2")
    eq(r.victim, "Гоблин", "the victim"); eq(r.chara_id, 1101, "its CharaID")
    Collector.hit(blow{ target_bonus = 2.0004 })
    eq(#records("bonus"), 1, "the same bonus to 2 decimals: none")
    Collector.hit(blow{ target_bonus = 0.5 })
    Collector.hit(blow{ skill = { attack = "弱攻撃" }, target_bonus = 0.5, target_rate = NIL, before = NIL, after = NIL })
    list = records("bonus")
    eq(#list, 3, "another bonus, another attack")
    eq(list[3].rate_before, nil, "a rate not known: none"); eq(list[3].before, nil, "nor the damage")
    Collector.hit(blow{ target_bonus = 0.001 })
    Collector.hit(blow{ target_bonus = 0 })
    Collector.hit(blow{ target_bonus = -0.2 })
    Collector.hit(blow{ target_bonus = NIL })
    Collector.hit(blow{ victim = PAWN, attacker = GOBLIN, skill = { attack = "x" } })
    eq(#records("bonus"), 3, "none at 0.001 or below, nor without one, nor on the party")
    eq(#records("sourceless"), 0, "every one of them had an attacker")
    -- a slam with no attacker (Falls and environment), a burn nobody known caused (Other), a mirror
    local slam = { t = 10, victim = GOBLIN, skill = {}, final = 1700, hp0 = 3000, hp1 = 1300, own = "self",
        damage_type = 14, flag = 10753 }
    Collector.hit(slam)
    Collector.hit(slam)
    Collector.hit({ t = 11, victim = GOBLIN, skill = { status = "FireSpread" }, status = "FireSpread", final = 30,
        hp0 = 1300, hp1 = 1270, damage_type = -1, flag = 8713 })
    Collector.hit({ t = 12, victim = GOBLIN, skill = {}, mirror = true, final = 1000, hp0 = 1270, hp1 = 270,
        damage_type = -1, flag = 566935691817 })
    list = records("sourceless")
    eq(#list, 3, "one per DamageType and Flag")
    eq(list[1].damage_type, 14, "DamageType"); eq(list[1].flag, 10753, "Flag"); eq(list[1].own, "self", "its own")
    eq(list[1].victim, "Гоблин", "the victim"); eq(list[1].chara_id, 1101, "its CharaID")
    eq(list[1].damage, 1700, "the damage"); eq(list[1].removed, 1700, "the HP it took")
    eq(list[1].dot, false, "no DoT tick"); eq(list[1].mirror, false, "no mirror")
    eq(list[2].dot, true, "a DoT tick"); eq(list[2].status, "FireSpread", "its status"); eq(list[2].flag, 8713, "8713")
    eq(list[3].mirror, true, "a mirror"); eq(list[3].flag, 566935691817, "bit 39")
    -- a sourceless hit on a party member is none of these
    Collector.hit({ t = 13, victim = PAWN, skill = {}, final = 5, hp0 = 100, hp1 = 95, own = "self",
        damage_type = 3, flag = 1 })
    eq(#records("sourceless"), 3, "on the party: none")
    eq(#R.calls, 0, "nothing read from the game")
end)

-- An enemy's own damage credited to the friend who knocked it (game/hits.lua's knock hit).
test("hits: a knock record per knocking attack and enemy kind, no sourceless one; no game read", function()
    world()
    local function knock(o)
        local h = { t = 12.2, attacker = PAWN, victim = GOBLIN, skill = { attack = "弱攻撃_ヒットスロー大" },
            knock = true, knock_gap = 0.4, final = 1000, hp0 = 3000, hp1 = 2000, damage_type = 14, flag = 10753 }
        for k, v in pairs(o or {}) do
            if v == NIL then h[k] = nil else h[k] = v end
        end
        return h
    end
    Collector.hit(knock())
    Collector.hit(knock{ knock_gap = 2.5, final = 540 })
    local list = records("knock")
    eq(#list, 1, "once per attack and kind")
    local r = list[1]
    eq(r.attack, "弱攻撃_ヒットスロー大", "the knocking attack"); eq(r.skill, nil, "no skill id")
    eq(r.attacker_kind, "pawn", "a pawn's"); eq(r.attacker, "Casca", "her name"); eq(r.gap, 0.4, "0.4 s after it")
    eq(r.damage, 1000, "the damage"); eq(r.removed, 1000, "the HP it took")
    eq(r.damage_type, 14, "DamageType"); eq(r.flag, 10753, "Flag")
    eq(r.victim, "Гоблин", "the victim"); eq(r.chara_id, 1101, "its CharaID")
    Collector.hit(knock{ skill = { attack = "地平斬り", id = "Job05_HorizontalSlash" } })
    Collector.hit(knock{ victim = { key = "e9", name = "Хобгоблин", kind = "enemy", base_id = "ch221000_00",
        chara_id = 2210 } })
    list = records("knock")
    eq(#list, 3, "another attack, another kind"); eq(list[2].skill, "Job05_HorizontalSlash", "its skill")
    eq(list[3].chara_id, 2210, "the other kind")
    -- a hit that is no knock writes none
    Collector.hit(blow())
    Collector.hit(knock{ knock = NIL })
    eq(#records("knock"), 3, "no knock: none")
    eq(#records("sourceless"), 0, "a knock hit has an attacker: no sourceless record")
    eq(#R.calls, 0, "nothing read from the game")
end)

test("party_join: every time, with the member and his old and new address", function()
    world()
    Collector.party_join(PAWN, 0x2A0000100, 0x2A0000900)
    Collector.party_join(PAWN, 0x2A0000900, 0x2A0001500)
    local list = records("party_join")
    eq(#list, 2, "every join")
    eq(list[1].name, "Casca", "the name"); eq(list[1].member_kind, "pawn", "a pawn")
    eq(list[1].chara_id, 2283028347, "his CharaID")
    eq(list[1].old, "0x2A0000100", "the old address"); eq(list[1].new, "0x2A0000900", "the new one")
    eq(list[2].old, "0x2A0000900", "the next join"); eq(list[2].new, "0x2A0001500", "its new one")
    Collector.party_join(PAWN, nil, 0x2A0002000)
    eq(records("party_join")[3].old, nil, "an old address not known: none")
end)

test("every record is one JSON line that starts with its time and kind", function()
    world()
    local c, actor = ghoul()
    Collector.enemy(c, actor, 10)
    Collector.hit(blow())
    Collector.party_join(PAWN, 1, 2)
    eq(#W.lines, 3, "three records")
    for _, line in ipairs(W.lines) do
        eq(line:match('^{"t":"%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d","kind":"[%a_]+",') ~= nil, true,
            "time and kind first: " .. line:sub(1, 60))
        eq(line:sub(-1), "\n", "one line"); eq(select(2, line:gsub("\n", "")), 1, "only one")
        eq(type(decode(line)), "table", "JSON")
    end
    eq(decode(W.lines[1]).kind, "enemy", "the kind")
    -- without an output nothing is written, and nothing raises
    Collector.output(nil)
    Collector.hit(blow{ target_bonus = 1 })
    eq(#W.lines, 3, "no output: nothing")
end)

-- The hidden-stats evidence ----------------------------------------------------------------------------------------

-- A snapshot as game/stat_check.lua gives it: the Warfarer of the ring check in the game (2026-11-06), Кольцо
-- бескорыстия (10223) and Кольцо погибели демонов (10227) on, max HP 3100. o.numbers changes numbers (NIL: none),
-- o.augments / o.rings / o.items / o.job replace those.
-- Some of its keys as game/stat_check.lua names them.
local DEF, ADD_DEF, ADD_ATK = "total.BasicDefence", "total.AdditionalDefence", "total.AdditionalAttack"

local function snap(o)
    o = o or {}
    local numbers = { [DEF] = 380, [ADD_DEF] = 159, ["total.ArmorDefence"] = 1106, ["total.BasicAttack"] = 420,
        ["basic.BlowResistance"] = 100, hp_max = 3100, hp_base = 2900, sp_max = 1300, weight_max = 62.7,
        ["eq.FireDefence"] = 20 }
    for k, v in pairs(o.numbers or {}) do
        if v == NIL then numbers[k] = nil else numbers[k] = v end
    end
    return { numbers = numbers, equipped = { job = o.job or 10, augments = o.augments or { "Job01_01", "Job05_00" },
        rings = o.rings or { 10223, 10227 }, items = o.items or { 1001, 2001 } } }
end

local function keys(t)
    local out = {}
    for k in pairs(t or {}) do out[#out + 1] = k end
    table.sort(out)
    return table.concat(out, " ")
end

test("stat_check: the first snapshot is only kept; the same snapshot again writes nothing", function()
    world()
    Collector.stat_check(10, snap())
    Collector.stat_check(12, snap())
    Collector.stat_check(14, snap())
    eq(#W.lines, 0, "no record")
    -- one change, then the same snapshot twice: one record
    local ringed = snap{ rings = { 3502, 10227 }, numbers = { hp_max = 3300 } }
    Collector.stat_check(16, ringed)
    Collector.stat_check(18, ringed)
    Collector.stat_check(20, snap{ rings = { 3502, 10227 }, numbers = { hp_max = 3300 } })
    eq(#records("stat_check"), 1, "one record for the change")
    eq(#R.calls, 0, "nothing read from the game")
end)

test("stat_check: a ring changed together with max HP: one record with what came in, what went out, what changed",
    function()
    world()
    Collector.stat_check(10, snap())
    Collector.stat_check(12, snap{ rings = { 3502, 10227 }, numbers = { hp_max = 3300 } })
    local list = records("stat_check")
    eq(#list, 1, "one record")
    local r = list[1]
    eq(r.job, 10, "the vocation"); eq(r.job_before, nil, "the same vocation before")
    eq(T.str(r.added), "3502", "Кольцо признания came in"); eq(T.str(r.removed), "10223", "Кольцо бескорыстия went out")
    eq(keys(r.changed), "hp_max", "only max HP changed")
    eq(r.changed.hp_max.from, 3100, "from 3100"); eq(r.changed.hp_max.to, 3300, "to 3300")
    eq(T.str(r.before.rings), "10223 10227", "the rings before"); eq(T.str(r.after.rings), "3502 10227", "after")
    eq(T.str(r.before.augments), "Job01_01 Job05_00", "the augments before")
    eq(T.str(r.after.augments), "Job01_01 Job05_00", "the same after")
    eq(T.str(r.before.items), "1001 2001", "the other gear before"); eq(T.str(r.after.items), "1001 2001", "after")
end)

test("stat_check: numbers changed without an equipment change (a level up) write nothing; the next change is from them",
    function()
    world()
    Collector.stat_check(10, snap())
    Collector.stat_check(12, snap{ numbers = { [DEF] = 390, hp_max = 3150 } })
    eq(#W.lines, 0, "a level up: no record")
    Collector.stat_check(14, snap{ rings = { 3502, 10227 }, numbers = { [DEF] = 390, hp_max = 3350 } })
    local r = records("stat_check")[1]
    eq(r ~= nil, true, "the ring's record")
    eq(keys(r.changed), "hp_max", "the level up's defence is not in it")
    eq(r.changed.hp_max.from, 3150, "from the level up's max HP"); eq(r.changed.hp_max.to, 3350, "to 3350")
end)

test("stat_check: the equipment changed without a number change writes nothing; numbers alone after it neither",
    function()
    world()
    Collector.stat_check(10, snap())
    -- Кольцо возвращения (10213) in place of Кольцо бескорыстия: nothing the record holds changes
    Collector.stat_check(12, snap{ rings = { 10213, 10227 } })
    eq(#W.lines, 0, "no number changed: no record")
    Collector.stat_check(14, snap{ rings = { 10213, 10227 }, numbers = { hp_max = 3150 } })
    eq(#W.lines, 0, "then a level up: the equipment is the kept one's, no record")
end)

test("stat_check: an augment changed; a number that comes or goes; a new vocation; an item read once as a ring and "
    .. "once as gear is no change", function()
    world()
    Collector.stat_check(10, snap())
    -- Стойкость out, Пылкость in: the defence's share went, a strength came
    Collector.stat_check(12, snap{ augments = { "Job04_04", "Job05_00" },
        numbers = { [ADD_DEF] = NIL, [ADD_ATK] = 30 } })
    local r = records("stat_check")[1]
    eq(T.str(r.added), "Job04_04", "the augment in"); eq(T.str(r.removed), "Job01_01", "the augment out")
    eq(keys(r.changed), ADD_ATK .. " " .. ADD_DEF, "both")
    eq(r.changed[ADD_DEF].from, 159, "from 159"); eq(r.changed[ADD_DEF].to, nil, "to none")
    eq(r.changed[ADD_ATK].from, nil, "from none"); eq(r.changed[ADD_ATK].to, 30, "to 30")
    -- the same ids, 10223 read as gear (its ring read failed this time): no equipment change
    Collector.stat_check(14, snap{ augments = { "Job04_04", "Job05_00" }, rings = { 10227 },
        items = { 1001, 2001, 10223 }, numbers = { [ADD_DEF] = NIL, [ADD_ATK] = 30, hp_max = 3150 } })
    eq(#records("stat_check"), 1, "no new record")
    -- a vocation change: its augments and numbers
    Collector.stat_check(16, snap{ job = 4, augments = { "Job04_00" }, numbers = { ["total.BasicAttack"] = 400 } })
    r = records("stat_check")[2]
    eq(r.job, 4, "the new vocation"); eq(r.job_before, 10, "the one before")
    eq(T.str(r.added), "Job04_00", "the augment; 10223 read as a ring again is no change")
    eq(T.str(r.removed), "Job04_04 Job05_00", "the augments out")
    eq(T.str(r.before.items), "1001 2001 10223", "as read before"); eq(T.str(r.after.rings), "10223 10227", "and now")
end)

test("stat_check: two equal rings count twice; a gear change is listed with the rings, augments first", function()
    world()
    Collector.stat_check(10, snap{ rings = { 3501, 3502 } })
    Collector.stat_check(12, snap{ rings = { 3502, 3502 }, augments = { "Job01_01" }, items = { 1001, 2002 },
        numbers = { hp_max = 3200 } })
    local r = records("stat_check")[1]
    eq(T.str(r.added), "2002 3502", "the second 3502 and the new armour")
    eq(T.str(r.removed), "Job05_00 2001 3501", "the augment, the old armour and 3501")
    eq(T.str(r.after.rings), "3502 3502", "both rings")
end)

test("stat_check: at most 300 records a session; reset starts afresh", function()
    world()
    local a, b = snap(), snap{ rings = { 3502, 10227 }, numbers = { hp_max = 3300 } }
    Collector.stat_check(0, a)
    for i = 1, 301 do Collector.stat_check(i, i % 2 == 1 and b or a) end
    eq(#records("stat_check"), 300, "the 301st not written")
    Collector.stat_check(400, a)
    eq(#records("stat_check"), 300, "nor any after it")
    Collector.reset()
    Collector.stat_check(401, a)
    Collector.stat_check(402, b)
    eq(#records("stat_check"), 301, "a new session: written again")
end)

test("stat_check: nil or a malformed snapshot, or no time, changes nothing; stat_forget forgets the last one",
    function()
    world()
    Collector.stat_check(10, snap())
    Collector.stat_check(11, nil)
    Collector.stat_check(12, { numbers = { hp_max = 1 } })
    Collector.stat_check(13, { equipped = { job = 1, augments = {}, rings = {}, items = {} } })
    Collector.stat_check(13.5, "snapshot")
    Collector.stat_check(0 / 0, snap{ rings = { 3502 }, numbers = { hp_max = 1 } })
    Collector.stat_check(nil, snap{ rings = { 3502 }, numbers = { hp_max = 1 } })
    eq(#W.lines, 0, "nothing written")
    Collector.stat_check(14, snap{ rings = { 3502, 10227 }, numbers = { hp_max = 3300 } })
    local r = records("stat_check")[1]
    eq(r.changed.hp_max.from, 3100, "compared with the last good one"); eq(T.str(r.removed), "10223", "its ring")
    -- a new world: the next snapshot is only kept
    Collector.stat_forget()
    Collector.stat_check(15, snap{ job = 4, augments = { "Job04_00" }, rings = {}, numbers = { hp_max = 2000 } })
    eq(#records("stat_check"), 1, "no record for a loaded save")
    Collector.stat_check(16, snap{ job = 4, augments = { "Job04_00" }, rings = { 3502 }, numbers = { hp_max = 2200 } })
    eq(#records("stat_check"), 2, "the next change is one")
    eq(records("stat_check")[2].before.rings, nil, "no ring before: none written")
end)

test("reset forgets the keys seen", function()
    world()
    local c, actor = ghoul()
    Collector.enemy(c, actor, 10)
    Collector.hit(blow())
    Collector.reset()
    Collector.enemy(c, actor, 10)
    Collector.hit(blow())
    eq(#records("enemy"), 2, "the enemy again"); eq(#records("bonus"), 2, "the bonus again")
end)

T.finish()
