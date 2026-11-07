package.path = "mod/reframework/autorun/?.lua;tests/?.lua;" .. package.path

local T = require("testlib")
local test, eq, near = T.test, T.eq, T.near
local ui = require("stubs/ui").install()
local i18n = require("DD2DamageMeter/i18n")
local Settings = require("DD2DamageMeter/settings")
local Overlay = require("DD2DamageMeter/ui/overlay")

local C = Overlay.COLORS
local STYLES = { "frameless", "panel" }

-- ImGuiWindowFlags (ImGui 1.92.0), as the overlay passes them.
local NO_TITLE_BAR, NO_MOVE, NO_BACKGROUND, NO_MOUSE_INPUTS, NO_FOCUS_ON_APPEARING, NO_NAV = 1, 4, 128, 512, 4096, 196608
local NO_BRING_TO_FRONT_ON_FOCUS = 8192
local COND_ALWAYS = 1

-- app.Character.JobEnum
local FIGHTER, MAGE, WARRIOR = 1, 3, 5

local function make_settings(over)
    local saved = over or {}
    return Settings.load({ read = function() return saved end, write = function(t) saved = t end })
end

-- Models in the shape view.lua produces (live/summary/details), strings already formatted. Guts is a warrior,
-- Torinald a fighter, Casca and Yves both mages (Casca first in the party, so Yves has the second shade).
local function live_model()
    return {
        header = { title = "Chimera", hp_text = "31 200 / 80 000", time = "5:18" },
        damage = {
            title = "Damage to enemies", total = "130 642", per_sec = "410/s",
            rows = {
                { key = "ch000000_00", name = "Guts", kind = "player", order = 0, job = WARRIOR, shade = 1, value = "52 898", fill = 1, per_sec = "166/s", share = "40%" },
                { key = "ch111007_00", name = "Torinald", kind = "pawn", order = 2, job = FIGHTER, shade = 1, value = "44 176", fill = 0.84, per_sec = "139/s", share = "34%" },
                { key = "ch100000_00", name = "Casca", kind = "pawn", order = 1, job = MAGE, shade = 1, value = "24 963", fill = 0.47, per_sec = "78/s", share = "19%" },
                { key = "ch111002_00", name = "Yves", kind = "pawn", order = 3, job = MAGE, shade = 2, value = "8 604", fill = 0.16, per_sec = "27/s", share = "7%" },
                { key = "ch300659_00", name = "Guard", kind = "ally", value = "908", fill = 0.02, per_sec = "3/s" },
            },
        },
        taken = {
            title = "Damage to party", total = "6 844",
            rows = {
                { label = "Chimera → Guts", value = "3 817", fill = 1 },
                { label = "Chimera → Casca", value = "3 027", fill = 0.79 },
            },
        },
        heal = {
            title = "Healing", total = "8 243", per_sec = "26/s",
            rows = {
                { key = "ch111002_00", name = "Yves", kind = "pawn", order = 3, job = MAGE, shade = 2, value = "7 012", fill = 1, per_sec = "22/s", share = "85%" },
            },
        },
    }
end

local function summary_model()
    return {
        title = "Victory", time = "5:18",
        enemies = {
            { label = "Chimera", hp_text = "0 / 80 000 HP", killed = true },
            { label = "Goblin ×3", hp_text = "3 700 HP each", killed = false },
        },
        damage = {
            title = "Dealt", total = "103 428",
            rows = {
                { key = "ch000000_00", name = "Guts", kind = "player", order = 0, job = WARRIOR, shade = 1, value = "44 463", fill = 1, share = "43%" },
                { key = "ch111007_00", name = "Torinald", kind = "pawn", order = 2, job = FIGHTER, shade = 1, value = "31 494", fill = 0.71, share = "30%" },
                { key = "ch100000_00", name = "Casca", kind = "pawn", order = 1, job = MAGE, shade = 1, value = "21 235", fill = 0.48, share = "21%" },
            },
        },
        allies = {
            title = "Allies",
            rows = { { key = "ch300659_00", name = "Guard", kind = "ally", value = "908", fill = 0.02 } },
        },
        heal = {
            title = "Healed", total = "8 243",
            rows = { { key = "ch111002_00", name = "Yves", kind = "pawn", order = 3, job = MAGE, shade = 2, value = "7 012", fill = 1, share = "85%" } },
        },
        armor = { { label = "Enemy defence absorbed", value = "≈ 68 640 · 88%" } },
    }
end

local function details_model()
    return {
        key = "ch111002_00", name = "Yves", kind = "pawn", order = 3, job = MAGE, shade = 2,
        rows = {
            { label = "Normal attacks", hits = "45", total = "9 100", max = "310", share = "17%", perfect = "" },
            { label = "Wild Fury", hits = "11", total = "43 798", max = "5 100", share = "83%", perfect = "7" },
        },
        extra = { { label = "Full damage (with overkill)", value = "55 000" } },
    }
end

local function fresh(style)
    ui.reset()
    Overlay.reset()
    i18n.set("en")
    return make_settings({ style = style })
end

-- Draws one frame and returns the actions.
local function draw(state, settings)
    ui.clear_calls()
    return Overlay.draw(state, settings)
end

-- The text that heads a block: on the panel the title with its total ("Dealt · 103 428"); without a background the
-- title alone (the total is a text of its own at the right of the block's band).
local function heading(style, title, total)
    if style == "panel" then return total and (title .. " · " .. total) or title end
    return title
end

local function index_of(list, text)
    for i, t in ipairs(list) do
        if t == text then return i end
    end
    return nil
end

-- A shadow or outline copy of a text: drawn in the near-black of the shadows (any alpha).
local function is_copy(c)
    return c.fn == "add_text" and (c.col & 0xFFFFFF) == (C.shadow & 0xFFFFFF)
end

-- The texts of the frame just drawn, in order, without their shadow and outline copies.
local function texts()
    local list = {}
    for _, c in ipairs(ui.calls) do
        if c.fn == "add_text" and not is_copy(c) then list[#list + 1] = c.text end
    end
    return list
end

local function has_text(s)
    return index_of(texts(), s) ~= nil
end

local function count_text(s)
    local n = 0
    for _, t in ipairs(texts()) do
        if t == s then n = n + 1 end
    end
    return n
end

-- The n-th add_text call that drew `text` itself (not a copy), and its index in ui.calls.
local function text_call(text, nth)
    local seen = 0
    for i, c in ipairs(ui.calls) do
        if c.fn == "add_text" and c.text == text and not is_copy(c) then
            seen = seen + 1
            if seen == (nth or 1) then return c, i end
        end
    end
    error("text not drawn: " .. text, 2)
end

-- The copies drawn right before the n-th `text`: { shadow = {...}, outline = {...} } (outline copies are the ones of
-- the outline's alpha).
local function copies_of(text, nth)
    local _, at = text_call(text, nth)
    local list = {}
    local i = at - 1
    while i >= 1 and is_copy(ui.calls[i]) and ui.calls[i].text == text do
        table.insert(list, 1, ui.calls[i])
        i = i - 1
    end
    return list
end

-- The layout item (row) a text was drawn in.
local function row_item(t)
    for _, it in ipairs(ui.items) do
        if it.y <= t.y and t.y < it.y + it.h then return it end
    end
    error("no row under " .. tostring(t.text), 2)
end

local function window_rects()
    local list = {}
    for _, c in ipairs(ui.calls) do
        if c.fn == "add_rect_filled" and c.layer == "window" then list[#list + 1] = c end
    end
    return list
end

local function background_rects()
    local list = {}
    for _, c in ipairs(ui.calls) do
        if c.fn == "add_rect_filled" and c.layer == "background" then list[#list + 1] = c end
    end
    return list
end

-- The bar of the row of the n-th text `text`: [1] its track, [2] its coloured part (the rectangles of the row that
-- share the track's left edge, top and bottom). Empty for a row without a bar.
local function bar_of(text, nth)
    local it = row_item(text_call(text, nth))
    local track
    local rows = {}
    for _, r in ipairs(window_rects()) do
        if r.y0 >= it.y - 2 and r.y1 <= it.y + it.h + 2 then
            rows[#rows + 1] = r
            if not track and (r.col == C.track or r.col == C.panel_track) then track = r end
        end
    end
    if not track then return {} end
    local out = {}
    for _, r in ipairs(rows) do
        if r.x0 == track.x0 and r.y0 == track.y0 and r.y1 == track.y1 then out[#out + 1] = r end
    end
    return out
end

local function width(rect)
    return rect.x1 - rect.x0
end

local function height(rect)
    return rect.y1 - rect.y0
end

-- Width of `text` as the stub measures it at the font size of the frame just drawn.
local function text_w(text)
    local px = ui.calls_of("push_font_size")[1][1]
    return (utf8.len(text) or #text) * ui.char_w * px / 14
end

local function brightness(col)
    return (col & 0xFF) + ((col >> 8) & 0xFF) + ((col >> 16) & 0xFF)
end

test("hidden draws nothing", function()
    for _, style in ipairs(STYLES) do
        local s = fresh(style)
        local a = draw({ mode = "hidden", live = live_model(), summary = summary_model(), details = details_model(),
            history_index = 1, history_count = 1 }, s)
        eq(#ui.calls, 0, style .. ": no imgui call at all")
        eq(a.select_actor, nil, "select_actor")
        eq(a.history, 0, "history")
        eq(a.hide, false, "hide")
        eq(a.back, false, "back")
        eq(a.moved, nil, "moved")

        -- nothing to show yet: a mode without its model draws nothing either
        draw({ mode = "live", history_index = 1, history_count = 0 }, s)
        eq(#ui.calls, 0, "live without a model")
        draw({ mode = "summary", live = live_model(), history_index = 1, history_count = 0 }, s)
        eq(#ui.calls, 0, "summary without a model")
    end
end)

test("live draws three blocks with formatted rows, in both styles", function()
    for _, style in ipairs(STYLES) do
        local s = fresh(style)
        draw({ mode = "live", live = live_model(), history_index = 1, history_count = 0 }, s)
        eq(#ui.calls_of("begin_window"), 1, style .. ": one window")
        eq(#ui.calls_of("end_window"), 1, "closed once")
        eq(ui.balanced(), true, "pushes and pops balance")

        local list = texts()
        -- header: title, HP, time
        for _, t in ipairs({ "Chimera", "31 200 / 80 000", "5:18" }) do eq(has_text(t), true, style .. ": header " .. t) end
        -- three blocks, in order, with their totals
        local damage = index_of(list, heading(style, "Damage to enemies", "130 642 · 410/s"))
        local taken = index_of(list, heading(style, "Damage to party", "6 844"))
        local heal = index_of(list, heading(style, "Healing", "8 243 · 26/s"))
        eq(damage ~= nil and taken ~= nil and heal ~= nil, true, "block titles drawn")
        eq(damage < taken and taken < heal, true, "damage, then taken, then healing")
        if style == "frameless" then
            eq(index_of(list, "130 642 · 410/s"), damage + 1, "the damage total right after its title")
            eq(index_of(list, "6 844"), taken + 1, "the damage to the party has its total too")
            eq(index_of(list, "8 243 · 26/s"), heal + 1, "the healing total right after its title")
        end
        -- rows: name on the left, formatted numbers on the right, on one line
        eq(index_of(list, "Guts") > damage and index_of(list, "Guts") < taken, true, "Guts in the damage block")
        eq(has_text("52 898 · 166/s · 40%"), true, "damage numbers")
        eq(has_text("908 · 3/s"), true, "an ally row has no share")
        eq(has_text("Chimera → Guts"), true, "taken label")
        eq(has_text("3 817"), true, "taken value")
        eq(has_text("7 012 · 22/s · 85%"), true, "heal numbers")
        eq(text_call("Guts").x < text_call("52 898 · 166/s · 40%").x, true, "name left, numbers right")
        eq(text_call("Guts").y, text_call("52 898 · 166/s · 40%").y, "on one line")
        -- every row has a bar: the party, the ally, the taken rows, the healers
        for _, t in ipairs({ "Guts", "Torinald", "Casca", "Yves", "Guard", "Chimera → Guts", "Chimera → Casca" }) do
            eq(#bar_of(t), 2, style .. ": a bar for " .. t)
        end
        eq(#bar_of("Yves", 2), 2, "a bar for the healer")
        -- rows do not overlap
        local rows = ui.items
        for i = 2, #rows do eq(rows[i].y >= rows[i - 1].y + rows[i - 1].h, true, "item " .. i .. " below item " .. (i - 1)) end
        -- every text is the window's (the background layer has only the backdrop)
        for _, c in ipairs(ui.calls_of("add_text")) do eq(c.layer, "window", "text on the window: " .. c.text) end
    end
end)

test("bars are filled by row.fill", function()
    for _, style in ipairs(STYLES) do
        local s = fresh(style)
        draw({ mode = "live", live = live_model(), history_index = 1, history_count = 0 }, s)
        local guts = bar_of("Guts")
        near(width(guts[2]), width(guts[1]), 1e-9, style .. ": fill 1 spans the row")
        near(width(bar_of("Torinald")[2]), 0.84 * width(guts[1]), 1e-6, "fill 0.84")
        near(width(bar_of("Casca")[2]), 0.47 * width(guts[1]), 1e-6, "fill 0.47")
        near(width(bar_of("Chimera → Casca")[2]), 0.79 * width(guts[1]), 1e-6, "taken fill 0.79")

        -- a missing or silly fill never breaks the bar
        local odd = live_model()
        odd.damage.rows[1].fill = 7
        odd.damage.rows[2].fill = nil
        odd.damage.rows[3].fill = -1
        draw({ mode = "live", live = odd, history_index = 1, history_count = 0 }, s)
        near(width(bar_of("Guts")[2]), width(bar_of("Guts")[1]), 1e-9, "fill above 1 is clamped")
        eq(#bar_of("Torinald"), 1, "no fill, no coloured part")
        eq(#bar_of("Casca"), 1, "negative fill, no coloured part")

        -- a tiny share still shows: at least 2 px; nothing at 0
        local tiny = live_model()
        tiny.damage.rows[5].fill = 0.001
        tiny.taken.rows[2].fill = 0.0001
        tiny.damage.rows[4].fill = 0
        draw({ mode = "live", live = tiny, history_index = 1, history_count = 0 }, s)
        near(width(bar_of("Guard")[2]), 2, 1e-9, style .. ": 0.001 of the bar is 2 px")
        near(width(bar_of("Chimera → Casca")[2]), 2, 1e-9, "a taken row too")
        eq(#bar_of("Yves"), 1, "0: no coloured part")
        near(width(bar_of("Guts")[2]), width(bar_of("Guts")[1]), 1e-9, "a full bar stays full")
    end
end)

test("party bars take the colour of the vocation, a second of the same vocation a shade", function()
    for _, style in ipairs(STYLES) do
        local s = fresh(style)
        draw({ mode = "live", live = live_model(), history_index = 1, history_count = 0 }, s)
        local mage = C.vocation[MAGE]
        eq(bar_of("Guts")[2].col, C.vocation[WARRIOR], style .. ": the player, a warrior")
        eq(bar_of("Torinald")[2].col, C.vocation[FIGHTER], "a fighter")
        eq(bar_of("Casca")[2].col, mage, "the first mage of the party")
        local yves = bar_of("Yves")[2].col
        eq(yves, Overlay.shade(mage, 2), "the second mage: the second shade")
        eq(yves ~= mage, true, "told apart from Casca")
        eq(brightness(yves) > brightness(mage), true, "a lighter shade")
        eq(bar_of("Yves", 2)[2].col, yves, "the same colour in the healing block")
        -- the other kinds
        eq(bar_of("Guard")[2].col, C.ally, "an ally")
        eq(bar_of("Chimera → Guts")[2].col, C.enemy, "damage to the party: enemy purple")

        -- the shade is the model's (view.lua ranks the whole party of the fight): the window does not rank the rows
        -- it shows, so a character keeps its colour when another one joins the list or the rows change places
        local gone = live_model()
        table.remove(gone.damage.rows, 3) -- Casca has no row (yet)
        gone.damage.rows[1], gone.damage.rows[3] = gone.damage.rows[3], gone.damage.rows[1]
        draw({ mode = "live", live = gone, history_index = 1, history_count = 0 }, s)
        eq(bar_of("Yves")[2].col, yves, "Yves keeps the second shade")
        local third = live_model()
        third.damage.rows[4].shade = 3
        draw({ mode = "live", live = third, history_index = 1, history_count = 0 }, s)
        eq(bar_of("Yves")[2].col, Overlay.shade(mage, 3), "a third: darker")
        eq(brightness(bar_of("Yves")[2].col) < brightness(mage), true, "darker than the first")
        local none = live_model()
        none.damage.rows[4].shade = nil
        draw({ mode = "live", live = none, history_index = 1, history_count = 0 }, s)
        eq(bar_of("Yves")[2].col, mage, "no shade: the vocation's colour")

        -- a vocation that could not be read is grey, shaded the same way
        local unknown = live_model()
        unknown.damage.rows[2].job = nil
        unknown.damage.rows[1].job = 0
        unknown.damage.rows[3].job, unknown.damage.rows[3].shade = 11, 2
        draw({ mode = "live", live = unknown, history_index = 1, history_count = 0 }, s)
        eq(bar_of("Guts")[2].col, C.unknown, "JobEnum 0: unknown")
        eq(bar_of("Torinald")[2].col, C.unknown, "nil: unknown")
        eq(bar_of("Casca")[2].col, Overlay.shade(C.unknown, 2), "a value outside the enum: unknown, with its shade")

        -- the summary colours the same way
        draw({ mode = "summary", summary = summary_model(), history_index = 1, history_count = 1 }, s)
        eq(bar_of("Torinald")[2].col, C.vocation[FIGHTER], "summary: by vocation")
        eq(bar_of("Yves")[2].col, Overlay.shade(mage, 2), "summary: the healer is the second mage")
        eq(bar_of("Guard")[2].col, C.ally, "summary: the ally")
    end
end)

test("the shades of a colour", function()
    local mage = C.vocation[MAGE]
    eq(Overlay.shade(mage, 1), mage, "the first keeps the colour")
    eq(Overlay.shade(mage, nil), mage, "no rank: the colour")
    eq(Overlay.shade(mage, 2) >> 24, mage >> 24, "alpha kept")
    eq(brightness(Overlay.shade(mage, 2)) > brightness(mage), true, "second lighter")
    eq(brightness(Overlay.shade(mage, 3)) < brightness(mage), true, "third darker")
    eq(Overlay.shade(mage, 4) ~= Overlay.shade(mage, 2), true, "a fourth has its own")
    -- every vocation colour is distinct, and none is a kind's colour
    local seen = {}
    for job = 1, 10 do
        local col = C.vocation[job]
        eq(type(col), "number", "colour of vocation " .. job)
        eq(seen[col], nil, "vocation " .. job .. " has its own colour")
        seen[col] = true
    end
    for _, kind in ipairs({ "unknown", "ally", "other", "enemy" }) do eq(seen[C[kind]], nil, kind .. " is no vocation colour") end
    -- the vocation colours' values (0xAABBGGRR)
    eq(C.vocation[1], 0xFF544BB8, "Fighter #B84B54")
    eq(C.vocation[10], 0xFF658E99, "Warfarer #998E65")
    eq(C.unknown, 0xFF80858A, "unknown #8A8580")
    eq(C.ally, 0xFF70818C, "allies #8C8170")
    eq(C.other, 0xFF70757A, "Other #7A7570")
    eq(C.enemy, 0xFFA65C8D, "enemies #8D5CA6")
end)

test("no input flags while the REFramework menu is closed", function()
    for _, style in ipairs(STYLES) do
        local s = fresh(style)
        ui.drawing_ui = false
        ui.press("damage:ch000000_00")
        local a = draw({ mode = "live", live = live_model(), history_index = 1, history_count = 0 }, s)
        local flags = ui.calls_of("begin_window")[1][3]
        eq(flags & NO_MOUSE_INPUTS, NO_MOUSE_INPUTS, style .. ": mouse passes through")
        eq(flags & NO_NAV, NO_NAV, "no navigation focus")
        eq(flags & NO_FOCUS_ON_APPEARING, NO_FOCUS_ON_APPEARING, "does not take focus")
        eq(flags & NO_TITLE_BAR, NO_TITLE_BAR, "no title bar")
        eq(flags & NO_BACKGROUND, NO_BACKGROUND, "imgui draws no background nor border: the overlay paints its own")
        eq(flags & NO_BRING_TO_FRONT_ON_FOCUS, NO_BRING_TO_FRONT_ON_FOCUS, "stays behind the REFramework windows")
        eq(#ui.calls_of("invisible_button"), 0, "no clickable rows")
        eq(#ui.calls_of("button"), 0, "no buttons")
        eq(a.select_actor, nil, "a click cannot select anything")
        eq(a.hide, false, "nor hide")

        -- the same window with the menu open takes input and can be dragged
        ui.drawing_ui = true
        draw({ mode = "live", live = live_model(), history_index = 1, history_count = 0 }, s)
        flags = ui.calls_of("begin_window")[1][3]
        eq(flags & NO_MOUSE_INPUTS, 0, "mouse input on")
        eq(flags & NO_NAV, 0, "navigation on")
        eq(flags & NO_MOVE, 0, "movable")
        eq(flags & NO_TITLE_BAR, NO_TITLE_BAR, "still no title bar")
        eq(flags & NO_FOCUS_ON_APPEARING, NO_FOCUS_ON_APPEARING, "still does not steal focus when it appears")
        eq(flags & NO_BRING_TO_FRONT_ON_FOCUS, NO_BRING_TO_FRONT_ON_FOCUS, "still behind the REFramework windows")
        eq(#ui.calls_of("invisible_button") > 0, true, "rows are clickable now")
    end
end)

test("click on a name returns select_actor when the menu is open", function()
    for _, style in ipairs(STYLES) do
        local s = fresh(style)
        ui.drawing_ui = true
        local state = { mode = "live", live = live_model(), history_index = 1, history_count = 0 }

        local a = draw(state, s)
        eq(a.select_actor, nil, style .. ": no click, no selection")

        ui.press("damage:ch111007_00")
        a = draw(state, s)
        eq(a.select_actor, "ch111007_00", "damage row")
        eq(a.hide, false, "only a selection")
        eq(a.history, 0, "history untouched")

        ui.press("heal:ch111002_00")
        a = draw(state, s)
        eq(a.select_actor, "ch111002_00", "heal row")

        ui.press("damage:ch300659_00")
        a = draw(state, s)
        eq(a.select_actor, "ch300659_00", "ally row")

        -- the same actor in two blocks never shares a button id
        local ids = {}
        for _, b in ipairs(ui.calls_of("invisible_button")) do
            eq(ids[b.id], nil, "unique id " .. b.id)
            ids[b.id] = true
        end
        eq(ids["taken:Chimera → Guts"], nil, "taken rows have no button")

        -- the button is the whole row: the name, the numbers and the bar under them
        local b = ui.find("invisible_button", "damage:ch000000_00")
        local name, bar = text_call("Guts"), bar_of("Guts")[1]
        eq(b.x <= name.x and name.y >= b.y and name.y < b.y + b.h, true, "the name is on the button")
        eq(bar.y1 <= b.y + b.h + 1e-9 and bar.x1 <= b.x + b.w + 1e-9, true, "and the bar")

        -- a hovered row is lit up
        ui.hovered["damage:ch000000_00"] = true
        draw(state, s)
        local lit = 0
        for _, r in ipairs(window_rects()) do
            if r.y0 <= name.y and name.y < r.y1 and r.col ~= C.track and r.col ~= C.panel_track
                and r.col ~= C.vocation[WARRIOR] then lit = lit + 1 end
        end
        eq(lit >= 1, true, "a hover highlight")
        ui.hovered = {}

        -- the summary rows work the same way
        ui.press("damage:ch000000_00")
        a = draw({ mode = "summary", summary = summary_model(), history_index = 1, history_count = 1 }, s)
        eq(a.select_actor, "ch000000_00", "summary damage row")
        ui.press("heal:ch111002_00")
        a = draw({ mode = "summary", summary = summary_model(), history_index = 1, history_count = 1 }, s)
        eq(a.select_actor, "ch111002_00", "summary heal row")
        ui.press("allies:ch300659_00")
        a = draw({ mode = "summary", summary = summary_model(), history_index = 1, history_count = 1 }, s)
        eq(a.select_actor, "ch300659_00", "summary ally row")
    end
end)

test("history buttons return -1/1", function()
    for _, style in ipairs(STYLES) do
        local s = fresh(style)
        ui.drawing_ui = true
        local state = { mode = "summary", summary = summary_model(), history_index = 2, history_count = 3 }

        eq(draw(state, s).history, 0, style .. ": no click, no paging")
        eq(has_text("2/3"), true, "position in the history")

        ui.press("history_prev")
        eq(draw(state, s).history, -1, "‹")
        ui.press("history_next")
        eq(draw(state, s).history, 1, "›")

        -- the ends have nothing to page to
        state.history_index = 1
        draw(state, s)
        eq(ui.find("invisible_button", "history_prev"), nil, "no ‹ at the first entry")
        eq(has_text("‹"), true, "a dim ‹ instead")
        eq(ui.find("invisible_button", "history_next") ~= nil, true, "› is there")
        state.history_index = 3
        draw(state, s)
        eq(ui.find("invisible_button", "history_next"), nil, "no › at the last entry")
        eq(ui.find("invisible_button", "history_prev") ~= nil, true, "‹ is there")

        -- a single fight: nothing to page, nothing to count
        state.history_index, state.history_count = 1, 1
        draw(state, s)
        eq(ui.find("invisible_button", "history_prev"), nil, "no ‹ with one fight")
        eq(ui.find("invisible_button", "history_next"), nil, "no › with one fight")
        eq(has_text("1/1"), false, "no counter with one fight")

        -- the live window has no history at all
        draw({ mode = "live", live = live_model(), history_index = 2, history_count = 3 }, s)
        eq(ui.find("invisible_button", "history_prev"), nil, "no ‹ in the live window")

        -- menu closed: the position is shown, the buttons are not
        ui.drawing_ui = false
        state.history_index, state.history_count = 2, 3
        ui.press("history_prev")
        eq(draw(state, s).history, 0, "no paging without the menu")
        eq(has_text("2/3"), true, "the counter stays")
        eq(#ui.calls_of("invisible_button"), 0, "no buttons")
    end
end)

test("the x button hides, the back button leaves the details", function()
    for _, style in ipairs(STYLES) do
        local s = fresh(style)
        ui.drawing_ui = true
        ui.press("hide")
        eq(draw({ mode = "live", live = live_model(), history_index = 1, history_count = 0 }, s).hide, true, style .. ": hide in live")
        eq(has_text("×"), true, "the × is drawn")
        ui.press("hide")
        eq(draw({ mode = "summary", summary = summary_model(), history_index = 1, history_count = 1 }, s).hide, true, "hide in summary")
        ui.press("hide")
        eq(draw({ mode = "live", live = live_model(), details = details_model(), history_index = 1, history_count = 0 }, s).hide,
            true, "hide in details")

        ui.press("back")
        local a = draw({ mode = "live", live = live_model(), details = details_model(), history_index = 1, history_count = 0 }, s)
        eq(a.back, true, "back from the details")
        eq(a.hide, false, "back is not hide")
        draw({ mode = "live", live = live_model(), history_index = 1, history_count = 0 }, s)
        eq(ui.find("invisible_button", "back"), nil, "no back button without details")

        ui.drawing_ui = false
        ui.press("hide")
        eq(draw({ mode = "live", live = live_model(), history_index = 1, history_count = 0 }, s).hide, false, "no x without the menu")
    end
end)

test("details replace the bars", function()
    for _, style in ipairs(STYLES) do
        local s = fresh(style)
        ui.drawing_ui = true
        local a = draw({ mode = "live", live = live_model(), details = details_model(), history_index = 1, history_count = 0 }, s)
        eq(a.select_actor, nil, style .. ": nothing selected")
        eq(has_text("Yves"), true, "character name")
        eq(has_text(heading(style, "Damage to enemies", "130 642 · 410/s")), false, "the live blocks are gone")
        eq(has_text(heading(style, "Healing", "8 243 · 26/s")), false, "all of them")
        -- column headings come from the language file
        for _, key in ipairs({ "details_hits", "details_total", "details_max", "details_perfect" }) do
            eq(has_text(i18n.t(key)), true, "heading " .. key)
        end
        for _, t in ipairs({ "Normal attacks", "45", "9 100", "310", "17%", "Wild Fury", "11", "43 798", "5 100", "83%", "7",
            "Full damage (with overkill)", "55 000" }) do
            eq(has_text(t), true, "cell " .. t)
        end
        -- table cells line up: the "Total" heading is above the totals
        local head = text_call(i18n.t("details_total"))
        local cell = text_call("9 100")
        near(head.x + text_w(i18n.t("details_total")), cell.x + text_w("9 100"), 1e-6, "right-aligned column")
        eq(ui.balanced(), true, "balanced")

        -- the line under the header has the character's colour: Yves is the party's second mage
        local line
        for _, r in ipairs(window_rects()) do
            if r.col == Overlay.shade(C.vocation[MAGE], 2) then line = r end
        end
        eq(line ~= nil, true, "a line in Yves' colour")
        eq(line.y0 > text_call("Yves").y and line.y1 < head.y, true, "between the name and the table")

        -- a row with a missing cell is drawn without it
        local gap = details_model()
        gap.rows[1].perfect = nil
        gap.rows[1].max = nil
        draw({ mode = "live", live = live_model(), details = gap, history_index = 1, history_count = 0 }, s)
        eq(has_text("Normal attacks"), true, "row with missing cells")
        eq(ui.balanced(), true, "balanced")

        -- a table with wide numbers makes the window wider instead of overflowing it
        local wide = details_model()
        wide.rows[2].total = "123 456 789 012"
        wide.rows[2].max = "987 654 321"
        wide.rows[2].hits = "1 234 567"
        draw({ mode = "live", live = live_model(), details = wide, history_index = 1, history_count = 0 }, s)
        local right_edge = -math.huge
        for _, it in ipairs(ui.items) do right_edge = math.max(right_edge, it.x + it.w) end
        for _, c in ipairs(ui.calls_of("add_text")) do
            if not is_copy(c) then eq(c.x + text_w(c.text) <= right_edge + 1e-6, true, "inside the window: " .. c.text) end
        end
        -- the label never runs into the first number
        eq(text_call("Wild Fury").x + text_w("Wild Fury") <= text_call("1 234 567").x, true, "label left of the numbers")

        -- no perfect hits anywhere: no column for them
        local m = details_model()
        m.rows[2].perfect = ""
        draw({ mode = "summary", summary = summary_model(), details = m, history_index = 1, history_count = 1 }, s)
        eq(has_text(i18n.t("details_perfect")), false, "perfect column left out")
        eq(has_text("Wild Fury"), true, "details also open from the summary")
        eq(has_text(heading(style, "Dealt", "103 428")), false, "the summary blocks are gone")

        -- details of an older model (no kind, no job): a bronze line, no error
        local old = details_model()
        old.key, old.kind, old.order, old.job = nil, nil, nil, nil
        local _, err = draw({ mode = "live", live = live_model(), details = old, history_index = 1, history_count = 0 }, s)
        eq(err, nil, "no error")
        local bronze = false
        for _, r in ipairs(window_rects()) do bronze = bronze or r.col == C.bronze end
        eq(bronze, true, "the bronze line")

        -- hidden stays hidden even with details
        draw({ mode = "hidden", details = details_model(), history_index = 1, history_count = 0 }, s)
        eq(#ui.calls, 0, "hidden")
    end
end)

test("a notice is one dim line at the bottom of every view", function()
    for _, style in ipairs(STYLES) do
        local s = fresh(style)
        local notice = "Game update? 2 game methods not found"
        for _, state in ipairs({
            { mode = "live", live = live_model() },
            { mode = "summary", summary = summary_model(), history_index = 1, history_count = 1 },
            { mode = "live", live = live_model(), details = details_model() },
        }) do
            draw(state, s)
            eq(has_text(notice), false, style .. ": no notice without one: " .. state.mode)
            state.notice = notice
            draw(state, s)
            local list = texts()
            eq(list[#list], notice, "the last line: " .. state.mode)
            eq(index_of(list, notice), #list, "drawn once")
            eq(ui.texts()[#ui.texts()], notice, "the last text call of all")
            eq(ui.balanced(), true, "balanced")
        end
        -- the dim text colour, on no band
        draw({ mode = "live", live = live_model(), notice = notice }, s)
        eq(text_call(notice).col, C.dim, "the dim text colour")
        if style == "panel" then eq(text_call("Damage to party · 6 844").col, C.dim, "like a section title on the panel") end
        local at = text_call(notice)
        for _, r in ipairs(window_rects()) do
            eq(not (r.y0 <= at.y and at.y < r.y1), true, "nothing drawn behind the notice")
        end
        -- hidden stays hidden
        draw({ mode = "hidden", live = live_model(), notice = notice }, s)
        eq(#ui.calls, 0, "hidden draws nothing, notice or not")
    end
end)

test("summary draws the summary blocks", function()
    for _, style in ipairs(STYLES) do
        local s = fresh(style)
        draw({ mode = "summary", summary = summary_model(), history_index = 1, history_count = 1 }, s)
        eq(ui.balanced(), true, style .. ": balanced")
        local list = texts()
        local dealt, healed = heading(style, "Dealt", "103 428"), heading(style, "Healed", "8 243")
        for _, t in ipairs({ "Victory", "5:18", "Chimera", "0 / 80 000 HP", "Goblin ×3", "3 700 HP each",
            dealt, "Guts", "44 463 · 43%", "Allies", "Guard", "908", healed, "7 012 · 85%",
            "Enemy defence absorbed", "≈ 68 640 · 88%" }) do
            eq(index_of(list, t) ~= nil, true, "summary shows " .. t)
        end
        if style == "frameless" then
            eq(index_of(list, "103 428"), index_of(list, dealt) + 1, "the total after its title")
            eq(index_of(list, "8 243"), index_of(list, healed) + 1, "the healing total after its title")
        end
        -- section names come from i18n
        for _, key in ipairs({ "enemies", "armor" }) do
            eq(has_text(i18n.t(key)), true, "section " .. key)
        end
        -- the order of the sections
        local order = { i18n.t("enemies"), dealt, "Allies", healed, i18n.t("armor") }
        local last = 0
        for _, t in ipairs(order) do
            local at = index_of(list, t)
            eq(at > last, true, t .. " comes after the previous section")
            last = at
        end
        -- no bars for enemies and armor
        eq(#bar_of("Guts"), 2, "damage rows are bars")
        eq(#bar_of("Goblin ×3"), 0, "enemy rows are plain text")
        eq(#bar_of("Enemy defence absorbed"), 0, "armor rows are plain text")

        -- empty blocks are not drawn
        local m = summary_model()
        m.heal.rows = {}
        m.allies.rows = {}
        m.armor = {}
        m.enemies = {}
        draw({ mode = "summary", summary = m, history_index = 1, history_count = 1 }, s)
        for _, t in ipairs({ healed, "Allies", i18n.t("armor"), i18n.t("enemies") }) do
            eq(has_text(t), false, "empty block " .. t .. " left out")
        end
        eq(has_text(dealt), true, "the damage block stays")
    end
end)

test("allies follow show_allies in the fight window and summary_allies in the summary", function()
    local s = fresh()
    draw({ mode = "live", live = live_model(), history_index = 1, history_count = 0 }, s)
    eq(has_text("Guard"), true, "ally row shown by default")
    draw({ mode = "summary", summary = summary_model(), history_index = 1, history_count = 1 }, s)
    eq(has_text("Allies"), true, "ally block shown by default")

    s:set("show_allies", false)
    draw({ mode = "live", live = live_model(), history_index = 1, history_count = 0 }, s)
    eq(has_text("Guard"), false, "ally row hidden")
    eq(has_text("Guts"), true, "party rows stay")
    draw({ mode = "summary", summary = summary_model(), history_index = 1, history_count = 1 }, s)
    eq(has_text("Allies"), true, "the summary has a switch of its own: the block stays")
    eq(has_text("Guard"), true, "and its rows")

    s:set("show_allies", true)
    s:set("summary_allies", false)
    draw({ mode = "live", live = live_model(), history_index = 1, history_count = 0 }, s)
    eq(has_text("Guard"), true, "the fight window does not follow the summary's switch")
    draw({ mode = "summary", summary = summary_model(), history_index = 1, history_count = 1 }, s)
    eq(has_text("Allies"), false, "ally block hidden")
    eq(has_text("Guard"), false, "and its rows")
    eq(has_text("Guts"), true, "the party stays")
end)

local function other_row(value, fill, per_sec)
    return { key = "other", name = "Other", kind = "other", value = value, fill = fill, per_sec = per_sec }
end

test("Other rows are grey, stay when show_allies is off and follow live_other", function()
    for _, style in ipairs(STYLES) do
        local s = fresh(style)
        local live = live_model()
        table.insert(live.damage.rows, other_row("200", 0.5, "1/s"))
        table.insert(live.heal.rows, other_row("50", 0.25, "0/s"))
        local state = { mode = "live", live = live, history_index = 1, history_count = 0 }

        draw(state, s)
        eq(count_text("Other"), 2, style .. ": a damage row and a heal row")
        local d, h = bar_of("Other", 1), bar_of("Other", 2)
        eq(d[2].col, C.other, "the damage row is grey"); eq(h[2].col, C.other, "the heal row is grey too")
        eq(C.other ~= C.ally, true, "a grey of its own, not the allies'")
        near(width(d[2]), 0.5 * width(d[1]), 1e-6, "fill 0.5"); near(width(h[2]), 0.25 * width(h[1]), 1e-6, "fill 0.25")
        eq(has_text("200 · 1/s"), true, "numbers, no share"); eq(has_text("50 · 0/s"), true, "heal numbers")
        eq(index_of(texts(), "Other") > index_of(texts(), "Guard"), true, "after the ally row")

        -- the setting hides allies only
        s:set("show_allies", false)
        draw(state, s)
        eq(has_text("Guard"), false, "the ally is hidden")
        eq(count_text("Other"), 2, "both Other rows stay")
        eq(bar_of("Other", 1)[2].col, C.other, "still grey")
        eq(has_text("Guts"), true, "party rows stay")

        -- live_other hides the Other rows, in the damage block and the healing block alike, and nothing else
        s:set("show_allies", true)
        s:set("live_other", false)
        draw(state, s)
        eq(count_text("Other"), 0, style .. ": no Other row")
        eq(has_text("Guard"), true, "the ally stays"); eq(has_text("Guts"), true, "so do the party rows")
        eq(has_text("Yves"), true, "and the healer")
        eq(has_text(heading(style, "Healing", "8 243 · 26/s")), true, "the healing block keeps its title")
        s:set("show_allies", false)
        draw(state, s)
        eq(has_text("Guard"), false, "allies off as well"); eq(has_text("Guts"), true, "the party stays")

        -- the summary's switch does not hide the fight window's Other rows
        s:set("live_other", true)
        s:set("summary_other", false)
        draw(state, s)
        eq(count_text("Other"), 2, "summary_other is the summary's")
    end
end)

test("the summary's Other rows: with the allies, alone, and without party damage", function()
    local s = fresh()
    local m = summary_model()
    table.insert(m.allies.rows, other_row("200", 0.25))
    table.insert(m.heal.rows, other_row("50", 0.1))
    local state = { mode = "summary", summary = m, history_index = 1, history_count = 1 }

    draw(state, s)
    eq(count_text("Other"), 2, "a damage row and a heal row")
    local list = texts()
    eq(index_of(list, "Allies") < index_of(list, "Guard") and index_of(list, "Guard") < index_of(list, "Other"), true,
        "Other follows the allies rows")
    eq(index_of(list, "Other") < index_of(list, "Healed"), true, "and comes before the healing block")
    eq(bar_of("Other", 1)[2].col, C.other, "grey"); eq(bar_of("Other", 2)[2].col, C.other, "the heal row is grey too")
    eq(has_text("200"), true, "value without a share")

    -- allies off: the ally rows and their block go, Other stays under the damage block
    s:set("summary_allies", false)
    draw(state, s)
    list = texts()
    eq(has_text("Guard"), false, "ally hidden"); eq(has_text("Allies"), false, "ally block hidden")
    eq(count_text("Other"), 2, "both Other rows stay")
    eq(index_of(list, "Dealt") < index_of(list, "Other") and index_of(list, "Other") < index_of(list, "Healed"),
        true, "Other sits between the damage and healing blocks")
    eq(bar_of("Other", 1)[2].col, C.other, "still grey")
    s:set("show_allies", false)
    draw(state, s)
    eq(has_text("Allies"), false, "the fight window's switch is not the summary's"); eq(count_text("Other"), 2, "Other stays")
    s:set("show_allies", true)

    -- summary_other takes the Other rows away, in the allies block and in the healing block
    s:set("summary_allies", true)
    s:set("summary_other", false)
    draw(state, s)
    eq(count_text("Other"), 0, "no Other row"); eq(has_text("Guard"), true, "the ally stays")
    eq(has_text("Allies"), true, "with its heading"); eq(has_text("Yves"), true, "and the healer stays")
    s:set("summary_allies", false)
    draw(state, s)
    eq(has_text("Allies"), false, "nothing of the block is left"); eq(has_text("Guard"), false, "no ally")
    eq(has_text("Dealt"), true, "the party's damage stays"); eq(has_text("Guts"), true, "party")
    s:set("summary_other", true)
    s:set("summary_allies", false)

    -- Other is all the damage there is: it gets the damage heading
    m = summary_model()
    m.damage.rows, m.damage.total = {}, "0"
    m.allies.rows = { other_row("200", 1) }
    draw({ mode = "summary", summary = m, history_index = 1, history_count = 1 }, s)
    eq(has_text("Dealt"), true, "heading without a total"); eq(has_text("Allies"), false, "no allies heading")
    eq(count_text("Other"), 1, "the row")
    eq(index_of(texts(), "Dealt") < index_of(texts(), "Other"), true, "under the heading")
    -- allies shown and no party damage: the Allies heading, as before
    s:set("summary_allies", true)
    m.allies.rows = { { key = "ch300659_00", name = "Guard", kind = "ally", value = "908", fill = 1 }, other_row("200", 0.2) }
    draw({ mode = "summary", summary = m, history_index = 1, history_count = 1 }, s)
    eq(has_text("Allies"), true, "Allies heading"); eq(has_text("Dealt"), false, "no empty damage block")
    -- nothing to show at all: no heading
    s:set("summary_allies", false)
    m.allies.rows = { { key = "ch300659_00", name = "Guard", kind = "ally", value = "908", fill = 1 } }
    draw({ mode = "summary", summary = m, history_index = 1, history_count = 1 }, s)
    eq(has_text("Allies"), false, "only a hidden ally: no heading"); eq(has_text("Dealt"), false, "and no damage heading")
end)

test("an Other row is not a button: it has no details", function()
    for _, style in ipairs(STYLES) do
        local s = fresh(style)
        ui.drawing_ui = true
        local live = live_model()
        table.insert(live.damage.rows, other_row("200", 0.5, "1/s"))
        table.insert(live.heal.rows, other_row("50", 0.25, "0/s"))
        ui.press("damage:other"); ui.press("heal:other")
        local a = draw({ mode = "live", live = live, history_index = 1, history_count = 0 }, s)
        eq(a.select_actor, nil, style .. ": nothing selected")
        for _, b in ipairs(ui.calls_of("invisible_button")) do
            eq(b.id ~= "damage:other" and b.id ~= "heal:other", true, "no button " .. tostring(b.id))
        end
        eq(count_text("Other"), 2, "the rows are drawn all the same")
        -- real rows keep their buttons
        ui.press("damage:ch300659_00")
        a = draw({ mode = "live", live = live, history_index = 1, history_count = 0 }, s)
        eq(a.select_actor, "ch300659_00", "an ally row still opens its details")
    end
end)

test("switched-off live blocks are not drawn", function()
    for _, style in ipairs(STYLES) do
        local s = fresh(style)
        local state = { mode = "live", live = live_model(), history_index = 1, history_count = 0 }
        draw(state, s)
        eq(has_text(heading(style, "Damage to party", "6 844")), true, style .. ": all three blocks to begin with")

        s:set("live_taken", false)
        draw(state, s)
        eq(has_text(heading(style, "Damage to party", "6 844")), false, "no «Damage to party» title")
        eq(has_text("Chimera → Guts"), false, "and no rows")
        eq(has_text(heading(style, "Damage to enemies", "130 642 · 410/s")), true, "damage stays")
        eq(has_text(heading(style, "Healing", "8 243 · 26/s")), true, "healing stays")
        eq(has_text("Chimera"), true, "the header stays")
        eq(ui.balanced(), true, "balanced")

        s:set("live_taken", true)
        s:set("live_damage", false)
        draw(state, s)
        eq(has_text(heading(style, "Damage to enemies", "130 642 · 410/s")), false, "no damage title")
        eq(count_text("Guts"), 0, "no damage rows"); eq(has_text("Guard"), false, "nor allies")
        eq(has_text("Chimera → Guts"), true, "taken stays"); eq(count_text("Yves"), 1, "the healer stays")

        s:set("live_damage", true)
        s:set("live_heal", false)
        draw(state, s)
        eq(has_text(heading(style, "Healing", "8 243 · 26/s")), false, "no healing title")
        eq(count_text("Yves"), 1, "only the damage row of Yves is left"); eq(has_text("Guts"), true, "damage stays")

        -- all off: the header alone
        s:set("live_damage", false); s:set("live_taken", false)
        draw(state, s)
        eq(#ui.calls_of("begin_window"), 1, "the window is still drawn")
        eq(#texts(), 3, "the header's title, HP and time are all that is left")
        eq(has_text("Chimera") and has_text("31 200 / 80 000") and has_text("5:18"), true, "the header")

        -- a block the model does not have is not drawn, and is no error, whatever the setting says
        s:set("live_damage", true); s:set("live_taken", true); s:set("live_heal", true)
        local m = live_model()
        m.taken, m.heal = nil, nil
        local _, err = draw({ mode = "live", live = m, history_index = 1, history_count = 0 }, s)
        eq(err, nil, "no error")
        eq(has_text(heading(style, "Damage to party", "6 844")), false, "no taken block in the model")
        eq(has_text(heading(style, "Healing", "8 243 · 26/s")), false, "no healing block in the model")
        eq(has_text("Guts"), true, "damage is drawn")
        m.damage = nil
        _, err = draw({ mode = "live", live = m, history_index = 1, history_count = 0 }, s)
        eq(err, nil, "a model with the header only draws"); eq(has_text("Chimera"), true, "the header")
    end
end)

test("switched-off summary blocks are not drawn", function()
    for _, style in ipairs(STYLES) do
        local s = fresh(style)
        local state = { mode = "summary", summary = summary_model(), history_index = 1, history_count = 1 }
        local dealt, healed = heading(style, "Dealt", "103 428"), heading(style, "Healed", "8 243")

        s:set("summary_enemies", false)
        draw(state, s)
        eq(has_text(i18n.t("enemies")), false, style .. ": no enemies title"); eq(has_text("Goblin ×3"), false, "no enemy rows")
        eq(has_text(dealt) and has_text(healed) and has_text(i18n.t("armor")), true, "the other blocks stay")
        eq(has_text("Victory"), true, "the header stays")

        s:set("summary_enemies", true)
        s:set("summary_damage", false)
        draw(state, s)
        eq(has_text(dealt), false, "no damage title"); eq(has_text("Guts"), false, "no party rows")
        eq(has_text("Allies"), true, "the allies block has a switch of its own"); eq(has_text("Guard"), true, "so has its row")
        eq(has_text(healed), true, "healing stays")

        s:set("summary_damage", true)
        s:set("summary_heal", false)
        draw(state, s)
        eq(has_text(healed), false, "no healing title"); eq(has_text("Yves"), false, "no healer")
        eq(has_text(dealt), true, "damage stays")

        s:set("summary_heal", true)
        s:set("summary_armor", false)
        draw(state, s)
        eq(has_text(i18n.t("armor")), false, "no armor title"); eq(has_text("Enemy defence absorbed"), false, "no armor row")
        eq(has_text(healed), true, "healing stays")

        -- everything off: the header alone
        for _, key in ipairs({ "summary_enemies", "summary_damage", "summary_heal", "summary_allies" }) do s:set(key, false) end
        draw(state, s)
        eq(#texts(), 2, "the title and the time are all that is left")
        eq(has_text("Victory") and has_text("5:18"), true, "the header")
        eq(ui.balanced(), true, "balanced")

        -- a block the model does not have is not drawn, whatever the setting says
        for _, key in ipairs({ "summary_enemies", "summary_damage", "summary_heal", "summary_allies", "summary_armor" }) do
            s:set(key, true)
        end
        local m = summary_model()
        m.enemies, m.heal, m.armor, m.allies = nil, nil, nil, nil
        local _, err = draw({ mode = "summary", summary = m, history_index = 1, history_count = 1 }, s)
        eq(err, nil, "no error")
        eq(has_text(dealt), true, "damage is drawn"); eq(has_text(healed), false, "no healing in the model")
        eq(has_text(i18n.t("enemies")) or has_text("Allies") or has_text(i18n.t("armor")), false, "nor the others")
        m.damage = nil
        _, err = draw({ mode = "summary", summary = m, history_index = 1, history_count = 1 }, s)
        eq(err, nil, "a model with the title only draws"); eq(has_text("Victory"), true, "the title")

        -- the damage block off and Other the only grey row: it still has a heading
        s:set("summary_allies", false)
        m = summary_model()
        m.damage = nil
        m.allies.rows = { other_row("200", 0.5) }
        draw({ mode = "summary", summary = m, history_index = 1, history_count = 1 }, s)
        eq(has_text("Allies"), false, "no allies heading"); eq(count_text("Other"), 1, "the Other row")
        eq(has_text("Dealt"), true, "under the damage heading")
        eq(index_of(texts(), "Dealt") < index_of(texts(), "Other"), true, "above it")
    end
end)

test("no damage types in the summary", function()
    for _, style in ipairs(STYLES) do
        local s = fresh(style)
        local m = summary_model()
        -- a v1 model still carrying its types draws without them
        m.types = { { label = "Slash", share = "78%", fill = 1 }, { label = "Magic", share = "12%", fill = 0.15 } }
        local _, err = draw({ mode = "summary", summary = m, history_index = 1, history_count = 1 }, s)
        eq(err, nil, style .. ": no error")
        eq(has_text("Damage types"), false, "no «Damage types» title")
        eq(has_text("Slash") or has_text("Magic") or has_text("78%"), false, "no type rows")
        eq(has_text(heading(style, "Healed", "8 243")), true, "the rest of the summary is there")
        i18n.set("ru")
        draw({ mode = "summary", summary = m, history_index = 1, history_count = 1 }, s)
        eq(has_text("Типы урона"), false, "nor in Russian")
        i18n.set("en")
    end
end)

test("frameless: light text with a shadow, outlined numbers, no background", function()
    local s = fresh()
    eq(s.values.style, "frameless", "the default look")
    draw({ mode = "live", live = live_model(), history_index = 1, history_count = 0 }, s)
    eq(#background_rects(), 0, "nothing behind the text: no panel, the halo is off by default")
    eq(#ui.calls_of("push_style_color"), 1, "one colour pushed")
    eq(ui.calls_of("push_style_color")[1][1], 5, "the border colour (ImGuiCol_Border)...")
    eq(ui.calls_of("push_style_color")[1][2] >> 24, 0, "...made transparent")

    eq(text_call("Guts").col, C.text, "names in the light text colour")
    eq(text_call("52 898 · 166/s · 40%").col, C.text, "numbers too")
    eq(text_call("Damage to party").col, C.block.enemies.title, "block titles in their block's colour")
    eq(C.text, 0xFFD4E4EC, "text #ECE4D4")
    eq(C.dim, 0xFFA8C4D2, "dim #D2C4A8")

    -- a name: nine shadow copies under it, the strongest one step down-right at the shadow's strength
    local name = copies_of("Guts")
    eq(#name, 9, "nine shadow copies")
    local main = text_call("Guts")
    eq(name[1].x, main.x + 1, "the first copy one pixel right"); eq(name[1].y, main.y + 1, "and down")
    eq(name[1].col >> 24, math.floor(255 * 0.8 + 0.5), "at the shadow's strength 0.8")
    -- a number: the shadow and the outline (one step all around) in one set of nine copies, one per offset, each as
    -- dark as the shadow's copy and the outline's together
    local number = "52 898 · 166/s · 40%"
    local num, at = copies_of(number), text_call(number)
    eq(#num, 9, "nine copies: the eight around it and the far shadow")
    local weight = { ["1,1"] = 1.0, ["2,2"] = 0.45, ["-1,0"] = 0.5, ["1,0"] = 0.5, ["0,-1"] = 0.5, ["0,1"] = 0.6,
        ["-1,-1"] = 0.3, ["1,-1"] = 0.3, ["-1,1"] = 0.3 }
    local seen = {}
    for _, c in ipairs(num) do
        local key = string.format("%d,%d", math.floor(c.x - at.x + 0.5), math.floor(c.y - at.y + 0.5))
        eq(weight[key] ~= nil and not seen[key], true, "one copy at " .. key)
        seen[key] = true
        local ring = key == "2,2" and 0 or 225 / 255
        local want = math.floor(255 * (1 - (1 - math.min(1, 0.8 * weight[key])) * (1 - ring)) + 0.5)
        eq(c.col >> 24, want, "the shadow and the outline together at " .. key)
    end
    eq(#copies_of("31 200 / 80 000"), 9, "the enemy's HP is a number")
    eq(#copies_of("5:18"), 9, "the time too")
    local title = copies_of("Damage to party")
    eq(#title, 9, "a title has the shadow only")
    eq(title[1].col >> 24, 204, "not the outline's darkness")
    -- every text costs ten calls: itself and nine copies
    local list = texts()
    eq(#ui.calls_of("add_text"), 10 * #list, "ten add_text calls per text")
    eq(#ui.calls_of("add_text"), 250, "250 for this live window (25 texts: the three totals are texts of their own)")

    -- weaker shadow: weaker copies; none at 0; no outline when off
    s:set("shadow", 0.5)
    draw({ mode = "live", live = live_model(), history_index = 1, history_count = 0 }, s)
    eq(copies_of("Guts")[1].col >> 24, 128, "shadow 0.5")
    s:set("shadow", 0)
    draw({ mode = "live", live = live_model(), history_index = 1, history_count = 0 }, s)
    eq(#copies_of("Guts"), 0, "no shadow")
    eq(#copies_of("3 817"), 8, "the outline stays")
    for _, c in ipairs(copies_of("3 817")) do eq(c.col >> 24, 225, "the outline's own darkness") end
    s:set("outline", false)
    draw({ mode = "live", live = live_model(), history_index = 1, history_count = 0 }, s)
    eq(#copies_of("3 817"), 0, "nothing but the text")
    s:set("shadow", 0.8)
    draw({ mode = "live", live = live_model(), history_index = 1, history_count = 0 }, s)
    eq(#copies_of("3 817"), 9, "the shadow only")
    eq(copies_of("3 817")[1].col >> 24, 204, "as for a name")
end)

test("texts are measured once per model and font size; positions go in reused tables", function()
    for _, style in ipairs(STYLES) do
        local s = fresh(style)
        local calc, measured = imgui.calc_text_size, 0
        imgui.calc_text_size = function(t)
            measured = measured + 1
            return calc(t)
        end
        local long = live_model()
        long.damage.rows[1].name = string.rep("Immensely Long Name ", 8) -- fit() measures many cuts of it
        local state = { mode = "live", live = long, history_index = 1, history_count = 0, notice = "A notice" }
        draw(state, s)
        eq(measured > 0, true, style .. ": measured on the first frame")
        local x = text_call("52 898 · 166/s · 40%").x
        local cut
        for _, t in ipairs(texts()) do if t:sub(1, 9) == "Immensely" then cut = t end end
        measured = 0
        draw(state, s)
        eq(measured, 0, "nothing measured again for the same model")
        eq(text_call("52 898 · 166/s · 40%").x, x, "the same layout")
        eq(has_text(cut), true, "the same cut name")
        -- a new model (the live window rebuilds it a few times a second), a new font size
        state.live = live_model()
        draw(state, s)
        eq(measured > 0, true, "a new model is measured")
        measured = 0
        s:set("scale", 1.5)
        draw(state, s)
        eq(measured > 0, true, "so is a new scale")
        measured = 0
        draw(state, s)
        eq(measured, 0, "and then kept")
        -- the summary and the details the same way
        local summary = { mode = "summary", summary = summary_model(), history_index = 2, history_count = 3 }
        draw(summary, s)
        measured = 0
        draw(summary, s)
        eq(measured, 0, "summary")
        local details = { mode = "live", live = live_model(), details = details_model(), history_index = 1, history_count = 0 }
        draw(details, s)
        measured = 0
        draw(details, s)
        eq(measured, 0, "details")
        imgui.calc_text_size = calc

        -- every rectangle and text position is one of a few tables, filled anew for each call
        s:set("halo", true)
        draw(state, s)
        local tables, n = {}, 0
        for _, c in ipairs(ui.calls) do
            local list = c.fn == "add_rect_filled" and { c[1], c[2] } or c.fn == "add_text" and { c[1] } or {}
            for _, t in ipairs(list) do
                if not tables[t] then
                    tables[t], n = true, n + 1
                end
            end
        end
        eq(n <= 3, true, "three tables for all positions, got " .. n)
    end
end)

test("the details table: cells are numbers, its headings are not", function()
    for _, style in ipairs(STYLES) do
        local s = fresh(style)
        s:set("shadow", 0) -- the outline alone shows what is drawn as a number
        draw({ mode = "live", live = live_model(), details = details_model(), history_index = 1, history_count = 0 }, s)
        for _, key in ipairs({ "details_hits", "details_total", "details_max", "details_perfect" }) do
            eq(#copies_of(i18n.t(key)), 0, style .. ": heading " .. key .. " has no outline")
        end
        eq(#copies_of("%"), 0, "nor the % heading")
        eq(#copies_of("9 100"), 8, "a cell is outlined")
        eq(#copies_of("Wild Fury"), 0, "a skill name is not")
        eq(#copies_of("55 000"), 8, "an extra line's number is")
    end
end)

test("frameless: a bronze line under the header, thin bars on a dark track under the names", function()
    local s = fresh()
    draw({ mode = "live", live = live_model(), history_index = 1, history_count = 0 }, s)
    local line
    for _, r in ipairs(window_rects()) do
        if r.col == C.bronze then line = r end
    end
    eq(line ~= nil, true, "a bronze line")
    eq(C.bronze & 0xFFFFFF, 0x5F96BE, "bronze #BE965F")
    eq(height(line), 1, "one pixel")
    near(width(line), 340, 1e-9, "as wide as the window")
    eq(line.y0 > text_call("Chimera").y and line.y1 < text_call("Damage to enemies").y, true,
        "between the header and the first block")

    -- the bar: a 3 px track under the name and the numbers, the coloured part on it
    local name = text_call("Guts")
    local bar = bar_of("Guts")
    eq(bar[1].col, C.track, "the dark track")
    eq(height(bar[1]), 3, "3 px by default")
    eq(height(bar[2]), 3, "the coloured part too")
    eq(bar[1].y0 >= name.y + 14, true, "under the text")
    eq(bar[1].x0, name.x, "starting where the name starts")
    local numbers = text_call("52 898 · 166/s · 40%")
    near(numbers.x + text_w("52 898 · 166/s · 40%"), bar[1].x1, 1e-6, "the numbers end where the bar ends")
    -- the track's 1 px dark edge
    local edges = 0
    for _, r in ipairs(window_rects()) do
        if (r.col & 0xFFFFFF) == (C.shadow & 0xFFFFFF) and r.col ~= C.track
            and ((r.y1 == bar[1].y0 and height(r) == 1) or (r.y0 == bar[1].y1 and height(r) == 1)) then
            edges = edges + 1
        end
    end
    eq(edges >= 2, true, "an edge above and below the track")
    -- rounding 0 everywhere: square, like the game
    for _, r in ipairs(window_rects()) do eq(r.rounding, 0, "square corners") end

    -- the thickness follows bar_px and the scale
    s:set("bar_px", 6)
    draw({ mode = "live", live = live_model(), history_index = 1, history_count = 0 }, s)
    eq(height(bar_of("Guts")[1]), 6, "6 px")
    -- however thick, the bar, its edge and its shadow stay inside the row (the button with the menu open)
    s:set("bar_px", 8)
    draw({ mode = "live", live = live_model(), history_index = 1, history_count = 0 }, s)
    local it, thick = row_item(text_call("Guts")), bar_of("Guts")[1]
    eq(height(thick), 8, "8 px")
    eq(thick.y1 + 1 <= it.y + it.h, true, "the bottom edge and the shadow inside the row")
    eq(thick.y0 - 1 >= text_call("Guts").y + 14, true, "the top edge below the text")
    s:set("bar_px", 1)
    draw({ mode = "live", live = live_model(), history_index = 1, history_count = 0 }, s)
    eq(height(bar_of("Guts")[1]), 1, "1 px")
    eq(height(bar_of("Guts")[2]), 1, "the coloured part too")
    s:set("bar_px", 3)
    s:set("scale", 2)
    draw({ mode = "live", live = live_model(), history_index = 1, history_count = 0 }, s)
    eq(height(bar_of("Guts")[1]), 6, "3 px at scale 2")
    eq(ui.balanced(), true, "balanced")
end)

-- Where the window's content starts and how wide it is at scale 1 (the stub's window at 40, 300 and its 8 px padding).
local X0, W = 48, 340

-- The band under the text `title` (frameless): its solid part, its fading part (the gradient call) and its mark.
local function band_of(title, nth)
    local t = text_call(title, nth)
    local solid, fade, mark
    for _, c in ipairs(ui.calls) do
        if c.layer == "window" and c.y0 and c.y0 <= t.y and t.y < c.y1 then
            if c.fn == "add_rect_filled_multi_color" then
                fade = c
            elseif c.fn == "add_rect_filled" and c.col == C.band then
                solid = c
            elseif c.fn == "add_rect_filled" and width(c) == 3 then
                mark = c
            end
        end
    end
    return solid, fade, mark
end

-- The index of a layout item and the item, for the item a text was drawn in.
local function item_of(t)
    for i, it in ipairs(ui.items) do
        if it.y <= t.y and t.y < it.y + it.h then return i, it end
    end
end

test("frameless: each block starts on a dark fading band with a coloured mark, its title and its total", function()
    local s = fresh()
    local B = C.block
    eq(C.band, 0x96080B0E, "the band: #0E0B08 at alpha 150")
    eq(B.damage.mark & 0xFFFFFF, 0x5F96BE, "damage: bronze mark"); eq(B.damage.title, 0xFF7AB2D6, "gold title #D6B27A")
    eq(B.enemies.mark & 0xFFFFFF, 0xA65C8D, "enemies: purple mark"); eq(B.enemies.title, 0xFFDAA9C9, "#C9A9DA")
    eq(B.heal.mark, 0xFF6A9E7F, "healing: green mark #7F9E6A"); eq(B.heal.title, 0xFF9BCBB7, "light green #B7CB9B")
    eq(B.other.mark, 0xFF405A6E, "the others: dark bronze #6E5A40"); eq(B.other.title, C.dim, "dim title")
    for _, view in ipairs({ "live", "summary" }) do
        local state = view == "live" and { mode = "live", live = live_model() }
            or { mode = "summary", summary = summary_model(), history_index = 1, history_count = 1 }
        draw(state, s)
        local cases = view == "live" and {
            { title = "Damage to enemies", total = "130 642 · 410/s", block = B.damage, first = true },
            { title = "Damage to party", total = "6 844", block = B.enemies },
            { title = "Healing", total = "8 243 · 26/s", block = B.heal },
        } or {
            { title = i18n.t("enemies"), block = B.enemies, first = true },
            { title = "Dealt", total = "103 428", block = B.damage },
            { title = "Allies", block = B.other },
            { title = "Healed", total = "8 243", block = B.heal },
            { title = i18n.t("armor"), block = B.other },
        }
        for _, case in ipairs(cases) do
            local what = view .. " " .. case.title
            local solid, fade, mark = band_of(case.title)
            eq(solid ~= nil and fade ~= nil and mark ~= nil, true, what .. ": a band, its fading part and a mark")
            -- solid over 65 % of the width, then fading out to the right edge
            eq(solid.x0, X0, what .. ": from the left edge"); near(solid.x1, X0 + 0.65 * W, 1e-9, "solid to 65 %")
            eq(height(solid), 20, "20 px high"); eq(solid.rounding, 0, "square")
            near(fade.x0, solid.x1, 1e-9, "the fade goes on from there"); near(fade.x1, X0 + W, 1e-9, "to the right edge")
            eq(fade.y0, solid.y0, "same top"); eq(fade.y1, solid.y1, "same bottom")
            eq(fade.ul, C.band, "dark at its left"); eq(fade.bl, C.band, "")
            eq(fade.ur, C.band & 0xFFFFFF, "clear at its right"); eq(fade.br, C.band & 0xFFFFFF, "")
            -- the mark: 3 px, opaque, in the block's colour, at the left edge
            eq(mark.x0, X0, "the mark at the left edge"); eq(height(mark), 20, "as high as the band")
            eq(mark.col, case.block.mark, what .. ": the block's mark colour"); eq(mark.col >> 24, 255, "opaque")
            -- the title: 8 px in, in the block's colour, in the middle of the band, with a shadow but no outline
            local t = text_call(case.title)
            eq(t.x, X0 + 8, "the title 8 px in"); eq(t.col, case.block.title, what .. ": the block's title colour")
            eq(t.y, solid.y0 + 3, "in the middle of the band")
            eq(#copies_of(case.title), 9, "shadowed"); eq(copies_of(case.title)[1].col >> 24, 204, "not outlined")
            -- the total: on the band, flush right, light, outlined
            if case.total then
                local n = text_call(case.total)
                near(n.x + text_w(case.total), X0 + W, 1e-9, "the total flush right"); eq(n.y, t.y, "on the band")
                eq(n.col, C.text, "light"); eq(copies_of(case.total)[1].col >> 24, 249, "outlined")
            end
            -- drawn first: the band is under its texts
            local _, at = text_call(case.title)
            local before = false
            for i = 1, at do before = before or ui.calls[i] == solid end
            eq(before, true, "the band is drawn before the title")
            -- the gap above: 6 px under the header's line for the first block, 10 px after a row for the others; the
            -- first row 4 px under the band
            local i, it = item_of(t)
            local prev, next_item = ui.items[i - 1], ui.items[i + 1]
            if case.first then
                local line
                for _, r in ipairs(window_rects()) do if r.col == C.bronze then line = r end end
                eq(solid.y0 - line.y1, 9, what .. ": 3 px under the line, then 6 px")
            else
                eq(solid.y0 - (prev.y + prev.h), 10, what .. ": 10 px after the row above")
            end
            eq(next_item.y, solid.y1 + 4, what .. ": the first row 4 px under the band")
        end
    end

    -- with the menu open the band and the header are no buttons (the window is dragged by them)
    ui.drawing_ui = true
    draw({ mode = "live", live = live_model(), history_index = 1, history_count = 0 }, s)
    for _, title in ipairs({ "Damage to enemies", "Damage to party", "Healing" }) do
        local solid = band_of(title)
        for _, b in ipairs(ui.calls_of("invisible_button")) do
            eq(b.y + b.h <= solid.y0 or b.y >= solid.y1, true, title .. ": no button on the band: " .. b.id)
        end
    end
    local _, header = item_of(text_call("Chimera"))
    for _, b in ipairs(ui.calls_of("invisible_button")) do
        eq(b.id == "hide" or b.y >= header.y + header.h, true, "nothing in the header is a button but ×: " .. b.id)
    end
end)

test("frameless: a REFramework without the gradient call draws the fade in steps", function()
    local s = fresh()
    draw({ mode = "live", live = live_model(), history_index = 1, history_count = 0 }, s)
    eq(#Overlay.missing(), 0, "nothing missing")
    local multi = ui.draw_list.add_rect_filled_multi_color
    ui.draw_list.add_rect_filled_multi_color = nil
    local _, err = draw({ mode = "live", live = live_model(), history_index = 1, history_count = 0 }, s)
    eq(err, nil, "no error")
    local missing = Overlay.missing()
    eq(table.concat(missing, ","), "add_rect_filled_multi_color", "the missing call is named")
    missing[1] = "changed"
    eq(Overlay.missing()[1], "add_rect_filled_multi_color", "a copy")
    local solid = band_of("Damage to enemies")
    local steps = {}
    for _, r in ipairs(window_rects()) do
        if r.y0 == solid.y0 and r.y1 == solid.y1 and (r.col & 0xFFFFFF) == (C.band & 0xFFFFFF) and r ~= solid then
            steps[#steps + 1] = r
        end
    end
    eq(#steps, 4, "four steps")
    near(steps[1].x0, solid.x1, 1e-9, "from where the solid part ends"); near(steps[4].x1, X0 + W, 1e-9, "to the edge")
    for i = 2, 4 do eq(steps[i].col >> 24 < steps[i - 1].col >> 24, true, "each one lighter") end
    eq(steps[1].col >> 24 < 150, true, "lighter than the solid part")
    -- not tried again once it failed, until the overlay is reset
    ui.draw_list.add_rect_filled_multi_color = multi
    draw({ mode = "live", live = live_model(), history_index = 1, history_count = 0 }, s)
    eq(#ui.calls_of("add_rect_filled_multi_color"), 0, "still the steps")
    Overlay.reset()
    eq(#Overlay.missing(), 0, "forgotten by a reset")
    draw({ mode = "live", live = live_model(), history_index = 1, history_count = 0 }, s)
    eq(#ui.calls_of("add_rect_filled_multi_color"), 3, "the gradient again, one per block")
end)

test("frameless: rows 8 px in, numbers flush right, the damage to the party in light purple", function()
    local s = fresh()
    draw({ mode = "live", live = live_model(), history_index = 1, history_count = 0 }, s)
    for _, name in ipairs({ "Guts", "Guard", "Chimera → Guts" }) do
        local t, bar = text_call(name), bar_of(name)
        eq(t.x, X0 + 8, name .. ": 8 px in"); eq(bar[1].x0, X0 + 8, "its bar too"); near(bar[1].x1, X0 + W, 1e-9, "to the edge")
    end
    eq(text_call("Yves", 2).x, X0 + 8, "a healer too")
    near(text_call("3 817").x + text_w("3 817"), X0 + W, 1e-9, "numbers flush right")
    eq(text_call("Chimera → Guts").col, C.enemy_label, "who hit whom: light purple")
    eq(C.enemy_label, 0xFFDAA9C9, "#C9A9DA")
    eq(text_call("3 817").col, C.text, "the number stays light")
    eq(text_call("Guts").col, C.text, "a party name stays light")
    -- the summary's armor too
    draw({ mode = "summary", summary = summary_model(), history_index = 1, history_count = 1 }, s)
    eq(text_call("Enemy defence absorbed").x, X0 + 8, "armor 8 px in")
    near(text_call("≈ 68 640 · 88%").x + text_w("≈ 68 640 · 88%"), X0 + W, 1e-9, "its value flush right")
    eq(row_item(text_call("Enemy defence absorbed")).h, 20, "armor rows 20 px")
end)

test("frameless: summary enemies have a purple diamond, hollow with a dim name once killed", function()
    local s = fresh()
    draw({ mode = "summary", summary = summary_model(), history_index = 1, history_count = 1 }, s)
    local function quads_at(t)
        local _, it = item_of(t)
        local list = {}
        for _, c in ipairs(ui.calls) do
            if (c.fn == "add_quad_filled" or c.fn == "add_quad") and c.points[1].y >= it.y and c.points[3].y <= it.y + it.h then
                list[#list + 1] = c
            end
        end
        return list, it
    end
    -- alive: a dark diamond one pixel larger, the purple one on it; the name light purple, 20 px in
    local goblin = text_call("Goblin ×3")
    local q, it = quads_at(goblin)
    eq(#q, 2, "two calls"); eq(q[1].fn, "add_quad_filled", "filled"); eq(q[2].fn, "add_quad_filled", "filled")
    eq(q[2].col, C.enemy, "purple"); eq(brightness(q[1].col) < 30, true, "the dark edge under it")
    local cx, cy = X0 + 8 + 3.5, it.y + it.h / 2
    local p = q[2].points
    near(p[1].x, cx, 1e-9, "top"); near(p[1].y, cy - 3.5, 1e-9, ""); near(p[2].x, cx + 3.5, 1e-9, "right")
    near(p[3].y, cy + 3.5, 1e-9, "bottom"); near(p[4].x, cx - 3.5, 1e-9, "left: 7 px across")
    near(q[1].points[2].x, cx + 4.5, 1e-9, "the dark one 1 px larger")
    eq(goblin.x, X0 + 20, "the name 20 px in"); eq(goblin.col, C.enemy_label, "light purple")
    eq(text_call("3 700 HP each").col, C.dim, "the HP dim")
    near(text_call("3 700 HP each").x + text_w("3 700 HP each"), X0 + W, 1e-9, "flush right")
    eq(it.h, 20, "a 20 px row"); eq(#bar_of("Goblin ×3"), 0, "no bar")
    -- killed: only the outline (a dark one under the purple one), the name dim
    local chimera = text_call("Chimera")
    q = quads_at(chimera)
    eq(#q, 2, "two calls"); eq(q[1].fn, "add_quad", "outline"); eq(q[2].fn, "add_quad", "outline")
    eq(q[2].col, C.enemy, "purple"); eq(chimera.col, C.dim, "the name dim")
    -- a REFramework without the quad calls: small squares instead, no error
    local filled, outline = ui.draw_list.add_quad_filled, ui.draw_list.add_quad
    ui.draw_list.add_quad_filled, ui.draw_list.add_quad = nil, nil
    Overlay.reset()
    local _, err = draw({ mode = "summary", summary = summary_model(), history_index = 1, history_count = 1 }, s)
    ui.draw_list.add_quad_filled, ui.draw_list.add_quad = filled, outline
    eq(err, nil, "no error")
    eq(table.concat(Overlay.missing(), ","), "add_quad,add_quad_filled", "both named, in order")
    local _, row = item_of(text_call("Goblin ×3"))
    local squares = 0
    for _, r in ipairs(window_rects()) do
        if r.y0 >= row.y and r.y1 <= row.y + row.h and r.x1 <= X0 + 20 and r.col == C.enemy then squares = squares + 1 end
    end
    eq(squares >= 1, true, "a purple square")
    Overlay.reset()
end)

test("frameless: the header is 24 px with its title at 16 px", function()
    local s = fresh()
    local calc, sizes = imgui.calc_text_size, {}
    imgui.calc_text_size = function(t)
        sizes[t] = ui.fonts[#ui.fonts]
        return calc(t)
    end
    draw({ mode = "live", live = live_model(), history_index = 1, history_count = 0 }, s)
    imgui.calc_text_size = calc
    local title, time, hp = text_call("Chimera"), text_call("5:18"), text_call("31 200 / 80 000")
    eq(title.px, 16, "the title at 16 px"); eq(time.px, 14, "the time at 14 px"); eq(hp.px, 14, "the HP at 14 px")
    eq(sizes["Chimera"], 16, "measured at the size it is drawn at"); eq(sizes["5:18"], 14, "")
    local header = ui.items[1]
    eq(header.h, 24, "24 px high"); eq(title.y, header.y + 4, "the title in its middle"); eq(time.y, header.y + 5, "")
    near(hp.x, title.x + text_w("Chimera") * 16 / 14 + 4, 1e-9, "the HP after the title, at its width at 16 px")
    eq(ui.balanced(), true, "balanced")
    -- the same text as the title and as a row: measured at each size
    local at = {}
    imgui.calc_text_size = function(t)
        at[t] = at[t] or {}
        at[t][ui.fonts[#ui.fonts]] = true
        return calc(t)
    end
    local same = live_model()
    same.header.title = "Guts"
    draw({ mode = "live", live = same, history_index = 1, history_count = 0 }, s)
    imgui.calc_text_size = calc
    eq(at["Guts"] and at["Guts"][16] and at["Guts"][14], true, "measured at 16 px for the title and at 14 px for the row")
    -- the details' name too
    draw({ mode = "live", live = live_model(), details = details_model(), history_index = 1, history_count = 0 }, s)
    eq(text_call("Yves").px, 16, "the details' name at 16 px")
    -- scale 2: 32 px
    s:set("scale", 2)
    draw({ mode = "live", live = live_model(), history_index = 1, history_count = 0 }, s)
    eq(text_call("Chimera").px, 32, "at scale 2"); eq(ui.items[1].h, 48, "48 px high")
end)

test("frameless details: the headings on a band without a mark, 20 px rows, every second row faintly banded", function()
    local s = fresh()
    draw({ mode = "live", live = live_model(), details = details_model(), history_index = 1, history_count = 0 }, s)
    local head = i18n.t("details_total")
    local solid, fade, mark = band_of(head)
    eq(solid ~= nil and fade ~= nil, true, "the headings on a band")
    eq(mark, nil, "without a mark")
    eq(text_call(head).col, C.dim, "dim headings")
    eq(row_item(text_call("Normal attacks")).h, 20, "20 px rows")
    eq(text_call("Normal attacks").x, X0 + 8, "skill names 8 px in")
    local function banded(label)
        local t = text_call(label)
        for _, r in ipairs(window_rects()) do
            if r.col == C.even_row and r.y0 <= t.y and t.y < r.y1 and r.x0 == X0 then return true end
        end
        return false
    end
    eq(C.even_row, 0x32080B0E, "#0E0B08 at alpha 50")
    eq(banded("Normal attacks"), false, "the first row: none")
    eq(banded("Wild Fury"), true, "the second row: a faint band")
end)

test("panel keeps its look: no bands, no diamonds, the title at 14 px", function()
    local s = fresh("panel")
    draw({ mode = "live", live = live_model(), history_index = 1, history_count = 0 }, s)
    eq(#ui.calls_of("add_rect_filled_multi_color"), 0, "no bands")
    eq(text_call("Chimera").px, 14, "the title at 14 px"); eq(ui.items[1].h, 20, "a 20 px header")
    eq(text_call("Damage to enemies · 130 642 · 410/s").col, C.dim, "a dim title with its total")
    eq(text_call("Chimera → Guts").col, C.text, "light labels")
    eq(text_call("Guts").x, X0 + 6, "texts 6 px into the bar")
    draw({ mode = "summary", summary = summary_model(), history_index = 1, history_count = 1 }, s)
    eq(#ui.calls_of("add_quad_filled") + #ui.calls_of("add_quad"), 0, "no diamonds")
    eq(text_call("Goblin ×3").x, X0 + 6, "enemies as plain rows"); eq(text_call("Goblin ×3").col, C.text, "")
    draw({ mode = "live", live = live_model(), details = details_model(), history_index = 1, history_count = 0 }, s)
    for _, r in ipairs(window_rects()) do eq(r.col ~= C.even_row and r.col ~= C.band, true, "no bands in the details") end
end)

test("frameless: the halo, when on, darkens the scene behind the text as much as the opacity says", function()
    local s = fresh()
    s:set("halo", true)
    draw({ mode = "live", live = live_model(), history_index = 1, history_count = 0 }, s)
    local layers = background_rects()
    eq(#layers, 8, "eight soft layers on the background layer")
    local alpha = layers[1].col >> 24
    eq(alpha, math.floor(255 * (1 - (1 - 0.78) ^ (1 / 8)) + 0.5), "together as dark as the opacity 0.78")
    for i, r in ipairs(layers) do
        eq(r.col, layers[1].col, "one colour")
        eq(brightness(r.col) < 3 * 0x20, true, "a dark colour")
        eq(r.rounding > 0, true, "rounded: the edges fade")
        if i > 1 then eq(r.x0 < layers[i - 1].x0 and r.y1 > layers[i - 1].y1, true, "each one larger") end
    end
    -- the innermost layer covers every text
    for _, c in ipairs(ui.calls_of("add_text")) do
        if not is_copy(c) then
            eq(c.x >= layers[1].x0 and c.y >= layers[1].y0 and c.y < layers[1].y1, true, "behind " .. c.text)
        end
    end
    -- the opacity drives it
    s:set("opacity", 0.4)
    draw({ mode = "live", live = live_model(), history_index = 1, history_count = 0 }, s)
    eq(background_rects()[1].col >> 24, math.floor(255 * (1 - 0.6 ^ (1 / 8)) + 0.5), "opacity 0.4: lighter")
    -- in every view
    draw({ mode = "summary", summary = summary_model(), history_index = 1, history_count = 1 }, s)
    eq(#background_rects(), 8, "summary")
    draw({ mode = "live", live = live_model(), details = details_model(), history_index = 1, history_count = 0 }, s)
    eq(#background_rects(), 8, "details")
    s:set("halo", false)
    draw({ mode = "live", live = live_model(), history_index = 1, history_count = 0 }, s)
    eq(#background_rects(), 0, "off again")
end)

test("panel: the bars on a dark warm panel at the opacity, with bronze lines", function()
    local s = fresh("panel")
    s:set("halo", true) -- the halo belongs to the frameless look
    s:set("opacity", 0.5)
    local state = { mode = "live", live = live_model(), history_index = 1, history_count = 0 }
    ui.window_pos = { x = 40, y = 300 }
    draw(state, s)
    local bg = background_rects()
    eq(bg[1] ~= nil, true, "the panel, behind the window")
    eq(bg[1].col & 0xFFFFFF, 0x141417, "#171414")
    eq(bg[1].col >> 24, 128, "alpha byte from opacity 0.5")
    eq(bg[1].rounding, 0, "square corners")
    eq(bg[1].x0, 40, "from the window's corner"); eq(bg[1].y0, 300, "")
    for _, c in ipairs(ui.calls_of("add_text")) do
        eq(c.x >= bg[1].x0 and c.x < bg[1].x1 and c.y >= bg[1].y0 and c.y < bg[1].y1, true, "on the panel: " .. c.text)
    end
    for _, r in ipairs(bg) do eq(r.rounding, 0, "no halo, nothing round") end
    eq(#bg <= 5, true, "the panel and its edge only")

    -- the bars are as tall as a row, with the texts on them
    local guts, name = bar_of("Guts"), text_call("Guts")
    eq(guts[1].col, C.panel_track, "the panel's bar track")
    eq(guts[1].y0 <= name.y and name.y < guts[1].y1, true, "the name on the bar")
    eq(height(guts[1]), 20, "a row high")
    for _, r in ipairs(window_rects()) do eq(r.rounding, 0, "square bars") end
    -- bronze: the line under the header, dark bronze lines between the rows
    local bronze, lines = 0, 0
    for _, r in ipairs(window_rects()) do
        if r.col == C.bronze then bronze = bronze + 1 end
        if r.col == C.line then lines = lines + 1 end
    end
    eq(bronze, 1, "the header's line")
    eq(lines, 8, "a line under every row: five damage rows, two taken, one healer")
    eq(C.line & 0xFFFFFF, 0x2C3A4A, "dark bronze #4A3A2C")

    -- the opacity
    s:set("opacity", 1)
    draw(state, s)
    eq(background_rects()[1].col >> 24, 255, "opaque")
    s:set("opacity", 0.2)
    draw(state, s)
    eq(background_rects()[1].col >> 24, 51, "the lowest opacity")
    -- every view
    draw({ mode = "summary", summary = summary_model(), history_index = 1, history_count = 1 }, s)
    eq(background_rects()[1].col >> 24, 51, "summary")
    draw({ mode = "live", live = live_model(), details = details_model(), history_index = 1, history_count = 0 }, s)
    eq(background_rects()[1].col >> 24, 51, "details")
    -- the panel covers the wider details table
    local wide = details_model()
    wide.rows[2].total = "123 456 789 012"
    draw({ mode = "live", live = live_model(), details = wide, history_index = 1, history_count = 0 }, s)
    local right = -math.huge
    for _, c in ipairs(ui.calls_of("add_text")) do
        if not is_copy(c) then right = math.max(right, c.x + text_w(c.text)) end
    end
    eq(background_rects()[1].x1 >= right, true, "the panel is as wide as the table")
    eq(ui.balanced(), true, "balanced")
end)

test("scale comes from the settings", function()
    for _, style in ipairs(STYLES) do
        local s = fresh(style)
        local state = { mode = "live", live = live_model(), history_index = 1, history_count = 0 }
        draw(state, s)
        local bg1 = width(bar_of("Guts")[1])
        local px1 = ui.calls_of("push_font_size")[1][1]
        s:set("scale", 2)
        draw(state, s)
        near(ui.calls_of("push_font_size")[1][1], 2 * px1, 1e-9, style .. ": font size doubles")
        near(width(bar_of("Guts")[1]), 2 * bg1, 1e-6, "bars are twice as wide")
        eq(ui.balanced(), true, "balanced")
    end
end)

test("the window position comes from the settings and is not forced every frame", function()
    local s = fresh()
    local state = { mode = "live", live = live_model(), history_index = 1, history_count = 0 }
    draw(state, s)
    local set = ui.calls_of("set_next_window_pos")
    eq(#set, 1, "position set on the first frame")
    eq(set[1].x, 40, "window_x")
    eq(set[1].y, 300, "window_y")
    eq(set[1].cond, COND_ALWAYS, "applied now")
    -- set before the window starts
    local before
    for i, c in ipairs(ui.calls) do
        if c.fn == "set_next_window_pos" then before = i end
        if c.fn == "begin_window" then eq(before ~= nil and before < i, true, "set before begin_window") end
    end

    draw(state, s)
    eq(#ui.calls_of("set_next_window_pos"), 0, "later frames leave the window where it is")

    s:set("window_x", 120)
    draw(state, s)
    set = ui.calls_of("set_next_window_pos")
    eq(#set, 1, "a changed setting moves the window")
    eq(set[1].x, 120, "new x")
    eq(set[1].y, 300, "same y")
    draw(state, s)
    eq(#ui.calls_of("set_next_window_pos"), 0, "and then it rests")
end)

test("moved is reported once, when a drag ends", function()
    for _, style in ipairs(STYLES) do
        local s = fresh(style)
        ui.drawing_ui = true
        local state = { mode = "live", live = live_model(), history_index = 1, history_count = 0 }
        eq(draw(state, s).moved, nil, style .. ": first frame")

        -- the player grabs the window and drags it: nothing is reported while the button is down
        ui.mouse_down = true
        ui.window_pos = { x = 70, y = 320 }
        eq(draw(state, s).moved, nil, "dragging")
        ui.window_pos = { x = 90.4, y = 330.6 }
        eq(draw(state, s).moved, nil, "still dragging")
        eq(#ui.calls_of("set_next_window_pos"), 0, "the window is not pulled back during the drag")

        -- released: one report, whole pixels
        ui.mouse_down = false
        local a = draw(state, s)
        eq(type(a.moved), "table", "drag ended")
        eq(a.moved.x, 90, "x")
        eq(a.moved.y, 331, "y")

        -- the caller stores it right away; the window then stays where it is
        s:set("window_x", a.moved.x)
        s:set("window_y", a.moved.y)
        eq(draw(state, s).moved, nil, "reported once")
        eq(#ui.calls_of("set_next_window_pos"), 0, "no snap after the settings follow the drag")
        eq(draw(state, s).moved, nil, "and never again")
    end
end)

test("a drag the settings do not follow snaps back", function()
    local s = fresh()
    ui.drawing_ui = true
    local state = { mode = "live", live = live_model(), history_index = 1, history_count = 0 }
    draw(state, s)
    ui.mouse_down = true
    ui.window_pos = { x = -50, y = 320 }
    draw(state, s)
    ui.mouse_down = false
    local a = draw(state, s)
    eq(a.moved.x, -50, "reported as dragged")
    -- the caller's settings clamp the x to 0
    s:set("window_x", a.moved.x)
    s:set("window_y", a.moved.y)
    eq(s.values.window_x, 0, "settings clamp")
    draw(state, s)
    local set = ui.calls_of("set_next_window_pos")
    eq(#set, 1, "the window is put where the settings say")
    eq(set[1].x, 0, "clamped x")
    eq(set[1].y, 320, "y as dragged")
end)

test("a click without a move, or a move without the menu, is not a drag", function()
    local s = fresh()
    ui.drawing_ui = true
    local state = { mode = "live", live = live_model(), history_index = 1, history_count = 0 }
    draw(state, s)
    ui.mouse_down = true
    eq(draw(state, s).moved, nil, "button down, window still")
    ui.mouse_down = false
    eq(draw(state, s).moved, nil, "button up, window still")

    -- the game window is pushed around while the menu is closed
    ui.drawing_ui = false
    ui.mouse_down = true
    ui.window_pos = { x = 10, y = 10 }
    eq(draw(state, s).moved, nil, "no drag without the menu")
    ui.mouse_down = false
    eq(draw(state, s).moved, nil, "and none after")
end)

test("a drag ending when the menu closes is still reported", function()
    local s = fresh()
    ui.drawing_ui = true
    local state = { mode = "live", live = live_model(), history_index = 1, history_count = 0 }
    draw(state, s)
    ui.mouse_down = true
    ui.window_pos = { x = 200, y = 210 }
    draw(state, s)
    ui.drawing_ui = false
    ui.mouse_down = false
    local a = draw(state, s)
    eq(type(a.moved), "table", "reported")
    eq(a.moved.x, 200, "x")
end)

test("long names are cut to fit their bar", function()
    for _, style in ipairs(STYLES) do
        local s = fresh(style)
        local m = live_model()
        local long = string.rep("Immensely Long Name ", 8)
        m.damage.rows[1].name = long
        m.taken.rows[1].label = "Chimera → " .. long
        draw({ mode = "live", live = m, history_index = 1, history_count = 0 }, s)
        -- the drawn text that starts with `prefix`
        local function drawn_with(prefix)
            for _, t in ipairs(texts()) do
                if t:sub(1, #prefix) == prefix then return t end
            end
        end
        for _, case in ipairs({
            { prefix = "Immensely", numbers = "52 898 · 166/s · 40%" },
            { prefix = "Chimera → Imm", numbers = "3 817" },
        }) do
            local drawn = drawn_with(case.prefix)
            eq(drawn ~= nil, true, style .. " " .. case.prefix .. ": drawn, shortened")
            eq(#drawn < #long, true, case.prefix .. ": shorter than the full text")
            eq(drawn:sub(-2), "..", case.prefix .. ": marked as cut")
            eq(text_call(drawn).x + text_w(drawn) <= text_call(case.numbers).x, true, case.prefix .. ": ends before the numbers start")
        end
        eq(ui.balanced(), true, "balanced")

        -- Cyrillic is cut on character boundaries
        local ru = live_model()
        ru.damage.rows[1].name = string.rep("Очень длинное имя ", 8)
        draw({ mode = "live", live = ru, history_index = 1, history_count = 0 }, s)
        for _, t in ipairs(ui.texts()) do
            eq(utf8.len(t) ~= nil, true, "valid UTF-8: " .. t)
        end
    end
end)

test("section names follow the interface language", function()
    local s = fresh()
    i18n.set("ru")
    draw({ mode = "summary", summary = summary_model(), details = nil, history_index = 1, history_count = 1 }, s)
    for _, key in ipairs({ "enemies", "armor" }) do
        eq(has_text(i18n.t(key)), true, "ru " .. key)
    end
    eq(has_text("Enemies"), false, "no English heading left")
    draw({ mode = "live", live = live_model(), details = details_model(), history_index = 1, history_count = 0 }, s)
    eq(has_text(i18n.t("details_hits")), true, "ru details heading")
    eq(has_text("Hits"), false, "no English column heading left")
    i18n.set("en")
end)

-- Overlay.draw must not raise, whatever fails: returns the actions and the error text, and
-- leaves no window, font or colour pushed.
local function safe_draw(state, settings)
    ui.clear_calls()
    local ok, actions, err = pcall(Overlay.draw, state, settings)
    eq(ok, true, "no error escaped: " .. tostring(actions))
    eq(type(actions), "table", "actions come back anyway")
    eq(actions.history, 0, "neutral actions")
    eq(actions.hide, false, "neutral actions")
    eq(ui.balanced(), true, "window, font and colour stacks are balanced")
    return actions, err
end

test("a broken model never raises and the window is still closed", function()
    for _, style in ipairs(STYLES) do
        local s = fresh(style)
        local m = live_model()
        m.damage.rows = 5 -- not a list
        local _, err = safe_draw({ mode = "live", live = m, history_index = 1, history_count = 0 }, s)
        eq(type(err), "string", style .. ": the error comes back as a string")
        eq(#ui.calls_of("begin_window"), 1, "the window had been started")
        eq(#ui.calls_of("end_window"), 1, "and was ended")
        eq(#ui.calls_of("pop_font_size"), #ui.calls_of("push_font_size"), "every font size was popped")

        -- the header's title breaks while its larger font size is pushed: both sizes are popped
        local title = live_model()
        title.header.title = {}
        _, err = safe_draw({ mode = "live", live = title, history_index = 1, history_count = 0 }, s)
        eq(type(err), "string", "a title that is not a text")
        eq(#ui.calls_of("pop_font_size"), #ui.calls_of("push_font_size"), "both font sizes popped")
        if style == "frameless" then eq(#ui.calls_of("push_font_size"), 2, "the window's and the title's") end

        -- a broken details model, a broken summary, a state that is not a table
        local d = details_model()
        d.rows = false
        _, err = safe_draw({ mode = "summary", summary = summary_model(), details = d, history_index = 1, history_count = 1 }, s)
        eq(type(err), "string", "broken details")
        local sm = summary_model()
        sm.armor = 5 -- not a list
        _, err = safe_draw({ mode = "summary", summary = sm, history_index = 1, history_count = 1 }, s)
        eq(type(err), "string", "broken summary")
        _, err = safe_draw(nil, s)
        eq(type(err), "string", "no state")
        _, err = safe_draw({ mode = "live", live = live_model() }, nil)
        eq(type(err), "string", "no settings")

        -- a healthy frame has no error and the next frame works after a broken one
        _, err = safe_draw({ mode = "live", live = live_model(), history_index = 1, history_count = 0 }, s)
        eq(err, nil, "no error")
        eq(has_text("Guts"), true, "drawn")
        _, err = safe_draw({ mode = "hidden" }, s)
        eq(err, nil, "hidden is not an error")
    end
end)

test("a failure before, in or after the window start never raises", function()
    for _, style in ipairs(STYLES) do
        local state = { mode = "live", live = live_model(), history_index = 1, history_count = 0 }

        -- settings that raise when read: nothing was started
        local bad = { values = setmetatable({}, { __index = function() error("values exploded") end }) }
        local _, err = safe_draw(state, bad)
        eq(err:find("values exploded", 1, true) ~= nil, true, style .. ": message kept")
        eq(#ui.calls_of("begin_window"), 0, "no window was started")

        -- the scale is missing: fails after begin_window, before the font is pushed
        local no_scale = fresh(style)
        no_scale.values.scale = nil
        _, err = safe_draw(state, no_scale)
        eq(type(err), "string", "no scale")
        eq(#ui.calls_of("end_window"), 1, "window ended")
        eq(#ui.calls_of("push_font_size"), 0, "no font was pushed")

        -- the drag tracking fails right after begin_window
        local fresh_settings = fresh(style)
        local get_pos = imgui.get_window_pos
        imgui.get_window_pos = function() error("no window pos") end
        _, err = safe_draw(state, fresh_settings)
        imgui.get_window_pos = get_pos
        eq(err:find("no window pos", 1, true) ~= nil, true, "drag tracking failure reported")
        eq(#ui.calls_of("end_window"), 1, "window ended")

        -- the font push itself fails: window and colour are still unwound
        local push = imgui.push_font_size
        imgui.push_font_size = function() error("no font") end
        _, err = safe_draw(state, fresh(style))
        imgui.push_font_size = push
        eq(err:find("no font", 1, true) ~= nil, true, "font push failure reported")
        eq(#ui.calls_of("end_window"), 1, "window ended")

        -- the window cannot be started: the colour already pushed is popped, no end_window
        local begin = imgui.begin_window
        imgui.begin_window = function() error("no window") end
        _, err = safe_draw(state, fresh(style))
        imgui.begin_window = begin
        eq(err:find("no window", 1, true) ~= nil, true, "begin failure reported")
        eq(#ui.calls_of("end_window"), 0, "nothing to end")
        eq(#ui.calls_of("pop_style_color"), 1, "colour popped")

        -- the menu state query fails before anything is started
        local is_drawing = reframework.is_drawing_ui
        reframework.is_drawing_ui = function() error("no menu state") end
        _, err = safe_draw(state, fresh(style))
        reframework.is_drawing_ui = is_drawing
        eq(err:find("no menu state", 1, true) ~= nil, true, "menu query failure reported")

        -- the background layer fails (the panel or the halo is drawn last): reported, all unwound
        local halo = fresh(style)
        halo:set("halo", true)
        local get_bg = imgui.get_background_draw_list
        imgui.get_background_draw_list = function() error("no background layer") end
        _, err = safe_draw(state, halo)
        eq(err:find("no background layer", 1, true) ~= nil, true, "background failure reported")
        eq(has_text("Guts"), true, "the text was drawn before")
        -- a REFramework without it: the text alone, no error
        imgui.get_background_draw_list = nil
        _, err = safe_draw(state, halo)
        imgui.get_background_draw_list = get_bg
        eq(err, nil, "no background layer, no error")
        eq(has_text("Guts"), true, "the text is there")
        eq(#background_rects(), 0, "nothing behind it")

        -- a click recorded before the failure is not lost
        local clicking = fresh(style)
        ui.drawing_ui = true
        ui.press("damage:ch000000_00")
        local m = live_model()
        m.taken.rows = 5 -- fails after the damage block
        local actions
        actions, err = safe_draw({ mode = "live", live = m, history_index = 1, history_count = 0 }, clicking)
        eq(type(err), "string", "failure after the damage block")
        eq(actions.select_actor, "ch000000_00", "the click made before the failure is kept")
    end
end)

T.finish()
