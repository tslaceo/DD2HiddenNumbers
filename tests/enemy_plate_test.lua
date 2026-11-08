package.path = "mod/reframework/autorun/?.lua;tests/?.lua;" .. package.path

local T = require("testlib")
local test, eq, near = T.test, T.eq, T.near
local ui = require("stubs/ui").install()
local i18n = require("DD2DamageMeter/i18n")
local Settings = require("DD2DamageMeter/settings")
local PlateModel = require("DD2DamageMeter/plate_model")
local Journal = require("DD2DamageMeter/journal")
local EnemyBars = require("DD2DamageMeter/ui/enemy_bars")
local EnemyPlate = require("DD2DamageMeter/ui/enemy_plate")
local SceneText = require("DD2DamageMeter/ui/scene_text")

local C = EnemyPlate.COLORS

-- The plate's ImU32 colours (0xAABBGGRR).
local NAME, WEAK, RESIST, IMMUNE, YOU, PLAIN = 0xFFB2DBEA, 0xFF6AD18F, 0xFF7A8AE0, 0xFF9A9A9A, 0xFFF0C89C, 0xFFD0E2E8
local BACK, BORDER = 0x8C000000, 0xFF4A4A4A

-- The boss bar as game/gauges.lua gives it: the probes' on 3440 × 1440, and on 1920 × 1080 (All not moved).
local WIDE = { x = 665.3, y = 109.5, width = 776 }
local FULL_HD = { x = 564, y = 109.5, width = 776 }

local function make_settings(over)
    local saved = over or {}
    return Settings.load({ read = function() return saved end, write = function(t) saved = t end })
end

local function fresh(over)
    ui.reset()
    EnemyPlate.reset()
    i18n.set("ru")
    return make_settings(over)
end

-- Every status but these, as an enabled mask.
local function enabled_without(...)
    local off, mask = {}, 0
    for _, name in ipairs({ ... }) do off[name] = true end
    for _, s in ipairs(Journal.STATUSES) do
        if not off[s.name] then mask = mask | s.bit end
    end
    return mask
end

-- Every status's name, in the journal's order.
local function every_status()
    local immune = {}
    for _, st in ipairs(Journal.STATUSES) do immune[#immune + 1] = st.name end
    return immune
end

-- A kind near the player as PlateModel.build takes it, with this body and parts (no body: no table read).
local function kind(id, name, count, body, parts, enabled)
    return { chara_id = id, name = name, count = count, enabled = enabled,
        table = body and { chara_id = id, state = "Normal", body = body, parts = parts or {} } or nil }
end

local function build(kinds, weapon, boss_id)
    return PlateModel.new():build(1, kinds, weapon, boss_id)
end

-- A Row of the model made by hand; `o` overrides any field.
local function row(id, name, count, o)
    local r = { chara_id = id, name = name, count = count, known = false, types = {}, parts = {}, part_rows = {},
        immune = {} }
    for f, v in pairs(o or {}) do r[f] = v end
    return r
end

local ALL_ONE = { Slash = 1, Blow = 1, Shoot = 1, Magic = 1, Fire = 1, Ice = 1, Thunder = 1, Light = 1 }

-- A screenshot from the game: the Norgan giant under its boss bar and a snow ogre, their tables as the collector
-- read them, hit with a slashing weapon.
local NORGAN, SNOW_OGRE = 2501, 2510
local GIANT_BODY = { Slash = 0.8, Blow = 0.8, Shoot = 0.8, Fire = 1.0, Ice = 0.4, Thunder = 0.8, Light = 0.8, Magic = 0.8 }
local GIANT_PARTS = {
    { kind = "head", mult = { Slash = 0.8, Blow = 0.8, Shoot = 1.2, Fire = 1.2, Ice = 0.4, Thunder = 0.8, Light = 0.8,
        Magic = 0.8 } },
    { kind = "weak", mult = { Slash = 1.5, Blow = 1.5, Shoot = 0.8, Fire = 1.2, Ice = 0.6, Thunder = 0.8, Light = 0.8,
        Magic = 0.8 } },
}
local OGRE_BODY = { Slash = 0.6, Blow = 0.6, Shoot = 0.6, Fire = 0.4, Ice = 0.6, Thunder = 0.75, Light = 0.6, Magic = 0.6 }
local OGRE_PARTS = {
    { kind = "weak", mult = { Slash = 1.0, Blow = 1.0, Shoot = 1.0, Fire = 0.8, Ice = 1.0, Thunder = 1.2, Light = 1.0,
        Magic = 1.0 } },
}

local function giant_plate(o)
    local plate = build({ kind(NORGAN, "Норганский великан", 1, GIANT_BODY, GIANT_PARTS, enabled_without("Blind")),
        kind(SNOW_OGRE, "Снежный огр", 1, OGRE_BODY, OGRE_PARTS, enabled_without("Sleep")) }, { phys = "Slash" }, NORGAN)
    for f, v in pairs(o or {}) do plate[f] = v end
    return plate
end

-- A crowd without a boss: goblins with no table read, hobgoblins whose head takes fire, an ogre; hit with a slashing
-- weapon.
local GOBLIN, HOBGOBLIN, OGRE, NOKKEN = 2200, 2201, 2210, 2240
local HOB_BODY = { Slash = 1, Blow = 1, Shoot = 1, Fire = 0.8, Ice = 1, Thunder = 1.2, Light = 1, Magic = 1 }
local HOB_HEAD = { { kind = "head", mult = { Fire = 1.2 } } }
local OGRE_PLAIN = { Slash = 0.8, Blow = 1, Shoot = 1, Fire = 1.5, Ice = 1, Thunder = 1, Light = 1, Magic = 1 }
local function crowd_plate(more)
    local plate = build({ kind(GOBLIN, "Гоблин", 5),
        kind(HOBGOBLIN, "Хобгоблин", 2, HOB_BODY, HOB_HEAD, enabled_without("Poison")),
        kind(OGRE, "Огр", 1, OGRE_PLAIN, nil, enabled_without("Sleep")) }, { phys = "Slash" })
    plate.more = more or 0
    return plate
end

local function text_of(line)
    local out = {}
    for _, seg in ipairs(line) do out[#out + 1] = seg[1] end
    return table.concat(out)
end

-- A table row as text: its label (indented by two spaces), " | ", then its cells or its note.
local function row_text(r)
    local right = {}
    for _, c in ipairs(r.cells or {}) do right[#right + 1] = c[1] end
    if r.note then right[#right + 1] = r.note[1] end
    return (r.indent and "  " or "") .. (r.label and r.label[1] or "") .. " | " .. table.concat(right, " ")
end

-- The columns of a row's underlined cells, "Slash Blow"; "" with none.
local function best_of(r)
    local out = {}
    for i, c in ipairs(r.cells or {}) do
        if c.best then out[#out + 1] = EnemyPlate.COLUMNS[i] end
    end
    return table.concat(out, " ")
end

-- A row's cell colours, a letter each: n(ame) w(eak) r(esist) i(mmune, the grey) y(ou) p(lain).
local LETTER = { name = "n", weak = "w", resist = "r", immune = "i", you = "y", plain = "p" }
local function colors_of(r)
    local out = {}
    for _, c in ipairs(r.cells or {}) do out[#out + 1] = LETTER[c[2]] or "?" end
    return table.concat(out)
end

local function starts(s, prefix)
    return s:sub(1, #prefix) == prefix
end

-- The width the stub gives `text` at `px`.
local function width(text, px)
    return utf8.len(text) * ui.char_w * px / 14
end

-- The stub's measure at any font size, as EnemyPlate.layout takes it.
local function measure_at(text, px)
    return width(text, px), px
end

local function round(v)
    return math.floor(v + 0.5)
end

-- The table -------------------------------------------------------------------------------------------------

test("the screenshot's giant and ogre as a table: the header, a body row and part rows per kind, «·» as the body",
    function()
    i18n.set("ru")
    local rows = EnemyPlate.rows(giant_plate())
    eq(#rows, 6, "the header, the giant's three rows, the ogre's two")
    eq(row_text(rows[1]), " | Реж Дроб Стрел Огонь Лёд Молн Свет Маг", "the header: the short names, in their order")
    eq(rows[1].label, nil, "no label over the names"); eq(colors_of(rows[1]), "iiiiiiii", "grey")
    eq(row_text(rows[2]), "Норганский великан | 0,8 0,8 0,8 1,0 0,4 0,8 0,8 0,8",
        "the boss first, its body: every column, ×1,0 too, no ×")
    eq(rows[2].label[2], "name", "its name in the name colour"); eq(rows[2].indent, nil, "not indented")
    eq(colors_of(rows[2]), "rrrprrrr", "each cell by its direction, ×1,0 plain")
    eq(row_text(rows[3]), "  слабое место | 1,5 1,5 · 1,2 0,6 · · ·", "its weak spot: «·» where as the body")
    eq(rows[3].label[2], "immune", "the label grey"); eq(rows[3].indent, true, "indented")
    eq(colors_of(rows[3]), "wwiwriii", "its values by direction, the «·» grey")
    eq(row_text(rows[4]), "  голова | · · · 1,2 · · · ·", "its head: Shoot «·» as always (open question 2)")
    eq(row_text(rows[5]), "Снежный огр | 0,6 0,6 0,6 0,4 0,6 0,75 0,6 0,6", "the ogre")
    eq(row_text(rows[6]), "  слабое место | 1,0 1,0 · 0,8 1,0 1,2 1,0 1,0", "its weak spot")
    eq(colors_of(rows[6]), "ppirpwpp", "its ×1,0 plain, the ×0,8 red, the ×1,2 green")
end)

test("the best of each row is underlined, each of a tie, none when all are equal; a «·» counts the body's",
    function()
    local rows = EnemyPlate.rows(giant_plate())
    eq(best_of(rows[1]), "", "the header none")
    eq(best_of(rows[2]), "Fire", "the giant's body: Fire ×1,0, the best type against it")
    eq(best_of(rows[3]), "Slash Blow", "its weak spot: both ×1,5")
    eq(best_of(rows[4]), "Fire", "its head: Fire ×1,2 over the body's ×0,8")
    eq(best_of(rows[5]), "Thunder", "the ogre's body: ×0,75")
    eq(best_of(rows[6]), "Thunder", "its weak spot: ×1,2")
    -- a «·» whose body value is the part's best
    local body = { Slash = 1.2, Blow = 1, Shoot = 1, Fire = 1.2, Ice = 1, Thunder = 1, Light = 1, Magic = 1 }
    rows = EnemyPlate.rows(build({ kind(OGRE, "Огр", 1, body, { { kind = "head", mult = { Fire = 0.5 } } }),
        kind(NOKKEN, "Нёккен", 1, ALL_ONE) }))
    eq(row_text(rows[2]), "Огр | 1,2 1,0 1,0 1,2 1,0 1,0 1,0 1,0", "the ogre")
    eq(best_of(rows[2]), "Slash Fire", "a tie: both")
    eq(row_text(rows[3]), "  голова | · · · 0,5 · · · ·", "its head takes less fire")
    eq(best_of(rows[3]), "Slash", "the head's best: its Slash, as the body's")
    eq(rows[4].label[1], "Нёккен", "then Нёккен"); eq(best_of(rows[4]), "", "every value equal: none")
end)

test("an all-×1 row (Нёккен): every cell 1,0 plain, none underlined, no part row", function()
    local plate = build({ kind(NOKKEN, "Нёккен", 1, ALL_ONE, nil, enabled_without("Frostbite", "Freeze", "Blind")) },
        { phys = "Slash" })
    local rows = EnemyPlate.rows(plate)
    eq(#rows, 2, "the header and its row")
    eq(row_text(rows[2]), "Нёккен | 1,0 1,0 1,0 1,0 1,0 1,0 1,0 1,0", "every column ×1,0")
    eq(colors_of(rows[2]), "pppppppp", "plain"); eq(best_of(rows[2]), "", "none underlined")
    local lines = EnemyPlate.lines(plate)
    eq(text_of(lines[1]), "Нёккен: не действует Обморожение, Заморозка, Ослепление ?", "its immunities below")
    eq(text_of(lines[2]), "ты: Режущий ×1,0", "you: its number")
end)

test("the immunity line: Blind with « ?» after it, in both languages; another status without, the order kept",
    function()
    local kinds = { kind(OGRE, "Огр", 1, OGRE_PLAIN, nil, enabled_without("Sleep", "Frostbite", "Blind")) }
    i18n.set("ru")
    eq(text_of(EnemyPlate.lines(build(kinds))[1]), "Огр: не действует Сон, Обморожение, Ослепление ?",
        "ru: Blind marked, last as in Journal.STATUSES")
    eq(text_of(EnemyPlate.lines(build({ kind(OGRE, "Огр", 1, OGRE_PLAIN, nil, enabled_without("Sleep")) }))[1]),
        "Огр: не действует Сон", "no Blind: no mark")
    eq(text_of(EnemyPlate.lines(build({ kind(OGRE, "Огр", 1, OGRE_PLAIN, nil, enabled_without("Blind")) }))[1]),
        "Огр: не действует Ослепление ?", "Blind alone, the first of its line")
    i18n.set("en")
    kinds[1].name = "Ogre"
    eq(text_of(EnemyPlate.lines(build(kinds))[1]), "Ogre: immune to Sleep, Frostbite, Blindness ?", "en")
    i18n.set("ru")
end)

test("a row with no table: its name and «нет данных» across the columns; no header without a number", function()
    local rows = EnemyPlate.rows(build({ kind(GOBLIN, "Гоблин", 3), kind(OGRE, "Огр", 1, OGRE_PLAIN) }))
    eq(#rows, 3, "the header, the goblins, the ogre")
    eq(row_text(rows[2]), "Гоблин ×3 | нет данных", "the name with its count, no data")
    eq(rows[2].cells, nil, "no cells"); eq(rows[2].note[2], "immune", "grey")
    eq(rows[2].label[2], "name", "the name in its colour")
    eq(row_text(rows[3]), "Огр | 0,8 1,0 1,0 1,5 1,0 1,0 1,0 1,0", "the ogre's cells")
    -- no row with a number: no header over nothing
    rows = EnemyPlate.rows(build({ kind(GOBLIN, "Гоблин", 3), kind(HOBGOBLIN, "Хобгоблин", 1, {}) }))
    eq(#rows, 2, "no header")
    eq(row_text(rows[1]), "Гоблин ×3 | нет данных", "no table read")
    eq(row_text(rows[2]), "Хобгоблин | нет данных", "an empty body: no data too")
    -- a boss with no table and a count
    rows = EnemyPlate.rows(build({ kind(NORGAN, "Морозный гигант", 2) }, nil, NORGAN))
    eq(row_text(rows[1]), "Морозный гигант ×2 | нет данных", "two of the boss's kind: the count")
end)

test("a column the read lost is «?» in grey and not the best; ×0 is grey; a row's cells in column order",
    function()
    local rows = EnemyPlate.rows(build({ kind(OGRE, "Огр", 1, { Slash = 0, Blow = 1, Fire = 1.5, Magic = 1.2 }) }))
    eq(row_text(rows[2]), "Огр | 0,0 1,0 ? 1,5 ? ? ? 1,2", "the lost columns «?», Magic last")
    eq(colors_of(rows[2]), "ipiwiiiw", "×0 grey, «?» grey")
    eq(best_of(rows[2]), "Fire", "the best of the values read")
    -- a weak part's ×0 cell, and a weak row before a head row whatever the parts' order
    rows = EnemyPlate.rows(build({ kind(OGRE, "Огр", 1, ALL_ONE, { { kind = "head", mult = { Blow = 1.2 } },
        { kind = "weak", mult = { Slash = 2, Fire = 0 } } }) }))
    eq(row_text(rows[3]), "  слабое место | 2,0 · · 0,0 · · · ·", "the weak spot first")
    eq(colors_of(rows[3]), "wiiiiiii", "its ×0 grey")
    eq(row_text(rows[4]), "  голова | · 1,2 · · · · · ·", "then the head")
end)

-- The state next to the name ------------------------------------------------------------------------------------

-- Nёkken's table as the collector read it after its tail was cut.
local NOKKEN_INJURED = { Slash = 4.5, Blow = 4, Shoot = 4, Fire = 6, Ice = 2, Thunder = 4, Light = 4, Magic = 4 }

-- A kind whose table is in `state`.
local function in_state(id, name, count, body, state, parts, enabled)
    local k = kind(id, name, count, body, parts, enabled)
    k.table.state = state
    return k
end

test("a kind's state next to its name when it is not Normal: «Нёккен (ранен)»", function()
    i18n.set("ru")
    local plate = build({ in_state(NOKKEN, "Нёккен", 1, NOKKEN_INJURED, "Injured", nil,
        enabled_without("Frostbite")) }, { phys = "Slash" })
    local rows = EnemyPlate.rows(plate)
    eq(row_text(rows[2]), "Нёккен (ранен) | 4,5 4,0 4,0 6,0 2,0 4,0 4,0 4,0", "the state word after the name")
    eq(rows[2].label[2], "name", "in the name's colour")
    eq(best_of(rows[2]), "Fire", "its injured table's best: Fire ×6")
    local lines = EnemyPlate.lines(plate)
    eq(text_of(lines[1]), "Нёккен (ранен): не действует Обморожение", "the immunity line names it as the table does")
    eq(text_of(lines[2]), "ты: Режущий ×4,5", "you: the injured table's")
    -- Normal: no word; an id with no word: the id itself
    eq(EnemyPlate.rows(build({ in_state(NOKKEN, "Нёккен", 1, ALL_ONE, "Normal") }))[2].label[1], "Нёккен",
        "Normal: no state word")
    eq(EnemyPlate.rows(build({ in_state(NOKKEN, "Нёккен", 1, ALL_ONE, "Foo") }))[2].label[1], "Нёккен (Foo)",
        "an unknown id: as it is")
    eq(EnemyPlate.rows(build({ in_state(GOBLIN, "Гоблин", 1, {}, "Angry") }))[1].label[1], "Гоблин (в ярости)",
        "a row with no data keeps its state")
    -- the words, in both languages
    for _, case in ipairs({ { "Angry", "в ярости", "enraged" }, { "Injured", "ранен", "injured" },
        { "Down", "повален", "downed" }, { "Flight", "в полёте", "flying" },
        { "HeartExposure", "сердце открыто", "heart exposed" } }) do
        local p = build({ in_state(OGRE, "Огр", 3, ALL_ONE, case[1]) })
        eq(EnemyPlate.rows(p)[2].label[1], "Огр ×3 (" .. case[2] .. ")", "ru " .. case[1] .. ", after the count")
        i18n.set("en")
        eq(EnemyPlate.rows(p)[2].label[1], "Огр ×3 (" .. case[3] .. ")", "en " .. case[1])
        i18n.set("ru")
    end
end)

test("Fimbul's second state, HeartExposure, gives «Фимбул (сердце открыто)»", function()
    i18n.set("ru")
    local rows = EnemyPlate.rows(build({ in_state(NORGAN, "Фимбул", 1, ALL_ONE, "HeartExposure") }, nil, NORGAN))
    eq(rows[2].label[1], "Фимбул (сердце открыто)", "the boss's name with its state's word")
    i18n.set("en")
    eq(EnemyPlate.rows(build({ in_state(NORGAN, "Fimbul", 1, ALL_ONE, "HeartExposure") }, nil, NORGAN))[2].label[1],
        "Fimbul (heart exposed)", "in English")
    i18n.set("ru")
end)

test("two rows of one name in different states stay two rows, each with its state", function()
    local plate = build({ in_state(NOKKEN, "Нёккен", 1, ALL_ONE, "Normal"),
        in_state(NOKKEN + 1, "Нёккен", 2, ALL_ONE, "Injured"), in_state(NOKKEN + 2, "Нёккен", 1, ALL_ONE, "Injured") })
    local rows = EnemyPlate.rows(plate)
    eq(#rows, 3, "the header and two rows")
    eq(row_text(rows[2]), "Нёккен | 1,0 1,0 1,0 1,0 1,0 1,0 1,0 1,0", "the Normal one")
    eq(row_text(rows[3]), "Нёккен ×3 (ранен) | 1,0 1,0 1,0 1,0 1,0 1,0 1,0 1,0", "the injured ones merged into one row")
end)

test("a boss with a count and a state", function()
    local plate = build({ in_state(NORGAN, "Норганский великан", 2, GIANT_BODY, "Angry", GIANT_PARTS,
        enabled_without("Blind")), kind(SNOW_OGRE, "Снежный огр", 1, OGRE_BODY, OGRE_PARTS) }, { phys = "Slash" },
        NORGAN)
    local rows = EnemyPlate.rows(plate)
    eq(row_text(rows[2]), "Норганский великан ×2 (в ярости) | 0,8 0,8 0,8 1,0 0,4 0,8 0,8 0,8", "the boss first")
    eq(row_text(rows[3]), "  слабое место | 1,5 1,5 · 1,2 0,6 · · ·", "its part rows as before")
    eq(row_text(rows[5]), "Снежный огр | 0,6 0,6 0,6 0,4 0,6 0,75 0,6 0,6", "the ogre: Normal, no word")
    eq(text_of(EnemyPlate.lines(plate)[1]), "Норганский великан (в ярости): не действует Ослепление ?",
        "its immunities: the state kept, the count left to the table")
end)

test("the immunity lines and the you line name a kind with its state, not its count", function()
    i18n.set("ru")
    local normal = { Slash = 0.5, Blow = 0.5, Shoot = 0.5, Fire = 0.7, Ice = 0.25, Thunder = 0.5, Light = 0.5,
        Magic = 0.5 }
    local plate = build({ in_state(NOKKEN, "Нёккен", 1, normal, "Normal", nil, enabled_without("Frostbite")),
        in_state(NOKKEN + 1, "Нёккен", 2, NOKKEN_INJURED, "Injured", nil, enabled_without("Frostbite")) },
        { phys = "Slash" })
    eq(#plate.rows, 2, "two rows: the tail cut on two")
    eq(EnemyPlate.rows(plate)[3].label[1], "Нёккен ×2 (ранен)", "the table keeps the count")
    local lines = EnemyPlate.lines(plate)
    eq(#lines, 3, "two immunity lines and you")
    eq(text_of(lines[1]), "Нёккен: не действует Обморожение", "the Normal one's")
    eq(text_of(lines[2]), "Нёккен (ранен): не действует Обморожение", "the injured one's: no longer the same line")
    eq(text_of(lines[3]), "ты: Режущий (Нёккен ×0,5, Нёккен (ранен) ×4,5)",
        "you: each with its state, no count beside the mult")
    eq(#lines[3], 1, "one segment"); eq(lines[3][1][2], "you", "in the you colour")
end)

test("layout: the name column's … cut keeps the count and the state word", function()
    i18n.set("ru")
    -- " ×2 (ранен)" is 11 characters, 77 px: the name gets 196 - 77
    local L = EnemyPlate.layout(build({ in_state(GOBLIN, string.rep("Д", 30), 2, ALL_ONE, "Injured") }), 2000, 14,
        measure_at)
    eq(L.lines[2][1][1], string.rep("Д", 16) .. "… ×2 (ранен)", "the name cut, its count and state kept")
    eq(L.lines[2][1].w, 196, "14 em")
    L = EnemyPlate.layout(build({ in_state(GOBLIN, string.rep("Д", 17), 1, ALL_ONE, "Angry") }), 2000, 14, measure_at)
    eq(L.lines[2][1][1], string.rep("Д", 17) .. " (в ярости)", "17 + 11 characters, 196 px: whole")
end)

-- The lines below the table -----------------------------------------------------------------------------------

test("«+N ещё» after the table, then the immunity lines, «ты:» last", function()
    i18n.set("ru")
    local lines = EnemyPlate.lines(crowd_plate(2))
    eq(#lines, 4, "+N, two immunity lines, you")
    eq(text_of(lines[1]), "+2 ещё", "+N first"); eq(lines[1][1][2], "plain", "plain")
    eq(text_of(lines[2]), "Хобгоблин: не действует Отравление", "an immunity line, without the count")
    eq(text_of(lines[4]), "ты: Режущий (Огр ×0,8; остальные ×1,0)", "you last")
    eq(lines[4][1][2], "you", "light blue")
    eq(#EnemyPlate.lines(crowd_plate(0)), 3, "no +N for 0")
end)

test("without a boss an immunity line per kind that has immunities; under a boss the boss's alone",
    function()
    local lines = EnemyPlate.lines(crowd_plate())
    eq(text_of(lines[1]), "Хобгоблин: не действует Отравление",
        "the hobgoblins': «<name>: не действует <list>», the count left to the table")
    eq(#lines[1], 1, "one segment"); eq(lines[1][1][2], "immune", "grey")
    eq(text_of(lines[2]), "Огр: не действует Сон", "the ogre's; the goblins have none")
    eq(text_of(lines[3]), "ты: Режущий (Огр ×0,8; остальные ×1,0)", "then you")
    -- under a boss: the boss's alone
    lines = EnemyPlate.lines(giant_plate())
    eq(#lines, 2, "the giant's immunities and you")
    eq(text_of(lines[1]), "Норганский великан: не действует Ослепление ?", "the boss's; the ogre's sleep left out")
    eq(text_of(lines[2]), "ты: Режущий ×0,8", "you: the boss's value")
    lines = EnemyPlate.lines(build({ kind(NORGAN, "Гигант", 1, GIANT_BODY), kind(OGRE, "Огр", 1, OGRE_PLAIN, nil,
        enabled_without("Sleep")) }, nil, NORGAN))
    eq(#lines, 0, "a boss with no immunity: no line, not the crowd's")
    -- two rows of one name and state with the same immunities, their counts apart: their line once
    local plate = build({ kind(HOBGOBLIN, "Хобгоблин", 2, HOB_BODY, nil, enabled_without("Poison")),
        kind(HOBGOBLIN + 1, "Хобгоблин", 1, OGRE_PLAIN, nil, enabled_without("Poison")) })
    eq(#plate.rows, 2, "two rows: their numbers differ")
    lines = EnemyPlate.lines(plate)
    eq(#lines, 1, "one immunity line"); eq(text_of(lines[1]), "Хобгоблин: не действует Отравление", "theirs")
end)

test("no you line when you is nil", function()
    local p = crowd_plate()
    p.you = nil
    local lines = EnemyPlate.lines(p)
    eq(#lines, 2, "the immunity lines only")
    for _, line in ipairs(lines) do eq(starts(text_of(line), "ты: "), false, "no you line") end
    eq(#EnemyPlate.rows(p), 5, "the table as before")
end)

test("you: a kind with no value is left out, all ×1 gives the type ×1,0, a boss without a value leaves it alone",
    function()
    local rows = { row(GOBLIN, "Гоблин", 5), row(HOBGOBLIN, "Хобгоблин", 2), row(OGRE, "Огр", 1) }
    local function you_line(you, boss)
        local lines = EnemyPlate.lines({ boss = boss, rows = rows, more = 0, you = you })
        return text_of(lines[#lines])
    end
    eq(you_line({ source = "hits", types = { { jt = "Slash", by_kind = { [GOBLIN] = 1, [OGRE] = 0.8 } },
        { jt = "Magic", by_kind = { [OGRE] = 1.3, [GOBLIN] = 2 } } } }),
        "ты: Режущий (Огр ×0,8; остальные ×1,0) · Магия (Гоблин ×2,0, Огр ×1,3)",
        "each type's kinds in parentheses, without their counts, the others at ×1 after them; the"
            .. " hobgoblin has no value: in neither; the kinds in the rows' order")
    eq(you_line({ source = "weapon", types = { { jt = "Slash", by_kind = { [GOBLIN] = 1, [OGRE] = 1 } } } }),
        "ты: Режущий ×1,0", "all ×1: the type with ×1,0")
    eq(you_line({ source = "weapon", types = { { jt = "Slash", by_kind = {} } } }), "ты: Режущий",
        "no kind with a value: the type alone, no invented ×1")
    eq(you_line({ source = "weapon", types = { { jt = "Blow", by_kind = {} } } }, row(NORGAN, "Гигант", 1)),
        "ты: Дробящий", "a boss with no value: the type alone")
    eq(you_line({ source = "weapon", types = { { jt = "Blow", by_kind = { [NORGAN] = 1 } },
        { jt = "Fire", by_kind = { [NORGAN] = 1.5 }, enchant = true } } }, row(NORGAN, "Гигант", 1)),
        "ты: Дробящий ×1,0 · Огонь (зачарование) ×1,5", "a boss: its values, with the enchant")
end)

test("the you line from the model always carries a number it knows", function()
    i18n.set("ru")
    local nokken = kind(NOKKEN, "Нёккен", 1, ALL_ONE, nil, enabled_without("Frostbite", "Freeze", "Blind"))
    local ogre = kind(OGRE, "Огр", 1, { Slash = 0.8, Blow = 1, Fire = 1.5 })
    local function you_of(kinds, boss_id)
        local lines = EnemyPlate.lines(build(kinds, { phys = "Slash" }, boss_id))
        return text_of(lines[#lines])
    end
    eq(you_of({ nokken, ogre }), "ты: Режущий (Огр ×0,8; остальные ×1,0)", "the ogre's slash, the others' ×1")
    local lines = EnemyPlate.lines(build({ nokken, ogre }, { phys = "Slash" }))
    eq(#lines[#lines], 1, "one segment"); eq(lines[#lines][1][2], "you", "in the you colour, the ; too")
    eq(you_of({ nokken }), "ты: Режущий ×1,0", "one kind: its number")
    eq(you_of({ nokken, kind(GOBLIN, "Гоблин", 3, ALL_ONE) }), "ты: Режущий ×1,0", "every kind ×1: ×1,0 alone")
    eq(you_of({ nokken, ogre, kind(GOBLIN, "Гоблин", 2) }), "ты: Режущий (Огр ×0,8; остальные ×1,0)",
        "a kind with no table left out")
    eq(you_of({ ogre, kind(GOBLIN, "Гоблин", 2) }), "ты: Режущий (Огр ×0,8)", "no kind at ×1 beside the ogre")
    eq(you_of({ kind(GOBLIN, "Гоблин", 2), kind(HOBGOBLIN, "Хобгоблин", 1) }), "ты: Режущий",
        "no kind with a number: the type alone")
    eq(you_of({ kind(GOBLIN, "Гоблин", 2) }), "ты: Режущий", "one kind without a number: the type alone")
    eq(you_of({ ogre, nokken }, OGRE), "ты: Режущий ×0,8", "a boss: its own number")
end)

test("a boss with no table or an empty body gets no invented ×1,0 on the you line", function()
    i18n.set("ru")
    for _, case in ipairs({ { "no table", nil }, { "an empty body", { chara_id = NORGAN, state = "Normal", body = {},
        parts = {} } } }) do
        local kinds = { { chara_id = NORGAN, name = "Гигант", count = 1, table = case[2] },
            { chara_id = GOBLIN, name = "Гоблин", count = 2 } }
        local plate = PlateModel.new():build(1, kinds, { phys = "Slash", enchant = "Dark" }, NORGAN)
        local lines = EnemyPlate.lines(plate)
        eq(text_of(lines[#lines]), "ты: Режущий · Тьма (зачарование) ×1,0",
            case[1] .. ": the slash with no number, Dark ×1 everywhere")
        plate = PlateModel.new():build(1, kinds, { phys = "Slash" }, nil)
        lines = EnemyPlate.lines(plate)
        eq(text_of(lines[#lines]), "ты: Режущий", case[1] .. ", no boss: no kind with a number")
    end
end)

test("the texts in English", function()
    i18n.set("en")
    local plate = build({ kind(NORGAN, "Norgan giant", 1, GIANT_BODY, GIANT_PARTS, enabled_without("Blind")),
        kind(GOBLIN, "Goblin", 4) }, { phys = "Slash" }, NORGAN)
    plate.more = 3
    local rows = EnemyPlate.rows(plate)
    eq(row_text(rows[1]), " | Slash Blunt Rngd Fire Ice Thndr Holy Mag", "the header")
    eq(row_text(rows[2]), "Norgan giant | 0.8 0.8 0.8 1.0 0.4 0.8 0.8 0.8", "the English decimal mark")
    eq(row_text(rows[3]), "  weak spot | 1.5 1.5 · 1.2 0.6 · · ·", "the weak spot")
    eq(row_text(rows[4]), "  head | · · · 1.2 · · · ·", "the head")
    eq(row_text(rows[5]), "Goblin ×4 | no data", "no table read")
    local lines = EnemyPlate.lines(plate)
    eq(text_of(lines[1]), "+3 more", "+N")
    eq(text_of(lines[2]), "Norgan giant: immune to Blindness ?", "the immunities")
    eq(text_of(lines[3]), "you: Slash ×0.8", "you")
    lines = EnemyPlate.lines(build({ kind(GOBLIN, "Goblin", 5, ALL_ONE), kind(OGRE, "Ogre", 1, OGRE_PLAIN) },
        { phys = "Slash", enchant = "Fire" }))
    eq(text_of(lines[1]), "you: Slash (Ogre ×0.8; others ×1.0) · Fire (enchant) (Ogre ×1.5; others ×1.0)",
        "the others, the enchant")
    i18n.set("ru")
end)

test("rows and lines never raise on odd plates", function()
    local odd = { n = 3, nil, {}, { rows = 5, more = "x", you = 7, boss = "x" } }
    for i = 1, odd.n do
        eq(#EnemyPlate.rows(odd[i]), 0, "no table " .. i); eq(#EnemyPlate.lines(odd[i]), 0, "no lines " .. i)
    end
    local rows = EnemyPlate.rows({ rows = { row(nil, nil, nil), 5 }, more = 0 })
    eq(#rows, 1, "a row that is not one is skipped; a nameless row is still a row")
    eq(row_text(rows[1]), "? | нет данных", "named «?»")
    -- odd fields: a body value that is not a number, part rows that are not rows, a status that is not a name
    rows = EnemyPlate.rows({ rows = { row(1, "Огр", 1, { known = true, immune = { 5, "Sleep" },
        body = { Fire = "x", Ice = 0 / 0, Slash = 1.5 },
        part_rows = { 5, { kind = "tail", mult = {} }, { kind = "head", mult = 7 }, { kind = "weak", mult = {
            Blow = "y", Fire = 2 } } } }), row(2, "Гоблин", 1, { body = 9 }) } })
    eq(#rows, 4, "the header, the ogre, its one part row, the goblins")
    eq(row_text(rows[2]), "Огр | 1,5 ? ? ? ? ? ? ?", "the number only")
    eq(row_text(rows[3]), "  слабое место | · · · 2,0 · · · ·", "the weak row; the odd ones skipped")
    eq(row_text(rows[4]), "Гоблин | нет данных", "a body that is not a table: no data")
    eq(text_of(EnemyPlate.lines({ rows = { row(1, "Огр", 1, { immune = { 5, "Sleep" } }) } })[1]),
        "Огр: не действует Сон", "the status that is a name")
end)

-- The place ------------------------------------------------------------------------------------------------

test("place with a boss: the right edge 12 px × scale left of the bar's left end, the top 22 units above its middle",
function()
    EnemyPlate.reset()
    eq(EnemyPlate.GAP, 12, "GAP"); eq(EnemyPlate.NAME_ABOVE, 22, "NAME_ABOVE")
    for _, case in ipairs({ { 1920, 1080, FULL_HD, 1 }, { 1920, 1080, FULL_HD, 1.5 }, { 3440, 1440, WIDE, 1.18 } }) do
        local dw, dh, bar, scale = case[1], case[2], case[3], case[4]
        local what = dw .. " × " .. dh .. " at scale " .. scale
        local x, y = EnemyPlate.place(300, 80, bar, dw, dh, scale, 1)
        local left, middle = EnemyBars.boss_left(bar, dw, dh)
        near(x + 300, left - 12 * scale, 0.5, "the right edge at " .. what)
        near(y, middle - 22 * dh / 1080, 0.5, "the top at " .. what)
        eq(x, round(x), "a whole pixel"); eq(y, round(y), "a whole pixel")
    end
    -- the bar's base not read: where the game has the bar
    local x = EnemyPlate.place(300, 80, {}, 1920, 1080, 1, 1)
    eq(x, 564 - 12 - 300, "no base: 396 units left of the centre")
end)

test("place without a boss: centred on the display, the top where the boss bar's name would be", function()
    EnemyPlate.reset()
    local x, y = EnemyPlate.place(360, 80, nil, 1920, 1080, 1, 1)
    eq(x, 960 - 180, "centred"); near(y, (109.5 - 22), 0.5, "the top at (BOSS_MIDDLE - 22) units")
    x, y = EnemyPlate.place(360, 80, nil, 1920, 1080, 2, 1)
    eq(x, 960 - 180, "the scale does not move it")
    near(y, 109.5 - 22, 0.5, "nor its top")
end)

test("boss placement holds 1 s after the bar goes", function()
    EnemyPlate.reset()
    eq(EnemyPlate.HOLD, 1, "HOLD")
    local bx, by = EnemyPlate.place(300, 80, FULL_HD, 1920, 1080, 1, 5)
    local x, y = EnemyPlate.place(300, 80, nil, 1920, 1080, 1, 5.5)
    eq(x, bx, "half a second later: still by the bar"); eq(y, by, "and its top")
    x, y = EnemyPlate.place(300, 80, nil, 1920, 1080, 1, 6)
    eq(x, bx, "a second later: still")
    x, y = EnemyPlate.place(300, 80, nil, 1920, 1080, 1, 6.1)
    eq(x, 960 - 150, "after that: centred"); near(y, 109.5 - 22, 0.5, "at the top")
    -- the bar back: by it again, and the hold starts anew
    EnemyPlate.place(300, 80, FULL_HD, 1920, 1080, 1, 7)
    x = EnemyPlate.place(300, 80, nil, 1920, 1080, 1, 7.9)
    eq(x, bx, "held again")
    -- reset forgets the bar
    EnemyPlate.place(300, 80, FULL_HD, 1920, 1080, 1, 8)
    EnemyPlate.reset()
    x = EnemyPlate.place(300, 80, nil, 1920, 1080, 1, 8.1)
    eq(x, 960 - 150, "forgotten")
end)

test("never off screen: a wide plate, or a boss bar near the left edge, keeps x at 0", function()
    EnemyPlate.reset()
    local x = EnemyPlate.place(2000, 80, FULL_HD, 1920, 1080, 1, 1)
    eq(x, 0, "a plate wider than the room left of the bar")
    x = EnemyPlate.place(300, 80, { x = 100, y = 109.5, width = 776 }, 1920, 1080, 1, 1)
    eq(x, 0, "a bar near the left edge")
    x = EnemyPlate.place(300, 80, { x = 320, y = 109.5, width = 776 }, 1920, 1080, 1, 1)
    eq(x, 8, "just enough room: 320 - 12 - 300")
    x = EnemyPlate.place(5000, 80, nil, 1920, 1080, 1, 1)
    eq(x, 0, "centred but wider than the display")
end)

test("displays 3440 × 1440 and 1280 × 720: x at least 0, centred by the display's width", function()
    for _, display in ipairs({ { 3440, 1440 }, { 1280, 720 }, { 1920, 1080 }, { 2560, 1080 } }) do
        EnemyPlate.reset() -- the boss bar held from the display before
        local dw, dh = display[1], display[2]
        local x, y = EnemyPlate.place(360, 80, nil, dw, dh, 1, 1)
        eq(x, round(dw / 2 - 180), "centred on " .. dw); eq(x >= 0, true, "on screen")
        near(y, (109.5 - 22) * dh / 1080, 0.5, "the top × H / 1080 on " .. dh)
        x = EnemyPlate.place(360, 80, {}, dw, dh, 1, 1)
        near(x + 360, dw / 2 - 396 * dh / 1080 - 12, 0.5, "by the boss bar where the game has it on " .. dw)
        eq(x >= 0, true, "on screen")
        x = EnemyPlate.place(dw * 2, 80, {}, dw, dh, 1, 1)
        eq(x, 0, "too wide: at 0 on " .. dw)
    end
end)

-- The drawing ----------------------------------------------------------------------------------------------

-- One frame; a drawing error fails the test, the stacks must balance.
local function draw(plate, s, boss, t)
    ui.clear_calls()
    local err = EnemyPlate.draw(plate, s, boss, t)
    if err then error("draw failed: " .. err, 2) end
    eq(ui.balanced(), true, "stacks balanced")
end

local function texts()
    return ui.calls_of("add_text")
end

-- The first text drawn that reads `text`, nil without one.
local function drawn(text)
    for _, c in ipairs(texts()) do
        if c.text == text then return c end
    end
    return nil
end

-- The plate's backing this frame: the first filled rectangle.
local function backing()
    return ui.calls_of("add_rect_filled")[1]
end

-- The underlines drawn this frame: the filled rectangles that are neither the backing nor a border strip.
local function underlines()
    local list = {}
    for _, c in ipairs(ui.calls_of("add_rect_filled")) do
        if c.col ~= BACK and c.col ~= BORDER then list[#list + 1] = c end
    end
    return list
end

-- The y of each line drawn, in order (the segments of one line share it).
local function line_tops()
    local tops, last = {}, nil
    for _, c in ipairs(texts()) do
        if c.y ~= last then tops[#tops + 1] = c.y end
        last = c.y
    end
    return tops
end

test("the plate: black at 55 % with a 1 px border, rounded 4 px × scale, padded 6 / 10 px × scale", function()
    for _, scale in ipairs({ 1, 1.5 }) do
        local s = fresh({ scale = scale })
        local plate = giant_plate()
        draw(plate, s, nil, 1)
        local px = 14 * scale
        near(ui.find("push_font_size")[1], px, 1e-9, "14 px × the scale pushed")
        local back = backing()
        eq(back.col, BACK, "black at 55 %, first"); near(back.rounding, 4 * scale, 1e-9, "rounded 4 px × scale")
        eq(back.layer, "background", "on the background list")
        eq(#ui.calls_of("add_rect_filled"), 7, "the plate and the six underlines")
        local borders = ui.calls_of("add_rect")
        eq(#borders, 1, "one outline: the border")
        local b = borders[1]
        eq(b.col, BORDER, "0x4A4A4A"); near(b.rounding, 4 * scale, 1e-9, "rounded alike"); eq(b.thickness, 1, "1 px")
        eq(b.x0, back.x0, "the border on the plate"); eq(b.y0, back.y0, "top"); eq(b.x1, back.x1, "right")
        eq(b.y1, back.y1, "bottom")
        -- its size: the layout's, plus the padding; eight lines one pitch apart
        local L = EnemyPlate.layout(plate, 1920 - 16 * scale - 20 * scale, px, measure_at)
        eq(#L.lines, 8, "the header, five rows of the kinds, the immunities, you")
        near(back.x1 - back.x0, L.w + 20 * scale, 1, "the width at scale " .. scale)
        near(L.w, 411 * scale, 1e-9, "the table's width")
        local pitch = px + EnemyPlate.LINE_GAP * scale
        near(back.y1 - back.y0, 8 * pitch - EnemyPlate.LINE_GAP * scale + 12 * scale, 1,
            "the height at scale " .. scale)
        -- where it stands: as place says
        local x, y = EnemyPlate.place(back.x1 - back.x0, back.y1 - back.y0, nil, 1920, 1080, scale, 1)
        eq(back.x0, x, "at the place's x"); eq(back.y0, y, "and y")
        eq(back.x0, round(back.x0), "a whole pixel"); eq(back.y0, round(back.y0), "a whole pixel")
        -- the texts: the header first, the giant's name a pitch down at the padding, its cells beside it
        local list = texts()
        eq(list[1].text, "Реж", "the header's first column first"); eq(list[1].col, IMMUNE, "grey")
        near(list[1].y, back.y0 + 6 * scale, 0.5, "6 px × scale down")
        local name = drawn("Норганский великан")
        near(name.x, back.x0 + 10 * scale, 0.5, "the name 10 px × scale in"); eq(name.col, NAME, "in the beige")
        near(name.y, list[1].y + pitch, 0.5, "one line down")
        eq(name.px, px, "at the font size"); eq(name.layer, "background", "on the background list")
        local cell = list[10]
        eq(cell.text, "0,8", "then its first cell"); eq(cell.col, RESIST, "red"); eq(cell.y, name.y, "on its line")
        near(cell.x + width("0,8", px), list[1].x + width("Реж", px), 0.5, "right-aligned under its header")
    end
end)

test("the best of a row is underlined: 1 px under its digits, in its colour", function()
    local s = fresh()
    draw(giant_plate(), s, nil, 1)
    local marked = {}
    for _, u in ipairs(underlines()) do
        eq(u.y1 - u.y0, 1, "1 px high")
        local under
        for _, c in ipairs(texts()) do
            if c.x == u.x0 and u.y1 == c.y + 14 then under = c end
        end
        eq(under ~= nil, true, "under a text, at the bottom of its line")
        eq(u.x1 - u.x0, width(under.text, 14), "as wide as its digits: " .. under.text)
        eq(u.col, under.col, "in its colour: " .. under.text)
        marked[#marked + 1] = under.text
    end
    eq(table.concat(marked, " "), "1,0 1,5 1,5 1,2 0,75 1,2",
        "the giant's Fire, its weak spot's Slash and Blow, its head's Fire, the ogre's Thunder, its weak spot's")
    eq(underlines()[1].col, PLAIN, "×1,0 plain"); eq(underlines()[2].col, WEAK, "×1,5 green")
    eq(underlines()[5].col, RESIST, "×0,75 red")
end)

test("the plate's colours", function()
    eq(C.name, NAME, "name 0xEADBB2"); eq(C.weak, WEAK, "weak 0x8FD16A"); eq(C.resist, RESIST, "resist 0xE08A7A")
    eq(C.immune, IMMUNE, "immune 0x9A9A9A"); eq(C.you, YOU, "you 0x9CC8F0"); eq(C.plain, PLAIN, "plain 0xE8E2D0")
    eq(C.back, BACK, "black at 55 %"); eq(C.border, BORDER, "the border")
    local s = fresh()
    draw(crowd_plate(1), s, nil, 1)
    local by = {}
    for _, c in ipairs(texts()) do by[c.text] = c.col end
    eq(by["Гоблин ×5"], NAME, "a name"); eq(by["1,2"], WEAK, "weak"); eq(by["0,8"], RESIST, "resist")
    eq(by["1,0"], PLAIN, "×1,0 plain"); eq(by["Реж"], IMMUNE, "the header grey"); eq(by["голова"], IMMUNE, "a part")
    eq(by["·"], IMMUNE, "«·» grey"); eq(by["нет данных"], IMMUNE, "no data grey")
    eq(by["Огр: не действует Сон"], IMMUNE, "an immunity line"); eq(by["+1 ещё"], PLAIN, "+N plain")
    eq(by["ты: Режущий (Огр ×0,8; остальные ×1,0)"], YOU, "you")
end)

test("the size: 14 px × the meter's scale × enemy_plate_size, 1 without the setting", function()
    -- the crowd's table is 369 px wide at 14 px; at 84 px (6 × 369 = 2214) it is wider than the display less the
    -- margins and the padding (1920 - 32 - 40): drawn at 70 px, the largest whole size that fits (1845 px; 71 is
    -- 1871)
    for _, case in ipairs({ { 1, nil, 14, 14 }, { 1, 2, 28, 28 }, { 1.5, 0.5, 10.5, 10.5 }, { 2, 3, 84, 70 } }) do
        local s = fresh({ scale = case[1] })
        s.values.enemy_plate_size = case[2]
        local plate = crowd_plate()
        draw(plate, s, nil, 1)
        local what = "scale " .. case[1] .. ", size " .. tostring(case[2])
        near(ui.find("push_font_size")[1], case[3], 1e-9, "pushed at " .. what)
        near(texts()[1].px, case[4], 1e-9, "drawn at " .. what)
        local back = backing()
        local x = EnemyPlate.place(back.x1 - back.x0, back.y1 - back.y0, nil, 1920, 1080, case[1], 1)
        eq(back.x0, x, "centred at " .. what)
        near(drawn("Гоблин ×5").x, back.x0 + 10 * case[1], 0.5, "the padding by the scale alone at " .. what)
        local tops = line_tops()
        local room = EnemyPlate.room(nil, 1920, 1080, case[1], 1)
        local L = EnemyPlate.layout(plate, room - 20 * case[1], case[3], measure_at)
        near(L.px, case[4], 1e-9, "the layout's size at " .. what)
        eq(#tops, #L.lines, "the lines drawn are the layout's at " .. what)
        near(tops[2] - tops[1], case[4] + EnemyPlate.LINE_GAP * case[4] / 14, 0.5,
            "the line gap grows with the font at " .. what)
    end
end)

test("without a boss bar the plate is centred at the top; the boss place holds a second", function()
    local s = fresh()
    draw(crowd_plate(), s, nil, 1)
    local back = backing()
    near((back.x0 + back.x1) / 2, 960, 1, "centred"); near(back.y0, 109.5 - 22, 0.5, "at the top")
    draw(giant_plate(), s, FULL_HD, 5)
    back = backing()
    near(back.x1, 564 - 12, 0.5, "by the boss bar")
    draw(giant_plate(), s, nil, 5.5)
    back = backing()
    near(back.x1, 564 - 12, 0.5, "still, half a second after the bar went")
    draw(giant_plate(), s, nil, 6.5)
    back = backing()
    near((back.x0 + back.x1) / 2, 960, 1, "centred again")
end)

test("nothing at all for a plate without lines", function()
    local s = fresh()
    draw({ rows = {}, more = 0 }, s, nil, 1)
    eq(#ui.calls, 0, "no imgui call")
    draw(nil, s, nil, 1)
    eq(#ui.calls, 0, "no plate: none either")
end)

test("the texts are measured once per font size", function()
    local s = fresh()
    local plate = crowd_plate()
    local calc, measured = imgui.calc_text_size, 0
    imgui.calc_text_size = function(text)
        measured = measured + 1
        return calc(text)
    end
    draw(plate, s, nil, 1)
    local once = measured
    eq(once > 0, true, "measured")
    draw(plate, s, nil, 2)
    eq(measured, once, "not again for the same texts")
    s:set("scale", 1.5)
    draw(plate, s, nil, 3)
    eq(measured, 2 * once, "again at another size")
    imgui.calc_text_size = calc
end)

test("draw never raises and stays balanced", function()
    local s = fresh()
    local plate = giant_plate()
    local add_text = ui.draw_list.add_text
    ui.draw_list.add_text = function() error("draw list broke") end
    ui.clear_calls()
    local err = EnemyPlate.draw(plate, s, FULL_HD, 1)
    eq(type(err), "string", "the error comes back")
    eq(ui.balanced(), true, "the font size popped again")
    ui.draw_list.add_text = add_text
    ui.clear_calls()
    eq(type(EnemyPlate.draw(plate, nil, nil, 1)), "string", "no settings")
    eq(type(EnemyPlate.draw(plate, { values = { scale = "big" } }, nil, 1)), "string", "a scale that is not a number")
    eq(ui.balanced(), true, "balanced")
    eq(#texts(), 0, "nothing drawn")
    draw(plate, s, 5, 1)
    eq(#texts() > 0, true, "a boss that is not a bar: drawn where the game has the bar")
    draw(plate, s, FULL_HD, nil)
    eq(#texts() > 0, true, "no time: drawn")
    -- a measure that breaks after the fit pushed a smaller size: every size popped again
    s.values.enemy_plate_size = 3
    local calc = imgui.calc_text_size
    imgui.calc_text_size = function(text)
        if #ui.fonts > 0 and ui.fonts[#ui.fonts] < 42 then error("measure broke") end
        return calc(text)
    end
    SceneText.reset()
    ui.clear_calls()
    err = EnemyPlate.draw(plate, s, FULL_HD, 1)
    imgui.calc_text_size = calc
    eq(type(err), "string", "the error comes back")
    eq(ui.balanced(), true, "the sizes pushed popped again")
    s.values.enemy_plate_size = 1
    -- without the display size or the background list nothing is drawn, nothing raises; a call found missing is
    -- named and not tried again until reset
    for _, name in ipairs({ "get_display_size", "get_background_draw_list" }) do
        local fn = imgui[name]
        imgui[name] = nil
        draw(plate, s, FULL_HD, 1)
        eq(#texts(), 0, "no " .. name .. ": nothing")
        imgui[name] = fn
        draw(plate, s, FULL_HD, 1)
        eq(#texts(), 0, name .. " is not tried again")
        eq(table.concat(EnemyPlate.missing(), ","), name, "and named")
        EnemyPlate.reset()
        draw(plate, s, FULL_HD, 1)
        eq(#texts() > 0, true, "until reset")
    end
end)

-- The room and the wrapping --------------------------------------------------------------------------------

-- The stub's width of `text` at 14 px: 7 px per character.
local function measure(text)
    return width(text, 14)
end

-- The lines of `lines` as "text" or "text (indented)".
local function shapes(lines)
    local out = {}
    for _, line in ipairs(lines) do out[#out + 1] = text_of(line) .. (line.indent and " (indented)" or "") end
    return table.concat(out, "|")
end

-- A plate with no table: a boss with no body and these immunities, and this "you" line.
local function no_table(immune, you)
    return { boss = row(NORGAN, "Гигант", 1, { immune = immune }), rows = {}, more = 0, you = you }
end

-- Blunt, then an enchant of fire, neither with a number: "ты: Дробящий · Огонь (зачарование)", 238 px; and with
-- the giant's numbers, "ты: Дробящий ×1,0 · Огонь (зачарование) ×1,5", 308 px.
local BLUNT_FIRE = { source = "weapon", types = { { jt = "Blow", by_kind = {} },
    { jt = "Fire", by_kind = {}, enchant = true } } }
local BLUNT_FIRE_N = { source = "weapon", types = { { jt = "Blow", by_kind = { [NORGAN] = 1 } },
    { jt = "Fire", by_kind = { [NORGAN] = 1.5 }, enchant = true } } }

test("room: from the left margin to 12 px before the boss bar; the display less the margins without one", function()
    EnemyPlate.reset()
    eq(EnemyPlate.MARGIN, 8, "MARGIN")
    eq(EnemyPlate.room(FULL_HD, 1920, 1080, 1, 1), 564 - 12 - 8, "by the bar at scale 1")
    eq(EnemyPlate.room(FULL_HD, 1920, 1080, 1.5, 1), 564 - 18 - 12, "the gap and the margin × scale")
    near(EnemyPlate.room(WIDE, 3440, 1440, 1, 1), 665.3 * 3440 / 1920 - 20, 1e-9, "3440 × 1440")
    eq(EnemyPlate.room({}, 1920, 1080, 1, 1), 564 - 20, "a bar that could not be read: where the game has it")
    eq(EnemyPlate.room({ x = 10, y = 109.5, width = 776 }, 1920, 1080, 1, 1), 0,
        "a bar at the edge: no room, never below 0")
    -- the bar held a second, like the place
    EnemyPlate.room(FULL_HD, 1920, 1080, 1, 5)
    eq(EnemyPlate.room(nil, 1920, 1080, 1, 5.5), 544, "held half a second after the bar went")
    eq(EnemyPlate.room(nil, 1920, 1080, 1, 6.1), 1920 - 16, "then the display less the margins")
    eq(EnemyPlate.room(nil, 1280, 720, 2, 7), 1280 - 32, "the margins × scale")
end)

test("wrap: a line below the table too wide breaks at its · joints onto indented lines", function()
    local plate = no_table({}, BLUNT_FIRE)
    eq(shapes(EnemyPlate.wrap(plate, 400, 14, measure)), "ты: Дробящий · Огонь (зачарование)",
        "wide enough: as EnemyPlate.lines gives it")
    -- 200 px: "ты: Дробящий" is 84 px, the joint and "Огонь (зачарование)" would make 238
    local lines = EnemyPlate.wrap(plate, 200, 14, measure)
    eq(shapes(lines), "ты: Дробящий|Огонь (зачарование) (indented)", "broken at the joint, the joint dropped")
    eq(lines[2][1][2], "you", "the piece moved down keeps its colour")
    -- the continuation line's room is one em smaller: 133 px fit 147 - 14, not 146 - 14
    eq(shapes(EnemyPlate.wrap(plate, 147, 14, measure)), "ты: Дробящий|Огонь (зачарование) (indented)", "fits")
    eq(shapes(EnemyPlate.wrap(plate, 146, 14, measure)), "ты: Дробящий|Огонь (зачаровани… (indented)",
        "cut to the room left")
end)

test("wrap: a list's comma stays at the end of the line broken, no line wider than the room", function()
    local plate = no_table({ "Poison", "Sleep", "Freeze" })
    -- "Гигант: не действует Отравление, Сон" is 252 px; with its "," 259, with ", Заморозка" 329
    local lines = EnemyPlate.wrap(plate, 260, 14, measure)
    eq(shapes(lines), "Гигант: не действует Отравление, Сон,|Заморозка (indented)", "the comma kept")
    eq(#lines[1], 1, "one segment: the list and its comma in one colour")
    eq(lines[1][1][2], "immune", "the list grey, its comma too")
    eq(lines[2][1][2], "immune", "the piece moved down grey too")
    -- the comma goes when it would make the line wider than the room: no line is ever wider
    lines = EnemyPlate.wrap(plate, 252, 14, measure)
    eq(shapes(lines), "Гигант: не действует Отравление, Сон|Заморозка (indented)", "252 px: the comma would be 259")
    plate = no_table(every_status(), BLUNT_FIRE)
    for w = 60, 400, 7 do
        for i, line in ipairs(EnemyPlate.wrap(plate, w, 14, measure)) do
            local lw = (line.indent and 14 or 0)
            for _, seg in ipairs(line) do lw = lw + measure(seg[1]) end
            eq(lw <= w, true, "line " .. i .. " within " .. w .. " px: " .. text_of(line))
        end
    end
end)

test("wrap: the you line's ; stays at the end of the line broken, in the you colour", function()
    local plate = { rows = { row(GOBLIN, "Гоблин", 5), row(HOBGOBLIN, "Хобгоблин", 2), row(OGRE, "Огр", 1) },
        more = 0, you = { source = "weapon", types = { { jt = "Slash", by_kind = { [GOBLIN] = 1, [HOBGOBLIN] = 1,
        [OGRE] = 0.8 } } } } }
    -- "ты: Режущий (Огр ×0,8" is 147 px, with its ";" 154, with "; остальные ×1,0)" 266
    local lines = EnemyPlate.wrap(plate, 160, 14, measure)
    local n = #lines
    eq(shapes({ lines[n - 1], lines[n] }), "ты: Режущий (Огр ×0,8;|остальные ×1,0) (indented)", "the ; kept")
    for i = n - 1, n do
        eq(#lines[i], 1, "one segment"); eq(lines[i][1][2], "you", "in the you colour, the ; too")
    end
    lines = EnemyPlate.wrap(plate, 150, 14, measure)
    n = #lines
    eq(shapes({ lines[n - 1], lines[n] }), "ты: Режущий (Огр ×0,8|остальные ×1,0) (indented)",
        "150 px: the ; would be 154, it goes")
end)

test("wrap: a piece too wide is cut with …", function()
    local plate = { boss = row(GOBLIN, string.rep("Д", 30), 1, { immune = { "Sleep" } }), rows = {}, more = 0 }
    -- "ДД…Д: не действует Сон" is 48 characters, 336 px
    local lines = EnemyPlate.wrap(plate, 100, 14, measure)
    eq(shapes(lines), string.rep("Д", 13) .. "…", "13 characters and the ellipsis: 98 px")
    eq(measure(lines[1][1][1]) <= 100, true, "within the room")
    eq(lines[1][1][2], "immune", "its colour kept")
    -- nothing fits: the ellipsis alone, never nothing
    lines = EnemyPlate.wrap(plate, 3, 14, measure)
    eq(lines[1][1][1], "…", "the ellipsis alone")
end)

-- The layout and the fit -----------------------------------------------------------------------------------

-- The segment of a layout line that reads `text`, nil without one.
local function seg_of(line, text)
    for _, s in ipairs(line) do
        if s[1] == text then return s end
    end
    return nil
end

test("layout: each column right-aligned, as wide as its widest header or cell; the names left-aligned", function()
    i18n.set("ru")
    eq(EnemyPlate.COL_GAP, 8, "COL_GAP"); eq(EnemyPlate.NAME_GAP, 12, "NAME_GAP")
    local L = EnemyPlate.layout(giant_plate(), 1000, 14, measure_at)
    eq(L.px, 14, "the set size: it fits")
    -- the name column: the widest label, "Норганский великан" (126 px); the columns from 126 + 12 px. Their widths
    -- in characters: Реж 3, Дроб 4, Стрел 5, Огонь 5, Лёд 3, Молн 4 (its header and the ogre's 0,75), Свет 4, Маг 3;
    -- 8 px between two
    local rights = { 159, 195, 238, 281, 310, 346, 382, 411 }
    local header = L.lines[1]
    for i, s in ipairs(header) do
        eq(s.x + s.w, rights[i], "header " .. s[1] .. " right-aligned")
    end
    eq(header[1].x, 138, "Реж 3 characters in its 3-character column")
    eq(L.lines[2][1].x, 0, "the giant's name at the left"); eq(L.lines[2][1][1], "Норганский великан", "whole")
    eq(L.lines[3][1].x, 14, "a part label an em in"); eq(L.lines[3][1][1], "слабое место", "its text")
    for row_i = 2, 6 do
        local line = L.lines[row_i]
        for i = 2, #line do eq(line[i].x + line[i].w, rights[i - 1], "row " .. row_i .. " cell " .. i - 1) end
    end
    eq(seg_of(L.lines[3], "·").x, 238 - 7, "«·» right-aligned too")
    eq(L.lines[5][7].x, 346 - 28, "the ogre's 0,75 fills the Молн column")
    eq(L.lines[2][5].under, true, "the giant's Fire underlined"); eq(L.lines[2][4].under, nil, "its Shoot not")
    eq(L.w, 411, "as wide as the table: the lines below are narrower")
    eq(L.lines[7][1][1], "Норганский великан: не действует Ослепление ?", "the immunities")
    eq(L.lines[7][1].x, 0, "at the left"); eq(L.lines[8][1][1], "ты: Режущий ×0,8", "you last")
    eq(L.line_h, 14, "the line's height"); eq(L.gap, 6, "the gap")
    near(L.h, 8 * 14 + 7 * 6, 1e-9, "eight lines")
    -- a cell wider than its header widens its column
    L = EnemyPlate.layout(build({ kind(OGRE, "Огр", 1, { Slash = 12.5, Blow = 1, Shoot = 1, Fire = 1, Ice = 1,
        Thunder = 1, Light = 1, Magic = 1 }) }), 1000, 14, measure_at)
    eq(L.lines[2][2][1], "12,5", "the ogre's slash"); eq(L.lines[2][2].x, 21 + 12, "its column from the name's end")
    eq(L.lines[1][1].x, 21 + 12 + 28 - 21, "the header right-aligned in the 4-character column")
    -- no data: the note at the columns' left
    L = EnemyPlate.layout(build({ kind(GOBLIN, "Гоблин", 3), kind(OGRE, "Огр", 1, ALL_ONE) }), 1000, 14, measure_at)
    eq(L.lines[2][2][1], "нет данных", "the goblins' note"); eq(L.lines[2][2].x, 63 + 12, "at the columns' left")
end)

test("layout: a name wider than 14 em is cut with …, its count kept", function()
    eq(EnemyPlate.NAME_EM, 14, "NAME_EM")
    local plate = build({ kind(GOBLIN, string.rep("Д", 30), 2, ALL_ONE), kind(OGRE, string.rep("Г", 28), 1, ALL_ONE) })
    local L = EnemyPlate.layout(plate, 2000, 14, measure_at)
    eq(L.lines[2][1][1], string.rep("Д", 24) .. "… ×2", "the name cut, the count kept: 196 px, 14 em")
    eq(L.lines[2][1].w, 196, "14 em")
    eq(L.lines[3][1][1], string.rep("Г", 28), "196 px: whole")
    eq(L.lines[2][2].x, 196 + 12, "the columns after 14 em")
    -- at 28 px, 14 em is 392 px: the same characters
    L = EnemyPlate.layout(plate, 4000, 28, measure_at)
    eq(L.lines[2][1][1], string.rep("Д", 24) .. "… ×2", "at 28 px")
end)

test("layout: a table wider than the room is laid out at the largest whole-pixel size that fits", function()
    eq(EnemyPlate.MIN_FIT, 0.5, "MIN_FIT")
    local plate = giant_plate() -- 411 px at 14 px: 29.36 px per px of font
    eq(EnemyPlate.layout(plate, 411, 14, measure_at).px, 14, "411 px: it fits at the set size")
    local L = EnemyPlate.layout(plate, 400, 14, measure_at)
    eq(L.px, 13, "400 px: 13 px (381.6 px)"); eq(L.w <= 400, true, "and fits: " .. L.w)
    L = EnemyPlate.layout(plate, 300, 14, measure_at)
    eq(L.px, 10, "300 px: 10 px (293.6 px), 11 is 322.9 px"); eq(L.w <= 300, true, "fits: " .. L.w)
    eq(L.lines[2][1][1], "Норганский великан", "no name cut")
    eq(L.line_h, 10, "the lines at the font size"); near(L.gap, 6 * 10 / 14, 1e-9, "the gap with them")
    eq(L.lines[7][1][1], "Норганский великан: не действует Ослепление ?", "the line below in one (225 px)")
    -- a set size that is not whole (the meter's scale 1.1): the whole sizes under it
    eq(EnemyPlate.layout(plate, 400, 15.4, measure_at).px, 13, "15.4 px set, 400 px: 13 px (14 is 411 px)")
    eq(EnemyPlate.layout(plate, 445, 15.4, measure_at).px, 15, "445 px: 15 px (440.4 px; 15.4 is 452.1 px)")
end)

test("layout: the floor is 7 px above 14 px, 50 % at 14 px and below; then the names give way", function()
    local plate = giant_plate()
    -- at 7 px the table is 205.5 px, its columns and gap 142.5: the names get 37.5 px, an em less when indented
    local L = EnemyPlate.layout(plate, 180, 14, measure_at)
    near(L.px, 7, 1e-9, "50 %")
    eq(L.lines[2][1][1], "Норгански…", "the giant cut"); eq(L.lines[3][1][1], "слабое …", "the label too")
    eq(L.lines[4][1][1], "голова", "a label that fits whole"); eq(L.lines[5][1][1], "Снежный о…", "the ogre cut")
    eq(L.w <= 180, true, "it fits: " .. L.w)
    -- the columns alone wider than the room: no smaller than 50 %
    L = EnemyPlate.layout(plate, 100, 14, measure_at)
    near(L.px, 7, 1e-9, "still 50 %"); eq(L.w > 100, true, "wider than the room: " .. L.w)
    eq(L.lines[2][1][1], "…", "the names down to the ellipsis")
    -- above 14 px the floor stays 7 px: 28 and 84 px set go down as far as 14 px does
    for _, px in ipairs({ 28, 84 }) do
        L = EnemyPlate.layout(plate, 180, px, measure_at)
        eq(L.px, 7, px .. " px set: 7 px, not " .. px / 2)
        eq(L.lines[2][1][1], "Норгански…", px .. " px set: the same cut as at 14")
    end
    -- below 14 px, 50 % of the set size
    eq(EnemyPlate.layout(plate, 100, 10, measure_at).px, 5, "10 px set: 5 px")
    near(EnemyPlate.layout(plate, 100, 8.4, measure_at).px, 4.2, 1e-9,
        "8.4 px set (the meter's scale 0.6): 4.2 px, under its whole sizes")
end)

test("draw: a table wider than the room is drawn smaller and stays left of the bar, on screen at 50 %", function()
    local s = fresh()
    s.values.enemy_plate_size = 2
    -- by FULL_HD the room is 544 px, 524 between the paddings; the giant's table is 822 px at 28 px
    draw(giant_plate(), s, FULL_HD, 1)
    local back = backing()
    eq(texts()[1].px, 17, "17 px: 499 px, 18 is 528")
    eq(back.x1 <= 564 - 12, true, "left of the bar"); eq(back.x0 >= 8, true, "past the margin")
    for _, c in ipairs(texts()) do
        eq(c.x + width(c.text, c.px) <= back.x1 - 10 + 0.5, true, "a text inside the plate: " .. c.text)
    end
    -- a bar near the left edge: 60 px between the paddings, the columns alone 142.5 px at 7 px
    s.values.enemy_plate_size = 1
    draw(giant_plate(), s, { x = 100, y = 109.5, width = 776 }, 2)
    back = backing()
    near(texts()[1].px, 7, 1e-9, "50 %, no smaller")
    eq(back.x0 >= 0, true, "on screen at the left"); eq(back.x1 <= 1920, true, "and at the right")
end)

test("under FULL_HD's bar at in-range sizes the plate stays left of the bar, its margin kept", function()
    -- the cases checked: the giant at scale 2 × size 3; the giant ×2 "Angry" (its label cut to 14 em, the count and
    -- the state kept) at scale 1 × size 3, and at scale 2 × size 3
    local angry = build({ in_state(NORGAN, "Норганский великан", 2, GIANT_BODY, "Angry", GIANT_PARTS,
        enabled_without("Blind")), kind(SNOW_OGRE, "Снежный огр", 1, OGRE_BODY, OGRE_PARTS) }, { phys = "Slash" },
        NORGAN)
    local cases = { { 2, giant_plate(), 16, "the giant at scale 2" },
        { 1, angry, 15, "the giant ×2 «в ярости» at scale 1" }, { 2, angry, 14, "the giant ×2 «в ярости» at scale 2" } }
    for _, case in ipairs(cases) do
        local scale, what = case[1], case[4] .. " × size 3"
        local s = fresh({ scale = scale })
        s.values.enemy_plate_size = 3
        draw(case[2], s, FULL_HD, 1)
        local back = backing()
        eq(texts()[1].px, case[3], "drawn at " .. case[3] .. " px: " .. what)
        eq(back.x1 <= 564 - 12 * scale, true, "the right edge before the bar: " .. back.x1 .. ", " .. what)
        eq(back.x0 >= 8 * scale, true, "the margin kept: " .. back.x0 .. ", " .. what)
        for _, c in ipairs(texts()) do
            eq(c.x + width(c.text, c.px) <= back.x1 - 10 * scale + 0.5, true,
                "a text inside: " .. c.text .. ", " .. what)
        end
        if case[2] == angry then
            eq(drawn("Норганский ве… ×2 (в ярости)") ~= nil, true,
                "the label cut to 14 em, its count and state kept: " .. what)
        end
    end
end)

test("never covers the bar: a boss immune to every status at sizes 1 to 3 stays left of the bar, on screen", function()
    local plate = giant_plate()
    plate.boss.immune = every_status()
    for _, size in ipairs({ 1, 2, 3 }) do
        local s = fresh()
        s.values.enemy_plate_size = size
        draw(plate, s, FULL_HD, 1)
        local back = backing()
        local what = " at size " .. size
        eq(back.x1 <= 564 - 12, true, "the right edge before the bar" .. what)
        eq(back.x0 >= 8, true, "the left edge on screen, past the margin" .. what)
        eq(#line_tops() > 6 + 2, true, "the immunity line wrapped" .. what)
        for _, c in ipairs(texts()) do
            eq(c.x + width(c.text, c.px) <= back.x1 - 10 + 0.5, true, "a text inside the plate: " .. c.text .. what)
            eq(c.x >= back.x0 + 10, true, "and past its padding" .. what)
        end
    end
end)

test("never off screen without a boss: 1280 × 720 at size 3, a crowd with long lines", function()
    local s = fresh()
    ui.display = { x = 1280, y = 720 }
    s.values.enemy_plate_size = 3
    local plate = crowd_plate()
    plate.rows[2].immune = every_status()
    draw(plate, s, nil, 1)
    local back = backing()
    eq(back.x0 >= 8, true, "the left edge past the margin"); eq(back.x1 <= 1280 - 8, true, "the right edge before it")
    near((back.x0 + back.x1) / 2, 640, 1, "centred")
    eq(#line_tops() > 5 + 3, true, "the immunity line wrapped")
    for _, c in ipairs(texts()) do
        eq(c.x + width(c.text, c.px) <= back.x1 - 10 + 0.5, true, "a text inside the plate: " .. c.text)
    end
    ui.display = { x = 1920, y = 1080 }
end)

test("a wrapped line keeps its colour and its continuation lines sit one em in", function()
    local s = fresh()
    -- a bar whose room (left - 12 - 8) holds "ты: Дробящий" (84 px) plus the padding, not the whole line (238)
    draw(no_table({}, BLUNT_FIRE), s, { x = 190, y = 109.5, width = 776 }, 1)
    local back = backing()
    eq(back.x1 <= 190 - 12, true, "before the bar")
    local name, first, moved = drawn("Гигант"), drawn("ты: Дробящий"), drawn("Огонь (зачарование)")
    eq(first.col, YOU, "blue"); eq(moved.col, YOU, "moved down: blue")
    eq(moved.y > first.y, true, "on the next line")
    eq(moved.x, first.x + 14, "one em in from the lines' left"); eq(first.x, name.x, "the lines' left")
end)

test("the immunity line and the you line are each one segment when they fit, and keep their colour wrapped", function()
    i18n.set("ru")
    -- whole: one segment each, one colour per line
    local lines = EnemyPlate.lines(giant_plate())
    eq(#lines[1], 1, "the immunity line is one segment"); eq(lines[1][1][2], "immune", "grey")
    eq(#lines[2], 1, "the boss's you line is one segment"); eq(lines[2][1][2], "you", "blue")
    lines = EnemyPlate.lines(no_table({ "Poison", "Sleep" }, BLUNT_FIRE))
    eq(text_of(lines[1]), "Гигант: не действует Отравление, Сон", "its comma inside it"); eq(#lines[1], 1, "one")
    eq(text_of(lines[2]), "ты: Дробящий · Огонь (зачарование)", "its separator inside it"); eq(#lines[2], 1, "one")
    -- wrapped: every segment of each line in its colour, the joints and the kept comma too
    local function all_in(line, color)
        for _, seg in ipairs(line) do
            if seg[2] ~= color then return false, seg[1] .. " in " .. seg[2] end
        end
        return true
    end
    local plate = no_table(every_status(), BLUNT_FIRE_N)
    for _, w in ipairs({ 100, 150, 210, 300 }) do
        lines = EnemyPlate.wrap(plate, w, 14, measure)
        local n_immune, n_you = 0, 0
        for i = 1, #lines do
            local line = lines[i]
            local color = line[1][2]
            if color == "immune" then n_immune = n_immune + 1 elseif color == "you" then n_you = n_you + 1 end
            eq(all_in(line, color), true, "line " .. i .. " in one colour at " .. w .. " px: " .. text_of(line))
            eq(#line, 1, "and so one segment at " .. w .. " px")
        end
        eq(n_immune > 1, true, "the immunities wrapped at " .. w .. " px")
        eq(n_you > 1, true, "the you line wrapped at " .. w .. " px")
    end
    -- and drawn so: with a bar at x = 190 the room is 170 px
    local s = fresh()
    draw(plate, s, { x = 190, y = 109.5, width = 776 }, 1)
    local seen = { [IMMUNE] = 0, [YOU] = 0, [PLAIN] = 0 }
    for _, c in ipairs(texts()) do
        if seen[c.col] then seen[c.col] = seen[c.col] + 1 end
        if c.text:find(",", 1, true) then eq(c.col == IMMUNE or c.col == YOU, true, "a comma in its line's colour") end
    end
    eq(seen[IMMUNE] > 1, true, "grey texts"); eq(seen[YOU] > 1, true, "blue texts")
    eq(seen[PLAIN], 0, "nothing plain on this plate: it has no table")
end)

test("without add_rect the border is four filled strips, the call named and not tried again", function()
    local s = fresh()
    local add_rect = ui.draw_list.add_rect
    ui.draw_list.add_rect = nil
    draw(giant_plate(), s, FULL_HD, 1)
    local fills = ui.calls_of("add_rect_filled")
    eq(#fills, 5 + 6, "the plate, four strips and the six underlines")
    eq(fills[1].col, BACK, "the plate first")
    for i = 2, 5 do eq(fills[i].col, BORDER, "a strip in the border's colour") end
    eq(fills[2].y1 - fills[2].y0, 1, "the top strip is 1 px high"); eq(fills[2].x0, fills[1].x0, "across the plate")
    eq(fills[2].x1, fills[1].x1, "to its right edge")
    eq(fills[3].y0, fills[1].y1 - 1, "the bottom strip at the bottom")
    eq(fills[4].x1 - fills[4].x0, 1, "the left strip is 1 px wide")
    eq(fills[5].x0, fills[1].x1 - 1, "the right strip at the right")
    eq(table.concat(EnemyPlate.missing(), ","), "add_rect", "named")
    ui.draw_list.add_rect = add_rect
    draw(giant_plate(), s, FULL_HD, 1)
    eq(#ui.calls_of("add_rect"), 0, "not tried again")
    EnemyPlate.reset()
    draw(giant_plate(), s, FULL_HD, 1)
    eq(#ui.calls_of("add_rect"), 1, "until reset")
end)

i18n.set("en")
T.finish()
