-- What the game knows about an enemy, read from a live character once per kind, and the type of a hit part
-- (the fields as found in game). The kind is the character's CharaID (Actor.chara_id), never the game
-- object's name: two variants of one prefab have different defences and stay two records, a crowd of one kind is read
-- once. Read-only, every game access under Safe.
--
--   enemies.data(character, actor) -> EnemyData | nil
--     EnemyData = { chara_id: integer, weak: integer, resist: integer, defence: number | nil,
--                   magic_defence: number | nil, enabled: integer | nil }
--     weak / resist are CharacterWeakpointType flags (DamageCalculator:get_WeakPointSettings / get_ResistSettings),
--     enabled the StatusConditionFlag mask of the statuses that can work on the enemy (nil when unreadable). Plain
--     numbers only (the ledger copies them). Every later call of the kind gives the same table. A read counts when
--     weak and resist are integers; else it is tried again on a later hit, at most 3 times per CharaID. nil without a
--     CharaID (nothing is read) and while there is no record; with no character the record of the kind is given when
--     there is one, and no try is spent.
--   enemies.part(character, actor, region_no) -> "head" | "body" | "other" | nil
--     the type of the part with this RegionStatusNo in the table in use (RegionStatusCtrl:getActiveRegionParam, never
--     the prefab's RegionStatusCtrl.Data). The game's answer is remembered per (CharaID, region number), at most 4096
--     of them; a table that cannot be reached is asked again, at most 3 times per region.
--   enemies.reset()  forgets everything read (a new world)
local Safe = require("DD2DamageMeter/game/safe")

local Enemies = {}

local MAX_TRIES = 3     -- failed reads of one CharaID (or of one of its regions) before it is left alone
local MAX_PARTS = 4096  -- remembered (CharaID, region number) pairs

-- app.IntermediateRegionParam.RegionTypeEnum: Head 0, Body 1, Other 2
local PART = { [0] = "head", "body", "other" }

local records = {}             -- chara_id -> EnemyData
local tries = {}               -- chara_id -> failed reads
local parts, n_parts = {}, 0   -- chara_id -> region number -> "head" | "body" | "other", false (no type) or the
                               -- number of asks that did not reach the table

function Enemies.reset()
    records, tries = {}, {}
    parts, n_parts = {}, 0
end

local function finite(x)
    if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge then return nil end
    return x
end

local function chara_id_of(actor)
    local id = type(actor) == "table" and actor.chara_id or nil
    if math.type(id) ~= "integer" then return nil end
    return id
end

local function read(character, id)
    local calc = Safe.call(character, "get_DamageCalculator")
    local weak = Safe.enum(Safe.call(calc, "get_WeakPointSettings"))
    local resist = Safe.enum(Safe.call(calc, "get_ResistSettings"))
    if weak == nil or resist == nil then return nil end
    local status = Safe.call(character, "get_StatusConditionCtrl")
    return {
        chara_id = id, weak = weak, resist = resist,
        defence = finite(Safe.call(calc, "get_Defence")),
        magic_defence = finite(Safe.call(calc, "get_MagicDefence")),
        enabled = Safe.enum(Safe.field(status, "EnableStatusConditionFlag")),
    }
end

function Enemies.data(character, actor)
    local id = chara_id_of(actor)
    if id == nil then return nil end
    local found = records[id]
    if found ~= nil or character == nil then return found end
    local failed = tries[id] or 0
    if failed >= MAX_TRIES then return nil end
    found = Safe.try(read, character, id)
    if found then
        records[id] = found
    else
        tries[id] = failed + 1
    end
    return found
end

-- The type of the part: "head" / "body" / "other"; false when the game's table has no such part or no type for it; nil
-- when the table cannot be reached.
local function read_part(character, region_no)
    local control = Safe.call(Safe.call(character, "get_DamageCalculator"), "get_RegionStatusCtrl")
    if control == nil then return nil end
    local param = Safe.call(control, "getActiveRegionParam(System.Int32)", region_no)
    if param == nil then return false end
    local kind = Safe.enum(Safe.call(param, "get_RegionType"))
    if kind == nil then kind = Safe.enum(Safe.field(param, "_RegionType")) end
    return PART[kind] or false
end

local function remember(id, region_no, value, is_new)
    if is_new then
        if n_parts >= MAX_PARTS then parts, n_parts = {}, 0 end
        n_parts = n_parts + 1
    end
    local by_region = parts[id]
    if by_region == nil then
        by_region = {}
        parts[id] = by_region
    end
    by_region[region_no] = value
end

function Enemies.part(character, actor, region_no)
    local id = chara_id_of(actor)
    if id == nil or math.type(region_no) ~= "integer" then return nil end
    local by_region = parts[id]
    local known = by_region and by_region[region_no]
    if type(known) == "string" then return known end
    if known == false or character == nil then return nil end
    local found = Safe.try(read_part, character, region_no)
    if found == nil then
        local failed = (known or 0) + 1
        remember(id, region_no, failed < MAX_TRIES and failed or false, known == nil)
    else
        remember(id, region_no, found, known == nil)
    end
    return found or nil
end

return Enemies
