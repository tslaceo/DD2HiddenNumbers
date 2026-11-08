package.path = "mod/reframework/autorun/?.lua;tests/?.lua;" .. package.path

local T = require("testlib")
local test, eq, near = T.test, T.eq, T.near
local ui = require("stubs/ui").install()
local i18n = require("DD2DamageMeter/i18n")
local Settings = require("DD2DamageMeter/settings")
local EnemyBars = require("DD2DamageMeter/ui/enemy_bars")
local BuildupBars = require("DD2DamageMeter/ui/buildup_bars")

-- The boss bar as game/gauges.lua gives it on 1920 × 1080 (All not moved): from x 564 to 1340, its middle at 109.5.
local FULL_HD = { x = 564, y = 109.5, width = 776 }
local WIDE = { x = 665.3, y = 109.5, width = 776 }

local BEIGE = EnemyBars.COLORS.text

-- ImU32 (0xAABBGGRR) of an opaque 0xRRGGBB.
local function abgr(rgb)
    local r, g, b = (rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF
    return 0xFF000000 | (b << 16) | (g << 8) | r
end

local function fresh(over)
    ui.reset()
    BuildupBars.reset()
    i18n.set("ru")
    local saved = over or {}
    return Settings.load({ read = function() return saved end, write = function(t) saved = t end })
end

local function draw(bar, rows, s, t)
    ui.clear_calls()
    local err = BuildupBars.draw(bar, rows, s, t)
    if err then error("draw failed: " .. err, 2) end
    eq(ui.balanced(), true, "stacks balanced")
end

-- The width the stub gives `text` at `px`.
local function width(text, px)
    return utf8.len(text) * ui.char_w * px / 14
end

-- The texts drawn in `col` (each SceneText's own copy, not its shadow or outline), in order.
local function texts_in(col)
    local out = {}
    for _, c in ipairs(ui.calls_of("add_text")) do
        if c.col == col then out[#out + 1] = c end
    end
    return out
end

-- The filled rectangles in `col`, in order.
local function rects_in(col)
    local out = {}
    for _, c in ipairs(ui.calls_of("add_rect_filled")) do
        if c.col == col then out[#out + 1] = c end
    end
    return out
end

local FAINT = { id = 3, name = "Faint", value = 313, max = 1400, hits = 11 }
local FIRE = { id = 5, name = "FireSpread", value = 1800, max = 5000, hits = 7 }

test("the texts: the status word; value / threshold and ≈ hits, the plural forms", function()
    i18n.set("ru")
    eq(BuildupBars.label(FAINT), "Обморок", "the journal's status word")
    eq(BuildupBars.label({ id = 14, name = "WetElectric" }), "Электричество (мокрый)", "WetElectric's own word")
    eq(BuildupBars.numbers(FIRE), "1 800 / 5 000 · ≈ 7 ударов", "7: ударов")
    for n, word in pairs({ [1] = "удар", [2] = "удара", [4] = "удара", [5] = "ударов", [11] = "ударов",
        [21] = "удар", [22] = "удара" }) do
        eq(BuildupBars.numbers({ value = 10, max = 100, hits = n }), "10 / 100 · ≈ " .. n .. " " .. word, "ru " .. n)
    end
    eq(BuildupBars.numbers({ value = 313.4, max = 1400 }), "313 / 1 400", "before the first rise: no hits")
    eq(BuildupBars.numbers({ value = 313 }), "313", "no threshold: the value alone")
    i18n.set("en")
    eq(BuildupBars.label(FAINT), "Faint", "en")
    eq(BuildupBars.numbers({ value = 10, max = 100, hits = 1 }), "10 / 100 · ≈ 1 hit", "en 1")
    eq(BuildupBars.numbers({ value = 10, max = 100, hits = 2 }), "10 / 100 · ≈ 2 hits", "en 2")
    eq(BuildupBars.label({ id = 14, name = "WetElectric" }), "Shock (wet)", "WetElectric's word in English")
    -- a status with no word: its enum name, else its number
    eq(BuildupBars.label({ id = 99, name = "Stun" }), "Stun", "no word: the enum name")
    eq(BuildupBars.label({ id = 42 }), "42", "no name: the number")
    i18n.set("ru")
end)

test("Blind's row: its word with « ?» after it, in both languages; another status's without", function()
    local BLIND = { id = 23, name = "Blind", value = 40, max = 100, hits = 3 }
    i18n.set("ru")
    eq(BuildupBars.label(BLIND), "Ослепление ?", "ru")
    eq(BuildupBars.label(FAINT), "Обморок", "Faint unmarked")
    i18n.set("en")
    eq(BuildupBars.label(BLIND), "Blindness ?", "en")
    eq(BuildupBars.label(FAINT), "Faint", "Faint unmarked in English")
    i18n.set("ru")
end)

test("the colour of each status, any other grey", function()
    local want = {
        Poison = 0x8FD16A, VirulentPoison = 0x8FD16A, FireSpread = 0xF0A050, OilSpread = 0xF0A050,
        Frostbite = 0x8EC8F0, Freeze = 0x8EC8F0, Faint = 0xD8D070, Sleep = 0xB79CE8, Electric = 0xE8E070,
        WetElectric = 0xE8E070, Wet = 0x6FA8DC, Oil = 0x9A8060, Stone = 0xB0B0B0,
    }
    for name, rgb in pairs(want) do eq(BuildupBars.color_of(name), abgr(rgb), name) end
    eq(BuildupBars.color_of(nil), abgr(0xB0B0B0), "no name: grey")
    -- drawn so: the word and the fill in the status colour, the numbers beige
    local s = fresh()
    draw(FULL_HD, { FAINT, FIRE }, s)
    eq(texts_in(abgr(0xD8D070))[1].text, "Обморок", "Faint's word in its colour")
    eq(texts_in(abgr(0xF0A050))[1].text, "Горение", "burning's")
    eq(texts_in(BEIGE)[1].text, "313 / 1 400 · ≈ 11 ударов", "the numbers beige")
    eq(#rects_in(abgr(0xD8D070)), 1, "Faint's fill"); eq(#rects_in(abgr(0xF0A050)), 1, "burning's fill")
end)

test("the rows under the bar: its left end and width, a gap under its marks, one row per status in the order given",
    function()
    eq(BuildupBars.TOP_GAP, 6, "TOP_GAP"); eq(BuildupBars.BAR_PX, 3, "BAR_PX"); eq(BuildupBars.FONT_SIZE, 14, "px")
    eq(BuildupBars.MARKS_BELOW, 18, "MARKS_BELOW")
    local s = fresh()
    draw(FULL_HD, { FAINT, FIRE }, s)
    local track = rects_in(BuildupBars.COLORS.track)
    eq(#track, 2, "a track per row")
    -- the segment marks end 18 units under the bar's middle: 127.5; the first row's text 6 px under that (133.5, 134
    -- rounded), its bar 2 px under the text's 14 px, 3 px high; the next row 5 px further down
    local word = texts_in(abgr(0xD8D070))[1]
    eq(word.x, 565, "the word 1 px in, its outline (1 px at 14 px) at the bar's left end")
    eq(word.y, 134, "6 px under the bar's marks")
    eq(word.px, 14, "14 px × the scale × enemy_hp_size")
    eq(track[1].x0, 564, "the track from the bar's left end"); eq(track[1].x1, 1340, "to its right end")
    eq(track[1].y0, 134 + 14 + 2, "under the text"); eq(track[1].y1 - track[1].y0, 3, "3 px")
    eq(texts_in(abgr(0xF0A050))[1].y, track[1].y1 + 5, "the next row 5 px under")
    eq(track[2].y0, track[1].y1 + 5 + 14 + 2, "its track")
    -- the numbers right-aligned at the bar's right end, their shadow included
    local numbers = texts_in(BEIGE)[1]
    eq(numbers.y, 134, "on the word's line")
    eq(numbers.x + width(numbers.text, 14) + 2, 1340, "their right edge 2 px (the shadow at 14 px) before the end")
end)

test("the fill: value / threshold of the bar's width, at most all of it", function()
    local s = fresh()
    local fill_col = abgr(0xD8D070)
    for _, case in ipairs({ { 313, 1400, 173 }, { 700, 1400, 388 }, { 1400, 1400, 776 }, { 2000, 1400, 776 },
        { 1, 1400, 1 } }) do
        draw(FULL_HD, { { id = 3, name = "Faint", value = case[1], max = case[2] } }, s)
        local fill = rects_in(fill_col)[1]
        eq(fill.x0, 564, "from the left end"); eq(fill.x1 - fill.x0, case[3], case[1] .. " / " .. case[2])
        eq(fill.y0, rects_in(BuildupBars.COLORS.track)[1].y0, "over the track")
    end
    -- no threshold: the track alone
    draw(FULL_HD, { { id = 3, name = "Faint", value = 313 } }, s)
    eq(#rects_in(fill_col), 0, "no fill"); eq(#rects_in(BuildupBars.COLORS.track), 1, "the track")
    eq(texts_in(BEIGE)[1].text, "313", "the value alone")
end)

test("the poise rows: «Пошатнуть» and «Опрокинуть», their colours, their numbers with the hits", function()
    i18n.set("ru")
    eq(BuildupBars.label({ id = "lean" }), "Пошатнуть", "stagger")
    eq(BuildupBars.label({ id = "blown" }), "Опрокинуть", "knock down")
    eq(BuildupBars.numbers({ id = "lean", value = 41841, max = 65000, hits = 24 }), "41 841 / 65 000 · ≈ 24 удара",
        "value / threshold · hits")
    eq(BuildupBars.color_of("lean"), abgr(0xD8D8D8), "lean's colour"); eq(BuildupBars.color_of("blown"),
        abgr(0xE07B6A), "blown's")
    i18n.set("en")
    eq(BuildupBars.label({ id = "lean" }), "Stagger", "en"); eq(BuildupBars.label({ id = "blown" }), "Knock down", "en")
    i18n.set("ru")
    local s = fresh()
    draw(FULL_HD, { { id = "lean", value = 41841, max = 65000, hits = 24 },
        { id = "blown", value = 41841, max = 195000 }, FAINT }, s)
    local lean, blown = texts_in(abgr(0xD8D8D8))[1], texts_in(abgr(0xE07B6A))[1]
    eq(lean.text, "Пошатнуть", "drawn in its colour"); eq(blown.text, "Опрокинуть", "and blown")
    eq(lean.y < blown.y and blown.y < texts_in(abgr(0xD8D070))[1].y, true, "in the order given: the poise first")
    eq(rects_in(abgr(0xD8D8D8))[1].x1 - 564, math.floor(776 * 41841 / 65000 + 0.5), "its fill")
end)

test("MAX_ROWS counts the poise rows: two of them and five statuses give six rows, the last status left out",
    function()
    eq(BuildupBars.MAX_ROWS, 6, "MAX_ROWS")
    local s = fresh()
    local rows = { { id = "lean", value = 100, max = 65000 }, { id = "blown", value = 100, max = 195000 } }
    for i, name in ipairs({ "Poison", "Faint", "FireSpread", "Frostbite", "Sleep" }) do
        rows[#rows + 1] = { id = i, name = name, value = 10, max = 100 }
    end
    draw(FULL_HD, rows, s)
    eq(#rects_in(BuildupBars.COLORS.track), 6, "six tracks")
    eq(#texts_in(abgr(0xB79CE8)), 0, "Sleep, the seventh row, not drawn")
    eq(#texts_in(abgr(0x8EC8F0)), 1, "Frostbite, the sixth, drawn")
end)

test("nothing at all without a boss bar or a building status", function()
    local s = fresh()
    draw(nil, { FAINT }, s)
    eq(#ui.calls, 0, "no bar: no imgui call")
    draw(FULL_HD, {}, s)
    eq(#ui.calls, 0, "no status: none")
    draw(FULL_HD, nil, s)
    eq(#ui.calls, 0, "no rows: none")
    draw(FULL_HD, { 5, { id = 3, name = "Faint", value = 0, max = 100 }, { id = 3, value = "x" } }, s)
    eq(#ui.calls, 0, "rows that are not rows, or at 0: none")
end)

test("nothing drawn outside the bar's two ends: long texts at large sizes are cut, the word first", function()
    for _, case in ipairs({ { 1, 1 }, { 1, 3 }, { 2, 3 }, { 1.5, 2 } }) do
        local s = fresh({ scale = case[1] })
        s.values.enemy_hp_size = case[2]
        local rows = { { id = 3, name = "Faint", value = 12345, max = 100000, hits = 1234 },
            { id = 5, name = "FireSpread", value = 1800, max = 5000, hits = 7 } }
        draw(FULL_HD, rows, s)
        local what = "scale " .. case[1] .. ", size " .. case[2]
        local px = 14 * case[1] * case[2]
        for _, c in ipairs(ui.calls_of("add_text")) do
            eq(c.x >= 564, true, "a text right of the left end: " .. c.text .. ", " .. what)
            eq(c.x + width(c.text, px) <= 1340, true, "a text left of the right end: " .. c.text .. ", " .. what)
        end
        for _, c in ipairs(ui.calls_of("add_rect_filled")) do
            eq(c.x0 >= 564 and c.x1 <= 1340, true, "a bar between the ends, " .. what)
        end
    end
    -- at 84 px the numbers alone are wider than the bar: the hits go, then they are cut; the word goes
    local s = fresh({ scale = 2 })
    s.values.enemy_hp_size = 3
    draw(FULL_HD, { { id = 3, name = "Faint", value = 12345, max = 100000, hits = 1234 } }, s)
    eq(#texts_in(abgr(0xD8D070)), 0, "no room for the word")
    local numbers = texts_in(BEIGE)[1].text
    eq(numbers:find("≈", 1, true), nil, "the hits left out: " .. numbers)
end)

test("the size and the place follow the meter's scale × enemy_hp_size and the display", function()
    local s = fresh({ scale = 1.5 })
    s.values.enemy_hp_size = 2
    draw(FULL_HD, { FAINT }, s)
    local word = texts_in(abgr(0xD8D070))[1]
    near(word.px, 42, 1e-9, "14 × 1.5 × 2"); eq(word.y, 137, "6 px × 1.5 under the marks: round(127.5 + 9)")
    near(ui.find("push_font_size")[1], 42, 1e-9, "pushed")
    local track = rects_in(BuildupBars.COLORS.track)[1]
    eq(track.y1 - track.y0, 5, "3 px × 1.5, rounded")
    -- 3440 × 1440: the bar's ends where EnemyBars has them
    s = fresh()
    ui.display = { x = 3440, y = 1440 }
    draw(WIDE, { FAINT }, s)
    local left = EnemyBars.boss_left(WIDE, 3440, 1440)
    local right = EnemyBars.boss_anchor(WIDE, 3440, 1440)
    track = rects_in(BuildupBars.COLORS.track)[1]
    eq(track.x0, math.ceil(left), "the left end"); eq(track.x1, math.floor(right), "the right end")
    ui.display = { x = 1920, y = 1080 }
end)

test("the first row's text, its outline included, starts below the bar's segment marks at 1080p and 1440p",
    function()
    for _, display in ipairs({ { 1920, 1080 }, { 2560, 1440 }, { 3440, 1440 } }) do
        local dw, dh = display[1], display[2]
        local s = fresh()
        ui.display = { x = dw, y = dh }
        draw(FULL_HD, { FAINT }, s)
        local _, middle = EnemyBars.boss_left(FULL_HD, dw, dh)
        local marks = middle + BuildupBars.MARKS_BELOW * dh / 1080
        local top = math.huge
        for _, c in ipairs(ui.calls_of("add_text")) do top = math.min(top, c.y) end
        eq(top > marks, true, dw .. " × " .. dh .. ": the texts from " .. top .. ", the marks to " .. marks)
        eq(texts_in(abgr(0xD8D070))[1].y, math.floor(marks + 6 + 0.5), dw .. " × " .. dh .. ": 6 px under them")
    end
    ui.display = { x = 1920, y = 1080 }
end)

test("draw never raises and stays balanced; a missing call is named and not tried again until reset", function()
    local s = fresh()
    local add_text = ui.draw_list.add_text
    ui.draw_list.add_text = function() error("draw list broke") end
    ui.clear_calls()
    eq(type(BuildupBars.draw(FULL_HD, { FAINT }, s)), "string", "the error comes back")
    eq(ui.balanced(), true, "the font size popped again")
    ui.draw_list.add_text = add_text
    eq(type(BuildupBars.draw(FULL_HD, { FAINT }, nil)), "string", "no settings")
    eq(type(BuildupBars.draw({}, { FAINT }, s)), "nil", "a bar that could not be read: where the game has it")
    local fn = imgui.get_background_draw_list
    imgui.get_background_draw_list = nil
    draw(FULL_HD, { FAINT }, s)
    eq(#ui.calls_of("add_text"), 0, "no background list: nothing")
    imgui.get_background_draw_list = fn
    draw(FULL_HD, { FAINT }, s)
    eq(#ui.calls_of("add_text"), 0, "not tried again")
    eq(table.concat(BuildupBars.missing(), ","), "get_background_draw_list", "named")
    BuildupBars.reset()
    draw(FULL_HD, { FAINT }, s)
    eq(#ui.calls_of("add_text") > 0, true, "until reset")
end)

-- The time left --------------------------------------------------------------------------------------------

-- Faint on the snow ogre, set off at t 10 with 7.97 s of its 8 left (Buildup.read's active row).
local function ogre(over)
    local r = { id = 3, name = "Faint", active = true, remain = 7.97, duration = 8, at = 10 }
    for k, v in pairs(over or {}) do r[k] = v end
    return r
end

test("an active row's text: «ещё N с», the seconds whole and rounded up; en and ru", function()
    i18n.set("ru")
    eq(BuildupBars.numbers(ogre()), "ещё 8 с", "7.97 s: 8")
    eq(BuildupBars.numbers(ogre({ remain = 0.3 })), "ещё 1 с", "0.3 s: 1, until the end")
    eq(BuildupBars.numbers(ogre({ remain = 3 })), "ещё 3 с", "3 s: 3")
    eq(BuildupBars.numbers(ogre(), 15), "ещё 3 с", "at t 15: 2.97 s left")
    eq(BuildupBars.numbers(ogre(), 30), "ещё 0 с", "past the end: 0")
    i18n.set("en")
    eq(BuildupBars.numbers(ogre()), "8 s left", "en")
    eq(i18n.t("buildup_left", "12"), "12 s left", "en buildup_left")
    eq(i18n.t("buildup_resist", "20"), "resistance 20%", "en buildup_resist")
    i18n.set("ru")
    eq(i18n.t("buildup_left", "12"), "ещё 12 с", "ru buildup_left")
    eq(i18n.t("buildup_resist", "20"), "сопротивление 20 %", "ru buildup_resist")
end)

test("the drawn time left drains with t: 7.97 at the read, 2.97 five seconds later, 0 past the end", function()
    local r = ogre()
    near(BuildupBars.left(r, 10), 7.97, 1e-9, "at the read")
    near(BuildupBars.left(r, 15), 2.97, 1e-9, "5 s later")
    near(BuildupBars.left(r, 17.97), 0, 1e-9, "at the end: 0")
    eq(BuildupBars.left(r, 30), 0, "past the end: 0, never below")
    eq(BuildupBars.left(r, nil), 7.97, "without a t: as read")
    eq(BuildupBars.left(r, 9), 7.97, "a t before the read: as read")
    r.at = nil
    eq(BuildupBars.left(r, 15), 7.97, "without the read's t: as read")
end)

test("an active row is drawn: its word in its colour, the time left beige, a bar full at the trigger that drains",
    function()
    local s = fresh()
    local col = abgr(0xD8D070)
    local full = ogre({ remain = 8 })
    draw(FULL_HD, { full }, s, 10)
    eq(texts_in(col)[1].text, "Обморок", "the word in Faint's colour")
    eq(texts_in(BEIGE)[1].text, "ещё 8 с", "the time left on the right, beige")
    local numbers = texts_in(BEIGE)[1]
    eq(numbers.x + width(numbers.text, 14) + 2, 1340, "right-aligned at the bar's right end")
    eq(#rects_in(BuildupBars.COLORS.track), 1, "its track")
    eq(rects_in(col)[1].x1 - rects_in(col)[1].x0, 776, "at the trigger: full")
    draw(FULL_HD, { full }, s, 14)
    eq(rects_in(col)[1].x1 - rects_in(col)[1].x0, 388, "at half time: half")
    eq(texts_in(BEIGE)[1].text, "ещё 4 с", "4 s left")
    draw(FULL_HD, { full }, s, 18)
    eq(#rects_in(col), 0, "at 0: empty, no fill"); eq(#rects_in(BuildupBars.COLORS.track), 1, "the track still there")
    eq(texts_in(BEIGE)[1].text, "ещё 0 с", "0 s left until the next read drops the row")
    draw(FULL_HD, { ogre() }, s, 10.5)
    eq(rects_in(col)[1].x1 - 564, math.floor(776 * 7.47 / 8 + 0.5), "drawn remain / duration of the width")
    -- no duration: the text alone and a full bar
    local endless = ogre()
    endless.duration = nil
    draw(FULL_HD, { endless }, s, 14)
    eq(rects_in(col)[1].x1 - rects_in(col)[1].x0, 776, "no duration: full")
    eq(texts_in(BEIGE)[1].text, "ещё 4 с", "the time left")
end)

test("draw without a t still draws, the time left as read", function()
    local s = fresh()
    draw(FULL_HD, { ogre() }, s)
    eq(texts_in(BEIGE)[1].text, "ещё 8 с", "7.97 s: 8")
    eq(rects_in(abgr(0xD8D070))[1].x1 - 564, math.floor(776 * 7.97 / 8 + 0.5), "the fill of 7.97 / 8")
end)

test("the resistance after the numbers at immunity 1 and above; none at 0", function()
    i18n.set("ru")
    local building = { id = 3, name = "Faint", value = 313, max = 1400, hits = 11, resistance = 0.2, immunity = 1 }
    eq(BuildupBars.numbers(building), "313 / 1 400 · ≈ 11 ударов · сопротивление 20 %", "a building row, 20 %")
    eq(BuildupBars.numbers(ogre({ resistance = 0.8, immunity = 3 })), "ещё 8 с · сопротивление 80 %",
        "an active row, 80 %")
    eq(BuildupBars.numbers(ogre({ resistance = 0.5, immunity = 2 })), "ещё 8 с · сопротивление 50 %", "50 %")
    eq(BuildupBars.numbers({ value = 313, max = 1400, hits = 11, resistance = 0, immunity = 0 }),
        "313 / 1 400 · ≈ 11 ударов", "immunity 0: none")
    eq(BuildupBars.numbers({ value = 313, max = 1400, resistance = 0.2, immunity = 0 }), "313 / 1 400",
        "immunity 0, a rate notwithstanding: none")
    eq(BuildupBars.numbers({ value = 313, max = 1400, resistance = 0, immunity = 1 }), "313 / 1 400",
        "a rate of 0: none")
    eq(BuildupBars.numbers({ value = 313, resistance = 0.2, immunity = 1 }), "313 · сопротивление 20 %",
        "no threshold: after the value")
    eq(BuildupBars.numbers(building, nil, true), "313 / 1 400 · сопротивление 20 %", "without the hits")
    eq(BuildupBars.numbers(building, nil, true, true), "313 / 1 400", "without the hits and the resistance")
    i18n.set("en")
    eq(BuildupBars.numbers(building), "313 / 1 400 · ≈ 11 hits · resistance 20%", "en")
    i18n.set("ru")
    -- drawn on both kinds of rows
    local s = fresh()
    draw(FULL_HD, { building, ogre({ resistance = 0.2, immunity = 1 }) }, s, 10)
    local beige = texts_in(BEIGE)
    eq(beige[1].text, "313 / 1 400 · ≈ 11 ударов · сопротивление 20 %", "on the building row")
    eq(beige[2].text, "ещё 8 с · сопротивление 20 %", "on the active row")
end)

test("room short: the hits go first, then the resistance, before the numbers are cut", function()
    local building = { id = 3, name = "Faint", value = 313, max = 1400, hits = 11, resistance = 0.2, immunity = 1 }
    local active = ogre({ resistance = 0.2, immunity = 1 })
    -- 42 px (21 px a letter): the whole 46 letters (966 px) do not fit, without the hits 32 (672 px) do
    local s = fresh({ scale = 1.5 })
    s.values.enemy_hp_size = 2
    draw(FULL_HD, { building, active }, s, 10)
    eq(texts_in(BEIGE)[1].text, "313 / 1 400 · сопротивление 20 %", "42 px: the hits gone, the resistance kept")
    eq(texts_in(BEIGE)[2].text, "ещё 8 с · сопротивление 20 %", "the active row whole (28 letters, 588 px)")
    -- 56 px (28 a letter): without the hits 896 px, too wide; the numbers alone 308 px, whole
    s = fresh({ scale = 2 })
    s.values.enemy_hp_size = 2
    draw(FULL_HD, { building, active }, s, 10)
    eq(texts_in(BEIGE)[1].text, "313 / 1 400", "56 px: the resistance gone too, the numbers whole")
    eq(texts_in(BEIGE)[2].text, "ещё 8 с", "the active row: the resistance gone (784 px), the time left whole")
end)

test("MAX_ROWS counts the active rows: seven active statuses give six rows", function()
    local s = fresh()
    local rows = {}
    for i, name in ipairs({ "Poison", "Faint", "FireSpread", "Frostbite", "Wet", "Oil", "Sleep" }) do
        rows[i] = { id = i, name = name, active = true, remain = 5, duration = 10, at = 1 }
    end
    draw(FULL_HD, rows, s, 1)
    eq(#rects_in(BuildupBars.COLORS.track), 6, "six tracks")
    eq(#texts_in(abgr(0xB79CE8)), 0, "Sleep, the seventh, not drawn")
    eq(#texts_in(abgr(0x9A8060)), 1, "Oil, the sixth, drawn")
    -- an active row that is not one: no time left as read, or none that is a number
    draw(FULL_HD, { { id = 3, name = "Faint", active = true, remain = 0, duration = 8, at = 1 },
        { id = 3, name = "Faint", active = true, remain = "x", duration = 8, at = 1 } }, s, 1)
    eq(#ui.calls, 0, "none drawn")
end)

i18n.set("en")
T.finish()
