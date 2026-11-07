-- Characters of the game as Actors (shape: fight.lua Interfaces): the party from the game's rosters, everybody else
-- by hostility, except critters (a full HP below CRITTER_HP): neutral whatever they are. Actors are cached by address
-- so one character is one table for the whole session; neither the cache nor the roster keeps a character (an
-- object kept from one frame to a later one may be one a scene change destroyed): the party's HP poll and skill
-- states read the characters the game lists in that very frame (Actors.present). The one game object kept is a
-- party member's app.Human (per party read, for one field read, and only while the game lists him).
-- The game can make a new character object for a party member mid-fight (the Gagana fight: each pawn at a second
-- address, the same CharaID). A roster member at an address that is no member's yet takes the cached actor of a party
-- member, now or before, of the same CharaID (unique in the party; an enemy kind shares one, so only the roster is
-- matched): one actor, one key, one row. His old object keeps resolving to that actor while it is a roster member's: it
-- is not reclassified as a member who left, and a prune keeps the old address. A character outside the roster with a
-- member's CharaID has the party read again first (it may be the new object, met before the next party read).
local Safe = require("DD2DamageMeter/game/safe")
local names_game = require("DD2DamageMeter/game/names_game")

local Actors = {}

local MAX_CACHED = 1000   -- past this many cached characters the ones outside the party are dropped
local MAX_PAWNS = 3
-- A character whose full HP is known and below this is a critter, never an enemy or an ally: the game calls a
-- chicken (1 HP) hostile, a deer (250 HP) is still a fight of its own.
local CRITTER_HP = 100

local cache = {}          -- address -> { actor, go }; `go`: the game object name seen when it was made
local cached = 0
local roster = {}         -- address -> { kind, order, index, addr, human } of the party as last refreshed; human:
                          -- the app.Human Actors.present(true) read at that place (false: none), nil before
local roster_list = {}    -- the same entries in party order
local party_actors = {}   -- Actors of the roster, same order
local members = {}        -- Actor -> true: the cached actors of party members, now or before
local homes = setmetatable({}, { __mode = "k" })  -- a party member's Actor -> his address at the last party read
local joined = nil        -- Actors.on_join's watcher, nil when none
local refreshed = false
local pawns_read = false  -- the last refresh could read the pawn list (else the roster says nothing about pawns)

-- Forgets every cached actor and the roster (a new area, a loaded save).
function Actors.reset()
    cache, cached = {}, 0
    roster, roster_list, party_actors = {}, {}, {}
    members = {}
    homes = setmetatable({}, { __mode = "k" })
    refreshed, pawns_read = false, false
end

-- The joins of a member's new object to his actor as they happen, for the debug collector (game/collector.lua):
-- fn(actor, old_addr, new_addr) at each, the member's actor, the address the party read last found him at (nil when
-- none) and the new one; a raising fn is ignored. Kept through Actors.reset; nil: none.
function Actors.on_join(fn)
    joined = fn
end

-- ch220003_00_15 -> ch220003_00: the trailing spawn index is not part of the kind.
local function base_of(go)
    if not go then return "?" end
    local base = go:gsub("_%d+$", "")
    if base == "" then return go end
    return base
end

local function max_hp_of(character)
    local hp = Safe.call(character, "get_OriginalMaxHp")
    if type(hp) == "number" then return hp end
    return nil
end

local function hp_of(character)
    local hp = Safe.call(character, "get_Hp")
    if type(hp) == "number" then return hp end
    return nil
end

local function finite(x)
    return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

-- app.CharacterID of the character (unique for the party, shared by an enemy kind), nil when unreadable.
local function chara_id_of(character)
    local id = Safe.call(character, "get_CharaID")
    if type(id) ~= "number" then return nil end
    return math.tointeger(id) or id
end

-- The party member's vocation (app.Character.JobEnum: 1 Fighter .. 10 Warfarer), nil when unreadable or none.
local function job_of(character)
    local job = Safe.field(Safe.call(Safe.call(character, "get_Human"), "get_JobContext"), "CurrentJob")
    job = type(job) == "number" and math.tointeger(job) or nil
    if job == nil or job < 1 then return nil end
    return job
end

-- Hostile when the character says so about the player or the player's battle
-- relationship to it is Hostile (1). nil when the game could not tell.
local function hostile_to_player(character)
    local player = Safe.call(Safe.singleton("app.CharacterManager"), "get_ManualPlayer")
    if player == nil then return nil end
    local hostile = Safe.call(character, "isHostile(app.Character)", player)
    if hostile == true then return true end
    local relation = Safe.call(player, "getBattleRelationshipTo(app.Character)", character)
    if relation == 1 then return true end
    if hostile == false or relation ~= nil then return false end
    return nil
end

-- A full HP of 0 is none read yet, not a critter's.
local function critter(actor)
    local hp = actor.max_hp
    return type(hp) == "number" and hp > 0 and hp < CRITTER_HP
end

local function remember(actor, real_name)
    if real_name then names_game.remember_enemy(actor.base_id, actor.name) end
end

-- Party members who left go with everybody else outside the roster; a roster member's old addresses stay (a
-- late event of his old object is still his, never a second actor under his key).
local function prune()
    local current = {}
    for _, actor in ipairs(party_actors) do current[actor] = true end
    local kept, n = {}, 0
    for addr, entry in pairs(cache) do
        if roster[addr] or current[entry.actor] then
            kept[addr] = entry
            n = n + 1
        end
    end
    cache, cached, members = kept, n, current
end

local function is_party(kind)
    return kind == "player" or kind == "pawn"
end

-- `id`: the CharaID when the caller has read it already.
local function build(character, addr, go, kind, order, id)
    local name, real = names_game.character_name(character)
    local base_id = base_of(go)
    local actor = {
        key = "a" .. addr, name = name or base_id, kind = kind, base_id = base_id,
        max_hp = max_hp_of(character), order = order,
        job = is_party(kind) and job_of(character) or nil,
        chara_id = id or chara_id_of(character),
    }
    if kind == "enemy" and critter(actor) then actor.kind = "other" end
    if actor.kind == "enemy" then remember(actor, real) end
    if is_party(kind) then members[actor], homes[actor] = true, addr end
    if not cache[addr] then cached = cached + 1 end
    cache[addr] = { actor = actor, go = go }
    return actor
end

-- The cached actor of a party member, now or before, whose CharaID this is; nil when none (or no id).
local function member_by_id(id)
    if id == nil then return nil end
    for actor in pairs(members) do
        if actor.chara_id == id then return actor end
    end
    return nil
end

-- This address is the party member's of this CharaID from now on (a new character object of his), told to
-- Actors.on_join's watcher; the new entry, nil when no cached member has the id.
local function join(addr, go, id)
    local actor = member_by_id(id)
    if actor == nil then return nil end
    if not cache[addr] then cached = cached + 1 end
    local entry = { actor = actor, go = go }
    cache[addr] = entry
    if joined then pcall(joined, actor, homes[actor], addr) end
    return entry
end

-- A roster member's actor now, whatever its address.
local function in_party(actor)
    for _, member in ipairs(party_actors) do
        if member == actor then return true end
    end
    return false
end

-- The cached entry of this address, unless the address now belongs to another character.
local function entry_for(addr, go)
    local entry = cache[addr]
    if entry and (go == nil or entry.go == nil or entry.go == go) then
        entry.go = entry.go or go
        return entry
    end
    return nil
end

local function become_enemy(actor, character)
    actor.kind = "enemy"
    local name, real = names_game.character_name(character)
    if real then actor.name = name end
    remember(actor, real)
end

-- The actor is at a place of the roster before `index` (a member's two objects listed at once).
local function listed_before(actor, index)
    for i = 1, index - 1 do
        if party_actors[i] == actor then return true end
    end
    return false
end

-- Everything about a roster member is re-read: its role, the name the HUD shows now (a support pawn flips between
-- _Name and _Nickname), its maximum HP, its vocation. A failed name or vocation read keeps the one already known.
-- An address that is no party member's yet (none cached, or one of somebody else's: met before the party had it) is
-- the member's of its CharaID when he has an actor, else as before. `index`: the place in the roster; a member
-- listed before it keeps the order of his first place, the one party() and address() answer for.
local function sync_member(character, addr, go, kind, order, index)
    local entry, id = entry_for(addr, go), nil
    if not (entry and members[entry.actor]) then
        id = chara_id_of(character)
        entry = join(addr, go, id) or entry
    end
    if not entry then return build(character, addr, go, kind, order, id) end
    local actor = entry.actor
    members[actor], homes[actor] = true, addr
    actor.kind = kind
    if not listed_before(actor, index) then actor.order = order end
    local name, real = names_game.character_name(character)
    if real then actor.name = name end
    actor.max_hp = max_hp_of(character) or actor.max_hp
    actor.job = job_of(character) or actor.job
    actor.chara_id = id or chara_id_of(character) or actor.chara_id
    return actor
end

-- Reads the party: the player (order 0) and up to three pawns in the pawn manager's order (1..3). Cached actors of
-- characters that left the party stay as they were. Cheap enough for a fight start and for about once a second.
-- Without a player character the world is going: the roster is empty and the pawn list is not read (nor a pawn
-- asked), as Actors.present gives nobody then.
function Actors.refresh()
    refreshed = true
    roster, roster_list, party_actors = {}, {}, {}
    local function add(character, kind, order)
        if not character then return end
        local addr = Safe.address(character)
        if addr == nil or roster[addr] then return end
        local entry = { kind = kind, order = order, index = #roster_list + 1, addr = addr }
        roster[addr] = entry
        roster_list[entry.index] = entry
        party_actors[entry.index] = sync_member(character, addr, Safe.go_name(character), kind, order, entry.index)
    end
    local player = Safe.call(Safe.singleton("app.CharacterManager"), "get_ManualPlayer")
    if player == nil then
        pawns_read = false
        return
    end
    add(player, "player", 0)
    local pawns = Safe.call(Safe.singleton("app.PawnManager"), "get_PawnCharacterList")
    pawns_read = pawns ~= nil
    for i, pawn in ipairs(Safe.list(pawns, MAX_PAWNS)) do
        add(pawn, "pawn", i)
    end
end

local function ensure_roster()
    if not refreshed then Actors.refresh() end
end

-- The Actor of a game character, nil when it cannot be identified. Party by the roster, then by hostility:
-- "enemy" when hostile and no critter, else "other" (an NPC, a critter or an object) until mark_fighting says it takes
-- part in the fight.
function Actors.of(character)
    if character == nil then return nil end
    local addr = Safe.address(character)
    if addr == nil then return nil end
    ensure_roster()
    local go = Safe.go_name(character)
    local entry = entry_for(addr, go)
    if entry then
        local actor = entry.actor
        if actor.kind == "pawn" and pawns_read and not roster[addr] and not in_party(actor) then
            -- a pawn that left the party is classified like anybody else (finished fights keep their copy); not
            -- one whose old object this is
            actor.order, actor.job = nil, nil
            if not critter(actor) and hostile_to_player(character) == true then
                become_enemy(actor, character)
            else
                actor.kind = "other"
            end
        elseif (actor.kind == "other" or actor.kind == "ally") and not critter(actor)
            and hostile_to_player(character) == true then
            become_enemy(actor, character)
        end
        return actor
    end
    local member = roster[addr]
    if member then
        local actor = sync_member(character, addr, go, member.kind, member.order, member.index)
        party_actors[member.index] = actor
        return actor
    end
    -- a party member's CharaID outside the roster may be his new object, made since the last party read: the
    -- party is read again (once: the character is cached after this), and the roster decides
    local id = chara_id_of(character)
    if member_by_id(id) then
        Actors.refresh()
        entry = roster[addr] and entry_for(addr, go)
        if entry then return entry.actor end
    end
    -- only here: a refresh in progress must not drop party actors it has yet to look at
    if cached >= MAX_CACHED then prune() end
    return build(character, addr, go, hostile_to_player(character) == true and "enemy" or "other", nil, id)
end

-- A character outside the party that is not hostile counts as an ally only after it has hit an enemy or been
-- hit by one; the hit adapter calls this. Enemies and party members keep their kind, a critter stays neutral.
function Actors.mark_fighting(actor)
    if type(actor) == "table" and actor.kind == "other" and not critter(actor) then actor.kind = "ally" end
end

-- The party member or ally whose app.CharacterID this is (a status's causer), nil for anybody else: an enemy
-- kind shares one id among all its instances.
function Actors.by_chara_id(id)
    if type(id) ~= "number" then return nil end
    id = math.tointeger(id) or id
    ensure_roster()
    for i, member in ipairs(roster_list) do
        local entry = cache[member.addr]
        if entry and entry.actor.chara_id == id and party_actors[i] then return party_actors[i] end
    end
    for _, entry in pairs(cache) do
        if entry.actor.chara_id == id and entry.actor.kind == "ally" then return entry.actor end
    end
    return nil
end

-- The party as Actors, in order: the player, then the pawns; an actor once, at his first place (a member's old and new
-- objects listed at once).
function Actors.party()
    ensure_roster()
    local list = {}
    for _, actor in ipairs(party_actors) do
        local listed = false
        for _, a in ipairs(list) do listed = listed or a == actor end
        if not listed then list[#list + 1] = actor end
    end
    return list
end

-- The party's characters the game lists now, by address: the player character and the pawns, read anew; empty
-- without a player character (the pawn list not read then).
local function listed_now()
    local now = {}
    local player = Safe.call(Safe.singleton("app.CharacterManager"), "get_ManualPlayer")
    local addr = Safe.address(player)
    if addr == nil then return now end
    now[addr] = player
    local pawns = Safe.call(Safe.singleton("app.PawnManager"), "get_PawnCharacterList")
    for _, pawn in ipairs(Safe.list(pawns, MAX_PAWNS)) do
        if pawn then
            local a = Safe.address(pawn)
            if a ~= nil then now[a] = pawn end
        end
    end
    return now
end

-- The party listing of one read, { [address] = character }: the player character
-- (app.CharacterManager:get_ManualPlayer()) and the pawns (app.PawnManager:get_PawnCharacterList(), at most three, a
-- null entry left out), read anew; empty without a player character, the pawn list then not read. For the calls of
-- the frame it was read in only (never to be kept): the mod reads it once a frame and hands it to Actors.present.
function Actors.listed()
    return listed_now()
end

-- The roster's members the game lists now, each with the character it lists. `now` is the party listing of this
-- frame (Actors.listed); without it the listing is read anew. A member is given at his first roster place whose
-- address the listing has, each actor once, in party order: { actor, character, addr }, character being the one the
-- game lists at addr, for the caller's calls in this frame only (never to be kept). With `with_human`, also human:
-- that place's app.Human, get_Human of the character listed, read once per party read and kept with the place (nil
-- when it gives none). Empty for an empty listing (no player character): the world is going (a title screen, a load),
-- and nobody is given, the pawns the game may still list included.
function Actors.present(with_human, now)
    local list = {}
    if now == nil then now = listed_now() end
    if next(now) == nil then return list end
    ensure_roster()
    local given = {}
    for i, entry in ipairs(roster_list) do
        local actor, character = party_actors[i], now[entry.addr]
        if actor ~= nil and character ~= nil and not given[actor] then
            given[actor] = true
            local m = { actor = actor, character = character, addr = entry.addr }
            if with_human then
                if entry.human == nil then entry.human = Safe.call(character, "get_Human") or false end
                m.human = entry.human or nil
            end
            list[#list + 1] = m
        end
    end
    return list
end

-- The address of a party member's character as the last party read found it (another one once the game made him a
-- new object: his actor stays), nil for anybody else.
function Actors.address(actor)
    if type(actor) ~= "table" then return nil end
    for i, member in ipairs(party_actors) do
        if member == actor then return roster_list[i].addr end
    end
    return nil
end

-- Current and full HP of any character (an enemy under its HP bar), read as the meter reads them: get_Hp, and
-- get_OriginalMaxHp raised to the current HP when that is more (as a fight's record takes it). nil when either is
-- not a finite number or the full HP is not above 0. Makes no actor and keeps nothing.
function Actors.health(character)
    if character == nil then return nil end
    local hp, full = hp_of(character), max_hp_of(character)
    if not (finite(hp) and finite(full)) or full <= 0 then return nil end
    return hp, math.max(full, hp)
end

return Actors
