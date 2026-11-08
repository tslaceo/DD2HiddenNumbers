-- The enemy plate in the fight (its model: plate_model.lua): what the enemy kinds near the player are weak to and
-- shrug off, and what the player's own attack gets, as a small table (a row per kind, a column per damage type). A
-- translucent black plate with a thin
-- border and small rounded corners, left of the boss bar when there is one (its right edge GAP px × the meter's
-- scale before the bar's left end, its top NAME_ABOVE GUI units × H / 1080 above the bar's middle, level with the
-- boss's name), else at the top centre, where the boss bar would be. It never covers the bar and never leaves the
-- screen sideways: it is laid out in the room it has (EnemyPlate.room, EnemyPlate.layout); its height is not
-- limited, so very large settings (the meter's scale × enemy_plate_size near their tops, a long list) can make it
-- reach the bottom of the screen. On imgui's background draw list (under every window), the font pushed as
-- ui/enemy_bars.lua does, at FONT_SIZE px × the meter's scale × the setting `enemy_plate_size` (1 while the setting
-- is missing). No game access; the texts from i18n and the journal's names of the types (Journal.type_label)
-- and statuses (status_<name>).
--
--   Colours: "name" (the pawn names' beige), "weak" (a mult above ×1, green), "resist" (below, red), "immune" (×0,
--     and the grey of the header, the part labels, "·", "?", "нет данных" and the immunity lines), "you" (light
--     blue), "plain" (×1,0, "+N").
--   EnemyPlate.rows(plate) -> { row }   the table: row = { label = seg | nil, indent = true | nil,
--     cells = { seg } | nil, note = seg | nil }, seg = { text, color, best = true | nil }; a name's label also has
--     `name`, the part of its text that is cut first (the name without its count and state).
--     The header first, when some row has cells: no label, the cells plate_col_<jt> in grey, in COLUMNS' order.
--     Then each kind, the boss's (plate.boss) first, then plate.rows in their order: its name row, the label "Гоблин
--     ×5 (в ярости)" in "name" (" ×N" when N > 1; the state when row.state is set: its word plate_state_<id>,
--     else the id itself), the cells its body's values in COLUMNS' order, the digits of I18n.mult without its "×"
--     ("0,75"), each in its direction's colour, "?" in grey for a column the body has no value of; with no body (or
--     one without a number), no cells but the note "нет данных" (plate_no_data) in grey across the columns. Then,
--     for a kind with cells, its part rows (row.part_rows, "weak" then "head" as the model gives them), indented,
--     the label plate_weak / plate_head in grey, the cells the part's values, "·" in grey for a type the part takes
--     as the body (the model leaves it out).
--     best: the cells of a row's largest value as shown, each when tied, none when all its values are equal or it
--     has none; a "·" counts with its body's value, so it is underlined when the body's value is the part's best;
--     "?" counts with none.
--     Rows that are not tables are skipped; a plate that is not a table has none.
--   EnemyPlate.lines(plate) -> { line }   the lines below the table, line = { { text, color } }: "+N ещё" (plate_more)
--     when plate.more > 0; the immunity lines, "Нёккен (ранен): не действует Сон, Заморозка" (plate_immune; the
--     kind named with its state, without the count; an unclear status's name with " ?" after it, Journal.mark_unclear:
--     "Ослепление ?") in grey, one per kind with immunities in the table's
--     order, under a boss the boss's alone, a line the same as one before it left out; then the "you" line.
--     Their joints are in their line's colour; segments of one colour side by side are one
--     segment, so each line is one segment while it fits.
--     The "you" line (plate_you, left out without plate.you): the types the player hits with, " · " between them, an
--     enchant's as plate_enchant; with a boss or a single row each with that kind's mult ("Дробящий ×1,0 · Огонь
--     (зачарование) ×1,5"); with more rows each with the kinds whose mult is not ×1 in parentheses after it (named
--     with their state, without the count, "Нёккен (ранен) ×4,5", so no two "×" stand side by side), and
--     "; остальные ×1,0" (plate_others) after them when some kind is ×1 ("Режущий (Огр ×0,8; остальные ×1,0) ·
--     Магия (Гоблин ×2,0, Огр ×1,3)"), or " ×1,0" alone when every kind is. A kind with no mult (the model
--     gives none it does not know) is in neither; a type no kind has a mult for stands alone.
--   EnemyPlate.wrap(plate, width, em, measure) -> { line }   those lines fitted into `width` px, measure(text) -> px
--     the width of a text: a line too wide breaks at its joints (" · ", ", ", "; ") onto continuation lines, each
--     `em` px (the font size) in, marked `line.indent = true`; a list's "," and the "you" line's ";" stay at the end
--     of the line broken (when they still fit), the other joints go; a piece (what lies between two joints) too wide
--     for its line is cut with "…" (at least the "…" itself). No line is wider than `width`.
--   EnemyPlate.layout(plate, width, px, measure) -> L | nil   the plate laid out in `width` px (the room between the
--     paddings) at the set font size px; measure(text, at) -> w, h of a text at the font size `at`.
--     The table: the name column left-aligned, each label at most NAME_EM em wide (an indented one an em in and an em
--     less), a longer name cut with "…" before its count and state, which stay; then NAME_GAP px × the font's
--     factor, then the columns, each right-aligned, as wide as its widest header or cell, COL_GAP px × the factor
--     apart; a note at the columns' left. When the table is wider than `width`, the whole plate is laid out at a
--     smaller font: the largest whole-pixel size under px that fits (the widths go with the font, so the size
--     that should fit, px × width / the table's width, is tried first), down to the floor, MIN_FIT × FONT_SIZE
--     (7 px) when px is larger than FONT_SIZE, else MIN_FIT of px; still wider there, the labels are cut to what the
--     columns leave (at least the "…"), and a table whose columns alone are wider stays wider. The lines below are
--     wrapped (as wrap) into `width` at that font. nil for a plate with neither.
--     L = { px, line_h, gap, w, h, lines = { { seg } } }: px the font size used; the lines one under another, line_h
--     high and gap (LINE_GAP px × px / FONT_SIZE) apart, h in all; seg = { text, color, x, w, under = true | nil }, x
--     from the left of the room, w its width, under for the best of a row; w the widest line's right end.
--   EnemyPlate.room(boss, dw, dh, scale, t) -> px   the plate's largest width: from the screen's left margin
--     (MARGIN px × scale) to GAP px × scale before the boss bar's left end while there is a bar (see place), else the
--     display's width less the margin on both sides; never below 0
--   EnemyPlate.place(w, h, boss, dw, dh, scale, t) -> x, y   the top left of a w × h plate on a dw × dh display, in
--     whole pixels, x never below 0: left of the boss bar `boss` (as game/gauges.lua gives it, { x, y, width }, read
--     by EnemyBars.boss_left; any other true value is a bar that could not be read) when there is one, and for
--     HOLD s after it went (the bar's last place, so the plate does not jump when the bar blinks off for a frame);
--     else centred on dw with its top (BOSS_MIDDLE - NAME_ABOVE) units × H / 1080 down
--   EnemyPlate.draw(plate, settings, boss, t) -> err   the plate laid out in its room less the paddings (PAD_X, PAD_Y
--     px × the meter's scale), at its place; each text at a whole pixel; the best of a row underlined, a line
--     UNDERLINE px high at the bottom of its line, as wide as its text, in its colour. Each text is measured at the
--     font size pushed for it (the sizes the fit tries pushed and popped again). Nothing, not even an imgui call, for
--     a plate without rows or lines. Never raises, whatever it is given: everything runs under one pcall and the font
--     sizes pushed are popped again; err = nil or the message of the error caught
--   EnemyPlate.COLORS = { name, weak, resist, immune, you, plain, back, border }   the look's ImU32 colours
--   EnemyPlate.COLUMNS   the table's columns: Slash Blow Shoot Fire Ice Thunder Light Magic
--   EnemyPlate.FONT_SIZE, PAD_X, PAD_Y, LINE_GAP, COL_GAP, NAME_GAP, NAME_EM, MIN_FIT, ROUNDING, GAP, MARGIN,
--     NAME_ABOVE, HOLD   the constants below
--   EnemyPlate.missing() -> { name }: the imgui calls found missing (get_display_size, get_background_draw_list,
--     add_rect: the border is four strips with square corners without it), in order, not tried again until
--     EnemyPlate.reset(), which also forgets the held boss bar and the measured widths
local i18n = require("DD2DamageMeter/i18n")
local Journal = require("DD2DamageMeter/journal")
local Kit = require("DD2DamageMeter/ui/kit")
local EnemyBars = require("DD2DamageMeter/ui/enemy_bars")
local SceneText = require("DD2DamageMeter/ui/scene_text")

local EnemyPlate = {}

local GUI_H = 1080         -- the bars' GUI space's height: a GUI unit is dh / GUI_H px
local FONT_SIZE = 14       -- px × the meter's scale × enemy_plate_size
local PAD_X, PAD_Y = 10, 6 -- px × the meter's scale between the plate's edge and its text
local LINE_GAP = 6         -- px × the font's factor between two lines (20 px lines for 14 px text, the journal's)
local COL_GAP = 8          -- px × the font's factor between two columns of the table
local NAME_GAP = 12        -- px × the font's factor between the name column and the first column
local NAME_EM = 14         -- em (the font size) a label may take before it is cut
local MIN_FIT = 0.5        -- of FONT_SIZE, or of a smaller set size: the smallest the fit goes
local UNDERLINE = 1        -- px: the line under the best of a row
local ROUNDING = 4         -- px × the meter's scale: the plate's corners
local BORDER = 1           -- px: the border's width
local GAP = 12             -- px × the meter's scale between the plate's right edge and the boss bar's left end
local MARGIN = 8           -- px × the meter's scale the plate keeps from the screen's left and right edges
local NAME_ABOVE = 22      -- GUI units from the boss bar's middle up to the plate's top: level with the boss's name
local HOLD = 1             -- s the boss placement holds after the bar went
local BACK_ALPHA = 140     -- 55 % of 255
EnemyPlate.FONT_SIZE, EnemyPlate.PAD_X, EnemyPlate.PAD_Y, EnemyPlate.LINE_GAP = FONT_SIZE, PAD_X, PAD_Y, LINE_GAP
EnemyPlate.COL_GAP, EnemyPlate.NAME_GAP, EnemyPlate.NAME_EM = COL_GAP, NAME_GAP, NAME_EM
EnemyPlate.MIN_FIT = MIN_FIT
EnemyPlate.ROUNDING, EnemyPlate.GAP, EnemyPlate.MARGIN = ROUNDING, GAP, MARGIN
EnemyPlate.NAME_ABOVE, EnemyPlate.HOLD = NAME_ABOVE, HOLD

-- ImU32 colours are 0xAABBGGRR; `abgr` takes the usual 0xRRGGBB and an alpha of 0..255.
local function abgr(rgb, alpha)
    local r, g, b = (rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF
    return (alpha << 24) | (b << 16) | (g << 8) | r
end

-- The plate's colours: the names in the pawn names' beige, the values by their direction, "you" light blue.
EnemyPlate.COLORS = {
    name = EnemyBars.COLORS.text,
    weak = abgr(0x8FD16A, 255),
    resist = abgr(0xE08A7A, 255),
    immune = abgr(0x9A9A9A, 255),
    you = abgr(0x9CC8F0, 255),
    plain = abgr(0xE8E2D0, 255),
    back = abgr(0x000000, BACK_ALPHA),
    border = abgr(0x4A4A4A, 255),
}
local C = EnemyPlate.COLORS

-- The table's columns, in their fixed order (a column per damage type).
local COLUMNS = { "Slash", "Blow", "Shoot", "Fire", "Ice", "Thunder", "Light", "Magic" }
EnemyPlate.COLUMNS = COLUMNS

-- The joints between the pieces of a line below the table; a line breaks at them when it is too wide.
local SEP = " · "        -- between the "you" line's types
local LIST = ", "        -- between the names of a list (the immunities, a type's kinds)
local OTHERS = "; "      -- before the "you" line's other kinds at ×1, after a type's kinds
-- What of a joint stays at the end of a line broken at it (nothing of the others).
local KEEP = { [LIST] = ",", [OTHERS] = ";" }
local ELLIPSIS = "…"     -- the end of a piece cut
local TIMES = "×"        -- I18n.mult's sign, left out of a cell
local DOT = "·"          -- a part's cell where it takes what the body takes
local UNKNOWN = "?"      -- a body's cell the read gave no number for
local PART_LABEL = { weak = "plate_weak", head = "plate_head" }
local EMPTY = {}

local missing
local held, held_t -- the boss bar's place last given to EnemyPlate.place or room, and when

function EnemyPlate.reset()
    missing = {}
    held, held_t = nil, nil
    SceneText.reset()
end
EnemyPlate.reset()

function EnemyPlate.missing()
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

local function list(t)
    return type(t) == "table" and t or EMPTY
end

local function color_of(mult)
    if mult <= 0 then return "immune" end
    if mult < 1 then return "resist" end
    if mult > 1 then return "weak" end
    return "plain"
end

local function name_of(row)
    local name = row.name
    if type(name) ~= "string" or name == "" then name = tostring(row.chara_id or "?") end
    return name
end

-- "Гоблин ×5": the name with the count when there are more than one, unless `no_count` (the lines below the table);
-- "Нёккен (ранен)": with the state in use when it is not Normal, its word plate_state_<id>, else the id
-- itself.
local function name_text(row, no_count)
    local name, n = name_of(row), row.count
    if not no_count and finite(n) and n > 1 then name = name .. " ×" .. i18n.num(n) end
    local state = row.state
    if type(state) == "string" and state ~= "" then
        local key = "plate_state_" .. state
        local word = i18n.t(key)
        if word == key then word = state end -- no text of that id: i18n gives the key back
        name = name .. " (" .. word .. ")"
    end
    return name
end

-- The plate's kinds: the boss's row, nil without one, and the other rows that are tables.
local function kinds_of(plate)
    local boss = type(plate.boss) == "table" and plate.boss or nil
    local rows = {}
    for _, r in ipairs(list(plate.rows)) do
        if type(r) == "table" then rows[#rows + 1] = r end
    end
    return boss, rows
end

-- The table -------------------------------------------------------------------------------------------------

-- A value as it is shown, in hundredths: what a row's best is found by.
local function shown(v)
    return math.floor(v * 100 + 0.5)
end

-- A value's cell: its digits without "×" ("0,75"), in its direction's colour.
local function value_cell(v)
    return { i18n.mult(v):sub(#TIMES + 1), color_of(v) }
end

-- A map's value of a column, nil without a finite one.
local function value(map, jt)
    local v = type(map) == "table" and map[jt] or nil
    return finite(v) and v or nil
end

-- Marks the cells of a row's largest value, values[i] the value of cell i (nil for none): each when tied, none when
-- every value is the same.
local function mark_best(cells, values)
    local hi, lo
    for i = 1, #COLUMNS do
        if values[i] then
            local v = shown(values[i])
            hi, lo = math.max(hi or v, v), math.min(lo or v, v)
        end
    end
    if hi == nil or hi == lo then return end
    for i = 1, #COLUMNS do
        if values[i] and shown(values[i]) == hi then cells[i].best = true end
    end
end

-- A kind's rows into `out`: its name row, with the body's cells or "нет данных", then its part rows.
local function kind_rows(out, row)
    local label = { name_text(row), "name", name = name_of(row) }
    local cells, values = {}, {}
    for i, jt in ipairs(COLUMNS) do
        values[i] = value(row.body, jt)
        cells[i] = values[i] and value_cell(values[i]) or { UNKNOWN, "immune" }
    end
    if next(values) == nil then
        out[#out + 1] = { label = label, note = { i18n.t("plate_no_data"), "immune" } }
        return
    end
    mark_best(cells, values)
    out[#out + 1] = { label = label, cells = cells }
    for _, p in ipairs(list(row.part_rows)) do
        if type(p) == "table" and PART_LABEL[p.kind] and type(p.mult) == "table" then
            local pc, pv = {}, {}
            for i, jt in ipairs(COLUMNS) do
                local v = value(p.mult, jt)
                pc[i] = v and value_cell(v) or { DOT, "immune" }
                pv[i] = v or values[i] -- a "·" takes what the body takes
            end
            mark_best(pc, pv)
            out[#out + 1] = { label = { i18n.t(PART_LABEL[p.kind]), "immune" }, indent = true, cells = pc }
        end
    end
end

local function table_rows(plate)
    local out = {}
    if type(plate) ~= "table" then return out end
    local boss, rows = kinds_of(plate)
    if boss then kind_rows(out, boss) end
    for _, r in ipairs(rows) do kind_rows(out, r) end
    for _, r in ipairs(out) do
        if r.cells then
            local header = {}
            for i, jt in ipairs(COLUMNS) do header[i] = { i18n.t("plate_col_" .. jt), "immune" } end
            table.insert(out, 1, { cells = header })
            break
        end
    end
    return out
end

function EnemyPlate.rows(plate)
    return table_rows(plate)
end

-- The lines below the table -----------------------------------------------------------------------------------
-- A line is first a list of pieces { text, color, joint, joint_color }, joint the separator before the piece (nil
-- for the first of a line) and joint_color its colour ("plain" unless given); EnemyPlate.lines renders them whole,
-- EnemyPlate.wrap fitted into a width.

local function piece(line, text, color, joint, joint_color)
    if text == nil or text == "" then return end
    line[#line + 1] = { text, color, #line > 0 and joint or nil, joint_color or "plain" }
end

-- `text` in `color` at the end of a rendered line: joined to the last segment when it has that colour.
local function add(line, text, color)
    if text == nil or text == "" then return end
    local last = line[#line]
    if last and last[2] == color then
        last[1] = last[1] .. text
    else
        line[#line + 1] = { text, color }
    end
end

-- "Гоблин: не действует Сон, Заморозка", joints and all in grey; nothing without an immunity.
local function immune_pieces(row)
    local out = {}
    for _, name in ipairs(list(row.immune)) do
        if type(name) == "string" then
            local text = Journal.mark_unclear(name, i18n.t("status_" .. name))
            if #out == 0 then text = i18n.t("plate_immune", name_text(row, true), text) end
            piece(out, text, "immune", LIST, "immune")
        end
    end
    return out
end

-- The "you" line's pieces, joints and all in its colour: with a boss or one row, each type with that kind's mult;
-- with more rows, the kinds whose mult is not ×1 in parentheses after it and "остальные ×1,0" after them when some
-- are ×1, or ×1,0 alone when all are. A kind with no mult is in neither.
local function you_pieces(you, boss, rows)
    local out = {}
    if type(you) ~= "table" then return out end
    local one = boss or (#rows == 1 and rows[1]) or nil
    for _, e in ipairs(list(you.types)) do
        if type(e) == "table" and e.jt ~= nil then
            local label = Journal.type_label(e.jt)
            if e.enchant then label = i18n.t("plate_enchant", label) end
            local by = list(e.by_kind)
            if one then
                local m = one.chara_id ~= nil and by[one.chara_id]
                if finite(m) then label = label .. " " .. i18n.mult(m) end
                piece(out, label, "you", SEP, "you")
            else
                local kinds, normal = {}, false -- { { text, joint } }; whether a kind is at ×1
                for _, r in ipairs(rows) do
                    local m = r.chara_id ~= nil and by[r.chara_id]
                    if finite(m) and m ~= 1 then
                        kinds[#kinds + 1] = { name_text(r, true) .. " " .. i18n.mult(m), LIST }
                    elseif finite(m) then
                        normal = true
                    end
                end
                if #kinds == 0 then
                    if normal then label = label .. " " .. i18n.mult(1) end -- alone with no kind's mult
                    piece(out, label, "you", SEP, "you")
                else
                    if normal then kinds[#kinds + 1] = { i18n.t("plate_others", i18n.mult(1)), OTHERS } end
                    kinds[#kinds][1] = kinds[#kinds][1] .. ")"
                    piece(out, label .. " (" .. kinds[1][1], "you", SEP, "you")
                    for i = 2, #kinds do piece(out, kinds[i][1], "you", kinds[i][2], "you") end
                end
            end
        end
    end
    if #out > 0 then out[1][1] = i18n.t("plate_you", out[1][1]) end
    return out
end

-- The lines below the table as lines of pieces.
local function below(plate)
    local lines = {}
    if type(plate) ~= "table" then return lines end
    local boss, rows = kinds_of(plate)
    local more = plate.more
    if finite(more) and more > 0 then
        lines[#lines + 1] = { { i18n.t("plate_more", math.floor(more)), "plain" } }
    end
    local seen = {} -- the immunity lines given, by their text
    for _, r in ipairs(boss and { boss } or rows) do -- under a boss its own alone
        local line = immune_pieces(r)
        local text = {}
        for _, p in ipairs(line) do text[#text + 1] = (p[3] or "") .. p[1] end
        text = table.concat(text)
        if #line > 0 and not seen[text] then
            seen[text] = true
            lines[#lines + 1] = line
        end
    end
    local you = you_pieces(plate.you, boss, rows)
    if #you > 0 then lines[#lines + 1] = you end
    return lines
end

function EnemyPlate.lines(plate)
    local out = {}
    for _, pl in ipairs(below(plate)) do
        local line = {}
        for _, p in ipairs(pl) do
            add(line, p[3], p[4])
            add(line, p[1], p[2])
        end
        out[#out + 1] = line
    end
    return out
end

-- `s` cut to at most max_w px with ELLIPSIS after it (the ELLIPSIS alone when nothing more fits).
local function cut(s, max_w, measure)
    local n = utf8.len(s)
    if not n then return s end
    local function at(keep) return s:sub(1, utf8.offset(s, keep + 1) - 1) .. ELLIPSIS end
    local lo, hi = 0, n - 1
    while lo < hi do
        local mid = (lo + hi + 1) // 2
        if measure(at(mid)) <= max_w then lo = mid else hi = mid - 1 end
    end
    return at(lo)
end

local function wrap_pieces(plines, width, em, measure)
    local out = {}
    for _, pl in ipairs(plines) do
        if #pl > 0 then
            local line, cw, avail
            local function open(indent)
                line, cw, avail = {}, 0, indent and width - em or width
                if indent then line.indent = true end
                out[#out + 1] = line
            end
            open(false)
            for _, p in ipairs(pl) do
                local text, color, joint, jc = p[1], p[2], p[3], p[4]
                local w = measure(text)
                if cw > 0 then
                    local jw = joint and measure(joint) or 0
                    if cw + jw + w <= avail then
                        add(line, joint, jc)
                        cw = cw + jw
                    else
                        local keep = KEEP[joint]
                        if keep and cw + measure(keep) <= avail then add(line, keep, jc) end
                        open(true)
                    end
                end
                if w > avail then
                    text = cut(text, avail, measure)
                    w = measure(text)
                end
                add(line, text, color)
                cw = cw + w
            end
        end
    end
    return out
end

function EnemyPlate.wrap(plate, width, em, measure)
    return wrap_pieces(below(plate), width, em, measure)
end

-- The layout ----------------------------------------------------------------------------------------------------

-- A label's text within max_w px: whole when it fits, else its name (the whole text without one) cut with "…" and
-- the rest of it (a name's count) after that.
local function label_text(label, max_w, measure)
    local text = label[1]
    if measure(text) <= max_w then return text end
    local name = label.name or text
    local rest = text:sub(#name + 1)
    return cut(name, max_w - (rest ~= "" and measure(rest) or 0), measure) .. rest
end

-- The table's size at the font size `at`, its labels at most name_max px wide (an indented one an em in): the
-- labels' texts by row, the name column's width, each column's, the gap after the names and the whole width.
local function size_table(trows, at, name_max, measure)
    local f = at / FONT_SIZE
    local function m(text) return (measure(text, at)) end
    local s = { at = at, labels = {}, cols = {}, name = 0, gap = NAME_GAP * f }
    local area = 0 -- the columns' width, or a note's when it is wider
    for i, r in ipairs(trows) do
        if r.label then
            local indent = r.indent and at or 0
            s.labels[i] = label_text(r.label, name_max - indent, m)
            s.name = math.max(s.name, indent + m(s.labels[i]))
        end
        for c, cell in ipairs(r.cells or EMPTY) do s.cols[c] = math.max(s.cols[c] or 0, m(cell[1])) end
        if r.note then area = math.max(area, m(r.note[1])) end
    end
    local cols = 0
    for c = 1, #s.cols do cols = cols + s.cols[c] + (c > 1 and COL_GAP * f or 0) end
    s.w = s.name + s.gap + math.max(area, cols)
    return s
end

-- The table's size at the font that fits `width`: the set size px when it fits, else the largest whole-pixel
-- size under it that does, down to the floor (MIN_FIT × FONT_SIZE, or MIN_FIT of a smaller px); still too wide
-- there, its labels cut to what the columns leave.
local function fit(trows, width, px, measure)
    local s = size_table(trows, px, NAME_EM * px, measure)
    if #trows == 0 or s.w <= width then return s end -- no table: nothing to shrink for
    local floor = MIN_FIT * math.min(px, FONT_SIZE)
    local function at(size) return size_table(trows, size, NAME_EM * size, measure) end
    -- the widths go with the font: the whole size that should fit first, then a pixel up while one fits, else down
    local top = math.ceil(px) - 1 -- the largest whole size under px
    local n = math.min(top, math.floor(px * width / s.w))
    if n < floor then
        s = at(floor)
    else
        s = at(n)
        if s.w <= width then
            while n < top do
                local up = at(n + 1)
                if up.w > width then break end
                n, s = n + 1, up
            end
        else
            while s.w > width and n - 1 >= floor do
                n = n - 1
                s = at(n)
            end
            if s.w > width and n > floor then s = at(floor) end
        end
    end
    if s.w > width then s = size_table(trows, s.at, width - (s.w - s.name), measure) end
    return s
end

local function layout(trows, blines, width, px, measure)
    if #trows == 0 and #blines == 0 then return nil end
    local s = fit(trows, width, px, measure)
    local at, f = s.at, s.at / FONT_SIZE
    local lines, line_h, w = {}, 0, 0
    local function seg(line, text, color, x, under)
        local sw, sh = measure(text, at)
        line[#line + 1] = { text, color, x = x, w = sw, under = under }
        line_h, w = math.max(line_h, sh), math.max(w, x + sw)
        return sw
    end
    -- each column's right end
    local right, x = {}, s.name + s.gap
    for c = 1, #s.cols do
        right[c] = x + s.cols[c]
        x = right[c] + COL_GAP * f
    end
    for i, r in ipairs(trows) do
        local line = {}
        if r.label then seg(line, s.labels[i], r.label[2], r.indent and at or 0) end
        for c, cell in ipairs(r.cells or EMPTY) do
            seg(line, cell[1], cell[2], right[c] - (measure(cell[1], at)), cell.best)
        end
        if r.note then seg(line, r.note[1], r.note[2], s.name + s.gap) end
        lines[#lines + 1] = line
    end
    for _, wl in ipairs(wrap_pieces(blines, width, at, function(text) return (measure(text, at)) end)) do
        local line, lx = {}, wl.indent and at or 0
        for _, p in ipairs(wl) do lx = lx + seg(line, p[1], p[2], lx) end
        lines[#lines + 1] = line
    end
    local gap = LINE_GAP * f
    return { px = at, line_h = line_h, gap = gap, lines = lines, w = w, h = #lines * line_h + (#lines - 1) * gap }
end

function EnemyPlate.layout(plate, width, px, measure)
    return layout(table_rows(plate), below(plate), width, px, measure)
end

-- The place ---------------------------------------------------------------------------------------------

-- The boss bar the plate goes by: `boss` when there is one (its numbers kept), else the one held for HOLD s; nil
-- without either.
local function bar_of(boss, t)
    if boss then
        held, held_t = type(boss) == "table" and { x = boss.x, y = boss.y, width = boss.width } or {}, t
        return held
    end
    if held and finite(t) and finite(held_t) and t - held_t <= HOLD then return held end
    return nil
end

function EnemyPlate.room(boss, dw, dh, scale, t)
    local bar = bar_of(boss, t)
    local margin = MARGIN * scale
    if bar then
        local left = EnemyBars.boss_left(bar, dw, dh)
        return math.max(0, left - GAP * scale - margin)
    end
    return math.max(0, dw - 2 * margin)
end

function EnemyPlate.place(w, h, boss, dw, dh, scale, t)
    local unit = dh / GUI_H
    local bar = bar_of(boss, t)
    local x, y
    if bar then
        local left, middle = EnemyBars.boss_left(bar, dw, dh)
        x, y = left - GAP * scale - w, middle - NAME_ABOVE * unit
    else
        x, y = (dw - w) / 2, (EnemyBars.BOSS_MIDDLE - NAME_ABOVE) * unit
    end
    return math.max(0, round(x)), round(y)
end

-- The drawing -------------------------------------------------------------------------------------------

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

local function pop_font(started)
    imgui.pop_font_size()
    started.fonts = started.fonts - 1
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

-- The border: an outline with the plate's rounding; four strips with square corners when add_rect is missing (it
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

local function draw_plate(started, plate, settings, boss, t)
    local trows, blines = table_rows(plate), below(plate)
    if #trows == 0 and #blines == 0 then return end
    local v = settings.values
    local scale = v.scale
    local size = v.enemy_plate_size
    if not finite(size) then size = 1 end
    local px = FONT_SIZE * scale * size
    local bg, dw, dh = surface()
    if not bg then return end
    local pad_x, pad_y = PAD_X * scale, PAD_Y * scale
    local room = EnemyPlate.room(boss, dw, dh, scale, t)
    -- a text measured at a size is measured with that size pushed: the one before it popped
    local pushed
    local function at_size(at)
        if pushed == at then return end
        if pushed then pop_font(started) end
        push_font(at, started)
        pushed = at
    end
    local L = layout(trows, blines, room - 2 * pad_x, px, function(text, at)
        at_size(at)
        return SceneText.size(text, at)
    end)
    at_size(L.px)
    local w = round(L.w + 2 * pad_x)
    local h = round(L.h + 2 * pad_y)
    local x0, y0 = EnemyPlate.place(w, h, boss, dw, dh, scale, t)
    local x1, y1 = x0 + w, y0 + h
    local rounding = ROUNDING * scale
    rect(bg, x0, y0, x1, y1, C.back, rounding)
    border(bg, x0, y0, x1, y1, rounding)
    local left, y = round(x0 + pad_x), y0 + pad_y
    local under = round(L.line_h) - UNDERLINE -- the underline's top under its line's top
    for _, line in ipairs(L.lines) do
        local ty = round(y)
        for _, seg in ipairs(line) do
            local x, color = math.floor(left + seg.x), C[seg[2]] or C.plain
            P[1], P[2] = x, ty
            bg:add_text(P, color, seg[1])
            if seg.under then rect(bg, x, ty + under, round(x + seg.w), ty + under + UNDERLINE, color) end
        end
        y = y + L.line_h + L.gap
    end
end

-- fn(started, ...) under one pcall; the font sizes it pushed are popped again.
local function guarded(fn, ...)
    local started = { fonts = 0 }
    local ok, err = pcall(fn, started, ...)
    for _ = 1, started.fonts do pcall(imgui.pop_font_size) end
    if ok then return nil end
    return tostring(err)
end

function EnemyPlate.draw(plate, settings, boss, t)
    return guarded(draw_plate, plate, settings, boss, t)
end

return EnemyPlate
