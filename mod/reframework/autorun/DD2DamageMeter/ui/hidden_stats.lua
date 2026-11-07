-- The hidden-stats panel (its model: hidden_stats_model.lua, its place: game/hidden_screens.lua): on the augments,
-- item and equipment screens, by the game's description (under it on the item screens; at the guild, above the
-- header of the equipped augments), what the hovered augment or ring gives, in numbers. The enemy plate's look
-- (ui/enemy_plate.lua):
-- a translucent black panel with a thin border and small rounded corners (its COLORS back and border, its ROUNDING
-- px × the meter's scale), the text PAD_X / PAD_Y px × the meter's scale in from its edge, the lines LINE_GAP px ×
-- the font's factor apart; the plain and ≈ lines in its "name" beige, the ?, none and legend lines in its "immune"
-- grey (a mark it does not know too, as the least sure). Each text in ui/scene_text.lua's look (outline and shadow),
-- measured there, at FONT_SIZE px × the meter's scale × the setting `hidden_stats_size` (1 while the setting is
-- missing or not a number), the font pushed as ui/enemy_bars.lua does, on imgui's background draw list (under every
-- window). No game access; the legend's text from i18n (hs_legend), the lines' as the Panel has them.
--
--   HiddenStatsUI.draw(panel, anchor, settings) -> err
--     panel: HiddenStatsModel.panel's Panel, { lines = { { text, mark = "plain" | "approx" | "guess" | "none" } },
--       legend = boolean }: its lines in their order (a line that is not a table, or whose text is not a string with
--       something other than spaces in it, is skipped), then, when legend is true, the hs_legend line.
--     anchor: Hover.anchor (game/hidden_screens.lua), { x, y, width, up } in GUI space (1920 × 1080): the left end, the
--       top of the room under the game's description (up: the bottom of the room above y) and the
--       description box's width.
--     The panel's top left lands GAP px × the meter's scale under (x, y) put on the display by EnemyBars.to_screen;
--     when anchor.up is true, its bottom lands GAP px × the meter's scale above that point instead, so that it grows
--     upwards with its lines. It is as wide as the anchor's width × H / 1080. Each line is wrapped into the panel's
--     inside (its width less PAD_X × scale on both sides): at spaces, as many words on a line as fit, but never
--     inside a number grouped as I18n.num groups it (a group of three digits after a digit: "2 000"); a word wider
--     than a line alone is broken between UTF-8 characters, never inside one (at least one character a line; a word
--     that is not valid UTF-8 is kept whole). A line's continuation lines stand an em (the font size) in, as the enemy
--     plate's. The panel never leaves the screen: when its bottom would go below the display it moves up until it is
--     at the bottom, and its top is never above 0 (a panel taller than the screen leaves at the bottom; an up panel
--     taller than the room above y reaches below y); when its right edge would pass the display's it moves left (its
--     left never below 0). All in whole pixels.
--     Nothing, not even an imgui call, without a line to show or without an anchor whose x, y and width are finite
--     numbers and width above 0. Never raises, whatever it is given: everything runs under one pcall and the font
--     size pushed is popped again; err = nil or the message of the error caught.
--   HiddenStatsUI.FONT_SIZE, HiddenStatsUI.GAP   the constants below
--   HiddenStatsUI.missing() -> { name }: the imgui calls found missing (get_display_size, get_background_draw_list,
--     add_rect: the border is four strips with square corners without it), in order, not tried again until
--     HiddenStatsUI.reset(), which also forgets the measured widths
local i18n = require("DD2DamageMeter/i18n")
local Kit = require("DD2DamageMeter/ui/kit")
local EnemyBars = require("DD2DamageMeter/ui/enemy_bars")
local EnemyPlate = require("DD2DamageMeter/ui/enemy_plate")
local SceneText = require("DD2DamageMeter/ui/scene_text")

local HiddenStatsUI = {}

local GUI_H = 1080                         -- the GUI space's height: a GUI unit of size is dh / GUI_H px
local FONT_SIZE = 14                       -- px × the meter's scale × hidden_stats_size (the enemy plate's)
local GAP = 6                              -- px × the meter's scale between the anchor and the panel's top
local PAD_X, PAD_Y = EnemyPlate.PAD_X, EnemyPlate.PAD_Y -- px × the meter's scale between the edge and the text
local LINE_GAP = EnemyPlate.LINE_GAP       -- px × the font's factor between two lines
local ROUNDING = EnemyPlate.ROUNDING       -- px × the meter's scale: the panel's corners
local BORDER = 1                           -- px: the border's width
HiddenStatsUI.FONT_SIZE, HiddenStatsUI.GAP = FONT_SIZE, GAP

local C = EnemyPlate.COLORS
-- A line's colour by its mark; any other mark grey.
local MARK_COLOR = { plain = C.name, approx = C.name, guess = C.immune, none = C.immune }

local missing

function HiddenStatsUI.reset()
    missing = {}
    SceneText.reset()
end
HiddenStatsUI.reset()

function HiddenStatsUI.missing()
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

-- The Panel's lines to draw, { { text, color } } with the legend last when it has one; nil when none is left.
local function lines_of(panel)
    if type(panel) ~= "table" or type(panel.lines) ~= "table" then return nil end
    local out = {}
    for _, line in ipairs(panel.lines) do
        if type(line) == "table" and type(line.text) == "string" and line.text:find("%S") then
            out[#out + 1] = { line.text, MARK_COLOR[line.mark] or C.immune }
        end
    end
    if #out == 0 then return nil end
    if panel.legend == true then out[#out + 1] = { i18n.t("hs_legend"), C.immune } end
    return out
end

local function placed(anchor)
    return type(anchor) == "table" and finite(anchor.x) and finite(anchor.y) and finite(anchor.width)
        and anchor.width > 0
end

-- The longest head of `word` (at least its first character) that is at most `avail` px wide, and the rest; nil when
-- the word is not valid UTF-8 or is one character.
local function split(word, avail, measure)
    local n = utf8.len(word)
    if not n or n < 2 then return nil end
    local function head(keep) return word:sub(1, utf8.offset(word, keep + 1) - 1) end
    local lo, hi = 1, n - 1
    while lo < hi do
        local mid = (lo + hi + 1) // 2
        if measure(head(mid)) <= avail then lo = mid else hi = mid - 1 end
    end
    local h = head(lo)
    return h, word:sub(#h + 1)
end

-- The words of `text`, its runs of non-spaces; a number's groups of three digits after a digit ("2 000", as I18n.num
-- writes it) stay with it as one word.
local function words_of(text)
    local list = {}
    for word in text:gmatch("%S+") do
        local last = list[#list]
        if last and last:find("%d$") and word:find("^%d%d%d%f[%D]") then
            list[#list] = last .. " " .. word
        else
            list[#list + 1] = word
        end
    end
    return list
end

-- `text` in lines at most `width` px wide, the continuations `em` px less (they stand an em in): at spaces, as many
-- words as fit; a word too wide for a line alone broken between characters. measure(s) -> px.
local function wrap(text, width, em, measure)
    local out, line = {}, nil
    local function avail() return #out == 0 and width or width - em end
    for _, word in ipairs(words_of(text)) do
        if line then
            local try = line .. " " .. word
            if measure(try) <= avail() then
                line = try
            else
                out[#out + 1] = line
                line = nil
            end
        end
        if not line then
            while measure(word) > avail() do
                local h, rest = split(word, avail(), measure)
                if not h then break end
                out[#out + 1] = h
                word = rest
            end
            line = word
        end
    end
    if line then out[#out + 1] = line end
    return out
end

-- The display's size and the background list, nil when either is missing.
local function surface()
    local dw, dh = Kit.display_size(missing)
    if not dw then return nil end
    local ok, bg = Kit.try(missing, "get_background_draw_list")
    if not ok or bg == nil then return nil end
    return bg, dw, dh
end

local P, Q = { 0, 0 }, { 0, 0 } -- positions handed to the draw list: filled anew for each call (the binding copies)

local function rect(dl, x0, y0, x1, y1, color, rounding)
    P[1], P[2], Q[1], Q[2] = x0, y0, x1, y1
    dl:add_rect_filled(P, Q, color, rounding or 0, 0)
end

local function outline(dl, x0, y0, x1, y1, color, rounding)
    P[1], P[2], Q[1], Q[2] = x0, y0, x1, y1
    dl:add_rect(P, Q, color, rounding, 0, BORDER)
end

-- The border: an outline with the panel's rounding; four strips with square corners when add_rect is missing (it
-- is not tried again until reset).
local function border(dl, x0, y0, x1, y1, rounding)
    if not missing.add_rect then
        if pcall(outline, dl, x0, y0, x1, y1, C.border, rounding) then return end
        missing.add_rect = true
    end
    local b = BORDER
    rect(dl, x0, y0, x1, y0 + b, C.border)
    rect(dl, x0, y1 - b, x1, y1, C.border)
    rect(dl, x0, y0 + b, x0 + b, y1 - b, C.border)
    rect(dl, x1 - b, y0 + b, x1, y1 - b, C.border)
end

-- The top left of a w × h panel under the anchor (above it, when the anchor is up) on a dw × dh display, on screen.
local function place(anchor, w, h, dw, dh, scale)
    local sx, sy = EnemyBars.to_screen(anchor.x, anchor.y, dw, dh)
    local x, y = round(sx), nil
    if anchor.up == true then y = round(sy - GAP * scale - h) else y = round(sy + GAP * scale) end
    if x + w > dw then x = round(dw - w) end
    if y + h > dh then y = round(dh - h) end
    return math.max(0, x), math.max(0, y)
end

local function draw_panel(started, panel, anchor, settings)
    local lines = lines_of(panel)
    if not lines or not placed(anchor) then return end
    local v = settings.values
    local scale = v.scale
    local size = v.hidden_stats_size
    if not finite(size) then size = 1 end
    local px = FONT_SIZE * scale * size
    local bg, dw, dh = surface()
    if not bg then return end
    imgui.push_font_size(px)
    started.fonts = started.fonts + 1
    local pad_x, pad_y = PAD_X * scale, PAD_Y * scale
    local w = round(anchor.width * dh / GUI_H)
    local function measure(text) return (SceneText.size(text, px)) end
    -- the lines wrapped: { text, color, continued }, and the tallest one's height
    local rows, line_h = {}, 0
    for _, line in ipairs(lines) do
        for i, text in ipairs(wrap(line[1], w - 2 * pad_x, px, measure)) do
            rows[#rows + 1] = { text, line[2], i > 1 }
            local _, th = SceneText.size(text, px)
            line_h = math.max(line_h, th)
        end
    end
    local gap = LINE_GAP * px / FONT_SIZE
    local h = round(#rows * line_h + (#rows - 1) * gap + 2 * pad_y)
    local x0, y0 = place(anchor, w, h, dw, dh, scale)
    local x1, y1 = x0 + w, y0 + h
    local rounding = ROUNDING * scale
    rect(bg, x0, y0, x1, y1, C.back, rounding)
    border(bg, x0, y0, x1, y1, rounding)
    local left, y = x0 + pad_x, y0 + pad_y
    for _, row in ipairs(rows) do
        SceneText.draw(bg, round(left + (row[3] and px or 0)), round(y), row[1], row[2], px)
        y = y + line_h + gap
    end
end

function HiddenStatsUI.draw(panel, anchor, settings)
    local started = { fonts = 0 }
    local ok, err = pcall(draw_panel, started, panel, anchor, settings)
    for _ = 1, started.fonts do pcall(imgui.pop_font_size) end
    if ok then return nil end
    return tostring(err)
end

return HiddenStatsUI
