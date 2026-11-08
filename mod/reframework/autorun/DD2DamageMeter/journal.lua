-- The journal's models: a Snapshot with its detail (ledger.lua) turned into ready-to-draw strings for the header of a
-- fight and the Enemies tab (the list of the fight's enemies and the card of the selected row), plus the names of the
-- tabs, damage types and the game's flags. Pure functions like view.lua, no game and no drawing.
-- ctx = { names = Names, i18n = i18n }.
--
--   Journal.TABS       { "summary", "enemies", "skills", "party", "heal", "chart", "record" } (titles: jtab_<id>)
--   Journal.WEAK       { { bit, name, key } } the CharacterWeakpointType flags in display order, key = their text
--   Journal.STATUSES   { { bit, name, message|nil, unclear|nil } } the StatusConditionFlag flags in display order;
--                      message = the game's message naming the status, lang key status_<name> as the fallback; the
--                      name shown starts with a capital (I18n.upper_first); unclear = true for a status the game
--                      keeps a flag for that nothing seen in game builds up (Blind): wherever the mod names it, its
--                      name is followed by " ?" (Journal.mark_unclear)
--   Journal.mark_unclear(name, text) -> text   `text` (a status's name as shown) with " ?" after it when the
--     Journal.STATUSES entry named `name` is unclear; `text` as it is for any other name, or one that is no entry's
--   Journal.type_label(jt) -> string   a Ledger.TYPES entry named
--   Journal.shows_zero(v) -> boolean   true when I18n.num(v) is "0": a row of that value is not shown (a blocked blow,
--     a grab); the totals and shares around it still count it
--   Journal.type_counts(types|nil, i18n) -> string   "Дробящий ×5, Огонь ×1": hits per type (jt -> n), the most first,
--     then in Ledger.TYPES order; a count that is not a number above 0 is left out ("" without one)
--   Journal.header(snap|nil, ctx, index, count) -> { line, fight|nil, numbers = { { label, value, block|nil } } }
--     line "Победа · 4:15 · Огр, Ящер ×2" (at most 3 kinds, then jmore_kinds); fight = jfight_of(index, count) when
--     count > 0; numbers: dealt ("damage"), per second, taken ("enemies"), healed ("heal"), the share the enemy
--     defence took ("—" without a defence step); block = whose colour the number takes. nil snap: line jno_fights,
--     no numbers.
--   Journal.enemies(snap|nil, ctx, sel) -> { list = { title, rows }, sel, card|nil }
--     rows: the kinds (Fight.kind_key) by largest full HP, on equal full HP the one the party's side hit last first;
--     a kind of one enemy is one row, a kind of several a kind row followed by its members (Journal.by_death)
--     row  = { id = "e:<enemy key>" | "k:<kind key>", label, hp_text, fill = HP left / full (0 killed, 1 unknown),
--              killed, group, member }
--     sel  = sel clamped to 1..#rows (1 when there are none); card = the card of rows[sel]
--     Card = { title, sub, killer | nil, deaths = { { label, text, line, killer | nil, killed } } | nil (a kind: its
--              members by Journal.by_death),
--              game = { data, weak = {}, resist = {}, immune = {}, defence | nil },
--              types = { title, rows = { { label, value, fill, mult, mult_value, eff, eff_text } }, parts | nil,
--                        empty | nil },
--              who = { title, total, rows, empty | nil },
--              attacks = { title, total, rows = { { label, name, types | nil, value, fill, kind, job, shade } } } }
--     sub (one enemy) and a death's text: "75 000 HP · убит на 4:12 · добил Torinald"; a death's line: "4:12 · 75 000 HP
--     · добил Torinald" (a living one "7 200 / 7 600 HP"); killer = { name, kind, job, shade } of who finished it
--     (the name as in the text), nil while it lives or when nobody is known
--     types.empty: no_data without the detail, jno_hits when nothing hit it, jno_damage when hits did but no row is
--     shown; who.empty: jno_damage when someone hit it but no row is shown, else nil
--     parts: "Режущий: голова ×1,4 · туловище ×1,0" for the type with the most damage among those that hit both the
--            head and the body through a region step, when its two multipliers, as shown, differ; else nil
--     who rows: { kind = "who", key, name, job_label, actor_kind, order, job, shade, hits, value, share, fill, grey },
--               each followed by its skills { kind = "skill", label, name, type_text | nil, hits, value, share, avg,
--               max, mult, mult_value, eff, eff_text }; label = "name · type_text"; share: of everything the enemy
--               took (every dealer's damage to it), on dealer and skill rows; fill: a dealer's value against the
--               biggest dealer's
--     No type, who, skill or attack row shows a value of 0 (Journal.shows_zero), except a type or skill row whose
--     multiplier's word is «не действует» (eff "invalid": hits fully absorbed), and the who row of such a skill.
--     mult = I18n.mult of the multiplier the game applied (damage after / before the region step, rounded by
--     Ledger.round_mult), "" without a region step; mult_value that rounded number (nil without one); eff =
--     Ledger.efficacy of it (nil without one); eff_text its word for invalid / resist / effective.
--     attacks rows: the friend hit (name, his kind, job, shade), types = his hits by type (Journal.type_counts, nil
--     without any), label = "name · types"; fill against the top row
--   Journal.who_of(snap, key, ctx, cache|nil) -> { name, kind, job, shade }   an actor key of the snapshot to draw in
--     its colour: its name (Other for nil, "other" and a key the snapshot does not know, kind "other"), its kind, job
--     and, for a party member, its shade; `cache` (a table kept over one model's build) holds View.shades once
--   Journal.by_death(a, b) -> boolean   the order of a kind's members ({ key, e = snap.enemies entry }): the killed
--     ones by when they died (the first first; one with no time after those with one), then the living by key
local Fight = require("DD2DamageMeter/fight")
local Ledger = require("DD2DamageMeter/ledger")
local View = require("DD2DamageMeter/view")
local I18n = require("DD2DamageMeter/i18n")

local Journal = {}

Journal.TABS = { "summary", "enemies", "skills", "party", "heal", "chart", "record" }

Journal.WEAK = {
    { bit = 1, name = "Slash", key = "type_Slash" },
    { bit = 2, name = "Blow", key = "type_Blow" },
    { bit = 4, name = "Shoot", key = "type_Shoot" },
    { bit = 8, name = "None", key = "type_Magic" },
    { bit = 16, name = "Fire", key = "element_Fire" },
    { bit = 32, name = "Ice", key = "element_Ice" },
    { bit = 64, name = "Thunder", key = "element_Thunder" },
    { bit = 128, name = "Light", key = "element_Light" },
    { bit = 256, name = "Magic", key = "weak_magic_all" },
    { bit = 512, name = "Physics", key = "weak_physics_all" },
}

-- Messages: the titles of the game's tutorial pages.
Journal.STATUSES = {
    { bit = 2, name = "Poison", message = "ui080101_40" },
    { bit = 128, name = "VirulentPoison", message = "ui080101_41" },
    { bit = 4, name = "Sleep", message = "ui080101_42" },
    { bit = 8, name = "Faint", message = "ui080101_43" },
    { bit = 256, name = "Frostbite", message = "ui080101_37" },
    { bit = 512, name = "Freeze", message = "ui080101_38" },
    { bit = 8192, name = "Electric" },
    { bit = 16, name = "Wet", message = "ui080101_47" },
    { bit = 1024, name = "Oil", message = "ui080101_46" },
    { bit = 32, name = "FireSpread", message = "ui080101_35" },
    { bit = 64, name = "OilSpread", message = "ui080101_36" },
    { bit = 2048, name = "Silence", message = "ui080101_45" },
    { bit = 4096, name = "Stone", message = "ui080101_44" },
    -- the game keeps the flag, but no attack, skill, item, pawn or enemy seen built it up (checked 2026-11-08)
    { bit = 8388608, name = "Blind", unclear = true },
}

local UNCLEAR = " ?" -- after an unclear status's name
local STATUS_BY_NAME = {}
for _, s in ipairs(Journal.STATUSES) do STATUS_BY_NAME[s.name] = s end

function Journal.mark_unclear(name, text)
    local s = name ~= nil and STATUS_BY_NAME[name] or nil
    if s and s.unclear then return text .. UNCLEAR end
    return text
end

local PARTY = { player = true, pawn = true }
local PLAIN = { Slash = true, Blow = true, Shoot = true, Magic = true }
local ELEMENTS = { Fire = true, Ice = true, Thunder = true, Light = true, Dark = true }
local EFF_TEXT = { invalid = "eff_invalid", resist = "eff_resist", effective = "eff_effective" }
local JOBS = 10           -- vocations with a name (job_1 .. job_10)
local MAX_KINDS = 3       -- kinds named in the fight's line
local SECOND_TYPE = 0.25  -- share of a skill's damage that gets its second type named

local TYPE_RANK = {}
for i, jt in ipairs(Ledger.TYPES) do TYPE_RANK[jt] = i end

function Journal.type_label(jt)
    if PLAIN[jt] then return I18n.t("type_" .. jt) end
    if ELEMENTS[jt] then return I18n.t("element_" .. jt) end
    if jt == "Status" then return I18n.t("dot") end
    return I18n.t("other")
end

function Journal.shows_zero(v)
    return I18n.num(v) == "0"
end
local shows_zero = Journal.shows_zero

-- Journal types in Ledger.TYPES order (anything else after them).
local function type_before(a, b)
    local ra, rb = TYPE_RANK[a] or math.huge, TYPE_RANK[b] or math.huge
    if ra ~= rb then return ra < rb end
    return tostring(a) < tostring(b)
end

-- A whole number (a flag mask, a vocation; a loaded history may give it as a float), else nil.
local function whole(x)
    return type(x) == "number" and math.tointeger(x) or nil
end

local function finite(x)
    return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

-- The multiplier the game applied: the damage after / before the region step; nil without a step.
local function ratio(before, after)
    if type(before) ~= "number" or type(after) ~= "number" or not (before > 0) then return nil end
    local r = after / before
    if not finite(r) then return nil end
    return r
end

-- Sets mult, eff and eff_text of a row; the number shown and the scale word come from one rounding.
local function with_mult(row, before, after, ctx)
    local r = ratio(before, after)
    local shown = r and Ledger.round_mult(r)
    row.mult = shown and ctx.i18n.mult(shown) or ""
    row.mult_value = shown
    row.eff = shown and Ledger.efficacy(shown) or nil
    local text = row.eff and EFF_TEXT[row.eff]
    row.eff_text = text and ctx.i18n.t(text) or nil
    return row
end

-- A row with its multiplier is shown unless its value shows as 0; a row of 0 that says «не действует» stays (hits the
-- enemy fully absorbed), any other one of 0 (a grab, a blow on the corpse at ×1,0) does not.
local function shown(row, value)
    return not shows_zero(value) or row.eff == "invalid"
end

-- The name of an actor key of the snapshot; Other for "other" and for a key it does not know.
local function name_of(snap, key, ctx)
    local s = snap.actors and snap.actors[key]
    if not s then return ctx.i18n.t("other") end
    return View.actor_name(s.actor, ctx)
end

local function by_key(a, b)
    return tostring(a.key) < tostring(b.key)
end

-- When a killed enemy entry died: its time, or math.huge when it was not kept.
local function died_at(e)
    local t = e.killed_at
    if type(t) == "number" and t == t then return t end
    return math.huge
end

function Journal.by_death(a, b)
    local ka, kb = a.e.killed == true, b.e.killed == true
    if ka ~= kb then return ka end
    if ka then
        local ta, tb = died_at(a.e), died_at(b.e)
        if ta ~= tb then return ta < tb end
    end
    return by_key(a, b)
end

-- The shades of the snapshot's party (View.shades), built once per model.
local function shades_of(snap, cache)
    if cache.shades == nil then cache.shades = View.shades(snap) end
    return cache.shades
end

function Journal.who_of(snap, key, ctx, cache)
    local s = key ~= nil and snap.actors and snap.actors[key] or nil
    local a = s and s.actor
    local kind = a and a.kind or "other"
    local shade = PARTY[kind] and shades_of(snap, cache or {})[tostring(key)] or nil
    return { name = key ~= nil and name_of(snap, key, ctx) or ctx.i18n.t("other"), kind = kind, job = a and a.job,
             shade = shade }
end
local who_of = Journal.who_of

-- The fight's enemies by kind, the biggest kind first (largest full HP, then the kind the party's side hit last, then
-- the most HP taken, then the kind key): { { id, members = { { key, e = snap.enemies entry } } (by key), shown (the
-- same members by Journal.by_death), max_hp } }.
local function enemy_kinds(snap)
    local by_id, kinds = {}, {}
    for key, e in pairs(snap.enemies or {}) do
        local id = Fight.kind_key(e.actor)
        local kind = by_id[id]
        if not kind then
            kind = { id = id, members = {}, shown = {}, max_hp = 0, taken = 0, last_hit = 0 }
            by_id[id] = kind
            kinds[#kinds + 1] = kind
        end
        local s = snap.actors and snap.actors[key]
        kind.members[#kind.members + 1] = { key = key, e = e }
        kind.shown[#kind.shown + 1] = kind.members[#kind.members]
        kind.max_hp = math.max(kind.max_hp, e.max_hp or 0)
        kind.taken = kind.taken + (s and s.taken or 0)
        kind.last_hit = math.max(kind.last_hit, View.last_hit(e))
    end
    for _, kind in ipairs(kinds) do
        table.sort(kind.members, by_key)
        table.sort(kind.shown, Journal.by_death)
    end
    table.sort(kinds, function(a, b)
        if a.max_hp ~= b.max_hp then return a.max_hp > b.max_hp end
        if a.last_hit ~= b.last_hit then return a.last_hit > b.last_hit end
        if a.taken ~= b.taken then return a.taken > b.taken end
        return a.id < b.id
    end)
    return kinds
end

local function kind_label(kind, ctx)
    local name = View.actor_name(kind.members[1].e.actor, ctx)
    if #kind.members == 1 then return name end
    return name .. " ×" .. #kind.members
end

local function party_totals(snap)
    local t = { dealt = 0, taken = 0, healed = 0, def_before = 0, def_after = 0 }
    for _, s in pairs(snap.actors or {}) do
        if PARTY[s.actor.kind] then
            t.dealt, t.taken, t.healed = t.dealt + s.dealt, t.taken + s.taken, t.healed + s.heal_done
            t.def_before, t.def_after = t.def_before + s.enemy_def_before, t.def_after + s.enemy_def_after
        end
    end
    return t
end

function Journal.header(snap, ctx, index, count)
    local i18n = ctx.i18n
    local h = { numbers = {} }
    if count and count > 0 then h.fight = i18n.t("jfight_of", index or 1, count) end
    if snap == nil then
        h.line = i18n.t("jno_fights")
        return h
    end
    local duration = snap.duration or 0
    local parts = { i18n.t(snap.outcome == "win" and "victory" or "fight_over"), i18n.time(duration) }
    local kinds, names = enemy_kinds(snap), {}
    for i, kind in ipairs(kinds) do
        if i > MAX_KINDS then
            names[#names + 1] = i18n.t("jmore_kinds", #kinds - MAX_KINDS)
            break
        end
        names[#names + 1] = kind_label(kind, ctx)
    end
    if #names > 0 then parts[#parts + 1] = table.concat(names, ", ") end
    h.line = table.concat(parts, " · ")

    local p = party_totals(snap)
    h.numbers = {
        { label = i18n.t("dealt"), value = i18n.num(p.dealt), block = "damage" },
        { label = i18n.t("jnum_dps"), value = i18n.num(p.dealt / math.max(1, duration)) },
        { label = i18n.t("jnum_taken"), value = i18n.num(p.taken), block = "enemies" },
        { label = i18n.t("healed"), value = i18n.num(p.healed), block = "heal" },
        { label = i18n.t("enemy_defence_saved"),
          value = p.def_before > 0 and i18n.pct((p.def_before - p.def_after) / p.def_before) or "—" },
    }
    return h
end

-- HP left (0 once killed, the full HP while unknown) and the full HP of an enemy entry.
local function hp_of(e)
    local max = e.max_hp or 0
    if e.killed then return 0, max end
    return e.hp or max, max
end

local function fill_of(left, max, killed)
    if max <= 0 then return killed and 0 or 1 end
    return math.max(0, math.min(1, left / max))
end

local function hp_text(e, i18n)
    local left, max = hp_of(e)
    if e.killed then return i18n.num(max) .. " HP" end
    return i18n.num(left) .. " / " .. i18n.num(max) .. " HP"
end

local function enemy_row(m, ctx, member)
    local left, max = hp_of(m.e)
    return {
        id = "e:" .. tostring(m.key), label = View.actor_name(m.e.actor, ctx), hp_text = hp_text(m.e, ctx.i18n),
        fill = fill_of(left, max, m.e.killed), killed = m.e.killed == true, group = false, member = member,
    }
end

-- "<name> ×n" with "<hp> HP each" and, when some died, how many (as the summary's group rows).
local function kind_row(kind, ctx)
    local i18n = ctx.i18n
    local lo, hi, left, full, killed = math.huge, 0, 0, 0, 0
    for _, m in ipairs(kind.members) do
        local l, max = hp_of(m.e)
        lo, hi = math.min(lo, max), math.max(hi, max)
        left, full = left + l, full + max
        if m.e.killed then killed = killed + 1 end
    end
    local n = #kind.members
    local each = lo == hi and i18n.num(hi) or (i18n.num(lo) .. "–" .. i18n.num(hi))
    local text = i18n.t("enemy_group_hp", each)
    if killed > 0 then text = text .. " · " .. i18n.t("killed_count", killed, n) end
    return {
        id = "k:" .. kind.id, label = kind_label(kind, ctx), hp_text = text, fill = fill_of(left, full, killed == n),
        killed = killed == n, group = true, member = false,
    }
end

-- "75 000 HP · убит на 4:12 · добил Torinald": the HP text, then when and by whom it was killed.
local function death_text(snap, m, ctx)
    local i18n, e = ctx.i18n, m.e
    local parts = { hp_text(e, i18n) }
    if e.killed then
        if e.killed_at then parts[#parts + 1] = i18n.t("jkilled_at", i18n.time(e.killed_at)) end
        if e.killer then parts[#parts + 1] = i18n.t("jkilled_by", name_of(snap, e.killer, ctx)) end
    end
    return table.concat(parts, " · ")
end

-- A member of a kind card: "4:12 · 75 000 HP · добил Torinald" (when it died, its HP, who finished it), a living one
-- its HP; and who finished it.
local function death_of(snap, m, ctx, cache)
    local i18n, e = ctx.i18n, m.e
    local d = { label = View.actor_name(e.actor, ctx), text = death_text(snap, m, ctx), killed = e.killed == true }
    local parts = {}
    if e.killed and e.killed_at then parts[1] = i18n.time(e.killed_at) end
    parts[#parts + 1] = hp_text(e, i18n)
    if e.killed and e.killer then
        d.killer = who_of(snap, e.killer, ctx, cache)
        parts[#parts + 1] = i18n.t("jkilled_by", d.killer.name)
    end
    d.line = table.concat(parts, " · ")
    return d
end

-- A status by the game's message (a tutorial page title, «Недуг: отравление»: the part after the first ": "),
-- else by the mod's word; with a capital, as the game's messages differ in case («осмоление», «Быстродействующий яд»).
local function status_name(s, ctx)
    local text = s.message and ctx.names:message(s.message)
    if text then
        local cut = text:find(": ", 1, true)
        if cut then text = text:sub(cut + 2) end
    end
    if text == nil or text == "" then text = ctx.i18n.t("status_" .. s.name) end
    return I18n.upper_first(text)
end

-- "Защита 250": the game's label for the stat (message), else the mod's; nil when the value was not read.
local function stat_text(value, message, fallback, ctx)
    if not finite(value) then return nil end
    return (ctx.names:message(message) or ctx.i18n.t(fallback)) .. " " .. ctx.i18n.num(value)
end

-- What the game says about the kind (its EnemyData); data = false when there is no usable record.
local function game_of(detail, kind_id, ctx)
    local i18n = ctx.i18n
    local game = { data = false, weak = {}, resist = {}, immune = {} }
    local rec = type(detail) == "table" and type(detail.kinds) == "table" and detail.kinds[kind_id] or nil
    if type(rec) ~= "table" then return game end
    local weak, resist = whole(rec.weak), whole(rec.resist)
    if weak == nil or resist == nil then return game end
    game.data = true
    for _, w in ipairs(Journal.WEAK) do
        if (weak & w.bit) ~= 0 then game.weak[#game.weak + 1] = i18n.t(w.key) end
        if (resist & w.bit) ~= 0 then game.resist[#game.resist + 1] = i18n.t(w.key) end
    end
    local enabled = whole(rec.enabled)
    if enabled == nil then
        -- the statuses were not read: say so rather than «none»
        game.immune[1] = i18n.t("no_data")
    else
        for _, s in ipairs(Journal.STATUSES) do
            if (enabled & s.bit) == 0 then
                game.immune[#game.immune + 1] = Journal.mark_unclear(s.name, status_name(s, ctx))
            end
        end
    end
    local stats = {}
    stats[#stats + 1] = stat_text(rec.defence, "Status_1", "jdefence", ctx)
    stats[#stats + 1] = stat_text(rec.magic_defence, "Status_3", "jmagic_defence", ctx)
    if #stats > 0 then game.defence = table.concat(stats, " · ") end
    return game
end

-- The Foes (ledger.lua) of the members that the detail has.
local function foes_of(snap, members)
    local foes = type(snap.detail) == "table" and snap.detail.foes
    local list = {}
    if type(foes) ~= "table" then return list end
    for _, m in ipairs(members) do
        if type(foes[m.key]) == "table" then list[#list + 1] = foes[m.key] end
    end
    return list
end

local function fresh(t, key, new)
    local v = t[key]
    if v == nil then
        v = new()
        t[key] = v
    end
    return v
end

local function new_type() return { dealt = 0, before = 0, after = 0, hits = 0 } end
local function new_part() return { before = 0, after = 0 } end
local function new_by() return { dealt = 0, hits = 0, skills = {} } end
local function new_skill() return { hits = 0, total = 0, max = 0, before = 0, after = 0, types = {} } end
local function new_attack() return { dealt = 0, hits = 0, types = {} } end

-- t[key] when t is a table and that is one too (a damaged or older history may lack it or hold something else).
local function table_at(t, key)
    local v = type(t) == "table" and t[key] or nil
    return type(v) == "table" and v or nil
end

-- One Foe for a kind card: the members' counters summed; a skill entry keeps the ref of its part with the most hits.
-- by_part only from the members that have it (a fight kept before it existed has none).
local function merge_foes(list)
    if #list <= 1 then return list[1] end
    local out = { types = {}, by = {}, attacks = {}, by_part = { head = {}, body = {} } }
    local ref_hits = {}
    for _, foe in ipairs(list) do
        for jt, t in pairs(foe.types or {}) do
            local o = fresh(out.types, jt, new_type)
            o.dealt, o.before, o.after, o.hits = o.dealt + t.dealt, o.before + t.before, o.after + t.after, o.hits + t.hits
        end
        for part, o in pairs(out.by_part) do
            for jt, p in pairs(table_at(foe.by_part, part) or {}) do
                if type(p) == "table" and type(p.before) == "number" and type(p.after) == "number" then
                    local s = fresh(o, jt, new_part)
                    s.before, s.after = s.before + p.before, s.after + p.after
                end
            end
        end
        for key, by in pairs(foe.by or {}) do
            local o = fresh(out.by, key, new_by)
            o.dealt, o.hits = o.dealt + by.dealt, o.hits + by.hits
            for raw, sk in pairs(by.skills or {}) do
                local s = fresh(o.skills, raw, new_skill)
                if ref_hits[s] == nil or sk.hits > ref_hits[s] then s.ref, ref_hits[s] = sk.ref, sk.hits end
                s.hits, s.total, s.max = s.hits + sk.hits, s.total + sk.total, math.max(s.max, sk.max)
                s.before, s.after = s.before + (sk.before or 0), s.after + (sk.after or 0)
                for jt, v in pairs(sk.types or {}) do s.types[jt] = (s.types[jt] or 0) + v end
            end
        end
        for key, a in pairs(foe.attacks or {}) do
            local o = fresh(out.attacks, key, new_attack)
            o.dealt, o.hits = o.dealt + a.dealt, o.hits + a.hits
            for jt, n in pairs(a.types or {}) do o.types[jt] = (o.types[jt] or 0) + n end
        end
    end
    return out
end

-- "Режущий: голова ×1,4 · туловище ×1,0": one damage type on the two kinds of part, so that the line tells about the
-- enemy, not about the mix of hits. The type is the one with the most damage (types.dealt; ties in Ledger.TYPES order)
-- among those with a region step on both parts; nil without one, or when its two multipliers, as shown, are the same.
local function parts_text(foe, ctx)
    local head, body = table_at(foe.by_part, "head"), table_at(foe.by_part, "body")
    if not (head and body) then return nil end
    local best, most, rh, rb
    for _, jt in ipairs(Ledger.TYPES) do
        local h, b = table_at(head, jt), table_at(body, jt)
        local mh, mb = h and ratio(h.before, h.after), b and ratio(b.before, b.after)
        if mh and mb then
            local t = table_at(foe.types, jt)
            local dealt = t and finite(t.dealt) and t.dealt or 0
            if most == nil or dealt > most then best, most, rh, rb = jt, dealt, mh, mb end
        end
    end
    if best == nil then return nil end
    rh, rb = Ledger.round_mult(rh), Ledger.round_mult(rb)
    if rh == rb then return nil end
    return ctx.i18n.t("jparts_type", Journal.type_label(best), ctx.i18n.mult(rh), ctx.i18n.mult(rb))
end

-- "Чем его били": damage by journal type, value-descending; no detail: no_data, nothing that hit it: jno_hits, hits
-- that show no row: jno_damage.
local function types_block(detail, foe, ctx)
    local i18n = ctx.i18n
    local block = { title = i18n.t("jhit_with"), rows = {} }
    if type(detail) ~= "table" then
        block.empty = i18n.t("no_data")
        return block
    end
    local list = {}
    for jt, t in pairs(foe and foe.types or {}) do list[#list + 1] = { jt = jt, t = t } end
    table.sort(list, function(a, b)
        if a.t.dealt ~= b.t.dealt then return a.t.dealt > b.t.dealt end
        return type_before(a.jt, b.jt)
    end)
    local top = list[1] and list[1].t.dealt or 0
    for _, e in ipairs(list) do
        local row = with_mult({ label = Journal.type_label(e.jt), value = i18n.num(e.t.dealt),
                                fill = top > 0 and math.min(1, e.t.dealt / top) or 0 }, e.t.before, e.t.after, ctx)
        if shown(row, e.t.dealt) then block.rows[#block.rows + 1] = row end
    end
    if #block.rows == 0 then block.empty = i18n.t(#list > 0 and "jno_damage" or "jno_hits") end
    block.parts = foe and parts_text(foe, ctx) or nil
    return block
end

-- "Огонь", "Огонь + Магия": the skill's main type, "+ <second type>" when that one holds at least SECOND_TYPE of its
-- damage; nil without a type.
local function skill_types(g)
    local list, total = {}, 0
    for jt, v in pairs(g.types) do
        list[#list + 1] = { jt = jt, v = v }
        total = total + v
    end
    table.sort(list, function(a, b)
        if a.v ~= b.v then return a.v > b.v end
        return type_before(a.jt, b.jt)
    end)
    if not list[1] then return nil end
    local text = Journal.type_label(list[1].jt)
    if list[2] and total > 0 and list[2].v / total >= SECOND_TYPE then
        text = text .. " + " .. Journal.type_label(list[2].jt)
    end
    return text
end

local function job_label(actor, i18n)
    local job = actor and whole(actor.job)
    if job == nil or job < 1 or job > JOBS then return nil end
    return i18n.t("job_" .. job)
end

-- Best first: larger value, then the player before pawns (by slot), then key.
local function best_first(a, b)
    if a.value ~= b.value then return a.value > b.value end
    local oa, ob = a.actor and a.actor.order or 0, b.actor and b.actor.order or 0
    if oa ~= ob then return oa < ob end
    return tostring(a.key) < tostring(b.key)
end

-- A dealer's row (grey: an ally or Other), then its skills (as shown); a dealer of 0 only with a skill row kept.
-- `taken`: what the enemy took from every dealer (the shares' whole), `top`: the biggest dealer's value.
local function add_dealer(rows, e, ctx, shade, grey, taken, top)
    local i18n, actor = ctx.i18n, e.actor
    local function share_of(v) return i18n.pct(taken > 0 and v / taken or 0) end
    local skills = {}
    for _, g in ipairs(View.skill_groups(e.by.skills or {}, ctx)) do
        local name, types = ctx.names:skill(g.ref), skill_types(g)
        local row = with_mult({
            kind = "skill", label = types and (name .. " · " .. types) or name, name = name, type_text = types,
            hits = i18n.num(g.hits), value = i18n.num(g.value), share = share_of(g.value),
            avg = i18n.num(g.hits > 0 and g.value / g.hits or 0), max = i18n.num(g.max),
        }, g.before, g.after, ctx)
        if shown(row, g.value) then skills[#skills + 1] = row end
    end
    if shows_zero(e.value) and #skills == 0 then return end
    rows[#rows + 1] = {
        kind = "who", key = e.key, name = actor and View.actor_name(actor, ctx) or i18n.t("other"),
        job_label = job_label(actor, i18n), actor_kind = actor and actor.kind or "other",
        order = actor and actor.order, job = actor and actor.job, shade = shade,
        hits = i18n.num(e.by.hits), value = i18n.num(e.value), share = share_of(e.value),
        fill = top > 0 and math.max(0, math.min(1, e.value / top)) or 0, grey = grey,
    }
    for _, row in ipairs(skills) do rows[#rows + 1] = row end
end

-- "Кто чем нанёс": the party by value, then the allies and Other (grey); each with its skills; every row with its
-- share of all the enemy took. The band's total is the party's. empty = jno_damage when someone hit it and no row is
-- shown.
local function who_block(snap, foe, ctx, cache)
    local party, grey, total, taken, top = {}, {}, 0, 0, 0
    for key, by in pairs(foe and foe.by or {}) do
        local s = snap.actors and snap.actors[key]
        local e = { key = key, actor = s and s.actor, by = by, value = by.dealt }
        if e.actor and PARTY[e.actor.kind] then
            party[#party + 1] = e
            total = total + e.value
        else
            grey[#grey + 1] = e
        end
        taken, top = taken + e.value, math.max(top, e.value)
    end
    table.sort(party, best_first)
    table.sort(grey, function(a, b)
        local oa, ob = a.key == "other", b.key == "other"
        if oa ~= ob then return ob end
        return best_first(a, b)
    end)
    local shades = #party > 0 and shades_of(snap, cache) or {}
    local rows = {}
    for _, e in ipairs(party) do add_dealer(rows, e, ctx, shades[tostring(e.key)], false, taken, top) end
    for _, e in ipairs(grey) do add_dealer(rows, e, ctx, nil, true, taken, top) end
    local empty = #rows == 0 and (#party + #grey) > 0 and ctx.i18n.t("jno_damage") or nil
    return { title = ctx.i18n.t("jwho"), total = ctx.i18n.num(total), rows = rows, empty = empty }
end

-- "Дробящий ×5, Огонь ×1": hits by main type, the most first, then in Ledger.TYPES order.
local function type_counts(types, i18n)
    local list = {}
    for jt, n in pairs(types or {}) do
        if type(n) == "number" and n > 0 then list[#list + 1] = { jt = jt, n = n } end
    end
    table.sort(list, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        return type_before(a.jt, b.jt)
    end)
    local out = {}
    for _, e in ipairs(list) do out[#out + 1] = Journal.type_label(e.jt) .. " ×" .. i18n.num(e.n) end
    return table.concat(out, ", ")
end
Journal.type_counts = type_counts

-- "Кого бил сам": what the enemy did to each friend, by value.
local function attacks_block(snap, foe, ctx, cache)
    local i18n = ctx.i18n
    local list, total = {}, 0
    for key, a in pairs(foe and foe.attacks or {}) do
        list[#list + 1] = { key = key, who = who_of(snap, key, ctx, cache), value = a.dealt, types = a.types }
        list[#list].name = list[#list].who.name
        total = total + a.dealt
    end
    table.sort(list, function(a, b)
        if a.value ~= b.value then return a.value > b.value end
        if a.name ~= b.name then return a.name < b.name end
        return tostring(a.key) < tostring(b.key)
    end)
    local top = list[1] and list[1].value or 0
    local rows = {}
    for _, e in ipairs(list) do
        if not shows_zero(e.value) then
            local counts = type_counts(e.types, i18n)
            local w = e.who
            rows[#rows + 1] = { label = counts ~= "" and (e.name .. " · " .. counts) or e.name, name = e.name,
                                types = counts ~= "" and counts or nil, value = i18n.num(e.value),
                                fill = top > 0 and math.max(0, math.min(1, e.value / top)) or 0,
                                kind = w.kind, job = w.job, shade = w.shade }
        end
    end
    return { title = i18n.t("jattacks"), total = i18n.num(total), rows = rows }
end

-- The card of a list row; src = { kind_id, members } (a kind row: all of the kind, else the one enemy).
local function card_of(snap, ctx, row, src)
    local foe = merge_foes(foes_of(snap, src.members))
    local card = { title = row.label }
    local cache = {}
    if row.group then
        card.sub = row.hp_text
        card.deaths = {}
        for _, m in ipairs(src.members) do card.deaths[#card.deaths + 1] = death_of(snap, m, ctx, cache) end
    else
        local e = src.members[1].e
        card.sub = death_text(snap, src.members[1], ctx)
        if e.killed and e.killer then card.killer = who_of(snap, e.killer, ctx, cache) end
    end
    card.game = game_of(snap.detail, src.kind_id, ctx)
    card.types = types_block(snap.detail, foe, ctx)
    card.who = who_block(snap, foe, ctx, cache)
    card.attacks = attacks_block(snap, foe, ctx, cache)
    return card
end

function Journal.enemies(snap, ctx, sel)
    local rows, sources, count = {}, {}, 0
    for _, kind in ipairs(snap and enemy_kinds(snap) or {}) do
        count = count + #kind.members
        local whole_kind = { kind_id = kind.id, members = kind.shown }
        if #kind.members == 1 then
            rows[#rows + 1] = enemy_row(kind.members[1], ctx, false)
            sources[#rows] = whole_kind
        else
            rows[#rows + 1] = kind_row(kind, ctx)
            sources[#rows] = whole_kind
            for _, m in ipairs(kind.shown) do
                rows[#rows + 1] = enemy_row(m, ctx, true)
                sources[#rows] = { kind_id = kind.id, members = { m } }
            end
        end
    end
    local i = type(sel) == "number" and math.tointeger(sel) or 1
    i = math.max(1, math.min(i, #rows))
    return {
        list = { title = ctx.i18n.t("jenemies_count", count), rows = rows },
        sel = i,
        card = rows[i] and card_of(snap, ctx, rows[i], sources[i]) or nil,
    }
end

return Journal
