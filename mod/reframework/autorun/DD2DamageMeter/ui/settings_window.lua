-- The settings window: a dark panel like the journal's beside the meter window, with the title, every shown setting
-- in its group under a heading (one row each: its label at the left, its value at the right, ‹ › around a choice or a
-- number; the table of the meter's sections as rows of two cells under its line of column names, a dim «—» where a
-- window has no such section), the selected row lighter (on a table row its selected cell lighter still, with a
-- bronze line under it), under a thin line the help of the selected row, and the hint lines at the bottom (both
-- wrapped to the window's width; the help as high as the longest help of any row). Drawn in the journal's window
-- (Kit.panel) with its kit, from the model of settings_view.lua; no texts of its own but the key prompt. The rows that
-- do not fit page, and the page drawn is the one that holds the selected row (the table's column names over it again
-- when it goes on over a page). The mouse works while the REFramework menu is open (the buttons exist only then);
-- without it the window is only a picture and follows its keys (SettingsUI.KEYS), which the game receives too.
-- It sits on the side of the meter with more room on the display, its top at the meter's, inside the display; when
-- the display size cannot be read, right of the meter at its top. Its width is the widest row's as the font measures
-- it, every row and value of the language shown counted, within SettingsUI.FIT_MIN..FIT_MAX × scale; measured inside
-- the window once per language and scale and taken from the next frame on (SettingsUI.WIDTH × scale until then, or
-- when measuring fails). The help's and the hint's lines are measured once per model, hint and width the same way.
--
-- SettingsUI.draw(state, settings) -> actions, err
--   state   = { model = SettingsView.build(...), sel = the selected row's index, col = the selected cell of a table
--             row (1 | 2), waiting = the setting that waits for a key | nil }
--   actions = { select = row index | nil, col = 1|2|nil (the cell clicked), select_step = -1|0|1, step = -1|0|1,
--               group_step = -1|0|1, activate = boolean (Enter: a switch flips, a key row waits for a key),
--               close = boolean }
--   err     = nil, or the message of an error caught while drawing. draw never raises: whatever it had started
--             (window, font sizes, colour) is ended again, and the actions gathered up to the failure are returned.
-- Button ids: "##dd2dm_srow:<key>" (select; on a switch, a key row or a table cell activate too: a cell's key is
-- its switch's, a table row's own button is over its label and only selects), "##dd2dm_sprev:<key>" /
-- "##dd2dm_snext:<key>" (select and step -1 / +1), "##dd2dm_sclose" (close).
-- SettingsUI.KEYS = { [vk] = { action field, value } }; SettingsUI.key_actions(pressed: table<vk, true>) -> actions
--   (the same fields; two keys of one field add up, at most 1 either way)
-- SettingsUI.missing() -> { name }: the imgui calls found missing (get_display_size, set_next_window_size, and the
--   kit's gradient), in order; SettingsUI.reset() forgets them and what was measured.
local i18n = require("DD2DamageMeter/i18n")
local Kit = require("DD2DamageMeter/ui/kit")
local Overlay = require("DD2DamageMeter/ui/overlay")
local SettingsView = require("DD2DamageMeter/settings_view")

local SettingsUI = {}

-- Where it goes, in pixels: EDGE from the display's edges; without the display size, at most FALLBACK_H tall.
local EDGE, FALLBACK_H = 16, 720
local METER_PAD = 8      -- imgui's padding on each side of the meter's content

-- Sizes in pixels at scale 1.
local TITLE_PX, SMALL_PX = 16, 12
-- The window's width is the widest row's (its label and widest value with the ‹ ›, the gaps and the margins) as the
-- font measures them in the language shown, within FIT_MIN..FIT_MAX; WIDTH until it is measured or when measuring
-- fails. MIN_W: the least it takes when neither side of the meter has its width.
local WIDTH, FIT_MIN, FIT_MAX, MIN_W = 360, 320, 480, 300
SettingsUI.WIDTH, SettingsUI.FIT_MIN, SettingsUI.FIT_MAX = WIDTH, FIT_MIN, FIT_MAX
local GAP = 12                 -- between the meter and the window
local MARGIN = 10
local TOP, HEAD_H, BODY_TOP, BODY_GAP, HINT_LINE, BOTTOM = 6, 32, 6, 8, 16, 6
local HELP_TOP, HELP_LINES, HELP_GAP = 4, 2, 4 -- the help: under its thin line, two lines until measured, the hint
local COLS_H, CELL_W, CELL_MARK = 16, 64, 2      -- the table: its line of column names, a cell, its bronze line
local ROW_H, BAND_H = Kit.ROW_H, Kit.BAND_H
local BTN_W, ARROW_W, PAD, SEL_MARK = 24, 20, 8, 3
local DASH = "—" -- a table cell of a window without that section

local C = Kit.COLORS

SettingsUI.KEYS = {
    [0x26] = { "select_step", -1 }, [0x28] = { "select_step", 1 }, -- Up / Down: the selection
    [0x25] = { "step", -1 }, [0x27] = { "step", 1 },               -- Left / Right: the value
    [0x21] = { "group_step", -1 }, [0x22] = { "group_step", 1 },   -- PgUp / PgDn: the groups
    [0x0D] = { "activate", true },                                   -- Enter
}

local function new_actions()
    return { select = nil, col = nil, select_step = 0, step = 0, group_step = 0, activate = false, close = false }
end

function SettingsUI.key_actions(pressed)
    local a = new_actions()
    for vk, down in pairs(pressed or {}) do
        local key = SettingsUI.KEYS[vk]
        if key and down then
            if key[2] == true then
                a[key[1]] = true
            else
                a[key[1]] = math.max(-1, math.min(1, a[key[1]] + key[2]))
            end
        end
    end
    return a
end

local missing
-- What was measured of the texts, one frame late (the window's size is given before its texts can be measured):
-- `fitted` the width for the language and scale it was measured at (w nil: measuring failed); `help_fit` every shown
-- row's help wrapped to the body's width and the most lines one takes; `hint_fit` the hint's lines wrapped to it.
local fitted, help_fit, hint_fit

function SettingsUI.reset()
    missing = {}
    fitted, help_fit, hint_fit = nil, nil, nil
end
SettingsUI.reset()

function SettingsUI.missing()
    local list = Kit.missing()
    for name in pairs(missing) do list[#list + 1] = name end
    table.sort(list)
    return list
end

local round = Kit.round

-- The width the window takes at scale s: the measured one for the language shown and s, else WIDTH × s.
local function width_at(s)
    if fitted and fitted.w and fitted.lang == i18n.lang() and fitted.scale == s then return fitted.w end
    return WIDTH * s
end

-- x and w of the window and the display's height (nil when unknown): beside the meter on the side with more room.
local function place_x(v)
    local s = v.scale
    local mx = v.window_x
    local mw = Overlay.WIDTH * s + 2 * METER_PAD
    local gap, w = GAP * s, width_at(s)
    local dw, dh = Kit.display_size(missing)
    if not dw then return round(mx + mw + gap), round(w), nil end
    local right = dw - (mx + mw) - gap - EDGE
    local left = mx - gap - EDGE
    w = math.max(1, math.min(w, math.max(right, left, MIN_W * s), dw - 2 * EDGE))
    local x = right >= left and mx + mw + gap or mx - gap - w
    x = math.max(EDGE, math.min(x, dw - EDGE - w))
    return round(x), round(w), dh
end

-- The hint's lines (one per "\n").
local function lines_of(text)
    local list = {}
    for line in (tostring(text) .. "\n"):gmatch("(.-)\n") do list[#list + 1] = line end
    return list
end

-- `text` in lines at most w wide at px, broken between words (a word wider than w alone, cut with "..").
local function wrap(k, text, w, px)
    local lines, line = {}, nil
    for word in text:gmatch("%S+") do
        local try = line and (line .. " " .. word) or word
        if line and k:width(try, px) > w then
            lines[#lines + 1] = line
            line = word
        else
            line = try
        end
    end
    lines[#lines + 1] = line
    for i, l in ipairs(lines) do lines[i] = k:fit(l, w, px) end
    return lines
end

-- The width the rows ask for at the kit's scale: the widest of each row's label and widest value (a choice or a
-- number between its ‹ ›, a switch, a key with its prompt too, a table row's two cells), the gaps and the margins;
-- within FIT_MIN..FIT_MAX × scale. Every row counts, shown or not, so that no setting changes the width.
local function rows_width(k)
    local s = k.scale
    local pad, btn, cw = PAD * s, ARROW_W * s, CELL_W * s
    local widest = 0
    for _, row in ipairs(SettingsView.texts(i18n)) do
        local value = 0
        for _, text in ipairs(row.values) do value = math.max(value, k:width(text)) end
        local need
        if row.kind == "pair" then
            need = 2 * cw + 2 * pad
        elseif row.kind == "choice" or row.kind == "number" then
            need = value + 2 * btn + 2 * pad
        else
            if row.kind == "key" then value = math.max(value, k:width(i18n.t("press_a_key"))) end
            need = value + 3 * pad
        end
        widest = math.max(widest, k:width(row.label) + need)
    end
    local w = widest + 2 * MARGIN * s
    if w ~= w or w <= 0 or w == math.huge then return nil end
    return math.max(FIT_MIN * s, math.min(FIT_MAX * s, w))
end

-- Measures the width once for each language and scale (a failure counts as measured: WIDTH until either changes).
local function fit_width(k)
    local lang, s = i18n.lang(), k.scale
    if fitted and fitted.lang == lang and fitted.scale == s then return end
    local ok, w = pcall(rows_width, k)
    fitted = { lang = lang, scale = s, w = ok and w or nil }
end

-- The help of every shown row of model m wrapped to w at px, and the most lines one takes; again only for another
-- model, width or size.
local function fit_help(k, m, w, px)
    if help_fit and help_fit.model == m and help_fit.w == w and help_fit.px == px then return help_fit end
    local fit = { model = m, w = w, px = px, lines = {}, n = 1 }
    for _, g in ipairs(m.groups) do
        for _, row in ipairs(g.rows) do
            local lines = wrap(k, row.help, w, px)
            fit.lines[row.index] = lines
            fit.n = math.max(fit.n, #lines)
        end
    end
    help_fit = fit
    return fit
end

-- The hint's lines, each wrapped to w at px; again only for another hint, width or size.
local function fit_hint(k, text, w, px)
    if hint_fit and hint_fit.text == text and hint_fit.w == w and hint_fit.px == px then return hint_fit end
    local lines = {}
    for _, line in ipairs(lines_of(text)) do
        for _, part in ipairs(wrap(k, line, w, px)) do lines[#lines + 1] = part end
    end
    hint_fit = { text = text, w = w, px = px, lines = lines }
    return hint_fit
end

-- A table row's content: its label at the left, at the right its two cells (a switch's value, or a dim «—» where the
-- window has no such section); selected, the cell `col` lighter still with a bronze line under it. A click on a cell
-- selects it and flips its switch; on the label it only selects the row.
local function draw_pair(k, row, selected, col, x, y, w)
    local s = k.scale
    local h, pad, cw = ROW_H * s, PAD * s, CELL_W * s
    local a = k.actions
    local cells_x = x + w - 2 * cw
    local ty = y + (h - k.px) / 2
    col = col == 2 and 2 or 1
    if not row.cells[col] then col = 3 - col end
    if k:button("##dd2dm_srow:" .. row.key, x, y, math.max(1, cells_x - x), h) then a.select = row.index end
    for c = 1, 2 do
        local cell, cx = row.cells[c], cells_x + (c - 1) * cw
        local text, color = DASH, C.dim
        if cell then
            if selected and c == col then
                k:rect(cx, y, cx + cw, y + h, C.selected)
                k:rect(cx, y + h - math.max(1, round(CELL_MARK * s)), cx + cw, y + h, C.bronze)
            end
            if k:button("##dd2dm_srow:" .. cell.key, cx, y, cw, h) then
                a.select, a.col, a.activate = row.index, c, true
            end
            text, color = cell.value, cell.on and C.ok or C.dim
        end
        k:text(cx + (cw - k:width(text)) / 2, ty, color, text)
    end
    k:text(x + pad, ty, C.text, k:fit(row.label, cells_x - x - 2 * pad))
end

-- The table's line of column names, over its cells.
local function columns_line(k, columns, x, y, w)
    local s = k.scale
    local cw, px = CELL_W * s, SMALL_PX * s
    local cells_x = x + w - 2 * cw
    for c, name in ipairs(columns) do
        local text = k:fit(name, cw, px)
        k:text(cells_x + (c - 1) * cw + (cw - k:width(text, px)) / 2, y + (COLS_H * s - px) / 2, C.dim, text, px)
    end
end

-- One row at (x, y), `w` wide: the selection's light and mark, the label at the left, the value at the right (the
-- key prompt while it waits; ‹ › around a choice or a number), and its buttons; a table row's cells (col: the
-- selected one).
local function draw_row(k, row, selected, col, waiting, x, y, w)
    local s = k.scale
    local h, pad = ROW_H * s, PAD * s
    local a = k.actions
    if selected then
        k:rect(x, y, x + w, y + h, C.selected)
        k:rect(x, y, x + math.max(1, round(SEL_MARK * s)), y + h, C.bronze)
    end
    if row.kind == "pair" then return draw_pair(k, row, selected, col, x, y, w) end
    local value, color = row.value, C.text
    if waiting == row.key then
        value, color = i18n.t("press_a_key"), C.bronze
    elseif row.kind == "switch" then
        color = row.on and C.ok or C.dim
    end
    local ty = y + (h - k.px) / 2
    local vw = k:width(value)
    local right = x + w - pad
    if row.kind == "choice" or row.kind == "number" then
        local btn = ARROW_W * s
        local next_x = x + w - btn
        local value_x = next_x - vw
        local prev_x = value_x - btn
        if k:button("##dd2dm_srow:" .. row.key, x, y, math.max(1, prev_x - x), h) then a.select = row.index end
        if k:glyph("##dd2dm_sprev:" .. row.key, "‹", prev_x, y, btn, h) then a.select, a.step = row.index, -1 end
        if k:glyph("##dd2dm_snext:" .. row.key, "›", next_x, y, btn, h) then a.select, a.step = row.index, 1 end
        k:text(value_x, ty, color, value)
        right = prev_x
    else
        if k:button("##dd2dm_srow:" .. row.key, x, y, w, h) then a.select, a.activate = row.index, true end
        right = right - vw
        k:text(right, ty, color, value)
    end
    k:text(x + pad, ty, C.text, k:fit(row.label, right - x - 2 * pad))
end

-- The body: each group's heading (and a table's line of column names) together with its first row (so a heading
-- never ends a page alone), then its other rows; a table row that starts a page has the column names over it again.
-- Returns the page of the selected row, and that row.
local function lay_out(k, m, state)
    local s = k.scale
    local band_h, row_h, cols_h = BAND_H * s, ROW_H * s, COLS_H * s
    local sel, col, waiting = state.sel, state.col, state.waiting
    local sel_page, sel_row
    for _, g in ipairs(m.groups) do
        local head_h = band_h + (g.columns and cols_h or 0)
        for j, row in ipairs(g.rows) do
            local first = j == 1
            local again = not first and g.columns and row.kind == "pair" and not k:fits(row_h)
            local h = first and head_h + row_h or again and cols_h + row_h or row_h
            local page = k:unit(h, function(x, y, w)
                if first then
                    k:sub({ x = x, y = y, w = w, h = math.huge, page = 1 }):band("damage", g.heading)
                    y = y + band_h
                end
                if (first or again) and g.columns then
                    columns_line(k, g.columns, x, y, w)
                    y = y + cols_h
                end
                draw_row(k, row, row.index == sel, col, waiting, x, y, w)
            end)
            if row.index == sel then sel_page, sel_row = page, row end
        end
    end
    return sel_page, sel_row
end

-- The title at the left; at the right, with the menu open, × (close), and the page when there is more than one.
local function title_line(k, title, page, pages, x, y, w)
    local s = k.scale
    local hh, btn = HEAD_H * s, BTN_W * s
    local right = x + w
    if k.interactive then
        right = right - btn
        if k:glyph("##dd2dm_sclose", "×", right, y, btn, hh) then k.actions.close = true end
        right = right - PAD * s
    end
    if pages > 1 then
        local small = SMALL_PX * s
        local text = i18n.t("jpage", page, pages)
        right = right - k:width(text, small)
        k:text(right, y + (hh - small) / 2, C.dim, text, small)
        right = right - PAD * s
    end
    local px = TITLE_PX * s
    k:text(x, y + (hh - px) / 2, C.text, k:fit(title, right - x, px), px)
end

-- Where the window goes and what fits in it: x, y, w, h, the lines the help and the hint take (as measured last, see
-- fill), the body's width and whether every row fits (else the body pages). The body is as tall as its rows, the
-- window at most what the display allows; the help is as high as the longest help of any row, so that the window
-- keeps its height whichever row is selected.
local function measure(state, v)
    local s = v.scale
    local m = state.model
    local L = { line = math.max(1, round(s)) }
    L.help_n = help_fit and help_fit.n or HELP_LINES
    L.hint_n = hint_fit and hint_fit.text == m.hint and #hint_fit.lines or #lines_of(m.hint)
    local dh
    L.x, L.w, dh = place_x(v)
    L.bw = L.w - 2 * MARGIN * s
    local count = Kit.new({ x = 0, y = 0, w = L.bw, h = math.huge, scale = s, page = 0 })
    lay_out(count, m, state)
    local fixed = (TOP + HEAD_H + BODY_TOP + BODY_GAP + HELP_TOP + L.help_n * HINT_LINE + HELP_GAP
        + L.hint_n * HINT_LINE + BOTTOM) * s + 2 * L.line
    local content = fixed + count:height()
    local room = (dh or FALLBACK_H) - 2 * EDGE
    L.fits = content <= room
    L.h = L.fits and math.ceil(content) or math.max(1, math.floor(room))
    local y = v.window_y
    if dh then y = math.max(EDGE, math.min(y, dh - EDGE - L.h)) end
    L.y = round(y)
    return L
end

-- The window's content in the kit k (frame: a kit on the background list): the title line, the bronze line, the page
-- of the body that holds the selection, the thin line and the selected row's help, the hint (both wrapped to the
-- body's width). First what has to be measured, once: the width for the next frames, the help's and the hint's lines
-- (drawn now; their heights count from the next frame, until then at most the lines that L has room for are drawn).
local function fill(k, frame, state, L)
    local s = k.scale
    local m = state.model
    local hpx = SMALL_PX * s
    fit_width(k)
    local help = fit_help(k, m, L.bw, hpx)
    local hint = fit_hint(k, m.hint, L.bw, hpx)
    local x = k.x + MARGIN * s
    local head_y = k.y + TOP * s
    local y = head_y + HEAD_H * s
    frame:rect(k.x + 1, y, k.x + k.w - 1, y + L.line, C.bronze)
    y = y + L.line + BODY_TOP * s
    local hint_y = k.y + k.h - (BOTTOM + L.hint_n * HINT_LINE) * s
    local help_y = hint_y - (HELP_GAP + L.help_n * HINT_LINE) * s
    local rule_y = help_y - HELP_TOP * s - L.line
    local body_h = L.fits and math.huge or math.max(1, rule_y - BODY_GAP * s - y)
    -- which page holds the selection, then that page
    local pass = k:sub({ x = x, y = y, w = L.bw, h = body_h, page = 0 })
    local page, row = lay_out(pass, m, state)
    title_line(k, m.title, page or 1, pass:pages(), x, head_y, L.bw)
    lay_out(k:sub({ x = x, y = y, w = L.bw, h = body_h, page = page or 1 }), m, state)

    frame:rect(x, rule_y, x + L.bw, rule_y + L.line, C.border)
    local lines = row and help.lines[row.index] or {}
    for i = 1, math.min(#lines, L.help_n) do
        local ly = help_y + (i - 1) * HINT_LINE * s
        k:text(x, ly + (HINT_LINE * s - hpx) / 2, C.mid, lines[i], hpx)
    end
    for i = 1, math.min(#hint.lines, L.hint_n) do
        local ly = hint_y + (i - 1) * HINT_LINE * s
        k:text(x, ly + (HINT_LINE * s - hpx) / 2, C.dim, hint.lines[i], hpx)
    end
end

function SettingsUI.draw(state, settings)
    local actions = new_actions()
    local L
    local err = Kit.panel({
        name = "DD2DamageMeter settings", missing = missing, actions = actions,
        place = function()
            L = measure(state, settings.values)
            return L.x, L.y, L.w, L.h, settings.values.scale
        end,
        fill = function(k, frame) fill(k, frame, state, L) end,
    })
    return actions, err
end

return SettingsUI
