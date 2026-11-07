-- Heals of the party (as logged in game, in the chimera fight among others). Every polled rise of
-- party HP came with an app.HitController.recoverHp call, so that call is the heal: its amount is the HP really
-- gained (hp1 - hp0). The healer is the user of the item while ItemManager.useItem runs on that target (its
-- convertHealHp gives the requested amount), else the heal area that touched the target in the same frames, or,
-- for a heal of at most 50 HP, the one that touched it last if that was at most 6 s ago (the healing spot heals on
-- for about 4 s after its last touch; Attrib), else a party member who was in the state of one of HEAL_SKILLS at most
-- its window of frames before (the mage's Argent Tonic heals as her Job03_FullRecover state ends, as logged in game;
-- states sampled by heals.sample), else nobody («other»). A party HP rise with no heal call since the
-- last poll is such a skill's heal, else an «other» heal, unless it is a jump to full HP or a rise from 0 (restores
-- and revives: recoverHpAndMaxHpCompletely, Character.recoverAll and reviveFromFallDead are not hooked and are no
-- heals). Read-only: hook rules in game/hook.lua.
--
--   heals.install(sink, attrib) -> number of hooked methods (3), { "Type.method(...)" } of the missing ones
--     sink.heal(Heal) (shape: fight.lua); sink.now() / sink.frame() are the clock of hooked heals (default: the
--     time and frame of the last heals.poll); attrib: the Attrib that hits' touches go to
--   heals.poll(frame, t, now)  once per frame, after the game's update: the HP poll of the party members the game
--                         lists in that frame (Actors.present: never a character kept from an earlier frame; none
--                         without a player character); a member not listed in a frame is polled afresh after it. `now`:
--                         the frame's party listing (Actors.listed), read anew when not given
--   heals.sample(frame, now)  once per frame while a fight is open: the skill state of each party member the game
--                         lists now (one field read per member), to find who cast a HEAL_SKILLS skill; a skill heal is
--                         { kind = "skill", id }; `now` as for the poll
--   heals.reset()         forgets item scopes, polled HP and the skills seen cast (scene change)
--   heals.info()          { scopes, errors, last_error }
local Safe = require("DD2DamageMeter/game/safe")
local Hook = require("DD2DamageMeter/game/hook")
local actors = require("DD2DamageMeter/game/actors")
local names_game = require("DD2DamageMeter/game/names_game")

local Heals = {}

local HOOKS = {
    recoverHp = { "app.HitController", "recoverHp(System.Single, System.Boolean, System.Int32, System.Boolean)" },
    useItem = { "app.ItemManager", "useItem(System.Int32, app.Character, app.Character)" },
    convertHealHp = { "app.ItemManager",
        "convertHealHp(System.Single, app.Character, app.CharacterID, app.ItemIDEnum, System.Boolean)" },
}

local HEALED = { player = true, pawn = true, ally = true }  -- whose heals count
-- Skills that heal with no heal call of their own to tell who healed: app.HumanCustomSkillID name -> frames after the
-- caster's last frame in its state that a heal with no other source is still hers.
local HEAL_SKILLS = { Job03_FullRecover = 10 }  -- the mage's Argent Tonic: heals the party as her state ends
local MAX_SCOPES = 16    -- open item uses; more means useItem calls whose post-hook never came
local FULL_EPS = 0.5     -- HP this close to the maximum is full
local RISE_EPS = 0.01    -- smaller polled rises are float noise

local key_of, obj, number = Hook.key_of, Hook.obj, Hook.number

local sink, attrib = nil, nil
local scopes, n_scopes = {}, 0  -- target character address -> { key, frame, user = Actor|nil, item_id, amount, prev }
local explained = {}            -- party actor key -> true: a heal call on it since the last poll
local last_hp = {}              -- party member's character address -> its HP at the last poll (a new object of his,
                                -- is polled afresh: its first HP is no rise)
local polled = { frame = 0, t = 0 }
local casts = {}                -- party actor key -> { frame, actor, id }: his latest frame in a HEAL_SKILLS state

function Heals.reset()
    scopes, n_scopes = {}, 0
    explained, last_hp = {}, {}
    casts = {}
end

-- Who is in a HEAL_SKILLS state now: one field read per party member the game lists now (the Human kept per party
-- read, read only while the game lists him: Actors.present).
function Heals.sample(frame, now)
    for _, m in ipairs(actors.present(true, now)) do
        local state = number(Safe.field(m.human, "<CustomSkillState>k__BackingField"))
        if state and state ~= 0 then
            local id = names_game.enum_name("app.HumanCustomSkillID", state)
            local actor = m.actor
            if id and HEAL_SKILLS[id] then casts[actor.key] = { frame = frame, actor = actor, id = id } end
        end
    end
end

-- The party member who cast a HEAL_SKILLS skill whose window holds `frame` (the latest cast; on a tie the first in
-- party order) and the skill's id; nil when none.
local function caster_for(frame)
    local best = nil
    for _, actor in ipairs(actors.party()) do
        local c = casts[actor.key]
        local inside = c and frame >= c.frame and frame - c.frame <= HEAL_SKILLS[c.id]
        if inside and (best == nil or c.frame > best.frame) then best = c end
    end
    if best then return best.actor, best.id end
    return nil
end

function Heals.info()
    local h = Hook.info()
    return { scopes = n_scopes, errors = h.errors, last_error = h.last_error }
end

local function clock(name, default)
    local fn = sink and sink[name]
    if fn then
        local ok, v = pcall(fn)
        if ok and number(v) then return v end
    end
    return default
end

local function emit(heal)
    local fn = sink and sink.heal
    if fn == nil then return end
    local ok, err = pcall(fn, heal)
    if not ok then Hook.fail("heals sink.heal", err) end
end

local function healer_for(frame, target_key, t, hp)
    if attrib == nil then return nil end
    local ok, healer, ref = pcall(function() return attrib:healer_for(frame, target_key, t, hp) end)
    if ok then return healer, ref end
    Hook.fail("heals attrib.healer_for", healer)
    return nil
end

-- The item use running on that character now. The item's heal happens inside useItem, in its frame (chimera log:
-- useItem, useItemSub, convertHealHp and recoverHp in one frame); the next frame is allowed too, because the frame
-- counter is advanced in on_frame, which can run between two hooks of one useItem. An older scope is a useItem whose
-- post-hook never came: it is dropped, else every later heal of that character would pass for the item.
local function live_scope(key)
    local frame = clock("frame", polled.frame)
    local scope = scopes[key]
    while scope ~= nil and not (frame >= scope.frame and frame - scope.frame <= 1) do
        scope = scope.prev
        scopes[key] = scope
        if scope == nil then n_scopes = n_scopes - 1 end
    end
    return scope
end

-- useItem(Int32 item, Character user, Character target): args[3..5]; a null target is the user himself
local function use_pre(args, st)
    local id = Hook.int32(args[3])
    local key = key_of(args[5]) or key_of(args[4])
    if id == nil or key == nil then return end
    if n_scopes >= MAX_SCOPES then scopes, n_scopes = {}, 0 end
    local scope = { key = key, frame = clock("frame", polled.frame), user = actors.of(obj(args[4])), item_id = id,
                    prev = scopes[key] }
    if scope.prev == nil then n_scopes = n_scopes + 1 end
    scopes[key] = scope
    st.item = scope
end

local function use_post(_, st)
    local scope = st.item
    if scope == nil then return end
    st.item = nil
    if scopes[scope.key] == scope then
        scopes[scope.key] = scope.prev
        if scope.prev == nil then n_scopes = n_scopes - 1 end
    end
    scope.prev = nil
end

-- static convertHealHp(Single, Character, CharacterID, ItemIDEnum, Boolean) -> Int32: args[3] the character healed;
-- the result is the item's heal amount
local function convert_pre(args, st)
    st.convert = key_of(args[3])
end

local function convert_post(retval, st)
    local key = st.convert
    if key == nil then return end
    st.convert = nil
    local scope = live_scope(key)
    local amount = Hook.int32(retval)
    if scope and amount and amount > 0 then scope.amount = amount end
end

-- recoverHp(Single amount, Boolean, Int32, Boolean): args[2] the target's HitController, args[3] the amount
local function recover_pre(args, st)
    local hc = obj(args[2])
    local hp0 = number(Safe.call(hc, "get_Hp"))
    if hp0 == nil then return end
    st.recover = { hc = hc, hp0 = hp0, amount = Hook.float(args[3]) }
end

local function recover_post(_, st)
    local r = st.recover
    if r == nil then return end
    st.recover = nil
    local hp1 = number(Safe.call(r.hc, "get_Hp"))
    if hp1 == nil or hp1 <= r.hp0 then return end
    local character = Safe.call(r.hc, "get_CachedCharacter")
    local target = actors.of(character)
    if target == nil or not HEALED[target.kind] then return end
    explained[target.key] = true
    if r.hp0 <= 0 then return end  -- back from 0 HP: a revive, not a heal
    local effective = hp1 - r.hp0
    local t = clock("now", polled.t)
    local heal = { t = t, target = target, amount = r.amount or effective, effective = effective }
    local addr = Safe.address(character)
    local scope = addr and live_scope(addr)
    if scope then
        heal.healer = scope.user
        heal.amount = scope.amount or heal.amount
        heal.source = { kind = "item", item_id = scope.item_id }
    else
        local frame = clock("frame", polled.frame)
        local healer, ref = healer_for(frame, target.key, t, effective)
        if healer then
            heal.healer = healer
            heal.source = { kind = "skill", name = type(ref) == "table" and ref.attack or nil }
        else
            local caster, id = caster_for(frame)
            heal.healer = caster
            heal.source = caster and { kind = "skill", id = id } or { kind = "other" }
        end
    end
    emit(heal)
end

local function is_full(actor, hp)
    local max = number(actor.max_hp)
    return max ~= nil and hp >= max - FULL_EPS
end

function Heals.poll(frame, t, now)
    polled.frame, polled.t = frame, t
    local seen = {}
    for _, m in ipairs(actors.present(nil, now)) do
        local actor, addr = m.actor, m.addr
        local key = actor.key
        local hp = number(Safe.call(m.character, "get_Hp"))
        if hp then
            local prev = last_hp[addr]
            if prev and hp - prev > RISE_EPS and prev > 0 and not explained[key] and not is_full(actor, hp) then
                local d = hp - prev
                local caster, id = caster_for(frame)
                emit({ t = t, target = actor, healer = caster, amount = d, effective = d,
                       source = caster and { kind = "skill", id = id } or { kind = "other" } })
            end
            seen[addr] = hp
        end
    end
    last_hp = seen
    if next(explained) then explained = {} end
end

function Heals.install(s, a)
    sink, attrib = s, a
    local H = HOOKS
    return Hook.install_all({
        { H.recoverHp[1], H.recoverHp[2], pre = recover_pre, post = recover_post },
        { H.useItem[1], H.useItem[2], pre = use_pre, post = use_post },
        { H.convertHealHp[1], H.convertHealHp[2], pre = convert_pre, post = convert_post },
    })
end

return Heals
