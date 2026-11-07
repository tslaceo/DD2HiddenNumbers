-- The journal's tab drawers besides Summary and Enemies (ui/journal.lua draws those):
--   tab id -> drawer(k, model) -> pages, used
-- k is a Kit over the tab's body (ui/kit.lua), model the tab's model (journal_tabs.lua); a drawer returns the pages
-- its body took and the height it used on k.page. Filled by the Skills, Chart, Damage to party, Healing and Record
-- tabs. A row's share is filled behind it in the colour of whom it is about (k:filled), a fighter's name in his
-- colour (Kit.actor_text).
--   skills  the choices as a row of buttons like the tabs, the heading row and the skill rows (who in his colour),
--           each filled in the member's colour; the choices and the heading on every page
--   chart   a column per party member, its parts stacked bottom-up 2 px apart in shades of his colour (the largest
--           his colour a little darker, each next one lighter, the rest the darkest; a part tall enough names its
--           skill (wrapped onto two lines when taller) and value), the total above it and the name under it in his
--           colour (the selected one on a lighter ground); right next to the columns the selected member's band and
--           his skills, each with its part's swatch (paged)
--   party   per member his row (name in his colour, HP lost) filled in his colour to his share of the biggest loss;
--           under it, 16 px further in, his armor line dim and what hit him filled in its colour
--   heal    per healer a band in his colour (name, total), his rows "→ <target in his colour> · <source>" with how
--           many times (dim) and the amount, filled in the healer's colour
--   record  the dropped line (dim) and the heading on every page, then a row per event: a heal's amount light green,
--           a kill marked after what did it
-- Buttons (only while interactive): "jchoice:<index>" and "jbar:<index>", both set actions.select.
local i18n = require("DD2DamageMeter/i18n")
local Kit = require("DD2DamageMeter/ui/kit")

local Tabs = {}

local C = Kit.COLORS

-- Sizes in pixels at scale 1.
local ROW_H, INDENT = Kit.ROW_H, 8               -- as the kit's rows
local SUB_PX, SMALL_PX = 13, 12                   -- a skill row under its fighter's band; a column part's texts
local SUB_INDENT = 24                             -- a row under its member's row: 16 px further in
local MEMBER_GAP = 4                              -- over a member's row, as over a band
local HEAD_GAP = 6                                -- between the choices and the heading
-- Table columns as { share of the row's width, least px }; the least widths are for a row COLUMNS_REF px wide times
-- the scale and shrink in proportion in a narrower one. Skills: the columns after the skill's label.
local WHO_COLUMN = { 0.12, 110 }
local NUMBER_COLUMNS = { { 0.06, 52 }, { 0.09, 76 }, { 0.08, 70 }, { 0.08, 70 }, { 0.07, 60 }, { 0.05, 44 } }
local COLUMNS_REF = 900
-- Chart: the columns (at most COL_H high, less when the body has less room), the total's line above them and the
-- name's under them, PART_GAP of panel between two parts of a column, a part's texts (its name, its value) when it is
-- SEG_TEXT_H high, its name on two lines when it is SEG_WRAP_H high; the list right next to the columns, at most
-- SIDE_W wide, the columns squeezed when it would get less than SIDE_MIN
local COL_W, COL_GAP, COL_H = 112, 12, 220
local TOTAL_H, NAME_H = 20, 20
local PART_GAP = 2
local SEG_TEXT_H, SEG_WRAP_H, SEG_PAD, SEG_LINE_GAP = 34, 48, 4, 2
local SIDE_W, SIDE_MIN, SIDE_GAP = 440, 200, 24
local SQUARE, SQUARE_X, SQUARE_GAP = 10, 16, 6
-- a part's shade of its member's colour (Kit.tint) by its size, lighter up the column: the largest a little darker
-- than the colour, each next one lighter; the rest (journal_tabs.lua's REST) REST_DIM of the way to the panel, the
-- darkest
local PART_TINT = { -0.08, 0.16, 0.34, 0.5 }
local REST_DIM = 0.55
-- Damage to party and Healing: the number columns at the right of a row
local COUNT_COLUMN, VALUE_COLUMN = { 0.07, 64 }, { 0.08, 70 }
-- Record: time, who, whom, what (false: the rest), amount; time and amount at least as wide as their heading and as
-- RECORD_WIDEST, a long value of theirs
local RECORD_COLUMNS = { { 0.05, 44 }, { 0.14, 110 }, { 0.14, 110 }, false, { 0.08, 70 } }
local RECORD_WIDEST = { "00:00", false, false, false, "+00 000" }
local HEAL_TEXT = C.block.heal.title              -- a heal's amount in the record

-- A part's colour: shade i of its member's colour `base`.
local function part_color(base, i)
    local t = PART_TINT[i]
    return t and Kit.tint(base, t) or Kit.mix(base, C.panel, REST_DIM)
end

-- The heights of a column's parts (bottom-up, `total` their values' sum) in a column h high with `gap` between two:
-- the gaps come out of the parts, so parts and gaps stay h high together. A part keeps at least 1 px and the others
-- share what is left in proportion; a column too short for that narrows its gaps. -> heights, gap
local function part_heights(parts, total, h, gap)
    local n, heights = #parts, {}
    if h <= 0 or total <= 0 then
        for i = 1, n do heights[i] = 0 end
        return heights, 0
    end
    gap = n > 1 and math.max(0, math.min(gap, (h - n) / (n - 1))) or 0
    -- held: the parts at 1 px; room and value: what the others share
    local held, room, value = {}, h - (n - 1) * gap, total
    repeat
        local again = false
        for i, p in ipairs(parts) do
            if not held[i] and room * p.value < value then
                held[i], room, value, again = true, room - 1, value - p.value, true
            end
        end
    until not again
    for i, p in ipairs(parts) do heights[i] = held[i] and 1 or room * p.value / value end
    return heights, gap
end

-- The band of a character (a model entry with kind, job, shade): its mark in his colour, the title in his name's.
local function fighter_band(k, who, title, total)
    k:band({ mark = Kit.actor_color(who.kind, who.job, who.shade), title = Kit.actor_text(who.kind, who.job, who.shade) },
        title, total)
end

-- The width of a column { share of the row's width, least px } in a row as wide as the kit.
local function column_w(k, col)
    return math.max(col[1] * k.w, col[2] * math.min(k.scale, k.w / COLUMNS_REF))
end

-- The choices of the Skills tab at (x, y), `w` wide, in the tabs' look (k:button_row), the selected one marked.
local function choice_row(k, choices, sel, x, y, w)
    local names, ids = {}, {}
    for i, c in ipairs(choices) do names[i], ids[i] = c.name, "jchoice:" .. i end
    local clicked = k:button_row(names, ids, sel, x, y, w)
    if clicked then k.actions.select = clicked end
end

-- A row of the skills table: the label takes what is left, `who` (group mode only) a column of its own in
-- `who_color`, the numbers right-aligned in theirs.
local function skill_cells(k, label, who, numbers, color, who_color)
    local cells = { { label, color = color } }
    if who then cells[2] = { who, w = column_w(k, WHO_COLUMN), color = who_color or color } end
    for i, col in ipairs(NUMBER_COLUMNS) do
        cells[#cells + 1] = { numbers[i], w = column_w(k, col), align = "right", color = color }
    end
    return cells
end

function Tabs.skills(k, m)
    local s = k.scale
    choice_row(k, m.choices, m.sel, k.x, k.y, k.w)
    local top, rh = (Kit.BUTTON_ROW_H + HEAD_GAP) * s, ROW_H * s
    local t = i18n.t
    -- the heading: a kit of its own on page 1, so it is drawn on every page
    local head = k:sub({ y = k.y + top, h = rh, page = 1 })
    head:row(skill_cells(head, t("jcol_skill_only"), m.group and t("jcol_who") or nil,
        { t("details_hits"), t("jcol_damage"), t("jcol_avg"), t("details_max"), t("jcol_dps"), "%" }, C.dim))
    local body = k:sub({ y = k.y + top + rh, h = math.max(1, k.h - top - rh) })
    if #m.rows == 0 then body:row({ { t("jno_hits"), color = C.dim } }) end
    for _, r in ipairs(m.rows) do
        body:row(skill_cells(body, r.label, m.group and (r.who or "") or nil,
            { r.hits, r.value, r.avg, r.max, r.dps, r.share }, C.text, Kit.actor_text(r.kind, r.job, r.shade)),
            { fill = { Kit.actor_color(r.kind, r.job, r.shade), r.fill } })
    end
    return body:pages(), top + rh + body:used()
end

-- A line of the chart's list, a skill row under its member's band: a colour square, the label and `value` at the
-- right, one step smaller than the base size and in C.mid.
local function swatch_row(k, color, label, value)
    local s = k.scale
    k:unit(ROW_H * s, function(x, y, w)
        local h, sq, px, pad = ROW_H * s, SQUARE * s, SUB_PX * s, INDENT * s
        local sx, sy = x + SQUARE_X * s, y + (h - sq) / 2
        k:rect(sx, sy, sx + sq, sy + sq, color)
        local ty = y + (h - px) / 2
        local lx = sx + sq + SQUARE_GAP * s
        local right = x + w - pad
        value = k:fit(value, (right - lx) / 2, px)
        local vw = k:width(value, px)
        k:text(right - vw, ty, C.mid, value, px)
        k:text(lx, ty, C.mid, k:fit(label, right - vw - pad - lx, px), px)
    end)
end

function Tabs.chart(k, m)
    local s = k.scale
    local bars = m.bars
    if #bars == 0 then
        k:row({ { i18n.t("jno_hits"), color = C.dim } })
        return k:pages(), k:used()
    end
    -- the columns, left-aligned; squeezed together when the list would get less than SIDE_MIN
    local n = #bars
    local bw, gap = COL_W * s, COL_GAP * s
    local need = n * bw + (n - 1) * gap
    local room = math.max(0, k.w - (SIDE_GAP + SIDE_MIN) * s)
    local f = need > room and room / need or 1
    bw, gap = bw * f, gap * f
    local area_w = n * bw + (n - 1) * gap
    local top_h, name_h = TOTAL_H * s, NAME_H * s
    local col_h = math.max(0, math.min(COL_H * s, k.h - top_h - name_h))
    local block_h = top_h + col_h + name_h
    local base = k.y + top_h + col_h
    local spx, pad = SMALL_PX * s, SEG_PAD * s
    k:rect(k.x, base, k.x + area_w, base + 1, C.border)
    for i, bar in ipairs(bars) do
        local bx = k.x + (i - 1) * (bw + gap)
        local cx0, cw = bx - gap / 2, bw + gap -- the column's box, its share of the gaps on both sides
        local on = i == m.sel
        if on then k:rect(cx0, k.y, cx0 + cw, k.y + block_h, C.selected) end
        if k:button("jbar:" .. i, cx0, k.y, cw, block_h) then k.actions.select = i end
        local main = Kit.actor_color(bar.kind, bar.job, bar.shade)
        local h = m.top > 0 and col_h * bar.value / m.top or 0
        local heights, part_gap = part_heights(bar.parts, bar.value, h, PART_GAP * s)
        local y = base
        for j, p in ipairs(bar.parts) do
            if j > 1 then y = y - part_gap end
            local ph = heights[j]
            local color = part_color(main, p.color)
            k:rect(bx, y - ph, bx + bw, y, color)
            if ph >= SEG_TEXT_H * s then
                local ink, ty, tw, line = Kit.on_color(color), y - ph + pad, bw - 2 * pad, spx + SEG_LINE_GAP * s
                local name = ph >= SEG_WRAP_H * s and k:wrap2(p.label, tw, spx) or { k:fit(p.label, tw, spx) }
                for _, text in ipairs(name) do
                    k:text(bx + pad, ty, ink, text, spx)
                    ty = ty + line
                end
                k:text(bx + pad, ty, ink, k:fit(p.text, tw, spx), spx)
            end
            y = y - ph
        end
        local total, name = k:fit(bar.total, cw), k:fit(bar.name, cw)
        k:text(bx + (bw - k:width(total)) / 2, y - top_h + (top_h - k.px) / 2, on and C.text or C.mid, total)
        k:text(bx + (bw - k:width(name)) / 2, base + (name_h - k.px) / 2, Kit.actor_text(bar.kind, bar.job, bar.shade),
            name)
    end
    -- right next to the columns: the selected member's band, then his skills in his parts' shades
    local sx = k.x + area_w + SIDE_GAP * s
    local side = k:sub({ x = sx, w = math.max(0, math.min(SIDE_W * s, k.x + k.w - sx)) })
    local chosen = bars[m.sel]
    if chosen then
        fighter_band(side, chosen, chosen.name, chosen.total)
        local main = Kit.actor_color(chosen.kind, chosen.job, chosen.shade)
        for _, e in ipairs(m.list) do swatch_row(side, part_color(main, e.color), e.label, e.value .. " · " .. e.share) end
    end
    return side:pages(), math.max(block_h, side:used())
end

function Tabs.party(k, m)
    local t = i18n.t
    if #m.members == 0 then
        k:row({ { t("jno_hits"), color = C.dim } })
        return k:pages(), k:used()
    end
    local s = k.scale
    local vw, sub = column_w(k, VALUE_COLUMN), { indent = SUB_INDENT * s }
    for _, member in ipairs(m.members) do
        k:unit(MEMBER_GAP * s)
        k:row({ Kit.name_cell(member), { member.taken, w = vw, align = "right" } },
            { fill = { Kit.actor_color(member.kind, member.job, member.shade), member.fill } })
        if member.armor then
            k:row({ { t("details_armor_saved"), color = C.dim },
                { member.armor, w = math.min(k:width(member.armor), k.w / 2), align = "right", color = C.dim } }, sub)
        end
        if #member.rows == 0 then k:row({ { t("jno_hits"), color = C.dim } }, sub) end
        for _, r in ipairs(member.rows) do
            k:row({ Kit.name_cell(r), { r.value, w = vw, align = "right" } },
                { indent = sub.indent, fill = { Kit.actor_color(r.kind, r.job, r.shade), r.fill } })
        end
    end
    return k:pages(), k:used()
end

function Tabs.heal(k, m)
    if #m.healers == 0 then
        k:band("heal", i18n.t("healed"), i18n.num(0))
        return k:pages(), k:used()
    end
    local cw, vw = column_w(k, COUNT_COLUMN), column_w(k, VALUE_COLUMN)
    for _, h in ipairs(m.healers) do
        fighter_band(k, h, h.name, h.total)
        local color = Kit.actor_color(h.kind, h.job, h.shade)
        for _, r in ipairs(h.rows) do
            local first = r.whom and { parts = { { "→ ", C.text },
                { r.whom, Kit.actor_text(r.whom_kind, r.whom_job, r.whom_shade) },
                { r.source and (" · " .. r.source), C.text } } } or { r.label }
            k:row({ first, { r.times or i18n.num(r.count), w = cw, align = "right", color = C.dim },
                { r.value, w = vw, align = "right" } }, { fill = { color, r.fill } })
        end
    end
    return k:pages(), k:used()
end

-- The record's column widths in the kit k (nil: the rest) for the heading `heading`.
local function record_widths(k, heading)
    local widths = {}
    for i = 1, #RECORD_COLUMNS do
        local col, widest = RECORD_COLUMNS[i], RECORD_WIDEST[i]
        local w = col and column_w(k, col) or nil
        if w and widest then w = math.max(w, k:width(widest), k:width(heading[i])) end
        widths[i] = w
    end
    return widths
end

-- A row of the record: time, who and whom in their columns, what takes the rest, the amount right-aligned.
local function record_cells(texts, widths, color)
    local cells = {}
    for i = 1, #RECORD_COLUMNS do cells[i] = { texts[i], w = widths[i], color = color } end
    cells[#cells].align = "right"
    return cells
end

function Tabs.record(k, m)
    local t, rh = i18n.t, ROW_H * k.scale
    local heading = { t("jcol_time"), t("jcol_who"), t("jcol_whom"), t("jcol_what"), t("jcol_amount") }
    local widths = record_widths(k, heading)
    -- the dropped line and the heading: a kit of their own on page 1, so they are drawn on every page
    local top = (m.dropped and 2 or 1) * rh
    local head = k:sub({ h = top, page = 1 })
    if m.dropped then head:row({ { m.dropped, color = C.dim } }) end
    head:row(record_cells(heading, widths, C.dim))
    local body = k:sub({ y = k.y + top, h = math.max(1, k.h - top) })
    if #m.rows == 0 then body:row({ { t("jno_hits"), color = C.dim } }) end
    -- one draw function for every event: of a record of thousands only the page shown builds its cells
    local killed = " · " .. t("killed")
    local r
    local function draw_event(x, y, w)
        local line = body:sub({ x = x, y = y, w = w, h = rh, page = 1 })
        local cells = record_cells({ r.time, r.who, r.whom, r.kill and (r.what .. killed) or r.what, r.amount }, widths,
            C.text)
        if r.heal then cells[#cells].color = HEAL_TEXT end
        line:row(cells)
    end
    for _, row in ipairs(m.rows) do
        r = row
        body:unit(rh, draw_event)
    end
    return body:pages(), top + body:used()
end

return Tabs
