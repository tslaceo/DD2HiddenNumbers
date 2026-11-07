package.path = "mod/reframework/autorun/?.lua;tests/?.lua;" .. package.path

local T = require("testlib")
local test, eq, near = T.test, T.eq, T.near
local ui = require("stubs/ui").install()
local i18n = require("DD2DamageMeter/i18n")
local Settings = require("DD2DamageMeter/settings")
local EnemyPlate = require("DD2DamageMeter/ui/enemy_plate")
local SceneText = require("DD2DamageMeter/ui/scene_text")
local HiddenStatsUI = require("DD2DamageMeter/ui/hidden_stats")

-- The enemy plate's ImU32 colours (0xAABBGGRR): its "name" beige, its "immune" grey, its panel and border.
local BEIGE, GREY, BACK, BORDER = 0xFFB2DBEA, 0xFF9A9A9A, 0x8C000000, 0xFF4A4A4A
local SHADOW, OUTLINE = 0xAB000000, 0xFF000000

-- The anchors as game/hidden_screens.lua gives them: the item screens' (txt_Name's x, the storage row's y + 40,
-- PNL_ItemInfo's width), the guild's (_TxtAbilityInfo's x, the «Используемые усилители» header bar's top,
-- up to the equipped table's right edge; the panel above it, growing upwards).
local ITEMS = { x = 1212, y = 423, width = 470 }
local GUILD = { x = 967.4, y = 561, width = 523, up = true }

-- A bane ring's line, about 150 characters (the longest the model writes).
local BANE = "≈ +50% к атаке против: Низший дракон, Каратель, Пурпурный дракон, Высший дракон, Дракон, Вурдалак, "
    .. "Лич, Стригой, Смерть, Барбатос и ещё 3"

local function make_settings(over)
    local saved = over or {}
    return Settings.load({ read = function() return saved end, write = function(t) saved = t end })
end

local function fresh(over)
    ui.reset()
    HiddenStatsUI.reset()
    i18n.set("ru")
    return make_settings(over)
end

-- A Panel as HiddenStatsModel.panel gives it: list = { { text, mark } }.
local function panel(list, legend)
    local lines = {}
    for i, l in ipairs(list) do lines[i] = { text = l[1], mark = l[2] } end
    return { lines = lines, legend = legend == true }
end

-- One frame; a drawing error fails the test, the stacks must balance.
local function draw(p, anchor, s)
    ui.clear_calls()
    local err = HiddenStatsUI.draw(p, anchor, s)
    if err then error("draw failed: " .. err, 2) end
    eq(ui.balanced(), true, "stacks balanced")
end

-- The texts drawn in a line's colour (not SceneText's shadow or outline copies), in order.
local function texts()
    local list = {}
    for _, c in ipairs(ui.calls_of("add_text")) do
        if c.col ~= SHADOW and c.col ~= OUTLINE then list[#list + 1] = c end
    end
    return list
end

local function strings()
    local out = {}
    for _, c in ipairs(texts()) do out[#out + 1] = c.text end
    return out
end

-- The width the stub gives `text` at `px`.
local function width(text, px)
    return utf8.len(text) * ui.char_w * px / 14
end

local function round(v)
    return math.floor(v + 0.5)
end

test("the lines in the Panel's order, plain and ≈ in the plate's beige, ? and none in its grey, the legend last",
    function()
    local s = fresh()
    eq(EnemyPlate.COLORS.name, BEIGE, "the plate's beige"); eq(EnemyPlate.COLORS.immune, GREY, "the plate's grey")
    local p = panel({ { "+200 к макс. здоровью", "plain" }, { "≈ +10% урона по врагам не в боевой стойке", "approx" },
        { "? +5% к скорости подъёма", "guess" }, { "+30% эффекта лечащего предмета", "plain" } }, true)
    draw(p, ITEMS, s)
    local list = texts()
    eq(#list, 5, "four lines and the legend")
    eq(list[1].text, "+200 к макс. здоровью", "first the Panel's first line")
    eq(list[1].col, BEIGE, "plain: beige")
    eq(list[2].text, "≈ +10% урона по врагам не в боевой стойке", "the ≈ line with its mark, as the model wrote it")
    eq(list[2].col, BEIGE, "approx: beige too")
    eq(list[3].text, "? +5% к скорости подъёма", "then the ? line")
    eq(list[3].col, GREY, "guess: grey")
    eq(list[4].text, "+30% эффекта лечащего предмета", "the Panel's order kept, not grouped by mark")
    eq(list[4].col, BEIGE, "plain: beige")
    eq(list[5].text, "≈ другие моды не подтверждают · ? догадка", "the legend last: hs_legend")
    eq(list[5].text, i18n.t("hs_legend"), "its i18n text")
    eq(list[5].col, GREY, "the legend in grey")
    for i = 2, #list do eq(list[i].y > list[i - 1].y, true, "each line under the one before") end
    for _, c in ipairs(list) do eq(c.layer, "background", "on the background list") end
    -- a none panel: its one line in grey, no legend
    draw(panel({ { "числа в игре не нашлось", "none" } }), ITEMS, s)
    eq(table.concat(strings(), "|"), "числа в игре не нашлось", "the none line alone")
    eq(texts()[1].col, GREY, "none: grey")
    -- legend false: no legend line
    draw(panel({ { "+200 к макс. здоровью", "plain" } }, false), ITEMS, s)
    eq(table.concat(strings(), "|"), "+200 к макс. здоровью", "no legend without legend = true")
    -- in English the legend's English text
    i18n.set("en")
    draw(panel({ { "≈ +10% damage", "approx" } }, true), ITEMS, s)
    eq(table.concat(strings(), "|"), "≈ +10% damage|≈ not confirmed by other mods · ? a guess", "the English legend")
end)

test("each text in SceneText's look: the shadow, eight outline copies, then the text in its colour", function()
    local s = fresh()
    draw(panel({ { "+200 к макс. здоровью", "plain" }, { "? +5%", "guess" } }), ITEMS, s)
    local calls = ui.calls_of("add_text")
    eq(#calls, 20, "ten add_text a line")
    for k = 0, 1 do
        local text = calls[k * 10 + 10]
        eq(calls[k * 10 + 1].col, SHADOW, "the shadow first")
        eq(calls[k * 10 + 1].text, text.text, "of the same text")
        for i = 2, 9 do eq(calls[k * 10 + i].col, OUTLINE, "eight outline copies") end
    end
    eq(calls[10].col, BEIGE, "the plain text in beige"); eq(calls[20].col, GREY, "the guess text in grey")
end)

test("under the anchor by GAP px × scale (above it when the anchor is up), left-aligned, as wide as the anchor × "
    .. "H / 1080, on three displays", function()
    for _, case in ipairs({ { 1920, 1080, 1, ITEMS }, { 2560, 1440, 1, ITEMS }, { 3440, 1440, 1, ITEMS },
                            { 3440, 1440, 1.5, GUILD }, { 1920, 1080, 0.8, GUILD } }) do
        local dw, dh, scale, anchor = case[1], case[2], case[3], case[4]
        local what = dw .. " × " .. dh .. " at scale " .. scale
        local s = fresh({ scale = scale })
        ui.display = { x = dw, y = dh }
        local p = panel({ { "+200 к макс. здоровью", "plain" }, { "≈ +10% урона", "approx" } }, true)
        draw(p, anchor, s)
        local fills = ui.calls_of("add_rect_filled")
        eq(#fills, 1, "one filled rect: the panel, at " .. what)
        local back = fills[1]
        eq(back.col, BACK, "the plate's translucent black at " .. what)
        eq(back.layer, "background", "on the background list")
        eq(back.rounding, EnemyPlate.ROUNDING * scale, "the plate's rounding × scale at " .. what)
        local unit = dh / 1080
        near(back.x0, anchor.x * dw / 1920, 0.5, "left-aligned with the anchor (EnemyBars.to_screen) at " .. what)
        if anchor.up then
            near(back.y1, anchor.y * unit - HiddenStatsUI.GAP * scale, 0.5, "its bottom GAP px × scale above it at "
                .. what)
        else
            near(back.y0, anchor.y * unit + HiddenStatsUI.GAP * scale, 0.5, "GAP px × scale under it at " .. what)
        end
        near(back.x1 - back.x0, anchor.width * unit, 0.5, "as wide as the anchor × H / 1080 at " .. what)
        for _, v in ipairs({ back.x0, back.y0, back.x1, back.y1 }) do eq(v, math.floor(v), "whole pixels") end
        local px = 14 * scale
        local pad_x, pad_y = EnemyPlate.PAD_X * scale, EnemyPlate.PAD_Y * scale
        local gap = EnemyPlate.LINE_GAP * scale
        local h = 3 * px + 2 * gap + 2 * pad_y
        near(back.y1 - back.y0, h, 0.5, "three lines high, the plate's gaps and paddings, at " .. what)
        local border = ui.calls_of("add_rect")
        eq(#border, 1, "one outline")
        eq(border[1].col, BORDER, "in the plate's border colour")
        eq(border[1].x0, back.x0); eq(border[1].y0, back.y0); eq(border[1].x1, back.x1); eq(border[1].y1, back.y1)
        eq(border[1].rounding, back.rounding, "the same corners"); eq(border[1].thickness, 1, "1 px")
        local list = texts()
        eq(#list, 3, "two lines and the legend at " .. what)
        for i, c in ipairs(list) do
            near(c.x, back.x0 + pad_x, 0.5, "the text PAD_X px × scale in at " .. what)
            near(c.y, back.y0 + pad_y + (i - 1) * (px + gap), 0.5, "line " .. i .. " at " .. what)
            eq(c.x, math.floor(c.x), "a whole pixel"); eq(c.y, math.floor(c.y), "a whole pixel")
            near(c.px, px, 1e-9, "14 px × scale at " .. what)
            eq(c.x + width(c.text, px) <= back.x1 - pad_x, true, "inside the panel at " .. what)
        end
        -- the add_rect_filled before the outline, both before the texts
        local order = {}
        for _, c in ipairs(ui.calls) do
            if c.fn == "add_rect_filled" or c.fn == "add_rect" or (c.fn == "add_text" and #order < 3) then
                order[#order + 1] = c.fn
            end
        end
        eq(table.concat(order, ","), "add_rect_filled,add_rect,add_text", "panel, border, then the texts")
    end
end)

test("a line longer than the width wraps to two, on a space, its words whole, the second an em in", function()
    local s = fresh()
    local long = "+30% к шансу найти предмет у поверженного врага при обыске тела, если рядом твои пешки"
    local inner = ITEMS.width - 2 * EnemyPlate.PAD_X -- 450 px at 1920 × 1080, scale 1
    eq(width(long, 14) > inner, true, "the line is wider than the panel's inside")
    draw(panel({ { long, "plain" }, { "? +5%", "guess" } }, true), ITEMS, s)
    local list = texts()
    eq(#list, 4, "the long line in two, the guess line, the legend")
    eq(list[1].text .. " " .. list[2].text, long, "broken at a space: the two halves are the line")
    eq(list[1].col, BEIGE, "both halves in the line's colour"); eq(list[2].col, BEIGE)
    eq(width(list[1].text, 14) <= inner, true, "the first half fits")
    eq(width(list[2].text, 14) <= inner - 14, true, "the second fits, an em in")
    eq(width(list[1].text .. " " .. list[2].text:match("^%S+"), 14) > inner, true,
        "greedy: the second half's first word did not fit on the first")
    eq(list[2].x, list[1].x + 14, "the continuation an em (the font size) in")
    eq(list[2].y, list[1].y + 14 + EnemyPlate.LINE_GAP, "on the next line")
    eq(list[3].text, "? +5%", "the next line after both halves"); eq(list[3].col, GREY)
    eq(list[3].x, list[1].x, "a new line starts at the left again")
    eq(list[4].text, i18n.t("hs_legend"), "the legend still last")
    local back = ui.calls_of("add_rect_filled")[1]
    near(back.y1 - back.y0, 4 * 14 + 3 * EnemyPlate.LINE_GAP + 2 * EnemyPlate.PAD_Y, 0.5, "four lines high")
end)

test("a bane ring's long line wraps into as many lines as it needs, each full, none wider than the panel", function()
    for _, case in ipairs({ { 1, 1, ITEMS }, { 1, 2, ITEMS }, { 1.5, 1, GUILD }, { 0.6, 1, ITEMS }, { 1, 0.5, GUILD } }) do
        local scale, size, anchor = case[1], case[2], case[3]
        local what = "scale " .. scale .. ", size " .. size
        local s = fresh({ scale = scale })
        eq(s.values.scale, scale, "the scale as set (settings keep it within 0.6 .. 2)")
        s.values.hidden_stats_size = size
        draw(panel({ { BANE, "approx" } }), anchor, s)
        local px = 14 * scale * size
        local inner = anchor.width - 2 * EnemyPlate.PAD_X * scale
        local list = texts()
        eq(#list >= 2, width(BANE, px) > inner, "wrapped exactly when wider than the inside at " .. what)
        local parts = {}
        for i, c in ipairs(list) do
            parts[i] = c.text
            eq(utf8.len(c.text) ~= nil, true, "valid UTF-8 at " .. what)
            local avail = i == 1 and inner or inner - px
            eq(width(c.text, px) <= avail, true, "line " .. i .. " fits at " .. what)
            if i < #list then
                local next_word = list[i + 1].text:match("^%S+")
                eq(width(c.text .. " " .. next_word, px) > avail, true, "line " .. i .. " is full at " .. what)
            end
        end
        eq(table.concat(parts, " "), BANE, "every word, in order, at " .. what)
    end
    -- bigger text: more lines
    local s = fresh()
    draw(panel({ { BANE, "approx" } }), ITEMS, s)
    local at_one = #texts()
    s.values.hidden_stats_size = 2
    draw(panel({ { BANE, "approx" } }), ITEMS, s)
    eq(#texts() > at_one, true, "twice the size, more lines")
end)

test("a number grouped as I18n.num writes it («2 000») is never broken at its group's space", function()
    local s = fresh()
    i18n.set("ru")
    local number = i18n.dec(2000)
    eq(number, "2 000", "I18n groups with a space")
    local head = "≈ выносливость за обычный удар: множитель"
    local text = head .. " " .. number .. ", предел 150"
    -- a panel whose inside fits the line up to "2" and two characters more, not up to "000,"
    local fit = utf8.len(head .. " 2") + 2
    local anchor = { x = 1212, y = 423, width = fit * 7 + 2 * EnemyPlate.PAD_X }
    draw(panel({ { text, "approx" } }), anchor, s)
    local list = strings()
    eq(list[1], head, "the line breaks before the number")
    eq(list[2], "2 000, предел 150", "the number whole on the next line")
    eq(table.concat(list, " "), text, "every word kept")
    -- digits that are not a group of three («12 1234») still break at their space: a panel 8 characters inside
    local narrow = { x = 1212, y = 423, width = 8 * 7 + 2 * EnemyPlate.PAD_X }
    draw(panel({ { "вес 12 1234", "plain" } }), narrow, s)
    eq(table.concat(strings(), "|"), "вес 12|1234", "«1234» is no group: the line breaks before it")
    draw(panel({ { "вес 12 345", "plain" } }), narrow, s)
    eq(table.concat(strings(), "|"), "вес|12 345", "«12 345» is one number: it goes on whole")
    draw(panel({ { "предел 150", "plain" } }), narrow, s)
    eq(table.concat(strings(), "|"), "предел|150", "three digits after a word, not a digit: free to break")
end)

test("a word wider than the panel is broken between characters, never inside a multi-byte one", function()
    local s = fresh()
    local inner = ITEMS.width - 2 * EnemyPlate.PAD_X
    for _, word in ipairs({ string.rep("ж", 100), string.rep("≈", 150), string.rep("aж≈", 40) }) do
        draw(panel({ { word, "plain" } }), ITEMS, s)
        local list = texts()
        eq(#list >= 2, true, "broken")
        local whole = {}
        for i, c in ipairs(list) do
            eq(utf8.len(c.text) ~= nil, true, "each piece valid UTF-8")
            eq(width(c.text, 14) <= (i == 1 and inner or inner - 14), true, "each piece fits")
            whole[i] = c.text
        end
        eq(table.concat(whole), word, "the pieces are the word")
        eq(utf8.len(list[1].text), inner // 7, "the first piece as long as fits")
    end
    -- "Слово" and then a long word: the word starts its own line, then breaks
    local text = "Слово " .. string.rep("ж", 70)
    draw(panel({ { text, "plain" } }), ITEMS, s)
    eq(table.concat(strings(), "|"), "Слово|" .. string.rep("ж", 62) .. "|" .. string.rep("ж", 8),
        "the long word on the next lines, an em in")
end)

test("a nil panel or anchor, or nothing to show: no imgui call at all", function()
    local s = fresh()
    local p = panel({ { "+200 к макс. здоровью", "plain" } }, true)
    local cases = {
        { nil, ITEMS, "a nil panel" },
        { p, nil, "a nil anchor" },
        { panel({}, true), ITEMS, "a panel without lines" },
        { { legend = true }, ITEMS, "a panel whose lines are missing" },
        { { lines = { 5, { mark = "plain" }, { text = 7, mark = "plain" }, { text = "  ", mark = "plain" } },
            legend = true }, ITEMS, "lines that are not lines, or blank" },
        { "panel", ITEMS, "a panel that is not a table" },
        { p, "anchor", "an anchor that is not a table" },
        { p, { x = 1212, y = 423 }, "an anchor without a width" },
        { p, { x = 0 / 0, y = 423, width = 470 }, "an anchor with a NaN" },
        { p, { x = 1212, y = math.huge, width = 470 }, "an anchor off at infinity" },
        { p, { x = 1212, y = 423, width = 0 }, "an anchor 0 wide" },
    }
    for _, case in ipairs(cases) do
        ui.clear_calls()
        local err = HiddenStatsUI.draw(case[1], case[2], s)
        eq(err, nil, "no error for " .. case[3])
        eq(#ui.calls, 0, "no imgui call for " .. case[3])
    end
    -- the lines that are lines are drawn, the others skipped
    draw({ lines = { 5, { text = "+200 к макс. здоровью", mark = "plain" }, { text = "", mark = "plain" } },
        legend = false }, ITEMS, s)
    eq(table.concat(strings(), "|"), "+200 к макс. здоровью", "the one good line")
    -- a mark the drawing does not know: grey, as the least sure
    draw(panel({ { "+1", "odd" } }), ITEMS, s)
    eq(texts()[1].col, GREY, "an unknown mark in grey")
end)

test("an anchor at y 1070 keeps the panel's bottom on screen: the panel moves up", function()
    for _, case in ipairs({ { 1920, 1080 }, { 3440, 1440 }, { 2560, 1440 } }) do
        local dw, dh = case[1], case[2]
        local what = dw .. " × " .. dh
        local s = fresh()
        ui.display = { x = dw, y = dh }
        local p = panel({ { "+200 к макс. здоровью", "plain" }, { BANE, "approx" } }, true)
        draw(p, { x = 1212, y = 1070, width = 470 }, s)
        local back = ui.calls_of("add_rect_filled")[1]
        local h = back.y1 - back.y0
        eq(h > 20, true, "a panel several lines high")
        eq(back.y1, dh, "its bottom at the screen's bottom at " .. what)
        near(back.x0, 1212 * dw / 1920, 0.5, "still left-aligned with the anchor at " .. what)
        for _, c in ipairs(texts()) do eq(c.y + c.px <= dh, true, "every text on screen at " .. what) end
        -- the texts keep their place in the panel
        near(texts()[1].y, back.y0 + EnemyPlate.PAD_Y, 0.5, "the first line at the panel's top at " .. what)
    end
    -- a panel taller than the screen: its top at the top
    local s = fresh()
    local many = {}
    for i = 1, 80 do many[i] = { "строка " .. i, "plain" } end
    draw(panel(many), ITEMS, s)
    eq(ui.calls_of("add_rect_filled")[1].y0, 0, "the top on screen at least")
    -- the right edge stays on screen too
    draw(panel({ { "+200", "plain" } }), { x = 1900, y = 423, width = 470 }, s)
    local back = ui.calls_of("add_rect_filled")[1]
    eq(back.x1, 1920, "moved left to the screen's right edge")
    eq(back.x1 - back.x0, 470, "as wide as before")
end)

test("an up anchor: the panel's bottom GAP px × scale above y, growing upwards with its lines, kept on screen",
    function()
    local GAP, PAD_Y, LINE_GAP = HiddenStatsUI.GAP, EnemyPlate.PAD_Y, EnemyPlate.LINE_GAP
    local s = fresh()
    -- one line, then three: the bottom stays by the anchor, the top goes up
    draw(panel({ { "+200 к макс. здоровью", "plain" } }), GUILD, s)
    local one = ui.calls_of("add_rect_filled")[1]
    near(one.y1, 561 - GAP, 0.5, "its bottom GAP px above y")
    draw(panel({ { "+200 к макс. здоровью", "plain" }, { "≈ +10% урона", "approx" } }, true), GUILD, s)
    local three = ui.calls_of("add_rect_filled")[1]
    eq(three.y1, one.y1, "the bottom stays")
    eq(three.y0 < one.y0, true, "more lines: the top higher")
    near(three.y1 - three.y0, 3 * 14 + 2 * LINE_GAP + 2 * PAD_Y, 0.5, "three lines high")
    local list = texts()
    eq(#list, 3, "two lines and the legend")
    near(list[1].y, three.y0 + PAD_Y, 0.5, "the first line at the panel's top: the lines read top-down")
    for i = 2, 3 do eq(list[i].y > list[i - 1].y, true, "line " .. i .. " under the one before") end
    eq(list[3].y + 14 <= three.y1 - PAD_Y + 0.5, true, "the last line inside the panel")
    -- a wrapped line grows it upwards too
    draw(panel({ { BANE, "approx" } }, true), GUILD, s)
    local bane = ui.calls_of("add_rect_filled")[1]
    eq(bane.y1, one.y1, "a wrapped line: the bottom stays")
    eq(bane.y0 < one.y0, true, "and the top goes higher")
    -- up only when it is true
    draw(panel({ { "+200", "plain" } }), { x = 967.4, y = 561, width = 523, up = "yes" }, s)
    near(ui.calls_of("add_rect_filled")[1].y0, 561 + GAP, 0.5, "an up that is not true: under y")
    -- at scale 1.5 on a 21:9 display, the same rule in its units
    s = fresh({ scale = 1.5 })
    ui.display = { x = 3440, y = 1440 }
    draw(panel({ { "+200", "plain" } }), GUILD, s)
    near(ui.calls_of("add_rect_filled")[1].y1, 561 * 1440 / 1080 - GAP * 1.5, 0.5, "21:9, scale 1.5")
    -- a panel taller than the room above y: its top at 0 (it then covers what is under it)
    s = fresh()
    local many = {}
    for i = 1, 30 do many[i] = { "строка " .. i, "plain" } end
    draw(panel(many), { x = 967.4, y = 100, width = 523, up = true }, s)
    local tall = ui.calls_of("add_rect_filled")[1]
    eq(tall.y0, 0, "its top on screen")
    eq(tall.y1 > 100, true, "its bottom below y then")
    -- an up anchor below the screen: the panel's bottom at the screen's bottom
    draw(panel({ { "+200", "plain" } }), { x = 967.4, y = 1200, width = 523, up = true }, s)
    eq(ui.calls_of("add_rect_filled")[1].y1, 1080, "kept on screen")
end)

test("the font: 14 px × scale × hidden_stats_size (1 while missing), pushed once and popped", function()
    local s = fresh()
    s.values.hidden_stats_size = nil -- missing, as in settings saved before the setting existed
    draw(panel({ { "+200", "plain" } }, true), ITEMS, s)
    local pushes, pops = ui.calls_of("push_font_size"), ui.calls_of("pop_font_size")
    eq(#pushes, 1, "pushed once"); eq(#pops, 1, "popped once")
    eq(pushes[1][1], 14, "14 px at scale 1, the size missing")
    for _, c in ipairs(ui.calls_of("add_text")) do eq(c.px, 14, "every text at that size") end
    eq(ui.calls[#ui.calls].fn, "pop_font_size", "popped after the last text")
    s = fresh({ scale = 1.5 })
    s.values.hidden_stats_size = 2
    draw(panel({ { "+200", "plain" } }, true), ITEMS, s)
    eq(ui.calls_of("push_font_size")[1][1], 42, "14 × 1.5 × 2")
    for _, c in ipairs(ui.calls_of("add_text")) do eq(c.px, 42, "every text at 42 px") end
    s.values.hidden_stats_size = "big"
    draw(panel({ { "+200", "plain" } }, true), ITEMS, s)
    eq(ui.calls_of("push_font_size")[1][1], 21, "a size that is not a number counts 1")
    -- a plain settings table, as the frame may pass
    draw(panel({ { "+200", "plain" } }), ITEMS, { values = { scale = 1, hidden_stats_size = 0.5 } })
    eq(ui.calls_of("push_font_size")[1][1], 7, "14 × 1 × 0.5")
    -- each text measured at the size pushed: once per text and size
    local calc, measured = imgui.calc_text_size, 0
    imgui.calc_text_size = function(text)
        eq(#ui.fonts, 1, "measured with the font size pushed")
        measured = measured + 1
        return calc(text)
    end
    SceneText.reset()
    s = fresh()
    draw(panel({ { BANE, "approx" } }, true), ITEMS, s)
    local once = measured
    eq(once > 0, true, "measured")
    draw(panel({ { BANE, "approx" } }, true), ITEMS, s)
    eq(measured, once, "not again for the same texts")
    imgui.calc_text_size = calc
end)

test("draw never raises and stays balanced; a missing call is named and not tried again until reset", function()
    local s = fresh()
    local p = panel({ { BANE, "approx" }, { "+200", "plain" } }, true)
    local add_text = ui.draw_list.add_text
    ui.draw_list.add_text = function() error("draw list broke") end
    ui.clear_calls()
    local err = HiddenStatsUI.draw(p, ITEMS, s)
    ui.draw_list.add_text = add_text
    eq(type(err), "string", "the error comes back")
    eq(ui.balanced(), true, "the font size popped again")
    ui.clear_calls()
    eq(type(HiddenStatsUI.draw(p, ITEMS, nil)), "string", "no settings")
    eq(type(HiddenStatsUI.draw(p, ITEMS, { values = { scale = "big" } })), "string", "a scale that is not a number")
    eq(ui.balanced(), true, "balanced")
    eq(#texts(), 0, "nothing drawn")
    local calc = imgui.calc_text_size
    imgui.calc_text_size = function() error("measure broke") end
    SceneText.reset()
    ui.clear_calls()
    err = HiddenStatsUI.draw(p, ITEMS, s)
    imgui.calc_text_size = calc
    eq(type(err), "string", "a measure that breaks: the error comes back")
    eq(ui.balanced(), true, "the size pushed popped again")
    for _, name in ipairs({ "get_display_size", "get_background_draw_list" }) do
        local fn = imgui[name]
        imgui[name] = nil
        draw(p, ITEMS, s)
        eq(#ui.calls, 0, "no " .. name .. ": nothing")
        imgui[name] = fn
        draw(p, ITEMS, s)
        eq(#texts(), 0, name .. " is not tried again")
        eq(table.concat(HiddenStatsUI.missing(), ","), name, "and named")
        HiddenStatsUI.reset()
        draw(p, ITEMS, s)
        eq(#texts() > 0, true, "until reset")
    end
    eq(#HiddenStatsUI.missing(), 0, "nothing missing after reset")
end)

test("without add_rect the border is four filled strips, the call named and not tried again", function()
    local s = fresh()
    local p = panel({ { "+200 к макс. здоровью", "plain" } }, true)
    local add_rect = ui.draw_list.add_rect
    ui.draw_list.add_rect = nil
    draw(p, ITEMS, s)
    local fills = ui.calls_of("add_rect_filled")
    eq(#fills, 5, "the panel and four strips")
    eq(fills[1].col, BACK, "the panel first")
    for i = 2, 5 do eq(fills[i].col, BORDER, "a strip in the border's colour") end
    eq(fills[2].y1 - fills[2].y0, 1, "the top strip is 1 px high"); eq(fills[2].x0, fills[1].x0, "across the panel")
    eq(fills[2].x1, fills[1].x1, "to its right edge")
    eq(fills[3].y0, fills[1].y1 - 1, "the bottom strip at the bottom")
    eq(fills[4].x1 - fills[4].x0, 1, "the left strip is 1 px wide")
    eq(fills[5].x0, fills[1].x1 - 1, "the right strip at the right")
    eq(#texts(), 2, "the texts still drawn")
    eq(table.concat(HiddenStatsUI.missing(), ","), "add_rect", "named")
    ui.draw_list.add_rect = add_rect
    draw(p, ITEMS, s)
    eq(#ui.calls_of("add_rect"), 0, "not tried again")
    HiddenStatsUI.reset()
    draw(p, ITEMS, s)
    eq(#ui.calls_of("add_rect"), 1, "tried again after reset")
end)

T.finish()
