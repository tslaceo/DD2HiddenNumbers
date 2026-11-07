package.path = "mod/reframework/autorun/?.lua;tests/?.lua;" .. package.path

local T = require("testlib")
local test, eq, near = T.test, T.eq, T.near
local DamageNumbers = require("DD2DamageMeter/damage_numbers")

local function actor(key, kind, job)
    return { key = key, name = key, kind = kind, job = job }
end

local GUTS = actor("ch000000_00", "player", 10)
local CASCA = actor("ch100000_00", "pawn", 5)
local ALLY = actor("ch111003_00", "ally")
local GOB = actor("a10", "enemy")
local GOB2 = actor("a11", "enemy")
local OGRE = actor("a12", "enemy")
local BARREL = actor("obj_1", "other")

local P1, P2 = { x = 1, y = 2, z = 3 }, { x = 4, y = 5, z = 6 }

-- A hit on an enemy that hits.lua gave its point; `o` overrides any field.
local function hit(attacker, victim, o)
    local h = { t = 10, attacker = attacker, victim = victim, skill = { attack = "atk", id = "Job05_CrescentSlash" },
        final = 100, hp0 = 1000, hp1 = 900, point = P1, weak_damage = false, target_bonus = 0 }
    for k, v in pairs(o or {}) do h[k] = v end
    return h
end

test("a counted hit on an enemy becomes a number: its HP, point, time, attacker and skill", function()
    local list = DamageNumbers.new()
    local n = list:add(hit(CASCA, GOB), 98.6, 10, 2)
    eq(#list.items, 1, "one number")
    eq(list.items[1], n, "the number given back")
    near(n.amount, 98.6, 1e-9, "the HP the meter counted")
    eq(n.point, P1, "the hit's point"); eq(n.t, 10, "its time")
    eq(n.victim, "a10", "the enemy"); eq(n.who, "ch100000_00", "the attacker")
    eq(n.skill, "Job05_CrescentSlash", "the skill")
    eq(n.kind, "pawn", "a pawn"); eq(n.job, 5, "its vocation"); eq(n.shade, 2, "its shade")
    eq(n.crit, false, "no crit"); eq(n.weak, false, "no weak point"); eq(n.dot, false, "no DoT tick")
end)

test("nothing for a hit on anyone but an enemy, without a point, or of no HP", function()
    local list = DamageNumbers.new()
    eq(list:add(hit(GOB, CASCA), 50, 10), nil, "an enemy's blow on the party")
    eq(list:add(hit(CASCA, BARREL), 50, 10), nil, "a barrel")
    eq(list:add(hit(CASCA, GOB, { point = false }), 50, 10), nil, "no point")
    eq(list:add(hit(CASCA, GOB), 0, 10), nil, "0 HP")
    eq(list:add(hit(CASCA, GOB), -5, 10), nil, "below 0")
    eq(list:add(hit(CASCA, GOB), nil, 10), nil, "no amount")
    eq(list:add(hit(CASCA, GOB), 0 / 0, 10), nil, "nan")
    eq(list:add(nil, 50, 10), nil, "no hit")
    eq(#list.items, 0, "none")
end)

test("the kind for the colour: party members and allies keep theirs, everything else is other", function()
    local list, t = DamageNumbers.new(), 0
    local function kind_of(attacker, o)
        t = t + 1
        local n = list:add(hit(attacker, GOB, o), 10, t)
        return n.kind, n.job, n.shade
    end
    local kind, job, shade = kind_of(GUTS)
    eq(kind, "player", "the player"); eq(job, 10, "a Warfarer"); eq(shade, nil, "no shade given: none")
    kind, job = kind_of(ALLY)
    eq(kind, "ally", "an ally"); eq(job, nil, "no vocation for an ally")
    eq(kind_of(nil, { skill = { status = "FireSpread" }, status = "FireSpread" }), "other", "nobody: a DoT tick")
    eq(kind_of(OGRE), "other", "an enemy hitting an enemy")
    eq(kind_of(BARREL), "other", "an object")
    kind, job = kind_of(actor("ch300656_00_3", "other", 3))
    eq(kind, "other", "a neutral character"); eq(job, nil, "no vocation either")
end)

test("a shade given as a function is asked only when a party member's hit makes a new number", function()
    local list, asked = DamageNumbers.new(), {}
    local function shade(h)
        asked[#asked + 1] = h.attacker.key
        return 3
    end
    local n = list:add(hit(CASCA, GOB), 10, 10, shade)
    eq(n.shade, 3, "its answer"); eq(#asked, 1, "asked once"); eq(asked[1], "ch100000_00", "for the hit's attacker")
    list:add(hit(CASCA, GOB), 10, 10.1, shade)
    list:add(hit(CASCA, GOB), 10, 10.2, shade)
    eq(#asked, 1, "a hit that joins the number: not asked")
    list:add(hit(ALLY, GOB), 10, 10.2, shade)
    list:add(hit(nil, GOB, { status = "Poison", skill = { status = "Poison" } }), 10, 10.2, shade)
    list:add(hit(OGRE, GOB), 10, 10.2, shade)
    eq(#asked, 1, "an ally, nobody, an enemy: not asked")
    list:add(hit(GUTS, GOB), 10, 10.2, shade)
    eq(#asked, 2, "another party member's new number: asked")
    eq(list:add(hit(GUTS, GOB2), 10, 10.2, 2).shade, 2, "a number still works")
end)

test("hits of one attacker with one skill on one enemy within 0.3 s of the first make one number", function()
    local list = DamageNumbers.new()
    local first = list:add(hit(GUTS, GOB, { point = P1 }), 2670, 10)
    eq(list:add(hit(GUTS, GOB, { point = P2 }), 762, 10), first, "the same tick: the same number")
    eq(list:add(hit(GUTS, GOB, { point = P2 }), 1320, 10.3), first, "0.3 s after the first: still")
    eq(#list.items, 1, "one number")
    near(first.amount, 2670 + 762 + 1320, 1e-9, "the sum")
    eq(first.point, P1, "at the first hit's point"); eq(first.t, 10, "and time")
    local later = list:add(hit(GUTS, GOB), 100, 10.31)
    eq(later ~= first, true, "more than 0.3 s after the first: a new number")
    eq(#list.items, 2, "two")
    -- whatever else differs never merges
    local n = #list.items
    list:add(hit(CASCA, GOB), 5, 10.32)
    list:add(hit(GUTS, GOB2), 5, 10.32)
    list:add(hit(GUTS, GOB, { skill = { attack = "other_atk", id = "Job10_Other" } }), 5, 10.32)
    list:add(hit(nil, GOB, { skill = { status = "FireSpread" }, status = "FireSpread" }), 5, 10.32)
    eq(#list.items, n + 4, "another attacker, enemy, skill or nobody: each its own number")
    near(later.amount, 100, 1e-9, "the number of 10.31 untouched")
    -- nobody's ticks of one status on one enemy merge like one attacker's hits
    local tick = list:add(hit(nil, GOB, { skill = { status = "FireSpread" }, status = "FireSpread" }), 7, 10.4)
    eq(tick.amount, 12, "nobody's two burn ticks within 0.3 s: one number")
end)

test("the skill a hit is merged by: its id, else a normal attack, else its attack, else its status", function()
    local list = DamageNumbers.new()
    local a = list:add(hit(GUTS, GOB, { skill = { attack = "斬り1", id = "Job05_CrescentSlash" } }), 1, 10)
    eq(list:add(hit(GUTS, GOB, { skill = { attack = "斬り2", id = "Job05_CrescentSlash" } }), 1, 10), a,
        "two attack names of one skill")
    local b = list:add(hit(GUTS, GOB, { skill = { attack = "弱攻撃1", normal = true } }), 1, 10)
    eq(b ~= a, true, "a normal attack is not the skill")
    eq(list:add(hit(GUTS, GOB, { skill = { attack = "弱攻撃2", normal = true } }), 1, 10), b,
        "two normal attacks of one swing")
    local c = list:add(hit(GUTS, GOB, { skill = { attack = "謎" } }), 1, 10)
    eq(c ~= a and c ~= b, true, "an attack nothing names: by its name")
    eq(list:add(hit(GUTS, GOB, { skill = { attack = "謎" } }), 1, 10), c, "the same name")
    eq(#list.items, 3, "three numbers")
end)

-- The DamageRate around the enemy's defence step as the game has it (Singles): the bonus hits.lua hands over.
local function f32(x) return string.unpack("f", string.pack("f", x)) end
local function step(before, after) return { target_bonus = f32(after) - f32(before) } end

test("the crit rule: the enemy's defence step raised the DamageRate; never a DoT tick", function()
    local crit = DamageNumbers.crit
    eq(crit(hit(GUTS, GOB, step(1, 1.5))), true, "1 -> 1.5 in the enemy's step: a downed enemy")
    eq(crit(hit(CASCA, GOB, step(2.2, 2.7))), true, "2.2 -> 2.7: a downed enemy under the incense")
    eq(crit(hit(CASCA, GOB, step(2.2, 2.2))), false, "a final 2.2 the step did not change: the incense, a buff")
    eq(crit(hit(CASCA, GOB, step(1.2, 1.2))), false, "1.2 from a jump: the attacker's step")
    eq(crit(hit(GUTS, GOB, step(1, 1))), false, "a normal hit")
    eq(crit(hit(GUTS, GOB, step(1.5, 1))), false, "a lowered rate: no crit")
    eq(crit(hit(GUTS, GOB, { target_bonus = 0.0005 })), false, "float dust is no rise")
    eq(crit(hit(GUTS, GOB, { target_bonus = nil })), false, "not read")
    eq(crit(hit(GUTS, GOB, { target_bonus = 0 / 0 })), false, "nan")
    eq(crit(hit(nil, GOB, { status = "FireSpread", target_bonus = 0.5 })), false, "a DoT tick")
end)

test("the weak-point rule: IsWeakDamage; never a DoT tick", function()
    local weak = DamageNumbers.weak
    eq(weak(hit(GUTS, GOB, { weak_damage = true })), true, "the game's flag")
    eq(weak(hit(GUTS, GOB, { weak_damage = true, target_bonus = -0.6 })), true, "whatever the rate")
    eq(weak(hit(GUTS, GOB, { weak_damage = false })), false, "not set")
    eq(weak(hit(GUTS, GOB, { weak_damage = nil })), false, "not read")
    eq(weak(hit(GUTS, GOB, { weak_damage = false, target_bonus = 0.5,
        region = { before = { Slash = 100 }, after = { Slash = 300 } } })), false,
        "a crit or a part's multiplier is not a weak point")
    eq(weak(hit(nil, GOB, { status = "FireSpread", weak_damage = true })), false, "a DoT tick")
end)

test("a number is a crit or a weak point when any of its hits is; a DoT tick is marked", function()
    local list = DamageNumbers.new()
    local n = list:add(hit(GUTS, GOB), 100, 10)
    eq(n.crit, false, "a plain first hit")
    list:add(hit(GUTS, GOB, { target_bonus = 0.5 }), 300, 10.1)
    eq(n.crit, true, "a crit joins: a crit"); eq(n.crit_t, 10.1, "since the crit")
    list:add(hit(GUTS, GOB, { target_bonus = 0.5 }), 300, 10.2)
    eq(n.crit_t, 10.1, "its pop starts once")
    list:add(hit(GUTS, GOB, { target_bonus = 0 }), 50, 10.25)
    eq(n.crit, true, "a plain hit after it changes nothing")
    eq(n.weak, false, "no weak point yet")
    list:add(hit(GUTS, GOB, { weak_damage = true }), 50, 10.3)
    eq(n.weak, true, "a weak-point hit joins: a weak point")
    near(n.amount, 800, 1e-9, "the sum")
    local both = list:add(hit(CASCA, GOB, { target_bonus = 0.5, weak_damage = true }), 10, 11)
    eq(both.crit and both.weak, true, "both at once"); eq(both.crit_t, 11, "a crit from its first hit")
    local tick = list:add(hit(nil, GOB, { status = "FireSpread", skill = { status = "FireSpread" } }), 10, 11)
    eq(tick.dot, true, "a DoT tick"); eq(tick.crit or tick.weak, false, "neither a crit nor a weak point")
end)

test("at most 40 numbers live: the oldest goes first", function()
    local list = DamageNumbers.new()
    eq(DamageNumbers.MAX, 40, "40")
    local first = list:add(hit(GUTS, GOB, { skill = { attack = "a0" } }), 1, 10)
    for i = 1, 39 do list:add(hit(GUTS, GOB, { skill = { attack = "a" .. i } }), 1, 10) end
    eq(#list.items, 40, "40 live")
    eq(list.items[1], first, "the first is the oldest")
    local new = list:add(hit(GUTS, GOB, { skill = { attack = "a40" } }), 1, 10.1)
    eq(#list.items, 40, "still 40")
    eq(list.items[1] ~= first, true, "the oldest is gone")
    eq(list.items[40], new, "the new one is last")
    -- a hit that merges takes no place
    list:add(hit(GUTS, GOB, { skill = { attack = "a40" } }), 1, 10.1)
    eq(#list.items, 40, "a merge adds none")
    eq(new.amount, 2, "merged")
end)

test("prune forgets the numbers older than their life; clear forgets all", function()
    local list = DamageNumbers.new()
    list:add(hit(GUTS, GOB), 1, 10)
    list:add(hit(CASCA, GOB), 1, 10.5)
    list:add(hit(ALLY, GOB), 1, 11)
    list:prune(11, 1)
    eq(#list.items, 3, "1 s old: still alive")
    list:prune(11.2, 1)
    eq(#list.items, 2, "the first is gone")
    eq(list.items[1].who, "ch100000_00", "the second is the oldest now")
    list:prune(12.4, 1.5)
    eq(#list.items, 1, "a longer life keeps the last")
    list:prune(12.6, 1.5)
    eq(#list.items, 0, "until it is over")
    list:clear()
    eq(#list.items, 0, "cleared")
    eq(list:add(hit(GUTS, GOB), 1, 13).amount, 1, "and filled again")
end)

T.finish()
