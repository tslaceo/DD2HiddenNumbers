package.path = "mod/reframework/autorun/?.lua;tests/?.lua;" .. package.path

local T = require("testlib")
local test, eq = T.test, T.eq
local ui = require("stubs/ui").install()
local i18n = require("DD2DamageMeter/i18n")
local Settings = require("DD2DamageMeter/settings")
local Menu = require("DD2DamageMeter/ui/menu")

local WIDGETS = { slider_int = true, slider_float = true, drag_int = true, checkbox = true, combo = true }
local F6, F7, F8, F9 = 0x75, 0x76, 0x77, 0x78

-- The menu's clock: every drawn frame is 16 ms later; a test moves `now` itself to skip time.
local now = 0
Menu.clock = function() return now end

local function make_store(data)
    local store = { data = data, writes = {} }
    function store.read() return store.data end
    function store.write(t)
        store.data = t
        store.writes[#store.writes + 1] = t
    end
    return store
end

local function fresh(lang)
    ui.reset()
    Menu.reset()
    now = 0
    i18n.set(lang or "en")
    local store = make_store(nil)
    return Settings.load(store), store
end

-- A settings stand-in that only records set() calls.
local function spy()
    local s = { values = {}, calls = {} }
    for k, v in pairs(Settings.DEFAULTS) do s.values[k] = v end
    function s.set(self, key, value)
        s.calls[#s.calls + 1] = { self = self, key = key, value = value }
        return true
    end
    return s
end

-- Draws one frame; returns what Menu.draw returns.
local function draw(settings)
    ui.clear_calls()
    now = now + 0.016
    return Menu.draw(settings, i18n)
end

-- The key button whose id is `##dd2dm_<key>`.
local function button_of(key)
    for _, c in ipairs(ui.calls_of("button")) do
        if c.label:sub(-#("##dd2dm_" .. key)) == "##dd2dm_" .. key then return c end
    end
    return nil
end

local function key_button()
    return button_of("settings_key")
end

local PROMPT = function() return i18n.t("press_a_key") .. "##dd2dm_settings_key" end

test("a closed header draws nothing else", function()
    local s = fresh()
    ui.header_open = false
    draw(s)
    eq(#ui.calls, 1, "only the header")
    eq(ui.calls[1].fn, "collapsing_header", "the header")
    eq(ui.calls[1][1], "Hidden Numbers##dd2dm_header", "its title and unique id")
end)

test("the menu holds only the line, the open button and the settings key button", function()
    for _, lang in ipairs({ "en", "ru" }) do
        local s = fresh(lang)
        local actions, err = draw(s)
        eq(err, nil, "no error in " .. lang)
        local order = {}
        for _, c in ipairs(ui.calls) do
            eq(WIDGETS[c.fn], nil, "no other control in " .. lang .. ": " .. c.fn)
            if c.fn ~= "same_line" then order[#order + 1] = c.fn .. ":" .. tostring(c[1]) end
        end
        eq(table.concat(order, " | "), table.concat({
            "collapsing_header:Hidden Numbers##dd2dm_header",
            "text:" .. i18n.t("settings_in_window", "F8"),
            "button:" .. i18n.t("open_settings") .. "##dd2dm_open_settings",
            "button:F8##dd2dm_settings_key",
            "text:" .. i18n.t("menu_settings_key"),
        }, " | "), "what is drawn in " .. lang)
        eq(actions.open_settings, false, "nothing asked")
        eq(#actions.changed, 0, "nothing changed")
    end
    i18n.set("ru")
    eq(i18n.t("settings_in_window", "F8"), "Настройки — в окне мода, клавиша F8", "the line in Russian")
    -- the line names the key the settings window has
    local s = fresh("ru")
    s:set("settings_key", F9)
    draw(s)
    eq(ui.has_text("Настройки — в окне мода, клавиша F9"), true, "with the key set")
    eq(key_button().label, "F9##dd2dm_settings_key", "the button shows it too")
end)

test("the open button asks for the settings window", function()
    local s = fresh()
    ui.press("dd2dm_open_settings")
    local actions = draw(s)
    eq(actions.open_settings, true, "asked")
    actions = draw(s)
    eq(actions.open_settings, false, "once")
    ui.header_open = false
    ui.press("dd2dm_open_settings")
    actions = draw(s)
    eq(actions.open_settings, false, "a folded header has no button")
end)

test("the settings key shows its name and is set by pressing a key", function()
    local s = fresh()
    draw(s)
    eq(key_button().label, "F8##dd2dm_settings_key", "0x77 is F8")
    eq(Menu.capturing(), false, "not waiting for a key")

    ui.press("dd2dm_settings_key")
    draw(s)
    eq(Menu.capturing(), true, "waiting from the click on")
    eq(Menu.waiting_for(), "settings_key", "for the settings key")
    eq(select(2, Menu.waiting_for()), "menu", "polled by the menu")
    draw(s)
    eq(key_button().label, PROMPT(), "waiting for a key")
    eq(s.values.settings_key, F8, "unchanged while waiting")

    ui.keys_down[0x7A] = true
    local actions = draw(s)
    eq(s.values.settings_key, 0x7A, "F11 taken")
    eq(table.concat(actions.changed, ","), "settings_key", "reported as changed")
    eq(Menu.capturing(), false, "the wait is over")
    draw(s)
    eq(key_button().label, "F11##dd2dm_settings_key", "shows the new key")
    ui.keys_down[0x41] = true
    draw(s)
    eq(s.values.settings_key, 0x7A, "not capturing any more")

    -- the spy sees one set() call with the code
    local sp = spy()
    fresh()
    ui.press("dd2dm_settings_key")
    draw(sp)
    draw(sp)
    ui.keys_down[0x79] = true
    draw(sp)
    eq(#sp.calls, 1, "one call")
    eq(sp.calls[1].self, sp, "called as a method")
    eq(sp.calls[1].key, "settings_key", "settings_key")
    eq(sp.calls[1].value, 0x79, "the code of F10")
end)

test("key capture ignores the mouse, held keys and Esc", function()
    local s = fresh()
    ui.keys_down[0x0D] = true -- Enter was down when the button was clicked
    ui.press("dd2dm_settings_key")
    draw(s)
    ui.keys_down[0x01] = true -- left mouse button (the click itself)
    ui.keys_down[0x02] = true
    ui.keys_down[0x04] = true
    draw(s)
    eq(s.values.settings_key, F8, "mouse buttons and the held key are not taken")

    -- once released the held key can be chosen
    ui.keys_down[0x0D] = nil
    ui.keys_down[0x01], ui.keys_down[0x02], ui.keys_down[0x04] = nil, nil, nil
    draw(s)
    ui.keys_down[0x0D] = true
    draw(s)
    eq(s.values.settings_key, 0x0D, "Enter taken after being released")

    -- Esc cancels
    ui.keys_down = {}
    ui.press("dd2dm_settings_key")
    draw(s)
    draw(s)
    ui.keys_down[0x1B] = true
    local actions = draw(s)
    eq(s.values.settings_key, 0x0D, "Esc does not become the key")
    eq(#actions.changed, 0, "nothing changed")
    ui.keys_down = {}
    draw(s)
    eq(key_button().label ~= PROMPT(), true, "capture over")

    -- clicking the button again cancels too
    ui.press("dd2dm_settings_key")
    draw(s)
    ui.press("dd2dm_settings_key")
    draw(s)
    draw(s)
    eq(key_button().label ~= PROMPT(), true, "second click cancels")
end)

test("key names on the button", function()
    local s = fresh()
    local names = { [0x70] = "F1", [0x7B] = "F12", [0x41] = "A", [0x5A] = "Z", [0x30] = "0", [0x39] = "9",
        [0x20] = "Space", [0xE8] = "0xE8" }
    for vk, name in pairs(names) do
        s.values.settings_key = vk
        draw(s)
        eq(key_button().label, name .. "##dd2dm_settings_key", string.format("name of 0x%02X", vk))
    end
end)

test("a key capture does not survive the menu being closed", function()
    local s = fresh()
    draw(s)
    ui.press("dd2dm_settings_key")
    draw(s)
    draw(s)
    eq(key_button().label, PROMPT(), "waiting for a key")

    -- the REFramework menu is closed for a while (no frames drawn), then opened again with
    -- Insert, which is still down in the first frame
    now = now + 3
    ui.keys_down[0x2D] = true
    draw(s)
    eq(s.values.settings_key, F8, "Insert is not bound")
    eq(key_button().label, "F8##dd2dm_settings_key", "the capture is over")
    eq(Menu.capturing(), false, "nothing waits")
    draw(s)
    eq(s.values.settings_key, F8, "and stays over")

    -- frames that follow each other keep waiting
    ui.keys_down = {}
    ui.press("dd2dm_settings_key")
    draw(s)
    for _ = 1, 10 do draw(s) end
    eq(key_button().label, PROMPT(), "still waiting after ten frames")
    ui.keys_down[0x41] = true
    draw(s)
    eq(s.values.settings_key, 0x41, "a key pressed in time is taken")

    -- folding the mod's header away cancels it too
    ui.keys_down = {}
    ui.press("dd2dm_settings_key")
    draw(s)
    draw(s)
    eq(key_button().label, PROMPT(), "waiting again")
    ui.header_open = false
    draw(s)
    ui.header_open = true
    draw(s)
    eq(key_button().label ~= PROMPT(), true, "folded header cancelled the wait")

    -- and Menu.reset forgets a wait
    ui.press("dd2dm_settings_key")
    draw(s)
    eq(Menu.capturing(), true, "waiting")
    Menu.reset()
    eq(Menu.capturing(), false, "reset")
end)

test("a key another setting has is not taken", function()
    local s = fresh()
    draw(s)
    ui.press("dd2dm_settings_key")
    draw(s)
    draw(s)
    ui.keys_down[F6] = true
    local actions = draw(s)
    eq(s.values.settings_key, F8, "F6 (the toggle key) is not taken")
    eq(#actions.changed, 0, "and nothing is reported as changed")
    eq(Menu.capturing(), true, "the button keeps waiting for a key that can be used")
    actions = draw(s)
    eq(#actions.changed, 0, "a key held on is not tried again and again")
    ui.keys_down[F6] = nil
    ui.keys_down[F7] = true
    actions = draw(s)
    eq(s.values.settings_key, F8, "F7 (the journal key) is not taken either")
    eq(Menu.capturing(), true, "still waiting")
    ui.keys_down[F7] = nil
    ui.keys_down[F9] = true
    actions = draw(s)
    eq(s.values.settings_key, F9, "F9 is taken")
    eq(table.concat(actions.changed, ","), "settings_key", "reported")
    eq(Menu.capturing(), false, "the wait is over")
end)

test("a wait the settings window started: polled by it, not by the menu", function()
    local s = fresh()
    draw(s)
    ui.keys_down[0x0D] = true -- the Enter that started it
    Menu.capture("toggle_key", "window")
    eq(Menu.capturing(), true, "waiting")
    local key, by = Menu.waiting_for()
    eq(key, "toggle_key", "for the toggle key"); eq(by, "window", "polled by the window")
    -- the menu draws its button as usual and leaves the wait alone
    ui.keys_down[0x41] = true
    local actions = draw(s)
    eq(#actions.changed, 0, "the menu does not poll it")
    eq(s.values.toggle_key, F6, "nothing taken by the menu")
    eq(key_button().label, "F8##dd2dm_settings_key", "the settings key's button does not wait")
    now = now + 3
    draw(s)
    eq(Menu.capturing(), true, "a pause between menu frames does not end it")
    ui.header_open = false
    draw(s)
    ui.header_open = true
    eq(Menu.capturing(), true, "nor a folded header")

    -- Menu.poll: the next key that goes down and was not held; the held one only once let go
    ui.keys_down = { [0x0D] = true }
    eq(Menu.poll(s), nil, "the held Enter is not taken")
    ui.keys_down = {}
    eq(Menu.poll(s), nil, "nothing down")
    ui.keys_down = { [F8] = true }
    eq(Menu.poll(s), nil, "F8 (the settings key) is refused")
    eq(s.values.toggle_key, F6, "unchanged")
    eq(Menu.capturing(), true, "the wait goes on")
    eq(Menu.poll(s), nil, "a refused key held on is not tried again")
    ui.keys_down = { [0x0D] = true }
    eq(Menu.poll(s), "toggle_key", "Enter, let go and pressed again, is taken")
    eq(s.values.toggle_key, 0x0D, "the toggle key is Enter")
    eq(Menu.capturing(), false, "the wait is over")
    eq(Menu.poll(s), nil, "no wait, nothing polled")

    -- Esc gives up
    ui.keys_down = {}
    Menu.capture("journal_key", "window")
    ui.keys_down = { [0x1B] = true }
    eq(Menu.poll(s), nil, "Esc")
    eq(s.values.journal_key, F7, "the journal key stays")
    eq(Menu.capturing(), false, "the wait is over")

    -- one wait at a time: a click on the menu's button moves it there; Menu.cancel ends it
    ui.keys_down = {}
    Menu.capture("toggle_key", "window")
    ui.press("dd2dm_settings_key")
    draw(s)
    key, by = Menu.waiting_for()
    eq(key, "settings_key", "the menu's button waits now"); eq(by, "menu", "polled by the menu")
    Menu.capture("journal_key", "window")
    eq(Menu.waiting_for(), "journal_key", "and back to the window")
    draw(s)
    eq(key_button().label, "F8##dd2dm_settings_key", "the menu's button does not wait")
    Menu.cancel()
    eq(Menu.capturing(), false, "cancelled")
    eq(Menu.waiting_for(), nil, "nothing waits")
end)

test("Menu.draw never raises", function()
    local function safe(settings, text)
        local ok, actions, err = pcall(Menu.draw, settings, text)
        eq(ok, true, "no error escaped: " .. tostring(actions))
        eq(type(actions), "table", "actions come back anyway")
        return actions, err
    end

    -- settings:set raises while the menu waits for a key
    local boom = spy()
    boom.set = function() error("set exploded") end
    fresh()
    ui.press("dd2dm_settings_key")
    safe(boom, i18n)
    ui.keys_down[F9] = true
    local actions, err = safe(boom, i18n)
    eq(type(err), "string", "the error comes back as a string")
    eq(err:find("set exploded", 1, true) ~= nil, true, "with its message")

    -- no settings, no texts, a widget that raises
    ui.clear_calls()
    ui.keys_down = {}
    _, err = safe(nil, i18n)
    eq(type(err), "string", "no settings")
    _, err = safe(spy(), {})
    eq(type(err), "string", "no i18n")
    local button = imgui.button
    imgui.button = function() error("imgui exploded") end
    _, err = safe(spy(), i18n)
    imgui.button = button
    eq(err:find("imgui exploded", 1, true) ~= nil, true, "a failing widget")

    -- and it keeps working afterwards
    fresh()
    local s = Settings.load(make_store(nil))
    actions, err = draw(s)
    eq(err, nil, "a healthy frame has no error")
    eq(key_button() ~= nil, true, "and draws")
end)

test("key_name", function()
    local names = {
        [0x76] = "F7", [0x70] = "F1", [0x7B] = "F12", [0x87] = "F24", [0x21] = "PageUp", [0x22] = "PageDown",
        [0x41] = "A", [0x39] = "9", [0x20] = "Space", [0x2D] = "Insert", [0xE8] = "0xE8",
    }
    for vk, name in pairs(names) do
        eq(Menu.key_name(vk), name, string.format("name of 0x%02X", vk))
    end
end)

test("the menu's texts exist in both languages", function()
    for _, lang in ipairs({ "en", "ru" }) do
        i18n.set(lang)
        for _, key in ipairs({ "press_a_key", "settings_in_window", "open_settings", "menu_settings_key" }) do
            eq(i18n.t(key) ~= key, true, key .. " in " .. lang)
        end
    end
    i18n.set("en")
end)

T.finish()
