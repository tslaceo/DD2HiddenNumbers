-- The player's own HP and stamina numbers by the game's HUD bars at the bottom of the screen (the
-- bars from gauges.player, game/gauges.lua: each bar's full-length background, not its fill; the numbers from
-- game/player_vitals.lua): above the HP bar, «3 031 / 3 031 (3 100)», the text's right edge at the bar's right end
-- and its bottom TEXT_GAP px × the meter's scale above the bar's top; under the stamina bar the same from the
-- stamina, the text's top TEXT_GAP px × the scale below the bar's bottom. A bar's left end and top land on the display
-- as EnemyBars.to_screen puts them, its width and height × H / 1080 (as the boss bar's, EnemyBars.boss_anchor), so
-- the texts stay put while the HP and stamina go down. In the look of the enemy HP numbers (ui/enemy_bars.lua: its
-- beige, ui/scene_text.lua's outline and shadow), at its FONT_SIZE px × the meter's scale × `enemy_hp_size`, on
-- imgui's background draw list (under every window). No game access and no texts of its own: the numbers come from
-- i18n.
--
--   PlayerNumbers.text(now, max, full) -> text | nil   "now / max", then " (full)" while max and full differ once
--     rounded (i18n.num gives them apart): «3 031 / 3 031 (3 100)», «3 100 / 3 100», «-120 / 1 300» (the sign as
--     i18n.num shows it); nil when one of the three is not a finite number
--   PlayerNumbers.draw(bars, vitals, settings) -> err   bars = gauges.player's answer ({ hp, sp }, each bar's
--     { x, y, width, height } or nil), vitals = PlayerVitals.read's answer. A bar whose place is not all finite
--     numbers, or whose numbers give no text, gets none; nothing, not even an imgui call, when neither has. Never
--     raises, whatever it is given: everything runs under one pcall and the font size pushed is popped again;
--     err = nil or the message of the error caught
--   PlayerNumbers.missing() -> { name }: the imgui calls found missing (get_display_size, get_background_draw_list), in
--     order, not tried again until PlayerNumbers.reset(), which also forgets the measured widths
local i18n = require("DD2DamageMeter/i18n")
local Kit = require("DD2DamageMeter/ui/kit")
local EnemyBars = require("DD2DamageMeter/ui/enemy_bars")
local SceneText = require("DD2DamageMeter/ui/scene_text")

local PlayerNumbers = {}

local GUI_H = 1080         -- the bars' GUI space's height: a GUI unit of size is dh / GUI_H px
local TEXT_GAP = EnemyBars.TEXT_GAP   -- px × the meter's scale between a text and its bar
local FONT_SIZE = EnemyBars.FONT_SIZE -- px × the meter's scale × enemy_hp_size
local C = EnemyBars.COLORS

local missing

function PlayerNumbers.reset()
    missing = {}
    SceneText.reset()
end
PlayerNumbers.reset()

function PlayerNumbers.missing()
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

function PlayerNumbers.text(now, max, full)
    if not (finite(now) and finite(max) and finite(full)) then return nil end
    local text, whole = i18n.num(now) .. " / " .. i18n.num(max), i18n.num(full)
    if whole ~= i18n.num(max) then text = text .. " (" .. whole .. ")" end
    return text
end

-- A bar as gauges.player gives it, with its place all finite numbers.
local function placed(bar)
    return type(bar) == "table" and finite(bar.x) and finite(bar.y) and finite(bar.width) and finite(bar.height)
end

-- The bar's text from `now`, `max` and `full`, nil when the bar is not placed or the numbers give none.
local function text_of(bar, now, max, full)
    if not placed(bar) then return nil end
    return PlayerNumbers.text(now, max, full)
end

-- On a dw × dh display: the bar's right end, its top and its bottom.
local function ends(bar, dw, dh)
    local left, top = EnemyBars.to_screen(bar.x, bar.y, dw, dh)
    local unit = dh / GUI_H
    return left + bar.width * unit, top, top + bar.height * unit
end

-- The display's size and the background list, nil when either is missing.
local function surface()
    local dw, dh = Kit.display_size(missing)
    if not dw then return nil end
    local ok, bg = Kit.try(missing, "get_background_draw_list")
    if not ok or bg == nil then return nil end
    return bg, dw, dh
end

local function draw_texts(started, bars, vitals, settings)
    if type(bars) ~= "table" or type(vitals) ~= "table" then return end
    local hp = text_of(bars.hp, vitals.hp, vitals.hp_max, vitals.hp_full)
    local sp = text_of(bars.sp, vitals.sp, vitals.sp_max, vitals.sp_full)
    if hp == nil and sp == nil then return end
    local v = settings.values
    local scale = v.scale
    local px = FONT_SIZE * scale * v.enemy_hp_size
    local bg, dw, dh = surface()
    if not bg then return end
    imgui.push_font_size(px)
    started.fonts = started.fonts + 1
    local gap = TEXT_GAP * scale
    if hp then
        local w, h = SceneText.size(hp, px)
        local right, top = ends(bars.hp, dw, dh)
        SceneText.draw(bg, round(right - w), round(top - gap - h), hp, C.text, px)
    end
    if sp then
        local w = SceneText.size(sp, px)
        local right, _, bottom = ends(bars.sp, dw, dh)
        SceneText.draw(bg, round(right - w), round(bottom + gap), sp, C.text, px)
    end
end

function PlayerNumbers.draw(bars, vitals, settings)
    local started = { fonts = 0 }
    local ok, err = pcall(draw_texts, started, bars, vitals, settings)
    for _ = 1, started.fonts do pcall(imgui.pop_font_size) end
    if ok then return nil end
    return tostring(err)
end

return PlayerNumbers
