-- One fight: hits and heals folded into per-character counters as they arrive.
-- No per-hit list is kept (a long fight is thousands of hits); memory depends on the
-- number of characters, enemies and distinct skills only.
-- An enemy takes part in the fight only through the party: a hit with a player or a pawn on a side counts at once and
-- engages the enemy on the other side (a party blow on the corpse of an enemy not engaged yet waits instead); a hit
-- between others waits in its enemy's pending list (bounded, see MAX_PENDING_*) until the party engages that enemy,
-- and is dropped when it has no enemy at all. Pending hits never reach a snapshot; Fight:held() tells how many were
-- held and not counted.
-- The per-enemy detail (damage by type, part, attacker and skill, enemy attacks, heals by target, the record) is
-- kept by the Ledger, which every counted hit and heal is passed to; a full snapshot carries it as snap.detail.
-- Linked bodies: an enemy of two bodies with one HP pool (the Evil Eye) loses on its other body, by a link mirror
-- (Hit.mirror, game/hits.lua), what the hit body lost. A mirror is never counted (no damage, no kill, no record).
-- A mirror on body B within LINK_FRAMES frames of a counted hit on a living enemy A of the same kind (Fight.kind_key;
-- either comes first) whose HP drop matches the mirror's within LINK_HP links the two for the rest of the fight: the
-- one the party hit first is kept, the other's counters, held hits and heals are folded into it (the lower HP of the
-- two: the pool only falls), and every later hit or heal of or on the other is counted as the kept one's. A mirror
-- with no such A, or one that removed nothing (a sync), is dropped. Parts of an enemy that have their own HP, and
-- enemies that never mirror, are as before.
-- A fight continued (DD2DamageMeter.lua): a finished fight can be reopened, and goes on as if it never ended; the
-- time between its finish and the reopen is paused, out of its duration and of every time it counts since t0 (its
-- kills', its record's). An alias makes a returning enemy's new object (a new key) count as one of its enemies: every
-- hit or heal of or on it is counted as that enemy's, as a linked body's is, and it never becomes an enemy of its own.
--
--   Hit  { t, attacker: Actor|nil, victim: Actor, skill = { id, attack, normal, status }, final, hp0, hp1, before, after,
--          types: table<raw type, number>|nil, guard, status: string|nil,
--          element: "None"|"Fire"|"Ice"|"Thunder"|"Light"|"Dark"|nil,
--          region: { before, after: table<raw type, number>, no: integer|nil, part: "head"|"body"|"other"|nil }|nil,
--          foe: EnemyData|nil, own: "blood_pact"|"self"|nil, knock: true|nil }
--          raw type: Slash Blow Shoot Magic Enchant NonMagicElement Fixed
--   Hit.own (game/hits.lua): the victim did it to himself, and the hit has no attacker. On a party member it is his own
--          damage taken, from its source (taken_from["self:<own>"]: Blood Pact, Self), never damage dealt; on an
--          enemy (a fall) it is ENV's damage dealt ("Falls and environment"), its kill "env"'s
--   Hit.knock (game/hits.lua): an enemy's own damage just after a friend's hit on it, which comes with that friend
--          as its attacker and the knocking hit's skill reference: counted as that friend's hit like any other (the
--          fight does not look at the flag)
--   Heal { t, target: Actor, healer: Actor|nil, amount, effective, source = { kind = "item" | "skill" | "other" |
--          "self", item_id, name, id } }   kind "self": the target's own heal (name "lifesteal" | "regen", healer =
--          target); a skill heal has the heal area's attack `name`, or the skill's HumanCustomSkillID name `id`
--          (game/heals.lua: Argent Tonic), kept by the ledger as "skill_id:<id>"
--   Actor { key, name, kind = "player" | "pawn" | "ally" | "enemy" | "other", base_id, max_hp, order, chara_id }
--   Hit.point, Hit.weak_damage, Hit.target_bonus: the hit point, IsWeakDamage and what the enemy's defence step added
--          to the DamageRate, read only for the damage numbers (game/hits.lua); the fight does not use them; nor
--          Hit.target_rate, Hit.damage_type, Hit.flag, read only for the debug collector (game/collector.lua)
--   Hit.mirror: true for a link mirror (see above); Hit.frame: the frame of the hit (game/hits.lua), what links go by
--   fight:add_hit(hit) -> the HP counted for this hit now (max(0, hp0 - hp1)), nil when it is held or dropped (a
--          mirror always)
--   Fight.new(t0), fight:add_heal(heal), fight:finish(t1, outcome), fight:is_engaged(key),
--   fight:reopen(t)   the finished fight goes on from t: t1 and outcome forgotten, t - t1 added to its pause
--   fight:alias(key, to_key)   character `key` counts as the fight's enemy `to_key` from now on (none when to_key
--          is no enemy of the fight); fight.aliases[key] -> that enemy's Actor
--   fight:note_hp(key, hp, full) -> enemy key, its entry | nil[, refused]   the HP character `key` has now as the game
--          shows it (read outside the hits): the fight's enemy it counts as takes it as its HP left; refused =
--          { key, name, max_hp } when only `full` kept it out (see the function)
--   fight.enemies[key].hit_hp: the HP the last counted hit on that enemy left (nil before one; note_hp never sets
--          it), what a returning enemy is matched against (DD2DamageMeter.lua); not in a snapshot
--   fight:held(), fight:snapshot(now, full) -> { t0, t1, outcome, duration, paused, actors, enemies, types, detail }
--     duration = (t1 or now) - t0 - paused; paused: the seconds it stood still (reopen), nil when none
--     enemies[key] = { actor, max_hp, hp (the HP left after the last counted hit on it or note_hp, whichever came
--                      last; nil while neither came), killed, killed_at = seconds since t0, without the pause | nil,
--                      killer = actor key | "env" | "other" | nil,
--                      last_hit = t of the latest hit on it by the party or an ally (the clock of t0) | nil }
--     detail: only with `full` (see ledger.lua)
--     actors[key].taken_from: attacker key | "env" | "other" | "self:<own>" -> HP lost; heal_sources: "skill" |
--                      "item:<id>" | "self:<name>" | "other" -> HP healed
--   Fight.kind_key(actor) -> "c" .. chara_id, else "b:" .. (base_id or key): what makes two enemies one kind
local Ledger = require("DD2DamageMeter/ledger")

local Fight = {}
Fight.__index = Fight

-- Pseudo-actors, shown in the window as grey rows outside every total: OTHER for damage and healing nobody
-- can be blamed for (a burn/poison/shock tick on an enemy whose causer is unknown, a heal with no healer and no known
-- source), «Прочее»; ENV for the damage enemies did to themselves (Hit.own: a fall) that no friend's hit just before
-- caused (that is the friend's), "Falls and environment".
local OTHER = { key = "other", name = "other", kind = "other", base_id = "other" }
local ENV = { key = "env", name = "env", kind = "other", base_id = "env" }

-- armor_* is this character's own armor on the damage he took; enemy_def_* is the defence
-- of his targets on the damage he dealt.
local function new_stats(actor)
    return {
        actor = actor,
        dealt = 0, dealt_full = 0, hits = 0, kills = 0,
        enemy_def_before = 0, enemy_def_after = 0, enemy_def_saved = 0,
        taken = 0, taken_full = 0, hits_taken = 0, taken_from = {},
        armor_before = 0, armor_after = 0, armor_saved = 0, guard = 0,
        heal_done = 0, heal_received = 0, heal_sources = {},
        skills = {},
    }
end

local function stats_for(self, actor)
    local s = self.actors[actor.key]
    if not s then
        s = new_stats(actor)
        self.actors[actor.key] = s
    end
    return s
end

local function add_to(t, key, amount)
    t[key] = (t[key] or 0) + amount
end

local function is_party(actor)
    return actor.kind == "player" or actor.kind == "pawn"
end

-- friend = player/pawn/ally, foe = enemy, neutral = anything else (objects, unknown).
local function side(actor)
    local kind = actor.kind
    if kind == "player" or kind == "pawn" or kind == "ally" then return "friend" end
    if kind == "enemy" then return "foe" end
    return "neutral"
end

local function opposite_sides(a, b)
    local sa, sb = side(a), side(b)
    return (sa == "friend" and sb == "foe") or (sa == "foe" and sb == "friend")
end

local ARMOR = { "armor_before", "armor_after", "armor_saved" }
local ENEMY_DEF = { "enemy_def_before", "enemy_def_after", "enemy_def_saved" }

-- Defence step of one hit, only when the game reported one (before > 0).
local function add_armor(s, keys, hit)
    local before, after = hit.before, hit.after
    if not (before and after and before > 0) then return end
    local kb, ka, ks = keys[1], keys[2], keys[3]
    s[kb] = s[kb] + before
    s[ka] = s[ka] + math.max(after, 0)
    if after > 0 then s[ks] = s[ks] + hit.final * before / after - hit.final end
end

local MAX_PENDING_ENEMY, MAX_PENDING_FIGHT = 1000, 5000
local LINK_FRAMES = 2  -- a mirror lands in the frame of the hit it mirrors or the next (seen in game)
local LINK_HP = 1      -- a mirror's HP drop is the mirrored hit's

function Fight.new(t0)
    return setmetatable({
        t0 = t0, t1 = nil, outcome = nil, actors = {}, enemies = {}, types = {},
        engaged = {},                    -- enemy key -> true once the party fought it
        pending = {}, pending_n = 0,     -- enemy key -> held hits (arrival order), their total
        dropped = 0,                     -- held hits lost to a cap
        ledger = Ledger.new(t0),
        links = {},                      -- enemy key of a linked body -> the Actor of the body kept
        kind_hits = {},                  -- kind key -> { enemy key -> { frame, drop } of its latest counted hit while
                                         -- alive }
        mirrors = {},                    -- kind key -> { actor, frame, drop }: the latest mirror no counted hit
                                         -- explained yet
        party_first = {}, seq = 0,       -- enemy key -> when the party first hit it (a count of counted hits)
        aliases = {},                    -- key of a returning enemy's new object -> the Actor of the enemy it
                                         -- continues
        paused = 0,                      -- seconds the fight stood still between a finish and a reopen
    }, Fight)
end

local function copy_flat(t)
    local c = {}
    for k, v in pairs(t) do c[k] = v end
    return c
end

function Fight.kind_key(actor)
    if actor.chara_id ~= nil then return "c" .. actor.chara_id end
    return "b:" .. (actor.base_id or actor.key)
end

-- An enemy of the fight. One that has only hit the party's side so far has the full HP of its actor and no hp
-- (unknown: the view shows the full HP). hit_hp: the HP the last counted hit on it left, nil before one (note_hp never
-- sets it): what a returning enemy is matched against (DD2DamageMeter.lua), never in a snapshot.
local function enemy_entry(self, actor)
    local e = self.enemies[actor.key]
    if not e then
        e = { actor = actor, max_hp = 0, hp = nil, killed = false }
        self.enemies[actor.key] = e
    end
    e.max_hp = math.max(e.max_hp, actor.max_hp or 0)
    return e
end

-- HP bookkeeping of an enemy victim; true when this hit is the one that killed it. `by`: whom the hit is credited to.
local function track_enemy(self, victim, hit, by)
    local e = enemy_entry(self, victim)
    e.max_hp = math.max(e.max_hp, hit.hp0)
    e.hp = math.max(hit.hp1, 0)
    e.hit_hp = e.hp
    if hit.hp1 <= 0 and not e.killed then
        e.killed = true
        e.killed_at = math.max(0, (hit.t or self.t0) - self.t0 - self.paused)
        e.killer = by
        return true
    end
    return false
end

-- How the ledger sees a counted hit: "dealt" is damage an enemy took (from a friend, or from nobody: a DoT tick),
-- "attack" an enemy's hit on a friend, "other" anything else (friendly fire, objects, enemy on enemy): recorded only.
local function role_of(attacker, victim)
    if victim.kind == "enemy" and (attacker == nil or side(attacker) == "friend") then return "dealt" end
    if attacker and attacker.kind == "enemy" and side(victim) == "friend" then return "attack" end
    return "other"
end

local function count_one(self, hit)
    local attacker, victim = hit.attacker, hit.victim
    local removed = math.max(0, hit.hp0 - hit.hp1) -- HP really taken away, no overkill
    -- The victim's own damage: an enemy's is ENV's; a party member's is his own, from its source.
    local own = attacker == nil and hit.own ~= nil
    local env = own and victim.kind == "enemy"
    local source = own and is_party(victim) and ("self:" .. tostring(hit.own)) or nil
    local by = (attacker and attacker.key) or (env and ENV.key) or source or "other"

    local v = stats_for(self, victim)
    v.taken = v.taken + removed
    v.taken_full = v.taken_full + hit.final
    v.hits_taken = v.hits_taken + 1
    add_to(v.taken_from, by, removed)
    if hit.guard then v.guard = v.guard + hit.guard end
    add_armor(v, ARMOR, hit)

    local killed = false
    if victim.kind == "enemy" then killed = track_enemy(self, victim, hit, by) end

    -- The attack name is the finer key: one skill id covers charge levels and perfect-timing
    -- variants that the details view still has to tell apart. A DoT tick has only its status.
    -- ref: { id, attack, normal = true for the game's state None, status of a DoT tick }.
    local ref = hit.skill or {}
    local key = source or ref.attack or ref.id or (ref.status and "status:" .. ref.status) or "?"
    local role = role_of(attacker, victim)
    local enemy = (role == "dealt" and victim) or (role == "attack" and attacker) or nil
    self.ledger:hit(hit, {
        removed = removed, role = role, skill = key, killed = killed,
        enemy = enemy and enemy.key, kind = enemy and Fight.kind_key(enemy),
        by = (env and ENV.key) or (source and victim.key) or nil,
    })

    if not attacker then
        -- No known attacker on an enemy: its own damage (a fall) is ENV's, any other (a DoT tick nobody applied) is
        -- Other's; the HP removed, with no kill, skill, type or defence. A party member as the victim keeps it only in
        -- taken_from (his own, or Other's); an ally or an object with no attacker is dropped by the gate and never
        -- gets here.
        if victim.kind == "enemy" then
            local o = stats_for(self, env and ENV or OTHER)
            o.dealt = o.dealt + removed
            o.dealt_full = o.dealt_full + hit.final
            o.hits = o.hits + 1
        end
        return removed
    end

    -- The attacker's entry exists even for friendly fire, so taken_from keys resolve to an actor.
    local a = stats_for(self, attacker)
    -- Friendly fire and hits on objects are damage taken, not damage dealt.
    if not opposite_sides(attacker, victim) then return removed end
    if attacker.kind == "enemy" then enemy_entry(self, attacker) end
    -- a hit of the party's side on an enemy (the side the damage-to-enemies block counts): of two enemies with the
    -- same full HP, the one hit last is the one the party fights now
    local t = hit.t or self.t0
    if victim.kind == "enemy" and t then
        local e = self.enemies[victim.key]
        e.last_hit = math.max(e.last_hit or t, t)
    end

    a.dealt = a.dealt + removed
    a.dealt_full = a.dealt_full + hit.final
    a.hits = a.hits + 1
    if killed then a.kills = a.kills + 1 end

    local sk = a.skills[key]
    if not sk then
        sk = { hits = 0, total = 0, max = 0 }
        a.skills[key] = sk
    end
    Ledger.vote_ref(sk, ref)
    sk.hits = sk.hits + 1
    sk.total = sk.total + removed
    sk.max = math.max(sk.max, removed)

    add_armor(a, ENEMY_DEF, hit)

    -- Party damage only: enemy blows and ally blows are not part of the group's types.
    if hit.types and is_party(attacker) then
        for type_key, amount in pairs(hit.types) do add_to(self.types, type_key, amount) end
    end
    return removed
end

-- The Actor a character's hits and heals count as: the body kept for a linked body, the enemy it continues for a
-- returning enemy's new object; nil for any other.
local function kept_as(self, key)
    return self.links[key] or self.aliases[key]
end

-- The hit with a linked body (or a returning enemy's new object) replaced by the body kept (the enemy it continues): a
-- new table, the caller's hit is left as it was.
local function linked(self, hit)
    local a, v = hit.attacker, hit.victim
    local la, lv = a and kept_as(self, a.key), v and kept_as(self, v.key)
    if not (la or lv) then return hit end
    local h = copy_flat(hit)
    h.attacker, h.victim = la or a, lv or v
    return h
end

local count_hit

-- Body `from`'s counters, as an enemy and on others, become `keep`'s.
local function fold(self, from, keep)
    local to = keep.key
    local ef = self.enemies[from]
    if ef then
        local et = enemy_entry(self, keep)
        et.max_hp = math.max(et.max_hp, ef.max_hp or 0)
        if et.hp == nil or (ef.hp ~= nil and ef.hp < et.hp) then et.hp = ef.hp end
        if et.hit_hp == nil or (ef.hit_hp ~= nil and ef.hit_hp < et.hit_hp) then et.hit_hp = ef.hit_hp end
        if ef.killed and not et.killed then et.killed, et.killed_at, et.killer = true, ef.killed_at, ef.killer end
        if ef.last_hit and (et.last_hit == nil or ef.last_hit > et.last_hit) then et.last_hit = ef.last_hit end
        self.enemies[from] = nil
    end
    local sf = self.actors[from]
    if sf then
        local st = stats_for(self, keep)
        for k, v in pairs(sf) do
            if type(v) == "number" then st[k] = (st[k] or 0) + v end
        end
        for k, v in pairs(sf.taken_from) do add_to(st.taken_from, k, v) end
        for k, v in pairs(sf.heal_sources) do add_to(st.heal_sources, k, v) end
        for k, sk in pairs(sf.skills) do
            local t = st.skills[k]
            if t == nil then
                st.skills[k] = sk
            else
                t.hits, t.total, t.max = t.hits + sk.hits, t.total + sk.total, math.max(t.max, sk.max)
            end
        end
        self.actors[from] = nil
    end
    for _, s in pairs(self.actors) do
        local v = s.taken_from[from]
        if v then
            s.taken_from[from] = nil
            add_to(s.taken_from, to, v)
        end
    end
    for _, e in pairs(self.enemies) do
        if e.killer == from then e.killer = to end
    end
    if self.engaged[from] then self.engaged[to] = true end
    self.engaged[from] = nil
    local first = self.party_first[from]
    if first and (self.party_first[to] == nil or first < self.party_first[to]) then self.party_first[to] = first end
    self.party_first[from] = nil
    self.ledger:fold(from, to)
    -- what waited for it is the kept one's now, and the kept one is engaged (the party hit it, or it was counted)
    local held = self.pending[from]
    if held then
        self.pending[from] = nil
        self.pending_n = self.pending_n - #held
        -- counted after the hit that linked, their HP is older: the pool keeps its lowest
        local e = self.enemies[to]
        local hp, hit_hp = e and e.hp, e and e.hit_hp
        for _, h in ipairs(held) do count_hit(self, h) end
        if e and hp and e.hp and hp < e.hp then e.hp = hp end
        if e and hit_hp and e.hit_hp and hit_hp < e.hit_hp then e.hit_hp = hit_hp end
    end
end

-- Bodies a and b mirror each other: the one the party hit first is kept (a when neither was), the other is folded in.
local function link(self, a, b)
    local keep, gone = a, b
    local fa, fb = self.party_first[a.key], self.party_first[b.key]
    if fb and (fa == nil or fb < fa) then keep, gone = b, a end
    self.links[gone.key] = keep
    for key, to in pairs(self.links) do
        if to.key == gone.key then self.links[key] = keep end
    end
    local hits = self.kind_hits[Fight.kind_key(gone)]
    if hits then hits[gone.key] = nil end
    fold(self, gone.key, keep)
end

local function within(early, late)
    return early ~= nil and late ~= nil and late >= early and late - early <= LINK_FRAMES
end

-- A hit's HP drop and a mirror's are the same.
local function same_drop(a, b)
    return math.abs(a - b) <= LINK_HP
end

-- A mirror on body b: linked to the living enemy of its kind that took a counted hit just before, else kept a moment
-- for a counted hit that comes right after (the game can mirror inside the hit, before it is counted); never counted.
local function mirror(self, hit)
    local b, f, drop = hit.victim, hit.frame, hit.hp0 - hit.hp1
    if self.links[b.key] or f == nil or not (drop > 0) then return end
    local kind = Fight.kind_key(b)
    local best, best_frame = nil, nil
    for key, at in pairs(self.kind_hits[kind] or {}) do
        local e = self.enemies[key]
        if key ~= b.key and e and not e.killed and within(at.frame, f) and same_drop(at.drop, drop)
            and (best_frame == nil or at.frame > best_frame) then
            best, best_frame = e.actor, at.frame
        end
    end
    if best then
        self.mirrors[kind] = nil
        return link(self, best, b)
    end
    self.mirrors[kind] = { actor = b, frame = f, drop = drop }
end

-- A counted hit on a living enemy: noted for the mirrors of its kind, and it explains a mirror that came just before.
local function note_hit(self, hit)
    local victim, attacker = hit.victim, hit.attacker
    if victim.kind ~= "enemy" then return end
    self.seq = self.seq + 1
    if attacker and is_party(attacker) and self.party_first[victim.key] == nil then
        self.party_first[victim.key] = self.seq
    end
    if hit.frame == nil or not (hit.hp0 > 0) then return end
    local kind = Fight.kind_key(victim)
    local hits = self.kind_hits[kind]
    if not hits then
        hits = {}
        self.kind_hits[kind] = hits
    end
    local drop = hit.hp0 - hit.hp1
    hits[victim.key] = { frame = hit.frame, drop = drop }
    local m = self.mirrors[kind]
    if m and m.actor.key ~= victim.key and not self.links[m.actor.key] and within(m.frame, hit.frame)
        and same_drop(m.drop, drop) then
        self.mirrors[kind] = nil
        link(self, victim, m.actor)
    end
end

function count_hit(self, hit)
    hit = linked(self, hit)
    local removed = count_one(self, hit)
    note_hit(self, hit)
    return removed
end

-- The enemy a hit between non-party characters is about: its victim, else its attacker.
local function enemy_of(hit)
    if hit.victim.kind == "enemy" then return hit.victim end
    local attacker = hit.attacker
    if attacker and attacker.kind == "enemy" then return attacker end
    return nil
end

local function hold(self, enemy, hit)
    local list = self.pending[enemy.key]
    if self.pending_n >= MAX_PENDING_FIGHT or (list and #list >= MAX_PENDING_ENEMY) then
        self.dropped = self.dropped + 1
        return
    end
    if not list then
        list = {}
        self.pending[enemy.key] = list
    end
    list[#list + 1] = hit
    self.pending_n = self.pending_n + 1
end

-- The party fights this enemy: what waited for it is counted now, in arrival order, ahead of the hit that engaged it.
local function engage(self, enemy)
    if self.engaged[enemy.key] then return end
    self.engaged[enemy.key] = true
    local list = self.pending[enemy.key]
    if not list then return end
    self.pending[enemy.key] = nil
    self.pending_n = self.pending_n - #list
    for _, held in ipairs(list) do count_hit(self, held) end
end

function Fight:add_hit(hit)
    if hit.mirror then return mirror(self, hit) end
    hit = linked(self, hit)
    local attacker, victim = hit.attacker, hit.victim
    local party_attacks = attacker ~= nil and is_party(attacker)
    if party_attacks or is_party(victim) then
        local enemy = party_attacks and victim or attacker
        if enemy and enemy.kind ~= "enemy" then enemy = nil end
        if enemy then
            -- A blow on a corpse is no proof that the party fights this enemy; a burn tick on a living one is the party's
            -- damage (spreading fire), so it engages.
            if party_attacks and not self.engaged[enemy.key] and hit.hp0 <= 0 then
                return hold(self, enemy, hit)
            end
            engage(self, enemy)
        end
        return count_hit(self, hit)
    end
    local enemy = enemy_of(hit)
    if enemy == nil then return end
    if self.engaged[enemy.key] then return count_hit(self, hit) end
    hold(self, enemy, hit)
end

-- True once the party fought this enemy (it hit it, or was hit by it): what others do to it counts.
function Fight:is_engaged(enemy_key)
    local to = kept_as(self, enemy_key)
    return self.engaged[to and to.key or enemy_key] == true
end

-- Hits that were held and are not in the numbers: still pending, or dropped by a cap.
function Fight:held()
    return self.pending_n + self.dropped
end

function Fight:add_heal(heal)
    -- a linked body's heal is the kept one's (a returning enemy's new object's, the enemy's it continues)
    local lt = heal.target and kept_as(self, heal.target.key)
    local lh = heal.healer and kept_as(self, heal.healer.key)
    if lt or lh then
        heal = copy_flat(heal)
        heal.target, heal.healer = lt or heal.target, lh or heal.healer
    end
    local source = heal.source or {}
    local healer = heal.healer
    if not healer then
        healer = source.kind == "item" and heal.target or OTHER
    end
    if not (is_party(healer) or is_party(heal.target) or self.actors[heal.target.key]) then return end
    local key, ledger_key = "other", "other"
    if source.kind == "skill" then
        key = "skill"
        ledger_key = source.id and ("skill_id:" .. tostring(source.id)) or ("skill:" .. (source.name or "?"))
    elseif source.kind == "item" then
        key = "item:" .. (source.item_id or "?")
        ledger_key = key
    elseif source.kind == "self" then
        key = "self:" .. (source.name or "?")
        ledger_key = key
    end

    local h = stats_for(self, healer)
    h.heal_done = h.heal_done + heal.effective
    add_to(h.heal_sources, key, heal.effective)
    local r = stats_for(self, heal.target)
    r.heal_received = r.heal_received + heal.effective
    self.ledger:heal(heal, { healer = healer.key, source = ledger_key })
end

function Fight:finish(t1, outcome)
    self.t1 = t1
    self.outcome = outcome
end

-- The finished fight goes on from `t`; the time since its finish is paused (out of its duration, its kills' and
-- its record's times), its end and outcome are to come.
function Fight:reopen(t)
    local gap = math.max(0, t - (self.t1 or t))
    self.paused = self.paused + gap
    self.ledger:pause(gap)
    self.t1, self.outcome = nil, nil
end

-- The character `key` (a returning enemy's new object) is the fight's enemy `to_key` from now on: its hits and
-- heals count as that enemy's, as a linked body's do.
function Fight:alias(key, to_key)
    local e = self.enemies[to_key]
    if e == nil or key == to_key then return end
    self.aliases[key] = e.actor
end

local function finite(x)
    return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

-- The HP character `key` has now, as the game shows it, read outside the hits (DD2DamageMeter.lua: the HP numbers'
-- read of a frame): the HP the game takes away (or gives back) where no counted hit sees it, and the HP of a hit
-- before the live window's next build. The fight's enemy it counts as (itself, the body kept for a linked body, the
-- enemy a returning enemy's new object continues) takes `hp` as its HP left and `full` as its full HP when that is
-- more. Nothing for:
--   - a key that is no enemy of the fight, or a killed one (its 0 and its kill stay);
--   - an `hp` that is not a finite number above 0: an enemy dies by a counted hit, never by a read;
--   - a `full` that differs from the full HP its Actor has (when that is known, above 0): another character than the
--     one the fight met (an address the game gave anew); a `full` that is no finite number is not compared.
-- Only `hp`: the HP its last counted hit left (hit_hp, what a returning enemy is matched against) stays as it was.
-- Gives that enemy's key and its entry (the fight's own table, to read: max_hp, hp, killed); nil when nothing was
-- taken, and then, when it was left out for its `full` alone, a second value { key, name, max_hp }: that enemy's key,
-- its Actor's name and full HP (for debug.log: such a refusal is told apart from the others).
function Fight:note_hp(key, hp, full)
    if not (finite(hp) and hp > 0) then return nil end
    local to = kept_as(self, key)
    if to then key = to.key end
    local e = self.enemies[key]
    if e == nil or e.killed then return nil end
    local known = e.actor.max_hp
    if finite(full) and finite(known) and known > 0 and full ~= known then
        return nil, { key = key, name = e.actor.name, max_hp = known }
    end
    e.hp = hp
    if finite(full) and full > e.max_hp then e.max_hp = full end
    return key, e
end

-- The actor is copied too: a later rename or kind change (a pawn's HUD name, a dismissed pawn, a neutral who
-- turned ally) does not rewrite a snapshot already taken, while every new snapshot shows the current one.
local function copy_stats(s)
    local c = copy_flat(s)
    c.actor = copy_flat(s.actor)
    c.taken_from = copy_flat(s.taken_from)
    c.heal_sources = copy_flat(s.heal_sources)
    c.skills = {}
    for k, sk in pairs(s.skills) do
        c.skills[k] = copy_flat(sk)
        c.skills[k].votes, c.skills[k].lead = nil, nil
    end
    return c
end

-- Independent copy: later hits do not change a snapshot already taken (history keeps them). Only a full one (the
-- journal's) carries the ledger's detail.
function Fight:snapshot(now, full)
    local actors, enemies = {}, {}
    for k, s in pairs(self.actors) do actors[k] = copy_stats(s) end
    for k, e in pairs(self.enemies) do
        enemies[k] = copy_flat(e)
        enemies[k].actor = copy_flat(e.actor)
        enemies[k].hit_hp = nil
    end
    return {
        t0 = self.t0, t1 = self.t1, outcome = self.outcome,
        duration = math.max(0, (self.t1 or now) - self.t0 - self.paused),
        paused = self.paused > 0 and self.paused or nil,
        actors = actors, enemies = enemies, types = copy_flat(self.types),
        detail = full and self.ledger:snapshot() or nil,
    }
end

return Fight
