-- The enemy HP numbers by the game's own HP bars (game/gauges.lua finds the bars, the caller adds each one's HP):
-- over a head, for each bar its HP as the setting `enemy_hp_numbers` asks, above the bar, the text's right edge at the
-- bar's right edge and its bottom TEXT_GAP px × the meter's scale above the bar's top, at FONT_SIZE px × the meter's
-- scale × the setting `enemy_hp_size`; at the boss bar at the top of the screen, the boss's HP as `boss_hp_numbers`
-- asks, right of the bar, the text's left edge BOSS_GAP px × the meter's scale after the bar's right end and its
-- middle on the bar's, at BOSS_FONT_SIZE px × the meter's scale × `enemy_hp_size`. On imgui's background draw list
-- (under every window), in one fixed look, the one of the pawns' names over their heads, whatever the meter's look
-- settings (ui/scene_text.lua), in their beige. No game access and no texts of its own: the numbers come from i18n.
--
--   EnemyBars.text(format, hp, full) -> text | nil   the numbers of one bar: "current" «12 340», "current_max"
--     «12 340 / 18 000», "percent" «69%», "current_percent" «12 340 · 69%», "all" «12 340 / 18 000 · 69%»;
--     nil for "off", another format, an HP that is not a number or a full HP not above 0
--   EnemyBars.to_screen(x, y, dw, dh) -> x, y   a point of the bars' GUI space (1920 × 1080) on a dw × dh display
--   EnemyBars.anchor(x, y, dw, dh) -> right, top   on screen, the right edge and the top of the bar centred at
--     (x, y) in GUI space
--   EnemyBars.boss_anchor(bar, dw, dh) -> right, middle   on screen, the boss bar's right end and its middle: from
--     bar = { x, y, width } as game/gauges.lua gives it (its left end and middle in GUI space, its width in its own
--     units); when they are not all finite numbers, where the game has the bar (BOSS_RIGHT, BOSS_MIDDLE)
--   EnemyBars.boss_left(bar, dw, dh) -> left, middle   the same for its left end (the enemy plate's anchor,
--     ui/enemy_plate.lua): BOSS_LEFT, BOSS_MIDDLE when the bar cannot be read
--   EnemyBars.draw(bars, settings) -> err   bars = { { x, y (the bar's centre in GUI space), hp, full } } (an entry
--     that is not such a table is skipped). Nothing, not even an imgui call, when no bar has a text.
--   EnemyBars.draw_boss(bar, settings) -> err   bar = { x, y, width, hp, full } (see boss_anchor), or nil for none.
--     Nothing, not even an imgui call, when it has no text.
--     Both never raise, whatever they are given: everything runs under one pcall and a font size pushed is popped
--     again; err = nil or the message of the error caught
--   EnemyBars.COLORS = { text, shadow, outline }   the look's ImU32 colours
--   EnemyBars.BAR_HALF_WIDTH, EnemyBars.BAR_TOP, EnemyBars.TEXT_GAP, EnemyBars.FONT_SIZE, EnemyBars.BOSS_LEFT,
--     EnemyBars.BOSS_RIGHT, EnemyBars.BOSS_MIDDLE   the constants below (the gap and the size also the player's
--     numbers', ui/player_numbers.lua)
--   EnemyBars.missing() -> { name }: the imgui calls found missing (get_display_size, get_background_draw_list), in
--     order, not tried again until EnemyBars.reset(), which also forgets the measured widths
local i18n = require("DD2DamageMeter/i18n")
local Kit = require("DD2DamageMeter/ui/kit")
local SceneText = require("DD2DamageMeter/ui/scene_text")

local EnemyBars = {}

-- The bars' GUI space (their view's ScreenSize); a point in it lands on the display at x × W / 1920, y × H / 1080.
local GUI_W, GUI_H = 1920, 1080
-- Half the bar's width, in GUI units scaled like a height (× H / 1080), not like the positions' x (× W / 1920): on a
-- wider display than 16:9 the game spreads the bars' positions over the width, but its HUD art keeps its shape,
-- scaled by the height (the numbers' right edge sat on the bar's right end on a 3440 × 1440 screenshot). The bar's HP
-- panel starts 62 units left of its centre. To move the right edge: P × 1080 / H, P being the px from the bar's
-- centre to its right end on a screenshot and H the display's height.
local BAR_HALF_WIDTH = 62
local BAR_TOP = 5          -- the bar's top above its centre, GUI units × H / 1080 (the HP panel's local y, -5)
local TEXT_GAP = 3         -- px × the meter's scale between the text's bottom and the bar's top
local FONT_SIZE = 15       -- px × the meter's scale × enemy_hp_size (the pawns' names are about this size)
-- The boss bar. Its panel All shrinks its elements' x by (16/9) / (W/H) and centres them on the display, so a width
-- in it lands on screen × H / 1080, like the overhead bars' art. Where the probes saw its base (s9g_Base: local
-- (564, 106), 776 × 7 units), used only when the base cannot be read: its left end BOSS_LEFT units left of the
-- display's centre (564 - 960), its right end BOSS_RIGHT units right of it (564 + 776 - 960), its middle BOSS_MIDDLE
-- units down from the top (106 + 7 / 2), all × H / 1080.
local BOSS_LEFT = -396
local BOSS_RIGHT = 380
local BOSS_MIDDLE = 109.5
local BOSS_GAP = 10        -- px × the meter's scale between the bar's right end and the text
local BOSS_FONT_SIZE = 18  -- px × the meter's scale × enemy_hp_size: a little bigger than over heads
-- The pawns' names' beige, measured on a screenshot of them.
local TEXT_RGB = 0xEADBB2
EnemyBars.BAR_HALF_WIDTH, EnemyBars.BAR_TOP = BAR_HALF_WIDTH, BAR_TOP
EnemyBars.TEXT_GAP, EnemyBars.FONT_SIZE = TEXT_GAP, FONT_SIZE
EnemyBars.BOSS_LEFT, EnemyBars.BOSS_RIGHT, EnemyBars.BOSS_MIDDLE = BOSS_LEFT, BOSS_RIGHT, BOSS_MIDDLE

-- ImU32 colours are 0xAABBGGRR; `abgr` takes the usual 0xRRGGBB and an alpha of 0..255.
local function abgr(rgb, alpha)
    local r, g, b = (rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF
    return (alpha << 24) | (b << 16) | (g << 8) | r
end

EnemyBars.COLORS = { text = abgr(TEXT_RGB, 255), shadow = SceneText.COLORS.shadow,
    outline = SceneText.COLORS.outline }
local C = EnemyBars.COLORS

local SEPARATOR = " · "

local missing

function EnemyBars.reset()
    missing = {}
    SceneText.reset()
end
EnemyBars.reset()

function EnemyBars.missing()
    local list = {}
    for name in pairs(missing) do list[#list + 1] = name end
    table.sort(list)
    return list
end

local function finite(x)
    return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local FORMATS = {
    current = function(cur) return cur end,
    current_max = function(cur, max) return cur .. " / " .. max end,
    percent = function(_, _, pct) return pct end,
    current_percent = function(cur, _, pct) return cur .. SEPARATOR .. pct end,
    all = function(cur, max, pct) return cur .. " / " .. max .. SEPARATOR .. pct end,
}

function EnemyBars.text(format, hp, full)
    local make = FORMATS[format]
    if make == nil or not (finite(hp) and finite(full)) or full <= 0 then return nil end
    hp = math.max(0, hp)
    return make(i18n.num(hp), i18n.num(full), i18n.pct(math.min(1, hp / full)))
end

function EnemyBars.to_screen(x, y, dw, dh)
    return x * dw / GUI_W, y * dh / GUI_H
end

function EnemyBars.anchor(x, y, dw, dh)
    local sx, sy = EnemyBars.to_screen(x, y, dw, dh)
    local unit = dh / GUI_H
    return sx + BAR_HALF_WIDTH * unit, sy - BAR_TOP * unit
end

function EnemyBars.boss_anchor(bar, dw, dh)
    local unit = dh / GUI_H
    if finite(bar.x) and finite(bar.y) and finite(bar.width) then
        local left, middle = EnemyBars.to_screen(bar.x, bar.y, dw, dh)
        return left + bar.width * unit, middle
    end
    return dw / 2 + BOSS_RIGHT * unit, BOSS_MIDDLE * unit
end

function EnemyBars.boss_left(bar, dw, dh)
    if finite(bar.x) and finite(bar.y) and finite(bar.width) then
        return EnemyBars.to_screen(bar.x, bar.y, dw, dh)
    end
    local unit = dh / GUI_H
    return dw / 2 + BOSS_LEFT * unit, BOSS_MIDDLE * unit
end

local function round(v)
    return math.floor(v + 0.5)
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

local function draw_all(started, bars, settings)
    local v = settings.values
    local list = {}
    for _, bar in ipairs(bars) do
        if type(bar) == "table" and finite(bar.x) and finite(bar.y) then
            local text = EnemyBars.text(v.enemy_hp_numbers, bar.hp, bar.full)
            if text then list[#list + 1] = { text, bar } end
        end
    end
    if #list == 0 then return end
    local scale = v.scale
    local px = FONT_SIZE * scale * v.enemy_hp_size
    local bg, dw, dh = surface()
    if not bg then return end
    push_font(px, started)
    for _, item in ipairs(list) do
        local text, bar = item[1], item[2]
        local w, h = SceneText.size(text, px)
        local right, top = EnemyBars.anchor(bar.x, bar.y, dw, dh)
        SceneText.draw(bg, round(right - w), round(top - TEXT_GAP * scale - h), text, C.text, px)
    end
end

local function draw_boss(started, bar, settings)
    if type(bar) ~= "table" then return end
    local v = settings.values
    local text = EnemyBars.text(v.boss_hp_numbers, bar.hp, bar.full)
    if text == nil then return end
    local scale = v.scale
    local px = BOSS_FONT_SIZE * scale * v.enemy_hp_size
    local bg, dw, dh = surface()
    if not bg then return end
    push_font(px, started)
    local _, h = SceneText.size(text, px)
    local right, middle = EnemyBars.boss_anchor(bar, dw, dh)
    SceneText.draw(bg, round(right + BOSS_GAP * scale), round(middle - h / 2), text, C.text, px)
end

-- fn(started, ...) under one pcall; the font sizes it pushed are popped again.
local function guarded(fn, ...)
    local started = { fonts = 0 }
    local ok, err = pcall(fn, started, ...)
    for _ = 1, started.fonts do pcall(imgui.pop_font_size) end
    if ok then return nil end
    return tostring(err)
end

function EnemyBars.draw(bars, settings)
    return guarded(draw_all, bars, settings)
end

function EnemyBars.draw_boss(bar, settings)
    return guarded(draw_boss, bar, settings)
end

return EnemyBars
