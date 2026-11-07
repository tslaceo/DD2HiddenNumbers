-- The enemy plate's model (ui/enemy_plate.lua draws it): for each enemy kind near the player, the values of its table
-- in use (game/enemy_table.lua) as a small table (its body, and its parts that take clearly more or less than its
-- body), the status conditions that do not work on it, and one "you" line: what the player hits with now and each
-- kind's table value for it. Pure Lua: no game access, no drawing. Every mult it gives is rounded by
-- Ledger.round_mult. Dark is ×1 for every kind (the tables have no column for it, the game applies ×1); for another
-- type a kind's body has no value for (no table, a table with no body, a column the read lost) the "you" line has no
-- mult of that kind, never an invented ×1.
--
--   PlateModel.new() -> model
--   model:add_hit(t, parts)   a player's hit on an enemy at time t: parts = Ledger.split(hit). Only its types the
--       "you" line can name are kept, each with its w (0 for one the region step took all of); which enemy it hit
--       does not matter. Hits more than RECENT seconds before t are dropped (here and in build), and the oldest
--       beyond MAX_HITS.
--   model:clear()   forgets the hits
--   model:build(t, kinds, weapon, boss_id) -> Plate
--     kinds = { { chara_id, name, count, table = Table | nil, enabled = integer | nil } }: Table from EnemyTable,
--       enabled = EnemyData.enabled (game/enemies.lua); the rows keep this order, so the caller keeps it stable
--     weapon = Weapon.read's answer (game/weapon.lua) | nil;  boss_id = the boss bar's chara_id | nil
--   Plate = { boss = Row | nil, rows = { Row }, more = integer, you = You | nil }
--     boss: the row of the first kind of chara_id boss_id, kept out of rows; rows: the other kinds' rows, merged
--     (see below), then at most ROWS, or BOSS_ROWS while there is a boss_id (the plate sits left of the boss bar);
--     more: the rows left out
--     The rows of kinds with the same name and state that show the same (known, types, parts, body, part_rows,
--     immune, and the same mult, or none on both, for each of the "you" line's types) are one row, at the first
--     one's place and with its chara_id, the counts summed (a count that is not a number counts 1); any number shown
--     differently, or another state, keeps them apart. The boss's row never merges.
--   Row = { chara_id, name, count, state, known, types = { { jt, mult } }, parts = { { kind, jt, mult } },
--           body = { [jt] = mult } | nil, part_rows = { { kind, mult = { [jt] = mult } } }, immune = { name } }
--     state: the kind's Table.state in use when it is a string other than "Normal" ("Angry", "Injured"...), else nil
--       (the plate names it after the kind's name; its table's values change with it)
--     known: true when the kind's table has a body (not an empty one), else false; body is nil without one
--     types: the body's values that are not 1 as shown, the largest first, equal ones in Ledger.TYPES order
--     parts: per part kind, "weak" then "head", the types whose value is at least PART_DIFF off the body's (×1 for a
--       type the body has no value for), never Shoot (arrows to the head: the table's ×1.2 was not applied in game,
--       not explained yet), in Ledger.TYPES order
--     body (the plate's table): the body's value of each of the tables' 8 columns (Slash Blow Shoot Fire Ice
--       Thunder Light Magic), ×1 included; a column the read lost has none; nil when known is false
--     part_rows: per part kind, "weak" then "head", one entry when one of its types is at least PART_DIFF off the
--       body's (the rule of parts; a kind's several parts give per type their largest value); its mult holds the
--       types whose value differs from the body's once rounded (a type absent is "as the body"), never Shoot
--     A kind with no table, or a table with no body (no Body part), has no types, no parts, no body and no part
--     rows.
--     immune: the names of the Journal.STATUSES entries (lang key status_<name>) whose bit is not set in enabled, in
--       that order; none when enabled is nil
--   You = { source = "hits" | "weapon", types = { { jt, by_kind = { [chara_id] = mult }, enchant = true | nil } } }
--     at most 2 types; by_kind holds the kinds of `kinds` that have a chara_id and a mult
--     "hits", when the hits of the last RECENT seconds have a type: the 2 types with the largest summed w (ties by
--       Ledger.TYPES order), given in Ledger.TYPES order, so two types of close weights do not swap places from one
--       build to the next. The types are the tables' (Slash Blow Shoot Magic Fire Ice Thunder Light) and Dark;
--       Status and Other are no attack type of the player.
--     "weapon", else: its phys, then its enchant (enchant = true) or else its own element
--     nil when neither gives a type
--     A kind's mult, from either: its body's value of the type; without one, 1 for Dark, else none. The hits
--       only pick the types: what a hit got through the part it struck is no kind's number, so the line stays put
--       from hit to hit.
--   PlateModel.RECENT (10 s), PlateModel.MAX_HITS (400), PlateModel.ROWS (6), PlateModel.BOSS_ROWS (3),
--   PlateModel.PART_DIFF (0.2)
local Ledger = require("DD2DamageMeter/ledger")
local Journal = require("DD2DamageMeter/journal")

local PlateModel = {}
PlateModel.__index = PlateModel

local RECENT = 10       -- s of the player's hits that decide the "you" line
local MAX_HITS = 400    -- hits kept
local ROWS = 6          -- rows without a boss
local BOSS_ROWS = 3     -- other kinds' rows under a boss
local PART_DIFF = 0.2   -- how far off the body's value a part's is noted
local EPS = 1e-9        -- times are sums of frame times, and 1.0 - 0.8 is a little under 0.2
local YOU_TYPES = 2     -- types on the "you" line
PlateModel.RECENT, PlateModel.MAX_HITS, PlateModel.ROWS, PlateModel.BOSS_ROWS, PlateModel.PART_DIFF =
    RECENT, MAX_HITS, ROWS, BOSS_ROWS, PART_DIFF

local TYPES = Ledger.TYPES
local PART_KINDS = { "weak", "head" }
-- The tables' columns (game/enemy_table.lua), in Ledger.TYPES order: what a row's body and part rows hold.
local COLUMNS = { "Slash", "Blow", "Shoot", "Fire", "Ice", "Thunder", "Light", "Magic" }
-- The player's attack types the "you" line can name: the tables' columns, and Dark.
local ATTACK = { Slash = true, Blow = true, Shoot = true, Magic = true, Fire = true, Ice = true, Thunder = true,
    Light = true, Dark = true }

local function finite(x)
    return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function positive(x)
    return finite(x) and x > 0 and x or 0
end

-- A whole number (a flag mask), else nil.
local function whole(x)
    return type(x) == "number" and math.tointeger(x) or nil
end

-- The kind's body values, nil when it has none.
local function body_of(k)
    local tbl = k.table
    local body = type(tbl) == "table" and tbl.body
    if type(body) ~= "table" or next(body) == nil then return nil end
    return body
end

-- The body's value of a type, 1 without one.
local function body_mult(body, jt)
    local v = body and body[jt]
    return finite(v) and v or 1
end

-- The "you" line's mult of a type from the body: its value; without one 1 for Dark (no table has a column for
-- it, the game applies ×1), else nil.
local function body_you(body, jt)
    local v = body and body[jt]
    if finite(v) then return v end
    if jt == "Dark" then return 1 end
    return nil
end

function PlateModel.new()
    return setmetatable({ hits = {} }, PlateModel)
end

function PlateModel:clear()
    self.hits = {}
end

-- Drops the hits more than RECENT seconds before t (none without a time), then the oldest beyond MAX_HITS.
local function trim(self, t)
    local hits = self.hits
    local n, cut = #hits, 0
    if finite(t) then
        while cut < n and t - hits[cut + 1].t > RECENT + EPS do cut = cut + 1 end
    end
    cut = math.max(cut, n - MAX_HITS)
    if cut <= 0 then return end
    table.move(hits, cut + 1, n, 1)
    for i = n - cut + 1, n do hits[i] = nil end
end

function PlateModel:add_hit(t, parts)
    if not finite(t) then return end
    if type(parts) == "table" then
        local kept = {}
        for jt, p in pairs(parts) do
            if ATTACK[jt] and type(p) == "table" then
                local w = positive(p.w)
                if w > 0 or positive(p.before) > 0 then kept[jt] = w end
            end
        end
        if next(kept) ~= nil then
            local hits = self.hits
            hits[#hits + 1] = { t = t, w = kept }
        end
    end
    trim(self, t)
end

-- A part kind's values in one map: per type the largest of its parts' (EnemyTable gives one entry per kind already).
local function kind_mult(parts, kind)
    local out = {}
    for _, p in ipairs(parts) do
        if type(p) == "table" and p.kind == kind and type(p.mult) == "table" then
            for _, jt in ipairs(COLUMNS) do
                local v = p.mult[jt]
                if finite(v) and (out[jt] == nil or v > out[jt]) then out[jt] = v end
            end
        end
    end
    return out
end

-- The table's rows of a body: each column with a number, rounded; and per part kind, when one of its types is
-- PART_DIFF off the body's, the types whose value differs from the body's once rounded, never Shoot.
local function table_of(row, body, parts)
    row.body = {}
    for _, jt in ipairs(COLUMNS) do
        if finite(body[jt]) then row.body[jt] = Ledger.round_mult(body[jt]) end
    end
    for _, kind in ipairs(PART_KINDS) do
        local mult, off, shown = kind_mult(parts, kind), false, {}
        for _, jt in ipairs(COLUMNS) do
            local v = mult[jt]
            if jt ~= "Shoot" and v ~= nil then
                off = off or math.abs(v - body_mult(body, jt)) >= PART_DIFF - EPS
                local r = Ledger.round_mult(v)
                if r ~= row.body[jt] then shown[jt] = r end
            end
        end
        if off then row.part_rows[#row.part_rows + 1] = { kind = kind, mult = shown } end
    end
end

-- The kind's state in use when it is not "Normal", nil without one.
local function state_of(k)
    local state = type(k.table) == "table" and k.table.state or nil
    if type(state) ~= "string" or state == "" or state == "Normal" then return nil end
    return state
end

local function row_of(k)
    local body = body_of(k)
    local row = { chara_id = k.chara_id, name = k.name, count = k.count, state = state_of(k), known = body ~= nil,
        types = {}, parts = {}, immune = {}, part_rows = {} }
    if body then
        for _, jt in ipairs(TYPES) do
            local v = body[jt]
            if finite(v) then
                local shown = Ledger.round_mult(v)
                if shown ~= 1 then
                    -- the largest first, after the equal ones before it in type order
                    local at = #row.types + 1
                    while at > 1 and row.types[at - 1].mult < shown do at = at - 1 end
                    table.insert(row.types, at, { jt = jt, mult = shown })
                end
            end
        end
        local parts = k.table.parts
        if type(parts) ~= "table" then parts = {} end
        for _, kind in ipairs(PART_KINDS) do
            for _, p in ipairs(parts) do
                if type(p) == "table" and p.kind == kind and type(p.mult) == "table" then
                    for _, jt in ipairs(TYPES) do
                        local v = p.mult[jt]
                        if jt ~= "Shoot" and finite(v) and math.abs(v - body_mult(body, jt)) >= PART_DIFF - EPS then
                            row.parts[#row.parts + 1] = { kind = kind, jt = jt, mult = Ledger.round_mult(v) }
                        end
                    end
                end
            end
        end
        table_of(row, body, parts)
    end
    local enabled = whole(k.enabled)
    if enabled then
        for _, s in ipairs(Journal.STATUSES) do
            if (enabled & s.bit) == 0 then row.immune[#row.immune + 1] = s.name end
        end
    end
    return row
end

-- The "you" line's types from the recent hits: { { jt } }, nil with none.
local function hit_types(hits)
    local sums = {}
    for _, h in ipairs(hits) do
        for jt, w in pairs(h.w) do sums[jt] = (sums[jt] or 0) + w end
    end
    local taken = {}
    for _ = 1, YOU_TYPES do
        local best, bw = nil, nil
        for _, jt in ipairs(TYPES) do
            local w = sums[jt]
            if w and not taken[jt] and (bw == nil or w > bw) then best, bw = jt, w end
        end
        if best == nil then break end
        taken[best] = true
    end
    -- picked by weight, given in type order: two types of close weights keep their places as hits age out
    local out = {}
    for _, jt in ipairs(TYPES) do
        if taken[jt] then out[#out + 1] = { jt = jt } end
    end
    if #out == 0 then return nil end
    return out
end

-- The "you" line's types from the weapon, nil with none.
local function weapon_types(weapon)
    if type(weapon) ~= "table" then return nil end
    local out = {}
    if ATTACK[weapon.phys] then out[#out + 1] = { jt = weapon.phys } end
    if ATTACK[weapon.enchant] then
        out[#out + 1] = { jt = weapon.enchant, enchant = true }
    elseif ATTACK[weapon.element] then
        out[#out + 1] = { jt = weapon.element }
    end
    if #out == 0 then return nil end
    return out
end

local function you_of(hits, kinds, weapon)
    local source, picked = "hits", hit_types(hits)
    if picked == nil then source, picked = "weapon", weapon_types(weapon) end
    if picked == nil then return nil end
    local types = {}
    for i, e in ipairs(picked) do
        -- each kind's table, whatever the hits got through
        local by_kind = {}
        for _, k in ipairs(kinds) do
            if k.chara_id ~= nil then
                local mult = body_you(body_of(k), e.jt)
                if mult ~= nil then by_kind[k.chara_id] = Ledger.round_mult(mult) end
            end
        end
        types[i] = { jt = e.jt, by_kind = by_kind, enchant = e.enchant }
    end
    return { source = source, types = types }
end

-- Whether two lists hold the same entries: equal values, or (with `fields`) entries equal in each of those fields.
local function same_list(a, b, fields)
    if #a ~= #b then return false end
    for i = 1, #a do
        if fields == nil then
            if a[i] ~= b[i] then return false end
        else
            for _, f in ipairs(fields) do
                if a[i][f] ~= b[i][f] then return false end
            end
        end
    end
    return true
end

local TYPE_FIELDS, PART_FIELDS = { "jt", "mult" }, { "kind", "jt", "mult" }

-- Whether two { [jt] = mult } maps (nil for none) hold the same values in the same columns.
local function same_map(a, b)
    if a == nil or b == nil then return a == b end
    for _, jt in ipairs(COLUMNS) do
        if a[jt] ~= b[jt] then return false end
    end
    return true
end

local function same_part_rows(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do
        if a[i].kind ~= b[i].kind or not same_map(a[i].mult, b[i].mult) then return false end
    end
    return true
end

-- Whether rows a and b show the same: one name and state, both known or neither, the same types, part note,
-- table cells (body and part rows) and immunities, and the same mult (or none on both) for each of the "you" line's
-- types.
local function same_shown(a, b, you)
    if type(a.name) ~= "string" or a.name == "" or a.name ~= b.name or a.state ~= b.state or a.known ~= b.known then
        return false
    end
    if not (same_list(a.types, b.types, TYPE_FIELDS) and same_list(a.parts, b.parts, PART_FIELDS)
            and same_map(a.body, b.body) and same_part_rows(a.part_rows, b.part_rows)
            and same_list(a.immune, b.immune)) then
        return false
    end
    for _, e in ipairs(you and you.types or {}) do
        if e.by_kind[a.chara_id] ~= e.by_kind[b.chara_id] then return false end
    end
    return true
end

local function count_of(row)
    return finite(row.count) and row.count or 1
end

function PlateModel:build(t, kinds, weapon, boss_id)
    trim(self, t)
    local valid = {}
    for _, k in ipairs(type(kinds) == "table" and kinds or {}) do
        if type(k) == "table" then valid[#valid + 1] = k end
    end
    local plate = { rows = {}, more = 0, you = you_of(self.hits, valid, weapon) }
    -- the rows, a row showing what one before it shows merged into that one; then the cap
    local rows = {}
    for _, k in ipairs(valid) do
        local row = row_of(k)
        if boss_id ~= nil and plate.boss == nil and k.chara_id == boss_id then
            plate.boss = row
        else
            local into = nil
            for _, r in ipairs(rows) do
                if same_shown(r, row, plate.you) then
                    into = r
                    break
                end
            end
            if into then into.count = count_of(into) + count_of(row) else rows[#rows + 1] = row end
        end
    end
    local cap = boss_id ~= nil and BOSS_ROWS or ROWS
    for i, r in ipairs(rows) do
        if i <= cap then plate.rows[i] = r else plate.more = plate.more + 1 end
    end
    return plate
end

return PlateModel
