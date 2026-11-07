package.path = "mod/reframework/autorun/?.lua;tests/?.lua;" .. package.path

local T = require("testlib")
local test, eq = T.test, T.eq
local ui = require("stubs/ui").install()
local i18n = require("DD2DamageMeter/i18n")
local Settings = require("DD2DamageMeter/settings")
local Fight = require("DD2DamageMeter/fight")
local View = require("DD2DamageMeter/view")
local Journal = require("DD2DamageMeter/journal")
local JournalUI = require("DD2DamageMeter/ui/journal")
local JournalTabs = require("DD2DamageMeter/journal_tabs")
local Kit = require("DD2DamageMeter/ui/kit")
local en = require("DD2DamageMeter/lang/en")
local ru = require("DD2DamageMeter/lang/ru")
local F = require("journal_fixture")

local C = Kit.COLORS

-- ImGuiWindowFlags (ImGui 1.92.0) and ImGuiCond_Always.
local FLAGS = { 1, 2, 4, 8, 16, 32, 128, 256, 4096, 8192 } -- always on
local NO_MOUSE_INPUTS, NO_NAV, ALWAYS_AUTO_RESIZE, COND_ALWAYS = 512, 196608, 64, 1
-- The window on the stub's 1920 x 1080 display at scale 1: 1 120 px wide, centred, its top at 7.5 % of the height
-- (where a window of 85 % would start), at most 918 high; the body starts 10 px in.
local WX, WY, WW, MAX_H = 400, 81, 1120, 918
local BX, BW = WX + 10, WW - 20

local function make_settings(over)
    local saved = over or {}
    return Settings.load({ read = function() return saved end, write = function(t) saved = t end })
end

local function fresh()
    ui.reset()
    JournalUI.reset()
    return make_settings()
end

-- The state of the journal on `tab` over the ogre fight (Russian), the second of 32 fights.
local function state(tab, body, page)
    local ctx = F.ctx("ru")
    return { tab = tab, header = Journal.header(F.snap, ctx, 2, 32), body = body, page = page or 1,
             hint = i18n.t("journal_hint", "F7") }
end

local function enemies_body(sel)
    return Journal.enemies(F.snap, F.ctx("ru"), sel or 1)
end

-- One frame; a drawing error fails the test, the stacks must balance.
local function draw(st, s)
    ui.clear_calls()
    local actions, err = JournalUI.draw(st, s)
    if err then error("draw failed: " .. err, 2) end
    eq(ui.balanced(), true, "stacks balanced")
    return actions
end

-- Two frames: the second has the window's height of what the first held.
local function settle(st, s)
    draw(st, s)
    return draw(st, s)
end

local function text_call(s)
    for _, c in ipairs(ui.calls) do
        if c.fn == "add_text" and c.text == s then return c end
    end
    return nil
end

-- The first text `s` drawn at font size px.
local function text_px(s, px)
    for _, c in ipairs(ui.calls) do
        if c.fn == "add_text" and c.text == s and math.abs(c.px - px) < 1e-9 then return c end
    end
    return nil
end

-- The first text `s` drawn in colour `col`.
local function text_in(s, col)
    for _, c in ipairs(ui.calls) do
        if c.fn == "add_text" and c.text == s and c.col == col then return c end
    end
    return nil
end

local function buttons()
    local list = {}
    for _, c in ipairs(ui.calls_of("invisible_button")) do list[#list + 1] = c.id end
    return list
end

local function has_button(id)
    for _, b in ipairs(buttons()) do
        if b == id then return true end
    end
    return false
end

local function rects_of(color)
    local list = {}
    for _, c in ipairs(ui.calls) do
        if c.fn == "add_rect_filled" and c.col == color then list[#list + 1] = c end
    end
    return list
end

-- A row's share: its colour at the fill's alpha.
local function faint(color)
    return (color & 0xFFFFFF) | (60 << 24)
end

-- The window's place and size of the last frame.
local function window()
    local pos, size = ui.find("set_next_window_pos"), ui.find("set_next_window_size")
    return pos.x, pos.y, size.w, size.h
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

test("the pager and hint texts", function()
    eq(ru.jpage, "стр. %d из %d", "ru.jpage")
    eq(en.jpage, "page %d of %d", "en.jpage")
    eq(ru.journal_hint, "%s закрыть · PgUp/PgDn вкладки · Home/End бои · Вверх/Вниз выбор · Влево/Вправо страницы",
        "ru.journal_hint")
    eq(en.journal_hint, "%s closes · PgUp/PgDn tabs · Home/End fights · Up/Down select · Left/Right pages",
        "en.journal_hint")
    eq(ru.journal_mouse, "мышь — с меню REFramework", "ru.journal_mouse")
    eq(en.journal_mouse, "mouse with the REFramework menu", "en.journal_mouse")
end)

test("a window 80 base font sizes wide, centred, its top edge where the largest window's is", function()
    local s = fresh()
    draw(state("enemies", enemies_body()), s)
    local size = ui.find("set_next_window_size")
    eq(size.w, WW, "1 120 px: 80 times 14"); eq(size.cond, COND_ALWAYS, "set every frame")
    eq(size.h, MAX_H, "the first frame knows no content yet: the largest window")
    local pos = ui.find("set_next_window_pos")
    eq(pos.x, WX, "centred"); eq(pos.y, WY, "the top of an 85 % window"); eq(pos[2], COND_ALWAYS, "pos every frame")
    local flags = ui.find("begin_window")[3]
    for _, f in ipairs(FLAGS) do eq(flags & f, f, "flag " .. f) end
    eq(flags & ALWAYS_AUTO_RESIZE, 0, "a fixed size")
    eq(#JournalUI.missing(), 0, "nothing missing")
    -- the panel behind it: the journal's dark colour over the whole window, nearly opaque, a 1 px edge
    local panel = rects_of(C.panel)[1]
    eq(panel.layer, "background", "under every window")
    eq(C.panel >> 24, 250, "alpha 250")
    eq(panel.x0, WX, "panel x0"); eq(panel.y0, WY, "panel y0"); eq(panel.x1, WX + WW, "panel x1")
    eq(panel.y1, WY + MAX_H, "panel y1")
    eq(#rects_of(C.border) >= 4, true, "the edge")
    -- every tab and every fight: the same top, the same width
    for _, tab in ipairs({ "summary", "enemies", "skills", "party", "heal", "chart", "record" }) do
        draw(state(tab, nil), s)
        local x, y, w = window()
        eq(x, WX, tab .. ": x"); eq(y, WY, tab .. ": top"); eq(w, WW, tab .. ": width")
        eq(text_call("Сводка").y, WY + 6 + 5, tab .. ": the tabs where they were")
    end
    -- wider at a larger scale, up to the display minus 32 px
    s:set("scale", 1.5)
    draw(state("enemies", enemies_body()), s)
    eq(ui.find("set_next_window_size").w, 1680, "1 120 times 1.5"); eq(ui.find("set_next_window_pos").x, 120, "centred")
    s:set("scale", 2)
    draw(state("enemies", enemies_body()), s)
    eq(ui.find("set_next_window_size").w, 1888, "at most the display minus 32")
    eq(ui.find("set_next_window_pos").x, 16, "16 px from each side")
    eq(ui.find("set_next_window_pos").y, WY, "the top does not move with the scale")
    -- a small screen: at most the display minus 32 px either way
    s:set("scale", 1)
    ui.display = { x = 200, y = 100 }
    draw(state("enemies", enemies_body()), s)
    size = ui.find("set_next_window_size")
    eq(size.w, 168, "small width"); eq(size.h, 68, "small height")
    pos = ui.find("set_next_window_pos")
    eq(pos.x, 16, "small x"); eq(pos.y, 16, "small y")
end)

test("the window's height follows what it holds, one frame late, at least the header's, at most 85 %", function()
    local s = fresh()
    -- the enemies tab of the ogre fight: shorter than the largest window
    local st = state("enemies", enemies_body())
    draw(st, s)
    local hint = text_call(i18n.t("journal_hint", "F7"))
    local content = math.ceil(hint.y - (22 - 12) / 2 + 22 + 4 - WY)
    eq(content < MAX_H, true, "the content is shorter: " .. content)
    draw(st, s)
    local x, y, w, h = window()
    eq(h, content, "the next frame's window as tall as it")
    eq(x, WX, "x"); eq(y, WY, "the top stays"); eq(w, WW, "width")
    local panel = rects_of(C.panel)[1]
    eq(panel.y1, WY + h, "the panel as tall as the window")
    eq(text_call(i18n.t("journal_hint", "F7")).y < WY + h, true, "the hint inside it")
    -- the header only (no fight): the least height still holds the tabs, the line, a row of numbers and the hint
    local least = math.ceil((6 + 24 + 32 + 52 + 8 + 6 + 22 + 4) + 1 + 1)
    settle({ tab = "enemies", header = Journal.header(nil, F.ctx("ru"), 1, 0), page = 1, hint = "F7" }, s)
    eq(select(4, window()), least, "the least height: " .. least)
    hint = text_call("F7")
    eq(hint.y > WY + least - 26 and hint.y < WY + least, true, "the hint at its bottom")
    -- a body taller than the room: the largest window, and pages
    local rows = {}
    for i = 1, 2000 do
        rows[i] = { time = "0:00", who = "W", whom = "V", what = "Event " .. i, amount = tostring(i), heal = false,
                    kill = false }
    end
    local long = state("record", { rows = rows })
    local a = draw(long, s)
    eq(select(4, window()), least, "one frame late: still the last height")
    a = draw(long, s)
    eq(select(4, window()), MAX_H, "then at most 85 % of the display")
    eq(a.pages > 1, true, "the rest pages")
    eq(text_call(i18n.t("jpage", 1, a.pages)) ~= nil, true, "the pager")
    -- the last page holds fewer rows: the window follows that page
    settle(state("record", { rows = rows }, a.pages), s)
    eq(select(4, window()) < MAX_H, true, "the last page's window is shorter")
    eq(select(2, window()), WY, "the top still there")
    -- a reset forgets the height
    JournalUI.reset()
    draw(st, s)
    eq(select(4, window()), MAX_H, "after a reset: the largest window again")
end)

test("the display size missing: 1280 × 720 and listed", function()
    local s = fresh()
    local get = imgui.get_display_size
    imgui.get_display_size = nil
    draw(state("enemies", enemies_body()), s)
    imgui.get_display_size = get
    local size = ui.find("set_next_window_size")
    eq(size.w, 1120, "width"); eq(size.h, 612, "the largest window: 85 % of 720")
    local pos = ui.find("set_next_window_pos")
    eq(pos.x, 80, "x"); eq(pos.y, 54, "y")
    eq(T.str(JournalUI.missing()), "get_display_size", "listed")
    local list = JournalUI.missing()
    list[1] = "changed"
    eq(JournalUI.missing()[1], "get_display_size", "a copy")
    JournalUI.reset()
    eq(#JournalUI.missing(), 0, "forgotten by a reset")
    -- a call that raises counts as missing too
    imgui.get_display_size = function() error("no display") end
    draw(state("enemies", enemies_body()), s)
    imgui.get_display_size = get
    eq(ui.find("set_next_window_size").w, 1120, "fallback")
    eq(T.str(JournalUI.missing()), "get_display_size", "listed")
end)

test("the window size call missing: the window takes its size from its content, listed", function()
    local s = fresh()
    local set = imgui.set_next_window_size
    imgui.set_next_window_size = nil
    draw(state("enemies", enemies_body()), s)
    imgui.set_next_window_size = set
    local flags = ui.find("begin_window")[3]
    eq(flags & ALWAYS_AUTO_RESIZE, ALWAYS_AUTO_RESIZE, "auto resize")
    local last = ui.calls_of("item_size")
    last = last[#last]
    eq(last ~= nil, true, "the content is declared")
    eq(last[2][1] - last[1][1] >= WW - 16, true, "as wide as the window")
    eq(last[2][2] - last[1][2] >= MAX_H - 16, true, "as tall as the window")
    eq(T.str(JournalUI.missing()), "set_next_window_size", "listed")
end)

test("no mouse input while the REFramework menu is closed", function()
    local s = fresh()
    draw(state("enemies", enemies_body()), s)
    local flags = ui.find("begin_window")[3]
    eq(flags & NO_MOUSE_INPUTS, NO_MOUSE_INPUTS, "no mouse input")
    eq(flags & NO_NAV, NO_NAV, "no keyboard navigation")
    eq(#buttons(), 0, "no buttons")
    ui.drawing_ui = true
    draw(state("enemies", enemies_body()), s)
    flags = ui.find("begin_window")[3]
    eq(flags & NO_MOUSE_INPUTS, 0, "the mouse works with the menu open")
    eq(flags & NO_NAV, 0, "nav flags off")
    eq(#buttons() > 0, true, "buttons")
end)

test("seven tabs, the active one marked, a click returns its id", function()
    local s = fresh()
    draw(state("enemies", enemies_body()), s)
    for _, id in ipairs(Journal.TABS) do
        local c = text_px(i18n.t("jtab_" .. id), 14)
        eq(c ~= nil, true, "tab " .. id)
        eq(c.col, id == "enemies" and C.text or C.dim, "text colour of " .. id)
    end
    eq(text_px("Получено", 14).y, text_px("Сводка", 14).y, "the party's tab is «Получено»")
    eq(#rects_of(C.tab_on), 1, "one active tab")
    eq(#rects_of(C.tab), 6, "six others")
    local on = rects_of(C.tab_on)[1]
    local title = text_call("Враги")
    eq(title.x > on.x0 and title.x < on.x1, true, "the active tab is «Враги»")
    eq(#rects_of(C.bronze) >= 1, true, "a bronze line under the row")
    eq(#buttons(), 0, "no buttons with the menu closed")

    ui.drawing_ui = true
    ui.press("jtab:skills")
    local a = draw(state("enemies", enemies_body()), s)
    eq(a.tab, "skills", "a click returns the tab's id")
    for _, id in ipairs(Journal.TABS) do eq(has_button("jtab:" .. id), true, "button " .. id) end
    a = draw(state("enemies", enemies_body()), s)
    eq(a.tab, nil, "no click, no tab")
end)

test("the fight's line at 17 px, its pager right after it, the five numbers large on one line", function()
    local s = fresh()
    draw(state("enemies", enemies_body()), s)
    local line = text_call("Победа · 4:15 · Огр, Ящер ×2")
    eq(line ~= nil, true, "the fight line")
    eq(line.px, 17, "at 17 px"); eq(line.x, BX, "at the left")
    local line_end = line.x + utf8.len(line.text) * ui.char_w * 17 / 14
    local prev, counter, nxt = text_call("‹"), text_call("бой 2 из 32"), text_call("›")
    eq(prev ~= nil and counter ~= nil and nxt ~= nil, true, "‹ бой 2 из 32 ›")
    eq(math.abs(prev.x - line_end - 12) < 1e-9, true, "12 px after the line: " .. (prev.x - line_end))
    eq(counter.x > prev.x and nxt.x > counter.x, true, "in that order")
    eq(nxt.x < BX + BW / 2, true, "not at the right edge")
    eq(text_call("×"), nil, "no close glyph with the menu closed")
    local want = {
        { "Нанесено", "82 500", C.block.damage.title }, { "Урон в секунду", "324", C.text },
        { "Получено", "700", C.block.enemies.title }, { "Вылечено", "231", C.block.heal.title },
        { "Срезано защитой врагов", "—", C.text },
    }
    local last_x, value_y = -1, nil
    for _, w in ipairs(want) do
        local label, value = text_px(w[1], 12), text_px(w[2], 22)
        eq(label ~= nil, true, "label " .. w[1])
        eq(label.col, C.dim, "dim label " .. w[1])
        eq(value ~= nil, true, "value " .. w[2] .. " at 22 px")
        eq(value.col, w[3], "value colour " .. w[2])
        eq(label.x > last_x, true, "cards left to right")
        value_y = value_y or value.y
        eq(value.y, value_y, "every value on one line")
        last_x = label.x
    end
    eq(#rects_of(C.card), 5, "five cards")
    local card = rects_of(C.card)[1]
    eq(card.y1 - card.y0, 52, "one line of labels: 52 px")
    eq(math.abs(value_y + 22 + 6 - card.y1) < 1e-9, true, "the values at the bottom of their cards")
    -- no fight: the line alone
    local ctx = F.ctx("ru")
    draw({ tab = "enemies", header = Journal.header(nil, ctx, 1, 0), page = 1 }, s)
    eq(text_call("Боёв пока нет") ~= nil, true, "no fights")
    eq(#rects_of(C.card), 0, "no cards")
    eq(text_call("‹"), nil, "no history arrows")
end)

test("a label too long for its card takes two lines; the values stay on one line at the bottom", function()
    local s = fresh()
    ui.display = { x = 900, y = 1080 } -- cards of 162 px: «Срезано защитой врагов» needs 132 + 16 at 12 px, not here
    local st = state("enemies", enemies_body())
    st.header.numbers[5].label = "Срезано защитой врагов очень длинно"
    draw(st, s)
    local first, second = text_px("Срезано защитой врагов", 12), text_px("очень длинно", 12)
    eq(first ~= nil and second ~= nil, true, "two lines")
    eq(second.y > first.y and second.x == first.x, true, "the second under the first")
    local card = rects_of(C.card)[1]
    eq(card.y1 - card.y0, 66, "two lines of labels: 66 px")
    local y
    for _, v in ipairs({ "82 500", "324", "700", "231", "—" }) do
        local c = text_px(v, 22)
        y = y or c.y
        eq(c.y, y, "one line: " .. v)
    end
    eq(math.abs(y + 22 + 6 - card.y1) < 1e-9, true, "at the bottom")
end)

test("history arrows and close", function()
    local s = fresh()
    ui.drawing_ui = true
    ui.press("jhist_prev")
    local a = draw(state("enemies", enemies_body()), s)
    eq(a.history, -1, "newer fight")
    ui.press("jhist_next")
    a = draw(state("enemies", enemies_body()), s)
    eq(a.history, 1, "older fight")
    eq(a.close, false, "not closed")
    ui.press("jclose")
    a = draw(state("enemies", enemies_body()), s)
    eq(a.close, true, "closed")
    eq(a.history, 0, "no history change")
    local close = text_call("×")
    eq(close ~= nil, true, "the close glyph")
    eq(close.x > BX + BW - 24, true, "at the right edge")
    ui.drawing_ui = false
    ui.press("jclose")
    a = draw(state("enemies", enemies_body()), s)
    eq(a.close, false, "menu closed: no button")
    eq(#buttons(), 0, "no buttons at all")
    ui.pressed = {}
end)

-- The 1 px-inset share fills of `color` (alpha 60) and their 3 px marks, by row.
local function fills_of(color)
    return rects_of(faint(color)), rects_of(color)
end

test("summary tab: damage filled in each fighter's colour, enemies and armor on the right", function()
    local s = fresh()
    local f = F.build()
    F.hit(f, 80, F.GUTS, F.LIZ2, 7200, 7150, { before = 100, after = 50 })
    local snap = f:snapshot(255, true)
    local body = View.summary(snap, F.ctx("ru"))
    draw(state("summary", body), s)
    for _, t in ipairs({ "Нанесено", "Torinald", "Guts", "Leo", "Враги", "Огр", "Ящер ×2", "Броня",
                         "Срезано защитой врагов" }) do
        eq(text_call(t) ~= nil, true, "drawn: " .. t)
    end
    local tori = text_call("Torinald")
    eq(tori.px, 16, "16 px names")
    eq(tori.col, Kit.actor_text("pawn", 4, 1), "in his colour")
    eq(text_call("Leo").col, C.dim, "an ally is grey")
    eq(text_call("Огр").col, C.dim, "a killed enemy is dim")
    eq(text_call("Ящер ×2").col, C.enemy_label, "a living one light purple")
    local numbers = text_call(body.damage.rows[1].value .. " · " .. body.damage.rows[1].share)
    eq(numbers ~= nil, true, "value · share")
    eq(numbers.y, tori.y, "on the name's line")
    -- the damage on the left 56 %, the enemies and the armor on the right (the tab «Враги» and the number card
    -- «Срезано защитой врагов» are not these)
    local mid = BX + BW * 0.56
    local function right_side(t)
        for _, c in ipairs(ui.calls) do
            if c.fn == "add_text" and c.text == t and c.x > mid and c.y > WY + 120 then return c end
        end
        return nil
    end
    eq(tori.x < mid, true, "damage on the left")
    eq(text_call("Нанесено").x < mid, true, "the damage band on the left")
    eq(right_side("Враги") ~= nil, true, "the enemies band on the right")
    eq(right_side("Враги").col, C.block.enemies.title, "in the enemies' colour")
    eq(text_call("Огр").x > mid, true, "enemies on the right")
    eq(right_side("Броня") ~= nil, true, "armor on the right")
    eq(body.armor[1].label, "Срезано защитой врагов", "the armor row of the fixture")
    eq(right_side("Срезано защитой врагов") ~= nil, true, "its label")
    eq(right_side(body.armor[1].value) ~= nil, true, "its value " .. body.armor[1].value)
    -- Torinald's row filled to his share in the thief's colour, a 3 px mark at its left, no line under it
    local fill, mark = fills_of(Kit.actor_color("pawn", 4, 1))
    eq(#fill, 1, "his fill"); eq(#mark, 1, "and its mark")
    eq(fill[1].x0, BX, "from the row's left"); eq(fill[1].x1, BX + math.floor(BW * 0.56), "his row is the biggest")
    eq(fill[1].y0 <= tori.y and fill[1].y1 >= tori.y + 16, true, "behind his name")
    eq(fill[1].y1 - fill[1].y0, 26, "the row less 1 px above and below")
    eq(mark[1].x1 - mark[1].x0, 3, "a 3 px mark"); eq(mark[1].y0, fill[1].y0, "as high")
    local guts = body.damage.rows[2]
    local gfill = fills_of(Kit.actor_color("player", 2, 1))[1]
    eq(math.abs((gfill.x1 - gfill.x0) - math.floor(BW * 0.56) * guts.fill) < 1e-9, true, "Guts' share of the top row")
    eq(#fills_of(C.ally) >= 1, true, "Leo's grey fill")
    for _, r in ipairs(ui.calls_of("add_rect_filled")) do
        if r.col == Kit.actor_color("pawn", 4, 1) then eq(r.y1 - r.y0 > 4, true, "no thin line under the row") end
    end
end)

test("enemies tab: the list and the main column at the top, who dealt what and whom it hit across the body", function()
    local s = fresh()
    draw(state("enemies", enemies_body(1)), s)
    for _, t in ipairs({ "Враги · 3", "Огр", "Ящер ×2", "Что говорит игра", "Чем его били", "Кто чем нанёс",
                         "Кого бил сам", "×1,5", "хорошо", "Torinald", " · Вор", " · Лучник", "Дождь стрел",
                         " · Огонь", " · Дробящий ×5, Огонь ×1", "Защита 250 · Маг. защита 180", "Уязвим:", "Дробящий",
                         "Свет", "Устойчив:", "Лёд", "Не действует:", "Сон" }) do
        eq(text_call(t) ~= nil, true, "drawn: " .. t)
    end
    -- the list, 130 px wide: the title light purple, killed names dim with «убит», the selected row marked
    local list_right = BX + 130
    eq(text_call("Враги · 3").col, C.enemy_label, "list title")
    eq(text_call("Враги · 3").x < list_right, true, "in the list")
    local ogre = text_call("Огр")
    eq(ogre.col, C.dim, "a killed enemy dim")
    eq(text_call("Ящер ×2").col, C.enemy_label, "a living kind light purple")
    eq(text_call("75 000 HP").col, C.dim, "hp text dim")
    local killed = text_call("убит")
    eq(killed ~= nil and killed.y == text_call("75 000 HP").y, true, "«убит» on the HP line")
    eq(killed.x < list_right, true, "inside the list")
    local marks = {}
    for _, r in ipairs(rects_of(C.enemy)) do
        if math.abs((r.x1 - r.x0) - 3) < 1e-9 and math.abs((r.y1 - r.y0) - 38) < 1e-9 then marks[#marks + 1] = r end
    end
    eq(#marks, 1, "one 3 px mark on a list row")
    eq(marks[1].y0 <= ogre.y and marks[1].y1 > ogre.y, true, "on the selected row")
    local member
    for _, c in ipairs(ui.calls) do
        if c.fn == "add_text" and c.text == "Ящер" then member = c; break end
    end
    eq(member.x > text_call("Ящер ×2").x, true, "member indented")
    -- the main column right of the list: the title 16 px light purple, its sub with the killer in his colour
    local title = text_px("Огр", 16)
    eq(title ~= nil and title.col == C.enemy_label, true, "card title at 16 px, light purple")
    eq(title.x > list_right, true, "right of the list")
    local sub = text_call("75 000 HP · убит на 4:12 · добил ")
    eq(sub ~= nil and sub.col == C.dim, true, "the sub dim")
    local killer = text_in("Torinald", Kit.actor_text("pawn", 4, 1))
    eq(killer ~= nil and killer.y == sub.y and killer.x > sub.x, true, "who finished it in his colour")
    local game, types = text_call("Что говорит игра"), text_call("Чем его били")
    eq(game.x > list_right and game.x < types.x, true, "two columns in the main column")
    eq(game.y, types.y, "side by side")
    eq(text_call("×1,5").col, C.ok, "×1,5 in ok"); eq(text_call("хорошо").col, C.ok, "its word too")
    -- who dealt what and whom it hit: under the list, across the whole body
    local list_bottom = WY + 0
    for _, c in ipairs(ui.calls) do
        if c.fn == "add_text" and c.text == "Ящер" and c.y > list_bottom then list_bottom = c.y end
    end
    local who, whom = text_call("Кто чем нанёс"), text_call("Кого бил сам")
    eq(who.x < list_right, true, "who dealt what under the list too")
    eq(who.y > list_bottom + 20, true, "below the list's last row")
    eq(whom.y > who.y and whom.x == who.x, true, "then whom it hit")
    eq(text_call("Guts · Дробящий ×5, Огонь ×1"), nil, "whom it hit: the name and the types apart")
    local victim = text_in("Guts", Kit.actor_text("player", 2, 1))
    for _, c in ipairs(ui.calls) do
        if c.fn == "add_text" and c.text == "Guts" and c.y > whom.y then victim = c end
    end
    eq(victim.col, Kit.actor_text("player", 2, 1), "the friend hit in his colour")
    eq(text_call(" · Дробящий ×5, Огонь ×1").col, C.dim, "the types dim")
    local afill = fills_of(Kit.actor_color("player", 2, 1))
    eq(#afill >= 1, true, "filled in his colour")
    eq(afill[#afill].x0, BX, "across the body"); eq(afill[#afill].x1, BX + BW, "the top row of its list")

    ui.drawing_ui = true
    ui.press("jrow:3")
    local a = draw(state("enemies", enemies_body(1)), s)
    eq(a.select, 3, "a click on a row selects it")
    eq(has_button("jrow:4"), true, "every row is a button")
    -- a resisted type is shown as bad
    ui.drawing_ui = false
    draw(state("enemies", enemies_body(4)), s)
    eq(text_call("×0,4").col, C.bad, "resist in bad")
    eq(text_call("плохо").col, C.bad, "its word")
    -- the head and body line under the types, dim
    local f = F.build()
    F.hit(f, 80, F.TORI, F.LIZ2, 7200, 7100, { skill = F.NORMAL, region = F.region({ Slash = 100 }, { Slash = 140 }, "head") })
    F.hit(f, 81, F.TORI, F.LIZ2, 7100, 7000, { skill = F.NORMAL, region = F.region({ Slash = 100 }, { Slash = 100 }, "body") })
    draw(state("enemies", Journal.enemies(f:snapshot(255, true), F.ctx("ru"), 4)), s)
    local parts = text_call("Режущий: голова ×1,4 · туловище ×1,0")
    eq(parts ~= nil, true, "drawn: the head and body line")
    eq(parts.col, C.dim, "dim")
    eq(parts.y > text_call("Чем его били").y, true, "under the types' title")
end)

test("who dealt what: «Доля» and «Множ.» apart; fighter rows in their colour and filled, skill rows smaller", function()
    local s = fresh()
    draw(state("enemies", enemies_body(1)), s)
    local head = text_call("Навык · тип")
    eq(head.col, C.dim, "heading row dim")
    eq(line_at(head.y), "Навык · тип | Ударов | Урон | Доля | Средний | Макс. | Множ.", "the columns")
    eq(text_call("Эффект"), nil, "no effect column")
    -- Torinald's row: his name in his colour at the base size, the vocation dim, his share; no average, max, mult
    local tori
    for _, c in ipairs(ui.calls) do
        if c.fn == "add_text" and c.text == "Torinald" and c.y > head.y then tori = c; break end
    end
    eq(tori.col, Kit.actor_text("pawn", 4, 1), "in his colour"); eq(tori.px, 14, "the base size")
    eq(line_at(tori.y), "Torinald |  · Вор | 2 | 73 800 | 98%", "name, vocation, hits, damage, share")
    eq(text_call(" · Вор").col, C.dim, "the vocation dim")
    -- filled to his share of the biggest dealer (his own), across the body, no line under it
    local fill, mark = fills_of(Kit.actor_color("pawn", 4, 1))
    local row_fill
    for _, r in ipairs(fill) do if r.y0 < tori.y and r.y1 > tori.y then row_fill = r end end
    eq(row_fill ~= nil, true, "a fill behind his row")
    eq(row_fill.x0, BX, "from the body's left"); eq(row_fill.x1, BX + BW, "the biggest dealer: the whole row")
    eq(#mark >= 1 and mark[1].x1 - mark[1].x0 == 3, true, "a 3 px mark")
    -- his skill: 13 px, C.mid, 16 px further in, the type dim, the multiplier in its own column
    local skill
    for _, c in ipairs(ui.calls) do
        if c.fn == "add_text" and c.text == "Обычные атаки" and c.y > tori.y then skill = c; break end
    end
    eq(skill.px, 13, "one step smaller"); eq(skill.col, C.mid, "in C.mid")
    eq(skill.x - tori.x, 16, "indented 16 px")
    eq(line_at(skill.y), "Обычные атаки |  · Режущий | 2 | 73 800 | 98% | 36 900 | 72 800 | ×1,0", "its columns")
    eq(text_px(" · Режущий", 13).col, C.dim, "the type dim")
    eq(text_call("×1,0").col, C.mid, "×1,0 plain")
    -- Guts' arrows went in at ×1,4: above 1, good
    local arrows = text_call("Дождь стрел")
    eq(line_at(arrows.y), "Дождь стрел |  · Огонь | 1 | 700 | 1% | 700 | 700 | ×1,4", "Guts' skill")
    eq(text_call("×1,4").col, C.ok, "above ×1,0: ok")
    -- Leo, an ally: grey, filled grey, a share too
    local leo = text_call("Leo")
    eq(leo.col, C.dim, "grey"); eq(line_at(leo.y), "Leo | 1 | 500 | 1%", "his share")
    eq(#fills_of(C.ally) >= 1, true, "a grey fill")
    -- a multiplier below ×1,0 that the game's scale calls normal is bad as well
    local f = Fight.new(0)
    F.hit(f, 1, F.TORI, F.LIZ1, 7600, 7450, { skill = F.NORMAL, element = "Fire",
        region = F.region({ Slash = 100, Magic = 100 }, { Slash = 0, Magic = 150 }, "body") })
    draw(state("enemies", Journal.enemies(f:snapshot(10, true), F.ctx("ru"), 1)), s)
    eq(text_call("×0,75").col, C.bad, "×0,75 below 1: bad")
    eq(text_call("не действует").col, C.bad, "«не действует» kept, bad")
end)

test("a kind's members in two columns, killed first by time, the killer in his colour", function()
    local s = fresh()
    local function goblin(key)
        return { key = key, name = key, kind = "enemy", base_id = "ch221002_00", chara_id = 2210, max_hp = 8000 }
    end
    local f = Fight.new(0)
    F.hit(f, 1, F.TORI, goblin("g1"), 8000, 7000, { skill = F.NORMAL })
    F.hit(f, 2, F.GUTS, goblin("g3"), 8000, 0, { skill = F.NORMAL })
    F.hit(f, 18, F.TORI, goblin("g2"), 8000, 0, { skill = F.NORMAL })
    local body = Journal.enemies(f:snapshot(20, true), F.ctx("ru"), 1)
    draw(state("enemies", body), s)
    local first = text_call("0:02 · 8 000 HP · добил ")
    local second = text_call("0:18 · 8 000 HP · добил ")
    local third = text_px("7 000 / 8 000 HP", 13) -- the list has it too, at 12 px
    eq(first ~= nil and second ~= nil and third ~= nil, true, "a line each")
    eq(first.y, second.y, "two side by side"); eq(second.x > first.x, true, "the second to the right")
    eq(third.y > first.y and third.x == first.x, true, "the third under the first")
    eq(first.col, C.dim, "dim"); eq(first.px, 13, "13 px")
    local guts = text_in("Guts", Kit.actor_text("player", 2, 1))
    eq(guts ~= nil and guts.y == first.y and guts.x > first.x and guts.x < second.x, true, "Guts in his colour")
    eq(text_in("Torinald", Kit.actor_text("pawn", 4, 1)) ~= nil, true, "Torinald in his")
    local title = text_px("Ящер ×3", 16)
    eq(title ~= nil and first.y > title.y, true, "under the kind's title")
    -- a main column narrower than two lines of 280 px: one a line (scale 2 on 1300 px: 944 px, under 1 120)
    ui.display = { x = 1300, y = 1080 }
    s:set("scale", 2)
    draw(state("enemies", body), s)
    local a, b = text_call("0:02 · 8 000 HP · добил "), text_call("0:18 · 8 000 HP · добил ")
    eq(a ~= nil and b ~= nil and b.y > a.y and b.x == a.x, true, "one a line")
end)

test("the killer's name in a card's title line stays whole when ImGui rounds every width up", function()
    -- ImGui's CalcTextSize gives whole pixels, rounded up: two pieces can be 1 px wider than the text in one
    local base = imgui.calc_text_size
    for _, advance in ipairs({ 6.9, 7.3, 7.5 }) do
        local s = fresh()
        imgui.calc_text_size = function(t)
            local r = base(t)
            r.x = math.ceil((utf8.len(t) or #t) * advance * r.y / 14 - 1e-9)
            return r
        end
        local ok, err = pcall(draw, state("enemies", enemies_body(1)), s)
        imgui.calc_text_size = base
        if not ok then error(err, 0) end
        local name = text_in("Torinald", Kit.actor_text("pawn", 4, 1))
        local cut
        for _, c in ipairs(ui.calls) do
            if c.fn == "add_text" and c.px == 12 and c.text:find("^Torin") then cut = c.text end
        end
        eq(cut, "Torinald", advance .. " px a character: the name whole")
        eq(name ~= nil, true, advance .. ": in his colour")
        eq(text_call("75 000 HP · убит на 4:12 · добил ") ~= nil, true, advance .. ": the text before it whole")
    end
end)

test("the enemy list's rows per page do not follow the selection", function()
    local s = fresh()
    local f = Fight.new(0)
    for i = 1, 25 do
        local g = { key = string.format("g%02d", i), name = "g", kind = "enemy", base_id = "ch221002_00",
                    chara_id = 2210, max_hp = 8000 }
        F.hit(f, i, F.TORI, g, 8000, i % 2 == 0 and 0 or 7000, { skill = F.NORMAL })
    end
    local snap = f:snapshot(30, true)
    -- the kind row (its card lists the 25) and its first member (a short card): the same rows a page
    local function list_page(sel)
        draw(state("enemies", Journal.enemies(snap, F.ctx("ru"), sel)), s)
        for _, c in ipairs(ui.calls) do
            if c.fn == "add_text" and c.x < BX + 130 then
                local page, pages = c.text:match("^стр%. (%d+) из (%d+)$")
                if page then return tonumber(page), tonumber(pages) end
            end
        end
    end
    local p1, n1 = list_page(1)
    local p2, n2 = list_page(2)
    eq(n1 ~= nil and n2 ~= nil, true, "the list pages")
    eq(n2, n1, "as many pages with a member selected as with the kind: " .. tostring(n1) .. ", " .. tostring(n2))
    eq(p1, 1, "the kind on page 1"); eq(p2, 1, "its first member too")
    eq(text_call("Ящер ×25") ~= nil, true, "the kind row still shown")
end)

test("a narrow main column puts the game's block above the types", function()
    local s = fresh()
    ui.display = { x = 780, y = 1080 } -- a window of 748, its main column 586 px: under 600
    draw(state("enemies", enemies_body(1)), s)
    local game, types = text_call("Что говорит игра"), text_call("Чем его били")
    eq(game.x, types.x, "one column")
    eq(game.y < types.y, true, "the game's block first")
end)

test("«нет данных» for a card without data", function()
    local s = fresh()
    draw(state("enemies", enemies_body(2)), s)
    eq(text_call("нет данных") ~= nil, true, "no data")
    eq(text_call("нет данных").col, C.dim, "dim")
    eq(text_call("Уязвим:"), nil, "no tag lines")
    eq(text_call("Чем его били") ~= nil, true, "the measured blocks still show")
    eq(text_call("Режущий") ~= nil, true, "types")
    -- statuses not read: said dim, not as a tag
    local _, snap = F.build()
    snap.detail.kinds.c2300 = { weak = 130, resist = 32 }
    draw(state("enemies", Journal.enemies(snap, F.ctx("ru"), 1)), s)
    local nd = text_call("нет данных")
    eq(nd ~= nil and nd.col, C.dim, "immune unread: dim text")
    eq(#rects_of(C.tag.immune[1]), 0, "no immune tag")
    eq(#rects_of(C.tag.weak[1]), 2, "weak tags")
    -- a snapshot without detail: no data in every measured block
    local f = F.build()
    draw(state("enemies", Journal.enemies(f:snapshot(255), F.ctx("ru"), 1)), s)
    local n = 0
    for _, t in ipairs(ui.texts()) do if t == "нет данных" then n = n + 1 end end
    eq(n, 4, "game, types, who and attacks")
    -- an enemy that only hit the party: «Ударов не было»
    draw(state("enemies", enemies_body(2)), s)
    eq(text_call("Ударов не было") ~= nil, true, "the lizards hit nobody")
    -- an enemy hit only for 0 HP: «Урона не было» in what hit it and who dealt it, «Ударов не было» whom it hit
    f = Fight.new(0)
    F.hit(f, 1, F.GUTS, F.LIZ1, 7600, 7600, { skill = { id = "Job02_ThreefoldArrow" } })
    draw(state("enemies", Journal.enemies(f:snapshot(5, true), F.ctx("ru"), 1)), s)
    n = 0
    for _, t in ipairs(ui.texts()) do if t == "Урона не было" then n = n + 1 end end
    eq(n, 2, "types and who")
    eq(text_call("Ударов не было") ~= nil, true, "it hit nobody")
end)

test("a long card pages", function()
    local s = fresh()
    local body = enemies_body(1)
    local rows = {}
    for i = 1, 60 do
        rows[i] = { kind = "who", key = "d" .. i, name = "Dealer " .. i, actor_kind = "pawn", hits = "1", value = "100",
                    share = "1%", fill = 0.5, grey = false }
    end
    body.card.who.rows = rows
    local a = draw(state("enemies", body, 1), s)
    eq(a.pages >= 2, true, "pages: " .. tostring(a.pages))
    eq(text_call("Dealer 1") ~= nil, true, "page 1 starts")
    eq(text_call("Dealer 60"), nil, "the last row is not on page 1")
    eq(text_call(i18n.t("jpage", 1, a.pages)) ~= nil, true, "the pager")
    eq(text_call("Огр") ~= nil, true, "the list on page 1")
    local pages = a.pages
    a = draw(state("enemies", body, 2), s)
    eq(a.pages, pages, "same count")
    eq(text_call("Dealer 60") ~= nil, true, "page 2 draws a row page 1 did not")
    eq(text_call("Dealer 1"), nil, "not the first rows again")
    eq(text_call(i18n.t("jpage", 2, pages)) ~= nil, true, "pager on page 2")
    -- pager buttons with the menu open
    ui.drawing_ui = true
    ui.press("jpage_next")
    a = draw(state("enemies", body, 1), s)
    eq(a.page, 1, "next page")
    ui.press("jpage_prev")
    a = draw(state("enemies", body, 2), s)
    eq(a.page, -1, "previous page")
    -- a short card: one page, no pager
    a = draw(state("enemies", enemies_body(1)), s)
    eq(a.pages, 1, "one page")
    eq(has_button("jpage_next"), false, "no pager")
    -- a page past the end (the window got larger): the last page is drawn, from the next frame for a new body
    ui.drawing_ui = false
    local fresh_body = enemies_body(1)
    fresh_body.card.who.rows = rows
    local last_row = " · Дробящий ×5, Огонь ×1" -- the card's last block
    a = draw(state("enemies", fresh_body, 9), s)
    eq(a.pages, pages, "pages counted")
    eq(text_call(last_row), nil, "the first frame draws past the end")
    draw(state("enemies", fresh_body, 9), s)
    eq(text_call(i18n.t("jpage", pages, pages)) ~= nil, true, "the last page")
    eq(text_call(last_row) ~= nil, true, "and its rows")
end)

test("a long enemy list keeps the selection visible", function()
    local s = fresh()
    local body = enemies_body(1)
    local rows = {}
    for i = 1, 25 do
        rows[i] = { id = "e:g" .. i, label = "Гоблин " .. i, hp_text = "900 HP", fill = 0, killed = true, group = false,
                    member = false }
    end
    body.list = { title = "Враги · 25", rows = rows }
    body.sel = 25
    draw(state("enemies", body), s)
    eq(text_call("Гоблин 25") ~= nil, true, "the selected row is drawn")
    eq(text_call("Гоблин 1"), nil, "the first page is not")
    local title = text_call("Враги · 25")
    eq(title ~= nil, true, "the title on every page, whole")
    -- six rows a page, whichever is selected, and the page under them
    local page = text_call(i18n.t("jpage", 5, 5))
    eq(page ~= nil, true, "the list's page")
    eq(page.y > text_call("Гоблин 25").y and page.x < BX + 130, true, "under its rows")
    body.sel = 1
    draw(state("enemies", body), s)
    eq(text_call("Гоблин 1") ~= nil, true, "first page")
    eq(text_call("Гоблин 6") ~= nil, true, "six rows a page")
    eq(text_call("Гоблин 7"), nil, "the seventh on the next page")
    eq(text_call(i18n.t("jpage", 1, 5)) ~= nil, true, "page 1 of 5")
    ui.drawing_ui = true
    draw(state("enemies", body), s)
    eq(has_button("jrow:1"), true, "the rows shown are buttons")
    eq(has_button("jrow:25"), false, "the others are not")
end)

-- The texts of the last frame that end past `right` (the stub's widths: ui.char_w per character at 14 px).
local function texts_past(right)
    local list = {}
    for _, c in ipairs(ui.calls) do
        if c.fn == "add_text" and c.x + utf8.len(c.text) * ui.char_w * c.px / 14 > right + 1e-6 then
            list[#list + 1] = c.text
        end
    end
    return list
end

-- Every page of the ogre's card at a display and scale: the texts drawn (as a set), those past the body's right, and
-- whether the game's block and the types are side by side.
local function card_pages(dw, dh, scale)
    local s = fresh()
    s:set("scale", scale)
    ui.display = { x = dw, y = dh }
    local body = enemies_body(1)
    local pages = draw(state("enemies", body, 1), s).pages
    local right = ui.find("set_next_window_pos").x + ui.find("set_next_window_size").w - 10 * scale
    local drawn, past, game, types = {}, {}, nil, nil
    for page = 1, pages do
        draw(state("enemies", body, page), s)
        for _, t in ipairs(ui.texts()) do drawn[t] = true end
        for _, t in ipairs(texts_past(right)) do past[#past + 1] = t end
        game, types = game or text_call("Что говорит игра"), types or text_call("Чем его били")
    end
    return drawn, past, game.x < types.x
end

test("the card's numbers stay inside the body at any display and scale", function()
    -- the types, the who table's heading, shares and multipliers drawn whole and inside, in two columns
    for _, case in ipairs({ { 1920, 1080, 1.8 }, { 1280, 800, 1.25 }, { 1920, 1080, 1.75 }, { 1366, 768, 1.25 },
                            { 1024, 768, 1 } }) do
        local what = string.format("%dx%d at %.2f", case[1], case[2], case[3])
        local drawn, past, two = card_pages(case[1], case[2], case[3])
        eq(T.str(past), "", what .. ": texts past the body")
        eq(two, true, what .. ": two columns")
        for _, t in ipairs({ "Режущий", "Стрелковый", "74 300", "600", "100", "×1,5", "хорошо", "Навык · тип",
                             "Ударов", "Урон", "Доля", "Средний", "Макс.", "Множ.", "73 800", "36 900", "72 800", "98%",
                             "1%", "×1,4" }) do
            eq(drawn[t], true, what .. ": drawn whole: " .. t)
        end
    end
    -- one column, and the whole range of the scale on a large and a small screen: nothing past the body
    for _, d in ipairs({ { 1920, 1080 }, { 1280, 720 }, { 1024, 768 } }) do
        for _, scale in ipairs({ 0.6, 1, 1.25, 1.5, 1.8, 2 }) do
            local _, past = card_pages(d[1], d[2], scale)
            eq(T.str(past), "", string.format("%dx%d at %.2f: texts past the body", d[1], d[2], scale))
        end
    end
    local drawn, _, two = card_pages(1280, 720, 2)
    eq(two, false, "1280x720 at 2: one column")
    for _, t in ipairs({ "74 300", "600", "100", "×1,5", "хорошо", "98%", "1%", "×1,4", "Доля", "Множ." }) do
        eq(drawn[t], true, "1280x720 at 2: drawn whole: " .. t)
    end
end)

test("a narrow main column is laid out for its width", function()
    -- the narrowest main column of two columns (600 px at scale 1): the type rows fit their 290 px column with a bar
    local s = fresh()
    ui.display = { x = 794, y = 768 }
    draw(state("enemies", enemies_body(1)), s)
    local game, types = text_call("Что говорит игра"), text_call("Чем его били")
    eq(game.y == types.y and game.x < types.x, true, "two columns")
    local bars = {}
    for _, r in ipairs(rects_of(C.track)) do
        if math.abs((r.y1 - r.y0) - 8) < 1e-9 then bars[#bars + 1] = r end -- the type rows' bars (8 px high)
    end
    eq(#bars, 3, "a bar per type")
    for _, b in ipairs(bars) do
        eq(b.x0 > types.x, true, "in the types' column")
        eq(b.x1 - b.x0 >= 30 - 1e-9, true, "the bar keeps 30 px: " .. (b.x1 - b.x0))
    end
    eq(text_call("Стрелковый") ~= nil, true, "the longest type's name whole")
    -- one column at scale 2 on 1280 x 720: the who table's names keep room next to the numbers
    s = fresh()
    s:set("scale", 2)
    ui.display = { x = 1280, y = 720 }
    local body = enemies_body(1)
    local pages = draw(state("enemies", body, 1), s).pages
    local name
    for page = 1, pages do
        draw(state("enemies", body, page), s)
        for _, c in ipairs(ui.calls) do
            if c.fn == "add_text" and c.text:sub(1, 7) == "Torinal" then name = c.text end
        end
    end
    eq(name ~= nil, true, "the dealer's name readable")
end)

test("keys map to actions", function()
    eq(JournalUI.key_actions({ [0x22] = true }).tab_step, 1, "PgDn")
    eq(JournalUI.key_actions({ [0x21] = true }).tab_step, -1, "PgUp")
    eq(JournalUI.key_actions({ [0x24] = true }).history, -1, "Home")
    eq(JournalUI.key_actions({ [0x23] = true }).history, 1, "End")
    eq(JournalUI.key_actions({ [0x26] = true }).select_step, -1, "Up")
    eq(JournalUI.key_actions({ [0x28] = true }).select_step, 1, "Down")
    eq(JournalUI.key_actions({ [0x25] = true }).page, -1, "Left")
    eq(JournalUI.key_actions({ [0x27] = true }).page, 1, "Right")
    local a = JournalUI.key_actions({ [0x41] = true })
    eq(a.tab, nil, "A: no tab"); eq(a.tab_step, 0, "tab_step"); eq(a.history, 0, "history")
    eq(a.select, nil, "select"); eq(a.select_step, 0, "select_step"); eq(a.page, 0, "page")
    eq(a.close, false, "close")
    a = JournalUI.key_actions({ [0x21] = true, [0x22] = true, [0x28] = true })
    eq(a.tab_step, 0, "both tab keys cancel out"); eq(a.select_step, 1, "with Down")
    eq(JournalUI.key_actions({}).page, 0, "nothing pressed")
    local want = { [0x21] = { "tab_step", -1 }, [0x22] = { "tab_step", 1 }, [0x24] = { "history", -1 },
                   [0x23] = { "history", 1 }, [0x26] = { "select_step", -1 }, [0x28] = { "select_step", 1 },
                   [0x25] = { "page", -1 }, [0x27] = { "page", 1 } }
    local n = 0
    for vk, w in pairs(JournalUI.KEYS) do
        n = n + 1
        eq(w[1], want[vk][1], "field of " .. vk); eq(w[2], want[vk][2], "step of " .. vk)
    end
    eq(n, 8, "eight keys")
end)

test("a tab without a drawer says «нет данных»; no body draws the header only", function()
    local s = fresh()
    -- every journal tab has a drawer now: a tab id of none
    draw(state("no_such_tab", { rows = {} }), s)
    eq(text_call("нет данных") ~= nil, true, "no drawer")
    eq(text_call("Победа · 4:15 · Огр, Ящер ×2") ~= nil, true, "the header")
    local a = draw(state("enemies", nil), s)
    eq(a.pages, 1, "one page")
    eq(text_call("Что говорит игра"), nil, "no body")
    eq(text_call("нет данных"), nil, "nothing in its place")
    eq(text_call("Враги") ~= nil, true, "the tabs")
end)

test("the hint: C.mid 12 px at the bottom, where the mouse works at the right end", function()
    local s = fresh()
    settle(state("enemies", enemies_body()), s)
    local _, _, _, h = window()
    local hint = text_call(i18n.t("journal_hint", "F7"))
    eq(hint ~= nil, true, "drawn")
    eq(hint.col, C.mid, "C.mid, not dim"); eq(hint.px, 12, "12 px"); eq(hint.x, BX, "at the left")
    eq(hint.y > WY + h - 30 and hint.y < WY + h, true, "at the bottom")
    local mouse = text_call("мышь — с меню REFramework")
    eq(mouse ~= nil, true, "the mouse's hint")
    eq(mouse.y, hint.y, "on the hint's line"); eq(mouse.col, C.mid, "C.mid"); eq(mouse.px, 12, "12 px")
    eq(math.abs(mouse.x + utf8.len(mouse.text) * ui.char_w * 12 / 14 - (BX + BW)) < 1e-9, true, "at the right edge")
    for _, c in ipairs(ui.calls) do
        if c.fn == "add_text" and c ~= hint and c ~= mouse then eq(c.y < hint.y, true, "above the hint: " .. c.text) end
    end
    local st = state("enemies", enemies_body())
    i18n.set("en")
    draw(st, s)
    eq(text_call("mouse with the REFramework menu") ~= nil, true, "English")
    i18n.set("ru")
end)

test("scale comes from the settings", function()
    local s = fresh()
    s:set("scale", 1.5)
    draw(state("enemies", enemies_body()), s)
    eq(ui.find("push_font_size")[1], 21, "14 px times 1.5")
    eq(text_call("Победа · 4:15 · Огр, Ящер ×2").px, 25.5, "the fight line: 17 times 1.5")
    eq(text_px("82 500", 33) ~= nil, true, "the numbers: 22 times 1.5")
    eq(ui.find("set_next_window_size").w, 1680, "the window 1 120 times 1.5")
end)

test("draw never raises and stays balanced", function()
    local s = fresh()
    local body = enemies_body()
    body.list.rows = 5 -- not a list
    local a, err = JournalUI.draw(state("enemies", body), s)
    eq(type(err), "string", "the error comes back")
    eq(ui.balanced(), true, "balanced")
    eq(#ui.calls_of("end_window"), 1, "the window was ended")
    eq(a.pages, 1, "actions still come back")
    -- broken while a smaller font size is pushed
    body = enemies_body()
    body.card.sub = {}
    ui.clear_calls()
    _, err = JournalUI.draw(state("enemies", body), s)
    eq(type(err), "string", "a sub that is not a text")
    eq(ui.balanced(), true, "balanced")
    eq(#ui.calls_of("pop_font_size"), #ui.calls_of("push_font_size"), "every size popped")
    -- a broken summary, a broken header, no state, no settings
    local sm = View.summary(F.snap, F.ctx("ru"))
    sm.armor = 5
    ui.clear_calls()
    _, err = JournalUI.draw(state("summary", sm), s)
    eq(type(err), "string", "broken summary"); eq(ui.balanced(), true, "balanced")
    local st = state("enemies", enemies_body())
    st.header.numbers = 7
    ui.clear_calls()
    _, err = JournalUI.draw(st, s)
    eq(type(err), "string", "broken header"); eq(ui.balanced(), true, "balanced")
    ui.clear_calls()
    _, err = JournalUI.draw(nil, s)
    eq(type(err), "string", "no state"); eq(ui.balanced(), true, "balanced")
    ui.clear_calls()
    _, err = JournalUI.draw(state("enemies", enemies_body()), nil)
    eq(type(err), "string", "no settings"); eq(ui.balanced(), true, "balanced")
    -- the window cannot start: the border colour is popped, nothing to end
    local begin = imgui.begin_window
    imgui.begin_window = function() error("no window") end
    ui.clear_calls()
    _, err = JournalUI.draw(state("enemies", enemies_body()), s)
    imgui.begin_window = begin
    eq(err:find("no window", 1, true) ~= nil, true, "reported")
    eq(#ui.calls_of("end_window"), 0, "nothing to end")
    eq(ui.balanced(), true, "balanced")
    -- a click made before the failure is kept
    ui.drawing_ui = true
    ui.press("jtab:chart")
    body = enemies_body()
    body.card.attacks.rows = 5
    ui.clear_calls()
    a, err = JournalUI.draw(state("enemies", body), s)
    eq(type(err), "string", "failure in the card")
    eq(a.tab, "chart", "the tab click is kept")
    -- the next frame works
    a, err = JournalUI.draw(state("enemies", enemies_body()), s)
    eq(err, nil, "healthy again")
end)

local function skills_body(sel)
    return JournalTabs.skills(F.snap, F.ctx("ru"), sel or 1)
end

local function chart_body(sel)
    return JournalTabs.chart(F.chart, F.ctx("ru"), sel or 1)
end

test("skills tab: the choices by damage, the table filled in each fighter's colour, who in his colour", function()
    local s = fresh()
    draw(state("skills", skills_body(1)), s)
    -- the choices: a row like the tabs, the whole party marked, then the members by the damage they dealt
    local party = text_call("Вся группа")
    eq(party ~= nil, true, "the whole party")
    eq(line_at(party.y), "Вся группа | Torinald | Guts", "Torinald dealt the most")
    eq(party.col, C.text, "the active choice bright")
    eq(text_call("Guts").col, C.dim, "the others dim")
    eq(#rects_of(C.tab_on), 2, "the active tab and the active choice")
    eq(#rects_of(C.tab), 6 + 2, "the other tabs and choices")
    -- the heading, dim, then the rows; «Кто» right after the skill's name
    local head = text_call("Навык")
    eq(head ~= nil, true, "heading")
    eq(text_call("Навык · тип"), nil, "not the card's skill-and-type heading")
    eq(head.y > party.y, true, "under the choices")
    eq(line_at(head.y), "Навык | Кто | Ударов | Урон | Средний | Макс. | Урон/с | %", "the heading's columns")
    eq(text_call("Урон/с").col, C.dim, "dim")
    local row = text_call("Обычные атаки")
    eq(row.y > head.y, true, "rows under the heading")
    eq(line_at(row.y), "Обычные атаки | Torinald | 3 | 81 400 | 27 133 | 72 800 | 319 | 99%", "Torinald's row")
    local who = text_in("Torinald", Kit.actor_text("pawn", 4, 1))
    eq(who ~= nil and who.y == row.y, true, "who in his colour")
    eq(text_call("Дождь стрел").y > row.y, true, "value-descending")
    -- each row filled to its share of the top row in the member's colour, no line under it
    local fill, mark = fills_of(Kit.actor_color("pawn", 4, 1))
    eq(#fill, 1, "Torinald's row filled"); eq(#mark, 1, "its mark")
    eq(fill[1].y0 < row.y and fill[1].y1 > row.y, true, "behind his row")
    eq(fill[1].x1 - fill[1].x0, BW, "the top row: the whole width")
    eq(#fills_of(Kit.actor_color("player", 2, 1)), 2, "Guts' two rows in the archer's colour")
    for _, r in ipairs(ui.calls_of("add_rect_filled")) do
        if r.col == Kit.actor_color("pawn", 4, 1) then eq(r.y1 - r.y0 > 2, true, "no thin line") end
    end
    eq(#buttons(), 0, "no buttons with the menu closed")
    -- a click on a choice selects it
    ui.drawing_ui = true
    ui.press("jchoice:3")
    local a = draw(state("skills", skills_body(1)), s)
    eq(a.select, 3, "jchoice:3")
    eq(has_button("jchoice:1") and has_button("jchoice:2"), true, "every choice is a button")
    -- one member: no who column, his numbers
    ui.drawing_ui = false
    draw(state("skills", skills_body(2)), s)
    eq(text_call("Кто"), nil, "no who column")
    eq(text_call("Torinald").col, C.text, "Torinald marked")
    row = text_call("Обычные атаки")
    eq(line_at(row.y), "Обычные атаки | 3 | 81 400 | 27 133 | 72 800 | 319 | 100%", "his row")
    -- nobody dealt anything: «Ударов не было»
    draw(state("skills", JournalTabs.skills(nil, F.ctx("ru"), 1)), s)
    eq(text_call("Ударов не было") ~= nil, true, "no hits")
    eq(text_call("Вся группа") ~= nil, true, "the choice still there")
end)

test("a long skills table pages, the choices and the heading on every page", function()
    local s = fresh()
    local body = skills_body(1)
    local rows = {}
    for i = 1, 80 do
        rows[i] = { label = "Skill " .. i, who = "Guts", hits = "1", value = "10", avg = "10", max = "10", dps = "1",
                    share = "1%", fill = 0.5, kind = "player", job = 2, shade = 1 }
    end
    body.rows = rows
    local a = draw(state("skills", body, 1), s)
    eq(a.pages >= 2, true, "pages: " .. a.pages)
    eq(text_call("Skill 1") ~= nil, true, "page 1 starts")
    eq(text_call("Skill 80"), nil, "not the last row")
    a = draw(state("skills", body, a.pages), s)
    eq(text_call("Skill 80") ~= nil, true, "the last page has it")
    eq(text_call("Skill 1"), nil, "not the first")
    eq(text_call("Вся группа") ~= nil, true, "the choices")
    eq(text_call("Навык") ~= nil, true, "the heading")
end)

-- The chart's column parts (112 px wide rects) by column, left to right:
-- { { x0, top, bottom, height, parts = { { color, y0, y1 } } (bottom-up) } }.
local function chart_columns(width)
    width = width or 112
    local by_x, cols = {}, {}
    for _, r in ipairs(ui.calls_of("add_rect_filled")) do
        if math.abs(r.x1 - r.x0 - width) < 1e-6 and r.col ~= C.selected and r.col ~= C.hover and r.col ~= C.border then
            local col = by_x[r.x0]
            if not col then
                col = { x0 = r.x0, top = math.huge, bottom = -math.huge, parts = {} }
                by_x[r.x0] = col
                cols[#cols + 1] = col
            end
            col.top, col.bottom = math.min(col.top, r.y0), math.max(col.bottom, r.y1)
            col.parts[#col.parts + 1] = { r.col, r.y0, r.y1 }
        end
    end
    table.sort(cols, function(a, b) return a.x0 < b.x0 end)
    for _, col in ipairs(cols) do
        col.height = col.bottom - col.top
        table.sort(col.parts, function(a, b) return a[3] > b[3] end)
    end
    return cols
end

-- A colour's lightness: the sum of its red, green and blue.
local function lightness(c) return (c & 0xFF) + ((c >> 8) & 0xFF) + ((c >> 16) & 0xFF) end

-- The first text `s` drawn left of x.
local function text_left_of(s, x)
    for _, c in ipairs(ui.calls) do
        if c.fn == "add_text" and c.text == s and c.x < x then return c end
    end
    return nil
end

test("chart: a column per member by damage, its parts in shades of his colour, his list right next to it", function()
    local s = fresh()
    draw(state("chart", chart_body(1)), s)
    local cols = chart_columns()
    eq(#cols, 2, "two columns")
    local tori, guts = cols[1], cols[2]
    eq(tori.x0, BX, "left-aligned"); eq(guts.x0 - tori.x0, 112 + 12, "112 wide, 12 apart")
    T.near(tori.height, 220, 1e-9, "the tallest 220 px, its gaps included")
    eq(math.abs(guts.height / tori.height - 6100 / 9900) < 1e-9, true, "heights in proportion")
    eq(math.abs(guts.bottom - tori.bottom) < 1e-9, true, "on one base line")
    -- parts bottom-up, the largest first, 2 px of panel between two, in shades of the member's colour: the largest
    -- his colour a little darker, each next one lighter than the one under it
    local thief, archer = Kit.actor_color("pawn", 4, 1), Kit.actor_color("player", 2, 1)
    local want = { Kit.tint(thief, -0.08), Kit.tint(thief, 0.16), Kit.tint(thief, 0.34), Kit.tint(thief, 0.5) }
    for i, p in ipairs(tori.parts) do
        eq(p[1], want[i], "Torinald's part " .. i .. " in his shade")
        if i > 1 then
            T.near(tori.parts[i - 1][2] - p[3], 2, 1e-9, "2 px under part " .. i)
            eq(lightness(p[1]) > lightness(tori.parts[i - 1][1]), true, "part " .. i .. " lighter than the one under it")
        end
    end
    eq(#tori.parts, 4, "his four skills")
    eq(lightness(want[1]) < lightness(thief), true, "the largest a little darker than his colour")
    eq(guts.parts[1][1], Kit.tint(archer, -0.08), "Guts' largest in his colour a little darker")
    -- the gaps come out of the parts: a part's share of the column less its three gaps
    T.near((tori.parts[2][3] - tori.parts[2][2]) / (tori.height - 3 * 2), 3500 / 9900, 1e-9, "a part's share")
    -- a part 34 px or more names its skill and value inside, in the colour that reads on it
    local name = text_call("Обычные атаки")
    eq(name ~= nil and name.x > tori.x0 and name.x < tori.x0 + 112, true, "the largest part names its skill")
    eq(name.col, Kit.on_color(want[1]), "dark or light by the part's lightness"); eq(name.px, 12, "12 px")
    local value = text_call("4 000")
    eq(value ~= nil and value.y > name.y and value.x == name.x, true, "its value under it")
    eq(text_left_of("400", BX + 200), nil, "a part under 34 px names nothing")
    -- totals above, names under in their colour; the selected column on a lighter ground
    local right = BX + 2 * 112 + 12
    local tname, gname = text_left_of("Torinald", right), text_left_of("Guts", right)
    eq(tname ~= nil and gname ~= nil, true, "names drawn")
    eq(tname.y >= tori.bottom, true, "the name under the column")
    eq(tname.col, Kit.actor_text("pawn", 4, 1), "in his colour"); eq(gname.col, Kit.actor_text("player", 2, 1), "his")
    local ttotal, gtotal = text_left_of("9 900", right), text_left_of("6 100", right)
    eq(ttotal ~= nil and gtotal ~= nil, true, "totals drawn")
    eq(ttotal.y < tori.top and gtotal.y < guts.top, true, "above the columns")
    eq(ttotal.col, C.text, "the selected one's total bright"); eq(gtotal.col, C.mid, "the other's C.mid")
    eq(#rects_of(C.selected), 1, "the selected column's ground")
    -- right next to the columns: Torinald's band and his skills with their parts' swatches; no legend
    local list_x = right + 24
    local band = text_in("Torinald", Kit.actor_text("pawn", 4, 1))
    for _, c in ipairs(ui.calls) do
        if c.fn == "add_text" and c.text == "Torinald" and c.x >= list_x then band = c end
    end
    eq(band.x >= list_x and band.x < list_x + 20, true, "his band right next to the columns")
    for i, t in ipairs({ "Перерезать горло", "Кража", "Тень" }) do
        local c
        for _, d in ipairs(ui.calls) do
            if d.fn == "add_text" and d.text == t and d.x >= list_x then c = d end -- the columns name some inside
        end
        eq(c ~= nil, true, "listed: " .. t)
        eq(c.col, C.mid, "C.mid"); eq(c.px, 13, "13 px")
        local swatch
        for _, r in ipairs(rects_of(want[i + 1])) do
            if math.abs(r.x1 - r.x0 - 10) < 1e-6 and r.y0 <= c.y + 13 and r.y1 >= c.y then swatch = r end
        end
        eq(swatch ~= nil, true, "a swatch in its part's shade: " .. t)
    end
    eq(text_call("4 000 · 40%") ~= nil, true, "value · share of his total")
    local function listed(t)
        for _, c in ipairs(ui.calls) do
            if c.fn == "add_text" and c.text == t and c.x >= list_x then return c end
        end
        return nil
    end
    eq(text_call("Остальное"), nil, "no legend")
    eq(listed("Дождь стрел"), nil, "Guts' skills are not listed")
    eq(#buttons(), 0, "no buttons with the menu closed")
    -- a click on a column selects it; Up and Down do the same (the select_step keys)
    ui.drawing_ui = true
    ui.press("jbar:2")
    local a = draw(state("chart", chart_body(1)), s)
    eq(a.select, 2, "jbar:2")
    eq(has_button("jbar:1"), true, "every column is a button")
    ui.drawing_ui = false
    draw(state("chart", chart_body(2)), s)
    eq(text_left_of("6 100", right).col, C.text, "the second selected")
    eq(listed("Дождь стрел") ~= nil, true, "his skills listed")
end)

test("chart: the rest the darkest; the columns stay in their area on a small screen; nothing to chart says so", function()
    local s = fresh()
    local f = Fight.new(0)
    local hp = F.OGRE.max_hp
    for i, id in ipairs({ "Job02_ThreefoldArrow", "Job02_Explosive", "Job03_Frigor", "Job04_Cutthroat",
                          "Job04_Pilfer", "Job04_Shadow" }) do
        F.hit(f, i, F.GUTS, F.OGRE, hp, hp - 1000, { skill = { id = id } })
        hp = hp - 1000
    end
    draw(state("chart", JournalTabs.chart(f:snapshot(10), F.ctx("ru"), 1)), s)
    local parts = chart_columns()[1].parts
    eq(#parts, 5, "four skills and the rest")
    local archer = Kit.actor_color("player", 2, 1)
    eq(parts[5][1], Kit.mix(archer, C.panel, 0.55), "the rest 55 % of the way to the panel")
    for i = 1, 4 do eq(lightness(parts[5][1]) < lightness(parts[i][1]), true, "darker than part " .. i) end
    eq(text_call("Остальное") ~= nil, true, "named inside: 2 000 of 6 000 is 71 px of the 212 left by the gaps")
    -- four members on a small screen at scale 2: squeezed, inside the body
    s = fresh()
    s:set("scale", 2)
    ui.display = { x = 800, y = 600 }
    f = Fight.new(0)
    local party = { F.GUTS, F.TORI,
                    { key = "a4", name = "Pawn Two", kind = "pawn", order = 2, job = 3 },
                    { key = "a5", name = "Pawn Three", kind = "pawn", order = 3, job = 5 } }
    for i, who in ipairs(party) do F.hit(f, i, who, F.OGRE, 75000 - i * 100, 74900 - i * 100, { skill = F.NORMAL }) end
    draw(state("chart", JournalTabs.chart(f:snapshot(10), F.ctx("ru"), 1)), s)
    local wx, ww = (800 - 768) / 2, 768
    local body_x0, body_x1 = wx + 20, wx + ww - 20
    local columns = 0
    for _, who in ipairs(party) do
        for _, r in ipairs(rects_of(Kit.tint(Kit.actor_color(who.kind, who.job, 1), -0.08))) do
            if r.x1 - r.x0 > 30 then -- a column (its one part), not a swatch
                columns = columns + 1
                eq(r.x0 >= body_x0 and r.x1 <= body_x1, true, "inside the body")
            end
        end
    end
    eq(columns, 4, "four columns")
    -- no fight: no columns, a dim line
    draw(state("chart", JournalTabs.chart(nil, F.ctx("ru"), 1)), s)
    eq(text_call("Ударов не было") ~= nil, true, "no hits")
    eq(text_call("Ударов не было").col, C.dim, "dim")
end)

test("chart: the gaps 2 px × scale out of the parts, the columns still in proportion; a tiny part still drawn", function()
    local f = Fight.new(0)
    local hp = F.OGRE.max_hp
    local function blow(t, who, skill, amount)
        F.hit(f, t, who, F.OGRE, hp, hp - amount, { skill = skill })
        hp = hp - amount
    end
    blow(1, F.GUTS, { id = "Job02_ThreefoldArrow" }, 6000)
    blow(2, F.GUTS, { id = "Job02_Explosive" }, 5) -- well under a pixel of the column, under its gap
    blow(3, F.TORI, F.NORMAL, 3000)
    local model = JournalTabs.chart(f:snapshot(10), F.ctx("ru"), 1)
    for _, scale in ipairs({ 1, 2 }) do
        local s = fresh()
        s:set("scale", scale)
        draw(state("chart", model), s)
        local cols = chart_columns(112 * scale)
        eq(#cols, 2, "two columns at scale " .. scale)
        local guts, tori = cols[1], cols[2]
        eq(#guts.parts, 2, "Guts' two skills")
        local big, tiny = guts.parts[1], guts.parts[2]
        T.near(big[2] - tiny[3], 2 * scale, 1e-9, "2 px × scale of panel between them")
        eq(tiny[3] - tiny[2] >= 1 - 1e-9, true, "the tiny part at least 1 px")
        eq(tiny[1], Kit.tint(Kit.actor_color("player", 2, 1), 0.16), "in the second shade")
        T.near(tori.height / guts.height, 3000 / 6005, 1e-9, "the columns' heights in proportion to their values")
        T.near(guts.bottom, tori.bottom, 1e-9, "on one base line")
    end
end)

test("chart: four columns 112 px × scale wide, 12 apart, and the list beside them fit at scale 1 and at 0.6", function()
    local f = Fight.new(0)
    local party = { F.GUTS, F.TORI,
                    { key = "a4", name = "Pawn Two", kind = "pawn", order = 2, job = 3 },
                    { key = "a5", name = "Pawn Three", kind = "pawn", order = 3, job = 5 } }
    for i, who in ipairs(party) do F.hit(f, i, who, F.OGRE, 75000 - i * 100, 74900 - i * 100, { skill = F.NORMAL }) end
    local model = JournalTabs.chart(f:snapshot(10), F.ctx("ru"), 1)
    for _, scale in ipairs({ 1, 0.6 }) do -- 0.6: the smallest scale the settings allow
        local s = fresh()
        s:set("scale", scale)
        draw(state("chart", model), s)
        local wx, _, ww = window()
        local bx, bw = wx + 10 * scale, ww - 20 * scale
        local cols = chart_columns(112 * scale)
        eq(#cols, 4, "four columns at scale " .. scale)
        for i, col in ipairs(cols) do
            T.near(col.x0, bx + (i - 1) * (112 + 12) * scale, 1e-9, "column " .. i .. " at scale " .. scale)
        end
        -- the list 24 px × scale right of the columns, its full 440 px × scale, inside the body
        local sx = bx + (4 * 112 + 3 * 12 + 24) * scale
        local band
        for _, r in ipairs(rects_of(C.band)) do
            if math.abs(r.x0 - sx) < 1e-9 then band = r end
        end
        eq(band ~= nil, true, "the list's band right of the columns at scale " .. scale)
        T.near(band.x1 - band.x0, 0.65 * 440 * scale, 1e-9, "the list 440 px × scale wide (its solid 65 %)")
        eq(sx + 440 * scale <= bx + bw, true, "the list inside the body at scale " .. scale)
    end
end)

test("chart: a long name wraps at a space in a part tall enough, else it is cut; a short one stays", function()
    local s = fresh()
    -- Torinald's parts take 86, 76, 43 and 9 px of his 220; the stub's 12 px text is 6 px a character, and 104 px
    -- fit inside a 112 px part
    local model = chart_body(1)
    local tori, guts = model.bars[1].parts, model.bars[2].parts
    tori[1].label = "Разрушительный выпад"         -- 120 px
    tori[2].label = "Перерезать горло"             -- 96 px
    tori[3].label = "Великая саламандра"           -- 108 px in a part under 48 px
    guts[1].label = "Сверхдлинноеназваниенавыка"   -- one word of 156 px in a part of 64 px
    draw(state("chart", model), s)
    local col = chart_columns()[1]
    local first, second = text_call("Разрушительный"), text_call("выпад")
    eq(first ~= nil and second ~= nil, true, "wrapped at the space")
    eq(first.x > col.x0 and first.x < col.x0 + 112, true, "inside the column")
    eq(second.x, first.x, "the second line under the first")
    T.near(second.y - first.y, 12 + 2, 1e-9, "a line and its gap lower")
    eq(second.px, 12, "12 px")
    local value = text_call("4 000")
    eq(value.x, first.x, "the value under the name")
    T.near(value.y - second.y, 12 + 2, 1e-9, "under the second line")
    eq(text_call("Разрушительный выпад"), nil, "not on one line")
    -- a name that fits stays on one line, its value right under it
    local short = text_call("Перерезать горло")
    eq(short ~= nil, true, "a short name whole")
    T.near(text_call("3 500").y - short.y, 12 + 2, 1e-9, "its value on the next line")
    -- a part under 48 px: one line cut with "..", the value under it
    local cut = text_call("Великая саламан..")
    eq(cut ~= nil, true, "cut")
    eq(text_call("саламандра"), nil, "no second line")
    T.near(text_call("2 000").y - cut.y, 12 + 2, 1e-9, "its value on the next line")
    -- one word too long for the column: cut, even in a tall part
    local word = text_call("Сверхдлинноеназ..")
    eq(word ~= nil, true, "the long word cut")
    T.near(text_call("3 000").y - word.y, 12 + 2, 1e-9, "its value on the next line")
end)

test("party and heal tabs: a band per fighter in his colour, rows filled in whose they are", function()
    local s = fresh()
    draw(state("party", JournalTabs.party(F.snap, F.ctx("ru"))), s)
    local guts, tori = text_call("Guts"), text_call("Torinald")
    eq(guts ~= nil and tori ~= nil, true, "a row per member")
    eq(guts.col, Kit.actor_text("player", 2, 1), "Guts' name in his colour")
    eq(tori.col, Kit.actor_text("pawn", 4, 1), "Torinald's in his")
    eq(tori.y > guts.y, true, "by the HP lost: Guts lost 700, Torinald nothing")
    eq(line_at(guts.y), "Guts | 700", "his name and the HP he lost")
    eq(line_at(tori.y), "Torinald | 0", "nothing taken")
    -- the member's own row filled in his colour, to his share of the biggest loss
    local gfill = rects_of(faint(Kit.actor_color("player", 2, 1)))
    eq(#gfill, 1, "Guts' row filled in his colour")
    eq(gfill[1].y0 < guts.y and gfill[1].y1 > guts.y, true, "behind his row"); eq(gfill[1].x1 - gfill[1].x0, BW, "the biggest")
    eq(#rects_of(faint(Kit.actor_color("pawn", 4, 1))), 0, "Torinald lost nothing: no fill")
    local row = text_call("Огр")
    eq(row ~= nil and row.y > guts.y and row.y < tori.y, true, "his row under his own")
    eq(line_at(row.y), "Огр |  · Дробящий ×5, Огонь ×1 | 700", "the kind, its hits by type, its value")
    eq(row.x - guts.x, 16, "16 px further in")
    eq(row.col, C.enemy_label, "an enemy light purple")
    eq(text_call(" · Дробящий ×5, Огонь ×1").col, C.dim, "the types dim")
    local fill = rects_of(faint(C.enemy))
    eq(#fill, 1, "filled in the enemies' purple"); eq(fill[1].x1 - fill[1].x0, BW, "the top row")
    eq(text_call("Ударов не было").y > tori.y, true, "Torinald: no hits")
    eq(text_call("Ударов не было").x - tori.x, 16, "under him, 16 px further in")
    eq(text_call("Броня поглотила"), nil, "no armor line without a defence step")
    -- two members who lost HP: each filled to his share of the biggest loss, the source rows in the attacker's colour
    local two = Fight.new(0)
    F.hit(two, 1, F.OGRE, F.GUTS, 2000, 1300, { types = { Blow = 700 } })
    F.hit(two, 2, F.OGRE, F.TORI, 2400, 2050, { types = { Blow = 350 } })
    draw(state("party", JournalTabs.party(two:snapshot(10, true), F.ctx("ru"))), s)
    gfill = rects_of(faint(Kit.actor_color("player", 2, 1)))
    local tfill = rects_of(faint(Kit.actor_color("pawn", 4, 1)))
    eq(#gfill, 1, "Guts' row"); eq(#tfill, 1, "Torinald's row")
    eq(gfill[1].x1 - gfill[1].x0, BW, "Guts lost the most")
    eq(math.abs((tfill[1].x1 - tfill[1].x0) - BW / 2) < 1e-9, true, "Torinald half as much")
    eq(#rects_of(faint(C.enemy)), 2, "each source row in the ogre's purple")
    -- the armor line, dim, under the member's row
    local f = Fight.new(0)
    F.hit(f, 1, F.OGRE, F.GUTS, 2245.86, 2107.967, { types = { Blow = 106.072 }, final = 137.8936, before = 900,
                                                     after = 106.072 })
    draw(state("party", JournalTabs.party(f:snapshot(10, true), F.ctx("ru"))), s)
    local armor = text_call("≈ 1 032 · 88%")
    eq(armor ~= nil, true, "the armor text"); eq(armor.col, C.dim, "dim")
    eq(line_at(armor.y), "Броня поглотила | ≈ 1 032 · 88%", "label and text")
    eq(text_call("Броня поглотила").col, C.dim, "the label dim")
    eq(text_call("Броня поглотила").x - text_call("Guts").x, 16, "under him, 16 px further in")
    eq(armor.y > text_call("Guts").y and armor.y < text_call("Огр").y, true, "between his row and the others")
    -- healing: a band per healer in his colour, the rows: → the target in his colour · the source | times | amount
    draw(state("heal", JournalTabs.heal(F.snap, F.ctx("ru"))), s)
    guts = text_call("Guts")
    eq(guts.col, Kit.actor_text("player", 2, 1), "the healer's colour")
    eq(line_at(guts.y), "Guts | 231", "the healer and his total")
    local arrow = text_call("→ ")
    eq(arrow.y > guts.y, true, "under his band")
    eq(line_at(arrow.y), "→  | Guts |  · Фруктовые пилюли | 1 раз | 231", "target and source, how many times, value")
    eq(text_call("1 раз").col, C.dim, "the count dim")
    local target
    for _, c in ipairs(ui.calls) do
        if c.fn == "add_text" and c.text == "Guts" and c.y == arrow.y then target = c end
    end
    eq(target.col, Kit.actor_text("player", 2, 1), "the target in his colour")
    local hfill = rects_of(faint(Kit.actor_color("player", 2, 1)))
    eq(#hfill, 1, "filled in the healer's colour")
    local other = text_call("Прочее")
    eq(other.col, C.dim, "Other's band grey"); eq(other.y > arrow.y, true, "after the party")
    eq(line_at(other.y), "Прочее | 15", "its total")
    eq(#rects_of(faint(C.other)), 1, "its row filled grey")
    eq(text_call(" · Прочее").y > other.y, true, "Other's row")
    -- nothing healed: an empty band
    draw(state("heal", JournalTabs.heal(nil, F.ctx("ru"))), s)
    local healed = text_in("Вылечено", C.block.heal.title)
    eq(healed ~= nil, true, "the healed band")
    eq(line_at(healed.y), "Вылечено | 0", "nothing")
    -- no fight: the party tab says so
    draw(state("party", JournalTabs.party(nil, F.ctx("ru"))), s)
    eq(text_call("Ударов не было") ~= nil, true, "no hits")
end)

test("record draws the heading, the events, heals in green, kills marked", function()
    local s = fresh()
    local body = JournalTabs.record(F.snap, F.ctx("ru"))
    draw(state("record", body), s)
    local head = text_call("Время")
    eq(head ~= nil, true, "the heading"); eq(head.col, C.dim, "dim")
    eq(line_at(head.y), "Время | Кто | Кого | Чем | Сколько", "its columns")
    local first = text_call("0:00")
    eq(first.y > head.y, true, "the events under it")
    eq(line_at(first.y), "0:00 | Torinald | Огр | Обычные атаки | 1 000", "the first event")
    eq(text_call("1 000").col, C.text, "a hit's amount")
    local heal = text_call("+231")
    eq(heal.col, C.block.heal.title, "a heal's amount light green")
    eq(line_at(heal.y), "1:40 | Guts | Guts | Фруктовые пилюли | +231", "the item heal")
    local kill = text_call("Обычные атаки · убит")
    eq(kill ~= nil, true, "a kill marked")
    eq(line_at(kill.y), "1:02 | Torinald | Ящер | Обычные атаки · убит | 7 600", "the lizard's death")
    eq(text_call("Время").y < text_call("0:00").y, true, "the heading first without a dropped line")
    -- the dropped line first, dim
    body.dropped = "Первые 500 событий не сохранены"
    draw(state("record", body), s)
    local dropped = text_call(body.dropped)
    eq(dropped ~= nil, true, "the dropped line"); eq(dropped.col, C.dim, "dim")
    eq(dropped.y < text_call("Время").y, true, "above the heading")
    -- nothing recorded
    draw(state("record", JournalTabs.record(nil, F.ctx("ru"))), s)
    eq(text_call("Ударов не было") ~= nil, true, "no hits")
    eq(text_call("Время") ~= nil, true, "the heading still")
end)

test("record: time and amount keep their text on a small screen at scale 2", function()
    local s = fresh()
    s:set("scale", 2)
    ui.display = { x = 1024, y = 768 }
    local body = JournalTabs.record(F.snap, F.ctx("ru"))
    local seen, pages = {}, draw(state("record", body), s).pages
    eq(pages > 1, true, "a few rows a page")
    for p = 1, pages do
        draw(state("record", body, p), s)
        for _, c in ipairs(ui.calls) do
            if c.fn == "add_text" then seen[c.text] = true end
        end
    end
    -- not cut with «..»: the time and the amount as wide as their texts, what still has room
    for _, text in ipairs({ "Время", "Сколько", "0:00", "1 000", "72 800", "+231", "Обычные атаки · убит" }) do
        eq(seen[text], true, "whole: " .. text)
    end
end)

test("record pages", function()
    local s = fresh()
    local rows = {}
    for i = 1, 2000 do
        rows[i] = { time = "0:00", who = "W", whom = "V", what = "Event " .. i, amount = tostring(i), heal = false,
                    kill = false }
    end
    local body = { rows = rows, dropped = "Первые 500 событий не сохранены" }
    -- the first and the last event drawn
    local function drawn()
        local lo, hi = math.huge, 0
        for _, c in ipairs(ui.calls) do
            local i = c.fn == "add_text" and tonumber(c.text:match("^Event (%d+)$"))
            if i then lo, hi = math.min(lo, i), math.max(hi, i) end
        end
        return lo, hi
    end
    local a = draw(state("record", body, 1), s)
    eq(a.pages > 1, true, "pages: " .. a.pages)
    local lo1, hi1 = drawn()
    eq(lo1, 1, "page 1 starts with the first")
    eq(hi1 < 2000, true, "not all of them")
    eq(a.pages, math.ceil(2000 / hi1), "every page as full")
    a = draw(state("record", body, 2), s)
    local lo2, hi2 = drawn()
    eq(lo2, hi1 + 1, "page 2 starts after page 1's last row")
    eq(hi2 - lo2, hi1 - lo1, "as many rows")
    eq(text_call("Время") ~= nil, true, "the heading on page 2")
    eq(text_call(body.dropped) ~= nil, true, "the dropped line on page 2")
    eq(text_call(i18n.t("jpage", 2, a.pages)) ~= nil, true, "the pager")
    draw(state("record", body, a.pages), s)
    local _, last = drawn()
    eq(last, 2000, "the last page ends with the last")
end)

test("kit: pieces fill a page, then the next; a column goes on under its kit's pieces", function()
    ui.reset()
    local dl = imgui.get_window_draw_list()
    local drawn = {}
    local k = Kit.new({ dl = dl, x = 10, y = 100, w = 300, h = 50, scale = 1, interactive = false, actions = {},
                        page = 2 })
    eq(k.px, 14, "base font"); eq(k.x, 10, "x"); eq(k.y, 100, "y"); eq(k.w, 300, "w")
    for i = 1, 5 do
        k:unit(20, function(x, y, w) drawn[#drawn + 1] = { i = i, x = x, y = y, w = w } end)
    end
    eq(k:pages(), 3, "two pieces a page")
    eq(#drawn, 2, "only page 2 drawn")
    eq(drawn[1].i, 3, "the third piece first"); eq(drawn[1].y, 100, "at the top")
    eq(drawn[2].i, 4, "then the fourth"); eq(drawn[2].y, 120, "under it")
    eq(drawn[1].x, 10, "x"); eq(drawn[1].w, 300, "w")
    eq(k:used(), 40, "page 2 holds 40 px"); eq(k:height(), 20, "the last page 20")
    -- a piece taller than the page takes a page of its own
    k = Kit.new({ dl = dl, x = 0, y = 0, w = 100, h = 50, scale = 1, page = 1 })
    k:unit(80, function() end)
    k:unit(10, function() end)
    eq(k:pages(), 2, "tall piece alone")
    eq(k:used(), 80, "page 1 holds the tall piece")
    eq(Kit.new({ dl = dl, x = 0, y = 0, w = 100, h = 50, scale = 1, page = 1 }):pages(), 1, "an empty kit: one page")
    eq(Kit.new({ dl = dl, x = 0, y = 0, w = 100, h = 50, scale = 1, page = 3 }):used(), 0, "nothing on page 3")
    -- a column: its pieces at its x and w, under the kit's, sharing its pages
    drawn = {}
    k = Kit.new({ dl = dl, x = 0, y = 0, w = 300, h = 100, scale = 1, page = 1 })
    k:unit(30, function(x, y, w) drawn[#drawn + 1] = { x, y, w } end)
    local col = k:column({ x = 120, w = 180 })
    col:unit(30, function(x, y, w) drawn[#drawn + 1] = { x, y, w } end)
    k:unit(20, function(x, y, w) drawn[#drawn + 1] = { x, y, w } end)
    eq(T.str(drawn[2]), "120 30 180", "the column's piece at its x and w, under the first")
    eq(T.str(drawn[3]), "0 60 300", "the kit's next piece under the column's")
    eq(k:height(), 80, "one height"); eq(col:pages(), k:pages(), "one count of pages")
    col:unit(30)
    eq(k:pages(), 2, "the column's piece that does not fit starts the kit's next page")
end)

test("kit: rows, cells, spans, fills and tags", function()
    ui.reset()
    imgui.push_font_size(14)
    local dl = imgui.get_window_draw_list()
    local k = Kit.new({ dl = dl, x = 0, y = 0, w = 400, h = 500, scale = 1, page = 1 })
    k:row({ { "left" }, { "9", w = 50, align = "right" } }, { indent = 10, fill = { C.ally, 0.5 } })
    local left, right = text_call("left"), text_call("9")
    eq(left.x, 10, "indented")
    eq(right.x, 400 - 7, "right-aligned to the edge")
    eq(left.y, 3, "centred in 20 px")
    -- the share: the colour faint over half the row, behind the text (drawn first), a 3 px mark in full at its left
    local fill, mark = rects_of(faint(C.ally))[1], rects_of(C.ally)[1]
    eq(fill ~= nil and mark ~= nil, true, "a fill and its mark")
    eq(fill.x0, 0, "from the row's left"); eq(fill.x1, 200, "half of the row")
    eq(fill.y0, 1, "1 px off the top"); eq(fill.y1, 19, "and the bottom")
    eq(mark.x0, 0, "the mark at its left"); eq(mark.x1, 3, "3 px"); eq(mark.y0, 1, "as high"); eq(mark.y1, 19, "as high")
    local order = {}
    for i, c in ipairs(ui.calls) do
        if c == fill then order.fill = i elseif c == left then order.text = i end
    end
    eq(order.fill < order.text, true, "the text over the fill")
    for _, r in ipairs(ui.calls_of("add_rect_filled")) do
        eq(r.y1 - r.y0 > 2, true, "no line under the row")
    end
    eq(k:height(), 20, "one row")
    -- a share of 0: nothing; a small one keeps its mark
    ui.clear_calls()
    k:row({ { "none" } }, { fill = { C.other, 0 } })
    eq(#ui.calls_of("add_rect_filled"), 0, "no fill for 0")
    k:row({ { "tiny" } }, { fill = { C.other, 0.001 } })
    eq(rects_of(faint(C.other))[1].x1, 3, "at least the mark's width")
    -- spans: side by side, the one that does not fit cut, those after it left out
    ui.clear_calls()
    k:spans(0, 0, 100, { { "abc", C.text }, { " · de", C.dim }, { "never", C.ok } }, 14)
    eq(text_call("abc").x, 0, "the first"); eq(text_call(" · de").x, 21, "the second right after it")
    eq(text_call(" · de").col, C.dim, "in its colour")
    ui.clear_calls()
    k:spans(0, 0, 50, { { "abc", C.text }, { " · defgh", C.dim }, { "x", C.ok } }, 14)
    eq(text_call("abc") ~= nil, true, "the first whole")
    eq(text_call("x"), nil, "nothing after the cut one")
    local cut
    for _, c in ipairs(ui.calls) do if c.fn == "add_text" and c.text ~= "abc" then cut = c.text end end
    eq(cut:sub(-2), "..", "the second cut: " .. tostring(cut))
    -- a cell of parts
    ui.clear_calls()
    k:row({ { parts = { { "Guts", C.ok }, { " · x", C.dim } } }, { "5", w = 20, align = "right" } })
    eq(text_call("Guts").col, C.ok, "a part"); eq(text_call(" · x").col, C.dim, "the next")
    local before = k:height()
    k:band("damage", "Dealt", "100")
    eq(k:height() - before, 24, "a band: 20 + 4")
    eq(text_call("Dealt").col, C.block.damage.title, "title colour")
    eq(text_call("100").x + 21 <= 400, true, "total at the right")
    k:band({ mark = C.ok, title = C.bad }, "Mine", "7")
    eq(text_call("Mine").col, C.bad, "a band's own colours")
    local marks = rects_of(C.ok)
    eq(#marks >= 1 and marks[#marks].x1 - marks[#marks].x0 == 3, true, "its mark")
    before = k:height()
    k:tags("Weak:", { "aaaaaaaaaa", "bbbbbbbbbb", "cccccccccc", "dddddddddd", "eeeeeeeeee", "ffffffffff" }, "weak")
    eq(k:height() - before > 20, true, "the tags wrap: more than one line")
    eq(#rects_of(C.tag.weak[1]), 6, "six tags")
    eq(text_call("aaaaaaaaaa").col, C.tag.weak[2], "tag text colour")
    k:tags("Immune:", {}, "immune")
    eq(text_call(i18n.t("jnone")).col, C.dim, "jnone when empty")
    eq(k:fit("abcdefghij", 35), "abc..", "fit cuts with ..")
    eq(k:fit("abc", 35), "abc", "fits")
    eq(k:width("abc", 28), 42, "width at a font size")
    eq(k:button("b", 0, 0, 10, 10), false, "not interactive: no button")
    eq(#ui.calls_of("invisible_button"), 0, "none made")
    imgui.pop_font_size()
    eq(ui.balanced(), true, "balanced")
end)

test("kit: a fighter's colours, tints and the text that reads on a colour", function()
    local thief = Kit.actor_color("pawn", 4, 1)
    eq(thief, C.vocation[4], "a party member: his vocation's colour")
    eq(Kit.actor_color("ally"), C.ally, "an ally"); eq(Kit.actor_color("other"), C.other, "Other")
    eq(Kit.actor_color("enemy"), C.enemy, "an enemy")
    local tint = Kit.tint(thief, 0.4)
    eq(tint >> 24, 255, "alpha kept")
    eq(Kit.actor_text("pawn", 4, 1), tint, "a name: the colour 40 % towards white")
    eq(Kit.actor_text("enemy"), C.enemy_label, "an enemy's name light purple")
    eq(Kit.actor_text("ally"), C.dim, "an ally's grey"); eq(Kit.actor_text("other"), C.dim, "Other's grey")
    eq(Kit.tint(0xFF000000, 1), 0xFFFFFFFF, "black all the way to white")
    eq(Kit.tint(0xFFFFFFFF, -1), 0xFF000000, "white all the way to black")
    eq(Kit.tint(0x80808080, 0), 0x80808080, "0: unchanged")
    eq(Kit.tint(0xFF000064, -0.5), 0xFF000032, "half way to black")
    eq(Kit.mix(0xFF000064, 0xFF0000C8, 0.5), 0xFF000096, "half way to another colour")
    eq(Kit.mix(0xFF102030, 0x10000000, 1), 0xFF000000, "all the way, its own alpha kept")
    eq(Kit.mix(0x80808080, 0xFFFFFFFF, 0), 0x80808080, "0: unchanged")
    eq(Kit.on_color(0xFFFFFFFF), C.ink, "dark text on white"); eq(Kit.on_color(0xFF000000), C.text, "light on black")
    eq(Kit.on_color(Kit.tint(thief, 0.6)), C.ink, "dark on a light shade")
    eq(Kit.on_color(Kit.tint(thief, -0.55)), C.text, "light on a dark one")
    eq(C.chunk, nil, "no chunk palette")
end)

test("kit: a row too narrow for its cells shrinks them to fit", function()
    ui.reset()
    imgui.push_font_size(14)
    local dl = imgui.get_window_draw_list()
    -- 8 px indent, then 50 + 60 + 2 gaps of 8 = 126 px of fixed cells in a 120 px row
    local k = Kit.new({ dl = dl, x = 0, y = 0, w = 120, h = 500, scale = 1, page = 1 })
    k:row({ { "a label" }, { "12", w = 50, align = "right" }, { "345", w = 60, align = "right" } })
    local label, a, b = text_call("a.."), text_call("12"), text_call("345") -- the label keeps 24 px
    eq(label ~= nil and a ~= nil and b ~= nil, true, "every cell drawn")
    eq(b.x + 3 * 7 <= 120 + 1e-9, true, "the last cell ends at the row's right: " .. b.x)
    eq(a.x + 2 * 7 < b.x, true, "the cells keep their order")
    eq(label.x, 8, "the label where it was")
    eq(a.x - 8 >= 24 - 1e-9, true, "the open cell keeps a little room")
    -- the cells fit: unchanged
    ui.clear_calls()
    k:row({ { "x" }, { "12", w = 50, align = "right" } })
    eq(text_call("12").x, 120 - 14, "right-aligned to the edge")
    -- nothing but fixed cells, too wide: shrunk to the row
    ui.clear_calls()
    k:row({ { "123456", w = 100 }, { "7", w = 100, align = "right" } })
    eq(text_call("7").x + 7 <= 120 + 1e-9, true, "inside the row")
    -- a cut text is never wider than its room, not even «..»
    eq(k:fit("abcdef", 10), "", "no room for «..»")
    eq(k:fit("abcdef", 14), "..", "just «..»")
    imgui.pop_font_size()
    eq(ui.balanced(), true, "balanced")
end)

test("kit: a button row like the tabs, the active one marked, a click returns its index", function()
    ui.reset()
    imgui.push_font_size(14)
    local dl = imgui.get_window_draw_list()
    local k = Kit.new({ dl = dl, x = 0, y = 0, w = 400, h = 500, scale = 1, page = 1 })
    local labels, ids = { "one", "two", "three" }, { "b:1", "b:2", "b:3" }
    eq(Kit.BUTTON_ROW_H, 24, "24 px high at scale 1")
    eq(k:button_row(labels, ids, 2, 10, 50, 300), nil, "not interactive: nothing clicked")
    eq(#ui.calls_of("invisible_button"), 0, "no buttons")
    -- each as wide as its label plus 10 px either side, 2 px apart: 41 at 10, 41 at 53, 55 at 96
    local on, off = rects_of(C.tab_on), rects_of(C.tab)
    eq(#on, 1, "one active"); eq(#off, 2, "two others")
    eq(on[1].x0, 53, "the second is active"); eq(on[1].x1, 94, "41 wide")
    eq(on[1].y0, 50, "at y"); eq(on[1].y1, 74, "24 high")
    eq(off[1].x0, 10, "the first at x"); eq(off[2].x0, 96, "the third"); eq(off[2].x1, 151, "55 wide")
    local bronze = rects_of(C.bronze)
    eq(#bronze, 3, "the active one's top, left and right edges bronze")
    for _, r in ipairs(bronze) do eq(r.x0 >= 53 and r.x1 <= 94, true, "on the active one") end
    eq(#rects_of(C.border), 6, "the others' edges")
    local two = text_call("two")
    eq(two.col, C.text, "the active label bright")
    eq(text_call("one").col, C.dim, "the others dim"); eq(text_call("three").col, C.dim, "dim")
    eq(two.x, 53 + (41 - 21) / 2, "centred"); eq(two.y, 50 + (24 - 14) / 2, "in the middle")
    -- interactive: a button over each, a click returns its index
    k = Kit.new({ dl = dl, x = 0, y = 0, w = 400, h = 500, scale = 1, page = 1, interactive = true })
    ui.clear_calls()
    ui.press("b:3")
    eq(k:button_row(labels, ids, 2, 10, 50, 300), 3, "b:3 clicked")
    local b = ui.calls_of("invisible_button")
    eq(#b, 3, "a button each")
    eq(b[1].id, "b:1", "its id"); eq(b[1].x, 10, "over it"); eq(b[1].w, 41, "as wide"); eq(b[1].h, 24, "as high")
    eq(b[3].id, "b:3", "in order"); eq(b[3].x, 96, "over the third")
    ui.clear_calls()
    eq(k:button_row(labels, ids, 2, 10, 50, 300), nil, "no click, nothing")
    -- too wide: equal widths, the labels fitted; no index active: none marked
    ui.clear_calls()
    k:button_row({ "aaaaaaaaaaaaaaaa", "b" }, { "c:1", "c:2" }, nil, 0, 0, 102)
    eq(#rects_of(C.tab_on), 0, "none active")
    off = rects_of(C.tab)
    eq(off[1].x1 - off[1].x0, 50, "half of 102 - 2 each"); eq(off[2].x0, 52, "after the gap")
    local cut = k:fit("aaaaaaaaaaaaaaaa", 30)
    eq(text_call(cut) ~= nil, true, "the long label fitted: " .. cut)
    eq(text_call("b").x, 52 + (50 - 7) / 2, "the short one centred")
    imgui.pop_font_size()
    eq(ui.balanced(), true, "balanced")
end)

T.finish()
