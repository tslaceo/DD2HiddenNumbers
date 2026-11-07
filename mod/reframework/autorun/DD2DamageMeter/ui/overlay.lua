-- The meter window: draws the display models (view.lua) with REFramework's imgui and reports
-- what the player did with it. No game logic and no texts of its own: every string comes from
-- the models or from i18n. The rows of the layout (the name on the left, the numbers on
-- the right, a bar for each character), in the colours of the game's own UI and in one of two
-- looks, the setting `style`:
--   frameless  no window background, like the game's control hints: light warm text with a dark
--              shadow straight over the scene; a header with a larger title and a thin bronze line
--              under it; each block on a dark band that fades out to the right, with a mark and a
--              title in the block's colour and the block's total at the right; the rows a little
--              indented, each with a thin bar on a dark track; with `halo` a soft dark halo behind it all;
--   panel      bars as tall as a row with the texts on them, on a dark warm panel with square
--              corners and thin bronze lines.
-- A party member's bar has the colour of their vocation (a second or third member of the same
-- vocation a lighter or darker shade of it); allies, Other and the damage to the party have
-- colours of their own.
--
-- A block of the live window or the summary is drawn when its model has it and its switch in the settings is on
-- (live_damage, live_taken, live_heal, summary_enemies, summary_damage, summary_heal, summary_armor); the rows of the
-- allies and of Other follow show_allies / live_other in the live window and summary_allies / summary_other in the
-- summary.
--
-- Overlay.draw(state, settings) -> actions, err
--   state   = { mode = "live"|"summary"|"hidden", live, summary, details, history_index, history_count, notice }
--             (history_index 1 = the newest fight; notice: nil or a text drawn as one dim line under the view,
--             e.g. the self-check's missing game methods)
--   actions = { select_actor = key|nil, history = -1|0|1, hide = boolean, back = boolean,
--               moved = { x = number, y = number }|nil }
--             history is the change of history_index (-1 towards the newest); back asks to leave the
--             details; moved is reported once, when a drag of the window ends.
--   err     = nil, or the message of an error caught while drawing. draw never raises:
--             whatever it had started (window, font sizes, colour) is ended again, and the
--             actions gathered up to the failure are returned.
-- Overlay.WIDTH: the width of the window's content at scale 1 (imgui's padding comes on each side; the details of a
-- character can be wider).
local i18n = require("DD2DamageMeter/i18n")

local Overlay = {}

-- ImGuiWindowFlags values of ImGui 1.92.0 (REFramework has no Lua enum for them).
local WIN_NO_TITLE_BAR = 1
local WIN_NO_RESIZE = 2
local WIN_NO_SCROLLBAR = 8
local WIN_NO_SCROLL_WITH_MOUSE = 16
local WIN_NO_COLLAPSE = 32
local WIN_ALWAYS_AUTO_RESIZE = 64
local WIN_NO_BACKGROUND = 128
local WIN_NO_SAVED_SETTINGS = 256
local WIN_NO_MOUSE_INPUTS = 512
local WIN_NO_FOCUS_ON_APPEARING = 4096
local WIN_NO_BRING_TO_FRONT_ON_FOCUS = 8192
local WIN_NO_NAV = 196608 -- NoNavInputs | NoNavFocus
local COND_ALWAYS = 1     -- ImGuiCond_Always
local COL_BORDER = 5      -- ImGuiCol_Border

-- imgui paints no background and no border: the panel is the overlay's own, with square corners.
local WINDOW_FLAGS = WIN_NO_TITLE_BAR | WIN_NO_RESIZE | WIN_NO_SCROLLBAR | WIN_NO_SCROLL_WITH_MOUSE
    | WIN_NO_COLLAPSE | WIN_ALWAYS_AUTO_RESIZE | WIN_NO_BACKGROUND | WIN_NO_SAVED_SETTINGS
    | WIN_NO_FOCUS_ON_APPEARING | WIN_NO_BRING_TO_FRONT_ON_FOCUS
-- With the REFramework menu closed the window is only a picture: the mouse and the keyboard
-- go straight to the game.
local CLICK_THROUGH_FLAGS = WIN_NO_MOUSE_INPUTS | WIN_NO_NAV

-- Sizes in pixels at scale 1.
local FONT_SIZE = 14
local WIDTH = 340
Overlay.WIDTH = WIDTH
local ROW_HEIGHT = 20       -- the panel's header and bars
local PADDING = 6
local MIN_LABEL_WIDTH = 170 -- skill name column of the details table
local HALO_MARGIN = 16      -- how far around the text the halo fades out
local HALO_LAYERS = 8
-- the frameless look's header and blocks
local HEADER_HEIGHT = 24
local TITLE_SIZE = 16       -- the header's title
local BAND_HEIGHT = 20
local BAND_SOLID = 0.65     -- the band is solid over this share of the width, then fades out
local MARK_WIDTH = 3
local INDENT = 8            -- rows and block titles start this far in
local ENEMY_INDENT = 20     -- a summary enemy's name, after its diamond
local DIAMOND = 3.5         -- half the width of an enemy's diamond
local GAP_FIRST, GAP = 2, 6 -- room above a band besides imgui's item spacing (4): 6 px under the header, 10 after a row
local FADE_STEPS = 4        -- the fade in steps, when the gradient call is missing

-- ImU32 colours are 0xAABBGGRR; `abgr` takes the usual 0xRRGGBB and an alpha of 0..255.
local function abgr(rgb, alpha)
    alpha = math.max(0, math.min(255, math.floor(alpha + 0.5)))
    local r, g, b = (rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF
    return (alpha << 24) | (b << 16) | (g << 8) | r
end

local function round(v)
    return math.floor(v + 0.5)
end

-- The game's palette: menu text, dimmer labels, bronze lines, the dark warm panel.
local TEXT_RGB, DIM_RGB, BRONZE_RGB, PANEL_RGB = 0xECE4D4, 0xD2C4A8, 0xBE965F, 0x171414
local LINE_RGB = 0x4A3A2C   -- the panel's lines between rows and its edge
local SHADOW_RGB = 0x050403 -- near-black: text shadows and outlines, the bar track and its edge
local HALO_RGB = 0x0E0B08   -- the halo and the bands
local PURPLE_RGB, LIGHT_PURPLE_RGB = 0x8D5CA6, 0xC9A9DA

local function opaque(list)
    local out = {}
    for i, rgb in ipairs(list) do out[i] = abgr(rgb, 255) end
    return out
end

Overlay.COLORS = {
    -- by app.Character.JobEnum: Fighter, Archer, Mage, Thief, Warrior, Sorcerer, Mystic Spearhand, Magick Archer,
    -- Trickster, Warfarer (a two-colour crest gives one colour)
    vocation = opaque({ 0xB84B54, 0xB88833, 0x448CA8, 0x6C9451, 0x802C30, 0x43599E, 0x994F3B, 0x547299, 0x945188,
        0x998E65 }),
    unknown = abgr(0x8A8580, 255), -- a party member whose vocation could not be read
    ally = abgr(0x8C8170, 255),
    other = abgr(0x7A7570, 255),   -- damage and healing nobody can be blamed for
    enemy = abgr(PURPLE_RGB, 255), -- the damage to the party: purple, like the game's enemy health bars
    text = abgr(TEXT_RGB, 255),
    dim = abgr(DIM_RGB, 255),
    bronze = abgr(BRONZE_RGB, 235),
    line = abgr(LINE_RGB, 255),
    shadow = abgr(SHADOW_RGB, 255), -- the colour of every shadow and outline copy (their alpha varies)
    track = abgr(SHADOW_RGB, 110),  -- frameless: the dark track of a bar
    panel_track = abgr(0xFFFFFF, 13),
    -- frameless
    band = abgr(HALO_RGB, 150),              -- the band under a block's title, fading out to the right
    even_row = abgr(HALO_RGB, 50),           -- every second row of the details
    enemy_label = abgr(LIGHT_PURPLE_RGB, 255), -- who hit whom, and the summary's enemies
    -- each block's mark and title
    block = {
        damage = { mark = abgr(BRONZE_RGB, 255), title = abgr(0xD6B27A, 255) },
        enemies = { mark = abgr(PURPLE_RGB, 255), title = abgr(LIGHT_PURPLE_RGB, 255) },
        heal = { mark = abgr(0x7F9E6A, 255), title = abgr(0xB7CB9B, 255) },
        other = { mark = abgr(0x6E5A40, 255), title = abgr(DIM_RGB, 255) },
    },
}
local C = Overlay.COLORS
local TEXT, DIM = C.text, C.dim
local EDGE = abgr(SHADOW_RGB, 200)          -- the frameless track's 1 px edge
local SHINE = abgr(0xFFFFFF, 46)            -- a faint light on the top edge of a thick bar
local HOVER = abgr(0xFFFFFF, 40)            -- panel: over the bar
local HOVER_FRAMELESS = abgr(0x3D3C36, 150) -- the warm grey of a selected row in the game's menus
local DIAMOND_EDGE = abgr(SHADOW_RGB, 230)

-- Text shadow: offset (in steps) and share of the shadow's strength of each near-black copy under a text.
local TAPS = {
    { 1, 1, 1.0 }, { 2, 2, 0.45 },
    { -1, 0, 0.5 }, { 1, 0, 0.5 }, { 0, -1, 0.5 }, { 0, 1, 0.6 },
    { -1, -1, 0.3 }, { 1, -1, 0.3 }, { -1, 1, 0.3 },
}
-- The outline of a number: the eight offsets one step around it, each as dark as OUTLINE_ALPHA.
local RING = { { -1, -1 }, { 0, -1 }, { 1, -1 }, { -1, 0 }, { 1, 0 }, { -1, 1 }, { 0, 1 }, { 1, 1 } }
local OUTLINE_ALPHA = 225

-- A colour for the n-th party member of one vocation (by party order): the colour itself, lighter, darker, lighter
-- still (positive: towards white, negative: towards black).
local SHADES = { 0, 0.3, -0.3, 0.5 }

function Overlay.shade(color, rank)
    local t = SHADES[((math.tointeger(rank) or 1) - 1) % #SHADES + 1]
    if t == 0 then return color end
    local out = color & 0xFF000000
    for shift = 0, 16, 8 do
        local v = (color >> shift) & 0xFF
        v = t > 0 and v + (255 - v) * t or v * (1 + t)
        out = out | (round(v) << shift)
    end
    return out
end

local PARTY = { player = true, pawn = true }

-- The bar colour of a character row (or of the details' character): a party member's vocation in the shade the
-- model gives it (`row.shade`, which member of that vocation it is in the fight).
local function row_color(row)
    if PARTY[row.kind] then
        return Overlay.shade(C.vocation[row.job] or C.unknown, row.shade)
    end
    if row.kind == "ally" then return C.ally end
    if row.kind == "other" then return C.other end
    return C.enemy
end

-- What the controls of the header do.
local CLICK = {
    history_prev = function(a) a.history = -1 end,
    history_next = function(a) a.history = 1 end,
    hide = function(a) a.hide = true end,
    back = function(a) a.back = true end,
}
local HIDE = { id = "hide", glyph = "×" }
local BACK = { id = "back", glyph = "‹" }

-- Where the window is (as last agreed with the settings) and whether a drag is under way; the shadow and outline
-- copies of the last shadow strength; what was measured of each model drawn (weak keys, so a model that is gone
-- takes its widths with it); the draw-list calls that failed.
local st
local copies
local measured
local missing

function Overlay.reset()
    st = { x = nil, y = nil, dragging = false }
    copies = {}
    measured = setmetatable({}, { __mode = "k" })
    missing = {}
end
Overlay.reset()

-- The copies (offset x, offset y, colour) drawn under a text for a shadow strength and a step: `taps` the shadow's,
-- `outlined` those of a number with the outline on, the shadow and the outline in one copy per offset (as dark as
-- both together: 1 - (1 - shadow) * (1 - outline)). Kept while the strength and the step last.
local function copies_for(strength, step)
    if copies.strength ~= strength or copies.step ~= step then
        local shadow, outline, offsets = {}, {}, {}
        local function at(d)
            local key = d[1] .. "," .. d[2]
            if not shadow[key] then
                shadow[key], outline[key] = 0, 0
                offsets[#offsets + 1] = { d[1], d[2], key }
            end
            return key
        end
        for _, d in ipairs(TAPS) do shadow[at(d)] = math.min(1, strength * d[3]) end
        for _, d in ipairs(RING) do outline[at(d)] = OUTLINE_ALPHA / 255 end
        local taps, outlined = {}, {}
        for _, o in ipairs(offsets) do
            local x, y, s = o[1] * step, o[2] * step, shadow[o[3]]
            if 255 * s >= 1 then taps[#taps + 1] = { x, y, abgr(SHADOW_RGB, 255 * s) } end
            local a = 255 * (1 - (1 - s) * (1 - outline[o[3]]))
            if a >= 1 then outlined[#outlined + 1] = { x, y, abgr(SHADOW_RGB, a) } end
        end
        copies = { strength = strength, step = step, taps = taps, outlined = outlined }
    end
    return copies.taps, copies.outlined
end

-- What is measured of a model at the font size `px` (pushed when this is called): the widths of its texts, the line
-- height and the details' columns, measured once; the window draws one model for many frames.
local function measure_at(model, px)
    local sizes = measured[model]
    if not sizes then
        sizes = {}
        measured[model] = sizes
    end
    local m = sizes[px]
    if not m then
        m = { w = {}, text_h = imgui.calc_text_size("Ag").y }
        sizes[px] = m
    end
    return m
end

-- The width of `text` at the font size pushed now.
local function text_width(c, text)
    local w = c.widths[text]
    if not w then
        w = imgui.calc_text_size(text).x
        c.widths[text] = w
    end
    return w
end

-- Draws and measures at the font size `px` until pop_font (a pushed size is counted in c.started, so that a failure
-- pops it); returns the line height at that size.
local function push_font(c, px)
    imgui.push_font_size(px)
    c.started.fonts = c.started.fonts + 1
    local m = measure_at(c.model, px)
    c.base_widths, c.widths = c.widths, m.w
    return m.text_h
end

local function pop_font(c)
    c.widths = c.base_widths
    imgui.pop_font_size()
    c.started.fonts = c.started.fonts - 1
end

-- Positions handed to the draw lists: filled anew for each call (the binding copies them), never a new table.
local P, Q, R, S = { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }

local function rect_on(dl, x0, y0, x1, y1, color, rounding)
    P[1], P[2], Q[1], Q[2] = x0, y0, x1, y1
    dl:add_rect_filled(P, Q, color, rounding or 0, 0)
end

local function rect(c, x0, y0, x1, y1, color)
    if x1 > x0 and y1 > y0 then rect_on(c.dl, x0, y0, x1, y1, color) end
end

-- Draw-list calls the overlay can do without: the gradient rectangle and the quads (AddRectFilledMultiColor,
-- AddQuadFilled, AddQuad in REFramework's binding). Each is tried under pcall; one that fails is not tried again
-- until Overlay.reset, and the caller draws its stand-in of plain rectangles.
local function call_on(dl, name, ...)
    return dl[name](dl, ...)
end

local function try_call(name, dl, ...)
    if missing[name] then return false end
    if pcall(call_on, dl, name, ...) then return true end
    missing[name] = true
    return false
end

-- The names of the draw-list calls found missing since the last reset, in order (a copy).
function Overlay.missing()
    local list = {}
    for name in pairs(missing) do list[#list + 1] = name end
    table.sort(list)
    return list
end

-- Draw-list text at (x, y) over its shadow (for a `number` with the outline on, the copies of the shadow and the
-- outline together); nothing for an empty or missing text.
local function put(c, x, y, color, text, number)
    if not text or text == "" then return end
    local dl = c.dl
    for _, t in ipairs((number and c.outline) and c.outlined or c.taps) do
        P[1], P[2] = x + t[1], y + t[2]
        dl:add_text(P, t[3], text)
    end
    P[1], P[2] = x, y
    dl:add_text(P, color, text)
end

-- `text` cut on a character boundary and ended with ".." so that it is at most `max_w` wide.
local function fit(c, text, max_w)
    if text == "" or text_width(c, text) <= max_w then return text end
    local n = utf8.len(text)
    if not n then return text end
    local function cut(keep) return text:sub(1, utf8.offset(text, keep + 1) - 1) .. ".." end
    local lo, hi = 0, n - 1
    while lo < hi do
        local mid = (lo + hi + 1) // 2
        if text_width(c, cut(mid)) <= max_w then lo = mid else hi = mid - 1 end
    end
    return cut(lo)
end

-- The non-empty parts joined: "52 898 · 166/s · 40%".
local function join(...)
    local parts = {}
    for i = 1, select("#", ...) do
        local part = select(i, ...)
        if part and part ~= "" then parts[#parts + 1] = part end
    end
    return table.concat(parts, " · ")
end

local function numbers_of(row)
    return join(row.value, row.per_sec, row.share)
end

-- Panel: a thin dark bronze line in the gap under a row that ends at `y` (the cursor is already on the next row).
local function row_line(c, x, y)
    local ly = math.floor((y + imgui.get_cursor_screen_pos().y) / 2)
    rect(c, x, ly, x + c.w, ly + 1, C.line)
end

-- The width of a bar's coloured part: `share` (above 0) of the bar's width `w`, and at least 2 px so that a tiny
-- share shows.
local function part(w, share)
    return math.min(w, math.max(2, w * share))
end

-- Frameless: a thin bar at (x, y), `w` wide: a dark track with a 1 px edge and its shadow, and the coloured part
-- `share` (0..1) of it.
local function thin_bar(c, x, y, w, color, share)
    local x1, t, s = x + w, c.bar_t, c.step
    if c.track_shadow then rect(c, x + s, y + s, x1 + s, y + t + s, c.track_shadow) end
    rect(c, x, y, x1, y + t, C.track)
    rect(c, x - 1, y - 1, x1 + 1, y, EDGE)
    rect(c, x - 1, y + t, x1 + 1, y + t + 1, EDGE)
    rect(c, x - 1, y, x, y + t, EDGE)
    rect(c, x1, y, x1 + 1, y + t, EDGE)
    if share > 0 then
        local fw = part(w, share)
        rect(c, x, y, x + fw, y + t, color)
        if t >= 3 then rect(c, x, y, x + fw, y + 1, SHINE) end
    end
end

-- Frameless: the band from x0 to x1 fades out from `color` at its left to clear at its right; in steps of falling
-- alpha when the gradient call is missing.
local function fade(c, x0, y0, x1, y1, color)
    local clear = color & 0xFFFFFF
    P[1], P[2], Q[1], Q[2] = x0, y0, x1, y1
    if try_call("add_rect_filled_multi_color", c.dl, P, Q, color, clear, clear, color) then return end
    local alpha, step = color >> 24, (x1 - x0) / FADE_STEPS
    for i = 1, FADE_STEPS do
        rect(c, x0 + (i - 1) * step, y0, x0 + i * step, y1, (round(alpha * (FADE_STEPS - i + 0.5) / FADE_STEPS) << 24) | clear)
    end
end

-- Frameless: the dark band a block starts on, as wide as the window: solid over most of it, then fading out to the
-- right, with a mark in the block's colour at its left (none for the details' headings).
local function band(c, x, y, mark)
    local h, xs = c.band_h, x + c.w * BAND_SOLID
    rect(c, x, y, xs, y + h, C.band)
    fade(c, xs, y, x + c.w, y + h, C.band)
    if mark then rect(c, x, y, x + c.mark_w, y + h, mark) end
end

-- One row with a bar: `left` (in `label_color`, light by default) and, right-aligned, the numbers `right`; the
-- coloured part is `fill` (0..1) of the bar. With an `id` and the REFramework menu open the row is a button (all
-- of it, the bar too); returns true when it was clicked.
local function bar(c, id, color, fill, left, right, label_color)
    left, right = left or "", right or ""
    local p = imgui.get_cursor_screen_pos()
    local h = c.frameless and c.bar_row_h or c.row_h
    local x1 = p.x + c.w
    local clicked, hovered = false, false
    if id and c.interactive then
        clicked = imgui.invisible_button(id, { c.w, h })
        hovered = imgui.is_item_hovered()
    else
        imgui.item_size({ p.x, p.y }, { x1, p.y + h })
    end
    local share = math.max(0, math.min(1, fill or 0))
    local ty = p.y
    if c.frameless then
        if hovered then rect(c, p.x, p.y, x1, p.y + h, HOVER_FRAMELESS) end
    else
        rect(c, p.x, p.y, x1, p.y + h, C.panel_track)
        if share > 0 then rect(c, p.x, p.y, p.x + part(c.w, share), p.y + h, color) end
        if hovered then rect(c, p.x, p.y, x1, p.y + h, HOVER) end
        ty = p.y + (h - c.text_h) / 2
    end
    local rw = right ~= "" and text_width(c, right) or 0
    put(c, p.x + c.lead, ty, label_color or TEXT, fit(c, left, c.w - rw - c.lead - c.inset - c.pad))
    put(c, x1 - c.inset - rw, ty, TEXT, right, true)
    if c.frameless then
        local bx = p.x + c.lead
        thin_bar(c, bx, round(p.y + c.text_h + c.bar_gap), x1 - bx, color, share)
    else
        row_line(c, p.x, p.y + h)
    end
    c.bottom = p.y + h
    return clicked
end

-- Whether a setting leaves something on: every value but false does.
local function on(setting)
    return setting ~= false
end

-- The rows that the switches leave on screen: `allies` and `other` hide the ally rows and the Other rows.
local function shown_rows(rows, allies, other)
    local list = {}
    for _, row in ipairs(rows) do
        if (row.kind ~= "ally" or on(allies)) and (row.kind ~= "other" or on(other)) then list[#list + 1] = row end
    end
    return list
end

-- Rows of characters (damage, healing). A click on a row selects that character; the Other row has nobody
-- behind it, so it is no button.
local function actor_bars(c, block, rows, allies, other)
    for _, row in ipairs(shown_rows(rows, allies, other)) do
        local id = row.key and row.kind ~= "other" and (block .. ":" .. row.key)
        if bar(c, id, row_color(row), row.fill, row.name, numbers_of(row)) then
            c.actions.select_actor = row.key
        end
    end
end

-- The title over a block (`block`: a key of C.block) with its `total`. On the panel a dim line, "Dealt · 103 428";
-- without a background a band with the block's mark, its title in the block's colour and the total at the right.
-- Without a block (the notice, a gap) a plain dim line.
local function section(c, block, title, total)
    local p = imgui.get_cursor_screen_pos()
    if not (c.frameless and block) then
        local h = c.section_gap + c.text_h
        imgui.item_size({ p.x, p.y }, { p.x + c.w, p.y + h })
        put(c, p.x + c.inset, p.y + c.section_gap, DIM, fit(c, join(title, total), c.w - 2 * c.inset))
        c.bottom = p.y + h
        return
    end
    local colors = C.block[block]
    local gap = (c.first_band and GAP_FIRST or GAP) * c.scale
    c.first_band = false
    local h, y = gap + c.band_h, p.y + gap
    imgui.item_size({ p.x, p.y }, { p.x + c.w, p.y + h })
    band(c, p.x, y, colors.mark)
    local ty = y + (c.band_h - c.text_h) / 2
    local rw = total and total ~= "" and text_width(c, total) or 0
    put(c, p.x + c.indent, ty, colors.title, fit(c, title, c.w - rw - c.indent - c.pad))
    put(c, p.x + c.w - rw, ty, TEXT, total, true)
    c.bottom = p.y + h
end

-- A line of plain text: `left` and, right-aligned, `right` (light unless their colours are given).
local function text_row(c, left, right, left_color, right_color)
    local p = imgui.get_cursor_screen_pos()
    imgui.item_size({ p.x, p.y }, { p.x + c.w, p.y + c.line_h })
    local ty = p.y + (c.line_h - c.text_h) / 2
    local rw = right and text_width(c, right) or 0
    put(c, p.x + c.lead, ty, left_color or TEXT, fit(c, left, c.w - rw - c.lead - c.inset - c.pad))
    put(c, p.x + c.w - c.inset - rw, ty, right_color or TEXT, right, true)
    if not c.frameless then row_line(c, p.x, p.y + c.line_h) end
    c.bottom = p.y + c.line_h
end

-- The four corners of a diamond centred at (cx, cy), `r` from its centre: top, right, bottom, left.
local function corners(cx, cy, r)
    P[1], P[2], Q[1], Q[2], R[1], R[2], S[1], S[2] = cx, cy - r, cx + r, cy, cx, cy + r, cx - r, cy
end

-- Frameless: an enemy's diamond, purple on a dark edge; only its outline once killed. Squares when the quads are
-- missing.
local function diamond(c, cx, cy, r, hollow)
    local dl = c.dl
    if hollow then
        corners(cx, cy, r)
        if try_call("add_quad", dl, P, Q, R, S, DIAMOND_EDGE, 3) and try_call("add_quad", dl, P, Q, R, S, C.enemy, 1) then
            return
        end
    else
        corners(cx, cy, r + 1)
        if try_call("add_quad_filled", dl, P, Q, R, S, DIAMOND_EDGE) then
            corners(cx, cy, r)
            if try_call("add_quad_filled", dl, P, Q, R, S, C.enemy) then return end
        end
    end
    rect(c, cx - r - 1, cy - r - 1, cx + r + 1, cy + r + 1, DIAMOND_EDGE)
    rect(c, cx - r + 1, cy - r + 1, cx + r - 1, cy + r - 1, C.enemy)
    if hollow then rect(c, cx - r + 2, cy - r + 2, cx + r - 2, cy + r - 2, DIAMOND_EDGE) end
end

-- Frameless: one enemy row of the summary: the diamond, the name after it in light purple (dim once killed), the HP
-- dim at the right.
local function enemy_row(c, e)
    local p = imgui.get_cursor_screen_pos()
    local x1 = p.x + c.w
    imgui.item_size({ p.x, p.y }, { x1, p.y + c.line_h })
    local r = DIAMOND * c.scale
    diamond(c, p.x + c.indent + r, p.y + c.line_h / 2, r, e.killed == true)
    local ty = p.y + (c.line_h - c.text_h) / 2
    local rw = e.hp_text and text_width(c, e.hp_text) or 0
    local lx = p.x + ENEMY_INDENT * c.scale
    put(c, lx, ty, e.killed and DIM or C.enemy_label, fit(c, e.label, x1 - rw - lx - c.pad))
    put(c, x1 - rw, ty, DIM, e.hp_text, true)
    c.bottom = p.y + c.line_h
end

-- A square button of the header row at (x, y); a disabled one is only a dim glyph.
local function glyph_button(c, ctl, x, y)
    local gx = x + (c.btn_w - text_width(c, ctl.glyph)) / 2
    local gy = y + (c.header_h - c.text_h) / 2
    if ctl.enabled == false then
        put(c, gx, gy, DIM, ctl.glyph)
        return
    end
    imgui.set_cursor_screen_pos({ x, y })
    local clicked = imgui.invisible_button(ctl.id, { c.btn_w, c.header_h })
    if imgui.is_item_hovered() then rect(c, x, y, x + c.btn_w, y + c.header_h, c.hover) end
    put(c, gx, gy, TEXT, ctl.glyph)
    if clicked then CLICK[ctl.id](c.actions) end
end

-- The line under the header: bronze, or the colour of the character whose details are shown.
local function header_line(c, color, t)
    local p = imgui.get_cursor_screen_pos()
    local h = t + c.line_gap
    imgui.item_size({ p.x, p.y }, { p.x + c.w, p.y + h })
    local y, s = round(p.y), c.step
    if c.line_shadow then rect(c, p.x + s, y + s, p.x + c.w + s, y + t + s, c.line_shadow) end
    rect(c, p.x, y, p.x + c.w, y + t, color)
    c.bottom = p.y + h
end

-- The header line: optional back button, title (larger without a background) with an optional dim `sub` text, the
-- time and the controls (buttons only while the REFramework menu is open) at the right edge; then the line under it
-- (`o.line`, `o.line_t`: its colour and thickness when not the bronze one).
local function header(c, o)
    local p = imgui.get_cursor_screen_pos()
    local x0, y0, x1 = p.x, p.y, p.x + c.w
    local hh = c.header_h
    local ty = y0 + (hh - c.text_h) / 2
    local right = x1 - c.inset
    for i = #o.ctls, 1, -1 do
        local ctl = o.ctls[i]
        if ctl.text then
            right = right - text_width(c, ctl.text)
            put(c, right, ty, DIM, ctl.text, true)
            right = right - c.gap
        elseif c.interactive then
            right = right - c.btn_w
            glyph_button(c, ctl, right, y0)
        end
    end
    if o.time then
        right = right - text_width(c, o.time)
        put(c, right, ty, TEXT, o.time, true)
        right = right - c.gap
    end
    local left = x0 + c.inset
    if o.lead and c.interactive then
        glyph_button(c, o.lead, x0, y0)
        left = x0 + c.btn_w
    end
    local title, sub = o.title, o.sub
    local room = right - left
    local sub_w = sub and sub ~= "" and text_width(c, sub) or nil
    local larger = c.title_px ~= c.px
    local th = larger and push_font(c, c.title_px) or c.text_h
    local sub_x
    if sub_w and room - sub_w - c.gap >= room * 0.4 then
        title = fit(c, title, room - sub_w - c.gap)
        sub_x = left + text_width(c, title) + c.gap
    else
        title = fit(c, title, room)
    end
    put(c, left, y0 + (hh - th) / 2, TEXT, title)
    if larger then pop_font(c) end
    if sub_x then put(c, sub_x, ty, DIM, sub, true) end
    -- the buttons moved the cursor: put it back and take the row's space
    imgui.set_cursor_screen_pos({ x0, y0 })
    imgui.item_size({ x0, y0 }, { x1, y0 + hh })
    c.bottom = y0 + hh
    header_line(c, o.line or C.bronze, o.line_t or c.line_t)
end

local function history_controls(state)
    local count = math.floor(state.history_count or 0)
    local index = math.floor(state.history_index or 1)
    if count < 2 then return {} end
    return {
        { id = "history_prev", glyph = "‹", enabled = index > 1 },
        { text = string.format("%d/%d", index, count) },
        { id = "history_next", glyph = "›", enabled = index < count },
    }
end

-- A block is drawn when the model has it and its setting is on (the model leaves out a block that was off when it
-- was built; the setting also takes effect before the next build). `v` = the settings' values.
local function live_view(c, m, v)
    header(c, { title = m.header.title, sub = m.header.hp_text, time = m.header.time, ctls = { HIDE } })
    if m.damage and on(v.live_damage) then
        section(c, "damage", m.damage.title, join(m.damage.total, m.damage.per_sec))
        actor_bars(c, "damage", m.damage.rows, v.show_allies, v.live_other)
    end
    if m.taken and on(v.live_taken) then
        section(c, "enemies", m.taken.title, m.taken.total)
        for _, row in ipairs(m.taken.rows) do
            bar(c, nil, C.enemy, row.fill, row.label, row.value, c.frameless and C.enemy_label or nil)
        end
    end
    if m.heal and on(v.live_heal) then
        section(c, "heal", m.heal.title, join(m.heal.total, m.heal.per_sec))
        actor_bars(c, "heal", m.heal.rows, true, v.live_other)
    end
end

local function summary_view(c, m, v, state)
    local ctls = history_controls(state)
    ctls[#ctls + 1] = HIDE
    header(c, { title = m.title, time = m.time, ctls = ctls })
    if m.enemies and on(v.summary_enemies) and #m.enemies > 0 then
        section(c, "enemies", i18n.t("enemies"))
        for _, e in ipairs(m.enemies) do
            if c.frameless then enemy_row(c, e) else text_row(c, e.label, e.hp_text) end
        end
    end
    local damage = m.damage and on(v.summary_damage) and #m.damage.rows > 0
    if damage then
        section(c, "damage", m.damage.title, m.damage.total)
        actor_bars(c, "damage", m.damage.rows, true, true)
    end
    -- the grey rows: the allies, then Other, each unless its switch is off. Without a visible ally the block has no
    -- "Allies" heading; Other then goes under the damage heading, which it gets itself when the party's block is not
    -- drawn.
    local grey = m.allies and shown_rows(m.allies.rows, v.summary_allies, v.summary_other) or {}
    if #grey > 0 then
        if grey[1].kind == "ally" then
            section(c, "other", m.allies.title)
        elseif not damage then
            section(c, "damage", m.damage and m.damage.title or i18n.t("dealt"))
        end
        actor_bars(c, "allies", grey, true, true)
    end
    local heal = m.heal and on(v.summary_heal) and shown_rows(m.heal.rows, true, v.summary_other) or {}
    if #heal > 0 then
        section(c, "heal", m.heal.title, m.heal.total)
        actor_bars(c, "heal", heal, true, true)
    end
    if m.armor and on(v.summary_armor) and #m.armor > 0 then
        section(c, "other", i18n.t("armor"))
        for _, row in ipairs(m.armor) do text_row(c, row.label, row.value) end
    end
end

-- Columns of the skill table. A column nobody has anything for (perfect hits) is left out.
local function detail_columns(c, d)
    local heads = { i18n.t("details_hits"), i18n.t("details_total"), i18n.t("details_max"), "%", i18n.t("details_perfect") }
    local fields = { "hits", "total", "max", "share", "perfect" }
    local cols = {}
    for i, field in ipairs(fields) do
        local width, used = text_width(c, heads[i]), false
        for _, row in ipairs(d.rows) do
            local cell = row[field]
            if cell and cell ~= "" then
                used = true
                width = math.max(width, text_width(c, cell))
            end
        end
        if used or field ~= "perfect" then cols[#cols + 1] = { head = heads[i], field = field, width = width } end
    end
    return cols
end

-- One row of the table: `cells[i]` right-aligned in column i (drawn as numbers when `numbers`), the label takes what
-- is left. `back`: drawn under the row first, "band" (the headings, frameless) or a colour.
local function table_row(c, cols, label, cells, color, numbers, back)
    local p = imgui.get_cursor_screen_pos()
    imgui.item_size({ p.x, p.y }, { p.x + c.w, p.y + c.line_h })
    if back == "band" then
        band(c, p.x, p.y, nil)
    elseif back then
        rect(c, p.x, p.y, p.x + c.w, p.y + c.line_h, back)
    end
    local ty = p.y + (c.line_h - c.text_h) / 2
    local right = p.x + c.w - c.inset
    for i = #cols, 1, -1 do
        local cell = cells[i] or ""
        put(c, right - text_width(c, cell), ty, color, cell, numbers)
        right = right - cols[i].width - c.col_gap
    end
    put(c, p.x + c.lead, ty, color, fit(c, label, right - (p.x + c.lead)))
    if not c.frameless then row_line(c, p.x, p.y + c.line_h) end
    c.bottom = p.y + c.line_h
end

local function details_view(c, d)
    -- the columns and their headings, once per model
    local cols, heads = c.memo.cols, c.memo.heads
    if not cols then
        cols, heads = detail_columns(c, d), {}
        for i, col in ipairs(cols) do heads[i] = col.head end
        c.memo.cols, c.memo.heads = cols, heads
    end
    local numeric = 0
    for _, col in ipairs(cols) do numeric = numeric + col.width + c.col_gap end
    c.w = math.max(c.w, MIN_LABEL_WIDTH * c.scale + numeric)
    -- the line under the name in the character's colour, as thick as a bar
    local known = PARTY[d.kind] or d.kind == "ally" or d.kind == "other"
    header(c, { lead = BACK, title = d.name, ctls = { HIDE }, line = known and row_color(d) or nil,
        line_t = known and (c.frameless and c.bar_t or 2 * c.line_t) or nil })
    -- without a background: the headings on a band, every second row faintly banded
    table_row(c, cols, "", heads, DIM, false, c.frameless and "band" or nil)
    for i, row in ipairs(d.rows) do
        local cells = {}
        for j, col in ipairs(cols) do cells[j] = row[col.field] end
        table_row(c, cols, row.label, cells, TEXT, true, c.frameless and i % 2 == 0 and C.even_row or nil)
    end
    if #d.extra > 0 then section(c, nil, "") end -- a gap before the extra lines
    for _, row in ipairs(d.extra) do text_row(c, row.label, row.value) end
end

-- Behind the text, on the background layer (under every window, not clipped to this one): the panel of the panel
-- look, or the halo of the frameless one. Drawn last, when the size of the text is known. `origin` is where the text
-- began, `wp` the window's corner.
local function backdrop(c, v, origin, wp)
    if c.frameless and not v.halo then return end
    local get = imgui.get_background_draw_list
    local bg = type(get) == "function" and get() or nil
    if bg == nil then return end
    local x0, y0, x1, y1 = origin.x, origin.y, origin.x + c.w, c.bottom
    if not c.frameless then
        -- the window's rectangle: the text and imgui's padding around it
        local px, py = x0 - wp.x, y0 - wp.y
        local ax, ay, bx, by = wp.x, wp.y, x1 + px, y1 + py
        rect_on(bg, ax, ay, bx, by, abgr(PANEL_RGB, v.opacity * 255))
        rect_on(bg, ax, ay, bx, ay + 1, C.line)
        rect_on(bg, ax, by - 1, bx, by, C.line)
        rect_on(bg, ax, ay + 1, ax + 1, by - 1, C.line)
        rect_on(bg, bx - 1, ay + 1, bx, by - 1, C.line)
        return
    end
    -- layers of one translucent near-black, each a little larger and rounder: as dark as the opacity in the middle,
    -- fading out over the margin
    local margin = HALO_MARGIN * c.scale
    local a = 1 - (1 - math.min(0.95, v.opacity)) ^ (1 / HALO_LAYERS)
    local color = abgr(HALO_RGB, math.max(1, a * 255))
    for i = 1, HALO_LAYERS do
        local e = margin * i / HALO_LAYERS
        rect_on(bg, x0 - e, y0 - e, x1 + e, y1 + e, color, e * 1.5 + 2 * c.scale)
    end
end

-- What the state asks for: "details", "live", "summary" or nil (nothing to draw).
local function pick_view(state)
    local mode = state.mode
    if mode ~= "live" and mode ~= "summary" then return nil end
    if state.details then return "details" end
    if mode == "live" and state.live then return "live" end
    if mode == "summary" and state.summary then return "summary" end
    return nil
end

local function draw_view(view, state, v, interactive, actions, wp, started)
    local scale = v.scale
    local frameless = v.style ~= "panel"
    local px = FONT_SIZE * scale
    local step = math.max(1, round(px / 16))
    local taps, outlined = copies_for(v.shadow, step)
    local model = state[view]
    local memo = measure_at(model, px)
    local origin = imgui.get_cursor_screen_pos()
    local inset = frameless and 0 or PADDING * scale -- the texts' distance from the left and right edge
    local c = {
        frameless = frameless, scale = scale, interactive = interactive, actions = actions, started = started,
        dl = imgui.get_window_draw_list(),
        model = model, memo = memo, widths = memo.w, px = px, text_h = memo.text_h,
        w = WIDTH * scale, row_h = ROW_HEIGHT * scale, pad = PADDING * scale, gap = 4 * scale,
        btn_w = ROW_HEIGHT * scale, col_gap = 10 * scale, section_gap = 6 * scale,
        header_h = (frameless and HEADER_HEIGHT or ROW_HEIGHT) * scale,
        title_px = frameless and TITLE_SIZE * scale or px,
        inset = inset, indent = INDENT * scale,
        lead = frameless and INDENT * scale or inset, -- where a row's text starts
        hover = frameless and HOVER_FRAMELESS or HOVER,
        taps = taps, outlined = outlined, outline = v.outline, step = step,
        line_t = math.max(1, round(scale)), line_gap = round(3 * scale),
        bar_t = math.max(1, round(v.bar_px * scale)), bar_gap = math.max(1, round(2 * scale)),
        band_h = BAND_HEIGHT * scale, mark_w = math.max(1, round(MARK_WIDTH * scale)), first_band = true,
        bottom = origin.y,
    }
    c.line_h = c.text_h + 6 * scale
    c.bar_row_h = c.text_h + c.bar_gap + c.bar_t + 1 + round(3 * scale)
    local function shadow_color(k)
        local a = 255 * math.min(1, v.shadow * k)
        return a >= 1 and abgr(SHADOW_RGB, a) or nil
    end
    c.track_shadow, c.line_shadow = shadow_color(0.6), shadow_color(0.8)

    if view == "details" then
        details_view(c, state.details)
    elseif view == "live" then
        live_view(c, state.live, v)
    else
        summary_view(c, state.summary, v, state)
    end
    if type(state.notice) == "string" and state.notice ~= "" then section(c, nil, state.notice) end
    backdrop(c, v, origin, wp)
end

-- Follows the window between the settings and the player's drag. The settings are put on the
-- window only when they differ from what both sides last agreed on (first frame, a change in
-- the menu, a drag the settings refused); a drag is reported once, when the button goes up.
-- Returns the window's position.
local function follow_drag(actions, interactive)
    local wp = imgui.get_window_pos()
    if interactive and imgui.is_mouse_down(0) then
        if math.abs(wp.x - st.x) >= 1 or math.abs(wp.y - st.y) >= 1 then st.dragging = true end
    elseif st.dragging then
        st.dragging = false
        st.x, st.y = math.floor(wp.x + 0.5), math.floor(wp.y + 0.5)
        actions.moved = { x = st.x, y = st.y }
    end
    return wp
end

-- The imgui part of a frame. Notes in `started` what it has begun (`fonts`: the font sizes pushed), so the caller
-- can end it again if anything raises half way.
local function draw_window(state, settings, actions, started)
    local view = pick_view(state)
    if not view then return end
    local v = settings.values
    local interactive = reframework:is_drawing_ui()

    if st.x ~= v.window_x or st.y ~= v.window_y then
        imgui.set_next_window_pos({ v.window_x, v.window_y }, COND_ALWAYS, { 0, 0 })
        st.x, st.y, st.dragging = v.window_x, v.window_y, false
    end
    -- no border either; Begin reads the colour, so it can be popped right after it
    imgui.push_style_color(COL_BORDER, 0)
    started.colour = true
    imgui.begin_window("DD2DamageMeter overlay", nil, interactive and WINDOW_FLAGS or (WINDOW_FLAGS | CLICK_THROUGH_FLAGS))
    started.window = true
    imgui.pop_style_color(1)
    started.colour = false
    local wp = follow_drag(actions, interactive)
    imgui.push_font_size(FONT_SIZE * v.scale)
    started.fonts = 1
    draw_view(view, state, v, interactive, actions, wp, started)
end

function Overlay.draw(state, settings)
    local actions = { history = 0, hide = false, back = false }
    local started = { fonts = 0 }
    local ok, err = pcall(draw_window, state, settings, actions, started)
    -- end what was begun, innermost first; a failing end must not hide the first error
    for _ = 1, started.fonts do pcall(imgui.pop_font_size) end
    if started.colour then pcall(imgui.pop_style_color, 1) end
    if started.window then pcall(imgui.end_window) end
    return actions, (not ok) and tostring(err) or nil
end

return Overlay
