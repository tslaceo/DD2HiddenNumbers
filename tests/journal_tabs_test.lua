package.path = "mod/reframework/autorun/?.lua;tests/?.lua;" .. package.path

local T = require("testlib")
local test, eq, near = T.test, T.eq, T.near
local Fight = require("DD2DamageMeter/fight")
local Journal = require("DD2DamageMeter/journal")
local JournalTabs = require("DD2DamageMeter/journal_tabs")
local View = require("DD2DamageMeter/view")
local Names = require("DD2DamageMeter/names")
local en = require("DD2DamageMeter/lang/en")
local ru = require("DD2DamageMeter/lang/ru")
local F = require("journal_fixture")

local function field(list, name)
    local out = {}
    for i, e in ipairs(list) do out[i] = tostring(e[name]) end
    return table.concat(out, " | ")
end

test("the Skills and Chart texts", function()
    local want = {
        jparty_all = { "Вся группа", "Whole party" }, jcol_who = { "Кто", "Who" }, jcol_dps = { "Урон/с", "DPS" },
        jrest = { "Остальное", "Rest" },
    }
    for key, text in pairs(want) do
        eq(ru[key], text[1], "ru." .. key)
        eq(en[key], text[2], "en." .. key)
    end
end)

test("skills: choices are the party first, then members by the damage dealt, the most first", function()
    local m = JournalTabs.skills(F.snap, F.ctx("ru"), 1)
    eq(field(m.choices, "id"), "party | a2 | a1", "ids: Torinald dealt 81 400, Guts 1 100")
    eq(field(m.choices, "name"), "Вся группа | Torinald | Guts", "names (Leo is an ally)")
    local tori, guts = m.choices[2], m.choices[3]
    eq(guts.kind, "player", "kind"); eq(guts.job, 2, "job"); eq(guts.shade, 1, "shade")
    eq(tori.kind, "pawn", "pawn kind"); eq(tori.order, 1, "order"); eq(tori.job, 4, "pawn job")
    eq(JournalTabs.skills(F.snap, F.ctx("en"), 1).choices[1].name, "Whole party", "English")
    -- pawns by slot, the player first whatever the keys
    local f = Fight.new(0)
    local p2 = { key = "a0", name = "Second", kind = "pawn", order = 2, job = 3 }
    local p1 = { key = "a9", name = "First", kind = "pawn", order = 1, job = 3 }
    local me = { key = "a5", name = "Me", kind = "player", job = 1 }
    for i, who in ipairs({ p2, p1, me }) do F.hit(f, i, who, F.OGRE, 75000 - i * 10, 75000 - i * 10 - 5) end
    m = JournalTabs.skills(f:snapshot(10), F.ctx("ru"), 1)
    eq(field(m.choices, "id"), "party | a5 | a9 | a0", "equal damage: the player, then slot 1, slot 2")
    eq(m.choices[3].shade, 1, "first mage"); eq(m.choices[4].shade, 2, "second mage")
    F.hit(f, 9, p2, F.OGRE, 74000, 73000)
    m = JournalTabs.skills(f:snapshot(10), F.ctx("ru"), 1)
    eq(field(m.choices, "id"), "party | a0 | a5 | a9", "the second pawn dealt the most")
    eq(m.choices[2].shade, 2, "his shade stays the second mage's")
end)

test("skills: whole party rows per member and skill", function()
    local m = JournalTabs.skills(F.snap, F.ctx("ru"), 1)
    eq(m.sel, 1, "sel"); eq(m.group, true, "group mode")
    eq(#m.rows, 3, "Torinald's normal attacks, Guts' two skills")
    local r = m.rows[1]
    eq(r.who, "Torinald", "who"); eq(r.label, "Обычные атаки", "label")
    eq(r.hits, "3", "hits"); eq(r.value, "81 400", "value")
    eq(r.kind, "pawn", "kind"); eq(r.job, 4, "job"); eq(r.order, 1, "order"); eq(r.shade, 1, "shade")
    eq(r.fill, 1, "the top row")
    eq(field(m.rows, "label"), "Обычные атаки | Дождь стрел | Мороз", "value-descending")
    eq(field(m.rows, "who"), "Torinald | Guts | Guts", "each with its member")
    eq(m.rows[2].value, "700", "Guts' arrows"); eq(m.rows[2].share, "1%", "share of the party's 82 500")
    eq(m.rows[1].share, "99%", "Torinald's share")
    eq(m.rows[3].fill, 400 / 81400, "fill against the top row")
    eq(m.total, "82 500", "the party's total")
    -- two members' rows of one value: the player's first
    local f = Fight.new(0)
    F.hit(f, 1, F.TORI, F.OGRE, 75000, 74000, { skill = F.NORMAL })
    F.hit(f, 2, F.GUTS, F.OGRE, 74000, 73000, { skill = F.NORMAL })
    m = JournalTabs.skills(f:snapshot(10), F.ctx("ru"), 1)
    eq(field(m.rows, "who"), "Guts | Torinald", "ties by party order")
end)

test("skills: one member with avg, dps and share", function()
    local m = JournalTabs.skills(F.snap, F.ctx("ru"), 2)
    eq(m.sel, 2, "sel: Torinald"); eq(m.group, false, "one member")
    eq(#m.rows, 1, "one skill")
    local r = m.rows[1]
    eq(r.who, nil, "no who")
    eq(r.label, "Обычные атаки", "label"); eq(r.hits, "3", "hits"); eq(r.value, "81 400", "value")
    eq(r.avg, "27 133", "avg"); eq(r.max, "72 800", "max"); eq(r.dps, "319", "dps"); eq(r.share, "100%", "share")
    eq(r.fill, 1, "fill"); eq(r.kind, "pawn", "kind"); eq(r.job, 4, "job")
    eq(m.total, "81 400", "the member's total")
    m = JournalTabs.skills(F.snap, F.ctx("ru"), 3)
    eq(field(m.rows, "label"), "Дождь стрел | Мороз", "Guts")
    eq(field(m.rows, "share"), "64% | 36%", "shares of Guts' 1 100")
    eq(m.rows[2].fill, 400 / 700, "fill against his top row")
    eq(m.rows[1].dps, "3", "700 over 255 s")
    eq(m.total, "1 100", "his total")
    -- the index is clamped
    eq(JournalTabs.skills(F.snap, F.ctx("ru"), 99).sel, 3, "past the end")
    eq(JournalTabs.skills(F.snap, F.ctx("ru"), 0).sel, 1, "before the start")
    eq(JournalTabs.skills(F.snap, F.ctx("ru"), nil).sel, 1, "nil")
    eq(JournalTabs.skills(F.snap, F.ctx("ru"), 2.5).sel, 1, "not a whole number")
end)

test("skills: a member without damage, no fight", function()
    local f = Fight.new(0)
    F.hit(f, 1, F.OGRE, F.GUTS, 2000, 1900, { types = { Blow = 100 } })
    local m = JournalTabs.skills(f:snapshot(10), F.ctx("ru"), 2)
    eq(field(m.choices, "id"), "party | a1", "Guts hit by the ogre is in the party")
    eq(#m.rows, 0, "no rows"); eq(m.total, "0", "nothing dealt")
    m = JournalTabs.skills(nil, F.ctx("ru"), 1)
    eq(field(m.choices, "id"), "party", "only the whole party")
    eq(m.sel, 1, "sel"); eq(m.group, true, "group"); eq(#m.rows, 0, "no rows"); eq(m.total, "0", "total")
end)

test("chart: a column per member by the damage dealt, its parts its own skills, the largest first", function()
    local m = JournalTabs.chart(F.chart, F.ctx("ru"), 1)
    eq(m.legend, nil, "no legend: each column has its own skills")
    eq(field(m.bars, "key"), "a2 | a1", "Torinald (9 900), then Guts (6 100)")
    eq(field(m.bars, "name"), "Torinald | Guts", "names")
    local tori, guts = m.bars[1], m.bars[2]
    eq(guts.value, 6100, "Guts' value"); eq(guts.total, "6 100", "his total")
    eq(tori.value, 9900, "Torinald's value"); eq(tori.total, "9 900", "his total")
    eq(m.top, 9900, "top")
    eq(guts.kind, "player", "kind"); eq(guts.job, 2, "job"); eq(guts.shade, 1, "shade")
    eq(tori.kind, "pawn", "pawn"); eq(tori.order, 1, "order"); eq(tori.job, 4, "pawn job")
    for _, bar in ipairs(m.bars) do
        local sum = 0
        for _, p in ipairs(bar.parts) do sum = sum + p.value end
        eq(sum, bar.value, "parts sum to " .. bar.name .. "'s value")
    end
    eq(field(tori.parts, "label"), "Обычные атаки | Перерезать горло | Кража | Тень", "Torinald's, the largest first")
    eq(field(tori.parts, "value"), "4000 | 3500 | 2000 | 400", "values")
    eq(field(tori.parts, "text"), "4 000 | 3 500 | 2 000 | 400", "as shown")
    eq(field(tori.parts, "color"), "1 | 2 | 3 | 4", "a shade each by size")
    eq(field(guts.parts, "label"), "Дождь стрел | Взрывная стрела | Обычные атаки | Мороз", "Guts' own order")
    eq(field(guts.parts, "share"), "49% | 25% | 16% | 10%", "shares of his column")
    eq(field(guts.parts, "color"), "1 | 2 | 3 | 4", "his shades by his own sizes")
    -- sel picks the column whose skills fill the list
    eq(m.sel, 1, "sel")
    eq(field(m.list, "label"), "Обычные атаки | Перерезать горло | Кража | Тень", "Torinald's skills, best first")
    eq(field(m.list, "value"), "4 000 | 3 500 | 2 000 | 400", "values")
    eq(field(m.list, "share"), "40% | 35% | 20% | 4%", "shares of his total")
    eq(field(m.list, "color"), "1 | 2 | 3 | 4", "each in its part's shade")
    m = JournalTabs.chart(F.chart, F.ctx("ru"), 2)
    eq(m.sel, 2, "Guts")
    eq(field(m.list, "label"), "Дождь стрел | Взрывная стрела | Обычные атаки | Мороз", "his skills")
    eq(JournalTabs.chart(F.chart, F.ctx("ru"), 7).sel, 2, "clamped")
    eq(JournalTabs.chart(F.chart, F.ctx("ru"), -1).sel, 1, "clamped up")
end)

test("chart: past the largest skills a column has «Остальное», the list keeps every skill", function()
    eq(JournalTabs.TOP_SKILLS, 4, "four skills a column"); eq(JournalTabs.REST, 5, "then the rest")
    local f = Fight.new(0)
    local hp = F.OGRE.max_hp
    for i, id in ipairs({ "Job02_ThreefoldArrow", "Job02_Explosive", "Job03_Frigor", "Job04_Cutthroat",
                          "Job04_Pilfer", "Job04_Shadow" }) do
        F.hit(f, i, F.GUTS, F.OGRE, hp, hp - (700 - i * 100), { skill = { id = id } })
        hp = hp - (700 - i * 100)
    end
    local m = JournalTabs.chart(f:snapshot(10), F.ctx("ru"), 1)
    local parts = m.bars[1].parts
    eq(field(parts, "label"), "Дождь стрел | Взрывная стрела | Мороз | Перерезать горло | Остальное", "four, then the rest")
    eq(field(parts, "value"), "600 | 500 | 400 | 300 | 300", "the rest sums the other two")
    eq(field(parts, "color"), "1 | 2 | 3 | 4 | 5", "the rest in the last shade")
    eq(parts[5].text, "300", "as shown"); eq(parts[5].share, "14%", "of 2 100")
    eq(field(m.list, "label"), "Дождь стрел | Взрывная стрела | Мороз | Перерезать горло | Кража | Тень", "every skill")
    eq(field(m.list, "color"), "1 | 2 | 3 | 4 | 5 | 5", "those in the rest in its shade")
    eq(JournalTabs.chart(f:snapshot(10), F.ctx("en"), 1).bars[1].parts[5].label, "Rest", "English")
end)

test("chart: a member without damage, no fight", function()
    local f = Fight.new(0)
    F.hit(f, 1, F.OGRE, F.GUTS, 2000, 1900, { types = { Blow = 100 } })
    F.hit(f, 2, F.TORI, F.OGRE, 75000, 74000, { skill = F.NORMAL })
    local m = JournalTabs.chart(f:snapshot(10), F.ctx("ru"), 2)
    eq(field(m.bars, "key"), "a2 | a1", "Guts has a bar, after the one who dealt damage")
    eq(m.bars[2].value, 0, "an empty one"); eq(#m.bars[2].parts, 0, "no parts"); eq(m.bars[2].total, "0", "total")
    eq(#m.list, 0, "nothing in his list")
    eq(m.top, 1000, "top")
    m = JournalTabs.chart(nil, F.ctx("ru"), 1)
    eq(#m.bars, 0, "no bars"); eq(m.top, 0, "top"); eq(m.sel, 1, "sel")
    eq(#m.list, 0, "no list")
end)

test("no row of 0 in Skills, Damage to party, Healing and Chart; totals and shares count everything", function()
    local f = F.build()
    F.hit(f, 80, F.GUTS, F.LIZ2, 7200, 7200, { skill = { id = "Job02_Explosive" } })  -- a skill that took no HP
    F.hit(f, 81, F.GUTS, F.LIZ2, 7200, 7199.7, { skill = { id = "Job04_Shadow" } })   -- 0.3 HP: shows as 0
    F.hit(f, 82, F.LIZ2, F.TORI, 2400, 2400, { types = { Blow = 50 } })              -- a blocked blow
    f:add_heal({ t = 83, target = F.TORI, healer = F.GUTS, amount = 40, effective = 0, source = { kind = "item", item_id = 38 } })
    f:add_heal({ t = 84, target = F.GUTS, healer = F.LEO, amount = 50, effective = 0,
                 source = { kind = "skill", name = "ヒーリングスポット" } })
    local snap = f:snapshot(255, true)
    local ctx = F.ctx("ru")

    local m = JournalTabs.skills(snap, ctx, 1)
    eq(field(m.rows, "label"), "Обычные атаки | Дождь стрел | Мороз", "no Взрывная стрела 0, no Тень 0")
    eq(m.total, "82 500", "the party's total"); eq(m.rows[2].share, "1%", "shares as before")
    m = JournalTabs.skills(snap, ctx, 3)
    eq(field(m.rows, "label"), "Дождь стрел | Мороз", "Guts alone"); eq(m.total, "1 100", "his total")
    eq(field(m.rows, "share"), "64% | 36%", "shares of his 1 100.3")

    local tori = JournalTabs.party(snap, ctx).members[2]
    eq(tori.name, "Torinald", "Torinald"); eq(#tori.rows, 0, "a lizard that took 0 HP off him has no row")

    m = JournalTabs.heal(snap, ctx)
    eq(field(m.healers, "key"), "a1 | other", "Leo healed nobody for any HP: no healer")
    eq(field(m.healers[1].rows, "label"), "→ Guts · Фруктовые пилюли", "no row of 0 for Torinald")
    eq(m.healers[1].total, "231", "his total")

    m = JournalTabs.chart(snap, ctx, 2)
    eq(field(m.bars[2].parts, "label"), "Дождь стрел | Мороз", "no part for a skill that shows 0")
    eq(field(m.bars[2].parts, "value"), "700 | 400", "Guts' parts")
    near(m.bars[2].value, 1100.3, 1e-6, "his bar counts everything that took HP"); eq(m.bars[2].total, "1 100", "total")
    eq(field(m.list, "label"), "Дождь стрел | Мороз", "his list"); eq(field(m.list, "share"), "64% | 36%", "shares")
end)

test("the Damage to party, Healing and Record texts", function()
    local want = {
        jcol_time = { "Время", "Time" }, jcol_whom = { "Кого", "Whom" }, jcol_what = { "Чем", "With" },
        jcol_amount = { "Сколько", "Amount" },
        jrecord_dropped = { "Не сохранено ранних событий: %d", "Earlier events not kept: %d" },
    }
    for key, text in pairs(want) do
        eq(ru[key], text[1], "ru." .. key)
        eq(en[key], text[2], "en." .. key)
    end
    -- the count follows a colon, so no noun has to agree with it
    local i18n = F.ctx("ru").i18n
    eq(i18n.t("jrecord_dropped", 1), "Не сохранено ранних событий: 1", "one")
    eq(i18n.t("jrecord_dropped", 1234), "Не сохранено ранних событий: 1234", "1234")
    i18n.set("en")
    eq(i18n.t("jrecord_dropped", 1), "Earlier events not kept: 1", "one, English")
end)

test("party: enemy hits by kind with types", function()
    local m = JournalTabs.party(F.snap, F.ctx("ru"))
    eq(field(m.members, "key"), "a1 | a2", "the party by order (Leo is an ally)")
    local guts, tori = m.members[1], m.members[2]
    eq(guts.name, "Guts", "name"); eq(guts.kind, "player", "kind"); eq(guts.job, 2, "job"); eq(guts.shade, 1, "shade")
    eq(tori.kind, "pawn", "pawn"); eq(tori.order, 1, "order"); eq(tori.job, 4, "pawn job")
    eq(guts.taken, "700", "his HP lost")
    eq(#guts.rows, 1, "the ogre only")
    eq(guts.rows[1].label, "Огр · Дробящий ×5, Огонь ×1", "the kind, its hits by type")
    eq(guts.rows[1].value, "700", "value"); eq(guts.rows[1].fill, 1, "fill")
    eq(guts.armor, nil, "no defence step")
    eq(tori.taken, "0", "Torinald was not hit"); eq(#tori.rows, 0, "no rows")
    -- a kind of two: one row, its enemies counted, their hits summed; value-descending
    local f = Fight.new(0)
    F.hit(f, 1, F.LIZ1, F.GUTS, 2000, 1900, { types = { Slash = 100 } })
    F.hit(f, 2, F.LIZ1, F.GUTS, 1900, 1800, { types = { Slash = 100 } })
    F.hit(f, 3, F.LIZ2, F.GUTS, 1800, 1750, { types = { Slash = 50 } })
    F.hit(f, 4, F.LIZ2, F.GUTS, 1750, 1700, { types = { Blow = 50 } })
    F.hit(f, 5, F.OGRE, F.GUTS, 1700, 1450, { types = { Blow = 250 } })
    m = JournalTabs.party(f:snapshot(10, true), F.ctx("ru"))
    guts = m.members[1]
    eq(guts.taken, "550", "taken")
    eq(field(guts.rows, "label"), "Ящер ×2 · Режущий ×3, Дробящий ×1 | Огр · Дробящий ×1", "kinds by value")
    eq(field(guts.rows, "value"), "300 | 250", "values")
    eq(guts.rows[2].fill, 250 / 300, "fill against the top row")
    -- one hit of each type: Ledger.TYPES order
    f = Fight.new(0)
    F.hit(f, 1, F.OGRE, F.GUTS, 2000, 1900, { types = { Blow = 100 } })
    F.hit(f, 2, F.OGRE, F.GUTS, 1900, 1800, { types = { Slash = 100 } })
    m = JournalTabs.party(f:snapshot(10, true), F.ctx("en"))
    eq(m.members[1].rows[1].label, "Огр · Slash ×1, Blunt ×1", "ties by type order, English")
    -- without the detail the kinds keep their rows, without types
    m = JournalTabs.party(f:snapshot(10), F.ctx("ru"))
    eq(m.members[1].rows[1].label, "Огр", "no detail: the name only")
    eq(m.members[1].rows[1].value, "200", "its value")
    eq(#JournalTabs.party(nil, F.ctx("ru")).members, 0, "no fight")
end)

test("party: members by the HP lost, the most first; each row says who hit him", function()
    local f = Fight.new(0)
    F.hit(f, 1, F.OGRE, F.GUTS, 2000, 1900, { types = { Blow = 100 } })
    F.hit(f, 2, F.LIZ1, F.TORI, 2400, 2000, { types = { Slash = 400 } })
    F.hit(f, 3, F.GUTS, F.TORI, 2000, 1950, { skill = F.NORMAL, types = { Shoot = 50 } }) -- friendly fire
    F.hit(f, 4, nil, F.TORI, 1950, 1930, {})                                             -- no attacker
    local m = JournalTabs.party(f:snapshot(10, true), F.ctx("ru"))
    eq(field(m.members, "name"), "Torinald | Guts", "Torinald lost 470, Guts 100")
    local rows = m.members[1].rows
    eq(field(rows, "name"), "Ящер | Guts | Прочее", "who hit him")
    eq(field(rows, "kind"), "enemy | player | other", "their kinds")
    eq(rows[1].types, "Режущий ×1", "the kind's hits by type"); eq(rows[1].label, "Ящер · Режущий ×1", "label")
    eq(rows[2].job, 2, "a friend's job"); eq(rows[2].shade, 1, "and shade"); eq(rows[1].shade, nil, "no shade for a kind")
    eq(rows[3].types, nil, "Other: no types"); eq(rows[3].label, "Прочее", "its name alone")
    -- equal losses keep party order
    f = Fight.new(0)
    F.hit(f, 1, F.OGRE, F.TORI, 2400, 2300, { types = { Blow = 100 } })
    F.hit(f, 2, F.OGRE, F.GUTS, 2000, 1900, { types = { Blow = 100 } })
    eq(field(JournalTabs.party(f:snapshot(10, true), F.ctx("ru")).members, "name"), "Guts | Torinald", "the player first")
    -- each member's share of the biggest loss
    f = Fight.new(0)
    F.hit(f, 1, F.OGRE, F.GUTS, 2000, 1900, { types = { Blow = 100 } })
    F.hit(f, 2, F.OGRE, F.TORI, 2400, 2000, { types = { Blow = 400 } })
    m = JournalTabs.party(f:snapshot(10, true), F.ctx("ru"))
    eq(field(m.members, "name"), "Torinald | Guts", "Torinald lost the most")
    near(m.members[1].fill, 1, 1e-9, "the biggest loss"); near(m.members[2].fill, 0.25, 1e-9, "Guts a quarter of it")
    eq(field(JournalTabs.party(Fight.new(0):snapshot(1, true), F.ctx("ru")).members, "fill"), "", "nobody")
end)

test("orders by a counter that is not a number: as 0, no error", function()
    local f = Fight.new(0)
    F.hit(f, 1, F.TORI, F.OGRE, 75000, 74000, { skill = F.NORMAL })
    F.hit(f, 2, F.GUTS, F.OGRE, 74000, 73500, { skill = F.NORMAL })
    F.hit(f, 3, F.OGRE, F.GUTS, 2000, 1900, { types = { Blow = 100 } })
    local snap = f:snapshot(10, true)
    for _, bad in ipairs({ 0 / 0, math.huge, -math.huge }) do
        snap.actors[F.GUTS.key].dealt = bad
        snap.actors[F.TORI.key].taken = bad
        local ok, m = pcall(JournalTabs.skills, snap, F.ctx("ru"), 1)
        eq(ok, true, "skills: " .. tostring(m))
        eq(field(m.choices, "id"), "party | a2 | a1", "Guts' " .. tostring(bad) .. " counts as 0")
        ok, m = pcall(JournalTabs.chart, snap, F.ctx("ru"), 1)
        eq(ok, true, "chart: " .. tostring(m))
        ok, m = pcall(JournalTabs.party, snap, F.ctx("ru"))
        eq(ok, true, "party: " .. tostring(m))
        eq(field(m.members, "name"), "Guts | Torinald", "Torinald's " .. tostring(bad) .. " counts as 0")
    end
end)

test("heal: a row's target, source and how many times", function()
    local f = Fight.new(0)
    for i = 1, 22 do
        f:add_heal({ t = i, target = F.TORI, healer = F.GUTS, amount = 10, effective = 10,
                     source = { kind = "item", item_id = 38 } })
    end
    f:add_heal({ t = 30, target = F.GUTS, healer = F.GUTS, amount = 5, effective = 5,
                 source = { kind = "item", item_id = 38 } })
    local m = JournalTabs.heal(f:snapshot(40, true), F.ctx("ru"))
    local rows = m.healers[1].rows
    eq(field(rows, "label"), "→ Torinald · Фруктовые пилюли | → Guts · Фруктовые пилюли", "rows")
    eq(field(rows, "whom"), "Torinald | Guts", "the targets"); eq(field(rows, "whom_kind"), "pawn | player", "kinds")
    eq(field(rows, "whom_job"), "4 | 2", "jobs"); eq(field(rows, "whom_shade"), "1 | 1", "shades")
    eq(field(rows, "source"), "Фруктовые пилюли | Фруктовые пилюли", "the source")
    eq(field(rows, "count"), "22 | 1", "counts"); eq(field(rows, "times"), "22 раза | 1 раз", "in words")
    eq(JournalTabs.heal(f:snapshot(40, true), F.ctx("en")).healers[1].rows[1].times, "22 times", "English")
    -- Other as a target
    f = Fight.new(0)
    f:add_heal({ t = 1, target = F.LEO, healer = F.GUTS, amount = 10, effective = 10, source = { kind = "other" } })
    local r = JournalTabs.heal(f:snapshot(5, true), F.ctx("ru")).healers[1].rows[1]
    eq(r.whom, "Leo", "an ally"); eq(r.whom_kind, "ally", "his kind"); eq(r.whom_shade, nil, "no shade")
end)

test("party: armor line per member", function()
    local f = Fight.new(0)
    -- the documented goblin hit on the player: 900 -> 106, 88 %, about 1 032 HP saved
    F.hit(f, 1, F.OGRE, F.GUTS, 2245.86, 2107.967, { types = { Blow = 106.072 }, final = 137.8936, before = 900,
                                                     after = 106.072 })
    F.hit(f, 2, F.OGRE, F.TORI, 2400, 2300, { types = { Blow = 100 } })
    local m = JournalTabs.party(f:snapshot(10, true), F.ctx("ru"))
    eq(m.members[1].armor, "≈ 1 032 · 88%", "saved and share")
    eq(m.members[2].armor, nil, "no defence step: no line")
end)

test("party: a kind's types read as the enemy card's «Кого бил сам», the armor as the details", function()
    local f = Fight.new(0)
    local hp = 2000
    local function blow(t, o)
        F.hit(f, t, F.OGRE, F.GUTS, hp, hp - 50, o)
        hp = hp - 50
    end
    for t = 1, 2 do blow(t, { types = { Blow = 50 } }) end
    for t = 3, 4 do blow(t, { types = { Slash = 50 } }) end
    blow(5, { element = "Ice", types = { Magic = 50 } })
    blow(6, { element = "Fire", types = { Magic = 50 } })
    blow(7, { types = { Shoot = 50 } })
    F.hit(f, 8, F.OGRE, F.GUTS, hp, hp - 100, { types = { Blow = 100 }, before = 400, after = 100 })
    local snap = f:snapshot(10, true)
    for _, lang in ipairs({ "ru", "en" }) do
        local ctx = F.ctx(lang)
        local row = JournalTabs.party(snap, ctx).members[1].rows[1]
        local card = Journal.enemies(snap, ctx, 1).card.attacks.rows[1]
        eq(row.label:match(" · (.*)$"), card.label:match(" · (.*)$"), "the card's type text, " .. lang)
        eq(JournalTabs.party(snap, ctx).members[1].armor, View.details(snap, F.GUTS.key, ctx).extra[1].value,
           "the details' armor text, " .. lang)
    end
    eq(JournalTabs.party(snap, F.ctx("ru")).members[1].rows[1].label,
       "Огр · Дробящий ×3, Режущий ×2, Стрелковый ×1, Огонь ×1, Лёд ×1", "the text itself")
end)

test("party: unknown attacker row («Прочее»)", function()
    local f = Fight.new(0)
    F.hit(f, 1, F.OGRE, F.GUTS, 2000, 1750, { types = { Blow = 250 } })
    F.hit(f, 2, nil, F.GUTS, 1750, 1650, { status = "Poison", skill = { status = "Poison" } })
    F.hit(f, 3, F.TORI, F.GUTS, 1650, 1600, { skill = F.NORMAL, types = { Slash = 50 } })
    local m = JournalTabs.party(f:snapshot(10, true), F.ctx("ru"))
    local guts = m.members[1]
    eq(guts.taken, "400", "taken")
    eq(field(guts.rows, "label"), "Огр · Дробящий ×1 | Прочее | Torinald", "the ogre, Other, a friend's blow")
    eq(field(guts.rows, "value"), "250 | 100 | 50", "values")
    eq(JournalTabs.party(f:snapshot(10, true), F.ctx("en")).members[1].rows[2].label, "Other", "English")
end)

-- A member's own damage and heals are his, by source.
test("party: a member's own damage is a row of its source, in his colour", function()
    local f = Fight.new(0)
    F.hit(f, 1, F.OGRE, F.GUTS, 2000, 1900, { types = { Blow = 100 } })
    F.hit(f, 2, nil, F.GUTS, 1900, 1870, { own = "blood_pact" })
    F.hit(f, 3, nil, F.GUTS, 1870, 1860, { own = "self" })
    F.hit(f, 4, nil, F.GUTS, 1860, 1855, {})
    F.hit(f, 5, nil, F.TORI, 2400, 2380, { own = "blood_pact" })
    local m = JournalTabs.party(f:snapshot(10, true), F.ctx("ru"))
    local guts, tori = m.members[1], m.members[2]
    eq(guts.taken, "145", "all of it lost")
    eq(field(guts.rows, "label"), "Огр · Дробящий ×1 | Пакт крови | Сам себе | Прочее", "by source, then Other")
    eq(field(guts.rows, "kind"), "enemy | player | player | other", "his own in his kind")
    eq(guts.rows[2].job, 2, "his job"); eq(guts.rows[2].shade, 1, "his shade"); eq(guts.rows[2].types, nil, "no types")
    eq(field(tori.rows, "label"), "Пакт крови", "the pawn's own"); eq(tori.rows[1].kind, "pawn", "in his colour")
    eq(field(JournalTabs.party(f:snapshot(10, true), F.ctx("en")).members[1].rows, "name"),
        "Огр | Blood Pact | Self | Other", "English")
end)

test("heal: a member's own heals are under him, «Вампиризм» and «Восстановление»", function()
    local f = Fight.new(0)
    local function own(t, who, name, amount)
        f:add_heal({ t = t, target = who, healer = who, amount = amount, effective = amount,
                     source = { kind = "self", name = name } })
    end
    own(1, F.GUTS, "lifesteal", 250)
    own(2, F.GUTS, "regen", 1.5)
    own(3, F.GUTS, "regen", 1.5)
    f:add_heal({ t = 4, target = F.TORI, amount = 5, effective = 5, source = { kind = "other" } })
    local m = JournalTabs.heal(f:snapshot(10, true), F.ctx("ru"))
    eq(field(m.healers, "key"), "a1 | other", "Guts heals himself; Other")
    local guts = m.healers[1]
    eq(guts.total, "253", "his total")
    eq(field(guts.rows, "label"), "→ Guts · Вампиризм | → Guts · Восстановление", "by source")
    eq(field(guts.rows, "count"), "1 | 2", "how many"); eq(field(guts.rows, "source"), "Вампиризм | Восстановление", "source")
    eq(field(JournalTabs.heal(f:snapshot(10, true), F.ctx("en")).healers[1].rows, "source"), "Lifesteal | Regeneration",
        "English")
end)

-- Argent Tonic is the mage's skill heal, named by its skill id as skills are.
test("heal: a skill heal by its skill id is named as the skill («Серебряный тоник»), in the Healing tab and the record",
        function()
    local f = Fight.new(0)
    f:add_heal({ t = 1, target = F.GUTS, healer = F.TORI, amount = 2000, effective = 1500,
                 source = { kind = "skill", id = "Job03_FullRecover" } })
    f:add_heal({ t = 2, target = F.TORI, healer = F.TORI, amount = 900, effective = 900,
                 source = { kind = "skill", id = "Job03_FullRecover" } })
    local snap = f:snapshot(10, true)
    local m = JournalTabs.heal(snap, F.ctx("ru"))
    eq(field(m.healers, "key"), "a2", "Torinald heals")
    eq(field(m.healers[1].rows, "label"), "→ Guts · Серебряный тоник | → Torinald · Серебряный тоник", "by target")
    eq(m.healers[1].total, "2 400", "his total")
    eq(field(JournalTabs.record(snap, F.ctx("ru")).rows, "what"), "Серебряный тоник | Серебряный тоник", "the record")
    local bare = { names = Names.new({}), i18n = F.ctx("ru").i18n }
    eq(JournalTabs.heal(snap, bare).healers[1].rows[1].source, bare.names:skill({ id = "Job03_FullRecover" }),
        "without the game's text: as skills are named elsewhere")
end)

test("heal: healer to target by source", function()
    local m = JournalTabs.heal(F.snap, F.ctx("ru"))
    eq(field(m.healers, "key"), "a1 | other", "Guts (his item), then Other")
    local guts, other = m.healers[1], m.healers[2]
    eq(guts.name, "Guts", "name"); eq(guts.kind, "player", "kind"); eq(guts.job, 2, "job"); eq(guts.shade, 1, "shade")
    eq(guts.total, "231", "total")
    eq(#guts.rows, 1, "one row")
    eq(guts.rows[1].label, "→ Guts · Фруктовые пилюли", "target and item")
    eq(guts.rows[1].value, "231", "value"); eq(guts.rows[1].count, 1, "count")
    eq(other.name, "Прочее", "Other"); eq(other.kind, "other", "its kind"); eq(other.total, "15", "its total")
    eq(other.rows[1].label, "→ Guts · Прочее", "an unknown source"); eq(other.rows[1].value, "15", "value")
    -- the healing spot is named by the game's message; the party by order, then Other
    local f = Fight.new(0)
    local spot = { kind = "skill", name = "ヒーリングスポット" }
    f:add_heal({ t = 1, target = F.GUTS, healer = F.TORI, amount = 40, effective = 40, source = spot })
    f:add_heal({ t = 2, target = F.GUTS, healer = F.TORI, amount = 40, effective = 40, source = spot })
    -- the larger spot is the same skill by name: one row for Guts
    f:add_heal({ t = 3, target = F.GUTS, healer = F.TORI, amount = 50, effective = 50,
                 source = { kind = "skill", name = "ヒーリングスポット_大" } })
    f:add_heal({ t = 3, target = F.TORI, healer = F.TORI, amount = 50, effective = 50, source = spot })
    f:add_heal({ t = 4, target = F.TORI, healer = F.TORI, amount = 5, effective = 5, source = { kind = "skill" } })
    f:add_heal({ t = 5, target = F.TORI, healer = F.TORI, amount = 4, effective = 4,
                 source = { kind = "skill", name = "回復" } })
    f:add_heal({ t = 6, target = F.GUTS, amount = 30, effective = 30, source = { kind = "item" } })
    f:add_heal({ t = 7, target = F.GUTS, amount = 20, effective = 20, source = { kind = "other" } })
    m = JournalTabs.heal(f:snapshot(10, true), F.ctx("ru"))
    eq(field(m.healers, "key"), "a1 | a2 | other", "the player, the pawn, Other")
    eq(field(m.healers, "total"), "30 | 189 | 20", "totals")
    local tori = m.healers[2]
    eq(field(tori.rows, "label"), "→ Guts · Исцеление | → Torinald · Исцеление | → Torinald · Навык",
        "the spot from the message; a nameless skill and another skill (never its attack name) by the mod's word")
    eq(field(tori.rows, "value"), "130 | 50 | 9", "value-descending")
    eq(field(tori.rows, "count"), "3 | 1 | 2", "how many heals")
    eq(tori.rows[2].fill, 50 / 130, "fill against the healer's top row")
    eq(m.healers[1].rows[1].label, "→ Guts · Предмет", "an item without an id")
    eq(JournalTabs.heal(f:snapshot(10, true), F.ctx("en")).healers[2].rows[1].label, "→ Guts · Anodyne", "English")
    eq(#JournalTabs.heal(f:snapshot(10), F.ctx("ru")).healers, 0, "no detail")
    eq(#JournalTabs.heal(nil, F.ctx("ru")).healers, 0, "no fight")
end)

test("heal: the healing spot without the game's message is «Навык», not its attack name", function()
    local f = Fight.new(0)
    f:add_heal({ t = 1, target = F.GUTS, healer = F.TORI, amount = 40, effective = 40,
                 source = { kind = "skill", name = "ヒーリングスポット" } })
    local bare = { names = Names.new({}), i18n = F.ctx("ru").i18n } -- the game answers no message
    local snap = f:snapshot(10, true)
    eq(JournalTabs.heal(snap, bare).healers[1].rows[1].label, "→ Guts · Навык", "the Healing tab")
    eq(JournalTabs.record(snap, bare).rows[1].what, "Навык", "the Record tab")
    eq(JournalTabs.heal(snap, F.ctx("ru")).healers[1].rows[1].label, "→ Guts · Исцеление", "with the message")
end)

test("record: hits and heals in order with names", function()
    local m = JournalTabs.record(F.snap, F.ctx("ru"))
    eq(#m.rows, 14, "every hit and heal")
    eq(m.dropped, nil, "nothing dropped")
    local r = m.rows[1]
    eq(r.time, "0:00", "time"); eq(r.who, "Torinald", "who"); eq(r.whom, "Огр", "whom")
    eq(r.what, "Обычные атаки", "what"); eq(r.amount, "1 000", "amount"); eq(r.heal, false, "a hit")
    eq(r.kill, false, "no kill")
    eq(field(m.rows, "time"), "0:00 | 0:05 | 0:06 | 0:10 | 0:11 | 0:12 | 0:13 | 0:14 | 0:15 | 1:02 | 1:10 | 1:40 | "
        .. "3:20 | 4:12", "oldest first")
    eq(field(m.rows, "who"), "Torinald | Guts | Leo | Огр | Огр | Огр | Огр | Огр | Огр | Torinald | Guts | Guts | "
        .. "Прочее | Torinald", "who")
    eq(field(m.rows, "whom"), "Огр | Огр | Огр | Guts | Guts | Guts | Guts | Guts | Guts | Ящер | Ящер | Guts | "
        .. "Guts | Огр", "whom")
    eq(m.rows[2].what, "Дождь стрел", "Guts' skill"); eq(m.rows[2].amount, "700", "its HP")
    eq(m.rows[3].what, "Обычные атаки", "an ally's normal attack")
    eq(m.rows[11].what, "Мороз", "Frigor")
    local item = m.rows[12]
    eq(item.what, "Фруктовые пилюли", "the item"); eq(item.amount, "+231", "a heal's amount"); eq(item.heal, true, "heal")
    eq(m.rows[13].what, "Прочее", "a heal of no known source"); eq(m.rows[13].amount, "+15", "+15")
    eq(m.rows[13].heal, true, "heal")
    eq(JournalTabs.record(F.snap, F.ctx("en")).rows[1].what, "Normal attacks", "English")
    eq(#JournalTabs.record(nil, F.ctx("ru")).rows, 0, "no fight")
    local live = F.build():snapshot(255)
    m = JournalTabs.record(live, F.ctx("ru"))
    eq(#m.rows, 0, "no detail: no rows"); eq(m.dropped, nil, "no dropped line")
end)

test("record: a held hit replayed shows at its own time", function()
    local f = Fight.new(0)
    F.hit(f, 1, F.TORI, F.OGRE, 75000, 74000, { skill = F.NORMAL })
    F.hit(f, 3, F.LEO, F.LIZ1, 7600, 7500, { skill = F.NORMAL }) -- held: the party has not fought the lizard yet
    F.hit(f, 5, F.LEO, F.LIZ1, 7500, 7400, { skill = F.NORMAL }) -- held
    F.hit(f, 5, F.GUTS, F.OGRE, 74000, 73900, { skill = { id = "Job02_ThreefoldArrow" } })
    F.hit(f, 8, F.TORI, F.LIZ1, 7400, 7000, { skill = F.NORMAL }) -- engages the lizard: Leo's two counted first
    local snap = f:snapshot(10, true)
    eq(field(snap.detail.record, "t"), "1 | 5 | 3 | 5 | 8", "the ledger keeps counting order")
    local m = JournalTabs.record(snap, F.ctx("ru"))
    eq(field(m.rows, "time"), "0:01 | 0:03 | 0:05 | 0:05 | 0:08", "by time")
    eq(field(m.rows, "who"), "Torinald | Leo | Guts | Leo | Torinald", "a tie keeps counting order")
    eq(field(m.rows, "amount"), "1 000 | 100 | 100 | 100 | 400", "amounts")
end)

test("record: an enemy hit names its type", function()
    local m = JournalTabs.record(F.snap, F.ctx("ru"))
    eq(m.rows[4].what, "Дробящий", "the ogre's blows")
    eq(m.rows[9].what, "Огонь", "its fire")
    eq(JournalTabs.record(F.snap, F.ctx("en")).rows[4].what, "Blunt", "English")
    -- a DoT tick nobody applied: Other, named by its status
    local f = Fight.new(0)
    F.hit(f, 1, F.TORI, F.OGRE, 75000, 74000, { skill = F.NORMAL })
    F.hit(f, 2, nil, F.OGRE, 74000, 73960, { status = "Poison", skill = { status = "Poison" } })
    m = JournalTabs.record(f:snapshot(10, true), F.ctx("ru"))
    eq(m.rows[2].who, "Прочее", "nobody"); eq(m.rows[2].whom, "Огр", "the ogre"); eq(m.rows[2].what, "Яд", "poison")
end)

test("record: a member's own damage and heals under him by source; an enemy's fall under «Падения и среда»", function()
    local f = Fight.new(0)
    F.hit(f, 1, F.TORI, F.OGRE, 75000, 74000, { skill = F.NORMAL })
    F.hit(f, 2, nil, F.GUTS, 2000, 1998, { own = "blood_pact" })
    f:add_heal({ t = 3, target = F.GUTS, healer = F.GUTS, amount = 100, effective = 100,
                 source = { kind = "self", name = "lifesteal" } })
    f:add_heal({ t = 4, target = F.GUTS, healer = F.GUTS, amount = 2, effective = 2,
                 source = { kind = "self", name = "regen" } })
    F.hit(f, 5, nil, F.OGRE, 74000, 73000, { own = "self", types = { Blow = 1000 } })
    F.hit(f, 6, nil, F.GUTS, 2098, 2088, { own = "self" })
    local m = JournalTabs.record(f:snapshot(10, true), F.ctx("ru"))
    eq(field(m.rows, "who"), "Torinald | Guts | Guts | Guts | Падения и среда | Guts", "who")
    eq(field(m.rows, "whom"), "Огр | Guts | Guts | Guts | Огр | Guts", "whom")
    eq(field(m.rows, "what"), "Обычные атаки | Пакт крови | Вампиризм | Восстановление | Дробящий | Сам себе",
        "a member's own by its source, the fall by its type")
    eq(field(m.rows, "amount"), "1 000 | 2 | +100 | +2 | 1 000 | 10", "amounts")
    eq(field(JournalTabs.record(f:snapshot(10, true), F.ctx("en")).rows, "what"),
        "Normal attacks | Blood Pact | Lifesteal | Regeneration | Blunt | Self", "English")
end)

test("record: no internal attack name or id reaches the text", function()
    local npc = { key = "a20", name = "Villager", kind = "other", base_id = "ch300100_00", max_hp = 500 }
    local f = Fight.new(0)
    F.hit(f, 1, F.GUTS, F.OGRE, 75000, 74000, { skill = { id = "Job02_ThreefoldArrow" } })
    F.hit(f, 2, npc, F.GUTS, 2000, 1950, { skill = { attack = "Atk_村人_殴り" }, types = { Blow = 50 } })
    F.hit(f, 3, F.TORI, F.GUTS, 1950, 1900, { skill = { attack = "CS_02_地平斬り_1" } }) -- friendly fire
    F.hit(f, 4, F.GUTS, F.TORI, 2400, 2390, { skill = { id = "Job02_ThreefoldArrow" } }) -- a skill he has on the ogre
    F.hit(f, 5, nil, F.OGRE, 74000, 73990, { types = { Blow = 10 } })                  -- nobody, no status
    F.hit(f, 6, F.GUTS, F.TORI, 2390, 2380, { skill = { attack = "N_矢_1", normal = true } }) -- friendly fire, normal
    F.hit(f, 7, npc, F.GUTS, 1900, 1890, { status = "Poison", skill = { status = "Poison" } }) -- the NPC's poison tick
    F.hit(f, 8, nil, F.GUTS, 1890, 1850, {})                                           -- a fall
    local snap = f:snapshot(10, true)
    local m = JournalTabs.record(snap, F.ctx("ru"))
    eq(field(m.rows, "who"), "Guts | Villager | Torinald | Guts | Прочее | Guts | Villager | Прочее", "who")
    eq(field(m.rows, "what"),
        "Дождь стрел | Дробящий | Навык | Дождь стрел | Дробящий | Обычные атаки | Яд | Прочее",
        "a neutral character's hit and a hit with no attacker by their type; friendly fire without a skill entry by the "
        .. "mod's word, a normal attack as normal attacks; a status tick by its status")
    -- a raw key in the record of a character who is not a friend (as before) is not shown either
    snap.detail.record[2].s = "Atk_村人_殴り"
    eq(JournalTabs.record(snap, F.ctx("ru")).rows[2].what, "Навык", "a raw key")
    eq(JournalTabs.record(snap, F.ctx("en")).rows[3].what, "Skill", "English")
end)

test("record: a kill is marked", function()
    local m = JournalTabs.record(F.snap, F.ctx("ru"))
    local kills = {}
    for i, r in ipairs(m.rows) do
        if r.kill then kills[#kills + 1] = tostring(i) end
    end
    eq(table.concat(kills, " "), "10 14", "the lizard at 1:02 and the ogre at 4:12")
    eq(m.rows[10].whom, "Ящер", "the lizard"); eq(m.rows[14].what, "Обычные атаки", "what stays the skill")
end)

test("record: dropped line", function()
    local f = Fight.new(0)
    local hp = 1e7
    for i = 1, 2500 do
        F.hit(f, i, F.TORI, F.OGRE, hp, hp - i, { skill = F.NORMAL })
        hp = hp - i
    end
    local snap = f:snapshot(3000, true)
    eq(snap.detail.record_dropped, 500, "the ledger dropped 500")
    local m = JournalTabs.record(snap, F.ctx("ru"))
    eq(m.dropped, "Не сохранено ранних событий: 500", "the dropped line")
    eq(#m.rows, 2000, "the latest 2000")
    eq(m.rows[1].amount, "501", "the 501st first"); eq(m.rows[2000].amount, "2 500", "the last")
    eq(JournalTabs.record(snap, F.ctx("en")).dropped, "Earlier events not kept: 500", "English")
end)

T.finish()
