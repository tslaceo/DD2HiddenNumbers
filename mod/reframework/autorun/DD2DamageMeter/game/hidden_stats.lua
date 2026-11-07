-- The numbers behind augments and rings, read from the game's own tables (the hidden-stats panel; the tables and
-- fields as read in the game on 2026-11-06).
-- Read-only: every game access under Safe, no hooks, no setters; never raises.
--
--   HiddenStatsGame.augment(name) -> AugmentRaw | nil
--     AugmentRaw = { v1 = number, v2 = number }: Value and Value2 of app.CharacterManager
--     <HumanParam>k__BackingField.AbilityParam:getParam(id), id the app.HumanAbilityID member called `name`
--     ("Job01_01"). nil for an augment with no row (Job10_02), an unknown name, or when nothing can be read.
--     Везение (Job10_03) has no row; its AugmentRaw is { additional = { cash, meat, cash_min, cash_max } } from the
--     same AbilityParam's AdditionalItemParam (read live on 2026-11-07): CashProbability, MeatProbability and the
--     smallest and largest Num of its LotteryCashInfos (the sums of extra gold); nil while any of them cannot be read
--     (never part of them; tried again on the next call).
--   HiddenStatsGame.ring(id, job) -> RingRaw | nil
--     the item `id` of app.ItemManager:get_ItemDataDict() (all the game's items, owned or not); nil when it is not a
--     ring (get_EquipParam()._EquipCategory other than 6, Jewelry), not in the table, or cannot be read. `job` is the
--     current app.Character.JobEnum 1..10, or nil. From get_ArmorParam():
--       special = _Special (app.EquipSpecial), v1 / v2 / v3 = _SpecialValue / 2 / 3;
--       fields = { [Name] = number }: app.ItemArmorParam's non-zero numeric fields (the type's own, read from the
--         type), without the leading "_" and without the _Special* ones (PhysicalDefence, PoisonResist, ...);
--     and from app.ItemManager's other tables, each nil when the ring has none or it cannot be read:
--       efficacy = { rate, kinds = { name... }, unnamed }: the ArmorSpecialEfficacyParam row whose ItemIDList has
--         the ring: AttackRate, and its CharaIDList's names by the static app.GUIBase.getName(CharacterID), in the
--         list's order, each name once; a kind with no name (nil, "", "<REF ...>") counts in `unnamed`;
--       from <JewelryAdditionalData>k__BackingField:
--       always = { per_sec, cool, cool_dodge } (Special 40): AlwaysDamageButStaminaSavingParam DamagePerSec,
--         SecDamageCoolTime, SecDamageCoolTimeOnAbsoluteAvoidance (the cool time after a perfect dodge);
--       drop = { rate_up, count_up, defeat } (Special 49): the DropUpParam.Settings row whose ItemID is the ring:
--         DropRateUp, DropCountUp, DefeatCount;
--       pickpocket = { base, factor } (Special 57): PickPocketParam BaseProbability, and the MultipleFactor of
--         `job`'s JobDataList row (nil without a job);
--       rejuv = { factor, cap } (Special 58): RecoverStaminaOnNormalAttackParam, the MultipleFactor and
--         the MaxValue of `job`'s JobDataList row; nil without a job;
--       `job`'s row: the row whose Job is `job`, else the row whose Job is 0 (JobEnum None): the lists
--         have rows 1..9 and 0, so the Warfarer (10) takes the 0 row;
--       curve = { top, steps } (a Special with a curve, 15 and 23): the _JewelryParameters entry of that _Type's
--         via.AnimationCurve, read by evaluate(Single) every 0.5 over its get_MinTime..get_MaxTime (0..100 when those
--         cannot be read or the range is empty; a coarser step past 400 points) and one step past it:
--         top: the largest value in the range;
--         steps = { { y, to }, ... }: the curve as flat steps, each value y and the x where it ends (found between
--           two points by halving, at most 64 times, to a hundredth); nil unless every point was read, the first
--           value is not 0, the last one is 0 and no 0 comes between, and there are at most 4 steps (as many as the
--           panel shows); and nil unless each step spans more than one point, where it ends is found, and the curve
--           reaches the next value within 0.25 of there (the game's steps end in ramps of 0.008 to
--           0.094). Live on 2026-11-07: Brawn 20 to 10, 10 to 20; Proximity 30 to 5, 20 to 10, 10 to 15.
--     The tables' arrays (T[]) are read by get_elements: in the game their get_Count answers but get_Item gives nil,
--     so Safe.list does not read them (checked live on 2026-11-06).
--   HiddenStatsGame.reset()  forgets everything read (a new game session)
--
-- Kept for the session: an augment by name, a ring by (id, job), each the same table on later calls (not to be
-- changed by the caller), and "none" answers too (no row, not a ring, not in the table). A read that failed (no
-- manager yet, a call that raised) is not kept and is tried again on the next call, with one exception: an item
-- whose get_EquipParam gives nothing, by a raise or not, counts as not a ring and is kept so (Safe.call cannot tell a
-- raise from the nil of an item with no equipment part). The ring's other tables are read with it: one that cannot
-- be read leaves its part nil for the session.
local Safe = require("DD2DamageMeter/game/safe")
local NamesGame = require("DD2DamageMeter/game/names_game")

local HiddenStatsGame = {}

local ABILITY_ID = "app.HumanAbilityID"
local GET_PARAM = "getParam(app.HumanAbilityID)"
local ARMOR_TYPE = "app.ItemArmorParam"
local JEWELRY = 6                -- app.ItemEquipCategory Jewelry
local JEWELRY_DATA = "<JewelryAdditionalData>k__BackingField"
local GET_NAME = "getName(app.CharacterID)"
local EVALUATE = "evaluate(System.Single)"
local FORTUITY = "Job10_03"      -- Везение: no row; its numbers are AbilityParam.AdditionalItemParam's
local CURVE_STEP = 0.5           -- the scan's step over a curve's x
local CURVE_POINTS = 400         -- at most about this many points: a wider range takes a coarser step
local CURVE_RANGE = { 0, 100 }   -- the x range when the curve does not tell its own
local MAX_STEPS = 4              -- the steps a curve line has places for (hidden_stats_data.lua)
local EDGE = 0.001               -- how close the halving finds where a step ends
local EDGE_TRIES = 64            -- at most this many halvings per edge (no loop without an end)
local TRANSITION = 0.25          -- the longest ramp from one step's value to the next's that is a step
-- app.EquipSpecial types whose numbers are in JewelryAdditionalData
local ALWAYS, DROP, PICKPOCKET, REJUV = 40, 49, 57, 58
local NO_JOB = 0                 -- app.Character.JobEnum None: the job lists' row for a vocation without its own

local augments = {}       -- name -> AugmentRaw, or false (no row)
local rings = {}          -- "id|job" -> RingRaw, or false (not a ring)
local armor_names = nil   -- app.ItemArmorParam's own instance field names, read once

function HiddenStatsGame.reset()
    augments, rings, armor_names = {}, {}, nil
end

local function finite(v)
    if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
    return v
end

local function number(obj, name) return finite(Safe.field(obj, name)) end

-- A name the game gives: not empty, not its "<REF ...>" placeholder for a missing message.
local function text_of(value)
    if type(value) == "string" and value ~= "" and not value:find("^<REF") then return value end
    return nil
end

local function a_elements(arr) return arr:get_elements() end

-- The items of a game array field (T[]) as a Lua sequence, a null item `false`; empty when it cannot be read.
local function elements(obj, name)
    local arr = Safe.field(obj, name)
    if arr == nil then return {} end
    return Safe.items(Safe.try(a_elements, arr))
end

-- augments -----------------------------------------------------------------------------------------------------------

local function get_param(params, id) return params:call(GET_PARAM, id) end

-- Везение's numbers from AbilityParam.AdditionalItemParam: the chances of extra gold and of meat and the
-- smallest and largest sum of gold; nil when any of them cannot be read (a null entry among the sums included).
local function additional(params)
    local p = Safe.field(params, "AdditionalItemParam")
    local cash, meat = number(p, "CashProbability"), number(p, "MeatProbability")
    if cash == nil or meat == nil then return nil end
    local low, high
    for _, info in ipairs(elements(p, "LotteryCashInfos")) do
        local sum = number(info or nil, "Num")
        if sum == nil then return nil end
        if low == nil or sum < low then low = sum end
        if high == nil or sum > high then high = sum end
    end
    if low == nil then return nil end
    return { cash = cash, meat = meat, cash_min = low, cash_max = high }
end

-- AugmentRaw, false for no row, nil when it cannot be read now.
local function read_augment(name)
    local id = NamesGame.enum_value(ABILITY_ID, name)
    if id == nil then return nil end
    local human = Safe.field(Safe.singleton("app.CharacterManager"), "<HumanParam>k__BackingField")
    local params = Safe.field(human, "AbilityParam")
    if params == nil then return nil end
    if name == FORTUITY then
        local found = additional(params)
        return found and { additional = found } or nil
    end
    local ok, row = pcall(get_param, params, id)
    if not ok then return nil end
    if row == nil then return false end
    local v1, v2 = number(row, "Value"), number(row, "Value2")
    if v1 == nil or v2 == nil then return nil end
    return { v1 = v1, v2 = v2 }
end

function HiddenStatsGame.augment(name)
    if type(name) ~= "string" then return nil end
    local found = augments[name]
    if found == nil then
        local ok, raw = pcall(read_augment, name)
        if ok and raw ~= nil then augments[name] = raw end
        found = ok and raw or nil
    end
    return found or nil
end

-- rings --------------------------------------------------------------------------------------------------------------

local function f_name(f) return f:get_name() end
local function f_static(f) return f:is_static() end
local function t_fields(td) return td:get_fields() end

-- app.ItemArmorParam's instance field names without the _Special* ones; nil while the type cannot be read.
local function armor_field_names()
    if armor_names then return armor_names end
    local td = Safe.type(ARMOR_TYPE)
    local names = {}
    for _, f in ipairs(Safe.items(td and Safe.try(t_fields, td))) do
        local name = f and Safe.try(f_name, f)
        if type(name) == "string" and Safe.try(f_static, f) == false and not name:find("^_Special") then
            names[#names + 1] = name
        end
    end
    if #names == 0 then return nil end
    armor_names = names
    return names
end

local function armor_fields(armor)
    local names = armor_field_names()
    if names == nil then return nil end
    local fields = {}
    for _, name in ipairs(names) do
        local v = number(armor, name)
        if v and v ~= 0 then fields[(name:gsub("^_", ""))] = v end
    end
    return fields
end

local function efficacy(im, id)
    for _, row in ipairs(elements(im, "ArmorSpecialEfficacyParam")) do
        local mine = false
        for _, item in ipairs(elements(row, "ItemIDList")) do
            if Safe.enum(item) == id then mine = true break end
        end
        if mine then
            local rate = number(row, "AttackRate")
            if rate == nil then return nil end
            local kinds, seen, unnamed = {}, {}, 0
            for _, kind in ipairs(elements(row, "CharaIDList")) do
                local chara = Safe.enum(kind)
                local name = chara and text_of(Safe.static("app.GUIBase", GET_NAME, chara))
                if name == nil then
                    unnamed = unnamed + 1
                elseif not seen[name] then
                    seen[name] = true
                    kinds[#kinds + 1] = name
                end
            end
            return { rate = rate, kinds = kinds, unnamed = unnamed }
        end
    end
    return nil
end

local function always(jewelry)
    local p = Safe.field(jewelry, "AlwaysDamageButStaminaSavingParam")
    local per_sec, cool = number(p, "DamagePerSec"), number(p, "SecDamageCoolTime")
    local cool_dodge = number(p, "SecDamageCoolTimeOnAbsoluteAvoidance")
    if per_sec == nil or cool == nil or cool_dodge == nil then return nil end
    return { per_sec = per_sec, cool = cool, cool_dodge = cool_dodge }
end

local function drop(jewelry, id)
    local p = Safe.field(jewelry, "DropUpParam")
    for _, s in ipairs(elements(p, "Settings")) do
        if Safe.enum(Safe.field(s, "ItemID")) == id then
            local rate_up, count_up = number(s, "DropRateUp"), number(s, "DropCountUp")
            local defeat = number(s, "DefeatCount")
            if rate_up == nil or count_up == nil or defeat == nil then return nil end
            return { rate_up = rate_up, count_up = count_up, defeat = defeat }
        end
    end
    return nil
end

-- The JobDataList row of `job`: the row whose Job is `job`, else the one whose Job is 0 (None); nil
-- without a job or such a row.
local function job_row(param, job)
    if job == nil then return nil end
    local none
    for _, row in ipairs(elements(param, "JobDataList")) do
        local row_job = Safe.enum(Safe.field(row, "Job"))
        if row_job == job then return row end
        if row_job == NO_JOB then none = row end
    end
    return none
end

local function pickpocket(jewelry, job)
    local p = Safe.field(jewelry, "PickPocketParam")
    local base = number(p, "BaseProbability")
    if base == nil then return nil end
    return { base = base, factor = number(job_row(p, job), "MultipleFactor") }
end

local function rejuv(jewelry, job)
    local row = job_row(Safe.field(jewelry, "RecoverStaminaOnNormalAttackParam"), job)
    local factor, cap = number(row, "MultipleFactor"), number(row, "MaxValue")
    if factor == nil or cap == nil then return nil end
    return { factor = factor, cap = cap }
end

-- The curve's value at x, nil when it cannot be read; x goes as a float, the parameter being a Single.
local function eval(c, x) return finite(Safe.call(c, EVALUATE, x + 0.0)) end

local function same(a, b) return math.abs(a - b) <= 1e-4 end

-- The curve's x range: get_MinTime..get_MaxTime, else CURVE_RANGE.
local function curve_range(c)
    local lo, hi = finite(Safe.call(c, "get_MinTime")), finite(Safe.call(c, "get_MaxTime"))
    if lo == nil or hi == nil or hi <= lo then return CURVE_RANGE[1], CURVE_RANGE[2] end
    return lo, hi
end

-- Where the curve stops giving what `left(value)` holds for, between a (where it holds, as a rule) and b (where it
-- does not): the first x past it, within EDGE, by at most EDGE_TRIES halvings (where floats are coarser than EDGE it
-- would never get there); nil when the curve does not answer meanwhile or that x is not reached. The value at the x it
-- gives is one `left` does not hold for: b moves only to such points. When `left` does not hold at a either (steps_of's
-- second call at a sharp step), the x given is within EDGE of a.
local function halve(c, a, b, left)
    for _ = 1, EDGE_TRIES do
        if b - a <= EDGE then break end
        local mid = (a + b) / 2
        local v = eval(c, mid)
        if v == nil then return nil end
        if left(v) then a = mid else b = mid end
    end
    if b - a > EDGE then return nil end
    return b
end

-- The steps of runs (each { y, first, last }): nil unless the curve is flat steps whose first value is not 0, whose
-- last value is 0 with no 0 before it, and that are at most MAX_STEPS. Each step is checked: it spans
-- more than one point of the scan (one point cannot tell a step from a ramp); where its value ends is found; and the
-- curve gives the next run's value within TRANSITION of there. The game's steps end in short ramps (Brawn 20 → 10
-- over 0.008, Proximity 20 → 10 over 0.094); a longer ramp, or a narrow step hidden between two points of a coarse
-- scan, gives no steps. The edge shown is where the value ends, to a hundredth.
local function steps_of(c, runs)
    local n = #runs - 1
    if n < 1 or n > MAX_STEPS or not same(runs[#runs].y, 0) then return nil end
    local steps = {}
    for i = 1, n do
        local run, next_run = runs[i], runs[i + 1]
        if same(run.y, 0) or not (run.last > run.first) then return nil end
        local ended = halve(c, run.last, next_run.first, function(v) return same(v, run.y) end)
        -- where next_run's value begins: the curve gives it there (b of the halving always does)
        local begun = ended and halve(c, ended, next_run.first, function(v) return not same(v, next_run.y) end)
        if begun == nil or begun - ended > TRANSITION then return nil end
        steps[i] = { y = run.y, to = math.floor(ended * 100 + 0.5) / 100 }
    end
    return steps
end

-- CurveRaw of a via.AnimationCurve (the header's `curve`), nil when no point can be read.
local function curve_of(c)
    local lo, hi = curve_range(c)
    local step = math.max(CURVE_STEP, (hi - lo) / CURVE_POINTS)
    local count = math.ceil((hi - lo) / step - 1e-9)
    local runs, top, whole = {}, nil, true
    -- the points lo, lo + step, ..., hi, and one past hi: a step that ends with the range shows its end
    for i = 0, count + 1 do
        local x = i <= count and math.min(lo + step * i, hi) or hi + step
        local y = eval(c, x)
        if y == nil then
            whole = false
        else
            if i <= count and (top == nil or y > top) then top = y end
            local run = runs[#runs]
            if run and same(run.y, y) then
                run.last = x
            elseif #runs < MAX_STEPS + 1 then
                runs[#runs + 1] = { y = y, first = x, last = x }
            else
                whole = false  -- more steps than a line shows (the last run is the 0 after them): no steps
            end
        end
    end
    if top == nil then return nil end
    return { top = top, steps = whole and steps_of(c, runs) or nil }
end

local function curve(jewelry, special)
    if special == 0 then return nil end
    for _, param in ipairs(elements(jewelry, "_JewelryParameters")) do
        if Safe.enum(Safe.field(param, "_Type")) == special then
            return curve_of(Safe.field(param, "Curve"))
        end
    end
    return nil
end

-- The item, false when the table has no such id, nil when it cannot be read now.
local function item_of(id)
    local dict = Safe.call(Safe.singleton("app.ItemManager"), "get_ItemDataDict")
    local has = Safe.call(dict, "ContainsKey", id)
    if has == false then return false end
    if has ~= true then return nil end
    return Safe.call(dict, "get_Item", id)
end

-- RingRaw, false when the item is not a ring (or not in the table), nil when it cannot be read now.
local function read_ring(id, job)
    local item = item_of(id)
    if not item then return item end
    local equip = Safe.call(item, "get_EquipParam")
    if Safe.enum(Safe.field(equip, "_EquipCategory")) ~= JEWELRY then return false end
    local armor = Safe.call(item, "get_ArmorParam")
    local special = Safe.enum(Safe.field(armor, "_Special"))
    local v1, v2, v3 = number(armor, "_SpecialValue"), number(armor, "_SpecialValue2"), number(armor, "_SpecialValue3")
    if special == nil or v1 == nil or v2 == nil or v3 == nil then return nil end
    local fields = armor_fields(armor)
    if fields == nil then return nil end
    local im = Safe.singleton("app.ItemManager")
    local jewelry = Safe.field(im, JEWELRY_DATA)
    return {
        special = special, v1 = v1, v2 = v2, v3 = v3, fields = fields,
        efficacy = efficacy(im, id),
        always = special == ALWAYS and always(jewelry) or nil,
        drop = special == DROP and drop(jewelry, id) or nil,
        pickpocket = special == PICKPOCKET and pickpocket(jewelry, job) or nil,
        rejuv = special == REJUV and rejuv(jewelry, job) or nil,
        curve = curve(jewelry, special),
    }
end

function HiddenStatsGame.ring(id, job)
    if math.type(id) ~= "integer" then return nil end
    job = math.type(job) and math.tointeger(job) or nil
    local key = id .. "|" .. tostring(job)
    local found = rings[key]
    if found == nil then
        local ok, raw = pcall(read_ring, id, job)
        if ok and raw ~= nil then rings[key] = raw end
        found = ok and raw or nil
    end
    return found or nil
end

return HiddenStatsGame
