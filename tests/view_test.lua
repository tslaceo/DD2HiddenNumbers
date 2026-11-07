package.path = "mod/reframework/autorun/?.lua;tests/?.lua;" .. package.path

local T = require("testlib")
local test, eq, near = T.test, T.eq, T.near
local i18n = require("DD2DamageMeter/i18n")
local Names = require("DD2DamageMeter/names")
local Fight = require("DD2DamageMeter/fight")
local View = require("DD2DamageMeter/view")

local GUTS = { key = "ch000000_00", name = "Guts", kind = "player", base_id = "ch000000_00", max_hp = 2400 }
local CASCA = { key = "ch100000_00", name = "Casca", kind = "pawn", base_id = "ch100000_00", max_hp = 2500, order = 1 }
local TORI = { key = "ch111007_00", name = "Torinald", kind = "pawn", base_id = "ch111007_00", max_hp = 2470, order = 2 }
local YVES = { key = "ch111002_00", name = "Yves", kind = "pawn", base_id = "ch111002_00", max_hp = 2600, order = 3 }
local GUARD = { key = "ch300659_00", name = "Guard", kind = "ally", base_id = "ch300659_00", max_hp = 1500 }
local CHIMERA = { key = "ch254000_00_207", name = "Chimera", kind = "enemy", base_id = "ch254000_00", max_hp = 80000 }
local OTHER = { key = "other", name = "other", kind = "other" } -- the pseudo-actor of unattributed damage and healing
local ENV = { key = "env", name = "env", kind = "other" }       -- the pseudo-actor of the enemies' own damage (falls)

local function goblin(n)
    return { key = "ch220003_00_" .. n, name = "Goblin", kind = "enemy", base_id = "ch220003_00", max_hp = 3700 }
end

local function wolf(n, max_hp)
    return { key = "ch221001_00_" .. n, name = "Wolf", kind = "enemy", base_id = "ch221001_00", max_hp = max_hp }
end

local NAMES = Names.new({
    enemy = function(base_id)
        return ({
            ch254000_00 = "Химера", ch220003_00 = "Гоблин", ch221001_00 = "Волк",
            ch230001_00 = "Огр", ch240001_00 = "Гарпия", ch250001_00 = "Скелет", ch220001_50 = "Хобгоблин",
        })[base_id]
    end,
    item = function(id) if id == 38 then return "пилюли" end end,
})

-- The context a window passes in; sets the interface language first.
local function ctx(lang)
    i18n.set(lang or "en")
    return { names = NAMES, i18n = i18n }
end

local function stats(a, o)
    local s = {
        actor = a, dealt = 0, dealt_full = 0, hits = 0, kills = 0,
        enemy_def_before = 0, enemy_def_after = 0, enemy_def_saved = 0,
        taken = 0, taken_full = 0, hits_taken = 0, taken_from = {},
        armor_before = 0, armor_after = 0, armor_saved = 0, guard = 0,
        heal_done = 0, heal_received = 0, heal_sources = {}, skills = {},
    }
    for k, v in pairs(o or {}) do s[k] = v end
    return s
end

-- A Snapshot built by hand: `list` holds Stats, `o` overrides top-level fields.
local function snapshot(list, o)
    local snap = { t0 = 0, duration = 318.5, actors = {}, enemies = {}, types = {} }
    for _, s in ipairs(list) do snap.actors[s.actor.key] = s end
    for k, v in pairs(o or {}) do snap[k] = v end
    return snap
end

local function foe(a, o)
    local e = { actor = a, max_hp = a.max_hp, hp = a.max_hp, killed = false }
    for k, v in pairs(o or {}) do e[k] = v end
    return e
end

-- Enemy `n` of kind `base`.
local function mob(base, n, max_hp)
    return { key = base .. "_" .. n, name = base, kind = "enemy", base_id = base, max_hp = max_hp }
end

-- Puts `count` enemies of one kind into the Stats list and the enemies table of a hand-built
-- snapshot: the first `killed` are dead, the others keep `hp` (default: full).
local function add_mobs(list, enemies, base, count, max_hp, killed, hp)
    for n = 1, count do
        local m = mob(base, n, max_hp)
        list[#list + 1] = stats(m, { taken = 100 })
        local dead = n <= (killed or 0)
        enemies[m.key] = foe(m, { killed = dead, hp = dead and 0 or (hp or max_hp) })
    end
end

-- The chimera fight's party numbers (logged in game): HP really removed per member.
local function party_snap(extra)
    local list = {
        stats(CASCA, { dealt = 21235, hits = 100 }),
        stats(YVES, { dealt = 6236, hits = 40 }),
        stats(GUTS, { dealt = 44463, hits = 300 }),
        stats(TORI, { dealt = 31494, hits = 200 }),
    }
    for _, s in ipairs(extra or {}) do list[#list + 1] = s end
    return snapshot(list)
end

local function names_of(rows)
    local out = {}
    for _, r in ipairs(rows) do out[#out + 1] = r.name end
    return table.concat(out, ",")
end

-- Feeds hits into a Fight and tracks each victim's HP so hp0/hp1 stay consistent.
local function striker(f)
    local hp = {}
    return function(attacker, victim, attack, amount, o)
        hp[victim.key] = hp[victim.key] or victim.max_hp
        local h = {
            t = 1, attacker = attacker, victim = victim, skill = { attack = attack },
            final = amount, hp0 = hp[victim.key], hp1 = hp[victim.key] - amount,
        }
        hp[victim.key] = h.hp1
        for k, v in pairs(o or {}) do h[k] = v end
        f:add_hit(h)
    end
end

test("shares and order", function()
    local m = View.live(party_snap(), 318.5, ctx())
    eq(names_of(m.damage.rows), "Guts,Torinald,Casca,Yves", "sorted by damage")
    local want = { { "44 463", "43%" }, { "31 494", "30%" }, { "21 235", "21%" }, { "6 236", "6%" } }
    for i, w in ipairs(want) do
        eq(m.damage.rows[i].value, w[1], "value " .. i)
        eq(m.damage.rows[i].share, w[2], "share " .. i)
    end
    eq(m.damage.rows[1].fill, 1, "first row is full")
    near(m.damage.rows[2].fill, 31494 / 44463, 1e-9, "fill is value / top value")
    near(m.damage.rows[4].fill, 6236 / 44463, 1e-9, "last fill")
    eq(m.damage.rows[1].kind, "player", "kind"); eq(m.damage.rows[2].kind, "pawn", "pawn kind")
    eq(m.damage.rows[1].key, GUTS.key, "the actor key opens the details")
    eq(m.damage.title, "Damage to enemies", "title")
    eq(m.damage.total, "103 428", "party total")
end)

test("character rows carry the actor's roster order", function()
    local snap = snapshot({
        stats(CASCA, { dealt = 21235, hits = 100, heal_done = 100 }),
        stats(YVES, { dealt = 6236, hits = 40, heal_done = 700 }),
        stats(GUTS, { dealt = 44463, hits = 300, heal_done = 300 }),
        stats(TORI, { dealt = 31494, hits = 200, heal_done = 200 }),
        stats(GUARD, { dealt = 908, hits = 3 }),
    })
    local function orders(rows)
        local out = {}
        for _, r in ipairs(rows) do out[#out + 1] = r.name .. "=" .. tostring(r.order) end
        return table.concat(out, ",")
    end
    local live = View.live(snap, 318.5, ctx())
    eq(orders(live.damage.rows), "Guts=nil,Torinald=2,Casca=1,Yves=3,Guard=nil", "live damage rows: player and ally have none")
    eq(orders(live.heal.rows), "Yves=3,Guts=nil,Torinald=2,Casca=1", "live heal rows")
    local s = View.summary(snap, ctx())
    eq(orders(s.damage.rows), "Guts=nil,Torinald=2,Casca=1,Yves=3", "summary damage rows")
    eq(orders(s.allies.rows), "Guard=nil", "summary ally rows")
    eq(orders(s.heal.rows), "Yves=3,Guts=nil,Torinald=2,Casca=1", "summary heal rows")
end)

test("character rows carry the actor's vocation like its order", function()
    local function voc(a, job)
        local c = {}
        for k, v in pairs(a) do c[k] = v end
        c.job = job
        return c
    end
    local snap = snapshot({
        stats(voc(CASCA, 1), { dealt = 21235, hits = 100, heal_done = 100 }),
        stats(voc(YVES, 3), { dealt = 6236, hits = 40, heal_done = 700 }),
        stats(voc(GUTS, 5), { dealt = 44463, hits = 300, heal_done = 300 }),
        stats(TORI, { dealt = 31494, hits = 200, heal_done = 200 }), -- vocation unknown
        stats(GUARD, { dealt = 908, hits = 3 }),
        stats(OTHER, { dealt = 50, hits = 1, heal_done = 20 }),
    })
    local function jobs(rows)
        local out = {}
        for _, r in ipairs(rows) do out[#out + 1] = r.name .. "=" .. tostring(r.job) end
        return table.concat(out, ",")
    end
    local live = View.live(snap, 318.5, ctx())
    eq(jobs(live.damage.rows), "Guts=5,Torinald=nil,Casca=1,Yves=3,Guard=nil,Other=nil", "live damage rows")
    eq(jobs(live.heal.rows), "Yves=3,Guts=5,Torinald=nil,Casca=1,Other=nil", "live heal rows")
    local s = View.summary(snap, ctx())
    eq(jobs(s.damage.rows), "Guts=5,Torinald=nil,Casca=1,Yves=3", "summary damage rows")
    eq(jobs(s.allies.rows), "Guard=nil,Other=nil", "summary grey rows")
    eq(jobs(s.heal.rows), "Yves=3,Guts=5,Torinald=nil,Casca=1,Other=nil", "summary heal rows")
    -- the details name whose they are, with the kind, order and vocation the window colours them by
    local d = View.details(snap, YVES.key, ctx())
    eq(d.key, YVES.key, "details key")
    eq(d.kind, "pawn", "details kind"); eq(d.order, 3, "details order"); eq(d.job, 3, "details vocation")
    local g = View.details(snap, GUTS.key, ctx())
    eq(g.kind, "player", "player"); eq(g.order, nil, "no order"); eq(g.job, 5, "player's vocation")
    eq(View.details(snap, TORI.key, ctx()).job, nil, "unknown vocation")
end)

test("party rows carry their shade: the rank among the fight's party members of one vocation", function()
    local function voc(a, job, order)
        local c = {}
        for k, v in pairs(a) do c[k] = v end
        c.job, c.order = job, order or a.order
        return c
    end
    local function shades(rows)
        local out = {}
        for _, r in ipairs(rows) do out[#out + 1] = r.name .. "=" .. tostring(r.shade) end
        return table.concat(out, ",")
    end
    -- Guts (the player), Casca (order 1) and Yves (order 3) are mages, Torinald a fighter. Casca has only been hit so
    -- far: no row of hers, but she is a party member of the fight and keeps her place before Yves.
    local list = {
        stats(voc(GUTS, 3), { dealt = 100, hits = 1, heal_done = 50 }),
        stats(voc(CASCA, 3), { taken = 300, hits_taken = 2 }),
        stats(voc(YVES, 3), { dealt = 500, hits = 3, heal_done = 80 }),
        stats(voc(TORI, 1), { dealt = 50, hits = 1 }),
        stats(GUARD, { dealt = 908, hits = 3 }),
        stats(OTHER, { dealt = 5, hits = 1, heal_done = 5 }),
        stats(voc(CHIMERA, 3), { taken = 600 }), -- an enemy is no party member, whatever it carries
    }
    local live = View.live(snapshot(list), 318.5, ctx())
    eq(shades(live.damage.rows), "Yves=3,Guts=1,Torinald=1,Guard=nil,Other=nil", "live damage rows")
    eq(shades(live.heal.rows), "Yves=3,Guts=1,Other=nil", "live heal rows")
    local s = View.summary(snapshot(list), ctx())
    eq(shades(s.damage.rows), "Yves=3,Guts=1,Torinald=1", "summary damage rows")
    eq(shades(s.allies.rows), "Guard=nil,Other=nil", "grey rows have none")
    eq(shades(s.heal.rows), "Yves=3,Guts=1,Other=nil", "summary heal rows")
    eq(View.details(snapshot(list), YVES.key, ctx()).shade, 3, "the details carry it")
    eq(View.details(snapshot(list), CASCA.key, ctx()).shade, 2, "Casca is the second mage")
    eq(View.details(snapshot(list), GUARD.key, ctx()).shade, nil, "an ally has none")

    -- Casca starts hitting: nobody's shade changes
    list[2] = stats(voc(CASCA, 3), { dealt = 700, hits = 4, taken = 300, hits_taken = 2 })
    live = View.live(snapshot(list), 318.5, ctx())
    eq(shades(live.damage.rows), "Casca=2,Yves=3,Guts=1,Torinald=1,Guard=nil,Other=nil", "the same shades")

    -- unknown vocations count as one; a player without an order comes first, a pawn without one last
    local rook = { key = "ch111050", name = "Rook", kind = "pawn", base_id = "ch111050" } -- no order, no vocation
    local unknown = snapshot({
        stats(voc(CASCA, nil), { dealt = 10, hits = 1 }),
        stats(rook, { dealt = 50, hits = 1 }),
        stats(voc(GUTS, nil, 0), { dealt = 30, hits = 1 }),
        stats(voc(TORI, 4), { dealt = 40, hits = 1 }),
    })
    eq(shades(View.live(unknown, 10, ctx()).damage.rows), "Rook=3,Torinald=1,Guts=1,Casca=2", "by order, unknown together")
end)

test("equal values keep a stable order", function()
    local snap = snapshot({
        stats(YVES, { dealt = 500, hits = 1 }), stats(GUTS, { dealt = 500, hits = 1 }),
        stats(TORI, { dealt = 500, hits = 1 }), stats(CASCA, { dealt = 500, hits = 1 }),
    })
    for _ = 1, 3 do
        eq(names_of(View.live(snap, 10, ctx()).damage.rows), "Guts,Casca,Torinald,Yves", "player first, pawns by slot")
    end
end)

test("per second over the duration", function()
    local m = View.live(party_snap(), 318.5, ctx())
    eq(m.damage.rows[1].per_sec, "140/s", "Guts 44463 / 318.5")
    eq(m.damage.rows[2].per_sec, "99/s", "Torinald")
    eq(m.damage.rows[4].per_sec, "20/s", "Yves")
    eq(m.damage.per_sec, "325/s", "group")
    eq(m.header.time, "5:18", "timer")
    eq(View.live(party_snap(), 318.5, ctx("ru")).damage.rows[1].per_sec, "140/с", "unit follows the language")
    -- a fight shorter than a second divides by one second
    local short = snapshot({ stats(GUTS, { dealt = 100, hits = 1 }) }, { duration = 0.25 })
    eq(View.live(short, 0.25, ctx()).damage.rows[1].per_sec, "100/s", "max(1, duration)")
    eq(View.live(short, 0.25, ctx()).header.time, "0:00", "timer under a second")
end)

test("ally row outside totals", function()
    local snap = party_snap({ stats(GUARD, { dealt = 908, hits = 4 }) })
    local m = View.live(snap, 318.5, ctx())
    eq(m.damage.total, "103 428", "guard 908 stays out of the total")
    eq(m.damage.per_sec, "325/s", "and out of the rate")
    eq(#m.damage.rows, 5, "four members and the guard")
    local g = m.damage.rows[5]
    eq(g.name, "Guard", "ally row after the party"); eq(g.kind, "ally", "marked as an ally")
    eq(g.value, "908", "value"); eq(g.per_sec, "3/s", "rate")
    eq(g.share, nil, "an ally has no share")
    near(g.fill, 908 / 44463, 1e-9, "fill against the party's top")
    eq(m.damage.rows[1].share, "43%", "party shares are unchanged")
    eq(m.damage.rows[4].name, "Yves", "the party keeps its place")

    -- a strong ally is still listed after the party and never overflows the bar
    snap = party_snap({ stats(GUARD, { dealt = 90000, hits = 4 }) })
    m = View.live(snap, 318.5, ctx())
    eq(m.damage.rows[5].name, "Guard", "after the party even when bigger")
    eq(m.damage.rows[5].fill, 1, "fill is capped")
    eq(m.damage.rows[1].fill, 1, "party top is still 1")

    local s = View.summary(party_snap({ stats(GUARD, { dealt = 908, hits = 4 }) }), ctx())
    eq(#s.damage.rows, 4, "summary damage has the party only")
    eq(s.damage.total, "103 428", "summary total")
    eq(#s.allies.rows, 1, "allies row"); eq(s.allies.rows[1].name, "Guard", "ally name")
    eq(s.allies.rows[1].value, "908", "ally value"); eq(s.allies.rows[1].share, nil, "no share")
end)

test("an ally-only fight scales the ally bars against the allies' own top", function()
    local guard2 = { key = "ch300660_00", name = "Guard 2", kind = "ally", base_id = "ch300660_00" }
    local snap = snapshot({ stats(GUARD, { dealt = 908, hits = 4 }), stats(guard2, { dealt = 454, hits = 2 }), stats(GUTS) })
    local m = View.live(snap, 100, ctx())
    eq(#m.damage.rows, 2, "two allies")
    eq(m.damage.total, "0", "no party damage")
    eq(m.damage.rows[1].name, "Guard", "bigger ally first"); eq(m.damage.rows[1].fill, 1, "own top is full")
    eq(m.damage.rows[2].fill, 0.5, "half of the allies' top")
    eq(View.summary(snap, ctx()).allies.rows[2].fill, 0.5, "summary allies too")
    -- with a party top the allies are still measured against it
    snap.actors[GUTS.key].dealt, snap.actors[GUTS.key].hits = 1816, 3
    m = View.live(snap, 100, ctx())
    eq(m.damage.rows[1].name, "Guts", "party first")
    eq(m.damage.rows[2].fill, 0.5, "908 / 1816"); eq(m.damage.rows[3].fill, 0.25, "454 / 1816")
end)

test("Other damage row sits after the allies, outside totals and shares", function()
    local snap = party_snap({ stats(GUARD, { dealt = 908, hits = 4 }), stats(OTHER, { dealt = 200, hits = 3 }) })
    local m = View.live(snap, 318.5, ctx())
    eq(m.damage.total, "103 428", "Other's 200 stays out of the total")
    eq(m.damage.per_sec, "325/s", "and out of the rate")
    eq(#m.damage.rows, 6, "four members, the guard, Other")
    eq(names_of(m.damage.rows), "Guts,Torinald,Casca,Yves,Guard,Other", "grey rows last, Other after the allies")
    local o = m.damage.rows[6]
    eq(o.name, "Other", "labelled Other"); eq(o.kind, "other", "kind"); eq(o.key, "other", "key")
    eq(o.value, "200", "value"); eq(o.per_sec, "1/s", "rate"); eq(o.share, nil, "no share")
    near(o.fill, 200 / 44463, 1e-9, "fill against the party's top")
    eq(m.damage.rows[1].share, "43%", "party shares are unchanged"); eq(m.damage.rows[4].share, "6%", "last party share")
    eq(View.live(snap, 318.5, ctx("ru")).damage.rows[6].name, i18n.t("other"), "Russian name from i18n")

    -- no allies: Other follows the party; a stronger Other never overflows the bar
    snap = party_snap({ stats(OTHER, { dealt = 90000, hits = 3 }) })
    m = View.live(snap, 318.5, ctx())
    eq(names_of(m.damage.rows), "Guts,Torinald,Casca,Yves,Other", "after the party even when bigger")
    eq(m.damage.rows[5].fill, 1, "fill is capped"); eq(m.damage.rows[1].fill, 1, "party top is still 1")
    eq(m.damage.total, "103 428", "total")

    -- damage that did not remove HP is no row
    snap = party_snap({ stats(OTHER, { dealt = 0, hits = 5, dealt_full = 30 }) })
    eq(#View.live(snap, 318.5, ctx()).damage.rows, 4, "dealt 0: no row")
    eq(#View.summary(snap, ctx()).allies.rows, 0, "dealt 0: no summary row")

    -- an Other-only fight: its own top; with an ally, the bigger of the grey rows
    snap = snapshot({ stats(GUTS), stats(OTHER, { dealt = 200, hits = 1 }) })
    m = View.live(snap, 100, ctx())
    eq(#m.damage.rows, 1, "only Other"); eq(m.damage.total, "0", "no party damage")
    eq(m.damage.rows[1].fill, 1, "own top is full")
    snap = snapshot({ stats(GUARD, { dealt = 400, hits = 1 }), stats(OTHER, { dealt = 200, hits = 1 }) })
    m = View.live(snap, 100, ctx())
    eq(names_of(m.damage.rows), "Guard,Other", "ally, then Other")
    eq(m.damage.rows[1].fill, 1, "the allies' top"); eq(m.damage.rows[2].fill, 0.5, "half of it")

    -- the summary: next to the allies rows, never in the party block
    local s = View.summary(party_snap({ stats(GUARD, { dealt = 908, hits = 4 }), stats(OTHER, { dealt = 200, hits = 3 }) }), ctx())
    eq(names_of(s.damage.rows), "Guts,Torinald,Casca,Yves", "summary damage has the party only")
    eq(s.damage.total, "103 428", "summary total")
    eq(s.damage.rows[1].share, "43%", "summary shares are unchanged")
    eq(names_of(s.allies.rows), "Guard,Other", "allies rows, then Other")
    local so = s.allies.rows[2]
    eq(so.kind, "other", "kind"); eq(so.value, "200", "value"); eq(so.share, nil, "no share"); eq(so.per_sec, nil, "no rate")
    near(so.fill, 200 / 44463, 1e-9, "fill against the party's top")
    s = View.summary(party_snap({ stats(OTHER, { dealt = 200, hits = 3 }) }), ctx("ru"))
    eq(names_of(s.allies.rows), i18n.t("other"), "Other alone is in the allies rows too")
    eq(View.summary(snapshot({ stats(OTHER, { dealt = 200, hits = 1 }) }), ctx()).allies.rows[1].fill, 1, "summary: own top")
end)

-- The enemies' own damage is a grey row of its own, beside Other and under Other's switch.
test("«Falls and environment» sits after the allies and before Other, outside totals, under Other's switch", function()
    local snap = party_snap({ stats(GUARD, { dealt = 908, hits = 4 }), stats(OTHER, { dealt = 200, hits = 3 }),
        stats(ENV, { dealt = 2000, hits = 2 }) })
    local m = View.live(snap, 318.5, ctx())
    eq(names_of(m.damage.rows), "Guts,Torinald,Casca,Yves,Guard,Falls and environment,Other", "after the allies")
    eq(m.damage.total, "103 428", "outside the total"); eq(m.damage.rows[1].share, "43%", "and the shares")
    local e = m.damage.rows[6]
    eq(e.key, "env", "key"); eq(e.kind, "other", "a grey row"); eq(e.value, "2 000", "value"); eq(e.share, nil, "no share")
    eq(e.per_sec, "6/s", "rate"); near(e.fill, 2000 / 44463, 1e-9, "fill against the party's top")
    eq(View.live(snap, 318.5, ctx("ru")).damage.rows[6].name, "Падения и среда", "Russian name")
    eq(names_of(View.live(snap, 318.5, ctx(), { other = false }).damage.rows), "Guts,Torinald,Casca,Yves,Guard",
        "Other's switch hides it too")
    -- the summary: in the allies block, beside Other
    local s = View.summary(snap, ctx())
    eq(names_of(s.allies.rows), "Guard,Falls and environment,Other", "summary grey rows")
    eq(names_of(s.damage.rows), "Guts,Torinald,Casca,Yves", "never in the party block")
    eq(names_of(View.summary(snap, ctx(), { other = false }).allies.rows), "Guard", "summary switch")
    eq(names_of(View.summary(snap, ctx(), { allies = false }).allies.rows), "Falls and environment,Other", "no allies")
    -- without party damage the grey rows are measured against the biggest of them
    m = View.live(snapshot({ stats(GUTS), stats(ENV, { dealt = 500, hits = 1 }), stats(OTHER, { dealt = 250, hits = 1 }) }),
        10, ctx())
    eq(names_of(m.damage.rows), "Falls and environment,Other", "the two grey rows")
    eq(m.damage.rows[1].fill, 1, "the biggest"); eq(m.damage.rows[2].fill, 0.5, "half of it")
    eq(#m.heal.rows, 0, "no healing row of it")
end)

test("a member's own damage is «Blood Pact → member» or «Self → member», not Other's", function()
    local f = Fight.new(0)
    f:add_hit({ t = 1, attacker = nil, victim = GUTS, skill = {}, final = 30, hp0 = 1000, hp1 = 970, own = "blood_pact" })
    f:add_hit({ t = 2, attacker = nil, victim = GUTS, skill = {}, final = 10, hp0 = 970, hp1 = 960, own = "self" })
    f:add_hit({ t = 3, attacker = nil, victim = CASCA, skill = {}, final = 5, hp0 = 900, hp1 = 895, own = "blood_pact" })
    f:add_hit({ t = 4, attacker = nil, victim = GUTS, skill = {}, final = 4, hp0 = 960, hp1 = 956 })
    local m = View.live(f:snapshot(10), 10, ctx())
    local labels = {}
    for _, r in ipairs(m.taken.rows) do labels[#labels + 1] = r.label .. " " .. r.value end
    eq(table.concat(labels, ", "), "Blood Pact → Guts 30, Self → Guts 10, Blood Pact → Casca 5, Other → Guts 4",
        "by source, value-descending")
    eq(m.taken.total, "49", "all of it is damage to the party")
    eq(#m.damage.rows, 0, "none of it is damage dealt")
    local ru = View.live(f:snapshot(10), 10, ctx("ru")).taken.rows
    eq(ru[1].label, "Пакт крови → Guts", "Russian"); eq(ru[2].label, "Сам себе → Guts", "Russian, no Blood Pact")
    -- the names of the sources; anything else is none, and an unknown source (a damaged history) is Other
    local i = ctx("en").i18n
    eq(View.own_name("self:blood_pact", i), "Blood Pact", "blood_pact"); eq(View.own_name("self:self", i), "Self", "self")
    eq(View.own_name("self:lifesteal", i), "Lifesteal", "lifesteal"); eq(View.own_name("self:regen", i), "Regeneration", "regen")
    eq(View.own_name("other", i), nil, "Other"); eq(View.own_name("self:bogus", i), nil, "unknown"); eq(View.own_name(nil, i), nil, "nil")
    local rows = View.live(snapshot({ stats(GUTS, { taken_from = { ["self:bogus"] = 3, other = 2 } }) }), 10, ctx()).taken.rows
    eq(#rows, 1, "folded into Other"); eq(rows[1].label, "Other → Guts", "label"); eq(rows[1].value, "5", "sum")
end)

test("a member's own heals are his healing row, by his plain name", function()
    local f = Fight.new(0)
    f:add_heal({ t = 1, target = CASCA, healer = CASCA, amount = 300, effective = 250, source = { kind = "self", name = "lifesteal" } })
    f:add_heal({ t = 2, target = CASCA, healer = CASCA, amount = 2, effective = 1.5, source = { kind = "self", name = "regen" } })
    f:add_heal({ t = 3, target = GUTS, amount = 550, effective = 100, source = { kind = "item", item_id = 38 } })
    f:add_heal({ t = 4, target = YVES, amount = 10, effective = 10, source = { kind = "other" } })
    local m = View.live(f:snapshot(100), 100, ctx())
    eq(names_of(m.heal.rows), "Casca,Guts (пилюли),Other", "Casca heals himself; Other stays last")
    eq(m.heal.rows[1].value, "252", "lifesteal and regeneration"); eq(m.heal.rows[1].share, "72%", "a share of the party's")
    eq(m.heal.total, "352", "in the party's total")
    eq(names_of(View.summary(f:snapshot(100), ctx()).heal.rows), "Casca,Guts (пилюли),Other", "the summary too")
end)

test("an item user who also heals himself keeps the item in his name", function()
    local f = Fight.new(0)
    f:add_heal({ t = 1, target = GUTS, amount = 550, effective = 230.9, source = { kind = "item", item_id = 38 } })
    f:add_heal({ t = 2, target = GUTS, healer = GUTS, amount = 2, effective = 2, source = { kind = "self", name = "regen" } })
    f:add_heal({ t = 3, target = GUTS, healer = GUTS, amount = 40, effective = 40,
                 source = { kind = "self", name = "lifesteal" } })
    eq(names_of(View.live(f:snapshot(10), 10, ctx()).heal.rows), "Guts (пилюли)", "his own heals do not hide the item")
    eq(View.live(f:snapshot(10), 10, ctx()).heal.rows[1].value, "273", "they count in his value")
    -- a spell of his still makes it the plain name
    f:add_heal({ t = 4, target = CASCA, healer = GUTS, amount = 50, effective = 50, source = { kind = "skill" } })
    eq(names_of(View.live(f:snapshot(10), 10, ctx()).heal.rows), "Guts", "a skill heal: the plain name")
end)

test("damage rows leave out enemies, objects and silent members", function()
    local gob = goblin(1)
    local snap = party_snap({
        stats(gob, { dealt = 5000, hits = 20 }),            -- enemies deal damage too (friend vs foe)
        stats({ key = "obj", name = "Barrel", kind = "other" }, { dealt = 7, hits = 1 }),
        stats({ key = "ch9", name = "Mute", kind = "pawn", order = 4 }, {}), -- never struck
    })
    local m = View.live(snap, 318.5, ctx())
    eq(names_of(m.damage.rows), "Guts,Torinald,Casca,Yves", "party only")
    eq(m.damage.total, "103 428", "total")
end)

test("enemy grouping", function()
    local g1, g2, g3, g4 = goblin(1), goblin(2), goblin(3), goblin(4)
    local snap = snapshot({
        stats(GUTS, { taken_from = { [g1.key] = 100, [g2.key] = 200, [g3.key] = 50, [g4.key] = 25.4, [CHIMERA.key] = 300 } }),
        stats(CASCA, { taken_from = { [g1.key] = 40 } }),
        stats(g1), stats(g2), stats(g3), stats(g4), stats(CHIMERA),
    })
    local rows = View.live(snap, 318.5, ctx()).taken.rows
    eq(#rows, 3, "four goblins on Guts make one row")
    eq(rows[1].label, "Гоблин ×4 → Guts", "merged by base_id")
    eq(rows[1].value, "375", "sum of the four (375.4)")
    eq(rows[2].label, "Химера → Guts", "a single enemy has no count")
    eq(rows[2].value, "300", "value")
    eq(rows[3].label, "Гоблин → Casca", "one goblin on another member: own row, no count")
    eq(rows[1].fill, 1, "top fill")
    near(rows[2].fill, 300 / 375.4, 1e-9, "fill against the top row")
    near(rows[3].fill, 40 / 375.4, 1e-9, "small fill")
    eq(View.live(snap, 318.5, ctx()).taken.title, "Damage to party", "title")
    -- the block's total: all the rows together (375.4 + 300 + 40)
    eq(View.live(snap, 318.5, ctx()).taken.total, "715", "the block total")
    local quiet = View.live(snapshot({ stats(GUTS), stats(CHIMERA) }), 10, ctx())
    eq(quiet.taken.total, "0", "nothing taken: 0, like the other blocks")
    -- Other and friendly fire count too
    local f = Fight.new(0)
    f:add_hit({ t = 1, attacker = nil, victim = GUTS, skill = {}, final = 50, hp0 = 1000, hp1 = 960 })
    f:add_hit({ t = 2, attacker = CASCA, victim = GUTS, skill = { attack = "N_軽" }, final = 30, hp0 = 960, hp1 = 940 })
    eq(View.live(f:snapshot(10), 10, ctx()).taken.total, "60", "40 from nobody, 20 from Casca")
end)

test("taken rows sort by value and the biggest merged row leads", function()
    local g1, g2 = goblin(1), goblin(2)
    local snap = snapshot({
        stats(GUTS, { taken_from = { [g1.key] = 60, [g2.key] = 70, [CHIMERA.key] = 100 } }),
        stats(g1), stats(g2), stats(CHIMERA),
    })
    local rows = View.live(snap, 10, ctx()).taken.rows
    eq(rows[1].label, "Гоблин ×2 → Guts", "130 beats 100")
    eq(rows[1].fill, 1, "top fill")
    near(rows[2].fill, 100 / 130, 1e-9, "second fill")
end)

test("taken rows with unknown attacker", function()
    local f = Fight.new(0)
    -- fall damage / a DoT nobody could be found for
    f:add_hit({ t = 1, attacker = nil, victim = GUTS, skill = {}, final = 50, hp0 = 1000, hp1 = 960 })
    -- friendly fire: a pawn hits the player; an ally hits a pawn
    f:add_hit({ t = 2, attacker = CASCA, victim = GUTS, skill = { attack = "N_軽" }, final = 30, hp0 = 960, hp1 = 940 })
    f:add_hit({ t = 3, attacker = GUARD, victim = CASCA, skill = { attack = "N_軽" }, final = 15, hp0 = 500, hp1 = 485 })
    local m = View.live(f:snapshot(10), 10, ctx())
    local labels = {}
    for _, r in ipairs(m.taken.rows) do labels[r.label] = r.value end
    eq(labels["Other → Guts"], "40", "no attacker lands under Other (HP really removed)")
    eq(labels["Casca → Guts"], "20", "friendly fire keeps the pawn's name")
    eq(labels["Guard → Casca"], "15", "an ally is a plain attacker")
    eq(#m.taken.rows, 3, "nothing else")
    eq(m.taken.rows[1].label, "Other → Guts", "largest first")

    local ru = View.live(f:snapshot(10), 10, ctx("ru"))
    eq(ru.taken.rows[1].label, "Прочее → Guts", "Russian label")

    -- a taken_from key without an actor, the heal pseudo-actor and zero entries
    local snap = snapshot({
        stats(GUTS, { taken_from = { ["gone"] = 10, other = 5, [CASCA.key] = 0 } }),
        stats({ key = "other", name = "other", kind = "other" }),
        stats(CASCA),
    })
    local rows = View.live(snap, 10, ctx()).taken.rows
    eq(#rows, 1, "unknown keys fold into one Other row, empty entries are dropped")
    eq(rows[1].label, "Other → Guts", "label"); eq(rows[1].value, "15", "sum")
end)

test("taken counts only members of the party as victims", function()
    local g = goblin(1)
    local snap = snapshot({
        stats(GUARD, { taken_from = { [g.key] = 99 } }),
        stats(g, { taken_from = { [GUTS.key] = 77 } }),
        stats(GUTS),
    })
    eq(#View.live(snap, 10, ctx()).taken.rows, 0, "damage to an ally or an enemy is not damage to the party")
end)

test("header picks the largest max HP", function()
    local g = goblin(1)
    local snap = snapshot({
        stats(g, { taken = 90000 }), stats(CHIMERA, { taken = 48800 }), -- the goblin took more, the boss is bigger
    }, {
        enemies = { [g.key] = foe(g, { hp = 0, killed = true }), [CHIMERA.key] = foe(CHIMERA, { hp = 31200 }) },
    })
    local h = View.live(snap, 318.5, ctx()).header
    eq(h.title, "Химера", "the boss, by name"); eq(h.hp_text, "31 200 / 80 000", "current / full"); eq(h.time, "5:18", "time")

    -- a killed main enemy shows 0 HP, as the summary does
    snap.enemies[CHIMERA.key] = foe(CHIMERA, { hp = 12.4, killed = true })
    eq(View.live(snap, 318.5, ctx()).header.hp_text, "0 / 80 000", "killed")
    snap.enemies[CHIMERA.key] = foe(CHIMERA, { hp = 31200 })

    -- equal max HP: the one that took more damage
    local a, b = goblin(1), goblin(2)
    snap = snapshot({ stats(a, { taken = 100 }), stats(b, { taken = 900 }) }, {
        enemies = { [a.key] = foe(a, { hp = 3600 }), [b.key] = foe(b, { hp = 2800 }) },
    })
    for _ = 1, 3 do
        eq(View.live(snap, 10, ctx()).header.hp_text, "2 800 / 3 700", "tie goes to the most damaged")
    end

    -- the enemy's name comes from the lookup, not from the actor
    local unknown = wolf(1, 900)
    snap = snapshot({ stats(unknown) }, { enemies = { [unknown.key] = foe(unknown) } })
    eq(View.live(snap, 10, ctx()).header.title, "Волк", "lookup by base_id")
    local bare = { names = Names.new(), i18n = i18n }
    eq(View.live(snap, 10, bare).header.title, "ch221001_00", "without a game lookup the base id shows")

    -- no enemies yet: no HP line
    local empty = View.live(snapshot({ stats(GUTS) }), 5, ctx()).header
    eq(empty.title, "", "no title"); eq(empty.hp_text, nil, "no HP text")
end)

test("header: on equal full HP the enemy the party hit last comes first, in the live window and the summary", function()
    local ogre, harpy = mob("ch230001_00", 1, 192000), mob("ch240001_00", 1, 192000)
    local f = Fight.new(0)
    local strike = striker(f)
    local function main(t)
        local snap = f:snapshot(t)
        return View.live(snap, t, ctx()).header.title, View.summary(snap, ctx()).enemies[1].label
    end
    strike(GUTS, ogre, "N_軽", 5000, { t = 1 })
    strike(CASCA, harpy, "N_軽", 100, { t = 2 })
    local live, summary = main(3)
    eq(live, "Гарпия", "hit last, though it took less"); eq(summary, "Гарпия", "the summary's main enemy too")
    strike(TORI, ogre, "N_軽", 10, { t = 4 })
    live, summary = main(5)
    eq(live, "Огр", "hit again"); eq(summary, "Огр", "summary")
    strike(GUARD, harpy, "N_軽", 10, { t = 6 })
    eq((main(7)), "Гарпия", "an ally's hit counts as the party's")
    -- unequal full HP: the bigger one, whatever the order of the hits
    for _, order in ipairs({ { CHIMERA, goblin(1) }, { goblin(1), CHIMERA } }) do
        f = Fight.new(0)
        strike = striker(f)
        strike(GUTS, order[1], "N_軽", 100, { t = 1 })
        strike(GUTS, order[2], "N_軽", 100, { t = 2 })
        live, summary = main(3)
        eq(live, "Химера", "the biggest, " .. order[2].key .. " hit last"); eq(summary, "Химера", "summary")
    end
end)

test("header: an enemy entry without the time of a hit counts as never hit", function()
    local a, b = goblin(1), goblin(2)
    local snap = snapshot({ stats(a, { taken = 900 }), stats(b, { taken = 100 }) }, {
        enemies = { [a.key] = foe(a, { hp = 2800 }), [b.key] = foe(b, { hp = 3600, last_hit = 5 }) },
    })
    eq(View.live(snap, 10, ctx()).header.hp_text, "3 600 / 3 700", "the one hit, though it took less")
    snap.enemies[b.key].last_hit = "5"
    eq(View.live(snap, 10, ctx()).header.hp_text, "2 800 / 3 700", "a time that is no number: never hit")
    snap.enemies[b.key].last_hit = 0 / 0
    eq(View.live(snap, 10, ctx()).header.hp_text, "2 800 / 3 700", "nor is NaN")
end)

test("an enemy that only hit the party is in the header and the summary", function()
    local f = Fight.new(0)
    f:add_hit({ t = 1, attacker = CHIMERA, victim = GUTS, skill = { attack = "bite" },
        final = 500, hp0 = 2400, hp1 = 1900 })
    local h = View.live(f:snapshot(10), 10, ctx()).header
    eq(h.title, "Химера", "the chimera heads the window")
    eq(h.hp_text, "80 000 / 80 000", "its HP is not known: shown as full")
    local s = View.summary(f:snapshot(10), ctx())
    eq(#s.enemies, 1, "one enemy")
    eq(s.enemies[1].label, "Химера", "named"); eq(s.enemies[1].hp_text, "80 000 / 80 000 HP", "full HP")
    -- next to goblins the party did hit, it is still the main enemy, and the goblins keep their HP
    local strike = striker(f)
    strike(GUTS, goblin(1), "N_軽", 3700)
    strike(CASCA, goblin(2), "N_軽", 700)
    s = View.summary(f:snapshot(10), ctx())
    eq(#s.enemies, 2, "the chimera and the goblins")
    eq(s.enemies[1].label, "Химера", "main"); eq(s.enemies[2].label, "Гоблин ×2", "the goblins")
    eq(s.enemies[2].hp_text, "3 700 HP each · killed: 1 of 2", "their HP and kill")
end)

test("an empty fight gives empty blocks", function()
    local f = Fight.new(100)
    local m = View.live(f:snapshot(112), 112, ctx())
    eq(m.header.time, "0:12", "timer"); eq(#m.damage.rows, 0, "damage rows")
    eq(m.damage.total, "0", "total"); eq(m.damage.per_sec, "0/s", "rate")
    eq(#m.taken.rows, 0, "taken rows"); eq(#m.heal.rows, 0, "heal rows"); eq(m.heal.total, "0", "heal total")
    local s = View.summary(f:snapshot(112), ctx())
    eq(#s.enemies, 0, "no enemies"); eq(#s.armor, 0, "no armor")
end)

test("heal rows", function()
    local f = Fight.new(0)
    f:add_heal({ t = 1, target = GUTS, healer = TORI, amount = 900, effective = 800, source = { kind = "skill" } })
    f:add_heal({ t = 2, target = GUTS, healer = TORI, amount = 100, effective = 100, source = { kind = "skill" } })
    -- potion: no healer, the target is credited
    f:add_heal({ t = 3, target = GUTS, amount = 550, effective = 230.9, source = { kind = "item", item_id = 38 } })
    -- a pawn who used a potion and also heals with a spell keeps the plain name
    f:add_heal({ t = 4, target = CASCA, amount = 1000, effective = 1000, source = { kind = "item", item_id = 67 } })
    f:add_heal({ t = 5, target = YVES, healer = CASCA, amount = 90, effective = 90, source = { kind = "skill" } })
    -- nobody to credit, and a heal at full HP
    f:add_heal({ t = 6, target = GUTS, amount = 50, effective = 50, source = { kind = "other" } })
    f:add_heal({ t = 7, target = YVES, healer = YVES, amount = 40, effective = 0, source = { kind = "skill" } })

    local m = View.live(f:snapshot(318.5), 318.5, ctx("ru"))
    eq(m.heal.title, i18n.t("healing"), "title")
    eq(#m.heal.rows, 4, "three healers: Torinald, Casca, Guts, then the Other row")
    eq(m.heal.rows[4].name, i18n.t("other"), "healing nobody can be blamed for: Other, last")
    eq(m.heal.rows[4].kind, "other", "marked as Other"); eq(m.heal.rows[4].value, "50", "its value")
    eq(m.heal.rows[1].name, "Casca", "mixed sources: plain name")
    eq(m.heal.rows[1].value, "1 090", "value")
    eq(m.heal.rows[2].name, "Torinald", "spell healer")
    eq(m.heal.rows[2].value, "900", "value")
    eq(m.heal.rows[3].name, "Guts (пилюли)", "item-only healer carries the item name")
    eq(m.heal.rows[3].value, "231", "value")
    eq(m.heal.rows[1].fill, 1, "top fill"); near(m.heal.rows[2].fill, 900 / 1090, 1e-9, "fill")
    eq(m.heal.rows[2].per_sec, "3/с", "per second")
    eq(m.heal.total, "2 221", "party healing only: the Other row's 50 is outside the total")
    eq(m.heal.per_sec, "7/с", "group rate")
end)

test("Other heal row sits after the party, outside totals and shares", function()
    local f = Fight.new(0)
    f:add_heal({ t = 1, target = GUTS, healer = TORI, amount = 750, effective = 750, source = { kind = "skill" } })
    f:add_heal({ t = 2, target = GUTS, amount = 250, effective = 250, source = { kind = "item", item_id = 38 } })
    f:add_heal({ t = 3, target = CASCA, amount = 100, effective = 90, source = { kind = "other" } })
    f:add_heal({ t = 4, target = GUTS, amount = 40, effective = 0, source = { kind = "other" } }) -- nothing restored
    f:add_heal({ t = 5, target = YVES, amount = 20, effective = 10, source = { kind = "other" } })
    local snap = f:snapshot(100)

    local m = View.live(snap, 100, ctx("en"))
    eq(names_of(m.heal.rows), "Torinald,Guts (пилюли),Other", "Other after the party")
    eq(m.heal.total, "1 000", "Other's 100 stays out of the total"); eq(m.heal.per_sec, "10/s", "and out of the rate")
    local o = m.heal.rows[3]
    eq(o.name, "Other", "labelled Other"); eq(o.kind, "other", "kind"); eq(o.key, "other", "key")
    eq(o.value, "100", "value"); eq(o.per_sec, "1/s", "rate"); eq(o.share, nil, "no share")
    near(o.fill, 100 / 750, 1e-9, "fill against the party's top")
    eq(m.heal.rows[1].share, "75%", "party shares are unchanged")

    local s = View.summary(snap, ctx("ru"))
    eq(names_of(s.heal.rows), "Torinald,Guts (пилюли)," .. i18n.t("other"), "summary: the same row")
    eq(s.heal.total, "1 000", "summary total"); eq(s.heal.rows[3].value, "100", "value"); eq(s.heal.rows[3].share, nil, "no share")
    eq(s.heal.rows[3].kind, "other", "kind"); eq(s.heal.rows[3].per_sec, nil, "no rate")
    near(s.heal.rows[3].fill, 100 / 750, 1e-9, "summary fill")
    eq(s.heal.rows[1].share, "75%", "summary shares are unchanged")

    -- only Other healed: its own top, no total
    f = Fight.new(0)
    f:add_heal({ t = 1, target = GUTS, amount = 50, effective = 50, source = { kind = "other" } })
    m = View.live(f:snapshot(10), 10, ctx("en"))
    eq(#m.heal.rows, 1, "Other alone"); eq(m.heal.rows[1].fill, 1, "own top is full"); eq(m.heal.total, "0", "no party healing")
    eq(#View.summary(f:snapshot(10), ctx("en")).heal.rows, 1, "summary too")
    -- damage dealt by Other does not make a heal row, nor the other way round
    eq(#View.live(snapshot({ stats(OTHER, { dealt = 30, hits = 1 }) }), 10, ctx()).heal.rows, 0, "no heal row for damage")
    eq(#View.live(snapshot({ stats(OTHER, { heal_done = 30 }) }), 10, ctx()).damage.rows, 0, "no damage row for healing")
end)

test("heal item labels", function()
    local snap = snapshot({
        stats(GUTS, { heal_done = 300, heal_sources = { ["item:38"] = 200, ["item:67"] = 100, ["item:5"] = 0 } }),
        stats(CASCA, { heal_done = 90, heal_sources = { ["item:?"] = 90 } }),
        stats(YVES, { heal_done = 10, heal_sources = { ["item:38"] = 5, skill = 5 } }),
    })
    local rows = View.live(snap, 100, ctx("en")).heal.rows
    eq(rows[1].name, "Guts (пилюли, Item #67)", "two items, biggest first, unknown name from the fallback")
    eq(rows[2].name, "Casca (Item)", "an item without an id")
    eq(rows[3].name, "Yves", "item and skill: plain")
end)

test("summary: title, time, shares and no per-second values", function()
    local snap = party_snap({ stats(GUARD, { dealt = 908, hits = 4 }) })
    snap.outcome = "win"; snap.t1 = 318.5
    local s = View.summary(snap, ctx())
    eq(s.title, "Victory", "win"); eq(s.time, "5:18", "time")
    eq(s.damage.title, "Dealt", "damage title")
    eq(names_of(s.damage.rows), "Guts,Torinald,Casca,Yves", "order")
    eq(s.damage.rows[1].share, "43%", "share"); eq(s.damage.rows[1].value, "44 463", "value")
    eq(s.damage.rows[1].fill, 1, "fill"); eq(s.damage.rows[1].key, GUTS.key, "key")
    eq(s.damage.rows[1].per_sec, nil, "the summary shows no rate")
    eq(s.allies.title, "Allies", "allies title")
    snap.outcome = "end"
    eq(View.summary(snap, ctx()).title, "Fight over", "end")
    snap.outcome = "abandoned"
    eq(View.summary(snap, ctx("ru")).title, i18n.t("fight_over"), "abandoned, Russian")
    snap.outcome = nil
    eq(View.summary(snap, ctx()).title, "Fight over", "unfinished")
end)

test("summary heal rows carry shares", function()
    local f = Fight.new(0)
    f:add_heal({ t = 1, target = GUTS, healer = TORI, amount = 750, effective = 750, source = { kind = "skill" } })
    f:add_heal({ t = 2, target = GUTS, amount = 250, effective = 250, source = { kind = "item", item_id = 38 } })
    local s = View.summary(f:snapshot(20), ctx("ru"))
    eq(s.heal.title, i18n.t("healed"), "title")
    eq(s.heal.rows[1].name, "Torinald", "order"); eq(s.heal.rows[1].share, "75%", "share")
    eq(s.heal.rows[2].name, "Guts (пилюли)", "his item heal"); eq(s.heal.rows[2].share, "25%", "share")
    eq(s.heal.rows[1].per_sec, nil, "no rate"); eq(s.heal.total, "1 000", "total")
end)

-- The chimera (alive, 31 200 of 80 000), 3 goblins and 9 more enemies of 4 kinds: 3 wolves,
-- 2 ogres, 2 harpies, 2 skeletons.
local function crowd()
    local list, enemies = { stats(CHIMERA, { taken = 48800 }) }, { [CHIMERA.key] = foe(CHIMERA, { hp = 31200 }) }
    add_mobs(list, enemies, "ch220003_00", 3, 3700, 2)
    add_mobs(list, enemies, "ch221001_00", 3, 3000, 3)
    add_mobs(list, enemies, "ch230001_00", 2, 9000, 0)
    add_mobs(list, enemies, "ch240001_00", 2, 1200, 1)
    add_mobs(list, enemies, "ch250001_00", 2, 800, 0)
    return list, enemies
end

test("summary merges same enemies and counts the rest", function()
    local list, enemies = crowd()
    local s = View.summary(snapshot(list, { enemies = enemies }), ctx())
    eq(#s.enemies, 5, "the main enemy, three kinds, one row for the rest")
    eq(s.enemies[1].label, "Химера", "the main enemy by name")
    eq(s.enemies[1].hp_text, "31 200 / 80 000 HP", "alive: current / full")
    eq(s.enemies[2].label, "Гоблин ×3", "the most numerous kind (ties: the bigger HP) comes first")
    eq(s.enemies[2].hp_text, "3 700 HP each · killed: 2 of 3", "HP each and killed")
    eq(s.enemies[3].label, "Волк ×3", "second kind of three")
    eq(s.enemies[3].hp_text, "3 000 HP each · killed: 3 of 3", "all killed")
    eq(s.enemies[4].label, "Огр ×2", "then two of a kind, the bigger HP first")
    eq(s.enemies[4].hp_text, "9 000 HP each", "no kills, no count")
    eq(s.enemies[5].label, "More enemies: 4 (HP 800 to 1 200)", "the remaining kinds: count, lowest to highest full HP")
    eq(s.enemies[5].hp_text, "killed: 1 of 4", "killed marked")
    s = View.summary(snapshot(list, { enemies = enemies }), ctx("ru"))
    eq(s.enemies[2].label, "Гоблин ×3", "Russian")
    eq(s.enemies[2].hp_text, "по 3 700 HP · убито: 2 из 3", "Russian group text")
    eq(s.enemies[5].label, "Ещё врагов: 4 (HP от 800 до 1 200)", "Russian rest label")
    eq(s.enemies[5].hp_text, "убито: 1 из 4", "Russian killed")
end)

test("summary enemy rows say whether they were killed: a group or the rest only when all of them were", function()
    local list, enemies = crowd()
    local s = View.summary(snapshot(list, { enemies = enemies }), ctx())
    local function killed()
        local out = {}
        for _, e in ipairs(s.enemies) do out[#out + 1] = tostring(e.killed) end
        return table.concat(out, ",")
    end
    -- the chimera alive, goblins 2 of 3, wolves 3 of 3, ogres none, the rest 1 of 4
    eq(killed(), "false,false,true,false,false", "alive, partly, all, none, partly")
    -- a killed main enemy; a lone leftover named and killed; the rest all killed
    enemies[CHIMERA.key] = foe(CHIMERA, { hp = 0, killed = true })
    for key, e in pairs(enemies) do
        if key:find("^ch2[45]") then enemies[key] = foe(e.actor, { hp = 0, killed = true }) end
    end
    s = View.summary(snapshot(list, { enemies = enemies }), ctx())
    eq(killed(), "true,false,true,false,true", "the main enemy and the rest killed")
    local lone = { stats(CHIMERA) }
    local lone_enemies = { [CHIMERA.key] = foe(CHIMERA) }
    add_mobs(lone, lone_enemies, "ch220003_00", 3, 3700, 3)
    add_mobs(lone, lone_enemies, "ch221001_00", 2, 3000, 0)
    add_mobs(lone, lone_enemies, "ch230001_00", 2, 9000, 0)
    add_mobs(lone, lone_enemies, "ch240001_00", 1, 1200, 1)
    s = View.summary(snapshot(lone, { enemies = lone_enemies }), ctx())
    eq(killed(), "false,true,false,false,true", "the lone leftover harpy, killed")
end)

test("summary: at most three group rows, the other kinds go to the rest row", function()
    local list, enemies = { stats(CHIMERA) }, { [CHIMERA.key] = foe(CHIMERA) }
    add_mobs(list, enemies, "ch220003_00", 1, 3700, 0)
    add_mobs(list, enemies, "ch221001_00", 2, 3000, 0)
    add_mobs(list, enemies, "ch230001_00", 2, 9000, 0)
    add_mobs(list, enemies, "ch240001_00", 1, 1200, 0)
    add_mobs(list, enemies, "ch250001_00", 1, 800, 0)
    local s = View.summary(snapshot(list, { enemies = enemies }), ctx())
    eq(#s.enemies, 5, "main, three groups, rest")
    eq(s.enemies[2].label, "Огр ×2", "count 2, bigger HP"); eq(s.enemies[3].label, "Волк ×2", "count 2, smaller HP")
    eq(s.enemies[4].label, "Гоблин", "count 1, biggest HP: one enemy has no count")
    eq(s.enemies[4].hp_text, "3 700 / 3 700 HP", "one enemy: HP left / full HP")
    eq(s.enemies[5].label, "More enemies: 2 (HP 800 to 1 200)", "the two kinds that did not make it")
    eq(s.enemies[5].hp_text, "killed: 0 of 2", "none killed")
end)

test("summary: a lone leftover enemy is named", function()
    local list, enemies = { stats(CHIMERA) }, { [CHIMERA.key] = foe(CHIMERA) }
    add_mobs(list, enemies, "ch220003_00", 3, 3700, 3)
    add_mobs(list, enemies, "ch221001_00", 2, 3000, 0)
    add_mobs(list, enemies, "ch230001_00", 2, 9000, 0)
    add_mobs(list, enemies, "ch240001_00", 1, 1200, 1)
    local s = View.summary(snapshot(list, { enemies = enemies }), ctx("ru"))
    eq(#s.enemies, 5, "main and four kinds, no rest row")
    eq(s.enemies[5].label, "Гарпия", "the leftover harpy is shown by name, not as 'more: 1'")
    eq(s.enemies[5].hp_text, "0 / 1 200 HP", "and it was killed")
    eq(s.enemies[2].hp_text, "по 3 700 HP · убито: 3 из 3", "all goblins killed")
end)

test("summary: equal HP in the rest row shows one number", function()
    local list, enemies = { stats(CHIMERA) }, { [CHIMERA.key] = foe(CHIMERA) }
    add_mobs(list, enemies, "ch220003_00", 3, 3700, 0)
    add_mobs(list, enemies, "ch221001_00", 2, 3000, 0)
    add_mobs(list, enemies, "ch230001_00", 2, 9000, 0)
    add_mobs(list, enemies, "ch250001_00", 1, 900, 0)
    add_mobs(list, enemies, "ch260001_00", 1, 900, 1)
    local s = View.summary(snapshot(list, { enemies = enemies }), ctx("ru"))
    eq(#s.enemies, 5, "main, three groups, rest")
    eq(s.enemies[5].label, "Ещё врагов: 2 (HP 900)", "one number instead of 'from 900 to 900'")
    eq(s.enemies[5].hp_text, "убито: 1 из 2", "killed")
    s = View.summary(snapshot(list, { enemies = enemies }), ctx("en"))
    eq(s.enemies[5].label, "More enemies: 2 (HP 900)", "English")
end)

test("summary: the main kind merges too, a range when its full HP differs", function()
    local list, enemies = {}, {}
    add_mobs(list, enemies, "ch220003_00", 3, 3700, 2, 500)
    add_mobs(list, enemies, "ch221001_00", 1, 900, 0)
    local s = View.summary(snapshot(list, { enemies = enemies }), ctx("ru"))
    eq(s.enemies[1].label, "Гоблин ×3", "merged label")
    eq(s.enemies[1].hp_text, "по 3 700 HP · убито: 2 из 3", "HP each and killed count")
    eq(s.enemies[2].label, "Волк", "a second kind with one enemy is a plain named row")
    eq(s.enemies[2].hp_text, "900 / 900 HP", "HP")
    s = View.summary(snapshot(list, { enemies = enemies }), ctx("en"))
    eq(s.enemies[1].hp_text, "3 700 HP each · killed: 2 of 3", "English text")

    enemies["ch220003_00_2"].max_hp = 3000
    s = View.summary(snapshot(list, { enemies = enemies }), ctx("en"))
    eq(s.enemies[1].hp_text, "3 000–3 700 HP each · killed: 2 of 3", "range")

    -- nothing killed: no count
    list, enemies = {}, {}
    add_mobs(list, enemies, "ch220003_00", 2, 3700, 0)
    eq(View.summary(snapshot(list, { enemies = enemies }), ctx("en")).enemies[1].hp_text, "3 700 HP each", "no kills")
end)

test("summary: a single enemy shows its end HP, a killed one 0 / max", function()
    local gob = goblin(1)
    local snap = snapshot({ stats(CHIMERA, { taken = 80000 }) }, {
        enemies = { [CHIMERA.key] = foe(CHIMERA, { hp = 0, killed = true }) },
    })
    local s = View.summary(snap, ctx("ru"))
    eq(#s.enemies, 1, "no row for the rest when there is none")
    eq(s.enemies[1].label, "Химера", "label without a count")
    eq(s.enemies[1].hp_text, "0 / 80 000 HP", "killed")
    snap.enemies[CHIMERA.key] = foe(CHIMERA, { hp = 12.4, killed = true }) -- healed back after the kill
    eq(View.summary(snap, ctx("ru")).enemies[1].hp_text, "0 / 80 000 HP", "killed stays 0")
    snap.enemies[CHIMERA.key] = foe(CHIMERA, { hp = 1200 })
    eq(View.summary(snap, ctx("en")).enemies[1].hp_text, "1 200 / 80 000 HP", "still alive")
    snap.enemies = { [gob.key] = foe(gob) }
    eq(View.summary(snap, ctx("en")).enemies[1].label, "Гоблин", "no count for one")
end)

test("armor text", function()
    local f = Fight.new(0)
    -- the documented goblin hit on the player: 900 -> 106, 88%, about 1032 HP saved
    f:add_hit({ t = 1, attacker = goblin(1), victim = GUTS, skill = { attack = "atk_goblin" },
        final = 137.8936, hp0 = 2245.86, hp1 = 2107.967, before = 900, after = 106.072 })
    local s = View.summary(f:snapshot(10), ctx())
    eq(#s.armor, 1, "the goblin's own blow is not the party's defence step: one row")
    eq(s.armor[1].label, "Absorbed by party armor", "label")
    eq(s.armor[1].value, "≈ 1 032 · 88%", "saved and share")

    -- the party's sword hit on a goblin: enemy defence
    f:add_hit({ t = 2, attacker = CASCA, victim = goblin(2), skill = { attack = "弱攻撃_ヒットスロー小" },
        final = 405.1336, hp0 = 3053.035, hp1 = 2647.901, before = 479.45, after = 339.45, types = { Slash = 339.45 } })
    s = View.summary(f:snapshot(10), ctx("ru"))
    eq(#s.armor, 2, "both rows")
    eq(s.armor[1].label, i18n.t("enemy_defence_saved"), "enemy defence first")
    eq(s.armor[1].value, "≈ 167 · 29%", "enemy defence: (before - after) / before")
    eq(s.armor[2].label, i18n.t("party_armor_saved"), "party armor second")
    eq(s.armor[2].value, "≈ 1 032 · 88%", "party armor")
end)

test("armor text is shared: saved HP and the share taken off", function()
    eq(View.armor_text(1000, 250, 750, ctx().i18n), "≈ 750 · 75%", "saved and (before - after) / before")
    eq(View.armor_text(900, 106.072, 1031.9, ctx("ru").i18n), "≈ 1 032 · 88%", "the documented goblin hit")
end)

test("armor sums the party members only", function()
    local snap = snapshot({
        stats(GUTS, { enemy_def_before = 200, enemy_def_after = 100, enemy_def_saved = 100,
            armor_before = 1000, armor_after = 500, armor_saved = 700 }),
        stats(CASCA, { enemy_def_before = 300, enemy_def_after = 150, enemy_def_saved = 50,
            armor_before = 1000, armor_after = 0, armor_saved = 20 }),
        stats(GUARD, { enemy_def_before = 9000, enemy_def_after = 1, enemy_def_saved = 9999,
            armor_before = 9000, armor_after = 1, armor_saved = 9999 }),
        stats(goblin(1), { enemy_def_before = 5000, enemy_def_after = 4000, enemy_def_saved = 888,
            armor_before = 5000, armor_after = 4000, armor_saved = 888 }),
    })
    local s = View.summary(snap, ctx())
    eq(s.armor[1].value, "≈ 150 · 50%", "enemy defence of the party's hits: (500 - 250) / 500")
    eq(s.armor[2].value, "≈ 720 · 75%", "party armor: (2000 - 500) / 2000")
    -- no armor numbers from the game at all: no rows rather than a misleading 0%
    eq(#View.summary(snapshot({ stats(GUTS) }), ctx()).armor, 0, "nothing reported")
    -- only one side reported
    local one = snapshot({ stats(GUTS, { armor_before = 100, armor_after = 50, armor_saved = 40 }) })
    local rows = View.summary(one, ctx()).armor
    eq(#rows, 1, "one row"); eq(rows[1].label, "Absorbed by party armor", "party armor only")
end)

test("summary has no damage types", function()
    local snap = snapshot({ stats(GUTS, { dealt = 100, hits = 1 }) }, { types = { Slash = 600, Magic = 300, Blow = 100 } })
    eq(View.summary(snap, ctx("en")).types, nil, "the types of the fight stay out of the summary")
    eq(View.summary(snapshot({}), ctx()).types, nil, "and out of an empty one")
    eq(View.live(snap, 10, ctx()).types, nil, "and out of the live window")
end)

-- The party with a guard and Other next to it (damage, and healing from Other).
local function grey_snap()
    return party_snap({
        stats(GUARD, { dealt = 908, hits = 4 }), stats(OTHER, { dealt = 200, hits = 3, heal_done = 50 }),
    })
end

test("switched-off blocks are not built", function()
    local snap = grey_snap()
    snap.actors[TORI.key].heal_done = 300
    local m = View.live(snap, 100, ctx(), { taken = false })
    eq(m.taken, nil, "the damage to the party is off"); eq(m.damage ~= nil, true, "damage stays")
    eq(m.heal ~= nil, true, "healing stays"); eq(m.header ~= nil, true, "the header always")
    m = View.live(snap, 100, ctx(), { damage = false, taken = false, heal = false })
    eq(m.damage, nil, "damage off"); eq(m.taken, nil, "taken off"); eq(m.heal, nil, "healing off")
    eq(m.header.time, "5:18", "the header is not a block")
    -- a show that is nil or has no false in it builds everything
    for _, show in ipairs({ {}, { taken = true, damage = 1 }, false }) do
        m = View.live(snap, 100, ctx(), show)
        eq(m.damage ~= nil and m.taken ~= nil and m.heal ~= nil, true, "all built for " .. tostring(show))
    end
    m = View.live(snap, 100, ctx())
    eq(m.damage ~= nil and m.taken ~= nil and m.heal ~= nil, true, "no show: all built")

    local s = View.summary(snap, ctx(), { enemies = false, armor = false })
    eq(s.enemies, nil, "summary enemies off"); eq(s.armor, nil, "armor off")
    eq(s.damage ~= nil and s.allies ~= nil and s.heal ~= nil, true, "the other blocks stay")
    eq(s.title, "Fight over", "the title is not a block"); eq(s.time, "5:18", "nor the time")
    s = View.summary(snap, ctx(), { damage = false, heal = false })
    eq(s.damage, nil, "damage off"); eq(s.heal, nil, "healing off")
    eq(names_of(s.allies.rows), "Guard,Other", "the grey rows have their own switches")
    s = View.summary(snap, ctx(), { allies = false, other = false })
    eq(s.allies, nil, "no ally and no Other row: no block")
    eq(s.damage ~= nil and s.heal ~= nil and s.enemies ~= nil and s.armor ~= nil, true, "the rest is built")
    s = View.summary(snap, ctx())
    eq(s.enemies ~= nil and s.damage ~= nil and s.allies ~= nil and s.heal ~= nil and s.armor ~= nil, true, "no show: all built")
end)

test("allies and Other rows follow show", function()
    local snap = grey_snap()
    snap.actors[TORI.key].heal_done = 300
    -- live: the grey rows sit in the damage block, Other also in the healing block
    eq(names_of(View.live(snap, 100, ctx(), {}).damage.rows), "Guts,Torinald,Casca,Yves,Guard,Other", "all by default")
    local m = View.live(snap, 100, ctx(), { allies = false })
    eq(names_of(m.damage.rows), "Guts,Torinald,Casca,Yves,Other", "no allies")
    near(m.damage.rows[5].fill, 200 / 44463, 1e-9, "Other is still measured against the party")
    eq(names_of(m.heal.rows), "Torinald,Other", "the healing block has no allies to drop")
    m = View.live(snap, 100, ctx(), { other = false })
    eq(names_of(m.damage.rows), "Guts,Torinald,Casca,Yves,Guard", "no Other row in the damage block")
    eq(names_of(m.heal.rows), "Torinald", "nor in the healing block")
    eq(m.damage.total, "103 428", "the totals are the party's"); eq(m.heal.total, "300", "all the same")
    m = View.live(snap, 100, ctx(), { allies = false, other = false })
    eq(names_of(m.damage.rows), "Guts,Torinald,Casca,Yves", "party only")
    -- the bars do not count hidden rows: with the ally hidden Other is measured against itself
    local lone = snapshot({ stats(GUARD, { dealt = 400, hits = 1 }), stats(OTHER, { dealt = 200, hits = 1 }) })
    m = View.live(lone, 10, ctx(), { allies = false })
    eq(names_of(m.damage.rows), "Other", "Other alone"); eq(m.damage.rows[1].fill, 1, "its own top, not the hidden ally's")

    -- the summary: the allies block holds the allies, then Other
    local s = View.summary(snap, ctx(), { allies = false })
    eq(names_of(s.allies.rows), "Other", "no allies: Other stays in the block")
    eq(names_of(s.damage.rows), "Guts,Torinald,Casca,Yves", "the party block is the party's")
    eq(names_of(s.heal.rows), "Torinald,Other", "Other heals")
    s = View.summary(snap, ctx(), { other = false })
    eq(names_of(s.allies.rows), "Guard", "no Other in the allies block")
    eq(names_of(s.heal.rows), "Torinald", "nor among the healers")
    s = View.summary(snap, ctx(), { allies = false, other = false })
    eq(s.allies, nil, "nothing to put in the block")
    eq(names_of(s.damage.rows), "Guts,Torinald,Casca,Yves", "party only")
    -- the damage block off leaves the grey rows alone, measured against the party's best all the same
    s = View.summary(snap, ctx(), { damage = false })
    eq(s.damage, nil, "damage off"); eq(names_of(s.allies.rows), "Guard,Other", "grey rows stay")
    near(s.allies.rows[1].fill, 908 / 44463, 1e-9, "fill against the party's top")
end)

-- A hobgoblin of a variant (CharaID) of the base ch220001_50; `n` tells them apart.
local function hobgoblin(chara_id, n)
    return { key = "ch220001_50_" .. chara_id .. "_" .. n, name = "Hobgoblin", kind = "enemy", base_id = "ch220001_50",
        chara_id = chara_id, max_hp = 4000 }
end

-- Puts `count` enemies built by `make(n)` into the Stats list and the enemies table, each having hit `victim` for 10 * n.
local function add_foes(list, enemies, victim, count, make, taken)
    for n = 1, count do
        local a = make(n)
        list[#list + 1] = stats(a, { taken = taken or 100 })
        enemies[a.key] = foe(a)
        victim.taken_from[a.key] = 10 * n
    end
end

test("two hobgoblin variants are two rows", function()
    local guts = stats(GUTS)
    local list, enemies = { guts }, {}
    add_foes(list, enemies, guts, 2, function(n) return hobgoblin(5201, n) end)
    add_foes(list, enemies, guts, 3, function(n) return hobgoblin(5301, n) end, 200)
    local snap = snapshot(list, { enemies = enemies })

    local s = View.summary(snap, ctx("ru"))
    eq(#s.enemies, 2, "two variants, two rows")
    eq(s.enemies[1].label, "Хобгоблин ×3", "the variant that took more is the main enemy")
    eq(s.enemies[2].label, "Хобгоблин ×2", "the other variant apart")
    eq(s.enemies[1].hp_text, i18n.t("enemy_group_hp", i18n.num(4000)), "its own HP line")

    local rows = View.live(snap, 100, ctx("ru")).taken.rows
    eq(#rows, 2, "taken rows apart too")
    eq(rows[1].label, "Хобгоблин ×3 → Guts", "the three"); eq(rows[1].value, "60", "10 + 20 + 30")
    eq(rows[2].label, "Хобгоблин ×2 → Guts", "the two"); eq(rows[2].value, "30", "10 + 20")
    eq(View.live(snap, 100, ctx("ru")).header.title, "Хобгоблин", "the name is still the game's name of the base")

    -- the variants stay apart for every member they hit
    local casca = stats(CASCA)
    casca.taken_from[hobgoblin(5201, 1).key] = 5
    snap.actors[CASCA.key] = casca
    rows = View.live(snap, 100, ctx("ru")).taken.rows
    eq(#rows, 3, "one more row for the other member"); eq(rows[3].label, "Хобгоблин → Casca", "a lone attacker has no count")
end)

test("one CharaID merges", function()
    local guts = stats(GUTS)
    local list, enemies = { guts }, {}
    add_foes(list, enemies, guts, 3, function(n)
        local g = goblin(n)
        g.chara_id = 7
        return g
    end)
    local snap = snapshot(list, { enemies = enemies })
    local s = View.summary(snap, ctx("ru"))
    eq(#s.enemies, 1, "one row"); eq(s.enemies[1].label, "Гоблин ×3", "three goblins of CharaID 7")
    local rows = View.live(snap, 100, ctx("ru")).taken.rows
    eq(#rows, 1, "one taken row"); eq(rows[1].label, "Гоблин ×3 → Guts", "merged"); eq(rows[1].value, "60", "sum")

    -- a CharaID wins over the base: two bases with one CharaID are one kind
    local a, b = goblin(1), goblin(2)
    a.chara_id, b.chara_id, b.base_id = 7, 7, "ch221001_00"
    snap = snapshot({ stats(a, { taken = 100 }), stats(b, { taken = 100 }) }, { enemies = { [a.key] = foe(a), [b.key] = foe(b) } })
    s = View.summary(snap, ctx("ru"))
    eq(#s.enemies, 1, "merged by the CharaID, not by the base"); eq(s.enemies[1].label, "Гоблин ×2", "named by the first")
end)

test("no CharaID falls back to base_id", function()
    local guts = stats(GUTS)
    local list, enemies = { guts }, {}
    add_foes(list, enemies, guts, 2, goblin)
    local snap = snapshot(list, { enemies = enemies })
    eq(View.summary(snap, ctx("ru")).enemies[1].label, "Гоблин ×2", "two goblins without a CharaID merge by base_id")
    eq(View.live(snap, 100, ctx("ru")).taken.rows[1].label, "Гоблин ×2 → Guts", "in the taken rows too")

    -- one with a CharaID is another kind than those without, whatever the base
    local g3 = goblin(3)
    g3.chara_id = 7
    list[#list + 1] = stats(g3, { taken = 100 })
    enemies[g3.key] = foe(g3)
    guts.taken_from[g3.key] = 5
    snap = snapshot(list, { enemies = enemies })
    local s = View.summary(snap, ctx("ru"))
    eq(#s.enemies, 2, "the CharaID goblin is apart"); eq(s.enemies[1].label, "Гоблин ×2", "the pair")
    eq(s.enemies[2].label, "Гоблин", "and the lone one")
    eq(#View.live(snap, 100, ctx("ru")).taken.rows, 2, "taken rows apart")

    -- an enemy with neither a base nor a CharaID is its own kind, by its key
    local odd1 = { key = "odd1", name = "Odd", kind = "enemy", max_hp = 100 }
    local odd2 = { key = "odd2", name = "Odd", kind = "enemy", max_hp = 100 }
    s = View.summary(snapshot({ stats(odd1, { taken = 1 }), stats(odd2, { taken = 1 }) },
        { enemies = { odd1 = foe(odd1), odd2 = foe(odd2) } }), ctx("en"))
    eq(#s.enemies, 2, "each its own row")
end)

test("details merge charge levels", function()
    local f = Fight.new(0)
    local strike = striker(f)
    for _ = 1, 6 do strike(GUTS, CHIMERA, "CSLv2_09_魔人斬り_溜_2_極", 4817) end
    strike(GUTS, CHIMERA, "CSLv2_09_魔人斬り_溜_1_極", 1000)
    strike(GUTS, CHIMERA, "CSLv2_03_三日月斬り_溜_2_main_極", 2805)
    strike(GUTS, CHIMERA, "CSLv2_03_三日月斬り_溜_2_main_極", 2805)
    strike(GUTS, CHIMERA, "CSLv2_03_三日月斬り_溜_2_main", 900)
    for _ = 1, 3 do strike(GUTS, CHIMERA, "N_軽", 100) end
    strike(GUTS, CHIMERA, "N_軽_早繋ぎ", 50)
    strike(CASCA, CHIMERA, "N_軽", 10)

    local d = View.details(f:snapshot(60), GUTS.key, ctx("ru"))
    eq(d.name, "Guts", "name")
    eq(#d.rows, 3, "two skills and the normal attacks")
    local r = d.rows[1]
    eq(r.label, i18n.t("skill") .. " (魔人斬り)", "charge 1 and charge 2 are one skill")
    eq(r.hits, "7", "7 hits"); eq(r.total, "29 902", "total"); eq(r.max, "4 817", "max")
    eq(r.perfect, "7", "all seven were perfect-timing hits"); eq(r.share, "81%", "share of the character's damage")
    r = d.rows[2]
    eq(r.label, i18n.t("skill") .. " (三日月斬り)", "second skill"); eq(r.hits, "3", "hits"); eq(r.total, "6 510", "total")
    eq(r.max, "2 805", "max"); eq(r.perfect, "2", "two perfect of three"); eq(r.share, "18%", "share")
    r = d.rows[3]
    eq(r.label, i18n.t("normal_attacks"), "normal attacks are one row"); eq(r.hits, "4", "hits")
    eq(r.total, "350", "total"); eq(r.max, "100", "max"); eq(r.perfect, "", "no perfect count for normal attacks")
    eq(r.share, "1%", "share")

    d = View.details(f:snapshot(60), GUTS.key, ctx("en"))
    eq(d.rows[1].label, "Skill (魔人斬り)", "English: key shown")
end)

test("details: a row keyed by an attack's core joins the skill row whose attack names share that core", function()
    local f = Fight.new(0)
    local strike = striker(f)
    -- the thief's skill: the state named two hits, the third came after the state was gone (no id)
    strike(TORI, CHIMERA, "CS_06_抉り抜き_1_押", 500, { skill = { id = "Job04_HollowOut", attack = "CS_06_抉り抜き_1_押" } })
    strike(TORI, CHIMERA, "CS_06_抉り抜き_1_2(Lv2)_押", 700,
        { skill = { id = "Job04_HollowOut", attack = "CS_06_抉り抜き_1_2(Lv2)_押" } })
    strike(TORI, CHIMERA, "CS_06_抉り抜き_2_押_slow_極", 900, { skill = { attack = "CS_06_抉り抜き_2_押_slow_極", normal = true } })
    -- a mage's shell: its late tick without an id
    strike(YVES, CHIMERA, "ファイヤーストーム_Lv.2", 300, { skill = { id = "Job03_Firestorm", attack = "ファイヤーストーム_Lv.2" } })
    strike(YVES, CHIMERA, "ファイヤーストーム", 40, { skill = { attack = "ファイヤーストーム" } })
    -- normal attacks and other cores stay where they are
    strike(TORI, CHIMERA, "N_軽", 50)
    strike(TORI, CHIMERA, "CS_02_別技_1", 60)
    local names = Names.new({ skill = function(ref) return ref.id and ("game:" .. ref.id) or nil end })
    i18n.set("en")
    local c = { names = names, i18n = i18n }
    local d = View.details(f:snapshot(60), TORI.key, c)
    eq(#d.rows, 3, "the skill, the other core, normal attacks")
    eq(d.rows[1].label, "game:Job04_HollowOut", "named by the id")
    eq(d.rows[1].hits, "3", "three hits"); eq(d.rows[1].total, "2 100", "total"); eq(d.rows[1].max, "900", "max")
    eq(d.rows[1].perfect, "1", "the late hit's perfect timing counts")
    eq(d.rows[2].label, "Skill (別技)", "another core is not merged")
    eq(d.rows[3].label, i18n.t("normal_attacks"), "normal attacks")
    d = View.details(f:snapshot(60), YVES.key, c)
    eq(#d.rows, 1, "the late tick joined its spell")
    eq(d.rows[1].label, "game:Job03_Firestorm", "spell"); eq(d.rows[1].hits, "2", "hits"); eq(d.rows[1].total, "340", "total")
end)

test("details: a core claimed by two skill rows stays its own row", function()
    local f = Fight.new(0)
    local strike = striker(f)
    strike(TORI, CHIMERA, "CS_06_抉り抜き_1_押", 500, { skill = { id = "Job04_HollowOut", attack = "CS_06_抉り抜き_1_押" } })
    strike(TORI, CHIMERA, "CS_06_抉り抜き_2_押", 400, { skill = { id = "Job04_ParryCounter", attack = "CS_06_抉り抜き_2_押" } })
    strike(TORI, CHIMERA, "CS_06_抉り抜き_3_押", 90, { skill = { attack = "CS_06_抉り抜き_3_押" } })
    local names = Names.new({ skill = function(ref) return ref.id and ("game:" .. ref.id) or nil end })
    i18n.set("en")
    local d = View.details(f:snapshot(60), TORI.key, { names = names, i18n = i18n })
    eq(#d.rows, 3, "two skills and the fallback row")
    eq(d.rows[3].label, "Skill (抉り抜き)", "the fallback row stays apart"); eq(d.rows[3].hits, "1", "its hit")
end)

test("details: normal attacks by the game's flag, DoT ticks by their status", function()
    local f = Fight.new(0)
    local strike = striker(f)
    -- the mage's normal bolt (state None) and a pattern-named normal attack: one row
    for _ = 1, 3 do strike(YVES, CHIMERA, "ラピッドショット", 100, { skill = { attack = "ラピッドショット", normal = true } }) end
    strike(YVES, CHIMERA, "N_軽", 10)
    -- her fire and her shock tick on
    for _ = 1, 4 do strike(YVES, CHIMERA, nil, 50, { skill = { status = "FireSpread" }, status = "FireSpread" }) end
    strike(YVES, CHIMERA, nil, 20, { skill = { status = "Electric" }, status = "Electric" })
    strike(YVES, CHIMERA, nil, 15, { skill = { status = "WetElectric" }, status = "WetElectric" })

    local d = View.details(f:snapshot(60), YVES.key, ctx("en"))
    eq(#d.rows, 3, "normal attacks, burning, shock")
    eq(d.rows[1].label, i18n.t("normal_attacks"), "the bolt is a normal attack"); eq(d.rows[1].hits, "4", "hits")
    eq(d.rows[1].total, "310", "total")
    eq(d.rows[2].label, "Burning", "burn ticks"); eq(d.rows[2].hits, "4", "hits"); eq(d.rows[2].total, "200", "total")
    eq(d.rows[3].label, "Shock", "both shocks in one row"); eq(d.rows[3].hits, "2", "hits")
    eq(d.rows[3].total, "35", "total")
    d = View.details(f:snapshot(60), YVES.key, ctx("ru"))
    eq(d.rows[2].label, i18n.t("dot_burn"), "Russian label")
    for _, r in ipairs(d.rows) do
        eq(r.label:find(i18n.t("skill"), 1, true), nil, "no «" .. i18n.t("skill") .. " (…)» row: " .. r.label)
    end
end)

test("details merge a game skill id with its attack names", function()
    local f = Fight.new(0)
    f:add_hit({ t = 1, attacker = GUTS, victim = CHIMERA, skill = { id = 77, attack = "x_極" },
        final = 100, hp0 = 5000, hp1 = 4900 })
    f:add_hit({ t = 2, attacker = GUTS, victim = CHIMERA, skill = { id = "77" },
        final = 60, hp0 = 4900, hp1 = 4840 })
    local d = View.details(f:snapshot(5), GUTS.key, ctx("en"))
    eq(#d.rows, 1, "numeric and string ids share a row")
    eq(d.rows[1].hits, "2", "hits"); eq(d.rows[1].total, "160", "total"); eq(d.rows[1].label, "Skill (77)", "label")
    eq(d.rows[1].perfect, "1", "perfect counted from the attack name")
end)

test("perfect timing is counted per hit when the skill has an id", function()
    local f = Fight.new(0)
    f:add_hit({ t = 1, attacker = GUTS, victim = CHIMERA, skill = { id = 77, attack = "CSLv2_09_魔人斬り_溜_2_極" },
        final = 400, hp0 = 5000, hp1 = 4600 })
    f:add_hit({ t = 2, attacker = GUTS, victim = CHIMERA, skill = { id = 77, attack = "CSLv2_09_魔人斬り_溜_2" },
        final = 300, hp0 = 4600, hp1 = 4300 })
    f:add_hit({ t = 3, attacker = GUTS, victim = CHIMERA, skill = { id = 77, attack = "CSLv2_09_魔人斬り_溜_2" },
        final = 250, hp0 = 4300, hp1 = 4050 })
    local d = View.details(f:snapshot(5), GUTS.key, ctx("en"))
    eq(#d.rows, 1, "one skill id, one merged row")
    eq(d.rows[1].hits, "3", "hits"); eq(d.rows[1].total, "950", "total"); eq(d.rows[1].max, "400", "max")
    eq(d.rows[1].perfect, "1", "one of the three hits was perfect")
end)

test("details extras", function()
    local f = Fight.new(0)
    local gob = goblin(1)
    -- overkill: 4694 into 28 HP, enemy defence on the way
    f:add_hit({ t = 1, attacker = GUTS, victim = gob, skill = { attack = "N_軽" },
        final = 4694.4, hp0 = 28.4, hp1 = 0, before = 800, after = 400 })
    f:add_hit({ t = 2, attacker = gob, victim = GUTS, skill = { attack = "atk" },
        final = 137.8936, hp0 = 2245.86, hp1 = 2107.967, before = 900, after = 106.072, guard = 120.4 })
    local d = View.details(f:snapshot(5), GUTS.key, ctx("en"))
    eq(d.name, "Guts", "name")
    eq(#d.extra, 4, "full damage, enemy defence, armor, shield")
    eq(d.extra[1].label, "Full damage (with overkill)", "label 1"); eq(d.extra[1].value, "4 694", "full damage")
    eq(d.extra[2].label, "Cut by enemy defense", "label 2")
    eq(d.extra[2].value, "≈ 4 694 · 50%", "defence: 4694.4 * 800 / 400 - 4694.4 = 4694, share 50%")
    eq(d.extra[3].label, "Armor absorbed", "label 3"); eq(d.extra[3].value, "≈ 1 032 · 88%", "armor")
    eq(d.extra[4].label, "Blocked by shield", "label 4"); eq(d.extra[4].value, "120", "shield")
    eq(d.rows[1].total, "28", "the row counts HP removed, the extra the full blow")

    -- a character who only took damage has just his armor
    d = View.details(snapshot({ stats(CASCA, { armor_before = 100, armor_after = 50, armor_saved = 40 }) }), CASCA.key, ctx("ru"))
    eq(#d.rows, 0, "no skills"); eq(#d.extra, 1, "armor only")
    eq(d.extra[1].label, i18n.t("details_armor_saved"), "Russian label"); eq(d.extra[1].value, "≈ 40 · 50%", "value")
end)

test("details of an enemy and of a missing character", function()
    local g = goblin(1)
    local snap = snapshot({ stats(g, { dealt = 10, dealt_full = 10, hits = 1,
        skills = { atk = { ref = { attack = "atk" }, hits = 1, total = 10, max = 10 } } }) })
    local d = View.details(snap, g.key, ctx("en"))
    eq(d.name, "Гоблин", "an enemy is named through the lookup")
    eq(d.rows[1].label, "Skill (atk)", "skill")
    eq(View.details(snap, "no-such-key", ctx("en")), nil, "unknown key gives no model")
    local other = View.details(snapshot({ stats({ key = "other", name = "other", kind = "other" }) }), "other", ctx("ru"))
    eq(other.name, i18n.t("other"), "the pseudo-actor is called Other")
end)

test("the models do not modify the snapshot", function()
    local snap = party_snap({ stats(GUARD, { dealt = 908, hits = 4 }) })
    local g = goblin(1)
    snap.actors[GUTS.key].taken_from[g.key] = 10
    snap.actors[g.key] = stats(g)
    snap.enemies[g.key] = foe(g)
    local function dump(t, out)
        local keys = {}
        for k in pairs(t) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, k in ipairs(keys) do
            local v = t[k]
            out[#out + 1] = tostring(k) .. "="
            if type(v) == "table" then out[#out + 1] = "{"; dump(v, out); out[#out + 1] = "}" else out[#out + 1] = tostring(v) end
        end
        return out
    end
    local before = table.concat(dump(snap, {}), ";")
    View.live(snap, 100, ctx()); View.summary(snap, ctx()); View.details(snap, GUTS.key, ctx())
    View.live(snap, 100, ctx(), { allies = false, other = false, taken = false })
    View.summary(snap, ctx(), { allies = false, other = false, damage = false })
    eq(table.concat(dump(snap, {}), ";"), before, "snapshot is untouched")
end)

test("skill_groups merges charge levels and sums the extra counters", function()
    -- skill entries as the ledger keeps them (ledger.lua: Foe.by[...].skills), and one without the extra counters
    local skills = {
        ["CSLv2_09_魔人斬り_溜_2"] = { ref = { attack = "CSLv2_09_魔人斬り_溜_2_極" }, hits = 2, total = 600, max = 400,
            before = 500, after = 600, types = { Slash = 600 } },
        ["CSLv2_09_魔人斬り_溜_1"] = { ref = { attack = "CSLv2_09_魔人斬り_溜_1" }, hits = 1, total = 100, max = 100,
            before = 100, after = 100, types = { Slash = 80, Fire = 20 } },
        ["CS_06_抉り抜き_1_押"] = { ref = { id = "Job04_HollowOut", attack = "CS_06_抉り抜き_1_押" }, hits = 1,
            total = 500, max = 500, before = 400, after = 500, types = { Slash = 500 } },
        ["CS_06_抉り抜き_2_押_slow"] = { ref = { attack = "CS_06_抉り抜き_2_押_slow" }, hits = 1, total = 300, max = 300,
            before = 300, after = 300, types = { Slash = 250, Shoot = 50 } },
        ["N_軽"] = { ref = { attack = "N_軽", normal = true }, hits = 3, total = 90, max = 30 },
    }
    local groups = View.skill_groups(skills, ctx("en"))
    eq(#groups, 3, "the charge levels, the skill with its late hit, normal attacks")
    local g = groups[1]
    eq(g.key, "Job04_HollowOut", "the biggest first"); eq(g.ref.id, "Job04_HollowOut", "named by the id row")
    eq(g.hits, 2, "the core row joined"); eq(g.value, 800, "value"); eq(g.max, 500, "max")
    eq(g.before, 700, "before summed"); eq(g.after, 800, "after summed")
    eq(g.types.Slash, 750, "types summed"); eq(g.types.Shoot, 50, "a type of the joined row")
    g = groups[2]
    eq(g.key, "魔人斬り", "charge levels by their core"); eq(g.hits, 3, "hits"); eq(g.value, 700, "value")
    eq(g.max, 400, "max"); eq(g.perfect, 2, "perfect"); eq(g.before, 600, "before"); eq(g.after, 700, "after")
    eq(g.types.Slash, 680, "slash"); eq(g.types.Fire, 20, "fire")
    eq(g.ref.attack, "CSLv2_09_魔人斬り_溜_2_極", "the biggest part names the row")
    g = groups[3]
    eq(g.key, "normal", "normal attacks"); eq(g.hits, 3, "hits"); eq(g.value, 90, "value")
    eq(g.before, 0, "no before"); eq(g.after, 0, "no after"); eq(next(g.types), nil, "no types")
    for _, group in ipairs(groups) do
        eq(group.best, nil, "no working fields: best"); eq(group.cores, nil, "cores"); eq(group.raw, nil, "raw")
    end
end)

test("actor_name: Other, enemies by their kind, everyone else by name", function()
    local c = ctx("ru")
    eq(View.actor_name(OTHER, c), i18n.t("other"), "Other")
    eq(View.actor_name(ENV, c), "Падения и среда", "the enemies' own damage")
    eq(View.actor_name(CHIMERA, c), "Химера", "an enemy")
    eq(View.actor_name(GUTS, c), "Guts", "a party member")
end)

T.finish()
