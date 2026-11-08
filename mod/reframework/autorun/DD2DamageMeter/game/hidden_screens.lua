-- The three screens the hidden-stats panel stands by (the guild's augments screen, the item screen and the
-- equipment screen; read in the game on 2026-11-06): which one is shown, what is hovered there, whose it is and
-- where the panel goes; and a character's base stats. Read-only: every game access under Safe or pcall, no hooks,
-- no setters; never raises.
--
-- Each screen is a via.gui.GUI whose GameObject has the screen's name, shown while its get_DrawSelf() is true, with an
-- app.<name> component:
--   ui060301_00 "items"      the item screen: the inventory, always the player's;
--   ui060401_00 "equipment"  the equipment-change screen: the component's DispCharaId (app.CharacterID) is the one
--                            shown (Z / C switch);
--     on both, the hovered item is the component's ItemGrid._ItemCtrl:get_SelectedInfo().Storage:get_ItemId();
--   ui040101_00 "augments"   the guild's augments screen: the hovered augment is told by its description only:
--     _TxtAbilityInfo's get_Message(), whitespace normalised (every run of it one space, none at the ends), matched
--     against the static app.GUIBase.getAbilityDetail(id) of the 52 augments Job01_00 .. Job09_04, Job10_00 ..
--     Job10_06 (app.HumanAbilityID), normalised the same way; whose: _CharaTab:get_SelectedCharaID(). Only while the
--     Augments panel is shown: _PnlAbilityRoot (PNL_AbilitySet) and _TxtAbilityInfo each answer
--     get_ActualVisible(), else get_Visible(), not false (one that cannot be read counts as shown); on the other tabs
--     the description keeps its last text.
--
--   HiddenScreens.current(t) -> Hover | nil   (t: seconds)
--     Hover = { kind = "augment", name = "Job05_00" } | { kind = "ring", id = 3502 }, both with
--       screen = "augments" | "items" | "equipment";
--       chara_id: the shown character's app.CharacterID as a non-negative integer (the item screen: the player's),
--         nil when it cannot be read;
--       who = "player" when chara_id is the player's (app.CharacterManager:get_ManualPlayer()'s get_CharaID(), else
--         its <CharaID>k__BackingField), "pawn" when it is another's; always "player" on the item screen; nil when
--         either id cannot be read;
--       anchor = { x, y, width, up, read } in GUI space (1920 x 1080), where the panel goes, each part read anew on
--         every call, but a part read from a scroll list's row (the item screens' y, the guild's width: see below):
--         the item screens: x = /PNL_Main/PNL_Control/PNL_ItemInfo/PNL_Control/txt_Name's global x, y = the
--           first storage row's (PNL_ItemInfo/PNL_Control/SCL_PartyList/PNL_Party00/txt_StorageNum) global y + 40,
--           width = PNL_ItemInfo's get_Size().w; up nil: the panel goes under y;
--         the guild: x = _TxtAbilityInfo's global x; y = the top of the «Используемые усилители» header's bar:
--           /PNL_Main/PNL_Control/PNL_AbilitySet/PNL_TitleBG/s9g_Bg's global y less half its get_Size().h, else
--           PNL_TitleBG's global y; width = the right edge of the table of equipped augments less x (x as
--           given, a fallback one too): the table's first row's HitArea
--           /PNL_Main/PNL_Control/PNL_AbilitySet/SCL_AbList/ITM_List/hit_List, its global x + get_Size().w, the
--           panel's right edge thus the table's; up = true: the panel's bottom goes above y and it grows upwards;
--         a part that cannot be read takes the place measured in the game: x 1212, the row's
--           y 383 and width 470 on the item screens; x 967.4, y 567 and width 523 at the guild (the guild's width
--           too when it is not a positive finite number);
--         read = { x, y, width }: each true when that part was read by its rule, false when it fell back
--           (the guild's y from PNL_TitleBG is a fallback too);
--         the two scroll lists' rows (the first storage row, the equipped table's first row) are not kept, as the
--           game can rebuild a list's rows while its screen stays drawn: the number taken from one (the row's y, the
--           table's right edge) is read from the drawn screen when the hover changes (the screen, the thing, whose)
--           or the screen is drawn again, and again at most every SCAN_EVERY seconds while it cannot be read; the
--           number is kept for that hover, the row is not.
--     nil when none of the three is drawn, when nothing is hovered (no item, an id of 0 or less, an empty or unmatched
--     description), when the guild's Augments panel or its description is not shown, when the hovered item is
--     not a ring (HiddenStatsGame.ring(id, HiddenScreens.job()) gives nil for it), or for a t that is not a finite
--     number.
--   HiddenScreens.base(chara_id) -> Base | nil
--     Base = { who, phys_defence, magic_defence, strength, magic }: the numbers in brackets on the status screen of
--     that character, read anew on each call from app.CharacterManager:get_PlayerStatusCalculatorHolder()'s
--     Calculators (a Dictionary<app.CharacterID, app.PlayerStatusCalculator>: the player and the pawns), the entry
--     whose key is chara_id, found by its enumerator (KeyValuePair key / value, else get_Key / get_Value), else by
--     ContainsKey / get_Item: calcBasicAttackDefence()'s <BasicDefence>, <BasicMagicDefence>, <BasicAttack> and
--     <BasicMagicAttack> k__BackingFields (a calc* method computes and returns; it sets nothing). who as Hover's.
--     nil when chara_id is not a number, has no calculator, or any of the four is not a finite number: never another
--     character's numbers.
--   HiddenScreens.calculator(chara_id) -> app.PlayerStatusCalculator | nil   the calculator base() reads for that
--     character, found as base() finds it (game/stat_check.lua reads the player's); nil when chara_id is not a number
--     or has none.
--   HiddenScreens.player_id() -> integer | nil   the player's app.CharacterID as Hover's chara_id gives it.
--   HiddenScreens.totals(chara_id) -> { phys, magic } | nil   that character's defence and magick defence as the status
--     screen shows them before its floor, read anew on each call from the calculator base() reads for it:
--     calcAttackDefenceWithEquipmentAndBuff()'s <BasicDefence> + <AdditionalDefence> + <ArmorDefence> and the same
--     three of MagicDefence (k__BackingFields; in the game 380 + 159 + 1106 = 1645, the screen's «1645 (380)»); each
--     nil when one of its three is not a finite number; nil when chara_id is not a number, has no calculator or no
--     struct, or neither can be read: never another character's.
--   HiddenScreens.equipped(chara_id) -> { augments, items } | nil   what that character has on, read anew; a
--     part is nil, unknown, unless it was read whole (what is not read is never taken as "not on"):
--     augments = { [name] = true }: HiddenScreens.augments of its Human's <AbilityContext>k__BackingField for its
--       Human's vocation (get_JobContext().CurrentJob); the Human is the player's get_ManualPlayer():get_Human() when
--       chara_id is the player's (as game/stat_check.lua reads it), else (and when that gives none) the calculator's
--       Human field, never another character's; nil when the Human, its vocation (None too) or its
--       AbilityContext cannot be read, or the read is not whole: a slot gives no number, or an id other than 0 has
--       no name in app.HumanAbilityID;
--     items = { [id] = true }: HiddenScreens.equips of the calculator's getEquipData().Data.Equips; nil when it
--       cannot be read or the read is not whole: an entry cannot be had or gives no id, or the array is longer than
--       MAX_EQUIPS;
--     nil when chara_id is not a number.
--   HiddenScreens.augments(context, job) -> { name... } | nil, whole, all_read   the app.HumanAbilityID names
--     ("Job05_00"; an id without a name, its number as text) of an app.AbilityContext's getAbility(job, slot) for
--     slots No0..No6 (app.AbilityContext.AbilitySlot's seven; in the game each answers a number, 0 for an empty one),
--     an empty slot (0) left out, sorted; a slot that gives nothing is left out while another slot can be read; nil
--     when none can be read. whole: every slot gave a number and every id other than 0 has a name; all_read: every
--     slot gave a number (game/stat_check.lua takes the player's only then); both false with nil.
--   HiddenScreens.equips(equips) -> { id... } | nil, whole   the item ids above 0 of an Equips array
--     (app.ItemDefine.StorageData[], a game array: read by get_elements, its get_Item gives nil), in its order, at most
--     MAX_EQUIPS entries; a null entry is an empty slot, an entry that cannot be had or gives no id is left out; nil
--     when the array cannot be read. whole: no entry was left out and the array has at most MAX_EQUIPS entries (false
--     with nil, and when its length cannot be read: then its entries are walked as Safe.items walks them).
--   HiddenScreens.job(chara_id) -> integer | nil   a current vocation (app.Character.JobEnum 1..10):
--     with chara_id, that character's: the Human field of the calculator base() reads for it, get_JobContext()
--     .CurrentJob; without chara_id, or when that cannot be read (no calculator, no Human, None), the player's:
--     get_ManualPlayer():get_Human():get_JobContext().CurrentJob; nil when that is unreadable or None (0) too.
--   HiddenScreens.reset()   forgets the screens found and the texts read (a new game session)
--   HiddenScreens.forget()  forgets the screens found and their elements, not the texts read; the next call looks at
--     once (the world may be going, a scene change, no player character)
--   HiddenScreens.kept() -> the number of screens kept
--   HiddenScreens.gone() -> the number of screens kept that were dropped because their get_DrawSelf raised (the
--     game destroyed them under the mod), since the mod was loaded; forget and reset leave it
--
-- Cost. While none of the screens kept is drawn, the scene's GUIs (via.SceneManager get_CurrentScene,
-- findComponents(via.gui.GUI), at most MAX_GUIS) are looked through at most once every SCAN_EVERY seconds; a look keeps
-- each of the three it finds (of two of one name, the drawn one), and a screen found again at the same address keeps
-- what was found under it. A kept screen stays while it exists: it is forgotten with everything under it when the
-- world may be going (the mod calls forget at each scene-type change and in the first frame without a player
-- character, and does not call current in a frame without one), and dropped when a look does not find it or its
-- get_DrawSelf raises (the game destroyed it under the mod: the last guard, counted by gone). Its elements are read
-- only in a frame its get_DrawSelf said it is drawn. The hovered thing, whose and the anchor are read on every call.
-- The item screens' description elements and the guild's header are found under the GUI's get_View by their names
-- as direct children, the first time the screen is read, and again at most every SCAN_EVERY seconds while one is
-- missing or its position cannot be read; the scroll lists' rows are found the same way each time they are read
-- (at a hover change). The 52 descriptions are read on the first non-empty description, and again
-- when a description matches none of the texts read so far, at most every REREAD_EVERY seconds (the game's language
-- can change); the texts of every language read are kept, so a language read once matches without a read.
local Safe = require("DD2DamageMeter/game/safe")
local Hook = require("DD2DamageMeter/game/hook")
local NamesGame = require("DD2DamageMeter/game/names_game")
local HiddenStatsGame = require("DD2DamageMeter/game/hidden_stats")

local HiddenScreens = {}

local SCAN_EVERY = 0.5     -- seconds between two looks through the scene's GUIs while no screen kept is drawn
local REREAD_EVERY = 3     -- seconds between two reads of the 52 descriptions on a description that matches none
local MAX_GUIS = 512       -- the scene's first GUIs looked at in one look (game/gauges.lua: the game had 30 to 80)
local MAX_CHILDREN = 64    -- an element's children looked at for one name
local MAX_CALCULATORS = 16 -- calculator entries looked at (the game had 4: the player and three pawns)
local MAX_EQUIPS = 32      -- equipment slots looked at
local SLOTS = 6            -- augment slots 0..SLOTS: app.AbilityContext.AbilitySlot No0..No6

local GET_COMPONENT = "getComponent(System.Type)"
local ABILITY_ID = "app.HumanAbilityID"
local GET_DETAIL = "getAbilityDetail(app.HumanAbilityID)"
local GET_ABILITY = "getAbility(app.Character.JobEnum, app.AbilityContext.AbilitySlot)"
local ABILITY_CONTEXT = "<AbilityContext>k__BackingField"

local SCREENS = { ui040101_00 = "augments", ui060301_00 = "items", ui060401_00 = "equipment" }
local ORDER = { "ui040101_00", "ui060301_00", "ui060401_00" }

-- The item screens' elements, each name a direct child of the one before (as read in the game): PNL_ItemInfo under the
-- view, then the description's name and the first storage row under PNL_ItemInfo.
local INFO_PATH = { "PNL_Main", "PNL_Control", "PNL_ItemInfo" }
local NAME_PATH = { "PNL_Control", "txt_Name" }
local ROW_PATH = { "PNL_Control", "SCL_PartyList", "PNL_Party00", "txt_StorageNum" }
local ROW_GAP = 40
-- The guild's «Используемые усилители» header (as read in the game): PNL_TitleBG under the view, its bar s9g_Bg
-- (a Scale9Grid, its global position its centre) a direct child of it.
local TITLE_PATH = { "PNL_Main", "PNL_Control", "PNL_AbilitySet", "PNL_TitleBG" }
local BAR = "s9g_Bg"
-- The first row of the guild's table of equipped augments: its via.gui.HitArea, under the view; its global x
-- the table's left edge, x + get_Size().w its right edge (the rows item1 .. item7 have one at the same x and width).
local EQUIPPED_PATH = { "PNL_Main", "PNL_Control", "PNL_AbilitySet", "SCL_AbList", "ITM_List", "hit_List" }
-- Where they were measured in the game (GUI space), for a part that cannot be read
local ITEM_X, ITEM_ROW_Y, ITEM_WIDTH = 1212, 383, 470
local GUILD_X, GUILD_HEADER_Y, GUILD_WIDTH = 967.4, 567, 523

local BASE_FIELDS = {
    phys_defence = "<BasicDefence>k__BackingField", magic_defence = "<BasicMagicDefence>k__BackingField",
    strength = "<BasicAttack>k__BackingField", magic = "<BasicMagicAttack>k__BackingField",
}

-- The three parts of each total the status screen shows, of calcAttackDefenceWithEquipmentAndBuff.
local TOTAL_PARTS = {
    phys = { "<BasicDefence>k__BackingField", "<AdditionalDefence>k__BackingField", "<ArmorDefence>k__BackingField" },
    magic = { "<BasicMagicDefence>k__BackingField", "<AdditionalMagicDefence>k__BackingField",
              "<ArmorMagicDefence>k__BackingField" },
}

-- The 52 augments: five a vocation, seven the Warfarer's.
local AUGMENTS = {}
for job = 1, 10 do
    for slot = 0, job == 10 and 6 or 4 do AUGMENTS[#AUGMENTS + 1] = string.format("Job%02d_%02d", job, slot) end
end

local screens = {}   -- GUI name -> { screen, gui, go, comp, addr, els, row } of each screen kept; els: the elements
                     -- found, the item screens' { info, name, complete, tried_at }, the guild's { title, bar,
                     -- complete, tried_at }; row: { key, value, tried_at }, the number read from its scroll list's row
                     -- for the hover `key` (row_value)
local looked_at = nil -- t of the last look through the GUIs
local by_text = {}   -- normalised description -> augment name, false when two augments of one language share it;
                     -- every language read
local read_at = nil  -- t of the last read of the descriptions
local gone = 0       -- screens kept that were dropped because their get_DrawSelf raised, since the mod was loaded
local drawn_last = nil -- the screen kept that the last call found drawn (its scroll-list numbers are read anew
                       -- when another one, or none, was)

function HiddenScreens.reset()
    screens, looked_at, by_text, read_at, drawn_last = {}, nil, {}, nil, nil
end

function HiddenScreens.forget()
    screens, looked_at, drawn_last = {}, nil, nil
end

function HiddenScreens.kept()
    local n = 0
    for _ in pairs(screens) do n = n + 1 end
    return n
end

function HiddenScreens.gone()
    return gone
end

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function due(last, t, every)
    return last == nil or t < last or t - last >= every
end

-- whose ---------------------------------------------------------------------------------------------------------------

-- A CharacterID as a non-negative integer: the game's ids pass 2^31 (2891076981), so one given as a signed 32-bit
-- number is turned back. nil for anything else.
local function chara(v)
    local id = Safe.enum(v)
    if id ~= nil and id < 0 and id >= -0x80000000 then id = id + 0x100000000 end
    return id
end

local function manual_player()
    return Safe.call(Safe.singleton("app.CharacterManager"), "get_ManualPlayer")
end

local function player_id()
    local player = manual_player()
    if player == nil then return nil end
    local id = chara(Safe.call(player, "get_CharaID"))
    if id == nil then id = chara(Safe.field(player, "<CharaID>k__BackingField")) end
    return id
end

local function who_of(id)
    if id == nil then return nil end
    local mine = player_id()
    if mine == nil then return nil end
    return id == mine and "player" or "pawn"
end

-- the screens ---------------------------------------------------------------------------------------------------------

local function current_scene()
    local manager = Safe.try(sdk.get_native_singleton, "via.SceneManager")
    local td = Safe.type("via.SceneManager")
    if manager == nil or td == nil then return nil end
    return Safe.try(sdk.call_native_func, manager, td, "get_CurrentScene")
end

local function m_elements(arr) return arr:get_elements() end

-- The three screens among the scene's GUIs (of two of one name, the first drawn one, else the first); one found again
-- at the address of the one kept stays the one kept.
local function look(t)
    looked_at = t
    local found = {}
    local gui_type = Safe.try(sdk.typeof, "via.gui.GUI")
    local scene = gui_type ~= nil and current_scene() or nil
    local guis = scene ~= nil and Safe.call(scene, "findComponents(System.Type)", gui_type) or nil
    for _, gui in ipairs(Safe.items(guis ~= nil and Safe.try(m_elements, guis) or nil, MAX_GUIS)) do
        local go = gui and Safe.call(gui, "get_GameObject") or nil
        local name = go ~= nil and Safe.call(go, "get_Name") or nil
        local screen = type(name) == "string" and SCREENS[name] or nil
        if screen and not (found[name] and found[name].drawn) then
            local drawn = Safe.call(go, "get_DrawSelf") == true
            if found[name] == nil or drawn then
                local comp_type = Safe.try(sdk.typeof, "app." .. name)
                local comp = comp_type ~= nil and Safe.call(go, GET_COMPONENT, comp_type) or nil
                if comp ~= nil then
                    found[name] = { screen = screen, gui = gui, go = go, comp = comp, addr = Safe.address(go),
                                    drawn = drawn, els = {} }
                end
            end
        end
    end
    for _, name in ipairs(ORDER) do
        local new, kept = found[name], screens[name]
        if new and kept and new.addr ~= nil and new.addr == kept.addr then new = kept end
        screens[name] = new
    end
end

local function m_call(obj, name) return obj:call(name) end

-- The first kept screen drawn now; one whose get_DrawSelf raises is gone and dropped (the last guard, counted).
local function drawn_screen()
    for _, name in ipairs(ORDER) do
        local s = screens[name]
        if s then
            local ok, drawn = pcall(m_call, s.go, "get_DrawSelf")
            if not ok then
                screens[name] = nil
                gone = gone + 1
            elseif drawn == true then
                return s
            end
        end
    end
    return nil
end

-- elements ------------------------------------------------------------------------------------------------------------

-- The direct child of `el` called `name`, nil when it is not among its first MAX_CHILDREN.
local function child(el, name)
    local c = Safe.call(el, "get_Child")
    for _ = 1, MAX_CHILDREN do
        if c == nil then return nil end
        if Safe.call(c, "get_Name") == name then return c end
        c = Safe.call(c, "get_Next")
    end
    return nil
end

local function path(el, names)
    for _, name in ipairs(names) do
        if el == nil then return nil end
        el = child(el, name)
    end
    return el
end

local function v_x(v) return v.x end
local function v_y(v) return v.y end
local function v_w(v) return v.w end
local function v_h(v) return v.h end

-- The element's global position, nil, nil when it is not two finite numbers.
local function position(el)
    local pos = Safe.call(el, "get_GlobalPosition")
    if pos == nil then return nil, nil end
    local x, y = Safe.try(v_x, pos), Safe.try(v_y, pos)
    if finite(x) and finite(y) then return x, y end
    return nil, nil
end

-- The element's get_Size() w and h as gauges.lua's place() reads them, each nil unless a finite number above 0.
local function size(el)
    local s = Safe.call(el, "get_Size")
    if s == nil then return nil, nil end
    local w, h = Safe.try(v_w, s), Safe.try(v_h, s)
    return (finite(w) and w > 0) and w or nil, (finite(h) and h > 0) and h or nil
end

-- The item screen's elements, looked for when one is missing and the last try is SCAN_EVERY old.
local function item_elements(s, t)
    local els = s.els
    if els.complete or not due(els.tried_at, t, SCAN_EVERY) then return els end
    els.tried_at = t
    if els.info == nil then els.info = path(Safe.call(s.gui, "get_View"), INFO_PATH) end
    if els.name == nil then els.name = path(els.info, NAME_PATH) end
    els.complete = els.info ~= nil and els.name ~= nil
    return els
end

-- The number `read(arg)` takes from a scroll list's row of the drawn screen `s`, for the hover `key`: read when
-- the hover changes (or the screen was drawn again: current forgets s.row then), and again at most every SCAN_EVERY
-- seconds while it gives nil; kept for that hover in between. The row itself is never kept.
local function row_value(s, key, t, read, arg)
    local r = s.row
    if r == nil or r.key ~= key then
        r = { key = key }
        s.row = r
    elseif r.value ~= nil or not due(r.tried_at, t, SCAN_EVERY) then
        return r.value
    end
    r.tried_at = t
    r.value = read(arg)
    return r.value
end

-- The first storage row's global y, found anew under PNL_ItemInfo; nil when it cannot be read.
local function storage_row_y(els)
    local _, y = position(path(els.info, ROW_PATH))
    return y
end

-- An element kept whose position cannot be read is looked for again.
local function item_anchor(s, t, key)
    local els = item_elements(s, t)
    local x = position(els.name)
    if x == nil and els.name ~= nil then els.name, els.complete = nil, false end
    local row_y = row_value(s, key, t, storage_row_y, els)
    local width = size(els.info)
    return { x = x or ITEM_X, y = (row_y or ITEM_ROW_Y) + ROW_GAP, width = width or ITEM_WIDTH,
             read = { x = x ~= nil, y = row_y ~= nil, width = width ~= nil } }
end

-- The guild screen's header, looked for when a part of it is missing and the last try is SCAN_EVERY old.
local function guild_elements(s, t)
    local els = s.els
    if els.complete or not due(els.tried_at, t, SCAN_EVERY) then return els end
    els.tried_at = t
    if els.title == nil then els.title = path(Safe.call(s.gui, "get_View"), TITLE_PATH) end
    if els.bar == nil then els.bar = child(els.title, BAR) end
    els.complete = els.title ~= nil and els.bar ~= nil
    return els
end

-- The header bar's top: the bar's centre less half its height, and true; else the header panel's y (nil when it is
-- not read either), and false. An element kept whose position cannot be read is looked for again.
local function header_top(els)
    local _, bar_y = position(els.bar)
    if bar_y == nil and els.bar ~= nil then els.bar, els.complete = nil, false end
    local _, bar_h = size(els.bar)
    if bar_y ~= nil and bar_h ~= nil then return bar_y - bar_h / 2, true end
    local _, title_y = position(els.title)
    if title_y == nil and els.title ~= nil then els.title, els.complete = nil, false end
    return title_y, false
end

-- The equipped table's right edge: its first row's global x + get_Size().w, the row found anew under the
-- screen's view; nil when either cannot be read or the sum is not finite.
local function table_edge(s)
    local row = path(Safe.call(s.gui, "get_View"), EQUIPPED_PATH)
    local x, w = position(row), size(row)
    if x == nil or w == nil then return nil end
    local edge = x + w
    if finite(edge) then return edge end
    return nil
end

-- From the anchor's x to the equipped table's right edge (the edge read for the hover `key`, row_value), and
-- true; nil, false when the edge cannot be read or the width is not a positive finite number.
local function table_width(s, t, key, x)
    local edge = row_value(s, key, t, table_edge, s)
    if edge == nil then return nil, false end
    local width = edge - x
    if finite(width) and width > 0 then return width, true end
    return nil, false
end

local function guild_anchor(s, t, text, key)
    local x = position(text)
    local els = guild_elements(s, t)
    local y, y_read = header_top(els)
    local width, width_read = table_width(s, t, key, x or GUILD_X)
    return { x = x or GUILD_X, y = y or GUILD_HEADER_Y, width = width or GUILD_WIDTH, up = true,
             read = { x = x ~= nil, y = y_read, width = width_read } }
end

-- what is hovered -----------------------------------------------------------------------------------------------------

-- Every run of whitespace one space, none at the ends; nil for an empty text or not a string.
local function normal(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    if text == "" then return nil end
    return text
end

-- The 52 descriptions in the game's language now, added to those of the languages read before.
local function read_texts(t)
    read_at = t
    local now = {}
    for _, name in ipairs(AUGMENTS) do
        local id = NamesGame.enum_value(ABILITY_ID, name)
        local text = id ~= nil and normal(Safe.static("app.GUIBase", GET_DETAIL, id)) or nil
        if text then
            if now[text] == nil then now[text] = name else now[text] = false end
        end
    end
    for text, name in pairs(now) do by_text[text] = name end
end

local function augment_of(message, t)
    local text = normal(message)
    if text == nil then return nil end
    local name = by_text[text]
    if name == nil and due(read_at, t, REREAD_EVERY) then
        read_texts(t)
        name = by_text[text]
    end
    return name or nil
end

-- Whether a GUI element is shown: get_ActualVisible(), else get_Visible(), not false; one that cannot be read counts
-- as shown (a missing method must not hide the panel everywhere).
local function shown(el)
    local v = Safe.call(el, "get_ActualVisible")
    if v == nil then v = Safe.call(el, "get_Visible") end
    return v ~= false
end

-- Only while the Augments panel is shown: the description keeps its last text on the other tabs.
local function augment_hover(s, t)
    local text = Safe.field(s.comp, "_TxtAbilityInfo")
    if not (shown(Safe.field(s.comp, "_PnlAbilityRoot")) and shown(text)) then return nil end
    local name = augment_of(Safe.call(text, "get_Message"), t)
    if name == nil then return nil end
    local chara_id = chara(Safe.call(Safe.field(s.comp, "_CharaTab"), "get_SelectedCharaID"))
    local key = s.screen .. "|" .. name .. "|" .. tostring(chara_id)
    return { kind = "augment", name = name, screen = s.screen, who = who_of(chara_id), chara_id = chara_id,
             anchor = guild_anchor(s, t, text, key) }
end

-- The hovered item's id, nil when there is none.
local function item_id(comp)
    local ctrl = Safe.field(Safe.field(comp, "ItemGrid"), "_ItemCtrl")
    local storage = Safe.field(Safe.call(ctrl, "get_SelectedInfo"), "Storage")
    local id = Safe.enum(Safe.call(storage, "get_ItemId"))
    if id == nil or id <= 0 then return nil end
    return id
end

local function ring_hover(s, t)
    local id = item_id(s.comp)
    -- whether it is a ring does not hang on the vocation: the player's, the one the panel reads the player's rings by
    -- (a pawn's are read by the pawn's), so his ring is read once
    if id == nil or HiddenStatsGame.ring(id, HiddenScreens.job()) == nil then return nil end
    local chara_id, who
    if s.screen == "items" then
        chara_id, who = player_id(), "player"
    else
        chara_id = chara(Safe.field(s.comp, "DispCharaId"))
        who = who_of(chara_id)
    end
    local key = s.screen .. "|" .. id .. "|" .. tostring(chara_id)
    return { kind = "ring", id = id, screen = s.screen, who = who, chara_id = chara_id,
             anchor = item_anchor(s, t, key) }
end

local function current(t)
    local s = drawn_screen()
    if s == nil and due(looked_at, t, SCAN_EVERY) then
        look(t)
        s = drawn_screen()
    end
    -- a screen drawn again (or after another) reads its scroll list's row anew
    if s ~= drawn_last then
        if s ~= nil then s.row = nil end
        drawn_last = s
    end
    if s == nil then return nil end
    if s.screen == "augments" then return augment_hover(s, t) end
    return ring_hover(s, t)
end

function HiddenScreens.current(t)
    if not finite(t) then return nil end
    local ok, hover = pcall(current, t)
    if ok then return hover end
    Hook.fail("hidden_screens", hover)
    return nil
end

-- the base ------------------------------------------------------------------------------------------------------------

-- The calculator whose key is `id`: by the dictionary's enumerator, else by ContainsKey / get_Item.
local function calculator_of(dict, id)
    local en = Safe.call(dict, "GetEnumerator")
    if en ~= nil then
        for _ = 1, MAX_CALCULATORS do
            if Safe.call(en, "MoveNext") ~= true then break end
            local kv = Safe.call(en, "get_Current")
            local key = Safe.field(kv, "key")
            if key == nil then key = Safe.call(kv, "get_Key") end
            if chara(key) == id then
                local value = Safe.field(kv, "value")
                if value == nil then value = Safe.call(kv, "get_Value") end
                if value ~= nil then return value end
            end
        end
    end
    if Safe.call(dict, "ContainsKey", id) ~= true then return nil end
    return Safe.call(dict, "get_Item", id)
end

-- The status calculator of the character `id` (a CharacterID as chara() gives it), nil when it has none.
local function calculator(id)
    local holder = Safe.call(Safe.singleton("app.CharacterManager"), "get_PlayerStatusCalculatorHolder")
    local dict = Safe.field(holder, "Calculators")
    if dict == nil then return nil end
    return calculator_of(dict, id)
end

local function read_base(chara_id)
    local id = chara(chara_id)
    if id == nil then return nil end
    local status = Safe.call(calculator(id), "calcBasicAttackDefence")
    if status == nil then return nil end
    local base = {}
    for key, field in pairs(BASE_FIELDS) do
        local v = Safe.field(status, field)
        if not finite(v) then return nil end
        base[key] = v
    end
    base.who = who_of(id)
    return base
end

function HiddenScreens.base(chara_id)
    local ok, base = pcall(read_base, chara_id)
    if ok then return base end
    Hook.fail("hidden_screens", base)
    return nil
end

local function calculator_by(chara_id)
    local id = chara(chara_id)
    if id == nil then return nil end
    return calculator(id)
end

function HiddenScreens.calculator(chara_id)
    local ok, calc = pcall(calculator_by, chara_id)
    if ok then return calc end
    Hook.fail("hidden_screens", calc)
    return nil
end

function HiddenScreens.player_id()
    local ok, id = pcall(player_id)
    if ok then return id end
    Hook.fail("hidden_screens", id)
    return nil
end

-- the vocation ------------------------------------------------------------------------------------------------------

-- An app.Human's current vocation, nil when it cannot be read or is None (0).
local function job_of(human)
    local context = Safe.call(human, "get_JobContext")
    local job = Safe.enum(Safe.field(context, "CurrentJob"))
    if job == nil or job < 1 then return nil end
    return job
end

-- The vocation of the character `chara_id` by its calculator's Human, nil when it cannot be read.
local function chara_job(chara_id)
    local id = chara(chara_id)
    if id == nil then return nil end
    return job_of(Safe.field(calculator(id), "Human"))
end

function HiddenScreens.job(chara_id)
    if chara_id ~= nil then
        local ok, job = pcall(chara_job, chara_id)
        if not ok then Hook.fail("hidden_screens", job) end
        if ok and job ~= nil then return job end
    end
    return job_of(Safe.call(manual_player(), "get_Human"))
end

-- the totals and what is on ---------------------------------------------------------------------------------------

local function read_totals(chara_id)
    local id = chara(chara_id)
    if id == nil then return nil end
    local status = Safe.call(calculator(id), "calcAttackDefenceWithEquipmentAndBuff")
    if status == nil then return nil end
    local out = {}
    for key, parts in pairs(TOTAL_PARTS) do
        local sum = 0
        for _, field in ipairs(parts) do
            local v = Safe.field(status, field)
            if not finite(v) then
                sum = nil
                break
            end
            sum = sum + v
        end
        out[key] = sum
    end
    if out.phys == nil and out.magic == nil then return nil end
    return out
end

function HiddenScreens.totals(chara_id)
    local ok, totals = pcall(read_totals, chara_id)
    if ok then return totals end
    Hook.fail("hidden_screens", totals)
    return nil
end

-- The augments' names, sorted, whether the read is whole and whether every slot gave a number; nil, false, false
-- when no slot can be read (an empty slot reads 0: a slot that gives nothing is not read, and with none read the
-- augments are unknown, not empty).
local function augments_of(context, job)
    if context == nil then return nil, false, false end
    local out, read, whole, all_read = {}, 0, true, true
    for slot = 0, SLOTS do
        local id = Safe.enum(Safe.call(context, GET_ABILITY, job, slot))
        if id == nil then
            whole, all_read = false, false
        else
            read = read + 1
            if id ~= 0 then
                local name = NamesGame.enum_name(ABILITY_ID, id)
                if name == nil then whole = false end
                out[#out + 1] = name or tostring(id)
            end
        end
    end
    if read == 0 then return nil, false, false end
    table.sort(out)
    return out, whole, all_read
end

function HiddenScreens.augments(context, job)
    local ok, list, whole, all_read = pcall(augments_of, context, job)
    if ok then return list, whole, all_read end
    Hook.fail("hidden_screens", list)
    return nil, false, false
end

local function c_len(c) return #c end
local function c_at(c, i) return c[i] end

-- An entry's item id: 0 for a null entry (an empty slot), nil when it cannot be had or gives no id.
local function entry_id(elements, i)
    local ok, entry = pcall(c_at, elements, i)
    if not ok then return nil end
    if not entry then return 0 end
    return Safe.enum(Safe.call(entry, "get_ItemId"))
end

-- The item ids above 0 of the Equips array, in its order, and whether the read is whole; nil, false when it cannot
-- be read.
local function equips_of(equips)
    if equips == nil then return nil, false end
    local elements = Safe.try(m_elements, equips)
    if elements == nil then return nil, false end
    local ids, whole = {}, true
    local n = Safe.try(c_len, elements)
    if math.type(n) ~= "integer" then
        -- no length: walked as Safe.items walks it, a null entry and one that cannot be had alike, so not whole
        for _, entry in ipairs(Safe.items(elements, MAX_EQUIPS)) do
            local id = entry and Safe.enum(Safe.call(entry, "get_ItemId")) or nil
            if id ~= nil and id > 0 then ids[#ids + 1] = id end
        end
        return ids, false
    end
    if n > MAX_EQUIPS then whole = false end
    for i = 1, math.min(n, MAX_EQUIPS) do
        local id = entry_id(elements, i)
        if id == nil then
            whole = false
        elseif id > 0 then
            ids[#ids + 1] = id
        end
    end
    return ids, whole
end

function HiddenScreens.equips(equips)
    local ok, ids, whole = pcall(equips_of, equips)
    if ok then return ids, whole end
    Hook.fail("hidden_screens", ids)
    return nil, false
end

-- A list read whole as a set; nil for nil or a read that is not whole.
local function set_of(list, whole)
    if list == nil or whole ~= true then return nil end
    local set = {}
    for _, v in ipairs(list) do set[v] = true end
    return set
end

local function read_equipped(chara_id)
    local id = chara(chara_id)
    if id == nil then return nil end
    local calc = calculator(id)
    local human = nil
    if id == player_id() then human = Safe.call(manual_player(), "get_Human") end
    if human == nil then human = Safe.field(calc, "Human") end
    local job = job_of(human)
    local augments = nil
    if job ~= nil then augments = set_of(augments_of(Safe.field(human, ABILITY_CONTEXT), job)) end
    local equips = Safe.field(Safe.field(Safe.call(calc, "getEquipData"), "Data"), "Equips")
    return { augments = augments, items = set_of(equips_of(equips)) }
end

function HiddenScreens.equipped(chara_id)
    local ok, on = pcall(read_equipped, chara_id)
    if ok then return on end
    Hook.fail("hidden_screens", on)
    return nil
end

return HiddenScreens
