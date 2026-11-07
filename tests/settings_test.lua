package.path = "mod/reframework/autorun/?.lua;tests/?.lua;" .. package.path

local T = require("testlib")
local test, eq, near = T.test, T.eq, T.near
local Settings = require("DD2DamageMeter/settings")

local KEYS = {
    "language", "toggle_key", "summary_autohide", "history_size", "window_x", "window_y",
    "opacity", "scale", "show_allies", "debug",
    "style", "halo", "bar_px", "outline", "shadow",
    "live_damage", "live_taken", "live_heal", "live_other",
    "summary_enemies", "summary_damage", "summary_armor", "summary_heal", "summary_allies", "summary_other",
    "journal", "journal_key", "history_file", "settings_key",
    "boss_hp_numbers", "enemy_hp_numbers", "enemy_hp_size", "buildup_bars", "player_numbers",
    "damage_numbers", "damage_numbers_style", "damage_numbers_size",
    "enemy_plate", "enemy_plate_size",
    "hidden_stats", "hidden_stats_size",
}

-- In-memory store; `data` is what the "file" holds, `writes` every table handed to write.
local function memory_store(data)
    local store = { data = data, writes = {} }
    function store.read() return store.data end
    function store.write(t)
        store.data = t
        store.writes[#store.writes + 1] = t
    end
    return store
end

local function count_keys(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

test("defaults when the file is missing", function()
    local store = memory_store(nil)
    local s = Settings.load(store)
    local v = s.values
    eq(v.language, "auto", "language")
    eq(v.toggle_key, 0x75, "toggle_key")
    eq(v.summary_autohide, 0, "summary_autohide")
    eq(v.history_size, 10, "history_size")
    eq(v.window_x, 40, "window_x")
    eq(v.window_y, 300, "window_y")
    near(v.opacity, 0.78, 1e-12, "opacity")
    near(v.scale, 1.0, 1e-12, "scale")
    eq(v.show_allies, true, "show_allies")
    eq(v.debug, false, "debug")
    eq(count_keys(v), #KEYS, "number of settings")
    for _, k in ipairs(KEYS) do
        eq(v[k], Settings.DEFAULTS[k], "DEFAULTS." .. k)
    end
    eq(#store.writes, 0, "loading does not write")
    -- values are the caller's own copy, not the shared defaults
    v.opacity = 0.3
    near(Settings.DEFAULTS.opacity, 0.78, 1e-12, "DEFAULTS untouched")
    near(Settings.load(memory_store(nil)).values.opacity, 0.78, 1e-12, "a second load starts from the defaults")
end)

test("values from the file override", function()
    local file = {
        language = "ru", toggle_key = 0x76, summary_autohide = 30, history_size = 25,
        window_x = 100, window_y = 500, opacity = 0.5, scale = 1.5, show_allies = false, debug = true,
    }
    local v = Settings.load(memory_store(file)).values
    for k, expected in pairs(file) do
        eq(v[k], expected, k)
    end
    -- a partial file only overrides what it has
    local p = Settings.load(memory_store({ language = "en", scale = 2 })).values
    eq(p.language, "en", "language from the file")
    near(p.scale, 2, 1e-12, "scale from the file")
    eq(p.history_size, 10, "history_size default")
    near(p.opacity, 0.78, 1e-12, "opacity default")
    eq(p.show_allies, true, "show_allies default")
end)

test("wrong type falls back", function()
    local v = Settings.load(memory_store({
        language = 5, toggle_key = "F6", summary_autohide = "5", history_size = true,
        window_x = {}, window_y = "300", opacity = "0.5", scale = false,
        show_allies = "yes", debug = 0,
    })).values
    for _, k in ipairs(KEYS) do
        eq(v[k], Settings.DEFAULTS[k], k .. " falls back")
    end
    -- a string that is not one of the languages, and nan, are as wrong as a wrong type
    local w = Settings.load(memory_store({ language = "de", opacity = 0 / 0, history_size = 0 / 0 })).values
    eq(w.language, "auto", "unknown language")
    near(w.opacity, 0.78, 1e-12, "nan opacity")
    eq(w.history_size, 10, "nan history_size")
    -- a missing, unreadable or non-table file is a missing file
    local broken_reads = {
        function() return "not a table" end,
        function() return 42 end,
        function() error("cannot read") end,
    }
    for i, read in ipairs(broken_reads) do
        local b = Settings.load({ read = read, write = function() end }).values
        for _, k in ipairs(KEYS) do
            eq(b[k], Settings.DEFAULTS[k], "broken read " .. i .. " " .. k)
        end
    end
end)

test("numbers clamped", function()
    local function load(t) return Settings.load(memory_store(t)).values end
    local lo = load({
        opacity = 0, scale = -3, history_size = 0, summary_autohide = -5,
        window_x = -50, window_y = -1,
    })
    near(lo.opacity, 0.2, 1e-12, "opacity min")
    near(lo.scale, 0.6, 1e-12, "scale min")
    eq(lo.history_size, 1, "history_size min")
    eq(lo.summary_autohide, 0, "summary_autohide min")
    eq(lo.window_x, 0, "window_x min")
    eq(lo.window_y, 0, "window_y min")
    local hi = load({
        opacity = 5, scale = 10, history_size = 500, summary_autohide = 9999,
        window_x = 1e9, window_y = math.huge,
    })
    near(hi.opacity, 1, 1e-12, "opacity max")
    near(hi.scale, 2, 1e-12, "scale max")
    eq(hi.history_size, 32, "history_size max")
    eq(hi.summary_autohide, 600, "summary_autohide max")
    eq(hi.window_x, 16384, "window_x max")
    eq(hi.window_y, 16384, "window_y max")
    -- the bounds themselves and values inside the range stay as they are
    local edge = load({ opacity = 0.2, scale = 2, history_size = 32, summary_autohide = 600 })
    near(edge.opacity, 0.2, 1e-12, "opacity at its minimum")
    near(edge.scale, 2, 1e-12, "scale at its maximum")
    eq(edge.history_size, 32, "history_size at its maximum")
    eq(edge.summary_autohide, 600, "summary_autohide at its maximum")
    local mid = load({ opacity = 0.5, scale = 1.25 })
    near(mid.opacity, 0.5, 1e-12, "opacity inside")
    near(mid.scale, 1.25, 1e-12, "scale inside")
    -- counts and pixels are whole numbers: rounded, and stored as integers even when the file has floats
    local whole = load({ history_size = 12.6, window_x = 40.0, window_y = 300.4, summary_autohide = 2.5 })
    eq(whole.history_size, 13, "history_size rounded")
    eq(whole.window_x, 40, "window_x")
    eq(whole.window_y, 300, "window_y rounded")
    eq(whole.summary_autohide, 3, "summary_autohide rounded")
    for _, k in ipairs({ "history_size", "window_x", "window_y", "summary_autohide", "toggle_key" }) do
        eq(math.type(whole[k]), "integer", k .. " is an integer")
    end
end)

-- toggle_key is a virtual-key code, not a quantity: 0 must not become 1 (the left mouse button,
-- DD2's light attack) and 1000 must not become 254 (VK_OEM_CLEAR). A bad code is as wrong as a
-- wrong type.
test("toggle_key out of range rejected", function()
    local function key_from_file(value)
        return Settings.load(memory_store({ toggle_key = value })).values.toggle_key
    end
    eq(key_from_file(0), 0x75, "0 (unbound) falls back, not clamped to 1")
    eq(key_from_file(-1), 0x75, "negative falls back")
    eq(key_from_file(255), 0x75, "above 254 falls back")
    eq(key_from_file(1000), 0x75, "1000 falls back, not clamped to 254")
    eq(key_from_file(1e9), 0x75, "huge falls back")
    eq(key_from_file(math.huge), 0x75, "inf falls back")
    eq(key_from_file(-math.huge), 0x75, "-inf falls back")
    eq(key_from_file(0 / 0), 0x75, "nan falls back")
    eq(key_from_file(117.5), 0x75, "a fraction is not a key code")
    eq(key_from_file("117"), 0x75, "a string is not a key code")
    -- the valid range stays as it is; a float with a whole value is stored as an integer
    eq(key_from_file(1), 1, "lowest code")
    eq(key_from_file(254), 254, "highest code")
    eq(key_from_file(0x76), 0x76, "F7")
    eq(key_from_file(118.0), 118, "whole float accepted")
    eq(math.type(key_from_file(118.0)), "integer", "stored as an integer")

    -- the menu path refuses the same values and leaves the key and the file alone
    local store = memory_store({ toggle_key = 0x76 })
    local s = Settings.load(store)
    for _, bad in ipairs({ 0, -1, 255, 1000, 117.5, 0 / 0, math.huge, "117", false }) do
        eq(s:set("toggle_key", bad), false, "set refuses " .. tostring(bad))
        eq(s.values.toggle_key, 0x76, "toggle_key unchanged after " .. tostring(bad))
    end
    eq(s:flush(), false, "refusals leave nothing to save")
    eq(#store.writes, 0, "rejections write nothing")
    -- F10: the file's F7 moved the journal to F8 and the settings window to F9
    eq(s:set("toggle_key", 0x79), true, "a valid code is accepted")
    eq(s.values.toggle_key, 0x79, "toggle_key changed")
    eq(s:set("toggle_key", 254), true, "highest code accepted")
    eq(s:set("toggle_key", 1), true, "lowest code accepted")
    eq(s.values.toggle_key, 1, "toggle_key at the lowest code")
    eq(#store.writes, 0, "set does not write")
    eq(s:flush(), true, "flush saves the changes")
    eq(store.data.toggle_key, 1, "toggle_key written")
    eq(#store.writes, 1, "one write for all the changes")
end)

test("set validates, flush writes once", function()
    local store = memory_store({ language = "en" })
    local s = Settings.load(store)

    eq(s:set("opacity", 0.5), true, "valid number accepted")
    near(s.values.opacity, 0.5, 1e-12, "opacity changed")
    eq(#store.writes, 0, "set does not write")

    eq(s:set("opacity", "0.9"), false, "wrong type rejected")
    near(s.values.opacity, 0.5, 1e-12, "opacity unchanged after a rejection")
    eq(s:set("language", "de"), false, "language outside the list rejected")
    eq(s.values.language, "en", "language unchanged after a rejection")
    eq(s:set("debug", nil), false, "nil rejected")
    eq(s:set("show_allies", 1), false, "a number is not a boolean")

    eq(s:set("opacity", 7), true, "out of range number accepted")
    near(s.values.opacity, 1, 1e-12, "and clamped")
    eq(s:set("history_size", 7.4), true, "fraction accepted")
    eq(s.values.history_size, 7, "and rounded")
    eq(s:set("language", "ru"), true, "language")
    eq(s:set("show_allies", false), true, "boolean false is a value, not a rejection")
    eq(s.values.show_allies, false, "show_allies off")
    eq(#store.writes, 0, "still nothing written after many changes")
    eq(store.data.language, "en", "the file still holds the old value")

    -- one flush writes everything
    eq(s:flush(), true, "flush wrote")
    eq(#store.writes, 1, "one write")
    near(store.data.opacity, 1, 1e-12, "the clamped value is written")
    eq(store.data.show_allies, false, "show_allies off written")
    eq(count_keys(store.data), #KEYS, "the whole table is written")
    eq(store.data.language, "ru", "other values travel along")

    -- the table handed to the store is a snapshot, not the live values
    store.data.language = "en"
    eq(s.values.language, "ru", "store cannot change the live values")

    -- nothing changed since: flush does nothing
    eq(s:flush(), false, "flush without changes")
    eq(#store.writes, 1, "no second write")

    -- same value again: accepted, still nothing to save
    eq(s:set("language", "ru"), true, "same value accepted")
    eq(s:flush(), false, "a same-value set is not a change")
    eq(#store.writes, 1, "no write when nothing changed")

    -- a new change makes it dirty again, once
    eq(s:set("scale", 1.5), true, "scale")
    eq(s:set("scale", 1.25), true, "scale again")
    eq(s:flush(), true, "second flush")
    eq(#store.writes, 2, "one more write")
    eq(s:flush(), false, "and clean again")

    -- what was saved is what the next session loads
    local again = Settings.load(store).values
    for _, k in ipairs(KEYS) do
        eq(again[k], s.values[k], "reloaded " .. k)
    end

    -- a change undone before the flush still counts as a change (cheap, and always safe)
    local back = Settings.load(memory_store(nil))
    back:set("opacity", 0.5)
    back:set("opacity", Settings.DEFAULTS.opacity)
    eq(back:flush(), true, "dirty stays dirty")
end)

test("unknown key dropped", function()
    local store = memory_store({ scale = 1.5, foo = 1, extra = "x", [1] = "list item" })
    local s = Settings.load(store)
    eq(s.values.foo, nil, "foo dropped")
    eq(s.values.extra, nil, "extra dropped")
    eq(s.values[1], nil, "list item dropped")
    eq(count_keys(s.values), #KEYS, "only the known settings remain")
    near(s.values.scale, 1.5, 1e-12, "known key kept")

    eq(s:set("foo", 1), false, "set refuses an unknown key")
    eq(s:set(1, 1), false, "set refuses a non-string key")
    eq(s.values.foo, nil, "foo not stored")
    eq(#store.writes, 0, "nothing written for unknown keys")

    -- the first real save cleans the file
    eq(s:set("debug", true), true, "debug")
    eq(s:flush(), true, "saved")
    eq(store.data.foo, nil, "foo gone from the written table")
    eq(store.data.extra, nil, "extra gone from the written table")
    eq(count_keys(store.data), #KEYS, "written table has the known settings only")
end)

test("a failing store does not break settings", function()
    local s = Settings.load({
        read = function() error("disk gone") end,
        write = function() error("disk full") end,
    })
    eq(s.values.history_size, 10, "defaults after a failed read")
    eq(s:set("history_size", 20), true, "set does not touch the store")
    eq(s.values.history_size, 20, "the value is live for this session")
    eq(s:flush(), false, "flush survives a failed write and reports it")
    eq(s.values.history_size, 20, "the value stays live")
end)

test("a failed write keeps the settings dirty until a write works", function()
    local store = memory_store({})
    local broken = true
    local write = store.write
    store.write = function(t)
        if broken then error("disk full") end
        write(t)
    end
    local s = Settings.load(store)
    eq(s:set("scale", 1.5), true, "set")
    eq(s:flush(), false, "the write fails")
    eq(s:flush(), false, "and again")
    eq(#store.writes, 0, "nothing reached the file")
    broken = false
    eq(s:flush(), true, "the next flush writes")
    near(store.data.scale, 1.5, 1e-12, "the pending value is saved")
    eq(s:flush(), false, "and then it is clean")
    eq(#store.writes, 1, "one write")
end)

test("LIMITS exports the numeric ranges read-only", function()
    local L = Settings.LIMITS
    eq(type(L), "table", "LIMITS")
    -- every numeric setting has a range, nothing else does
    for _, k in ipairs(KEYS) do
        eq(type(L[k]) == "table", type(Settings.DEFAULTS[k]) == "number", "range of " .. k)
    end
    eq(L.language, nil, "a string setting has no range")
    eq(L.show_allies, nil, "a boolean has no range")
    near(L.opacity.min, 0.2, 1e-12, "opacity min")
    near(L.opacity.max, 1, 1e-12, "opacity max")
    eq(L.opacity.integer, nil, "opacity is not integer")
    near(L.scale.min, 0.6, 1e-12, "scale min")
    near(L.scale.max, 2, 1e-12, "scale max")
    eq(L.history_size.min, 1, "history_size min")
    eq(L.history_size.max, 32, "history_size max")
    eq(L.history_size.integer, true, "history_size is integer")
    eq(L.summary_autohide.max, 600, "summary_autohide max")
    eq(L.window_x.max, 16384, "window_x max")
    eq(L.toggle_key.min, 1, "toggle_key min")
    eq(L.toggle_key.max, 254, "toggle_key max")
    eq(L.toggle_key.code, true, "toggle_key is a code")
    eq(L.journal_key.min, 1, "journal_key min")
    eq(L.journal_key.max, 254, "journal_key max")
    eq(L.journal_key.code, true, "journal_key is a code")
    eq(L.settings_key.min, 1, "settings_key min")
    eq(L.settings_key.max, 254, "settings_key max")
    eq(L.settings_key.code, true, "settings_key is a code")

    -- read-only, at both levels
    eq(pcall(function() L.opacity = {} end), false, "cannot replace a range")
    eq(pcall(function() L.opacity.min = 0 end), false, "cannot edit a range")
    eq(pcall(function() L.extra = {} end), false, "cannot add a range")
    near(L.opacity.min, 0.2, 1e-12, "range unchanged")
    -- a copy: the validation does not read it
    local s = Settings.load(memory_store(nil))
    s:set("opacity", 0)
    near(s.values.opacity, 0.2, 1e-12, "opacity still clamped to the real limit")

    eq(L.bar_px.min, 1, "bar_px min"); eq(L.bar_px.max, 8, "bar_px max"); eq(L.bar_px.integer, true, "bar_px is integer")
    near(L.shadow.min, 0, 1e-12, "shadow min"); near(L.shadow.max, 1, 1e-12, "shadow max")
    eq(L.shadow.integer, nil, "shadow is not integer")
    eq(L.style, nil, "the style is a choice, not a range")

    -- every key can be walked
    local n = 0
    for _ in pairs(L) do n = n + 1 end
    eq(n, 15, "fifteen numeric settings (hidden_stats_size the fifteenth)")
end)

test("the look of the window: style, halo, bar thickness, outline, shadow", function()
    local v = Settings.load(memory_store(nil)).values
    eq(v.style, "frameless", "no background by default")
    eq(v.halo, false, "no halo by default")
    eq(v.bar_px, 3, "3 px bars")
    eq(math.type(v.bar_px), "integer", "a whole number of pixels")
    eq(v.outline, true, "numbers outlined by default")
    near(v.shadow, 0.8, 1e-12, "shadow strength")

    local f = Settings.load(memory_store({ style = "panel", halo = true, bar_px = 6, outline = false, shadow = 0.4 })).values
    eq(f.style, "panel", "the panel from the file"); eq(f.halo, true, "halo on"); eq(f.bar_px, 6, "bar_px")
    eq(f.outline, false, "outline off"); near(f.shadow, 0.4, 1e-12, "shadow")

    -- wrong types and unknown styles fall back
    local w = Settings.load(memory_store({ style = "glass", halo = "yes", bar_px = "3", outline = 1, shadow = "0.5" })).values
    for _, k in ipairs({ "style", "halo", "bar_px", "outline", "shadow" }) do
        eq(w[k], Settings.DEFAULTS[k], k .. " falls back")
    end
    eq(Settings.load(memory_store({ style = 2 })).values.style, "frameless", "a number is no style")

    -- clamped and rounded
    local lo = Settings.load(memory_store({ bar_px = 0, shadow = -1 })).values
    eq(lo.bar_px, 1, "bar_px min"); near(lo.shadow, 0, 1e-12, "shadow min")
    local hi = Settings.load(memory_store({ bar_px = 20, shadow = 5 })).values
    eq(hi.bar_px, 8, "bar_px max"); near(hi.shadow, 1, 1e-12, "shadow max")
    eq(Settings.load(memory_store({ bar_px = 2.6 })).values.bar_px, 3, "bar_px rounded")
    eq(Settings.load(memory_store({ shadow = 0 / 0 })).values.shadow, 0.8, "nan shadow falls back")

    -- the menu path
    local s = Settings.load(memory_store(nil))
    eq(s:set("style", "panel"), true, "panel"); eq(s.values.style, "panel", "set")
    eq(s:set("style", "frameless"), true, "frameless again")
    eq(s:set("style", "Panel"), false, "the values are exact"); eq(s.values.style, "frameless", "unchanged")
    eq(s:set("halo", true), true, "halo"); eq(s:set("outline", false), true, "outline")
    eq(s:set("bar_px", 5), true, "bar_px"); eq(s:set("shadow", 0.25), true, "shadow")
    eq(s:set("halo", 1), false, "a number is not a boolean")
end)

test("0.2 defaults", function()
    local store = memory_store(nil)
    local v = Settings.load(store).values
    for _, k in ipairs({
        "live_damage", "live_taken", "live_heal", "live_other",
        "summary_enemies", "summary_damage", "summary_armor", "summary_heal", "summary_allies", "summary_other",
        "journal",
    }) do
        eq(v[k], true, k .. " is on")
    end
    eq(v.show_allies, true, "show_allies stays on")
    eq(v.journal_key, 0x76, "the journal key is F7")
    eq(math.type(v.journal_key), "integer", "a whole code")
    eq(v.history_file, false, "history.json is off")
    eq(v.history_size, 10, "history_size stays 10")
    for _, k in ipairs(KEYS) do
        eq(v[k], Settings.DEFAULTS[k], "DEFAULTS." .. k)
    end
    eq(#store.writes, 0, "loading does not write")

    -- the switches come back from the file; a wrong type falls back to the default
    local f = Settings.load(memory_store({
        live_damage = false, summary_armor = false, journal = false, history_file = true, live_heal = 0, summary_other = "no",
    })).values
    eq(f.live_damage, false, "live_damage from the file")
    eq(f.summary_armor, false, "summary_armor from the file")
    eq(f.journal, false, "journal from the file")
    eq(f.history_file, true, "history_file from the file")
    eq(f.live_heal, true, "a number is no switch")
    eq(f.summary_other, true, "a string is no switch")
    local s = Settings.load(memory_store(nil))
    eq(s:set("live_taken", false), true, "a switch is set")
    eq(s:set("journal", 1), false, "a number is not a boolean")
    eq(s.values.live_taken, false, "live_taken off")
    eq(s.values.journal, true, "journal unchanged after a refusal")
end)

test("enemy_hp_numbers: all by default, one of six values, anything else refused", function()
    local values = { "off", "current", "current_max", "percent", "current_percent", "all" }
    local store = memory_store(nil)
    local s = Settings.load(store)
    eq(Settings.DEFAULTS.enemy_hp_numbers, "all", "the default")
    eq(s.values.enemy_hp_numbers, "all", "loaded without a file")
    eq(Settings.LIMITS.enemy_hp_numbers, nil, "a choice, no range")
    for _, value in ipairs(values) do
        eq(s:set("enemy_hp_numbers", value), true, value .. " accepted")
        eq(s.values.enemy_hp_numbers, value, value .. " kept")
        eq(Settings.load(memory_store({ enemy_hp_numbers = value })).values.enemy_hp_numbers, value, value .. " loads")
    end
    for _, wrong in ipairs({ "max", "ALL", "", 1, true }) do
        eq(s:set("enemy_hp_numbers", wrong), false, tostring(wrong) .. " refused")
        eq(Settings.load(memory_store({ enemy_hp_numbers = wrong })).values.enemy_hp_numbers, "all",
            tostring(wrong) .. " in the file falls back")
    end
    eq(s.values.enemy_hp_numbers, "all", "the last good value stays")
end)

test("boss_hp_numbers: all by default, the same six values as the numbers over enemies, set apart from them", function()
    local values = { "off", "current", "current_max", "percent", "current_percent", "all" }
    local s = Settings.load(memory_store(nil))
    eq(Settings.DEFAULTS.boss_hp_numbers, "all", "the default")
    eq(s.values.boss_hp_numbers, "all", "loaded without a file")
    eq(Settings.LIMITS.boss_hp_numbers, nil, "a choice, no range")
    for _, value in ipairs(values) do
        eq(s:set("boss_hp_numbers", value), true, value .. " accepted")
        eq(s.values.boss_hp_numbers, value, value .. " kept")
        eq(s.values.enemy_hp_numbers, "all", value .. ": the numbers over enemies keep theirs")
        eq(Settings.load(memory_store({ boss_hp_numbers = value })).values.boss_hp_numbers, value, value .. " loads")
    end
    for _, wrong in ipairs({ "max", "ALL", "", 1, true }) do
        eq(s:set("boss_hp_numbers", wrong), false, tostring(wrong) .. " refused")
        eq(Settings.load(memory_store({ boss_hp_numbers = wrong })).values.boss_hp_numbers, "all",
            tostring(wrong) .. " in the file falls back")
    end
    eq(s.values.boss_hp_numbers, "all", "the last good value stays")
    s:set("enemy_hp_numbers", "off")
    eq(s.values.boss_hp_numbers, "all", "the numbers over enemies off: the boss's stay")
end)

test("buildup_bars: on by default, a switch", function()
    eq(Settings.DEFAULTS.buildup_bars, true, "the default")
    local s = Settings.load(memory_store(nil))
    eq(s.values.buildup_bars, true, "loaded without a file")
    eq(Settings.LIMITS.buildup_bars, nil, "no range")
    eq(s:set("buildup_bars", false), true, "off"); eq(s.values.buildup_bars, false, "kept")
    eq(s:set("buildup_bars", "no"), false, "a text refused")
    eq(Settings.load(memory_store({ buildup_bars = false })).values.buildup_bars, false, "off loads")
    eq(Settings.load(memory_store({ buildup_bars = 1 })).values.buildup_bars, true, "a number in the file falls back")
end)

test("player_numbers: on by default, a switch", function()
    eq(Settings.DEFAULTS.player_numbers, true, "the default")
    local s = Settings.load(memory_store(nil))
    eq(s.values.player_numbers, true, "loaded without a file")
    eq(Settings.LIMITS.player_numbers, nil, "no range")
    eq(s:set("player_numbers", false), true, "off"); eq(s.values.player_numbers, false, "kept")
    eq(s:set("player_numbers", "no"), false, "a text refused")
    eq(Settings.load(memory_store({ player_numbers = false })).values.player_numbers, false, "off loads")
    eq(Settings.load(memory_store({ player_numbers = 1 })).values.player_numbers, true,
        "a number in the file falls back")
end)

test("enemy_hp_size: 1 by default, a factor from 0.5 to 3, clamped", function()
    local function load(t) return Settings.load(memory_store(t)).values.enemy_hp_size end
    eq(Settings.DEFAULTS.enemy_hp_size, 1.0, "the default")
    eq(load(nil), 1.0, "loaded without a file")
    local L = Settings.LIMITS.enemy_hp_size
    near(L.min, 0.5, 1e-12, "min 0.5"); near(L.max, 3, 1e-12, "max 3")
    eq(L.integer, nil, "not a whole number"); eq(L.code, nil, "a quantity")
    near(load({ enemy_hp_size = 0.1 }), 0.5, 1e-12, "below: the least")
    near(load({ enemy_hp_size = 7 }), 3, 1e-12, "above: the most")
    near(load({ enemy_hp_size = 1.5 }), 1.5, 1e-12, "inside: kept")
    eq(load({ enemy_hp_size = "2" }), 1.0, "a text falls back")
    eq(load({ enemy_hp_size = 0 / 0 }), 1.0, "nan falls back")
    local s = Settings.load(memory_store(nil))
    eq(s:set("enemy_hp_size", 2.5), true, "set"); near(s.values.enemy_hp_size, 2.5, 1e-12, "kept")
    eq(s:set("enemy_hp_size", 9), true, "clamped, not refused"); near(s.values.enemy_hp_size, 3, 1e-12, "to 3")
    eq(s:set("enemy_hp_size", true), false, "a switch value refused")
    near(s.values.enemy_hp_size, 3, 1e-12, "the last good value stays")
end)

test("damage numbers: on, rising, 100 % by default; the style one of two, the size 0.5 to 3", function()
    local function load(t) return Settings.load(memory_store(t)).values end
    local D = Settings.DEFAULTS
    eq(D.damage_numbers, true, "on by default"); eq(load(nil).damage_numbers, true, "loaded without a file")
    eq(D.damage_numbers_style, "rise", "rise by default"); eq(load(nil).damage_numbers_style, "rise", "loaded")
    eq(D.damage_numbers_size, 1.0, "100 % by default"); eq(load(nil).damage_numbers_size, 1.0, "loaded")
    eq(load({ damage_numbers = false }).damage_numbers, false, "off kept")
    eq(load({ damage_numbers = "no" }).damage_numbers, true, "a text falls back")
    eq(Settings.LIMITS.damage_numbers_style, nil, "a choice, no range")
    for _, style in ipairs({ "rise", "plates" }) do
        eq(load({ damage_numbers_style = style }).damage_numbers_style, style, style .. " loads")
    end
    local s = Settings.load(memory_store(nil))
    eq(s:set("damage_numbers_style", "plates"), true, "plates accepted")
    for _, wrong in ipairs({ "Rise", "hitsplat", "", 1, true }) do
        eq(s:set("damage_numbers_style", wrong), false, tostring(wrong) .. " refused")
        eq(load({ damage_numbers_style = wrong }).damage_numbers_style, "rise", tostring(wrong) .. " falls back")
    end
    eq(s.values.damage_numbers_style, "plates", "the last good value stays")
    local L = Settings.LIMITS.damage_numbers_size
    near(L.min, 0.5, 1e-12, "min 0.5"); near(L.max, 3, 1e-12, "max 3")
    eq(L.integer, nil, "not a whole number"); eq(L.code, nil, "a quantity")
    near(load({ damage_numbers_size = 0.1 }).damage_numbers_size, 0.5, 1e-12, "below: the least")
    near(load({ damage_numbers_size = 7 }).damage_numbers_size, 3, 1e-12, "above: the most")
    near(load({ damage_numbers_size = 1.7 }).damage_numbers_size, 1.7, 1e-12, "inside: kept")
    eq(load({ damage_numbers_size = 0 / 0 }).damage_numbers_size, 1.0, "nan falls back")
end)

test("the enemy plate: on, 100 % by default; the size a factor from 0.5 to 3, clamped", function()
    local function load(t) return Settings.load(memory_store(t)).values end
    local D = Settings.DEFAULTS
    eq(D.enemy_plate, true, "on by default"); eq(load(nil).enemy_plate, true, "loaded without a file")
    eq(load({ enemy_plate = false }).enemy_plate, false, "off kept")
    eq(load({ enemy_plate = "no" }).enemy_plate, true, "a text falls back")
    eq(Settings.LIMITS.enemy_plate, nil, "a switch, no range")
    eq(D.enemy_plate_size, 1.0, "100 % by default"); eq(load(nil).enemy_plate_size, 1.0, "loaded")
    local L = Settings.LIMITS.enemy_plate_size
    near(L.min, 0.5, 1e-12, "min 0.5"); near(L.max, 3, 1e-12, "max 3")
    eq(L.integer, nil, "not a whole number"); eq(L.code, nil, "a quantity")
    near(load({ enemy_plate_size = 0.1 }).enemy_plate_size, 0.5, 1e-12, "below: the least")
    near(load({ enemy_plate_size = 7 }).enemy_plate_size, 3, 1e-12, "above: the most")
    near(load({ enemy_plate_size = 1.7 }).enemy_plate_size, 1.7, 1e-12, "inside: kept")
    eq(load({ enemy_plate_size = "2" }).enemy_plate_size, 1.0, "a text falls back")
    eq(load({ enemy_plate_size = 0 / 0 }).enemy_plate_size, 1.0, "nan falls back")
    local s = Settings.load(memory_store(nil))
    eq(s:set("enemy_plate", false), true, "switched off"); eq(s.values.enemy_plate, false, "off")
    eq(s:set("enemy_plate", 0), false, "a number is not a switch")
    eq(s:set("enemy_plate_size", 2.5), true, "set"); near(s.values.enemy_plate_size, 2.5, 1e-12, "kept")
    eq(s:set("enemy_plate_size", 9), true, "clamped, not refused"); near(s.values.enemy_plate_size, 3, 1e-12, "to 3")
    eq(s.values.enemy_hp_size, 1.0, "the HP numbers keep their own size")
end)

test("the hidden-stats panel: on, 100 % by default; the size a factor from 0.5 to 3, clamped", function()
    local function load(t) return Settings.load(memory_store(t)).values end
    local D = Settings.DEFAULTS
    eq(D.hidden_stats, true, "on by default"); eq(load(nil).hidden_stats, true, "loaded without a file")
    eq(load({ hidden_stats = false }).hidden_stats, false, "off kept")
    eq(load({ hidden_stats = "no" }).hidden_stats, true, "a text falls back")
    eq(Settings.LIMITS.hidden_stats, nil, "a switch, no range")
    eq(D.hidden_stats_size, 1.0, "100 % by default"); eq(load(nil).hidden_stats_size, 1.0, "loaded")
    local L = Settings.LIMITS.hidden_stats_size
    near(L.min, 0.5, 1e-12, "min 0.5"); near(L.max, 3, 1e-12, "max 3")
    eq(L.integer, nil, "not a whole number"); eq(L.code, nil, "a quantity")
    near(load({ hidden_stats_size = 0.1 }).hidden_stats_size, 0.5, 1e-12, "below: the least")
    near(load({ hidden_stats_size = 7 }).hidden_stats_size, 3, 1e-12, "above: the most")
    near(load({ hidden_stats_size = 1.7 }).hidden_stats_size, 1.7, 1e-12, "inside: kept")
    eq(load({ hidden_stats_size = "2" }).hidden_stats_size, 1.0, "a text falls back")
    eq(load({ hidden_stats_size = 0 / 0 }).hidden_stats_size, 1.0, "nan falls back")
    local s = Settings.load(memory_store(nil))
    eq(s:set("hidden_stats", false), true, "switched off"); eq(s.values.hidden_stats, false, "off")
    eq(s:set("hidden_stats", 0), false, "a number is not a switch")
    eq(s:set("hidden_stats_size", 2.5), true, "set"); near(s.values.hidden_stats_size, 2.5, 1e-12, "kept")
    eq(s:set("hidden_stats_size", 9), true, "clamped, not refused"); near(s.values.hidden_stats_size, 3, 1e-12, "to 3")
    eq(s:set("hidden_stats_size", -1), true, "clamped"); near(s.values.hidden_stats_size, 0.5, 1e-12, "to 0.5")
    eq(s.values.enemy_plate_size, 1.0, "the plate keeps its own size")
end)

test("history_size clamps to 32", function()
    eq(Settings.load(memory_store({ history_size = 50 })).values.history_size, 32, "a saved 50")
    eq(Settings.load(memory_store({ history_size = 33 })).values.history_size, 32, "a saved 33")
    eq(Settings.load(memory_store({ history_size = 32 })).values.history_size, 32, "32 stays")
    eq(Settings.load(memory_store({ history_size = 1 })).values.history_size, 1, "1 stays")
    local s = Settings.load(memory_store(nil))
    eq(s:set("history_size", 40), true, "a value over the limit is accepted")
    eq(s.values.history_size, 32, "and clamped")
    eq(s:set("history_size", 0), true, "zero is accepted")
    eq(s.values.history_size, 1, "and clamped up")
    eq(Settings.LIMITS.history_size.max, 32, "the menu's slider ends at 32")
end)

test("summary_allies follows a saved show_allies", function()
    local function load(t) return Settings.load(memory_store(t)).values end
    eq(load({ show_allies = false }).summary_allies, false, "a saved show_allies off")
    eq(load({ show_allies = false }).show_allies, false, "and show_allies itself stays off")
    eq(load({ show_allies = true }).summary_allies, true, "a saved show_allies on")
    eq(load({ show_allies = false, summary_allies = true }).summary_allies, true, "the file's own summary_allies wins")
    eq(load({ show_allies = true, summary_allies = false }).summary_allies, false, "and the other way")
    eq(load({}).summary_allies, true, "neither: the default")
    eq(load(nil).summary_allies, true, "no file: the default")
    eq(load({ show_allies = "no" }).summary_allies, true, "a show_allies of the wrong type does not count")
    eq(load({ show_allies = false, summary_allies = "yes" }).summary_allies, false, "a broken summary_allies is as good as none")

    -- only the load follows: later the two are independent
    local s = Settings.load(memory_store({ show_allies = false }))
    eq(s:set("show_allies", true), true, "show_allies on again")
    eq(s.values.summary_allies, false, "summary_allies does not follow a later change")
    eq(s:flush(), true, "saved")
    eq(Settings.load(memory_store(s.store.data)).values.summary_allies, false, "the file now holds its own summary_allies")
end)

test("the two keys never match", function()
    local store = memory_store({ toggle_key = 0x75 })
    local s = Settings.load(store)
    eq(s.values.journal_key, 0x76, "journal on F7")
    eq(s:set("journal_key", 0x75), false, "the journal key may not be the toggle key")
    eq(s.values.journal_key, 0x76, "journal_key unchanged")
    eq(s:set("toggle_key", 0x76), false, "the toggle key may not be the journal key")
    eq(s.values.toggle_key, 0x75, "toggle_key unchanged")
    eq(s:set("toggle_key", 118.0), false, "a whole float is the same code")
    eq(s:flush(), false, "refusals leave nothing to save")
    eq(#store.writes, 0, "and nothing written")

    -- the same value again is not a clash with the other key
    eq(s:set("toggle_key", 0x75), true, "toggle_key to itself")
    eq(s:set("journal_key", 0x76), true, "journal_key to itself")

    -- a code that is free is taken; the old one is free for the other key at once
    eq(s:set("toggle_key", 0x78), true, "a free code")
    eq(s:set("journal_key", 0x75), true, "the old toggle key is free now")
    eq(s.values.journal_key, 0x75, "journal_key on F6")
    eq(s:set("toggle_key", 0x75), false, "and now the journal's")
    eq(s:flush(), true, "the accepted changes are saved")
    eq(store.data.toggle_key, 0x78, "toggle_key saved")
    eq(store.data.journal_key, 0x75, "journal_key saved")

    -- a refusal is not a rejection of the other rules: a bad code is still false, a clash is false too
    eq(s:set("journal_key", 0), false, "0 refused")
    eq(s:set("journal_key", 0x78), false, "the toggle key refused")

    -- a file that already has both on one code is mended at load: the journal moves
    local w = Settings.load(memory_store({ toggle_key = 0x78, journal_key = 0x78 })).values
    eq(w.toggle_key, 0x78, "the toggle key stays")
    eq(w.journal_key, 0x76, "the journal key is the first of F7..F12 that differs")
end)

test("a saved toggle key of F7 moves the journal key", function()
    local function load(t) return Settings.load(memory_store(t)).values end
    local v = load({ toggle_key = 0x76 })
    eq(v.toggle_key, 0x76, "a 0.1 file keeps its toggle key")
    eq(v.journal_key, 0x77, "and the journal takes F8")
    eq(load({ toggle_key = 0x76, journal_key = 0x76 }).journal_key, 0x77, "a saved clash moves the journal key too")
    eq(load({ toggle_key = 0x76, journal_key = 0x7B }).journal_key, 0x7B, "a journal key that differs stays")
    eq(load({ toggle_key = 0x77 }).journal_key, 0x76, "F8 as the toggle key leaves F7 to the journal")
    eq(load({ toggle_key = 0x75 }).journal_key, 0x76, "F6 leaves F7 to the journal")
    eq(load({ toggle_key = 0x76, journal_key = 0 }).journal_key, 0x77, "a broken journal key falls back to F7, then moves")
    eq(math.type(load({ toggle_key = 0x76 }).journal_key), "integer", "a whole code")

    -- loading changes nothing in the file: the move is saved with the next change
    local store = memory_store({ toggle_key = 0x76 })
    local s = Settings.load(store)
    eq(#store.writes, 0, "loading does not write")
    eq(s:flush(), false, "and leaves nothing dirty")
    eq(s:set("scale", 1.5), true, "a later change")
    eq(s:flush(), true, "saved")
    eq(store.data.journal_key, 0x77, "with the journal key that works")
end)

test("journal_key code rules", function()
    local function key_from_file(value)
        return Settings.load(memory_store({ journal_key = value })).values.journal_key
    end
    eq(key_from_file(0), 0x76, "0 falls back, not clamped to 1")
    eq(key_from_file(255), 0x76, "255 falls back, not clamped to 254")
    eq(key_from_file(-1), 0x76, "negative falls back")
    eq(key_from_file(1000), 0x76, "1000 falls back")
    eq(key_from_file(117.5), 0x76, "a fraction is not a key code")
    eq(key_from_file(0 / 0), 0x76, "nan falls back")
    eq(key_from_file("119"), 0x76, "a string is not a key code")
    eq(key_from_file(0x78), 0x78, "F9 is taken")
    eq(key_from_file(1), 1, "lowest code")
    eq(key_from_file(254), 254, "highest code")
    eq(key_from_file(121.0), 121, "a whole float is accepted")
    eq(math.type(key_from_file(121.0)), "integer", "stored as an integer")

    local store = memory_store(nil)
    local s = Settings.load(store)
    for _, bad in ipairs({ 0, -1, 255, 1000, 117.5, 0 / 0, math.huge, "119", false }) do
        eq(s:set("journal_key", bad), false, "set refuses " .. tostring(bad))
        eq(s.values.journal_key, 0x76, "journal_key unchanged after " .. tostring(bad))
    end
    eq(s:flush(), false, "refusals leave nothing to save")
    eq(s:set("journal_key", 0x78), true, "F9 accepted")
    eq(s.values.journal_key, 0x78, "journal_key changed")
    eq(s:flush(), true, "saved")
    eq(store.data.journal_key, 0x78, "journal_key written")
end)

test("the settings window key: F8 by default, a code like the other two", function()
    local store = memory_store(nil)
    local v = Settings.load(store).values
    eq(Settings.DEFAULTS.settings_key, 0x77, "the default is F8")
    eq(v.settings_key, 0x77, "loaded without a file: F8")
    eq(math.type(v.settings_key), "integer", "a whole code")
    eq(Settings.load(memory_store({ settings_key = 0x7A })).values.settings_key, 0x7A, "F11 from the file")
    for _, bad in ipairs({ 0, 255, 117.5, "120", 0 / 0 }) do
        eq(Settings.load(memory_store({ settings_key = bad })).values.settings_key, 0x77, "falls back from " .. tostring(bad))
    end
    local s = Settings.load(store)
    for _, bad in ipairs({ 0, -1, 255, 117.5, 0 / 0, "120", true }) do
        eq(s:set("settings_key", bad), false, "set refuses " .. tostring(bad))
    end
    eq(s.values.settings_key, 0x77, "unchanged after the refusals")
    eq(s:set("settings_key", 0x7A), true, "F11 accepted")
    eq(s:flush(), true, "saved")
    eq(store.data.settings_key, 0x7A, "written")
end)

test("the three keys never match", function()
    local store = memory_store(nil)
    local s = Settings.load(store)
    local v = s.values
    eq(v.toggle_key ~= v.journal_key and v.journal_key ~= v.settings_key and v.toggle_key ~= v.settings_key, true,
        "the defaults differ")
    -- each refuses the code either of the others has
    eq(s:set("settings_key", 0x75), false, "not the toggle key")
    eq(s:set("settings_key", 0x76), false, "not the journal key")
    eq(s:set("toggle_key", 0x77), false, "the toggle key is not the settings key")
    eq(s:set("journal_key", 0x77), false, "nor the journal key")
    eq(v.toggle_key, 0x75, "toggle_key unchanged"); eq(v.journal_key, 0x76, "journal_key unchanged")
    eq(v.settings_key, 0x77, "settings_key unchanged")
    eq(s:flush(), false, "refusals leave nothing to save")
    -- to itself is no clash; a freed code is free for the others at once
    eq(s:set("settings_key", 0x77), true, "settings_key to itself")
    eq(s:set("settings_key", 0x7A), true, "a free code")
    eq(s:set("toggle_key", 0x77), true, "F8 is free now")
    eq(s:set("settings_key", 0x77), false, "and taken again")

    -- a file with clashes is mended at load, without writing: the toggle key stays, the journal key and then the
    -- settings key move to the first of F7..F12 that no other key has
    local function load(t) return Settings.load(memory_store(t)).values end
    local w = load({ toggle_key = 0x77 })
    eq(w.toggle_key, 0x77, "a toggle key of F8 stays"); eq(w.journal_key, 0x76, "the journal keeps F7")
    eq(w.settings_key, 0x78, "the settings window moves to F9")
    w = load({ toggle_key = 0x76 })
    eq(w.journal_key, 0x77, "a toggle key of F7: the journal takes F8")
    eq(w.settings_key, 0x78, "and the settings window F9")
    w = load({ journal_key = 0x77 })
    eq(w.journal_key, 0x77, "a journal key of F8 stays"); eq(w.settings_key, 0x76, "the settings window takes the free F7")
    w = load({ toggle_key = 0x78, journal_key = 0x78, settings_key = 0x78 })
    eq(w.toggle_key, 0x78, "all on F9: the toggle key stays"); eq(w.journal_key, 0x76, "the journal takes F7")
    eq(w.settings_key, 0x77, "the settings window F8")
    w = load({ settings_key = 0x75 })
    eq(w.settings_key, 0x77, "the toggle key's F6: the settings window takes F8")
    w = load({ toggle_key = 0x76, journal_key = 0x77, settings_key = 0x77 })
    eq(w.journal_key, 0x77, "a journal key that differs stays"); eq(w.settings_key, 0x78, "the settings key moves")
    local st = memory_store({ toggle_key = 0x77 })
    local loaded = Settings.load(st)
    eq(#st.writes, 0, "loading does not write"); eq(loaded:flush(), false, "and leaves nothing dirty")
end)

T.finish()
