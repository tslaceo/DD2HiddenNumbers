-- The models of the journal's tabs besides Summary and Enemies: the Skills table, the Chart, the Damage to party, the
-- Healing and the Record of a fight's Snapshot, ready-to-draw strings like journal.lua. Pure functions, no game and no
-- drawing; snap nil (no fight yet) gives an empty model. ctx = { names = Names, i18n = i18n }. No row, chart chunk or
-- healer shows a value of 0 (Journal.shows_zero: a blocked blow, a grab); totals and shares still count it.
--
--   JournalTabs.skills(snap|nil, ctx, sel) -> { choices, sel, group, rows, total }
--     choices = { { id = "party"|actor key, name, kind, job, order, shade } }: the whole party (jparty_all), then the
--               party members by the damage they dealt, the most first (as the summary; ties in party order)
--     sel     = sel clamped to 1..#choices (1 when it is not a whole number); group = sel picks the whole party
--     rows    = { { label, who|nil, hits, value, avg, max, dps, share, fill, kind, job, order, shade } }: the whole
--               party's (member, skill) pairs with who = the member's name, else the chosen member's View.skill_groups;
--               value-descending; avg = value / hits, dps = value / max(1, duration), share of total, fill against
--               the top row; kind, job, order, shade of the member
--     total   = the selection's damage
--   JournalTabs.chart(snap|nil, ctx, sel) -> { bars, top, sel, list }
--     bars   = { { key, name, kind, job, order, shade, value: number, total, parts = { { label, value: number, text,
--              share, color } } } }: one per party member by the damage dealt, the most first (as Skills); its parts
--              bottom-up: its JournalTabs.TOP_SKILLS largest skills, the largest first, then jrest for the others
--     top    = the largest bar value (0 without one); sel = sel clamped to 1..#bars (1 when there are none)
--     list   = { { label, value, share, color } }: the skills of bars[sel], best first
--   color: which shade of its member's colour a part (or a skill of the list) takes: 1..JournalTabs.TOP_SKILLS (4)
--   by size, JournalTabs.REST (5) for jrest. A bar's value is what its member's skills took off; the parts and the
--   list have only the skills whose damage does not show as 0; share = of the bar's value.
--   JournalTabs.party(snap|nil, ctx) -> { members }
--     members = { { key, name, kind, job, order, shade, taken, fill, armor|nil, rows = { { label, name, types|nil,
--               value, fill, kind, job, shade } } } }: the party by the HP lost, the most first (ties in party order);
--               taken = the HP the member lost, fill = that against the biggest loss; armor = "≈ 1 032 · 88%" (the HP
--               his armor saved and the share it took, as
--               the summary) when the game reported a defence step; rows = what hit him: an enemy kind "Огр ·
--               Дробящий ×5, Огонь ×1" (several of the kind: "Ящер ×2 · ...", their hits by type from the detail
--               summed), another character by name, his own damage by its source (View.own_name: Blood Pact, Self;
--               his kind, job and shade), Other (no attacker); label = "name · types"; kind, job, shade of who hit him
--               ("enemy" for a kind, "other" for Other); value-descending, fill against the top row
--   JournalTabs.heal(snap|nil, ctx) -> { healers }
--     healers = { { key, name, kind, job, order, shade, total, rows = { { label, whom, whom_kind, whom_job,
--               whom_shade, source, value, count, times, fill } } } }: the party members who healed by order, then
--               the other healers by key, then Other; rows "→ Guts · Фруктовые пилюли" (label; whom the target and
--               his kind, job, shade; source the source name: the healing spot by the game's message, another skill
--               by the text `skill`, a member's own heal by its source: Lifesteal, Regeneration) per target and source
--               name, count = the heals, times = "862 раза" (jtimes);
--               value-descending, fill against the healer's top row
--   JournalTabs.record(snap|nil, ctx) -> { dropped|nil, rows }
--     rows    = { { time, who, whom, what, amount, heal, kill } }: the detail's record by time, a tie in counting
--               order (a held hit is counted late with its own time); who / whom by name (Other when unknown); what
--               = the friend's skill, a member's own damage by its source, the damage type of any other hit (an
--               enemy's, a neutral character's, one with no attacker), a status tick's status, a heal's source, else
--               normal attacks or the text `skill` (never an internal attack name); amount "+231" for a heal
--     dropped = jrecord_dropped(n) when the record lost its oldest n events
local Fight = require("DD2DamageMeter/fight")
local Journal = require("DD2DamageMeter/journal")
local View = require("DD2DamageMeter/view")

local JournalTabs = {}

local PARTY = { player = true, pawn = true }
local FRIEND = { player = true, pawn = true, ally = true }
local shows_zero = Journal.shows_zero
local TOP_SKILLS = 4
local REST = TOP_SKILLS + 1
JournalTabs.TOP_SKILLS, JournalTabs.REST = TOP_SKILLS, REST
local HEAL_SPOT = "ヒーリング"             -- part of the healing spot's attack name (game/hits.lua)
local HEAL_SPOT_MESSAGE = "job03_act_01" -- the game's name of that skill, the mage's Anodyne

-- The party members of a snapshot by order (the player, then the pawns by slot, then by key), each with the shade
-- of its vocation colour: { { key, stats, name, kind, job, order, shade } }.
local function members_of(snap, ctx)
    local list = {}
    if not snap then return list end
    for key, s in pairs(snap.actors or {}) do
        local a = s.actor
        if PARTY[a.kind] then
            list[#list + 1] = { key = key, stats = s, name = View.actor_name(a, ctx), kind = a.kind, job = a.job,
                                order = a.order, rank = a.order or (a.kind == "player" and 0 or math.huge) }
        end
    end
    table.sort(list, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        return tostring(a.key) < tostring(b.key)
    end)
    local shades = #list > 0 and View.shades(snap) or {}
    for _, m in ipairs(list) do
        m.shade = shades[tostring(m.key)]
        m.rank = nil
    end
    return list
end

-- A Stats counter as a number to sort and compare by: one that is not a finite number counts as 0.
local function counter(m, field)
    local v = tonumber(m.stats[field])
    if v == nil or v ~= v or v == math.huge or v == -math.huge then return 0 end
    return v
end

-- The members (members_of) by a Stats counter, the most first; ties keep party order.
local function most_first(members, field)
    local list = {}
    for i, m in ipairs(members) do list[i] = { m = m, i = i, v = counter(m, field) } end
    table.sort(list, function(a, b)
        if a.v ~= b.v then return a.v > b.v end
        return a.i < b.i
    end)
    for i, e in ipairs(list) do list[i] = e.m end
    return list
end

-- sel as a whole number in 1..n (1 when it is not one, or n is 0).
local function clamp(sel, n)
    local i = type(sel) == "number" and math.tointeger(sel) or 1
    return math.max(1, math.min(i, n))
end

local function groups_of(m, ctx)
    return View.skill_groups(m.stats.skills or {}, ctx)
end

function JournalTabs.skills(snap, ctx, sel)
    local i18n = ctx.i18n
    local members = most_first(members_of(snap, ctx), "dealt")
    local choices = { { id = "party", name = i18n.t("jparty_all") } }
    for _, m in ipairs(members) do
        choices[#choices + 1] = { id = m.key, name = m.name, kind = m.kind, job = m.job, order = m.order,
                                  shade = m.shade }
    end
    local i = clamp(sel, #choices)
    local group = i == 1
    -- (member, group) pairs of the selection, value-descending; ties keep the choices' order, then the groups'
    local list = {}
    for _, m in ipairs(group and members or { members[i - 1] }) do
        for _, g in ipairs(groups_of(m, ctx)) do list[#list + 1] = { m = m, g = g, n = #list + 1 } end
    end
    table.sort(list, function(a, b)
        if a.g.value ~= b.g.value then return a.g.value > b.g.value end
        return a.n < b.n
    end)
    local total = 0
    for _, e in ipairs(list) do total = total + e.g.value end
    local top = list[1] and list[1].g.value or 0
    local duration = math.max(1, snap and snap.duration or 0)
    local rows = {}
    for _, e in ipairs(list) do
        local m, g = e.m, e.g
        if not shows_zero(g.value) then
            rows[#rows + 1] = {
                label = ctx.names:skill(g.ref), who = group and m.name or nil,
                hits = i18n.num(g.hits), value = i18n.num(g.value),
                avg = i18n.num(g.hits > 0 and g.value / g.hits or 0), max = i18n.num(g.max),
                dps = i18n.num(g.value / duration), share = i18n.pct(total > 0 and g.value / total or 0),
                fill = top > 0 and math.min(1, g.value / top) or 0,
                kind = m.kind, job = m.job, order = m.order, shade = m.shade,
            }
        end
    end
    return { choices = choices, sel = i, group = group, rows = rows, total = i18n.num(total) }
end

function JournalTabs.chart(snap, ctx, sel)
    local i18n = ctx.i18n
    local members = most_first(members_of(snap, ctx), "dealt")
    local bars, top, groups = {}, 0, {}
    for n, m in ipairs(members) do
        -- what the member's skills took off, and those of them shown (best first)
        local value, shown = 0, {}
        for _, g in ipairs(groups_of(m, ctx)) do
            if g.value > 0 then value = value + g.value end
            if not shows_zero(g.value) then shown[#shown + 1] = g end
        end
        groups[n] = shown
        local parts, rest = {}, 0
        for j, g in ipairs(shown) do
            if j <= TOP_SKILLS then
                parts[j] = { label = ctx.names:skill(g.ref), value = g.value, text = i18n.num(g.value),
                             share = i18n.pct(g.value / value), color = j }
            else
                rest = rest + g.value
            end
        end
        if rest > 0 then
            parts[#parts + 1] = { label = i18n.t("jrest"), value = rest, text = i18n.num(rest),
                                  share = i18n.pct(rest / value), color = REST }
        end
        bars[n] = { key = m.key, name = m.name, kind = m.kind, job = m.job, order = m.order, shade = m.shade,
                    value = value, total = i18n.num(value), parts = parts }
        top = math.max(top, value)
    end
    local i = clamp(sel, #bars)
    local list = {}
    if bars[i] then
        local value = bars[i].value
        for j, g in ipairs(groups[i]) do
            list[j] = { label = ctx.names:skill(g.ref), value = i18n.num(g.value), share = i18n.pct(g.value / value),
                        color = j <= TOP_SKILLS and j or REST }
        end
    end
    return { bars = bars, top = top, sel = i, list = list }
end

-- The snapshot's detail (ledger.lua), nil without one.
local function detail_of(snap)
    local d = snap and snap.detail
    return type(d) == "table" and d or nil
end

-- A detail field that is not a table (a damaged history) read as an empty one.
local function table_or_empty(t)
    return type(t) == "table" and t or {}
end

-- The name of an actor key of the snapshot; Other for nil, "other" and a key it does not know.
local function name_of(snap, key, ctx)
    local s = key ~= nil and snap.actors and snap.actors[key]
    if not s then return ctx.i18n.t("other") end
    return View.actor_name(s.actor, ctx)
end

-- The member's armor text as the details' (View.armor_text); nil when the game reported no defence step.
local function armor_of(s, i18n)
    local before = s.armor_before or 0
    if not (before > 0) then return nil end
    return View.armor_text(before, s.armor_after or 0, s.armor_saved, i18n)
end

-- What hit a party member, by whom it is blamed on: an enemy kind (Fight.kind_key; its enemies counted, their hits by
-- type from the detail summed), another character, his own damage by its source (View.own_name), or Other (no
-- attacker, or one the snapshot does not know).
local function taken_rows(snap, m, ctx, cache)
    local i18n = ctx.i18n
    local d = detail_of(snap)
    local foes = table_or_empty(d and d.foes)
    local by, list = {}, {}
    for akey, amount in pairs(m.stats.taken_from or {}) do
        local own = View.own_name(akey, i18n)
        local s = not own and akey ~= "other" and snap.actors[akey] or nil
        local actor = s and s.actor
        local enemy = actor ~= nil and actor.kind == "enemy"
        local id = (own and "s:" .. akey) or (enemy and "k:" .. Fight.kind_key(actor))
            or (actor and "a:" .. tostring(akey)) or "other"
        local g = by[id]
        if not g then
            g = { id = id, value = 0, enemies = 0, types = {}, own = own }
            by[id] = g
            list[#list + 1] = g
        end
        g.value = g.value + amount
        -- a kind is named after its enemy of the smallest key
        if actor and (g.key == nil or tostring(akey) < tostring(g.key)) then g.key, g.actor = akey, actor end
        if enemy then
            g.enemies = g.enemies + 1
            local foe = foes[akey]
            local hits = type(foe) == "table" and type(foe.attacks) == "table" and foe.attacks[m.key] or nil
            for jt, n in pairs(type(hits) == "table" and table_or_empty(hits.types) or {}) do
                g.types[jt] = (g.types[jt] or 0) + n
            end
        end
    end
    for _, g in ipairs(list) do
        -- his own damage: in his colour, by its source's name
        g.who = Journal.who_of(snap, g.own and m.key or g.key, ctx, cache)
        if g.own then g.who.name = g.own end
        local name = g.who.name
        if g.enemies > 1 then name = name .. " ×" .. g.enemies end
        local counts = Journal.type_counts(g.types, i18n)
        g.name, g.types_text = name, counts ~= "" and counts or nil
        g.label = counts ~= "" and (name .. " · " .. counts) or name
    end
    table.sort(list, function(a, b)
        if a.value ~= b.value then return a.value > b.value end
        if a.label ~= b.label then return a.label < b.label end
        return a.id < b.id
    end)
    local top = list[1] and list[1].value or 0
    local rows = {}
    for _, g in ipairs(list) do
        if not shows_zero(g.value) then
            rows[#rows + 1] = { label = g.label, name = g.name, types = g.types_text, value = i18n.num(g.value),
                                fill = top > 0 and math.min(1, g.value / top) or 0, kind = g.who.kind, job = g.who.job,
                                shade = g.who.shade }
        end
    end
    return rows
end

function JournalTabs.party(snap, ctx)
    local i18n = ctx.i18n
    local members = {}
    local list = most_first(members_of(snap, ctx), "taken")
    local top = list[1] and counter(list[1], "taken") or 0
    local cache = {}
    for _, m in ipairs(list) do
        members[#members + 1] = {
            key = m.key, name = m.name, kind = m.kind, job = m.job, order = m.order, shade = m.shade,
            taken = i18n.num(m.stats.taken), fill = top > 0 and math.min(1, counter(m, "taken") / top) or 0,
            armor = armor_of(m.stats, i18n), rows = taken_rows(snap, m, ctx, cache),
        }
    end
    return { members = members }
end

-- A heal's source by name: an item by the game's text, the healing spot by the game's message, any other skill (or
-- the spot without its message) and an item the game did not name by the mod's word, never by an internal attack
-- name; a skill by its id as skills are named (Argent Tonic); a member's own heal by its source (View.own_name);
-- anything else Other.
local function source_name(source, ctx)
    local i18n = ctx.i18n
    if type(source) ~= "string" then return i18n.t("other") end
    local own = View.own_name(source, i18n)
    if own then return own end
    local skill_id = source:match("^skill_id:(.+)$")
    if skill_id then return ctx.names:skill({ id = skill_id }) end
    local id = source:match("^item:(.*)$")
    if id then
        if id == "" or id == "?" then return i18n.t("item") end
        return ctx.names:item(tonumber(id) or id)
    end
    local name = source:match("^skill:(.*)$")
    if name then
        return name:find(HEAL_SPOT, 1, true) and ctx.names:message(HEAL_SPOT_MESSAGE) or i18n.t("skill")
    end
    return i18n.t("other")
end

-- A healer's rows, one per target and source name (the healing spot and its larger form are one row), and his total.
local function heal_rows(snap, by_target, ctx, cache)
    local i18n = ctx.i18n
    local by, list, total = {}, {}, 0
    for target, by_source in pairs(table_or_empty(by_target)) do
        local who = Journal.who_of(snap, target, ctx, cache)
        local whom = who.name
        for source, cell in pairs(table_or_empty(by_source)) do
            if type(cell) == "table" then
                local from = source_name(source, ctx)
                local label = "→ " .. whom .. " · " .. from
                local id = tostring(target) .. "\0" .. label
                local r = by[id]
                if not r then
                    r = { id = id, label = label, amount = 0, n = 0, whom = whom, whom_kind = who.kind,
                          whom_job = who.job, whom_shade = who.shade, source = from }
                    by[id] = r
                    list[#list + 1] = r
                end
                local amount = tonumber(cell.amount) or 0
                r.amount, r.n = r.amount + amount, r.n + (tonumber(cell.n) or 0)
                total = total + amount
            end
        end
    end
    table.sort(list, function(a, b)
        if a.amount ~= b.amount then return a.amount > b.amount end
        return a.id < b.id
    end)
    local top = list[1] and list[1].amount or 0
    local rows = {}
    for _, r in ipairs(list) do
        if not shows_zero(r.amount) then
            rows[#rows + 1] = { label = r.label, whom = r.whom, whom_kind = r.whom_kind, whom_job = r.whom_job,
                                whom_shade = r.whom_shade, source = r.source, value = i18n.num(r.amount), count = r.n,
                                times = i18n.tn("jtimes", r.n), fill = top > 0 and math.min(1, r.amount / top) or 0 }
        end
    end
    return rows, total
end

function JournalTabs.heal(snap, ctx)
    local i18n = ctx.i18n
    local d = detail_of(snap)
    local heals = table_or_empty(d and d.heals)
    -- the party members who healed by order, then anyone else who did (an ally) by key, then Other
    local list, party = {}, {}
    for _, m in ipairs(members_of(snap, ctx)) do
        if heals[m.key] ~= nil then list[#list + 1] = m end
        party[m.key] = true
    end
    local others = {}
    for key in pairs(heals) do
        if not party[key] and key ~= "other" then others[#others + 1] = key end
    end
    table.sort(others, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(others) do
        local s = snap.actors and snap.actors[key]
        local a = s and s.actor
        list[#list + 1] = { key = key, name = name_of(snap, key, ctx), kind = a and a.kind or "other", job = a and a.job,
                            order = a and a.order }
    end
    if heals.other ~= nil then list[#list + 1] = { key = "other", name = i18n.t("other"), kind = "other" } end
    local healers = {}
    local cache = {}
    for _, h in ipairs(list) do
        local rows, total = heal_rows(snap, heals[h.key], ctx, cache)
        if not shows_zero(total) then
            healers[#healers + 1] = { key = h.key, name = h.name, kind = h.kind, job = h.job, order = h.order,
                                      shade = h.shade, total = i18n.num(total), rows = rows }
        end
    end
    return { healers = healers }
end

-- An event's time (seconds since the fight's start); 0 when it is not a number.
local function time_of(e)
    local t = e.t
    if type(t) ~= "number" or t ~= t then return 0 end
    return t
end

-- What a hit was done with: a member's own damage by its source ("self:<source>"), a friend's skill by its entry in
-- the snapshot (named as in the details), the damage type of any other hit ("t:<jt>"), a status tick's status, else
-- (friendly fire, a hit on an object, a key the snapshot has no entry for) normal attacks or the mod's word: an
-- internal attack name or id is never shown.
local function hit_what(snap, e, ctx)
    local names = ctx.names
    local s = type(e.s) == "string" and e.s or "?"
    local own = View.own_name(s, ctx.i18n)
    if own then return own end
    local by = e.a ~= nil and snap.actors and snap.actors[e.a]
    if by and by.actor and FRIEND[by.actor.kind] then
        local sk = type(by.skills) == "table" and by.skills[s]
        if type(sk) == "table" and sk.ref then return names:skill(sk.ref) end
    end
    local jt = s:match("^t:(.+)$")
    if jt then return Journal.type_label(jt) end
    local status = s:match("^status:(.+)$")
    if status then return names:skill({ status = status }) end
    if names:skill_key({ attack = s }) == "normal" then return ctx.i18n.t("normal_attacks") end
    return ctx.i18n.t("skill")
end

function JournalTabs.record(snap, ctx)
    local i18n = ctx.i18n
    local m = { rows = {} }
    local d = detail_of(snap)
    if not d then return m end
    local dropped = d.record_dropped
    if type(dropped) == "number" and dropped >= 1 and dropped < math.huge then
        m.dropped = i18n.t("jrecord_dropped", math.floor(dropped))
    end
    -- the ledger keeps counting order; a held hit, counted when its enemy is engaged, goes back to its own time
    local events = {}
    for i, e in ipairs(table_or_empty(d.record)) do
        if type(e) == "table" then events[#events + 1] = { e = e, t = time_of(e), i = i } end
    end
    table.sort(events, function(a, b)
        if a.t ~= b.t then return a.t < b.t end
        return a.i < b.i
    end)
    for _, x in ipairs(events) do
        local e = x.e
        local heal = e.k == "heal"
        m.rows[#m.rows + 1] = {
            time = i18n.time(x.t), who = name_of(snap, e.a, ctx), whom = name_of(snap, e.v, ctx),
            what = heal and source_name(e.s, ctx) or hit_what(snap, e, ctx),
            amount = (heal and "+" or "") .. i18n.num(e.n), heal = heal, kill = e.kill == true,
        }
    end
    return m
end

return JournalTabs
