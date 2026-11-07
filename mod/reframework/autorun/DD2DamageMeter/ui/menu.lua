-- The mod's part of REFramework's own window, and the key capture of the mod's key settings. The settings themselves
-- are in the mod's own window (ui/settings_window.lua); REFramework's window keeps a collapsing header with a line
-- that says so and names its key, a button that opens it, and the settings key's button (a way back when that key
-- clashes with something). Called from re.on_draw_ui; a change goes through settings:set, which validates it (the
-- caller writes the file with settings:flush). Labels from i18n.
--
-- Menu.draw(settings, i18n) -> actions, err
--   actions = { changed = { key... }, open_settings = boolean }   the settings changed this frame; the open button
--   err     = nil, or the message of an error caught while drawing; draw never raises
-- Menu.key_name(vk) -> "F7", "PageUp", ... the name of a virtual-key code
-- Menu.TITLE      the mod's name as players see it: this header, the settings window's title and the line REFramework's
--                 log gets at a load. Files, folders, data paths, window ids and require paths keep DD2DamageMeter.
-- The key capture: one wait at a time for the next key press, for one of the key settings, started by the settings
-- key's button here ("menu") or by the settings window ("window"). Whoever started it polls it: Menu.draw a wait of
-- the menu's (and drops it when the menu was closed or the header folded), the settings window its own.
-- Menu.capture(key, by)      starts waiting for setting `key` (a wait already running ends); keys held now count
--                            only once let go
-- Menu.cancel()              ends the wait
-- Menu.capturing() -> true while a wait runs; Menu.waiting_for() -> key, by (nil without a wait)
-- Menu.poll(settings) -> key|nil   one look at the keys: the first that went down and was not held becomes the
--                            setting's key (returned when settings:set took it); Esc gives up; a key the settings
--                            refuse (another key setting's) is not taken and the wait goes on
local Menu = {}

local TITLE = "Hidden Numbers"
Menu.TITLE = TITLE
-- REFramework draws all scripts' menus in one window without an ID scope, so every widget of
-- this mod carries "##dd2dm_<name>": the visible label stays, the ID cannot clash with another
-- script's "Scale" or "Language".
local ID_PREFIX = "##dd2dm_"

-- Windows virtual-key codes. The keys that can be chosen start at Backspace (8): the codes
-- below it are the mouse buttons and Cancel.
local VK_FIRST, VK_LAST = 8, 254
local VK_ESCAPE = 0x1B
local KEY_NAMES = {
    [0x09] = "Tab", [0x0D] = "Enter", [0x20] = "Space", [0x21] = "PageUp", [0x22] = "PageDown",
    [0x23] = "End", [0x24] = "Home", [0x2D] = "Insert", [0x2E] = "Delete",
}

-- Menu.draw runs only while the REFramework menu is open. A pause this long between two draws
-- means it was closed: a wait of the menu's must not go on through that (opening the menu again
-- with Insert would bind Insert).
local CAPTURE_GAP = 0.3 -- seconds
Menu.clock = os.clock   -- tests replace it

-- nil, or { key = the setting that waits for a key, by = "menu"|"window", held = the keys to ignore }.
local capture
local last_draw

function Menu.reset()
    capture = nil
    last_draw = nil
end

function Menu.capturing()
    return capture ~= nil
end

function Menu.waiting_for()
    if capture == nil then return nil end
    return capture.key, capture.by
end

function Menu.key_name(vk)
    if vk >= 0x70 and vk <= 0x87 then return "F" .. (vk - 0x6F) end
    if (vk >= 0x30 and vk <= 0x39) or (vk >= 0x41 and vk <= 0x5A) then return string.char(vk) end
    return KEY_NAMES[vk] or string.format("0x%02X", vk)
end

local function keys_down()
    local down = {}
    for vk = VK_FIRST, VK_LAST do
        if reframework:is_key_down(vk) then down[vk] = true end
    end
    return down
end

function Menu.capture(key, by)
    capture = { key = key, by = by, held = keys_down() }
end

function Menu.cancel()
    capture = nil
end

function Menu.poll(settings)
    if capture == nil then return nil end
    for vk = VK_FIRST, VK_LAST do
        if not reframework:is_key_down(vk) then
            capture.held[vk] = nil
        elseif not capture.held[vk] then
            local waiting = capture
            capture = nil
            if vk == VK_ESCAPE then return nil end
            if settings:set(waiting.key, vk) ~= false then return waiting.key end
            capture = waiting
            capture.held[vk] = true
            return nil
        end
    end
    return nil
end

local function menu_wait()
    return capture ~= nil and capture.by == "menu"
end

-- A button showing the key of setting `key`; a click starts (or gives up) waiting for the next key press, and moves
-- the wait here from wherever it was.
local function key_control(settings, actions, key, label, i18n)
    local waiting = capture ~= nil and capture.key == key
    local shown = waiting and i18n.t("press_a_key") or Menu.key_name(settings.values[key])
    local clicked = imgui.button(shown .. ID_PREFIX .. key)
    imgui.same_line()
    imgui.text(label)
    if clicked then
        if waiting then Menu.cancel() else Menu.capture(key, "menu") end
    elseif waiting and menu_wait() then
        local changed = Menu.poll(settings)
        if changed then actions.changed[#actions.changed + 1] = changed end
    end
end

local function draw_controls(settings, actions, i18n)
    local now = Menu.clock()
    if menu_wait() and last_draw and now - last_draw > CAPTURE_GAP then capture = nil end
    last_draw = now
    if not imgui.collapsing_header(TITLE .. ID_PREFIX .. "header") then
        if menu_wait() then capture = nil end -- a folded header draws no button to wait with
        return
    end
    imgui.text(i18n.t("settings_in_window", Menu.key_name(settings.values.settings_key)))
    if imgui.button(i18n.t("open_settings") .. ID_PREFIX .. "open_settings") then actions.open_settings = true end
    key_control(settings, actions, "settings_key", i18n.t("menu_settings_key"), i18n)
end

function Menu.draw(settings, i18n)
    local actions = { changed = {}, open_settings = false }
    local ok, err = pcall(draw_controls, settings, actions, i18n)
    return actions, (not ok) and tostring(err) or nil
end

return Menu
