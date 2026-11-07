package.path = "mod/reframework/autorun/?.lua;tests/?.lua;" .. package.path

local T = require("testlib")
local test, eq = T.test, T.eq
local ui = require("stubs/ui").install()
local i18n = require("DD2DamageMeter/i18n")
local Settings = require("DD2DamageMeter/settings")
local SettingsView = require("DD2DamageMeter/settings_view")
local SettingsUI = require("DD2DamageMeter/ui/settings_window")
local Kit = require("DD2DamageMeter/ui/kit")
local Menu = require("DD2DamageMeter/ui/menu")

local C = Kit.COLORS
local WINDOW = "DD2DamageMeter settings"
-- ImGuiWindowFlags (ImGui 1.92.0) and ImGuiCond_Always.
local FLAGS = { 1, 2, 4, 8, 16, 32, 128, 256, 4096, 8192 } -- always on
local NO_MOUSE_INPUTS, NO_NAV, ALWAYS_AUTO_RESIZE, COND_ALWAYS = 512, 196608, 64, 1

-- At scale 1 and a 1920 × DISPLAY_H display, once measured: the meter at x 40 is 340 + 2 × 8 px wide, the window
-- 12 px to its right, 320 px wide (its widest row at the stub's 7 px a character, the key prompt beside «Настройки»,
-- takes 63 + 210 + 3 × 8 and the margins 2 × 10: 317, and 320 is the least). Its height: 6 + 32 above the bronze line
-- (1 px), 6, nine headings (24), the table's line of column names (16) and 37 rows (20; 35 with the panel: no halo,
-- no bars), 8, a thin line (1), 4, the help's lines (16; three: the longest help at 300 px), 4, three hint lines (16)
-- and 6 under them: 1136 px. Before it is measured: 360 px wide, the help two lines high. DISPLAY_H is 1200: on the
-- stub's 1080 (1048 px for the window) the rows page since the buildup bars' row (tested apart).
local DISPLAY_H = 1200
local function fixed_h(help_n, hint_n)
    return 6 + 32 + 1 + 6 + 8 + 1 + 4 + help_n * 16 + 4 + hint_n * 16 + 6
end
local BODY_H = 9 * 24 + 16 + 37 * 20
local CONTENT_H = fixed_h(3, 3) + BODY_H
local W = 320

local function make_settings(over)
    local saved = over or {}
    return Settings.load({ read = function() return saved end, write = function(t) saved = t end })
end

local function state(s, sel, waiting, col)
    return { model = SettingsView.build(s, i18n), sel = sel or 1, col = col or 1, waiting = waiting }
end

-- One frame; a drawing error fails the test, the stacks must balance.
local function draw(st, s)
    ui.clear_calls()
    local actions, err = SettingsUI.draw(st, s)
    if err then error("draw failed: " .. err, 2) end
    eq(ui.balanced(), true, "stacks balanced")
    return actions
end

-- The frames the measuring takes (the width, then the help's and the hint's lines at that width): after them the
-- window keeps its size. The calls kept are the last frame's.
local function settle(s, st)
    for _ = 1, 3 do draw(st or state(s), s) end
end

-- Fresh state and settings, the window measured in `lang` at their scale.
local function fresh(over, lang)
    ui.reset()
    ui.display = { x = 1920, y = DISPLAY_H }
    SettingsUI.reset()
    i18n.set(lang or "ru")
    local s = make_settings(over)
    settle(s)
    ui.clear_calls()
    return s
end

local function text_call(s)
    for _, c in ipairs(ui.calls) do
        if c.fn == "add_text" and c.text == s then return c end
    end
    return nil
end

-- A group's heading: drawn in the bands' gold.
local function heading_call(s)
    for _, c in ipairs(ui.calls) do
        if c.fn == "add_text" and c.text == s and c.col == C.block.damage.title then return c end
    end
    return nil
end

-- The texts drawn in `color`, in order.
local function texts_in(color)
    local list = {}
    for _, c in ipairs(ui.calls) do
        if c.fn == "add_text" and c.col == color then list[#list + 1] = c end
    end
    return list
end

local function buttons()
    local list = {}
    for _, c in ipairs(ui.calls_of("invisible_button")) do list[#list + 1] = c.id end
    return list
end

local function button(id)
    for _, c in ipairs(ui.calls_of("invisible_button")) do
        if c.id == id then return c end
    end
    return nil
end

local function rects_of(color)
    local list = {}
    for _, c in ipairs(ui.calls) do
        if c.fn == "add_rect_filled" and c.col == color then list[#list + 1] = c end
    end
    return list
end

-- The texts drawn on the line at y, left to right.
local function line_at(y)
    local list = {}
    for _, c in ipairs(ui.calls) do
        if c.fn == "add_text" and math.abs(c.y - y) < 1e-6 then list[#list + 1] = c end
    end
    table.sort(list, function(a, b) return a.x < b.x end)
    local out = {}
    for i, c in ipairs(list) do out[i] = c.text end
    return table.concat(out, " | ")
end

local function index_of(key)
    for i, row in ipairs(SettingsView.ROWS) do
        if row.key == key then return i end
    end
end

-- The label calls of the model's rows, matched in drawing order (a label can be in two groups: «Размер», «Прочее»).
local function labels_drawn(m)
    local texts, at, out = {}, 0, {}
    for _, c in ipairs(ui.calls) do
        if c.fn == "add_text" then texts[#texts + 1] = c end
    end
    for _, g in ipairs(m.groups) do
        for _, r in ipairs(g.rows) do
            for i = at + 1, #texts do
                if texts[i].text == r.label and texts[i].col == C.text then
                    at = i
                    out[r.key] = texts[i]
                    break
                end
            end
            if not out[r.key] then error("not drawn after the one before: " .. r.label) end
        end
    end
    return out
end

-- The help lines drawn (12 px, light grey), joined by a space.
local function help_drawn()
    local parts = {}
    for _, c in ipairs(texts_in(C.mid)) do parts[#parts + 1] = c.text end
    return table.concat(parts, " "), #parts
end

test("a panel beside the meter, on the side with more room, inside the display", function()
    local s = fresh()
    draw(state(s), s)
    local pos, size = ui.find("set_next_window_pos"), ui.find("set_next_window_size")
    eq(size.w, W, "320 px wide at scale 1"); eq(size.h, CONTENT_H, "as tall as its content")
    eq(pos.x, 40 + 356 + 12, "12 px right of the meter"); eq(pos[2], COND_ALWAYS, "pos every frame")
    eq(pos.y, DISPLAY_H - 16 - CONTENT_H, "the meter's top, moved up to fit the display")
    eq(size.cond, COND_ALWAYS, "size every frame")
    eq(ui.find("begin_window")[1], WINDOW, "its own window")
    local flags = ui.find("begin_window")[3]
    for _, f in ipairs(FLAGS) do eq(flags & f, f, "flag " .. f) end
    eq(flags & ALWAYS_AUTO_RESIZE, 0, "a fixed size")
    -- the journal's look: its dark panel on the background layer with a 1 px edge, a bronze line under the title
    local panel = rects_of(C.panel)[1]
    eq(panel.layer, "background", "under every window")
    eq(panel.x0, pos.x, "panel x0"); eq(panel.y0, pos.y, "panel y0")
    eq(panel.x1, pos.x + W, "panel x1"); eq(panel.y1, pos.y + CONTENT_H, "panel y1")
    eq(#rects_of(C.border) >= 4, true, "the edge")
    eq(#rects_of(C.bronze) >= 1, true, "the bronze line")

    -- a meter high up (with room under it for the window's 1136 px): the window's top is the meter's
    s:set("window_y", 30)
    draw(state(s), s)
    eq(ui.find("set_next_window_pos").y, 30, "at the meter's top")
    -- a meter on the right half: the window goes to its left
    s:set("window_x", 1500)
    draw(state(s), s)
    eq(ui.find("set_next_window_pos").x, 1500 - 12 - W, "12 px left of the meter")
    -- not enough room on either side for 320 px: as wide as the room, still beside the meter
    s:set("window_x", 40)
    ui.display = { x = 740, y = DISPLAY_H }
    draw(state(s), s)
    pos, size = ui.find("set_next_window_pos"), ui.find("set_next_window_size")
    eq(pos.x, 408, "right of the meter"); eq(size.w, 740 - 408 - 16, "the room there")
    -- scale 2: measured again, twice as wide, beside the twice as wide meter
    ui.display = { x = 1920, y = DISPLAY_H }
    s:set("scale", 2)
    settle(s)
    pos, size = ui.find("set_next_window_pos"), ui.find("set_next_window_size")
    eq(size.w, 2 * W, "640 px at scale 2"); eq(pos.x, 40 + 680 + 16 + 24, "beside the meter of scale 2")
    eq(size.h, DISPLAY_H - 32, "as tall as the display allows")
    eq(pos.y, 16, "inside it")
end)

test("on 1920 × 1080 the window's 37 rows page: two pages, Debug on the second, drawn when selected", function()
    local s = fresh()
    ui.display = { x = 1920, y = 1080 }
    settle(s)
    ui.drawing_ui = true
    draw(state(s, 1), s)
    eq(ui.find("set_next_window_size").h, 1080 - 32, "as tall as the display allows (the content is 1136 px)")
    eq(text_call(i18n.t("jpage", 1, 2)) ~= nil, true, "page 1 of 2 in the title")
    eq(text_call("Отладка"), nil, "Debug not on the first page")
    draw(state(s, index_of("debug")), s)
    eq(text_call(i18n.t("jpage", 2, 2)) ~= nil, true, "its row selected: page 2 of 2")
    eq(text_call("Отладка") ~= nil, true, "Debug drawn"); eq(#rects_of(C.selected) >= 1, true, "and lit")
    eq(button("##dd2dm_srow:debug") ~= nil, true, "its button there")
    ui.drawing_ui = false
end)

test("the display size missing: right of the meter at its top, listed", function()
    local s = fresh()
    local get = imgui.get_display_size
    imgui.get_display_size = nil
    draw(state(s), s)
    imgui.get_display_size = get
    local pos, size = ui.find("set_next_window_pos"), ui.find("set_next_window_size")
    eq(pos.x, 408, "right of the meter"); eq(pos.y, 300, "at its top")
    eq(size.w, W, "320 wide"); eq(size.h, math.min(CONTENT_H, 720 - 32), "at most what 720 px allow")
    eq(T.str(SettingsUI.missing()), "get_display_size", "listed")
    SettingsUI.reset()
    eq(#SettingsUI.missing(), 0, "forgotten by a reset")
    imgui.get_display_size = function() error("no display") end
    draw(state(s), s)
    imgui.get_display_size = get
    eq(ui.find("set_next_window_pos").x, 408, "a call that raises: the same place")
    eq(T.str(SettingsUI.missing()), "get_display_size", "listed")
end)

test("the window size call missing: the window takes its size from its content", function()
    local s = fresh()
    local set = imgui.set_next_window_size
    imgui.set_next_window_size = nil
    draw(state(s), s)
    imgui.set_next_window_size = set
    eq(ui.find("begin_window")[3] & ALWAYS_AUTO_RESIZE, ALWAYS_AUTO_RESIZE, "auto resize")
    local last = ui.calls_of("item_size")
    last = last[#last]
    eq(last ~= nil, true, "the content is declared")
    eq(last[2][1] - last[1][1] >= W - 16, true, "as wide as the window")
    eq(T.str(SettingsUI.missing()), "set_next_window_size", "listed")
end)

-- calc_text_size replaced while fn runs: per_char(code point) px a character at 14 px, in proportion at other sizes.
-- The kit's measured widths are forgotten before and after.
local function with_font(per_char, fn)
    local calc = imgui.calc_text_size
    imgui.calc_text_size = function(text)
        local w = 0
        for _, cp in utf8.codes(text) do w = w + per_char(cp) end
        local px = ui.fonts[#ui.fonts] or 16
        return { x = w * px / 14, y = px }
    end
    Kit.reset()
    local ok, err = pcall(fn)
    imgui.calc_text_size = calc
    Kit.reset()
    if not ok then error(err, 0) end
end

local function cyrillic(cp) return cp >= 0x400 and cp <= 0x4FF end

test("the width: the widest row as the font measures it, in the language shown", function()
    eq(SettingsUI.WIDTH, 360, "360 px until measured"); eq(SettingsUI.FIT_MIN, 320, "at least 320")
    eq(SettingsUI.FIT_MAX, 480, "at most 480")
    -- the stub's 7 px a character: the widest row is the settings key's with its prompt, 317 px: the least, 320
    for _, lang in ipairs({ "ru", "en" }) do
        local s = fresh(nil, lang)
        draw(state(s), s)
        eq(ui.find("set_next_window_size").w, W, "320 px in " .. lang)
    end
    -- Cyrillic letters wider than Latin ones (9 px against 7): the Russian window is wider, the English one is not
    with_font(function(cp) return cyrillic(cp) and 9 or 7 end, function()
        local s = fresh()
        draw(state(s), s)
        -- «Настройки» 9 × 9, the prompt 20 × 9 + 10 × 7, the gaps 3 × 8, the margins 2 × 10
        eq(ui.find("set_next_window_size").w, 81 + 250 + 24 + 20, "375 px in Russian")
        -- the key prompt and every label and value drawn whole
        local st = state(s, index_of("settings_key"), "settings_key")
        draw(st, s)
        local drawn = labels_drawn(st.model)
        for _, g in ipairs(st.model.groups) do
            for _, r in ipairs(g.rows) do eq(drawn[r.key].text, r.label, r.key .. " whole") end
        end
        eq(line_at(drawn.settings_key.y), "Настройки | " .. i18n.t("press_a_key"), "the prompt beside its label")
        for _, c in ipairs(ui.calls_of("add_text")) do eq(c.text:sub(-2) ~= "..", true, "nothing cut: " .. c.text) end
        -- English measured again: the least
        i18n.set("en")
        settle(s)
        eq(ui.find("set_next_window_size").w, W, "320 px in English")
    end)
    -- the window measures within 320..480 px × scale
    with_font(function() return 20 end, function()
        local s = fresh()
        draw(state(s), s)
        eq(ui.find("set_next_window_size").w, 480, "very wide letters: at most 480")
        s:set("scale", 1.5)
        settle(s)
        eq(ui.find("set_next_window_size").w, 720, "480 × 1.5")
    end)
    with_font(function() return 1 end, function()
        local s = fresh({ scale = 1.5 })
        draw(state(s), s)
        eq(ui.find("set_next_window_size").w, 480, "very narrow letters: at least 320 × 1.5")
    end)
    -- drawn with the stub's font: no label or value cut, in either language, at the longest values
    for _, lang in ipairs({ "ru", "en" }) do
        local s = fresh({ language = lang, boss_hp_numbers = "all", enemy_hp_numbers = "all" }, lang)
        local st = state(s)
        draw(st, s)
        local drawn = labels_drawn(st.model)
        for _, g in ipairs(st.model.groups) do
            for _, r in ipairs(g.rows) do
                eq(drawn[r.key].text, r.label, r.key .. " whole in " .. lang)
                if r.value then
                    eq(line_at(drawn[r.key].y):find(r.value, 1, true) ~= nil, true, r.key .. ": " .. r.value)
                end
            end
        end
        for _, c in ipairs(ui.calls_of("add_text")) do
            eq(c.text:sub(-2) ~= "..", true, "nothing cut in " .. lang .. ": " .. c.text)
        end
    end
end)

test("the width: 360 px × scale until measured or when it fails; measured once per language and scale", function()
    -- the first frame: not measured yet
    ui.reset()
    ui.display = { x = 1920, y = DISPLAY_H }
    SettingsUI.reset()
    i18n.set("ru")
    local s = make_settings()
    draw(state(s), s)
    eq(ui.find("set_next_window_size").w, 360, "360 px on the first frame")
    eq(ui.find("set_next_window_size").h, fixed_h(2, 3) + BODY_H, "the help two lines high")
    draw(state(s), s)
    eq(ui.find("set_next_window_size").w, W, "measured from the next")
    -- a text that cannot be measured (a key's name, measured only for the width): 360 px, the window still drawn
    local calc, raised = imgui.calc_text_size, 0
    imgui.calc_text_size = function(text)
        if text == "0x01" then
            raised = raised + 1
            error("no size")
        end
        return calc(text)
    end
    Kit.reset()
    SettingsUI.reset()
    for _ = 1, 5 do draw(state(s), s) end
    eq(ui.find("set_next_window_size").w, 360, "measuring failed: 360 px")
    eq(raised, 1, "tried once, not every frame")
    eq(text_call("Стиль") ~= nil, true, "the window drawn")
    s:set("scale", 1.5)
    for _ = 1, 3 do draw(state(s), s) end
    eq(ui.find("set_next_window_size").w, 540, "360 × 1.5")
    eq(raised, 2, "tried again at another scale")
    -- measured once per language and scale: a text measured only for the width is not measured again
    local seen = 0
    imgui.calc_text_size = function(text)
        if text == "0x01" then seen = seen + 1 end
        return calc(text)
    end
    s = fresh()
    seen = 0
    for _ = 1, 5 do
        Kit.reset() -- the kit's own cache of widths would hide a measuring again
        draw(state(s), s)
    end
    eq(seen, 0, "not again in five frames")
    i18n.set("en")
    for _ = 1, 5 do
        Kit.reset()
        draw(state(s), s)
    end
    eq(seen, 1, "once for English")
    s:set("scale", 1.5)
    for _ = 1, 5 do
        Kit.reset()
        draw(state(s), s)
    end
    eq(seen, 2, "once for another scale")
    imgui.calc_text_size = calc
    Kit.reset()
end)

test("the help and the hint wrap to the measured width; the window's height follows them", function()
    -- every letter 9 px: English 341 px wide (the settings key's row: 8 × 9 + 25 × 9 + 3 × 8, the margins)
    with_font(function() return 9 end, function()
        local s = fresh(nil, "en")
        ui.display = { x = 1920, y = 1200 } -- room for the whole height: 1080 px would page the rows
        local st = state(s, 1)
        draw(st, s)
        local size, pos = ui.find("set_next_window_size"), ui.find("set_next_window_pos")
        eq(size.w, 72 + 225 + 24 + 20, "341 px")
        local right = pos.x + size.w - 10
        local function right_of(c) return c.x + imgui.calc_text_size(c.text).x * c.px / 16 end
        -- the hint: its last line (46 letters, 355 px at 12 px) on two lines; every word kept
        local hint, want = {}, {}
        for _, c in ipairs(texts_in(C.dim)) do
            if c.px == 12 and c.y > texts_in(C.mid)[1].y then
                hint[#hint + 1] = c.text
                eq(right_of(c) <= right, true, "inside the body: " .. c.text)
            end
        end
        eq(#hint, 4, "four hint lines")
        for part in (st.model.hint .. "\n"):gmatch("(.-)\n") do want[#want + 1] = part end
        eq(table.concat(hint, " "), table.concat(want, " "), "the hint whole")
        eq(hint[4], "menu", "the last word on a line of its own")
        -- the help of every row whole, inside the body; one height for all, with the hint's fourth line. The longest
        -- help, the Other row's (it also names "Falls and environment"), takes four lines
        local heights = {}
        for sel = 1, #SettingsView.ROWS do
            st = state(s, sel)
            draw(st, s)
            heights[ui.find("set_next_window_size").h] = true
            local help
            for _, g in ipairs(st.model.groups) do
                for _, r in ipairs(g.rows) do
                    if r.index == sel then help = r.help end
                end
            end
            eq(help_drawn(), help, "the help of row " .. sel)
            for _, c in ipairs(texts_in(C.mid)) do eq(right_of(c) <= right, true, "inside the body: " .. c.text) end
        end
        local n = 0
        for h in pairs(heights) do
            n = n + 1
            eq(h, fixed_h(4, 4) + BODY_H, "four help lines and four hint lines")
        end
        eq(n, 1, "one height")
    end)
end)

test("the title, the groups with their headings, every row with its value, the table, the hint", function()
    local s = fresh({ halo = false, scale = 1.18 })
    draw(state(s), s)
    local m = SettingsView.build(s, i18n)
    local title = text_call("Hidden Numbers · Настройки")
    eq(title ~= nil, true, "the title with the mod's name")
    eq(title.px, 16 * 1.18, "at 16 px × scale")
    s:set("scale", 1)
    settle(s)
    m = SettingsView.build(s, i18n)
    local drawn = labels_drawn(m)
    local last_y = text_call(m.title).y
    for _, g in ipairs(m.groups) do
        local h = heading_call(g.heading)
        eq(h ~= nil, true, "heading " .. g.heading)
        eq(h.y > last_y, true, g.heading .. " under what came before")
        last_y = h.y
        for _, r in ipairs(g.rows) do
            local label = drawn[r.key]
            eq(label.px, 14, "at 14 px")
            eq(label.y > last_y, true, r.key .. " under what came before")
            last_y = label.y
            if r.value then
                eq(line_at(label.y):find(r.value, 1, true) ~= nil, true, r.key .. ": its value on its line: "
                    .. line_at(label.y))
            end
        end
    end
    eq(heading_call("Вид метра").y < heading_call("Что показывать").y, true, "the meter's look first")
    -- the values: a switch on in green, off dim; a choice or a number between ‹ ›, with its unit
    eq(text_call("вкл").col, C.ok, "on in green")
    eq(text_call("выкл").col, C.dim, "off dim")
    eq(line_at(drawn.scale.y), "Размер | ‹ | 100 % | ›", "a percent with its arrows")
    eq(line_at(drawn.bar_px.y), "Полосы | ‹ | 3 px | ›", "px")
    eq(line_at(drawn.summary_autohide.y), "Сводка гаснет через | ‹ | никогда | ›", "never")
    eq(line_at(drawn.language.y), "Язык | ‹ | Как в игре | ›", "a choice")
    eq(line_at(drawn.toggle_key.y), "Метр | F6", "a key: its name")
    eq(line_at(drawn.boss_hp_numbers.y), "У босса | ‹ | HP / макс. и % | ›", "an HP format by its short name")
    -- the table: its line of column names under the heading, two cells a row, a dim «—» where there is no section
    local cols = text_call("Бой")
    eq(cols ~= nil, true, "the column names")
    eq(line_at(cols.y), "Бой | Сводка", "«Бой | Сводка»")
    eq(cols.px, 12, "at 12 px"); eq(cols.col, C.dim, "dim")
    eq(cols.y > heading_call("Что показывать").y and cols.y < drawn.section_enemies.y, true, "between")
    eq(line_at(drawn.section_enemies.y), "Враги | — | вкл", "the enemies: the summary's only")
    eq(line_at(drawn.section_damage.y), "Нанесено | вкл | вкл", "dealt: both")
    eq(line_at(drawn.section_taken.y), "Получено | вкл | —", "taken: the fight's only")
    eq(line_at(drawn.section_heal.y), "Лечение | вкл | вкл", "healing")
    eq(line_at(drawn.section_armor.y), "Броня | — | вкл", "armor: the summary's only")
    eq(line_at(drawn.section_allies.y), "Союзники | вкл | вкл", "allies")
    eq(line_at(drawn.section_other.y), "Прочее | вкл | вкл", "other")
    local dash = text_call("—")
    eq(dash.col, C.dim, "the dash dim")
    -- the cells sit under their column names
    local summary = text_call("Сводка")
    local function centre(c) return c.x + imgui.calc_text_size(c.text).x * c.px / 16 / 2 end
    local function cell_of(y, n)
        local list = {}
        for _, c in ipairs(ui.calls_of("add_text")) do
            if math.abs(c.y - y) < 1e-6 and c.text ~= "Враги" and c.text ~= "Нанесено" then list[#list + 1] = c end
        end
        table.sort(list, function(a, b) return a.x < b.x end)
        return list[n]
    end
    eq(math.abs(centre(cell_of(drawn.section_damage.y, 2)) - centre(summary)) < 1, true, "the summary column")
    eq(math.abs(centre(cell_of(drawn.section_damage.y, 1)) - centre(cols)) < 1, true, "the fight column")
    eq(math.abs(centre(cell_of(drawn.section_enemies.y, 1)) - centre(cols)) < 1, true, "the dash under «Бой»")
    s:set("live_taken", false)
    draw(state(s), s)
    eq(line_at(drawn.section_taken.y), "Получено | выкл | —", "a cell off")
    -- the hint: one dim 12 px line per part, at the bottom
    local lines = {}
    for part in (m.hint .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = part end
    eq(#lines, 3, "three hint lines")
    local pos, size = ui.find("set_next_window_pos"), ui.find("set_next_window_size")
    for i, part in ipairs(lines) do
        local c = text_call(part)
        eq(c ~= nil, true, "hint line " .. i .. ": " .. part)
        eq(c.px, 12, "at 12 px"); eq(c.col, C.dim, "dim")
        eq(c.y > last_y, true, "under the rows")
        eq(c.y + 12 <= pos.y + size.h, true, "inside the window")
    end
    eq(lines[3]:find("F8", 1, true) ~= nil, true, "the hint names the settings key")
    -- in English too
    i18n.set("en")
    draw(state(s), s)
    eq(text_call("Hidden Numbers · Settings") ~= nil, true, "the English title")
    eq(heading_call("Meter look") ~= nil, true, "an English heading")
    eq(line_at(text_call("Fight").y), "Fight | Summary", "the columns in English")
end)

test("the selected row lighter with a bronze mark, in the table its cell too; a waiting key row asks", function()
    local s = fresh()
    local sel = index_of("scale")
    draw(state(s, sel), s)
    local y = text_call(i18n.t("setting_scale")).y
    local lit = rects_of(C.selected)
    eq(#lit, 1, "one row lit")
    eq(lit[1].y0 <= y and lit[1].y1 >= y + 14, true, "the selected one")
    local mark = nil
    for _, r in ipairs(rects_of(C.bronze)) do
        if r.y0 == lit[1].y0 and r.x1 - r.x0 == 3 then mark = r end
    end
    eq(mark ~= nil, true, "a 3 px bronze mark at its left")
    -- a table row: the row lit, and its selected cell again, with a 2 px bronze line under it
    local function cell_lit(key, col)
        draw(state(s, index_of(key), nil, col), s)
        lit = rects_of(C.selected)
        eq(#lit, 2, key .. ": the row and its cell")
        local row, cell = lit[1], lit[2]
        eq(cell.x1 - cell.x0, 64, "a cell 64 px wide"); eq(cell.y0 == row.y0 and cell.y1 == row.y1, true, "as tall")
        local line = nil
        for _, r in ipairs(rects_of(C.bronze)) do
            if r.x0 == cell.x0 and r.x1 == cell.x1 and r.y1 == cell.y1 and r.y1 - r.y0 == 2 then line = r end
        end
        eq(line ~= nil, true, key .. ": a bronze line under the cell")
        return cell, row
    end
    local cell, row = cell_lit("section_damage", 1)
    eq(cell.x0, row.x1 - 128, "the fight cell"); eq(cell.x1, row.x1 - 64, "left of the summary cell")
    cell = cell_lit("section_damage", 2)
    eq(cell.x0, row.x1 - 64, "the summary cell"); eq(cell.x1, row.x1, "at the row's right")
    cell = cell_lit("section_enemies", 1)
    eq(cell.x0, row.x1 - 64, "the enemies: never the «—», their summary cell")
    cell = cell_lit("section_taken", 2)
    eq(cell.x0, row.x1 - 128, "the damage taken: their fight cell")
    -- waiting for a key: the row says so, in bronze
    draw(state(s, index_of("journal_key"), "journal_key"), s)
    local prompt = text_call(i18n.t("press_a_key"))
    eq(prompt ~= nil, true, "the prompt")
    eq(prompt.col, C.bronze, "in bronze")
    eq(line_at(prompt.y), "Журнал | " .. i18n.t("press_a_key"), "on the journal key's row")
    eq(text_call("F7"), nil, "in place of the key's name")
end)

test("the help line: the selected row's, under a thin line above the hint, as high as the longest help", function()
    for _, lang in ipairs({ "ru", "en" }) do
        local s = fresh(nil, lang)
        local heights = {}
        for sel, row in ipairs(SettingsView.ROWS) do
            local st = state(s, sel, nil, 2)
            draw(st, s)
            local size, pos = ui.find("set_next_window_size"), ui.find("set_next_window_pos")
            heights[size.h] = true
            local want
            for _, g in ipairs(st.model.groups) do
                for _, r in ipairs(g.rows) do
                    if r.index == sel then want = r.help end
                end
            end
            local text, n = help_drawn()
            eq(text, want, row.key .. ": its help, whole, in " .. lang)
            eq(n >= 1 and n <= 3, true, row.key .. ": one to three lines (the longest at 300 px) in " .. lang)
            eq(size.h, CONTENT_H, row.key .. ": room for three in " .. lang)
            local hint = text_call(st.model.hint:match("^[^\n]+"))
            local x0 = pos.x + 10
            for _, c in ipairs(texts_in(C.mid)) do
                eq(c.px, 12, "12 px"); eq(c.x, x0, "at the body's left")
                eq(c.x + imgui.calc_text_size(c.text).x * 12 / 16 <= x0 + W - 20, true, "inside the body's width")
                eq(c.y < hint.y, true, "above the hint")
            end
        end
        local n = 0
        for _ in pairs(heights) do n = n + 1 end
        eq(n, 1, "one height for every row in " .. lang)
    end
    -- the thin line between the body and the help; a short help on one line
    local s = fresh()
    draw(state(s, index_of("shadow")), s)
    local first_help = texts_in(C.mid)[1]
    local rule
    for _, r in ipairs(rects_of(C.border)) do
        if r.y1 - r.y0 == 1 and r.x1 - r.x0 == W - 20 then rule = r end
    end
    eq(rule ~= nil, true, "a thin line as wide as the body")
    eq(rule.y1 <= first_help.y, true, "above the help")
    eq(first_help.text, "Тень под текстом и цифрами.", "the shadow's help")
    eq(#texts_in(C.mid), 1, "on one line")
    -- a long help wraps at word ends
    draw(state(s, index_of("section_damage")), s)
    local help = texts_in(C.mid)
    eq(#help, 3, "three lines")
    eq(help[2].y - help[1].y, 16, "16 px apart"); eq(help[3].y - help[2].y, 16, "16 px apart")
    eq(help_drawn(), "„Нанесено“ — показывать ли раздел в метре во время боя и в сводке после боя. — значит, такого "
        .. "раздела там нет.", "the table row's help, named")
    -- a hidden row selected: no help, the same height
    s:set("style", "panel")
    draw(state(s, index_of("halo")), s)
    eq(#texts_in(C.mid), 0, "no help for a row not drawn")
    eq(#rects_of(C.selected), 0, "nothing lit")
end)

test("the halo and the bars: not drawn with the panel, and the window is shorter", function()
    local s = fresh()
    draw(state(s), s)
    eq(text_call("Ореол") ~= nil and text_call("Полосы") ~= nil, true, "without the panel: both rows")
    eq(ui.find("set_next_window_size").h, CONTENT_H, "37 rows")
    s:set("style", "panel")
    ui.drawing_ui = true
    draw(state(s), s)
    eq(text_call("Ореол"), nil, "no halo row"); eq(text_call("Полосы"), nil, "no bars row")
    eq(button("##dd2dm_srow:halo"), nil, "no halo button"); eq(button("##dd2dm_snext:bar_px"), nil, "no bars buttons")
    eq(ui.find("set_next_window_size").h, CONTENT_H - 2 * 20, "two rows shorter")
    eq(line_at(text_call("Стиль").y), "Стиль | ‹ | Панель | ›", "the panel")
    ui.drawing_ui = false
end)

test("no mouse input while the REFramework menu is closed", function()
    local s = fresh()
    draw(state(s), s)
    local flags = ui.find("begin_window")[3]
    eq(flags & NO_MOUSE_INPUTS, NO_MOUSE_INPUTS, "no mouse input")
    eq(flags & NO_NAV, NO_NAV, "no keyboard navigation")
    eq(#buttons(), 0, "no buttons")
    eq(text_call("×"), nil, "no close glyph")
    eq(text_call("‹").col, C.dim, "the arrows dim")
    ui.drawing_ui = true
    draw(state(s), s)
    flags = ui.find("begin_window")[3]
    eq(flags & NO_MOUSE_INPUTS, 0, "the mouse works with the menu open")
    eq(flags & NO_NAV, 0, "nav flags off")
    eq(text_call("‹").col, C.text, "the arrows lit")
end)

test("the mouse: a row selects, a switch or a cell flips, a key row waits, ‹ › step, × closes", function()
    local s = fresh()
    ui.drawing_ui = true
    draw(state(s), s)
    -- every row has its button, a choice and a number their arrows, a table row a button per cell with a switch
    for _, row in ipairs(SettingsView.ROWS) do
        eq(button("##dd2dm_srow:" .. row.key) ~= nil, true, row.key .. " has a row button")
        local arrows = row.kind == "choice" or row.kind == "number"
        eq(button("##dd2dm_sprev:" .. row.key) ~= nil, arrows, row.key .. " ‹")
        eq(button("##dd2dm_snext:" .. row.key) ~= nil, arrows, row.key .. " ›")
        if row.cells then
            for c = 1, 2 do
                if row.cells[c] then
                    eq(button("##dd2dm_srow:" .. row.cells[c]) ~= nil, true, row.cells[c] .. ": a cell button")
                end
            end
        end
    end
    eq(button("##dd2dm_sclose") ~= nil, true, "the close button")
    local seen, n = {}, 0
    for _, id in ipairs(buttons()) do
        eq(id:find("##dd2dm_", 1, true), 1, "prefixed: " .. id)
        eq(seen[id], nil, "unique: " .. id)
        seen[id] = true
        n = n + 1
    end
    -- 37 rows, 11 cells, the arrows of 5 choices and 12 numbers, ×
    eq(n, 37 + 11 + 2 * 17 + 1, "no button for a «—»")
    -- the buttons do not overlap: a row's button ends where its ‹ starts, a table row's where its cells start
    local row, prev, nxt = button("##dd2dm_srow:scale"), button("##dd2dm_sprev:scale"), button("##dd2dm_snext:scale")
    eq(row.x + row.w <= prev.x, true, "row button left of ‹")
    eq(prev.x + prev.w <= nxt.x, true, "‹ left of ›")
    eq(nxt.x + nxt.w <= 408 + W, true, "› inside the window")
    local switch = button("##dd2dm_srow:halo")
    eq(switch.w, W - 20, "a switch's row button is the whole row")
    local label, fight, summary = button("##dd2dm_srow:section_damage"), button("##dd2dm_srow:live_damage"),
        button("##dd2dm_srow:summary_damage")
    eq(label.x + label.w, fight.x, "the label's button ends at the fight cell")
    eq(fight.w, 64, "a cell's button: the cell"); eq(fight.x + fight.w, summary.x, "then the summary cell")
    eq(summary.x + summary.w, 408 + W - 10, "at the row's right")

    local function click(id)
        ui.press(id)
        return draw(state(s), s)
    end
    local a = click("dd2dm_srow:halo")
    eq(a.select, index_of("halo"), "a switch row: selected"); eq(a.activate, true, "and flipped")
    eq(a.step, 0, "no step"); eq(a.col, nil, "no cell")
    a = click("dd2dm_srow:toggle_key")
    eq(a.select, index_of("toggle_key"), "a key row: selected"); eq(a.activate, true, "and waits for a key")
    a = click("dd2dm_srow:scale")
    eq(a.select, index_of("scale"), "a number row: selected"); eq(a.activate, false, "nothing else")
    a = click("dd2dm_snext:scale")
    eq(a.select, index_of("scale"), "› selects its row"); eq(a.step, 1, "and steps up")
    a = click("dd2dm_sprev:language")
    eq(a.select, index_of("language"), "‹ on the language"); eq(a.step, -1, "steps down")
    -- the table
    a = click("dd2dm_srow:summary_damage")
    eq(a.select, index_of("section_damage"), "a cell: its row"); eq(a.col, 2, "its cell")
    eq(a.activate, true, "and flipped")
    a = click("dd2dm_srow:show_allies")
    eq(a.select, index_of("section_allies"), "the fight's allies: their row"); eq(a.col, 1, "the fight cell")
    eq(a.activate, true, "flipped")
    a = click("dd2dm_srow:summary_enemies")
    eq(a.select, index_of("section_enemies"), "the enemies"); eq(a.col, 2, "the summary cell")
    a = click("dd2dm_srow:section_heal")
    eq(a.select, index_of("section_heal"), "the label: the row"); eq(a.col, nil, "no cell")
    eq(a.activate, false, "nothing flipped")
    a = click("dd2dm_sclose")
    eq(a.close, true, "× closes")
    a = draw(state(s), s)
    eq(a.select, nil, "a quiet frame"); eq(a.close, false, "nothing")
    ui.drawing_ui = false
end)

test("keys map to actions", function()
    local K = SettingsUI.KEYS
    eq(T.str(K[0x26]), "select_step -1", "Up"); eq(T.str(K[0x28]), "select_step 1", "Down")
    eq(T.str(K[0x25]), "step -1", "Left"); eq(T.str(K[0x27]), "step 1", "Right")
    eq(T.str(K[0x21]), "group_step -1", "PgUp"); eq(T.str(K[0x22]), "group_step 1", "PgDn")
    eq(K[0x0D][1], "activate", "Enter")
    local n = 0
    for _ in pairs(K) do n = n + 1 end
    eq(n, 7, "seven keys")
    local a = SettingsUI.key_actions({ [0x28] = true })
    eq(a.select_step, 1, "Down"); eq(a.step, 0, "no step"); eq(a.activate, false, "no Enter")
    a = SettingsUI.key_actions({ [0x27] = true, [0x0D] = true, [0x21] = true })
    eq(a.step, 1, "Right"); eq(a.activate, true, "Enter"); eq(a.group_step, -1, "PgUp")
    a = SettingsUI.key_actions({ [0x26] = true, [0x28] = true })
    eq(a.select_step, 0, "Up and Down cancel out")
    a = SettingsUI.key_actions({ [0x41] = true })
    eq(a.select_step + a.step + a.group_step, 0, "another key: nothing"); eq(a.activate, false, "nothing")
    eq(a.col, nil, "no cell")
    eq(SettingsUI.key_actions(nil).close, false, "no keys")
end)

test("rows that do not fit page, and the page shown holds the selection", function()
    local s = fresh()
    ui.display = { x = 1280, y = 720 }
    local n = #SettingsView.ROWS
    draw(state(s, 1), s)
    local size = ui.find("set_next_window_size")
    eq(size.h, 720 - 32, "as tall as the display allows")
    eq(heading_call("Вид метра") ~= nil, true, "page 1: the first group")
    eq(text_call("Отладка"), nil, "not the last row")
    eq(text_call(i18n.t("jpage", 1, 2)) ~= nil, true, "page 1 of 2 in the title line")
    -- the selection on the last row: the page that holds it
    draw(state(s, n), s)
    local last = text_call("Отладка")
    eq(last ~= nil, true, "the last row is shown")
    eq(#rects_of(C.selected), 1, "lit")
    eq(heading_call("Вид метра"), nil, "the first group is not")
    eq(text_call(i18n.t("jpage", 2, 2)) ~= nil, true, "page 2 of 2")
    local pos = ui.find("set_next_window_pos")
    eq(last.y + 14 <= pos.y + size.h, true, "inside the window")
    eq(help_drawn(), i18n.t("setting_help_debug"), "its help")
    -- every row is on some page, inside the body, above the help; a heading never ends a page alone
    for sel = 1, n do
        local st = state(s, sel)
        draw(st, s)
        local label
        for _, c in ipairs(ui.calls_of("add_text")) do
            if c.text == i18n.t("setting_" .. SettingsView.ROWS[sel].key) and c.col == C.text then label = c end
        end
        eq(label ~= nil, true, "row " .. sel .. " shown when selected")
        local help = texts_in(C.mid)[1]
        eq(label.y + 14 <= help.y, true, SettingsView.ROWS[sel].key .. " above the help")
        for gi, g in ipairs(st.model.groups) do
            local h = heading_call(g.heading)
            if h then
                local first = g.rows[1].label
                local seen = false
                for _, c in ipairs(ui.calls_of("add_text")) do
                    if c.text == first and c.col == C.text and c.y > h.y then seen = true end
                end
                eq(seen, true, "group " .. gi .. "'s heading with its first row on the page of " .. sel)
                if g.columns then
                    eq(text_call(g.columns[1]) ~= nil, true, "the table's column names with its heading")
                end
            end
        end
    end
    -- a small screen at scale 2: the selection is still shown
    s:set("scale", 2)
    draw(state(s, n), s)
    eq(text_call("Отладка") ~= nil, true, "the selection shown at scale 2")
    eq(#rects_of(C.selected), 1, "and lit")
end)

test("a table that goes on over a page has its column names over it on the new page too", function()
    local s = fresh()
    -- 510 px: a body of 510 - 32 - 164 = 314 px holds the meter's look (204) and the table's heading, its names and
    -- its first three rows (60 + 2 × 20); its fourth row starts page 2. Four pages since the player's numbers' row
    -- came in: page 3 from the health numbers' size, Debug alone on page 4. Paging is by design; a 1440p screen
    -- shows one page
    ui.display = { x = 1920, y = 510 }
    local function count(text)
        local n = 0
        for _, c in ipairs(ui.calls_of("add_text")) do
            if c.text == text then n = n + 1 end
        end
        return n
    end
    draw(state(s, index_of("section_enemies")), s)
    eq(text_call(i18n.t("jpage", 1, 4)) ~= nil, true, "page 1 of 4")
    eq(heading_call("Что показывать") ~= nil, true, "page 1: the table's heading")
    eq(count("Бой"), 1, "its column names once")
    eq(text_call("Получено") ~= nil, true, "its third row"); eq(text_call("Лечение"), nil, "not its fourth")
    draw(state(s, index_of("section_heal")), s)
    eq(text_call(i18n.t("jpage", 2, 4)) ~= nil, true, "page 2")
    eq(heading_call("Что показывать"), nil, "no heading on page 2")
    eq(count("Бой"), 1, "the column names once")
    local cols, label = text_call("Бой"), text_call("Лечение")
    eq(line_at(cols.y), "Бой | Сводка", "both names")
    eq(cols.y < label.y and label.y - cols.y < 16 + 20, true, "right over the fourth row")
    for _, c in ipairs(ui.calls_of("add_text")) do
        if c.px == 14 and c.y > text_call(i18n.t("jpage", 2, 4)).y + 1 then
            eq(c.y > cols.y, true, "the first thing on the page: " .. c.text)
        end
    end
    eq(line_at(label.y), "Лечение | вкл | вкл", "the row's cells under them")
    -- the other rows of the table follow without the names again
    eq(text_call("Прочее") ~= nil and text_call("Сводка гаснет через") ~= nil, true, "the rest of the group")
    -- every row still on some page, lit when selected
    for sel = 1, #SettingsView.ROWS do
        draw(state(s, sel), s)
        eq(#rects_of(C.selected) >= 1, true, "row " .. sel .. " shown")
    end
end)

test("the health numbers: at the boss, over enemies (short names), the player's, the buildup bars, their size",
    function()
    local s = fresh()
    ui.drawing_ui = true
    local i = index_of("boss_hp_numbers")
    eq(SettingsView.ROWS[i].group, SettingsView.ROWS[i + 1].group, "in their group")
    eq(SettingsView.ROWS[i - 1].group ~= SettingsView.ROWS[i].group, true, "its first row")
    eq(index_of("enemy_hp_numbers"), i + 1, "the numbers over enemies under it")
    eq(index_of("player_numbers"), i + 2, "the player's numbers' switch under them")
    eq(index_of("buildup_bars"), i + 3, "the buildup bars' switch under it")
    eq(index_of("enemy_hp_size"), i + 4, "their size under all four")
    draw(state(s, i), s)
    local heading = heading_call("Цифры здоровья")
    local boss, over = text_call("У босса"), text_call("Над врагами")
    eq(heading ~= nil and boss ~= nil and over ~= nil, true, "the heading and the labels")
    eq(boss.y > heading.y and over.y > boss.y, true, "in order")
    eq(line_at(boss.y), "У босса | ‹ | HP / макс. и % | ›", "all, by its short name")
    eq(line_at(over.y), "Над врагами | ‹ | HP / макс. и % | ›", "the same over enemies")
    eq(line_at(over.y + 20), "Моё здоровье и выносливость | вкл", "the player's numbers' switch, on")
    eq(line_at(over.y + 40), "Накопление статусов | вкл", "the buildup bars' switch, on")
    eq(line_at(over.y + 60), "Размер | ‹ | 100 % | ›", "the size under them, a percent")
    eq(help_drawn(), "Как показывать здоровье. Сейчас: «12 340 / 18 000 · 69%».", "the help shows the format")
    draw(state(s, i + 2), s)
    eq(help_drawn(), "Числа у твоих полос здоровья и выносливости: сейчас / предел, в скобках полный предел, "
        .. "когда он урезан.", "the player's numbers' help")
    draw(state(s, i), s)
    ui.press("dd2dm_snext:boss_hp_numbers")
    local a = draw(state(s, 1), s)
    eq(a.select, i, "› selects it"); eq(a.step, 1, "and steps it")
    s:set("boss_hp_numbers", "current")
    s:set("enemy_hp_numbers", "off")
    draw(state(s, i), s)
    eq(line_at(text_call("У босса").y), "У босса | ‹ | HP | ›", "another format")
    eq(line_at(text_call("Над врагами").y), "Над врагами | ‹ | выкл | ›", "off")
    eq(help_drawn(), "Как показывать здоровье. Сейчас: «12 340».", "its help")
    ui.press("dd2dm_sprev:enemy_hp_size")
    a = draw(state(s, i), s)
    eq(a.select, i + 4, "‹ selects the size"); eq(a.step, -1, "and steps it down")
    i18n.set("en")
    draw(state(s, i), s)
    eq(line_at(text_call("At the boss").y), "At the boss | ‹ | HP | ›", "in English")
    eq(heading_call("Health numbers") ~= nil, true, "its heading")
    i18n.set("ru")
    ui.drawing_ui = false
end)

test("draw never raises and stays balanced", function()
    local s = fresh()
    local st = state(s)
    st.model.groups[2].rows = 5 -- not a list
    local a, err = SettingsUI.draw(st, s)
    eq(type(err), "string", "the error comes back")
    eq(ui.balanced(), true, "balanced")
    eq(type(a), "table", "actions come back")
    -- a label that is not a text, while a smaller font size is pushed for the title
    st = state(s)
    st.model.title = {}
    ui.clear_calls()
    _, err = SettingsUI.draw(st, s)
    eq(type(err), "string", "a title that is not a text"); eq(ui.balanced(), true, "balanced")
    eq(#ui.calls_of("pop_font_size"), #ui.calls_of("push_font_size"), "every size popped")
    -- a help that is not a text, a table row without its cells
    st = state(s)
    st.model.groups[1].rows[1].help = {}
    ui.clear_calls()
    _, err = SettingsUI.draw(st, s)
    eq(type(err), "string", "a help that is not a text"); eq(ui.balanced(), true, "balanced")
    st = state(s)
    st.model.groups[2].rows[1].cells = nil
    ui.clear_calls()
    _, err = SettingsUI.draw(st, s)
    eq(type(err), "string", "a table row without cells"); eq(ui.balanced(), true, "balanced")
    ui.clear_calls()
    _, err = SettingsUI.draw(nil, s)
    eq(type(err), "string", "no state"); eq(ui.balanced(), true, "balanced")
    ui.clear_calls()
    _, err = SettingsUI.draw(state(s), nil)
    eq(type(err), "string", "no settings"); eq(ui.balanced(), true, "balanced")
    ui.clear_calls()
    _, err = SettingsUI.draw({ sel = 1 }, s)
    eq(type(err), "string", "no model"); eq(ui.balanced(), true, "balanced")
    -- the window cannot start
    local begin = imgui.begin_window
    imgui.begin_window = function() error("no window") end
    ui.clear_calls()
    _, err = SettingsUI.draw(state(s), s)
    imgui.begin_window = begin
    eq(err:find("no window", 1, true) ~= nil, true, "reported")
    eq(#ui.calls_of("end_window"), 0, "nothing to end")
    eq(ui.balanced(), true, "balanced")
    -- a click made before the failure is kept
    ui.drawing_ui = true
    ui.press("dd2dm_srow:style")
    st = state(s)
    st.model.groups[3].rows[1].label = {}
    ui.clear_calls()
    a, err = SettingsUI.draw(st, s)
    eq(type(err), "string", "failure further down")
    eq(a.select, 1, "the click is kept")
    a, err = SettingsUI.draw(state(s), s)
    eq(err, nil, "healthy again")
    ui.drawing_ui = false
end)

test("a window that cannot begin leaves no place or size for the next window", function()
    local s = fresh()
    -- push_style_color raises: nothing was given to imgui yet
    local push = imgui.push_style_color
    imgui.push_style_color = function() error("no colour") end
    local _, err = SettingsUI.draw(state(s), s)
    imgui.push_style_color = push
    eq(type(err), "string", "reported")
    eq(ui.find("set_next_window_pos"), nil, "no position given"); eq(ui.find("set_next_window_size"), nil, "no size")
    eq(ui.balanced(), true, "balanced")
    -- begin_window raises for this window: an empty window takes what was given, the next one gets nothing
    local begin = imgui.begin_window
    imgui.begin_window = function(name, ...)
        if name == WINDOW then error("no window") end
        return begin(name, ...)
    end
    ui.clear_calls()
    _, err = SettingsUI.draw(state(s), s)
    imgui.begin_window = begin
    eq(err:find("no window", 1, true) ~= nil, true, "reported")
    eq(ui.next_pos, nil, "no position left for the next window"); eq(ui.next_size, nil, "nor a size")
    local spare = ui.calls_of("begin_window")
    eq(#spare, 1, "one empty window took them")
    eq(spare[1][3] & NO_MOUSE_INPUTS, NO_MOUSE_INPUTS, "it takes no mouse")
    eq(#ui.calls_of("end_window"), 1, "and is ended")
    eq(ui.balanced(), true, "balanced")
end)

test("scale and font sizes come from the settings", function()
    local s = fresh({ scale = 1.5 })
    draw(state(s, index_of("style")), s)
    eq(ui.find("push_font_size")[1], 21, "14 px × 1.5")
    eq(text_call("Hidden Numbers · Настройки").px, 24, "title 16 × 1.5")
    eq(ui.find("set_next_window_size").w, 480, "the least, 320 × 1.5 (its rows measured 317 × 1.5)")
    eq(ui.find("set_next_window_size").h, math.min(DISPLAY_H - 32, CONTENT_H * 1.5), "its height × 1.5")
    eq(texts_in(C.mid)[1].px, 18, "the help 12 × 1.5")
    eq(text_call("Бой").px, 18, "the column names 12 × 1.5")
end)

i18n.set("en")
T.finish()
