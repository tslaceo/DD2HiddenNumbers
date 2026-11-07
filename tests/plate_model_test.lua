package.path = "mod/reframework/autorun/?.lua;tests/?.lua;" .. package.path

local T = require("testlib")
local test, eq = T.test, T.eq
local PlateModel = require("DD2DamageMeter/plate_model")
local Journal = require("DD2DamageMeter/journal")

local ALL_ONE = { Slash = 1, Blow = 1, Shoot = 1, Magic = 1, Fire = 1, Ice = 1, Thunder = 1, Light = 1 }

-- A kind near the player; `o` overrides any field.
local function kind(id, o)
    local k = { chara_id = id, name = "kind" .. id, count = 1 }
    for f, v in pairs(o or {}) do k[f] = v end
    return k
end

-- A Table (game/enemy_table.lua) with this body and parts.
local function tbl(id, body, parts)
    return { chara_id = id, state = "Normal", body = body, parts = parts or {} }
end

-- Ledger.split's answer for one type.
local function part(jt, w, before, after)
    return { [jt] = { w = w, before = before or 0, after = after or 0 } }
end

-- The bits of every status but these.
local function enabled_without(...)
    local off, mask = {}, 0
    for _, name in ipairs({ ... }) do off[name] = true end
    for _, s in ipairs(Journal.STATUSES) do
        if not off[s.name] then mask = mask | s.bit end
    end
    return mask
end

local function types_text(types)
    local out = {}
    for _, e in ipairs(types) do out[#out + 1] = e.jt .. "=" .. tostring(e.mult) end
    return table.concat(out, " ")
end

local function parts_text(parts)
    local out = {}
    for _, e in ipairs(parts) do out[#out + 1] = e.kind .. ":" .. e.jt .. "=" .. tostring(e.mult) end
    return table.concat(out, " ")
end

local function one_row(k)
    return PlateModel.new():build(1, { k }, nil, nil).rows[1]
end

test("only values off ×1, the largest first", function()
    local r = one_row(kind(10, { table = tbl(10, { Slash = 1, Fire = 1.5, Ice = 0.1, Light = 1.2, Blow = 0.75 }) }))
    eq(types_text(r.types), "Fire=1.5 Light=1.2 Blow=0.75 Ice=0.1", "the types")
end)

test("equal mults keep type order, equal as shown too", function()
    local r = one_row(kind(10, { table = tbl(10, { Magic = 0.5, Light = 1.5, Ice = 1.5, Slash = 0.5, Fire = 1.496 }) }))
    eq(types_text(r.types), "Fire=1.5 Ice=1.5 Light=1.5 Slash=0.5 Magic=0.5", "the types")
end)

test("a value off ×1 as shown: 1.004 is ×1, ×0 is written, the values come rounded", function()
    local r = one_row(kind(10, { table = tbl(10, { Slash = 1.004, Blow = 0, Magic = 1.2345, Thunder = 0.996 }) }))
    eq(types_text(r.types), "Magic=1.23 Blow=0.0", "the types")
end)

test("a part note at 0.2 or more, never Shoot", function()
    local head = { kind = "head", mult = { Slash = 1.4, Shoot = 1.2 } }
    local r = one_row(kind(10, { table = tbl(10, ALL_ONE, { head }) }))
    eq(parts_text(r.parts), "head:Slash=1.4", "the parts")
end)

test("a part against the body's value, weak before head, 0.2 off counts and 0.19 does not", function()
    local body = { Slash = 0.8, Blow = 1, Fire = 1.5, Ice = 1 }
    local r = one_row(kind(10, { table = tbl(10, body, {
        { kind = "head", mult = { Blow = 1.19, Ice = 2 } },
        { kind = "weak", mult = { Slash = 1.0, Fire = 1.5, Thunder = 1.3 } },
    }) }))
    -- weak Slash: 1.0 against the body's 0.8 (a float a little under 0.2 off); weak Thunder against ×1 (no column)
    eq(parts_text(r.parts), "weak:Slash=1.0 weak:Thunder=1.3 head:Ice=2.0", "the parts")
end)

test("a table with no body: no types and no part line", function()
    local r = one_row(kind(10, { table = tbl(10, {}, { { kind = "weak", mult = { Fire = 2 } } }) }))
    eq(#r.types, 0, "no types"); eq(#r.parts, 0, "no part line")
end)

test("known: a table with a body; not with no table, an empty body or a table that is not one", function()
    eq(one_row(kind(10, { table = tbl(10, ALL_ONE) })).known, true, "every type ×1: known")
    eq(one_row(kind(10, { table = tbl(10, { Fire = 1.5 }) })).known, true, "one column: known")
    eq(one_row(kind(10)).known, false, "no table")
    eq(one_row(kind(10, { table = tbl(10, {}) })).known, false, "an empty body")
    eq(one_row(kind(10, { table = { parts = {} } })).known, false, "a table with no body")
    eq(one_row(kind(10, { table = "x" })).known, false, "a table that is not one")
end)

-- The Norgan giant and snow ogre of a screenshot from the game: their bodies and parts as the collector
-- read them.
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

-- A map { [jt] = mult } as "jt=mult" in the table's column order.
local COLUMNS = { "Slash", "Blow", "Shoot", "Fire", "Ice", "Thunder", "Light", "Magic" }
local function map_text(map)
    local out = {}
    for _, jt in ipairs(COLUMNS) do
        if map[jt] ~= nil then out[#out + 1] = jt .. "=" .. tostring(map[jt]) end
    end
    for jt in pairs(map) do
        local column = false
        for _, c in ipairs(COLUMNS) do column = column or c == jt end
        if not column then out[#out + 1] = jt .. "=" .. tostring(map[jt]) .. "(not a column)" end
    end
    return table.concat(out, " ")
end

local function part_rows_text(rows)
    local out = {}
    for _, p in ipairs(rows) do out[#out + 1] = p.kind .. ": " .. map_text(p.mult) end
    return table.concat(out, " | ")
end

test("body: every one of the 8 columns, rounded, ×1 included", function()
    local r = one_row(kind(10, { table = tbl(10, GIANT_BODY) }))
    eq(map_text(r.body), "Slash=0.8 Blow=0.8 Shoot=0.8 Fire=1.0 Ice=0.4 Thunder=0.8 Light=0.8 Magic=0.8",
        "every column, Fire's ×1 too")
    r = one_row(kind(10, { table = tbl(10, { Slash = 1.004, Blow = 0, Shoot = 1, Fire = 1.2345, Ice = 0.996,
        Thunder = 1, Light = 1, Magic = 1, Dark = 2 }) }))
    eq(map_text(r.body), "Slash=1.0 Blow=0.0 Shoot=1.0 Fire=1.23 Ice=1.0 Thunder=1.0 Light=1.0 Magic=1.0",
        "rounded by Ledger.round_mult; ×0 kept; only the tables' columns")
    -- a column the read lost: no invented ×1
    r = one_row(kind(10, { table = tbl(10, { Fire = 1.5, Ice = 0 / 0 }) }))
    eq(map_text(r.body), "Fire=1.5", "the columns that have a number")
end)

test("body: nil without a known body", function()
    eq(one_row(kind(10)).body, nil, "no table")
    eq(one_row(kind(10, { table = tbl(10, {}) })).body, nil, "an empty body")
    eq(one_row(kind(10, { table = { parts = {} } })).body, nil, "a table with no body")
    eq(one_row(kind(10, { table = "x" })).body, nil, "a table that is not one")
    eq(one_row(kind(10, { table = tbl(10, ALL_ONE) })).body ~= nil, true, "every type ×1: a body")
end)

test("part_rows: the screenshot's giant and ogre, weak before head, absent where as the body, never Shoot", function()
    local r = one_row(kind(10, { table = tbl(10, GIANT_BODY, GIANT_PARTS) }))
    eq(part_rows_text(r.part_rows), "weak: Slash=1.5 Blow=1.5 Fire=1.2 Ice=0.6 | head: Fire=1.2",
        "the giant: the types off its body; its head's Shoot ×1.2 left out (open question 2)")
    r = one_row(kind(20, { table = tbl(20, OGRE_BODY, OGRE_PARTS) }))
    eq(part_rows_text(r.part_rows), "weak: Slash=1.0 Blow=1.0 Fire=0.8 Ice=1.0 Thunder=1.2 Light=1.0 Magic=1.0",
        "the ogre: its weak spot's ×1 values too, as they differ from the body; Shoot absent")
    -- the existing fields stay as they were
    eq(parts_text(r.parts), "weak:Slash=1.0 weak:Blow=1.0 weak:Fire=0.8 weak:Ice=1.0 weak:Thunder=1.2 "
        .. "weak:Light=1.0 weak:Magic=1.0", "parts unchanged")
end)

test("part_rows: a part kind only when a type differs by 0.2 or more; then its smaller differences too", function()
    local body = { Slash = 0.8, Blow = 1, Shoot = 1, Fire = 1, Ice = 1, Thunder = 1, Light = 1, Magic = 1 }
    local function rows_of(parts) return part_rows_text(one_row(kind(10, { table = tbl(10, body, parts) })).part_rows) end
    eq(rows_of({ { kind = "head", mult = { Slash = 0.9, Fire = 1.19 } } }), "", "0.1 and 0.19 off: no row")
    eq(rows_of({ { kind = "head", mult = { Shoot = 2 } } }), "", "only Shoot off: no row")
    eq(rows_of({ { kind = "head", mult = { Slash = 1.0, Fire = 1.1 } } }), "head: Slash=1.0 Fire=1.1",
        "Slash 0.2 off (a float a little under): the row, Fire's 0.1 in it")
    eq(rows_of({ { kind = "weak", mult = { Slash = 1.5, Blow = 1.004, Ice = 0.996, Light = 1.2345 } } }),
        "weak: Slash=1.5 Light=1.23", "as the body once rounded: absent; the values rounded")
    -- a column the body lost: the part's value is present, against ×1 for the rule
    local lost = { Slash = 1, Blow = 1 }
    local r = one_row(kind(10, { table = tbl(10, lost, { { kind = "weak", mult = { Fire = 1.3, Ice = 1 } } }) }))
    eq(part_rows_text(r.part_rows), "weak: Fire=1.3 Ice=1.0", "both present: the body has no Fire nor Ice")
    -- two parts of one kind: the largest value per type, as EnemyTable gives one
    r = one_row(kind(10, { table = tbl(10, body, { { kind = "weak", mult = { Slash = 1.5 } },
        { kind = "weak", mult = { Slash = 2, Fire = 1.2 } } }) }))
    eq(part_rows_text(r.part_rows), "weak: Slash=2.0 Fire=1.2", "one row")
    -- no body: no part rows
    eq(#one_row(kind(10, { table = tbl(10, {}, { { kind = "weak", mult = { Fire = 2 } } }) })).part_rows, 0,
        "no body, no part row")
    eq(#one_row(kind(10)).part_rows, 0, "no table, none")
end)

test("immune from the enabled mask", function()
    local r = one_row(kind(10, { enabled = enabled_without("Poison", "Sleep") }))
    eq(table.concat(r.immune, " "), "Poison Sleep", "the statuses that do not work")
end)

test("immune in Journal.STATUSES order, whatever the mask's order", function()
    local r = one_row(kind(10, { enabled = enabled_without("Blind", "Freeze", "Poison") }))
    eq(table.concat(r.immune, " "), "Poison Freeze Blind", "in the journal's order")
end)

test("nil enabled: no immunity line", function()
    local r = one_row(kind(10, { table = tbl(10, ALL_ONE) }))
    eq(#r.immune, 0, "no immunity")
end)

test("no table: name and count only", function()
    local r = one_row(kind(10, { name = "Goblin", count = 5 }))
    eq(r.chara_id, 10, "the kind"); eq(r.name, "Goblin", "its name"); eq(r.count, 5, "its count")
    eq(#r.types, 0, "no types"); eq(#r.parts, 0, "no parts"); eq(#r.immune, 0, "no immunity")
end)

test("a boss first and the boss's row apart", function()
    local plate = PlateModel.new():build(1, { kind(1), kind(2, { name = "Griffin" }), kind(3) }, nil, 2)
    eq(plate.boss.chara_id, 2, "the boss's row"); eq(plate.boss.name, "Griffin", "its name")
    eq(#plate.rows, 2, "the others")
    eq(plate.rows[1].chara_id, 1, "in the kinds' order"); eq(plate.rows[2].chara_id, 3, "then the next")
    eq(plate.more, 0, "nothing left out")
end)

test("no boss row without a boss", function()
    local plate = PlateModel.new():build(1, { kind(1), kind(2) }, nil, nil)
    eq(plate.boss, nil, "no boss"); eq(#plate.rows, 2, "two rows")
end)

test("caps", function()
    local kinds = {}
    for i = 1, 8 do kinds[i] = kind(i) end
    local plate = PlateModel.new():build(1, kinds, nil, nil)
    eq(#plate.rows, 6, "8 kinds and no boss: 6 rows"); eq(plate.more, 2, "+2")
    eq(plate.rows[6].chara_id, 6, "the first 6")

    kinds = {}
    for i = 1, 6 do kinds[i] = kind(i) end
    plate = PlateModel.new():build(1, kinds, nil, 2)
    eq(plate.boss.chara_id, 2, "the boss")
    eq(#plate.rows, 3, "a boss and 5 others: 3 rows"); eq(plate.more, 2, "+2")
    eq(plate.rows[2].chara_id, 3, "the boss skipped"); eq(plate.rows[3].chara_id, 4, "the third")

    plate = PlateModel.new():build(1, kinds, nil, 6)
    eq(plate.boss.chara_id, 6, "a boss listed after the cap is still the boss")
    eq(#plate.rows, 3, "3 rows"); eq(plate.more, 2, "+2")
end)

-- Two Hobgoblin CharaIDs read in the game: one name, one table (only their HP and defence differ).
local HOB_BODY = { Slash = 1, Blow = 1, Fire = 0.8, Thunder = 1.2 }
local HOB_HEAD = { { kind = "head", mult = { Blow = 1.4 } } }
local function hobgoblin(id, count, o)
    local k = kind(id, { name = "Hobgoblin", count = count, table = tbl(id, HOB_BODY, HOB_HEAD),
        enabled = enabled_without("Sleep") })
    for f, v in pairs(o or {}) do k[f] = v end
    return k
end

test("kinds of one name showing the same merge into one row, the counts summed, at the first one's place",
    function()
    local m = PlateModel.new()
    local plate = m:build(1, { kind(1, { name = "Goblin" }), hobgoblin(52, 2), kind(3, { name = "Ogre" }),
        hobgoblin(53, 1) }, { phys = "Slash", element = "Fire" }, nil)
    eq(#plate.rows, 3, "three rows"); eq(plate.more, 0, "none left out")
    local hob = plate.rows[2]
    eq(hob.chara_id, 52, "the first one's place and kind"); eq(hob.name, "Hobgoblin", "the name")
    eq(hob.count, 3, "Hobgoblin ×3")
    eq(types_text(hob.types), "Thunder=1.2 Fire=0.8", "its types"); eq(parts_text(hob.parts), "head:Blow=1.4", "parts")
    eq(table.concat(hob.immune, " "), "Sleep", "immunities")
    eq(plate.rows[3].name, "Ogre", "the ogre after it")
    -- a merged pair takes one row: 7 kinds, two of them twins, fit the 6 rows
    local kinds = { hobgoblin(52, 2), hobgoblin(53, 1) }
    for i = 1, 5 do kinds[#kinds + 1] = kind(i) end
    plate = m:build(1, kinds, nil, nil)
    eq(#plate.rows, 6, "six rows"); eq(plate.more, 0, "none left out"); eq(plate.rows[1].count, 3, "the twins one")
    kinds[#kinds + 1] = kind(6)
    plate = m:build(1, kinds, nil, nil)
    eq(#plate.rows, 6, "a seventh row's kind"); eq(plate.more, 1, "is left out")
end)

test("any number shown differently keeps two kinds of one name apart", function()
    local function rows_of(a, b, weapon, hits)
        local m = PlateModel.new()
        for _, h in ipairs(hits or {}) do m:add_hit(1, h[1], h[2]) end
        local plate = m:build(2, { a, b }, weapon, nil)
        return #plate.rows, plate.rows[1].count
    end
    eq(rows_of(hobgoblin(52, 2), hobgoblin(53, 1)), 1, "the same: one row")
    eq(rows_of(hobgoblin(52, 2), hobgoblin(53, 1, { table = tbl(53, { Fire = 0.7, Thunder = 1.2 }, HOB_HEAD) })), 2,
        "a type's value differs: two rows")
    eq(rows_of(hobgoblin(52, 2), hobgoblin(53, 1, { table = tbl(53, HOB_BODY, {}) })), 2, "no part note: two rows")
    eq(rows_of(hobgoblin(52, 2), hobgoblin(53, 1, { enabled = enabled_without() })), 2, "no immunity: two rows")
    eq(rows_of(hobgoblin(52, 2), hobgoblin(53, 1, { name = "Goblin" })), 2, "another name: two rows")
    -- the "you" values come from the tables: a slash that got ×1.3 on one changes neither
    eq(rows_of(hobgoblin(52, 2), hobgoblin(53, 1), { phys = "Slash" }, { { part("Slash", 130, 100, 130), 52 } }), 1,
        "a hit's ratio on one: the same you value, one row")
    -- one table without the slash's column: ×1 on one, none on the other
    local n, count = rows_of(hobgoblin(52, 2),
        hobgoblin(53, 1, { table = tbl(53, { Blow = 1, Fire = 0.8, Thunder = 1.2 }, HOB_HEAD) }), { phys = "Slash" })
    eq(n, 2, "a you value differs: two rows"); eq(count, 2, "the counts their own")
    -- with no table both: the same nothing shown
    eq(rows_of(kind(52, { name = "Hobgoblin" }), kind(53, { name = "Hobgoblin" }), { phys = "Slash" }), 1,
        "no table on both: one row")
    eq(rows_of(kind(52, { name = "Hobgoblin" }), hobgoblin(53, 1), { phys = "Slash" }), 2,
        "a table on one only: two rows")
    -- every type ×1 against no table shows "all types ×1" against "no data", with no you line to tell them apart
    eq(rows_of(kind(52, { name = "Hobgoblin", table = tbl(52, ALL_ONE) }), kind(53, { name = "Hobgoblin" })), 2,
        "known on one only: two rows")
    eq(rows_of(kind(52, { name = "Hobgoblin", table = tbl(52, {}) }), kind(53, { name = "Hobgoblin" })), 1,
        "an empty body and no table: neither known, one row")
    -- the table shows every body cell and the part rows' smaller differences
    local full = { Slash = 1, Blow = 1, Shoot = 1, Fire = 0.8, Ice = 1, Thunder = 1.2, Light = 1, Magic = 1 }
    local lost = { Slash = 1, Blow = 1, Fire = 0.8, Ice = 1, Thunder = 1.2, Light = 1, Magic = 1 } -- no Shoot
    eq(rows_of(hobgoblin(52, 2, { table = tbl(52, full, HOB_HEAD) }), hobgoblin(53, 1, { table = tbl(53, lost,
        HOB_HEAD) })), 2, "a body cell ×1 against one the read lost: two rows")
    eq(rows_of(hobgoblin(52, 2, { table = tbl(52, full, { { kind = "head", mult = { Blow = 1.4, Fire = 0.9 } } }) }),
        hobgoblin(53, 1, { table = tbl(53, full, HOB_HEAD) })), 2, "a part cell 0.1 off: two rows")
    eq(rows_of(hobgoblin(52, 2, { table = tbl(52, full, HOB_HEAD) }), hobgoblin(53, 1, { table = tbl(53, full,
        HOB_HEAD) })), 1, "the same cells: one row")
end)

-- Nёkken's table as the collector read it after its tail was cut.
local NOKKEN_INJURED = { Slash = 4.5, Blow = 4, Shoot = 4, Fire = 6, Ice = 2, Thunder = 4, Light = 4, Magic = 4 }

test("state: the table's state when it is not Normal, else none", function()
    local function state_of(t) return one_row(kind(10, { table = t })).state end
    local injured = tbl(10, NOKKEN_INJURED)
    injured.state = "Injured"
    eq(state_of(injured), "Injured", "Injured")
    eq(state_of(tbl(10, ALL_ONE)), nil, "Normal: none")
    eq(one_row(kind(10)).state, nil, "no table: none")
    eq(state_of({ chara_id = 10, state = "Angry", body = {}, parts = {} }), "Angry", "an empty body keeps its state")
    eq(state_of({ chara_id = 10, state = 3, body = ALL_ONE, parts = {} }), nil, "a state that is not a string: none")
    eq(state_of({ chara_id = 10, state = "", body = ALL_ONE, parts = {} }), nil, "an empty one: none")
    eq(state_of({ chara_id = 10, body = ALL_ONE, parts = {} }), nil, "no state: none")
end)

test("rows of one name merge only when their state is the same too", function()
    local function nokken(id, count, state)
        local t = tbl(id, ALL_ONE)
        t.state = state
        return kind(id, { name = "Nokken", count = count, table = t })
    end
    local plate = PlateModel.new():build(1, { nokken(1, 1, "Normal"), nokken(2, 1, "Injured") }, nil, nil)
    eq(#plate.rows, 2, "the same cells, Normal and Injured: two rows")
    eq(plate.rows[1].state, nil, "the first Normal"); eq(plate.rows[2].state, "Injured", "the second injured")
    plate = PlateModel.new():build(1, { nokken(1, 1, "Injured"), nokken(2, 2, "Injured") }, nil, nil)
    eq(#plate.rows, 1, "both injured: one row"); eq(plate.rows[1].count, 3, "the counts summed")
    plate = PlateModel.new():build(1, { nokken(1, 1, "Normal"), nokken(2, 2) }, nil, nil)
    eq(#plate.rows, 1, "Normal and no state show alike: one row")
end)

test("a boss's kind never merges with a crowd row", function()
    local plate = PlateModel.new():build(1, { hobgoblin(52, 1), hobgoblin(53, 2) }, { phys = "Slash" }, 53)
    eq(plate.boss.chara_id, 53, "the boss"); eq(plate.boss.count, 2, "its own count")
    eq(#plate.rows, 1, "the other kind its own row"); eq(plate.rows[1].chara_id, 52, "the crowd's")
    eq(plate.rows[1].count, 1, "its own count")
end)

test("you from hits", function()
    local m = PlateModel.new()
    m:add_hit(1, part("Blow", 150, 100, 150), 10)
    m:add_hit(2, part("Blow", 150, 100, 150), 10)
    m:add_hit(2, part("Fire", 50, 50, 50), 10)
    local you = m:build(3, { kind(10, { table = tbl(10, { Blow = 0.7, Fire = 1.3 }) }) }, { phys = "Slash" }, nil).you
    eq(you.source, "hits", "the hits decide")
    eq(#you.types, 2, "two types")
    eq(you.types[1].jt, "Blow", "the largest w first"); eq(you.types[1].by_kind[10], 0.7, "its table, not the ×1.5")
    eq(you.types[2].jt, "Fire", "then the next"); eq(you.types[2].by_kind[10], 1.3, "its table, not the ×1")
end)

test("you from hits: two slashes at a part's ×0.45 and ×0.49 both give the kind's body value", function()
    local m = PlateModel.new()
    local kinds = { kind(10, { table = tbl(10, { Slash = 0.5, Blow = 1 }) }), kind(20) }
    m:add_hit(1, part("Slash", 45, 100, 45), 10)
    m:add_hit(1, part("Slash", 120, 100, 120), 20)
    local by = m:build(1.5, kinds, nil, nil).you.types[1].by_kind
    eq(by[10], 0.5, "after the leg: the body's ×0.5"); eq(by[20], nil, "no table: none, whatever got through")
    m:add_hit(2, part("Slash", 49, 100, 49), 10)
    by = m:build(2.5, kinds, nil, nil).you.types[1].by_kind
    eq(by[10], 0.5, "after the next part: the same"); eq(by[20], nil, "still none")
end)

test("you from hits: every kind takes its table, hit or not", function()
    local m = PlateModel.new()
    m:add_hit(1, part("Fire", 150, 100, 150), 10)
    local kinds = {
        kind(10, { table = tbl(10, ALL_ONE) }),
        kind(20, { table = tbl(20, { Fire = 0.8 }) }),
        kind(30, { table = tbl(30, { Ice = 2 }) }),   -- no Fire column
        kind(40),                                      -- no table
    }
    local you = m:build(2, kinds, nil, nil).you
    eq(you.types[1].jt, "Fire", "fire")
    local by = you.types[1].by_kind
    eq(by[10], 1.0, "the hit kind: its body's value, not what got through")
    eq(by[20], 0.8, "an unhit kind: its body's value")
    eq(by[30], nil, "no column: no mult"); eq(by[40], nil, "no table: none")
end)

test("you: a kind with no table, an empty body or no column has no mult; Dark is ×1; a hit gives none",
    function()
    local kinds = {
        kind(10),                                       -- no table
        kind(20, { table = tbl(20, {}) }),              -- a table with no body
        kind(30, { table = tbl(30, { Fire = 1.5 }) }),  -- no Slash column: the read lost it
    }
    local m = PlateModel.new()
    local you = m:build(1, kinds, { phys = "Slash", enchant = "Dark" }, nil).you
    eq(you.types[1].jt, "Slash", "slash")
    local by = you.types[1].by_kind
    eq(by[10], nil, "no table: none"); eq(by[20], nil, "an empty body: none"); eq(by[30], nil, "no column: none")
    eq(you.types[2].jt, "Dark", "dark")
    by = you.types[2].by_kind
    eq(by[10], 1, "Dark: ×1 with no table"); eq(by[20], 1, "with an empty body"); eq(by[30], 1, "with a body")
    -- the player's slash got through the region step on the kind with no table: still no number of it
    m:add_hit(1, part("Slash", 100, 100, 120), 10)
    by = m:build(2, kinds, nil, nil).you.types[1].by_kind
    eq(by[10], nil, "hit: still none"); eq(by[20], nil, "the others still none"); eq(by[30], nil, "none")
end)

test("you from hits: at most 2 types, picked by the largest summed w (ties by type order), given in type order",
    function()
    local m = PlateModel.new()
    m:add_hit(1, part("Ice", 30), 10)
    m:add_hit(1, part("Thunder", 20), 10)
    m:add_hit(1, part("Fire", 30), 10)
    m:add_hit(1, part("Thunder", 20), 10)
    local you = m:build(2, { kind(10) }, nil, nil).you
    eq(#you.types, 2, "two: Thunder (40) and, a tie of 30, Fire before Ice")
    eq(you.types[1].jt, "Fire", "Fire first in type order"); eq(you.types[2].jt, "Thunder", "then Thunder")
    -- their weights cross: the order stays
    m = PlateModel.new()
    m:add_hit(1, part("Fire", 100), 10)
    m:add_hit(1, part("Slash", 60), 10)
    you = m:build(2, { kind(10) }, nil, nil).you
    eq(you.types[1].jt .. " " .. you.types[2].jt, "Slash Fire", "fire the heavier")
    m:add_hit(2, part("Slash", 60), 10)
    you = m:build(3, { kind(10) }, nil, nil).you
    eq(you.types[1].jt .. " " .. you.types[2].jt, "Slash Fire", "slash the heavier now: the same order")
end)

test("you from hits: Status and Other are not the player's types, Dark is", function()
    local m = PlateModel.new()
    m:add_hit(1, part("Status", 1000), 10)
    m:add_hit(1, part("Other", 1000), 10)
    m:add_hit(1, part("Dark", 5, 5, 5), 10)
    local you = m:build(2, { kind(10, { table = tbl(10, { Magic = 0.5 }) }) }, nil, nil).you
    eq(#you.types, 1, "Dark only"); eq(you.types[1].jt, "Dark", "dark")
    eq(you.types[1].by_kind[10], 1, "×1")
end)

test("you from hits: only Status ticks are no hits, the weapon decides", function()
    local m = PlateModel.new()
    m:add_hit(1, part("Status", 1), 10)
    local you = m:build(2, { kind(10) }, { phys = "Blow" }, nil).you
    eq(you.source, "weapon", "the weapon")
end)

test("you from hits: a mixed hit shows both its types", function()
    local m = PlateModel.new()
    m:add_hit(1, { Slash = { w = 60, before = 50, after = 60 }, Magic = { w = 40, before = 50, after = 40 } }, 10)
    local you = m:build(2, { kind(10, { table = tbl(10, { Slash = 0.9, Magic = 2 }) }) }, nil, nil).you
    eq(you.types[1].jt, "Slash", "slash"); eq(you.types[1].by_kind[10], 0.9, "its table, not the ×1.2")
    eq(you.types[2].jt, "Magic", "magick"); eq(you.types[2].by_kind[10], 2.0, "its table, not the ×0.8")
end)

test("you from hits: a type the region step took all of is still the player's, at its table's value", function()
    local m = PlateModel.new()
    m:add_hit(1, part("Ice", 50, 50, 0), 20)           -- absorbed: the table says ×1
    m:add_hit(1, { Slash = { w = 100, before = 100, after = 100 }, Thunder = { w = 0, before = 40, after = 0 } }, 10)
    local kinds = { kind(10, { table = tbl(10, { Slash = 1.3, Thunder = 0 }) }),
        kind(20, { table = tbl(20, { Ice = 1 }) }) }
    local you = m:build(2, kinds, nil, nil).you
    eq(#you.types, 2, "slash and ice"); eq(you.types[1].jt, "Slash", "slash"); eq(you.types[2].jt, "Ice", "ice")
    eq(you.types[2].by_kind[20], 1.0, "its table, not what got through")
    -- a mixed hit's absorbed type, w 0: picked while no other type has a weight
    m = PlateModel.new()
    m:add_hit(1, { Slash = { w = 100, before = 100, after = 100 }, Thunder = { w = 0, before = 40, after = 0 } }, 10)
    you = m:build(2, kinds, nil, nil).you
    eq(#you.types, 2, "slash and thunder"); eq(you.types[2].jt, "Thunder", "thunder")
    eq(you.types[2].by_kind[10], 0.0, "its table's ×0")
end)

test("you from the weapon with no hits in 10 s", function()
    local m = PlateModel.new()
    m:add_hit(0, part("Fire", 100, 100, 150), 10)
    local kinds = { kind(10, { table = tbl(10, { Blow = 0.8, Fire = 1.5 }) }) }
    eq(m:build(10, kinds, { phys = "Blow" }, nil).you.source, "hits", "10 s: still the hits")
    local you = m:build(10.5, kinds, { phys = "Blow" }, nil).you
    eq(you.source, "weapon", "the weapon")
    eq(#you.types, 1, "its type only"); eq(you.types[1].jt, "Blow", "blunt"); eq(you.types[1].by_kind[10], 0.8, "×0.8")
end)

test("you from the weapon: its type, then the enchant, else its own element", function()
    local kinds = { kind(10, { table = tbl(10, { Slash = 1.2, Fire = 1.5, Ice = 0.5 }) }), kind(20) }
    local m = PlateModel.new()
    local you = m:build(1, kinds, { phys = "Slash", element = "Ice", enchant = "Fire" }, nil).you
    eq(#you.types, 2, "two")
    eq(you.types[1].jt, "Slash", "the type"); eq(you.types[1].by_kind[10], 1.2, "its body value")
    eq(you.types[1].by_kind[20], nil, "no table: none"); eq(you.types[1].enchant, nil, "no enchant")
    eq(you.types[2].jt, "Fire", "the enchant"); eq(you.types[2].enchant, true, "marked")
    eq(you.types[2].by_kind[10], 1.5, "×1.5")

    you = m:build(1, kinds, { phys = "Slash", element = "Ice" }, nil).you
    eq(you.types[2].jt, "Ice", "its own element"); eq(you.types[2].enchant, nil, "no enchant")
    eq(you.types[2].by_kind[10], 0.5, "×0.5")

    you = m:build(1, kinds, { phys = "Magic", enchant = "Dark" }, nil).you
    eq(you.types[1].jt, "Magic", "a staff"); eq(you.types[1].by_kind[10], nil, "no Magic column: none")
    eq(you.types[2].jt, "Dark", "dark"); eq(you.types[2].by_kind[10], 1, "Dark has no column: ×1")
end)

test("you nil with neither", function()
    local m = PlateModel.new()
    eq(m:build(1, { kind(10) }, nil, nil).you, nil, "no hits, no weapon")
    eq(m:build(1, { kind(10) }, {}, nil).you, nil, "a weapon answer with no type")
end)

test("clear forgets the hits", function()
    local m = PlateModel.new()
    m:add_hit(1, part("Fire", 100, 100, 150), 10)
    m:clear()
    eq(m:build(2, { kind(10) }, { phys = "Slash" }, nil).you.source, "weapon", "the weapon")
    eq(m:build(2, { kind(10) }, nil, nil).you, nil, "nothing")
end)

test("at most 400 hits kept, the oldest go first", function()
    local m = PlateModel.new()
    m:add_hit(1, part("Fire", 1000), 10)
    for _ = 1, 399 do m:add_hit(1, part("Slash", 1), 10) end
    local you = m:build(1, { kind(10) }, nil, nil).you
    eq(#you.types, 2, "400 hits: the first one kept"); eq(you.types[2].jt, "Fire", "fire, after slash in type order")
    m:add_hit(1, part("Slash", 1), 10)
    you = m:build(1, { kind(10) }, nil, nil).you
    eq(#you.types, 1, "401: the first one gone"); eq(you.types[1].jt, "Slash", "slash only")
end)

test("nothing raises on odd input", function()
    local m = PlateModel.new()
    m:add_hit(nil, part("Fire", 1), 10)
    m:add_hit(1, nil, 10)
    m:add_hit(1, { Fire = "x" }, 10)
    local plate = m:build(2, { kind(10, { table = { body = { Fire = 0 / 0, Ice = 1.5 }, parts = { "x" } } }), "x" },
        { phys = "Bogus" }, nil)
    eq(types_text(plate.rows[1].types), "Ice=1.5", "the finite value only")
    eq(#plate.rows, 1, "the odd kind left out"); eq(plate.you, nil, "no you")
    plate = m:build(2, nil, nil, nil)
    eq(#plate.rows, 0, "no kinds"); eq(plate.more, 0, "none more")
end)

T.finish()
