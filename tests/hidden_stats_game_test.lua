package.path = "mod/reframework/autorun/?.lua;tests/?.lua;" .. package.path

local T = require("testlib")
local test, eq = T.test, T.eq
local R = require("stubs/reframework")
local NamesGame = require("DD2DamageMeter/game/names_game")
local HiddenStatsGame = require("DD2DamageMeter/game/hidden_stats")
local I18n = require("DD2DamageMeter/i18n")
local Data = require("DD2DamageMeter/hidden_stats_data")
local Model = require("DD2DamageMeter/hidden_stats_model")

-- app.ItemArmorParam's own fields in the game's order (as read in game); the fake declares them on the type, so that
-- the module finds them as in the game (td:get_fields()).
local ARMOR_FIELDS = {
    "_StyleNo", "_PhysicalDefence", "_SlashDefenceRate", "_StrikeDefenceRate", "_MagicDefence", "_FireDefence",
    "_FireResist", "_IceDefence", "_IceResist", "_ThunderDefence", "_ThunderResist", "_LightDefence", "_DarkDefence",
    "_ShakeResistRate", "_BlowResistRate", "_PoisonResist", "_SleepResist", "_SilentResist", "_StoneResist",
    "_WaterResist", "_OilResist", "_FaintResist", "_ColdResist", "_Special", "_SpecialValue", "_SpecialValue2",
    "_SpecialValue3",
}

-- The numbers below are the game's, as read on 2026-11-06.
local PICKPOCKET_JOBS = { { 1, 1.0 }, { 2, 0.9 }, { 3, 1.0 }, { 4, 0.4 }, { 5, 1.8 }, { 6, 1.0 }, { 7, 0.8 },
                          { 8, 0.7 }, { 9, 2.0 }, { 0, 1.0 } }
local REJUV_JOBS = { { 1, 20, 150 }, { 2, 10, 150 }, { 3, 50, 150 }, { 4, 15, 100 }, { 5, 10, 150 }, { 6, 50, 150 },
                     { 7, 15, 150 }, { 8, 20, 100 }, { 9, 2000, 150 }, { 0, 10, 50 } }
-- DropUpParam.Settings: ItemID, DefeatCount, DropRateUp, DropCountUp
local DROP_SETTINGS = { { 10223, 0, 8, 0 }, { 10234, 1, 12, 0 }, { 10235, 3, 12, 1 }, { 10236, 6, 25, 2 },
                        { 10237, 15, 35, 3 }, { 10238, 50, 50, 4 }, { 10239, 100, 100, 5 } }
-- ArmorSpecialEfficacyParam: AttackRate, the ring, its kinds (a name, or false for a kind GUIBase.getName has no
-- name for: nil, "" or a "<REF ...>" placeholder)
local EFFICACY = {
    { 60, 10201, { "Лич", "Вурдалак", "Смерть", false, false, false, false, false } },
    { 50, 10202, { "Низший дракон", "Каратель", "Разоритель Священного сада", "Разоритель Агамена",
                   "Губитель Вермунда", "Губитель островного лагеря", false, false, false } },
    { 20, 10227, { "Барбатос", false } },
}

-- Везение's AbilityParam.AdditionalItemParam.LotteryCashInfos, read live on 2026-11-07: Num, Weight
local LOTTERY = { { 100, 5 }, { 1000, 30 }, { 3000, 40 }, { 5000, 20 }, { 10000, 5 } }

-- The two rings' curves as evaluate gave them live on 2026-11-07: flat steps that end in 0. Which side of an edge
-- takes the step's value is not known, so the fakes take both: Brawn's x = 10 is still 20, Proximity's x = 5 is 20.
local function brawn(x)
    if x <= 10 then return 20.0 elseif x <= 20 then return 10.0 end
    return 0.0
end
local function proximity(x)
    if x < 5 then return 30.0 elseif x < 10 then return 20.0 elseif x < 15 then return 10.0 end
    return 0.0
end

local w -- the current fake world: every object made, the curves' asks

local function obj(type_name, fields, methods)
    local o = R.object(type_name, fields, methods)
    w.all[#w.all + 1] = o
    return o
end

-- A managed array as the game gives it: get_Count answers, get_Item gives nil, get_elements gives the items.
local function array(type_name, items)
    local a = R.array(items, type_name)
    w.all[#w.all + 1] = a
    return a
end

-- A boxed enum value, as the arrays of ItemIDEnum / CharacterID give them (value__).
local function boxed(type_name, value) return obj(type_name, { value__ = value }) end

-- A ring's (or an armour's) ArmorParam: every field present, 0 unless given.
local function armor_param(values)
    local fields = {}
    for _, name in ipairs(ARMOR_FIELDS) do fields[name] = values[name] or 0 end
    fields._DefaultValue = 7  -- the type's static member (declared in world()), readable through the object too
    return obj("app.ItemArmorParam", fields)
end

local function item(id, category, armor_values)
    local equip = category and obj("app.ItemEquipParam", { _EquipCategory = category }) or nil
    local armor = armor_values and armor_param(armor_values) or nil
    return obj("app.ItemCommonParam", { _Id = id }, {
        get_EquipParam = function() return equip end,
        get_ArmorParam = function() return armor end,
    })
end

local function ring(id, special, v1, extra)
    local values = { _Special = special, _SpecialValue = v1 or 0 }
    for k, v in pairs(extra or {}) do values[k] = v end
    return item(id, 6, values)
end

-- A curve: evaluate(Single) gives w.curves[name](x), so that a test can change it; every x asked is kept in
-- w.asked[name]. `range` { min, max }: what get_MinTime / get_MaxTime give, kept in w.ranges[name] (without it the
-- curve has no such methods and they give nil, as an unknown method does in REFramework).
local function curve(name, fn, range)
    w.asked[name] = {}
    w.curves[name] = fn
    local methods = {
        ["evaluate(System.Single)"] = function(_, x)
            local asked = w.asked[name]
            asked[#asked + 1] = x
            return w.curves[name](x)
        end,
    }
    if range then
        w.ranges[name] = range
        methods.get_MinTime = function() return w.ranges[name][1] end
        methods.get_MaxTime = function() return w.ranges[name][2] end
    end
    return obj("via.AnimationCurve", {}, methods)
end

local function world()
    R.new({ containers = true })
    NamesGame.reset()
    HiddenStatsGame.reset()
    w = { all = {}, asked = {}, curves = {}, ranges = {} }
    local td = R.type("app.ItemArmorParam")
    for _, name in ipairs(ARMOR_FIELDS) do
        td.fields[#td.fields + 1] = {
            get_name = function() return name end,
            is_static = function() return false end,
            get_data = function(_, o) return o.fields[name] end,
        }
    end
    -- a static member of the type is not an armour number
    td.fields[#td.fields + 1] = { get_name = function() return "_DefaultValue" end,
                                  is_static = function() return true end, get_data = function() return 7 end }

    -- the augments
    R.enum("app.HumanAbilityID", { Job01_01 = 5, Job05_00 = 24, Job06_01 = 30, Job10_02 = 51, Job10_03 = 52 })
    local rows = {
        [5] = { Value = 45.0, Value2 = 30.0 }, [24] = { Value = 200.0, Value2 = 0.0 },
        [30] = { Value = 75.0, Value2 = 90.0 },
    }
    -- Везение's numbers: not a row, a table of the same AbilityParam (the type names are the fake's)
    local infos = {}
    for i, l in ipairs(LOTTERY) do
        infos[i] = obj("app.AdditionalItemParameter.LotteryCashInfo", { Num = l[1], Weight = l[2] })
    end
    w.fortuity = obj("app.AdditionalItemParameter", { CashProbability = 50.0, MeatProbability = 20.0,
        LotteryCashInfos = array("app.AdditionalItemParameter.LotteryCashInfo[]", infos) })
    w.ability = obj("app.AbilityParameter", { AdditionalItemParam = w.fortuity }, {
        ["getParam(app.HumanAbilityID)"] = function(_, id)
            local row = rows[id]
            return row and obj("app.AbilityParameter.Ability", { AbilityID = id, Value = row.Value,
                                                                  Value2 = row.Value2, Comment = "" }) or nil
        end,
    })
    w.cm = obj("app.CharacterManager", {
        ["<HumanParam>k__BackingField"] = obj("app.HumanParameter", { AbilityParam = w.ability }),
    })
    R.singleton("app.CharacterManager", w.cm)

    -- the items
    local items = {
        [3502] = ring(3502, 1, 200),
        [3509] = ring(3509, 0, 0, { _PhysicalDefence = 50 }),
        [10202] = ring(10202, 0),
        [10227] = ring(10227, 53),
        [10214] = ring(10214, 40),
        [10223] = ring(10223, 49),
        [10235] = ring(10235, 49),
        [10231] = ring(10231, 57),
        [10232] = ring(10232, 58),
        [3538] = ring(3538, 15),
        [3548] = ring(3548, 23),
        [2001] = item(2001, 1, { _PhysicalDefence = 30, _Special = 3, _SpecialValue = 5 }),  -- a shield
        [1] = item(1, nil, nil),                                                               -- a potion
    }
    w.dict = obj("System.Collections.Generic.Dictionary`2<System.Int32,app.ItemCommonParam>", {}, {
        ContainsKey = function(_, id) return items[id] ~= nil end,
        get_Item = function(_, id) return items[id] end,
    })

    local names = {}  -- CharacterID -> what GUIBase.getName gives
    w.names = names
    local efficacy = {}
    for r, row in ipairs(EFFICACY) do
        local kinds = {}
        for k, name in ipairs(row[3]) do
            local chara = 1000 * r + k
            -- a kind with no name: nil, "" or the game's placeholder, in turn
            names[chara] = name or ({ false, "", "<REF ch999_name>" })[k % 3 + 1] or nil
            kinds[k] = boxed("app.CharacterID", chara)
        end
        efficacy[r] = obj("app.ArmorSpecialEfficacyParameter", {
            AttackRate = row[1],
            ItemIDList = array("app.ItemIDEnum[]", { boxed("app.ItemIDEnum", row[2]) }),
            CharaIDList = array("app.CharacterID[]", kinds),
        })
    end
    R.method("app.GUIBase", "getName(app.CharacterID)", function(id) return names[id] or nil end, { static = true })

    local settings, pick, rejuv = {}, {}, {}
    for i, s in ipairs(DROP_SETTINGS) do
        settings[i] = obj("app.JewelryAdditionalData.DropUpParameter.Setting",
            { ItemID = s[1], DefeatCount = s[2], DropRateUp = s[3], DropCountUp = s[4] })
    end
    for i, j in ipairs(PICKPOCKET_JOBS) do
        pick[i] = obj("app.JewelryAdditionalData.PickPocketParameter.JobData", { Job = j[1], MultipleFactor = j[2] })
    end
    for i, j in ipairs(REJUV_JOBS) do
        rejuv[i] = obj("app.JewelryAdditionalData.RecoverStaminaOnNormalAttackParameter.JobData",
            { Job = j[1], MultipleFactor = j[2], MultipleFactorOnClimbOrHoldDown = 0.5, MaxValue = j[3],
              BreakProbability = 0 })
    end
    local jewelry = obj("app.JewelryAdditionalData", {
        AlwaysDamageButStaminaSavingParam = obj("app.JewelryAdditionalData.AlwaysDamageButStaminaSavingParameter",
            { DamagePerSec = 120.0, SecDamageCoolTime = 1.0, SecDamageCoolTimeOnAbsoluteAvoidance = 0.3 }),
        DropUpParam = obj("app.JewelryAdditionalData.DropUpParameter", { DefeatCountUpForStrong = 3,
            Settings = array("app.JewelryAdditionalData.DropUpParameter.Setting[]", settings) }),
        PickPocketParam = obj("app.JewelryAdditionalData.PickPocketParameter", { BaseProbability = 1.5,
            BreakProbability = 0.0,
            JobDataList = array("app.JewelryAdditionalData.PickPocketParameter.JobData[]", pick) }),
        RecoverStaminaOnNormalAttackParam = obj("app.JewelryAdditionalData.RecoverStaminaOnNormalAttackParameter", {
            JobDataList = array("app.JewelryAdditionalData.RecoverStaminaOnNormalAttackParameter.JobData[]", rejuv) }),
        -- Brawn's curve says its range (0..20: its last step ends where the range does), Proximity's does not
        _JewelryParameters = array("app.JewelryAdditionalParameter[]", {
            obj("app.JewelryAdditionalParameter", { _Type = 15, Curve = curve("brawn", brawn, { 0.0, 20.0 }) }),
            obj("app.JewelryAdditionalParameter", { _Type = 23, Curve = curve("proximity", proximity) }),
        }),
    })
    w.im = obj("app.ItemManager", {
        ArmorSpecialEfficacyParam = array("app.ArmorSpecialEfficacyParameter[]", efficacy),
        ["<JewelryAdditionalData>k__BackingField"] = jewelry,
    }, { get_ItemDataDict = function() return w.dict end })
    R.singleton("app.ItemManager", w.im)
    return w
end

local function keys(t)
    local out = {}
    for k in pairs(t) do out[#out + 1] = k end
    table.sort(out)
    return table.concat(out, " ")
end

local function has(list, value)
    for _, v in ipairs(list) do if v == value then return true end end
    return false
end

-- augments -----------------------------------------------------------------------------------------------------------

test("an augment's two numbers come from the game's ability table, asked by its HumanAbilityID", function()
    world()
    local raw = HiddenStatsGame.augment("Job01_01")
    eq(raw.v1, 45, "Стойкость Value")
    eq(raw.v2, 30, "Стойкость Value2")
    eq(keys(raw), "v1 v2", "only the two numbers")
    local asked = R.calls_of("getParam(app.HumanAbilityID)")
    eq(#asked, 1, "one ask")
    eq(asked[1].args[1], 5, "asked by the enum's value of Job01_01")
    eq(HiddenStatsGame.augment("Job05_00").v1, 200, "Жизненная сила")
end)

test("an augment with no row in the table, or with no such name, gives nil", function()
    world()
    eq(HiddenStatsGame.augment("Job10_02"), nil, "Job10_02 has no row")
    eq(HiddenStatsGame.augment("Job99_00"), nil, "no such augment")
    eq(HiddenStatsGame.augment(nil), nil, "no name")
    eq(HiddenStatsGame.augment(5), nil, "a number is not a name")
end)

test("an augment is read once a session: found or without a row; reset forgets", function()
    world()
    HiddenStatsGame.augment("Job01_01")
    HiddenStatsGame.augment("Job10_02")
    local n = #R.calls
    eq(HiddenStatsGame.augment("Job01_01").v2, 30, "the same numbers")
    eq(HiddenStatsGame.augment("Job10_02"), nil, "still none")
    eq(#R.calls, n, "no game call the second time")
    HiddenStatsGame.reset()
    HiddenStatsGame.augment("Job01_01")
    eq(#R.calls, n + 1, "read again after reset")
end)

-- Везение (Job10_03): no row; its numbers are AbilityParam.AdditionalItemParam's

test("Везение: the chances of gold and meat and the smallest and largest sum, from AdditionalItemParam", function()
    world()
    local raw = HiddenStatsGame.augment("Job10_03")
    eq(keys(raw), "additional", "only its own part: no v1 / v2")
    local a = raw.additional
    eq(a.cash, 50, "CashProbability")
    eq(a.meat, 20, "MeatProbability")
    eq(a.cash_min, 100, "the smallest LotteryCashInfos Num")
    eq(a.cash_max, 10000, "the largest")
    eq(keys(a), "cash cash_max cash_min meat", "the four numbers")
    for _, c in ipairs(R.calls_of("getParam(app.HumanAbilityID)")) do
        eq(c.args[1] ~= 52, true, "no row asked for Job10_03")
    end
    -- kept for the session, as an augment's row is
    local n = #R.calls
    eq(HiddenStatsGame.augment("Job10_03"), raw, "the same table")
    eq(#R.calls, n, "no game call the second time")
end)

test("Везение: the sums by their size, not their place; a null entry is not a sum", function()
    world()
    local infos = {
        obj("app.AdditionalItemParameter.LotteryCashInfo", { Num = 3000, Weight = 40 }),
        obj("app.AdditionalItemParameter.LotteryCashInfo", { Num = 10000, Weight = 5 }),
        obj("app.AdditionalItemParameter.LotteryCashInfo", { Num = 100, Weight = 5 }),
        obj("app.AdditionalItemParameter.LotteryCashInfo", { Num = 1000, Weight = 30 }),
    }
    w.fortuity.fields.LotteryCashInfos = array("app.AdditionalItemParameter.LotteryCashInfo[]", infos)
    local a = HiddenStatsGame.augment("Job10_03").additional
    eq(a.cash_min, 100, "the smallest, third in the list")
    eq(a.cash_max, 10000, "the largest, second")
    HiddenStatsGame.reset()
    w.fortuity.fields.LotteryCashInfos = array("app.AdditionalItemParameter.LotteryCashInfo[]", { infos[1], false })
    eq(HiddenStatsGame.augment("Job10_03"), nil, "a null entry: the sums are not all known")
end)

test("Везение: any number unreadable gives nil, never part of them; not kept, read once it answers", function()
    local function without(fn, what)
        world()
        fn()
        eq(HiddenStatsGame.augment("Job10_03"), nil, what)
    end
    without(function() w.ability.fields.AdditionalItemParam = nil end, "no AdditionalItemParam")
    without(function() w.fortuity.fields.CashProbability = nil end, "no CashProbability")
    without(function() w.fortuity.fields.MeatProbability = 0 / 0 end, "a NaN MeatProbability")
    without(function() w.fortuity.fields.LotteryCashInfos = nil end, "no LotteryCashInfos")
    without(function()
        w.fortuity.fields.LotteryCashInfos = array("app.AdditionalItemParameter.LotteryCashInfo[]", {})
    end, "no sums")
    without(function() w.fortuity.fields.LotteryCashInfos.items[2].fields.Num = nil end, "a sum unreadable")
    without(function() w.fortuity.poison = true end, "the table raises")
    -- not kept: once the table answers, it is read
    w.fortuity.poison = false
    eq(HiddenStatsGame.augment("Job10_03").additional.cash, 50, "read once it answers")
end)

-- rings: their own numbers --------------------------------------------------------------------------------------------

test("a ring's Special and its three values (3502, Кольцо признания)", function()
    world()
    local raw = HiddenStatsGame.ring(3502)
    eq(raw.special, 1, "Special type 1")
    eq(raw.v1, 200, "_SpecialValue")
    eq(raw.v2, 0, "_SpecialValue2")
    eq(raw.v3, 0, "_SpecialValue3")
    eq(keys(raw.fields), "", "no armour numbers: _Special and _SpecialValue are not fields")
    eq(raw.efficacy, nil, "not a bane ring")
    eq(raw.drop, nil, "no drop numbers")
    eq(raw.always, nil, "no damage-per-second numbers")
    eq(raw.pickpocket, nil, "no pickpocket numbers")
    eq(raw.rejuv, nil, "no stamina numbers")
    eq(raw.curve, nil, "no curve")
end)

test("a Special-0 ring's armour numbers, without the leading _ (3509)", function()
    world()
    local raw = HiddenStatsGame.ring(3509)
    eq(raw.special, 0, "Special 0")
    eq(raw.fields.PhysicalDefence, 50, "_PhysicalDefence")
    eq(keys(raw.fields), "PhysicalDefence", "only the non-zero ones; no static member")
end)

test("a bane ring: the attack rate and the kinds it works on, by the game's names (10202, 10227)", function()
    world()
    local e = HiddenStatsGame.ring(10202).efficacy
    eq(e.rate, 50, "AttackRate")
    eq(has(e.kinds, "Низший дракон"), true, "a named kind")
    eq(#e.kinds, 6, "six named kinds")
    eq(e.unnamed, 3, "three of the nine have no name")
    eq(e.kinds[1], "Низший дракон", "in the game's order")
    local d = HiddenStatsGame.ring(10227).efficacy
    eq(d.rate, 20, "Кольцо погибели демонов")
    eq(table.concat(d.kinds, ","), "Барбатос", "its named kind")
    eq(d.unnamed, 1, "and one with no name")
end)

test("a bane ring's kind names: two kinds of one name are one name", function()
    world()
    w.names[2007] = "Каратель"  -- one of 10202's three unnamed kinds gets an earlier kind's name
    local e = HiddenStatsGame.ring(10202).efficacy
    eq(#e.kinds, 6, "still six names")
    eq(e.kinds[2], "Каратель", "at its first place")
    eq(e.unnamed, 2, "two without a name now")
end)

test("the drop numbers of Бескорыстие and a wicked ring (10223, 10235)", function()
    world()
    local d = HiddenStatsGame.ring(10235).drop
    eq(d.rate_up, 12, "DropRateUp")
    eq(d.count_up, 1, "DropCountUp")
    eq(d.defeat, 3, "DefeatCount")
    local v = HiddenStatsGame.ring(10223).drop
    eq(v.rate_up, 8, "Бескорыстие DropRateUp")
    eq(v.count_up, 0, "Бескорыстие DropCountUp")
    eq(v.defeat, 0, "Бескорыстие DefeatCount")
end)

test("Ограбление: the base chance and the factor of the given vocation (10231)", function()
    world()
    local p = HiddenStatsGame.ring(10231, 4).pickpocket
    eq(p.base, 1.5, "BaseProbability")
    eq(p.factor, 0.4, "Thief's factor")
    eq(HiddenStatsGame.ring(10231, 9).pickpocket.factor, 2.0, "Trickster's factor")
    eq(HiddenStatsGame.ring(10231, 10).pickpocket.factor, 1.0, "the Warfarer has no row: the Job 0 row's")
    local none = HiddenStatsGame.ring(10231).pickpocket
    eq(none.base, 1.5, "the base without a vocation")
    eq(none.factor, nil, "no vocation, no factor")
end)

test("Омоложение: the factor and the cap of the vocation's own row (10232)", function()
    world()
    local r = HiddenStatsGame.ring(10232, 3).rejuv
    eq(r.factor, 50, "Mage's MultipleFactor")
    eq(r.cap, 150, "Mage's MaxValue")
    eq(keys(r), "cap factor", "the two numbers: MultipleFactor and MaxValue")
    local thief = HiddenStatsGame.ring(10232, 4).rejuv
    eq(thief.factor, 15, "Thief's MultipleFactor")
    eq(thief.cap, 100, "Thief's MaxValue")
    local warfarer = HiddenStatsGame.ring(10232, 10).rejuv
    eq(warfarer.factor, 10, "the Warfarer has no row: the Job 0 row's factor")
    eq(warfarer.cap, 50, "and its cap")
    eq(HiddenStatsGame.ring(10232).rejuv, nil, "no vocation, no row: no numbers")
end)

test("Храбрость: damage per second and its two cool times (10214)", function()
    world()
    local a = HiddenStatsGame.ring(10214).always
    eq(a.per_sec, 120, "DamagePerSec")
    eq(a.cool, 1.0, "SecDamageCoolTime")
    eq(a.cool_dodge, 0.3, "after a perfect dodge")
end)

-- A curve's steps as "y<to y<to ...", or "nil".
local function steps(c)
    if c == nil or c.steps == nil then return "nil" end
    local out = {}
    for _, s in ipairs(c.steps) do out[#out + 1] = string.format("%g<%g", s.y, s.to) end
    return table.concat(out, " ")
end

local function bounds(list)
    local lo, hi = math.huge, -math.huge
    for _, x in ipairs(list) do lo, hi = math.min(lo, x), math.max(hi, x) end
    return lo, hi
end

test("a curve ring: its steps, each value with the x where it ends, and its top (3538, 3548)", function()
    world()
    local brawn_curve = HiddenStatsGame.ring(3538).curve
    eq(steps(brawn_curve), "20<10 10<20", "Кольцо атлетичности: +20 up to 10, +10 up to 20, then 0")
    eq(brawn_curve.top, 20, "its top")
    local prox = HiddenStatsGame.ring(3548).curve
    eq(steps(prox), "30<5 20<10 10<15", "Кольцо близости: 30, 20, 10 up to 5, 10, 15")
    eq(prox.top, 30, "its top")
    for _, s in ipairs(prox.steps) do eq(math.type(s.to), "float", "an edge is a number of the curve's x") end
end)

test("a curve is read over its MinTime..MaxTime and one step past it, else over 0..100, by Single", function()
    world()
    HiddenStatsGame.ring(3538)
    local lo, hi = bounds(w.asked.brawn)
    eq(lo, 0.0, "Brawn from its MinTime")
    eq(hi <= 20.5, true, "to one step past its MaxTime 20: " .. hi)
    eq(hi > 20, true, "past it: the last step ends where the range does")
    HiddenStatsGame.ring(3548)
    lo, hi = bounds(w.asked.proximity)
    eq(lo, 0.0, "no MinTime: from 0")
    eq(hi >= 100 and hi <= 100.5, true, "no MaxTime: to 100 (and one step): " .. hi)
    for _, name in ipairs({ "brawn", "proximity" }) do
        for _, x in ipairs(w.asked[name]) do eq(math.type(x), "float", "a Single is passed as a float") end
    end
    -- a range that is empty or not a number: 0..100 as well
    for _, range in ipairs({ { 20.0, 20.0 }, { 30.0, 10.0 }, { 0 / 0, 20.0 }, { 0.0, nil } }) do
        world()
        w.ranges.brawn = range
        local c = HiddenStatsGame.ring(3538)
        lo, hi = bounds(w.asked.brawn)
        eq(lo == 0 and hi >= 100, true, "range " .. tostring(range[1]) .. ".." .. tostring(range[2]))
        eq(steps(c.curve), "20<10 10<20", "and the same steps")
    end
end)

test("a curve that is not flat steps ending in 0 has no steps; its top stays", function()
    local function read(fn)
        world()
        w.curves.proximity = fn
        return HiddenStatsGame.ring(3548).curve
    end
    local peak = read(function(x) return 30.0 - math.abs(x - 37) / 10 end)
    eq(steps(peak), "nil", "a slope")
    eq(peak.top, 30, "its top at x = 37")
    local flat = read(function() return 20.0 end)
    eq(steps(flat), "nil", "never back to 0: where it ends is not known")
    eq(flat.top, 20, "its top")
    eq(steps(read(function(x) return x < 5 and 0.0 or (x < 10 and 20.0 or 0.0) end)), "nil",
        "0 first: the bonus does not start at the range's start")
    eq(steps(read(function(x)
        if x < 5 then return 30.0 elseif x < 10 then return 0.0 elseif x < 15 then return 10.0 end
        return 0.0
    end)), "nil", "a 0 between two steps")
    -- four steps are shown, five are more than a line has places for
    eq(steps(read(function(x) return x < 20 and 40.0 - 10 * math.floor(x / 5) or 0.0 end)),
        "40<5 30<10 20<15 10<20", "four steps")
    local five = read(function(x) return x < 25 and 50.0 - 10 * math.floor(x / 5) or 0.0 end)
    eq(steps(five), "nil", "five steps")
    eq(five.top, 50, "its top")
    -- a point the curve does not answer: no steps (one may hide there), the top of the rest
    local holes = read(function(x) if x == 7 then return nil end return proximity(x) end)
    eq(steps(holes), "nil", "an unread point")
    eq(holes.top, 30, "the top of what was read")
    -- the edge between two points, to a hundredth: a step that ends at 7.5 is not 7 or 8
    eq(steps(read(function(x) return x < 7.25 and 30.0 or (x < 12.75 and 15.0 or 0.0) end)), "30<7.25 15<12.75",
        "edges between the points of the scan")
    -- an edge off the hundredths is shown rounded, not dropped for the top line
    eq(steps(read(function(x) return x < 22 / 3 and 30.0 or (x < 12.754 and 15.0 or 0.0) end)), "30<7.33 15<12.75",
        "edges off the hundredths, rounded")
    eq(read(function() return nil end), nil, "a curve that answers nothing: no curve")
end)

-- Two outcomes for a curve: each step is checked, or there are no steps and the top line
-- shows. A step must span more than one point of the scan, and the curve must give the next value within 0.25 of
-- where the step's value ends.
test("a step is checked at its edge and by its width; else no steps", function()
    -- a steep ramp 30 → 0 over x 0..2: four one-point runs, which were read as steps up to 0, 0.5, 1, 1.5
    world()
    w.curves.proximity = function(x) return x < 2 and 30.0 - 15 * x or 0.0 end
    local ramp = HiddenStatsGame.ring(3548).curve
    eq(steps(ramp), "nil", "a ramp is not steps")
    eq(ramp.top, 30, "its top")
    -- a 2-wide step under a 0..1000 range: the scan steps by 2.5 and does not land on 10..12, which gives 15
    world()
    w.ranges.brawn = { 0.0, 1000.0 }
    w.curves.brawn = function(x)
        if x <= 10 then return 20.0 elseif x <= 12 then return 15.0 elseif x <= 20 then return 10.0 end
        return 0.0
    end
    local narrow = HiddenStatsGame.ring(3538).curve
    eq(steps(narrow), "nil", "after the 20 ends at 10 the curve gives 15, and the next run's 10 only from 12")
    eq(narrow.top, 20, "its top")
    -- the same curve, but the 15 falls on a point of the scan (x = 10): a one-point run is not taken as a step, even
    -- where it would be right, since one point cannot tell a step from a point on a ramp
    world()
    w.ranges.brawn = { 0.0, 1000.0 }
    w.curves.brawn = function(x)
        if x < 10 then return 20.0 elseif x < 12 then return 15.0 elseif x <= 20 then return 10.0 end
        return 0.0
    end
    eq(steps(HiddenStatsGame.ring(3538).curve), "nil", "a run of one point")
    -- the live shapes under a 0..1000 range still give their steps (wide enough for the coarser scan)
    world()
    w.ranges.brawn = { 0.0, 1000.0 }
    eq(steps(HiddenStatsGame.ring(3538).curve), "20<10 10<20", "Brawn's steps at a step of 2.5")
    -- the curve does not answer while an edge is halved: no steps
    world()
    w.curves.proximity = function(x)
        if x > 4.5 and x < 5 then return nil end
        return proximity(x)
    end
    eq(steps(HiddenStatsGame.ring(3548).curve), "nil", "an unread point inside the halving")
end)

-- The curves as the game gives them (one-shot live read, 2026-11-07): each step ends in a short linear ramp,
-- not a sharp edge. Brawn: 20 down to 10 at 1280 a unit from x = 10 (10.0005 → 19.36, 10.001 → 18.72, 10.002 →
-- 17.44, 10.005 → 13.60, 10.01 → 10), then sharp at 20 (19.99 → 10, 20 → 0); range 0..100. Proximity: 30 down to
-- 20 at 1280 a unit from 5 (5.001 → 28.72, 5.005 → 23.60, 5.01 → 20), then 20 to 10 and 10 to 0 at 320/3 a unit
-- from 10 and 15 (10.001 → 19.89, 10.01 → 18.93, 10.05 → 14.67, 10.1 → 10; 15.001 → 9.89, 15.05 → 4.67, 15.1 → 0).
local function live_brawn(x)
    if x <= 10 then return 20.0 elseif x < 20 then return math.max(10.0, 20.0 - 1280 * (x - 10)) end
    return 0.0
end
local function live_proximity(x)
    if x <= 5 then return 30.0 end
    if x <= 10 then return math.max(20.0, 30.0 - 1280 * (x - 5)) end
    if x <= 15 then return math.max(10.0, 20.0 - 320 / 3 * (x - 10)) end
    return math.max(0.0, 10.0 - 320 / 3 * (x - 15))
end

test("the live curves: steps that end in short ramps give their steps; the edge is where the value ends",
    function()
    -- the fakes give what the game gave
    local LIVE = {
        { live_brawn, { { 10, 20 }, { 10.0005, 19.3604 }, { 10.001, 18.7195 }, { 10.002, 17.4402 },
                        { 10.005, 13.5999 }, { 10.01, 10 }, { 19.99, 10 }, { 20, 0 } } },
        { live_proximity, { { 5, 30 }, { 5.001, 28.7201 }, { 5.005, 23.5999 }, { 5.01, 20 }, { 10, 20 },
                            { 10.001, 19.8933 }, { 10.01, 18.9333 }, { 10.05, 14.6666 }, { 10.1, 10 }, { 15, 10 },
                            { 15.001, 9.8933 }, { 15.05, 4.6666 }, { 15.1, 0 } } },
    }
    for _, l in ipairs(LIVE) do
        for _, p in ipairs(l[2]) do T.near(l[1](p[1]), p[2], 2e-3, "the fake at " .. p[1]) end
    end
    world()
    w.ranges.brawn = { 0.0, 100.0 }
    w.curves.brawn = live_brawn
    w.curves.proximity = live_proximity
    local brawn_raw, prox_raw = HiddenStatsGame.ring(3538), HiddenStatsGame.ring(3548)
    eq(steps(brawn_raw.curve), "20<10 10<20", "Brawn: up to 10 and up to 20")
    eq(steps(prox_raw.curve), "30<5 20<10 10<15", "Proximity: up to 5, 10, 15")
    -- and the panel says so, not the top-only line
    I18n.set("ru")
    local function text(id, raw)
        local p = Model.panel(Data.ring(id), raw)
        return p and p.lines[1].text
    end
    eq(text(3538, brawn_raw), "+20% от базовой силы при поклаже до 10, +10% — до 20", "Brawn's line")
    eq(text(3548, prox_raw), "+30% к силе выстрела из лука на расстоянии до 5 от цели, +20% — до 10, +10% — до 15",
        "Proximity's line")
    I18n.set("en")
    eq(text(3538, brawn_raw), "+20% of the base strength with a load of up to 10, +10% up to 20", "en Brawn")
    I18n.set("ru")
end)

test("a step's ramp to the next value is taken up to 0.25 long; a longer one gives no steps", function()
    -- Proximity's first step ends in a ramp of `len` from x = 5.1 (between two points of the scan), sharp elsewhere
    local function with_ramp(len)
        world()
        w.curves.proximity = function(x)
            if x <= 5.1 then return 30.0 end
            if x < 5.1 + len then return 30.0 - 10 * (x - 5.1) / len end
            if x < 10 then return 20.0 end
            return proximity(x)
        end
        return steps(HiddenStatsGame.ring(3548).curve)
    end
    eq(with_ramp(0.2), "30<5.1 20<10 10<15", "0.2: a step, its edge where the 30 ends")
    eq(with_ramp(0.3), "nil", "0.3: too long a ramp")
end)

test("the halving of an edge stops after a fixed number of tries; an edge it cannot reach gives no steps", function()
    -- at x near 1e13 two floats are 0.002 apart, more than the edge's 0.001: the halving can never get there
    world()
    local at = 1e13
    w.ranges.brawn = { at, at + 4000 }
    w.curves.brawn = function(x)
        if x < at + 1000 then return 20.0 elseif x < at + 2000 then return 10.0 end
        return 0.0
    end
    local c = HiddenStatsGame.ring(3538).curve
    eq(steps(c), "nil", "no steps")
    eq(c.top, 20, "the top")
    eq(#w.asked.brawn < 402 + 2 * 100, true, "the scan and a bounded halving: " .. #w.asked.brawn .. " asks")
end)

test("a curve is read once, with its ring: a second ring() does not evaluate it again", function()
    world()
    local first = HiddenStatsGame.ring(3538)
    local asked = #w.asked.brawn
    eq(asked > 0, true, "read the first time")
    eq(HiddenStatsGame.ring(3538), first, "the same table")
    eq(#w.asked.brawn, asked, "no evaluate the second time")
    eq(#R.calls_of("evaluate(System.Single)"), asked, "nor any other game call to the curve")
end)

-- rings: what is not one, caching, failures ----------------------------------------------------------------------------

test("an item that is not a ring gives nil, and so does an unknown id", function()
    world()
    eq(HiddenStatsGame.ring(2001), nil, "EquipCategory 1 (a shield with a Special)")
    eq(HiddenStatsGame.ring(1), nil, "not equipment")
    eq(HiddenStatsGame.ring(424242), nil, "not in the game's table")
    eq(HiddenStatsGame.ring("3502"), nil, "a string is not an id")
    local n = #R.calls
    HiddenStatsGame.ring(2001)
    HiddenStatsGame.ring(1)
    HiddenStatsGame.ring(424242)
    eq(#R.calls, n, "the answer is kept: no game call the second time")
end)

test("a ring is read once per (id, vocation) a session; reset forgets", function()
    world()
    local first = HiddenStatsGame.ring(3502)
    local n = #R.calls
    eq(HiddenStatsGame.ring(3502), first, "the same table")
    eq(#R.calls, n, "a second ring(3502) makes no game call")
    HiddenStatsGame.ring(10231, 4)
    n = #R.calls
    eq(HiddenStatsGame.ring(10231, 4).pickpocket.factor, 0.4, "kept")
    eq(#R.calls, n, "no game call for the same vocation")
    eq(HiddenStatsGame.ring(10231, 5).pickpocket.factor, 1.8, "another vocation is read")
    eq(#R.calls > n, true, "with game calls")
    HiddenStatsGame.reset()
    n = #R.calls
    HiddenStatsGame.ring(3502)
    eq(#R.calls > n, true, "read again after reset")
end)

test("a game whose calls raise gives nil and never raises; the failure is not kept", function()
    world()
    for _, o in ipairs(w.all) do o.poison = true end
    local ok, raw = pcall(HiddenStatsGame.ring, 3502)
    eq(ok, true, "ring never raises")
    eq(raw, nil, "ring gives nil")
    ok, raw = pcall(HiddenStatsGame.ring, 10202, 4)
    eq(ok and raw, nil, "a bane ring too")
    ok, raw = pcall(HiddenStatsGame.augment, "Job01_01")
    eq(ok, true, "augment never raises")
    eq(raw, nil, "augment gives nil")
    -- the game answers again: read now, nothing was kept from the failure
    for _, o in ipairs(w.all) do o.poison = false end
    eq(HiddenStatsGame.ring(3502).v1, 200, "the ring once the game answers")
    eq(HiddenStatsGame.augment("Job01_01").v1, 45, "the augment once the game answers")
end)

test("one table that raises: nil for now, read when it answers", function()
    world()
    w.ability.poison = true
    eq(HiddenStatsGame.augment("Job01_01"), nil, "the ability table raises")
    w.ability.poison = false
    eq(HiddenStatsGame.augment("Job01_01").v1, 45, "not kept as no row: read once it answers")
    w.dict.poison = true
    eq(HiddenStatsGame.ring(3502), nil, "the item table raises")
    w.dict.poison = false
    eq(HiddenStatsGame.ring(3502).v1, 200, "not kept as not a ring: read once it answers")
    -- no manager at all (a title screen): nil, then the numbers once it is there
    world()
    R.singleton("app.ItemManager", nil)
    R.singleton("app.CharacterManager", nil)
    eq(HiddenStatsGame.ring(3502), nil, "no item manager")
    eq(HiddenStatsGame.augment("Job01_01"), nil, "no character manager")
    R.singleton("app.ItemManager", w.im)
    R.singleton("app.CharacterManager", w.cm)
    eq(HiddenStatsGame.ring(3502).v1, 200, "the ring")
    eq(HiddenStatsGame.augment("Job01_01").v2, 30, "the augment")
end)

T.finish()
