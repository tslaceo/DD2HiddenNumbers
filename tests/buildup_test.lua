package.path = "mod/reframework/autorun/?.lua;tests/?.lua;" .. package.path

local T = require("testlib")
local test, eq, near = T.test, T.eq, T.near
local R = require("stubs/reframework")
local names_game = require("DD2DamageMeter/game/names_game")
local Buildup = require("DD2DamageMeter/game/buildup")

local ENUM = "app.StatusConditionDef.StatusConditionEnum"

local function world()
    R.new()
    R.enum(ENUM, { None = 0, Poison = 1, Faint = 3, FireSpread = 5, VirulentPoison = 7, Frostbite = 8,
        Electric = 13, EnchantFire = 15, EnchantIce = 16, EnchantThunder = 17 })
    names_game.reset()
    Buildup.reset()
end

-- An app.StatusConditionInfo: o.id, o.value (read anew each call, so a test changes it), o.max (EnduranceMax of the
-- second action param; the first has none), o.resist, o.level; o.active (get_IsActive), o.remain (get_ActiveRemainTime,
-- frames; -1 by default), o.timer = { n, frames }: ActiveTimerMaxFrame of the n-th action param (the list as long as
-- needed; the first param has an ActiveTimerMaxFrame of 0 when it is not the n-th, the others none).
local function info(o)
    local fields = { { _Rate = 1 }, { EnduranceMax = o.max } }
    if o.timer then
        fields[1].ActiveTimerMaxFrame = 0
        for i = #fields + 1, o.timer[1] do fields[i] = { _Rate = 1 } end
        fields[o.timer[1]].ActiveTimerMaxFrame = o.timer[2]
    end
    local params = {}
    for i, f in ipairs(fields) do params[i] = R.object("app.StatusConditionActionParam", f) end
    local res = R.object("app.StatusConditionParamRes", { _ActionParamList = R.list(params,
        "System.Collections.Generic.List`1<app.StatusConditionActionParam>") })
    return R.object("app.StatusConditionInfo", {}, {
        get_StatusConditionId = function() return o.id end,
        getEnduranceValue = function() return o.value end,
        get_ParamRes = function() return res end,
        get_ResistanceRate = function() return o.resist end,
        get_ImmunityLevel = function() return o.level end,
        get_IsActive = function() return o.active == true end,
        get_ActiveRemainTime = function() return o.remain or -1 end,
    })
end

-- A boss whose StatusConditionCtrl lists these statuses (each made by info); flag its EnableStatusConditionFlag (none
-- by default).
local function boss(statuses, go, flag)
    local c = R.character{ go = go or "ch250000_00", hp = 40000, max_hp = 90000 }
    local infos = {}
    for i, o in ipairs(statuses) do infos[i] = info(o) end
    c.ctrl = R.object("app.StatusConditionCtrl", { StatusConditionInfoList = R.list(infos,
        "System.Collections.Generic.List`1<app.StatusConditionInfo>"), EnableStatusConditionFlag = flag })
    c.methods.get_StatusConditionCtrl = function() return c.ctrl end
    return c
end

-- A read's rows as "name value/max hits" joined by " | "; an active row "name active remain/duration".
local function text(rows)
    if rows == nil then return "nil" end
    local out = {}
    for _, r in ipairs(rows) do
        if r.active then
            out[#out + 1] = tostring(r.name or r.id) .. " active " .. tostring(r.remain) .. "/" .. tostring(r.duration)
        else
            out[#out + 1] = tostring(r.name or r.id) .. " " .. tostring(r.value) .. "/" .. tostring(r.max) .. " "
                .. tostring(r.hits)
        end
    end
    return table.concat(out, " | ")
end

-- A row's every field, "key=value" sorted and joined by " ".
local function fields(row)
    local out = {}
    for k, v in pairs(row) do out[#out + 1] = tostring(k) .. "=" .. tostring(v) end
    table.sort(out)
    return table.concat(out, " ")
end

test("the statuses building, in id order: value and threshold; those at 0 left out", function()
    world()
    local c = boss({ { id = 5, value = 1800, max = 5000 }, { id = 1, value = 0, max = 3000 },
        { id = 3, value = 313, max = 1400 }, { id = 8, value = 0, max = 800 } })
    local rows = Buildup.read(c, 1)
    eq(text(rows), "Faint 313/1400 nil | FireSpread 1800/5000 nil", "Faint (3) before FireSpread (5), no hits yet")
    eq(rows[1].id, 3, "its StatusConditionEnum value")
    eq(Buildup.READ_EVERY, 0.1, "READ_EVERY"); eq(Buildup.INCREMENTS, 5, "INCREMENTS")
end)

test("the threshold is EnduranceMax of the action param that has it; none without one", function()
    world()
    local o = { id = 3, value = 200, max = 1400 }
    local c = boss({ o, { id = 1, value = 50 } })
    local rows = Buildup.read(c, 1)
    eq(rows[1].max, nil, "Poison: no param with EnduranceMax, no threshold")
    eq(rows[2].max, 1400, "Faint: the second param's EnduranceMax")
    eq(rows[2].hits, nil, "and no hits")
end)

test("hits left from the rises: +100 three times, max 1400 at 313: ceil(1087 / 100) = 11", function()
    world()
    local o = { id = 3, value = 13, max = 1400 }
    local c = boss({ o })
    eq(Buildup.read(c, 1)[1].hits, nil, "the first read: no rise yet")
    for i, v in ipairs({ 113, 213, 313 }) do
        o.value = v
        local rows = Buildup.read(c, 1 + i * 0.2)
        if i < 3 then eq(rows[1].hits ~= nil, true, "a rise: hits") end
    end
    eq(Buildup.read(c, 2)[1].hits, 11, "11 hits")
end)

test("a falling value (the decay) adds no rise; the average is of the last 5 rises", function()
    world()
    local o = { id = 3, value = 0, max = 1400 }
    local c = boss({ o })
    local t = 1
    local function at(v)
        o.value, t = v, t + 0.2
        return Buildup.read(c, t)
    end
    at(0)
    at(100)                                       -- +100
    eq(at(94)[1].hits, math.ceil((1400 - 94) / 100), "decay: still the one rise of 100")
    eq(at(88)[1].hits, 14, "ceil(1312 / 100)")
    -- five rises of 30 push the 100 out: the average of the last 5 is 30
    local v = 88
    for _ = 1, 5 do
        v = v + 30
        at(v)
    end
    eq(at(v)[1].hits, math.ceil((1400 - v) / 30), "the last five rises, 30 each")
    -- back to 0 (the status set off, or it decayed away): no row; the next rise counts from 0
    eq(text(at(0)), "", "at 0: no row")
    eq(at(50)[1].hits, math.ceil((1400 - 50) / ((30 * 4 + 50) / 5)), "the rise from 0 is one of the last 5")
    -- at or over the threshold: no hits left to name
    eq(at(1400)[1].hits, nil, "at the threshold: none")
end)

test("read at most every 0.1 s: the last answer in between; another character is read at once", function()
    world()
    local o = { id = 3, value = 100, max = 1400 }
    local c = boss({ o })
    eq(Buildup.read(c, 1)[1].value, 100, "read")
    o.value = 200
    eq(Buildup.read(c, 1.05)[1].value, 100, "0.05 s later: the last answer")
    eq(Buildup.read(c, 1.1)[1].value, 200, "0.1 s later: read again")
    local other = boss({ { id = 5, value = 700, max = 5000 } }, "ch250001_00")
    eq(Buildup.read(other, 1.12)[1].name, "FireSpread", "another boss: read now")
    o.value = 300
    eq(Buildup.read(c, 1.13)[1].value, 300, "the first again: read now too")
    eq(Buildup.read(c, nil)[1].value, 300, "no time: its last answer, nothing read")
    -- a clock that went back reads again
    o.value = 400
    eq(Buildup.read(c, 0.5)[1].value, 400, "t went back: read")
end)

test("the rises are kept per character and status", function()
    world()
    local a, b = { id = 3, value = 0, max = 1000 }, { id = 3, value = 0, max = 1000 }
    local ca, cb = boss({ a }, "ch250000_00"), boss({ b }, "ch250001_00")
    Buildup.read(ca, 1); Buildup.read(cb, 1)
    a.value, b.value = 100, 500
    eq(Buildup.read(ca, 2)[1].hits, 9, "the first boss: rises of 100, ceil(900 / 100)")
    eq(Buildup.read(cb, 2)[1].hits, 1, "the second: a rise of 500, ceil(500 / 500)")
end)

test("the resistance and immunity level are read with the row; the name is nil for an id the enum lacks", function()
    world()
    local rows = Buildup.read(boss({ { id = 3, value = 10, max = 100, resist = 0.2, level = 1 },
        { id = 42, value = 5, max = 100 } }), 1)
    eq(rows[1].resistance, 0.2, "ResistanceRate"); eq(rows[1].immunity, 1, "ImmunityLevel")
    eq(rows[2].id, 42, "an id the enum has no member for"); eq(rows[2].name, nil, "no name")
end)

test("unreadable: nil without raising; reset forgets the rises", function()
    world()
    eq(Buildup.read(nil, 1), nil, "no character")
    local c = R.character{ go = "ch250000_00" }
    eq(Buildup.read(c, 1), nil, "no StatusConditionCtrl")
    c.methods.get_StatusConditionCtrl = function() return R.object("app.StatusConditionCtrl", {}) end
    eq(Buildup.read(c, 2), nil, "no list")
    local broken = R.object("app.StatusConditionInfo", {}, {
        get_StatusConditionId = function() error("gone") end,
        getEnduranceValue = function() error("gone") end,
    })
    c.methods.get_StatusConditionCtrl = function()
        return R.object("app.StatusConditionCtrl", { StatusConditionInfoList = R.list({ broken, false, 5 }) })
    end
    eq(Buildup.read(c, 3), nil, "entries that cannot be read")
    c.methods.get_StatusConditionCtrl = function() error("destroyed") end
    eq(Buildup.read(c, 4), nil, "the controller raises")
    -- a value that is not a number is left out
    local ok = boss({ { id = 3, value = "x", max = 100 }, { id = 5, value = 0 / 0, max = 100 },
        { id = 1, value = 20, max = 100 } })
    eq(text(Buildup.read(ok, 5)), "Poison 20/100 nil", "the finite value only")
    -- reset: the rises forgotten
    local o = { id = 3, value = 0, max = 1000 }
    local d = boss({ o }, "ch250002_00")
    Buildup.read(d, 10)
    o.value = 100
    eq(Buildup.read(d, 11)[1].hits, 9, "a rise")
    Buildup.reset()
    eq(Buildup.read(d, 12)[1].hits, nil, "reset: none")
end)

-- The poise ------------------------------------------------------------------------------------------------

local LEAN = "getDmgReactionLeanPoint(System.Int32)"
local BLOWN = "getDmgReactionBlownPoint(System.Int32)"
local THRESHOLD = "getNextThreshold(System.Boolean, System.Int32)"

-- The boss's app.HitController with Fimbul's thresholds (lean 65 000, blown 195 000): o.lean, o.blown its points (read
-- anew each call); o.index the one index that answers (-1 by default), o.asked the indexes asked, in order.
local function hit_ctrl(o)
    o.asked = {}
    local function at(i, v)
        o.asked[#o.asked + 1] = i
        if i == (o.index or -1) then return v end
        return nil
    end
    return R.object("app.HitController", {}, {
        [LEAN] = function(_, i) return at(i, o.lean) end,
        [BLOWN] = function(_, i) return at(i, o.blown) end,
        [THRESHOLD] = function(_, blown, i)
            if i ~= (o.index or -1) then return nil end
            return blown and 195000 or 65000
        end,
    })
end

test("the stagger and knock-down rows from the HitController, before the statuses, each while above 0", function()
    world()
    local p = { lean = 41841, blown = 41841 }
    local c, hc = boss({ { id = 3, value = 313, max = 1400 } }), hit_ctrl(p)
    local rows = Buildup.read(c, 1, hc)
    eq(text(rows), "lean 41841/65000 nil | blown 41841/195000 nil | Faint 313/1400 nil",
        "lean, then blown, then the statuses")
    eq(rows[1].id, "lean", "the id lean"); eq(rows[2].id, "blown", "and blown"); eq(rows[1].name, nil, "no status name")
    p.lean = 0
    eq(text(Buildup.read(c, 2, hc)), "blown 41841/195000 nil | Faint 313/1400 nil", "lean at 0: no row")
    p.blown = 0
    eq(text(Buildup.read(c, 3, hc)), "Faint 313/1400 nil", "both at 0: the statuses alone")
end)

test("the poise at index -1; when -1 gives nothing, at 0", function()
    world()
    local p = { lean = 900, blown = 900 }
    local c = boss({})
    local rows = Buildup.read(c, 1, hit_ctrl(p))
    eq(text(rows), "lean 900/65000 nil | blown 900/195000 nil", "at -1")
    eq(table.concat(p.asked, ","), "-1,-1", "-1 asked, once for each")
    p.index = 0
    rows = Buildup.read(c, 2, hit_ctrl(p))
    eq(text(rows), "lean 900/65000 nil | blown 900/195000 nil", "-1 gives nothing: at 0")
    eq(table.concat(p.asked, ","), "-1,0,-1,0", "-1, then 0")
    p.index = 7
    eq(Buildup.read(c, 3, hit_ctrl(p)), nil, "neither, and no status in the list: nothing read, nil")
end)

test("the hits left to a stagger from its rises; a reaction's reset to 0 drops the row", function()
    world()
    local p = { lean = 1000, blown = 1000 }
    local c, hc = boss({}), hit_ctrl(p)
    local t = 1
    local function at(lean, blown)
        p.lean, p.blown, t = lean, blown or lean, t + 0.2
        return Buildup.read(c, t, hc)
    end
    at(1000)
    at(2000)
    local rows = at(3000)
    eq(rows[1].hits, math.ceil((65000 - 3000) / 1000), "two rises of 1000: 62")
    eq(rows[2].hits, nil, "the knock-down: no estimate, its rises notwithstanding")
    eq(at(2994)[1].hits, math.ceil((65000 - 2994) / 1000), "the drain adds no rise")
    -- the boss staggers: the points back to 0, the row gone; the next rises count from 0
    eq(text(at(0, 2994)), "blown 2994/195000 nil", "the lean at 0: its row gone")
    rows = at(500, 3494)
    eq(rows[1].hits, math.ceil((65000 - 500) / ((1000 + 1000 + 500) / 3)), "the rise from 0 one of the last 5")
end)

test("no HitController, the statuses alone; a HitController alone, the poise rows; neither, nil", function()
    world()
    local c = boss({ { id = 3, value = 313, max = 1400 } })
    eq(text(Buildup.read(c, 1)), "Faint 313/1400 nil", "no HitController")
    local bare = R.character{ go = "ch250001_00" }
    eq(text(Buildup.read(bare, 1, hit_ctrl({ lean = 10, blown = 10 }))), "lean 10/65000 nil | blown 10/195000 nil",
        "no status list: the poise rows")
    eq(Buildup.read(R.character{ go = "ch250002_00" }, 1, R.object("app.HitController", {})), nil, "neither: nil")
    local broken = R.object("app.HitController", {}, { [LEAN] = function() error("gone") end })
    eq(text(Buildup.read(c, 2, broken)), "Faint 313/1400 nil", "a HitController that raises: no poise row")
end)

-- The time left ---------------------------------------------------------------------------------------------

-- Faint on the snow ogre (read in the game): set off, 477.94 frames left of its 480 (the third param's).
local function ogre_faint(value)
    return { id = 3, value = value, max = 1400, active = true, remain = 477.94, timer = { 3, 480 }, resist = 0.2,
        level = 1 }
end

test("an active status's row: the time left and the duration in seconds, at the read's t", function()
    world()
    local rows = Buildup.read(boss({ ogre_faint(0) }), 5)
    eq(#rows, 1, "one row")
    local r = rows[1]
    eq(r.id, 3, "its id"); eq(r.name, "Faint", "its name"); eq(r.active, true, "active")
    near(r.remain, 477.94 / 60, 1e-9, "477.94 frames: about 7.97 s")
    eq(r.duration, 8, "ActiveTimerMaxFrame 480: 8 s"); eq(r.at, 5, "the t of the read")
    eq(r.resistance, 0.2, "the resistance as now"); eq(r.immunity, 1, "the immunity level as now")
    eq(r.value, nil, "no buildup value: an active row does not stand on it"); eq(r.max, nil, "nor a threshold")
    eq(r.hits, nil, "nor hits")
end)

test("the buildup at the threshold while active gives the same active row, one row, not two", function()
    world()
    local at_0 = Buildup.read(boss({ ogre_faint(0) }, "ch250000_00"), 5)
    local at_max = Buildup.read(boss({ ogre_faint(1400) }, "ch250001_00"), 5)
    eq(#at_max, 1, "one row")
    eq(fields(at_max[1]), fields(at_0[1]), "the same row as at 0")
    eq(fields(at_max[1]):find("value", 1, true), nil, "no value in it")
end)

test("active with no time left (-1, as EnchantThunder was) gives no timer: no row at 0, the building row above it",
    function()
    world()
    -- not an enchant (those have no row at all): Poison active at -1, as the probe saw EnchantThunder
    local poison = { id = 1, value = 0, active = true, remain = -1, timer = { 2, 3600 } }
    eq(text(Buildup.read(boss({ poison }), 1)), "", "active at -1, its buildup 0: no row")
    poison.remain = 0
    eq(text(Buildup.read(boss({ poison }, "ch250001_00"), 1)), "", "0 frames left: none either")
    local faint = { id = 3, value = 50, max = 1400, active = true, remain = -1, timer = { 3, 480 } }
    local rows = Buildup.read(boss({ faint }, "ch250002_00"), 1)
    eq(text(rows), "Faint 50/1400 nil", "active at -1 with buildup: the building row")
    eq(rows[1].active, nil, "not active")
end)

test("the status ends: back to the building row while its buildup is above 0, else none", function()
    world()
    local o = ogre_faint(0)
    local c = boss({ o })
    eq(text(Buildup.read(c, 1)), "Faint active " .. tostring(477.94 / 60) .. "/" .. tostring(480 / 60), "active")
    o.remain = 60
    eq(Buildup.read(c, 1.2)[1].remain, 1, "60 frames: 1 s")
    eq(Buildup.read(c, 1.2)[1].at, 1.2, "at the new read")
    o.active, o.remain, o.value = false, -1, 300
    local rows = Buildup.read(c, 1.4)
    eq(text(rows), "Faint 300/1400 4", "over, its buildup 300: the building row (a rise of 300 from the 0 read)")
    local r = rows[1]
    eq(r.active, nil, "inactive: active nil"); eq(r.remain, nil, "no remain"); eq(r.duration, nil, "no duration")
    eq(r.at, nil, "no at")
    o.value = 0
    eq(text(Buildup.read(c, 1.6)), "", "over at 0: no row")
end)

test("the duration is ActiveTimerMaxFrame of the first param that has one above 0; nil without one", function()
    for _, n in ipairs({ 1, 2, 3, 4, 6 }) do
        world()
        local o = { id = 3, value = 0, max = 1400, active = true, remain = 100, timer = { n, 600 } }
        local rows = Buildup.read(boss({ o }), 1)
        eq(rows[1].duration, 10, "600 frames on param " .. n .. ": 10 s")
        -- the threshold, from the same pass, once the status is over
        o.active, o.remain, o.value = false, -1, 300
        eq(Buildup.read(boss({ o }, "ch250001_00"), 1)[1].max, 1400, "param " .. n .. ": EnduranceMax still found")
    end
    world()
    local rows = Buildup.read(boss({ { id = 3, value = 0, max = 1400, active = true, remain = 100 } }), 1)
    eq(rows[1].active, true, "active with time")
    eq(rows[1].duration, nil, "no param with ActiveTimerMaxFrame: no duration")
    world()
    Buildup.read(boss({ ogre_faint(0) }), 1)
    eq(#R.calls_of("get_ParamRes"), 1, "one pass over the params: get_ParamRes asked once for the row")
end)

test("a status's rises are forgotten when its immunity level changes, kept while it stays", function()
    world()
    local o = { id = 3, value = 0, max = 1400, level = 0, timer = { 3, 480 } }
    local c = boss({ o })
    local t = 1
    local function at(v, level)
        o.value, t = v, t + 0.2
        if level ~= nil then o.level = level end
        return Buildup.read(c, t)
    end
    at(0)
    at(100)
    eq(at(200)[1].hits, 12, "two rises of 100 at level 0: ceil(1200 / 100)")
    eq(at(250, 1)[1].hits, nil, "the level 1: the rises forgotten, this read's too")
    eq(at(300)[1].hits, math.ceil(1100 / 50), "the level stays 1: the next rise kept")
    eq(at(400)[1].hits, math.ceil(1000 / 75), "and the one after: the average of 50 and 100")
    o.level = nil
    eq(at(500)[1].hits, math.ceil(900 / ((50 + 100 + 100) / 3)), "an unreadable level forgets nothing")
    eq(at(600, 1)[1].hits, math.ceil(800 / ((50 + 100 + 100 + 100) / 4)), "1 again, as last read: nothing forgotten")
    -- through a trigger: building at level 0, set off (level 1, its buildup at 0), over and building again: the hits
    -- left from the rises after the trigger alone
    world()
    o = { id = 3, value = 0, max = 1400, level = 0, timer = { 3, 480 } }
    c, t = boss({ o }), 1
    at(0)
    at(100)
    eq(at(200)[1].hits, 12, "two rises of 100")
    o.active, o.remain = true, 400
    eq(at(0, 1)[1].active, true, "set off: the active row")
    o.active, o.remain = false, -1
    eq(at(60)[1].hits, math.ceil(1340 / 60), "over: the one rise of 60 since, not the 100s before")
end)

-- An enemy's own enchant -----------------------------------------------------------------------------------

test("an enemy's own enchant (an Enchant* status) gives no row, active or building", function()
    world()
    -- the lesser demon's ice aura (read in the game): EnchantIce active, 3600 frames left the whole fight
    local ice = { id = 16, value = 0, active = true, remain = 3600, timer = { 2, 3600 } }
    eq(text(Buildup.read(boss({ ice }), 1)), "", "EnchantIce active at 3600: no row")
    eq(text(Buildup.read(boss({ { id = 15, value = 500, max = 1000 } }, "ch250001_00"), 1)), "",
        "EnchantFire building at 500: no row")
    eq(text(Buildup.read(boss({ { id = 17, value = 0, active = true, remain = 600, timer = { 2, 600 } } },
        "ch250002_00"), 1)), "", "EnchantThunder with time left: no row")
    eq(text(Buildup.read(boss({ { id = 42, value = 5, max = 100 } }, "ch250003_00"), 1)), "42 5/100 nil",
        "a status with no enum name: shown as before")
end)

test("the other rows of a read with enchants are unaffected", function()
    world()
    local c = boss({ { id = 16, value = 0, active = true, remain = 3600, timer = { 2, 3600 } },
        { id = 15, value = 500, max = 1000 }, ogre_faint(0), { id = 5, value = 1800, max = 5000 },
        { id = 42, value = 5, max = 100 } })
    local rows = Buildup.read(c, 1, hit_ctrl({ lean = 900, blown = 900 }))
    eq(text(rows), "lean 900/65000 nil | blown 900/195000 nil | Faint active " .. tostring(477.94 / 60) .. "/"
        .. tostring(480 / 60) .. " | FireSpread 1800/5000 nil | 42 5/100 nil",
        "the poise, Faint in effect, burning building and the nameless status; no enchant")
end)

-- A status the boss is immune to -------------------------------------------------------------------------

local BARBATOS = 8392704 -- bits 12 and 23 (read in the game): no buildup status enabled
local FIMBUL = 7422      -- bits 1-7 and 10-12: off for Frostbite 8, Freeze 9 and Electric 13

test("Barbatos's flag: burning gives no row, building or set off", function()
    world()
    local fire = { id = 5, value = 900, max = 4000, timer = { 3, 900 } }
    eq(text(Buildup.read(boss({ fire }, "ch250000_00", BARBATOS), 1)), "", "FireSpread at 900 / 4000: no row")
    fire.value, fire.active, fire.remain = 0, true, 600
    eq(text(Buildup.read(boss({ fire }, "ch250001_00", BARBATOS), 1)), "", "FireSpread set off, 10 s left: no row")
    -- an id outside 0..62 has no bit: shown
    eq(text(Buildup.read(boss({ { id = 63, value = 5, max = 100 }, { id = -1, value = 6, max = 100 } }, "ch250002_00",
        BARBATOS), 1)), "-1 6/100 nil | 63 5/100 nil", "ids -1 and 63: no bit tested, shown")
end)

test("Fimbul's flag: Faint shown, Electric not; the poise rows unaffected", function()
    world()
    local c = boss({ { id = 3, value = 313, max = 1400 }, { id = 13, value = 40, max = 300 } }, nil, FIMBUL)
    eq(text(Buildup.read(c, 1, hit_ctrl({ lean = 900, blown = 900 }))),
        "lean 900/65000 nil | blown 900/195000 nil | Faint 313/1400 nil", "Faint (bit 3 on) shown, Electric (13) not")
    -- the flag boxed, as the game may give an enum: read with its value__
    local boxed = R.object("app.StatusConditionDef.StatusConditionFlag", { value__ = FIMBUL })
    eq(text(Buildup.read(boss({ { id = 3, value = 313, max = 1400 }, { id = 13, value = 40, max = 300 } },
        "ch250001_00", boxed), 1)), "Faint 313/1400 nil", "a boxed flag: the same")
    -- every status off: the poise rows alone
    eq(text(Buildup.read(boss({ { id = 3, value = 313, max = 1400 } }, "ch250002_00", BARBATOS), 1,
        hit_ctrl({ lean = 900, blown = 900 }))), "lean 900/65000 nil | blown 900/195000 nil",
        "Barbatos: the poise only")
end)

test("an unreadable flag (nil, not a number, not whole) hides nothing", function()
    world()
    local statuses = { { id = 3, value = 313, max = 1400 }, { id = 13, value = 40, max = 300 } }
    for i, flag in ipairs({ false, "7422", 7422.5, {} }) do
        local f = flag
        if f == false then f = nil end
        eq(text(Buildup.read(boss(statuses, "ch25000" .. i .. "_00", f), 1)),
            "Faint 313/1400 nil | Electric 40/300 nil", "flag " .. tostring(f) .. ": every status shown")
    end
end)

test("a hidden status's rises are not kept: shown again, its hits start from its next rise", function()
    world()
    local o = { id = 13, value = 0, max = 300 }
    local c = boss({ o }, nil, FIMBUL)
    local t = 1
    for _, v in ipairs({ 0, 100, 200 }) do
        o.value, t = v, t + 0.2
        eq(text(Buildup.read(c, t)), "", "Electric at " .. v .. " under Fimbul's flag: no row")
    end
    c.ctrl.fields.EnableStatusConditionFlag = nil -- the flag unreadable now
    o.value = 250
    eq(Buildup.read(c, t + 0.2)[1].hits, nil, "its first read shown: no rise kept from the hidden reads")
    o.value = 270
    eq(Buildup.read(c, t + 0.4)[1].hits, math.ceil(30 / 20), "the next rise counts")
end)

T.finish()
