-- The debug collector: what the mod meets in the game, as records for reframework/data/DD2DamageMeter/collect.jsonl,
-- to check the enemy plate and the hit paths against the game before a release, and the hidden stats' readings
-- against the player's own numbers. Read-only, every game
-- access under Safe, no hook of its own. The entry file calls it only while the setting `debug` is on and the game is
-- not paused in a menu, and writes the file (Collector.output). Each record is written once per game session (a Lua
-- state) and key, except enchant, party_join and stat_check. A record is one line of JSON (HistoryFile.encode) that
-- starts with "t" (os.date's local time, "2026-11-04T21:07:33") and "kind"; plain numbers, strings and booleans after
-- them, a value the game did not give left out.
--
--   Collector.output(fn)   fn(text) gets each record's text, ending in "\n"; nil: the records go nowhere
--   Collector.enemy(character, actor, t)
--     a live enemy met: by the plate (one in sight under a bar) or by the hit path (a hit on it). The kind is the
--     Actor's CharaID (none, or no character or time: nothing read). Its state in use (RegionStatusCtrl:
--     get_PrioStatusId) is read at most every STATE_EVERY s per kind (and when t went back), nothing else while its
--     key (CharaID, state) is seen; a new key reads the kind's whole table once, from this character:
--     kind "enemy": name, base_id, chara_id, state (none when it cannot be read);
--       states: every state of get_RegionStatusDataProp():get_IntermediateRegionStatusParams() (at most MAX_STATES),
--         { id, parts }, its parts its own list (get_IntermediateRegionParams, at most MAX_REGIONS) as EnemyTable.part
--         reads them: { no, type, attr, weak, mult };
--       active: for each region number any state lists (first seen first), what getActiveRegionParam answers now:
--         { asked, part } or { asked, none = true };
--       has_body: whether the state in use lists a Body part (none when that state is not listed);
--       table: EnemyTable.peek's Table for this character now (its body and part lines; none without a state),
--         read apart from the plate's own reads: its cache stays as it was;
--       data: game/enemies.lua's record of the kind (weak, resist, defence, magic_defence, enabled) as read already
--         (asked without a character: no try spent).
--   Collector.weapons(t, player)
--     the player's weapons, at most every WEAPON_EVERY s (and when t went back); player() gives his character and is
--     called only then. Each hand that holds a weapon (get_RightWeapon, get_LeftWeapon):
--     kind "weapon" once per (weapon id, hand), looked at when the hand's weapon object changes: hand "right" |
--       "left", id (the weapon's GameObject name; the key is that with its Job, IsBlunt and ElementType: a name may
--       be one of many weapons), job (Job), blunt (IsBlunt), element_type (ElementType), original_element
--       (get_OriginalElementType()), answer (Weapon.peek: what Weapon.read gives for him now);
--     kind "enchant" whenever the hand's NowElementType (Weapon.now_element) differs from the one last written for the
--       hand, the first one seen too: hand, value. A hand without a weapon is not looked at (its entry is stale).
--   Collector.hit(h)   a Hit of game/hits.lua, only one on an enemy; reads nothing of the game:
--     kind "bonus" once per (attack name, bonus to 2 decimals), when Hit.target_bonus is above BONUS_MIN: attack,
--       skill, attacker_kind, attacker (his name), before, after (the damage around the defence step), rate_before,
--       rate_after (the DamageRate around the enemy's step), bonus, victim, base_id, chara_id;
--     kind "sourceless" once per (DamageType, Flag), a hit with no attacker ("Falls and environment", "Other", a
--       mirror): damage_type, flag, victim, base_id, chara_id, damage (Hit.final), removed (the HP it took), dot (a
--       DoT tick), status (its status), mirror, own;
--     kind "knock" once per (attack name, the victim's CharaID, else its base_id), a knock hit (Hit.knock: an
--       enemy's own damage credited to the friend whose hit came just before; it has an attacker, so no "sourceless"
--       record): attack, skill (the knocking hit's), attacker_kind, attacker (his name), gap (Hit.knock_gap, s since
--       that hit), damage, removed, damage_type, flag, victim, base_id, chara_id.
--   Collector.party_join(actor, old, new)
--     kind "party_join" every time a member's new object takes his actor (game/actors.lua): name, member_kind,
--     chara_id, old, new (the addresses in hex, "0x2A0000100"; none when not known).
--   Collector.stat_check(t, snapshot)   the hidden-stats evidence; reads nothing of the game:
--     snapshot is game/stat_check.lua's { numbers = { [name] = n }, equipped = { job, augments, rings, items } } (one
--     that is not such a table, or no time: nothing done). It is compared with the last one given in this session,
--     then kept in its place. The equipment differs when the augments, or the equipped item ids (the rings and the
--     items together: an item read once as a ring and once not is no change), differ as multisets; the numbers when
--     a number is not the same, or is in one of the two only.
--     kind "stat_check" when both differ, at most MAX_STAT_CHECKS a session: job (now), job_before (only when it
--       changed), before / after = { augments, rings, items } as given, added / removed (the augments' names, then
--       the item ids: what came in, what went out), changed = { [name] = { from, to } } (from or to left out when the
--       number was not there). An empty list is left out.
--   Collector.stat_forget()   forgets the last snapshot (a new world: a loaded save is no equipment change; Debug
--     switched: what changed while it was off is none either)
--   Collector.reset()   forgets the keys seen, the times of the looks, the last snapshot and the count of stat_check
--     records (a new game session; the tests)
local Safe = require("DD2DamageMeter/game/safe")
local EnemyTable = require("DD2DamageMeter/game/enemy_table")
local Weapon = require("DD2DamageMeter/game/weapon")
local enemies = require("DD2DamageMeter/game/enemies")
local HistoryFile = require("DD2DamageMeter/history_file")

local Collector = {}

local STATE_EVERY = 1    -- s between two reads of a kind's state
local WEAPON_EVERY = 1   -- s between two looks at the player's weapons
local MAX_STATES = 32    -- states looked through: twice the plate's (enemy_table.lua), so that a cut there shows here
local MAX_REGIONS = 128  -- parts of a state looked through: twice the plate's
local BONUS_MIN = 0.001  -- an enemy-step bonus above this is one
local MAX_STAT_CHECKS = 300  -- stat_check records written in a session at most
local ACTIVE = "getActiveRegionParam(System.Int32)"
local BODY = 1           -- app.IntermediateRegionParam.RegionTypeEnum
local HANDS = {          -- WeaponElementInfo.<WeaponType>k__BackingField: 1 right, 0 left
    { name = "right", no = 1, getter = "get_RightWeapon" },
    { name = "left", no = 0, getter = "get_LeftWeapon" },
}

local out = nil          -- Collector.output's fn
local seen = {}          -- record kind -> key -> true
local state_at = {}      -- chara_id -> t of the last read of its state
local weapons_at = nil   -- t of the last look at the weapons
local held = {}          -- hand -> the address of the weapon object last looked at in it (false: one without)
local values = {}        -- hand -> the NowElementType last written for it
local stat_last = nil    -- the last snapshot given to stat_check (nil: none yet, or forgotten)
local stat_count = 0     -- stat_check records written in this session

function Collector.output(fn)
    out = fn
end

function Collector.reset()
    seen, state_at, weapons_at, held, values = {}, {}, nil, {}, {}
    stat_last, stat_count = nil, 0
end

local function finite(x)
    if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge then return nil end
    return x
end

-- Whether a look made last at `last` (nil: never) is due at `t`.
local function due(last, t, every)
    return last == nil or t < last or t - last >= every
end

-- true the first time `key` of the record kind `kind` comes, and it is noted.
local function first(kind, key)
    local keys = seen[kind]
    if keys == nil then
        keys = {}
        seen[kind] = keys
    end
    if keys[key] then return false end
    keys[key] = true
    return true
end

-- The record as one line, its time and kind first.
local function put(kind, record)
    if out == nil then return end
    local rest = HistoryFile.encode(record)
    local head = string.format('{"t":"%s","kind":"%s"', os.date("%Y-%m-%dT%H:%M:%S"), kind)
    out(head .. (rest == "{}" and "}" or "," .. rest:sub(2)) .. "\n")
end

-- Enemies ------------------------------------------------------------------------------------------

-- The character's RegionStatusCtrl and its state in use (nil when it cannot be read).
local function control_of(character)
    local rsc = Safe.call(Safe.call(character, "get_DamageCalculator"), "get_RegionStatusCtrl")
    local state = Safe.call(rsc, "get_PrioStatusId")
    if type(state) ~= "string" or state == "" then state = nil end
    return rsc, state
end

-- Every state of the table in use with its own parts, and the region numbers they list, each once.
local function states_of(rsc)
    local states, numbers, listed = {}, {}, {}
    local data = Safe.call(rsc, "get_RegionStatusDataProp")
    for _, s in ipairs(Safe.list(Safe.call(data, "get_IntermediateRegionStatusParams"), MAX_STATES)) do
        if s then
            local id, parts = Safe.call(s, "get_StatusId"), {}
            for _, param in ipairs(Safe.list(Safe.call(s, "get_IntermediateRegionParams"), MAX_REGIONS)) do
                local p = param and EnemyTable.part(param) or nil
                if p then
                    parts[#parts + 1] = p
                    if p.no ~= nil and not listed[p.no] then
                        listed[p.no] = true
                        numbers[#numbers + 1] = p.no
                    end
                end
            end
            states[#states + 1] = { id = type(id) == "string" and id or nil, parts = parts }
        end
    end
    return states, numbers
end

-- Whether the state `state` lists a Body part; nil when it is not listed.
local function has_body(states, state)
    for _, s in ipairs(states) do
        if state ~= nil and s.id == state then
            for _, p in ipairs(s.parts) do
                if p.type == BODY then return true end
            end
            return false
        end
    end
    return nil
end

local function read_enemy(character, actor, rsc, state)
    local states, numbers = states_of(rsc)
    local active = {}
    for i, no in ipairs(numbers) do
        local p = EnemyTable.part(Safe.call(rsc, ACTIVE, no), no)
        active[i] = p and { asked = no, part = p } or { asked = no, none = true }
    end
    put("enemy", {
        name = actor.name, base_id = actor.base_id, chara_id = actor.chara_id, state = state,
        states = states, active = active, has_body = has_body(states, state),
        table = state and EnemyTable.peek(character, actor.chara_id) or nil,
        data = enemies.data(nil, actor),
    })
end

function Collector.enemy(character, actor, t)
    if character == nil or type(actor) ~= "table" or math.type(actor.chara_id) ~= "integer" or finite(t) == nil then
        return
    end
    local id = actor.chara_id
    if not due(state_at[id], t, STATE_EVERY) then return end
    state_at[id] = t
    local rsc, state = control_of(character)
    if first("enemy", id .. "|" .. (state or "")) then read_enemy(character, actor, rsc, state) end
end

-- Weapons ------------------------------------------------------------------------------------------

-- The weapon's record, once per (weapon id, hand).
local function weapon_seen(character, weapon, hand)
    local job, element = Safe.enum(Safe.field(weapon, "Job")), Safe.enum(Safe.field(weapon, "ElementType"))
    local blunt = Safe.field(weapon, "IsBlunt")
    if type(blunt) ~= "boolean" then blunt = nil end
    local id = Safe.go_name(weapon)
    local key = string.format("%s/%s/%s/%s", tostring(id), tostring(job), tostring(blunt), tostring(element))
    if not first("weapon", key .. "|" .. hand.name) then return end
    put("weapon", {
        hand = hand.name, id = id, job = job, blunt = blunt, element_type = element,
        original_element = Safe.enum(Safe.call(weapon, "get_OriginalElementType")), answer = Weapon.peek(character),
    })
end

function Collector.weapons(t, player)
    if finite(t) == nil or not due(weapons_at, t, WEAPON_EVERY) then return end
    weapons_at = t
    local character = type(player) == "function" and Safe.try(player) or nil
    if character == nil then return end
    for _, hand in ipairs(HANDS) do
        local weapon = Safe.call(character, hand.getter)
        if weapon ~= nil then
            local addr = Safe.address(weapon) or false
            if held[hand.name] ~= addr then
                held[hand.name] = addr
                weapon_seen(character, weapon, hand)
            end
            local value = Weapon.now_element(character, hand.no)
            if value ~= nil and value ~= values[hand.name] then
                values[hand.name] = value
                put("enchant", { hand = hand.name, value = value })
            end
        end
    end
end

-- Hits ---------------------------------------------------------------------------------------------

local function removed(h)
    local hp0, hp1 = finite(h.hp0), finite(h.hp1)
    if hp0 == nil or hp1 == nil then return nil end
    return math.max(0, hp0 - hp1)
end

function Collector.hit(h)
    local victim = type(h) == "table" and h.victim or nil
    if type(victim) ~= "table" or victim.kind ~= "enemy" then return end
    local attacker = type(h.attacker) == "table" and h.attacker or nil
    local skill = type(h.skill) == "table" and h.skill or {}
    local bonus = finite(h.target_bonus)
    local cents = bonus and math.floor(bonus * 100 + 0.5)
    if bonus and bonus > BONUS_MIN and first("bonus", tostring(skill.attack) .. "|" .. cents) then
        local rate = finite(h.target_rate)
        put("bonus", {
            attack = skill.attack, skill = skill.id, attacker_kind = attacker and attacker.kind,
            attacker = attacker and attacker.name, before = finite(h.before), after = finite(h.after),
            rate_before = rate, rate_after = rate and rate + bonus, bonus = bonus,
            victim = victim.name, base_id = victim.base_id, chara_id = victim.chara_id,
        })
    end
    if h.attacker == nil and first("sourceless", tostring(h.damage_type) .. "|" .. tostring(h.flag)) then
        put("sourceless", {
            damage_type = h.damage_type, flag = h.flag, victim = victim.name, base_id = victim.base_id,
            chara_id = victim.chara_id, damage = finite(h.final), removed = removed(h), dot = h.status ~= nil,
            status = h.status, mirror = h.mirror == true, own = h.own,
        })
    end
    if h.knock == true and attacker
        and first("knock", tostring(skill.attack) .. "|" .. tostring(victim.chara_id or victim.base_id)) then
        put("knock", {
            attack = skill.attack, skill = skill.id, attacker_kind = attacker.kind, attacker = attacker.name,
            gap = finite(h.knock_gap), damage = finite(h.final), removed = removed(h), damage_type = h.damage_type,
            flag = h.flag, victim = victim.name, base_id = victim.base_id, chara_id = victim.chara_id,
        })
    end
end

-- The party ----------------------------------------------------------------------------------------

local function hex(addr)
    addr = type(addr) == "number" and math.tointeger(addr) or nil
    if addr == nil then return nil end
    return string.format("0x%X", addr)
end

function Collector.party_join(actor, old, new)
    if type(actor) ~= "table" then return end
    put("party_join", { name = actor.name, member_kind = actor.kind, chara_id = actor.chara_id, old = hex(old),
        new = hex(new) })
end

-- The hidden-stats evidence ------------------------------------------------------------------------------------------

local function list_of(v)
    return type(v) == "table" and v or {}
end

-- The snapshot's equipment as { job, augments, rings, items }, each list a table; nil when it is not a snapshot.
local function equipment_of(snapshot)
    if type(snapshot) ~= "table" or type(snapshot.numbers) ~= "table" or type(snapshot.equipped) ~= "table" then
        return nil
    end
    local e = snapshot.equipped
    return { job = e.job, augments = list_of(e.augments), rings = list_of(e.rings), items = list_of(e.items) }
end

-- The rings and the items as one sorted list of ids.
local function gear(e)
    local all = table.move(e.rings, 1, #e.rings, 1, {})
    table.move(e.items, 1, #e.items, #all + 1, all)
    table.sort(all)
    return all
end

-- The entries of `a` that `b` has fewer of (as multisets), in a's order, appended to `into`.
local function minus(a, b, into)
    local left = {}
    for _, v in ipairs(b) do left[v] = (left[v] or 0) + 1 end
    for _, v in ipairs(a) do
        if (left[v] or 0) > 0 then left[v] = left[v] - 1 else into[#into + 1] = v end
    end
    return into
end

-- Every number that is not the same in the two, { from, to }; nil when none.
local function changes(before, after)
    local changed = {}
    for name, from in pairs(before) do
        if after[name] ~= from then changed[name] = { from = from, to = after[name] } end
    end
    for name, to in pairs(after) do
        if before[name] == nil then changed[name] = { to = to } end
    end
    return next(changed) ~= nil and changed or nil
end

local function nonempty(list)
    if #list == 0 then return nil end
    return list
end

local function side(e)
    return { augments = nonempty(e.augments), rings = nonempty(e.rings), items = nonempty(e.items) }
end

function Collector.stat_check(t, snapshot)
    local now = equipment_of(snapshot)
    if finite(t) == nil or now == nil then return end
    local last = stat_last
    stat_last = snapshot
    if last == nil or stat_count >= MAX_STAT_CHECKS then return end
    local was = equipment_of(last)
    local was_gear, now_gear = gear(was), gear(now)
    local added = minus(now_gear, was_gear, minus(now.augments, was.augments, {}))
    local removed = minus(was_gear, now_gear, minus(was.augments, now.augments, {}))
    if #added == 0 and #removed == 0 then return end
    local changed = changes(last.numbers, snapshot.numbers)
    if changed == nil then return end
    stat_count = stat_count + 1
    put("stat_check", {
        job = now.job, job_before = was.job ~= now.job and was.job or nil, before = side(was), after = side(now),
        added = nonempty(added), removed = nonempty(removed), changed = changed,
    })
end

function Collector.stat_forget()
    stat_last = nil
end

return Collector
