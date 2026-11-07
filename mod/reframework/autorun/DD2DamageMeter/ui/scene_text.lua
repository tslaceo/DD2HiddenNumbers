-- Text straight over the scene in one fixed look, the one of the pawns' names over their heads: the text over black
-- copies of it one step around it (the outline), over a translucent black copy a little down and to the right (the
-- shadow). The steps are those of 15 px text (shadow 2 px, outline 1 px) × (font size / 15), at least 1 px. Drawn
-- by the enemy HP numbers (ui/enemy_bars.lua) and the damage numbers (ui/damage_numbers.lua); no game access, no
-- texts of its own.
--
--   SceneText.draw(dl, x, y, text, color, px, alpha)   the shadow, the outline copies and the text in `color`, its top
--     left at (x, y), on the draw list dl; px is the font size the caller pushed; alpha (0..1, default 1) fades the
--     three alike
--   SceneText.size(text, px) -> w, h   the size of `text` at the font size px (pushed by the caller), measured once
--     per text and size (at most MAX_SIZES remembered, then measured afresh)
--   SceneText.reach(px) -> outline, shadow   how far the copies reach past the text at the font size px, in px: the
--     outline on every side, the shadow right and down (never less than the outline)
--   SceneText.faded(color, alpha) -> ImU32   color with its own alpha × alpha (0..1)
--   SceneText.COLORS = { shadow, outline }   ImU32
--   SceneText.reset()   forgets the sizes measured
local SceneText = {}

local BASE_PX = 15
local SHADOW_OFFSET, OUTLINE_OFFSET = 2, 1
local SHADOW_ALPHA = 171   -- 67 % of 255
local MAX_SIZES = 256

SceneText.COLORS = { shadow = SHADOW_ALPHA << 24, outline = 0xFF000000 }
local C = SceneText.COLORS

-- The outline's eight directions.
local RING = { { -1, -1 }, { 0, -1 }, { 1, -1 }, { -1, 0 }, { 1, 0 }, { -1, 1 }, { 0, 1 }, { 1, 1 } }

local sizes, n_sizes -- px -> text -> { w, h }

function SceneText.reset()
    sizes, n_sizes = {}, 0
end
SceneText.reset()

local function round(v)
    return math.floor(v + 0.5)
end

function SceneText.faded(color, alpha)
    if alpha == nil or alpha >= 1 then return color end
    local a = round(((color >> 24) & 0xFF) * math.max(0, alpha))
    return (color & 0x00FFFFFF) | (a << 24)
end

function SceneText.reach(px)
    local f = px / BASE_PX
    return math.max(1, round(OUTLINE_OFFSET * f)), math.max(1, round(SHADOW_OFFSET * f))
end

function SceneText.size(text, px)
    if n_sizes >= MAX_SIZES then SceneText.reset() end
    local at = sizes[px]
    if at == nil then
        at = {}
        sizes[px] = at
    end
    local s = at[text]
    if s == nil then
        local d = imgui.calc_text_size(text)
        s = { d.x, d.y }
        at[text] = s
        n_sizes = n_sizes + 1
    end
    return s[1], s[2]
end

local P = { 0, 0 } -- positions handed to the draw list: filled anew for each call (the binding copies them)

function SceneText.draw(dl, x, y, text, color, px, alpha)
    local o, s = SceneText.reach(px)
    P[1], P[2] = x + s, y + s
    dl:add_text(P, SceneText.faded(C.shadow, alpha), text)
    local outline = SceneText.faded(C.outline, alpha)
    for _, d in ipairs(RING) do
        P[1], P[2] = x + d[1] * o, y + d[2] * o
        dl:add_text(P, outline, text)
    end
    P[1], P[2] = x, y
    dl:add_text(P, SceneText.faded(color, alpha), text)
end

return SceneText
