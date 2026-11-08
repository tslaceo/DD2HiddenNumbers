package.path = "mod/reframework/autorun/?.lua;tests/?.lua;" .. package.path

local T = require("testlib")
local test, eq, near = T.test, T.eq, T.near
local Fight = require("DD2DamageMeter/fight")
local Ledger = require("DD2DamageMeter/ledger")

local function actor(key, name, kind, base_id, max_hp, order)
    return { key = key, name = name, kind = kind, base_id = base_id, max_hp = max_hp, order = order }
end

local PL = actor("ch000000_00", "Guts", "player", "ch000000_00", 2400)
local P0 = actor("ch100000_00", "Casca", "pawn", "ch100000_00", 2500, 1)
local P1 = actor("ch111007_00", "Torinald", "pawn", "ch111007_00", 2470, 2)
local P2 = actor("ch111002_00", "Yves", "pawn", "ch111002_00", 2600, 3)
local ALLY = actor("ch111003_00", "Stranger", "ally", "ch111003_00", 1500)
local GOB = actor("ch220003_00_15", "Goblin", "enemy", "ch220003_00", 3700)
local GOB2 = actor("ch220003_00_16", "Goblin", "enemy", "ch220003_00", nil)
local BARREL = actor("obj_barrel_01", "Barrel", "other", "obj_barrel", 200)
local ALLY2 = actor("ch111004_00", "Hermit", "ally", "ch111004_00", 1400)
local MINO = actor("ch230001_00_1", "Minotaur", "enemy", "ch230001_00", 55000)

-- A plain hit with sane defaults; `o` overrides any field.
local function hit(attacker, victim, o)
    local h = {
        t = 1, attacker = attacker, victim = victim, skill = { attack = "atk" },
        final = 100, hp0 = 1000, hp1 = 900,
    }
    for k, v in pairs(o or {}) do h[k] = v end
    return h
end

test("the documented sword hit", function()
    local f = Fight.new(0)
    f:add_hit({ t = 1, attacker = P0, victim = GOB, skill = { attack = "弱攻撃_ヒットスロー小" },
        final = 405.1336, hp0 = 3053.035, hp1 = 2647.901, before = 479.45, after = 339.45, types = { Slash = 339.45 } })
    local snap = f:snapshot(2)
    local s = snap.actors[P0.key]
    eq(s.actor.key, P0.key, "actor"); eq(s.actor.name, "Casca", "actor name")
    near(s.dealt, 405.134, 0.01, "dealt"); near(s.dealt_full, 405.1336, 1e-9, "dealt_full")
    eq(s.hits, 1, "hits"); eq(s.kills, 0, "kills")
    local saved = 405.1336 * 479.45 / 339.45 - 405.1336
    near(s.enemy_def_before, 479.45, 0.01); near(s.enemy_def_after, 339.45, 0.01)
    near(s.enemy_def_saved, saved, 0.01)
    eq(s.armor_before, 0, "the attacker's own armor is untouched")
    local sk = s.skills["弱攻撃_ヒットスロー小"]
    eq(sk.hits, 1, "skill hits"); near(sk.total, 405.134, 0.01, "skill total"); near(sk.max, 405.134, 0.01, "skill max")
    eq(sk.ref.attack, "弱攻撃_ヒットスロー小", "skill ref")
    -- the goblin is a victim: HP bookkeeping and the taken side
    local e = snap.enemies[GOB.key]
    eq(e.actor.key, GOB.key, "enemy actor"); eq(e.max_hp, 3700, "enemy max_hp"); near(e.hp, 2647.901, 1e-6, "enemy hp")
    eq(e.killed, false, "killed")
    near(snap.actors[GOB.key].taken, 405.134, 0.01, "goblin taken")
    near(snap.actors[GOB.key].taken_from[P0.key], 405.134, 0.01, "goblin taken_from")
    -- the same step seen from the goblin's side is its own armor
    local g = snap.actors[GOB.key]
    near(g.armor_before, 479.45, 0.01, "goblin armor_before"); near(g.armor_after, 339.45, 0.01, "goblin armor_after")
    near(g.armor_saved, saved, 0.01, "goblin armor_saved")
    eq(g.enemy_def_before, 0, "goblin dealt nothing")
    near(snap.types.Slash, 339.45, 1e-9, "types")
end)

test("overkill counts HP removed, full damage kept", function()
    local f = Fight.new(0)
    f:add_hit(hit(PL, GOB, { final = 4694.4, hp0 = 28.4, hp1 = 0 }))
    local snap = f:snapshot(1)
    local s = snap.actors[PL.key]
    near(s.dealt, 28.4, 1e-9, "dealt"); near(s.dealt_full, 4694.4, 1e-9, "dealt_full")
    eq(s.kills, 1, "kills")
    eq(snap.enemies[GOB.key].killed, true, "killed")
    near(snap.enemies[GOB.key].hp, 0, 1e-9, "hp")
    near(snap.actors[GOB.key].taken, 28.4, 1e-9, "victim taken"); near(snap.actors[GOB.key].taken_full, 4694.4, 1e-9, "victim taken_full")
end)

test("a kill is counted once, only for enemy victims", function()
    local f = Fight.new(0)
    f:add_hit(hit(P0, GOB, { hp0 = 50, hp1 = 0 }))
    f:add_hit(hit(P1, GOB, { hp0 = 0, hp1 = 0 }))      -- stale hit in the same frame
    f:add_hit(hit(GOB2, PL, { hp0 = 30, hp1 = 0 }))    -- the player goes down: not a kill, not an enemy
    f:add_hit(hit(P2, GOB2, { hp0 = 100, hp1 = 120 })) -- HP went up under the hit
    local snap = f:snapshot(1)
    eq(snap.actors[P0.key].kills, 1, "first killer")
    eq(snap.actors[P1.key].kills, 0, "second hit is not a kill")
    eq(snap.actors[GOB2.key].kills, 0, "downing the player is not a kill")
    eq(snap.enemies[PL.key], nil, "player is not an enemy")
    near(snap.actors[P1.key].dealt, 0, 1e-9, "stale hit removes nothing")
    near(snap.actors[P2.key].dealt, 0, 1e-9, "dealt never negative")
end)

test("goblin hit on the player: armor saved 1032", function()
    local f = Fight.new(0)
    f:add_hit({ t = 1, attacker = GOB, victim = PL, skill = { attack = "atk_goblin" },
        final = 137.8936, hp0 = 2245.86, hp1 = 2107.967, before = 900, after = 106.072 })
    local snap = f:snapshot(2)
    local p = snap.actors[PL.key]
    near(p.taken, 137.89, 0.01, "taken"); near(p.taken_full, 137.8936, 1e-9, "taken_full")
    eq(p.hits_taken, 1, "hits_taken"); near(p.taken_from[GOB.key], 137.89, 0.01, "taken_from goblin")
    -- the player's own armor on the damage he took
    near(p.armor_before, 900, 1e-9, "armor_before"); near(p.armor_after, 106.072, 1e-9, "armor_after")
    near(p.armor_saved, 1032.2, 0.5, "armor_saved")
    near((p.armor_before - p.armor_after) / p.armor_before, 794 / 900, 0.001, "share")
    eq(p.enemy_def_before, 0, "the player dealt nothing")
    -- the goblin's blow met that armor: its enemy_def_* hold the same numbers
    local g = snap.actors[GOB.key]
    near(g.enemy_def_before, 900, 1e-9, "goblin enemy_def_before"); near(g.enemy_def_after, 106.072, 1e-9, "goblin enemy_def_after")
    near(g.enemy_def_saved, 1032.2, 0.5, "goblin enemy_def_saved")
    eq(g.armor_before, 0, "the goblin's own armor is untouched")
    near(g.dealt, 137.89, 0.01, "goblin dealt")
    -- the player is not an enemy, and the goblin's blow is not party damage
    eq(snap.enemies[PL.key], nil, "enemies")
    eq(next(snap.types), nil, "types")
end)

test("all absorbed: before/after counted, saved not", function()
    local f = Fight.new(0)
    f:add_hit(hit(GOB, PL, { final = 0.77, hp0 = 500, hp1 = 499.23, before = 132, after = -8 }))
    local snap = f:snapshot(1)
    local p, g = snap.actors[PL.key], snap.actors[GOB.key]
    near(p.armor_before, 132, 1e-9, "armor_before")
    near(p.armor_after, 0, 1e-9, "armor_after clamped")
    near(p.armor_saved, 0, 1e-9, "armor_saved")
    near(g.enemy_def_before, 132, 1e-9, "enemy_def_before")
    near(g.enemy_def_after, 0, 1e-9, "enemy_def_after clamped")
    near(g.enemy_def_saved, 0, 1e-9, "enemy_def_saved")
end)

test("no armor numbers: armor untouched", function()
    local f = Fight.new(0)
    f:add_hit(hit(PL, GOB))
    f:add_hit(hit(PL, GOB, { before = 0, after = 0 }))
    local snap = f:snapshot(1)
    local s, g = snap.actors[PL.key], snap.actors[GOB.key]
    eq(s.enemy_def_before, 0, "before"); eq(s.enemy_def_after, 0, "after"); eq(s.enemy_def_saved, 0, "saved")
    eq(g.armor_before, 0, "victim before"); eq(g.armor_after, 0, "victim after"); eq(g.armor_saved, 0, "victim saved")
    eq(s.hits, 2, "hits")
end)

test("armor sums over hits", function()
    local f = Fight.new(0)
    f:add_hit(hit(PL, GOB, { final = 100, before = 200, after = 100 }))  -- saved 100
    f:add_hit(hit(PL, GOB, { final = 50, before = 300, after = 150 }))   -- saved 50
    f:add_hit(hit(PL, GOB, { final = 1, before = 10, after = -2 }))      -- counted, not saved
    local snap = f:snapshot(1)
    local s, g = snap.actors[PL.key], snap.actors[GOB.key]
    near(s.enemy_def_before, 510, 1e-9, "before"); near(s.enemy_def_after, 250, 1e-9, "after")
    near(s.enemy_def_saved, 150, 1e-9, "saved")
    near(g.armor_before, 510, 1e-9, "victim before"); near(g.armor_after, 250, 1e-9, "victim after")
    near(g.armor_saved, 150, 1e-9, "victim saved")
end)

test("hit without attacker", function()
    local f = Fight.new(0)
    f:add_hit({ t = 1, attacker = nil, victim = PL, skill = {}, final = 50, hp0 = 1000, hp1 = 960,
        before = 20, after = 10, types = { Blow = 50 } })
    local snap = f:snapshot(2)
    local p = snap.actors[PL.key]
    near(p.taken_from.other, 40, 1e-9, "taken_from.other")
    near(p.taken, 40, 1e-9, "taken"); near(p.taken_full, 50, 1e-9, "taken_full"); eq(p.hits_taken, 1, "hits_taken")
    near(p.armor_before, 20, 1e-9, "armor_before"); near(p.armor_after, 10, 1e-9, "armor_after")
    near(p.armor_saved, 50, 1e-9, "armor_saved")
    local n = 0
    for _ in pairs(snap.actors) do n = n + 1 end
    eq(n, 1, "no phantom attacker")
    eq(next(snap.types), nil, "unattributed damage is not party damage")
end)

test("an enemy DoT tick with no known source is Other's damage", function()
    local f = Fight.new(0)
    f:add_hit(hit(P0, GOB, { final = 100, hp0 = 1000, hp1 = 900, types = { Slash = 100 } }))
    f:add_hit({ t = 2, attacker = nil, victim = GOB, skill = {}, final = 60, hp0 = 900, hp1 = 850, status = "burn",
        before = 20, after = 10, types = { Fire = 50 } })
    f:add_hit({ t = 3, attacker = nil, victim = GOB, skill = {}, final = 10, hp0 = 850, hp1 = 840, status = "poison" })
    local snap = f:snapshot(4)
    local o = snap.actors.other
    eq(o.actor.key, "other", "pseudo key"); eq(o.actor.kind, "other", "pseudo kind")
    near(o.dealt, 60, 1e-9, "dealt is the HP removed (50 + 10)"); near(o.dealt_full, 70, 1e-9, "dealt_full (60 + 10)")
    eq(o.hits, 2, "hits"); eq(o.kills, 0, "kills")
    eq(next(o.skills), nil, "no skills")
    eq(o.enemy_def_before, 0, "no enemy_def_before"); eq(o.enemy_def_after, 0, "no enemy_def_after")
    eq(o.enemy_def_saved, 0, "no enemy_def_saved")
    -- not a party member's damage, not a party type
    local p = snap.actors[P0.key]
    near(p.dealt, 100, 1e-9, "the pawn's own dealt is untouched"); eq(p.hits, 1, "the pawn's hits")
    for _, key in ipairs({ PL.key, P1.key, P2.key }) do eq(snap.actors[key], nil, "nobody else is credited") end
    near(snap.types.Slash, 100, 1e-9, "types: the pawn's blow"); eq(snap.types.Fire, nil, "types: no tick damage")
    -- the victim lost the HP all the same
    near(snap.actors[GOB.key].taken, 160, 1e-9, "goblin taken")
    near(snap.actors[GOB.key].taken_from.other, 60, 1e-9, "goblin taken_from.other")
    near(snap.enemies[GOB.key].hp, 840, 1e-9, "enemy hp")
    -- a tick that kills is nobody's kill
    f:add_hit({ t = 5, attacker = nil, victim = GOB, skill = {}, final = 900, hp0 = 840, hp1 = 0, status = "burn" })
    snap = f:snapshot(6)
    eq(snap.enemies[GOB.key].killed, true, "the enemy died")
    eq(snap.actors.other.kills, 0, "Other has no kills"); near(snap.actors.other.dealt, 900, 1e-9, "no overkill in dealt")
    eq(snap.actors[P0.key].kills, 0, "nor does the pawn")
end)

test("a sourceless hit on a party member, an ally or an object is not Other's dealt", function()
    local f = Fight.new(0)
    f:add_hit({ t = 1, attacker = nil, victim = PL, skill = {}, final = 50, hp0 = 1000, hp1 = 950, status = "burn" })
    -- no party and no enemy in these two: they are not part of the fight at all
    f:add_hit({ t = 2, attacker = nil, victim = ALLY, skill = {}, final = 20, hp0 = 800, hp1 = 780 })
    f:add_hit({ t = 3, attacker = nil, victim = BARREL, skill = {}, final = 20, hp0 = 200, hp1 = 180 })
    local snap = f:snapshot(4)
    eq(snap.actors.other, nil, "no Other entry: nothing was dealt")
    near(snap.actors[PL.key].taken_from.other, 50, 1e-9, "party member: taken_from.other")
    eq(snap.actors[ALLY.key], nil, "ally: dropped")
    eq(snap.actors[BARREL.key], nil, "object: dropped")
end)

-- Hit.own (game/hits.lua), the victim did it to himself.
test("a member's own damage is his own: taken from its source, never dealt, never Other's", function()
    local f = Fight.new(0)
    f:add_hit(hit(P0, GOB, { hp0 = 3700, hp1 = 3600, types = { Slash = 100 } }))
    f:add_hit({ t = 2, attacker = nil, victim = P0, skill = {}, final = 1.6, hp0 = 2500, hp1 = 2498.4,
        own = "blood_pact" })
    f:add_hit({ t = 3, attacker = nil, victim = P0, skill = { attack = "緋染_代償" }, final = 2, hp0 = 2498.4,
        hp1 = 2496.4, own = "blood_pact", before = 4, after = 2 })
    f:add_hit({ t = 4, attacker = nil, victim = PL, skill = {}, final = 10, hp0 = 2400, hp1 = 2390, own = "self" })
    local snap = f:snapshot(5, true)
    local p0, pl = snap.actors[P0.key], snap.actors[PL.key]
    near(p0.taken, 3.6, 1e-9, "his HP lost"); eq(p0.hits_taken, 2, "two of his own")
    near(p0.taken_from["self:blood_pact"], 3.6, 1e-9, "from Blood Pact"); eq(p0.taken_from.other, nil, "not Other")
    eq(p0.taken_from[P0.key], nil, "not friendly fire")
    near(p0.armor_before, 4, 1e-9, "his armor step counts as for any hit")
    near(p0.dealt, 100, 1e-9, "his dealt is his blow only"); eq(p0.hits, 1, "one hit dealt")
    near(pl.taken_from["self:self"], 10, 1e-9, "the player's own, no Blood Pact")
    eq(pl.dealt, 0, "he dealt nothing")
    eq(snap.actors.other, nil, "no Other entry"); eq(snap.actors.env, nil, "nor the environment's")
    near(snap.types.Slash, 100, 1e-9, "party types: the blow only")
    eq(snap.enemies[P0.key], nil, "no enemy made of it")
    local r = snap.detail.record
    eq(#r, 4, "every hit recorded")
    eq(r[2].a, P0.key, "his own: under him"); eq(r[2].v, P0.key, "on him"); eq(r[2].s, "self:blood_pact", "its source")
    eq(r[4].a, PL.key, "the player's own"); eq(r[4].s, "self:self", "its source")
    eq(snap.detail.foes[P0.key], nil, "no foe")
end)

test("an enemy's own damage is «Falls and environment»'s, its kill too; a tick nobody caused stays Other's", function()
    local f = Fight.new(0)
    f:add_hit({ t = 1, attacker = nil, victim = GOB, skill = {}, final = 500, hp0 = 3700, hp1 = 3200, own = "self" })
    eq(f:held(), 1, "an enemy the party has not fought: its fall waits like any hit on it")
    f:add_hit(hit(P0, GOB, { t = 2, hp0 = 3200, hp1 = 3100, types = { Slash = 100 } }))
    f:add_hit({ t = 3, attacker = nil, victim = GOB, skill = {}, final = 1000, hp0 = 3100, hp1 = 2100, own = "self",
        types = { Fixed = 1000 } })
    f:add_hit({ t = 4, attacker = nil, victim = GOB, skill = { status = "Poison" }, status = "Poison", final = 10,
        hp0 = 2100, hp1 = 2090 })
    f:add_hit({ t = 5, attacker = nil, victim = GOB, skill = {}, final = 5000, hp0 = 2090, hp1 = 0, own = "self" })
    local snap = f:snapshot(6, true)
    local env = snap.actors.env
    eq(env.actor.key, "env", "pseudo key"); eq(env.actor.kind, "other", "a grey row's kind")
    near(env.dealt, 3590, 1e-9, "500 + 1000 + 2090, no overkill"); near(env.dealt_full, 6500, 1e-9, "full damage")
    eq(env.hits, 3, "hits"); eq(env.kills, 0, "a pseudo-actor counts no kills"); eq(next(env.skills), nil, "no skills")
    local other = snap.actors.other
    near(other.dealt, 10, 1e-9, "the tick nobody caused"); eq(other.hits, 1, "one")
    local gob = snap.actors[GOB.key]
    near(gob.taken_from.env, 3590, 1e-9, "taken from the environment"); near(gob.taken_from.other, 10, 1e-9, "and Other")
    eq(snap.enemies[GOB.key].killed, true, "it died"); eq(snap.enemies[GOB.key].killer, "env", "the killer is the row")
    local p0 = snap.actors[P0.key]
    near(p0.dealt, 100, 1e-9, "the pawn's own"); eq(p0.kills, 0, "nobody's kill")
    near(snap.detail.foes[GOB.key].by.env.dealt, 3590, 1e-9, "the card's dealer"); eq(snap.detail.foes[GOB.key].by.env.hits, 3, "hits")
    eq(snap.detail.foes[GOB.key].by.other.hits, 1, "Other's tick")
    eq(snap.types.Other, nil, "not the party's types")
    local r = snap.detail.record
    eq(r[1].a, "env", "the record"); eq(r[#r].kill, true, "the kill"); eq(r[#r].a, "env", "by the row")
end)

-- A knock hit (game/hits.lua) is an enemy's own damage that comes with the friend who knocked it as its attacker
-- and that friend's skill reference; the fight counts it as that friend's hit, as it counts any other.
test("a knock hit is its friend's: dealt, the knocking skill, taken_from, the kill; nothing for ENV", function()
    local f = Fight.new(0)
    local FROST = "フロストスパイクLv2_冷気_対ノルド敵"
    f:add_hit(hit(PL, GOB, { t = 1, hp0 = 3700, hp1 = 3600 }))
    f:add_hit(hit(ALLY, GOB, { t = 2, skill = { id = "Job03_Frigor", attack = FROST }, final = 400, hp0 = 3600,
        hp1 = 3200 }))
    f:add_hit({ t = 4.2, attacker = ALLY, victim = GOB, skill = { id = "Job03_Frigor", attack = FROST }, knock = true,
        final = 1000, hp0 = 3200, hp1 = 2200 })
    f:add_hit(hit(P0, GOB, { t = 5, skill = { attack = "弱攻撃_ヒットスロー大" }, final = 1600, hp0 = 2200, hp1 = 600 }))
    f:add_hit({ t = 5.5, attacker = P0, victim = GOB, skill = { attack = "弱攻撃_ヒットスロー大" }, knock = true,
        final = 1000, hp0 = 600, hp1 = 0 })
    local snap = f:snapshot(6, true)
    local ally, p0 = snap.actors[ALLY.key], snap.actors[P0.key]
    near(ally.dealt, 1400, 1e-9, "the ally's spike and slam"); eq(ally.hits, 2, "two hits")
    near(ally.skills[FROST].total, 1400, 1e-9, "in her Frost Spike"); eq(ally.skills[FROST].hits, 2, "two hits")
    eq(ally.skills[FROST].ref.id, "Job03_Frigor", "its skill")
    near(p0.dealt, 2200, 1e-9, "the pawn's throw and the slam's last 600"); eq(p0.kills, 1, "the slam killed")
    near(p0.skills["弱攻撃_ヒットスロー大"].total, 2200, 1e-9, "in her throw")
    local gob = snap.actors[GOB.key]
    near(gob.taken_from[ALLY.key], 1400, 1e-9, "taken from the ally")
    near(gob.taken_from[P0.key], 2200, 1e-9, "and from the pawn")
    eq(gob.taken_from.env, nil, "nothing from the environment")
    eq(snap.enemies[GOB.key].killer, P0.key, "the pawn's kill"); eq(snap.enemies[GOB.key].last_hit, 5.5, "hit last")
    eq(snap.actors.env, nil, "no «Falls and environment» row"); eq(snap.actors.other, nil, "nor Other")
    near(snap.detail.foes[GOB.key].by[ALLY.key].dealt, 1400, 1e-9, "the enemy card: the ally's")
    local r = snap.detail.record
    eq(r[3].a, ALLY.key, "the record: the ally's")
    eq(r[#r].a, P0.key, "the kill: the pawn's"); eq(r[#r].kill, true, "a kill")
end)

test("a member's own heal: he is its healer, by its source", function()
    local f = Fight.new(0)
    f:add_heal({ t = 1, target = P0, healer = P0, amount = 300, effective = 250, source = { kind = "self", name = "lifesteal" } })
    f:add_heal({ t = 2, target = P0, healer = P0, amount = 2, effective = 1.5, source = { kind = "self", name = "regen" } })
    local snap = f:snapshot(3, true)
    local p0 = snap.actors[P0.key]
    near(p0.heal_done, 251.5, 1e-9, "healed"); near(p0.heal_received, 251.5, 1e-9, "and received")
    near(p0.heal_sources["self:lifesteal"], 250, 1e-9, "lifesteal"); near(p0.heal_sources["self:regen"], 1.5, 1e-9, "regen")
    eq(snap.actors.other, nil, "not Other")
    near(snap.detail.heals[P0.key][P0.key]["self:lifesteal"].amount, 250, 1e-9, "the detail, by source")
    eq(snap.detail.record[2].a, P0.key, "the record: his"); eq(snap.detail.record[2].s, "self:regen", "its source")
end)

-- The Evil Eye, two bodies of one CharaID with one HP pool; a hit on one is mirrored on the other.
local EYE_A = { key = "a301", name = "ch270000_00", kind = "enemy", base_id = "ch270000_00", chara_id = 469873306,
                max_hp = 650000 }
local EYE_B = { key = "a302", name = "ch270000_00", kind = "enemy", base_id = "ch270000_00", chara_id = 469873306,
                max_hp = 650000 }

-- A party hit on `body` in `frame`, and the mirror on `other` (a sourceless hit with mirror = true) in `mframe`.
local function eye_hit(f, who, body, other, frame, mframe, hp0, amount)
    f:add_hit(hit(who, body, { frame = frame, hp0 = hp0, hp1 = hp0 - amount, final = amount, skill = { attack = "N" } }))
    if other then
        f:add_hit({ t = 1, attacker = nil, victim = other, skill = {}, final = amount, hp0 = hp0, hp1 = hp0 - amount,
                    mirror = true, frame = mframe })
    end
end

test("linked bodies: a mirror is never counted; the mirrored body joins the one hit, in the same frame or the next",
        function()
    local f = Fight.new(0)
    eye_hit(f, P0, EYE_A, EYE_B, 100, 100, 650000, 1000)
    eye_hit(f, PL, EYE_A, EYE_B, 110, 111, 649000, 2000)
    eq(f:add_hit({ t = 2, victim = EYE_B, skill = {}, final = 5, hp0 = 647000, hp1 = 646995, mirror = true, frame = 120 }),
        nil, "a mirror counts nothing")
    -- the party hits the other body too (it would be engaged now, and no mirror may count then either)
    eye_hit(f, P0, EYE_B, EYE_A, 130, 130, 647000, 500)
    local snap = f:snapshot(5, true)
    near(snap.actors[EYE_A.key].taken, 3500, 1e-9, "the body hit first took every hit once")
    eq(snap.actors[EYE_B.key], nil, "the other body has no entry"); eq(snap.enemies[EYE_B.key], nil, "and is no enemy")
    eq(snap.actors.env, nil, "nothing for «Падения и среда»"); eq(snap.actors.other, nil, "nor Other")
    near(snap.actors[P0.key].dealt + snap.actors[PL.key].dealt, 3500, 1e-9, "dealt once")
    eq(#snap.detail.record, 3, "three lines in the record")
    eq(snap.enemies[EYE_A.key].hp, 646500, "the pool's HP")
end)

test("linked bodies: after the link the other body's hits and blows are the kept one's; it is never listed",
        function()
    local f = Fight.new(0)
    eye_hit(f, P0, EYE_A, EYE_B, 100, 100, 650000, 1000)
    -- the party hits body B; its mirror lands on A
    eye_hit(f, PL, EYE_B, EYE_A, 120, 121, 649000, 5000)
    -- body B hits the player
    f:add_hit(hit(EYE_B, PL, { frame = 130, hp0 = 2400, hp1 = 2300, final = 100, types = { Blow = 100 } }))
    eq(f:is_engaged(EYE_B.key), true, "the other body is engaged as the kept one")
    -- the killing blow on B
    eye_hit(f, P0, EYE_B, EYE_A, 140, 140, 644000, 644000)
    local snap = f:snapshot(5, true)
    eq(snap.actors[EYE_B.key], nil, "no entry for B"); eq(snap.enemies[EYE_B.key], nil, "B is never listed")
    local a = snap.actors[EYE_A.key]
    near(a.taken, 650000, 1e-6, "A took the whole pool, once")
    near(snap.actors[PL.key].taken_from[EYE_A.key], 100, 1e-9, "B's blow on the player is A's")
    eq(snap.enemies[EYE_A.key].killed, true, "A died"); eq(snap.enemies[EYE_A.key].killer, P0.key, "by the pawn's blow")
    eq(snap.actors[P0.key].kills, 1, "one kill")
    near(snap.detail.foes[EYE_A.key].by[PL.key].dealt, 5000, 1e-9, "the card has the hit on B")
    eq(snap.detail.foes[EYE_B.key], nil, "B has no card")
    near(snap.detail.foes[EYE_A.key].attacks[PL.key].dealt, 100, 1e-9, "A's attack on the player")
    for _, e in ipairs(snap.detail.record) do
        if e.a == EYE_B.key or e.v == EYE_B.key then error("the record names B") end
    end
    eq(snap.actors.env, nil, "nothing for «Падения и среда»")
end)

test("linked bodies: a mirror before its hit links too; the body the party hit first is kept", function()
    -- the game mirrors inside the hit, before it is counted
    local f = Fight.new(0)
    f:add_hit({ t = 1, victim = EYE_B, skill = {}, final = 1000, hp0 = 650000, hp1 = 649000, mirror = true, frame = 99 })
    eye_hit(f, P0, EYE_A, nil, 100, nil, 650000, 1000)
    local snap = f:snapshot(5)
    eq(snap.enemies[EYE_B.key], nil, "B linked"); near(snap.actors[EYE_A.key].taken, 1000, 1e-9, "counted once on A")
    -- B was hit first (its mirror came too late to link), then A: B is kept, A folded into it
    f = Fight.new(0)
    eye_hit(f, PL, EYE_B, EYE_A, 100, 105, 650000, 1000)
    eq(f:snapshot(5).enemies[EYE_A.key], nil, "the late mirror is dropped, nothing linked yet")
    eye_hit(f, P0, EYE_A, EYE_B, 200, 200, 649000, 3000)
    snap = f:snapshot(5, true)
    eq(snap.enemies[EYE_A.key], nil, "A folded into B"); eq(snap.actors[EYE_A.key], nil, "no entry for A")
    near(snap.actors[EYE_B.key].taken, 4000, 1e-9, "B has both hits"); eq(snap.actors[EYE_B.key].hits_taken, 2, "two")
    eq(snap.enemies[EYE_B.key].hp, 646000, "the pool's HP: the lower of the two")
    near(snap.detail.foes[EYE_B.key].by[P0.key].dealt, 3000, 1e-9, "the card has the hit on A")
    near(snap.detail.foes[EYE_B.key].by[PL.key].dealt, 1000, 1e-9, "and the first one")
    eq(snap.detail.record[2].v, EYE_B.key, "the record names B")
    eq(f:is_engaged(EYE_A.key), true, "A is engaged as B")
end)

test("linked bodies: a sync with no loss is ignored; a mirror with nobody to join is dropped", function()
    local f = Fight.new(0)
    eye_hit(f, P0, EYE_A, nil, 100, nil, 650000, 1000)
    f:add_hit({ t = 1, victim = EYE_B, skill = {}, final = 649000, hp0 = 649000, hp1 = 649000, mirror = true,
                frame = 300 })
    local snap = f:snapshot(5, true)
    eq(snap.enemies[EYE_B.key], nil, "nothing for B"); eq(snap.actors.env, nil, "nor «Падения и среда»")
    eq(#snap.detail.record, 1, "one line")
    -- a mirror on an enemy whose kind nobody hit: dropped, nothing linked
    f = Fight.new(0)
    f:add_hit(hit(P0, GOB, { frame = 100, hp0 = 3700, hp1 = 3600 }))
    f:add_hit({ t = 1, victim = MINO, skill = {}, final = 10, hp0 = 55000, hp1 = 54990, mirror = true, frame = 100 })
    snap = f:snapshot(5)
    eq(snap.enemies[MINO.key], nil, "dropped"); near(snap.actors[GOB.key].taken, 100, 1e-9, "the goblin as it was")
end)

-- The fold takes the hidden body's held hits and heals along; a link needs the mirror's HP drop.
test("linked bodies: the hidden body's held hits are counted on the link, its heals are the kept one's", function()
    local f = Fight.new(0)
    -- an ally hits B before the party fought it: held
    f:add_hit(hit(ALLY, EYE_B, { frame = 90, hp0 = 650000, hp1 = 649300, final = 700 }))
    eq(f:held(), 1, "held")
    -- a party healer heals B (an enemy healed: rare, but kept): B's entry before the link
    f:add_heal({ t = 1, target = EYE_B, healer = P2, amount = 50, effective = 50, source = { kind = "skill" } })
    eye_hit(f, P0, EYE_A, EYE_B, 100, 100, 649300, 800)
    eq(f:held(), 0, "nothing held any more")
    f:add_heal({ t = 2, target = EYE_B, healer = P2, amount = 30, effective = 30, source = { kind = "skill" } })
    local snap = f:snapshot(5, true)
    eq(snap.actors[EYE_B.key], nil, "no entry for B")
    near(snap.actors[EYE_A.key].taken, 1500, 1e-9, "the pawn's 800 and the ally's 700")
    eq(snap.enemies[EYE_A.key].hp, 648500, "the pool's HP stays the lowest, the held hit's is older")
    near(snap.actors[ALLY.key].dealt, 700, 1e-9, "the ally's damage")
    near(snap.actors[EYE_A.key].heal_received, 80, 1e-9, "both heals on A")
    eq(snap.detail.heals[P2.key][EYE_B.key], nil, "the detail's heals name A only")
    near(snap.detail.heals[P2.key][EYE_A.key]["skill:?"].amount, 80, 1e-9, "summed under A")
    near(snap.detail.foes[EYE_A.key].by[ALLY.key].dealt, 700, 1e-9, "the card has the ally's hit")
end)

test("linked bodies: a link needs the mirror's HP drop; a sync never links", function()
    local f = Fight.new(0)
    -- two goblins of one kind: a hit on one, a bit-39 sync with no loss on the other
    f:add_hit(hit(P0, GOB, { frame = 100, hp0 = 3700, hp1 = 3600 }))
    f:add_hit({ t = 1, victim = GOB2, skill = {}, final = 3700, hp0 = 3700, hp1 = 3700, mirror = true, frame = 100 })
    f:add_hit(hit(P0, GOB2, { frame = 110, hp0 = 3700, hp1 = 3500 }))
    local snap = f:snapshot(5)
    eq(snap.enemies[GOB.key] ~= nil and snap.enemies[GOB2.key] ~= nil, true, "both goblins listed")
    near(snap.actors[GOB2.key].taken, 200, 1e-9, "the second goblin's own hit")
    -- a mirror whose drop is not the hit's
    f = Fight.new(0)
    eye_hit(f, P0, EYE_A, nil, 100, nil, 650000, 1000)
    f:add_hit({ t = 1, victim = EYE_B, skill = {}, final = 900, hp0 = 650000, hp1 = 649100, mirror = true, frame = 100 })
    eye_hit(f, P0, EYE_B, nil, 120, nil, 649100, 500)
    snap = f:snapshot(5)
    eq(snap.enemies[EYE_B.key] ~= nil, true, "not linked: B is its own"); near(snap.actors[EYE_B.key].taken, 500, 1e-9, "")
    -- within 1 HP it is the same drop
    f = Fight.new(0)
    eye_hit(f, P0, EYE_A, nil, 100, nil, 650000, 1000)
    f:add_hit({ t = 1, victim = EYE_B, skill = {}, final = 1000, hp0 = 650000, hp1 = 649000.5, mirror = true, frame = 101 })
    eye_hit(f, P0, EYE_B, nil, 120, nil, 649000, 500)
    eq(f:snapshot(5).enemies[EYE_B.key], nil, "linked")
end)

test("linked bodies: two enemies of one kind are never linked without a mirror; a sourceless hit is still the fall's",
        function()
    local f = Fight.new(0)
    f:add_hit(hit(P0, GOB, { frame = 100, hp0 = 3700, hp1 = 3600 }))
    f:add_hit(hit(P0, GOB2, { frame = 100, hp0 = 3700, hp1 = 3500 }))
    f:add_hit({ t = 1, victim = GOB2, skill = {}, final = 300, hp0 = 3500, hp1 = 3200, own = "self", frame = 101 })
    local snap = f:snapshot(5)
    near(snap.actors[GOB.key].taken, 100, 1e-9, "the first goblin"); near(snap.actors[GOB2.key].taken, 500, 1e-9, "the second")
    near(snap.actors.env.dealt, 300, 1e-9, "the sourceless hit without bit 39: «Падения и среда»")
    eq(snap.enemies[GOB.key] ~= nil and snap.enemies[GOB2.key] ~= nil, true, "both listed")
end)

test("friendly fire stays out of dealt", function()
    local f = Fight.new(0)
    f:add_hit(hit(P0, PL, { hp0 = 1000, hp1 = 970, final = 33, skill = { attack = "slash" },
        before = 60, after = 30, types = { Slash = 30 } }))
    f:add_hit(hit(ALLY, P0, { hp0 = 500, hp1 = 490, final = 10 }))
    local snap = f:snapshot(1)
    local pawn, pl = snap.actors[P0.key], snap.actors[PL.key]
    -- the attacker: nothing dealt, but the entry exists so the name can be looked up
    eq(pawn.actor.key, P0.key, "attacker entry")
    eq(pawn.dealt, 0, "dealt"); eq(pawn.dealt_full, 0, "dealt_full"); eq(pawn.hits, 0, "hits"); eq(pawn.kills, 0, "kills")
    eq(next(pawn.skills), nil, "skills")
    eq(pawn.enemy_def_before, 0, "enemy_def_before"); eq(pawn.enemy_def_saved, 0, "enemy_def_saved")
    eq(snap.actors[ALLY.key].dealt, 0, "ally dealt")
    eq(next(snap.types), nil, "friendly fire is not damage dealt to enemies")
    -- the victim: it still hurt
    near(pl.taken, 30, 1e-9, "taken"); near(pl.taken_full, 33, 1e-9, "taken_full"); eq(pl.hits_taken, 1, "hits_taken")
    near(pl.taken_from[P0.key], 30, 1e-9, "taken_from pawn")
    near(pl.armor_before, 60, 1e-9, "armor_before"); near(pl.armor_after, 30, 1e-9, "armor_after")
    near(pl.armor_saved, 33, 1e-9, "armor_saved")
    near(pawn.taken_from[ALLY.key], 10, 1e-9, "ally on pawn")
end)

test("enemy hitting an enemy is not dealt", function()
    local f = Fight.new(0)
    f:add_hit(hit(PL, GOB, { hp0 = 400, hp1 = 300 })) -- the party fights the victim
    f:add_hit(hit(GOB2, GOB, { hp0 = 300, hp1 = 250, final = 50 }))
    local snap = f:snapshot(1)
    eq(snap.actors[GOB2.key].dealt, 0, "dealt"); eq(snap.actors[GOB2.key].hits, 0, "hits")
    near(snap.actors[GOB.key].taken_from[GOB2.key], 50, 1e-9, "taken_from")
    near(snap.enemies[GOB.key].hp, 250, 1e-9, "the hit still lowers the enemy's HP")
    -- a kill by another enemy is nobody's kill
    f:add_hit(hit(GOB2, GOB, { hp0 = 250, hp1 = 0, final = 250 }))
    snap = f:snapshot(2)
    eq(snap.enemies[GOB.key].killed, true, "killed")
    eq(snap.actors[GOB2.key].kills, 0, "kills")
end)

test("hit on an object is not dealt", function()
    local f = Fight.new(0)
    f:add_hit(hit(PL, BARREL, { hp0 = 200, hp1 = 0, final = 300, before = 20, after = 10, types = { Blow = 200 } }))
    f:add_hit(hit(BARREL, PL, { hp0 = 1000, hp1 = 950, final = 50 }))
    local snap = f:snapshot(1)
    local pl, barrel = snap.actors[PL.key], snap.actors[BARREL.key]
    eq(pl.dealt, 0, "dealt"); eq(pl.dealt_full, 0, "dealt_full"); eq(pl.hits, 0, "hits"); eq(pl.kills, 0, "kills")
    eq(next(pl.skills), nil, "skills"); eq(pl.enemy_def_before, 0, "enemy_def_before")
    eq(barrel.dealt, 0, "an object deals nothing"); eq(barrel.hits, 0, "object hits")
    near(barrel.taken, 200, 1e-9, "object taken"); near(barrel.taken_from[PL.key], 200, 1e-9, "object taken_from")
    near(barrel.armor_before, 20, 1e-9, "object armor_before")
    near(pl.taken, 50, 1e-9, "the player still takes damage from it"); near(pl.taken_from[BARREL.key], 50, 1e-9, "player taken_from")
    eq(snap.enemies[BARREL.key], nil, "an object is not an enemy")
    eq(next(snap.types), nil, "types")
end)

test("guard sums on the victim", function()
    local f = Fight.new(0)
    f:add_hit(hit(GOB, PL, { guard = 30 }))
    f:add_hit(hit(GOB, PL, { guard = 25.5 }))
    f:add_hit(hit(GOB, PL))
    local snap = f:snapshot(1)
    near(snap.actors[PL.key].guard, 55.5, 1e-9, "victim guard")
    eq(snap.actors[GOB.key].guard, 0, "attacker guard")
end)

test("types sum the party's damage to enemies only", function()
    local f = Fight.new(0)
    f:add_hit(hit(PL, GOB, { types = { Slash = 80, Fire = 20 } }))
    f:add_hit(hit(P2, GOB, { types = { Magic = 60, Fire = 15 } }))
    f:add_hit(hit(ALLY, GOB, { types = { Slash = 999 } }))
    f:add_hit(hit(GOB, P0, { types = { Slash = 777 } }))
    local t = f:snapshot(1).types
    near(t.Slash, 80, 1e-9, "Slash"); near(t.Fire, 35, 1e-9, "Fire"); near(t.Magic, 60, 1e-9, "Magic")
end)

test("skills aggregate by raw key: the attack name first, then the id", function()
    local f = Fight.new(0)
    f:add_hit(hit(P1, GOB, { skill = { id = "Skill 7", attack = "a" }, hp0 = 1000, hp1 = 900 }))
    f:add_hit(hit(P1, GOB, { skill = { id = "Skill 7", attack = "b_極" }, hp0 = 900, hp1 = 650 }))
    f:add_hit(hit(P1, GOB, { skill = { id = "Skill 7", attack = "a" }, hp0 = 650, hp1 = 600 }))
    f:add_hit(hit(P1, GOB, { skill = { id = "Skill 9" }, hp0 = 600, hp1 = 580 }))
    f:add_hit(hit(P1, GOB, { skill = { attack = "plain" }, hp0 = 580, hp1 = 530 }))
    f:add_hit(hit(P1, GOB, { skill = {}, hp0 = 530, hp1 = 520 }))
    local sk = f:snapshot(1).actors[P1.key].skills
    eq(sk.a.hits, 2, "same attack name, same entry"); near(sk.a.total, 150, 1e-9, "attack total"); near(sk.a.max, 100, 1e-9, "attack max")
    eq(sk.a.ref.id, "Skill 7", "ref keeps the id"); eq(sk.a.ref.attack, "a", "ref keeps the attack name")
    eq(sk["b_極"].hits, 1, "another attack of the same skill id is its own entry"); near(sk["b_極"].total, 250, 1e-9, "its total")
    eq(sk["Skill 7"], nil, "the id is not the key while an attack name exists")
    eq(sk["Skill 9"].hits, 1, "id-only key"); near(sk["Skill 9"].total, 20, 1e-9, "id-only total")
    eq(sk.plain.hits, 1, "attack-only key"); near(sk.plain.total, 50, 1e-9, "attack-only total")
    eq(sk["?"].hits, 1, "unknown key"); near(sk["?"].total, 10, 1e-9, "unknown total")
end)

-- Hits of one attack name in a row: "n" a normal attack (state None), "?" nothing known, else the skill id.
local function hits_of(f, attacker, attack, seq)
    for _, v in ipairs(seq) do
        local skill = { attack = attack }
        if v == "n" then skill.normal = true elseif v ~= "?" then skill.id = v end
        f:add_hit(hit(attacker, GOB, { skill = skill, final = 10, hp0 = 1000, hp1 = 990 }))
    end
end

local function rep(v, n)
    local t = {}
    for i = 1, n do t[i] = v end
    return table.unpack(t)
end

test("a skill entry is named by most of its hits: one stray id does not relabel normal attacks", function()
    local f = Fight.new(0)
    -- Casca: 10 normal N_軽, one N_軽 while the state said War Cry, 5 more normal
    hits_of(f, P1, "N_軽", { rep("n", 10) })
    hits_of(f, P1, "N_軽", { "Job05_WarCry" })
    hits_of(f, P1, "N_軽", { rep("n", 5) })
    local sk = f:snapshot(1).actors[P1.key].skills["N_軽"]
    eq(sk.ref.id, nil, "no skill id"); eq(sk.ref.normal, true, "still a normal attack")
    eq(sk.hits, 16, "all hits counted"); near(sk.total, 160, 1e-9, "total")
end)

test("a skill entry follows the leading vote: an id or a normal attack, ties keep the current one", function()
    local f = Fight.new(0)
    -- a shell first seen as a normal attack (it landed after the state was gone), then mostly with its skill
    hits_of(f, P1, "連なり撃ち_近距離", { "n", "Job02_ThreefoldArrow" })
    eq(f:snapshot(1).actors[P1.key].skills["連なり撃ち_近距離"].ref.normal, true, "a tie keeps the normal attack")
    hits_of(f, P1, "連なり撃ち_近距離", { "Job02_ThreefoldArrow" })
    local sk = f:snapshot(1).actors[P1.key].skills["連なり撃ち_近距離"]
    eq(sk.ref.id, "Job02_ThreefoldArrow", "the skill leads"); eq(sk.ref.normal, nil, "no normal flag")
    eq(sk.ref.attack, "連なり撃ち_近距離", "attack name"); eq(sk.hits, 3, "hits")
    -- a first stray id, then mostly normal attacks
    hits_of(f, P1, "N_軽_早繋ぎ", { "Job05_WarCry", "n", "n" })
    sk = f:snapshot(1).actors[P1.key].skills["N_軽_早繋ぎ"]
    eq(sk.ref.id, nil, "the stray id gave way"); eq(sk.ref.normal, true, "normal attack")
    -- two ids: the leader names it, a tie keeps it
    hits_of(f, P1, "CS_09_魔人斬り", { "Job05_IndomitableLash", "Job05_CrescentSlash" })
    eq(f:snapshot(1).actors[P1.key].skills["CS_09_魔人斬り"].ref.id, "Job05_IndomitableLash", "tie")
    hits_of(f, P1, "CS_09_魔人斬り", { "Job05_CrescentSlash" })
    eq(f:snapshot(1).actors[P1.key].skills["CS_09_魔人斬り"].ref.id, "Job05_CrescentSlash", "the new leader")
end)

test("a skill entry: one known vote beats any number of unknown ones", function()
    local f = Fight.new(0)
    hits_of(f, P1, "CS_06_抉り抜き_1_押", { "?", "?", "?", "Job04_HollowOut" })
    local sk = f:snapshot(1).actors[P1.key].skills["CS_06_抉り抜き_1_押"]
    eq(sk.ref.id, "Job04_HollowOut", "the id at once"); eq(sk.hits, 4, "hits")
    hits_of(f, P1, "CS_06_抉り抜き_1_押", { "?", "?", "?", "?" })
    eq(f:snapshot(1).actors[P1.key].skills["CS_06_抉り抜き_1_押"].ref.id, "Job04_HollowOut", "unknown never leads")
    hits_of(f, P1, "x", { "?", "n" })
    eq(f:snapshot(1).actors[P1.key].skills.x.ref.normal, true, "a normal attack beats unknown too")
end)

test("a skill entry's new name does not rewrite a snapshot taken before", function()
    local f = Fight.new(0)
    hits_of(f, P1, "x", { "?" })
    local before = f:snapshot(1)
    hits_of(f, P1, "x", { "Job01_BlinkStrike" })
    eq(before.actors[P1.key].skills.x.ref.id, nil, "the earlier snapshot keeps its ref")
    eq(before.actors[P1.key].skills.x.hits, 1, "and its count")
    eq(f:snapshot(1).actors[P1.key].skills.x.ref.id, "Job01_BlinkStrike", "the live entry has the id")
end)

test("skills keep the normal-attack flag, and a DoT tick is keyed by its status", function()
    local f = Fight.new(0)
    f:add_hit(hit(P2, GOB, { skill = { attack = "ラピッドショット", normal = true }, hp0 = 1000, hp1 = 950 }))
    f:add_hit(hit(P2, GOB, { skill = { status = "FireSpread" }, status = "FireSpread", hp0 = 950, hp1 = 920 }))
    f:add_hit(hit(P2, GOB, { skill = { status = "FireSpread" }, status = "FireSpread", hp0 = 920, hp1 = 900 }))
    f:add_hit(hit(P2, GOB, { skill = { status = "Poison" }, status = "Poison", hp0 = 900, hp1 = 890 }))
    f:add_hit(hit(P2, GOB, { skill = {}, hp0 = 890, hp1 = 885 }))
    local sk = f:snapshot(1).actors[P2.key].skills
    eq(sk["ラピッドショット"].ref.normal, true, "ref keeps the normal flag")
    eq(sk["status:FireSpread"].hits, 2, "burn ticks are one entry")
    near(sk["status:FireSpread"].total, 50, 1e-9, "their total")
    eq(sk["status:FireSpread"].ref.status, "FireSpread", "ref keeps the status")
    eq(sk["status:Poison"].hits, 1, "another status, another entry")
    eq(sk["?"].hits, 1, "an unknown skill is not mixed with the ticks")
end)

test("enemy HP: max from the actor or from the first hp0, latest hp", function()
    local f = Fight.new(0)
    f:add_hit(hit(PL, GOB, { hp0 = 3000, hp1 = 2900 }))
    f:add_hit(hit(PL, GOB, { hp0 = 2900, hp1 = 2800 }))
    f:add_hit(hit(PL, GOB2, { hp0 = 500, hp1 = 400 }))
    f:add_hit(hit(PL, GOB2, { hp0 = 400, hp1 = 100 }))
    local e = f:snapshot(1).enemies
    near(e[GOB.key].max_hp, 3700, 1e-9, "known max_hp"); near(e[GOB.key].hp, 2800, 1e-9, "known hp")
    near(e[GOB2.key].max_hp, 500, 1e-9, "inferred max_hp"); near(e[GOB2.key].hp, 100, 1e-9, "inferred hp")
    eq(e[GOB2.key].killed, false, "alive")
end)

test("note_hp: an enemy of the fight takes the HP the game shows now, read outside the hits", function()
    local f = Fight.new(0)
    f:add_hit(hit(PL, MINO, { hp0 = 55000, hp1 = 50000 }))
    local key, e = f:note_hp(MINO.key, 47681.5, 55000)
    eq(key, MINO.key, "its key"); eq(e, f.enemies[MINO.key], "its entry")
    near(f:snapshot(1).enemies[MINO.key].hp, 47681.5, 1e-9, "the HP shown")
    -- HP up again (a heal the hits never see): taken too; a full HP above the known one raises it
    f:note_hp(MINO.key, 48000, 56000)
    local m = f:snapshot(1).enemies[MINO.key]
    near(m.hp, 48000, 1e-9, "up"); near(m.max_hp, 56000, 1e-9, "full HP raised")
    f:note_hp(MINO.key, 47000, 50000)
    near(f:snapshot(1).enemies[MINO.key].max_hp, 56000, 1e-9, "never lowered")
    near(f:snapshot(1).enemies[MINO.key].hp, 47000, 1e-9, "the HP")
    -- the next hit's HP after it, as before
    f:add_hit(hit(PL, MINO, { hp0 = 47000, hp1 = 46000 }))
    near(f:snapshot(1).enemies[MINO.key].hp, 46000, 1e-9, "a hit sets it")
    -- an enemy that only hit the party: its HP is known from now on
    f:add_hit(hit(GOB, PL, { hp0 = 2400, hp1 = 2300 }))
    eq(f:snapshot(1).enemies[GOB.key].hp, nil, "not known")
    f:note_hp(GOB.key, 3100, 3700)
    near(f:snapshot(1).enemies[GOB.key].hp, 3100, 1e-9, "known")
    -- below 0 is 0
    f:note_hp(GOB.key, -5, 3700)
    near(f:snapshot(1).enemies[GOB.key].hp, 0, 1e-9, "0")
    -- nothing for a character that is no enemy of the fight, a party member, an HP that is not a number
    eq(f:note_hp(GOB2.key, 100, 500), nil, "no enemy of the fight")
    eq(f:snapshot(1).enemies[GOB2.key], nil, "none made")
    eq(f:note_hp(PL.key, 100, 2400), nil, "the player")
    for _, bad in ipairs({ 0 / 0, math.huge, "5" }) do
        eq(f:note_hp(MINO.key, bad, 56000), nil, "HP " .. tostring(bad))
    end
    eq(f:note_hp(MINO.key, nil, 56000), nil, "no HP")
    near(f:snapshot(1).enemies[MINO.key].hp, 46000, 1e-9, "kept")
    f:note_hp(MINO.key, 45000, 0 / 0)
    near(f:snapshot(1).enemies[MINO.key].hp, 45000, 1e-9, "a full HP that is not a number: the HP alone")
    near(f:snapshot(1).enemies[MINO.key].max_hp, 56000, 1e-9, "the full HP kept")
    -- a killed enemy keeps its 0 and its kill
    f:add_hit(hit(P0, MINO, { hp0 = 45000, hp1 = 0 }))
    eq(f:note_hp(MINO.key, 120, 56000), nil, "killed: nothing")
    local k = f:snapshot(1).enemies[MINO.key]
    near(k.hp, 0, 1e-9, "0"); eq(k.killed, true, "killed"); eq(k.killer, P0.key, "by the pawn")
end)

test("note_hp: a linked body or a returning enemy's new object gives its HP to the enemy it counts as", function()
    local EYE_A = { key = "a301", name = "ch270000_00", kind = "enemy", base_id = "ch270000_00", chara_id = 469873306,
                    max_hp = 650000 }
    local EYE_B = { key = "a302", name = "ch270000_00", kind = "enemy", base_id = "ch270000_00", chara_id = 469873306,
                    max_hp = 650000 }
    local f = Fight.new(0)
    f:add_hit(hit(P0, EYE_A, { frame = 100, hp0 = 650000, hp1 = 649000, final = 1000 }))
    f:add_hit({ t = 1, victim = EYE_B, skill = {}, final = 1000, hp0 = 650000, hp1 = 649000, mirror = true,
                frame = 100 })
    local key = f:note_hp(EYE_B.key, 640000, 650000)
    eq(key, EYE_A.key, "the kept body's key")
    near(f:snapshot(1).enemies[EYE_A.key].hp, 640000, 1e-9, "the pool's HP")
    eq(f:snapshot(1).enemies[EYE_B.key], nil, "the other body stays no enemy")
    local DEMON = actor("a84752", "Lesser demon", "enemy", "ch255000_00", 260000)
    local DEMON2 = actor("a43200", "Lesser demon", "enemy", "ch255000_00", 260000)
    f = Fight.new(0)
    f:add_hit(hit(PL, DEMON, { hp0 = 260000, hp1 = 22612 }))
    f:alias(DEMON2.key, DEMON.key)
    eq(f:note_hp(DEMON2.key, 22000, 260000), DEMON.key, "the enemy it continues")
    near(f:snapshot(1).enemies[DEMON.key].hp, 22000, 1e-9, "its HP")
    eq(f:snapshot(1).enemies[DEMON2.key], nil, "no enemy of its own")
end)

test("an enemy that only hit the party or an ally is one of the fight's enemies", function()
    local f = Fight.new(0)
    f:add_hit(hit(GOB, PL, { hp0 = 2000, hp1 = 1900 }))
    f:add_hit(hit(GOB2, ALLY, { hp0 = 1500, hp1 = 1400 }))
    local e = f:snapshot(1).enemies
    eq(e[GOB2.key], nil, "one that only hit an ally waits for the party")
    f:add_hit(hit(GOB2, P1, { hp0 = 2470, hp1 = 2460 }))
    e = f:snapshot(1).enemies
    eq(e[GOB.key] ~= nil, true, "the goblin that hit the player")
    eq(e[GOB.key].actor.key, GOB.key, "its actor")
    eq(e[GOB.key].max_hp, 3700, "its full HP from the actor")
    eq(e[GOB.key].hp, nil, "its HP is not known")
    eq(e[GOB.key].killed, false, "alive")
    eq(e[GOB2.key] ~= nil, true, "the one that hit an ally")
    eq(e[GOB2.key].max_hp, 0, "no full HP known")
    eq(e[PL.key], nil, "the player is no enemy")
    -- hit later: its HP is known from then on, a kill still counts once
    f:add_hit(hit(PL, GOB, { hp0 = 3000, hp1 = 2500 }))
    f:add_hit(hit(GOB, PL, { hp0 = 1900, hp1 = 1800 }))
    e = f:snapshot(2).enemies
    near(e[GOB.key].hp, 2500, 1e-9, "HP after the party's blow"); eq(e[GOB.key].max_hp, 3700, "full HP")
    f:add_hit(hit(P0, GOB, { hp0 = 2500, hp1 = 0 }))
    local snap = f:snapshot(3)
    eq(snap.enemies[GOB.key].killed, true, "killed"); eq(snap.actors[P0.key].kills, 1, "one kill")
    -- blows that are no fight with the party's side do not list the attacker
    local MOB = actor("ch230001_00_1", "Ogre", "enemy", "ch230001_00", 9000)
    f = Fight.new(0)
    f:add_hit(hit(PL, GOB, { hp0 = 400, hp1 = 300 }))
    f:add_hit(hit(MOB, GOB, { hp0 = 300, hp1 = 250 }))
    f:add_hit(hit(MOB, BARREL, { hp0 = 200, hp1 = 100 }))
    e = f:snapshot(1).enemies
    eq(e[MOB.key], nil, "an enemy hitting an enemy or an object")
    eq(e[GOB.key] ~= nil, true, "its victim is listed as before")
end)

test("item heal goes to the user, skill heal to the healer", function()
    local f = Fight.new(0)
    f:add_heal({ t = 1, target = PL, healer = nil, amount = 550, effective = 230.9,
        source = { kind = "item", name = "Healing Pill", item_id = 38 } })
    f:add_heal({ t = 2, target = P0, healer = P2, amount = 700, effective = 400, source = { kind = "skill", name = "Halo" } })
    local snap = f:snapshot(3)
    local pl, p0, p2 = snap.actors[PL.key], snap.actors[P0.key], snap.actors[P2.key]
    near(pl.heal_done, 230.9, 1e-9, "item user heal_done"); near(pl.heal_sources["item:38"], 230.9, 1e-9, "item source")
    near(pl.heal_received, 230.9, 1e-9, "item user heal_received")
    near(p2.heal_done, 400, 1e-9, "healer heal_done"); near(p2.heal_sources.skill, 400, 1e-9, "skill source")
    eq(p2.heal_received, 0, "healer received")
    near(p0.heal_received, 400, 1e-9, "target heal_received"); eq(p0.heal_done, 0, "target heal_done")
end)

test("heal sources split by item and kind", function()
    local f = Fight.new(0)
    f:add_heal({ t = 1, target = PL, healer = P1, amount = 100, effective = 100, source = { kind = "item", item_id = 38 } })
    f:add_heal({ t = 2, target = PL, healer = P1, amount = 50, effective = 40, source = { kind = "item", item_id = 67 } })
    f:add_heal({ t = 3, target = PL, healer = P1, amount = 50, effective = 25, source = { kind = "item", item_id = 38 } })
    f:add_heal({ t = 4, target = PL, healer = P1, amount = 10, effective = 5, source = { kind = "other" } })
    local s = f:snapshot(5).actors[P1.key]
    near(s.heal_sources["item:38"], 125, 1e-9, "item 38"); near(s.heal_sources["item:67"], 40, 1e-9, "item 67")
    near(s.heal_sources.other, 5, 1e-9, "other")
    near(s.heal_done, 170, 1e-9, "heal_done is the sum of the sources")
end)

test("heal with no healer and an unknown source goes to the other pseudo-actor", function()
    local f = Fight.new(0)
    f:add_heal({ t = 1, target = P0, healer = nil, amount = 80, effective = 60, source = { kind = "other" } })
    local snap = f:snapshot(2)
    local o = snap.actors.other
    eq(o.actor.key, "other", "pseudo key"); eq(o.actor.kind, "other", "pseudo kind")
    near(o.heal_done, 60, 1e-9, "other heal_done"); near(o.heal_sources.other, 60, 1e-9, "other source")
    near(snap.actors[P0.key].heal_received, 60, 1e-9, "target heal_received")
end)

test("duration and finish", function()
    local f = Fight.new(10)
    local live = f:snapshot(25)
    eq(live.t0, 10, "t0"); eq(live.t1, nil, "t1"); eq(live.outcome, nil, "outcome"); near(live.duration, 15, 1e-9, "live duration")
    f:finish(40, "win")
    local done = f:snapshot(999)
    eq(done.t1, 40, "t1"); eq(done.outcome, "win", "outcome"); near(done.duration, 30, 1e-9, "finished duration ignores now")
    local early = Fight.new(10):snapshot(5)
    near(early.duration, 0, 1e-9, "duration is never negative")
end)

test("a snapshot keeps the names and kinds of its time", function()
    local pawn = actor("a100", "Godwin", "pawn", "ch111007", 2470, 2)
    local guard = actor("a200", "Форрест", "other", "ch300656_00", 1500)
    local f = Fight.new(0)
    f:add_hit(hit(pawn, GOB))
    f:add_hit(hit(GOB, guard))
    f:add_heal({ t = 1, target = pawn, healer = nil, amount = 5, effective = 5, source = { kind = "other" } })
    f:finish(2, "win")
    local done = f:snapshot(2)
    -- later the game renames the pawn, dismisses him, and the guard joins in
    pawn.name, pawn.kind, pawn.order = "Torinald", "other", nil
    guard.kind = "ally"
    GOB.name = "Гоблин"
    local p = done.actors[pawn.key].actor
    eq(p.name, "Godwin", "name of the finished fight")
    eq(p.kind, "pawn", "kind of the finished fight")
    eq(p.order, 2, "order of the finished fight")
    eq(done.actors[guard.key].actor.kind, "other", "guard as he was")
    eq(done.enemies[GOB.key].actor.name, "Goblin", "enemy as it was")
    eq(done.actors.other.actor.key, "other", "the pseudo-actor")
    done.actors.other.actor.name = "changed"
    eq(f:snapshot(3).actors.other.actor.name, "other", "the pseudo-actor is not shared between snapshots")
    -- a live snapshot shows the current names
    local live = f:snapshot(3)
    eq(live.actors[pawn.key].actor.name, "Torinald", "live: fresh name")
    eq(live.actors[guard.key].actor.kind, "ally", "live: fresh kind")
    GOB.name = "Goblin"
end)

test("a snapshot does not change when the fight goes on", function()
    local f = Fight.new(0)
    f:add_hit(hit(PL, GOB, { skill = { attack = "a" }, hp0 = 1000, hp1 = 900, types = { Slash = 100 } }))
    f:add_heal({ t = 1, target = PL, healer = P2, amount = 10, effective = 10, source = { kind = "skill" } })
    local snap = f:snapshot(1)
    f:add_hit(hit(PL, GOB, { skill = { attack = "a" }, hp0 = 900, hp1 = 0, types = { Slash = 900 } }))
    f:add_hit(hit(PL, GOB2))
    f:add_heal({ t = 2, target = PL, healer = P2, amount = 10, effective = 10, source = { kind = "skill" } })
    local s = snap.actors[PL.key]
    near(s.dealt, 100, 1e-9, "dealt"); eq(s.hits, 1, "hits"); eq(s.kills, 0, "kills")
    near(s.skills.a.total, 100, 1e-9, "skill total"); eq(s.skills.a.hits, 1, "skill hits")
    near(snap.actors[GOB.key].taken_from[PL.key], 100, 1e-9, "taken_from")
    near(snap.actors[P2.key].heal_sources.skill, 10, 1e-9, "heal_sources")
    eq(snap.enemies[GOB.key].killed, false, "enemy killed"); near(snap.enemies[GOB.key].hp, 900, 1e-9, "enemy hp")
    eq(snap.enemies[GOB2.key], nil, "later enemy")
    near(snap.types.Slash, 100, 1e-9, "types")
end)

local function count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

test("an ally's fight with a far enemy waits until the party hits that enemy", function()
    local f = Fight.new(0)
    f:add_hit(hit(ALLY, MINO, { hp0 = 55000, hp1 = 54000, final = 1000, types = { Slash = 1000 } }))
    f:add_hit(hit(MINO, ALLY, { hp0 = 1500, hp1 = 1400, final = 100 }))
    local snap = f:snapshot(1)
    eq(count(snap.actors), 0, "no actor: " .. count(snap.actors))
    eq(count(snap.enemies), 0, "no enemy")
    eq(count(snap.types), 0, "no type")
    for k in pairs(snap) do
        eq(k == "t0" or k == "t1" or k == "outcome" or k == "duration" or k == "actors" or k == "enemies" or k == "types",
            true, "snapshot key " .. k)
    end
    eq(f:held(), 2, "two hits held")

    -- the party touches the minotaur: what the ally did to it, and it to the ally, is counted first
    f:add_hit(hit(PL, MINO, { hp0 = 54000, hp1 = 53900, final = 100 }))
    snap = f:snapshot(2)
    local ally, mino = snap.actors[ALLY.key], snap.actors[MINO.key]
    near(ally.dealt, 1000, 1e-9, "the ally's earlier damage"); eq(ally.hits, 1, "its hits")
    near(ally.taken, 100, 1e-9, "the ally's earlier damage taken"); near(ally.taken_from[MINO.key], 100, 1e-9, "from the minotaur")
    near(mino.taken, 1100, 1e-9, "the minotaur took both"); near(mino.dealt, 100, 1e-9, "and dealt its blow")
    near(snap.actors[PL.key].dealt, 100, 1e-9, "the player's blow")
    eq(snap.types.Slash, nil, "the ally's blow is not a party type")
    -- replayed first: the engaging hit leaves the last HP
    near(snap.enemies[MINO.key].hp, 53900, 1e-9, "enemy hp after the engaging hit"); eq(snap.enemies[MINO.key].max_hp, 55000, "max hp")
    eq(f:held(), 0, "nothing is held any more")
end)

test("an enemy that hits the party is engaged: ally hits on it count from then on", function()
    local f = Fight.new(0)
    f:add_hit(hit(ALLY, GOB, { hp0 = 3700, hp1 = 3600 }))
    eq(count(f:snapshot(1).actors), 0, "held")
    f:add_hit(hit(GOB, P0, { hp0 = 2500, hp1 = 2450, final = 50 }))
    local snap = f:snapshot(2)
    near(snap.actors[ALLY.key].dealt, 100, 1e-9, "the held ally hit is counted")
    near(snap.actors[P0.key].taken, 50, 1e-9, "the blow on the pawn")
    eq(snap.enemies[GOB.key] ~= nil, true, "the goblin is an enemy of the fight")
    eq(f:held(), 0, "nothing held")
    f:add_hit(hit(ALLY, GOB, { hp0 = 3600, hp1 = 3500 }))
    near(f:snapshot(3).actors[ALLY.key].dealt, 200, 1e-9, "a later ally hit counts at once")
    eq(f:held(), 0, "and is not held")
    -- another enemy that never touched the party stays out
    f:add_hit(hit(ALLY, MINO, { hp0 = 55000, hp1 = 54000 }))
    snap = f:snapshot(4)
    eq(snap.enemies[MINO.key], nil, "not an enemy of the fight"); near(snap.actors[ALLY.key].dealt, 200, 1e-9, "ally dealt")
    eq(f:held(), 1, "held")
end)

test("a party blow on a corpse that is not engaged adds no enemy and no kill", function()
    local f = Fight.new(0)
    f:add_hit(hit(PL, MINO, { hp0 = 0, hp1 = 0, final = 500 }))
    local snap = f:snapshot(1)
    eq(count(snap.enemies), 0, "no enemy"); eq(count(snap.actors), 0, "no actor")
    eq(f:held(), 1, "the blow is held")
    -- an enemy already in the fight: its corpse blows count as before
    f:add_hit(hit(PL, GOB, { hp0 = 100, hp1 = 0 }))
    f:add_hit(hit(P0, GOB, { hp0 = 0, hp1 = 0, final = 80 }))
    snap = f:snapshot(2)
    eq(snap.actors[PL.key].kills, 1, "one kill"); eq(snap.actors[P0.key].hits, 1, "the corpse blow of an engaged enemy counts")
    eq(f:held(), 1, "still only the first")
end)

test("a party DoT tick on a living enemy counts and engages it: the fire is the party's damage", function()
    local f = Fight.new(0)
    f:add_hit(hit(ALLY, GOB, { hp0 = 3700, hp1 = 3600 }))
    eq(f:is_engaged(GOB.key), false, "not engaged")
    eq(f:held(), 1, "the ally's blow waits")
    f:add_hit(hit(P0, GOB, { status = "Poison", skill = { status = "Poison" }, hp0 = 3600, hp1 = 3590, final = 10 }))
    eq(f:is_engaged(GOB.key), true, "the tick engaged it")
    local snap = f:snapshot(1)
    eq(snap.actors[P0.key].skills["status:Poison"].hits, 1, "the tick"); near(snap.actors[P0.key].dealt, 10, 1e-9, "its damage")
    near(snap.actors[ALLY.key].dealt, 100, 1e-9, "the ally's blow, replayed before it")
    eq(snap.enemies[GOB.key] ~= nil, true, "an enemy of the fight")
    eq(f:held(), 0, "nothing held")
    -- engaged: the next ally blow counts at once
    f:add_hit(hit(ALLY, GOB, { hp0 = 3590, hp1 = 3490 }))
    near(f:snapshot(2).actors[ALLY.key].dealt, 200, 1e-9, "counted at once")
    eq(f:held(), 0, "not held")
    -- the tick of another character, on another enemy that the party has not touched
    f:add_hit(hit(PL, MINO, { status = "FireSpread", skill = { status = "FireSpread" }, hp0 = 55000, hp1 = 54990, final = 10 }))
    eq(f:is_engaged(MINO.key), true, "engaged by the player's fire")
    eq(f:snapshot(3).actors[PL.key].skills["status:FireSpread"].hits, 1, "counted")
end)

test("a party tick on a corpse that is not engaged waits like a blow on it", function()
    local f = Fight.new(0)
    f:add_hit(hit(P0, GOB, { status = "Poison", skill = { status = "Poison" }, hp0 = 0, hp1 = 0, final = 10 }))
    eq(f:is_engaged(GOB.key), false, "engages nothing")
    eq(count(f:snapshot(1).actors), 0, "not counted"); eq(f:held(), 1, "held")
end)

test("is_engaged tells the enemies the party fought", function()
    local f = Fight.new(0)
    eq(f:is_engaged(GOB.key), false, "nothing yet")
    f:add_hit(hit(ALLY, GOB))
    eq(f:is_engaged(GOB.key), false, "an ally's blow engages nothing")
    f:add_hit(hit(GOB, P1))
    eq(f:is_engaged(GOB.key), true, "an enemy that hit the party")
    f:add_hit(hit(PL, GOB2))
    eq(f:is_engaged(GOB2.key), true, "an enemy the party hit")
    eq(f:is_engaged(MINO.key), false, "another one")
    eq(f:is_engaged(nil), false, "no key")
end)

test("a hit that has no enemy in it is dropped when the party is not in it", function()
    local f = Fight.new(0)
    f:add_hit({ t = 1, attacker = nil, victim = ALLY, skill = {}, final = 20, hp0 = 800, hp1 = 780 }) -- fall damage
    f:add_hit(hit(BARREL, ALLY, { hp0 = 800, hp1 = 700 }))
    f:add_hit(hit(ALLY, BARREL, { hp0 = 200, hp1 = 0 }))
    f:add_hit(hit(ALLY, ALLY2, { hp0 = 800, hp1 = 790 }))
    local snap = f:snapshot(1)
    eq(count(snap.actors), 0, "nothing counted"); eq(count(snap.enemies), 0, "no enemy")
    eq(f:held(), 0, "dropped hits are not held")
    -- with the party on a side it counts at once, enemy or not
    f:add_hit({ t = 2, attacker = nil, victim = P0, skill = {}, final = 20, hp0 = 800, hp1 = 780 })
    f:add_hit(hit(P0, BARREL, { hp0 = 200, hp1 = 0 }))
    f:add_hit(hit(ALLY2, PL, { hp0 = 900, hp1 = 890 }))
    snap = f:snapshot(3)
    near(snap.actors[P0.key].taken, 20, 1e-9, "fall damage of a pawn"); near(snap.actors[BARREL.key].taken, 200, 1e-9, "object")
    near(snap.actors[PL.key].taken, 10, 1e-9, "friendly fire on the player")
end)

test("party friendly fire counts and engages no enemy", function()
    local f = Fight.new(0)
    f:add_hit(hit(ALLY, MINO, { hp0 = 55000, hp1 = 54000 }))
    f:add_hit(hit(P0, PL, { hp0 = 1000, hp1 = 970, final = 33 }))
    local snap = f:snapshot(1)
    near(snap.actors[PL.key].taken, 30, 1e-9, "taken"); eq(snap.actors[P0.key].dealt, 0, "not dealt")
    eq(snap.actors[ALLY.key], nil, "the ally's held hit stays out")
    eq(f:held(), 1, "still held")
end)

test("a DoT tick with no known source on an enemy that is not engaged goes to Other once it is", function()
    local f = Fight.new(0)
    f:add_hit({ t = 1, attacker = nil, victim = GOB, skill = {}, final = 60, hp0 = 3700, hp1 = 3650, status = "burn" })
    eq(count(f:snapshot(1).actors), 0, "held"); eq(f:held(), 1, "held count")
    f:add_hit(hit(GOB, PL, { hp0 = 2000, hp1 = 1950, final = 50 }))
    local snap = f:snapshot(2)
    near(snap.actors.other.dealt, 50, 1e-9, "Other's damage"); eq(snap.actors.other.hits, 1, "Other's hits")
    near(snap.actors[GOB.key].taken_from.other, 50, 1e-9, "the goblin's taken_from")
    near(snap.enemies[GOB.key].hp, 3650, 1e-9, "its HP")
    eq(f:held(), 0, "nothing held")
end)

test("held hits are capped at 1000 per enemy and 5000 per fight, and held() counts the dropped ones", function()
    local f = Fight.new(0)
    for _ = 1, 1005 do f:add_hit(hit(ALLY, MINO, { hp0 = 55000, hp1 = 54990, final = 10 })) end
    eq(f:held(), 1005, "1000 pending and 5 dropped")
    f:add_hit(hit(PL, MINO, { hp0 = 54990, hp1 = 54980, final = 10 }))
    local snap = f:snapshot(1)
    eq(snap.actors[ALLY.key].hits, 1000, "only the pending ones are replayed")
    eq(f:held(), 5, "the dropped ones stay counted")

    f = Fight.new(0)
    local mobs = {}
    for i = 1, 6 do mobs[i] = actor("ch230001_00_" .. i, "Minotaur", "enemy", "ch230001_00", 55000) end
    for i = 1, 6 do
        for _ = 1, 1000 do f:add_hit(hit(ALLY, mobs[i], { hp0 = 55000, hp1 = 54990, final = 10 })) end
    end
    eq(f:held(), 6000, "5000 pending, 1000 dropped")
    f:add_hit(hit(PL, mobs[6], { hp0 = 54990, hp1 = 54980, final = 10 }))
    eq(f:snapshot(1).actors[ALLY.key], nil, "the sixth enemy had nothing pending")
    eq(f:held(), 6000, "the dropped ones are still counted")
    f:add_hit(hit(PL, mobs[1], { hp0 = 54990, hp1 = 54980, final = 10 }))
    eq(f:snapshot(2).actors[ALLY.key].hits, 1000, "the first enemy's pending hits are replayed")
    eq(f:held(), 5000, "4000 pending, 1000 dropped")
    -- freed room takes new held hits again
    f:add_hit(hit(ALLY, mobs[2], { hp0 = 55000, hp1 = 54990, final = 10 }))
    eq(f:held(), 5001, "the second enemy's list is full (1000): one more dropped")
    local other = actor("ch230001_00_77", "Minotaur", "enemy", "ch230001_00", 55000)
    f:add_hit(hit(ALLY, other, { hp0 = 55000, hp1 = 54990, final = 10 }))
    eq(f:held(), 5002, "4001 pending, 1001 dropped")
    f:add_hit(hit(PL, other, { hp0 = 54990, hp1 = 54980, final = 10 }))
    eq(f:snapshot(3).actors[ALLY.key].hits, 1001, "a new enemy's hit fits in the freed room")
    eq(f:held(), 5001, "4000 pending, 1001 dropped")
end)

test("heals count for the party, for a party healer, or for a character already in the fight", function()
    local f = Fight.new(0)
    -- nobody of the party, nobody in the fight yet
    f:add_heal({ t = 1, target = ALLY, healer = ALLY2, amount = 100, effective = 100, source = { kind = "skill" } })
    f:add_heal({ t = 1, target = ALLY, healer = nil, amount = 100, effective = 100, source = { kind = "item", item_id = 38 } })
    f:add_heal({ t = 1, target = ALLY, healer = nil, amount = 100, effective = 100, source = { kind = "other" } })
    eq(count(f:snapshot(1).actors), 0, "dropped")
    -- a party healer, a party target
    f:add_heal({ t = 2, target = ALLY, healer = P2, amount = 100, effective = 80, source = { kind = "skill" } })
    f:add_heal({ t = 2, target = PL, healer = ALLY2, amount = 50, effective = 50, source = { kind = "skill" } })
    local snap = f:snapshot(2)
    near(snap.actors[P2.key].heal_done, 80, 1e-9, "party healer"); near(snap.actors[ALLY.key].heal_received, 80, 1e-9, "its target")
    near(snap.actors[ALLY2.key].heal_done, 50, 1e-9, "ally healing the player"); near(snap.actors[PL.key].heal_received, 50, 1e-9, "player")
    -- the ally is in the fight now: its item heal and a heal by another ally count
    f:add_heal({ t = 3, target = ALLY, healer = nil, amount = 100, effective = 70, source = { kind = "item", item_id = 38 } })
    f:add_heal({ t = 3, target = ALLY, healer = ALLY2, amount = 100, effective = 60, source = { kind = "skill" } })
    snap = f:snapshot(3)
    near(snap.actors[ALLY.key].heal_done, 70, 1e-9, "the ally's own item heal"); near(snap.actors[ALLY.key].heal_received, 210, 1e-9, "received")
    near(snap.actors[ALLY2.key].heal_done, 110, 1e-9, "the other ally's heal")
    -- an ally that was in a counted hit
    local g = Fight.new(0)
    g:add_hit(hit(PL, GOB))
    g:add_hit(hit(GOB, ALLY, { hp0 = 1500, hp1 = 1400 }))
    g:add_heal({ t = 2, target = ALLY, healer = nil, amount = 100, effective = 100, source = { kind = "item", item_id = 38 } })
    near(g:snapshot(3).actors[ALLY.key].heal_done, 100, 1e-9, "in a counted hit")
    -- a held hit does not make its ally known
    local h = Fight.new(0)
    h:add_hit(hit(ALLY, MINO))
    h:add_heal({ t = 2, target = ALLY, healer = nil, amount = 100, effective = 100, source = { kind = "item", item_id = 38 } })
    eq(count(h:snapshot(3).actors), 0, "a held hit is no entry")
end)

-- Counts every table entry reachable from t, without descending into actor fixtures.
local function count_entries(t, skip, seen)
    seen = seen or {}
    if seen[t] then return 0 end
    seen[t] = true
    local n = 0
    for _, v in pairs(t) do
        n = n + 1
        if type(v) == "table" and not skip[v] then n = n + count_entries(v, skip, seen) end
    end
    return n
end

test("3000 hits stay aggregated", function()
    local attackers = { PL, P0, P1, P2 }
    local enemies, hp, skip = {}, {}, {}
    for _, a in ipairs(attackers) do skip[a] = true end
    for i = 1, 25 do
        enemies[i] = actor("ch220003_00_" .. i, "Goblin", "enemy", "ch220003_00", 100000)
        hp[i] = 100000
        skip[enemies[i]] = true
    end
    local f = Fight.new(0)
    local expect_dealt, expect_hits, expect_full, expect_type = { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, 0
    local skill_total = {}
    local function fire(i)
        local ai, ei = i % 4 + 1, i % 25 + 1
        local removed = 10 + i % 7
        local final = removed + 3
        local sk = "skill" .. i % 3
        f:add_hit({ t = i * 0.1, attacker = attackers[ai], victim = enemies[ei], skill = { id = sk },
            final = final, hp0 = hp[ei], hp1 = hp[ei] - removed, before = 100, after = 50, types = { Slash = removed } })
        hp[ei] = hp[ei] - removed
        expect_dealt[ai] = expect_dealt[ai] + removed
        expect_hits[ai] = expect_hits[ai] + 1
        expect_full[ai] = expect_full[ai] + final
        expect_type = expect_type + removed
        local key = ai .. sk
        skill_total[key] = (skill_total[key] or 0) + removed
    end
    -- every attacker, enemy and skill has been seen by hit 300; the ledger's record fills up to its cap and stays there,
    -- so the entries are counted once it is full
    local warm = Ledger.RECORD_MAX + 299
    for i = 0, warm do fire(i) end
    local after_warm = count_entries(f, skip)
    for i = warm + 1, 2999 do fire(i) end
    local after_3000 = count_entries(f, skip)

    eq(after_3000, after_warm, "entries must not grow with the number of hits")
    local direct = 0
    for _ in pairs(f) do direct = direct + 1 end
    eq(direct < 100, true, "direct entries of the fight object")

    local snap = f:snapshot(300)
    local total_dealt, total_taken, total_armor = 0, 0, 0
    for i, a in ipairs(attackers) do
        local s = snap.actors[a.key]
        eq(s.dealt, expect_dealt[i], "dealt " .. a.name); eq(s.hits, expect_hits[i], "hits " .. a.name)
        eq(s.dealt_full, expect_full[i], "dealt_full " .. a.name)
        eq(s.enemy_def_before, 100 * expect_hits[i], "enemy_def_before " .. a.name)
        eq(s.enemy_def_after, 50 * expect_hits[i], "enemy_def_after " .. a.name)
        local sum_skills = 0
        for k = 0, 2 do
            local row = s.skills["skill" .. k]
            eq(row.total, skill_total[i .. "skill" .. k], "skill total " .. a.name .. k)
            sum_skills = sum_skills + row.total
        end
        eq(sum_skills, s.dealt, "skills add up to dealt " .. a.name)
        total_dealt = total_dealt + s.dealt
    end
    local hp_left = 0
    for i, e in ipairs(enemies) do
        local en = snap.enemies[e.key]
        eq(en.hp, hp[i], "enemy hp " .. i); eq(en.killed, false, "enemy alive " .. i)
        total_taken = total_taken + snap.actors[e.key].taken
        total_armor = total_armor + snap.actors[e.key].armor_before
        hp_left = hp_left + en.hp
    end
    eq(total_taken, total_dealt, "damage taken by the enemies equals damage dealt")
    eq(total_armor, 100 * 3000, "enemy armor seen from the victims")
    eq(hp_left, 25 * 100000 - total_dealt, "enemy HP matches")
    eq(snap.types.Slash, expect_type, "types")
end)

test("killed at and by", function()
    local f = Fight.new(2)
    f:add_hit(hit(P0, GOB, { t = 5, hp0 = 100, hp1 = 60 }))
    local e = f:snapshot(6).enemies[GOB.key]
    eq(e.killed_at, nil, "alive: no time"); eq(e.killer, nil, "alive: no killer")
    f:add_hit(hit(P1, GOB, { t = 12, hp0 = 60, hp1 = 0 }))
    f:add_hit(hit(P2, GOB, { t = 13, hp0 = 0, hp1 = 0 })) -- a stale blow on the corpse
    e = f:snapshot(14).enemies[GOB.key]
    eq(e.killed_at, 10, "seconds since the start"); eq(e.killer, P1.key, "the killer's key")
    -- a DoT kill with no attacker
    f:add_hit(hit(PL, GOB2, { t = 3, hp0 = 100, hp1 = 80 }))
    f:add_hit({ t = 20, attacker = nil, victim = GOB2, skill = { status = "burn" }, final = 80, hp0 = 80, hp1 = 0, status = "burn" })
    e = f:snapshot(21).enemies[GOB2.key]
    eq(e.killed_at, 18, "a tick's kill time"); eq(e.killer, "other", "nobody to blame")
    -- a snapshot already taken keeps what it had
    local snap = f:snapshot(21)
    eq(snap.enemies[GOB.key].killer, P1.key, "still the first killer")
end)

test("an enemy keeps the time of the latest hit on it by the party or an ally", function()
    local f = Fight.new(0)
    f:add_hit(hit(PL, GOB, { t = 3 }))
    f:add_hit(hit(GOB, P0, { t = 5, hp0 = 2500, hp1 = 2400 }))   -- its blow on the party is no hit on it
    local early = f:snapshot(6)
    eq(early.enemies[GOB.key].last_hit, 3, "the player's hit")
    f:add_hit(hit(ALLY, GOB, { t = 7, hp0 = 900, hp1 = 850 }))
    eq(f:snapshot(8).enemies[GOB.key].last_hit, 7, "an ally's hit, the enemy engaged")
    -- an enemy on an enemy, a tick nobody applied, friendly fire: not the party's side
    f:add_hit(hit(MINO, GOB, { t = 9, hp0 = 850, hp1 = 800 }))
    f:add_hit({ t = 10, victim = GOB, skill = { status = "burn" }, final = 10, hp0 = 800, hp1 = 790, status = "burn" })
    f:add_hit(hit(PL, P0, { t = 11, hp0 = 2400, hp1 = 2390 }))
    local snap = f:snapshot(12)
    eq(snap.enemies[GOB.key].last_hit, 7, "still the ally's")
    eq(snap.enemies[MINO.key], nil, "the minotaur only hit an enemy: not in the fight")
    -- an enemy that only hit the party was never hit
    f:add_hit(hit(MINO, P1, { t = 13, hp0 = 2470, hp1 = 2400 }))
    eq(f:snapshot(14).enemies[MINO.key].last_hit, nil, "never hit")
    -- held hits replayed when the party engages, then the engaging hit: the latest of them
    f:add_hit(hit(ALLY2, GOB2, { t = 15, hp0 = 500, hp1 = 450 }))
    eq(f:snapshot(16).enemies[GOB2.key], nil, "held")
    f:add_hit(hit(P2, GOB2, { t = 17, hp0 = 450, hp1 = 400 }))
    eq(f:snapshot(18).enemies[GOB2.key].last_hit, 17, "the engaging hit")
    f:add_hit(hit(PL, GOB, { t = 6, hp0 = 790, hp1 = 780 }))     -- one timed before the latest
    eq(f:snapshot(19).enemies[GOB.key].last_hit, 7, "the latest stays")
    eq(early.enemies[GOB.key].last_hit, 3, "a snapshot already taken keeps its time")
end)

test("a held hit that kills is timed by its own moment", function()
    local f = Fight.new(0)
    f:add_hit(hit(ALLY, GOB, { t = 4, hp0 = 50, hp1 = 0 }))      -- held: the party has not fought it yet
    f:add_hit(hit(PL, GOB, { t = 9, hp0 = 1000, hp1 = 990 }))   -- engages: the held kill is replayed first
    local e = f:snapshot(10).enemies[GOB.key]
    eq(e.killed_at, 4, "when it happened, not when it was counted"); eq(e.killer, ALLY.key, "the ally")
end)

test("full snapshot carries the detail, a live one does not", function()
    local f = Fight.new(0)
    f:add_hit(hit(P0, GOB, { types = { Slash = 100 } }))
    eq(f:snapshot(5).detail, nil, "live")
    eq(f:snapshot(5, false).detail, nil, "full = false")
    local d = f:snapshot(5, true).detail
    eq(type(d), "table", "full")
    eq(d.foes[GOB.key].by[P0.key].hits, 1, "the foe"); eq(d.foes[GOB.key].types.Slash.dealt, 100, "its types")
    eq(#d.record, 1, "the record"); eq(d.record_dropped, 0, "nothing dropped")
    eq(type(d.kinds), "table", "kinds"); eq(type(d.heals), "table", "heals")
end)

test("held hits reach the detail when the enemy is engaged", function()
    local f = Fight.new(0)
    f:add_hit(hit(ALLY, GOB, { hp0 = 1000, hp1 = 950 }))
    eq(f:held(), 1, "held")
    eq(f:snapshot(1, true).detail.foes[GOB.key], nil, "not in the detail while held")
    eq(#f:snapshot(1, true).detail.record, 0, "nor in the record")
    f:add_hit(hit(P0, GOB, { hp0 = 950, hp1 = 900 }))
    local d = f:snapshot(2, true).detail
    eq(d.foes[GOB.key].by[ALLY.key].hits, 1, "the ally's hit is replayed"); eq(d.foes[GOB.key].by[P0.key].hits, 1, "the party's")
    eq(#d.record, 2, "both are in the record, the held one first"); eq(d.record[1].a, ALLY.key, "order")
end)

test("the ledger takes the roles of the counted hits", function()
    local f = Fight.new(0)
    f:add_hit(hit(ALLY, GOB, { hp0 = 1000, hp1 = 990 }))  -- held
    f:add_hit(hit(GOB, PL, { hp0 = 2000, hp1 = 1960 }))   -- the enemy hits the player: engages, "attack"
    f:add_hit(hit(P0, PL, { hp0 = 2000, hp1 = 1990 }))    -- friendly fire: record only
    f:add_hit(hit(GOB, GOB2, { hp0 = 300, hp1 = 250 }))   -- the party has not met GOB2: held, then replayed
    f:add_hit(hit(P1, GOB2, { hp0 = 300, hp1 = 250 }))    -- the party hits GOB2
    f:add_hit(hit(GOB, GOB2, { hp0 = 250, hp1 = 200 }))   -- enemy on enemy: record only
    local d = f:snapshot(1, true).detail
    eq(d.foes[GOB.key].by[ALLY.key].dealt, 10, "the replayed ally hit"); eq(d.foes[GOB.key].attacks[PL.key].dealt, 40, "the attack")
    eq(d.foes[GOB2.key].by[P1.key].dealt, 50, "the party's hit"); eq(next(d.foes[GOB2.key].attacks), nil, "GOB2 attacked nobody")
    eq(d.foes[GOB.key].attacks[GOB2.key], nil, "an enemy on an enemy is no attack")
    eq(d.foes[GOB2.key].by[GOB.key], nil, "nor damage dealt")
    eq(#d.record, 6, "ally, attack, friendly fire, enemy on enemy (replayed), party, enemy on enemy")
end)

test("kind key prefers the CharaID", function()
    eq(Fight.kind_key({ chara_id = 52, base_id = "ch220001_50", key = "a1" }), "c52", "CharaID")
    eq(Fight.kind_key({ base_id = "ch220001_50", key = "a1" }), "b:ch220001_50", "base id")
    eq(Fight.kind_key({ key = "a9" }), "b:a9", "key")
    eq(Fight.kind_key({ chara_id = 0, key = "a9" }), "c0", "a zero CharaID is still one")
end)

test("add_hit gives the HP it counted for the hit now, nil for a hit held or dropped", function()
    local f = Fight.new(0)
    near(f:add_hit(hit(P0, GOB, { hp0 = 1000, hp1 = 880 })), 120, 1e-9, "a party hit: the HP removed")
    eq(f:add_hit(hit(P0, GOB, { hp0 = 880, hp1 = 880, final = 0 })), 0, "a blocked blow: counted, 0")
    eq(f:add_hit(hit(ALLY, MINO, { hp0 = 55000, hp1 = 54500 })), nil, "an ally on an enemy not engaged: held")
    eq(f:add_hit(hit(P0, GOB2, { hp0 = 0, hp1 = 0 })), nil, "a party blow on a corpse not engaged: held")
    eq(f:add_hit(hit(ALLY, BARREL, { hp0 = 200, hp1 = 150 })), nil, "no enemy and no party: dropped")
    near(f:add_hit(hit(ALLY, GOB, { hp0 = 880, hp1 = 800 })), 80, 1e-9, "an ally on an engaged enemy")
    near(f:add_hit(hit(nil, GOB, { hp0 = 800, hp1 = 790, status = "FireSpread" })), 10, 1e-9, "a tick nobody applied")
    near(f:add_hit(hit(P0, GOB, { hp0 = 28.4, hp1 = 0, final = 4694.4 })), 28.4, 1e-9, "overkill: the HP there was")
    near(f:add_hit(hit(GOB, PL, { hp0 = 2400, hp1 = 2300 })), 100, 1e-9, "an enemy's blow on the party: counted too")
    -- the ally's held hit on the minotaur is counted when the party engages it, but only the engaging hit is given
    near(f:add_hit(hit(P1, MINO, { hp0 = 54500, hp1 = 53500 })), 1000, 1e-9, "the engaging hit's own HP, not the held 500")
    near(f:snapshot(1).actors[ALLY.key].dealt, 80 + 500, 1e-9, "the held hit counted with it")
end)

-- A lesser demon (CharaID 7) the game makes anew; its new object continues the old enemy.
local DEMON = actor("a84752", "Lesser demon", "enemy", "ch255000_00", 260000)
DEMON.chara_id = 7
local DEMON2 = actor("a43200", "Lesser demon", "enemy", "ch255000_00", 260000)
DEMON2.chara_id = 7

test("a reopened fight goes on; the time it stood still is in neither its duration nor its times", function()
    local f = Fight.new(10)
    f:add_hit(hit(PL, MINO, { t = 20, hp0 = 55000, hp1 = 30000 }))
    f:finish(40, "win")
    eq(f:snapshot(40).duration, 30, "30 s before")
    eq(f:snapshot(40).paused, nil, "a fight never reopened has no pause")
    f:reopen(55.5)
    local live = f:snapshot(60)
    eq(live.t1, nil, "open again"); eq(live.outcome, nil, "no outcome yet")
    near(live.duration, 60 - 10 - 15.5, 1e-9, "the 15.5 s it stood still are not in it")
    f:add_hit(hit(PL, MINO, { t = 70, hp0 = 30000, hp1 = 0 }))
    f:finish(75, "end")
    local snap = f:snapshot(75, true)
    eq(snap.t0, 10, "from its start"); eq(snap.t1, 75, "to its new end"); eq(snap.outcome, "end", "its new outcome")
    near(snap.duration, 75 - 10 - 15.5, 1e-9, "duration without the gap")
    near(snap.paused, 15.5, 1e-9, "the gap told")
    near(snap.enemies[MINO.key].killed_at, 70 - 10 - 15.5, 1e-9, "killed at, in fighting time")
    local r = snap.detail.record
    near(r[1].t, 10, 1e-9, "the record before the gap")
    near(r[2].t, 70 - 10 - 15.5, 1e-9, "and after it, in fighting time")
    -- reopened twice: both gaps add up
    f:reopen(80)
    f:finish(90, "end")
    near(f:snapshot(90).paused, 15.5 + 5, 1e-9, "two gaps")
    near(f:snapshot(90).duration, 90 - 10 - 20.5, 1e-9, "neither in the duration")
end)

test("an alias counts a new object's hits and heals as the enemy it continues", function()
    local f = Fight.new(0)
    f:add_hit(hit(PL, DEMON, { t = 1, hp0 = 260000, hp1 = 22612, final = 237388 }))
    f:finish(5, "win")
    f:reopen(20)
    eq(f:is_engaged(DEMON2.key), false, "a new key is no enemy of the fight")
    f:alias(DEMON2.key, DEMON.key)
    eq(f:is_engaged(DEMON2.key), true, "aliased: engaged as the old enemy")
    eq(f.aliases[DEMON2.key], DEMON, "the alias names the old enemy's Actor")
    f:add_hit(hit(DEMON2, PL, { t = 21, hp0 = 2400, hp1 = 2100, final = 300 }))
    near(f:add_hit(hit(ALLY, DEMON2, { t = 22, hp0 = 22612, hp1 = 22000, final = 612 })), 612, 1e-9,
        "an ally's blow is counted: the old enemy is engaged")
    f:add_heal({ t = 23, target = DEMON2, amount = 100, effective = 100, source = { kind = "other" } })
    f:add_hit(hit(P0, DEMON2, { t = 24, hp0 = 22100, hp1 = 0, final = 22100 }))
    f:finish(25, "end")
    local snap = f:snapshot(25, true)
    local n = 0
    for _ in pairs(snap.enemies) do n = n + 1 end
    eq(n, 1, "one enemy")
    local e = snap.enemies[DEMON.key]
    eq(e.killed, true, "the kill lands on the one enemy"); eq(e.killer, P0.key, "by Casca")
    near(e.hp, 0, 1e-9, "its HP")
    eq(snap.actors[DEMON2.key], nil, "the new object has no row")
    near(snap.actors[DEMON.key].taken, 237388 + 612 + 22100, 1e-9, "everything it took, on the one row")
    near(snap.actors[DEMON.key].heal_received, 100, 1e-9, "its heal too")
    near(snap.actors[PL.key].taken_from[DEMON.key], 300, 1e-9, "its blow on the player is the old enemy's")
    eq(snap.actors[P0.key].kills, 1, "Casca's kill")
    eq(snap.detail.foes[DEMON2.key], nil, "no enemy card of its own")
    near(snap.detail.foes[DEMON.key].attacks[PL.key].dealt, 300, 1e-9, "the card has its attack")
end)

T.finish()
