-- The damage numbers (their model: damage_numbers.lua) on imgui's background draw list, each anchored to its hit's
-- point in the world: projected anew every frame (draw.world_to_screen), and not drawn while that point is off the
-- display. Two looks, the setting `damage_numbers_style`:
--   "rise"    the number in its attacker's colour in the pawn names' look (ui/scene_text.lua), centred on the point,
--             rising RISE_PX over RISE_LIFE s (fast, then slower) and fading out over the last FADE s; a crit CRIT ×
--             bigger with «!» after it, popping from POP × its size to its size over POP_S s; a DoT tick DOT × smaller
--   "plates"  a plate in the attacker's colour at PLATE_ALPHA with a 1 px dark border and light text, standing on the
--             point for PLATE_LIFE s and fading out over the last FADE s; a crit's plate CRIT × bigger with a 2 px
--             gold border, a DoT tick's DOT × smaller. A plate that would overlap a plate drawn before it (an older
--             one) moves to the first free one of SPOTS around the point, else stays; that offset, in screen px from
--             the point, is kept for its life
--   in both a weak-point number has a small diamond before it: in its colour (rise), in the text's (plates).
-- Sizes in px are × the meter's scale × `damage_numbers_size`; the colours are the meter's (Kit.actor_color). It keeps
-- on each number what it worked out for it: its colour, its text, its plate's offset. No game access but the
-- projection, no texts of its own (the number from i18n).
--
--   DamageNumbersUI.draw(list, settings, t) -> err   prunes the list to the style's life, then draws it, oldest first
--     (the newest on top). Nothing, not even an imgui call, for an empty list. Never raises: everything runs under
--     pcall and the font sizes pushed are popped again; err = nil or the message of the first error caught (a
--     projection that raises costs its number this frame, the others are drawn)
--   DamageNumbersUI.life(style) -> s;  .alpha(age, life) -> 0..1;  .rise(age, unit) -> px;  .pop(age) -> factor
--   DamageNumbersUI.place(box, taken, gap) -> dx, dy   box = { x0, y0, x1, y1 }, taken = { box... } (taken.n of them
--     when set): (0, 0) when box overlaps none of them, else the first offset of SPOTS (in box widths and heights,
--     plus gap) where it overlaps none, else (0, 0)
--   DamageNumbersUI.GOLD   the ImU32 of a crit plate's border
--   DamageNumbersUI.missing() -> { name }: the calls found missing (world_to_screen, get_display_size,
--     get_background_draw_list, add_quad_filled: the diamond is a square without it), in order, not tried again
--     until DamageNumbersUI.reset()
local i18n = require("DD2DamageMeter/i18n")
local Kit = require("DD2DamageMeter/ui/kit")
local SceneText = require("DD2DamageMeter/ui/scene_text")

local DamageNumbersUI = {}

local RISE_FONT, RISE_LIFE, RISE_PX = 18, 1.0, 40 -- px, s, px over the life
local PLATE_FONT, PLATE_LIFE = 14, 1.5            -- px, s
local PLATE_PAD_X, PLATE_PAD_Y = 5, 2             -- px × the plate's size factor around its text
local PLATE_ALPHA = 0.8
local PLATE_GAP = 2                               -- px between a moved plate and the one it moved from
local FADE = 0.4                                  -- s: the end of a life, fading out (the rise's last 40 %)
local CRIT, DOT = 1.4, 0.8                        -- size factors
local POP, POP_S = 1.35, 0.25
local DIAMOND_R, DIAMOND_GAP = 0.28, 0.22         -- × the font size: half the diamond's height, its gap to the number
local GOLD_RGB = 0xE6B84C
local BORDER, CRIT_BORDER = 1, 2                  -- px
local SHOWN = 0.5                                 -- the least amount i18n.num does not show as 0
-- Where a plate goes when it would overlap: up one plate height, down, left, right, the diagonals, two up, two down.
local SPOTS = { { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 }, { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 }, { 0, -2 },
    { 0, 2 } }

-- ImU32 colours are 0xAABBGGRR; `abgr` takes the usual 0xRRGGBB and an alpha of 0..255.
local function abgr(rgb, alpha)
    local r, g, b = (rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF
    return (alpha << 24) | (b << 16) | (g << 8) | r
end

local C = Kit.COLORS
local GOLD = abgr(GOLD_RGB, 255)
DamageNumbersUI.GOLD = GOLD

local missing
local taken = { n = 0 } -- the boxes of the plates drawn this frame (reused)

function DamageNumbersUI.reset()
    missing = {}
end
DamageNumbersUI.reset()

function DamageNumbersUI.missing()
    local list = {}
    for name in pairs(missing) do list[#list + 1] = name end
    table.sort(list)
    return list
end

local function round(v)
    return math.floor(v + 0.5)
end

local function finite(x)
    return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

function DamageNumbersUI.life(style)
    return style == "plates" and PLATE_LIFE or RISE_LIFE
end

function DamageNumbersUI.alpha(age, life)
    if age >= life then return 0 end
    return math.min(1, (life - age) / FADE)
end

function DamageNumbersUI.rise(age, unit)
    local p = math.max(0, math.min(1, age / RISE_LIFE))
    return RISE_PX * unit * (1 - (1 - p) ^ 2)
end

function DamageNumbersUI.pop(age)
    local p = math.max(0, age) / POP_S
    if p >= 1 then return 1 end
    return 1 + (POP - 1) * (1 - p) ^ 2
end

local function overlaps(a, x0, y0, x1, y1)
    return a[1] < x1 and x0 < a[3] and a[2] < y1 and y0 < a[4]
end

local function free(box, dx, dy, list)
    local x0, y0, x1, y1 = box[1] + dx, box[2] + dy, box[3] + dx, box[4] + dy
    for i = 1, list.n or #list do
        if overlaps(list[i], x0, y0, x1, y1) then return false end
    end
    return true
end

function DamageNumbersUI.place(box, list, gap)
    if free(box, 0, 0, list) then return 0, 0 end
    local w, h = box[3] - box[1] + gap, box[4] - box[2] + gap
    for _, s in ipairs(SPOTS) do
        local dx, dy = s[1] * w, s[2] * h
        if free(box, dx, dy, list) then return dx, dy end
    end
    return 0, 0
end

-- The number's colour and text, made again only when what they show changed.
local function color_of(n)
    if n.color == nil then n.color = Kit.actor_color(n.kind, n.job, n.shade) end
    return n.color
end

local function text_of(n, mark)
    if n.text_amount ~= n.amount or n.text_mark ~= mark then
        n.text, n.text_amount, n.text_mark = i18n.num(n.amount) .. (mark and "!" or ""), n.amount, mark
    end
    return n.text
end

local P, Q, R, S = { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 } -- positions handed to the draw list (the binding copies)

local function rect(dl, x0, y0, x1, y1, color)
    P[1], P[2], Q[1], Q[2] = x0, y0, x1, y1
    dl:add_rect_filled(P, Q, color)
end

-- A diamond centred at (cx, cy), r from its centre to each corner; a square when the quads are missing.
local function diamond(dl, cx, cy, r, color)
    if not missing.add_quad_filled then
        P[1], P[2], Q[1], Q[2], R[1], R[2], S[1], S[2] = cx, cy - r, cx + r, cy, cx, cy + r, cx - r, cy
        if pcall(dl.add_quad_filled, dl, P, Q, R, S, color) then return end
        missing.add_quad_filled = true
    end
    local h = r * 0.75
    rect(dl, cx - h, cy - h, cx + h, cy + h, color)
end

local function size_factor(n)
    if n.crit then return CRIT end
    if n.dot then return DOT end
    return 1
end

local function push(px, started)
    imgui.push_font_size(px)
    started.fonts = started.fonts + 1
end

local function pop(started)
    imgui.pop_font_size()
    started.fonts = started.fonts - 1
end

local function draw_rise(dl, n, x, y, t, unit, started)
    local age = math.max(0, t - n.t)
    local alpha = DamageNumbersUI.alpha(age, RISE_LIFE)
    if alpha <= 0 then return end
    local px = RISE_FONT * unit * size_factor(n)
    if n.crit then px = px * DamageNumbersUI.pop(t - (n.crit_t or n.t)) end
    local text = text_of(n, n.crit)
    push(px, started)
    local w, h = SceneText.size(text, px)
    local r = n.weak and DIAMOND_R * px or 0
    local lead = n.weak and 2 * r + DIAMOND_GAP * px or 0
    local left = round(x - (lead + w) / 2)
    local top = round(y - DamageNumbersUI.rise(age, unit) - h / 2)
    local color = color_of(n)
    if n.weak then
        local edge = math.max(1, round(px / RISE_FONT))
        diamond(dl, left + r, top + h / 2, r + edge, SceneText.faded(SceneText.COLORS.outline, alpha))
        diamond(dl, left + r, top + h / 2, r, SceneText.faded(color, alpha))
    end
    SceneText.draw(dl, left + round(lead), top, text, color, px, alpha)
    pop(started)
end

-- A border `b` px wide just inside the box.
local function border(dl, x0, y0, x1, y1, b, color)
    rect(dl, x0, y0, x1, y0 + b, color)
    rect(dl, x0, y1 - b, x1, y1, color)
    rect(dl, x0, y0 + b, x0 + b, y1 - b, color)
    rect(dl, x1 - b, y0 + b, x1, y1 - b, color)
end

local function draw_plate(dl, n, x, y, t, unit, started)
    local age = math.max(0, t - n.t)
    local alpha = DamageNumbersUI.alpha(age, PLATE_LIFE)
    if alpha <= 0 then return end
    local f = unit * size_factor(n)
    local px = PLATE_FONT * f
    local text = text_of(n, false)
    push(px, started)
    local w, h = SceneText.size(text, px)
    local r = n.weak and DIAMOND_R * px or 0
    local lead = n.weak and 2 * r + DIAMOND_GAP * px or 0
    local pw, ph = round(lead + w + 2 * PLATE_PAD_X * f), round(h + 2 * PLATE_PAD_Y * f)
    local x0, y0 = round(x - pw / 2), round(y - ph / 2)
    local i = taken.n + 1
    local box = taken[i] or {}
    taken[i] = box
    box[1], box[2], box[3], box[4] = x0, y0, x0 + pw, y0 + ph
    if n.ox == nil then n.ox, n.oy = DamageNumbersUI.place(box, taken, round(PLATE_GAP * unit)) end
    x0, y0 = x0 + n.ox, y0 + n.oy
    local x1, y1 = x0 + pw, y0 + ph
    box[1], box[2], box[3], box[4] = x0, y0, x1, y1
    taken.n = i
    local color = color_of(n)
    rect(dl, x0, y0, x1, y1, SceneText.faded(color, PLATE_ALPHA * alpha))
    if n.crit then
        border(dl, x0, y0, x1, y1, CRIT_BORDER, SceneText.faded(GOLD, alpha))
    else
        border(dl, x0, y0, x1, y1, BORDER, SceneText.faded(C.shadow, 0.9 * alpha))
    end
    local tx, ty = x0 + round((pw - lead - w) / 2), y0 + round((ph - h) / 2)
    local ink = SceneText.faded(C.text, alpha)
    if n.weak then diamond(dl, tx + r, y0 + ph / 2, r, ink) end
    tx = tx + round(lead)
    P[1], P[2] = tx + 1, ty + 1
    dl:add_text(P, SceneText.faded(C.shadow, 0.8 * alpha), text)
    P[1], P[2] = tx, ty
    dl:add_text(P, ink, text)
    pop(started)
end

local function project(fn, point)
    local s = fn(point)
    if s == nil then return nil end
    return s.x, s.y
end

local function world_to_screen() return draw.world_to_screen end

local function projector()
    if missing.world_to_screen then return nil end
    local ok, fn = pcall(world_to_screen)
    if ok and type(fn) == "function" then return fn end
    missing.world_to_screen = true
    return nil
end

local function draw_all(list, settings, t, started)
    local v = settings.values
    local plates = v.damage_numbers_style == "plates"
    list:prune(t, DamageNumbersUI.life(v.damage_numbers_style))
    local items = list.items
    if #items == 0 then return nil end
    local fn = projector()
    if fn == nil then return nil end
    local dw, dh = Kit.display_size(missing)
    if not dw then return nil end
    local ok, dl = Kit.try(missing, "get_background_draw_list")
    if not ok or dl == nil then return nil end
    local unit = v.scale * v.damage_numbers_size
    taken.n = 0
    local first_err
    for _, n in ipairs(items) do
        local fine, x, y = true, nil, nil
        -- an amount i18n.num shows as 0 waits for a hit to join it
        if n.amount >= SHOWN then fine, x, y = pcall(project, fn, n.point) end
        if not fine then
            first_err = first_err or tostring(x)
        elseif finite(x) and finite(y) and x >= 0 and x <= dw and y >= 0 and y <= dh then
            if plates then draw_plate(dl, n, x, y, t, unit, started) else draw_rise(dl, n, x, y, t, unit, started) end
        end
    end
    return first_err
end

function DamageNumbersUI.draw(list, settings, t)
    local started = { fonts = 0 }
    local ok, err = pcall(draw_all, list, settings, t, started)
    for _ = 1, started.fonts do pcall(imgui.pop_font_size) end
    if ok then return err end
    return tostring(err)
end

return DamageNumbersUI
