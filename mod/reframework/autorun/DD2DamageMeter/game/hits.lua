-- Hits from the game's damage pipeline, in the call order logged in game. One call of
-- app.HitController.damageProc(DamageInfo) is one hit: its pre-hook opens a context in its hook storage, the hooks
-- that run inside it (defence step, region step, updateDamage, subGuardHp) fill the context of the same DamageInfo,
-- and its post-hook turns the context into one Hit (shape: fight.lua) when updateDamage ran, or into a heal-area touch
-- when the mage's healing spot touched somebody. Nested damageProc calls each keep their own context. Read-only: hook
-- rules in game/hook.lua.
--
-- The Hit's damage by type comes in two steps: the defence step (before, after, types: the defence is subtracted) and
-- the region step (region.before / region.after: each type multiplied by the hit part's factor, keyed like types;
-- region.no the RegionStatusNo of the part, region.part its type when the victim is an enemy, game/enemies.lua). The
-- element is DamageInfo:get_ElementType(): the attack's own _ElementType says -1 for an enchanted weapon and 0 for a
-- mage's bolt that hits as Thunder. Hit.foe is the data of the enemy side of the hit (game/enemies.lua): the victim's
-- when the victim is an enemy, else the attacker's when that is one.
-- For the damage numbers, and only while sink.points() says so, a hit on an enemy also carries Hit.point (the
-- DamageInfo's ContactInfo Position, the hit point in world space; when that is missing or the origin, as a DoT tick
-- may have it, about 1 m above the victim's root; nil when neither can be read), Hit.weak_damage (IsWeakDamage is
-- true) and Hit.target_bonus: what the enemy calculator's defence step added to the DamageRate (after - before), the
-- game's bonus for the enemy's state (+0.5 on a downed enemy); the attacker's buffs (the Trickster's incense, a jump
-- attack) are added before it, in his own step (measured in game). Nil when the step did not run or was not
-- read: the DamageRate is read around it only on that calculator and only while sink.points() or sink.debug() says
-- so.
-- For the debug collector (game/collector.lua), and only while sink.debug() says so: a hit on an enemy (no mirror)
-- carries Hit.target_bonus as above and Hit.target_rate, the DamageRate before that step (not its hit point or
-- IsWeakDamage); a hit on an enemy with no attacker at its end (its own, a DoT tick nobody known caused, a mirror),
-- or a knock hit (below), carries Hit.damage_type and Hit.flag, the DamageInfo's DamageType and Flag as integers
-- (Flag read as for a mirror), and a knock hit Hit.knock_gap, the seconds since the friend's hit that knocked; and
-- sink.met hands over the victim of each hit on an enemy that still had HP. With sink.debug() and sink.points() both
-- off none of them is read.
-- Hit.own says the victim did it to himself: a hit that is no DoT tick, with no attacker or one that resolves to
-- the victim; on an enemy ("self": a fall, a slam after being blown away, a part breaking off; seen in game: no
-- attacker and no AttackGameObject) unless it is a knock hit (below), on a party member when the DamageInfo names his
-- own GameObject as the attacking one (AttackGameObject, read only for such hits): Blood Pact's HP cost. "blood_pact"
-- for a party member who has the Warrior's Blood Pact (Job05_ScarletVow) equipped in his current vocation (asked
-- again at most every PACT_EVERY seconds per member: the cost ticks about every frame), else "self"; Hit.attacker is
-- then nil.
-- Hit.knock: such an enemy's own damage that comes at most KNOCK_WINDOW s (by Hit.t's clock, not before it)
-- after the last hit a friend (a player, a pawn or an ally) did to that enemy is that friend's: an enemy blown away
-- and slamming down. Hit.attacker is then that friend, Hit.skill a copy of that hit's skill reference ({ id, attack,
-- normal }), Hit.own nil and Hit.knock true, and the hit counts as the friend's in every way (the fight, the damage
-- numbers, a party member's sink.party_hit). Without such a hit it is its own as above. The last friend's hit is kept
-- per enemy key: a friend's hit on an enemy that is no DoT tick, no mirror and no knock hit; at most MAX_KNOCKERS
-- enemies, a new one past that drops the one hit longest ago.
-- Hit.mirror: a hit on an enemy with no attacker (or one that resolves to the victim) whose DamageInfo Flag has bit
-- 39 set (MIRROR_BIT; Flag read only for such hits, DoT ticks included, before the DoT check: a burning body mirrors
-- too) is a link mirror, never a DoT tick nor its own: an enemy of two bodies with one HP pool (the Evil Eye) loses on
-- its other body what the hit body lost (seen in game), or a sync of the two that changes nothing; it reads
-- nothing more (no skill, status or hit point). Hit.frame: the sink's frame of the hit.
--
--   hits.install(sink, attrib) -> number of hooked methods (7), { "Type.method(...)" } of the missing ones
--     sink.hit(Hit); sink.touch(frame, healer, target_key, ref, t); sink.status(t, victim_key, status, applier);
--     sink.party_hit(t, enemy_key), called before the hit's sink.hit so that a fight can start first, for a direct
--     blow between the party and an enemy that still had HP (no DoT tick, no corpse; a party member's knock hit is
--     his blow); enemy_key is the actor key of the enemy side of the hit;
--     sink.strike(frame, attacker_key) as a party member's or an ally's hit on an enemy starts (damageProc's
--     pre-hook): its attacker is a player, a pawn or an ally (an ally too, for her lifesteal; a neutral character is
--     an ally only from the end of his first hit on an enemy), its victim an enemy (a hit on a friend, an ally or an
--     object, a healing-spot touch, is none); a lifesteal heal can come before the hit ends, and a hit that ends
--     uncounted or with no HP removed was one all the same. The attacker read there is the hit's attacker at its end
--     too (read once per hit);
--     sink.now() -> t and sink.frame() -> frame number are the clock (default os.clock() and 0);
--     sink.points() -> true to read the damage numbers' fields of a hit on an enemy (none: never);
--     sink.debug() -> true to read the debug collector's fields of a hit on an enemy (none: never);
--     sink.met(character, actor, t), while sink.debug() says so, for each hit on an enemy that still had HP (not on a
--     corpse), before its sink.hit: the victim's character (only for the call: not kept) and Actor, the hit's time;
--     attrib: optional Attrib, asked for a DoT's source only where the game cannot tell
--   hits.reset()  forgets open contexts, the skills learned for shell attacks, the Blood Pact checks and the friends'
--                 hits kept for knocks (scene change)
--   hits.info()   { open, learned, errors, last_error }
local Safe = require("DD2DamageMeter/game/safe")
local Hook = require("DD2DamageMeter/game/hook")
local actors = require("DD2DamageMeter/game/actors")
local enemies = require("DD2DamageMeter/game/enemies")
local names_game = require("DD2DamageMeter/game/names_game")

local Hits = {}

local DI = "app.HitController.DamageInfo"
local HOOKS = {
    damageProc = { "app.HitController", "damageProc(" .. DI .. ")" },
    player_defence = { "app.PlayerDamageCalculator", "calcDamageValueDefence(" .. DI .. ")" },
    enemy_defence = { "app.ExceptPlayerDamageCalculator", "calcDamageValueDefence(" .. DI .. ")" },
    region = { "app.HitController", "calcRegionDamageRate(" .. DI .. ")" },
    updateDamage = { "app.HitController", "updateDamage(" .. DI .. ", System.UInt32, System.Single, System.Boolean)" },
    subGuardHp = { "app.HitController", "subGuardHp(System.Single, " .. DI .. ")" },
    applyStatusDamage = { "app.CharacterDamageCalculator",
        "applyStatusDamage(" .. DI .. ", app.StatusConditionDef.StatusConditionEnum, System.Single)" },
}

-- DamageInfo damage by type; a negative value means "no damage of this type" (as logged in game).
local DAMAGE = {
    { "SlashDamage", "Slash" }, { "BlowDamage", "Blow" }, { "ShootDamage", "Shoot" }, { "MagicDamage", "Magic" },
    { "NonMagicElementDamage", "NonMagicElement" }, { "FixedDamage", "Fixed" },
}

-- app.AttackUserData.ElementType by value, as DamageInfo:get_ElementType() gives it; any other value is no element.
local ELEMENT = { [0] = "None", "Fire", "Ice", "Thunder", "Light", "Dark" }

-- Statuses that tick damage, app.StatusConditionDef.StatusConditionEnum.
local DOT = { { 1, "Poison" }, { 5, "FireSpread" }, { 7, "VirulentPoison" }, { 8, "Frostbite" }, { 9, "Freeze" },
              { 13, "Electric" }, { 14, "WetElectric" } }
local DOT_NAME = {}
for _, s in ipairs(DOT) do DOT_NAME[s[1]] = s[2] end
local ACTIVE = "IsStatusConditionActive(app.StatusConditionDef.StatusConditionEnum, System.Boolean)"
local EQUIPPED = "hasEquipedSkill(app.Character.JobEnum, app.HumanCustomSkillID)"
local BLOOD_PACT = "Job05_ScarletVow"  -- the Warrior's skill that costs its user HP all the while it is on
local MIRROR_BIT = 39                   -- DamageInfo.Flag bit of a hit that mirrors a linked body's loss
local CAUSED = "getStatusConditionCausedCharacterId(app.StatusConditionDef.StatusConditionEnum)"

local HEAL_AREA = "ヒーリング"   -- part of the healing spot's attack name ヒーリングスポット
local PARTY = { player = true, pawn = true }
local FRIEND = { player = true, pawn = true, ally = true }
local MAX_OPEN = 64      -- open contexts; more means calls whose post-hook never came
local MAX_LEARNED = 1024 -- (attacker, shell attack name) pairs with a learned skill
local PACT_EVERY = 1.0   -- s a party member's Blood Pact check is kept
local MAX_PACTS = 16     -- members with a kept check; more means a party that changed many times
local KNOCK_WINDOW = 3   -- s after a friend's hit on an enemy that the enemy's own damage is that friend's
local MAX_KNOCKERS = 64  -- enemies with a kept friend's hit; past it the oldest is dropped
-- names_game.attack_skill rules that name a skill by its Japanese name: they override a state or a shell's majority
local BY_JA_NAME = { ja = true, ja_prefix = true }

local key_of, obj, number = Hook.key_of, Hook.obj, Hook.number

local sink, attrib = nil, nil
local open, n_open = {}, 0         -- DamageInfo address -> context of the innermost damageProc running on it
-- attacker key .. "|" .. shell attack name -> { counts = { state -> hits }, best, best_n }
local learned, n_learned = {}, 0
local pacts, n_pacts = {}, 0       -- party actor key -> { t, on }: his Blood Pact check, made at t
-- enemy actor key -> { attacker, t, skill = { id, attack, normal } }: the last friend's hit on it
local knockers, n_knockers = {}, 0

function Hits.reset()
    open, n_open = {}, 0
    learned, n_learned = {}, 0
    pacts, n_pacts = {}, 0
    knockers, n_knockers = {}, 0
end

function Hits.info()
    local h = Hook.info()
    return { open = n_open, learned = n_learned, errors = h.errors, last_error = h.last_error }
end

local function clock(name, default)
    local fn = sink and sink[name]
    if fn then
        local ok, v = pcall(fn)
        if ok and number(v) then return v end
    end
    return default()
end
local function zero() return 0 end
local function now() return clock("now", os.clock) end
local function frame() return clock("frame", zero) end

-- Every sink call on its own: a broken one costs its own event only.
local function emit(name, ...)
    local fn = sink and sink[name]
    if fn == nil then return end
    local ok, err = pcall(fn, ...)
    if not ok then Hook.fail("hits sink." .. name, err) end
end

local function text(v)
    if type(v) == "string" and v ~= "" then return v end
    return nil
end

-- Damage in the DamageInfo now: the sum of max(0, x) over the types plus EnchantDamage * EnchantRate; `types`
-- (optional) gets each type with damage, keyed without "Damage".
local function damage_of(di, types)
    local total = 0
    for _, d in ipairs(DAMAGE) do
        local x = number(Safe.field(di, d[1]))
        if x and x > 0 then
            total = total + x
            if types then types[d[2]] = x end
        end
    end
    local e, rate = number(Safe.field(di, "EnchantDamage")), number(Safe.field(di, "EnchantRate"))
    local x = e and rate and number(e * rate)
    if x and x > 0 then
        total = total + x
        if types then types.Enchant = x end
    end
    return total
end

-- The attacker, as logged in game: the owner of a shell (arrows, spells), else the attacking hit controller's
-- character, else the attack's owner game object. The second result tells a shell hit.
local function attacker_of(di)
    local ahc = Safe.field(di, "<AttackHitController>k__BackingField")
    local shell = Safe.field(ahc, "<CachedShell>k__BackingField")
    if shell ~= nil then
        local owner = Safe.field(shell, "<OwnerCharacter>k__BackingField") or Safe.call(shell, "get_OwnerCharacter")
        if owner ~= nil then return owner, true end
    end
    local c = Safe.call(ahc, "get_CachedCharacter")
    if c == nil then
        local owner = Safe.field(di, "<AttackOwnerObject>k__BackingField")
        local character_type = owner and Safe.try(sdk.typeof, "app.Character")
        if character_type then c = Safe.call(owner, "getComponent(System.Type)", character_type) end
    end
    return c, shell ~= nil
end

-- The hit's attacker as damageProc's pre-hook read it (ctx.di: the DamageInfo it had); read now when it had none.
local function attacker_at_start(ctx, di)
    if ctx.di ~= nil then return ctx.attacker, ctx.shell end
    return attacker_of(di)
end

-- Whether bit `n` of a 64-bit flag is set: the game gives an integer (a float or a boxed value is read too, without
-- losing the bit); nil when it is no number.
local function flag_bit(v, n)
    if type(v) == "table" or type(v) == "userdata" then v = Safe.field(v, "value__") end
    if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
    local i = math.tointeger(v)
    if i then return (i >> n) & 1 == 1 end
    if math.type(v) == "float" and v == math.floor(v) then return math.floor(math.abs(v) / 2 ^ n) % 2 == 1 end
    return nil
end

-- The victim: the character of updateDamage's hit controller, else of the DamageInfo's.
local function victim_of(ctx, di)
    local c = Safe.call(ctx.hc, "get_CachedCharacter")
    if c ~= nil then return c end
    return Safe.call(Safe.field(di, "<DamageHitController>k__BackingField"), "get_CachedCharacter")
end

-- The attacker's (app.Human's) skill state: its HumanCustomSkillID name, "" for None, nil when it cannot be read or
-- the enum does not know the value.
local function state_of(human)
    local state = number(Safe.field(human, "<CustomSkillState>k__BackingField"))
    if state == nil then return nil end
    if state == 0 then return "" end
    return names_game.enum_name("app.HumanCustomSkillID", state)
end

-- A hit's skill is the attacker's state at hit time; a shell lands late (Firestorm burns on while the mage casts
-- something else), so a shell hit takes the state seen on most of its attacker's hits of its attack name instead. Hits
-- without a state vote too (""): the mage's normal bolt once flew during Thunder Boon (seen in game) and stays a
-- normal attack. A state that cannot be named votes "?" and says nothing. A tie keeps the leader. `who` is the
-- attacker's key (nil: unknown, its votes pooled). A shell that lands during another skill's state (Meteor's rocks,
-- Blizzard's shells) is named by its attack name instead, where that names a skill (skill_by_name). Gives the skill
-- id, or nil and true for a normal attack (the state None), or nil when nothing is known.
local function skill_of(human, attack, shell, who)
    local state = state_of(human)
    if shell then
        if attack == nil then return nil end
        local key = (who or "?") .. "|" .. attack
        local l = learned[key]
        if l == nil then
            if n_learned >= MAX_LEARNED then learned, n_learned = {}, 0 end
            l = { counts = {}, best = "?", best_n = 0 }
            learned[key] = l
            n_learned = n_learned + 1
        end
        local vote = state or "?"
        local n = (l.counts[vote] or 0) + 1
        l.counts[vote] = n
        if n > l.best_n then l.best, l.best_n = vote, n end
        state = l.best
    end
    if state == "" then return nil, true end
    if state == "?" then return nil end
    return state
end

-- The app.Human's current vocation (app.Character.JobEnum), nil when it cannot be read.
local function job_of(human)
    return number(Safe.field(Safe.call(human, "get_JobContext"), "CurrentJob"))
end

-- The game's own answer: the skill `value` (a HumanCustomSkillID) is equipped in vocation `job`.
local function equipped(human, job, value)
    return Safe.call(Safe.field(human, "<SkillContext>k__BackingField"), EQUIPPED, job, value) == true
end

-- The skill an attack name points at in the attacker's vocation (names_game.attack_skill), when it changes what the
-- state said (`id`) and the attacker has it equipped there: a CS number, an older skill's ("cs") or a newer one's
-- ("cs_tu"), only names a hit the state did not name (None, or a value the enum does not know); the skill's Japanese
-- name, exact or by its start, also overrides a state or a shell's majority that names another skill.
local function skill_by_name(human, attack, id)
    local job = job_of(human)
    local name, value, rule = names_game.attack_skill(attack, job)
    if name == nil or name == id or (id ~= nil and not BY_JA_NAME[rule]) then return nil end
    if not equipped(human, job, value) then return nil end
    return name
end

-- Blood Pact equipped in the party member's current vocation, as asked at most PACT_EVERY seconds before `t`.
local function blood_pact(character, actor, t)
    local kept = pacts[actor.key]
    if kept and t >= kept.t and t - kept.t < PACT_EVERY then return kept.on end
    local human = Safe.call(character, "get_Human")
    local job, value = job_of(human), names_game.enum_value("app.HumanCustomSkillID", BLOOD_PACT)
    local on = job ~= nil and value ~= nil and equipped(human, job, value)
    if kept == nil then
        if n_pacts >= MAX_PACTS then pacts, n_pacts = {}, 0 end
        n_pacts = n_pacts + 1
    end
    pacts[actor.key] = { t = t, on = on }
    return on
end

-- A party member's own damage, when the DamageInfo's AttackGameObject is his GameObject (the DamageInfo's
-- DamageGameObject when the character gives none): "blood_pact" with Blood Pact equipped in his current vocation,
-- else "self"; nil when it is not his own.
local function own_damage(di, victim_char, victim, t)
    local by = Safe.address(Safe.field(di, "<AttackGameObject>k__BackingField"))
    if by == nil then return nil end
    local go = Safe.call(victim_char, "get_GameObject") or Safe.field(di, "<DamageGameObject>k__BackingField")
    if by ~= Safe.address(go) then return nil end
    if blood_pact(victim_char, victim, t) then return "blood_pact" end
    return "self"
end

local function skill_ref(skill)
    return { id = skill.id, attack = skill.attack, normal = skill.normal }
end

-- A friend's hit on an enemy at t, kept as the one that may knock it down; a new enemy past MAX_KNOCKERS drops the
-- one hit longest ago.
local function note_knocker(victim, attacker, t, skill)
    if knockers[victim.key] == nil then
        if n_knockers >= MAX_KNOCKERS then
            local oldest, oldest_t = nil, nil
            for key, k in pairs(knockers) do
                if oldest_t == nil or k.t < oldest_t then oldest, oldest_t = key, k.t end
            end
            knockers[oldest] = nil
            n_knockers = n_knockers - 1
        end
        n_knockers = n_knockers + 1
    end
    knockers[victim.key] = { attacker = attacker, t = t, skill = skill_ref(skill) }
end

-- The friend whose hit on the enemy came at most KNOCK_WINDOW s before t, a copy of that hit's skill reference and the
-- seconds between them; nil when there is none.
local function knocker_of(victim, t)
    local k = knockers[victim.key]
    if k == nil or t < k.t or t - k.t > KNOCK_WINDOW then return nil end
    return k.attacker, skill_ref(k.skill), t - k.t
end

local function dot_source(t, victim_key, status)
    if attrib == nil then return nil end
    local ok, a = pcall(function() return attrib:dot_source(t, victim_key, status) end)
    if ok then return a end
    Hook.fail("hits attrib.dot_source", a)
    return nil
end

-- A tick without an attack is credited through the victim's active statuses and who caused them (a party or ally
-- CharacterID); Attrib's record is the fallback when the game cannot be asked, and also when an active status's
-- causer is nobody we know (an enemy's poison on the party: Attrib may know that enemy, and crediting it so does no
-- harm). No active status: nobody («прочее»), so fall damage is never blamed on the last one who stunned the victim.
local function dot_credit(t, character, victim)
    local sc = Safe.call(character, "get_StatusConditionCtrl")
    local asked, first = false, nil
    if sc ~= nil then
        for _, s in ipairs(DOT) do
            local on = Safe.call(sc, ACTIVE, s[1], false)
            if on ~= nil then asked = true end
            if on == true then
                local who = actors.by_chara_id(Safe.call(sc, CAUSED, s[1]))
                if who then return who, s[2] end
                first = first or s[2]
            end
        end
    end
    if not asked then return dot_source(t, victim.key, nil), nil end
    if first then return dot_source(t, victim.key, first), first end
    return nil, nil
end

-- The sink's answer to sink[name](): true only when it says true (none, or one that raises, is false).
local function wanted(name)
    local fn = sink and sink[name]
    if fn == nil then return false end
    local ok, on = pcall(fn)
    return ok and on == true
end

local function points_wanted() return wanted("points") end
local function debug_wanted() return wanted("debug") end

local ROOT_LIFT = 1.0 -- m above the victim's root (at its feet): a hit without a hit point shows about mid-body

local function xyz(p) return p.x, p.y, p.z end

-- p and its coordinates when it is a place: three numbers, not all 0 (a ContactInfo nobody filled in).
local function place(p)
    if p == nil then return nil end
    local ok, x, y, z = pcall(xyz, p)
    if not (ok and number(x) and number(y) and number(z)) or (x == 0 and y == 0 and z == 0) then return nil end
    return p, x, y, z
end

local function lifted(x, y, z) return Vector3f.new(x, y + ROOT_LIFT, z) end

-- The hit point; else ROOT_LIFT above the victim's root, a new vector (the root itself without Vector3f.new).
local function point_of(di, victim_char)
    local p = place(Safe.field(di, "<Position>k__BackingField"))
    if p ~= nil then return p end
    local root, x, y, z = place(Safe.call(Safe.call(Safe.call(victim_char, "get_GameObject"), "get_Transform"),
        "get_Position"))
    if root == nil then return nil end
    local ok, v = pcall(lifted, x, y, z)
    if ok and v ~= nil then return v end
    return root
end

local function finish_hit(ctx)
    local final, hp0, hp1 = number(ctx.final), number(ctx.hp0), number(ctx.hp1)
    if not (final and hp0 and hp1) then return end
    local di = ctx.di or obj(ctx.slot)
    if di == nil then return end
    local victim_char = victim_of(ctx, di)
    local victim = actors.of(victim_char)
    if victim == nil then return end
    local t = now()
    local aud = Safe.field(di, "<AttackUserData>k__BackingField")
    local attacker_char, shell = attacker_at_start(ctx, di)
    local attacker = actors.of(attacker_char)
    local skill, status = {}, nil
    local element = ELEMENT[Safe.enum(Safe.call(di, "get_ElementType"))]
    -- a link mirror first: a body that burns mirrors all the same, and it is no DoT tick
    local mirror, flag = nil, nil
    if victim.kind == "enemy" and (attacker == nil or attacker.key == victim.key) then
        flag = Safe.field(di, "Flag")
        if flag_bit(flag, MIRROR_BIT) then mirror, attacker = true, nil end
    end
    if mirror then
        -- nothing more to read: it is never counted
    elseif aud ~= nil then
        skill.attack = text(Safe.call(aud, "get_Name"))
        local human = Safe.call(attacker_char, "get_Human")
        -- the attacker's actor key, else its human's address
        local who = attacker and attacker.key
        if who == nil then
            local addr = Safe.address(human)
            who = addr and "h" .. addr
        end
        skill.id, skill.normal = skill_of(human, skill.attack, shell, who)
        local named = skill.attack and attacker and attacker.kind ~= "enemy"
            and skill_by_name(human, skill.attack, skill.id)
        if named then skill.id, skill.normal = named, nil end
    elseif attacker == nil then
        -- a DoT tick: its status is all there is to say about it
        attacker, status = dot_credit(t, victim_char, victim)
        skill = { status = status }
    end
    -- a hit with no attacker that is no DoT tick nor a mirror: an enemy's own, unless a friend's hit on it came just
    -- before (then it is that friend's, a knock), a party member's own when the DamageInfo says so; the fight
    -- drops one on anyone else
    local own, knock, gap = nil, nil, nil
    if not mirror and status == nil and (attacker == nil or attacker.key == victim.key) then
        if victim.kind == "enemy" then
            local by, ref
            by, ref, gap = knocker_of(victim, t)
            if by then
                attacker, skill, knock = by, ref, true
            else
                own, attacker = "self", nil
            end
        elseif PARTY[victim.kind] then
            own = own_damage(di, victim_char, victim, t)
        end
        if own then attacker = nil end
    end
    -- a neutral character fighting an enemy is an ally from now on
    if attacker then
        if attacker.kind == "other" and victim.kind == "enemy" then actors.mark_fighting(attacker) end
        if victim.kind == "other" and attacker.kind == "enemy" then actors.mark_fighting(victim) end
        -- a burn tick after the music, or a blow on a corpse (the game runs updateDamage on the dead too), is no
        -- party hit: it would open a fight of its own
        local party = (PARTY[attacker.kind] and victim.kind == "enemy")
            or (PARTY[victim.kind] and attacker.kind == "enemy")
        if party and status == nil and hp0 > 0 then
            emit("party_hit", t, (victim.kind == "enemy" and victim or attacker).key)
        end
        -- a friend's blow on an enemy (no DoT tick, no knock) is the one that may knock it down
        if victim.kind == "enemy" and FRIEND[attacker.kind] and status == nil and not knock then
            note_knocker(victim, attacker, t, skill)
        end
    end
    -- the enemy side of the hit: the victim when it is an enemy, else the attacker when it is one; the part is the
    -- victim's
    local foe
    if victim.kind == "enemy" then
        foe = enemies.data(victim_char, victim)
        local region = ctx.region
        if region and region.no ~= nil then region.part = enemies.part(victim_char, victim, region.no) end
    elseif attacker and attacker.kind == "enemy" then
        foe = enemies.data(attacker_char, attacker)
    end
    local collect = victim.kind == "enemy" and debug_wanted()
    -- a live enemy only, as for a party hit: not a blow or a tick on a corpse
    if collect and hp0 > 0 then emit("met", victim_char, victim, t) end
    local hit = {
        t = t, attacker = attacker, victim = victim, skill = skill, element = element,
        final = final, hp0 = hp0, hp1 = hp1, before = ctx.before, after = ctx.after, types = ctx.types,
        region = ctx.region, guard = ctx.guard, status = status, foe = foe, own = own, mirror = mirror, knock = knock,
        frame = frame(),
    }
    if victim.kind == "enemy" and not mirror and points_wanted() then
        hit.point = point_of(di, victim_char)
        hit.weak_damage = Safe.field(di, "IsWeakDamage") == true
        hit.target_bonus = ctx.target_bonus
    end
    if collect then
        if not mirror then hit.target_bonus, hit.target_rate = ctx.target_bonus, ctx.target_rate end
        -- no attacker at the end, or a knock: the Flag was read for the mirror check
        if attacker == nil or knock then
            hit.damage_type = Safe.enum(Safe.field(di, "DamageType"))
            hit.flag = Safe.enum(flag) or number(flag)
        end
        if knock then hit.knock_gap = gap end
    end
    emit("hit", hit)
end

-- A damageProc without updateDamage: only the healing spot's touches are kept (Attrib credits heals by them).
local function touch(ctx)
    if not (sink and sink.touch) then return end
    local di = ctx.di or obj(ctx.slot)
    local attack = text(Safe.call(Safe.field(di, "<AttackUserData>k__BackingField"), "get_Name"))
    if attack == nil or not attack:find(HEAL_AREA, 1, true) then return end
    local healer = actors.of((attacker_at_start(ctx, di)))
    local target = actors.of(victim_of(ctx, di))
    if healer and target then emit("touch", frame(), healer, target.key, { attack = attack }, now()) end
end

-- damageProc(DamageInfo): args[2] this, args[3] the DamageInfo
local function proc_pre(args, st)
    local slot = args[3]
    local key = key_of(slot)
    if key == nil then return end
    if n_open >= MAX_OPEN then open, n_open = {}, 0 end
    local ctx = { key = key, slot = slot, prev = open[key] }
    if ctx.prev == nil then n_open = n_open + 1 end
    open[key] = ctx
    st.hit = ctx
    -- the attacker as the hit starts: a party member's or an ally's strike on an enemy (the lifesteal can come inside
    -- this call)
    local di = obj(slot)
    if di == nil then return end
    ctx.di = di
    ctx.attacker, ctx.shell = attacker_of(di)
    local a = actors.of(ctx.attacker)
    if a == nil or not FRIEND[a.kind] then return end
    local victim = actors.of(Safe.call(obj(args[2]), "get_CachedCharacter"))
    if victim and victim.kind == "enemy" then emit("strike", frame(), a.key) end
end

local function proc_post(_, st)
    local ctx = st.hit
    if ctx == nil then return end
    st.hit = nil
    if open[ctx.key] == ctx then
        open[ctx.key] = ctx.prev
        if ctx.prev == nil then n_open = n_open - 1 end
    end
    ctx.prev = nil
    if ctx.updated then finish_hit(ctx) else touch(ctx) end
end

-- calcDamageValueDefence(DamageInfo): args[3] the DamageInfo; the damage before/after the victim's defence and, on
-- the enemy calculator (`rate`) while sink.points() or sink.debug() says so, the DamageRate before/after: the step's
-- bonus for the enemy's state. The last step of a hit counts.
local function defence_pre(args, st, rate)
    local ctx = open[key_of(args[3]) or false]
    if ctx == nil then return end
    local di = obj(args[3])
    if di == nil then return end
    st.defence = { ctx = ctx, di = di, before = damage_of(di),
        rate = rate and (points_wanted() or debug_wanted()) and number(Safe.field(di, "DamageRate")) or nil }
end

local function enemy_defence_pre(args, st) defence_pre(args, st, true) end

local function defence_post(_, st)
    local d = st.defence
    if d == nil then return end
    st.defence = nil
    local types = {}
    local after = damage_of(d.di, types)
    local rate = d.rate and number(Safe.field(d.di, "DamageRate"))
    local ctx = d.ctx
    ctx.before, ctx.after, ctx.types = d.before, after, next(types) and types or nil
    ctx.target_bonus = rate and rate - d.rate or nil
    ctx.target_rate = rate and d.rate or nil
end

-- calcRegionDamageRate(DamageInfo): args[2] the victim's HitController, args[3] the DamageInfo; the damage of each type
-- before / after the hit part's factors, and the part's RegionStatusNo. The first step of a hit counts.
local function region_pre(args, st)
    local ctx = open[key_of(args[3]) or false]
    if ctx == nil then return end
    local di = obj(args[3])
    if di == nil then return end
    local before = {}
    damage_of(di, before)
    st.region = { ctx = ctx, di = di, before = before }
end

local function region_post(_, st)
    local r = st.region
    if r == nil then return end
    st.region = nil
    if r.ctx.region ~= nil then return end
    local after = {}
    damage_of(r.di, after)
    r.ctx.region = { before = r.before, after = after, no = Safe.enum(Safe.field(r.di, "RegionStatusNo")) }
end

-- updateDamage(DamageInfo, UInt32, Single damage, Boolean): args[2] the victim's HitController, args[3] the
-- DamageInfo, args[5] the damage; HP before and after the call
local function update_pre(args, st)
    local ctx = open[key_of(args[3]) or false]
    if ctx == nil then return end
    local hc = obj(args[2])
    st.update = { ctx = ctx, hc = hc, final = Hook.float(args[5]), hp0 = number(Safe.call(hc, "get_Hp")) }
end

local function update_post(_, st)
    local u = st.update
    if u == nil then return end
    st.update = nil
    local ctx = u.ctx
    local hp1 = number(Safe.call(u.hc, "get_Hp"))
    if ctx.updated then
        -- a second updateDamage of the same hit on the same victim: still one hit, its damage summed; one on another
        -- hit controller is not this hit's, the first stays
        local addr = Safe.address(u.hc)
        if addr ~= nil and addr == Safe.address(ctx.hc) then
            ctx.final = ctx.final and u.final and ctx.final + u.final
            ctx.hp1 = hp1
        end
    else
        ctx.updated = true
        ctx.final, ctx.hp0, ctx.hp1, ctx.hc = u.final, u.hp0, hp1, u.hc
    end
end

-- subGuardHp(Single, DamageInfo): args[3] the guard damage, args[4] the DamageInfo
local function guard_pre(args)
    local ctx = open[key_of(args[4]) or false]
    if ctx == nil then return end
    local guard = Hook.float(args[3])
    if guard and guard > 0 then ctx.guard = (ctx.guard or 0) + guard end
end

-- applyStatusDamage(DamageInfo, StatusConditionEnum, Single): a DoT status built up by a hit; Attrib's fallback
-- record of who applies what (seen in game: in practice only stun buildup, which is no DoT)
local function status_pre(args)
    local value = Hook.float(args[5])
    if value == nil or value <= 0 then return end
    local status = DOT_NAME[Hook.int32(args[4]) or false]
    if status == nil then return end
    local di = obj(args[3])
    if di == nil then return end
    local applier = actors.of((attacker_of(di)))
    local victim = actors.of(Safe.call(Safe.field(di, "<DamageHitController>k__BackingField"), "get_CachedCharacter"))
    if applier and victim then emit("status", now(), victim.key, status, applier) end
end

function Hits.install(s, a)
    sink, attrib = s, a
    local H = HOOKS
    return Hook.install_all({
        { H.damageProc[1], H.damageProc[2], pre = proc_pre, post = proc_post },
        { H.player_defence[1], H.player_defence[2], pre = defence_pre, post = defence_post },
        { H.enemy_defence[1], H.enemy_defence[2], pre = enemy_defence_pre, post = defence_post },
        { H.region[1], H.region[2], pre = region_pre, post = region_post },
        { H.updateDamage[1], H.updateDamage[2], pre = update_pre, post = update_post },
        { H.subGuardHp[1], H.subGuardHp[2], pre = guard_pre },
        { H.applyStatusDamage[1], H.applyStatusDamage[2], pre = status_pre },
    })
end

return Hits
