package.path = "mod/reframework/autorun/?.lua;tests/?.lua;" .. package.path

local T = require("testlib")
local test, eq, near = T.test, T.eq, T.near
local R = require("stubs/reframework")

local STATIC = { static = true }
local FIND = "findComponents(System.Type)"
local GET_COMPONENT = "getComponent(System.Type)"

local G -- the scene of the current test: G.guis, the GUIs findComponents gives

-- A fresh game and a fresh reader; the scene manager answers with G's scene. o.boss: the boss bar's component type
-- exists too.
local function fresh(o)
    for name in pairs(package.loaded) do
        if name:find("^DD2DamageMeter/") then package.loaded[name] = nil end
    end
    DD2DM_HOOKS = nil
    R.new()
    G = { guis = {} }
    R.type("via.gui.GUI")
    R.type("app.ui020601")
    if o and o.boss then R.type("app.ui020501") end
    G.scene = R.object("via.Scene", {}, {
        [FIND] = function(_, t)
            if t == nil or t.runtime_type ~= "via.gui.GUI" then return nil end
            local arr = R.object("via.gui.GUI[]")
            arr.items = G.guis
            return arr
        end,
    })
    R.method("via.SceneManager", "get_CurrentScene", function() return G.scene end, STATIC)
    R.native("via.SceneManager", R.object("via.SceneManager"))
    return require("DD2DamageMeter/game/gauges"), require("DD2DamageMeter/game/hook")
end

-- A GUI on a GameObject called `name` (default "ui020601") with an app.ui020601 component (none with o.no_comp):
-- drawn (o.drawn, default true), hostile (o.hostile, default true), its character (o.chara, default a new one) and
-- its All panel at (o.x, o.y) (default 960, 400). The returned bar has its parts: bar.gui, bar.go, bar.comp,
-- bar.panel, and o's values live (bar.o.drawn = false hides it).
local function bar(o)
    o = o or {}
    if o.drawn == nil then o.drawn = true end
    if o.hostile == nil then o.hostile = true end
    local b = { o = o }
    b.chara = o.chara or R.character({ go = "ch220003_00_15", hp = 1000, max_hp = 2000 })
    b.panel = R.object("via.gui.Panel", {}, {
        get_GlobalPosition = function() return o.pos or { x = o.x or 960, y = o.y or 400, z = 0 } end,
    })
    b.comp = R.object("app.ui020601", { CompChara = b.chara, All = b.panel })
    setmetatable(b.comp.fields, { __index = function(_, k)
        if k == "IsHostile" then return o.hostile end
    end })
    b.go = R.object("via.GameObject", {}, {
        get_Name = function() return o.name or "ui020601" end,
        get_DrawSelf = function() return o.drawn end,
        [GET_COMPONENT] = function(_, t)
            if o.no_comp or t == nil or t.runtime_type ~= "app.ui020601" then return nil end
            return b.comp
        end,
    })
    b.gui = R.object("via.gui.GUI", {}, { get_GameObject = function() return b.go end })
    G.guis[#G.guis + 1] = b.gui
    return b
end

local function scans()
    return #R.calls_of(FIND)
end

-- GUI elements from specs { name, pos = { x, y }, size = { w, h }, children = { spec... } }, each linked to its first
-- child (get_Child) and its next sibling (get_Next); a spec's values are read live. specs[name] = the spec, and
-- spec.el its element. Returns the first one.
local function elements(list, specs)
    local first, prev
    for _, sp in ipairs(list) do
        local el
        el = R.object("via.gui.Control", {}, {
            get_Name = function() return sp.name end,
            get_Child = function() return el.child end,
            get_Next = function() return el.next end,
            get_GlobalPosition = function() return sp.pos and { x = sp.pos[1], y = sp.pos[2], z = 0 } end,
            get_Size = function() return sp.size_value or (sp.size and { w = sp.size[1], h = sp.size[2] }) end,
        })
        sp.el = el
        specs[sp.name] = sp
        if sp.children then el.child = elements(sp.children, specs) end
        if prev then prev.next = el else first = el end
        prev = el
    end
    return first
end

-- The bar's elements as the probes saw them on a 3440 × 1440 display: the base among others, under a panel.
local function boss_tree()
    return {
        { name = "pnl_Name" },
        { name = "pnl_Gauge", children = {
            { name = "s9g_Base", pos = { 665.3, 106 }, size = { 776, 7 } },
            { name = "HP", children = { { name = "tex_Startpos", pos = { 1240.9, 106 } } } },
        } },
        { name = "Dot" },
    }
end

-- The boss bar: a GUI on a GameObject named "ui020501" with an app.ui020501 component, drawn (o.drawn, default
-- true), and its All panel over o.tree (default boss_tree()). As in the game, its Target is the boss's GameObject
-- (b.target_go: its getComponent(System.Type) gives the boss's app.Character) and its TargetHitCtrl the boss's
-- app.HitController (b.hc: get_CachedCharacter gives the character); the character is o.target, default a new one
-- (b.target). The returned b has b.gui, b.go, b.comp, b.all, b.target, b.target_go, b.hc, b.specs (by name:
-- b.specs.s9g_Base.pos = ... moves the base), and o's values live (o.no_cached: get_CachedCharacter gives nil;
-- o.no_component: the GameObject has no app.Character).
local function boss(o)
    o = o or {}
    if o.drawn == nil then o.drawn = true end
    local b = { o = o, specs = {} }
    b.target = o.target or R.character({ go = "ch250000_00", hp = 40000, max_hp = 90000 })
    b.target_go = R.object("via.GameObject", {}, {
        get_Name = function() return "ch250000_00" end,
        [GET_COMPONENT] = function(_, t)
            if o.no_component or t == nil or t.runtime_type ~= "app.Character" then return nil end
            return b.target
        end,
    })
    b.hc = R.object("app.HitController", {}, {
        get_CachedCharacter = function() if not o.no_cached then return b.target end end,
    })
    local first = elements(o.tree or boss_tree(), b.specs)
    b.all = R.object("via.gui.Panel", {}, {
        get_Name = function() return "PNL_All" end,
        get_Child = function() return first end,
    })
    b.comp = R.object("app.ui020501", { Target = b.target_go, TargetHitCtrl = b.hc, All = b.all })
    b.go = R.object("via.GameObject", {}, {
        get_Name = function() return o.name or "ui020501" end,
        get_DrawSelf = function() return o.drawn end,
        [GET_COMPONENT] = function(_, t)
            if t == nil or t.runtime_type ~= "app.ui020501" then return nil end
            return b.comp
        end,
    })
    b.gui = R.object("via.gui.GUI", {}, { get_GameObject = function() return b.go end })
    G.guis[#G.guis + 1] = b.gui
    return b
end

-- The calls that walk the bar's elements.
local function walks()
    return #R.calls_of("get_Child") + #R.calls_of("get_Next")
end

test("only the ui020601 GUIs with their component are kept; the scene is looked through about once a second", function()
    local gauges = fresh()
    local a = bar({ x = 100, y = 200 })
    bar({ name = "ui020101" })            -- another GUI
    bar({ no_comp = true })               -- a ui020601 without the component
    local b = bar({ x = 300, y = 400 })
    local list = gauges.shown(10)
    eq(scans(), 1, "the scene is looked through")
    eq(#list, 2, "two bars")
    eq(list[1].character, a.chara, "the first bar's character"); eq(list[1].x, 100, "x"); eq(list[1].y, 200, "y")
    eq(list[2].character, b.chara, "the second's"); eq(list[2].x, 300, "x"); eq(list[2].y, 400, "y")
    eq(gauges.count(), 2, "two kept")
    -- within the second the kept bars are read again, the scene is not
    local c = bar({ x = 500 })
    eq(#gauges.shown(10.5), 2, "a new GUI is not seen yet")
    eq(#gauges.shown(10.99), 2, "nor at 0.99 s")
    eq(scans(), 1, "one look in that second")
    local names = #R.calls_of("get_Name")
    gauges.shown(10.99)
    eq(#R.calls_of("get_Name"), names, "no GameObject's name asked between the looks")
    list = gauges.shown(11)
    eq(scans(), 2, "a second later: again")
    eq(#list, 3, "the new one is there")
    eq(list[3].character, c.chara, "in the scene's order")
    -- a GUI gone from the scene is gone at the next look
    table.remove(G.guis, 1)
    eq(#gauges.shown(11.5), 3, "still kept until the next look")
    eq(#gauges.shown(12), 2, "then gone")
    eq(scans(), 3, "three looks in all")
end)

test("only the bars drawn now and hostile, with their character and centre", function()
    local gauges = fresh()
    local a = bar({ x = 960, y = 300 })
    local b = bar({ drawn = false })
    local c = bar({ hostile = false, drawn = false })
    local list = gauges.shown(1)
    eq(#list, 1, "one bar")
    eq(list[1].character, a.chara, "the drawn, hostile one")
    -- the game shows and hides them: each frame reads them again
    b.o.drawn, a.o.drawn = true, false
    list = gauges.shown(1.02)
    eq(#list, 1, "one bar"); eq(list[1].character, b.chara, "the other one now")
    c.o.drawn = true
    eq(#gauges.shown(1.03), 1, "drawn but not hostile: left out")
    c.o.drawn, c.o.hostile = false, true
    eq(#gauges.shown(1.04), 1, "hostile but not drawn: left out")
    c.o.drawn = true
    eq(#gauges.shown(1.06), 2, "drawn and hostile: shown")
    -- a value that is not true is not true
    b.o.drawn = 1
    a.o.drawn, a.o.hostile = true, "yes"
    list = gauges.shown(1.08)
    eq(#list, 1, "DrawSelf 1, IsHostile \"yes\": neither")
    eq(list[1].character, c.chara, "only c")
    -- a bar without its character or its position this frame is left out, and kept
    c.comp.fields.CompChara = nil
    eq(#gauges.shown(1.1), 0, "no character: left out")
    c.comp.fields.CompChara = c.chara
    c.comp.fields.All = nil
    eq(#gauges.shown(1.12), 0, "no panel: left out")
    c.comp.fields.All = c.panel
    c.o.x = 0 / 0
    eq(#gauges.shown(1.14), 0, "a position that is not a number: left out")
    c.o.x = nil
    eq(#gauges.shown(1.16), 1, "back")
    eq(gauges.count(), 3, "all three still kept")
end)

test("a bar whose game calls raise (gone since the look) is dropped until the next look, without an error", function()
    local gauges, Hook = fresh()
    local a = bar({ x = 100 })
    local b = bar({ x = 200 })
    eq(#gauges.shown(5), 2, "two bars")
    a.go.poison = true
    local list = gauges.shown(5.02)
    eq(#list, 1, "the other one still comes"); eq(list[1].character, b.chara, "b")
    eq(Hook.info().errors, 0, "no error: the game destroying a bar is normal play")
    eq(gauges.gone(), 1, "counted as gone")
    for i = 1, 20 do gauges.shown(5.02 + i * 0.02) end
    eq(gauges.gone(), 1, "not read again before the next look")
    eq(gauges.count(), 1, "dropped")
    -- its panel raising, the same
    b.panel.poison = true
    eq(#gauges.shown(5.5), 0, "nothing")
    eq(gauges.gone(), 2, "gone"); eq(gauges.count(), 0, "dropped too")
    -- the next look: a GameObject that raises is not kept again; a bar that is, raising, is dropped again: once a
    -- look at most
    gauges.shown(6)
    eq(gauges.gone(), 3, "b once more at the next look")
    a.go.poison, b.panel.poison = false, false
    eq(#gauges.shown(7), 2, "mended: both back")
    -- a field that cannot be read, the same
    a.comp.poison = true
    eq(#gauges.shown(7.02), 1, "a component that raises: dropped")
    eq(gauges.gone(), 4, "gone")
    a.comp.poison = false
    eq(Hook.info().errors, 0, "never an error")
    -- an error of the mod's own reading is counted where the mod's other errors go, the bar dropped all the same
    local reported = {}
    Hook.on_error(function(where) reported[#reported + 1] = where end)
    b.o.pos = setmetatable({}, { __index = function() error("no x here") end })
    eq(#gauges.shown(7.04), 0, "a's dropped until the next look, b's position unreadable")
    eq(Hook.info().errors, 1, "counted"); eq(reported[1], "gauges", "where")
    eq(gauges.gone(), 4, "not as gone")
    b.o.pos = nil
    eq(#gauges.shown(8), 2, "both back at the next look")
    Hook.on_error(nil)
end)

test("no scene, no GUI type or a raising scene: no bars and no error", function()
    local gauges, Hook = fresh()
    bar()
    R.native("via.SceneManager", nil)
    eq(#gauges.shown(1), 0, "no scene manager")
    R.native("via.SceneManager", R.object("via.SceneManager"))
    R.undeclare("via.gui.GUI")
    eq(#gauges.shown(2), 0, "no GUI type")
    R.type("via.gui.GUI")
    G.scene.poison = true
    eq(#gauges.shown(3), 0, "a scene that raises")
    G.scene.poison = false
    G.guis[1].poison = true
    eq(#gauges.shown(4), 0, "a GUI that raises while looked through")
    G.guis[1].poison = false
    eq(#gauges.shown(5), 1, "then there")
    eq(Hook.info().errors, 0, "no error: nothing was kept")
end)

test("the caps: at most 64 bars kept and the first 512 GUIs looked at, in the scene's order", function()
    local gauges = fresh()
    for i = 1, 70 do bar({ x = i }) end
    local names = #R.calls_of("get_Name")
    local list = gauges.shown(1)
    eq(gauges.count(), 64, "64 bars kept of 70")
    eq(#list, 64, "and shown")
    for i = 1, 64 do eq(list[i].x, i, "the scene's first ones, in its order") end
    eq(#R.calls_of("get_Name") - names, 64, "the walk stops at the 64th bar")
    -- 511 other GUIs, then two bars: the 512th GUI is looked at, the 513th is not
    G.guis = {}
    for i = 1, 511 do bar({ name = "ui" .. i }) end
    local last = bar({ x = 512 })
    bar({ x = 513 })
    names = #R.calls_of("get_Name")
    list = gauges.shown(2)
    eq(#list, 1, "one bar"); eq(list[1].character, last.chara, "the 512th GUI's")
    eq(#R.calls_of("get_Name") - names, 512, "512 GameObjects' names asked, no more")
end)

test("reset forgets the bars, and the next call looks again", function()
    local gauges = fresh()
    bar()
    eq(#gauges.shown(1), 1, "one bar")
    gauges.reset()
    eq(gauges.count(), 0, "forgotten")
    eq(#gauges.shown(1.1), 1, "looked through again at once")
    eq(scans(), 2, "two looks")
end)

-- The boss bar ------------------------------------------------------------------------------------------------

test("the boss bar: found in the same look as the bars; its target, left end, middle and width from its base", function()
    local gauges = fresh({ boss = true })
    local a = bar({ x = 100 })
    bar({ name = "ui020502" })            -- another GUI
    local b = boss()
    local shown = gauges.boss(10)
    local list = gauges.shown(10)
    eq(scans(), 1, "one look for both")
    eq(#list, 1, "the bar over a head"); eq(list[1].character, a.chara, "its character")
    eq(shown.character, b.target, "the boss bar's target")
    near(shown.x, 665.3, 1e-9, "x: the base's left end in GUI space")
    near(shown.y, 109.5, 1e-9, "y: its middle, the top 106 + half its height 7")
    eq(shown.width, 776, "its width in its own units")
    -- the boss bar alone looks too, and the bars come from that look
    gauges.reset()
    eq(gauges.boss(11).character, b.target, "after a reset: looked for at once")
    eq(scans(), 2, "a look")
    eq(#gauges.shown(11), 1, "the bars found in it")
    eq(scans(), 2, "no other look")
    -- within the second the scene is not looked through again; a second later it is
    eq(gauges.boss(11.9) ~= nil, true, "still there"); eq(scans(), 2, "no look")
    eq(gauges.boss(12) ~= nil, true, "a second later"); eq(scans(), 3, "a look")
    -- without a boss bar in the scene: none
    table.remove(G.guis)
    eq(gauges.boss(13), nil, "gone at the next look")
    -- only the first GUI called ui020501 with its component is taken
    local first = boss({ target = R.character({ go = "ch250001_00" }) })
    boss()
    eq(gauges.boss(14).character, first.target, "the scene's first")
end)

test("the base is looked for under All once, when the bar is first drawn, and kept while the bar is the same", function()
    local gauges = fresh({ boss = true })
    local b = boss({ drawn = false })
    eq(gauges.boss(1), nil, "not drawn: nothing")
    eq(walks(), 0, "nor looked for")
    local before = #R.calls
    eq(gauges.boss(1.02), nil, "a frame not drawn")
    eq(#R.calls - before, 1, "one call: its DrawSelf")
    b.o.drawn = true
    local shown = gauges.boss(1.04)
    eq(shown ~= nil, true, "drawn: there")
    local walked = walks()
    eq(walked > 0, true, "the base looked for")
    eq(#R.calls_of("get_Name") > 1, true, "by the elements' names")
    for i = 1, 5 do gauges.boss(1.04 + i * 0.02) end
    eq(walks(), walked, "kept: not looked for again")
    eq(gauges.boss(2.5) ~= nil, true, "the next look")
    eq(scans(), 2, "looked through")
    eq(walks(), walked, "the same bar: its base kept")
    -- each frame drawn: its position and size read again
    b.specs.s9g_Base.pos = { 700, 120 }
    shown = gauges.boss(2.6)
    eq(shown.x, 700, "moved: x"); near(shown.y, 123.5, 1e-9, "y")
    b.specs.s9g_Base.size = { 500, 10 }
    shown = gauges.boss(2.62)
    eq(shown.width, 500, "the size read again"); near(shown.y, 125, 1e-9, "its middle")
    -- another bar at the next look: its base looked for anew
    G.guis = {}
    local other = boss()
    shown = gauges.boss(4)
    eq(shown.character, other.target, "the other bar")
    eq(walks() > walked, true, "its base looked for")
    near(shown.x, 665.3, 1e-9, "its own base")
end)

test("drawn and with a target: else no boss bar", function()
    local gauges = fresh({ boss = true })
    local b = boss()
    eq(gauges.boss(1) ~= nil, true, "drawn, with a target")
    b.o.drawn = false
    eq(gauges.boss(1.02), nil, "not drawn")
    b.o.drawn = 1
    eq(gauges.boss(1.04), nil, "DrawSelf 1 is not true")
    b.o.drawn = true
    b.comp.fields.Target, b.comp.fields.TargetHitCtrl = nil, nil
    eq(gauges.boss(1.06), nil, "no target")
    b.comp.fields.Target, b.comp.fields.TargetHitCtrl = b.target_go, b.hc
    eq(gauges.boss(1.08).character, b.target, "back")
end)

test("the boss: TargetHitCtrl's character, else the app.Character of the Target GameObject; never the GameObject", function()
    local gauges, Hook = fresh({ boss = true })
    local b = boss()
    local shown = gauges.boss(1)
    eq(shown.character, b.target, "the hit controller's character")
    eq(shown.character ~= b.target_go, true, "not the Target GameObject")
    local asked = 0
    for _, c in ipairs(R.calls) do
        if c.this == b.target_go then asked = asked + 1 end
    end
    eq(asked, 0, "the GameObject not asked while the hit controller answers")
    -- the hit controller without a character: the GameObject's app.Character component
    b.o.no_cached = true
    shown = gauges.boss(1.02)
    eq(shown.character, b.target, "the component")
    local comps = R.calls_of(GET_COMPONENT)
    local last = comps[#comps]
    eq(last.this, b.target_go, "asked of the Target GameObject")
    eq(last.args[1].runtime_type, "app.Character", "for the app.Character type")
    -- no hit controller at all: the same
    b.comp.fields.TargetHitCtrl = nil
    eq(gauges.boss(1.04).character, b.target, "without TargetHitCtrl")
    -- a hit controller that raises (the boss gone): the component, and no error
    b.comp.fields.TargetHitCtrl = b.hc
    b.o.no_cached = false
    b.hc.poison = true
    eq(gauges.boss(1.06).character, b.target, "a raising hit controller: the component")
    -- neither: no boss bar
    b.o.no_component = true
    eq(gauges.boss(1.08), nil, "no character: none")
    b.hc.poison = false
    b.target_go.poison = true
    eq(gauges.boss(1.1).character, b.target, "the hit controller again; the GameObject not needed")
    b.o.no_cached = true
    eq(gauges.boss(1.12), nil, "a raising GameObject and no cached character: none")
    eq(gauges.boss(1.14), nil, "still none, the bar kept")
    b.target_go.poison, b.o.no_cached = false, false
    eq(gauges.boss(1.16).character, b.target, "back at once: the bar was kept")
    eq(Hook.info().errors, 0, "no error")
    eq(gauges.gone(), 0, "nothing dropped")
end)

test("a base not found or not readable: the target without a place; not found, looked for again a look later", function()
    local gauges = fresh({ boss = true })
    local b = boss({ tree = { { name = "pnl_Name" }, { name = "pnl_Gauge", children = { { name = "HP" } } } } })
    local shown = gauges.boss(1)
    eq(shown.character, b.target, "the target")
    eq(shown.x, nil, "no x"); eq(shown.y, nil, "no y"); eq(shown.width, nil, "no width")
    local walked = walks()
    eq(walked > 0, true, "looked for")
    for i = 1, 10 do gauges.boss(1 + i * 0.05) end
    eq(walks(), walked, "not on every frame")
    gauges.boss(2)
    eq(walks() > walked, true, "again at the next look")
    -- the element appears (its name, read live): found at the next look, then kept
    b.specs.HP.name = "s9g_Base"
    b.specs.s9g_Base = b.specs.HP
    b.specs.HP.pos, b.specs.HP.size = { 564, 106 }, { 776, 7 }
    gauges.boss(2.5)
    eq(gauges.boss(2.6).x, nil, "not before the next look")
    shown = gauges.boss(3)
    eq(shown.x, 564, "found"); near(shown.y, 109.5, 1e-9, "its middle"); eq(shown.width, 776, "its width")
    -- a position or size the game does not give this frame, or not a number: no place this frame
    for _, case in ipairs({ { nil, { 776, 7 }, "no position" }, { { 564, 106 }, nil, "no size" },
                            { { 0 / 0, 106 }, { 776, 7 }, "x not a number" }, { { 564, math.huge }, { 776, 7 }, "y" },
                            { { 564, 106 }, { 0, 7 }, "no width" }, { { 564, 106 }, { 776, 0 / 0 }, "a height" } }) do
        b.specs.s9g_Base.pos, b.specs.s9g_Base.size = case[1], case[2]
        shown = gauges.boss(3.1)
        eq(shown.character, b.target, case[3] .. ": the target")
        eq(shown.x, nil, case[3] .. ": no place")
    end
    b.specs.s9g_Base.pos, b.specs.s9g_Base.size = { 564, 106 }, { 776, 7 }
    eq(gauges.boss(3.2).x, 564, "back")
end)

test("the walk is bounded: the first 128 elements, five levels under All", function()
    local gauges = fresh({ boss = true })
    local list = {}
    for i = 1, 200 do list[i] = { name = "el" .. i } end
    list[129].name = "s9g_Base"
    list[129].pos, list[129].size = { 564, 106 }, { 776, 7 }
    boss({ tree = list })
    local names = #R.calls_of("get_Name")
    gauges.boss(1)
    local asked = #R.calls_of("get_Name") - names
    eq(gauges.boss(1.02).x, nil, "the 129th element is not looked at")
    eq(asked, 1 + 128, "the GameObject's name in the look, then 128 elements'")
    -- 128th: found
    G.guis = {}
    list[129].name, list[128].name = "el129", "s9g_Base"
    list[128].pos, list[128].size = { 600, 106 }, { 776, 7 }
    boss({ tree = list })
    eq(gauges.boss(3).x, 600, "the 128th is")
    -- five levels under All: found; six: not
    local function nested(depth)
        local spec = { name = "s9g_Base", pos = { 564, 106 }, size = { 776, 7 } }
        for i = depth - 1, 1, -1 do spec = { name = "lv" .. i, children = { spec } } end
        return { spec }
    end
    G.guis = {}
    boss({ tree = nested(5) })
    eq(gauges.boss(5).x, 564, "five levels down: found")
    G.guis = {}
    boss({ tree = nested(6) })
    eq(gauges.boss(7).x, nil, "six: not")
end)

test("a boss bar whose game calls raise is dropped until the next look, without an error; the mod's own errors count", function()
    local gauges, Hook = fresh({ boss = true })
    local b = boss()
    bar()
    eq(gauges.boss(5) ~= nil, true, "there")
    b.go.poison = true
    eq(gauges.boss(5.02), nil, "a GameObject that raises: none")
    eq(Hook.info().errors, 0, "no error: gone since the look"); eq(gauges.gone(), 1, "counted as gone")
    for i = 1, 20 do gauges.boss(5.02 + i * 0.02) end
    eq(gauges.gone(), 1, "not read again before the next look")
    eq(#gauges.shown(5.5), 1, "the bars over heads still come")
    -- at the next look the GameObject is not taken (its name cannot be read): nothing
    eq(gauges.boss(6), nil, "not found"); eq(gauges.gone(), 1, "not kept, so not read")
    b.go.poison = false
    eq(gauges.boss(7) ~= nil, true, "mended")
    -- a component that raises
    b.comp.poison = true
    eq(gauges.boss(7.02), nil, "a component that raises"); eq(gauges.gone(), 2, "gone")
    b.comp.poison = false
    eq(gauges.boss(8) ~= nil, true, "back at the next look")
    -- a base that raises: the same, its search again at the next look
    b.specs.s9g_Base.el.poison = true
    eq(gauges.boss(8.02), nil, "a base that raises"); eq(gauges.gone(), 3, "gone")
    for i = 1, 10 do gauges.boss(8.02 + i * 0.02) end
    eq(gauges.gone(), 3, "once")
    b.specs.s9g_Base.el.poison = false
    eq(gauges.boss(9).x, 665.3, "back with its base")
    -- an element that raises while the base is looked for, the same
    G.guis = {}
    local c = boss()
    c.specs.pnl_Name.el.poison = true
    eq(gauges.boss(10), nil, "the search raised"); eq(gauges.gone(), 4, "gone")
    eq(gauges.boss(10.5), nil, "not tried again before the next look"); eq(gauges.gone(), 4, "once")
    eq(Hook.info().errors, 0, "never an error")
    -- an error of the mod's own reading (a size whose width cannot be read) is counted, once a look at most
    c.specs.pnl_Name.el.poison = false
    local reported = {}
    Hook.on_error(function(where) reported[#reported + 1] = where end)
    c.specs.s9g_Base.size_value = setmetatable({}, { __index = function() error("no width here") end })
    eq(gauges.boss(11), nil, "none")
    eq(Hook.info().errors, 1, "counted"); eq(reported[1], "gauges", "where the mod's other errors go")
    for i = 1, 10 do gauges.boss(11 + i * 0.02) end
    eq(Hook.info().errors, 1, "once a look at most")
    eq(gauges.gone(), 4, "not as gone")
    Hook.on_error(nil)
end)

test("the look goes past the 64th bar to the boss bar, then stops", function()
    local gauges = fresh({ boss = true })
    for i = 1, 70 do bar({ x = i }) end
    local b = boss()
    gauges.boss(0)                        -- asked for: the looks take it
    local names = #R.calls_of("get_Name")
    gauges.shown(1)
    eq(#R.calls_of("get_Name") - names, 71, "every GUI's name to the boss bar's, the 71st")
    eq(gauges.count(), 64, "64 bars kept")
    eq(gauges.boss(1).character, b.target, "and the boss bar")
    -- the boss bar first: the walk stops at the 64th bar
    G.guis = {}
    b = boss()
    for i = 1, 70 do bar({ x = i }) end
    names = #R.calls_of("get_Name")
    gauges.shown(2)
    eq(#R.calls_of("get_Name") - names, 65, "the boss bar's and 64 bars' names")
    eq(gauges.boss(2).character, b.target, "the boss bar")
    -- no boss bar: the first 512 GUIs looked at
    G.guis = {}
    for i = 1, 600 do bar({ name = "ui" .. i }) end
    names = #R.calls_of("get_Name")
    eq(gauges.boss(3), nil, "none")
    eq(#R.calls_of("get_Name") - names, 512, "512 names, no more")
end)

test("the looks take the boss bar only once it was asked for since the last reset", function()
    local gauges = fresh({ boss = true })
    local b = boss()                      -- the scene's first GUI
    for i = 1, 70 do bar({ x = i }) end
    -- the calls on the boss bar beyond its GameObject's name, which the look asks of every GUI
    local function boss_calls()
        local n = 0
        for _, c in ipairs(R.calls) do
            if (c.this == b.go and c.sig ~= "get_Name") or c.this == b.comp or c.this == b.all then n = n + 1 end
        end
        return n
    end
    local names = #R.calls_of("get_Name")
    eq(#gauges.shown(1), 64, "64 bars")
    eq(#R.calls_of("get_Name") - names, 65, "not asked for: the walk stops at the 64th bar, as without it")
    for t = 2, 4 do gauges.shown(t) end
    eq(scans(), 4, "four looks")
    eq(boss_calls(), 0, "nothing of the boss bar read in them")
    -- asked for: looked through at once, the boss bar taken
    eq(gauges.boss(4.5).character, b.target, "found at once")
    eq(scans(), 5, "a look of its own")
    eq(boss_calls() > 0, true, "read")
    gauges.shown(4.6)
    eq(scans(), 5, "the bars come from that look")
    gauges.boss(5.6)
    gauges.shown(5.6)
    eq(scans(), 6, "then one look for both")
    -- reset: not taken again until it is asked for
    gauges.reset()
    local read = boss_calls()
    names = #R.calls_of("get_Name")
    for t = 7, 9 do gauges.shown(t) end
    eq(#R.calls_of("get_Name") - names, 3 * 65, "each look stops at the 64th bar again")
    eq(boss_calls(), read, "nothing of the boss bar read")
    eq(gauges.boss(9.1).character, b.target, "asked for again: found at once")
    -- the boss bar after 70 bars, not asked for: the walk does not go on to it
    table.remove(G.guis, 1)
    G.guis[#G.guis + 1] = b.gui
    gauges.reset()
    names = #R.calls_of("get_Name")
    eq(#gauges.shown(10), 64, "64 bars")
    eq(#R.calls_of("get_Name") - names, 64, "the walk stops at the 64th bar, not at the boss bar")
    names = #R.calls_of("get_Name")
    eq(gauges.boss(10.1).character, b.target, "asked for: found")
    eq(#R.calls_of("get_Name") - names >= 71, true, "by a walk that went on to it")
    -- without the boss bar's type nothing changes either way
    gauges = fresh()
    for i = 1, 70 do bar({ x = i }) end
    eq(gauges.boss(1), nil, "no type: no boss bar")
    names = #R.calls_of("get_Name")
    gauges.shown(2)
    eq(#R.calls_of("get_Name") - names, 64, "and the walk stops at the 64th bar")
end)

test("reset forgets the boss bar too, and the next call looks again", function()
    local gauges = fresh({ boss = true })
    boss()
    eq(gauges.boss(1) ~= nil, true, "there")
    local walked = walks()
    gauges.reset()
    eq(gauges.boss(1.1) ~= nil, true, "looked for again at once")
    eq(scans(), 2, "two looks")
    eq(walks() > walked, true, "its base looked for again")
end)

test("the boss bar hands back its TargetHitCtrl as hc, from the one read that finds its character", function()
    local gauges = fresh({ boss = true })
    local b = boss()
    eq(gauges.boss(1).hc, b.hc, "the boss's app.HitController")
    local reads = 0
    b.comp.fields.TargetHitCtrl = nil
    setmetatable(b.comp.fields, { __index = function(_, k)
        if k == "TargetHitCtrl" then
            reads = reads + 1
            return b.hc
        end
    end })
    eq(gauges.boss(1.02).hc, b.hc, "the same")
    eq(reads, 1, "TargetHitCtrl read once a call, for the character and hc alike")
    -- no hit controller: the character from the Target GameObject, and no hc
    setmetatable(b.comp.fields, nil)
    local shown = gauges.boss(1.04)
    eq(shown.character, b.target, "the character still"); eq(shown.hc, nil, "no hc")
end)

-- The player's HUD -----------------------------------------------------------------------------------------

-- A bar's background chain, as the probe saw it: PNL_Hp/PNL_Hpbg/PNL_Mhpbg/s9g_Base, or with `sp`
-- PNL_Sp/PNL_Spbg/PNL_Mspbg/s9g_Base; its s9g_Base at `pos` with `size` (by default the HP bar's: (669.8, 1010),
-- 780 × 7). Gives the panel's spec and the s9g_Base's.
local function bar_chain(sp, pos, size)
    local base = { name = "s9g_Base", pos = pos or { 669.8, 1010 }, size = size or { 780, 7 } }
    local names = sp and { "PNL_Sp", "PNL_Spbg", "PNL_Mspbg" } or { "PNL_Hp", "PNL_Hpbg", "PNL_Mhpbg" }
    return { name = names[1], children = { { name = names[2], children = {
        { name = names[3], children = { base } } } } } }, base
end

-- The player's HUD: a GUI on a GameObject named "ui020901", drawn (o.drawn, default true), its view (the GUI's
-- get_View) over o.tree, else the tree the probes saw: PNL_Playergauge/PNL_All (o.gauge_name: another name for
-- PNL_Playergauge), under it (after o.before plain elements) a status panel, then PNL_Sp and PNL_Hp (in the probe's
-- walk PNL_Sp came first). Before PNL_Playergauge, right under the view, decoys of both chains: a PNL_Hp and a
-- PNL_Sp with their own backgrounds (500 wide), and a PNL_Pawngauge/PNL_All holding both (400 wide). Each bar's
-- full-length
-- background is the one taken: PNL_Hp/PNL_Hpbg/PNL_Mhpbg/s9g_Base (669.8, 1010, 780 × 7) and
-- PNL_Sp/PNL_Spbg/PNL_Mspbg/s9g_Base (669.8, 1026.6, 780 × 6). The names repeat before them: the status panel's
-- s9g_Base, s9g_Line and rec_Line; the fills (PNL_Hp/PNL_Line/PNL_Mline/s9g_Line, 469.7 wide at 60 % HP, and
-- PNL_Sp/PNL_Spline/PNL_Mspline/rec_Line, 710.6); the s9g_Base under PNL_Whiteline (the cut max) and PNL_TempBg. The
-- returned h has h.gui, h.go, h.view, h.hp and h.sp (the two backgrounds' specs: h.hp.size = ... resizes it),
-- h.sp_panel (PNL_Sp's spec: its name is read live, o.sp_name gives it another at first), h.lines (every element of
-- the tree), and o's values live.
local function hud(o)
    o = o or {}
    if o.drawn == nil then o.drawn = true end
    local h = { o = o }
    local tree = o.tree
    if tree == nil then
        h.sp = { name = "s9g_Base", pos = { 669.8, 1026.6 }, size = { 780, 6 } }
        h.sp_panel = { name = o.sp_name or "PNL_Sp", children = {
            { name = "PNL_Spline", children = { { name = "PNL_Mspline", children = {
                { name = "rec_Line", pos = { 669.8, 1028.6 }, size = { 710.6, 2 } } } } } },
            { name = "PNL_Whiteline", children = {
                { name = "s9g_Base", pos = { 669.8, 1026.6 }, size = { 760, 6 } } } },
            { name = "PNL_Spbg", children = { { name = "PNL_Mspbg", children = { h.sp } } } },
        } }
        local hp_panel
        hp_panel, h.hp = bar_chain(false)
        table.insert(hp_panel.children, 1, { name = "PNL_TempBg", children = {
            { name = "s9g_Base", pos = { 669.8, 1010 }, size = { 740, 7 } } } })
        table.insert(hp_panel.children, 1, { name = "PNL_Whiteline", children = {
            { name = "s9g_Base", pos = { 669.8, 1010 }, size = { 700, 7 } } } })
        table.insert(hp_panel.children, 1, { name = "PNL_Line", children = { { name = "PNL_Mline", children = {
            { name = "s9g_Line", pos = { 669.8, 1013.5 }, size = { 469.7, 6 } } } } } })
        local all = {}
        for i = 1, o.before or 0 do all[i] = { name = "el" .. i } end
        all[#all + 1] = { name = "PNL_Status", children = {
            { name = "s9g_Base", pos = { 600, 996 }, size = { 40, 40 } },
            { name = "s9g_Line", pos = { 640, 996 }, size = { 40, 6 } },
            { name = "rec_Line", pos = { 680, 996 }, size = { 30, 3 } },
        } }
        all[#all + 1] = h.sp_panel
        all[#all + 1] = hp_panel
        all[#all + 1] = { name = "tex_Startpos", pos = { 1249.9, 1010 } }
        tree = {
            (bar_chain(false, { 100, 200 }, { 500, 7 })),
            (bar_chain(true, { 100, 220 }, { 500, 6 })),
            { name = "PNL_Pawngauge", children = { { name = "PNL_All", children = {
                (bar_chain(true, { 100, 320 }, { 400, 6 })), (bar_chain(false, { 100, 300 }, { 400, 7 })) } } } },
            { name = o.gauge_name or "PNL_Playergauge", children = {
                { name = "PNL_All", pos = { 671.3, 1010 }, children = all } } },
        }
    end
    local specs = {}
    local first = elements(tree, specs)
    h.lines = {}
    local function collect(list)
        for _, sp in ipairs(list) do
            h.lines[#h.lines + 1] = sp.el
            if sp.children then collect(sp.children) end
        end
    end
    collect(tree)
    h.view = R.object("via.gui.View", {}, { get_Child = function() return first end })
    h.go = R.object("via.GameObject", {}, {
        get_Name = function() return o.name or "ui020901" end,
        get_DrawSelf = function() return o.drawn end,
    })
    h.gui = R.object("via.gui.GUI", {}, {
        get_GameObject = function() return h.go end,
        get_View = function() if not o.no_view then return h.view end end,
    })
    G.guis[#G.guis + 1] = h.gui
    return h
end

test("the player's HUD: each bar's full-length background, its left end, top and size", function()
    local gauges = fresh()
    local a = bar({ x = 100 })
    bar({ name = "ui020902" })            -- another GUI
    local h = hud()
    local p = gauges.player(10)
    eq(scans(), 1, "one look")
    near(p.hp.x, 669.8, 1e-9, "the HP bar's left end"); near(p.hp.y, 1010, 1e-9, "its top")
    eq(p.hp.width, 780, "its width in its own units"); eq(p.hp.height, 7, "its height")
    near(p.sp.x, 669.8, 1e-9, "the stamina bar's left end"); near(p.sp.y, 1026.6, 1e-9, "its top")
    eq(p.sp.width, 780, "its width"); eq(p.sp.height, 6, "its height")
    -- the bars over heads come from that look
    local list = gauges.shown(10)
    eq(#list, 1, "the bar over a head"); eq(list[1].character, a.chara, "its character")
    eq(scans(), 1, "no other look")
    -- within the second the scene is not looked through again; a second later it is
    eq(gauges.player(10.9) ~= nil, true, "still there"); eq(scans(), 1, "no look")
    eq(gauges.player(11) ~= nil, true, "a second later"); eq(scans(), 2, "a look")
    -- each read gives the bars' place and size anew: the HP bar grows with the max HP
    h.hp.size = { 806, 7 }
    eq(gauges.player(11.02).hp.width, 806, "the HP bar's new width")
    h.sp.pos = { 680, 1030 }
    p = gauges.player(11.04)
    eq(p.sp.x, 680, "the stamina bar moved"); eq(p.sp.y, 1030, "its top")
    -- only the scene's first GUI called ui020901 is taken
    G.guis = {}
    local first = hud()
    first.hp.size = { 500, 7 }
    hud()
    eq(gauges.player(12).hp.width, 500, "the scene's first")
end)

test("the bars' backgrounds by their parent chain, never a fill, the cut max's line or another s9g_Base",
    function()
    local gauges = fresh()
    local h = hud()
    local p = gauges.player(1)
    -- before them: a PNL_Hp and a PNL_Sp chain right under the view (500 wide) and both under PNL_Pawngauge/PNL_All
    -- (400); under PNL_Playergauge/PNL_All the status panel's s9g_Base, s9g_Line and rec_Line; under PNL_Hp the fill
    -- s9g_Line (469.7 wide), the s9g_Base under PNL_Whiteline (700) and under PNL_TempBg (740); under PNL_Sp the fill
    -- rec_Line (710.6) and PNL_Whiteline's s9g_Base (760)
    eq(p.hp.width, 780, "the HP bar's background under PNL_Playergauge/PNL_All/PNL_Hp/PNL_Hpbg/PNL_Mhpbg")
    eq(p.hp.height, 7, "its height"); near(p.hp.y, 1010, 1e-9, "its top")
    eq(p.sp.width, 780, "the stamina bar's under PNL_Playergauge/PNL_All/PNL_Sp/PNL_Spbg/PNL_Mspbg")
    near(p.sp.y, 1026.6, 1e-9, "its top")
    -- without PNL_Playergauge: neither bar, though both chains are there under the view and under PNL_Pawngauge/PNL_All
    G.guis = {}
    hud({ gauge_name = "PNL_Xgauge" })
    p = gauges.player(2)
    eq(p ~= nil, true, "drawn: an answer"); eq(p.hp, nil, "no HP bar"); eq(p.sp, nil, "no stamina bar")
    -- without PNL_Sp in the tree: no stamina bar, though s9g_Base elements are there
    G.guis = {}
    h = hud({ sp_name = "PNL_Xp" })
    p = gauges.player(3)
    eq(p.sp, nil, "no stamina bar"); eq(p.hp.width, 780, "the HP bar still")
    -- a GUI with no view: neither bar, the HUD still drawn
    G.guis = {}
    hud({ no_view = true })
    p = gauges.player(4)
    eq(p ~= nil, true, "drawn: an answer"); eq(p.hp, nil, "no HP bar"); eq(p.sp, nil, "no stamina bar")
end)

test("the bars late in the HUD's tree (the probe's PNL_Sp was its 424th element, PNL_Hp its 446th) are found;"
    .. " at most 1024 elements a name", function()
    local gauges = fresh()
    hud({ before = 440 })
    local p = gauges.player(1)
    eq(p.hp.width, 780, "the HP bar after 440 other elements"); eq(p.sp.width, 780, "the stamina bar")
    -- found once, kept: the walk is not made again at the next looks
    local walked = walks()
    for t = 2, 4 do gauges.player(t) end
    eq(scans(), 4, "three more looks")
    eq(walks(), walked, "no walk in them")
    -- the bound: PNL_Playergauge as the 1024th element looked at is found, as the 1025th it is not
    local function flat(n)
        local list = {}
        for i = 1, n do list[i] = { name = "el" .. i } end
        list[n + 1] = { name = "PNL_Playergauge", children = {
            { name = "PNL_All", children = { (bar_chain(false)) } } } }
        return list
    end
    G.guis = {}
    hud({ tree = flat(1023) })
    eq(gauges.player(5).hp.width, 780, "the 1024th element: found")
    G.guis = {}
    hud({ tree = flat(1024) })
    eq(gauges.player(6).hp, nil, "the 1025th: not looked at")
end)

test("the HUD not drawn: nil; its bars are looked for once, when first drawn, and kept while it is the same",
    function()
    local gauges = fresh()
    local h = hud({ drawn = false })
    eq(gauges.player(1), nil, "not drawn: nil")
    eq(walks(), 0, "its bars not looked for")
    local before = #R.calls
    eq(gauges.player(1.02), nil, "a frame not drawn")
    eq(#R.calls - before, 1, "one call: its DrawSelf")
    h.o.drawn = true
    eq(gauges.player(1.04) ~= nil, true, "drawn: there")
    local walked = walks()
    eq(walked > 0, true, "the bars looked for")
    for i = 1, 5 do gauges.player(1.04 + i * 0.02) end
    eq(walks(), walked, "kept: not looked for again")
    eq(gauges.player(2.5) ~= nil, true, "the next look")
    eq(scans(), 2, "looked through")
    eq(walks(), walked, "the same HUD: its bars kept")
    h.o.drawn = 1
    eq(gauges.player(2.52), nil, "DrawSelf 1 is not true")
    h.o.drawn = true
    -- a bar not found: nil, looked for again after the next look; found then
    G.guis = {}
    h = hud({ sp_name = "PNL_Xp" })
    eq(gauges.player(4).sp, nil, "no stamina bar")
    walked = walks()
    for i = 1, 10 do gauges.player(4 + i * 0.05) end
    eq(walks(), walked, "not on every frame")
    h.sp_panel.name = "PNL_Sp"
    eq(gauges.player(4.6).sp, nil, "not before the next look")
    local function view_calls()
        local n = 0
        for _, c in ipairs(R.calls) do
            if c.this == h.view then n = n + 1 end
        end
        return n
    end
    local from_view = view_calls()
    local p = gauges.player(5)
    eq(walks() > walked, true, "looked for again at the next look")
    eq(p.sp.height, 6, "found"); eq(p.hp.height, 7, "the HP bar kept")
    eq(view_calls(), from_view, "under the PNL_All kept: nothing walked from the view again")
    -- a bar that gives no finite place or size this frame: nil this frame, kept
    for _, case in ipairs({ { nil, { 780, 6 }, "no position" }, { { 669.8, 1026.6 }, nil, "no size" },
                            { { 0 / 0, 1026.6 }, { 780, 6 }, "x not a number" },
                            { { 669.8, math.huge }, { 780, 6 }, "y" }, { { 669.8, 1026.6 }, { 0, 6 }, "no width" },
                            { { 669.8, 1026.6 }, { 780, 0 / 0 }, "a height" } }) do
        h.sp.pos, h.sp.size = case[1], case[2]
        p = gauges.player(5.1)
        eq(p.sp, nil, case[3] .. ": no stamina bar"); eq(p.hp.width, 780, case[3] .. ": the HP bar still")
    end
    h.sp.pos, h.sp.size = { 669.8, 1026.6 }, { 780, 6 }
    eq(gauges.player(5.2).sp.width, 780, "back")
    -- another HUD at the next look: its bars looked for anew
    G.guis = {}
    hud()
    walked = walks()
    eq(gauges.player(7).hp.width, 780, "the other HUD")
    eq(walks() > walked, true, "its bars looked for")
    -- no HUD in the scene: nil
    G.guis = {}
    eq(gauges.player(9), nil, "none at the next look")
end)

test("the looks take the HUD only once gauges.player was called since the last reset", function()
    local gauges = fresh()
    local h = hud()                       -- the scene's first GUI
    for i = 1, 70 do bar({ x = i }) end
    -- the calls on the HUD beyond its GameObject's name, which the look asks of every GUI
    local function hud_calls()
        local mine = { [h.view] = true }
        for _, el in ipairs(h.lines) do mine[el] = true end
        local n = 0
        for _, c in ipairs(R.calls) do
            if (c.this == h.go and c.sig ~= "get_Name") or (c.this == h.gui and c.sig ~= "get_GameObject")
                    or mine[c.this] then
                n = n + 1
            end
        end
        return n
    end
    local names = #R.calls_of("get_Name")
    eq(#gauges.shown(1), 64, "64 bars")
    eq(#R.calls_of("get_Name") - names, 65, "not asked for: the walk stops at the 64th bar, as without it")
    for t = 2, 4 do gauges.shown(t) end
    eq(gauges.boss(4.2), nil, "the boss bar asked for: none")
    eq(scans(), 5, "five looks")
    eq(hud_calls(), 0, "nothing of the HUD read in them")
    -- asked for: looked through at once, the HUD taken
    eq(gauges.player(4.5).hp.width, 780, "found at once")
    eq(scans(), 6, "a look of its own")
    eq(hud_calls() > 0, true, "read")
    gauges.shown(4.6)
    eq(scans(), 6, "the bars come from that look")
    -- reset: not taken again until it is asked for
    gauges.reset()
    local read = hud_calls()
    for t = 7, 9 do gauges.shown(t) end
    eq(hud_calls(), read, "nothing of the HUD read")
    eq(gauges.player(9.1).hp.width, 780, "asked for again: found at once")
    -- the HUD after 70 bars, asked for: the walk goes on to it, then stops
    table.remove(G.guis, 1)
    G.guis[#G.guis + 1] = h.gui
    for i = 1, 10 do bar({ x = 100 + i }) end
    gauges.reset()
    gauges.player(10)
    names = #R.calls_of("get_Name")
    gauges.shown(11)
    eq(#R.calls_of("get_Name") - names, 71, "every GUI's name to the HUD's, the 71st, and no further")
    local after = #R.calls_of("get_Name")
    eq(gauges.player(11).hp.width, 780, "and the HUD")
    eq(#R.calls_of("get_Name"), after, "no other look")
end)

test("a HUD whose game calls raise is dropped until the next look, without an error; the mod's own errors count",
    function()
    local gauges, Hook = fresh()
    local h = hud()
    eq(gauges.player(5) ~= nil, true, "there")
    h.go.poison = true
    eq(gauges.player(5.02), nil, "a GameObject that raises: none")
    eq(Hook.info().errors, 0, "no error: gone since the look"); eq(gauges.gone(), 1, "counted as gone")
    for i = 1, 20 do gauges.player(5.02 + i * 0.02) end
    eq(gauges.gone(), 1, "not read again before the next look")
    eq(gauges.player(6), nil, "not found at the next look: its name cannot be read")
    h.go.poison = false
    eq(gauges.player(7) ~= nil, true, "mended")
    -- a bar's background that raises: the same
    h.hp.el.poison = true
    eq(gauges.player(7.02), nil, "a background that raises"); eq(gauges.gone(), 2, "gone")
    h.hp.el.poison = false
    eq(gauges.player(8).hp.width, 780, "back at the next look")
    -- an element that raises while the bars are looked for, and a GUI that raises: the same
    G.guis = {}
    local other = hud()
    other.lines[1].poison = true
    eq(gauges.player(9), nil, "the search raised"); eq(gauges.gone(), 3, "gone")
    eq(gauges.player(9.5), nil, "not tried again before the next look"); eq(gauges.gone(), 3, "once")
    other.lines[1].poison = false
    other.gui.poison = true
    eq(gauges.player(10), nil, "a GUI that raises: not taken in the look"); eq(gauges.gone(), 3, "nothing kept")
    other.gui.poison = false
    eq(gauges.player(11).sp.width, 780, "back")
    eq(Hook.info().errors, 0, "never an error")
    -- an error of the mod's own reading (a size whose width cannot be read) is counted, once a look at most
    local reported = {}
    Hook.on_error(function(where) reported[#reported + 1] = where end)
    other.sp.size_value = setmetatable({}, { __index = function() error("no width here") end })
    eq(gauges.player(11.02), nil, "none")
    eq(Hook.info().errors, 1, "counted"); eq(reported[1], "gauges", "where the mod's other errors go")
    for i = 1, 10 do gauges.player(11.02 + i * 0.02) end
    eq(Hook.info().errors, 1, "once a look at most")
    eq(gauges.gone(), 3, "not as gone")
    Hook.on_error(nil)
end)

test("reset forgets the HUD too, and the next call looks again", function()
    local gauges = fresh()
    hud()
    eq(gauges.player(1) ~= nil, true, "there")
    local walked = walks()
    gauges.reset()
    eq(gauges.player(1.1) ~= nil, true, "looked for again at once")
    eq(scans(), 2, "two looks")
    eq(walks() > walked, true, "its bars looked for again")
end)

-- The game calls made on any of `objects` from call number `from` on.
local function asked(objects, from)
    local set, n = {}, 0
    for _, o in ipairs(objects) do set[o] = true end
    for i = from + 1, #R.calls do
        if set[R.calls[i].this] then n = n + 1 end
    end
    return n
end

test("forget drops the bars, the boss bar and the HUD kept, not what was asked for: one look takes all three",
        function()
    local gauges = fresh({ boss = true })
    local a, b, h = bar(), boss(), hud()
    eq(#gauges.shown(10), 1, "a bar"); eq(gauges.boss(10) ~= nil, true, "the boss bar")
    eq(gauges.player(10) ~= nil, true, "the HUD")
    eq(gauges.count(), 1, "a bar kept")
    gauges.forget()
    eq(gauges.count(), 0, "no bar kept")
    -- the world changes under them: what was kept is never asked again; one look finds the new ones, all three
    G.guis = {}
    local a2, b2, h2 = bar({ x = 300 }), boss(), hud()
    local from, looks = #R.calls, scans()
    local list = gauges.shown(10.1)
    eq(#list, 1, "the new bar"); eq(list[1].character, a2.chara, "its character")
    eq(gauges.boss(10.1).character, b2.target, "the new boss bar, from the same look")
    eq(gauges.player(10.1) ~= nil, true, "the new HUD, from the same look")
    eq(scans(), looks + 1, "one look for the three, as before the forget")
    local old = { a.go, a.gui, a.panel, b.go, b.gui, b.all, b.hc, b.specs.s9g_Base.el, h.go, h.gui, h.view }
    for _, el in ipairs(h.lines) do old[#old + 1] = el end
    eq(asked(old, from), 0, "nothing kept before the forget asked")
    -- reset still forgets what was asked for: three looks
    gauges.reset()
    looks = scans()
    gauges.shown(10.2); gauges.boss(10.2); gauges.player(10.2)
    eq(scans(), looks + 3, "after a reset each is looked for on its own first call")
    eq(h2 ~= nil, true, "the new HUD")
end)

T.finish()
