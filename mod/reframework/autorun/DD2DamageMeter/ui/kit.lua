-- Drawing helpers of the journal window (ui/journal.lua), its tab drawers (ui/journal_tabs.lua) and the settings
-- window (ui/settings_window.lua): the journal's colours, its window (a dark panel of its own), text at a font size,
-- measuring and fitting, rectangles, buttons, and pieces laid out one under another over pages. Draws on an imgui
-- draw list with REFramework's binding; no game logic and no texts of its own.
--
--   Kit.panel{ name, place, fill, missing, actions } -> err   one frame of a window with the journal's look, under
--                pcall: place() -> x, y, w, h, scale (inside the protection); then the window there (imgui paints
--                no background or border; no mouse while the REFramework menu is closed; its content as its size
--                when set_next_window_size is missing), the font size 14 × scale pushed, the dark panel with its 1 px
--                edge on the background draw list, and fill(k, frame): k a kit over the window (interactive with the
--                menu open, its actions `actions`), frame a kit on the background list (or k). Never raises:
--                whatever was begun (window, font sizes, colour) is ended again; err = nil or the message. A window
--                that could not begin leaves its place and size to an empty window, not to the next one begun.
--   Kit.try(missing, name, ...) -> ok, result   imgui[name](...) under pcall; false when it is missing or fails,
--                and then noted in `missing` (a set) and not tried again
--   Kit.display_size(missing) -> w, h | nil   the display's size (get_display_size through Kit.try)
--   Kit.round(v) -> the nearest whole number
--
--   Kit.COLORS   Overlay.COLORS plus panel, card, tab, tab_on, border, ok, bad, mid, ink,
--                tag = { weak|resist|immune = { background, text } }, selected, hover (all ImU32)
--   Kit.actor_color(kind, job, shade) -> ImU32   a character's colour, as the bars of the meter window
--   Kit.actor_text(kind, job, shade) -> ImU32   that colour for a name on the panel: a party member's lighter, an
--                enemy's light purple, an ally's and Other's grey (C.dim)
--   Kit.tint(color, t) -> ImU32   color towards white (t > 0) or black (t < 0) by |t| (0..1), its alpha kept
--   Kit.mix(color, other, t) -> ImU32   color t (0..1) of the way to `other`, its own alpha kept
--   Kit.on_color(color) -> ImU32   the text colour that reads best on `color`: C.ink (dark) or C.text (light)
--   Kit.new{ dl, x, y, w, h, scale, interactive, actions, page, started } -> k
--     fields k.x, k.y, k.w, k.h, k.px (the base font size, 14 px times scale), k.scale, k.page, k.interactive,
--     k.actions (where a drawer puts what its buttons did), k.dl. The caller has pushed the font size k.px;
--     `started` counts the font sizes the kit pushes ({ fonts = n }), so a failure can pop them.
--   k:unit(h, draw) -> page   a piece h high under the previous one: draw(x, y, w) runs when the piece falls on
--                             k.page, else it is only counted; a piece that does not fit starts the next page
--   k:fits(h) -> boolean      whether a piece h high would go on under the previous one (false: it starts a page)
--   k:pages() -> integer      pages taken so far (at least 1); k:height() -> the height used on the last page;
--                             k:used() -> the height its pieces take on k.page (0 when none falls there)
--   k:sub{ x, y, w, h, page } -> k   a kit over another area (missing fields: this kit's), nothing used yet
--   k:column{ x, w } -> k   a kit over another x and w whose pieces go on under this kit's (pages and heights shared)
--   k:text(x, y, color, s, px); k:width(s, px) -> number; k:fit(s, w, px) -> s cut with ".." to be at most w wide
--                        ("" when not even ".." fits)
--   k:wrap2(s, w, px) -> { line } | { line, line }   s in at most two lines w wide: the words that fit on the first,
--                        the rest (cut with "..") on the second; one line (cut) when not even its first word fits
--   k:spans(x, y, w, spans, px)   texts side by side, spans = { { text, color } }, at most w in all: the first that
--                        does not fit is cut with "..", those after it left out
--   k:spans_width(spans, px) -> the width k:spans takes for them whole: the sum of each one's own width (ImGui
--                        rounds every width up, so measuring them as one text can be short by a pixel a span)
--   Kit.name_cell(r) -> a row's first cell: r.name in the colour of r.kind, r.job, r.shade (Kit.actor_text), then
--                        " · " and r.types dim; without a name r.label in light purple
--   k:rect(x0, y0, x1, y1, color, rounding)
--   k:bar(x, y, w, h, color, share)   a dark track and its coloured part share (0..1), at least 2 px of it
--   k:filled(x, y, w, h, color, share)   a row's share: `color` faint over share (0..1) of w (at least the mark), a
--                        3 px mark of it in full at the left, both 1 px off the top and bottom; nothing for 0
--   k:band(block, title, total)   a unit: 4 px, then the 20 px band: dark, fading out to the right, a mark and the
--                        title in the block's colours (block: a key of COLORS.block, or { mark, title } colours)
--   k:row(cells, opts)   a unit 20 px; cells = { { text|[1], w|[2], align = "left"|"right", color, px,
--                        parts = spans (in place of the text, left-aligned), bar = { color, share } } } (w nil: the
--                        rest; bar: a bar in place of the text);
--                        opts = { indent (8 px), back = colour, fill = { color, share } (k:filled behind the row) };
--                        fixed widths too wide for the row shrink in proportion (open cells keep 24 px each), so
--                        no cell leaves the row
--   k:tags(label, list, kind, empty)   a unit: label then rounded tags of `kind` (a key of COLORS.tag), wrapped;
--                        `empty` (default jnone) dim when the list is empty
--   k:button(id, x, y, w, h) -> boolean   an invisible button, lighter while hovered; false unless interactive
--   k:glyph(id, g, x, y, w, h) -> boolean   the glyph g centred in the box, a button with the menu open (dim without)
--   k:button_row(labels, ids, active, x, y, w) -> index|nil   the journal's tab look at (x, y), `w` wide: each label
--                        on the tabs' ground, labels[active] lighter with a bronze edge, all squeezed to one width
--                        when too wide; ids[i] is the button over labels[i]; returns the index clicked
--   Kit.BUTTON_ROW_H     the height of a button row at scale 1; Kit.ROW_H, Kit.BAND_H the heights of a row and of a
--                        band's unit (its gap above included) at scale 1; Kit.FONT_SIZE the base font size at scale 1
-- Positions, widths and px are pixels on screen; the kit's own sizes are at scale 1 times k.scale.
-- Kit.missing() -> { name } the draw-list calls found missing (the gradient), Kit.reset() forgets them and the widths.
local i18n = require("DD2DamageMeter/i18n")
local Overlay = require("DD2DamageMeter/ui/overlay")

local Kit = {}

-- ImU32 colours are 0xAABBGGRR; `abgr` takes the usual 0xRRGGBB and an alpha of 0..255.
local function abgr(rgb, alpha)
    alpha = alpha or 255
    local r, g, b = (rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF
    return (alpha << 24) | (b << 16) | (g << 8) | r
end

local C = {}
for key, value in pairs(Overlay.COLORS) do C[key] = value end
C.panel = abgr(0x171414, 250) -- nearly opaque: the game's own menus do not show through
C.card = abgr(0x211B17)
C.tab = abgr(0x1F1A16)
C.tab_on = abgr(0x33271D)
C.border = abgr(0x4A3A2C)
C.ok = abgr(0x9FD07A)
C.bad = abgr(0xE89A9A)
C.mid = abgr(0xCFC7B8)
C.ink = abgr(0x171414) -- dark text on a light ground
C.tag = {
    weak = { abgr(0x3C5A2C), abgr(0xD8ECC4) },
    resist = { abgr(0x5A2A2A), abgr(0xF0C8C8) },
    immune = { abgr(0x3A3A3A), abgr(0xCFC7B8) },
}
C.selected = abgr(0xFFFFFF, 18) -- a selected row, lighter than the panel
C.hover = abgr(0xFFFFFF, 24)    -- a button under the mouse
Kit.COLORS = C
local PARTY = { player = true, pawn = true }

function Kit.actor_color(kind, job, shade)
    if PARTY[kind] then return Overlay.shade(C.vocation[job] or C.unknown, shade) end
    if kind == "ally" then return C.ally end
    if kind == "other" then return C.other end
    return C.enemy
end

function Kit.mix(color, other, t)
    t = math.max(0, math.min(1, tonumber(t) or 0))
    local out = color & 0xFF000000
    for shift = 0, 16, 8 do
        local v, w = (color >> shift) & 0xFF, (other >> shift) & 0xFF
        out = out | (math.floor(v + (w - v) * t + 0.5) << shift)
    end
    return out
end

function Kit.tint(color, t)
    t = math.max(-1, math.min(1, tonumber(t) or 0))
    return Kit.mix(color, t > 0 and 0xFFFFFFFF or 0xFF000000, math.abs(t))
end

local TEXT_TINT = 0.4 -- a party member's name: its colour this much towards white, to read on the dark panel

function Kit.actor_text(kind, job, shade)
    if PARTY[kind] then return Kit.tint(Kit.actor_color(kind, job, shade), TEXT_TINT) end
    if kind == "enemy" then return C.enemy_label end
    return C.dim
end

-- The relative luminance (WCAG) of an ImU32 colour, and the contrast of two.
local LUMA = { 0.2126, 0.7152, 0.0722 } -- red, green, blue

local function luminance(color)
    local sum = 0
    for i, weight in ipairs(LUMA) do
        local v = ((color >> (8 * (i - 1))) & 0xFF) / 255
        v = v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4
        sum = sum + weight * v
    end
    return sum
end

local function contrast(a, b)
    local la, lb = luminance(a), luminance(b)
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05)
end

function Kit.on_color(color)
    return contrast(color, C.ink) > contrast(color, C.text) and C.ink or C.text
end

-- Sizes at scale 1.
local FONT_SIZE = 14
local ROW_H = 20
local BAND_H, BAND_GAP = 20, 4
local BAND_SOLID = 0.65 -- the band is solid over this share of its width, then fades out
local MARK_W = 3
local INDENT = 8        -- where a band's title and a row's first cell start
local CELL_GAP = 8
local OPEN_MIN = 24     -- what a row's open cell keeps when its fixed cells do not fit
local CELL_BAR_H = 8     -- a bar in place of a cell's text (the type rows of What hit it)
local FILL_ALPHA = 60   -- a row's share: its colour this faint behind the text
local FILL_INSET = 1    -- the share keeps this off the row's top and bottom, so that filled rows stay apart
local TAG_PX, TAG_H, TAG_PAD, TAG_GAP, TAG_ROUND = 12, 16, 5, 4, 3
local BUTTON_ROW_H, BUTTON_PAD, BUTTON_GAP = 24, 10, 2
Kit.BUTTON_ROW_H = BUTTON_ROW_H
Kit.FONT_SIZE = FONT_SIZE
Kit.ROW_H, Kit.BAND_H = ROW_H, BAND_GAP + BAND_H
local FADE_STEPS = 4
local MAX_WIDTHS = 4000 -- texts measured before the width cache starts over

-- Text widths by font size, and the draw-list calls found missing.
local widths, n_widths
local missing

function Kit.reset()
    widths, n_widths = {}, 0
    missing = {}
end
Kit.reset()

function Kit.missing()
    local list = {}
    for name in pairs(missing) do list[#list + 1] = name end
    table.sort(list)
    return list
end

local K = {}
K.__index = K

-- `cur`: where the next piece goes (at: its page, cy: its offset on that page) and the height used on k.page; a
-- column shares it with the kit it was made from.
function Kit.new(o)
    local scale = o.scale or 1
    return setmetatable({
        dl = o.dl, x = o.x, y = o.y, w = o.w, h = o.h, scale = scale, px = FONT_SIZE * scale,
        interactive = o.interactive == true, actions = o.actions or {}, page = o.page or 1,
        started = o.started or { fonts = 0 }, cur = { at = 1, cy = 0, used = 0 },
    }, K)
end

function K:sub(o)
    return Kit.new({
        dl = self.dl, x = o.x or self.x, y = o.y or self.y, w = o.w or self.w, h = o.h or self.h,
        scale = self.scale, interactive = self.interactive, actions = self.actions,
        page = o.page or self.page, started = self.started,
    })
end

function K:column(o)
    local k = self:sub({ x = o.x, w = o.w })
    k.cur = self.cur
    return k
end

function K:unit(h, draw)
    local cur = self.cur
    if cur.cy > 0 and cur.cy + h > self.h then
        cur.at, cur.cy = cur.at + 1, 0
    end
    local page = cur.at
    if page == self.page then
        if draw then draw(self.x, self.y + cur.cy, self.w) end
        cur.used = cur.cy + h
    end
    cur.cy = cur.cy + h
    return page
end

function K:fits(h)
    local cur = self.cur
    return cur.cy == 0 or cur.cy + h <= self.h
end

function K:pages()
    return self.cur.at
end

function K:height()
    return self.cur.cy
end

function K:used()
    return self.cur.used
end

-- Runs fn at the font size px (pushed unless it is the base one, and counted so that a failure pops it).
local function at_size(self, px, fn, ...)
    if px == self.px then return fn(...) end
    imgui.push_font_size(px)
    self.started.fonts = self.started.fonts + 1
    local r = fn(...)
    imgui.pop_font_size()
    self.started.fonts = self.started.fonts - 1
    return r
end

-- Positions handed to the draw list: filled anew for each call (the binding copies them).
local P, Q = { 0, 0 }, { 0, 0 }

local function add_text(dl, x, y, color, s)
    P[1], P[2] = x, y
    dl:add_text(P, color, s)
end

function K:text(x, y, color, s, px)
    if s == nil or s == "" then return end
    at_size(self, px or self.px, add_text, self.dl, x, y, color, s)
end

local function measure(s)
    return imgui.calc_text_size(s).x
end

function K:width(s, px)
    if s == nil or s == "" then return 0 end
    px = px or self.px
    local by = widths[px]
    if not by then
        by = {}
        widths[px] = by
    end
    local w = by[s]
    if not w then
        w = at_size(self, px, measure, s)
        if n_widths >= MAX_WIDTHS then
            widths, n_widths = { [px] = {} }, 0
            by = widths[px]
        end
        by[s] = w
        n_widths = n_widths + 1
    end
    return w
end

function K:spans(x, y, max_w, list, px)
    local right = x + max_w
    for _, sp in ipairs(list) do
        local text = sp[1] or sp.text
        if text ~= nil and text ~= "" then
            local shown = self:fit(text, right - x, px)
            if shown == "" then return end
            self:text(x, y, sp[2] or sp.color or C.text, shown, px)
            if shown ~= text then return end
            x = x + self:width(text, px)
        end
    end
end

function K:spans_width(list, px)
    local w = 0
    for _, sp in ipairs(list) do w = w + self:width(sp[1] or sp.text, px) end
    return w
end

function Kit.name_cell(r)
    if r.name == nil then return { r.label, color = C.enemy_label } end
    return { parts = { { r.name, Kit.actor_text(r.kind, r.job, r.shade) }, { r.types and (" · " .. r.types), C.dim } } }
end

function K:fit(s, max_w, px)
    if s == nil or s == "" then return "" end
    if self:width(s, px) <= max_w then return s end
    local n = utf8.len(s)
    if not n then return s end
    local function cut(keep) return s:sub(1, utf8.offset(s, keep + 1) - 1) .. ".." end
    local lo, hi = 0, n - 1
    while lo < hi do
        local mid = (lo + hi + 1) // 2
        if self:width(cut(mid), px) <= max_w then lo = mid else hi = mid - 1 end
    end
    local short = cut(lo)
    if lo == 0 and self:width(short, px) > max_w then return "" end
    return short
end

function K:wrap2(s, w, px)
    if self:width(s, px) <= w then return { s } end
    local words = {}
    for word in s:gmatch("%S+") do words[#words + 1] = word end
    local first, n = "", 0
    for i, word in ipairs(words) do
        local try = i == 1 and word or (first .. " " .. word)
        if self:width(try, px) > w then break end
        first, n = try, i
    end
    if n == 0 or n == #words then return { self:fit(s, w, px) } end
    return { first, self:fit(table.concat(words, " ", n + 1), w, px) }
end

function K:rect(x0, y0, x1, y1, color, rounding)
    if not (x1 > x0 and y1 > y0) then return end
    P[1], P[2], Q[1], Q[2] = x0, y0, x1, y1
    self.dl:add_rect_filled(P, Q, color, rounding or 0, 0)
end

-- The band fades out from `color` at its left to clear at its right; in steps of falling alpha when the gradient
-- call is missing (it is not tried again until Kit.reset).
local function gradient(dl, color, clear)
    dl:add_rect_filled_multi_color(P, Q, color, clear, clear, color)
end

local function fade(self, x0, y0, x1, y1, color)
    if x1 <= x0 then return end
    local clear = color & 0xFFFFFF
    if not missing.add_rect_filled_multi_color then
        P[1], P[2], Q[1], Q[2] = x0, y0, x1, y1
        if pcall(gradient, self.dl, color, clear) then return end
        missing.add_rect_filled_multi_color = true
    end
    local alpha, step = color >> 24, (x1 - x0) / FADE_STEPS
    for i = 1, FADE_STEPS do
        local a = math.floor(alpha * (FADE_STEPS - i + 0.5) / FADE_STEPS + 0.5)
        self:rect(x0 + (i - 1) * step, y0, x0 + i * step, y1, (a << 24) | clear)
    end
end

function K:bar(x, y, w, h, color, share)
    if w <= 0 then return end
    self:rect(x, y, x + w, y + h, C.track)
    share = math.max(0, math.min(1, tonumber(share) or 0))
    if share > 0 then self:rect(x, y, x + math.min(w, math.max(2, w * share)), y + h, color) end
end
local bar = K.bar

function K:filled(x, y, w, h, color, share)
    share = math.max(0, math.min(1, tonumber(share) or 0))
    if share <= 0 or w <= 0 then return end
    local s = self.scale
    local inset = FILL_INSET * s
    local mark = math.max(1, math.floor(MARK_W * s + 0.5))
    y, h = y + inset, h - 2 * inset
    self:rect(x, y, x + math.max(mark, w * share), y + h, (color & 0xFFFFFF) | (FILL_ALPHA << 24))
    self:rect(x, y, x + mark, y + h, color)
end

function K:band(block, title, total)
    local s = self.scale
    self:unit((BAND_GAP + BAND_H) * s, function(x, y, w)
        local colors = type(block) == "table" and block or C.block[block] or C.block.other
        local h = BAND_H * s
        y = y + BAND_GAP * s
        local xs = x + w * BAND_SOLID
        self:rect(x, y, xs, y + h, C.band)
        fade(self, xs, y, x + w, y + h, C.band)
        self:rect(x, y, x + math.max(1, math.floor(MARK_W * s + 0.5)), y + h, colors.mark)
        local ty = y + (h - self.px) / 2
        local tw = self:width(total)
        local pad = INDENT * s
        self:text(x + pad, ty, colors.title, self:fit(title, w - tw - 3 * pad))
        self:text(x + w - pad - tw, ty, C.text, total)
    end)
end

local function cell_text(c) return c.text or c[1] end
local function cell_w(c) return c.w or c[2] end

function K:row(cells, opts)
    opts = opts or {}
    local s = self.scale
    self:unit(ROW_H * s, function(x, y, w)
        local h = ROW_H * s
        if opts.back then self:rect(x, y, x + w, y + h, opts.back) end
        local fill = opts.fill
        if fill then self:filled(x, y, w, h, fill.color or fill[1], fill.share or fill[2]) end
        local x0 = x + (opts.indent or INDENT * s)
        local gap = CELL_GAP * s
        local fixed, open = 0, 0
        for _, c in ipairs(cells) do
            local cw = cell_w(c)
            if cw then fixed = fixed + cw else open = open + 1 end
        end
        -- fixed cells too wide for the row shrink, gaps and all, so that every cell stays inside it
        local room = math.max(0, x + w - x0)
        local need = fixed + gap * (#cells - 1)
        local keep = open * OPEN_MIN * s
        local f = 1
        if need > 0 and need + keep > room then f = math.max(0, room - keep) / need end
        gap = gap * f
        local rest = math.max(0, room - need * f) / math.max(1, open)
        local cx = x0
        for _, c in ipairs(cells) do
            local cw = cell_w(c)
            cw = cw and cw * f or rest
            if c.bar then
                local bh = CELL_BAR_H * s
                bar(self, cx, y + (h - bh) / 2, cw, bh, c.bar.color or c.bar[1], c.bar.share or c.bar[2])
            elseif c.parts then
                local px = c.px or self.px
                self:spans(cx, y + (h - px) / 2, cw, c.parts, px)
            else
                local px = c.px or self.px
                local text = self:fit(cell_text(c), cw, px)
                local tx = cx
                if c.align == "right" then tx = cx + cw - self:width(text, px) end
                self:text(tx, y + (h - px) / 2, c.color or C.text, text, px)
            end
            cx = cx + cw + gap
        end
    end)
end

function K:tags(label, list, kind, empty)
    local s = self.scale
    local colors = C.tag[kind] or C.tag.immune
    local tag_px, line_h = TAG_PX * s, ROW_H * s
    local pad, gap, th = TAG_PAD * s, TAG_GAP * s, TAG_H * s
    local lx = self.x + INDENT * s
    local x0 = lx + self:width(label) + 6 * s
    local right = self.x + self.w
    -- where each tag goes: { x offset from x0, line, text, width }
    local placed, cx, line = {}, 0, 0
    for _, t in ipairs(list) do
        local tw = self:width(t, tag_px) + 2 * pad
        if cx > 0 and x0 + cx + tw > right then cx, line = 0, line + 1 end
        local room = right - x0 - cx
        local text = t
        if tw > room then
            text = self:fit(t, room - 2 * pad, tag_px)
            tw = room
        end
        placed[#placed + 1] = { cx, line, text, tw }
        cx = cx + tw + gap
    end
    self:unit((line + 1) * line_h, function(_, y)
        self:text(lx, y + (line_h - self.px) / 2, C.text, label)
        if #placed == 0 then
            self:text(x0, y + (line_h - self.px) / 2, C.dim, empty or i18n.t("jnone"))
            return
        end
        for _, p in ipairs(placed) do
            local tx, ty = x0 + p[1], y + p[2] * line_h + (line_h - th) / 2
            self:rect(tx, ty, tx + p[4], ty + th, colors[1], TAG_ROUND * s)
            self:text(tx + pad, ty + (th - tag_px) / 2, colors[2], p[3], tag_px)
        end
    end)
end

-- `id` must be unique within the window (imgui tells buttons apart by it).
function K:button(id, x, y, w, h)
    if not self.interactive then return false end
    imgui.set_cursor_screen_pos({ x, y })
    local clicked = imgui.invisible_button(id, { math.max(1, w), math.max(1, h) })
    if imgui.is_item_hovered() then self:rect(x, y, x + w, y + h, C.hover) end
    return clicked == true
end

function K:glyph(id, g, x, y, w, h)
    local clicked = self:button(id, x, y, w, h)
    self:text(x + (w - self:width(g)) / 2, y + (h - self.px) / 2, self.interactive and C.text or C.dim, g)
    return clicked
end

function K:button_row(labels, ids, active, x, y, w)
    local s = self.scale
    local pad, gap, h = BUTTON_PAD * s, BUTTON_GAP * s, BUTTON_ROW_H * s
    local n = #labels
    local widths, total = {}, 0
    for i, label in ipairs(labels) do
        widths[i] = self:width(label) + 2 * pad
        total = total + widths[i]
    end
    local room = w - gap * (n - 1)
    local squeeze = total > room
    local clicked
    local bx = x
    for i, label in ipairs(labels) do
        local bw = squeeze and room / n or widths[i]
        local on = i == active
        self:rect(bx, y, bx + bw, y + h, on and C.tab_on or C.tab)
        local edge = on and C.bronze or C.border
        self:rect(bx, y, bx + bw, y + 1, edge)
        self:rect(bx, y + 1, bx + 1, y + h, edge)
        self:rect(bx + bw - 1, y + 1, bx + bw, y + h, edge)
        -- over the ground, so that its hover light shows
        if self:button(ids[i], bx, y, bw, h) then clicked = i end
        local text = squeeze and self:fit(label, bw - 2 * pad) or label
        self:text(bx + (bw - self:width(text)) / 2, y + (h - self.px) / 2, on and C.text or C.dim, text)
        bx = bx + bw + gap
    end
    return clicked
end

-- The window --------------------------------------------------------------------------------------

-- ImGuiWindowFlags values of ImGui 1.92.0.
local WIN_NO_TITLE_BAR = 1
local WIN_NO_RESIZE = 2
local WIN_NO_MOVE = 4
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

-- imgui paints no background and no border: the panel is the window's own.
local WINDOW_FLAGS = WIN_NO_TITLE_BAR | WIN_NO_RESIZE | WIN_NO_MOVE | WIN_NO_SCROLLBAR | WIN_NO_SCROLL_WITH_MOUSE
    | WIN_NO_COLLAPSE | WIN_NO_BACKGROUND | WIN_NO_SAVED_SETTINGS | WIN_NO_FOCUS_ON_APPEARING
    | WIN_NO_BRING_TO_FRONT_ON_FOCUS
-- With the REFramework menu closed the mouse goes to the game.
local CLICK_THROUGH_FLAGS = WIN_NO_MOUSE_INPUTS | WIN_NO_NAV
local WINDOW_PADDING = 8 -- imgui's, around the content of a window that sizes itself
-- An empty window that takes the place and size given to a window that then could not begin.
local SPARE = "DD2DamageMeter spare"

function Kit.round(v)
    return math.floor(v + 0.5)
end

function Kit.try(missing, name, ...)
    if missing[name] then return false end
    local fn = imgui[name]
    if type(fn) == "function" then
        local ok, r = pcall(fn, ...)
        if ok then return true, r end
    end
    missing[name] = true
    return false
end

function Kit.display_size(missing)
    local ok, d = Kit.try(missing, "get_display_size")
    if ok and (type(d) == "table" or type(d) == "userdata") then
        local w, h = d.x, d.y
        if type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then return w, h end
    end
    return nil
end

-- The imgui part of a frame. Notes in `started` what it has begun (`placed`: the place and size given, `fonts`: the
-- font sizes pushed), so that Kit.panel can end it again if anything raises half way.
local function panel_frame(o, started)
    local x, y, w, h, scale = o.place()
    local interactive = reframework:is_drawing_ui()
    -- no border either; Begin reads the colour, so it can be popped right after it
    imgui.push_style_color(COL_BORDER, 0)
    started.colour = true
    -- the place and size right before Begin, which takes them
    imgui.set_next_window_pos({ x, y }, COND_ALWAYS, { 0, 0 })
    started.placed = true
    local sized = Kit.try(o.missing, "set_next_window_size", { w, h }, COND_ALWAYS)
    local flags = WINDOW_FLAGS | (interactive and 0 or CLICK_THROUGH_FLAGS) | (sized and 0 or WIN_ALWAYS_AUTO_RESIZE)
    imgui.begin_window(o.name, nil, flags)
    started.window = true
    imgui.pop_style_color(1)
    started.colour = false
    imgui.push_font_size(FONT_SIZE * scale)
    started.fonts = started.fonts + 1

    local k = Kit.new({ dl = imgui.get_window_draw_list(), x = x, y = y, w = w, h = h, scale = scale,
        interactive = interactive, actions = o.actions, started = started })
    -- the panel on the background layer (under every window, not clipped to this one)
    local get_bg = imgui.get_background_draw_list
    local bg = type(get_bg) == "function" and get_bg() or nil
    local frame = bg and Kit.new({ dl = bg, x = x, y = y, w = w, h = h, scale = scale, started = started }) or k
    frame:rect(x, y, x + w, y + h, C.panel)
    frame:rect(x, y, x + w, y + 1, C.border)
    frame:rect(x, y + h - 1, x + w, y + h, C.border)
    frame:rect(x, y + 1, x + 1, y + h - 1, C.border)
    frame:rect(x + w - 1, y + 1, x + w, y + h - 1, C.border)
    o.fill(k, frame)
    -- a window that sizes itself (no set_next_window_size): its content is the whole window
    if not sized then
        local p = WINDOW_PADDING
        imgui.set_cursor_screen_pos({ x + p, y + p })
        imgui.item_size({ x + p, y + p }, { x + w - p, y + h - p })
    end
end

function Kit.panel(o)
    local started = { fonts = 0 }
    local ok, err = pcall(panel_frame, o, started)
    -- end what was begun, innermost first; a failing end must not hide the first error
    for _ = 1, started.fonts do pcall(imgui.pop_font_size) end
    if started.placed and not started.window then
        -- the border colour is still pushed: the empty window has no visible edge either
        if pcall(imgui.begin_window, SPARE, nil, WINDOW_FLAGS | CLICK_THROUGH_FLAGS) then pcall(imgui.end_window) end
    end
    if started.colour then pcall(imgui.pop_style_color, 1) end
    if started.window then pcall(imgui.end_window) end
    return (not ok) and tostring(err) or nil
end

return Kit
