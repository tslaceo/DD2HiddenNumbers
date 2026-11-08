package.path = "mod/reframework/autorun/?.lua;tests/?.lua;" .. package.path

local T = require("testlib")
local test, eq, near = T.test, T.eq, T.near
local R = require("stubs/reframework")

local GET_ABILITY = "getAbility(app.Character.JobEnum, app.AbilityContext.AbilitySlot)"
local AC_FIELD = "<AbilityContext>k__BackingField"

-- The CharacterIDs read in the game: the player Guts, the pawn Casca.
local PLAYER_ID, CASCA_ID = 2891076981, 2283028347

-- app.HumanAbilityID: the 52 augments, Job01_00 .. Job09_04 and Job10_00 .. Job10_06, valued 4 .. 55 here.
local AUGMENT_ID = {}
do
    local i = 0
    for job = 1, 10 do
        for slot = 0, job == 10 and 6 or 4 do
            i = i + 1
            AUGMENT_ID[string.format("Job%02d_%02d", job, slot)] = i + 3
        end
    end
end

local G -- the current test's world

-- A backing field's name.
local function bf(name) return "<" .. name .. ">k__BackingField" end

-- The two status structs' instance fields, as their types give them (backing fields). The basic one
-- (calcBasicAttackDefence) is the parent of the one with equipment and buffs (calcAttackDefenceWithEquipmentAndBuff),
-- which adds the equipment's parts: its own fields are only these. Each type also has a static field and one that is
-- no number.
local BASIC_TYPE, TOTAL_TYPE = "app.PlayerBasicAttackDefenceStatus", "app.PlayerAttackDefenceStatus"
local BASIC_FIELDS = { "BasicAttack", "BasicDefence", "BasicMagicAttack", "BasicMagicDefence", "AdditionalAttack",
    "AdditionalDefence", "AdditionalMagicAttack", "AdditionalMagicDefence", "Blow", "BlowResistance" }
local TOTAL_FIELDS = { "ArmorAttack", "ArmorDefence", "ArmorMagicAttack", "ArmorMagicDefence", "BlowFactor",
    "BlowResistanceFactor", "ArmorBlownDefenceFactor" }

-- The player's numbers as read in the game (2026-11-06, the Warfarer): the status screen's
-- Защита «1645 (380)» = 380 + 159 + 1106, the brackets of Сбивание с ног «651 (100)» and УСТ к сбиванию «882 (100)»;
-- the Blow factors are made up. The basic struct's values, then the other's (the same, with the equipment's parts).
local function basic_values()
    return {
        [bf("BasicAttack")] = 420.0, [bf("AdditionalAttack")] = 0.0,
        [bf("BasicDefence")] = 380.0, [bf("AdditionalDefence")] = 159.0,
        [bf("BasicMagicAttack")] = 372.2, [bf("AdditionalMagicAttack")] = 0.0,
        [bf("BasicMagicDefence")] = 373.8, [bf("AdditionalMagicDefence")] = 157.14,
        [bf("Blow")] = 100.0, [bf("BlowResistance")] = 100.0,
        [bf("Owner")] = R.object("app.Character"), Count = 7,
    }
end

local function total_values()
    local t = basic_values()
    t[bf("ArmorAttack")], t[bf("ArmorDefence")] = 1261.0, 1106.0
    t[bf("ArmorMagicAttack")], t[bf("ArmorMagicDefence")] = 1267.8, 964.0
    t[bf("BlowFactor")], t[bf("BlowResistanceFactor")], t[bf("ArmorBlownDefenceFactor")] = 1.0, 1.0, 0.0
    return t
end

-- app.EquipParam's own fields as the type gives them: name -> static or not.
local EQ_FIELDS = { "_PhysicalDefence", "_MagicDefence", "_FireDefence", "_IceDefence", "_ThunderDefence",
    "_PoisonResist", "_ColdResist", "_SlashDefenceRate", "_Owner" }

local function eq_values()
    return { _PhysicalDefence = 1106.0, _MagicDefence = 964.0, _FireDefence = 20.0, _IceDefence = 0.0,
        _ThunderDefence = 40.0, _PoisonResist = 5.0, _ColdResist = 75.0, _SlashDefenceRate = 6.0,
        _Owner = R.object("app.Character"), Version = 3 }
end

-- A field of a type as td:get_fields() gives it.
local function field(name, static)
    return { get_name = function() return name end, is_static = function() return static == true end }
end

-- An item in an equipment slot (app.ItemDefine.StorageData).
local function storage(id)
    return R.object("app.ItemDefine.StorageData", {}, { get_ItemId = function() return id end })
end

-- Dictionary<app.CharacterID, app.PlayerStatusCalculator> over G.calcs ({ { key, calculator } }), read by its
-- enumerator as game/hidden_screens.lua reads it.
local function calculators()
    return R.object("System.Collections.Generic.Dictionary`2<app.CharacterID,app.PlayerStatusCalculator>", {}, {
        GetEnumerator = function()
            local i = 0
            return R.object("Enumerator", {}, {
                MoveNext = function() i = i + 1; return i <= #G.calcs end,
                get_Current = function()
                    return R.object("KeyValuePair", { key = G.calcs[i][1], value = G.calcs[i][2] })
                end,
            })
        end,
    })
end

-- The player's status calculator, every answer read live from G: G.basic / G.status (the two status structs'
-- values; nil: no struct), G.hp / G.sp / G.weight = { max, base }, G.equips (item ids, false: a null slot; nil: no
-- Equips), G.eq (EquipParam's values; nil: none).
local function player_calculator()
    return R.object("app.PlayerStatusCalculator", {}, {
        calcBasicAttackDefence = function()
            return G.basic and R.object(BASIC_TYPE, G.basic) or nil
        end,
        calcAttackDefenceWithEquipmentAndBuff = function()
            return G.status and R.object(TOTAL_TYPE, G.status) or nil
        end,
        calcMaxHPWithEquipmentAndBuff = function() return G.hp[1] end,
        calcBasicMaxHP = function() return G.hp[2] end,
        calcMaxStaminaWithEquipmentAndBuff = function() return G.sp[1] end,
        calcBasicMaxStamina = function() return G.sp[2] end,
        calcMaxWeightWithBuff = function() return G.weight[1] end,
        calcBasicMaxWeight = function() return G.weight[2] end,
        getEquipData = function()
            local equips = nil
            if G.equips then
                local slots = {}
                for i, id in ipairs(G.equips) do slots[i] = id and storage(id) or false end
                equips = R.array(slots, "app.ItemDefine.StorageData[]")
            end
            local data = R.object("app.EquipData", { Equips = equips,
                _EqParam = G.eq and R.object("app.EquipParam", G.eq) or nil })
            return R.object("app.ReadOnlyEquipData", { Data = data })
        end,
    })
end

-- A fresh game and fresh modules: the player (the Warfarer, 10) with his AbilityContext (G.slots[job][slot] the
-- augment's HumanAbilityID, 0 an empty slot), the calculators of the player and Casca, and the fields of
-- app.EquipParam and of the two status structs; HiddenStatsGame.ring is faked at the module's edge: G.rings[id] (each
-- job it was asked with in G.ring_jobs).
local function fresh()
    for name in pairs(package.loaded) do
        if name:find("^DD2DamageMeter/") then package.loaded[name] = nil end
    end
    DD2DM_HOOKS = nil
    R.new({ containers = true })
    G = { job = 10, ring_jobs = {}, basic = basic_values(), status = total_values(), hp = { 3100.0, 2900.0 },
          sp = { 1300.0, 1150.0 }, weight = { 62.7, 60.0 }, equips = { 1001, 2001, 0, false, 10223, 3502, 2003 },
          eq = eq_values(), rings = { [3502] = { special = 1 }, [10223] = { special = 49 } } }
    G.slots = { [10] = { [0] = AUGMENT_ID.Job05_00, [1] = 0, [2] = AUGMENT_ID.Job01_01, [3] = AUGMENT_ID.Job10_04,
                         [4] = 0, [5] = 0, [6] = 0 } }
    R.enum("app.HumanAbilityID", AUGMENT_ID)
    local td = R.type("app.EquipParam")
    for _, name in ipairs(EQ_FIELDS) do td.fields[#td.fields + 1] = field(name) end
    td.fields[#td.fields + 1] = field("Version", true)
    local basic, total = R.type(BASIC_TYPE), R.type(TOTAL_TYPE, BASIC_TYPE)
    for _, name in ipairs(BASIC_FIELDS) do basic.fields[#basic.fields + 1] = field(bf(name)) end
    basic.fields[#basic.fields + 1] = field(bf("Owner"))
    basic.fields[#basic.fields + 1] = field("Count", true)
    for _, name in ipairs(TOTAL_FIELDS) do total.fields[#total.fields + 1] = field(bf(name)) end

    local ctx = R.object("app.JobContext", {})
    setmetatable(ctx.fields, { __index = function(_, k) if k == "CurrentJob" then return G.job end end })
    G.ac = R.object("app.AbilityContext", {}, {
        [GET_ABILITY] = function(_, job, slot)
            G.asked = G.asked or {}
            G.asked[#G.asked + 1] = job .. "/" .. slot
            local slots = G.slots[job]
            return slots and slots[slot]
        end,
    })
    G.human = R.object("app.Human", {}, { get_JobContext = function() return ctx end })
    setmetatable(G.human.fields, { __index = function(_, k) if k == AC_FIELD then return G.ac end end })
    G.player = R.character({ go = "ch000000_00", chara_id = PLAYER_ID })
    G.player.methods.get_Human = function() return G.human end
    G.calcs = {
        { CASCA_ID, R.object("app.PlayerStatusCalculator", {}, {}) },
        { PLAYER_ID, player_calculator() },
    }
    local holder = R.object("app.PlayerStatusCalculatorHolder", { Calculators = calculators() })
    G.cm = R.object("app.CharacterManager", {}, {
        get_ManualPlayer = function() return G.player end,
        get_PlayerStatusCalculatorHolder = function() return holder end,
    })
    R.singleton("app.CharacterManager", G.cm)

    local HG = require("DD2DamageMeter/game/hidden_stats")
    HG.ring = function(id, job)
        G.ring_jobs[#G.ring_jobs + 1] = job
        return G.rings[id]
    end
    return require("DD2DamageMeter/game/stat_check"), require("DD2DamageMeter/game/hook")
end

local function keys(t)
    local out = {}
    for k in pairs(t or {}) do out[#out + 1] = k end
    table.sort(out)
    return table.concat(out, " ")
end

-- `prefix` .. each name of the lists, sorted, as keys() writes them.
local function prefixed(prefix, ...)
    local out = {}
    for _, list in ipairs({ ... }) do
        for _, name in ipairs(list) do out[#out + 1] = prefix .. name end
    end
    table.sort(out)
    return table.concat(out, " ")
end

test("snapshot: every number of both status structs, the six maxima and the equipment's sums", function()
    local SC = fresh()
    local s = SC.snapshot()
    local n = s.numbers
    eq(keys(n), prefixed("basic.", BASIC_FIELDS)
        .. " eq.ColdResist eq.FireDefence eq.MagicDefence eq.PhysicalDefence eq.PoisonResist eq.SlashDefenceRate "
        .. "eq.ThunderDefence hp_base hp_max sp_base sp_max " .. prefixed("total.", BASIC_FIELDS, TOTAL_FIELDS)
        .. " weight_base weight_max", "each struct's fields, its parent type's too; the maxima; the non-zero sums")
    eq(n["total.BasicDefence"] + n["total.AdditionalDefence"] + n["total.ArmorDefence"], 1645, "Защита «1645 (380)»")
    eq(n["basic.BasicDefence"], 380, "the number in brackets, from the basic struct")
    eq(n["basic.AdditionalDefence"], 159, "Стойкость's share")
    near(n["total.AdditionalMagicDefence"], 157.14, 1e-9, "a float as read")
    eq(n["basic.Blow"], 100, "knockdown power's bracket"); eq(n["basic.BlowResistance"], 100, "knockdown resistance's")
    eq(n["total.BlowResistanceFactor"], 1, "a Blow field of the struct with equipment")
    eq(n["total.ArmorBlownDefenceFactor"], 0, "a field of 0 is kept"); eq(n["basic.AdditionalAttack"], 0, "here too")
    eq(n["basic.Owner"], nil, "not a number"); eq(n["basic.Count"], nil, "a static field left out")
    eq(n["basic.ArmorDefence"], nil, "the basic struct has no equipment part")
    eq(n.hp_max, 3100, "max HP"); eq(n.hp_base, 2900, "its base")
    eq(n.sp_max, 1300, "max stamina"); eq(n.sp_base, 1150, "its base")
    near(n.weight_max, 62.7, 1e-9, "carry weight"); eq(n.weight_base, 60, "its base")
    eq(n["eq.ThunderDefence"], 40, "an equipment sum"); eq(n["eq.ColdResist"], 75, "a resist")
    eq(n["eq.IceDefence"], nil, "a sum of 0 left out")
    eq(n["eq.Version"], nil, "a static field left out"); eq(n["eq.Owner"], nil, "not a number")
end)

test("snapshot: a field a patch adds is recorded; a struct whose type cannot be read gives its known fields",
    function()
    local SC = fresh()
    local total = R.type(TOTAL_TYPE)
    total.fields[#total.fields + 1] = field(bf("GuardBreak"))
    G.status[bf("GuardBreak")] = 30.0
    eq(SC.snapshot().numbers["total.GuardBreak"], 30, "the new field")
    -- neither type's field list can be read: the parts known from the game, by name
    SC = fresh()
    local function raising() return setmetatable({}, { __len = function() error("fields raised") end,
        __index = function() error("fields raised") end }) end
    R.type(BASIC_TYPE).fields, R.type(TOTAL_TYPE).fields = raising(), raising()
    local n = SC.snapshot().numbers
    eq(keys(n):match("^(.-) eq%."), prefixed("basic.", BASIC_FIELDS), "the basic struct's known fields")
    eq(keys(n):match("sp_max (.-) weight_base"), prefixed("total.", BASIC_FIELDS, TOTAL_FIELDS),
        "the other's, its Blow ones among them")
end)

test("a ring swap that changes only the knockdown resistance is a stat_check record", function()
    local SC = fresh()
    local decode = require("json_decode")
    local Collector = require("DD2DamageMeter/game/collector")
    local lines = {}
    Collector.output(function(text) lines[#lines + 1] = text end)
    Collector.stat_check(10, SC.snapshot())
    -- Кольцо решимости (3535, type 12) in place of Кольцо бескорыстия: only the knockdown resistance moves
    G.rings[3535] = { special = 12 }
    G.equips[5] = 3535
    G.status[bf("BlowResistance")] = 200.0
    Collector.stat_check(12, SC.snapshot())
    eq(#lines, 1, "one record")
    local r = decode(lines[1])
    eq(r.kind, "stat_check", "a stat_check")
    eq(T.str(r.added), "3535", "Кольцо решимости in"); eq(T.str(r.removed), "10223", "Кольцо бескорыстия out")
    eq(keys(r.changed), "total.BlowResistance", "only the knockdown resistance")
    eq(r.changed["total.BlowResistance"].from, 100, "from 100"); eq(r.changed["total.BlowResistance"].to, 200, "to 200")
end)

test("snapshot: the vocation, the augments by name, the rings and the other gear, each sorted", function()
    local SC = fresh()
    local e = SC.snapshot().equipped
    eq(e.job, 10, "the Warfarer")
    eq(T.str(e.augments), "Job01_01 Job05_00 Job10_04", "the augments of slots No0..No6, empty ones left out")
    eq(table.concat(G.asked, " "), "10/0 10/1 10/2 10/3 10/4 10/5 10/6",
        "slots No0..No6 of his vocation (app.AbilityContext.AbilitySlot has seven)")
    eq(T.str(e.rings), "3502 10223", "the rings")
    eq(T.str(e.items), "1001 2001 2003", "the weapon and armour; an empty or null slot left out")
    for _, job in ipairs(G.ring_jobs) do eq(job, 10, "a ring read by his vocation") end
    -- another vocation: its own slots
    G.job = 4
    G.slots[4] = { [0] = AUGMENT_ID.Job04_00, [1] = AUGMENT_ID.Job02_03, [2] = 0, [3] = 0, [4] = 0, [5] = 0, [6] = 0 }
    e = SC.snapshot().equipped
    eq(e.job, 4, "the Thief"); eq(T.str(e.augments), "Job02_03 Job04_00", "his augments")
    -- an id the enum does not name is kept as its number
    G.slots[4][2] = 999
    eq(T.str(SC.snapshot().equipped.augments), "999 Job02_03 Job04_00", "999")
    -- a boxed id, as the game can give
    G.slots[4] = { [0] = R.object("app.HumanAbilityID", { value__ = AUGMENT_ID.Job09_01 }), [1] = 0, [2] = 0, [3] = 0,
                   [4] = 0, [5] = 0, [6] = 0 }
    eq(T.str(SC.snapshot().equipped.augments), "Job09_01", "boxed")
end)

test("snapshot is nil, \"augments\", when no augment slot can be read; empty slots (0) are no such case", function()
    local SC, Hook = fresh()
    -- getAbility gives nothing for all 7 slots: unreadable, not empty
    G.slots[10] = {}
    local s, why = SC.snapshot()
    eq(s, nil, "no snapshot: an augment change could never be told")
    eq(why, "augments", "why")
    eq(#G.asked, 7, "all 7 slots asked")
    -- the method missing on the context (an unknown method gives nil): the same
    G.ac = R.object("app.AbilityContext", {}, {})
    s, why = SC.snapshot()
    eq(s, nil, "no getAbility"); eq(why, "augments", "why")
    eq(Hook.info().errors, 0, "no error of the mod's own")
    -- every slot empty (0): known, none equipped
    SC = fresh()
    G.slots[10] = { [0] = 0, [1] = 0, [2] = 0, [3] = 0, [4] = 0, [5] = 0, [6] = 0 }
    s, why = SC.snapshot()
    eq(s ~= nil and #s.equipped.augments, 0, "a snapshot with no augment"); eq(why, nil, "no why")
    -- a full snapshot gives no why
    SC = fresh()
    s, why = SC.snapshot()
    eq(s ~= nil, true, "a snapshot"); eq(why, nil, "no why")
end)

test("snapshot is nil, with no why, when one augment slot or one item cannot be read while the rest can", function()
    local function skipped(what, setup)
        local SC, Hook = fresh()
        eq(SC.snapshot() ~= nil, true, what .. ": a snapshot before")
        setup()
        local s, why = SC.snapshot()
        eq(s, nil, what .. ": that sample skipped (what was not read is not taken as empty)")
        eq(why, nil, what .. ": no why")
        eq(Hook.info().errors, 0, what .. ": no error of the mod's own")
    end
    skipped("a slot gives nothing", function() G.slots[10][2] = nil end)
    skipped("one slot read, the others not", function() G.slots[10] = { [3] = AUGMENT_ID.Job10_04 } end)
    skipped("a slot gives no number", function() G.slots[10][4] = "Job04_00" end)
    skipped("an item's id cannot be read", function()
        local calc = G.calcs[2][2]
        local get = calc.methods.getEquipData
        calc.methods.getEquipData = function(...)
            local roe = get(...)
            roe.fields.Data.fields.Equips.items[1].methods.get_ItemId = function() return nil end
            return roe
        end
    end)
    -- an id the enum does not name is read: kept as its number, the snapshot taken
    local SC = fresh()
    G.slots[10][1] = 999
    local s = SC.snapshot()
    eq(s ~= nil and T.str(s.equipped.augments), "999 Job01_01 Job05_00 Job10_04", "an unnamed id: a snapshot")
end)

test("snapshot: the Equips array is read by get_elements (get_Item gives nil in the game)", function()
    local SC = fresh()
    G.equips = { 3502 }
    eq(T.str(SC.snapshot().equipped.rings), "3502", "read")
    G.equips = {}
    local e = SC.snapshot().equipped
    eq(#e.rings + #e.items, 0, "nothing equipped")
end)

test("snapshot is nil when the player, his calculator, his status, the Equips, his vocation or his augments "
    .. "cannot be read", function()
    local function none(what, setup)
        local SC, Hook = fresh()
        setup()
        eq(SC.snapshot(), nil, what)
        eq(Hook.info().errors, 0, what .. ": no error")
    end
    none("no character manager", function() R.singleton("app.CharacterManager", nil) end)
    none("no player", function() G.player = nil end)
    none("no CharaID", function() G.player.chara_id = nil end)
    none("no calculator for him", function() table.remove(G.calcs, 2) end)
    none("no status", function() G.status = nil end)
    none("no basic status", function() G.basic = nil end)
    none("no Equips", function() G.equips = nil end)
    none("no vocation", function() G.job = nil end)
    none("None", function() G.job = 0 end)
    none("no AbilityContext", function() G.ac = nil end)
end)

test("snapshot: a number that cannot be read is left out, the rest is kept", function()
    local SC = fresh()
    G.hp = { 0 / 0, nil }
    G.weight = { math.huge, 60.0 }
    G.eq = nil
    G.status[bf("ArmorAttack")] = nil
    G.basic[bf("Blow")] = 0 / 0
    local s = SC.snapshot()
    eq(s.numbers.hp_max, nil, "a NaN"); eq(s.numbers.hp_base, nil, "none")
    eq(s.numbers.weight_max, nil, "not finite"); eq(s.numbers.weight_base, 60, "the base")
    eq(s.numbers["total.ArmorAttack"], nil, "a part missing"); eq(s.numbers["basic.Blow"], nil, "a NaN part")
    eq(s.numbers["eq.FireDefence"], nil, "no EquipParam: no sums")
    eq(s.numbers["total.BasicDefence"], 380, "the rest"); eq(T.str(s.equipped.rings), "3502 10223", "the equipment")
end)

test("snapshot only reads: the calc* methods and getters, never a setter", function()
    local SC = fresh()
    SC.snapshot()
    local sigs, seen = {}, {}
    for _, c in ipairs(R.calls) do
        if not seen[c.sig] then
            seen[c.sig] = true
            sigs[#sigs + 1] = c.sig
        end
    end
    table.sort(sigs)
    eq(table.concat(sigs, " "), "GetEnumerator MoveNext calcAttackDefenceWithEquipmentAndBuff "
        .. "calcBasicAttackDefence calcBasicMaxHP "
        .. "calcBasicMaxStamina calcBasicMaxWeight calcMaxHPWithEquipmentAndBuff calcMaxStaminaWithEquipmentAndBuff "
        .. "calcMaxWeightWithBuff getAbility(app.Character.JobEnum, app.AbilityContext.AbilitySlot) getEquipData "
        .. "get_CharaID get_Current get_Human get_ItemId get_JobContext get_ManualPlayer "
        .. "get_PlayerStatusCalculatorHolder", "the calls made")
end)

test("fakes that raise: nil, or that part left out; nothing raises, no error of the mod's own", function()
    local function case(what, setup, check)
        local SC, Hook = fresh()
        setup()
        local ok, s = pcall(SC.snapshot)
        assert(ok, what .. ": " .. tostring(s))
        check(s)
        eq(Hook.info().errors, 0, what .. ": no error of the mod's own")
    end
    case("the calculator", function() G.calcs[2][2].poison = true end,
        function(s) eq(s, nil, "the calculator raises") end)
    case("the AbilityContext", function() G.ac.poison = true end,
        function(s) eq(s, nil, "no augment slot read: the augments unknown, no snapshot") end)
    case("the Equips array", function()
        local calc = G.calcs[2][2]
        local get = calc.methods.getEquipData
        calc.methods.getEquipData = function(...)
            local roe = get(...)
            -- the stub's get_elements does not look at `poison`: this one raises
            roe.fields.Data.fields.Equips.get_elements = function() error("get_elements raised") end
            return roe
        end
    end, function(s) eq(s, nil, "get_elements raises") end)
    case("an item slot", function()
        G.equips = { 3502, 2001 }
        local calc = G.calcs[2][2]
        local get = calc.methods.getEquipData
        calc.methods.getEquipData = function(...)
            local roe = get(...)
            roe.fields.Data.fields.Equips.items[2].poison = true
            return roe
        end
    end, function(s) eq(s, nil, "an item slot not read: no snapshot") end)
    case("the EquipParam", function()
        local calc = G.calcs[2][2]
        local get = calc.methods.getEquipData
        calc.methods.getEquipData = function(...)
            local roe = get(...)
            roe.fields.Data.fields._EqParam.poison = true
            return roe
        end
    end, function(s)
        eq(s.numbers["eq.FireDefence"], nil, "no sums"); eq(s.numbers["total.BasicDefence"], 380, "the rest")
    end)
    case("the type's fields", function()
        R.type("app.EquipParam").fields = setmetatable({}, { __len = function() error("fields raised") end,
            __index = function() error("fields raised") end })
    end, function(s) eq(s.numbers["eq.FireDefence"], nil, "no sums"); eq(s.numbers.hp_max, 3100, "the rest") end)
end)

test("a raise outside Safe is counted at stat_check once and gives nil", function()
    local SC, Hook = fresh()
    require("DD2DamageMeter/game/hidden_stats").ring = function() error("ring raised") end
    eq(SC.snapshot(), nil, "nil")
    local info = Hook.info()
    eq(info.errors, 1, "one error")
    local where = tostring(info.last_error)
    eq(where:find("^stat_check: ") ~= nil, true, "at stat_check: " .. where)
end)

T.finish()
