-- The settings window's model (ui/settings_window.lua draws it): the rows of every group, each row's label, value as
-- text and help line, what Left/Right make of a value, and the moves of the selection. Pure Lua: labels, headings and
-- help lines come from i18n (`setting_<row key>`, `sgroup_<group>`, `setting_help_<key>`), ranges from
-- Settings.LIMITS, key names from Menu.key_name.
--
--   SettingsView.GROUPS = { { id, keys = { row key... }, table = true|nil } }   the groups in the order drawn; a
--                       `table` group starts with the table of the meter's sections
--   SettingsView.ROWS = { { key, kind, group, cells } }   every row once, in that order; kind "switch" | "choice" |
--                       "number" | "key" | "pair"; group: its index in GROUPS. A "pair" row (key "section_<id>") is
--                       a line of that table: cells = { the fight window's switch | false, the summary's | false }
--                       (false: that window has no such section). A row's index here is its index everywhere.
--   SettingsView.STEPS = { [key] = step }   what one Left/Right adds to a number
--   SettingsView.shown(settings, index) -> boolean   whether the row is shown: the halo and the bars only while the
--                       style is the one without the panel
--   SettingsView.build(settings, i18n) -> { title, groups = { { heading, columns = { fight, summary } (a table
--                       group), rows = { { index, key, kind, label, help, value, on, cells } } } }, hint }
--                       the shown rows only; value: the value as text; on: whether a switch is on; help: the row's
--                       help line; a pair row has cells = { { key, value, on } | false, ... } instead of value and on
--   SettingsView.step(settings, key, dir) -> value | nil   one step (dir -1 | 1) from the current value: a switch
--                       flipped, the previous / next choice (round from the last to the first), a number by its step
--                       within its limits; nil when there is none (a key or a pair row, a number at its end)
--   SettingsView.move(settings, sel, col, a) -> sel, col   a = { select = row index | nil, col = 1|2|nil,
--                       select_step = -1|0|1, group_step = -1|0|1, step = -1|0|1 }: a row clicked (and its cell),
--                       the shown row above / below (stopping at the ends), the first row of the previous / next group
--                       (none before the first or after the last); in that order, within the rows. On a pair row
--                       Left/Right (step) go to its other cell, skipping a cell without a switch, and col always
--                       names a cell with one. A row hidden under the selection gives way to the nearest one above.
--   SettingsView.target(sel, col) -> key, kind   the setting the selection changes: the row's own (its kind), or on
--                       a pair row its cell's (kind "cell": a switch that Left/Right do not flip)
--   SettingsView.texts(i18n) -> { { key, kind, label, values = { text... } } }   every row, shown or not, with every
--                       value text it can show: each choice's name, a switch either way, a number at both ends, each
--                       key's name; none for a pair row (its cells are switches). The window measures its width with
--                       them.
local Settings = require("DD2DamageMeter/settings")
local Menu = require("DD2DamageMeter/ui/menu")

local SettingsView = {}

local TITLE = Menu.TITLE

-- The table's rows: each section of the meter, its switch in the fight window and in the summary.
local PAIRS = {
    section_enemies = { false, "summary_enemies" },
    section_damage = { "live_damage", "summary_damage" },
    section_taken = { "live_taken", false },
    section_heal = { "live_heal", "summary_heal" },
    section_armor = { false, "summary_armor" },
    section_allies = { "show_allies", "summary_allies" },
    section_other = { "live_other", "summary_other" },
}

SettingsView.GROUPS = {
    { id = "look", keys = { "style", "scale", "opacity", "shadow", "outline", "halo", "bar_px", "window_x",
        "window_y" } },
    { id = "show", table = true, keys = { "section_enemies", "section_damage", "section_taken", "section_heal",
        "section_armor", "section_allies", "section_other", "summary_autohide" } },
    { id = "damage_numbers", keys = { "damage_numbers", "damage_numbers_style", "damage_numbers_size" } },
    { id = "hp_numbers", keys = { "boss_hp_numbers", "enemy_hp_numbers", "player_numbers", "buildup_bars",
        "enemy_hp_size" } },
    { id = "enemy_plate", keys = { "enemy_plate", "enemy_plate_size" } },
    { id = "hidden_stats", keys = { "hidden_stats", "hidden_stats_size" } },
    { id = "journal", keys = { "journal", "history_size", "history_file" } },
    { id = "keys", keys = { "toggle_key", "journal_key", "settings_key" } },
    { id = "other", keys = { "language", "debug" } },
}

-- Rows shown only while another setting has a value: the halo and the bars belong to the look without the panel.
local SHOWN_WHEN = { halo = { "style", "frameless" }, bar_px = { "style", "frameless" } }

-- What the HP numbers show, over heads and at the boss bar alike.
local HP_FORMATS = {
    values = { "off", "current", "current_max", "percent", "current_percent", "all" },
    labels = { "hpfmt_off", "hpfmt_current", "hpfmt_current_max", "hpfmt_percent", "hpfmt_current_percent",
        "hpfmt_all" },
}

-- Settings chosen from a list: the values in order, and the i18n keys of their names.
local CHOICES = {
    language = { values = { "auto", "en", "ru" }, labels = { "lang_auto", "lang_en", "lang_ru" } },
    style = { values = { "frameless", "panel" }, labels = { "style_frameless", "style_panel" } },
    enemy_hp_numbers = HP_FORMATS,
    boss_hp_numbers = HP_FORMATS,
    damage_numbers_style = { values = { "rise", "plates" }, labels = { "dnum_rise", "dnum_plates" } },
}

SettingsView.STEPS = {
    summary_autohide = 1, history_size = 1, bar_px = 1, -- seconds, fights, pixels
    window_x = 10, window_y = 10,                       -- pixels
    opacity = 0.05, scale = 0.05, shadow = 0.1,
    enemy_hp_size = 0.1, damage_numbers_size = 0.1, enemy_plate_size = 0.1, hidden_stats_size = 0.1, -- 10 %
}

-- The unit of a number's text: a factor as a percent, pixels, seconds (0: never); any other a whole number alone.
local UNITS = {
    scale = "pct", opacity = "pct", shadow = "pct", enemy_hp_size = "pct", damage_numbers_size = "pct",
    enemy_plate_size = "pct", hidden_stats_size = "pct",
    bar_px = "px", window_x = "px", window_y = "px",
    summary_autohide = "sec",
}

local function kind_of(key)
    if PAIRS[key] then return "pair" end
    if CHOICES[key] then return "choice" end
    local limit = Settings.LIMITS[key]
    if limit and limit.code then return "key" end
    if type(Settings.DEFAULTS[key]) == "boolean" then return "switch" end
    return "number"
end

local ROWS, FIRST = {}, {} -- FIRST[group] = the index of its first row
for gi, g in ipairs(SettingsView.GROUPS) do
    FIRST[gi] = #ROWS + 1
    for _, key in ipairs(g.keys) do
        ROWS[#ROWS + 1] = { key = key, kind = kind_of(key), group = gi, cells = PAIRS[key] }
    end
end
SettingsView.ROWS = ROWS

function SettingsView.shown(settings, index)
    local row = ROWS[index]
    if row == nil then return false end
    local rule = SHOWN_WHEN[row.key]
    return rule == nil or settings.values[rule[1]] == rule[2]
end

local function number_text(key, value, i18n)
    local unit = UNITS[key]
    if unit == "pct" then return i18n.t("svalue_pct", math.floor(value * 100 + 0.5)) end
    value = math.tointeger(value) or math.floor(value + 0.5)
    if unit == "px" then return i18n.t("svalue_px", value) end
    if unit == "sec" then return value == 0 and i18n.t("svalue_never") or i18n.t("svalue_sec", value) end
    return string.format("%d", value)
end

local function value_text(key, kind, value, i18n)
    if kind == "switch" then return i18n.t(value and "switch_on" or "switch_off") end
    if kind == "key" then return Menu.key_name(value) end
    if kind == "choice" then
        local choice = CHOICES[key]
        for i, v in ipairs(choice.values) do
            if v == value then return i18n.t(choice.labels[i]) end
        end
        return tostring(value)
    end
    return number_text(key, value, i18n)
end

-- The help line: setting_help_<key>; shared by the table's rows (naming the row; the Other row also says what else it
-- covers), by the key rows (after what the key does) and by the two HP number rows (the chosen format as it looks).
local function help_text(row, label, v, i18n)
    local key = row.key
    if row.kind == "pair" then
        local text = i18n.t("setting_help_section", label)
        if key == "section_other" then text = text .. " " .. i18n.t("setting_help_section_other") end
        return text
    end
    if row.kind == "key" then return i18n.t("setting_help_key", i18n.t("setting_help_" .. key)) end
    if CHOICES[key] == HP_FORMATS then
        return i18n.t("setting_help_hp_numbers", i18n.t("hpnum_" .. tostring(v[key])))
    end
    if key == "journal" then return i18n.t("setting_help_journal", Menu.key_name(v.journal_key)) end
    if key == "history_size" then return i18n.t("setting_help_history_size", Settings.LIMITS.history_size.max) end
    return i18n.t("setting_help_" .. key)
end

local function row_model(row, index, v, i18n)
    local label = i18n.t("setting_" .. row.key)
    local r = { index = index, key = row.key, kind = row.kind, label = label, help = help_text(row, label, v, i18n) }
    if row.kind == "pair" then
        r.cells = {}
        for c = 1, 2 do
            local key = row.cells[c]
            r.cells[c] = key and { key = key, value = value_text(key, "switch", v[key], i18n), on = v[key] == true }
                or false
        end
        return r
    end
    r.value = value_text(row.key, row.kind, v[row.key], i18n)
    if row.kind == "switch" then r.on = v[row.key] == true end
    return r
end

function SettingsView.build(settings, i18n)
    local v = settings.values
    local groups = {}
    for gi, g in ipairs(SettingsView.GROUPS) do
        local rows = {}
        for i = FIRST[gi], FIRST[gi] + #g.keys - 1 do
            if SettingsView.shown(settings, i) then rows[#rows + 1] = row_model(ROWS[i], i, v, i18n) end
        end
        groups[gi] = { heading = i18n.t("sgroup_" .. g.id), rows = rows }
        if g.table then groups[gi].columns = { i18n.t("scol_live"), i18n.t("scol_summary") } end
    end
    return {
        title = TITLE .. " · " .. i18n.t("settings_title"),
        groups = groups,
        hint = i18n.t("settings_hint", Menu.key_name(v.settings_key)),
    }
end

local function sign(n)
    if type(n) ~= "number" or n == 0 or n ~= n then return 0 end
    return n > 0 and 1 or -1
end

function SettingsView.step(settings, key, dir)
    dir = sign(dir)
    local value = settings.values[key]
    local kind = kind_of(key)
    if dir == 0 or kind == "key" or kind == "pair" then return nil end
    if kind == "switch" then return not value end
    if kind == "choice" then
        local values, at = CHOICES[key].values, 1
        for i, v in ipairs(values) do
            if v == value then at = i end
        end
        return values[(at - 1 + dir) % #values + 1]
    end
    local limit = Settings.LIMITS[key]
    local new = value + dir * SettingsView.STEPS[key]
    if not limit.integer then new = math.floor(new * 100 + 0.5) / 100 end -- no float dust: 0.8 + 0.1 is 0.9
    new = math.max(limit.min, math.min(limit.max, new))
    if new == value then return nil end
    return new
end

function SettingsView.move(settings, sel, col, a)
    local n = #ROWS
    local function clamp(i) return math.max(1, math.min(n, i)) end
    local function shown(i) return SettingsView.shown(settings, i) end
    sel = clamp(math.tointeger(sel) or 1)
    col = col == 2 and 2 or 1
    local picked = math.tointeger(a.select)
    if picked then
        sel = clamp(picked)
        if a.col == 1 or a.col == 2 then col = a.col end
    end
    local dir = sign(a.select_step)
    if dir ~= 0 then
        local i = sel + dir
        while ROWS[i] and not shown(i) do i = i + dir end
        if ROWS[i] then sel = i end
    end
    local g = ROWS[sel].group + sign(a.group_step)
    if g ~= ROWS[sel].group and FIRST[g] then
        local i = FIRST[g]
        while ROWS[i + 1] and ROWS[i + 1].group == g and not shown(i) do i = i + 1 end
        sel = i
    end
    while sel > 1 and not shown(sel) do sel = sel - 1 end
    local cells = ROWS[sel].cells
    if cells then
        local to = col + sign(a.step)
        if cells[to] then col = to end
        if not cells[col] then col = 3 - col end
    end
    return sel, col
end

function SettingsView.target(sel, col)
    local row = ROWS[sel]
    if row == nil then return nil end
    if row.cells then return row.cells[col] or nil, "cell" end
    return row.key, row.kind
end

function SettingsView.texts(i18n)
    local list = {}
    for _, row in ipairs(ROWS) do
        local key, kind, values = row.key, row.kind, {}
        local limit = Settings.LIMITS[key]
        if kind == "choice" then
            for _, label in ipairs(CHOICES[key].labels) do values[#values + 1] = i18n.t(label) end
        elseif kind == "switch" then
            values = { i18n.t("switch_on"), i18n.t("switch_off") }
        elseif kind == "number" then
            values = { number_text(key, limit.min, i18n), number_text(key, limit.max, i18n) }
        elseif kind == "key" then
            for vk = limit.min, limit.max do values[#values + 1] = Menu.key_name(vk) end
        end
        list[#list + 1] = { key = key, kind = kind, label = i18n.t("setting_" .. key), values = values }
    end
    return list
end

return SettingsView
