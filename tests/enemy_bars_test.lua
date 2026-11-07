package.path = "mod/reframework/autorun/?.lua;tests/?.lua;" .. package.path

local T = require("testlib")
local test, eq, near = T.test, T.eq, T.near
local ui = require("stubs/ui").install()
local i18n = require("DD2DamageMeter/i18n")
local Settings = require("DD2DamageMeter/settings")
local EnemyBars = require("DD2DamageMeter/ui/enemy_bars")

local C = EnemyBars.COLORS

local function make_settings(over)
    local saved = over or {}
    return Settings.load({ read = function() return saved end, write = function(t) saved = t end })
end

local function fresh(over)
    ui.reset()
    EnemyBars.reset()
    i18n.set("ru")
    return make_settings(over)
end

-- One frame; a drawing error fails the test, the stacks must balance.
local function draw(bars, s)
    ui.clear_calls()
    local err = EnemyBars.draw(bars, s)
    if err then error("draw failed: " .. err, 2) end
    eq(ui.balanced(), true, "stacks balanced")
end

-- The texts drawn in the text colour (not the shadow or outline copies), in order.
local function texts()
    local list = {}
    for _, c in ipairs(ui.calls_of("add_text")) do
        if c.col == C.text then list[#list + 1] = c end
    end
    return list
end

-- The width the stub gives `text` at `px` (15 by default).
local function width(text, px)
    return utf8.len(text) * ui.char_w * (px or 15) / 14
end

local function round(v)
    return math.floor(v + 0.5)
end

test("the six formats, with i18n's numbers and percent", function()
    i18n.set("ru")
    local text = EnemyBars.text
    eq(text("off", 12340, 18000), nil, "off: nothing")
    eq(text("current", 12340, 18000), "12 340", "current")
    eq(text("current_max", 12340, 18000), "12 340 / 18 000", "current_max")
    eq(text("percent", 12340, 18000), "69%", "percent: 12 340 of 18 000 is 68.6 %")
    eq(text("percent", 12240, 18000), "68%", "68 %")
    eq(text("current_percent", 12240, 18000), "12 240 · 68%", "current_percent")
    eq(text("all", 12240, 18000), "12 240 / 18 000 · 68%", "all")
    eq(text("all", 12340.4, 18000.2), "12 340 / 18 000 · 69%", "whole numbers, rounded")
    eq(text("all", -5, 18000), "0 / 18 000 · 0%", "below 0: 0")
    eq(text("all", 0, 18000), "0 / 18 000 · 0%", "killed")
    eq(text("all", 900, 900), "900 / 900 · 100%", "full")
    eq(text("percent", 950, 900), "100%", "never above 100 %")
    eq(text("whatever", 1, 2), nil, "a format the mod does not know: nothing")
    eq(text("all", "lots", 2), nil, "an HP that is not a number: nothing")
    eq(text("all", 1, 0), nil, "no full HP: nothing")
    i18n.set("en")
    eq(text("all", 12240, 18000), "12 240 / 18 000 · 68%", "the same in English")
end)

test("the settings window's names of the formats are what the formats draw", function()
    for _, lang in ipairs({ "ru", "en" }) do
        i18n.set(lang)
        for _, format in ipairs({ "current", "current_max", "percent", "current_percent", "all" }) do
            eq(i18n.t("hpnum_" .. format), EnemyBars.text(format, 12340, 18000), format .. " in " .. lang)
        end
    end
    i18n.set("ru")
end)

test("a point of the bars' GUI space on the display", function()
    local x, y = EnemyBars.to_screen(960, 540, 1920, 1080)
    eq(x, 960, "1920 × 1080: as it is"); eq(y, 540, "y")
    x, y = EnemyBars.to_screen(960, 540, 3440, 1440)
    eq(x, 1720, "3440 × 1440: x × 3440 / 1920"); eq(y, 720, "y × 1440 / 1080")
    x, y = EnemyBars.to_screen(1920, 1080, 3440, 1440)
    eq(x, 3440, "the corner"); eq(y, 1440, "the corner")
    x, y = EnemyBars.to_screen(0, 0, 3440, 1440)
    eq(x, 0, "the origin"); eq(y, 0, "the origin")
    -- the bar's right edge and top: its half width and its top scaled like a height (BAR_HALF_WIDTH, BAR_TOP)
    eq(EnemyBars.BAR_HALF_WIDTH, 62, "62 GUI units"); eq(EnemyBars.BAR_TOP, 5, "5 GUI units")
    local right, top = EnemyBars.anchor(960, 540, 1920, 1080)
    eq(right, 960 + 62, "1920 × 1080: 62 px right of the centre"); eq(top, 540 - 5, "5 px above it")
    right, top = EnemyBars.anchor(960, 540, 3440, 1440)
    near(right, 1720 + 62 * 1440 / 1080, 1e-9, "3440 × 1440: 62 × 1440 / 1080 px right")
    near(top, 720 - 5 * 1440 / 1080, 1e-9, "5 × 1440 / 1080 px above")
end)

test("above the bar: the text's right edge at the bar's right edge, its bottom 3 px above the bar's top", function()
    for _, display in ipairs({ { 1920, 1080 }, { 3440, 1440 } }) do
        local s = fresh()
        ui.display = { x = display[1], y = display[2] }
        draw({ { x = 960, y = 400, hp = 12340, full = 18000 }, { x = 300, y = 700, hp = 50, full = 100 } }, s)
        local list = texts()
        eq(#list, 2, "one text per bar")
        eq(list[1].text, "12 340 / 18 000 · 69%", "the default: all")
        eq(list[2].text, "50 / 100 · 50%", "the second bar")
        for i, bar in ipairs({ { 960, 400 }, { 300, 700 } }) do
            local right, top = EnemyBars.anchor(bar[1], bar[2], display[1], display[2])
            local c = list[i]
            local w = width(c.text)
            near(c.x + w, right, 0.5, "the right edge at the bar's at " .. display[1])
            near(c.y + 15, top - 3, 0.5, "the bottom 3 px above the bar's top at " .. display[1])
            eq(c.x, math.floor(c.x), "a whole pixel"); eq(c.y, math.floor(c.y), "a whole pixel")
            eq(c.layer, "background", "on the background list: under every window")
            eq(c.px, 15, "15 px at scale 1 and size 1")
        end
    end
end)

-- The ImU32 colours (0xAABBGGRR) of the fixed look.
local BEIGE, SHADOW, OUTLINE = 0xFFB2DBEA, 0xAB000000, 0xFF000000

-- What one frame drew: "x,y,colour,text,px" per text and the number of rectangles.
local function snapshot(s, bars)
    draw(bars, s)
    local out = {}
    for _, c in ipairs(ui.calls_of("add_text")) do
        out[#out + 1] = string.format("%s,%s,%x,%s,%s", c.x, c.y, c.col, c.text, c.px)
    end
    return table.concat(out, "|"), #ui.calls_of("add_rect_filled")
end

test("one fixed look: the pawn names' beige over black outline copies over a black shadow down-right", function()
    local s = fresh()
    draw({ { x = 960, y = 400, hp = 100, full = 200 } }, s)
    local calls = ui.calls_of("add_text")
    eq(#calls, 10, "the shadow, eight outline copies, the text")
    local text = calls[10]
    eq(text.text, "100 / 200 · 50%", "the text last, over everything")
    eq(text.col, BEIGE, "in the pawn names' beige #EADBB2")
    eq(EnemyBars.COLORS.text, BEIGE, "COLORS.text")
    local shadow = calls[1]
    eq(shadow.text, text.text, "the shadow is the text again")
    eq(shadow.col, SHADOW, "black at 67 %")
    eq(shadow.x - text.x, 2, "2 px to the right"); eq(shadow.y - text.y, 2, "2 px down")
    local seen, n = {}, 0
    for i = 2, 9 do
        local c = calls[i]
        eq(c.text, text.text, "an outline copy is the text again")
        eq(c.col, OUTLINE, "black")
        local dx, dy = c.x - text.x, c.y - text.y
        eq(math.abs(dx) == 1 or math.abs(dy) == 1, true, "one px off")
        eq(math.abs(dx) <= 1 and math.abs(dy) <= 1, true, "at most one px off")
        if not seen[dx .. "," .. dy] then n = n + 1 end
        seen[dx .. "," .. dy] = true
    end
    eq(n, 8, "in the eight directions")
    eq(#ui.calls_of("add_rect_filled"), 0, "no halo, no plate")
end)

test("the numbers ignore the meter's look settings", function()
    local bars = { { x = 960, y = 400, hp = 12340, full = 18000 }, { x = 300, y = 700, hp = 5, full = 10 } }
    local base, rects = snapshot(fresh(), bars)
    eq(rects, 0, "no rectangle")
    for _, over in ipairs({ { style = "panel" }, { shadow = 0 }, { shadow = 1 }, { outline = false }, { halo = true },
                            { halo = true, opacity = 1 }, { style = "panel", halo = true, shadow = 0, outline = false,
                              opacity = 0.2, bar_px = 8 } }) do
        local keys = {}
        for k, v in pairs(over) do keys[#keys + 1] = k .. "=" .. tostring(v) end
        table.sort(keys)
        local got, n = snapshot(fresh(over), bars)
        eq(got, base, "the same with " .. table.concat(keys, " "))
        eq(n, 0, "no rectangle with " .. table.concat(keys, " "))
    end
end)

test("the size: 15 px × the meter's scale × enemy_hp_size; the shadow and the outline grow with it", function()
    -- scale, enemy_hp_size, px, shadow offset (2 px × the factor), outline offset (1 px × the factor), gap (3 × scale)
    for _, case in ipairs({ { 1, 1, 15, 2, 1 }, { 1, 2, 30, 4, 2 }, { 1.5, 1, 22.5, 3, 2 }, { 1.5, 2, 45, 6, 3 },
                            { 1.18, 1, 17.7, 2, 1 }, { 0.6, 0.5, 4.5, 1, 1 } }) do
        local scale, size, px = case[1], case[2], case[3]
        local what = "scale " .. scale .. ", size " .. size
        local s = fresh({ scale = scale, enemy_hp_size = size })
        draw({ { x = 960, y = 400, hp = 100, full = 200 } }, s)
        local calls = ui.calls_of("add_text")
        local text = calls[#calls]
        near(text.px, px, 1e-9, "the font size at " .. what)
        near(ui.find("push_font_size")[1], px, 1e-9, "pushed at " .. what)
        eq(calls[1].x - text.x, case[4], "the shadow's offset at " .. what)
        eq(calls[1].y - text.y, case[4], "down too at " .. what)
        local far = 0
        for i = 2, 9 do far = math.max(far, math.abs(calls[i].x - text.x), math.abs(calls[i].y - text.y)) end
        eq(far, case[5], "the outline's offset at " .. what)
        local right, top = EnemyBars.anchor(960, 400, 1920, 1080)
        near(text.x + width(text.text, px), right, 0.5, "the right edge at the bar's at " .. what)
        near(text.y + px, top - 3 * scale, 0.5, "the bottom 3 px × scale above the bar at " .. what)
        eq(text.x, round(text.x), "a whole pixel")
    end
end)

test("nothing at all for no bar, for off, or for a bar the format leaves without text", function()
    local s = fresh()
    draw({}, s)
    eq(#ui.calls, 0, "no bar: no imgui call")
    s:set("enemy_hp_numbers", "off")
    draw({ { x = 960, y = 400, hp = 100, full = 200 } }, s)
    eq(#ui.calls, 0, "off: none either")
    s:set("enemy_hp_numbers", "current")
    draw({ { x = 960, y = 400, hp = "x", full = 200 }, { x = 100, y = 100, hp = 5, full = 10 } }, s)
    eq(#texts(), 1, "a bar without numbers is skipped, the other drawn")
    eq(texts()[1].text, "5", "the current HP only")
end)

test("a text is measured once per font size", function()
    local s = fresh()
    local bars = { { x = 960, y = 400, hp = 100, full = 200 } }
    local calc, measured = imgui.calc_text_size, 0
    imgui.calc_text_size = function(text)
        measured = measured + 1
        return calc(text)
    end
    draw(bars, s)
    draw(bars, s)
    eq(measured, 1, "once for two frames")
    s:set("scale", 1.5)
    draw(bars, s)
    eq(measured, 2, "again at another size")
    imgui.calc_text_size = calc
end)

test("draw never raises and stays balanced", function()
    local s = fresh()
    local bars = { { x = 960, y = 400, hp = 100, full = 200 } }
    local add_text = ui.draw_list.add_text
    ui.draw_list.add_text = function() error("draw list broke") end
    ui.clear_calls()
    local err = EnemyBars.draw(bars, s)
    eq(type(err), "string", "the error comes back")
    eq(ui.balanced(), true, "the font size popped again")
    ui.draw_list.add_text = add_text
    -- no list, no settings: the error comes back too, nothing raises, nothing is drawn
    ui.clear_calls()
    eq(type(EnemyBars.draw(nil, s)), "string", "no list of bars")
    eq(type(EnemyBars.draw(5, s)), "string", "a list that is not one")
    eq(type(EnemyBars.draw(bars, nil)), "string", "no settings")
    eq(type(EnemyBars.draw(bars, { values = { enemy_hp_numbers = "all", scale = "big", enemy_hp_size = 1 } })),
        "string", "a scale that is not a number")
    eq(ui.balanced(), true, "balanced")
    eq(#ui.calls_of("add_text"), 0, "nothing drawn")
    -- bars that are not bars are skipped
    draw({ 5, { x = "a", y = 1, hp = 1, full = 2 }, { x = 1, y = 0 / 0, hp = 1, full = 2 } }, s)
    eq(#ui.calls_of("add_text"), 0, "nothing drawn for them")
    -- without the display size or the background list nothing is drawn, nothing raises; a call found missing is
    -- named and not tried again until reset
    for _, name in ipairs({ "get_display_size", "get_background_draw_list" }) do
        local fn = imgui[name]
        imgui[name] = nil
        draw(bars, s)
        eq(#ui.calls_of("add_text"), 0, "no " .. name .. ": nothing")
        imgui[name] = fn
        draw(bars, s)
        eq(#texts(), 0, name .. " is not tried again")
        eq(table.concat(EnemyBars.missing(), ","), name, "and named")
        EnemyBars.reset()
        draw(bars, s)
        eq(#texts(), 1, "until reset")
    end
end)

-- The boss bar ------------------------------------------------------------------------------------------------

-- The boss bar as game/gauges.lua gives it on a 3440 × 1440 display (the probes': its base at global (665.3, 106),
-- 776 × 7) and on a 1920 × 1080 one (All not moved: the base at its local (564, 106)).
local WIDE = { x = 665.3, y = 109.5, width = 776 }
local FULL_HD = { x = 564, y = 109.5, width = 776 }

local function boss(over)
    local b = { x = WIDE.x, y = WIDE.y, width = WIDE.width, hp = 40000, full = 90000 }
    for k, v in pairs(over or {}) do b[k] = v end
    return b
end

-- One frame of the boss's numbers; a drawing error fails the test, the stacks must balance.
local function draw_boss(bar, s)
    ui.clear_calls()
    local err = EnemyBars.draw_boss(bar, s)
    if err then error("draw failed: " .. err, 2) end
    eq(ui.balanced(), true, "stacks balanced")
end

test("the boss bar on the display: its right end and middle from its base, else where the game has it", function()
    local right, middle = EnemyBars.boss_anchor(WIDE, 3440, 1440)
    near(right, 2227, 0.5, "3440 × 1440: the right end at 2227 px")
    near(right, 665.3 * 3440 / 1920 + 776 * 1440 / 1080, 1e-9, "the left end × W / 1920, the width × H / 1080")
    near(middle, 146, 1e-9, "the middle at 146 px: 109.5 × 1440 / 1080")
    right, middle = EnemyBars.boss_anchor(FULL_HD, 1920, 1080)
    eq(right, 564 + 776, "1920 × 1080: as it is"); eq(middle, 109.5, "the middle")
    -- without its base: where the probes saw it, centred on the display, its sizes × H / 1080
    eq(EnemyBars.BOSS_RIGHT, 380, "the right end 380 units right of the centre: 564 + 776 - 960")
    eq(EnemyBars.BOSS_MIDDLE, 109.5, "the middle 109.5 units down: 106 + 7 / 2")
    for _, display in ipairs({ { 3440, 1440 }, { 1920, 1080 }, { 2560, 1080 } }) do
        local w, h = display[1], display[2]
        local r, m = EnemyBars.boss_anchor({}, w, h)
        near(r, w / 2 + 380 * h / 1080, 1e-9, "no base at " .. w .. ": the right end")
        near(m, 109.5 * h / 1080, 1e-9, "the middle")
    end
    local r, m = EnemyBars.boss_anchor({}, 3440, 1440)
    near(r, 2227, 0.5, "3440 × 1440: the same right end as the base gives"); near(m, 146, 1e-9, "and middle")
    eq(EnemyBars.boss_anchor({}, 1920, 1080), 1340, "1920 × 1080 too")
    -- a place that is not all numbers counts as none
    for _, bad in ipairs({ { x = 1, y = 2 }, { x = "a", y = 2, width = 3 }, { x = 1, y = 0 / 0, width = 3 },
                           { x = 1, y = 2, width = math.huge } }) do
        eq(EnemyBars.boss_anchor(bad, 1920, 1080), 1340, "a broken place: where the game has it")
    end
end)

test("the boss bar's left end and middle (the enemy plate's anchor): from its base, else where the game has it",
function()
    local left, middle = EnemyBars.boss_left(WIDE, 1920, 1080)
    near(left, 665.3, 1e-9, "1920 × 1080: the left end as it is"); eq(middle, 109.5, "the middle")
    left, middle = EnemyBars.boss_left(WIDE, 3440, 1440)
    near(left, 665.3 * 3440 / 1920, 1e-9, "3440 × 1440: the left end × W / 1920")
    near(middle, 146, 1e-9, "the middle × H / 1080")
    -- the left end and the right end are one bar's width apart, × H / 1080
    local right = EnemyBars.boss_anchor(WIDE, 3440, 1440)
    near(right - left, 776 * 1440 / 1080, 1e-9, "the width between them")
    -- without its base: 396 units left of the display's centre (564 - 960), × H / 1080, with BOSS_MIDDLE
    eq(EnemyBars.BOSS_LEFT, -396, "BOSS_LEFT")
    left, middle = EnemyBars.boss_left({}, 3440, 1440)
    near(left, 3440 / 2 - 396 * 1440 / 1080, 1e-9, "no base on 3440 × 1440: the left end")
    near(middle, 109.5 * 1440 / 1080, 1e-9, "the middle")
    eq(EnemyBars.boss_left({}, 1920, 1080), 564, "1920 × 1080: where the probes saw the base")
    for _, bad in ipairs({ { x = 1, y = 2 }, { x = "a", y = 2, width = 3 }, { x = 1, y = 0 / 0, width = 3 },
                           { x = 1, y = 2, width = math.huge } }) do
        eq(EnemyBars.boss_left(bad, 1920, 1080), 564, "a broken place: where the game has it")
    end
end)

test("right of the boss bar: the text's left edge 10 px × scale after its right end, its middle on the bar's", function()
    for _, case in ipairs({ { 3440, 1440, WIDE, 1 }, { 1920, 1080, FULL_HD, 1 }, { 3440, 1440, WIDE, 1.18 },
                            { 1920, 1080, FULL_HD, 2 } }) do
        local w, h, place, scale = case[1], case[2], case[3], case[4]
        local what = w .. " × " .. h .. " at scale " .. scale
        local s = fresh({ scale = scale })
        ui.display = { x = w, y = h }
        draw_boss(boss(place), s)
        local list = texts()
        eq(#list, 1, "one text at " .. what)
        local c = list[1]
        eq(c.text, "40 000 / 90 000 · 44%", "all by default at " .. what)
        local px = 18 * scale
        near(c.px, px, 1e-9, "18 px × the scale at " .. what)
        local right, middle = EnemyBars.boss_anchor(place, w, h)
        near(c.x, right + 10 * scale, 0.5, "the left edge 10 px × scale after the bar at " .. what)
        near(c.y + px / 2, middle, 0.5, "the middle on the bar's at " .. what)
        eq(c.x, math.floor(c.x), "a whole pixel"); eq(c.y, math.floor(c.y), "a whole pixel")
        eq(c.layer, "background", "on the background list: under every window")
    end
    -- on a 3440 × 1440 display: the left edge at about 2227 + 12 px, the middle at about 146 px
    local s = fresh({ scale = 1.18 })
    ui.display = { x = 3440, y = 1440 }
    draw_boss(boss(), s)
    local c = texts()[1]
    near(c.x, 2227 + 10 * 1.18, 1, "x on 3440 × 1440"); near(c.y + 18 * 1.18 / 2, 146, 1, "y")
    -- the base not found: where the game has the bar
    draw_boss(boss({ x = false, y = false, width = false }), s)
    near(texts()[1].x, 2227 + 10 * 1.18, 1, "the same place")
    ui.display = { x = 1920, y = 1080 }
end)

test("the boss's numbers: the six formats of boss_hp_numbers, not of enemy_hp_numbers; the size of both", function()
    local want = { off = nil, current = "40 000", current_max = "40 000 / 90 000", percent = "44%",
        current_percent = "40 000 · 44%", all = "40 000 / 90 000 · 44%" }
    for _, format in ipairs({ "off", "current", "current_max", "percent", "current_percent", "all" }) do
        local s = fresh({ boss_hp_numbers = format, enemy_hp_numbers = "current" })
        draw_boss(boss(), s)
        if want[format] then
            eq(#texts(), 1, format .. ": one text"); eq(texts()[1].text, want[format], format)
        else
            eq(#ui.calls, 0, "off: not even an imgui call")
        end
    end
    local s = fresh({ enemy_hp_numbers = "off" })
    draw_boss(boss(), s)
    eq(texts()[1].text, "40 000 / 90 000 · 44%", "the numbers over enemies off: the boss's still")
    -- the size of the enemy numbers: × enemy_hp_size, 18 px at 100 %
    for _, case in ipairs({ { 1, 1, 18 }, { 1, 2, 36 }, { 1.5, 0.5, 13.5 }, { 2, 3, 108 } }) do
        s = fresh({ scale = case[1], enemy_hp_size = case[2] })
        draw_boss(boss(), s)
        near(texts()[1].px, case[3], 1e-9, "scale " .. case[1] .. ", size " .. case[2])
        near(ui.find("push_font_size")[1], case[3], 1e-9, "pushed")
    end
    -- killed, full, above full
    s = fresh()
    draw_boss(boss({ hp = 0 }), s); eq(texts()[1].text, "0 / 90 000 · 0%", "killed")
    draw_boss(boss({ hp = 90000 }), s); eq(texts()[1].text, "90 000 / 90 000 · 100%", "full")
    draw_boss(boss({ hp = "x" }), s); eq(#ui.calls, 0, "an HP that is not a number: nothing")
    draw_boss(boss({ full = 0 }), s); eq(#ui.calls, 0, "no full HP: nothing")
end)

test("the boss's numbers in the same fixed look as over heads, whatever the meter's look", function()
    local s = fresh()
    draw_boss(boss(), s)
    local calls = ui.calls_of("add_text")
    eq(#calls, 10, "the shadow, eight outline copies, the text")
    local text = calls[10]
    eq(text.col, BEIGE, "the pawn names' beige")
    eq(calls[1].col, SHADOW, "a black shadow"); eq(calls[1].x - text.x, 2, "2 px right"); eq(calls[1].y - text.y, 2, "down")
    for i = 2, 9 do
        eq(calls[i].col, OUTLINE, "black outline copies")
        eq(math.max(math.abs(calls[i].x - text.x), math.abs(calls[i].y - text.y)), 1, "one px off")
    end
    local function frame_of(over)
        draw_boss(boss(), fresh(over))
        local out = {}
        for _, c in ipairs(ui.calls_of("add_text")) do
            out[#out + 1] = string.format("%s,%s,%x,%s,%s", c.x, c.y, c.col, c.text, c.px)
        end
        return table.concat(out, "|") .. "|" .. #ui.calls_of("add_rect_filled")
    end
    local base = frame_of({})
    for _, over in ipairs({ { style = "panel" }, { shadow = 0 }, { outline = false }, { halo = true, opacity = 1 } }) do
        eq(frame_of(over), base, "the same with another look of the meter")
    end
end)

test("draw_boss never raises and stays balanced", function()
    local s = fresh()
    local add_text = ui.draw_list.add_text
    ui.draw_list.add_text = function() error("draw list broke") end
    ui.clear_calls()
    local err = EnemyBars.draw_boss(boss(), s)
    eq(type(err), "string", "the error comes back")
    eq(ui.balanced(), true, "the font size popped again")
    ui.draw_list.add_text = add_text
    ui.clear_calls()
    eq(EnemyBars.draw_boss(nil, s), nil, "no bar: nothing, no error")
    eq(EnemyBars.draw_boss(5, s), nil, "a bar that is not one: nothing")
    eq(type(EnemyBars.draw_boss(boss(), nil)), "string", "no settings")
    eq(type(EnemyBars.draw_boss(boss(), { values = { boss_hp_numbers = "all", scale = "big", enemy_hp_size = 1 } })),
        "string", "a scale that is not a number")
    eq(ui.balanced(), true, "balanced")
    eq(#ui.calls_of("add_text"), 0, "nothing drawn")
    for _, name in ipairs({ "get_display_size", "get_background_draw_list" }) do
        local fn = imgui[name]
        imgui[name] = nil
        draw_boss(boss(), s)
        eq(#ui.calls_of("add_text"), 0, "no " .. name .. ": nothing")
        imgui[name] = fn
        draw_boss(boss(), s)
        eq(#texts(), 0, name .. " is not tried again")
        eq(table.concat(EnemyBars.missing(), ","), name, "and named with the enemy numbers' calls")
        EnemyBars.reset()
        draw_boss(boss(), s)
        eq(#texts(), 1, "until reset")
    end
end)

i18n.set("en")
T.finish()
