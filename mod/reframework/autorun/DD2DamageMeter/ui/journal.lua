-- The journal window: a dark panel centred near the top of the screen with the tabs, the fight's line, the five
-- numbers, the current tab's body (paged) and a hint line, drawn with REFramework's imgui from the models of
-- journal.lua and view.lua (and journal_tabs.lua for the other tabs). No game logic and no texts of its own.
-- The window is WIDTH_EM base font sizes wide (at most the display minus EDGE_ROOM), centred; its top edge stays where
-- the largest window's would be (SHARE of the display's height, centred), so the tabs never move; its height is that
-- of what it held the frame before (one frame late), at least the header's and the hint's, at most the largest
-- window's, beyond which the body pages.
-- The mouse works while the REFramework menu is open (the buttons exist only then); without it the window is only a
-- picture and the journal follows its keys (JournalUI.KEYS), which the game receives too.
--
-- JournalUI.draw(state, settings) -> actions, err
--   state   = { tab, header = Journal.header(...), body = the tab's model|nil (nil: the header only), page, hint }
--             body: summary View.summary(snap, ctx), enemies Journal.enemies(snap, ctx, sel), the other tabs their
--             drawer's model (ui/journal_tabs.lua); a tab without a drawer says no_data
--   actions = { tab = id|nil, tab_step = -1|0|1, history = -1|0|1, select = integer|nil, select_step = -1|0|1,
--               page = -1|0|1, close = boolean, pages = integer (the pages the body took, at least 1) }
--   err     = nil, or the message of an error caught while drawing. draw never raises: whatever it had started
--             (window, font sizes, colour) is ended again, and the actions gathered up to the failure are returned.
-- Button ids: "jtab:<tab id>" (tab), "jhist_prev"/"jhist_next" (history -1/+1), "jclose" (close),
-- "jpage_prev"/"jpage_next" (page -1/+1), "jrow:<index>" (select).
-- JournalUI.KEYS = { [vk] = { action field, step } }; JournalUI.key_actions(pressed: table<vk, true>) -> actions
--   (the same fields without pages; two keys of one field add up, at most 1 either way)
-- JournalUI.missing() -> { name }: the imgui calls found missing (get_display_size, set_next_window_size, and the
--   kit's gradient), in order; JournalUI.reset() forgets them, what was measured and the window's height.
local i18n = require("DD2DamageMeter/i18n")
local Journal = require("DD2DamageMeter/journal")
local Kit = require("DD2DamageMeter/ui/kit")
local Tabs = require("DD2DamageMeter/ui/journal_tabs")

local JournalUI = {}

-- The window: WIDTH_EM times the base font size (Kit.FONT_SIZE) wide, 1 120 px at scale 1; the largest one SHARE of
-- the display's height; each at most the display minus EDGE_ROOM. The display's size when it cannot be read:
-- FALLBACK_W x _H.
local WIDTH_EM = 80
local SHARE, EDGE_ROOM = 0.85, 32
local FALLBACK_W, FALLBACK_H = 1280, 720

-- Sizes in pixels at scale 1.
local LINE_PX, TITLE_PX, SMALL_PX, SUB_PX, VALUE_PX = 17, 16, 12, 13, 22
local MARGIN = 10
local TAB_TOP, TAB_H = 6, Kit.BUTTON_ROW_H
local HEAD_H, BTN_W, GAP, PAGER_GAP = 32, 24, 8, 12
-- a number card: its label's lines from the top, its value on the bottom
local CARD_GAP, CARD_PAD, CARD_TOP, LABEL_LINE, VALUE_GAP, CARD_BOTTOM = 6, 8, 6, 14, 4, 6
local BODY_GAP, BODY_TOP = 8, 6 -- above and under the line over the body
local PAGER_H, HINT_H, BOTTOM = 22, 22, 4
local ROW_H = Kit.ROW_H
local SKILL_INDENT = 24 -- a skill row's text: 16 px further in than its fighter's
-- the Summary tab
local SPLIT, COLUMN_GAP, SUMMARY_ROW_H = 0.56, 20, 28
-- the Enemies tab: the list (LIST_ROWS rows a page, whichever row is selected), the main column
local LIST_W, LIST_GAP, LIST_TITLE_H, LIST_ROW_H, LIST_PAGE_H, LIST_ROWS = 130, 12, 24, 40, 18, 6
local LIST_PAD, MEMBER_INDENT, LIST_BAR_H, SEL_MARK = 6, 10, 3, 3
local CARD_TITLE_H, TWO_COLUMNS, INDIVIDUAL_W = 26, 600, 280
local VALUE_W = 80
-- Columns as { share of the row's width, least px }. The least widths are for a row *_REF px wide times the scale
-- and shrink in proportion in a narrower one: the type rows (label, multiplier, word, damage; the bar takes the rest)
-- fit a column of the narrowest two-column main column, the who table's number columns (hits, damage, share,
-- average, max, multiplier) a row WHO_REF wide.
local TYPE_COLUMNS = { { 0.15, 72 }, { 0.075, 34 }, { 0.18, 64 }, { 0.12, 50 } }
local TYPE_REF = (TWO_COLUMNS - COLUMN_GAP) / 2
local WHO_COLUMNS = { { 0.06, 52 }, { 0.09, 72 }, { 0.06, 48 }, { 0.08, 66 }, { 0.08, 66 }, { 0.07, 52 } }
local WHO_REF = 700

local C = Kit.COLORS
local EFF_COLOR = { effective = C.ok, resist = C.bad, invalid = C.bad }

JournalUI.KEYS = {
    [0x21] = { "tab_step", -1 }, [0x22] = { "tab_step", 1 },     -- PgUp / PgDn: tabs
    [0x24] = { "history", -1 }, [0x23] = { "history", 1 },      -- Home / End: newer / older fight
    [0x26] = { "select_step", -1 }, [0x28] = { "select_step", 1 }, -- Up / Down: selection
    [0x25] = { "page", -1 }, [0x27] = { "page", 1 },             -- Left / Right: pages
}

local function new_actions()
    return { tab = nil, tab_step = 0, history = 0, select = nil, select_step = 0, page = 0, close = false }
end

function JournalUI.key_actions(pressed)
    local a = new_actions()
    for vk, down in pairs(pressed or {}) do
        local key = JournalUI.KEYS[vk]
        if key and down then a[key[1]] = math.max(-1, math.min(1, a[key[1]] + key[2])) end
    end
    return a
end

-- imgui calls found missing (not tried again until reset), the pages each body took when last drawn (weak keys, so a
-- body that is gone takes its count with it) and the height the window's content took in the last frame.
local missing
local last_pages
local last_h

function JournalUI.reset()
    missing = {}
    last_pages = setmetatable({}, { __mode = "k" })
    last_h = nil
    Kit.reset()
end
JournalUI.reset()

function JournalUI.missing()
    local list = Kit.missing()
    for name in pairs(missing) do list[#list + 1] = name end
    table.sort(list)
    return list
end

local round = Kit.round

-- The height of a number card whose labels take `lines` lines, at scale 1.
local function card_h(lines)
    return CARD_TOP + lines * LABEL_LINE + VALUE_GAP + VALUE_PX + CARD_BOTTOM
end

-- The least height of the window: the tabs, the fight's line, the numbers (labels of one line) and the hint.
local function least_h(s)
    return math.ceil((TAB_TOP + TAB_H + HEAD_H + card_h(1) + BODY_GAP + BODY_TOP + HINT_H + BOTTOM) * s
        + math.max(1, round(s)) + 1)
end

-- x, y, w, h of the window and the height of the largest one.
local function geometry(s)
    local dw, dh = Kit.display_size(missing)
    if not dw then dw, dh = FALLBACK_W, FALLBACK_H end
    local w = math.max(1, math.min(round(WIDTH_EM * Kit.FONT_SIZE * s), round(dw - EDGE_ROOM)))
    local max_h = math.max(1, math.min(round(dh * SHARE), round(dh - EDGE_ROOM)))
    local h = math.max(1, math.min(max_h, math.max(least_h(s), last_h or max_h)))
    return round((dw - w) / 2), round((dh - max_h) / 2), w, h, max_h
end

-- The non-empty parts joined: "73 800 · 99%".
local function join(...)
    local parts = {}
    for i = 1, select("#", ...) do
        local part = select(i, ...)
        if part and part ~= "" then parts[#parts + 1] = part end
    end
    return table.concat(parts, " · ")
end

-- `text` as spans in `color`, the last `who.name` in it in his colour (who = { name, kind, job, shade }).
local function with_name(text, who, color)
    local name = type(who) == "table" and who.name
    if type(name) ~= "string" or name == "" then return { { text, color } } end
    local at, from = nil, 1
    while true do
        local i, j = text:find(name, from, true)
        if not i then break end
        at, from = i, j + 1
    end
    if not at then return { { text, color } } end
    local after = at + #name
    return { { text:sub(1, at - 1), color }, { name, Kit.actor_text(who.kind, who.job, who.shade) },
             { text:sub(after), color } }
end

-- The colour of a multiplier as shown: above ×1,0 good, below it bad, ×1,0 (or none) plain.
local function mult_color(r)
    local v = r.mult_value
    if type(v) == "number" then
        if v > 1 then return C.ok end
        if v < 1 then return C.bad end
    end
    return C.mid
end

-- The tab row: every tab, the current one on a lighter ground with a bronze edge; squeezed to fit when too wide.
local function tab_row(k, current, x, y, w)
    local titles, ids, on = {}, {}, nil
    for i, id in ipairs(Journal.TABS) do
        titles[i], ids[i] = i18n.t("jtab_" .. id), "jtab:" .. id
        if id == current then on = i end
    end
    local clicked = k:button_row(titles, ids, on, x, y, w)
    if clicked then k.actions.tab = Journal.TABS[clicked] end
end

-- The fight's line at the left, ‹ fight › (the history) PAGER_GAP after it and, with the menu open, × (close) at the
-- right edge.
local function header_line(k, h, x, y, w)
    local s = k.scale
    local hh, btn = HEAD_H * s, BTN_W * s
    local right = x + w
    if k.interactive then
        right = right - btn
        if k:glyph("jclose", "×", right, y, btn, hh) then k.actions.close = true end
        right = right - GAP * s
    end
    local px = LINE_PX * s
    -- the glyph boxes are wider than their glyphs: the gap is measured to the glyph
    local inset = h.fight and (btn - k:width("‹")) / 2 or 0
    local pager_w = h.fight and (PAGER_GAP * s - inset + 2 * btn + k:width(h.fight)) or 0
    local line = k:fit(h.line, math.max(0, right - x - pager_w), px)
    k:text(x, y + (hh - px) / 2, C.text, line, px)
    if h.fight then
        local bx = x + k:width(line, px) + PAGER_GAP * s - inset
        if k:glyph("jhist_prev", "‹", bx, y, btn, hh) then k.actions.history = -1 end
        bx = bx + btn
        k:text(bx, y + (hh - k.px) / 2, C.dim, h.fight)
        bx = bx + k:width(h.fight)
        if k:glyph("jhist_next", "›", bx, y, btn, hh) then k.actions.history = 1 end
    end
end

-- The number cards side by side: the label dim (up to two lines), the value large in its block's title colour, every
-- value on one line at the bottom of its card. Returns their height.
local function number_cards(k, list, x, y, w)
    local n = #list
    if n == 0 then return 0 end
    local s = k.scale
    local gap, pad = CARD_GAP * s, CARD_PAD * s
    local lpx, vpx = SMALL_PX * s, VALUE_PX * s
    local cw = (w - gap * (n - 1)) / n
    local labels, lines = {}, 1
    for i, num in ipairs(list) do
        labels[i] = k:wrap2(num.label, cw - 2 * pad, lpx)
        lines = math.max(lines, #labels[i])
    end
    local ch = card_h(lines) * s
    for i, num in ipairs(list) do
        local cx = x + (i - 1) * (cw + gap)
        k:rect(cx, y, cx + cw, y + ch, C.card)
        k:rect(cx, y + ch - 1, cx + cw, y + ch, C.border)
        for j, line in ipairs(labels[i]) do
            local ly = y + (CARD_TOP + (j - 1) * LABEL_LINE) * s + (LABEL_LINE * s - lpx) / 2
            k:text(cx + pad, ly, C.dim, line, lpx)
        end
        local colors = num.block and C.block[num.block]
        k:text(cx + pad, y + ch - CARD_BOTTOM * s - vpx, colors and colors.title or C.text,
            k:fit(num.value, cw - 2 * pad, vpx), vpx)
    end
    return ch
end

-- ‹ page p of n › at the right end of the line at (x, y), when there is more than one page.
local function pager(k, page, pages, x, y, w)
    if pages <= 1 then return end
    local s = k.scale
    local h, btn = PAGER_H * s, BTN_W * s
    local text = i18n.t("jpage", page, pages)
    local right = x + w - btn
    if k:glyph("jpage_next", "›", right, y, btn, h) then k.actions.page = 1 end
    right = right - k:width(text)
    k:text(right, y + (h - k.px) / 2, C.dim, text)
    if k:glyph("jpage_prev", "‹", right - btn, y, btn, h) then k.actions.page = -1 end
end

-- The hint at the left and where the mouse works at the right, both in C.mid.
local function hint_line(k, hint, x, y, w)
    local s = k.scale
    local px = SMALL_PX * s
    local ty = y + (HINT_H * s - px) / 2
    local mouse = k:fit(i18n.t("journal_mouse"), w / 3, px)
    local mx = x + w - k:width(mouse, px)
    k:text(mx, ty, C.mid, mouse, px)
    if type(hint) == "string" and hint ~= "" then
        k:text(x, ty, C.mid, k:fit(hint, math.max(0, mx - GAP * s - x), px), px)
    end
end

-- Summary: a character's row filled to its share in its colour, the name (in its colour; grey rows dim) and
-- "value · share" at 16 px.
local function summary_row(k, row, grey)
    local s = k.scale
    k:unit(SUMMARY_ROW_H * s, function(x, y, w)
        local h, px, pad = SUMMARY_ROW_H * s, TITLE_PX * s, 8 * s
        k:filled(x, y, w, h, Kit.actor_color(row.kind, row.job, row.shade), row.fill)
        local numbers = join(row.value, row.share)
        local nw = k:width(numbers, px)
        local ty = y + (h - px) / 2
        local name_color = grey and C.dim or Kit.actor_text(row.kind, row.job, row.shade)
        k:text(x + pad, ty, name_color, k:fit(row.name, w - nw - 3 * pad, px), px)
        k:text(x + w - pad - nw, ty, grey and C.dim or C.text, numbers, px)
    end)
end

-- Summary: the damage and its grey rows on the left, the enemies and the armor on the right.
local function summary_tab(k, m)
    local s = k.scale
    local lw = math.floor(k.w * SPLIT)
    local gap = COLUMN_GAP * s
    local left = k:sub({ w = lw })
    local right = k:sub({ x = k.x + lw + gap, w = k.w - lw - gap })
    local grey = m.allies and m.allies.rows or {}
    if m.damage then
        left:band("damage", m.damage.title, m.damage.total)
        for _, row in ipairs(m.damage.rows) do summary_row(left, row, false) end
    elseif #grey > 0 then
        left:band("damage", i18n.t("dealt"))
    end
    for _, row in ipairs(grey) do summary_row(left, row, true) end
    if m.enemies and #m.enemies > 0 then
        right:band("enemies", i18n.t("enemies"))
        for _, e in ipairs(m.enemies) do
            right:row({ { e.label, color = e.killed and C.dim or C.enemy_label },
                { e.hp_text, w = math.min(right:width(e.hp_text), right.w / 2), align = "right", color = C.dim } })
        end
    end
    if m.armor and #m.armor > 0 then
        right:band("other", i18n.t("armor"))
        for _, a in ipairs(m.armor) do
            right:row({ { a.label }, { a.value, w = math.min(right:width(a.value), right.w / 2), align = "right" } })
        end
    end
    return math.max(left:pages(), right:pages()), math.max(left:used(), right:used())
end

-- Enemies: one row of the list, `h` high at (x, y): the name (dim once killed), the HP text under it («killed» at its
-- right) and a thin health bar; the selected row lighter with a purple mark; a kind's members indented.
local function enemy_row(k, row, i, selected, x, y, w, h)
    local s = k.scale
    local rh = h - 2 * s
    if k:button("jrow:" .. i, x, y, w, rh) then k.actions.select = i end
    if selected then
        k:rect(x, y, x + w, y + rh, C.selected)
        k:rect(x, y, x + math.max(1, round(SEL_MARK * s)), y + rh, C.enemy)
    end
    local pad, small = LIST_PAD * s, SMALL_PX * s
    local lx = x + pad + (row.member and MEMBER_INDENT * s or 0)
    local right = x + w - pad
    k:text(lx, y + 4 * s, row.killed and C.dim or C.enemy_label, k:fit(row.label, right - lx))
    local hp_right = right
    if row.killed then
        local killed = i18n.t("killed")
        local kw = k:width(killed, small)
        k:text(right - kw, y + 21 * s, C.dim, killed, small)
        hp_right = right - kw - 4 * s
    end
    k:text(lx, y + 21 * s, C.dim, k:fit(row.hp_text, hp_right - lx, small), small)
    k:bar(lx, y + 34 * s, right - lx, math.max(1, round(LIST_BAR_H * s)), C.enemy, row.fill)
end

-- Enemies: the list in (x, y, w, h), its title on every page and, when it pages, the page under its rows; the page
-- shown is the one that holds the selection.
local function enemy_list(k, list, sel, x, y, w, h)
    local s = k.scale
    local rows = list.rows
    local th, rh, ph = LIST_TITLE_H * s, LIST_ROW_H * s, LIST_PAGE_H * s
    local n = #rows
    local per = math.max(1, math.floor((h - th) / rh))
    if n > per then per = math.max(1, math.floor((h - th - ph) / rh)) end
    sel = math.max(1, math.min(math.tointeger(sel) or 1, n))
    local page = (sel - 1) // per
    local pages = math.max(1, (n + per - 1) // per)
    local pad, small = LIST_PAD * s, SMALL_PX * s
    k:text(x + pad, y + (th - k.px) / 2, C.enemy_label, k:fit(list.title, w - 2 * pad))
    for i = page * per + 1, math.min(n, (page + 1) * per) do
        enemy_row(k, rows[i], i, i == sel, x, y + th + (i - page * per - 1) * rh, w, rh)
    end
    if pages > 1 then
        local text = k:fit(i18n.t("jpage", page + 1, pages), w - 2 * pad, small)
        k:text(x + pad, y + th + per * rh + (ph - small) / 2, C.dim, text, small)
    end
end

-- The card's "What the game says": its tags and defence, or no_data. An immune list that only says no_data (the
-- statuses were not read) is that dim text, not a tag.
local function game_block(k, g)
    k:band("enemies", i18n.t("jgame_says"))
    if not g.data then
        k:row({ { i18n.t("no_data"), color = C.dim } })
        return
    end
    k:tags(i18n.t("jweak"), g.weak, "weak")
    k:tags(i18n.t("jresist"), g.resist, "resist")
    local immune, empty = g.immune, nil
    if #immune == 1 and immune[1] == i18n.t("no_data") then immune, empty = {}, immune[1] end
    k:tags(i18n.t("jimmune"), immune, "immune", empty)
    if g.defence then k:row({ { g.defence, color = C.dim } }) end
end

-- The widths of `columns` (TYPE_COLUMNS, WHO_COLUMNS) in a row as wide as the kit.
local function widths_of(k, columns, ref)
    local unit = math.min(k.scale, k.w / ref)
    local list = {}
    for i, col in ipairs(columns) do list[i] = math.max(col[1] * k.w, col[2] * unit) end
    return list
end

-- The card's "What hit it": per type its bar, the multiplier the game applied (above ×1,0 good, below it bad) and its
-- word in the scale's colour, the damage; then the head and body line.
local function types_block(k, b)
    k:band("damage", b.title)
    if b.empty then k:row({ { b.empty, color = C.dim } }) end
    local w = widths_of(k, TYPE_COLUMNS, TYPE_REF)
    for _, r in ipairs(b.rows) do
        k:row({
            { r.label, w = w[1] },
            { bar = { C.block.damage.mark, r.fill } },
            { r.mult, w = w[2], align = "right", color = mult_color(r) },
            { r.eff_text or "", w = w[3], color = EFF_COLOR[r.eff] or C.mid },
            { r.value, w = w[4], align = "right" },
        })
    end
    if b.parts then k:row({ { b.parts, color = C.dim } }) end
end

-- A row of the who table: `first` (a cell) takes what is left, the numbers right-aligned in their columns.
local function who_cells(k, first, numbers, color, px)
    first.color, first.px = first.color or color, first.px or px
    local cells = { first }
    for i, w in ipairs(widths_of(k, WHO_COLUMNS, WHO_REF)) do
        cells[i + 1] = { numbers[i], w = w, align = "right", color = color, px = px }
    end
    return cells
end

-- The card's "Who dealt what", across the body: a dim heading row; each dealer filled to its share in its colour,
-- its name in that colour (grey ones dim); its skills under it smaller and indented, the type dim, the multiplier in
-- its own column (above ×1,0 good, below it bad).
local function who_block(k, who, none)
    k:band("damage", who.title, who.total)
    if #who.rows == 0 then
        k:row({ { none, color = C.dim } })
        return
    end
    local t = i18n.t
    k:row(who_cells(k, { t("jcol_skill") }, { t("details_hits"), t("jcol_damage"), t("jcol_share"), t("jcol_avg"),
        t("details_max"), t("jcol_mult") }, C.dim))
    local s = k.scale
    local grey = false
    for _, r in ipairs(who.rows) do
        if r.kind == "who" then
            grey = r.grey == true
            local name = grey and C.dim or Kit.actor_text(r.actor_kind, r.job, r.shade)
            local first = { parts = { { r.name, name }, { r.job_label and (" · " .. r.job_label), C.dim } } }
            k:row(who_cells(k, first, { r.hits, r.value, r.share or "", "", "", "" }, grey and C.dim or C.text),
                { fill = { Kit.actor_color(r.actor_kind, r.job, r.shade), r.fill } })
        else
            local px, color = SUB_PX * s, grey and C.dim or C.mid
            local first = { parts = { { r.name or r.label, color }, { r.type_text and (" · " .. r.type_text), C.dim } } }
            local cells = who_cells(k, first, { r.hits, r.value, r.share or "", r.avg, r.max, r.mult }, color, px)
            cells[#cells].color = mult_color(r)
            k:row(cells, { indent = SKILL_INDENT * s })
        end
    end
end

-- The card's "Whom it hit", across the body: each friend filled to his share in his colour, his name in it, the
-- types dim.
local function attacks_block(k, a, none)
    k:band("enemies", a.title, a.total)
    if #a.rows == 0 then
        k:row({ { none, color = C.dim } })
        return
    end
    for _, r in ipairs(a.rows) do
        k:row({ Kit.name_cell(r), { r.value, w = VALUE_W * k.scale, align = "right" } },
            { fill = { Kit.actor_color(r.kind, r.job, r.shade), r.fill } })
    end
end

-- The height `fill(kit)` takes `w` wide (nothing is drawn).
local function height_of(k, w, fill)
    local m = k:sub({ w = w, h = math.huge, page = 0 })
    fill(m)
    return m:height()
end

-- The card's title line: the title light purple, its sub dim at the right (who finished it in his colour), as wide as
-- its pieces laid out side by side.
local function card_title(k, c)
    local s = k.scale
    local tpx, small, pad = TITLE_PX * s, SMALL_PX * s, 8 * s
    local th = CARD_TITLE_H * s
    k:unit(th, function(x, y, w)
        local sub = with_name(c.sub, c.killer, C.dim)
        local sw = math.min(k:spans_width(sub, small), w * 0.6)
        k:text(x + pad, y + (th - tpx) / 2, C.enemy_label, k:fit(c.title, w - sw - 3 * pad, tpx), tpx)
        k:spans(x + w - pad - sw, y + (th - small) / 2, sw, sub, small)
    end)
end

-- A kind's members, one line each ("0:18 · 8 000 HP · добил Alex", the killer in his colour), two side by side when
-- the column is wide enough.
local function individuals(k, list)
    if list == nil or #list == 0 then return end
    local s = k.scale
    local cols = k.w >= 2 * INDIVIDUAL_W * s and 2 or 1
    local cw, rh, px, pad = k.w / cols, ROW_H * s, SUB_PX * s, 8 * s
    for i = 1, #list, cols do
        k:unit(rh, function(x, y)
            for j = 0, cols - 1 do
                local d = list[i + j]
                if d then
                    k:spans(x + j * cw + pad, y + (rh - px) / 2, cw - 2 * pad, with_name(d.line or d.text, d.killer,
                        C.dim), px)
                end
            end
        end)
    end
end

-- The main column of the Enemies tab: the card's title line, a kind's members, then the game's block and the types
-- (side by side when the column is wide enough).
local function main_column(k, c)
    card_title(k, c)
    individuals(k, c.deaths)
    if k.w >= TWO_COLUMNS * k.scale then
        local gap = COLUMN_GAP * k.scale
        local cw = (k.w - gap) / 2
        local function game(m) game_block(m, c.game) end
        local function types(m) types_block(m, c.types) end
        k:unit(math.max(height_of(k, cw, game), height_of(k, cw, types)), function(x, y)
            game(k:sub({ x = x, y = y, w = cw, h = math.huge, page = 1 }))
            types(k:sub({ x = x + cw + gap, y = y, w = cw, h = math.huge, page = 1 }))
        end)
    else
        game_block(k, c.game)
        types_block(k, c.types)
    end
end

-- Enemies: at the top the list on the left (LIST_ROWS rows a page, and a line for its page when it has more; on page
-- 1) and the main column; under both, across the body, who dealt what and whom it hit (they page).
local function enemies_tab(k, m)
    local s = k.scale
    local lw = math.min(LIST_W * s, k.w * 0.4)
    local gap = LIST_GAP * s
    local mw = math.max(1, k.w - lw - gap)
    local c = m.card
    local n = #m.list.rows
    local list_h = math.min(k.h, (LIST_TITLE_H + math.min(n, LIST_ROWS) * LIST_ROW_H
        + (n > LIST_ROWS and LIST_PAGE_H or 0)) * s)
    if k.page == 1 then enemy_list(k, m.list, m.sel, k.x, k.y, lw, list_h) end
    local top_h = list_h
    if c then
        main_column(k:column({ x = k.x + lw + gap, w = mw }), c)
        top_h = k:pages() > 1 and k.h or math.max(list_h, k:height())
        if k:pages() == 1 and k:height() < list_h then k:unit(list_h - k:height()) end
    end
    if k.page == 1 then k:rect(k.x + lw + gap / 2, k.y, k.x + lw + gap / 2 + 1, k.y + top_h, C.border) end
    if c == nil then return 1, list_h end
    -- without the fight's detail every measured block says no_data, else an empty one says there were no hits (who
    -- dealt what: no damage, when there were hits)
    local none = c.types.empty == i18n.t("no_data") and c.types.empty or i18n.t("jno_hits")
    who_block(k, c.who, c.who.empty or none)
    attacks_block(k, c.attacks, none)
    return k:pages(), math.max(k:used(), k.page == 1 and list_h or 0)
end

local DRAWERS = { summary = summary_tab, enemies = enemies_tab }

-- The body of the current tab in the kit k; returns the pages it took and the height it used on k.page.
local function draw_body(k, state)
    local m = state.body
    if m == nil then return 1, 0 end
    local drawer = DRAWERS[state.tab] or Tabs[state.tab]
    if not drawer then
        k:row({ { i18n.t("no_data"), color = C.dim } })
        return k:pages(), k:used()
    end
    local pages, used = drawer(k, m)
    return pages or k:pages(), used or k:used()
end

-- The page to draw: state.page, at most the pages this body took when it was last drawn (a smaller window or a
-- larger scale can leave fewer).
local function page_of(state)
    local page = math.max(1, math.tointeger(state.page) or 1)
    local known = type(state.body) == "table" and last_pages[state.body]
    if known and page > known then page = known end
    return page
end

-- The journal in the window of the kit k (frame: a kit on the background list): the tabs, the bronze line, the
-- fight's line, the numbers, the body of the current tab (paged in the largest window's room, max_h high) and its
-- pager, the hint; notes the height all that took for the next frame's window.
local function fill(k, frame, state, actions, max_h)
    local s = k.scale
    local wx, wy, ww = k.x, k.y, k.w
    local x, w = wx + MARGIN * s, ww - 2 * MARGIN * s
    local y = wy + TAB_TOP * s
    tab_row(k, state.tab, x, y, w)
    y = y + TAB_H * s
    local line = math.max(1, round(s))
    frame:rect(wx + 1, y, wx + ww - 1, y + line, C.bronze)
    y = y + line
    local h = state.header or {}
    header_line(k, h, x, y, w)
    y = y + HEAD_H * s
    local ch = number_cards(k, h.numbers or {}, x, y, w)
    if ch > 0 then y = y + ch + BODY_GAP * s end
    k:rect(x, y, x + w, y + 1, C.border)
    y = y + BODY_TOP * s

    local foot = (HINT_H + BOTTOM) * s
    local room = math.max(1, wy + max_h - PAGER_H * s - foot - y)
    local page = page_of(state)
    local body = k:sub({ x = x, y = y, w = w, h = room, page = page })
    local pages, used = draw_body(body, state)
    pages = math.max(1, math.tointeger(pages) or 1)
    actions.pages = pages
    if type(state.body) == "table" then last_pages[state.body] = pages end
    -- a page before the last is as tall as the room, so its pager stays where it is
    if page < pages then used = room end
    y = y + math.max(0, math.min(room, tonumber(used) or room))
    if pages > 1 then
        pager(k, math.min(page, pages), pages, x, y, w)
        y = y + PAGER_H * s
    end
    -- a short body: the hint still at the bottom of the least window
    y = math.max(y, wy + least_h(s) - foot)
    hint_line(k, state.hint, x, y, w)
    last_h = math.ceil(y + foot - wy)
end

function JournalUI.draw(state, settings)
    local actions = new_actions()
    actions.pages = 1
    local max_h
    local err = Kit.panel({
        name = "DD2DamageMeter journal", missing = missing, actions = actions,
        place = function()
            local scale = settings.values.scale
            local x, y, w, h
            x, y, w, h, max_h = geometry(scale)
            return x, y, w, h, scale
        end,
        fill = function(k, frame) fill(k, frame, state, actions, max_h) end,
    })
    return actions, err
end

return JournalUI
