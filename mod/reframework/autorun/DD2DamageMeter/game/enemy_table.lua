-- An enemy kind's part table in use, for the enemy plate: the multiplier per damage type of its main body and of its
-- head and weak-spot parts, in the state the enemy is in now. The
-- kind is the CharaID (Actor.chara_id), never the game object's name. Read-only, every game access under Safe.
--
--   EnemyTable.read(character, chara_id, t) -> Table | nil
--     Table = { chara_id: integer, state: string | nil, body: { [jt] = number },
--               parts: { { kind: "weak" | "head", mult: { [jt] = number } } } }
--     t: seconds. The game is read when the kind's last read, good or not, is READ_EVERY old (or later than t: a clock
--     that went back); in between, and when the read fails, the last good Table of the kind is given, nil when there
--     is none. Without a CharaID, nil and nothing is read; without a character or a time, the last good Table and
--     nothing is read.
--     The path: character:get_DamageCalculator():get_RegionStatusCtrl(); state its get_PrioStatusId() ("Normal",
--     "Angry", "Flight", "Down", ...). The region numbers are those of the state in use only: the state of
--     get_RegionStatusDataProp():get_IntermediateRegionStatusParams() whose get_StatusId() is the PrioStatusId, its
--     get_IntermediateRegionParams (the Wight's Normal lists r0-r3, its Down only r2 and r3; another state's numbers
--     could bring that state's values in, if getActiveRegionParam falls back to it). Each is asked of
--     getActiveRegionParam. No state, or none of that name, is a failed read. Never the prefab's template
--     RegionStatusCtrl.Data (a trap: it is not the table in use).
--     jt: Slash, Blow, Shoot from _DamageAdjustRatePys[0..2]; Magic, Fire, Ice, Thunder, Light from
--     _DamageAdjustRateMgc[0..4]. Read through the part's getters, which give plain numbers, else from the fields
--     (arrays of boxed Singles, read by their ToString). A type without a finite number is left out.
--     body: the part of RegionType Body with the smallest RegionNo, whatever its values. With none, the Other part
--     without the WeakRegion flag with the smallest RegionNo, else the Other part with it with the smallest (the
--     Ghoul's main parts are Other); an Other part that takes no damage, every number it gives 0, is passed over
--     unless every Other part is so (the Fallen dragon's parts 0, 1 and 7-11). Empty when there is none of these.
--     parts: one entry per kind, "weak" then "head", each the largest value per type of its parts. "weak" is a part
--     with the WeakRegion flag (_Attr bit 256) whatever its type, "head" a Head part without it; a Body or Other part
--     with the flag is also a body candidate, Other parts without it are left out.
--     A read counts when at least one part gives a number. Plain numbers and strings only.
--   EnemyTable.cached(chara_id) -> Table | nil   the last good Table of the kind, reading nothing
--   EnemyTable.peek(character, chara_id) -> Table | nil
--     the Table read now from the character, as above, for the debug collector (game/collector.lua): kept nowhere,
--     neither the kind's last Table nor its read time change, so that what the plate shows does not hang on it; nil
--     when the read fails, and nil with nothing read without a character or a CharaID
--   EnemyTable.part(param, no) -> { no, type, attr, weak, mult } | nil
--     one app.IntermediateRegionParam as the read above reads it, for the debug collector (game/collector.lua): its
--     RegionNo (else `no`), RegionType and _Attr as integers, weak its WeakRegion bit, mult as above (empty when it
--     gives no number); nil without a part. Plain values only.
--   EnemyTable.reset()   forgets everything (a new world)
local Safe = require("DD2DamageMeter/game/safe")

local EnemyTable = {}

local READ_EVERY = 1     -- s between two reads of one kind
local MAX_STATES = 16    -- states looked through (the Griffin has 5)
local MAX_REGIONS = 64   -- region numbers asked (the Griffin has 16 parts, the Chimera about 30)

local ACTIVE = "getActiveRegionParam(System.Int32)"
local PYS = "getDamageAdjustRatePys(app.AttackUserData.AttrPhysicsEnum)"
local MGC = "getDamageAdjustRateMgc(app.AttackUserData.ElementType)"
local PHYS = { [0] = "Slash", "Blow", "Shoot" }                         -- AttrPhysicsEnum 0..2
local MAGIC = { [0] = "Magic", "Fire", "Ice", "Thunder", "Light" }      -- ElementType 0..4; Dark has no column
local HEAD, BODY, OTHER = 0, 1, 2   -- app.IntermediateRegionParam.RegionTypeEnum
local WEAK_REGION = 256   -- IntermediateRegionParam.AttributeFlags.WeakRegion_SE_Effect_Ability
local KINDS = { "weak", "head" }

local tables = {}    -- chara_id -> the last good Table
local read_at = {}   -- chara_id -> t of the last read, good or not

function EnemyTable.reset()
    tables, read_at = {}, {}
end

local function finite(x)
    if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge then return nil end
    return x
end

local function whole(x)
    if type(x) ~= "number" then return nil end
    return math.tointeger(x)
end

local function region_no(param)
    local no = whole(Safe.call(param, "get_RegionNo"))
    if no == nil then no = whole(Safe.field(param, "_RegionNo")) end
    return no
end

-- The region numbers the state named `state` lists in the table in use, each once; nil when no state has that name.
local function region_numbers(rsc, state)
    local data = Safe.call(rsc, "get_RegionStatusDataProp")
    for _, s in ipairs(Safe.list(Safe.call(data, "get_IntermediateRegionStatusParams"), MAX_STATES)) do
        if s and Safe.call(s, "get_StatusId") == state then
            local out, seen = {}, {}
            for _, param in ipairs(Safe.list(Safe.call(s, "get_IntermediateRegionParams"), MAX_REGIONS)) do
                local no = param and region_no(param) or nil
                if no ~= nil and not seen[no] then
                    seen[no] = true
                    out[#out + 1] = no
                end
            end
            return out
        end
    end
    return nil
end

-- A Single of a field array: boxed in the game, its ToString the number.
local function single(v)
    if type(v) == "table" or type(v) == "userdata" then v = tonumber(Safe.call(v, "ToString")) end
    return finite(v)
end

-- The part's rates into `mult`, named by `names` (index 0..n): the getter, else the field array.
local function rates(param, getter, field, names, mult)
    local items = nil
    for i = 0, #names do
        local v = finite(Safe.call(param, getter, i))
        if v == nil then
            items = items or Safe.list(Safe.field(param, field), #names + 1)
            v = single(items[i + 1])
        end
        if v ~= nil then mult[names[i]] = v end
    end
end

-- The part's multipliers by type.
local function mults(param)
    local mult = {}
    rates(param, PYS, "_DamageAdjustRatePys", PHYS, mult)
    rates(param, MGC, "_DamageAdjustRateMgc", MAGIC, mult)
    return mult
end

-- The part with these multipliers: its type, flags and number read now.
local function described(param, no, mult)
    local kind = Safe.enum(Safe.call(param, "get_RegionType"))
    if kind == nil then kind = Safe.enum(Safe.field(param, "_RegionType")) end
    local attr = Safe.enum(Safe.field(param, "_Attr"))
    return { no = region_no(param) or no, type = kind, attr = attr, weak = attr ~= nil and (attr & WEAK_REGION) ~= 0,
        mult = mult }
end

function EnemyTable.part(param, no)
    if param == nil then return nil end
    return described(param, no, mults(param))
end

-- The part numbered `no` in the state in use: { no, type, attr, weak, mult }; nil when there is none or it gives no
-- number (then nothing more of it is read).
local function read_part(rsc, no)
    local param = Safe.call(rsc, ACTIVE, no)
    if param == nil then return nil end
    local mult = mults(param)
    if next(mult) == nil then return nil end
    return described(param, no, mult)
end

-- Whether every number of `mult` is 0: a part that takes no damage.
local function no_damage(mult)
    for _, v in pairs(mult) do
        if v ~= 0 then return false end
    end
    return true
end

-- How `p` stands as the body, the smaller first: 1 a Body part, 2 an Other part without the weak flag, 3 a weak Other
-- part, 4 and 5 such Other parts that take no damage; nil when it is none.
local function body_rank(p)
    if p.type == BODY then return 1 end
    if p.type ~= OTHER then return nil end
    local r = p.weak and 3 or 2
    if no_damage(p.mult) then r = r + 2 end
    return r
end

local function merge(by_kind, kind, mult)
    local into = by_kind[kind]
    if into == nil then
        into = {}
        by_kind[kind] = into
    end
    for jt, v in pairs(mult) do
        if into[jt] == nil or v > into[jt] then into[jt] = v end
    end
end

local function read(character, id)
    local rsc = Safe.call(Safe.call(character, "get_DamageCalculator"), "get_RegionStatusCtrl")
    if rsc == nil then return nil end
    local state = Safe.call(rsc, "get_PrioStatusId")
    if type(state) ~= "string" or state == "" then return nil end
    local numbers = region_numbers(rsc, state)
    if numbers == nil then return nil end
    local body, rank, by_kind, found = nil, nil, {}, false
    for _, no in ipairs(numbers) do
        local p = read_part(rsc, no)
        if p ~= nil then
            found = true
            local r = body_rank(p)
            if r ~= nil and (body == nil or r < rank or (r == rank and p.no < body.no)) then body, rank = p, r end
            if p.weak then
                merge(by_kind, "weak", p.mult)
            elseif p.type == HEAD then
                merge(by_kind, "head", p.mult)
            end
        end
    end
    if not found then return nil end
    local parts = {}
    for _, kind in ipairs(KINDS) do
        if by_kind[kind] then parts[#parts + 1] = { kind = kind, mult = by_kind[kind] } end
    end
    return { chara_id = id, state = state, body = body and body.mult or {}, parts = parts }
end

function EnemyTable.read(character, chara_id, t)
    if math.type(chara_id) ~= "integer" then return nil end
    local kept = tables[chara_id]
    if character == nil or finite(t) == nil then return kept end
    local last = read_at[chara_id]
    if last ~= nil and t >= last and t - last < READ_EVERY then return kept end
    read_at[chara_id] = t
    local found = Safe.try(read, character, chara_id)
    if found == nil then return kept end
    tables[chara_id] = found
    return found
end

function EnemyTable.peek(character, chara_id)
    if character == nil or math.type(chara_id) ~= "integer" then return nil end
    return Safe.try(read, character, chara_id)
end

function EnemyTable.cached(chara_id)
    if math.type(chara_id) ~= "integer" then return nil end
    return tables[chara_id]
end

return EnemyTable
