-- The status buildup bars under the game's boss bar (their reader: game/buildup.lua): the
-- boss's poise, a row for a stagger and one for a knock-down, then a row for each status building on it or in effect,
-- each as wide as the boss bar, TOP_GAP px × the meter's scale under the segment marks the game draws under the bar
-- (MARKS_BELOW): the row's word on the left in its colour, its numbers on the right ("1 800 / 5 000 · ≈ 7
-- ударов"; a status in effect: "ещё 12 с"; after either, the resistance earlier triggers raised: " · сопротивление
-- 20 %"), and under them a thin bar BAR_PX px × the scale high in that colour on a dark track, filled value /
-- threshold, or for a status in effect, full when it is set off and drained to empty over its duration, every frame.
-- On imgui's background draw list (under every window), the texts in the look of the HP numbers
-- (ui/scene_text.lua: shadow and outline, the numbers in their beige), at FONT_SIZE px × the meter's scale ×
-- `enemy_hp_size`. Everything stays between the boss bar's two ends, the texts' shadow and outline too, so it never
-- covers the boss's HP numbers right of the bar nor the enemy plate left of it: a text too long is cut (the hits go
-- first, then the resistance, then the numbers are cut with "…"; the word gets what the numbers leave, WORD_GAP px ×
-- the scale away, and goes when no letter of it fits). No game access; the texts from i18n.
--
-- An active row is Buildup.read's row of a status in effect: active = true and a remain (s) above 0, with its
-- duration (s, may be nil) and at (the read's t); any other row is a building one.
--
--   BuildupBars.label(row) -> text   a poise row's word (buildup_lean «Пошатнуть», buildup_blown «Опрокинуть», by its
--     id); a status's: status_<name>, else the enum name itself, else the id; an unclear status's word with " ?"
--     after it (Journal.mark_unclear: "Ослепление ?")
--   BuildupBars.left(row, t) -> s   an active row's seconds left at t: max(0, remain - (t - at)), so that it drains
--     between the reads; remain as read without a t, without an at, or with t before at
--   BuildupBars.numbers(row, t, no_hits, no_resist) -> text   an active row's "ещё N с" (buildup_left; N the seconds
--     left at t, whole and rounded up, so "ещё 1 с" lasts until the end); a building row's "value / max · ≈ N
--     ударов" (buildup_hits, its plural form by I18n.tn), the hits only with a threshold and a hits count and not
--     `no_hits`, "value / max" without hits, "value" alone without a threshold. Then, on either and not
--     `no_resist`, " · сопротивление 20 %" (buildup_resist, round(resistance × 100)) when its immunity is 1 or more
--     and its resistance above 0
--   BuildupBars.color_of(name) -> ImU32   a status's colour by its name, a poise row's by its id ("lean", "blown")
--     (RGB below), B0B0B0 for any other
--   BuildupBars.draw(bar, rows, settings, t) -> err   bar = the boss bar as game/gauges.lua gives it ({ x, y, width },
--     its ends by EnemyBars.boss_left and EnemyBars.boss_anchor; where the game has the bar when they cannot be
--     read); rows = Buildup.read's answer, the poise rows first: one row each, in the order given, for at most
--     MAX_ROWS of those that are active or have a value above 0 (an entry that is not such a row is skipped); t = the
--     frame's time (s, the clock Buildup.read had). The fill is, of the bar's width and at most all of it, an active
--     row's BuildupBars.left(row, t) / duration (all of it without a duration, none at 0), a building row's value /
--     max (none without a threshold). Nothing, not even an imgui call, without a bar or such a row. Never raises,
--     whatever it is given: everything runs under one pcall and the font size pushed is popped again; err = nil or the
--     message of the error caught
--   BuildupBars.COLORS = { text, track }   the numbers' beige and the track's ImU32
--   BuildupBars.MARKS_BELOW, FONT_SIZE, TOP_GAP, TEXT_GAP, BAR_PX, ROW_GAP, WORD_GAP, MAX_ROWS   the constants below
--   BuildupBars.missing() -> { name }: the imgui calls found missing (get_display_size, get_background_draw_list), in
--     order, not tried again until BuildupBars.reset(), which also forgets the measured widths
local i18n = require("DD2DamageMeter/i18n")
local Journal = require("DD2DamageMeter/journal")
local Kit = require("DD2DamageMeter/ui/kit")
local EnemyBars = require("DD2DamageMeter/ui/enemy_bars")
local SceneText = require("DD2DamageMeter/ui/scene_text")

local BuildupBars = {}

local GUI_H = 1080         -- the bars' GUI space's height: a GUI unit is dh / GUI_H px
-- The boss bar's HP-segment marks: the diamonds the game draws just under the bar. On a Fimbul screenshot
-- they reached about 22 px under the bar's middle, from 14 px; the rows start below MARKS_BELOW units under the
-- bar's middle, × H / 1080 like BOSS_MIDDLE (ui/enemy_bars.lua). A boss with no marks gets that gap anyway.
local MARKS_BELOW = 18
local FONT_SIZE = 14       -- px × the meter's scale × enemy_hp_size
local TOP_GAP = 6          -- px × the meter's scale between the segment marks and the first row's text
local TEXT_GAP = 2         -- px × the scale between a row's text and its bar
local BAR_PX = 3           -- px × the scale: a row's bar
local ROW_GAP = 5          -- px × the scale between a row's bar and the next row's text
local WORD_GAP = 12        -- px × the scale at least between the status word and the numbers
local MAX_ROWS = 6         -- rows drawn: the statuses building at once past these are left out
local TRACK_ALPHA = 140    -- 55 % of 255: the track's black, as the enemy plate's backing
BuildupBars.MARKS_BELOW = MARKS_BELOW
BuildupBars.FONT_SIZE, BuildupBars.TOP_GAP, BuildupBars.TEXT_GAP, BuildupBars.BAR_PX = FONT_SIZE, TOP_GAP, TEXT_GAP,
    BAR_PX
BuildupBars.ROW_GAP, BuildupBars.WORD_GAP, BuildupBars.MAX_ROWS = ROW_GAP, WORD_GAP, MAX_ROWS

-- ImU32 colours are 0xAABBGGRR; `abgr` takes the usual 0xRRGGBB and an alpha of 0..255.
local function abgr(rgb, alpha)
    local r, g, b = (rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF
    return (alpha << 24) | (b << 16) | (g << 8) | r
end

-- Each status's colour, by its StatusConditionEnum name; any other OTHER_RGB.
local RGB = {
    Poison = 0x8FD16A, VirulentPoison = 0x8FD16A,
    FireSpread = 0xF0A050, OilSpread = 0xF0A050,
    Frostbite = 0x8EC8F0, Freeze = 0x8EC8F0,
    Faint = 0xD8D070,
    Sleep = 0xB79CE8,
    Electric = 0xE8E070, WetElectric = 0xE8E070,
    Wet = 0x6FA8DC,
    Oil = 0x9A8060,
    -- the poise rows, by their ids
    lean = 0xD8D8D8,
    blown = 0xE07B6A,
}
local POISE_WORD = { lean = "buildup_lean", blown = "buildup_blown" }
local OTHER_RGB = 0xB0B0B0

BuildupBars.COLORS = { text = EnemyBars.COLORS.text, track = abgr(0x000000, TRACK_ALPHA) }
local C = BuildupBars.COLORS

local SEP = " · "
local ELLIPSIS = "…"

local missing

function BuildupBars.reset()
    missing = {}
    SceneText.reset()
end
BuildupBars.reset()

function BuildupBars.missing()
    local list = {}
    for name in pairs(missing) do list[#list + 1] = name end
    table.sort(list)
    return list
end

local function finite(x)
    return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function round(v)
    return math.floor(v + 0.5)
end

function BuildupBars.color_of(name)
    return abgr(RGB[name] or OTHER_RGB, 255)
end

function BuildupBars.label(row)
    if POISE_WORD[row.id] then return i18n.t(POISE_WORD[row.id]) end
    local name = row.name
    if type(name) == "string" and name ~= "" then
        local key = "status_" .. name
        local word = i18n.t(key)
        if word == key then word = name end -- i18n gives the key back for a text it does not have
        return Journal.mark_unclear(name, word)
    end
    return tostring(row.id or "?")
end

-- An active row (Buildup.read's: a status in effect) with its time left as read.
local function timed(row)
    return row.active == true and finite(row.remain) and row.remain > 0
end

-- A row that raised its resistance: a level of 1 or more and a rate above 0.
local function resisted(row)
    return finite(row.immunity) and row.immunity >= 1 and finite(row.resistance) and row.resistance > 0
end

function BuildupBars.left(row, t)
    if finite(t) and finite(row.at) and t >= row.at then return math.max(0, row.remain - (t - row.at)) end
    return row.remain
end

function BuildupBars.numbers(row, t, no_hits, no_resist)
    local text
    if timed(row) then
        text = i18n.t("buildup_left", i18n.num(math.ceil(BuildupBars.left(row, t))))
    else
        text = i18n.num(row.value)
        if finite(row.max) then
            text = text .. " / " .. i18n.num(row.max)
            if not no_hits and finite(row.hits) then text = text .. SEP .. i18n.tn("buildup_hits", row.hits) end
        end
    end
    if not no_resist and resisted(row) then
        text = text .. SEP .. i18n.t("buildup_resist", i18n.num(row.resistance * 100))
    end
    return text
end

-- The share of the bar's width a row fills, nil for none: an active row's time left of its duration (all of it
-- without a duration), a building row's value of its threshold (none without one); at most 1.
local function share(row, t)
    if timed(row) then
        if not (finite(row.duration) and row.duration > 0) then return 1 end
        return math.min(1, BuildupBars.left(row, t) / row.duration)
    end
    if finite(row.max) and row.max > 0 then return math.min(1, row.value / row.max) end
    return nil
end

-- The display's size and the background list, nil when either is missing.
local function surface()
    local dw, dh = Kit.display_size(missing)
    if not dw then return nil end
    local ok, bg = Kit.try(missing, "get_background_draw_list")
    if not ok or bg == nil then return nil end
    return bg, dw, dh
end

local function push_font(px, started)
    imgui.push_font_size(px)
    started.fonts = started.fonts + 1
end

local P, Q = { 0, 0 }, { 0, 0 } -- positions handed to the draw list: filled anew for each call (the binding copies)

local function rect(dl, x0, y0, x1, y1, color)
    P[1], P[2], Q[1], Q[2] = x0, y0, x1, y1
    dl:add_rect_filled(P, Q, color, 0, 0)
end

-- `s` cut to at most max_w px with ELLIPSIS after it (the ELLIPSIS alone when nothing more fits).
local function cut(s, max_w, px)
    local n = utf8.len(s)
    if not n then return s end
    local function at(keep) return s:sub(1, utf8.offset(s, keep + 1) - 1) .. ELLIPSIS end
    local lo, hi = 0, n - 1
    while lo < hi do
        local mid = (lo + hi + 1) // 2
        if SceneText.size(at(mid), px) <= max_w then lo = mid else hi = mid - 1 end
    end
    return at(lo)
end

-- The row's numbers at t within `room` px: whole, else without the hits, else without the resistance too, else cut.
local function fit_numbers(row, room, px, t)
    local text = BuildupBars.numbers(row, t)
    if SceneText.size(text, px) > room then text = BuildupBars.numbers(row, t, true) end
    if SceneText.size(text, px) > room then text = BuildupBars.numbers(row, t, true, true) end
    if SceneText.size(text, px) > room then text = cut(text, room, px) end
    return text
end

-- The status word within `room` px, cut when it is longer; nil when not one letter of it fits.
local function fit_word(word, room, px)
    if SceneText.size(word, px) <= room then return word end
    word = cut(word, room, px)
    if word == ELLIPSIS or SceneText.size(word, px) > room then return nil end
    return word
end

local function draw_rows(started, bar, rows, settings, t)
    if type(bar) ~= "table" or type(rows) ~= "table" then return end
    local list = {}
    for _, r in ipairs(rows) do
        if #list >= MAX_ROWS then break end
        if type(r) == "table" and (timed(r) or finite(r.value) and r.value > 0) then list[#list + 1] = r end
    end
    if #list == 0 then return end
    local v = settings.values
    local scale = v.scale
    local px = FONT_SIZE * scale * v.enemy_hp_size
    local bg, dw, dh = surface()
    if not bg then return end
    push_font(px, started)
    local left, middle = EnemyBars.boss_left(bar, dw, dh)
    local right = EnemyBars.boss_anchor(bar, dw, dh)
    local x0, x1 = math.ceil(left), math.floor(right)
    local outline, shadow = SceneText.reach(px)
    local room = x1 - x0 - outline - shadow -- the texts' room: their copies stay between the ends
    local thick = math.max(1, round(BAR_PX * scale))
    local y = round(middle + MARKS_BELOW * dh / GUI_H + TOP_GAP * scale)
    for _, r in ipairs(list) do
        local color = BuildupBars.color_of(r.name or r.id)
        local numbers = fit_numbers(r, room, px, t)
        local nw, h = SceneText.size(numbers, px)
        local word = fit_word(BuildupBars.label(r), room - nw - WORD_GAP * scale, px)
        if word then SceneText.draw(bg, x0 + outline, y, word, color, px) end
        SceneText.draw(bg, math.floor(x1 - shadow - nw), y, numbers, C.text, px)
        local by = y + round(h + TEXT_GAP * scale)
        rect(bg, x0, by, x1, by + thick, C.track)
        local filled = share(r, t)
        if filled then
            local fill = round((x1 - x0) * filled)
            if fill > 0 then rect(bg, x0, by, x0 + fill, by + thick, color) end
        end
        y = by + thick + round(ROW_GAP * scale)
    end
end

-- fn(started, ...) under one pcall; the font sizes it pushed are popped again.
local function guarded(fn, ...)
    local started = { fonts = 0 }
    local ok, err = pcall(fn, started, ...)
    for _ = 1, started.fonts do pcall(imgui.pop_font_size) end
    if ok then return nil end
    return tostring(err)
end

function BuildupBars.draw(bar, rows, settings, t)
    return guarded(draw_rows, bar, rows, settings, t)
end

return BuildupBars
