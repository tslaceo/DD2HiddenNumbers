package.path = "mod/reframework/autorun/?.lua;tests/?.lua;" .. package.path

local T = require("testlib")
local test, eq, near = T.test, T.eq, T.near
local Fight = require("DD2DamageMeter/fight")
local Ledger = require("DD2DamageMeter/ledger")

local function actor(key, name, kind, base_id, max_hp, chara_id)
    return { key = key, name = name, kind = kind, base_id = base_id, max_hp = max_hp, chara_id = chara_id }
end

local P0 = actor("ch100000_00", "Casca", "pawn", "ch100000_00", 2500)
local P1 = actor("ch111007_00", "Torinald", "pawn", "ch111007_00", 2470)
local P2 = actor("ch111002_00", "Yves", "pawn", "ch111002_00", 2600)
local PL = actor("ch000000_00", "Guts", "player", "ch000000_00", 2400)
local BARREL = actor("obj_barrel_01", "Barrel", "other", "obj_barrel", 200)
local HOB = actor("ch230001_00_3", "Hobgoblin", "enemy", "ch230001_00", 18000, 5201)
local GOB = actor("ch220003_00_15", "Goblin", "enemy", "ch220003_00", 3700, 52)

-- A Hit with the fields a test leaves out filled in: the time, an attack name, the full damage as the HP taken.
local function hit(o)
    local h = { t = 1, skill = { attack = "atk" } }
    for k, v in pairs(o) do h[k] = v end
    h.final = h.final or (h.hp0 - h.hp1)
    return h
end

-- The detail of a fight that got these hits (a snapshot at 100 s).
local function detail(...)
    local f = Fight.new(0)
    for _, h in ipairs({ ... }) do f:add_hit(h) end
    return f:snapshot(100, true).detail
end

-- The enemy of the last hit, as the detail has it.
local function feed(...)
    local last = select(select("#", ...), ...)
    local enemy = last.victim.kind == "enemy" and last.victim or last.attacker
    return detail(...).foes[enemy.key]
end

-- The party hits the enemy once, so that a DoT tick on it counts afterwards.
local function engage(enemy)
    return hit{ attacker = P0, victim = enemy, hp0 = 1000, hp1 = 990, types = { Slash = 10 } }
end

test("enchanted strike on a hobgoblin", function() -- CS_02_地平斬り_1_極, in-game log: Blow 312.625, Enchant 312.625 x 0.17 -> x1.2
    local h = hit{ attacker = P0, victim = HOB, element = "Thunder", hp0 = 18000, hp1 = 17600,
        region = { before = { Blow = 312.625, Enchant = 53.14625 }, after = { Blow = 312.625, Enchant = 63.775504 }, no = 0, part = "other" } }
    local f = feed(h)
    near(f.types.Blow.dealt + f.types.Thunder.dealt, 400, 1e-6)
    near(f.types.Blow.dealt, 400 * 312.625 / 376.400504, 1e-6)
    near(f.types.Thunder.after / f.types.Thunder.before, 1.2, 1e-6); near(f.types.Blow.after / f.types.Blow.before, 1, 1e-9)
    eq(f.types.Blow.hits, 1, "Blow hits"); eq(f.types.Thunder.hits, 1, "Thunder hits")
    eq(f.types.Magic, nil, "the element replaces Magic")
end)

test("magic without element is Magic, non-magic element follows the element, fixed is Other", function()
    eq(Ledger.split{ element = "None", region = { before = { Magic = 100 }, after = { Magic = 100 } } }.Magic.w, 100, "Magic")
    eq(Ledger.split{ element = "Fire", types = { NonMagicElement = 50 } }.Fire.w, 50, "NonMagicElement with an element")
    eq(Ledger.split{ element = "None", types = { NonMagicElement = 50, Fixed = 10 } }.Other.w, 60, "NonMagicElement without, Fixed")
    eq(Ledger.split{ element = "Dark", types = { Magic = 5, Enchant = 7 } }.Dark.w, 12, "Magic and Enchant take the element")
    eq(Ledger.split{ types = { Enchant = 7 } }.Magic.w, 7, "no element at all")
    local s = Ledger.split{ element = "Light", types = { Slash = 3, Blow = 4, Shoot = 5 } }
    eq(s.Slash.w, 3, "Slash stays"); eq(s.Blow.w, 4, "Blow stays"); eq(s.Shoot.w, 5, "Shoot stays"); eq(s.Light, nil, "no element on physical")
end)

test("split falls back: the region, then the types, then Status, then Other", function()
    local s = Ledger.split{ region = { before = { Slash = 20 }, after = { Slash = 10 } }, types = { Blow = 99 } }
    eq(s.Slash.w, 10, "the region wins"); eq(s.Slash.before, 20, "before"); eq(s.Slash.after, 10, "after"); eq(s.Blow, nil, "not the types")
    s = Ledger.split{ region = { before = { Slash = 0 }, after = {} }, types = { Blow = 99 } }
    eq(s.Blow.w, 99, "an empty region is no region"); eq(s.Blow.before, 0, "types: before"); eq(s.Blow.after, 0, "types: after")
    s = Ledger.split{ status = "Poison" }
    eq(s.Status.w, 1, "a DoT tick"); eq(next(s, "Status"), nil, "only Status")
    s = Ledger.split{}
    eq(s.Other.w, 1, "nothing known"); eq(next(s, "Other"), nil, "only Other")
    s = Ledger.split{ types = { Magic = -5 } }
    eq(s.Other.w, 1, "no damage of a type is not a type")
end)

test("when everything was absorbed the damage before the step weighs", function()
    local s = Ledger.split{ region = { before = { Slash = 50, Blow = 30 }, after = { Slash = 0, Blow = 0 } } }
    eq(s.Slash.w, 50, "Slash"); eq(s.Blow.w, 30, "Blow"); eq(s.Slash.after, 0, "after stays 0")
end)

test("main type: the largest weight, ties by the display order", function()
    eq(Ledger.main_type{ types = { Slash = 10, Blow = 30 } }, "Blow", "largest")
    eq(Ledger.main_type{ types = { Shoot = 20, Slash = 20, Blow = 20 } }, "Slash", "tie: Slash first")
    eq(Ledger.main_type{ element = "Fire", types = { Magic = 60, Slash = 40 } }, "Fire", "the element")
    eq(Ledger.main_type{ element = "Fire", types = { Magic = 20, Shoot = 20 } }, "Shoot", "tie: Shoot before Fire")
    eq(Ledger.main_type{ element = "Ice", types = { Magic = 20, NonMagicElement = 20 } }, "Ice", "two raw types of one jt add up")
    eq(Ledger.main_type{ status = "Poison" }, "Status", "a DoT tick")
    eq(Ledger.main_type{}, "Other", "nothing known")
    eq(Ledger.TYPES[1], "Slash", "first"); eq(Ledger.TYPES[#Ledger.TYPES], "Other", "last"); eq(#Ledger.TYPES, 11, "all")
end)

test("no region step: weights from the defence step, no multiplier", function() -- types {Slash=300, Shoot=100}, removed 200
    local f = feed(hit{ attacker = P0, victim = HOB, hp0 = 1000, hp1 = 800, types = { Slash = 300, Shoot = 100 } })
    near(f.types.Slash.dealt, 150, 1e-9, "Slash"); near(f.types.Shoot.dealt, 50, 1e-9, "Shoot")
    eq(f.types.Slash.before, 0, "Slash before"); eq(f.types.Slash.after, 0, "Slash after")
    eq(f.types.Shoot.before, 0, "Shoot before"); eq(f.types.Shoot.after, 0, "Shoot after")
    eq(f.types.Slash.hits, 1, "hits")
    eq(next(f.by_part.head), nil, "no head without a region"); eq(next(f.by_part.body), nil, "no body either")
end)

test("fully absorbed hit", function() -- region before {Slash=50} after {Slash=0}, removed 0
    local f = feed(hit{ attacker = P0, victim = HOB, hp0 = 1000, hp1 = 1000, region = { before = { Slash = 50 }, after = { Slash = 0 }, part = "body" } })
    eq(f.types.Slash.hits, 1, "hits"); eq(f.types.Slash.before, 50, "before"); eq(f.types.Slash.after, 0, "after")
    eq(f.types.Slash.dealt, 0, "dealt")
    eq(f.by[P0.key].hits, 1, "the hit is the attacker's")
end)

test("a DoT tick is Status", function() -- attacker nil, status "FireSpread", removed 40
    local f = feed(engage(HOB),
        hit{ attacker = nil, victim = HOB, status = "FireSpread", skill = { status = "FireSpread" }, hp0 = 990, hp1 = 950 })
    eq(f.by.other.dealt, 40, "by.other.dealt"); eq(f.by.other.hits, 1, "by.other.hits")
    eq(f.types.Status.dealt, 40, "types.Status.dealt"); eq(f.types.Status.hits, 1, "types.Status.hits")
    eq(f.types.Status.before, 0, "no multiplier")
    local sk = f.by.other.skills["status:FireSpread"]
    eq(sk.hits, 1, "skill hits"); eq(sk.ref.status, "FireSpread", "ref"); eq(sk.types.Status, 40, "skill type")
end)

test("parts: head against the rest, per damage type", function() -- Shoot head 100/100, Slash part "other" 100/60
    local f = feed(
        hit{ attacker = P0, victim = HOB, hp0 = 1000, hp1 = 900, region = { before = { Shoot = 100 }, after = { Shoot = 100 }, part = "head" } },
        hit{ attacker = P0, victim = HOB, hp0 = 900, hp1 = 860, region = { before = { Slash = 100 }, after = { Slash = 60 }, part = "other" } },
        hit{ attacker = P0, victim = HOB, hp0 = 860, hp1 = 800, region = { before = { Slash = 50 }, after = { Slash = 60 }, part = "head" } })
    eq(f.by_part.head.Shoot.before, 100, "head Shoot before"); eq(f.by_part.head.Shoot.after, 100, "head Shoot after")
    eq(f.by_part.head.Slash.before, 50, "head Slash before"); eq(f.by_part.head.Slash.after, 60, "head Slash after")
    eq(f.by_part.body.Slash.before, 100, "body Slash before"); eq(f.by_part.body.Slash.after, 60, "body Slash after")
    eq(f.by_part.body.Shoot, nil, "no Shoot on the body")
    f = feed(hit{ attacker = P0, victim = HOB, element = "Thunder", hp0 = 1000, hp1 = 900,
        region = { before = { Slash = 70, Magic = 30, Enchant = 10 }, after = { Slash = 70, Magic = 45, Enchant = 15 },
                   part = "body" } })
    eq(f.by_part.body.Slash.before, 70, "body: Slash on its own"); eq(f.by_part.body.Slash.after, 70, "after")
    eq(f.by_part.body.Thunder.before, 40, "Magic and Enchant take the element"); eq(f.by_part.body.Thunder.after, 60, "after")
    eq(next(f.by_part.head), nil, "head untouched")
    f = feed(hit{ attacker = P0, victim = HOB, hp0 = 1000, hp1 = 900, region = { before = { Slash = 70 }, after = { Slash = 70 } } })
    eq(next(f.by_part.head), nil, "no part named, none counted"); eq(next(f.by_part.body), nil, "none on the body")
    -- at most the two parts times the journal types: the keys are the parts, then the types
    local hits = {}
    for i, part in ipairs({ "head", "body", "other" }) do
        for _, el in ipairs({ "None", "Fire", "Ice", "Thunder", "Light", "Dark" }) do
            hits[#hits + 1] = hit{ attacker = P0, victim = HOB, element = el, hp0 = 1000, hp1 = 999, region = {
                before = { Slash = i, Blow = i, Shoot = i, Magic = i, NonMagicElement = i, Fixed = i },
                after = { Slash = i, Blow = i, Shoot = i, Magic = i, NonMagicElement = i, Fixed = i }, part = part } }
        end
    end
    f = feed(table.unpack(hits))
    local types = {}
    for _, jt in ipairs(Ledger.TYPES) do types[jt] = true end
    local n = 0
    for part, by_type in pairs(f.by_part) do
        eq(part == "head" or part == "body", true, "a part: " .. tostring(part))
        for jt in pairs(by_type) do
            eq(types[jt], true, "a journal type: " .. tostring(jt))
            n = n + 1
        end
    end
    eq(n <= 2 * #Ledger.TYPES, true, "bounded: " .. n)
end)

test("per attacker and skill", function() -- two P0 hits of attack "N_連斬_1"
    local f = feed(
        hit{ attacker = P0, victim = HOB, skill = { attack = "N_連斬_1", normal = true }, hp0 = 1000, hp1 = 900,
            region = { before = { Slash = 120 }, after = { Slash = 100 } } },
        hit{ attacker = P0, victim = HOB, skill = { attack = "N_連斬_1", normal = true }, hp0 = 900, hp1 = 700,
            region = { before = { Slash = 230 }, after = { Slash = 200 } } },
        hit{ attacker = P1, victim = HOB, skill = { attack = "other", id = "Job02_X" }, hp0 = 700, hp1 = 650, types = { Shoot = 50 } })
    eq(f.by[P0.key].hits, 2, "P0 hits"); eq(f.by[P0.key].dealt, 300, "P0 dealt")
    local sk = f.by[P0.key].skills["N_連斬_1"]
    eq(sk.hits, 2, "skill hits"); eq(sk.total, 300, "total"); eq(sk.max, 200, "max")
    eq(sk.before, 350, "before"); eq(sk.after, 300, "after"); eq(sk.types.Slash, 300, "types.Slash == total")
    eq(sk.ref.attack, "N_連斬_1", "ref attack"); eq(sk.ref.normal, true, "ref normal"); eq(sk.votes, nil, "the votes stay inside")
    eq(f.by[P1.key].hits, 1, "P1 hits"); eq(f.by[P1.key].skills.other.ref.id, "Job02_X", "P1's ref")
    eq(f.by[P1.key].skills.other.types.Shoot, 50, "P1's type"); eq(f.by[P0.key].skills.other, nil, "skills stay apart")
end)

test("a skill's ref follows the leading vote, as the actor's does", function()
    local hits = {}
    for i = 1, 10 do hits[#hits + 1] = hit{ attacker = P1, victim = HOB, skill = { attack = "N_軽", normal = true }, hp0 = 1000 - i, hp1 = 999 - i } end
    hits[#hits + 1] = hit{ attacker = P1, victim = HOB, skill = { attack = "N_軽", id = "Job05_WarCry" }, hp0 = 900, hp1 = 899 }
    local f = Fight.new(0)
    for _, h in ipairs(hits) do f:add_hit(h) end
    local snap = f:snapshot(1, true)
    local ref = snap.detail.foes[HOB.key].by[P1.key].skills["N_軽"].ref
    eq(ref.id, nil, "one stray id does not relabel"); eq(ref.normal, true, "still a normal attack")
    eq(ref.attack, snap.actors[P1.key].skills["N_軽"].ref.attack, "the same as the actor's")
end)

test("enemy attacks by main type", function() -- GOB -> P0: 5 x types{Blow=100}, 1 x element Fire types{Magic=200}
    local hits = {}
    for i = 1, 5 do hits[#hits + 1] = hit{ attacker = GOB, victim = P0, hp0 = 2500 - 10 * (i - 1), hp1 = 2500 - 10 * i, types = { Blow = 100 } } end
    hits[#hits + 1] = hit{ attacker = GOB, victim = P0, element = "Fire", hp0 = 2450, hp1 = 2420, types = { Magic = 200 } }
    local f = feed(table.unpack(hits))
    local a = f.attacks[P0.key]
    eq(a.hits, 6, "hits"); eq(a.types.Blow, 5, "Blow"); eq(a.types.Fire, 1, "Fire"); eq(a.types.Magic, nil, "not Magic")
    eq(a.dealt, 80, "dealt is the HP removed")
    eq(next(f.types), nil, "the enemy took nothing"); eq(next(f.by), nil, "from nobody")
end)

test("a hit that removed no HP: no enemy attack, no event, unless it killed; the rest still counts", function()
    -- in game: blocked blows and grabs, «Kratos · Прочее ×10, Дробящий ×2» in «Кого бил сам»
    local f = Fight.new(0)
    f:add_hit(hit{ attacker = GOB, victim = P0, hp0 = 2500, hp1 = 2500 })
    f:add_hit(hit{ attacker = GOB, victim = P1, hp0 = 2470, hp1 = 2470, types = { Blow = 80 } })
    f:add_hit(hit{ attacker = GOB, victim = P0, hp0 = 2500, hp1 = 2400, types = { Blow = 100 } })
    local d = f:snapshot(10, true).detail
    local a = d.foes[GOB.key].attacks
    eq(a[P1.key], nil, "a victim hit for 0 HP only is not there")
    eq(a[P0.key].hits, 1, "only the hit that took HP"); eq(a[P0.key].types.Blow, 1, "its type")
    eq(a[P0.key].types.Other, nil, "no type count for the 0-HP hit"); eq(a[P0.key].dealt, 100, "dealt")
    eq(#d.record, 1, "one event"); eq(d.record[1].n, 100, "the hit that took HP")

    -- a friend's 0-HP hit on an enemy: still counted for the enemy, not in the record; a 0-HP kill is
    f = Fight.new(0)
    f:add_hit(hit{ t = 1, attacker = P0, victim = HOB, hp0 = 1000, hp1 = 990, types = { Slash = 10 } })
    f:add_hit(hit{ t = 2, attacker = P0, victim = HOB, hp0 = 990, hp1 = 990, types = { Slash = 50 } })
    f:add_hit(hit{ t = 3, attacker = PL, victim = P0, hp0 = 2500, hp1 = 2500 })
    f:add_hit(hit{ t = 4, attacker = P1, victim = HOB, hp0 = 0, hp1 = 0 })
    d = f:snapshot(10, true).detail
    local foe = d.foes[HOB.key]
    eq(foe.by[P0.key].hits, 2, "the dealer's hits keep the 0-HP one"); eq(foe.types.Slash.hits, 2, "so do the types")
    eq(foe.by[P1.key].hits, 1, "the killing blow")
    eq(#d.record, 2, "the first hit and the kill"); eq(d.record[1].n, 10, "first")
    eq(d.record[2].kill, true, "a 0-HP hit that killed is recorded"); eq(d.record[2].n, 0, "with 0")
end)

test("heals by healer, target and source", function()
    local f = Fight.new(0)
    f:add_hit(hit{ attacker = P0, victim = GOB, hp0 = 1000, hp1 = 990 })
    f:add_heal({ t = 2, target = P0, healer = nil, amount = 300, effective = 230.9, source = { kind = "item", item_id = 38 } })
    f:add_heal({ t = 3, target = P0, healer = P2, amount = 40, effective = 40, source = { kind = "skill", name = "ヒーリングスポット" } })
    f:add_heal({ t = 4, target = P0, healer = P2, amount = 10, effective = 10, source = { kind = "skill", name = "ヒーリングスポット" } })
    f:add_heal({ t = 5, target = P1, healer = nil, amount = 5, effective = 5, source = { kind = "other" } })
    f:add_heal({ t = 6, target = P1, healer = P2, amount = 7, effective = 7, source = { kind = "skill" } })
    local heals = f:snapshot(100, true).detail.heals
    eq(heals[P0.key][P0.key]["item:38"].amount, 230.9, "item 38 on P0"); eq(heals[P0.key][P0.key]["item:38"].n, 1, "n")
    eq(heals[P2.key][P0.key]["skill:ヒーリングスポット"].amount, 50, "healing spot P2 -> P0"); eq(heals[P2.key][P0.key]["skill:ヒーリングスポット"].n, 2, "n")
    eq(heals.other[P1.key].other.amount, 5, "no healer, no source"); eq(heals.other[P1.key].other.n, 1, "n")
    eq(heals[P2.key][P1.key]["skill:?"].amount, 7, "a skill heal with no attack name")
end)

test("the record keeps the latest 2000", function() -- 2500 hits with removed i
    local f = Fight.new(0)
    for i = 1, 2500 do f:add_hit(hit{ t = i, attacker = P0, victim = HOB, hp0 = 1e9, hp1 = 1e9 - i }) end
    local d = f:snapshot(3000, true).detail
    eq(#d.record, 2000, "size"); eq(d.record_dropped, 500, "dropped")
    eq(d.record[1].n, 501, "oldest"); eq(d.record[2000].n, 2500, "newest"); eq(d.record[1].k, "hit", "kind")
    for i = 2, 2000 do
        if d.record[i].n ~= d.record[i - 1].n + 1 then error("not in order at " .. i) end
    end
    eq(d.foes[HOB.key].by[P0.key].hits, 2500, "the counters keep every hit")
end)

test("a short record is oldest first, and heals share it", function()
    local f = Fight.new(0)
    f:add_hit(hit{ t = 1, attacker = P0, victim = HOB, hp0 = 1000, hp1 = 990 })
    f:add_heal({ t = 2, target = P0, healer = P2, amount = 40, effective = 40, source = { kind = "skill", name = "heal" } })
    f:add_hit(hit{ t = 3, attacker = P1, victim = HOB, hp0 = 990, hp1 = 970 })
    local d = f:snapshot(10, true).detail
    eq(#d.record, 3, "size"); eq(d.record_dropped, 0, "nothing dropped")
    eq(d.record[1].t, 1, "first"); eq(d.record[2].k, "heal", "the heal"); eq(d.record[3].t, 3, "last")
    local e = d.record[2]
    eq(e.a, P2.key, "healer"); eq(e.v, P0.key, "target"); eq(e.s, "skill:heal", "source"); eq(e.n, 40, "amount")
    f:add_heal({ t = 4, target = P0, healer = nil, amount = 5, effective = 5, source = { kind = "other" } })
    e = f:snapshot(10, true).detail.record[4]
    eq(e.k, "heal", "kind"); eq(e.a, nil, "no healer"); eq(e.s, "other", "source")
end)

test("events: skill key of a friend, main type of an enemy, kill flag, time since the start", function()
    local f = Fight.new(2)
    f:add_hit(hit{ t = 12, attacker = P1, victim = GOB, skill = { attack = "slash_1" }, hp0 = 100, hp1 = 40 })
    f:add_hit(hit{ t = 13, attacker = GOB, victim = P1, element = "Fire", hp0 = 2000, hp1 = 1970, types = { Magic = 50 } })
    f:add_hit(hit{ t = 14, attacker = P1, victim = GOB, skill = { attack = "slash_2" }, hp0 = 40, hp1 = 0 })
    f:add_hit(hit{ t = 15, attacker = nil, victim = P1, status = "Poison", skill = { status = "Poison" }, hp0 = 1970, hp1 = 1960 })
    local r = f:snapshot(20, true).detail.record
    eq(r[1].t, 10, "time since t0"); eq(r[1].a, P1.key, "attacker"); eq(r[1].v, GOB.key, "victim")
    eq(r[1].s, "slash_1", "a friend's hit: the raw skill key"); eq(r[1].n, 60, "HP removed"); eq(r[1].kill, nil, "no kill")
    eq(r[2].s, "t:Fire", "an enemy's hit: its main type"); eq(r[2].a, GOB.key, "enemy attacker")
    eq(r[3].kill, true, "the killing hit"); eq(r[3].n, 40, "no overkill")
    eq(r[4].a, nil, "a tick with no attacker"); eq(r[4].s, "status:Poison", "its skill key")
end)

test("events: anyone but a friend is recorded by the main type, a status tick by its status, never by an attack name",
        function()
    local NPC = actor("ch300100_00", "Villager", "other", "ch300100_00", 500)
    local f = Fight.new(0)
    f:add_hit(hit{ attacker = NPC, victim = P0, skill = { attack = "Atk_村人_殴り" }, hp0 = 1000, hp1 = 950,
        types = { Blow = 50 } })
    f:add_hit(hit{ attacker = BARREL, victim = PL, skill = { attack = "obj_explode" }, hp0 = 1000, hp1 = 900,
        element = "Fire", types = { NonMagicElement = 100 } })
    f:add_hit(hit{ attacker = P0, victim = PL, skill = { attack = "slash_1" }, hp0 = 900, hp1 = 880 })
    f:add_hit(hit{ attacker = NPC, victim = P0, status = "Poison", skill = { status = "Poison" }, hp0 = 950, hp1 = 940 })
    f:add_hit(hit{ attacker = nil, victim = P0, skill = {}, hp0 = 940, hp1 = 900, types = { Blow = 40 } })
    f:add_hit(hit{ attacker = GOB, victim = P0, status = "Poison", skill = { status = "Poison" }, hp0 = 900, hp1 = 890 })
    local r = f:snapshot(1, true).detail.record
    eq(#r, 6, "six events")
    eq(r[1].s, "t:Blow", "a neutral character's hit: its main type")
    eq(r[2].s, "t:Fire", "an object's: its main type")
    eq(r[3].s, "slash_1", "friendly fire keeps the friend's raw skill key")
    eq(r[4].s, "status:Poison", "a neutral character's status tick: its status")
    eq(r[5].s, "t:Blow", "a hit with no attacker and no status (a fall): its main type")
    eq(r[6].s, "t:Status", "an enemy's tick stays an enemy's hit: its main type")
end)

test("a hit with no attacker goes to whom the fight credits it; a member's own is recorded by its source", function()
    local l = Ledger.new(0)
    -- an enemy's fall: «Falls and environment» took the HP off; the record names it and the hit's main type
    l:hit(hit{ victim = GOB, skill = {}, hp0 = 1000, hp1 = 0, types = { Fixed = 1000 }, own = "self" },
        { removed = 1000, role = "dealt", skill = "?", killed = true, enemy = GOB.key, kind = "c52", by = "env" })
    -- a member's own HP cost: recorded under him, by its source; no foe
    l:hit(hit{ victim = P0, skill = {}, hp0 = 900, hp1 = 898, own = "blood_pact" },
        { removed = 2, role = "other", skill = "self:blood_pact", by = P0.key })
    -- a tick nobody caused stays Other's
    l:hit(hit{ victim = GOB, skill = { status = "Poison" }, status = "Poison", hp0 = 0, hp1 = 0 },
        { removed = 0, role = "dealt", skill = "status:Poison", enemy = GOB.key, kind = "c52" })
    local d = l:snapshot()
    local foe = d.foes[GOB.key]
    eq(foe.by.env.dealt, 1000, "the enemy's fall by «env»"); eq(foe.by.env.hits, 1, "one hit")
    eq(foe.by.other.dealt, 0, "the tick is Other's"); eq(foe.by.other.hits, 1, "one tick")
    eq(d.record[1].a, "env", "the record: who"); eq(d.record[1].s, "t:Other", "its main type")
    eq(d.record[1].kill, true, "it killed")
    eq(d.record[2].a, P0.key, "the member himself"); eq(d.record[2].v, P0.key, "on himself")
    eq(d.record[2].s, "self:blood_pact", "by its source"); eq(d.record[2].n, 2, "the HP")
    eq(d.foes[P0.key], nil, "no foe"); eq(#d.record, 2, "the tick of 0 HP is no event")
end)

test("friendly fire and hits on objects are recorded and build no foe", function()
    local f = Fight.new(0)
    f:add_hit(hit{ attacker = P0, victim = PL, hp0 = 1000, hp1 = 970 })
    f:add_hit(hit{ attacker = PL, victim = BARREL, hp0 = 200, hp1 = 150 })
    local d = f:snapshot(1, true).detail
    eq(next(d.foes), nil, "no foes"); eq(#d.record, 2, "two events")
    eq(d.record[1].n, 30, "friendly fire"); eq(d.record[2].v, BARREL.key, "the object")
end)

test("a kind keeps the first enemy data met", function()
    local foe_a, foe_b = { name = "first", flags = { a = 1 } }, { name = "second" }
    local f = Fight.new(0)
    f:add_hit(hit{ attacker = P0, victim = GOB, hp0 = 100, hp1 = 90 })
    f:add_hit(hit{ attacker = P0, victim = GOB, foe = foe_a, hp0 = 90, hp1 = 80 })
    f:add_hit(hit{ attacker = P0, victim = GOB, foe = foe_b, hp0 = 80, hp1 = 70 })
    local d = f:snapshot(1, true).detail
    eq(d.kinds.c52.name, "first", "the first one, under the CharaID")
    d.kinds.c52.flags.a = 99
    eq(foe_a.flags.a, 1, "an independent copy")
    local e = hit{ attacker = P0, victim = actor("ch300000_00_1", "Wolf", "enemy", "ch300000_00", 500), foe = { name = "wolf" }, hp0 = 50, hp1 = 40 }
    f:add_hit(e)
    eq(f:snapshot(2, true).detail.kinds["b:ch300000_00"].name, "wolf", "no CharaID: the base id")
end)

test("a snapshot of the ledger is independent of later hits and of its own edits", function()
    local f = Fight.new(0)
    f:add_hit(hit{ attacker = P0, victim = HOB, hp0 = 1000, hp1 = 900, types = { Slash = 100 } })
    f:add_heal({ t = 2, target = P0, healer = P2, amount = 40, effective = 40, source = { kind = "skill", name = "heal" } })
    local d = f:snapshot(5, true).detail
    f:add_hit(hit{ attacker = P0, victim = HOB, hp0 = 900, hp1 = 800, types = { Slash = 100 } })
    f:add_heal({ t = 3, target = P0, healer = P2, amount = 40, effective = 40, source = { kind = "skill", name = "heal" } })
    eq(d.foes[HOB.key].types.Slash.dealt, 100, "types"); eq(d.foes[HOB.key].by[P0.key].hits, 1, "by")
    eq(d.heals[P2.key][P0.key]["skill:heal"].amount, 40, "heals"); eq(#d.record, 2, "record")
    d.foes[HOB.key].types.Slash.dealt = -1
    d.record[1].n = -1
    local d2 = f:snapshot(6, true).detail
    eq(d2.foes[HOB.key].types.Slash.dealt, 200, "a second snapshot"); eq(d2.record[1].n, 100, "its record")
end)

test("efficacy on the shown value", function()
    eq(Ledger.efficacy(0), "invalid", "0"); eq(Ledger.efficacy(0.004), "invalid", "0.004"); eq(Ledger.efficacy(-1), "invalid", "-1")
    eq(Ledger.efficacy(0.49), "resist", "0.49"); eq(Ledger.efficacy(0.5), "normal", "0.5")
    eq(Ledger.efficacy(1), "normal", "1"); eq(Ledger.efficacy(1.4949), "normal", "1.4949")
    eq(Ledger.efficacy(1.4951), "effective", "1.4951"); eq(Ledger.efficacy(2), "effective", "2")
    eq(Ledger.efficacy(nil), nil, "nil")
    eq(Ledger.efficacy(0 / 0), nil, "NaN"); eq(Ledger.efficacy(math.huge), nil, "inf")
    eq(Ledger.efficacy(-math.huge), nil, "-inf")
    eq(Ledger.round_mult(0.7549), 0.75, "round_mult"); eq(Ledger.round_mult(1.005 + 1e-9), 1.01, "round up"); eq(Ledger.round_mult(2), 2, "whole")
end)

T.finish()
