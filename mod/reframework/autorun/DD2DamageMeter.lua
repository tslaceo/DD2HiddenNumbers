-- DD2DamageMeter: a damage meter for Dragon's Dogma 2 (REFramework). This file wires the parts together:
--   at load    settings (reframework/data/DD2DamageMeter/settings.json), language, the hooks (game/hits.lua,
--              game/heals.lua, the scene change) and the self-check: game methods that cannot be found (hooked, or
--              only called: the battle mode, the party, a hit's HP, victim and element, names, an enemy's data) are
--              listed in DD2DM.info().missing and in a one-line notice, and everything else keeps working;
--   each frame battle mode -> fight clock -> Fight -> history, the party's HP poll, the overlay and the toggle key,
--              the journal's key, the settings window's key, the game's pause and the hidden-stats panel; while the
--              journal is open, its keys, models and window instead of the overlay (and no pause read, no panel);
--              while the settings window is open, its keys, model and window by the overlay;
--   menu       in REFramework's own window a line that says where the settings are, a button that opens the
--              settings window and the settings key's button (ui/menu.lua).
-- Hits and heals reach only the open fight, which counts the ones that involve the party or an enemy the party fought
-- (fight.lua); a fight ends 3 s after the game's battle mode drops, and a battle that comes back inside that time, or
-- a party hit on one of its enemies, keeps it going; a hit on any other enemy starts a new fight (clock.lua).
-- A new fight that opens at most RETURN_WINDOW (30) s after the last kept fight ended may be that fight going on
-- (the game can end a battle when the player falls and is put back, and make the enemy anew): its first friend's blow
-- on a living enemy decides, if it lands inside those 30 s. When that enemy has the CharaID of an enemy the kept fight
-- left alive, and an HP before the blow at most RETURN_HP_BELOW (2 %) of that enemy's max HP below the HP it was left
-- with and at most RETURN_HP_ABOVE (0.1 %, at least 1 HP) above it (an enemy does not come back healed, but it
-- can come back a little lower: damage after the finish, DoT ticks), the kept fight goes on in place of the new one:
-- the new object counts as that enemy (fight.lua's alias), the hits and heals the new fight took before the blow (at
-- most RETURN_KEEP) are counted in it, the time from its end to the new fight's start is no fighting time, and when
-- it ends again its snapshot takes its own history entry's place (the journal stays on what it showed; history.json
-- is written as after any kept fight). Only the newest kept fight can be continued, and only a kept one; the
-- clock knows nothing of it, and a new world keeps it (reset_world).
-- While a fight is open each party member's skill state is read once per frame (one field each): a heal with no other
-- source just after a member's Argent Tonic is hers (game/heals.lua).
-- A heal on a party member or an ally that the game gave no source for (game/heals.lua: no healer, source
-- "other") is his own: lifesteal when the game asked for at least 10 HP and it comes at most 3 frames after a hit of
-- his on an enemy began (its damageProc started, game/hits.lua: the game can heal him inside it, before the hit is
-- counted), else regeneration (attrib.lua).
-- An enemy's own damage (a slam after being blown away) at most 3 s after a friend's hit on it comes from
-- game/hits.lua as that friend's hit (Hit.knock): counted, drawn and kept as the friend's, never fed to the
-- enemy plate (no attack of the player's).
-- A finished fight is kept (history, summary) only when it has a hit
-- between the party and an enemy that is not a DoT tick and whose victim still had HP; such ticks and blows
-- on a corpse do not start a fight either (game/hits.lua). Everything read from the game is reset when the player
-- character is gone at a scene change, or when a party read finds another player character (a loaded save).
-- The window's models are built with the switches in the settings (live_*, show_allies, summary_*): a block that is
-- off is not built, and a change in the settings window rebuilds them at once.
-- With the setting `debug` on, reframework/data/DD2DamageMeter/debug.log gets one line per finished fight (and after
-- it one with the enemy plate's cost since the last such line), per resume after a short break of the battle, per
-- fight continued by a returning enemy and per caught error; it starts afresh in each game session and stops at
-- 5 MB. With it on, and never while the game is paused in a menu, the debug collector (game/collector.lua) also
-- writes what the mod meets in the game to reframework/data/DD2DamageMeter/collect.jsonl: each enemy kind's table in
-- each state, the first time the plate (a kind in sight, met after the plate's frame) or a hit on a living one meets
-- it; the player's weapons and enchants (looked at once a second); the enemy step's bonuses, the sourceless hits on
-- enemies and the knock hits, from the hit sink (game/hits.lua reads their fields only then); a party member's
-- new character object (game/actors.lua); and the hidden-stats evidence: a snapshot of the player's
-- numbers and equipment (game/stat_check.lua) every 2 s and 1 s after a pause's end, a record each time his
-- augments or gear changed together with his numbers (a new world, or what changed while `debug` was off, is no
-- change). The file is appended to, kept across game sessions, and stops at 200 MB with one debug.log line; debug.log
-- also gets its size at the session's first record, after each fight's plate line one with the meets' cost, and once
-- a game session one when the player's augments cannot be read for the evidence (stat_sample). Each time the
-- hidden-stats panel stops being shown (nothing hovered on its screens any more), debug.log gets one line with its
-- cost since the last such line (log_hidden_cost); the first time in a game session it is placed on a screen by an
-- anchor with a part that fell back to its measured place, one line naming the parts (tell_anchor).
-- With the setting `history_file` on, the kept fights (with their detail) are read from reframework/data/DD2DamageMeter/
-- history.json once per Lua state (when it first loads this file, or else when the setting is switched on), and the
-- whole history is written there (history_file.lua, at most 4 MB) after each kept fight, in the frame callback (a
-- fight can end inside a hook: its write waits for the next frame), and when the setting is switched on; off, the file
-- is never read, written or touched.
-- The journal (ui/journal.lua; with the setting `journal` on) opens and closes on the press of `journal_key` (not while
-- a key wait holds the keys back), on the fight the summary shows. While it is open the overlay is not drawn, and the
-- keys of JournalUI.KEYS change its tab, fight, selection and page (a key that is also the toggle key or the settings
-- key acts only for the journal); the game receives them too. Its models are built only while it is open and
-- something changed (its tab, fight or selection, the language, a setting, a kept fight; not its page, which only the
-- drawing reads); closed, it costs one key read per frame. Opened on another fight, or when a kept fight changes the
-- fight it shows, it starts its selections and pages afresh; a fight continued that takes its own entry's place
-- changes no index, and its selections and pages stay.
-- The settings window (ui/settings_window.lua, its model settings_view.lua) holds every setting. It opens and closes
-- on the press of `settings_key` (also with the journal off; not while a key wait holds the keys back) or with the
-- menu's button. It and the journal never open together: opening one closes the other. While it is open the meter is
-- shown, hidden or not (the open fight, else the last kept fight's summary), so that each change is seen at once, and
-- the keys of SettingsUI.KEYS move its selection and change values (a key that is also the toggle key or the journal
-- key acts only for it; the game receives them too). A key wait ends when REFramework's menu opens or closes. A change
-- from it or from the menu goes through settings:set, then apply_changes (the language, the history, history.json, the
-- models). Its model is built only while it is open and a value or the language changed; closed, it costs one key read
-- per frame. The settings are saved when it and REFramework's menu are both closed again, and every 5 s while one of
-- them is open.
-- The enemy HP numbers (ui/enemy_bars.lua; the settings `enemy_hp_numbers` and `boss_hp_numbers`, each "off" or a
-- format, and `enemy_hp_size`, the size of both): over each HP bar the game draws now above a hostile character's
-- head, and right of the boss bar it draws at the top of the screen (game/gauges.lua), that character's HP as the
-- meter reads it (game/actors.lua), drawn first in the frame on the background list, so that the meter and the
-- settings window are in front; none while the journal is open. Each one off is neither read nor drawn, and a
-- setting switched off forgets the bars found. The HP they read in a frame is also the open fight's enemy's under
-- that bar (Fight:note_hp) and, when the live window's enemy line is about that enemy, that line's in the same frame
-- (meter_hp); with both off the line goes by the counted hits alone, built every LIVE_EVERY s.
-- The damage numbers (damage_numbers.lua, ui/damage_numbers.lua; the settings `damage_numbers`,
-- `damage_numbers_style`, `damage_numbers_size`): each hit on an enemy that the open fight counts becomes the HP it
-- counted, at the hit's point (read by game/hits.lua only while they are on, the journal is closed, the game is not
-- paused and a fight is open), in the attacker's colour as in the meter; drawn after the enemy HP numbers, before the
-- settings window and the meter, none while the journal is open. Off, nothing is read or drawn, and the numbers live
-- are forgotten (also when the style changes, the journal opens, the game pauses or the world is new).
-- The enemy plate (ui/enemy_plate.lua, its model plate_model.lua; the settings `enemy_plate` and `enemy_plate_size`):
-- what the enemy kinds near the player are weak to and shrug off, and what his own attack gets. Its kinds are the boss
-- bar's boss (still the boss EnemyPlate.HOLD s after its bar went, as the plate's place holds), the enemies under the
-- hostile bars (the game's bars are read once a frame for the HP numbers and the plate; no critter) and the open
-- fight's living enemies (a returning enemy's new object is the enemy it continues), one per CharaID with how
-- many there are, in the order first seen since the plate appeared.
-- Each kind's table in use (game/enemy_table.lua) is read from a character in sight, else its last one is taken; its
-- statuses come from game/enemies.lua (tried from a character at most once a second a kind: the tries are the hits'
-- too), the player's weapon from game/weapon.lua, and the player's own hits on enemies (not DoT ticks nor knock hits)
-- feed the model from the hit sink. Shown while a fight is open or a hostile bar is drawn and PLATE_LINGER s after;
-- built at most every PLATE_EVERY s, drawn after the enemy HP numbers and before the damage numbers, none while the
-- journal is open. Off, nothing of it is read or drawn, and what it held is forgotten (also when the world is new).
-- The status buildup bars (ui/buildup_bars.lua, their reader game/buildup.lua; the setting `buildup_bars`, sized by
-- `enemy_hp_size`): under the boss bar the game draws now, how far its boss is from a stagger and from a knock-down
-- (from the bar's hit controller), and for each status building on it how far it is from setting the status off;
-- with each, about how many more hits that takes. Read (at most 10 times a second) and drawn only
-- while that bar is drawn, from the frame's one boss bar read, after the boss's HP numbers and before the enemy plate;
-- none while the journal is open. Off, nothing of it is read or drawn, and its rises are forgotten (also when the
-- world is new).
-- The player's own numbers (ui/player_numbers.lua, their reader game/player_vitals.lua; the setting
-- `player_numbers`, sized by `enemy_hp_size`): by the player's HP and stamina bars the game draws now at
-- the bottom of the screen (gauges.player: each bar's full length, not its fill), the HP now / its max as cut by
-- damage (the full max in brackets while it is cut) above the HP bar's right end, the same for the stamina under its
-- bar's right end; only the player's own character, no pawn's. The
-- player's numbers are read only in a frame the game draws its HUD, and drawn after the buildup bars and before the
-- enemy plate; none while the journal is open. Off, neither the HUD nor the numbers are read, nothing is drawn, and
-- the bars found are forgotten.
-- The hidden-stats panel (ui/hidden_stats.lua; its model hidden_stats_model.lua, its meanings hidden_stats_data.lua,
-- its reads game/hidden_screens.lua and game/hidden_stats.lua; the settings `hidden_stats` and `hidden_stats_size`):
-- on the guild's augments screen, the item screen and the equipment screen, by the game's description, what the
-- hovered augment or ring gives in the game's own numbers, each line marked by how sure its reading is. Read and drawn
-- in each frame the setting is on, the journal is closed and the player character is there, paused or not (the
-- item and equipment screens pause the game); its screens are looked for at most every 0.5 s while none of them is
-- drawn. A ring's numbers are read by the vocation of the character the screen shows, a personal number
-- by that character's base (none while whose it is is unknown). The panel is built again only when the
-- thing hovered, whose it is, the game's numbers, the base's numbers or the language changed; drawn after the damage
-- numbers, under the settings window and the meter. Off, nothing of it is read or drawn, and the panel and the screens
-- found are forgotten (also when the world is new, with the game's numbers read).
-- While the game is paused in a menu (game/pause.lua: the pause menu, the map...; read once per frame while the
-- journal is closed), the meter is hidden unless the settings window is open, and the enemy HP numbers, the buildup
-- bars, the player's numbers, the enemy plate and the damage numbers are neither read nor drawn (the hidden-stats
-- panel is); the journal and the settings window work as before, the hidden state of the toggle key and the fight go
-- on unchanged, and the summary's auto-hide counts from the pause's end.
-- No game object kept from one frame to a later one is used once a scene change may have destroyed it (a game
-- method called on such an object can fault inside the game and leave it hung). The objects kept are the
-- hidden-stats panel's screens with their elements and the game's bars (the overhead ones, the boss bar, the player's
-- HUD); the pause manager is looked up by name in each frame it is read. Each frame first reads the party listing anew
-- (world_frame: the player character and the pawns, once a frame for everything that needs it): without a player
-- character (a title screen, a load, a save being quit) the world is going, the objects kept are dropped in the first
-- such frame, and while it lasts neither screens nor bars are read (nor the debug evidence taken); with him back they
-- are looked for again, and the evidence waits a second. Each scene-type change drops them too, whatever the player.
-- A kept screen the game destroyed before either told is still caught by its own read (the last guard: its
-- get_DrawSelf raises and it is dropped). The party's HP poll and skill states read the characters of that frame's
-- listing, never ones kept from an earlier one (game/actors.lua, game/heals.lua); a party read without a player reads
-- no pawn. With `debug` on, debug.log tells each of these by frame (world_frame, on_scene_change, note_gone), so that an exit to the title shows
-- which came first.
--
-- Reload-safe: the state lives in the global DD2DM (DD2DM.state) and survives a
-- reload of this file; every method is hooked once per Lua state (game/hook.lua), the frame and menu callbacks are
-- registered once, from BeginRendering, and all of them find the handlers of the latest load at call time.
--
--   DD2DM.info() -> { version, hooks, missing = { "Type.method(...)" }, draw_missing = { "add_quad"... }, fighting,
--                     history, frame, loads, errors, last_error, language, journal, journal_missing = { name },
--                     settings_missing = { name }, enemy_bars_missing = { name }, damage_numbers_missing = { name },
--                     enemy_plate_missing = { name }, buildup_bars_missing = { name },
--                     player_numbers_missing = { name }, hidden_stats_missing = { name } }
--                   (draw_missing: draw-list calls the overlay found missing and drew plain rectangles for instead;
--                   journal: open or not; journal_missing, settings_missing, enemy_bars_missing,
--                   damage_numbers_missing, enemy_plate_missing, buildup_bars_missing, player_numbers_missing,
--                   hidden_stats_missing: the imgui and draw calls the journal, the settings window, the enemy HP
--                   numbers, the damage numbers, the enemy plate, the buildup bars, the player's numbers, the
--                   hidden-stats panel found missing)
local VERSION = "1.0.0"

local Fight = require("DD2DamageMeter/fight")
local Clock = require("DD2DamageMeter/clock")
local History = require("DD2DamageMeter/history")
local HistoryFile = require("DD2DamageMeter/history_file")
local Attrib = require("DD2DamageMeter/attrib")
local i18n = require("DD2DamageMeter/i18n")
local Names = require("DD2DamageMeter/names")
local View = require("DD2DamageMeter/view")
local Journal = require("DD2DamageMeter/journal")
local JournalTabs = require("DD2DamageMeter/journal_tabs")
local Settings = require("DD2DamageMeter/settings")
local Ledger = require("DD2DamageMeter/ledger")
local PlateModel = require("DD2DamageMeter/plate_model")
local Safe = require("DD2DamageMeter/game/safe")
local Hook = require("DD2DamageMeter/game/hook")
local actors = require("DD2DamageMeter/game/actors")
local enemies = require("DD2DamageMeter/game/enemies")
local battle = require("DD2DamageMeter/game/battle")
local names_game = require("DD2DamageMeter/game/names_game")
local hits = require("DD2DamageMeter/game/hits")
local heals = require("DD2DamageMeter/game/heals")
local gauges = require("DD2DamageMeter/game/gauges")
local pause = require("DD2DamageMeter/game/pause")
local EnemyTable = require("DD2DamageMeter/game/enemy_table")
local Weapon = require("DD2DamageMeter/game/weapon")
local Buildup = require("DD2DamageMeter/game/buildup")
local PlayerVitals = require("DD2DamageMeter/game/player_vitals")
local Overlay = require("DD2DamageMeter/ui/overlay")
local JournalUI = require("DD2DamageMeter/ui/journal")
local Menu = require("DD2DamageMeter/ui/menu")
local SettingsView = require("DD2DamageMeter/settings_view")
local SettingsUI = require("DD2DamageMeter/ui/settings_window")
local EnemyBars = require("DD2DamageMeter/ui/enemy_bars")
local DamageNumbers = require("DD2DamageMeter/damage_numbers")
local DamageNumbersUI = require("DD2DamageMeter/ui/damage_numbers")
local EnemyPlate = require("DD2DamageMeter/ui/enemy_plate")
local BuildupBars = require("DD2DamageMeter/ui/buildup_bars")
local PlayerNumbers = require("DD2DamageMeter/ui/player_numbers")
local Collector = require("DD2DamageMeter/game/collector")
local HiddenStatsData = require("DD2DamageMeter/hidden_stats_data")
local HiddenStatsModel = require("DD2DamageMeter/hidden_stats_model")
local HiddenStatsGame = require("DD2DamageMeter/game/hidden_stats")
local HiddenScreens = require("DD2DamageMeter/game/hidden_screens")
local HiddenStatsUI = require("DD2DamageMeter/ui/hidden_stats")
local StatCheck = require("DD2DamageMeter/game/stat_check")

local DATA = "DD2DamageMeter/"   -- relative to reframework/data
local SETTINGS_FILE = DATA .. "settings.json"
local LOG_FILE = DATA .. "debug.log"
local HISTORY_FILE = DATA .. "history.json"
local LOG_MAX = 5 * 1024 * 1024  -- debug.log never grows past this in one game session
local LOG_FULL = "debug.log reached 5 MB: nothing more is written in this game session\n"
local COLLECT_FILE = DATA .. "collect.jsonl"
local COLLECT_MAX = 200 * 1024 * 1024  -- collect.jsonl never grows past this, whatever the game sessions
local COLLECT_FULL = "collect.jsonl reached 200 MB: nothing more is written to it"
local LIVE_EVERY = 0.1           -- seconds between two builds of the live window (each build looks names up)
local REFRESH_EVERY = 1          -- seconds between two reads of the party (the game flips pawn names)
local LANGUAGE_EVERY = 2         -- seconds between two asks for the game's language while the setting is "auto"
local FLUSH_EVERY = 5            -- seconds between two settings saves while the menu or settings window is open
local PLATE_EVERY = 0.1          -- seconds between two builds of the enemy plate (each build looks its kinds up)
local PLATE_LINGER = 3           -- seconds the enemy plate stays after the last fight or hostile bar, and keeps the
                                 -- last kinds it listed while it lists none
local PLATE_DATA_EVERY = 1       -- seconds between two of the plate's tries at a kind's enemy data from a character:
                                 -- a failed one spends one of the 3 game/enemies.lua gives a CharaID, the hits' too
local RETURN_WINDOW = 30         -- seconds after a kept fight ended in which a returning enemy continues it
local RETURN_HP_BELOW = 0.02     -- how far below the HP it was left with a returning enemy may come back, and
local RETURN_HP_ABOVE = 0.001    -- how far above (at least 1 HP), each a share of its max HP
local RETURN_KEEP = 1000         -- the most hits and heals a new fight keeps while it may still continue one
local STAT_EVERY = 2             -- seconds between two snapshots of the hidden-stats evidence
local STAT_AFTER_PAUSE = 1       -- seconds after a pause's end before its snapshot (none in between)
local SCENE_TYPE, SCENE_METHOD = "app.GuiManager", "OnChangeSceneType"  -- by name: its parameters are not read
local BATTLE_TYPE, BATTLE_METHOD = "app.BattleManager", "get_BattleMode"
-- Not hooked, only called; without them there is no party, no HP or victim of a hit, no character name, no
-- element of a hit, no data of an enemy.
local CALLED = {
    { "app.CharacterManager", "get_ManualPlayer" }, { "app.PawnManager", "get_PawnCharacterList" },
    { "app.HitController", "get_Hp" }, { "app.HitController", "get_CachedCharacter" },
    { "app.GUIBase", "getName(app.Character)" },
    -- a hit's element, an enemy's flags, the type of a hit part
    { "app.HitController.DamageInfo", "get_ElementType" },
    { "app.ExceptPlayerDamageCalculator", "get_WeakPointSettings" },
    { "app.RegionStatusCtrl", "getActiveRegionParam(System.Int32)" },
}
local PARTY = { player = true, pawn = true }
local FRIEND = { player = true, pawn = true, ally = true }
-- The settings that decide which blocks and rows the models hold: a change rebuilds them at once.
local SWITCHES = {}
for _, key in ipairs({ "live_damage", "live_taken", "live_heal", "show_allies", "live_other", "summary_enemies",
                       "summary_damage", "summary_armor", "summary_heal", "summary_allies", "summary_other" }) do
    SWITCHES[key] = true
end
-- The journal's tabs whose model has a selection (sel), each with the rows of its body the selection picks from (the
-- enemy list's rows, the Skills choices, the chart's bars); the others take no select action.
local SELECTS = {
    enemies = function(body) return type(body.list) == "table" and body.list.rows or nil end,
    skills = function(body) return body.choices end,
    chart = function(body) return body.bars end,
}

-- State ---------------------------------------------------------------------------------------------

local M = rawget(_G, "DD2DM")
if type(M) ~= "table" then
    M = {}
    rawset(_G, "DD2DM", M)
end
local S = M.state
if type(S) ~= "table" then
    S = {}
    M.state = S
end

-- The one clock: seconds, read once per frame (DD2DM.clock replaces os.clock in the tests).
local function now()
    local clock = M.clock
    if type(clock) == "function" then
        local t = clock()
        if type(t) == "number" then return t end
    end
    return os.clock()
end

local store = {
    read = function() return json.load_file(SETTINGS_FILE) end,
    write = function(values)
        if json.dump_file(SETTINGS_FILE, values) == false then error("json.dump_file failed") end
    end,
}

S.loads = (S.loads or 0) + 1
S.settings = S.settings or Settings.load(store)
local settings = S.settings
-- defaults; also fills fields that a newer version adds to the state of an older load
for k, v in pairs({ frame = 0, t = now(), mode = "idle", hidden = false, paused = false, history_index = 1,
                    hooks_n = 0, missing = {}, draw_logged = {} }) do
    if S[k] == nil then S[k] = v end
end
S.clock = S.clock or Clock.new()
S.history = S.history or History.new(settings.values.history_size)
S.history:resize(settings.values.history_size)
S.attrib = S.attrib or Attrib.new()
-- The journal: open or not, its tab, the history index of its fight, per tab the selection and the page; dirty: its
-- models (model = { header, body, hint }) are built again the next time it is drawn; keys: its keys' last state
-- (unknown right after it opened); pages: the pages its body took when last drawn; rows = { tab, index, n }: the rows
-- the selection of the last built body can take (nil without one).
if type(S.journal) ~= "table" then S.journal = {} end
for k, v in pairs({ open = false, tab = "enemies", index = 1, sel = {}, page = {}, dirty = true, keys = {},
                    pages = 1 }) do
    if S.journal[k] == nil then S.journal[k] = v end
end
-- The settings window: open or not, its selected row (an index of SettingsView.ROWS) and on a table row its selected
-- cell (col); dirty: its model is built again the next time it is drawn; keys: its keys' last state (unknown right
-- after it opened).
if type(S.settings_window) ~= "table" then S.settings_window = {} end
for k, v in pairs({ open = false, sel = 1, col = 1, dirty = true, keys = {} }) do
    if S.settings_window[k] == nil then S.settings_window[k] = v end
end
-- The damage numbers live: made anew by each load (they last a second or so).
S.numbers = DamageNumbers.new()
-- The enemy plate's model: the player's recent hits, made anew by each load (they last 10 s).
S.plate = PlateModel.new()

-- What the enemy plate shows (plate_frame); forget_plate starts it afresh. near_at: the last time a fight was open or a
-- hostile bar drawn; order: each kind's (CharaID's) place by when it was first seen since the plate appeared, seen: the
-- kinds counted so far; plate: the model's last build, the one drawn (nil: none), built_at: its time, listed_at: the
-- last build that listed a kind; boss: the Actor of the boss bar's boss at the last build that read the bar, boss_at:
-- the last frame the bar was read (the boss held EnemyPlate.HOLD s after, plate_kinds); data_at: each kind's last try
-- at its enemy data from a character (plate_build).
local function forget_plate()
    S.plate_view = { order = {}, seen = 0, data_at = {} }
end
forget_plate()
-- The hidden-stats panel kept (hidden_stats_frame): what it was built from (kind; id: the augment's name or the ring's
-- id; lang; who; raw: the game's numbers as read, the same table while they are; base: the base read, nil without
-- one; total: hidden_total's, nil without a total line) and panel, the Panel built (nil: none for it); empty while
-- nothing is hovered. forget_hidden starts it afresh.
local function forget_hidden()
    S.hidden_view = {}
end
forget_hidden()
-- With `debug` on, the enemy plate's cost since it was last logged (log_plate_cost).
S.plate_cost = { frames = 0, builds = 0, ms = 0, max = 0 }
-- With `debug` on, the hidden-stats panel's cost since it was last logged (log_hidden_cost).
local function hidden_cost()
    return { frames = 0, builds = 0, ms = 0, max = 0, idle = 0, idle_ms = 0, idle_max = 0 }
end
S.hidden_cost = hidden_cost()
-- With `debug` on, the screens whose fallen-back anchor debug.log has told in this game session (tell_anchor).
S.anchor_told = S.anchor_told or {}
-- HiddenScreens.gone() as debug.log last told it (note_gone).
S.hidden_gone = S.hidden_gone or HiddenScreens.gone()
-- With `debug` on, the debug collector's meets and their time since they were last logged (log_collect_cost).
S.collect_cost = { calls = 0, ms = 0, max = 0 }

local ctx = { names = Names.new(names_game.lookup()), i18n = i18n }

-- Debug log -----------------------------------------------------------------------------------------

local function write_log(text)
    if not settings.values.debug or S.log_full then return end
    local line = os.date("%Y-%m-%d %H:%M:%S ") .. (tostring(text):gsub("[\r\n]+", " ")) .. "\n"
    -- the first line of a game session (a reload is the same session) replaces an earlier session's log
    local f = io.open(LOG_FILE, S.log_bytes == nil and "w" or "a")
    if f == nil then return end
    local bytes = S.log_bytes or 0
    if bytes + #line + #LOG_FULL > LOG_MAX then
        line = LOG_FULL
        S.log_full = true
    end
    f:write(line)
    f:close()
    S.log_bytes = bytes + #line
end

local function log_line(text)
    pcall(write_log, text)
end

-- collect.jsonl --------------------------------------------------------------------------------------

-- A record of the debug collector, appended: the file is kept across game sessions. Its size is the file's at the
-- session's first record (seek("end") of the handle; 0 when that gives no number), told in debug.log once
-- ("collect.jsonl: 1234 bytes at start"), then counted. A record that would take it past COLLECT_MAX is not written,
-- nor any after it in this game session, and debug.log says so once.
local function write_collect(text)
    if S.collect_full then return end
    local f = io.open(COLLECT_FILE, "a")
    if f == nil then return end
    local bytes = S.collect_bytes
    if bytes == nil then
        local ok, size = pcall(f.seek, f, "end")
        if ok and math.type(size) == "integer" then
            bytes = size
            log_line(string.format("collect.jsonl: %d bytes at start", size))
        else
            bytes = 0
            log_line("collect.jsonl: no size at start (seek gave none), counted from 0")
        end
    end
    if bytes + #text > COLLECT_MAX then
        f:close()
        S.collect_full, S.collect_bytes = true, bytes
        log_line(COLLECT_FULL)
        return
    end
    f:write(text)
    f:close()
    S.collect_bytes = bytes + #text
end

-- The debug collector works only with `debug` on and never while the game is paused in a menu.
local function collecting()
    return settings.values.debug == true and not S.paused
end

Collector.output(write_collect)

-- Every caught error comes here through Hook.fail: the first ones of each place, then every 1000th.
Hook.on_error(function(where, err, count)
    local text = "error " .. tostring(where) .. ": " .. tostring(err)
    if type(count) == "number" and count > 1 then text = text .. " (" .. count .. " so far)" end
    log_line(text)
end)

local function guard(where, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then Hook.fail(where, err) end
end

-- "fight end 12.3s dealt=..." for a kept fight, "dropped end ..." for one that was not kept; held = hits that waited
-- for an enemy the party never fought and were not counted.
local function fight_line(word, snap, held)
    local dealt, taken, healed, ally_dealt, hit_count = 0, 0, 0, 0, 0
    for _, s in pairs(snap.actors) do
        local kind = s.actor.kind
        if PARTY[kind] then
            dealt, taken, healed = dealt + s.dealt, taken + s.taken, healed + s.heal_done
            hit_count = hit_count + s.hits
        elseif kind == "ally" then
            ally_dealt = ally_dealt + s.dealt
        end
    end
    local n_enemies, killed = 0, 0
    for _, e in pairs(snap.enemies) do
        n_enemies = n_enemies + 1
        if e.killed then killed = killed + 1 end
    end
    return string.format("%s %s %.1fs dealt=%.0f taken=%.0f healed=%.0f allies=%.0f hits=%d enemies=%d killed=%d held=%d",
        word, tostring(snap.outcome), snap.duration, dealt, taken, healed, ally_dealt, hit_count, n_enemies, killed, held)
end

-- "plate frames=812 builds=81 avg=0.042ms max=1.300ms": the frames the enemy plate was shown since the last such line,
-- the builds among them, and plate_frame's average and largest time by os.clock; measured only with `debug` on (see
-- measured_plate_frame), written after each fight's line, none when it was not shown.
local function log_plate_cost()
    local c = S.plate_cost
    if c.frames == 0 then return end
    log_line(string.format("plate frames=%d builds=%d avg=%.3fms max=%.3fms", c.frames, c.builds, c.ms / c.frames,
        c.max))
    S.plate_cost = { frames = 0, builds = 0, ms = 0, max = 0 }
end

-- "hidden stats frames=212 builds=3 avg=0.041ms max=0.300ms idle=31000 idle_avg=0.004ms idle_max=1.200ms": the
-- frames something was hovered on the panel's screens since the last such line, the panel's builds among them, and
-- hidden_stats_frame's average and largest time on them by os.clock (HiddenScreens.current's included); then the
-- frames before with the setting on and nothing hovered, and their average and largest time (HiddenScreens.current's
-- alone: in play its look through the scene's GUIs every 0.5 s; on one of the screens its reads with
-- nothing to show, such as a sword under the cursor on the item screen). Measured only with `debug` on (see
-- measured_hidden_stats_frame); there are no fights in the menus, so it is written in the first frame nothing is
-- hovered after one or more that had something.
local function log_hidden_cost()
    local c = S.hidden_cost
    local idle_avg = c.idle > 0 and c.idle_ms / c.idle or 0
    log_line(string.format("hidden stats frames=%d builds=%d avg=%.3fms max=%.3fms idle=%d idle_avg=%.3fms "
        .. "idle_max=%.3fms", c.frames, c.builds, c.ms / c.frames, c.max, c.idle, idle_avg, c.idle_max))
    S.hidden_cost = hidden_cost()
end

-- A meet of the debug collector (a kind in sight after the plate's frame, or a hit's living enemy), timed by os.clock
-- for log_collect_cost.
local function collector_meet(character, actor, t)
    local c0 = os.clock()
    guard("collector", Collector.enemy, character, actor, t)
    local ms, c = (os.clock() - c0) * 1000, S.collect_cost
    c.calls, c.ms, c.max = c.calls + 1, c.ms + ms, math.max(c.max, ms)
end

-- "collect calls=95 avg=0.004ms max=2.100ms": the debug collector's meets since the last such line and their average
-- and largest time, written after each fight's plate line, none when there was no meet.
local function log_collect_cost()
    local c = S.collect_cost
    if c.calls == 0 then return end
    log_line(string.format("collect calls=%d avg=%.3fms max=%.3fms", c.calls, c.ms / c.calls, c.max))
    S.collect_cost = { calls = 0, ms = 0, max = 0 }
end

-- The hidden-stats evidence, while the debug collector collects: a snapshot of the player's numbers and equipment
-- (game/stat_check.lua) for Collector.stat_check, at most every STAT_EVERY s, and STAT_AFTER_PAUSE s after a pause's
-- end (S.stat_due, its time, set by set_paused): the equipment is changed in the game's paused menus. None in
-- that second, whatever the 2 s say (quitting from the pause menu ends a pause just as the world starts going, and a
-- snapshot then would read status calculators being torn down); at its end it is taken only with the player character
-- there in that frame (stat_sample runs only in a frame world_frame found him, read anew), else in the first frame
-- after with him there. Likewise STAT_AFTER_PAUSE s after he comes back (world_frame sets S.stat_due). A
-- snapshot that is nil because no augment slot can be read is told in debug.log once a game session
-- (S.stat_augments_told): without the augments no change of them can make a record.
local function stat_sample(t)
    local due, last = S.stat_due, S.stat_at
    if type(due) == "number" then
        -- the second after a pause (a clock that went back does not hold it longer)
        if t < due and due - t <= STAT_AFTER_PAUSE then return end
    elseif last ~= nil and t >= last and t - last < STAT_EVERY then
        return
    end
    S.stat_at, S.stat_due = t, nil
    local snapshot, why = StatCheck.snapshot()
    if why == "augments" and not S.stat_augments_told then
        S.stat_augments_told = true
        log_line("stat_check: the augment slots cannot be read (getAbility gave nothing for all 7): no snapshot, "
            .. "so no stat_check record")
    end
    Collector.stat_check(t, snapshot)
end

-- history.json ---------------------------------------------------------------------------------------

-- Read once per Lua state, before anything is written there. The file's fights are older than those kept in this Lua
-- state, so they go after them, newest first, history_size in all. Their text is made now (the first kept fight of
-- the session writes them all again, and that must not wait for a frame).
local function load_history()
    S.history_read = true
    local ok, decoded = pcall(json.load_file, HISTORY_FILE)
    local snaps = HistoryFile.unpack(ok and decoded or nil)
    local size = settings.values.history_size
    local merged = History.new(size)
    for i = math.min(#snaps, math.max(0, size - S.history:count())), 1, -1 do
        merged:push(snaps[i])
        HistoryFile.encode_fight(snaps[i])
    end
    for i = S.history:count(), 1, -1 do merged:push(S.history:get(i)) end
    S.history = merged
    S.models_dirty, S.journal.dirty = true, true
end

-- The whole history, newest first, as far as MAX_BYTES holds. Each fight was made into text once, when it was kept.
local function write_history()
    S.history_write_due = nil
    local ok = pcall(function()
        local snaps = {}
        for i = 1, S.history:count() do snaps[i] = S.history:get(i) end
        local text = HistoryFile.pack(snaps, HistoryFile.MAX_BYTES)
        local f = io.open(HISTORY_FILE, "w")
        if f == nil then error("cannot open " .. HISTORY_FILE) end
        local written = f:write(text)
        f:close()
        if written == nil then error("cannot write " .. HISTORY_FILE) end
    end)
    if not ok then log_line("history: could not write " .. HISTORY_FILE) end
end

-- Fights --------------------------------------------------------------------------------------------

local function drop_details()
    S.details_key, S.details_model = nil, nil
    S.models_dirty = true
end

-- A hit between the party and an enemy, either way, that is not a DoT tick, nor a blow on a corpse.
local function real_hit(h)
    local a, v = h.attacker, h.victim
    if h.status ~= nil or a == nil or v == nil then return false end
    if not (type(h.hp0) == "number" and h.hp0 > 0) then return false end
    return (PARTY[a.kind] == true and v.kind == "enemy") or (PARTY[v.kind] == true and a.kind == "enemy")
end

-- A heal on a party member or an ally with no healer and no known source is his own (Attrib: lifesteal or
-- regeneration).
local function own_heal(h)
    local target, source = h.target, h.source
    if h.healer ~= nil or type(source) ~= "table" or source.kind ~= "other" then return end
    if not (type(target) == "table" and (PARTY[target.kind] or target.kind == "ally")) then return end
    h.healer = target
    h.source = { kind = "self", name = S.attrib:own_heal(S.frame, target.key, h.amount or h.effective) }
end

-- A returning enemy continues the fight --------------------------------------------------------------
-- S.last_kept = { fight, snap, t1 }: the newest kept fight (its Fight, its history entry, its end), only while it left
-- an enemy alive that can come back (returnable). S.returning: the open fight may still be that one going on; it keeps
-- what the open fight took so far (R[1..n] = { item = Hit or Heal, heal = true | nil }). S.continued: the history
-- entry the open fight, a continued one, replaces when it ends.

-- An enemy a returning one can be: left alive, with a CharaID and a known HP.
local function returnable(e)
    return not e.killed and type(e.hp) == "number" and math.type(e.actor.chara_id) == "integer"
end

local function continuable(fight)
    for _, e in pairs(fight.enemies) do
        if returnable(e) then return true end
    end
    return false
end

-- A friend's blow on a living enemy (no DoT tick, no mirror): the hit that decides.
local function friend_blow(h)
    local a, v = h.attacker, h.victim
    return a ~= nil and FRIEND[a.kind] == true and v ~= nil and v.kind == "enemy" and h.status == nil and not h.mirror
        and type(h.hp0) == "number" and h.hp0 > 0
end

-- The enemy of `fight` that the victim of `h` is, back: left alive, of the victim's CharaID, with the hit's hp0 at most
-- RETURN_HP_BELOW below the HP it was left with and at most RETURN_HP_ABOVE above it; the closest (then the
-- lowest key) when there are more; nil when none.
local function returning_enemy(fight, h)
    local id = h.victim.chara_id
    if math.type(id) ~= "integer" then return nil end
    local best, best_d = nil, nil
    for key, e in pairs(fight.enemies) do
        if returnable(e) and e.actor.chara_id == id then
            local max = e.max_hp or 0
            local d = math.abs(h.hp0 - e.hp)
            if h.hp0 >= e.hp - RETURN_HP_BELOW * max and h.hp0 <= e.hp + math.max(1, RETURN_HP_ABOVE * max)
                    and (best == nil or d < best_d or (d == best_d and key < best)) then
                best, best_d = key, d
            end
        end
    end
    return best
end

-- Whether the open fight may still be the last kept one at `t` (RETURN_WINDOW after it ended); when not, it is a
-- fight of its own from now on.
local function still_returning(t)
    local last = S.last_kept
    if last ~= nil and type(t) == "number" and t - last.t1 <= RETURN_WINDOW then return true end
    S.returning = nil
    return false
end

-- A hit or heal of the open fight, kept to be counted again if it turns out to be the last kept one; past RETURN_KEEP
-- it is a fight of its own.
local function keep_for_return(item, heal)
    local R = S.returning
    if R.n >= RETURN_KEEP then
        S.returning = nil
        return
    end
    R.n = R.n + 1
    R[R.n] = { item = item, heal = heal }
end

-- The open fight is the last kept one going on: that Fight is reopened at the open one's start (the time between is
-- paused), the victim's key is aliased to its enemy, and what the open fight took so far is counted in it, in order.
-- Its history entry stays until it ends again (finish_fight).
local function continue_fight(last, R, victim, enemy_key)
    local fight, opened = last.fight, S.fight
    local gap = math.max(0, opened.t0 - last.t1)
    fight:reopen(opened.t0)
    fight:alias(victim.key, enemy_key)
    S.fight, S.fight_real, S.continued, S.last_kept = fight, true, last.snap, nil
    S.live_model, S.live_at = nil, nil
    log_line(string.format("fight continued after %.1fs by a returning %s", gap, tostring(victim.name)))
    for i = 1, R.n do
        local x = R[i]
        if x.heal then fight:add_heal(x.item) else fight:add_hit(x.item) end
    end
end

-- A hit of the open fight while it may be the last kept one going on: the first friend's blow on a living enemy
-- decides (on the last kept fight's enemy back: it goes on; else the open fight is one of its own); the hits before it
-- are kept.
local function returning_hit(h)
    if not still_returning(h.t or S.t) then return end
    if not friend_blow(h) then return keep_for_return(h, nil) end
    local R = S.returning
    S.returning = nil
    local last = S.last_kept
    local key = returning_enemy(last.fight, h)
    if key ~= nil then continue_fight(last, R, h.victim, key) end
end

local function start_fight(t)
    -- opened at most RETURN_WINDOW s after the last kept fight ended, it may be that one going on
    local last = S.last_kept
    if last ~= nil and t - last.t1 > RETURN_WINDOW then S.last_kept, last = nil, nil end
    S.returning = last ~= nil and { n = 0 } or nil
    S.fight, S.fight_real, S.hit_resume_logged = Fight.new(t), false, nil
    S.attrib:new_fight(S.frame)       -- heals in this fight go to no heal area of the one before
    S.before_fight = { mode = S.mode, hidden = S.hidden }  -- what the window goes back to if the fight is not kept
    S.mode, S.hidden = "live", false  -- the window comes back with every new fight
    S.live_model, S.live_at = nil, nil
    drop_details()
    S.refresh_due = true              -- the party is read again at once (or on the next frame from a hook)
end

-- A fight was kept: the journal stays on the newest fight (index 1) or on the one it showed, now one further down
-- (the oldest left when that one fell out of the history). When that is another fight (index 1, or the one shown fell
-- out), the selections and pages of the one shown before are forgotten.
local function journal_fight_kept()
    local J = S.journal
    local count = S.history:count()
    local index = J.index > 1 and J.index + 1 or 1
    if index == 1 or index > count then J.sel, J.page = {}, {} end
    J.index = math.min(index, count)
    J.dirty = true
end

local function finish_fight(ev)
    local fight, continued = S.fight, S.continued
    S.fight = nil                     -- from here on hits and heals have nowhere to go
    S.continued, S.returning = nil, nil
    if fight == nil then return end
    fight:finish(ev.t, ev.outcome)
    -- the full snapshot (with the journal's detail) costs a deep copy: only a kept fight gets one, and only here
    local snap = fight:snapshot(ev.t, S.fight_real == true)
    S.live_model = nil
    drop_details()
    if not S.fight_real then
        -- battle music with no blow exchanged (only burn ticks, only blows on corpses): dropped, and the window
        -- shows again what it showed before (the last summary, or nothing)
        local before = S.before_fight or {}
        S.mode, S.hidden, S.summary_at = before.mode or "idle", before.hidden == true, S.t
        log_line(fight_line("dropped", snap, fight:held()))
        log_plate_cost()
        log_collect_cost()
        return
    end
    if continued ~= nil and S.history:get(1) == continued then
        -- a fight continued is kept once, in place of its entry from before; the journal stays where it was
        S.history:replace_newest(snap)
        S.journal.dirty = true
    else
        S.history:push(snap)
        journal_fight_kept()
    end
    S.history_index = 1
    S.last_kept = continuable(fight) and { fight = fight, snap = snap, t1 = ev.t } or nil
    S.mode, S.summary_at = "summary", S.t
    log_line(fight_line("fight", snap, fight:held()))
    log_plate_cost()
    log_collect_cost()
    -- written by the next frame callback: a fight can end inside a hook (a party hit on a new enemy in the end grace),
    -- and the file is up to 4 MB written at once
    if settings.values.history_file then S.history_write_due = true end
end

-- The game's battle broke off for a moment and the fight goes on. A hit can resume a fight again and again while the
-- mode stays Normal, so only the first resume by a hit is logged per fight.
local function log_resume(ev)
    if ev.by == "hit" then
        if S.hit_resume_logged then return end
        S.hit_resume_logged = true
    end
    log_line(string.format("fight resumed after %.1fs by %s", ev.gap, tostring(ev.by)))
end

local function handle_one(ev)
    if ev == nil then return end
    if ev.kind == "start" then
        start_fight(ev.t)
    elseif ev.kind == "finish" then
        finish_fight(ev)
    elseif ev.kind == "resume" then
        log_resume(ev)
    end
end

-- The clock's answer: one event, nothing, or (a hit on a new enemy in the end grace) a finish and a start.
local function handle(...)
    for i = 1, select("#", ...) do handle_one((select(i, ...))) end
end

-- Hooks and the self-check ---------------------------------------------------------------------------

local function frame_time() return S.t end
local function frame_no() return S.frame end

-- A party attacker's shade as the meter has it: its rank in its vocation among the open fight's party members (a
-- Fight's actors are shaped as a snapshot's). Asked only when its hit makes a new damage number.
local function party_shade(h)
    local fight = S.fight
    if fight == nil then return nil end
    return View.shades(fight)[tostring(h.attacker.key)]
end

-- A hit the fight counted, with a point, becomes a damage number (or joins one).
local function add_number(h, amount)
    S.numbers:add(h, amount, h.t or S.t, party_shade)
end

-- The enemy plate's model takes the player's hits on enemies, a fight open or not; not a DoT tick nor a knock hit
-- (the enemy's own damage after his blow), no attack of his.
local function feed_plate(h)
    local a, v = h.attacker, h.victim
    if h.status ~= nil or h.knock or a == nil or v == nil or a.kind ~= "player" or v.kind ~= "enemy" then return end
    S.plate:add_hit(h.t, Ledger.split(h))
end

local hit_sink = {
    now = frame_time, frame = frame_no,
    -- the damage numbers' reads of a hit on an enemy: only while they are on, the journal is closed, the game is not
    -- paused in a menu and a fight is open (a party hit opens it before its own hit comes)
    points = function()
        return settings.values.damage_numbers == true and not S.journal.open and not S.paused and S.fight ~= nil
    end,
    -- the debug collector's reads of a hit on an enemy, and the enemy it meets
    debug = collecting,
    met = function(character, actor, t)
        if collecting() then collector_meet(character, actor, t) end
    end,
    hit = function(h)
        if collecting() then guard("collector", Collector.hit, h) end
        if settings.values.enemy_plate then guard("enemy plate", feed_plate, h) end
        if S.fight == nil then return end
        -- it may make the open fight the last kept one, going on
        if S.returning then guard("returning enemy", returning_hit, h) end
        local fight = S.fight
        local counted = fight:add_hit(h)
        if not S.fight_real and real_hit(h) then S.fight_real = true end
        if counted and h.point then guard("damage numbers", add_number, h, counted) end
    end,
    touch = function(frame, healer, target_key, ref, t) S.attrib:touch(frame, healer, target_key, ref, t) end,
    -- a party member's or an ally's hit on an enemy starts (in or out of a fight): the lifesteal can follow it
    strike = function(frame, attacker_key) S.attrib:struck(frame, attacker_key) end,
    status = function(t, victim_key, status, applier) S.attrib:status_applied(t, victim_key, status, applier) end,
    -- the hit is on an enemy of the open fight, or on another one (then it is another fight: see the clock)
    party_hit = function(t, enemy_key)
        local fight, joins = S.fight, nil
        if fight ~= nil and enemy_key ~= nil then joins = fight:is_engaged(enemy_key) end
        handle(S.clock:on_party_hit(t, joins))
    end,
}

local heal_sink = {
    now = frame_time, frame = frame_no,
    heal = function(h)
        local fight = S.fight
        if fight == nil then return end
        own_heal(h)
        -- kept, in case the open fight turns out to be the last kept one going on
        if S.returning and still_returning(h.t or S.t) then keep_for_return(h, true) end
        fight:add_heal(h)
    end,
}

local function player_character()
    return Safe.call(Safe.singleton("app.CharacterManager"), "get_ManualPlayer")
end

local function player_address()
    return Safe.address(player_character())
end

-- A new world (a loaded save, or the player gone at a scene change): the open fight is abandoned and nothing read from
-- the old world is kept, except the last kept fight a returning enemy may continue (S.last_kept): the game can put
-- the player back after a fall through a scene change and make the enemy anew, and that must still continue the fight
-- (a loaded save is told apart by none of it; the CharaID and HP match guard it).
local function reset_world()
    handle(S.clock:reset(S.t))
    hits.reset()
    heals.reset()
    S.attrib:reset()
    actors.reset()
    enemies.reset()
    names_game.reset()
    gauges.reset()
    EnemyTable.reset()
    Weapon.reset()
    EnemyPlate.reset()
    Buildup.reset()
    S.numbers:clear()
    S.plate:clear()
    forget_plate()
    HiddenScreens.reset()
    HiddenStatsGame.reset()
    HiddenStatsUI.reset()
    forget_hidden()
    -- a loaded save's equipment is no change of the player's (the hidden-stats evidence)
    Collector.stat_forget()
    S.refresh_due = true
end

-- The game objects kept from one frame to a later one that a scene change destroys: the hidden-stats panel's
-- screens and their elements, the bars over heads, the boss bar and the player's HUD (they are only read in a frame
-- the world is there, and read anew after this). The pause manager is not kept (game/pause.lua looks it up by name
-- at each read). The bars are forgotten, not reset: the next look takes all of them at once (one look, not one a
-- kind).
local function drop_kept()
    HiddenScreens.forget()
    gauges.forget()
end

-- The game changes its scene type without a load too, and on a load the new player may not be there yet. The hook
-- resets only when the player is gone (and forgets it); else it asks for a party read on the next frame, and that read
-- resets when it finds another player (see refresh_party). Whatever the player, the screens and bars kept are
-- dropped first (debug.log: "scene type changed after frame N (player here|no player)").
local function on_scene_change()
    drop_kept()
    local here = player_address() ~= nil
    log_line(string.format("scene type changed after frame %d (%s)", S.frame, here and "player here" or "no player"))
    if not here then
        reset_world()
        S.player_addr = nil
    else
        S.refresh_due = true
    end
end

-- This frame's party listing (Actors.listed: the player character and the pawns), read once by world_frame and
-- handed to the HP poll and the skill states; nil outside on_frame (never kept to a later frame).
local frame_party = nil

-- The world this frame, read before anything else in it: the party listing, read anew each frame (once,
-- for the HP poll and the skill states too), and with it the player character as the game has him now
-- (app.CharacterManager:get_ManualPlayer()). Without one the world is going or gone (the title screen, a load, a save
-- being quit): in the first such frame the objects kept are dropped (drop_kept), and while it lasts they are not read
-- (window_frame), nor is the debug evidence taken; when he is back they are looked for again, the party is read in
-- that frame, and the evidence waits STAT_AFTER_PAUSE s (a load is setting the new world up). With
-- `debug` on, each change after the first frame is one debug.log line: "world: no player character at frame N: the
-- screens and bars kept dropped" / "world: player character back at frame N".
local function world_frame(t)
    local now = actors.listed()
    frame_party = now
    local here = next(now) ~= nil
    local was = S.world
    S.world = here
    if here == was then return end
    if not here then drop_kept() end
    if was == nil then return end -- the first frame of this Lua state: nothing changed
    if here then
        -- the party is read in this very frame (game_frame), not up to a second later: the read without him
        -- left the roster empty, and a pawn's hit before the next read would be «other» or an ally's
        S.refresh_due = true
        local due = type(S.stat_due) == "number" and S.stat_due or t
        S.stat_due = math.max(due, t + STAT_AFTER_PAUSE)
        log_line(string.format("world: player character back at frame %d", S.frame))
    else
        log_line(string.format("world: no player character at frame %d: the screens and bars kept dropped", S.frame))
    end
end

-- A hidden-stats screen kept that the game destroyed under the mod (its get_DrawSelf raised: the last guard,
-- HiddenScreens.gone) is one debug.log line, with the frame: "hidden screens: a kept screen raised at frame N (the
-- game destroyed it): dropped".
local function note_gone()
    local n = HiddenScreens.gone()
    if n == S.hidden_gone then return end
    S.hidden_gone = n
    log_line(string.format("hidden screens: a kept screen raised at frame %d (the game destroyed it): dropped",
        S.frame))
end

local function method_found(type_name, name)
    local td = Safe.type(type_name)
    return td ~= nil and Safe.try(function() return td:get_method(name) end) ~= nil
end

local function install()
    local n, missing = 0, {}
    local function add(count, list)
        n = n + count
        for _, name in ipairs(list) do missing[#missing + 1] = name end
    end
    add(hits.install(hit_sink, S.attrib))
    add(heals.install(heal_sink, S.attrib))
    if Hook.install(SCENE_TYPE, SCENE_METHOD, nil, function() on_scene_change() end) then
        n = n + 1
    else
        missing[#missing + 1] = SCENE_TYPE .. "." .. SCENE_METHOD
    end
    -- not hooked, polled every frame: without it no fight starts with the battle music
    if not method_found(BATTLE_TYPE, BATTLE_METHOD) then missing[#missing + 1] = BATTLE_TYPE .. "." .. BATTLE_METHOD end
    for _, m in ipairs(CALLED) do
        if not method_found(m[1], m[2]) then missing[#missing + 1] = m[1] .. "." .. m[2] end
    end
    S.hooks_n, S.missing = n, missing
end

-- Language ------------------------------------------------------------------------------------------

-- "auto": the game's language when it is one the mod has (en, ru), else the last such answer, else English.
local function wanted_language()
    local lang = settings.values.language
    if lang ~= "auto" then return lang end
    local game = names_game.language()
    if game then S.game_lang = game end
    return S.game_lang or "en"
end

local function apply_language()
    S.language_at = S.t
    local lang = wanted_language()
    if lang ~= i18n.lang() then
        i18n.set(lang)
        S.models_dirty, S.journal.dirty, S.settings_window.dirty = true, true, true
    end
    local n = #S.missing
    S.notice = n > 0 and i18n.t("missing_methods", n) or nil
end

-- Window --------------------------------------------------------------------------------------------

local function details_of(snap)
    if S.details_key == nil then return nil end
    local d = View.details(snap, S.details_key, ctx)
    if d == nil then S.details_key = nil end
    return d
end

-- The switches of the blocks and rows, as the view takes them (a block or rows that are off are not built).
local function live_show()
    local v = settings.values
    return { damage = v.live_damage, taken = v.live_taken, heal = v.live_heal, allies = v.show_allies, other = v.live_other }
end

local function summary_show()
    local v = settings.values
    return { enemies = v.summary_enemies, damage = v.summary_damage, allies = v.summary_allies, other = v.summary_other,
        heal = v.summary_heal, armor = v.summary_armor }
end

-- The live model at most every LIVE_EVERY seconds (the first one of a fight at once: start_fight forgets live_at); the
-- summary and details only when something changed. The time and the dirty flag are noted before building, so a build
-- that raises is not tried again on every frame, the first one included: the live window keeps its last good model
-- (the same fight), a summary that failed is not drawn (it would be another fight's).
local function build_models(t, mode)
    if mode == "live" then
        local fight = S.fight
        if fight and (S.models_dirty or t - (S.live_at or -math.huge) >= LIVE_EVERY) then
            S.live_at, S.models_dirty = t, false
            local snap = fight:snapshot(t)
            S.live_model = View.live(snap, t, ctx, live_show())
            S.details_model = details_of(snap)
        end
    elseif mode == "summary" and S.models_dirty then
        S.models_dirty = false
        S.summary_model, S.details_model = nil, nil
        local snap = S.history:get(S.history_index)
        if snap then
            S.summary_model = View.summary(snap, ctx, summary_show())
            S.details_model = details_of(snap)
        end
    end
end

-- What the meter shows (its mode) and whether it is hidden. While the settings window is open it is not hidden, and
-- without an open fight it shows the summary of the last kept fight, so that each change is seen at once; else it is
-- hidden while the game is paused in a menu too.
local function meter_mode(setup, paused)
    if not setup then return S.mode, S.hidden or paused end
    if S.mode ~= "live" and S.history:count() > 0 then return "summary", false end
    return S.mode, false
end

local function overlay_state(mode, hidden)
    if hidden or (mode ~= "live" and mode ~= "summary") then mode = "hidden" end
    return {
        mode = mode, live = S.live_model, summary = S.summary_model, details = S.details_model,
        history_index = S.history_index, history_count = S.history:count(), notice = S.notice,
    }
end

local function apply_actions(a, t)
    if a.select_actor ~= nil then
        S.details_key = a.select_actor
        S.models_dirty = true
    end
    if a.back then drop_details() end
    if a.history ~= nil and a.history ~= 0 then
        local index = math.max(1, math.min(S.history:count(), S.history_index + a.history))
        if index ~= S.history_index then
            S.history_index = index
            drop_details()
        end
    end
    if a.select_actor ~= nil or (a.history ~= nil and a.history ~= 0) then S.summary_at = t end
    if a.hide then S.hidden = true end
    if type(a.moved) == "table" then
        settings:set("window_x", a.moved.x)
        settings:set("window_y", a.moved.y)
        S.settings_window.dirty = true -- it shows the position
    end
end

local function save_settings()
    if settings.dirty and not settings:flush() then log_line("settings: could not write " .. SETTINGS_FILE) end
end

-- Saved when the REFramework menu and the settings window are both closed again, and at most every FLUSH_EVERY
-- seconds while either of them is open.
local function save_while_editing(t, editing)
    if editing and not S.editing then
        S.flushed_at = t
    elseif editing then
        if t - (S.flushed_at or t) >= FLUSH_EVERY then
            save_settings()
            S.flushed_at = t
        end
    elseif S.editing then
        save_settings()
    end
    S.editing = editing
end

-- A wait for a key press ends when the REFramework menu opens or closes: one started there or by a click has nothing
-- left to wait with, and the Insert that opens or closes the menu must not become the key. So a wait that runs holds
-- the other keys back (Menu.capturing()).
local function menu_open_or_closed(t, open)
    if open ~= (S.ui_open == true) then Menu.cancel() end
    if not open and S.ui_open then
        S.summary_at = t                      -- the summary's auto-hide counts from here
        if S.details_key ~= nil then drop_details() end
    end
    S.ui_open = open
end

-- Its own key wait ends with it.
local function close_settings(t)
    local SW = S.settings_window
    SW.open, SW.keys = false, {}
    if select(2, Menu.waiting_for()) == "window" then Menu.cancel() end
    S.summary_at = t                          -- the summary's auto-hide counts from here
end

-- The game paused in a menu, or no longer: the damage numbers live are forgotten, so that none comes back stale (and
-- none is made while it lasts: see hit_sink.points); the summary's auto-hide counts from its end, and the hidden-stats
-- evidence takes its snapshot STAT_AFTER_PAUSE s after it (stat_sample).
local function set_paused(t, paused)
    if paused == S.paused then return end
    S.paused = paused
    if paused then
        S.numbers:clear()
    else
        S.summary_at, S.stat_due = t, t + STAT_AFTER_PAUSE
    end
end

-- A draw call the overlay found missing (it draws plain rectangles instead): one debug line the first time.
local function note_draw_missing()
    for _, name in ipairs(Overlay.missing()) do
        if not S.draw_logged[name] then
            S.draw_logged[name] = true
            log_line("draw call missing: " .. name .. " (plain rectangles drawn instead)")
        end
    end
end

-- Enemy HP numbers ----------------------------------------------------------------------------------

-- One frame's read of the game's bars (gauges.shown or gauges.boss), for the HP numbers and the enemy plate alike; one
-- that raises is counted at `where` and gives none.
local function read_gauge(where, read, t)
    local ok, v = pcall(read, t)
    if ok then return v end
    Hook.fail(where, v)
    return nil
end

-- The bars the game draws now over hostile characters (gauges.shown), each with its character's HP; a bar whose HP
-- cannot be read gets no numbers.
local function enemy_bars_frame(bars)
    local list = {}
    for _, bar in ipairs(bars) do
        local hp, full = actors.health(bar.character)
        if hp then
            bar.hp, bar.full = hp, full
            list[#list + 1] = bar
        end
    end
    local err = EnemyBars.draw(list, settings)
    if err then Hook.fail("enemy bars", err) end
end

-- The boss bar the game draws now at the top of the screen (gauges.boss), with its target's HP; no numbers when that
-- HP cannot be read.
local function boss_bar_frame(bar)
    local hp, full = actors.health(bar.character)
    if hp == nil then return end
    bar.hp, bar.full = hp, full
    local err = EnemyBars.draw_boss(bar, settings)
    if err then Hook.fail("boss bar", err) end
end

-- The HP the HP numbers read this frame (bar.hp, bar.full of the bars over heads, then of the boss bar; a bar without
-- them was not read) goes to the open fight's enemy under the bar (Fight:note_hp), and to the live window's enemy line
-- when it is about that enemy: that line is built every LIVE_EVERY s from the HP the counted hits left, and so lagged
-- the numbers by a hit or by HP the game took away outside them. No game call of its own: the bar's character is
-- matched to the Actor the hits made by its address (actors.cached).
local function meter_hp(bars, boss)
    local fight = S.fight
    local header = S.live_model and S.live_model.header
    local function take(bar)
        local actor = bar.hp ~= nil and actors.cached(bar.character) or nil
        if actor == nil then return end
        local key, e = fight:note_hp(actor.key, bar.hp, bar.full)
        if e ~= nil and header ~= nil and header.key == key then header.hp_text = View.header_hp(e, i18n) end
    end
    for _, bar in ipairs(bars or {}) do take(bar) end
    if boss then take(boss) end
end

-- The poise and the status buildup under the boss bar the game draws now (gauges.boss), read from its boss and its
-- hit controller at most every Buildup.READ_EVERY s; a status in effect drains at the frame's t in between.
local function buildup_frame(t, bar)
    local err = BuildupBars.draw(bar, Buildup.read(bar.character, t, bar.hc), settings, t)
    if err then Hook.fail("buildup bars", err) end
end

-- The player's own HP and stamina by the HUD bars the game draws now (gauges.player), read from the player's
-- character.
local function player_numbers_frame(bars)
    local err = PlayerNumbers.draw(bars, PlayerVitals.read(player_character()), settings)
    if err then Hook.fail("player numbers", err) end
end

-- Enemy plate ---------------------------------------------------------------------------------------

-- The kinds in sight (each { character, actor }) that the last plate build listed while the debug collector collects,
-- for meet_in_sight in the same frame; nil when none.
local in_sight = nil

-- The kinds near the player, in the plate's order (see forget_plate): the boss bar's boss, the characters under the
-- hostile bars and the open fight's living enemies, each enemy once (its Actor's key), one entry per CharaID:
-- { chara_id, name (its first enemy's), count, actor, character (one in sight, nil when none is) }. Only enemies
-- (Actor kind "enemy": no party member, NPC or critter, game/actors.lua) with a CharaID are listed, none the fight has
-- as killed. Also the boss's CharaID when it is listed. While no boss bar is read and the last one was read at most
-- EnemyPlate.HOLD s ago (V.boss_at), its boss's Actor as of the last build that read it is listed first, with no
-- character (its last table, nothing of a game object that may be gone), and is still the boss: the plate's content
-- holds with its place (ui/enemy_plate.lua) when the bar blinks off.
local function plate_kinds(t, bars, boss)
    local V, fight = S.plate_view, S.fight
    local aliases = fight and fight.aliases
    local list, by_id, counted = {}, {}, {}
    local function add(actor, character)
        if actor == nil or actor.kind ~= "enemy" or math.type(actor.chara_id) ~= "integer" then return nil end
        -- a returning enemy's new object is the fight's enemy it continues, counted once with it
        local alias = aliases and aliases[actor.key]
        local key = alias and alias.key or actor.key
        if counted[key] then return nil end
        local e = fight and fight.enemies[key]
        if e and e.killed then return nil end
        counted[key] = true
        local id = actor.chara_id
        local kind = by_id[id]
        if kind == nil then
            kind = { chara_id = id, name = actor.name, count = 0, actor = actor }
            by_id[id], list[#list + 1] = kind, kind
            if V.order[id] == nil then
                V.seen = V.seen + 1
                V.order[id] = V.seen
            end
        end
        kind.count = kind.count + 1
        if kind.character == nil and character ~= nil then kind.character, kind.actor = character, actor end
        return id
    end
    local boss_id
    if boss ~= nil then
        V.boss = actors.of(boss.character)
        boss_id = add(V.boss, boss.character)
    elseif V.boss ~= nil and V.boss_at ~= nil and t - V.boss_at <= EnemyPlate.HOLD then
        boss_id = add(V.boss, nil)
    else
        V.boss = nil
    end
    for _, bar in ipairs(bars or {}) do add(actors.of(bar.character), bar.character) end
    if fight then
        -- by key: the order the fight's enemies are first seen in must not hang on pairs()
        local keys = {}
        for key, e in pairs(fight.enemies) do
            if not e.killed then keys[#keys + 1] = key end
        end
        table.sort(keys)
        for _, key in ipairs(keys) do add(fight.enemies[key].actor, nil) end
    end
    table.sort(list, function(a, b) return V.order[a.chara_id] < V.order[b.chara_id] end)
    return list, boss_id
end

-- The plate's model built for the kinds near the player: each with its table in use, read from a character in sight
-- (at most once a second a kind, game/enemy_table.lua), else the kind's last one, and the statuses that work on it
-- (game/enemies.lua: tried from a character in sight at most every PLATE_DATA_EVERY s a kind, else the kind's record,
-- which spends no try); the player's weapon; the boss. nil when no kind is listed. While the debug collector collects,
-- the kinds in sight are noted for it (in_sight).
local function plate_build(t, bars, boss)
    local list, boss_id = plate_kinds(t, bars, boss)
    if #list == 0 then return nil end
    local kinds, data_at, sight = {}, S.plate_view.data_at, collecting() and {} or nil
    for i, k in ipairs(list) do
        local id, tbl = k.chara_id, nil
        if k.character ~= nil then tbl = EnemyTable.read(k.character, id, t) else tbl = EnemyTable.cached(id) end
        local character = k.character
        if character ~= nil then
            if data_at[id] == nil or t - data_at[id] >= PLATE_DATA_EVERY then data_at[id] = t else character = nil end
        end
        local data = enemies.data(character, k.actor)
        if sight and k.character ~= nil then sight[#sight + 1] = { character = k.character, actor = k.actor } end
        kinds[i] = { chara_id = id, name = k.name, count = k.count, table = tbl, enabled = data and data.enabled }
    end
    in_sight = sight
    return S.plate:build(t, kinds, Weapon.read(player_character(), t), boss_id)
end

-- The enemy plate this frame (`bars`, `boss`: the game's bars as read for this frame, nil when not read). Shown while
-- a fight is open or a hostile bar is drawn (over a head or the boss's), and PLATE_LINGER s after neither; then its
-- kinds' order is forgotten. While one holds it is built at most every PLATE_EVERY s (at once when it appears); a
-- build that lists no kind keeps the last plate for PLATE_LINGER s after the last one that did, then none. Drawn
-- every frame it is shown. Each frame with a boss bar is noted for the boss's hold (plate_kinds). Gives whether it was
-- shown and whether it was built.
local function plate_frame(t, bars, boss)
    local V = S.plate_view
    if boss ~= nil then V.boss_at = t end
    local near = S.fight ~= nil or (bars ~= nil and #bars > 0) or boss ~= nil
    if near then V.near_at = t end
    if V.near_at == nil then return false, false end
    if t - V.near_at >= PLATE_LINGER then
        forget_plate()
        return false, false
    end
    local built = false
    if near and (V.built_at == nil or t - V.built_at >= PLATE_EVERY) then
        V.built_at, built = t, true -- noted first: a build that raises is not tried again on every frame
        local plate = plate_build(t, bars, boss)
        if plate ~= nil then
            V.plate, V.listed_at = plate, t
        elseif V.listed_at == nil or t - V.listed_at >= PLATE_LINGER then
            V.plate = nil
        end
    end
    if V.plate ~= nil then
        local err = EnemyPlate.draw(V.plate, settings, boss, t)
        if err then Hook.fail("enemy plate", err) end
    end
    return true, built
end

-- The kinds in sight that this frame's plate build listed, met by the debug collector after the plate's frame, so that
-- the plate's time is its own; forgotten once met (no character is kept past its frame).
local function meet_in_sight(t)
    local list = in_sight
    in_sight = nil
    if list == nil or not collecting() then return end
    for _, k in ipairs(list) do collector_meet(k.character, k.actor, t) end
end

-- plate_frame; with `debug` on, its time by os.clock over the frames it is shown, for log_plate_cost.
local function measured_plate_frame(t, bars, boss)
    if not settings.values.debug then
        plate_frame(t, bars, boss)
        return
    end
    local c0 = os.clock()
    local shown, built = plate_frame(t, bars, boss)
    if not shown then return end
    local ms, c = (os.clock() - c0) * 1000, S.plate_cost
    c.frames, c.ms, c.max = c.frames + 1, c.ms + ms, math.max(c.max, ms)
    if built then c.builds = c.builds + 1 end
end

-- Damage numbers ------------------------------------------------------------------------------------

local function damage_numbers_frame(t)
    local err = DamageNumbersUI.draw(S.numbers, settings, t)
    if err then Hook.fail("damage numbers", err) end
end

-- Hidden stats --------------------------------------------------------------------------------------

-- Whether the Entry has a line with a personal number.
local function wants_base(entry)
    if type(entry) ~= "table" or type(entry.lines) ~= "table" then return false end
    for _, line in ipairs(entry.lines) do
        if line.base ~= nil then return true end
    end
    return false
end

local BASE_KEYS = { "who", "phys_defence", "magic_defence", "strength", "magic" }
local TOTAL_KEYS = { "phys", "magic", "equipped", "who" }

-- Whether two tables (or nils) hold the same values at `keys`.
local function same_values(a, b, keys)
    if a == nil or b == nil then return a == b end
    for _, key in ipairs(keys) do
        if a[key] ~= b[key] then return false end
    end
    return true
end

-- Whether the Entry has a line followed by a total line.
local function wants_total(entry)
    if type(entry) ~= "table" or type(entry.lines) ~= "table" then return false end
    for _, line in ipairs(entry.lines) do
        if line.total ~= nil then return true end
    end
    return false
end

-- What the total lines need, HiddenStatsModel.panel's `total`: the shown character's totals
-- (HiddenScreens.totals(chara_id)), whether the hovered augment or ring is on that character (by
-- HiddenScreens.equipped(chara_id): unknown when that part cannot be read) and whose; nil when the totals cannot be
-- read (what is on is not read then).
local function hidden_total(hover)
    local sums = HiddenScreens.totals(hover.chara_id)
    if type(sums) ~= "table" then return nil end
    local on = HiddenScreens.equipped(hover.chara_id)
    local set, key = nil, nil
    if type(on) == "table" then
        if hover.kind == "augment" then set, key = on.augments, hover.name else set, key = on.items, hover.id end
    end
    local equipped = nil
    if type(set) == "table" then equipped = set[key] == true end
    return { phys = sums.phys, magic = sums.magic, equipped = equipped, who = hover.who }
end

-- With `debug` on, the first time in a game session a screen's panel is placed by an anchor with a part that fell back
-- to its measured place (Hover.anchor.read), one debug.log line names the parts and the place taken:
-- "hidden stats: items anchor fell back: width (x=1212 y=423 width=470)". Once per screen (S.anchor_told); with
-- `debug` off nothing is written or noted.
local ANCHOR_PARTS = { "x", "y", "width" }
local function tell_anchor(hover)
    local anchor = hover.anchor
    local read = type(anchor) == "table" and anchor.read or nil
    local screen = tostring(hover.screen)
    if not settings.values.debug or type(read) ~= "table" or S.anchor_told[screen] then return end
    local parts = {}
    for _, part in ipairs(ANCHOR_PARTS) do
        if read[part] == false then parts[#parts + 1] = part end
    end
    if #parts == 0 then return end
    S.anchor_told[screen] = true
    local function g(v) return type(v) == "number" and string.format("%g", v) or tostring(v) end
    log_line(string.format("hidden stats: %s anchor fell back: %s (x=%s y=%s width=%s)", screen,
        table.concat(parts, ", "), g(anchor.x), g(anchor.y), g(anchor.width)))
end

-- The hidden-stats panel this frame, paused or not: what is hovered on the guild's augments screen, the item screen or
-- the equipment screen (HiddenScreens.current), its meaning (HiddenStatsData), the game's numbers for it
-- (HiddenStatsGame; a ring's by the vocation of the character the screen shows) and, for an entry with a
-- personal number, that character's base (HiddenScreens.base(chara_id); none while whose it is is unknown);
-- for an entry with a total line, that character's totals and whether the thing is on them (hidden_total; not
-- read for the others). The Panel is built again only when one of them (the base and the totals by their numbers) or
-- the language changed, and drawn every frame by the game's description (Hover.anchor). Gives whether something was
-- hovered and whether the panel was built.
local function hidden_stats_frame(t)
    local hover = HiddenScreens.current(t)
    if hover == nil then
        if next(S.hidden_view) ~= nil then forget_hidden() end
        return false, false
    end
    local kind, id, entry, raw = hover.kind, nil, nil, nil
    if kind == "augment" then
        id = hover.name
        entry = HiddenStatsData.augment(id)
        if entry and entry.lines then raw = HiddenStatsGame.augment(id) end
    elseif kind == "ring" then
        id = hover.id
        entry = HiddenStatsData.ring(id)
        if entry and entry.lines then raw = HiddenStatsGame.ring(id, HiddenScreens.job(hover.chara_id)) end
    end
    local who, base, total = hover.who, nil, nil
    if who ~= nil and wants_base(entry) then base = HiddenScreens.base(hover.chara_id) end
    if wants_total(entry) then total = hidden_total(hover) end
    local lang = i18n.lang()
    local V, built = S.hidden_view, false
    if V.kind ~= kind or V.id ~= id or V.lang ~= lang or V.who ~= who or V.raw ~= raw
            or not same_values(V.base, base, BASE_KEYS) or not same_values(V.total, total, TOTAL_KEYS) then
        -- noted first: a build that raises is not tried again on every frame
        V = { kind = kind, id = id, lang = lang, who = who, raw = raw, base = base, total = total }
        S.hidden_view, built = V, true
        V.panel = HiddenStatsModel.panel(entry, raw, base, total)
    end
    if V.panel ~= nil then
        local err = HiddenStatsUI.draw(V.panel, hover.anchor, settings)
        if err then Hook.fail("hidden stats", err) end
        tell_anchor(hover)
    end
    return true, built
end

-- hidden_stats_frame; with `debug` on, its time by os.clock in every frame, for log_hidden_cost: on the frames
-- something is hovered, else on the idle ones; the first idle frame after one or more hovered ones writes the line.
local function measured_hidden_stats_frame(t)
    if not settings.values.debug then
        hidden_stats_frame(t)
        return
    end
    local c0 = os.clock()
    local shown, built = hidden_stats_frame(t)
    local ms, c = (os.clock() - c0) * 1000, S.hidden_cost
    if shown then
        c.frames, c.ms, c.max = c.frames + 1, c.ms + ms, math.max(c.max, ms)
        if built then c.builds = c.builds + 1 end
        return
    end
    if c.frames > 0 then
        log_hidden_cost()
        c = S.hidden_cost
    end
    c.idle, c.idle_ms, c.idle_max = c.idle + 1, c.idle_ms + ms, math.max(c.idle_max, ms)
end

-- Journal -------------------------------------------------------------------------------------------

-- On the fight the summary shows (the selections and pages of another fight are forgotten); the settings window closes,
-- the damage numbers live are forgotten.
local function open_journal()
    if S.settings_window.open then close_settings(S.t) end
    S.numbers:clear()
    local J = S.journal
    if J.index ~= S.history_index then J.sel, J.page = {}, {} end
    J.open, J.index, J.dirty, J.keys = true, S.history_index, true, {}
end

local function close_journal(t)
    local J = S.journal
    J.open, J.keys = false, {}
    S.summary_at = t                          -- the summary's auto-hide counts from here
end

-- The current tab's model of `snap` (nil without a fight).
local function journal_body(tab, snap, sel)
    if snap == nil then return nil end
    if tab == "summary" then return View.summary(snap, ctx) end
    if tab == "enemies" then return Journal.enemies(snap, ctx, sel) end
    local build = JournalTabs[tab]
    if type(build) == "function" then return build(snap, ctx, sel) end
    return nil
end

-- How many rows the selection of a tab's body can take (SELECTS); nil for a tab without a selection or a body without
-- its rows.
local function selectable(tab, body)
    local rows_of = SELECTS[tab]
    if rows_of == nil or type(body) ~= "table" then return nil end
    local rows = rows_of(body)
    if type(rows) ~= "table" then return nil end
    return #rows
end

-- The models of the open journal. Noted as built first, so a build that raises is not tried again on every frame
-- (the window then shows its tabs over an empty header and body).
local function build_journal()
    local J = S.journal
    J.dirty, J.model, J.rows = false, nil, nil
    local count = S.history:count()
    J.index = math.max(1, math.min(J.index, count))
    local snap = S.history:get(J.index)
    local tab = J.tab
    local body = journal_body(tab, snap, J.sel[tab])
    -- the selection as the model clamped it, so that presses past the last row do not build up
    if type(body) == "table" and math.type(body.sel) == "integer" then J.sel[tab] = body.sel end
    local n = selectable(tab, body)
    if n then J.rows = { tab = tab, index = J.index, n = n } end
    J.model = {
        header = Journal.header(snap, ctx, J.index, count),
        body = body,
        hint = i18n.t("journal_hint", Menu.key_name(settings.values.journal_key)),
    }
end

-- The actions of the journal's window or keys (ui/journal.lua); pages = the pages its body took. A new selection is
-- clamped to the rows of the last built body of this tab and fight first, so that Down on the last row changes nothing
-- (a body not built yet clamps it itself). A page change only redraws: no model reads the page.
local function apply_journal(a, pages, t)
    local J = S.journal
    local changed = false
    local tab = J.tab
    if a.tab ~= nil then
        tab = a.tab
    elseif a.tab_step ~= nil and a.tab_step ~= 0 then
        local tabs, at = Journal.TABS, 1
        for i, id in ipairs(tabs) do
            if id == J.tab then at = i end
        end
        tab = tabs[(at - 1 + a.tab_step) % #tabs + 1]
    end
    if tab ~= J.tab then J.tab, J.page[tab], changed = tab, 1, true end
    if a.history ~= nil and a.history ~= 0 then
        local index = math.max(1, math.min(S.history:count(), J.index + a.history))
        if index ~= J.index then J.index, J.page, changed = index, {}, true end
    end
    tab = J.tab
    if SELECTS[tab] then
        local old = J.sel[tab] or 1
        local sel = math.tointeger(a.select) or old
        if a.select_step ~= nil and a.select_step ~= 0 then sel = sel + a.select_step end
        local rows = J.rows
        local n = rows and rows.tab == tab and rows.index == J.index and rows.n or math.huge
        sel = math.max(1, math.min(sel, n))
        if sel ~= old then J.sel[tab], J.page[tab], changed = sel, 1, true end
    end
    if a.page ~= nil and a.page ~= 0 then
        local old = J.page[tab] or 1
        J.page[tab] = math.max(1, math.min(pages, old + a.page))
    end
    if changed then J.dirty = true end
    if a.close then close_journal(t) end
end

-- The open journal in place of the overlay: its keys on their press edges (a key held when it opened counts once it
-- was seen up; none while a key wait holds them back), its models when something changed, its window.
local function journal_frame(t)
    local J = S.journal
    local pressed = {}
    for vk in pairs(JournalUI.KEYS) do
        local down = reframework:is_key_down(vk) == true
        if down and J.keys[vk] == false then pressed[vk] = true end
        J.keys[vk] = down
    end
    if Menu.capturing() then pressed = {} end

    if J.dirty then guard("journal models", build_journal) end
    local m = J.model or {}
    local actions, err = JournalUI.draw({ tab = J.tab, header = m.header, body = m.body, page = J.page[J.tab] or 1,
        hint = m.hint }, settings)
    if err then Hook.fail("journal", err) end
    if type(actions) ~= "table" then actions = {} end
    if not err then J.pages = math.max(1, math.tointeger(actions.pages) or 1) end
    -- a smaller window or a larger scale can leave fewer pages than the one kept
    if (J.page[J.tab] or 1) > J.pages then J.page[J.tab] = J.pages end
    apply_journal(actions, J.pages, t)
    apply_journal(JournalUI.key_actions(pressed), J.pages, t)
end

-- Settings window -----------------------------------------------------------------------------------

-- The side effects of settings that changed (each one through settings:set), in the settings window or in the
-- REFramework menu: the language, the history's size, history.json, the models of the switches, the hidden-stats
-- evidence's last snapshot (Debug switched).
local function apply_changes(changed)
    if #changed == 0 then return end
    -- any change rebuilds the journal (its hint names its key) and the settings window (it shows the values)
    S.journal.dirty, S.settings_window.dirty = true, true
    for _, key in ipairs(changed) do
        if key == "language" then
            apply_language()
        elseif key == "history_size" then
            S.history:resize(settings.values.history_size)
            S.history_index = math.max(1, math.min(S.history_index, S.history:count()))
            S.models_dirty = true
        elseif key == "history_file" then
            if settings.values.history_file then
                save_settings()           -- first: the data folder is made by the settings file, not by io.open
                -- off at the start: the file is read now, or the write would drop its fights
                if not S.history_read then guard("history", load_history) end
                write_history()
            end
        elseif key == "enemy_hp_numbers" or key == "boss_hp_numbers" then
            if settings.values[key] == "off" then gauges.reset() end
        elseif key == "enemy_plate" then
            -- off: its hits and what it showed are forgotten, and the bars found, as when the HP numbers go off
            if not settings.values.enemy_plate then
                S.plate:clear()
                forget_plate()
                gauges.reset()
            end
        elseif key == "buildup_bars" then
            -- off: its rises are forgotten, and the bars found, as when the HP numbers go off
            if not settings.values.buildup_bars then
                Buildup.reset()
                gauges.reset()
            end
        elseif key == "player_numbers" then
            -- off: the bars found are forgotten, as when the HP numbers go off
            if not settings.values.player_numbers then gauges.reset() end
        elseif key == "hidden_stats" then
            -- off: the panel kept and the screens found are forgotten
            if not settings.values.hidden_stats then
                HiddenScreens.reset()
                forget_hidden()
            end
        elseif key == "damage_numbers" or key == "damage_numbers_style" then
            S.numbers:clear()
        elseif key == "debug" then
            -- the evidence starts afresh: what changed while Debug was off (level ups, meals) is no record
            Collector.stat_forget()
        elseif SWITCHES[key] then
            S.models_dirty = true
        end
    end
end

-- The journal closes; the meter's models are built again (it can show a summary it did not show).
local function open_settings()
    local SW = S.settings_window
    if S.journal.open then close_journal(S.t) end
    SW.open, SW.dirty, SW.keys = true, true, {}
    S.models_dirty = true
end

-- Noted as built first, so a build that raises is not tried again on every frame (the window is then not drawn).
local function build_settings()
    local SW = S.settings_window
    SW.dirty, SW.model = false, nil
    SW.model = SettingsView.build(settings, i18n)
end

-- A value for `key` from the settings window: through settings:set, then the side effects when it changed.
local function change(key, value)
    local old = settings.values[key]
    if settings:set(key, value) and settings.values[key] ~= old then apply_changes({ key }) end
end

-- The actions of the settings window or of its keys (ui/settings_window.lua) on the open window: the selection
-- first (on a table row Left/Right move it between the row's cells), then a step or Enter on the selected setting (a
-- switch or a table cell flips; a key row waits for a key, or gives the wait up).
local function apply_settings(a, t)
    local SW = S.settings_window
    if not SW.open then return end
    SW.sel, SW.col = SettingsView.move(settings, SW.sel, SW.col, a)
    local key, kind = SettingsView.target(SW.sel, SW.col)
    if key ~= nil and kind ~= "cell" and a.step ~= nil and a.step ~= 0 then
        local value = SettingsView.step(settings, key, a.step)
        if value ~= nil then change(key, value) end
    end
    if key ~= nil and a.activate then
        if kind == "switch" or kind == "cell" then
            change(key, not settings.values[key])
        elseif kind == "key" then
            if Menu.waiting_for() == key then Menu.cancel() else Menu.capture(key, "window") end
        end
    end
    if a.close then close_settings(t) end
end

-- The open settings window: its keys on their press edges (a key held when it opened counts once it was seen up; none
-- while a key wait holds them back), its own key wait, its model when something changed, its window.
local function settings_frame(t)
    local SW = S.settings_window
    local pressed = {}
    for vk in pairs(SettingsUI.KEYS) do
        local down = reframework:is_key_down(vk) == true
        if down and SW.keys[vk] == false then pressed[vk] = true end
        SW.keys[vk] = down
    end
    if Menu.capturing() then pressed = {} end
    if select(2, Menu.waiting_for()) == "window" then
        local changed = Menu.poll(settings)
        if changed then apply_changes({ changed }) end
    end

    if SW.dirty then guard("settings models", build_settings) end
    if SW.model then
        local actions, err = SettingsUI.draw({ model = SW.model, sel = SW.sel, col = SW.col,
            waiting = Menu.waiting_for() }, settings)
        if err then Hook.fail("settings window", err) end
        if type(actions) == "table" then apply_settings(actions, t) end
    end
    apply_settings(SettingsUI.key_actions(pressed), t)
end

local function window_frame(t)
    local open = reframework:is_drawing_ui() == true
    menu_open_or_closed(t, open)
    local waiting = Menu.capturing()
    local J, SW = S.journal, S.settings_window
    -- the windows open as the frame starts: a key of theirs does not open or close the other one
    local journal_was, setup_was = J.open, SW.open

    -- the journal key, on the press edge as the toggle key below; with the journal off it is not read
    if settings.values.journal then
        local jk = settings.values.journal_key
        local jdown = reframework:is_key_down(jk) == true
        if jdown and not S.journal_key_down and jk == S.journal_key_vk and not waiting
                and not (setup_was and SettingsUI.KEYS[jk]) then
            if J.open then close_journal(t) else open_journal() end
        end
        S.journal_key_vk, S.journal_key_down = jk, jdown
    else
        if J.open then close_journal(t) end
        S.journal_key_vk, S.journal_key_down = nil, nil
    end
    -- the settings key, on the press edge as well, also with the journal off
    local sk = settings.values.settings_key
    local sdown = reframework:is_key_down(sk) == true
    if sdown and not S.settings_key_down and sk == S.settings_key_vk and not waiting
            and not (journal_was and JournalUI.KEYS[sk]) then
        if SW.open then close_settings(t) else open_settings() end
    end
    S.settings_key_vk, S.settings_key_down = sk, sdown
    local journal, setup = J.open, SW.open
    -- the player character there this frame (world_frame); without him nothing kept is read
    local world = S.world == true
    -- the game paused in a menu; not read while the journal is open, which a pause does not hide
    local paused = not journal and pause.paused()
    set_paused(t, paused)
    -- the debug collector's look at the player's weapons (at most once a second) and the hidden-stats evidence (every
    -- 2 s, and 1 s after a pause's end), after this frame's pause read; none while the world is not there
    if collecting() and world then
        guard("collector", Collector.weapons, t, player_character)
        guard("collector", stat_sample, t)
    end

    -- the toggle key, on the press edge; not while a key wait holds the keys back, and not for the press that chose
    -- the key; while the journal or the settings window is open, not when it is one of their keys
    local vk = settings.values.toggle_key
    local down = reframework:is_key_down(vk) == true
    if down and not S.key_down and vk == S.key_vk and not waiting
            and not (journal and JournalUI.KEYS[vk]) and not (setup and SettingsUI.KEYS[vk]) then
        S.hidden = not S.hidden
        if not S.hidden then S.summary_at = t end
    end
    S.key_vk, S.key_down = vk, down

    local hide_after = settings.values.summary_autohide
    if S.mode == "summary" and not S.hidden and not open and not journal and not setup and not paused
            and hide_after > 0 and t - (S.summary_at or t) >= hide_after then
        S.hidden = true
    end

    if journal then
        guard("journal", journal_frame, t)
    else
        -- the enemy numbers before both, then the buildup bars, then the player's numbers, then the enemy plate,
        -- then the damage numbers over them: the background list draws in call order, so the settings window's panel
        -- and the meter's are in front of them; none while the game is paused or the world is not there. The
        -- game's bars are read once for the HP numbers, the buildup bars and the plate, only when one wants them; the
        -- player's HUD only for his numbers.
        if not paused and world then
            local v = settings.values
            local over, at_boss, plate = v.enemy_hp_numbers ~= "off", v.boss_hp_numbers ~= "off", v.enemy_plate
            local buildup = v.buildup_bars
            local bars = (over or plate) and read_gauge("enemy bars", gauges.shown, t) or nil
            local boss = (at_boss or plate or buildup) and read_gauge("boss bar", gauges.boss, t) or nil
            local hud = v.player_numbers and read_gauge("player bars", gauges.player, t) or nil
            if over and bars then guard("enemy bars", enemy_bars_frame, bars) end
            if at_boss and boss then guard("boss bar", boss_bar_frame, boss) end
            -- the HP those numbers read, to the open fight and the meter's enemy line (built below)
            if S.fight ~= nil and ((over and bars) or (at_boss and boss)) then
                guard("meter hp", meter_hp, over and bars or nil, at_boss and boss or nil)
            end
            if buildup and boss then guard("buildup bars", buildup_frame, t, boss) end
            if hud then guard("player numbers", player_numbers_frame, hud) end
            if plate then guard("enemy plate", measured_plate_frame, t, bars, boss) end
            if in_sight then guard("collector", meet_in_sight, t) end
            if v.damage_numbers then guard("damage numbers", damage_numbers_frame, t) end
        end
        -- the hidden-stats panel, paused or not (the item and equipment screens pause the game): over those, under
        -- the settings window's panel and the meter's; while the world is not there, nothing
        if settings.values.hidden_stats then
            if world then
                guard("hidden stats", measured_hidden_stats_frame, t)
                note_gone()
            elseif next(S.hidden_view) ~= nil then
                forget_hidden()
            end
        end
        -- the settings window first: a change it makes is in the meter of the same frame
        if setup then guard("settings", settings_frame, t) end
        local mode, hidden = meter_mode(SW.open, paused)
        if not hidden then guard("models", build_models, t, mode) end
        local actions, err = Overlay.draw(overlay_state(mode, hidden), settings)
        if err then Hook.fail("overlay", err) end
        if type(actions) == "table" then apply_actions(actions, t) end
    end
    note_draw_missing()
    save_while_editing(t, open or SW.open)
end

-- Frame and menu ------------------------------------------------------------------------------------

-- The party read; another player character than the one remembered is a new world. A moment without a player
-- keeps the one remembered.
local function refresh_party()
    local addr = player_address()
    if addr ~= nil and S.player_addr ~= nil and addr ~= S.player_addr then reset_world() end
    if addr ~= nil then S.player_addr = addr end
    S.refresh_due = false
    actors.refresh()
end

local function poll_battle(t)
    local b = battle.poll()
    if b then handle(S.clock:on_mode(t, b.mode, b.ending)) end
end

local function tick_clock(t)
    handle(S.clock:tick(t))
end

-- Each step on its own: one that raises does not stop the others. The party read comes first, so that a new world
-- abandons the open fight before its battle mode is read.
local function game_frame(t)
    if S.refresh_due or S.refreshed_at == nil or t - S.refreshed_at >= REFRESH_EVERY then
        S.refresh_due, S.refreshed_at = false, t  -- a read that raises is not tried again on every frame
        guard("refresh", refresh_party)
    end
    guard("battle", poll_battle, t)
    guard("tick", tick_clock, t)
    -- the party's skill states, for the heal skills that tell nothing else (game/heals.lua): only in a fight
    if S.fight ~= nil then guard("heal skills", heals.sample, S.frame, frame_party) end
    guard("heals", heals.poll, S.frame, t, frame_party)
    guard("prune", S.attrib.prune, S.attrib, S.frame, t)
    -- the fights kept since the last frame, also inside a hook (off since then: not written)
    if S.history_write_due then
        if settings.values.history_file then write_history() else S.history_write_due = nil end
    end
end

function M.on_frame()
    local t = now()
    S.t, S.frame = t, S.frame + 1
    frame_party = nil
    guard("world", world_frame, t)
    guard("frame", game_frame, t)
    if settings.values.language == "auto" and t - (S.language_at or -math.huge) >= LANGUAGE_EVERY then
        guard("language", apply_language)
    end
    guard("window", window_frame, t)
    frame_party = nil
end

function M.on_draw_ui()
    local actions, err = Menu.draw(settings, i18n)
    if err then Hook.fail("menu", err) end
    if type(actions) ~= "table" then actions = {} end
    apply_changes(type(actions.changed) == "table" and actions.changed or {})
    if actions.open_settings and not S.settings_window.open then open_settings() end
    if S.notice then imgui.text(S.notice) end
end

-- A party member's new character object joining his actor (actors.on_join), for the debug collector.
actors.on_join(function(actor, old, new)
    if collecting() then guard("collector", Collector.party_join, actor, old, new) end
end)

function M.info()
    local h = Hook.info()
    return {
        version = VERSION, hooks = S.hooks_n, missing = table.move(S.missing, 1, #S.missing, 1, {}),
        draw_missing = Overlay.missing(),
        fighting = S.clock:fighting(), history = S.history:count(), frame = S.frame, loads = S.loads,
        errors = h.errors, last_error = h.last_error, language = i18n.lang(),
        journal = S.journal.open == true, journal_missing = JournalUI.missing(),
        settings_missing = SettingsUI.missing(), enemy_bars_missing = EnemyBars.missing(),
        damage_numbers_missing = DamageNumbersUI.missing(), enemy_plate_missing = EnemyPlate.missing(),
        buildup_bars_missing = BuildupBars.missing(), player_numbers_missing = PlayerNumbers.missing(),
        hidden_stats_missing = HiddenStatsUI.missing(),
    }
end

M.version = VERSION

-- Start ---------------------------------------------------------------------------------------------

guard("install", install)
guard("language", apply_language)
if S.loads == 1 and settings.values.history_file then guard("history", load_history) end

-- The callbacks of the first load call the handlers of the latest one.
local function run(name)
    local m = rawget(_G, "DD2DM")
    local fn = type(m) == "table" and m[name] or nil
    if type(fn) ~= "function" then return end
    local ok, err = pcall(fn)
    if not ok then pcall(Hook.fail, name, err) end
end

if not S.callbacks_requested then
    S.callbacks_requested = true
    -- registered from BeginRendering, so that a reload from inside a frame callback is safe
    re.on_pre_application_entry("BeginRendering", function()
        if not S.callbacks_registered then
            S.callbacks_registered = true
            local ok, err = pcall(function()
                re.on_frame(function() run("on_frame") end)
                re.on_draw_ui(function() run("on_draw_ui") end)
            end)
            if not ok then pcall(Hook.fail, "callbacks", err) end
        end
        -- REFramework builds since 2026-08 remove a callback that returns STOP; older ones ignore it
        return re.CallbackNextAction and re.CallbackNextAction.STOP
    end)
end

if log then
    if #S.missing > 0 then
        pcall(log.warn, "[DD2DamageMeter] game methods not found: " .. table.concat(S.missing, ", "))
    end
    -- "[DD2DamageMeter] Hidden Numbers 1.0.0 loaded (load 1), hooks: 11, missing: 0": the README tells a player who
    -- reports a bug to look for "Hidden Numbers" in REFramework's log; the tag is the files' name, as in the line above
    pcall(log.info, string.format("[DD2DamageMeter] %s %s loaded (load %d), hooks: %d, missing: %d", Menu.TITLE,
        VERSION, S.loads, S.hooks_n, #S.missing))
end
return M
