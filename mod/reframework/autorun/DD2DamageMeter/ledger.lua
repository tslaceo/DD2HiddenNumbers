-- The per-enemy detail of one fight, for the journal: what each enemy took (by damage type, part, attacker and skill,
-- with the multiplier the game applied), what each enemy did to the friends, heals by healer, target and source, and
-- the latest events. Counters only, no hit list: memory depends on the enemies, attackers and distinct skills, plus a
-- record of at most RECORD_MAX events (older ones are only counted).
-- Fight feeds it from count_hit and add_heal and hands out Ledger:snapshot() as snap.detail.
--
-- A journal damage type (jt) is one of Ledger.TYPES. The game's raw types (Slash Blow Shoot Magic Enchant
-- NonMagicElement Fixed, the keys of Hit.types and Hit.region) become jt through the hit's element: Magic and Enchant
-- take the element when it is Fire/Ice/Thunder/Light/Dark, else Magic; NonMagicElement takes the element, else Other;
-- Fixed is Other.
--
--   Ledger.TYPES         { "Slash", "Blow", "Shoot", "Fire", "Ice", "Thunder", "Light", "Dark", "Magic", "Status",
--                          "Other" } (display order)
--   Ledger.RECORD_MAX    2000
--   Ledger.split(hit) -> table<jt, { w, before, after }>
--     w is the weight the HP removed is shared out by: the damage after the region step (before it when all of
--     those are 0) of the hit's region; else the value of hit.types; else Status for a DoT tick, else Other
--     (w = 1). before/after are the damage of the type before / after the region step (0 without a region).
--   Ledger.main_type(hit) -> jt              the type of the largest w, ties by Ledger.TYPES order
--   Ledger.round_mult(x) -> number           2 decimals
--   Ledger.efficacy(x) -> "invalid" | "resist" | "normal" | "effective" | nil
--     the game's scale on the multiplier as shown (rounded to 2 decimals): <= 0, < 0.5, < 1.5, else; nil for nil,
--     NaN or infinity
--   Ledger.vote_ref(sk, ref)                 names the skill entry sk by the leading vote of the refs of its hits
--   Ledger.new(t0) -> ledger
--   ledger:hit(hit, o)    o = { removed, role = "dealt" | "attack" | "other", skill = raw skill key, killed,
--                               enemy = enemy actor key | nil, kind = Fight.kind_key of that enemy | nil,
--                               by = actor key | nil }
--     "dealt": damage the enemy took (a friend's hit, or a hit with no attacker: by[o.by], by.other without one);
--     "attack": the enemy hit a friend; "other": recorded only. o.by: whom a hit with no attacker is credited to (the
--     fight's pseudo-actor "env" for an enemy's own damage, the member himself for his own). hit.foe (the enemy's
--     data) is kept per kind, the first one met. A hit that removed no HP (a blocked blow, a grab) is no attack and no
--     event, unless it killed; as "dealt" it still counts.
--   ledger:heal(heal, o)  o = { healer = actor key | "other", source = "item:<id>" | "skill:<attack>" |
--                               "skill_id:<HumanCustomSkillID name>" | "self:<name>" (a member's own: lifesteal,
--                               regen) | "other" }
--   ledger:fold(from, to)  enemy `from` is the same enemy as `to` (linked bodies, fight.lua): its Foe is summed into
--                          to's, its heals (as a healer and as a target) are to's, and the record names `to` where it
--                          named `from`
--   ledger:pause(seconds)  the fight stood still for `seconds` (a fight continued): later events are timed
--                          without them
--   ledger:snapshot() -> Detail (an independent copy)
--
--   Detail = { foes = table<enemy key, Foe>, kinds = table<kind key, EnemyData>,
--              heals = table<healer key, table<target key, table<source, { amount, n }>>>,
--              record = { Event } oldest first, record_dropped = events older than the record }
--   Foe    = { types = table<jt, { dealt, before, after, hits }>,
--              by_part = { head = table<jt, { before, after }>, body = table<jt, { before, after }> }: the damage of
--                  each type before / after the region step on a hit part ("other" counts as body),
--              by = table<attacker key | "env" | "other", { dealt, hits, skills = table<raw skill key,
--                  { ref, hits, total, max, before, after, types = table<jt, number> }> }>,
--              attacks = table<victim key, { dealt, hits, types = table<jt, integer> }> }
--   Event  = { t = seconds since t0 (without the time the fight stood still), k = "hit" | "heal",
--              a = actor key (the attacker, else o.by) | nil, v = victim or target key,
--              s = raw skill key (a friend's hit) | "status:<name>" (a status tick of anyone but an enemy) |
--                  "self:<source>" (a member's own damage, Fight) |
--                  "t:" .. main type (any other hit: an enemy's, a neutral character's, an object's, nobody's) |
--                  the heal's source,
--              n = HP removed or healed, kill = true | nil }
local Ledger = {}
Ledger.__index = Ledger

Ledger.TYPES = { "Slash", "Blow", "Shoot", "Fire", "Ice", "Thunder", "Light", "Dark", "Magic", "Status", "Other" }
Ledger.RECORD_MAX = 2000

local TYPES = Ledger.TYPES
local RAW = { "Slash", "Blow", "Shoot", "Magic", "Enchant", "NonMagicElement", "Fixed" }
local ELEMENTS = { Fire = true, Ice = true, Thunder = true, Light = true, Dark = true }
local PART = { head = "head", body = "body", other = "body" } -- region part -> Foe.by_part key
local FRIEND = { player = true, pawn = true, ally = true }

local function positive(v)
    return type(v) == "number" and v > 0 and v or 0
end

local function copy_flat(t)
    local c = {}
    for k, v in pairs(t) do c[k] = v end
    return c
end

local function deep_copy(v)
    if type(v) ~= "table" then return v end
    local c = {}
    for k, x in pairs(v) do c[k] = deep_copy(x) end
    return c
end

local function jt_of(raw, element)
    if raw == "Slash" or raw == "Blow" or raw == "Shoot" then return raw end
    local el = ELEMENTS[element] and element or nil
    if raw == "Magic" or raw == "Enchant" then return el or "Magic" end
    if raw == "NonMagicElement" then return el or "Other" end
    return "Other"
end

local function add_part(out, jt, w, before, after)
    local p = out[jt]
    if not p then
        p = { w = 0, before = 0, after = 0 }
        out[jt] = p
    end
    p.w, p.before, p.after = p.w + w, p.before + before, p.after + after
end

local function split_region(region, element)
    local out, total = {}, 0
    for _, raw in ipairs(RAW) do
        local b = positive(region.before and region.before[raw])
        local a = positive(region.after and region.after[raw])
        if b > 0 or a > 0 then
            add_part(out, jt_of(raw, element), a, b, a)
            total = total + a
        end
    end
    if next(out) == nil then return nil end
    -- Everything absorbed: the damage before the step says what the hit was made of.
    if total <= 0 then
        for _, p in pairs(out) do p.w = p.before end
    end
    return out
end

local function split_types(types, element)
    local out = {}
    for _, raw in ipairs(RAW) do
        local v = positive(types[raw])
        if v > 0 then add_part(out, jt_of(raw, element), v, 0, 0) end
    end
    if next(out) == nil then return nil end
    return out
end

function Ledger.split(hit)
    local out = hit.region and split_region(hit.region, hit.element)
    if not out and hit.types then out = split_types(hit.types, hit.element) end
    if out then return out end
    return { [hit.status and "Status" or "Other"] = { w = 1, before = 0, after = 0 } }
end

local function main_of(parts)
    local best, w = "Other", -1
    for _, jt in ipairs(TYPES) do
        local p = parts[jt]
        if p and p.w > w then best, w = jt, p.w end
    end
    return best
end

function Ledger.main_type(hit)
    return main_of(Ledger.split(hit))
end

function Ledger.round_mult(x)
    return math.floor(x * 100 + 0.5) / 100
end

function Ledger.efficacy(x)
    if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge then return nil end
    local r = Ledger.round_mult(x)
    if r <= 0 then return "invalid" end
    if r < 0.5 then return "resist" end
    if r < 1.5 then return "normal" end
    return "effective"
end

-- Hits of one skill entry can say different things (a shell landing after its skill state was gone, a blow while the
-- state still named a skill): each hit votes with its id, else "normal", else "?", and the entry's ref is that of a hit
-- of the leading known vote; "?" leads only while nothing is known, a tie keeps the current ref. A new table, so that
-- snapshots already taken keep the ref they had. sk keeps the votes in sk.votes and the leader in sk.lead.
function Ledger.vote_ref(sk, ref)
    local votes = sk.votes
    if not votes then
        votes = {}
        sk.votes = votes
    end
    local vote = ref.id ~= nil and tostring(ref.id) or (ref.normal == true and "normal") or "?"
    local n = (votes[vote] or 0) + 1
    votes[vote] = n
    if sk.ref == nil or (vote ~= sk.lead and vote ~= "?" and (sk.lead == "?" or n > votes[sk.lead])) then
        sk.ref = { id = ref.id, attack = ref.attack, normal = ref.normal, status = ref.status }
        sk.lead = vote
    end
end

function Ledger.new(t0)
    return setmetatable({
        t0 = t0 or 0,
        paused = 0, -- seconds the fight stood still (ledger:pause)
        foes = {}, kinds = {}, heals = {},
        ring = {}, ring_first = 1, ring_n = 0, -- the record: a ring, ring_first is its oldest event
        record_dropped = 0,
    }, Ledger)
end

local function since(self, t)
    return math.max(0, (t or self.t0) - self.t0 - self.paused)
end

function Ledger:pause(seconds)
    self.paused = self.paused + seconds
end

local function push(self, event)
    local max = Ledger.RECORD_MAX
    if self.ring_n < max then
        self.ring_n = self.ring_n + 1
        self.ring[self.ring_n] = event
    else
        self.ring[self.ring_first] = event
        self.ring_first = self.ring_first % max + 1
        self.record_dropped = self.record_dropped + 1
    end
end

local function foe_for(self, key)
    local foe = self.foes[key]
    if not foe then
        foe = { types = {}, by = {}, attacks = {}, by_part = { head = {}, body = {} } }
        self.foes[key] = foe
    end
    return foe
end

-- The enemy took this hit: HP removed shared out by the weights of the hit's types.
local function add_dealt(foe, hit, o, parts, removed)
    local total = 0
    for _, jt in ipairs(TYPES) do
        local p = parts[jt]
        if p then total = total + p.w end
    end

    local akey = hit.attacker and hit.attacker.key or o.by or "other"
    local by = foe.by[akey]
    if not by then
        by = { dealt = 0, hits = 0, skills = {} }
        foe.by[akey] = by
    end
    by.dealt, by.hits = by.dealt + removed, by.hits + 1

    local skey = o.skill or "?"
    local sk = by.skills[skey]
    if not sk then
        sk = { hits = 0, total = 0, max = 0, before = 0, after = 0, types = {} }
        by.skills[skey] = sk
    end
    Ledger.vote_ref(sk, hit.skill or {})
    sk.hits, sk.total, sk.max = sk.hits + 1, sk.total + removed, math.max(sk.max, removed)

    for _, jt in ipairs(TYPES) do
        local p = parts[jt]
        if p then
            local share = total > 0 and removed * (p.w / total) or 0
            local t = foe.types[jt]
            if not t then
                t = { dealt = 0, before = 0, after = 0, hits = 0 }
                foe.types[jt] = t
            end
            t.dealt, t.before, t.after, t.hits = t.dealt + share, t.before + p.before, t.after + p.after, t.hits + 1
            sk.types[jt] = (sk.types[jt] or 0) + share
            sk.before, sk.after = sk.before + p.before, sk.after + p.after
        end
    end

    local region = hit.region
    local part = region and PART[region.part]
    if part then
        local by_type = foe.by_part[part]
        for jt, p in pairs(parts) do
            if p.before > 0 or p.after > 0 then
                local row = by_type[jt]
                if not row then
                    row = { before = 0, after = 0 }
                    by_type[jt] = row
                end
                row.before, row.after = row.before + p.before, row.after + p.after
            end
        end
    end
end

-- The enemy hit a friend: counted by victim, with its hits by main damage type.
local function add_attack(foe, hit, parts, removed)
    local key = hit.victim.key
    local a = foe.attacks[key]
    if not a then
        a = { dealt = 0, hits = 0, types = {} }
        foe.attacks[key] = a
    end
    a.dealt, a.hits = a.dealt + removed, a.hits + 1
    local main = main_of(parts)
    a.types[main] = (a.types[main] or 0) + 1
end

-- What the record says a hit was made with. The game has only internal names for the attacks of anyone but the
-- friends: a friend's hit keeps its raw skill key; a status tick of anyone but an enemy its status, a member's own
-- damage its source; everything else (an enemy's hit, its status ticks included, a neutral character's or an
-- object's, a hit with no attacker) its main type.
local function event_key(attacker, skill, parts)
    if attacker and FRIEND[attacker.kind] then return skill or "?" end
    local enemy = attacker ~= nil and attacker.kind == "enemy"
    if type(skill) == "string" and not enemy
        and (skill:sub(1, 7) == "status:" or (attacker == nil and skill:sub(1, 5) == "self:")) then
        return skill
    end
    return "t:" .. main_of(parts)
end

function Ledger:hit(hit, o)
    local parts = Ledger.split(hit)
    local removed = o.removed or 0
    local attacker = hit.attacker
    if o.kind and hit.foe and self.kinds[o.kind] == nil then self.kinds[o.kind] = hit.foe end
    local counts = removed > 0 or o.killed
    if o.enemy and o.role == "dealt" then
        add_dealt(foe_for(self, o.enemy), hit, o, parts, removed)
    elseif o.enemy and o.role == "attack" and counts then
        add_attack(foe_for(self, o.enemy), hit, parts, removed)
    end
    if not counts then return end
    push(self, {
        t = since(self, hit.t), k = "hit", a = attacker and attacker.key or o.by, v = hit.victim.key,
        s = event_key(attacker, o.skill, parts), n = removed, kill = o.killed and true or nil,
    })
end

function Ledger:heal(heal, o)
    local healer, source = o.healer or "other", o.source or "other"
    local target = heal.target.key
    local by_target = self.heals[healer]
    if not by_target then
        by_target = {}
        self.heals[healer] = by_target
    end
    local by_source = by_target[target]
    if not by_source then
        by_source = {}
        by_target[target] = by_source
    end
    local cell = by_source[source]
    if not cell then
        cell = { amount = 0, n = 0 }
        by_source[source] = cell
    end
    cell.amount, cell.n = cell.amount + heal.effective, cell.n + 1
    push(self, {
        t = since(self, heal.t), k = "heal", a = healer ~= "other" and healer or nil, v = target, s = source,
        n = heal.effective,
    })
end

local function sum_into(t, f, fields)
    for _, k in ipairs(fields) do t[k] = (t[k] or 0) + (f[k] or 0) end
end

function Ledger:fold(from, to)
    local f = self.foes[from]
    if f then
        local t = foe_for(self, to)
        for jt, x in pairs(f.types) do
            local y = t.types[jt]
            if y then sum_into(y, x, { "dealt", "before", "after", "hits" }) else t.types[jt] = x end
        end
        for part, rows in pairs(f.by_part) do
            local into = t.by_part[part]
            if into == nil then
                into = {}
                t.by_part[part] = into
            end
            for jt, x in pairs(rows) do
                local y = into[jt]
                if y then sum_into(y, x, { "before", "after" }) else into[jt] = x end
            end
        end
        for akey, x in pairs(f.by) do
            local y = t.by[akey]
            if y == nil then
                t.by[akey] = x
            else
                sum_into(y, x, { "dealt", "hits" })
                for raw, sk in pairs(x.skills) do
                    local into = y.skills[raw]
                    if into == nil then
                        y.skills[raw] = sk
                    else
                        sum_into(into, sk, { "hits", "total", "before", "after" })
                        into.max = math.max(into.max, sk.max)
                        for jt, v in pairs(sk.types) do into.types[jt] = (into.types[jt] or 0) + v end
                    end
                end
            end
        end
        for vkey, x in pairs(f.attacks) do
            local y = t.attacks[vkey]
            if y == nil then
                t.attacks[vkey] = x
            else
                sum_into(y, x, { "dealt", "hits" })
                for jt, n in pairs(x.types) do y.types[jt] = (y.types[jt] or 0) + n end
            end
        end
        self.foes[from] = nil
    end
    local function into(by_target, target, by_source)
        local cells = by_target[target]
        if cells == nil then
            by_target[target] = by_source
            return
        end
        for source, c in pairs(by_source) do
            local d = cells[source]
            if d then sum_into(d, c, { "amount", "n" }) else cells[source] = c end
        end
    end
    local as_healer = self.heals[from]
    if as_healer then
        self.heals[from] = nil
        local mine = self.heals[to]
        if mine == nil then
            mine = {}
            self.heals[to] = mine
        end
        for target, by_source in pairs(as_healer) do into(mine, target, by_source) end
    end
    for _, by_target in pairs(self.heals) do
        local by_source = by_target[from]
        if by_source then
            by_target[from] = nil
            into(by_target, to, by_source)
        end
    end
    for i = 1, self.ring_n do
        local e = self.ring[i]
        if e.a == from then e.a = to end
        if e.v == from then e.v = to end
    end
end

function Ledger:snapshot()
    local foes = {}
    for key, foe in pairs(self.foes) do
        local c = deep_copy(foe)
        for _, by in pairs(c.by) do
            for _, sk in pairs(by.skills) do sk.votes, sk.lead = nil, nil end
        end
        foes[key] = c
    end
    local record = {}
    for i = 1, self.ring_n do
        record[i] = copy_flat(self.ring[(self.ring_first + i - 2) % self.ring_n + 1])
    end
    return {
        foes = foes, kinds = deep_copy(self.kinds), heals = deep_copy(self.heals),
        record = record, record_dropped = self.record_dropped,
    }
end

return Ledger
