-- The hidden-stats evidence: the player's numbers
-- as the status screen shows them and what he has equipped, read from the game's status calculator and equipment data
-- in any frame, not from the screen (checked in the game that they are the screen's numbers: Защита
-- «1645 (380)» = 380 + 159 + 1106, max HP 3100, carry weight 62.70). The debug collector compares them
-- (Collector.stat_check). Read-only: the calc* methods compute and return a value and set nothing; every game access
-- under Safe; never raises.
--
--   StatCheck.snapshot() -> Snapshot | nil, why
--     Snapshot = { numbers = { [name] = n }, equipped = { job, augments = { name... }, rings = { id... },
--                  items = { id... } } }
--     numbers, from the player's app.PlayerStatusCalculator (HiddenScreens.calculator(HiddenScreens.player_id())),
--       each left out when it cannot be read or is not a finite number; no total is made of them:
--       basic.<Name> / total.<Name>: every numeric instance field, 0 included, of the two status
--         structs, the key's prefix telling which, so that the two never collide (both have BasicDefence...):
--         basic. of calcBasicAttackDefence() (the bases, the status screen's numbers in brackets, and what is added
--         to them: Basic*, Additional*, the knockdown ones Blow, BlowResistance...); total. of
--         calcAttackDefenceWithEquipmentAndBuff() (the same with the equipment's parts and the buffs: Armor*,
--         BlowFactor, ArmorBlownDefenceFactor...; in the game Защита «1645 (380)» = total.BasicDefence 380 +
--         total.AdditionalDefence 159 + total.ArmorDefence 1106). The fields are read through the struct's own type
--         definition and its parent types' (a field a patch adds is recorded too); <Name>k__BackingField is Name, a
--         leading "_" is dropped. When a struct's type gives no field, the fields known from the game (KNOWN) are read
--         by name;
--       hp_max / hp_base: calcMaxHPWithEquipmentAndBuff() / calcBasicMaxHP(); sp_max / sp_base: the same of
--         MaxStamina; weight_max / weight_base: calcMaxWeightWithBuff() / calcBasicMaxWeight();
--       eq.<Name>: getEquipData().Data._EqParam's (app.EquipParam: the equipment's sums, the status screen's resist
--         lists) non-zero numeric instance fields, read the same way (eq.PhysicalDefence, eq.FireDefence,
--         eq.PoisonResist, eq.SlashDefenceRate...).
--     equipped:
--       job: the player's current vocation (HiddenScreens.job());
--       augments: the app.HumanAbilityID names ("Job05_00"; an id without a name, its number as text) of his Human's
--         <AbilityContext>k__BackingField getAbility(job, slot) for slots No0..No6, an empty slot (0) left out,
--         sorted: HiddenScreens.augments, which the hidden-stats panel's total line reads too (it takes them only
--         whole: an id without a name is unknown there, its number here);
--       rings / items: of getEquipData().Data.Equips (app.ItemDefine.StorageData[], a game array: read by
--         get_elements, its get_Item gives nil), each get_ItemId() above 0 (HiddenScreens.equips, read whole): the
--         rings (HiddenStatsGame.ring(id, job) gives one) and the rest (weapons, armour), each sorted.
--     nil when the player's CharaID, his calculator, either status struct, the Equips, his vocation or his
--     AbilityContext cannot be read, and when one part is read and another not: an augment slot that gives no
--     number while another does, an Equips entry that cannot be had or gives no id, an Equips array longer than
--     HiddenScreens' MAX_EQUIPS or without a length. What was not read is not taken as empty: the next snapshot
--     would show it as put on, a record of a change that never was; the collector keeps its last snapshot. nil,
--     "augments" when none of the 7 augment slots can be read (getAbility gives nothing for each: the augments are
--     unknown, not empty, and an augment change could never be told).
-- A type's field names are kept for the session once read (by its full name).
local Safe = require("DD2DamageMeter/game/safe")
local Hook = require("DD2DamageMeter/game/hook")
local HiddenScreens = require("DD2DamageMeter/game/hidden_screens")
local HiddenStatsGame = require("DD2DamageMeter/game/hidden_stats")

local StatCheck = {}

local ABILITY_CONTEXT = "<AbilityContext>k__BackingField"
local MAX_FIELDS = 256   -- fields of one type looked at
local MAX_PARENTS = 8    -- parent types looked through

-- The status structs' fields seen in the game (2026-11-06), read by name when a struct's type gives none.
local KNOWN = {}
for _, part in ipairs({ "Basic", "Additional", "Armor" }) do
    for _, stat in ipairs({ "Attack", "Defence", "MagicAttack", "MagicDefence" }) do
        KNOWN[#KNOWN + 1] = "<" .. part .. stat .. ">k__BackingField"
    end
end
for _, name in ipairs({ "Blow", "BlowResistance", "BlowFactor", "BlowResistanceFactor", "ArmorBlownDefenceFactor" }) do
    KNOWN[#KNOWN + 1] = "<" .. name .. ">k__BackingField"
end

-- The six maxima: name -> the calculator's method.
local MAXIMA = {
    hp_max = "calcMaxHPWithEquipmentAndBuff", hp_base = "calcBasicMaxHP",
    sp_max = "calcMaxStaminaWithEquipmentAndBuff", sp_base = "calcBasicMaxStamina",
    weight_max = "calcMaxWeightWithBuff", weight_base = "calcBasicMaxWeight",
}

local field_names = {}  -- a type's full name -> its instance field names and its parents', once read

local function finite(v)
    if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
    return v
end

local function o_type(obj) return obj:get_type_definition() end
local function t_name(td) return td:get_full_name() end
local function t_fields(td) return td:get_fields() end
local function t_parent(td) return td:get_parent_type() end
local function f_name(f) return f:get_name() end
local function f_static(f) return f:is_static() end

-- numbers ------------------------------------------------------------------------------------------------------------

-- The instance field names of the object's type and of its parent types; nil when none can be read.
local function names_of(obj)
    local td = Safe.try(o_type, obj)
    local key = td and Safe.try(t_name, td)
    if key and field_names[key] then return field_names[key] end
    local names = {}
    for _ = 1, MAX_PARENTS do
        if td == nil then break end
        for _, f in ipairs(Safe.items(Safe.try(t_fields, td), MAX_FIELDS)) do
            local name = f and Safe.try(f_name, f)
            if type(name) == "string" and Safe.try(f_static, f) == false then names[#names + 1] = name end
        end
        td = Safe.try(t_parent, td)
    end
    if #names == 0 then return nil end
    if type(key) == "string" then field_names[key] = names end
    return names
end

-- "<Blow>k__BackingField" -> "Blow", "_FireDefence" -> "FireDefence".
local function short(name)
    return name:match("^<(.+)>k__BackingField$") or (name:gsub("^_", ""))
end

-- The object's finite numeric fields into `numbers` as prefix .. short name (`known` read by name when its type gives
-- no field; zero left out when `nonzero`).
local function put_fields(obj, prefix, numbers, known, nonzero)
    if obj == nil then return end
    for _, name in ipairs(names_of(obj) or known or {}) do
        local v = finite(Safe.field(obj, name))
        if v and not (nonzero and v == 0) then numbers[prefix .. short(name)] = v end
    end
end

-- equipment ----------------------------------------------------------------------------------------------------------

-- The rings and the other items of the Equips array; nil when it is not read whole.
local function items_of(equips, job)
    local ids, whole = HiddenScreens.equips(equips)
    if ids == nil or whole ~= true then return nil end
    local rings, items = {}, {}
    for _, id in ipairs(ids) do
        local list = HiddenStatsGame.ring(id, job) ~= nil and rings or items
        list[#list + 1] = id
    end
    table.sort(rings)
    table.sort(items)
    return rings, items
end

-- the snapshot -------------------------------------------------------------------------------------------------------

local function read()
    local calc = HiddenScreens.calculator(HiddenScreens.player_id())
    local basic = Safe.call(calc, "calcBasicAttackDefence")
    local status = Safe.call(calc, "calcAttackDefenceWithEquipmentAndBuff")
    if basic == nil or status == nil then return nil end
    local data = Safe.field(Safe.call(calc, "getEquipData"), "Data")
    local equips = Safe.field(data, "Equips")
    if equips == nil then return nil end
    local job = HiddenScreens.job()
    if job == nil then return nil end
    local human = Safe.call(Safe.call(Safe.singleton("app.CharacterManager"), "get_ManualPlayer"), "get_Human")
    local context = Safe.field(human, ABILITY_CONTEXT)
    if context == nil then return nil end
    local augments, _, all_read = HiddenScreens.augments(context, job)
    if augments == nil then return nil, "augments" end
    if all_read ~= true then return nil end
    local rings, items = items_of(equips, job)
    if rings == nil then return nil end

    local numbers = {}
    put_fields(basic, "basic.", numbers, KNOWN)
    put_fields(status, "total.", numbers, KNOWN)
    for name, method in pairs(MAXIMA) do numbers[name] = finite(Safe.call(calc, method)) end
    put_fields(Safe.field(data, "_EqParam"), "eq.", numbers, nil, true)
    return { numbers = numbers, equipped = { job = job, augments = augments, rings = rings, items = items } }
end

function StatCheck.snapshot()
    local ok, snapshot, why = pcall(read)
    if ok then return snapshot, why end
    Hook.fail("stat_check", snapshot)
    return nil
end

return StatCheck
