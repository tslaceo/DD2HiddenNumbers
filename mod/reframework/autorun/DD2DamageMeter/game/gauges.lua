-- The game's HP bars, read-only: the bars over the heads of nearby characters, the boss's bar at the top of the
-- screen, and the player's own HP and stamina bars at the bottom. Each overhead bar is a via.gui.GUI whose
-- GameObject is named "ui020601" and carries an app.ui020601 component: CompChara (the character), IsHostile, All (the
-- bar's panel, whose global position is the bar's centre in the GUI's own 1920 x 1080 space). The boss bar is the one
-- GUI named "ui020501", with an app.ui020501 component: Target (the boss's via.GameObject), TargetHitCtrl (the boss's
-- app.HitController) and All, the panel the bar's elements hang under; its base element, "s9g_Base", has the bar's
-- left end at its global position and its size in the bar's own units. The player's HUD is the one GUI named
-- "ui020901" (found by probing the game); under its view (the GUI's get_View) the HP bar's full-length background is
-- the element PNL_Playergauge/PNL_All/PNL_Hp/PNL_Hpbg/PNL_Mhpbg/s9g_Base and the stamina bar's
-- PNL_Playergauge/PNL_All/PNL_Sp/PNL_Spbg/PNL_Mspbg/s9g_Base, each with its left end and top at its global position
-- and its size in its own units, as the boss's base (as probed: the
-- s9g_Line and rec_Line elsewhere under PNL_Hp and PNL_Sp are the fills, as long as the HP or stamina now, and the
-- s9g_Base under PNL_Whiteline follows the max as cut by damage). A bar is on screen exactly while its GameObject's
-- DrawSelf is true. Every game access under Safe or pcall.
--
--   gauges.shown(t) -> { { character, x, y } }   the bars drawn now whose IsHostile is true, in the scene's order;
--     x, y the bar's centre in GUI space. The current scene's GUIs are looked through when the last look is
--     RESCAN_EVERY seconds old (t: seconds), and the bars found are kept until the next look; between the looks
--     only the kept ones are read. A bar without its character or its position this frame is left out. A kept bar
--     whose reading raises is dropped until the next look: without an error when a game call raised (the game
--     destroyed it since the look: counted by gauges.gone), else Hook.fail counts the error.
--   gauges.boss(t) -> { character, hc, x, y, width } | nil   the boss bar while it is drawn and has its boss, found
--     by the same look (the scene's first one). The looks take it only once gauges.boss was called since the last
--     reset; until then they read nothing of it, and the first call looks at once. character: the boss's
--     app.Character, TargetHitCtrl's get_CachedCharacter, else the Target GameObject's app.Character component; hc:
--     TargetHitCtrl itself, the boss's app.HitController (its poise, game/buildup.lua), nil when the bar has none;
--     x, y its left end and its middle in GUI space, width its width in its own units (on screen a height's scale:
--     × H / 1080). x, y and width are nil when its base element is not found or does not give a finite position and
--     size this frame. The base is looked for under All (first child, next sibling: at most MAX_ELEMENTS elements,
--     MAX_DEPTH levels down) the first time the bar is drawn, and kept while the looks find the same GameObject; one
--     not found is looked for again after the next look. A boss bar whose reading raises is dropped until the next
--     look, as a bar over a head.
--   gauges.player(t) -> { hp = { x, y, width, height } | nil, sp = { ... } | nil } | nil   the player's HUD while it
--     is drawn, found by the same look (the scene's first one) and taken by the looks only once gauges.player was
--     called since the last reset, as the boss bar. hp: the HP bar's background, sp: the stamina bar's; x, y its
--     left end and top in GUI space, width and height its size in its own units (on screen a height's scale:
--     × H / 1080), read anew each call; nil when its element is not found or does not give a finite position and size,
--     with a width, this call. Each background is found by its parent chain: PNL_Playergauge/PNL_All once for both,
--     then PNL_Hp/PNL_Hpbg/PNL_Mhpbg/s9g_Base and PNL_Sp/PNL_Spbg/PNL_Mspbg/s9g_Base under it, each name the first of
--     its name met depth first under the element found for the name before it (first child, next sibling: at most
--     MAX_HUD_ELEMENTS elements, MAX_DEPTH levels down, each time; the first name under the view). So an element of
--     one of these names outside the chain above it (a PNL_Hp outside PNL_Playergauge/PNL_All, an s9g_Base outside
--     PNL_Hpbg/PNL_Mhpbg) is never taken. PNL_All and the two backgrounds are looked for the first time the HUD is
--     drawn and kept while the looks find the same GameObject; one not found is looked for again after the next look.
--     A HUD whose reading raises is dropped until the next look, as a bar over a head.
--   gauges.gone() -> the number of kept bars dropped because a game call on them raised, since the mod was loaded
--   gauges.count() -> the number of overhead bars kept
--   gauges.reset()   forgets the kept bars, the boss bar and the player's HUD: the next call looks again (a new world;
--     a setting switched off); the next calls of gauges.boss and gauges.player look again on their own
--   gauges.forget()  forgets the kept bars, the boss bar and the player's HUD, not that the boss bar and the HUD were
--     asked for: the next call makes one look that takes all of them (each scene-type change and the first
--     frame without a player character, after which the mod reads none of them until he is back)
local Safe = require("DD2DamageMeter/game/safe")
local Hook = require("DD2DamageMeter/game/hook")

local Gauges = {}

local RESCAN_EVERY = 1   -- seconds between two looks through the scene's GUIs
local BAR_NAME = "ui020601"
local BOSS_NAME = "ui020501"
local BASE_NAME = "s9g_Base"
local PLAYER_NAME = "ui020901"
-- The player's HUD bars' full-length backgrounds by their parent chain (the name paths probed in game: the HP one 780
-- units long at 60 % HP, where its fill s9g_Line was 469.7): PNL_All under the HUD's view, then each bar's under it.
local ALL_PATH = { "PNL_Playergauge", "PNL_All" }
local HP_PATH = { "PNL_Hp", "PNL_Hpbg", "PNL_Mhpbg", "s9g_Base" }
local SP_PATH = { "PNL_Sp", "PNL_Spbg", "PNL_Mspbg", "s9g_Base" }
local GET_COMPONENT = "getComponent(System.Type)"
local MAX_GUIS = 512     -- the scene's first GUIs looked at in one look (the game had about 30 to 80)
local MAX_BARS = 64      -- bars kept (the game had 4 to 19)
local MAX_ELEMENTS = 128 -- the boss bar's elements looked at for its base (the probe found it among its first 120)
local MAX_HUD_ELEMENTS = 1024 -- the HUD's elements looked at for each name of a chain: the probe's walk from the view
                              -- met PNL_Sp at its 424th element and PNL_Hp at its 446th, of 469
local MAX_DEPTH = 5      -- levels under All (the probe walked five), or under the element a chain's name is looked
                         -- for under (each of the HUD's names is right under the one before it)

local bars = {}          -- { go, comp } of each bar found at the last look
local boss = nil         -- { go, comp, addr, base } of the boss bar; base: its element, false when not found, nil
                         -- when not looked for yet
local boss_wanted = false -- gauges.boss was called since the last reset: the looks take the boss bar
local player = nil       -- { gui, go, addr, all, hp, sp } of the player's HUD; all: its PNL_All, hp, sp: its
                         -- bars' backgrounds, each as base above
local player_wanted = false -- gauges.player was called since the last reset: the looks take the player's HUD
local looked_at = nil    -- t of the last look
local gone = 0           -- kept objects dropped because a game call on them raised

function Gauges.reset()
    bars, boss, boss_wanted, player, player_wanted, looked_at = {}, nil, false, nil, false, nil
end

function Gauges.forget()
    bars, boss, player, looked_at = {}, nil, nil, nil
end

function Gauges.count()
    return #bars
end

local function finite(x)
    return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function current_scene()
    local manager = Safe.try(sdk.get_native_singleton, "via.SceneManager")
    local td = Safe.type("via.SceneManager")
    if manager == nil or td == nil then return nil end
    return Safe.try(sdk.call_native_func, manager, td, "get_CurrentScene")
end

local function elements(arr) return arr:get_elements() end

-- The bars over heads (at most MAX_BARS) and, when they are wanted, the boss bar and the player's HUD among the
-- scene's first MAX_GUIS GUIs; the walk ends once it has all it can take.
local function look()
    local found, boss_found, player_found = {}, nil, nil
    local gui_type = Safe.try(sdk.typeof, "via.gui.GUI")
    local bar_type = Safe.try(sdk.typeof, "app.ui020601")
    local boss_type = boss_wanted and Safe.try(sdk.typeof, "app.ui020501") or nil
    local scene = current_scene()
    if gui_type == nil or (bar_type == nil and boss_type == nil and not player_wanted) or scene == nil then
        return found
    end
    local guis = Safe.call(scene, "findComponents(System.Type)", gui_type)
    if guis == nil then return found end
    for _, gui in ipairs(Safe.items(Safe.try(elements, guis), MAX_GUIS)) do
        if gui then
            local go = Safe.call(gui, "get_GameObject")
            local name = go ~= nil and Safe.call(go, "get_Name") or nil
            if name == BAR_NAME and bar_type ~= nil and #found < MAX_BARS then
                local comp = Safe.call(go, GET_COMPONENT, bar_type)
                if comp ~= nil then found[#found + 1] = { go = go, comp = comp } end
            elseif name == BOSS_NAME and boss_type ~= nil and boss_found == nil then
                local comp = Safe.call(go, GET_COMPONENT, boss_type)
                if comp ~= nil then boss_found = { go = go, comp = comp, addr = Safe.address(go) } end
            elseif name == PLAYER_NAME and player_wanted and player_found == nil then
                player_found = { gui = gui, go = go, addr = Safe.address(go) }
            end
            if (bar_type == nil or #found >= MAX_BARS) and (boss_type == nil or boss_found ~= nil)
                    and (not player_wanted or player_found ~= nil) then
                break
            end
        end
    end
    return found, boss_found, player_found
end

-- The game calls on a kept object between the looks. One that raises (the game throws on an object it destroyed
-- since the look: "Invoke threw an exception") raises GONE, and the object is dropped until the next look without
-- counting an error; any other error in a read is the mod's own and is counted.
local GONE = setmetatable({}, { __tostring = function() return "gone since the look" end })
local function m_call(obj, name) return obj:call(name) end
local function m_field(obj, name) return obj:get_field(name) end

local function get(obj, name)
    local ok, v = pcall(m_call, obj, name)
    if not ok then error(GONE, 0) end
    return v
end

local function field(obj, name)
    local ok, v = pcall(m_field, obj, name)
    if not ok then error(GONE, 0) end
    return v
end

-- The bar as shown now, nil when it is not drawn, not hostile, or without its character or position.
local function read(bar)
    if get(bar.go, "get_DrawSelf") ~= true then return nil end
    local comp = bar.comp
    if field(comp, "IsHostile") ~= true then return nil end
    local character = field(comp, "CompChara")
    if character == nil then return nil end
    local panel = field(comp, "All")
    if panel == nil then return nil end
    local pos = get(panel, "get_GlobalPosition")
    if pos == nil then return nil end
    local x, y = pos.x, pos.y
    if not (finite(x) and finite(y)) then return nil end
    return { character = character, x = x, y = y }
end

-- The element called `name` under `root` (its children, depth first), nil when it is not among the first `max` or
-- deeper than MAX_DEPTH.
local function find_element(root, name, max)
    local seen = 0
    local function walk(el, depth)
        while el ~= nil and seen < max do
            seen = seen + 1
            if get(el, "get_Name") == name then return el end
            if depth < MAX_DEPTH then
                local found = walk(get(el, "get_Child"), depth + 1)
                if found then return found end
            end
            el = get(el, "get_Next")
        end
        return nil
    end
    return walk(get(root, "get_Child"), 1)
end

-- The element at the end of the chain `path` under `root`: each name looked for under the one found before, among
-- at most MAX_HUD_ELEMENTS.
local function find_path(root, path)
    local el = root
    for _, name in ipairs(path) do
        el = find_element(el, name, MAX_HUD_ELEMENTS)
        if el == nil then return nil end
    end
    return el
end

-- An element's place as read now: { x, y (its left end and top in GUI space), width, height (its size in its own
-- units) }, nil when they are not all finite numbers with a width.
local function place(el)
    local pos, size = get(el, "get_GlobalPosition"), get(el, "get_Size")
    if pos == nil or size == nil then return nil end
    local x, y, w, h = pos.x, pos.y, size.w, size.h
    if not (finite(x) and finite(y) and finite(w) and finite(h)) or w <= 0 then return nil end
    return { x = x, y = y, width = w, height = h }
end

-- The boss: Target is the boss's GameObject, TargetHitCtrl (hc) its app.HitController. The character is the hit
-- controller's (as game/hits.lua takes a victim's), else the GameObject's app.Character component; nil without
-- either. Through Safe: a boss gone gives nil, the bar is kept.
local function boss_character(comp, hc)
    local character = Safe.call(hc, "get_CachedCharacter")
    if character ~= nil then return character end
    local target = field(comp, "Target")
    local character_type = target ~= nil and Safe.try(sdk.typeof, "app.Character") or nil
    if character_type == nil then return nil end
    return Safe.call(target, GET_COMPONENT, character_type)
end

-- The boss bar as shown now (see Gauges.boss), nil when it is not drawn or has no boss.
local function read_boss(b)
    if get(b.go, "get_DrawSelf") ~= true then return nil end
    local hc = field(b.comp, "TargetHitCtrl")
    local character = boss_character(b.comp, hc)
    if character == nil then return nil end
    local shown = { character = character, hc = hc }
    if b.base == nil then
        local all = field(b.comp, "All")
        b.base = all ~= nil and find_element(all, BASE_NAME, MAX_ELEMENTS) or false
    end
    local base = b.base and place(b.base)
    if base then shown.x, shown.y, shown.width = base.x, base.y + base.height / 2, base.width end
    return shown
end

-- The player's HUD as shown now (see Gauges.player), nil when it is not drawn.
local function read_player(p)
    if get(p.go, "get_DrawSelf") ~= true then return nil end
    if p.hp == nil or p.sp == nil then
        if p.all == nil then
            local view = get(p.gui, "get_View")
            p.all = view ~= nil and find_path(view, ALL_PATH) or false
        end
        if p.hp == nil then p.hp = p.all and find_path(p.all, HP_PATH) or false end
        if p.sp == nil then p.sp = p.all and find_path(p.all, SP_PATH) or false end
    end
    return { hp = p.hp and place(p.hp) or nil, sp = p.sp and place(p.sp) or nil }
end

-- What a look found (`found`), or the object kept (`kept`) when the look found its GameObject again; then the kept
-- one's elements under `keys` that were not found are looked for again.
local function keep(found, kept, keys)
    if found == nil or kept == nil or found.addr == nil or found.addr ~= kept.addr then return found end
    for _, key in ipairs(keys) do
        if kept[key] == false then kept[key] = nil end
    end
    return kept
end

-- The scene looked through when the last look is RESCAN_EVERY old. The boss bar and the player's HUD kept are kept on
-- when the look finds their GameObject again, with their elements (one not found is looked for again).
local function refresh(t)
    if looked_at ~= nil and t - looked_at < RESCAN_EVERY then return end
    -- noted first: a look that fails is tried again a second later, not on every frame
    local kept_boss, kept_player = boss, player
    looked_at, bars, boss, player = t, {}, nil, nil
    local found, b, p = look()
    bars = found
    boss = keep(b, kept_boss, { "base" })
    player = keep(p, kept_player, { "all", "hp", "sp" })
end

-- A kept object whose read raised: gone since the look, or the mod's own error (counted).
local function dropped(err)
    if err == GONE then gone = gone + 1 else Hook.fail("gauges", err) end
end

function Gauges.shown(t)
    refresh(t)
    local list = {}
    local i = 1
    while i <= #bars do
        local ok, bar = pcall(read, bars[i])
        if ok then
            if bar then list[#list + 1] = bar end
            i = i + 1
        else
            table.remove(bars, i)
            dropped(bar)
        end
    end
    return list
end

function Gauges.boss(t)
    -- first asked for since the last reset: a look now, one that takes it
    if not boss_wanted then boss_wanted, looked_at = true, nil end
    refresh(t)
    if boss == nil then return nil end
    local ok, shown = pcall(read_boss, boss)
    if ok then return shown end
    boss = nil
    dropped(shown)
    return nil
end

function Gauges.player(t)
    -- first asked for since the last reset: a look now, one that takes it
    if not player_wanted then player_wanted, looked_at = true, nil end
    refresh(t)
    if player == nil then return nil end
    local ok, shown = pcall(read_player, player)
    if ok then return shown end
    player = nil
    dropped(shown)
    return nil
end

function Gauges.gone()
    return gone
end

return Gauges
