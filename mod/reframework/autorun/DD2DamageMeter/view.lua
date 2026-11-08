-- Display models: a Snapshot turned into rows of ready-to-draw strings for the live window,
-- the post-fight summary and the per-character details. Pure functions, no game and no
-- drawing; the window only lays the rows out.
-- ctx = { names = Names, i18n = i18n }; both are passed in so texts and names can be stubbed.
-- show = the player's switches (nil: everything): a block whose key is false is not built (nil in the model), and
-- `allies` / `other` = false leave the ally rows / the Other rows (Other, "Falls and environment") out of the blocks
-- that have them.
--   View.live:    damage, taken, heal, allies, other
--   View.summary: enemies, damage, allies, other, heal, armor
-- The live window's header = { title, time, key, hp_text }: key is the actor key of the enemy it is about (nil without
-- one), hp_text that enemy's View.header_hp.
--   View.header_hp(e, i18n) -> "31 200 / 80 000" | nil   a snapshot's (or the fight's) enemy entry { max_hp, hp,
--     killed }: its HP left (0 once killed, its full HP while not known) / its full HP; nil without a full HP
--     (DD2DamageMeter.lua puts the HP its HP numbers read into the header between two builds of the live window)
-- Shared with the journal (journal.lua):
--   View.actor_name(actor, ctx) -> string
--   View.own_name(key, i18n) -> string | nil   the name of a member's own source ("self:blood_pact", "self:self",
--     "self:lifesteal", "self:regen": Fight's taken_from and heal source keys), nil for any other key
--   View.armor_text(before, after, saved, i18n) -> "≈ 1 032 · 88%"   HP saved and the share a defence step took off
--     (before > 0)
--   View.shades(snap) -> table<tostring(actor key), integer>   which member of its vocation each party member is
--   View.last_hit(snap.enemies entry) -> number   when the party's side last hit it, 0 for never (or not kept);
--     enemies of the same full HP go by it, the latest first
--   View.skill_groups(skills, ctx) -> { { key, ref, hits, value, max, perfect, before, after, types } }
--     skill entries (raw key -> { ref, hits, total, max[, before, after, types] }) merged into skills, best first
local Fight = require("DD2DamageMeter/fight")

local View = {}

local PARTY = { player = true, pawn = true }
local ALLY = { ally = true }

-- Whether `show` leaves `key` on: it does unless `show` is a table that has false there.
local function wanted(show, key)
    return type(show) ~= "table" or show[key] ~= false
end

-- Seconds a fight has lasted. The snapshot already knows it; `now` only covers a snapshot
-- that carries no duration.
local function duration_of(snap, now)
    return snap.duration or math.max(0, (snap.t1 or now or snap.t0) - snap.t0)
end

local function per_second(value, duration)
    return value / math.max(1, duration)
end

-- Best first: larger value, then player before pawns (by slot), then key.
local function sort_entries(list)
    table.sort(list, function(a, b)
        if a.value ~= b.value then return a.value > b.value end
        local oa, ob = a.order or 0, b.order or 0
        if oa ~= ob then return oa < ob end
        return a.key < b.key
    end)
end

local function fill_of(value, top)
    return top > 0 and math.min(1, value / top) or 0
end

-- The fight's pseudo-actors (fight.lua) by key: unattributed damage and healing, the enemies' own damage.
local PSEUDO = { other = "other", env = "env" }

-- Enemies are named by the game's text for their kind, the pseudo-actors by their texts ("Other", "Falls and
-- environment"), everyone else keeps the name the actor was given.
local function actor_name(actor, ctx)
    local pseudo = PSEUDO[actor.key]
    if pseudo then return ctx.i18n.t(pseudo) end
    if actor.kind == "enemy" then return ctx.names:enemy(actor.base_id or actor.key) end
    return actor.name or actor.key
end
View.actor_name = actor_name

-- A member's own damage and heals by source.
local OWN = { blood_pact = "own_blood_pact", self = "own_self", lifesteal = "own_lifesteal", regen = "own_regen" }

function View.own_name(key, i18n)
    local source = type(key) == "string" and key:match("^self:(.+)$")
    local text = source and OWN[source]
    return text and i18n.t(text) or nil
end

-- Which member of their vocation each party member of the fight is (1, 2, 3 by party order: the player, then the
-- pawns by slot), by actor key; the vocations not known count as one. Every party member of the snapshot counts,
-- with a row or not, so a character's shade does not change when another starts hitting.
local function shades(snap)
    local list = {}
    for key, s in pairs(snap.actors) do
        local a = s.actor
        if PARTY[a.kind] then
            local order = a.order or (a.kind == "player" and 0 or math.huge)
            list[#list + 1] = { key = tostring(key), order = order, job = a.job or "?" }
        end
    end
    table.sort(list, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.key < b.key
    end)
    local ranks, count = {}, {}
    for _, e in ipairs(list) do
        count[e.job] = (count[e.job] or 0) + 1
        ranks[e.key] = count[e.job]
    end
    return ranks
end
View.shades = shades

-- Characters of the given kinds ranked by the Stats counter `field`. A character is listed
-- when that counter or the counter `also` is above zero (a striker whose blows were all
-- absorbed still has a row), best first.
local function ranked(snap, kinds, field, also)
    local list, shade = {}, nil
    for key, s in pairs(snap.actors) do
        if kinds[s.actor.kind] and (s[field] > 0 or (also and s[also] > 0)) then
            shade = shade or shades(snap)
            list[#list + 1] = { key = key, order = s.actor.order, stats = s, value = s[field], shade = shade[tostring(key)] }
        end
    end
    sort_entries(list)
    return list
end

local function total_of(list)
    local sum = 0
    for _, e in ipairs(list) do sum = sum + e.value end
    return sum
end

-- A pseudo-actor of the fight (`key`: "other" for damage and healing nobody can be blamed for; "env" for
-- the enemies' own damage) as a list entry for the Stats counter `field`; nil when it has nothing there. Looked up by
-- its key: an object also has the kind "other".
local function pseudo_entry(snap, key, field)
    local s = snap.actors[key]
    if s and s.actor.key == key and (s[field] or 0) > 0 then
        return { key = key, stats = s, value = s[field] }
    end
    return nil
end

-- One row of a character list: `total` (when given) adds a share, `duration` a per-second value.
-- `order` is the pawn's roster slot (nil for the player and allies), `job` the party member's vocation (nil when
-- unknown) and `shade` which member of that vocation it is (see shades); the window colours by them.
local function character_row(e, name, ctx, top, total, duration)
    local i18n = ctx.i18n
    local row = {
        key = e.key, name = name, kind = e.stats.actor.kind, order = e.stats.actor.order, job = e.stats.actor.job,
        shade = e.shade,
        value = i18n.num(e.value), fill = fill_of(e.value, top),
    }
    if duration then row.per_sec = i18n.num(per_second(e.value, duration)) .. i18n.t("per_sec") end
    if total then row.share = i18n.pct(total > 0 and e.value / total or 0) end
    return row
end

-- Damage rows of the party (with shares; none when the damage block is off) and the grey rows (outside totals and
-- shares): the allies, then the enemies' own damage ("Falls and environment"), then Other, each unless `show` leaves
-- it out (the last two both follow `other`).
local function damage_rows(snap, ctx, duration, show)
    local party = ranked(snap, PARTY, "dealt", "hits")
    local grey = wanted(show, "allies") and ranked(snap, ALLY, "dealt", "hits") or {}
    if wanted(show, "other") then
        grey[#grey + 1] = pseudo_entry(snap, "env", "dealt")
        grey[#grey + 1] = pseudo_entry(snap, "other", "dealt")
    end
    local total = total_of(party)
    local top = party[1] and party[1].value or 0
    -- grey rows are measured against the party's best; with no party damage, against the biggest of their own
    local grey_top = top
    if top <= 0 then
        for _, e in ipairs(grey) do grey_top = math.max(grey_top, e.value) end
    end
    local party_rows, grey_rows = {}, {}
    for _, e in ipairs(wanted(show, "damage") and party or {}) do
        party_rows[#party_rows + 1] = character_row(e, actor_name(e.stats.actor, ctx), ctx, top, total, duration)
    end
    for _, e in ipairs(grey) do
        grey_rows[#grey_rows + 1] = character_row(e, actor_name(e.stats.actor, ctx), ctx, grey_top, nil, duration)
    end
    return party_rows, grey_rows, total
end

-- "Guts (potion)" for a healer whose healing came only from items, his own heals (lifesteal, regeneration) left aside;
-- the plain name otherwise.
local function heal_name(s, ctx)
    local name = actor_name(s.actor, ctx)
    local items = {}
    for source, amount in pairs(s.heal_sources) do
        if amount > 0 and source:sub(1, 5) ~= "self:" then
            local id = source:match("^item:(.*)$")
            if not id then return name end
            items[#items + 1] = { source = source, id = tonumber(id) or id, amount = amount }
        end
    end
    if #items == 0 then return name end
    table.sort(items, function(a, b)
        if a.amount ~= b.amount then return a.amount > b.amount end
        return a.source < b.source
    end)
    local labels = {}
    for _, item in ipairs(items) do
        labels[#labels + 1] = item.id == "?" and ctx.i18n.t("item") or ctx.names:item(item.id)
    end
    return string.format("%s (%s)", name, table.concat(labels, ", "))
end

-- Party healing rows (with shares), then the grey Other row (no share, outside the total) unless `show` leaves it out.
local function heal_rows(snap, ctx, duration, show)
    local list = ranked(snap, PARTY, "heal_done")
    local other = wanted(show, "other") and pseudo_entry(snap, "other", "heal_done") or nil
    local top = list[1] and list[1].value or 0
    local total = total_of(list)
    local rows = {}
    for _, e in ipairs(list) do
        rows[#rows + 1] = character_row(e, heal_name(e.stats, ctx), ctx, top, total, duration)
    end
    if other then
        rows[#rows + 1] = character_row(other, actor_name(other.stats.actor, ctx), ctx, top > 0 and top or other.value,
            nil, duration)
    end
    return rows, total
end

-- Who a taken-damage entry is blamed on: the attacker's actor (nil when unknown) and the key
-- rows are merged by (enemies of one kind, see Fight.kind_key, share it); a member's own damage is its source's name.
local function blame(snap, attacker_key, ctx)
    local own = View.own_name(attacker_key, ctx.i18n)
    if own then return nil, attacker_key, own end
    local a = attacker_key ~= "other" and snap.actors[attacker_key]
    local actor = a and a.actor
    if not actor then return nil, "other" end
    if actor.kind == "enemy" then return actor, "enemy:" .. Fight.kind_key(actor) end
    return actor, attacker_key
end

-- "enemy → member" rows. Enemies of one kind that hit the same member are one row with a
-- count; a member's own damage is "Blood Pact → member" or "Self → member"; a hit nobody can be blamed for is
-- "Other". Also the rows' total.
local function taken_rows(snap, ctx)
    local list = {}
    for _, v in pairs(snap.actors) do
        if PARTY[v.actor.kind] then
            local mine = {} -- this member's rows by what they are blamed on
            for attacker_key, amount in pairs(v.taken_from) do
                if amount > 0 then
                    local attacker, who, own = blame(snap, attacker_key, ctx)
                    local g = mine[who]
                    if not g then
                        g = { value = 0, count = 0, attacker = attacker, victim = v.actor, own = own }
                        mine[who] = g
                        list[#list + 1] = g
                    end
                    g.value = g.value + amount
                    g.count = g.count + 1
                end
            end
        end
    end
    for _, g in ipairs(list) do
        local who = g.own or (g.attacker and actor_name(g.attacker, ctx)) or ctx.i18n.t("other")
        if g.attacker and g.attacker.kind == "enemy" and g.count > 1 then who = who .. " ×" .. g.count end
        g.label = who .. " → " .. actor_name(g.victim, ctx)
        g.key = g.label
    end
    sort_entries(list)
    local top = list[1] and list[1].value or 0
    local rows = {}
    for _, g in ipairs(list) do
        rows[#rows + 1] = { label = g.label, value = ctx.i18n.num(g.value), fill = fill_of(g.value, top) }
    end
    return rows, total_of(list)
end

-- When the party's side last hit an enemy entry (Fight's last_hit); 0 for never, or for an entry kept without it.
local function last_hit(e)
    local t = e.last_hit
    if type(t) == "number" and t == t then return t end
    return 0
end
View.last_hit = last_hit

-- Enemies the fight saw, the biggest first: largest full HP, then the one the party's side hit last, then the most
-- damage taken. An enemy that only hit the party has no HP yet: its full HP is shown.
local function enemy_entries(snap)
    local list = {}
    for key, e in pairs(snap.enemies) do
        local s = snap.actors[key]
        list[#list + 1] = {
            key = key, actor = e.actor, max_hp = e.max_hp or 0, hp = e.hp or e.max_hp or 0,
            killed = e.killed, taken = s and s.taken or 0, last_hit = last_hit(e),
        }
    end
    table.sort(list, function(a, b)
        if a.max_hp ~= b.max_hp then return a.max_hp > b.max_hp end
        if a.last_hit ~= b.last_hit then return a.last_hit > b.last_hit end
        if a.taken ~= b.taken then return a.taken > b.taken end
        return a.key < b.key
    end)
    return list
end

-- "31 200 / 80 000": an enemy entry's HP left (0 once killed, its full HP while not known) and full HP; nil without a
-- full HP.
local function header_hp(e, i18n)
    local max_hp = e.max_hp or 0
    if max_hp <= 0 then return nil end
    return i18n.num(e.killed and 0 or e.hp or max_hp) .. " / " .. i18n.num(max_hp)
end
View.header_hp = header_hp

local function header_model(snap, duration, ctx)
    local i18n = ctx.i18n
    local main = enemy_entries(snap)[1]
    local header = { title = "", time = i18n.time(duration) }
    if main then
        header.title, header.key = actor_name(main.actor, ctx), main.key
        header.hp_text = header_hp(main, i18n)
    end
    return header
end

local function killed_in(list)
    local n = 0
    for _, e in ipairs(list) do
        if e.killed then n = n + 1 end
    end
    return n
end

local function hp_bounds(list)
    local lo, hi = list[1].max_hp, list[1].max_hp
    for _, e in ipairs(list) do
        lo, hi = math.min(lo, e.max_hp), math.max(hi, e.max_hp)
    end
    return lo, hi
end

-- Row of one kind of enemy: a single enemy shows "HP left / full HP" (0 once killed), several
-- "<name> ×n" with "<hp> HP each" and, when some died, how many. `killed` when every one of them died.
local function group_row(group, ctx)
    local i18n = ctx.i18n
    local name = actor_name(group[1].actor, ctx)
    if #group == 1 then
        local e = group[1]
        return { label = name, hp_text = i18n.num(e.killed and 0 or e.hp) .. " / " .. i18n.num(e.max_hp) .. " HP",
            killed = e.killed == true }
    end
    local lo, hi = hp_bounds(group)
    local each = lo == hi and i18n.num(hi) or (i18n.num(lo) .. "–" .. i18n.num(hi))
    local killed = killed_in(group)
    local text = i18n.t("enemy_group_hp", each)
    if killed > 0 then text = text .. " · " .. i18n.t("killed_count", killed, #group) end
    return { label = name .. " ×" .. #group, hp_text = text, killed = killed == #group }
end

-- Enemies split into kinds (Fight.kind_key: the CharaID, else the base_id): { id, list, max_hp } each, in no
-- particular order.
local function kinds_of(entries)
    local by_id, kinds = {}, {}
    for _, e in ipairs(entries) do
        local id = Fight.kind_key(e.actor)
        local kind = by_id[id]
        if not kind then
            kind = { id = id, list = {}, max_hp = 0 }
            by_id[id] = kind
            kinds[#kinds + 1] = kind
        end
        kind.list[#kind.list + 1] = e
        kind.max_hp = math.max(kind.max_hp, e.max_hp)
    end
    return kinds
end

local MAX_GROUP_ROWS = 3 -- kinds besides the main one that get a row of their own

-- The main enemy (with all of its kind), then the other kinds as group rows (most numerous
-- first, then the biggest HP), then everything left over counted in one row; a lone leftover
-- enemy is named instead.
local function enemy_rows(snap, ctx)
    local list = enemy_entries(snap)
    if #list == 0 then return {} end
    local main_id = Fight.kind_key(list[1].actor)
    local main, others = nil, {}
    for _, kind in ipairs(kinds_of(list)) do
        if kind.id == main_id then main = kind else others[#others + 1] = kind end
    end
    table.sort(others, function(a, b)
        if #a.list ~= #b.list then return #a.list > #b.list end
        if a.max_hp ~= b.max_hp then return a.max_hp > b.max_hp end
        return a.id < b.id
    end)
    local rows = { group_row(main.list, ctx) }
    local rest = {}
    for i, kind in ipairs(others) do
        if i <= MAX_GROUP_ROWS then
            rows[#rows + 1] = group_row(kind.list, ctx)
        else
            for _, e in ipairs(kind.list) do rest[#rest + 1] = e end
        end
    end
    if #rest == 1 then
        rows[#rows + 1] = group_row(rest, ctx)
    elseif #rest > 1 then
        local i18n = ctx.i18n
        local lo, hi = hp_bounds(rest)
        local label = lo == hi and i18n.t("more_enemies_same_hp", #rest, i18n.num(lo))
            or i18n.t("more_enemies", #rest, i18n.num(lo), i18n.num(hi))
        local killed = killed_in(rest)
        rows[#rows + 1] = { label = label, hp_text = i18n.t("killed_count", killed, #rest), killed = killed == #rest }
    end
    return rows
end

-- "≈ 1 032 · 88%": HP saved (recomputed, hence the ≈) and the share the defence took off.
local function armor_text(before, after, saved, i18n)
    return "≈ " .. i18n.num(saved) .. " · " .. i18n.pct((before - after) / before)
end
View.armor_text = armor_text

-- One row per side that the game reported numbers for; none when it reported nothing.
local function armor_rows(snap, ctx)
    local i18n = ctx.i18n
    local def_before, def_after, def_saved = 0, 0, 0
    local arm_before, arm_after, arm_saved = 0, 0, 0
    for _, s in pairs(snap.actors) do
        if PARTY[s.actor.kind] then
            def_before, def_after, def_saved =
                def_before + s.enemy_def_before, def_after + s.enemy_def_after, def_saved + s.enemy_def_saved
            arm_before, arm_after, arm_saved =
                arm_before + s.armor_before, arm_after + s.armor_after, arm_saved + s.armor_saved
        end
    end
    local rows = {}
    if def_before > 0 then
        rows[#rows + 1] = { label = i18n.t("enemy_defence_saved"), value = armor_text(def_before, def_after, def_saved, i18n) }
    end
    if arm_before > 0 then
        rows[#rows + 1] = { label = i18n.t("party_armor_saved"), value = armor_text(arm_before, arm_after, arm_saved, i18n) }
    end
    return rows
end

-- A row keyed by an attack name's core (no skill id: a late hit the game no longer tied to its skill) joins the skill
-- row whose attack names have that core, when only one skill row has it; normal attacks and status rows stay apart.
local function merge_cores(list)
    local into = {}  -- core -> the one id row that has it, false when several do
    for _, g in ipairs(list) do
        if g.id then
            for core in pairs(g.cores) do into[core] = into[core] == nil and g end
        end
    end
    local out = {}
    for _, g in ipairs(list) do
        local target = not g.id and g.key ~= "normal" and g.key ~= "?" and not g.key:find("^dot:") and into[g.key]
        if target then
            target.value, target.hits = target.value + g.value, target.hits + g.hits
            target.max, target.perfect = math.max(target.max, g.max), target.perfect + g.perfect
            target.before, target.after = target.before + g.before, target.after + g.after
            for jt, v in pairs(g.types) do target.types[jt] = (target.types[jt] or 0) + v end
        else
            out[#out + 1] = g
        end
    end
    return out
end

-- Raw skill keys (every charge level and follow-up of a game attack) merged by names:skill_key, then the rows keyed by
-- an attack's core into their skill (merge_cores), best first. The ledger's entries also carry the damage before and
-- after the region step and the damage by journal type: summed too (0 and {} where the entries have none).
function View.skill_groups(skills, ctx)
    local groups, list = {}, {}
    for raw, sk in pairs(skills) do
        local key = ctx.names:skill_key(sk.ref)
        local g = groups[key]
        if not g then
            g = { key = key, value = 0, hits = 0, max = 0, perfect = 0, before = 0, after = 0, types = {},
                  best = -math.huge, cores = {} }
            groups[key] = g
            list[#list + 1] = g
        end
        g.value = g.value + sk.total
        g.hits = g.hits + sk.hits
        g.max = math.max(g.max, sk.max)
        g.before = g.before + (sk.before or 0)
        g.after = g.after + (sk.after or 0)
        for jt, v in pairs(sk.types or {}) do g.types[jt] = (g.types[jt] or 0) + v end
        local attack = sk.ref and sk.ref.attack
        if type(attack) == "string" and attack:find("_極", 1, true) then g.perfect = g.perfect + sk.hits end
        if sk.ref and sk.ref.id ~= nil then
            g.id = true
            if type(attack) == "string" then g.cores[ctx.names:skill_key({ attack = attack })] = true end
        end
        -- the biggest part names the row (ties: the smaller raw key, for a stable pick)
        local name = tostring(raw)
        if sk.total > g.best or (sk.total == g.best and name < g.raw) then
            g.best, g.raw, g.ref = sk.total, name, sk.ref
        end
    end
    list = merge_cores(list)
    sort_entries(list)
    for _, g in ipairs(list) do g.best, g.raw, g.cores, g.id = nil, nil, nil, nil end
    return list
end

-- The skill table of one character's details.
local function skill_rows(s, ctx)
    local i18n = ctx.i18n
    local list = View.skill_groups(s.skills, ctx)
    local total = total_of(list)
    local rows = {}
    for _, g in ipairs(list) do
        rows[#rows + 1] = {
            label = ctx.names:skill(g.ref),
            hits = i18n.num(g.hits), total = i18n.num(g.value), max = i18n.num(g.max),
            share = i18n.pct(total > 0 and g.value / total or 0),
            perfect = g.perfect > 0 and i18n.num(g.perfect) or "",
        }
    end
    return rows
end

-- Numbers that do not fit the skill table; a line appears only when it has something to say.
local function extra_rows(s, ctx)
    local i18n = ctx.i18n
    local rows = {}
    if s.dealt_full > 0 then
        rows[#rows + 1] = { label = i18n.t("details_full_damage"), value = i18n.num(s.dealt_full) }
    end
    if s.enemy_def_before > 0 then
        rows[#rows + 1] = {
            label = i18n.t("enemy_defence_saved"),
            value = armor_text(s.enemy_def_before, s.enemy_def_after, s.enemy_def_saved, i18n),
        }
    end
    if s.armor_before > 0 then
        rows[#rows + 1] = {
            label = i18n.t("details_armor_saved"),
            value = armor_text(s.armor_before, s.armor_after, s.armor_saved, i18n),
        }
    end
    if s.guard > 0 then
        rows[#rows + 1] = { label = i18n.t("details_guard"), value = i18n.num(s.guard) }
    end
    return rows
end

-- Live window: header, damage (party, then the grey rows: the allies, the enemies' own damage, Other), damage taken,
-- healing (party, then Other).
-- A block `show` switches off is left out.
function View.live(snap, now, ctx, show)
    local i18n = ctx.i18n
    local duration = duration_of(snap, now)
    local m = { header = header_model(snap, duration, ctx) }
    if wanted(show, "damage") then
        local party, grey, dealt = damage_rows(snap, ctx, duration, show)
        for _, row in ipairs(grey) do party[#party + 1] = row end
        m.damage = {
            title = i18n.t("damage_to_enemies"), rows = party,
            total = i18n.num(dealt), per_sec = i18n.num(per_second(dealt, duration)) .. i18n.t("per_sec"),
        }
    end
    if wanted(show, "taken") then
        local taken, taken_total = taken_rows(snap, ctx)
        m.taken = { title = i18n.t("damage_to_party"), rows = taken, total = i18n.num(taken_total) }
    end
    if wanted(show, "heal") then
        local heal, healed = heal_rows(snap, ctx, duration, show)
        m.heal = {
            title = i18n.t("healing"), rows = heal,
            total = i18n.num(healed), per_sec = i18n.num(per_second(healed, duration)) .. i18n.t("per_sec"),
        }
    end
    return m
end

-- Summary after a fight: values and shares, no per-second rates. A block `show` switches off is left out; the allies
-- block (the allies, then the Other row) is left out when neither of its kinds of row is wanted.
function View.summary(snap, ctx, show)
    local i18n = ctx.i18n
    local m = { title = i18n.t(snap.outcome == "win" and "victory" or "fight_over"), time = i18n.time(duration_of(snap)) }
    if wanted(show, "enemies") then m.enemies = enemy_rows(snap, ctx) end
    local grey_wanted = wanted(show, "allies") or wanted(show, "other")
    if wanted(show, "damage") or grey_wanted then
        local party, grey, dealt = damage_rows(snap, ctx, nil, show)
        if wanted(show, "damage") then m.damage = { title = i18n.t("dealt"), rows = party, total = i18n.num(dealt) } end
        if grey_wanted then m.allies = { title = i18n.t("allies"), rows = grey } end
    end
    if wanted(show, "heal") then
        local heal, healed = heal_rows(snap, ctx, nil, show)
        m.heal = { title = i18n.t("healed"), rows = heal, total = i18n.num(healed) }
    end
    if wanted(show, "armor") then m.armor = armor_rows(snap, ctx) end
    return m
end

-- Breakdown of one character (actor key); nil when the fight has no such character. Its kind, order, job and shade
-- colour it as in the lists.
function View.details(snap, key, ctx)
    local s = snap.actors[key]
    if not s then return nil end
    local d = { name = actor_name(s.actor, ctx), rows = skill_rows(s, ctx), extra = extra_rows(s, ctx) }
    d.key, d.kind, d.order, d.job = key, s.actor.kind, s.actor.order, s.actor.job
    d.shade = PARTY[s.actor.kind] and shades(snap)[tostring(key)] or nil
    return d
end

return View
