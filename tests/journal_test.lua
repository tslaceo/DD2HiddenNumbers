package.path = "mod/reframework/autorun/?.lua;tests/?.lua;" .. package.path

local T = require("testlib")
local test, eq, near = T.test, T.eq, T.near
local i18n = require("DD2DamageMeter/i18n")
local Names = require("DD2DamageMeter/names")
local Fight = require("DD2DamageMeter/fight")
local Ledger = require("DD2DamageMeter/ledger")
local Journal = require("DD2DamageMeter/journal")
local View = require("DD2DamageMeter/view")
local HistoryFile = require("DD2DamageMeter/history_file")
local F = require("journal_fixture")
local json_decode = require("json_decode")

local function card(snap, sel, lang)
    return Journal.enemies(snap, F.ctx(lang), sel).card
end

local function row_with(rows, field, value)
    for _, r in ipairs(rows) do
        if r[field] == value then return r end
    end
    return nil
end

local function labels(rows)
    local out = {}
    for _, r in ipairs(rows) do out[#out + 1] = r.label end
    return table.concat(out, " | ")
end

test("header line, fight counter and the five numbers", function()
    local h = Journal.header(F.snap, F.ctx("ru"), 2, 32)
    eq(h.line, "Победа · 4:15 · Огр, Ящер ×2", "line")
    eq(h.fight, "бой 2 из 32", "fight counter")
    local want = {
        { "Нанесено", "82 500", "damage" }, { "Урон в секунду", "324" }, { "Получено", "700", "enemies" },
        { "Вылечено", "231", "heal" }, { "Срезано защитой врагов", "—" },
    }
    eq(#h.numbers, #want, "five numbers")
    for i, w in ipairs(want) do
        eq(h.numbers[i].label, w[1], "label " .. i)
        eq(h.numbers[i].value, w[2], "value " .. i)
        eq(h.numbers[i].block, w[3], "block " .. i)
    end
    h = Journal.header(F.snap, F.ctx("en"), 1, 3)
    eq(h.line, "Victory · 4:15 · Огр, Ящер ×2", "English line, the game's enemy names")
    eq(h.fight, "fight 1 of 3", "English counter")
    eq(h.numbers[2].label, "Damage per second", "English label")
end)

test("header without a fight", function()
    local h = Journal.header(nil, F.ctx("ru"), 1, 0)
    eq(h.line, "Боёв пока нет", "line")
    eq(h.fight, nil, "no counter")
    eq(#h.numbers, 0, "no numbers")
    eq(Journal.header(nil, F.ctx("en"), 1, 0).line, "No fights yet", "English")
end)

test("header: a fight that just ended, at most three kinds, the share the enemy defence took", function()
    local f = Fight.new(10)
    for i = 1, 5 do
        local e = { key = "e" .. i, name = "b" .. i, kind = "enemy", base_id = "b" .. i, chara_id = 100 + i,
                    max_hp = 1000 * i }
        F.hit(f, 12, F.GUTS, e, e.max_hp, e.max_hp - 50, { before = 100, after = 50 })
    end
    f:finish(40, "end")
    -- the game names each kind (here by its id), so the line shows which three come first
    local names = Names.new({ enemy = function(base_id) return base_id end })
    local function ctx(lang)
        i18n.set(lang)
        return { names = names, i18n = i18n }
    end
    local h = Journal.header(f:snapshot(40), ctx("ru"), 1, 1)
    eq(h.line, "Бой окончен · 0:30 · b5, b4, b3, ещё 2", "three kinds, then the count of the others")
    eq(h.fight, "бой 1 из 1", "one fight")
    eq(h.numbers[5].value, "50%", "defence took half before the region step")
    eq(h.numbers[5].block, nil, "no block")
    eq(Journal.header(f:snapshot(40), ctx("en"), 1, 1).line, "Fight over · 0:30 · b5, b4, b3, 2 more", "English")
end)

test("header and list: on equal full HP the kind the party hit last comes first", function()
    local ogre = { key = "e1", name = "ch230000_00", kind = "enemy", base_id = "ch230000_00", chara_id = 2300,
                   max_hp = 7600 }
    local wolf = { key = "e2", name = "ch221001_00", kind = "enemy", base_id = "ch221001_00", chara_id = 2211,
                   max_hp = 7600 }
    local f = Fight.new(0)
    local function order(t)
        local snap = f:snapshot(t)
        return Journal.header(snap, F.ctx("ru"), 1, 1).line, labels(Journal.enemies(snap, F.ctx("ru"), 1).list.rows)
    end
    F.hit(f, 1, F.GUTS, ogre, 7600, 5000)
    F.hit(f, 2, F.GUTS, wolf, 7600, 7500)
    local line, list = order(3)
    eq(line, "Бой окончен · 0:03 · Волк, Огр", "the wolf, hit last, though it took less")
    eq(list, "Волк | Огр", "the list too")
    F.hit(f, 4, F.TORI, ogre, 5000, 4990)
    line, list = order(5)
    eq(line, "Бой окончен · 0:05 · Огр, Волк", "the ogre hit again"); eq(list, "Огр | Волк", "list")
    -- a kind of several: the hit on any of its members counts; so does an ally's hit on an enemy the party fights
    F.hit(f, 6, F.GUTS, F.LIZ1, 7600, 7500)
    F.hit(f, 6.5, F.LIZ2, F.GUTS, 2000, 1900)
    F.hit(f, 7, F.LEO, F.LIZ2, 7600, 7590)
    line, list = order(8)
    eq(line, "Бой окончен · 0:08 · Ящер ×2, Огр, Волк", "the lizards")
    eq(list, "Ящер ×2 | Ящер | Ящер | Огр | Волк", "list")
    -- a bigger kind stays first whatever the order of the hits
    local big = { key = "e3", name = "ch999999_00", kind = "enemy", base_id = "ch999999_00", chara_id = 9999,
                  max_hp = 8000 }
    F.hit(f, 0.5, F.GUTS, big, 8000, 7990)
    eq((order(9)), "Бой окончен · 0:09 · Безымянный враг, Ящер ×2, Огр, ещё 1", "the biggest first")
end)

test("list: one row per enemy, a kind of several under a kind row", function()
    local m = Journal.enemies(F.snap, F.ctx("ru"), 1)
    eq(m.list.title, "Враги · 3", "title counts enemies")
    local rows = m.list.rows
    eq(#rows, 4, "ogre, the lizard kind, two lizards")
    local want = {
        { id = "e:a10", label = "Огр", hp_text = "75 000 HP", killed = true, group = false, member = false, fill = 0 },
        { id = "k:c2210", label = "Ящер ×2", hp_text = "по 7 600 HP · убито: 1 из 2", killed = false, group = true,
          member = false, fill = 7200 / 15200 },
        { id = "e:a11", label = "Ящер", hp_text = "7 600 HP", killed = true, group = false, member = true, fill = 0 },
        { id = "e:a12", label = "Ящер", hp_text = "7 200 / 7 600 HP", killed = false, group = false, member = true,
          fill = 7200 / 7600 },
    }
    for i, w in ipairs(want) do
        for field, value in pairs(w) do
            if field == "fill" then near(rows[i].fill, value, 1e-9, "row " .. i .. " fill")
            else eq(rows[i][field], value, "row " .. i .. " " .. field) end
        end
    end
    eq(m.sel, 1, "selection kept")
    eq(m.card.title, "Огр", "card of the selected row")
end)

test("the selection is clamped to the list", function()
    eq(Journal.enemies(F.snap, F.ctx("ru"), 0).sel, 1, "below")
    local m = Journal.enemies(F.snap, F.ctx("ru"), 99)
    eq(m.sel, 4, "above"); eq(m.card.title, "Ящер", "the last row's card")
    eq(Journal.enemies(F.snap, F.ctx("ru"), nil).sel, 1, "nil")
    local empty = Journal.enemies(Fight.new(0):snapshot(5, true), F.ctx("ru"), 3)
    eq(#empty.list.rows, 0, "no rows"); eq(empty.list.title, "Враги · 0", "title")
    eq(empty.sel, 1, "selection"); eq(empty.card, nil, "no card")
end)

test("card of one enemy: what the game says", function()
    local c = card(F.snap, 1)
    eq(c.title, "Огр", "title")
    eq(c.deaths, nil, "one enemy: no list of deaths")
    eq(c.game.data, true, "data read")
    eq(T.str(c.game.weak), "Дробящий Свет", "weak: Blow 2 + Light 128")
    eq(T.str(c.game.resist), "Лёд", "resist: Ice 32")
    eq(table.concat(c.game.immune, ", "),
        "Отравление, Быстродействующий яд, Сон, Обморок, Обморожение, Ледяные оковы, Электричество",
        "immune: the statuses off in 8395888, the game's messages cut after «: » with a capital, electricity from the "
        .. "lang file")
    eq(c.game.defence, "Защита 250 · Маг. защита 180", "defence")
end)

test("status and defence names: the game's messages, else the lang texts", function()
    local bare = { names = Names.new({ enemy = function() return "Огр" end }), i18n = i18n }
    i18n.set("ru")
    local g = Journal.enemies(F.snap, bare, 1).card.game
    eq(table.concat(g.immune, ", "), "Отравление, Сильный яд, Сон, Обморок, Обморожение, Заморозка, Электричество",
        "fallback names")
    eq(g.defence, "Защита 250 · Маг. защита 180", "fallback labels")
    g = card(F.snap, 1, "en").game
    eq(table.concat(g.immune, ", "), "Blighted, Fulminant Poison, Sleep, Unconscious, Frostbite, Ice-Bound, Shock",
        "English messages cut after «: »")
    eq(T.str(g.weak), "Blunt Holy", "English weak"); eq(T.str(g.resist), "Ice", "English resist")
    eq(g.defence, "Defense 250 · Magick Defense 180", "the game's labels")
    i18n.set("en")
    eq(Journal.enemies(F.snap, bare, 1).card.game.defence, "Defense 250 · Magick defense 180", "English fallbacks")
end)

test("a status name from the game starts with a capital letter", function()
    -- in game: «Не действует: осмоление» next to «Быстродействующий яд»
    local messages = { ui080101_46 = "Недуг: осмоление", ui080101_41 = "Недуг: Быстродействующий яд",
                       ui080101_40 = "ёжик", ui080101_42 = "Debilitation: sleep", ui080101_43 = "«обморок»" }
    local ctx = { names = Names.new({ enemy = function() return "Огр" end,
                                      message = function(name) return messages[name] end }), i18n = i18n }
    i18n.set("ru")
    local _, snap = F.build()
    snap.detail.kinds.c2300.enabled = 8395888 - 1024 -- Oil off too
    eq(table.concat(Journal.enemies(snap, ctx, 1).card.game.immune, ", "),
        "Ёжик, Быстродействующий яд, Sleep, «обморок», Обморожение, Заморозка, Электричество, Осмоление",
        "the game's messages and the lang texts, each with a capital; another first character as it is")
end)

test("Blind in the immune list with « ?» after it, in both languages; the others without, the order kept", function()
    local _, snap = F.build()
    -- every status but Sleep, Frostbite and Blind works
    snap.detail.kinds.c2300.enabled = (8388607 + 8388608) - 4 - 256 - 8388608
    eq(table.concat(card(snap, 1, "ru").game.immune, ", "), "Сон, Обморожение, Ослепление ?",
        "ru: Blind marked, Sleep and Frostbite not, in Journal.STATUSES order")
    eq(table.concat(card(snap, 1, "en").game.immune, ", "), "Sleep, Frostbite, Blindness ?", "en: the same mark")
    snap.detail.kinds.c2300.enabled = (8388607 + 8388608) - 4
    eq(table.concat(card(snap, 1, "ru").game.immune, ", "), "Сон", "Blind works: no mark anywhere")
    i18n.set("ru")
end)

test("unclear statuses: Blind alone, marked by its entry; mark_unclear adds « ?» to its text only", function()
    local unclear = {}
    for _, s in ipairs(Journal.STATUSES) do
        if s.unclear then unclear[#unclear + 1] = s.name end
    end
    eq(table.concat(unclear, " "), "Blind", "Blind's entry has unclear = true, no other")
    eq(Journal.mark_unclear("Blind", "Ослепление"), "Ослепление ?", "Blind")
    eq(Journal.mark_unclear("Blind", "Blindness"), "Blindness ?", "Blind in English")
    eq(Journal.mark_unclear("Sleep", "Сон"), "Сон", "another status as it is")
    eq(Journal.mark_unclear("Stun", "Stun"), "Stun", "a name that is no entry as it is")
    eq(Journal.mark_unclear(nil, "x"), "x", "no name"); eq(Journal.mark_unclear(5, "5"), "5", "a number")
end)

test("no enemy data: «нет данных»", function()
    for _, sel in ipairs({ 2, 3, 4 }) do
        local c = card(F.snap, sel)
        eq(c.game.data, false, "sel " .. sel .. ": no data")
        eq(#c.game.weak + #c.game.resist + #c.game.immune, 0, "sel " .. sel .. ": no tags")
        eq(c.game.defence, nil, "sel " .. sel .. ": no defence")
    end
    local c = card(F.snap, 2)
    eq(labels(c.types.rows), "Режущий | Лёд", "the measured types still listed")
    eq(c.types.empty, nil, "not empty")
end)

test("a broken or partial enemy record", function()
    local _, snap = F.build()
    snap.detail.kinds.c2300 = { weak = "x", resist = 32 }
    eq(card(snap, 1).game.data, false, "a flag that is not a number")
    snap.detail.kinds.c2300 = { weak = 130.5, resist = 32 }
    eq(card(snap, 1).game.data, false, "a flag that is not whole")
    snap.detail.kinds.c2300 = { weak = 130.0, resist = 0 }
    local g = card(snap, 1).game
    eq(g.data, true, "whole floats (a loaded history) are flags")
    eq(T.str(g.weak), "Дробящий Свет", "weak"); eq(#g.resist, 0, "no resist")
    eq(T.str(g.immune), "нет данных", "statuses unreadable: said so, not «none»")
    eq(g.defence, nil, "no defence read")
    snap.detail.kinds.c2300 = { weak = 0, resist = 0, enabled = 8388607 + 8388608, magic_defence = 90 }
    g = card(snap, 1).game
    eq(#g.weak, 0, "no weakness"); eq(#g.immune, 0, "every status works")
    eq(g.defence, "Маг. защита 90", "only the magic defence")
    snap.detail.kinds.c2300 = "broken"
    eq(card(snap, 1).game.data, false, "not a table")
end)

test("types with the applied multiplier and the game's scale", function()
    local types = card(F.snap, 1).types
    eq(types.title, "Чем его били", "title")
    eq(types.empty, nil, "rows")
    local rows = types.rows
    eq(#rows, 3, "Slash, Fire, Shoot")
    local want = {
        { "Режущий", "74 300", "×1,0", "normal", nil, 1 },
        { "Огонь", "600", "×1,5", "effective", "хорошо", 600 / 74300 },
        { "Стрелковый", "100", "×1,0", "normal", nil, 100 / 74300 },
    }
    for i, w in ipairs(want) do
        eq(rows[i].label, w[1], "label " .. i); eq(rows[i].value, w[2], "value " .. i)
        eq(rows[i].mult, w[3], "mult " .. i); eq(rows[i].eff, w[4], "eff " .. i)
        eq(rows[i].eff_text, w[5], "eff_text " .. i); near(rows[i].fill, w[6], 1e-9, "fill " .. i)
    end
    local ice = card(F.snap, 4).types.rows[1]
    eq(ice.label, "Лёд", "lizard: ice"); eq(ice.value, "400", "value")
    eq(ice.mult, "×0,4", "mult"); eq(ice.eff, "resist", "eff"); eq(ice.eff_text, "плохо", "text")

    local f = F.build()
    F.hit(f, 80, nil, F.LIZ2, 7200, 7150, { skill = { status = "Poison" }, status = "Poison" })
    F.hit(f, 81, F.TORI, F.LIZ2, 7150, 7150,
        { skill = F.NORMAL, region = F.region({ Slash = 100 }, { Slash = 0 }, "body") })
    rows = card(f:snapshot(255, true), 4).types.rows
    eq(labels(rows), "Лёд | Урон от состояния | Режущий", "by value")
    eq(rows[2].value, "50", "the DoT tick"); eq(rows[2].mult, "", "no region step: no multiplier")
    eq(rows[2].eff, nil, "no scale"); eq(rows[2].eff_text, nil, "no word")
    eq(rows[3].value, "0", "absorbed"); eq(rows[3].mult, "×0,0", "nothing went through")
    eq(rows[3].eff, "invalid", "invalid"); eq(rows[3].eff_text, "не действует", "text")

    local en = card(F.snap, 1, "en").types.rows[2]
    eq(en.mult, "×1.5", "English multiplier"); eq(en.eff_text, "good", "English word")
end)

test("the multiplier shown and its scale word come from one rounding", function()
    local _, snap = F.build()
    local slash = snap.detail.foes.a10.types.Slash
    slash.before, slash.after = 1000, 1496 -- 1.496 shows as ×1,5 (rounded up), so it is «хорошо»
    local row = card(snap, 1).types.rows[1]
    eq(row.mult, "×1,5", "shown"); eq(row.eff, "effective", "scale of the shown value")
    eq(row.eff, Ledger.efficacy(1.496), "Ledger.efficacy agrees")
    slash.before, slash.after = 1000, 1494.9
    row = card(snap, 1).types.rows[1]
    eq(row.mult, "×1,49", "two decimals"); eq(row.eff, "normal", "below 1,5")
    slash.before, slash.after = 0, 500
    row = card(snap, 1).types.rows[1]
    eq(row.mult, "", "no before: no multiplier"); eq(row.eff, nil, "no scale")
    slash.before, slash.after = math.huge, math.huge
    row = card(snap, 1).types.rows[1]
    eq(row.mult, "", "not finite: no multiplier"); eq(row.eff, nil, "no scale")
end)

test("head and body line: one damage type hit on both, only when they differ", function()
    -- the ogre's head took the arrows (Shoot, Fire), its body the blades (Slash): no type on both, no line (in game
    -- the hobgoblin's «голова ×0,8 · туловище ×1,32» was only the lightning on its body)
    eq(card(F.snap, 1).types.parts, nil, "ogre: the parts were hit by different types")
    eq(card(F.snap, 4).types.parts, nil, "no part known")
    local f = F.build()
    F.hit(f, 80, F.TORI, F.LIZ2, 7200, 7100,
        { skill = F.NORMAL, region = F.region({ Slash = 100 }, { Slash = 150 }, "head") })
    eq(card(f:snapshot(255, true), 4).types.parts, nil, "only the head")
    F.hit(f, 81, F.TORI, F.LIZ2, 7100, 7000,
        { skill = F.NORMAL, region = F.region({ Slash = 100 }, { Slash = 100 }, "other") })
    eq(card(f:snapshot(255, true), 4).types.parts, "Режущий: голова ×1,5 · туловище ×1,0", "slash on both")
    eq(card(f:snapshot(255, true), 4, "en").types.parts, "Slash: head ×1.5 · body ×1.0", "English")
    -- the type with the most damage among those hit on both parts; its line only
    F.hit(f, 82, F.GUTS, F.LIZ2, 7000, 6000, { skill = { id = "Job03_Frigor" }, element = "Ice",
        region = F.region({ Magic = 500 }, { Magic = 1000 }, "head") })
    F.hit(f, 83, F.GUTS, F.LIZ2, 6000, 5000, { skill = { id = "Job03_Frigor" }, element = "Ice",
        region = F.region({ Magic = 1000 }, { Magic = 1000 }, "body") })
    eq(card(f:snapshot(255, true), 4).types.parts, "Лёд: голова ×2,0 · туловище ×1,0", "ice took the most")
    F.hit(f, 84, F.GUTS, F.LIZ2, 5000, 3000, { skill = { id = "Job03_Frigor" }, element = "Ice",
        region = F.region({ Magic = 1500 }, { Magic = 4000 }, "body") })
    eq(card(f:snapshot(255, true), 4).types.parts, nil, "ice ×2,0 on both: no line, and not slash's either")
    -- a type with damage on one part only does not count, however much it took
    f = Fight.new(0)
    F.hit(f, 1, F.TORI, F.LIZ1, 7600, 7500, { skill = F.NORMAL, region = F.region({ Slash = 100 }, { Slash = 80 }, "head") })
    F.hit(f, 2, F.TORI, F.LIZ1, 7500, 7400, { skill = F.NORMAL, region = F.region({ Slash = 100 }, { Slash = 100 }, "body") })
    F.hit(f, 3, F.GUTS, F.LIZ1, 7400, 4400, { skill = { id = "Job03_Frigor" }, element = "Thunder",
        region = F.region({ Magic = 2000 }, { Magic = 3000 }, "body") })
    eq(card(f:snapshot(10, true), 1).types.parts, "Режущий: голова ×0,8 · туловище ×1,0", "lightning on the body only")
end)

test("head and body line of a kind sums its members per type", function()
    local f = Fight.new(0)
    F.hit(f, 1, F.TORI, F.LIZ1, 7600, 7500, { skill = F.NORMAL, region = F.region({ Slash = 100 }, { Slash = 130 }, "head") })
    F.hit(f, 2, F.TORI, F.LIZ2, 7600, 7500, { skill = F.NORMAL, region = F.region({ Slash = 100 }, { Slash = 100 }, "body") })
    F.hit(f, 3, F.TORI, F.LIZ2, 7500, 7400, { skill = F.NORMAL, region = F.region({ Slash = 100 }, { Slash = 140 }, "head") })
    local snap = f:snapshot(10, true)
    eq(Journal.enemies(snap, F.ctx("ru"), 1).list.rows[1].group, true, "the kind row")
    eq(card(snap, 1).types.parts, "Режущий: голова ×1,35 · туловище ×1,0", "both lizards' heads, one body")
    eq(card(snap, 2).types.parts, nil, "the first lizard: its head only")
    eq(card(snap, 3).types.parts, "Режущий: голова ×1,4 · туловище ×1,0", "the second one alone")
end)

test("a history.json fight without the per-type parts shows no head and body line", function()
    local f = Fight.new(0)
    F.hit(f, 1, F.TORI, F.LIZ1, 7600, 7500, { skill = F.NORMAL, region = F.region({ Slash = 100 }, { Slash = 130 }, "head") })
    F.hit(f, 2, F.TORI, F.LIZ1, 7500, 7400, { skill = F.NORMAL, region = F.region({ Slash = 100 }, { Slash = 100 }, "body") })
    local loaded = HistoryFile.unpack({ json_decode(HistoryFile.encode_fight(f:snapshot(10, true))) })[1]
    eq(card(loaded, 1).types.parts, "Режущий: голова ×1,3 · туловище ×1,0", "the file keeps the per-type parts")
    -- a foe of a file written before: the parts summed over the types, no by_part
    local foe = loaded.detail.foes[F.LIZ1.key]
    foe.by_part = nil
    foe.parts = { head = { before = 100, after = 130 }, body = { before = 100, after = 100 } }
    local ok, c = pcall(card, loaded, 1)
    eq(ok, true, "no error: " .. tostring(c))
    eq(c.types.parts, nil, "no line"); eq(labels(c.types.rows), "Режущий", "the rest of the card as before")
    foe.by_part = { head = "broken", body = { Slash = { before = "x" } } }
    eq(card(loaded, 1).types.parts, nil, "a damaged by_part: no line, no error")
end)

test("who dealt what: party first, allies grey, every row's share of what the enemy took", function()
    local who = card(F.snap, 1).who
    eq(who.title, "Кто чем нанёс", "title")
    eq(who.total, "74 500", "the party's damage to it")
    local r = who.rows
    eq(#r, 6, "three dealers, each with one skill")
    -- the ogre took 75 000: Torinald 73 800, Guts 700, Leo 500
    local want = {
        { kind = "who", key = "a2", name = "Torinald", job_label = "Вор", actor_kind = "pawn", order = 1, job = 4,
          shade = 1, hits = "2", value = "73 800", share = "98%", grey = false, fill = 1 },
        { kind = "skill", label = "Обычные атаки · Режущий", name = "Обычные атаки", type_text = "Режущий", hits = "2",
          value = "73 800", share = "98%", avg = "36 900", max = "72 800", mult = "×1,0", mult_value = 1,
          eff = "normal" },
        { kind = "who", key = "a1", name = "Guts", job_label = "Лучник", actor_kind = "player", job = 2, shade = 1,
          hits = "1", value = "700", share = "1%", grey = false, fill = 700 / 73800 },
        { kind = "skill", label = "Дождь стрел · Огонь", name = "Дождь стрел", type_text = "Огонь", hits = "1",
          value = "700", share = "1%", avg = "700", max = "700", mult = "×1,4", eff = "normal" },
        { kind = "who", key = "a3", name = "Leo", actor_kind = "ally", value = "500", share = "1%", grey = true,
          fill = 500 / 73800 },
        { kind = "skill", label = "Обычные атаки · Режущий", value = "500", share = "1%", mult = "×1,0" },
    }
    for i, w in ipairs(want) do
        for field, value in pairs(w) do eq(r[i][field], value, "row " .. i .. " " .. field) end
    end
    near(r[4].mult_value, 1.4, 1e-9, "the multiplier as shown, a number")
    eq(r[2].eff_text, nil, "normal: no word")
    eq(r[5].job_label, nil, "an ally has no vocation")
    -- a skill row without a damage type: its name alone
    local f = Fight.new(0)
    F.hit(f, 1, F.GUTS, F.OGRE, 75000, 74000, { skill = { id = "Job02_ThreefoldArrow" } })
    local snap = f:snapshot(5, true)
    for _, sk in pairs(snap.detail.foes[F.OGRE.key].by[F.GUTS.key].skills) do sk.types = nil end -- a fight kept before them
    local skill = card(snap, 1).who.rows[2]
    eq(skill.label, "Дождь стрел", "the name"); eq(skill.name, "Дождь стрел", "name"); eq(skill.type_text, nil, "no type")
    eq(skill.mult, "", "no region step"); eq(skill.mult_value, nil, "no number")
end)

test("a kind's members: the killed by when they died, the first first, then the living; each with its line", function()
    local function goblin(key)
        return { key = key, name = key, kind = "enemy", base_id = "ch221002_00", chara_id = 2210, max_hp = 8000 }
    end
    local g1, g2, g3, g4 = goblin("g1"), goblin("g2"), goblin("g3"), goblin("g4")
    local f = Fight.new(0)
    F.hit(f, 1, F.TORI, g1, 8000, 7000, { skill = F.NORMAL }) -- g1 lives
    F.hit(f, 2, F.GUTS, g3, 8000, 0, { skill = F.NORMAL })    -- g3 dies at 0:02
    F.hit(f, 3, F.TORI, g4, 8000, 7900, { skill = F.NORMAL }) -- g4 lives
    F.hit(f, 18, F.TORI, g2, 8000, 0, { skill = F.NORMAL })   -- g2 dies at 0:18
    local snap = f:snapshot(20, true)
    local m = Journal.enemies(snap, F.ctx("ru"), 1)
    local ids = {}
    for i, r in ipairs(m.list.rows) do ids[i] = r.id end
    eq(table.concat(ids, " "), "k:c2210 e:g3 e:g2 e:g1 e:g4", "the list: killed first by time, the living by key")
    local d = m.card.deaths
    eq(#d, 4, "a line per member")
    eq(d[1].line, "0:02 · 8 000 HP · добил Guts", "first killed first")
    eq(d[2].line, "0:18 · 8 000 HP · добил Torinald", "then the next")
    eq(d[3].line, "7 000 / 8 000 HP", "a living one: its HP"); eq(d[4].line, "7 900 / 8 000 HP", "by key")
    eq(d[1].killed, true, "killed"); eq(d[3].killed, false, "alive")
    eq(d[1].killer.name, "Guts", "who finished it"); eq(d[1].killer.kind, "player", "his kind")
    eq(d[1].killer.job, 2, "job"); eq(d[1].killer.shade, 1, "shade")
    eq(d[2].killer.kind, "pawn", "Torinald"); eq(d[3].killer, nil, "nobody finished a living one")
    eq(d[1].text, "8 000 HP · убит на 0:02 · добил Guts", "the text as before")
    eq(d[1].label, "Ящер", "the name")
    -- a killed one without a time after those with one; a kill nobody is known for has no killer
    snap.enemies.g3.killed_at = nil
    snap.enemies.g2.killer = nil
    d = Journal.enemies(snap, F.ctx("ru"), 1).card.deaths
    eq(d[1].line, "0:18 · 8 000 HP", "the timed kill first, no killer"); eq(d[1].killer, nil, "nobody")
    eq(d[2].line, "8 000 HP · добил Guts", "then the one without a time")
    eq(Journal.enemies(snap, F.ctx("en"), 1).card.deaths[2].line, "8 000 HP · finished by Guts", "English")
    -- one enemy's card: who finished it
    local c = card(F.snap, 1)
    eq(c.killer.name, "Torinald", "the ogre's killer"); eq(c.killer.kind, "pawn", "his kind"); eq(c.killer.job, 4, "job")
    eq(card(F.snap, 4).killer, nil, "a living lizard")
end)

test("who_of: the name, kind, job and shade of an actor key; the party's shades once per card", function()
    local ctx = F.ctx("ru")
    local cache = {}
    local w = Journal.who_of(F.snap, F.TORI.key, ctx, cache)
    eq(w.name, "Torinald", "name"); eq(w.kind, "pawn", "kind"); eq(w.job, 4, "job"); eq(w.shade, 1, "shade")
    w = Journal.who_of(F.snap, F.OGRE.key, ctx, cache)
    eq(w.name, "Огр", "an enemy by the game's name"); eq(w.kind, "enemy", "kind"); eq(w.shade, nil, "no shade")
    w = Journal.who_of(F.snap, "nobody", ctx, cache)
    eq(w.name, "Прочее", "a key the fight does not know"); eq(w.kind, "other", "Other")
    w = Journal.who_of(F.snap, nil, ctx, cache)
    eq(w.name, "Прочее", "no key"); eq(w.kind, "other", "Other")
    eq(Journal.who_of(F.snap, F.LEO.key, ctx, {}).kind, "ally", "an ally")
    -- a card builds the party's shades once (who dealt what, whom it hit and the killer share them)
    local shades, calls = View.shades, 0
    View.shades = function(snap) calls = calls + 1; return shades(snap) end
    local ok, err = pcall(Journal.enemies, F.snap, ctx, 1)
    View.shades = shades
    eq(ok, true, tostring(err))
    eq(calls, 1, "View.shades once per card")
end)

test("whom it hit: each friend's name, types, colour and fill", function()
    local rows = card(F.snap, 1).attacks.rows
    eq(#rows, 1, "Guts")
    local r = rows[1]
    eq(r.name, "Guts", "name"); eq(r.types, "Дробящий ×5, Огонь ×1", "types")
    eq(r.label, "Guts · Дробящий ×5, Огонь ×1", "label")
    eq(r.kind, "player", "kind"); eq(r.job, 2, "job"); eq(r.shade, 1, "shade"); eq(r.fill, 1, "the top row")
    local f = F.build()
    F.hit(f, 90, F.OGRE, F.TORI, 2400, 2050, { types = { Blow = 350 } })
    F.hit(f, 91, F.OGRE, F.LEO, 1800, 1700, {})
    local snap = f:snapshot(255, true)
    snap.detail.foes[F.OGRE.key].attacks[F.LEO.key].types = {}
    rows = card(snap, 1).attacks.rows
    eq(rows[2].name, "Torinald", "second"); eq(rows[2].fill, 350 / 700, "against the top row")
    eq(rows[3].name, "Leo", "an ally"); eq(rows[3].kind, "ally", "his kind"); eq(rows[3].shade, nil, "no shade")
    eq(rows[3].types, nil, "no types counted"); eq(rows[3].label, "Leo", "the name alone")
end)

test("a skill's label adds a second type that holds at least a quarter", function()
    local f = F.build()
    F.hit(f, 80, F.GUTS, F.LIZ2, 7200, 6200, { skill = { id = "Job02_ThreefoldArrow" }, element = "Fire",
        region = F.region({ Shoot = 300, Enchant = 700 }, { Shoot = 300, Enchant = 700 }) })
    local rows = card(f:snapshot(255, true), 4).who.rows
    eq(labels(rows), "Дождь стрел · Огонь + Стрелковый | Мороз · Лёд", "30 % Shoot is named")
    eq(rows[1].name, "Guts", "the dealer")
end)

test("whom it hit, by type and element", function()
    local a = card(F.snap, 1).attacks
    eq(a.title, "Кого бил сам", "title")
    eq(a.total, "700", "total")
    eq(#a.rows, 1, "one victim")
    eq(a.rows[1].label, "Guts · Дробящий ×5, Огонь ×1", "victim, types by count")
    eq(a.rows[1].value, "700", "value")
    local lizards = card(F.snap, 2).attacks
    eq(#lizards.rows, 0, "the lizards hit nobody"); eq(lizards.total, "0", "total")
end)

test("type counts: the most hits first, ties in type order, counted types only", function()
    local ru = F.ctx("ru").i18n
    eq(Journal.type_counts({ Fire = 1, Blow = 5 }, ru), "Дробящий ×5, Огонь ×1", "by count")
    eq(Journal.type_counts({ Blow = 2, Ice = 2, Slash = 2 }, ru), "Режущий ×2, Дробящий ×2, Лёд ×2", "ties by type order")
    eq(Journal.type_counts({ Blow = 0, Fire = "3", Ice = 1 }, ru), "Лёд ×1", "a zero or non-number count is left out")
    eq(Journal.type_counts({}, ru), "", "no hits"); eq(Journal.type_counts(nil, ru), "", "no types")
    eq(Journal.type_counts({ Blow = 1, Slash = 1 }, F.ctx("en").i18n), "Slash ×1, Blunt ×1", "English")
end)

test("a card shows no row of 0; totals and shares still count everything", function()
    -- in game: «Прочее 0» in «Чем его били», «Зеркальный щит · Прочее ×3 — 0», «Kratos · Прочее ×10, Дробящий ×2»
    local f = F.build()
    F.hit(f, 80, F.GUTS, F.LIZ2, 7200, 7200, { skill = { id = "Job02_Explosive" } }) -- a skill that took no HP
    F.hit(f, 81, F.LEO, F.LIZ2, 7200, 7200, { skill = F.NORMAL })                     -- a dealer who took none
    F.hit(f, 82, F.TORI, F.LIZ2, 7200, 7199.6, { skill = F.NORMAL, types = { Blow = 10 } }) -- 0.4 HP: shows as 0
    F.hit(f, 83, F.LIZ2, F.TORI, 2400, 2400, { types = { Blow = 50 } })              -- a blocked blow
    F.hit(f, 84, F.LIZ2, F.TORI, 2400, 2300, { types = { Slash = 100 } })
    F.hit(f, 85, F.LIZ2, F.GUTS, 1300, 1300, { types = { Blow = 60 } })              -- a victim hit for 0 only
    local c = card(f:snapshot(255, true), 4)
    eq(labels(c.types.rows), "Лёд", "no «Прочее 0», no «Дробящий 0»")
    eq(c.types.rows[1].fill, 1, "the top row")
    eq(#c.who.rows, 2, "Guts and his Frigor: no 0 skill, no dealer of 0")
    eq(c.who.rows[1].name, "Guts", "the dealer"); eq(c.who.rows[2].label, "Мороз · Лёд", "his skill")
    eq(c.who.rows[1].share, "100%", "share"); eq(c.who.total, "400", "the party's total")
    eq(#c.attacks.rows, 1, "a victim hit for 0 only has no row")
    eq(c.attacks.rows[1].label, "Torinald · Режущий ×1", "the blocked blow is not counted")
    eq(c.attacks.total, "100", "total")
    eq(Journal.shows_zero(0), true, "0"); eq(Journal.shows_zero(0.49), true, "0.49")
    eq(Journal.shows_zero(0.5), false, "0.5 shows as 1"); eq(Journal.shows_zero(0 / 0), true, "NaN")
    eq(Journal.shows_zero(nil), true, "nil")
    -- an enemy that took only hits of 0: there were hits, no damage; no empty block
    local WOLF = { key = "a13", name = "ch221001_00", kind = "enemy", base_id = "ch221001_00", chara_id = 2211,
                   max_hp = 3000 }
    f = Fight.new(0)
    F.hit(f, 1, F.GUTS, WOLF, 3000, 3000, { skill = { id = "Job02_ThreefoldArrow" } })
    c = card(f:snapshot(5, true), 1)
    eq(#c.types.rows, 0, "no rows"); eq(c.types.empty, "Урона не было", "hits, but no damage")
    eq(#c.who.rows, 0, "no who rows"); eq(c.who.empty, "Урона не было", "the who block says so too")
    eq(c.who.total, "0", "total")
    eq(card(f:snapshot(5, true), 1, "en").types.empty, "No damage", "English")
end)

test("a row of 0 is kept when its multiplier says «не действует»", function()
    -- three fire spells fully absorbed (500 -> 0, no HP taken): the type, the skill and its dealer stay
    local f = Fight.new(0)
    F.hit(f, 1, F.TORI, F.LIZ1, 7600, 7000, { skill = F.NORMAL, region = F.region({ Slash = 600 }, { Slash = 600 }, "body") })
    for i = 1, 3 do
        F.hit(f, 1 + i, F.GUTS, F.LIZ1, 7000, 7000, { skill = { id = "Job03_Frigor" }, element = "Fire",
            region = F.region({ Magic = 500 }, { Magic = 0 }, "body") })
    end
    local c = card(f:snapshot(10, true), 1)
    eq(labels(c.types.rows), "Режущий | Огонь", "the fire row of 0")
    local fire = c.types.rows[2]
    eq(fire.value, "0", "value"); eq(fire.mult, "×0,0", "mult"); eq(fire.eff, "invalid", "eff")
    eq(fire.eff_text, "не действует", "its word")
    eq(c.types.empty, nil, "not empty")
    eq(#c.who.rows, 4, "Torinald and his skill, Guts and his")
    local guts, frigor = c.who.rows[3], c.who.rows[4]
    eq(guts.kind, "who", "Guts' row kept for his skill"); eq(guts.name, "Guts", "Guts")
    eq(guts.value, "0", "value"); eq(guts.hits, "3", "hits"); eq(guts.share, "0%", "share")
    eq(frigor.label, "Мороз · Огонь", "his skill"); eq(frigor.value, "0", "value"); eq(frigor.hits, "3", "hits")
    eq(frigor.mult, "×0,0", "mult"); eq(frigor.eff_text, "не действует", "its word")
    eq(c.who.total, "600", "total"); eq(c.who.rows[1].share, "100%", "Torinald's share")
    eq(c.who.empty, nil, "rows, no empty text")

    -- one hit: its slash part absorbed (100 -> 0), its fire part through (100 -> 150), 150 HP taken
    f = Fight.new(0)
    F.hit(f, 1, F.TORI, F.LIZ1, 7600, 7450, { skill = F.NORMAL, element = "Fire",
        region = F.region({ Slash = 100, Magic = 100 }, { Slash = 0, Magic = 150 }, "body") })
    c = card(f:snapshot(10, true), 1)
    eq(labels(c.types.rows), "Огонь | Режущий", "both types")
    eq(c.types.rows[1].value, "150", "fire"); eq(c.types.rows[1].eff_text, "хорошо", "×1,5")
    local slash = c.types.rows[2]
    eq(slash.value, "0", "slash took none of the HP"); eq(slash.mult, "×0,0", "mult")
    eq(slash.eff_text, "не действует", "its word")
    eq(c.who.rows[2].mult, "×0,75", "the skill row: both parts"); eq(c.who.rows[2].value, "150", "value")

    -- still hidden: hits of 0 with no type part (a grab, a blocked blow), blows on the corpse at ×1,0
    f = Fight.new(0)
    F.hit(f, 1, F.TORI, F.LIZ1, 7600, 7000, { skill = F.NORMAL, region = F.region({ Slash = 600 }, { Slash = 600 }, "body") })
    F.hit(f, 2, F.LEO, F.LIZ1, 7000, 7000, { skill = { id = "Job01_Mirror" } })
    F.hit(f, 3, F.TORI, F.LIZ1, 7000, 7000, { skill = { id = "Job01_Mirror" } })
    F.hit(f, 4, F.TORI, F.LIZ1, 7000, 0, { skill = F.NORMAL, region = F.region({ Slash = 7000 }, { Slash = 7000 }, "body") })
    for i = 1, 3 do
        F.hit(f, 4 + i, F.GUTS, F.LIZ1, 0, 0, { skill = { id = "Job02_ThreefoldArrow" },
            region = F.region({ Shoot = 100 }, { Shoot = 100 }, "head") })
    end
    c = card(f:snapshot(10, true), 1)
    eq(labels(c.types.rows), "Режущий", "no «Прочее 0», no «Стрелковый 0 ×1,0»")
    eq(#c.who.rows, 2, "Torinald and his normal attacks only")
    eq(c.who.rows[1].name, "Torinald", "Torinald"); eq(c.who.rows[2].label, "Обычные атаки · Режущий", "his skill")
    eq(c.types.parts, nil, "no line: slash on the body only")
end)

test("killed at and by", function()
    eq(card(F.snap, 1).sub, "75 000 HP · убит на 4:12 · добил Torinald", "ogre")
    eq(card(F.snap, 3).sub, "7 600 HP · убит на 1:02 · добил Torinald", "first lizard")
    eq(card(F.snap, 4).sub, "7 200 / 7 600 HP", "alive")
    eq(card(F.snap, 1, "en").sub, "75 000 HP · killed at 4:12 · finished by Torinald", "English")
    local f = F.build()
    F.hit(f, 90, nil, F.LIZ2, 7200, 0, { skill = { status = "FireSpread" }, status = "FireSpread" })
    eq(card(f:snapshot(255, true), 4).sub, "7 600 HP · убит на 1:30 · добил Прочее", "a DoT tick nobody applied")
end)

-- An enemy's own damage (a fall) is «Падения и среда», a grey dealer of its own beside Other.
test("a card: the enemy's own damage is a grey «Падения и среда» row, and its kill is that row's", function()
    local f = Fight.new(0)
    F.hit(f, 1, F.TORI, F.LIZ1, 7600, 7000, { skill = F.NORMAL, types = { Slash = 600 } })
    F.hit(f, 2, nil, F.LIZ1, 7000, 6000, { own = "self", types = { Fixed = 1000 } })
    F.hit(f, 3, nil, F.LIZ1, 6000, 5900, { status = "Poison", skill = { status = "Poison" } })
    F.hit(f, 4, nil, F.LIZ1, 5900, 0, { own = "self", types = { Fixed = 5900 } })
    f:finish(10, "win")
    local c = card(f:snapshot(10, true), 1)
    local dealers = {}
    for _, r in ipairs(c.who.rows) do
        if r.kind == "who" then dealers[#dealers + 1] = r end
    end
    eq(#dealers, 3, "three dealers")
    local names, grey, kinds = {}, {}, {}
    for i, r in ipairs(dealers) do names[i], grey[i], kinds[i] = r.name, tostring(r.grey), r.actor_kind end
    eq(table.concat(names, " | "), "Torinald | Падения и среда | Прочее", "the party, the fall a grey dealer, Other last")
    eq(table.concat(grey, " | "), "false | true | true", "the pseudo-actors are grey")
    eq(table.concat(kinds, " | "), "pawn | other | other", "their kind")
    eq(dealers[2].value, "6 900", "1 000 and the 5 900 that killed it"); eq(dealers[2].share, "91%", "of all it took")
    eq(c.who.total, "600", "the band's total is the party's")
    eq(c.killer.name, "Падения и среда", "the killer is that row"); eq(c.killer.kind, "other", "a grey one")
    eq(c.sub, "7 600 HP · убит на 0:04 · добил Падения и среда", "the line")
    eq(card(f:snapshot(10, true), 1, "en").killer.name, "Falls and environment", "English")
end)

test("kind card sums its members and lists deaths", function()
    local c = card(F.snap, 2)
    eq(c.title, "Ящер ×2", "title")
    eq(c.sub, "по 7 600 HP · убито: 1 из 2", "the kind row's text")
    local rows = c.types.rows
    eq(labels(rows), "Режущий | Лёд", "types of both")
    eq(rows[1].value, "7 600", "slash"); eq(rows[2].value, "400", "ice")
    eq(rows[2].mult, "×0,4", "ice multiplier")
    eq(#c.deaths, 2, "one line per member")
    eq(c.deaths[1].label, "Ящер", "first"); eq(c.deaths[1].text, "7 600 HP · убит на 1:02 · добил Torinald", "killed")
    eq(c.deaths[2].label, "Ящер", "second"); eq(c.deaths[2].text, "7 200 / 7 600 HP", "alive")
    eq(c.who.total, "8 000", "the party's damage to both")
    eq(c.who.rows[1].name, "Torinald", "first dealer"); eq(c.who.rows[1].share, "95%", "share")
    eq(c.who.rows[3].name, "Guts", "second dealer"); eq(c.who.rows[3].share, "5%", "share")
    eq(c.game.data, false, "no data for the kind")
end)

test("a kind card sums the counters of one skill used on several members", function()
    local f = F.build()
    F.hit(f, 80, F.TORI, F.LIZ2, 7200, 7000, { skill = F.NORMAL, region = F.region({ Slash = 200 }, { Slash = 200 }) })
    local rows = card(f:snapshot(255, true), 2).who.rows
    eq(rows[1].name, "Torinald", "dealer")
    eq(rows[2].label, "Обычные атаки · Режущий", "one skill row")
    eq(rows[2].hits, "2", "a hit on each lizard"); eq(rows[2].value, "7 800", "summed")
    eq(rows[2].max, "7 600", "the biggest"); eq(rows[2].avg, "3 900", "average")
end)

test("an enemy that only hit the party", function()
    local f = F.build()
    local WOLF = { key = "a13", name = "ch221001_00", kind = "enemy", base_id = "ch221001_00", chara_id = 2211,
                   max_hp = 3000 }
    F.hit(f, 100, WOLF, F.GUTS, 1300, 1250, { types = { Blow = 50 } })
    local snap = f:snapshot(255, true)
    local m = Journal.enemies(snap, F.ctx("ru"), 5)
    eq(m.list.title, "Враги · 4", "four enemies")
    local row = m.list.rows[5]
    eq(row.id, "e:a13", "the wolf last"); eq(row.label, "Волк", "name")
    eq(row.hp_text, "3 000 / 3 000 HP", "full HP shown"); eq(row.fill, 1, "HP unknown: full bar")
    eq(row.killed, false, "alive")
    local c = m.card
    eq(#c.types.rows, 0, "no types rows"); eq(c.types.empty, "Ударов не было", "said so")
    eq(c.types.parts, nil, "no parts")
    eq(#c.who.rows, 0, "nobody hit it"); eq(c.who.total, "0", "total")
    eq(c.who.empty, nil, "no hits: the window's own text")
    eq(c.attacks.rows[1].label, "Guts · Дробящий ×1", "its hit"); eq(c.attacks.total, "50", "total")
    eq(Journal.header(snap, F.ctx("ru"), 1, 1).line, "Победа · 4:15 · Огр, Ящер ×2, Волк", "header lists it")
end)

test("enemies the game has no name for are «Безымянный враг», each kind its own rows", function()
    -- in game: blood worms out of a wall, ch272002_00, a kind the game gives no name
    local f = Fight.new(0)
    local WORM1 = { key = "a20", name = "ch272002_00_01", kind = "enemy", base_id = "ch272002_00", chara_id = 2722,
                    max_hp = 500 }
    local WORM2 = { key = "a21", name = "ch272002_00_02", kind = "enemy", base_id = "ch272002_00", chara_id = 2722,
                    max_hp = 500 }
    local SPAWN = { key = "a22", name = "ch272000_00_00", kind = "enemy", base_id = "ch272000_00", chara_id = 2720,
                    max_hp = 300 }
    F.hit(f, 1, F.GUTS, F.OGRE, 75000, 74000)
    F.hit(f, 2, F.GUTS, WORM1, 500, 0)
    F.hit(f, 3, F.GUTS, WORM2, 500, 400)
    F.hit(f, 4, F.GUTS, SPAWN, 300, 200)
    F.hit(f, 5, WORM2, F.GUTS, 2000, 1950, { types = { Blow = 50 } })
    f:finish(10, "win")
    local snap = f:snapshot(10, true)
    local ctx = F.ctx("ru")
    local m = Journal.enemies(snap, ctx, 2)
    eq(labels(m.list.rows), "Огр | Безымянный враг ×2 | Безымянный враг | Безымянный враг | Безымянный враг",
        "the named kind, the unnamed kind of two with its members, the other unnamed kind apart")
    eq(m.list.rows[2].id, "k:c2722", "the worms' kind row"); eq(m.list.rows[5].id, "e:a22", "the other kind")
    eq(m.card.title, "Безымянный враг ×2", "the kind card")
    eq(m.card.deaths[1].label, "Безымянный враг", "a member in the card")
    eq(Journal.header(snap, ctx, 1, 1).line, "Победа · 0:10 · Огр, Безымянный враг ×2, Безымянный враг", "header")
    local summary = View.summary(snap, ctx)
    eq(summary.enemies[2].label, "Безымянный враг ×2", "the window's summary row")
    eq(View.live(snap, 10, ctx).taken.rows[1].label, "Безымянный враг → Guts", "who hit whom in the window")
    eq(Journal.enemies(snap, F.ctx("en"), 2).list.rows[2].label, "Unnamed enemy ×2", "English")
end)

test("a snapshot without detail", function()
    local f = F.build()
    local snap = f:snapshot(255)
    eq(snap.detail, nil, "a plain snapshot")
    local ok, m = pcall(Journal.enemies, snap, F.ctx("ru"), 1)
    eq(ok, true, "no error: " .. tostring(m))
    local c = m.card
    eq(#c.types.rows, 0, "no rows"); eq(c.types.empty, "нет данных", "no data")
    eq(c.game.data, false, "no game data")
    eq(#c.who.rows, 0, "no who rows"); eq(#c.attacks.rows, 0, "no attacks")
    eq(c.sub, "75 000 HP · убит на 4:12 · добил Torinald", "the enemy's own entry still tells its death")
    ok, m = pcall(Journal.enemies, snap, F.ctx("ru"), 2)
    eq(ok, true, "kind card: no error")
    eq(m.card.types.empty, "нет данных", "kind card: no data")
    eq(Journal.header(snap, F.ctx("ru"), 1, 1).numbers[1].value, "82 500", "the header needs no detail")
end)

test("type labels, tabs and the game's flag tables", function()
    i18n.set("ru")
    local want = { Slash = "Режущий", Blow = "Дробящий", Shoot = "Стрелковый", Fire = "Огонь", Ice = "Лёд",
                   Thunder = "Молния", Light = "Свет", Dark = "Тьма", Magic = "Магия", Status = "Урон от состояния",
                   Other = "Прочее" }
    for _, jt in ipairs(Ledger.TYPES) do eq(Journal.type_label(jt), want[jt], jt) end
    eq(T.str(Journal.TABS), "summary enemies skills party heal chart record", "tabs")
    for _, tab in ipairs(Journal.TABS) do
        eq(i18n.t("jtab_" .. tab) ~= "jtab_" .. tab, true, "a title for " .. tab)
    end
    local weak = {}
    for _, w in ipairs(Journal.WEAK) do weak[#weak + 1] = w.bit .. "=" .. w.name .. ":" .. w.key end
    eq(table.concat(weak, " "), "1=Slash:type_Slash 2=Blow:type_Blow 4=Shoot:type_Shoot 8=None:type_Magic "
        .. "16=Fire:element_Fire 32=Ice:element_Ice 64=Thunder:element_Thunder 128=Light:element_Light "
        .. "256=Magic:weak_magic_all 512=Physics:weak_physics_all", "WEAK")
    local statuses = {}
    for _, s in ipairs(Journal.STATUSES) do statuses[#statuses + 1] = s.bit .. "=" .. s.name .. ":" .. tostring(s.message) end
    eq(table.concat(statuses, " "), "2=Poison:ui080101_40 128=VirulentPoison:ui080101_41 4=Sleep:ui080101_42 "
        .. "8=Faint:ui080101_43 256=Frostbite:ui080101_37 512=Freeze:ui080101_38 8192=Electric:nil "
        .. "16=Wet:ui080101_47 1024=Oil:ui080101_46 32=FireSpread:ui080101_35 64=OilSpread:ui080101_36 "
        .. "2048=Silence:ui080101_45 4096=Stone:ui080101_44 8388608=Blind:nil", "STATUSES")
    for _, s in ipairs(Journal.STATUSES) do
        eq(i18n.t("status_" .. s.name) ~= "status_" .. s.name, true, "a fallback name for " .. s.name)
    end
end)

test("the models do not modify the snapshot", function()
    local function dump(t, out)
        local keys = {}
        for k in pairs(t) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, k in ipairs(keys) do
            local v = t[k]
            out[#out + 1] = tostring(k) .. "="
            if type(v) == "table" then out[#out + 1] = "{"; dump(v, out); out[#out + 1] = "}"
            else out[#out + 1] = tostring(v) end
        end
        return out
    end
    local before = table.concat(dump(F.snap, {}), ";")
    Journal.header(F.snap, F.ctx("ru"), 1, 1)
    for sel = 1, 4 do Journal.enemies(F.snap, F.ctx("ru"), sel) end
    eq(table.concat(dump(F.snap, {}), ";"), before, "snapshot is untouched")
end)

T.finish()
