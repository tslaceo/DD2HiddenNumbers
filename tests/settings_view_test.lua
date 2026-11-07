package.path = "mod/reframework/autorun/?.lua;tests/?.lua;" .. package.path

local T = require("testlib")
local test, eq, near = T.test, T.eq, T.near
local i18n = require("DD2DamageMeter/i18n")
local Settings = require("DD2DamageMeter/settings")
local SettingsView = require("DD2DamageMeter/settings_view")

local function make_settings(saved)
    saved = saved or {}
    return Settings.load({ read = function() return saved end, write = function(t) saved = t end })
end

-- The groups and their rows, as the settings window shows them.
local WANT = {
    { "look", { "style", "scale", "opacity", "shadow", "outline", "halo", "bar_px", "window_x", "window_y" } },
    { "show", { "section_enemies", "section_damage", "section_taken", "section_heal", "section_armor",
        "section_allies", "section_other", "summary_autohide" } },
    { "damage_numbers", { "damage_numbers", "damage_numbers_style", "damage_numbers_size" } },
    { "hp_numbers", { "boss_hp_numbers", "enemy_hp_numbers", "player_numbers", "buildup_bars", "enemy_hp_size" } },
    { "enemy_plate", { "enemy_plate", "enemy_plate_size" } },
    { "hidden_stats", { "hidden_stats", "hidden_stats_size" } },
    { "journal", { "journal", "history_size", "history_file" } },
    { "keys", { "toggle_key", "journal_key", "settings_key" } },
    { "other", { "language", "debug" } },
}

-- The table «What to show»: each row's switch in the fight window and in the summary (false: «—»).
local CELLS = {
    section_enemies = { false, "summary_enemies" },
    section_damage = { "live_damage", "summary_damage" },
    section_taken = { "live_taken", false },
    section_heal = { "live_heal", "summary_heal" },
    section_armor = { false, "summary_armor" },
    section_allies = { "show_allies", "summary_allies" },
    section_other = { "live_other", "summary_other" },
}

local function index_of(key)
    for i, row in ipairs(SettingsView.ROWS) do
        if row.key == key then return i end
    end
end

local function row_of(m, key)
    for _, g in ipairs(m.groups) do
        for _, r in ipairs(g.rows) do
            if r.key == key then return r end
        end
    end
    return nil
end

-- The keys of a built model's rows, in order.
local function keys_of(m)
    local out = {}
    for _, g in ipairs(m.groups) do
        for _, r in ipairs(g.rows) do out[#out + 1] = r.key end
    end
    return table.concat(out, ",")
end

test("groups and rows in order, every setting once: a row or a cell of the table", function()
    eq(#SettingsView.GROUPS, #WANT, "nine groups")
    local n = 0
    for gi, want in ipairs(WANT) do
        local g = SettingsView.GROUPS[gi]
        eq(g.id, want[1], "group " .. gi)
        eq(table.concat(g.keys, ","), table.concat(want[2], ","), "the rows of " .. want[1])
        eq(g.table == true, want[1] == "show", "only " .. want[1] .. " has the table")
        for _, key in ipairs(want[2]) do
            n = n + 1
            local row = SettingsView.ROWS[n]
            eq(row.key, key, "row " .. n)
            eq(row.group, gi, key .. " in group " .. gi)
        end
    end
    eq(#SettingsView.ROWS, n, "the rows are the groups' rows")
    local seen, total = {}, 0
    local function see(key)
        eq(seen[key], nil, key .. " once")
        seen[key] = true
        eq(Settings.DEFAULTS[key] ~= nil, true, key .. " is a setting")
    end
    for _, row in ipairs(SettingsView.ROWS) do
        if CELLS[row.key] then
            eq(row.kind, "pair", row.key .. " is a row of the table")
            for c = 1, 2 do
                eq(row.cells[c], CELLS[row.key][c], row.key .. " cell " .. c)
                if row.cells[c] then
                    see(row.cells[c])
                    eq(type(Settings.DEFAULTS[row.cells[c]]), "boolean", row.cells[c] .. " is a switch")
                end
            end
        else
            eq(row.cells, nil, row.key .. " has no cells")
            see(row.key)
        end
    end
    for key in pairs(Settings.DEFAULTS) do
        total = total + 1
        eq(seen[key], true, key .. " is in the window")
    end
    -- the kind of each row
    local kinds = {}
    for _, row in ipairs(SettingsView.ROWS) do kinds[row.key] = row.kind end
    for _, key in ipairs({ "language", "style", "boss_hp_numbers", "enemy_hp_numbers", "damage_numbers_style" }) do
        eq(kinds[key], "choice", key)
    end
    for _, key in ipairs({ "toggle_key", "journal_key", "settings_key" }) do eq(kinds[key], "key", key) end
    for _, key in ipairs({ "summary_autohide", "scale", "opacity", "shadow", "bar_px", "window_x", "window_y",
                           "history_size", "enemy_hp_size", "damage_numbers_size", "enemy_plate_size",
                           "hidden_stats_size" }) do
        eq(kinds[key], "number", key)
    end
    for _, key in ipairs({ "debug", "outline", "halo", "journal", "history_file", "damage_numbers", "enemy_plate",
                           "player_numbers", "hidden_stats" }) do
        eq(kinds[key], "switch", key)
    end
end)

test("the model: headings, short labels, the table's columns and cells, the values with their units", function()
    local s = make_settings({ language = "ru", opacity = 0.78, window_x = 40, halo = false, scale = 1.18 })
    local function labels(lang, want)
        i18n.set(lang)
        local m = SettingsView.build(s, i18n)
        eq(m.title, "Hidden Numbers · " .. i18n.t("settings_title"), "title in " .. lang)
        eq(m.hint, i18n.t("settings_hint", "F8"), "hint with the settings key in " .. lang)
        local out = {}
        for gi, g in ipairs(m.groups) do
            eq(g.heading, i18n.t("sgroup_" .. WANT[gi][1]), "heading " .. gi .. " in " .. lang)
            local parts = {}
            for _, r in ipairs(g.rows) do parts[#parts + 1] = r.label end
            out[#out + 1] = g.heading .. ": " .. table.concat(parts, ", ")
        end
        eq(table.concat(out, " | "), want, "the headings and labels in " .. lang)
        return m
    end
    labels("ru", "Вид метра: Стиль, Размер, Фон, Тень, Обводка, Ореол, Полосы, Позиция X, Позиция Y"
        .. " | Что показывать: Враги, Нанесено, Получено, Лечение, Броня, Союзники, Прочее, Сводка гаснет через"
        .. " | Цифры урона: Показывать, Вид, Размер"
        .. " | Цифры здоровья: У босса, Над врагами, Моё здоровье и выносливость, Накопление статусов, Размер"
        .. " | Плашка врагов: Показывать, Размер"
        .. " | Скрытые числа: Показывать, Размер"
        .. " | Журнал: Вести журнал, Хранить боёв, Сохранять между запусками"
        .. " | Клавиши: Метр, Журнал, Настройки"
        .. " | Прочее: Язык, Отладка")
    local m = labels("en", "Meter look: Style, Size, Background, Shadow, Outline, Halo, Bars, Position X, Position Y"
        .. " | What to show: Enemies, Dealt, Taken, Healing, Armor, Allies, Other, Summary hides after"
        .. " | Damage numbers: Show, Style, Size"
        .. " | Health numbers: At the boss, Over enemies, My health and stamina, Status buildup, Size"
        .. " | Enemy plate: Show, Size"
        .. " | Hidden stats: Show, Size"
        .. " | Journal: Keep a journal, Fights kept, Save between sessions"
        .. " | Keys: Meter, Journal, Settings"
        .. " | Other: Language, Debug")
    -- the rows are numbered as SettingsView.ROWS, of its kind
    for _, g in ipairs(m.groups) do
        for _, r in ipairs(g.rows) do
            eq(r.key, SettingsView.ROWS[r.index].key, r.key .. " index")
            eq(r.kind, SettingsView.ROWS[r.index].kind, r.key .. " kind")
            eq(type(r.help), "string", r.key .. " has a help line")
            if r.kind ~= "pair" then eq(type(r.value), "string", r.key .. ": its value as a text") end
        end
    end
    -- the table: its group has the columns, each row two cells (a switch's value, or false for «—»)
    i18n.set("ru")
    s:set("live_taken", false)
    m = SettingsView.build(s, i18n)
    eq(T.str(m.groups[2].columns), "Бой Сводка", "the columns «Бой | Сводка»")
    for gi, g in ipairs(m.groups) do
        if gi ~= 2 then eq(g.columns, nil, "no columns in group " .. gi) end
    end
    for key, want in pairs(CELLS) do
        local r = row_of(m, key)
        eq(r.value, nil, key .. ": no value of its own"); eq(r.on, nil, "no state of its own")
        for c = 1, 2 do
            if want[c] then
                eq(r.cells[c].key, want[c], key .. " cell " .. c)
                eq(r.cells[c].on, s.values[want[c]], want[c] .. " on or off")
                eq(r.cells[c].value, s.values[want[c]] and "вкл" or "выкл", want[c] .. " as a switch")
            else
                eq(r.cells[c], false, key .. " cell " .. c .. ": «—»")
            end
        end
    end
    eq(row_of(m, "section_taken").cells[1].value, "выкл", "a cell off")
    eq(row_of(m, "section_taken").cells[1].on, false, "off")
    -- the values: percent, px, seconds, a number alone, the names of the choices
    eq(row_of(m, "style").value, "Без панели", "the style without the panel")
    eq(row_of(m, "scale").value, "118 %", "the size as a percent")
    eq(row_of(m, "opacity").value, "78 %", "the background as a percent")
    eq(row_of(m, "shadow").value, "80 %", "the shadow as a percent")
    eq(row_of(m, "outline").value, "вкл", "a switch on"); eq(row_of(m, "outline").on, true, "on")
    eq(row_of(m, "halo").value, "выкл", "a switch off"); eq(row_of(m, "halo").on, false, "off")
    eq(row_of(m, "bar_px").value, "3 px", "the bars in px")
    eq(row_of(m, "window_x").value, "40 px", "the position in px"); eq(row_of(m, "window_y").value, "300 px", "y")
    eq(row_of(m, "summary_autohide").value, "никогда", "0 s: never")
    eq(row_of(m, "damage_numbers").value, "вкл", "the damage numbers on")
    eq(row_of(m, "damage_numbers_style").value, "Взлетают", "rise")
    eq(row_of(m, "damage_numbers_size").value, "100 %", "their size as a percent")
    eq(row_of(m, "boss_hp_numbers").value, "HP / макс. и %", "the boss's numbers: all, by its short name")
    eq(row_of(m, "enemy_hp_numbers").value, "HP / макс. и %", "over enemies: the same")
    eq(row_of(m, "enemy_hp_size").value, "100 %", "their size as a percent")
    eq(row_of(m, "player_numbers").value, "вкл", "the player's numbers on")
    eq(row_of(m, "player_numbers").on, true, "on")
    eq(row_of(m, "enemy_plate").value, "вкл", "the enemy plate on"); eq(row_of(m, "enemy_plate").on, true, "on")
    eq(row_of(m, "enemy_plate_size").value, "100 %", "its size as a percent")
    eq(row_of(m, "hidden_stats").value, "вкл", "the hidden-stats panel on")
    eq(row_of(m, "hidden_stats").on, true, "on")
    eq(row_of(m, "hidden_stats_size").value, "100 %", "its size as a percent")
    eq(row_of(m, "history_size").value, "10", "the fights kept: the number alone")
    eq(row_of(m, "journal").value, "вкл", "the journal on"); eq(row_of(m, "history_file").value, "выкл", "the file off")
    eq(row_of(m, "toggle_key").value, "F6", "a key: its name"); eq(row_of(m, "settings_key").value, "F8", "F8")
    eq(row_of(m, "language").value, "Русский", "a language: its name")
    s:set("summary_autohide", 10)
    s:set("scale", 0.6)
    s:set("opacity", 1)
    s:set("shadow", 0)
    s:set("window_x", 16384)
    s:set("style", "panel")
    s:set("damage_numbers_style", "plates")
    s:set("damage_numbers_size", 2.5)
    s:set("enemy_hp_size", 0.5)
    s:set("enemy_plate", false)
    s:set("enemy_plate_size", 3)
    s:set("hidden_stats", false)
    s:set("hidden_stats_size", 0.5)
    s:set("history_size", 32)
    s:set("language", "auto")
    s:set("toggle_key", 0x21)
    m = SettingsView.build(s, i18n)
    eq(row_of(m, "summary_autohide").value, "10 с", "seconds")
    eq(row_of(m, "scale").value, "60 %", "60 %"); eq(row_of(m, "opacity").value, "100 %", "100 %")
    eq(row_of(m, "shadow").value, "0 %", "0 %"); eq(row_of(m, "window_x").value, "16384 px", "the most")
    eq(row_of(m, "style").value, "Панель", "the panel")
    eq(row_of(m, "damage_numbers_style").value, "Плашки", "plates")
    eq(row_of(m, "damage_numbers_size").value, "250 %", "250 %"); eq(row_of(m, "enemy_hp_size").value, "50 %", "50 %")
    eq(row_of(m, "enemy_plate").value, "выкл", "the plate off")
    eq(row_of(m, "enemy_plate_size").value, "300 %", "300 %")
    eq(row_of(m, "hidden_stats").value, "выкл", "the hidden-stats panel off")
    eq(row_of(m, "hidden_stats").on, false, "off")
    eq(row_of(m, "hidden_stats_size").value, "50 %", "50 %")
    eq(row_of(m, "history_size").value, "32", "32")
    eq(row_of(m, "language").value, "Как в игре", "auto: same as the game")
    eq(row_of(m, "toggle_key").value, "PageUp", "Menu.key_name")
    local short = { off = "выкл", current = "HP", current_max = "HP / макс.", percent = "%", current_percent = "HP и %",
        all = "HP / макс. и %" }
    local short_en = { off = "off", current = "HP", current_max = "HP / max", percent = "%",
        current_percent = "HP and %", all = "HP / max and %" }
    for format, text in pairs(short) do
        s:set("boss_hp_numbers", format)
        s:set("enemy_hp_numbers", format)
        i18n.set("ru")
        m = SettingsView.build(s, i18n)
        eq(row_of(m, "boss_hp_numbers").value, text, format .. " at the boss")
        eq(row_of(m, "enemy_hp_numbers").value, text, format .. " over enemies")
        i18n.set("en")
        eq(row_of(SettingsView.build(s, i18n), "boss_hp_numbers").value, short_en[format], format .. " in English")
    end
    -- in English: the units and the names
    m = SettingsView.build(s, i18n)
    eq(row_of(m, "summary_autohide").value, "10 s", "seconds"); eq(row_of(m, "scale").value, "60%", "a percent")
    eq(row_of(m, "window_x").value, "16384 px", "px"); eq(row_of(m, "style").value, "Panel", "Panel")
    eq(row_of(m, "language").value, "Same as game", "auto"); eq(row_of(m, "debug").value, "off", "off")
    eq(T.str(m.groups[2].columns), "Fight Summary", "the columns")
    s:set("summary_autohide", 0)
    eq(row_of(SettingsView.build(s, i18n), "summary_autohide").value, "never", "never")
    s:set("style", "frameless")
    eq(row_of(SettingsView.build(s, i18n), "style").value, "No panel", "No panel")
end)

test("the halo and the bars: rows only without the panel, built and selected so", function()
    local s = make_settings()
    eq(s.values.style, "frameless", "the default: no panel")
    local halo, bars = index_of("halo"), index_of("bar_px")
    eq(SettingsView.shown(s, halo), true, "the halo shown"); eq(SettingsView.shown(s, bars), true, "the bars shown")
    local m = SettingsView.build(s, i18n)
    eq(#m.groups[1].rows, 9, "nine rows")
    eq(row_of(m, "halo") ~= nil and row_of(m, "bar_px") ~= nil, true, "both in the model")
    local move = SettingsView.move
    eq(move(s, index_of("outline"), 1, { select_step = 1 }), halo, "Down from the outline: the halo")
    eq(move(s, index_of("window_x"), 1, { select_step = -1 }), bars, "Up from the position: the bars")
    -- the panel
    s:set("style", "panel")
    eq(SettingsView.shown(s, halo), false, "the halo hidden"); eq(SettingsView.shown(s, bars), false, "the bars hidden")
    for i, row in ipairs(SettingsView.ROWS) do
        if row.key ~= "halo" and row.key ~= "bar_px" then eq(SettingsView.shown(s, i), true, row.key .. " shown") end
    end
    m = SettingsView.build(s, i18n)
    eq(keys_of(m):find("halo", 1, true), nil, "no halo row"); eq(keys_of(m):find("bar_px", 1, true), nil, "no bars")
    eq(#m.groups[1].rows, 7, "seven rows")
    eq(m.groups[1].rows[5].key, "outline", "the outline"); eq(m.groups[1].rows[6].key, "window_x", "then the position")
    eq(move(s, index_of("outline"), 1, { select_step = 1 }), index_of("window_x"), "Down skips them")
    eq(move(s, index_of("window_x"), 1, { select_step = -1 }), index_of("outline"), "Up skips them")
    eq(move(s, index_of("window_x"), 1, { select_step = -1, step = 1 }), index_of("outline"), "with a step too")
    -- a selection left on a hidden row: the nearest shown row above
    eq(move(s, halo, 1, {}), index_of("outline"), "on the halo: the outline")
    eq(move(s, bars, 1, {}), index_of("outline"), "on the bars: the outline")
    eq(move(s, bars, 1, { select_step = 1 }), index_of("window_x"), "Down from the bars: the position")
    eq(move(s, halo, 1, { select = halo }), index_of("outline"), "a click on it (not drawn): the outline")
    -- back to no panel: there again
    s:set("style", "frameless")
    eq(#SettingsView.build(s, i18n).groups[1].rows, 9, "nine rows again")
    eq(move(s, index_of("outline"), 1, { select_step = 1 }), halo, "Down: the halo again")
end)

test("the table: Left/Right between a row's cells past a «—», the setting under the selection", function()
    local s = make_settings()
    local move = SettingsView.move
    local enemies, damage, taken = index_of("section_enemies"), index_of("section_damage"), index_of("section_taken")
    local function at(sel, col, a)
        local i, c = move(s, sel, col, a)
        return i .. ":" .. c
    end
    -- a row of two: Left the fight's cell, Right the summary's; no further
    eq(at(damage, 1, { step = 1 }), damage .. ":2", "Right: the summary cell")
    eq(at(damage, 2, { step = -1 }), damage .. ":1", "Left: the fight cell")
    eq(at(damage, 1, { step = -1 }), damage .. ":1", "Left on the fight cell: stays")
    eq(at(damage, 2, { step = 1 }), damage .. ":2", "Right on the summary cell: stays")
    -- a «—»: never selected
    eq(at(enemies, 1, {}), enemies .. ":2", "the enemies: only the summary cell")
    eq(at(enemies, 2, { step = -1 }), enemies .. ":2", "Left: no fight cell, stays")
    eq(at(taken, 2, {}), taken .. ":1", "the damage taken: only the fight cell")
    eq(at(taken, 1, { step = 1 }), taken .. ":1", "Right: no summary cell, stays")
    eq(at(index_of("section_armor"), 1, { step = -1 }), index_of("section_armor") .. ":2", "the armor: summary")
    -- Up/Down keep the column where there is a cell
    eq(at(enemies, 2, { select_step = 1 }), damage .. ":2", "Down: the summary column")
    eq(at(damage, 1, { select_step = 1 }), taken .. ":1", "Down: the fight column")
    eq(at(damage, 1, { select_step = -1 }), enemies .. ":2", "Up to the enemies: their summary cell")
    eq(at(taken, 1, { select_step = 1, step = 1 }), index_of("section_heal") .. ":2", "Down, then Right")
    -- a cell clicked
    eq(at(index_of("scale"), 1, { select = damage, col = 2 }), damage .. ":2", "a click: its row and cell")
    eq(at(damage, 2, { select = taken, col = 2 }), taken .. ":1", "a click on a «—»: the cell there is")
    eq(at(damage, 2, { select = damage }), damage .. ":2", "a click on the label: the cell kept")
    -- the group jumps land on the table's first row; the column of a row outside the table is kept
    eq(at(1, 1, { group_step = 1 }), enemies .. ":2", "PgDn: the enemies, their summary cell")
    eq(at(index_of("scale"), 2, { select_step = 1 }), index_of("opacity") .. ":2", "outside the table: kept")
    eq(at(index_of("scale"), 1, { step = 1 }), index_of("scale") .. ":1", "a step outside the table: no cell move")
    -- the setting under the selection
    local target = SettingsView.target
    eq(T.str({ target(damage, 1) }), "live_damage cell", "the fight's damage")
    eq(T.str({ target(damage, 2) }), "summary_damage cell", "the summary's damage")
    eq(T.str({ target(index_of("section_allies"), 1) }), "show_allies cell", "the fight's allies")
    eq(T.str({ target(index_of("section_allies"), 2) }), "summary_allies cell", "the summary's allies")
    eq(target(enemies, 1), nil, "a «—»: none")
    eq(T.str({ target(index_of("scale"), 2) }), "scale number", "a number row: its own")
    eq(T.str({ target(index_of("debug"), 1) }), "debug switch", "a switch")
    eq(T.str({ target(index_of("toggle_key"), 1) }), "toggle_key key", "a key")
    eq(target(99, 1), nil, "no row")
    -- a table row has no step: Left/Right move between its cells
    eq(SettingsView.step(s, "section_damage", 1), nil, "no step for a table row")
end)

test("the help line of every row, in both languages", function()
    local s = make_settings()
    for _, lang in ipairs({ "ru", "en" }) do
        i18n.set(lang)
        local m = SettingsView.build(s, i18n)
        local n = 0
        for _, g in ipairs(m.groups) do
            for _, r in ipairs(g.rows) do
                n = n + 1
                eq(r.help ~= "" and r.help:find("setting_help", 1, true) == nil, true, r.key .. " in " .. lang)
                eq(r.help:find("%", 1, true) == nil or r.key:find("hp_numbers", 1, true) ~= nil, true,
                    r.key .. ": formatted in " .. lang .. ": " .. r.help)
            end
        end
        eq(n, #SettingsView.ROWS, "every row has one")
        -- the rows' own texts
        for _, key in ipairs({ "style", "scale", "opacity", "shadow", "outline", "halo", "bar_px", "window_x",
                               "window_y", "summary_autohide", "damage_numbers", "damage_numbers_style",
                               "damage_numbers_size", "enemy_hp_size", "player_numbers", "enemy_plate",
                               "enemy_plate_size", "hidden_stats", "hidden_stats_size", "history_file", "language",
                               "debug" }) do
            eq(row_of(m, key).help, i18n.t("setting_help_" .. key), key .. " in " .. lang)
        end
        -- the table's rows: one text naming the row; the Other row also says it covers «Падения и среда»
        for key in pairs(CELLS) do
            local r = row_of(m, key)
            local want = i18n.t("setting_help_section", r.label)
            if key == "section_other" then want = want .. " " .. i18n.t("setting_help_section_other") end
            eq(r.help, want, key .. " in " .. lang)
            eq(r.help:find(r.label, 1, true) ~= nil, true, key .. " names its row in " .. lang)
        end
        eq(row_of(m, "section_other").help:find(i18n.t("env"), 1, true) ~= nil, true,
            "the Other row names «Падения и среда» in " .. lang)
        -- the keys: what the key does, then how to choose another
        for _, key in ipairs({ "toggle_key", "journal_key", "settings_key" }) do
            eq(row_of(m, key).help, i18n.t("setting_help_key", i18n.t("setting_help_" .. key)), key .. " in " .. lang)
        end
        -- the journal names its key; the fights kept their most
        eq(row_of(m, "journal").help, i18n.t("setting_help_journal", "F7"), "the journal key in " .. lang)
        eq(row_of(m, "history_size").help, i18n.t("setting_help_history_size", 32), "up to 32 in " .. lang)
    end
    i18n.set("ru")
    local m = SettingsView.build(s, i18n)
    eq(row_of(m, "section_damage").help, "„Нанесено“ — показывать ли раздел в метре во время боя и в сводке после "
        .. "боя. — значит, такого раздела там нет.", "the table's row named")
    eq(row_of(m, "toggle_key").help, "Показать или скрыть метр. Enter — назначить другую клавишу.", "the meter's key")
    eq(row_of(m, "settings_key").help, "Открыть это окно. Enter — назначить другую клавишу.", "this window's key")
    eq(row_of(m, "journal").help, "Запоминать бои для журнала (F7).", "the journal")
    eq(row_of(m, "history_size").help, "Сколько последних боёв помнить, до 32.", "the fights kept")
    -- the HP numbers: the chosen format as it looks, each row its own
    eq(row_of(m, "boss_hp_numbers").help, "Как показывать здоровье. Сейчас: «12 340 / 18 000 · 69%».", "all")
    s:set("boss_hp_numbers", "current_percent")
    s:set("journal_key", 0x79)
    m = SettingsView.build(s, i18n)
    eq(row_of(m, "boss_hp_numbers").help, "Как показывать здоровье. Сейчас: «12 340 · 69%».", "HP and %")
    eq(row_of(m, "enemy_hp_numbers").help, "Как показывать здоровье. Сейчас: «12 340 / 18 000 · 69%».", "its own")
    eq(row_of(m, "journal").help, "Запоминать бои для журнала (F10).", "the journal's key as it is")
    s:set("enemy_hp_numbers", "off")
    eq(row_of(SettingsView.build(s, i18n), "enemy_hp_numbers").help, "Как показывать здоровье. Сейчас: «выкл».",
        "off")
    i18n.set("en")
    eq(row_of(SettingsView.build(s, i18n), "boss_hp_numbers").help, "How health is shown. Now: “12 340 · 69%”.",
        "in English")
end)

test("the background's help names no level the setting cannot reach", function()
    -- its least is 20 %: no «0 %», no number at all
    eq(Settings.LIMITS.opacity.min, 0.2, "20 % the least")
    for _, lang in ipairs({ "ru", "en" }) do
        i18n.set(lang)
        local help = row_of(SettingsView.build(make_settings(), i18n), "opacity").help
        eq(help:find("%d") == nil, true, "no number in " .. lang .. ": " .. help)
    end
    i18n.set("ru")
    eq(row_of(SettingsView.build(make_settings(), i18n), "opacity").help,
        "Насколько тёмная подложка: больше — темнее. Без панели — плотность ореола.", "the Russian")
end)

test("the texts of every row for the window's width: each label and every value it can show", function()
    for _, lang in ipairs({ "ru", "en" }) do
        i18n.set(lang)
        local list = SettingsView.texts(i18n)
        eq(#list, #SettingsView.ROWS, "every row, shown or not, in " .. lang)
        local by = {}
        for i, t in ipairs(list) do
            eq(t.key, SettingsView.ROWS[i].key, "in order")
            eq(t.kind, SettingsView.ROWS[i].kind, t.key .. " kind")
            eq(t.label, i18n.t("setting_" .. t.key), t.key .. " label")
            by[t.key] = t
        end
        local function has(key, text)
            for _, v in ipairs(by[key].values) do
                if v == text then return true end
            end
            return false
        end
        eq(by.halo ~= nil and by.bar_px ~= nil, true, "the halo and the bars too")
        eq(#by.section_damage.values, 0, "a table row: no values (its cells are switches)")
        eq(T.str(by.debug.values), i18n.t("switch_on") .. " " .. i18n.t("switch_off"), "a switch either way")
        eq(#by.boss_hp_numbers.values, 6, "the six HP formats")
        eq(has("boss_hp_numbers", i18n.t("hpfmt_all")), true, "all of them by name")
        eq(#by.language.values, 3, "three languages"); eq(has("language", i18n.t("lang_auto")), true, "auto")
        eq(#by.style.values, 2, "two styles")
        eq(T.str(by.window_x.values), i18n.t("svalue_px", 0) .. " " .. i18n.t("svalue_px", 16384), "both ends")
        eq(T.str(by.summary_autohide.values), i18n.t("svalue_never") .. " " .. i18n.t("svalue_sec", 600), "never")
        eq(by.scale.values[2], i18n.t("svalue_pct", 200), "the size at its most")
        eq(#by.toggle_key.values, 254, "every key code's name")
        eq(has("settings_key", "PageDown") and has("settings_key", "F8"), true, "names as the window shows them")
    end
    i18n.set("ru")
end)

test("Left/Right: a switch flips, a choice wraps round, a number steps within its limits", function()
    local s = make_settings()
    local step = SettingsView.step
    -- switches
    eq(step(s, "debug", 1), true, "off: Right turns it on"); eq(step(s, "debug", -1), true, "and Left")
    eq(step(s, "outline", 1), false, "on: off")
    -- choices go round
    eq(step(s, "language", 1), "en", "auto -> en"); eq(step(s, "language", -1), "ru", "auto <- ru (round)")
    s:set("language", "ru")
    eq(step(s, "language", 1), "auto", "ru -> auto (round)"); eq(step(s, "language", -1), "en", "ru <- en")
    eq(step(s, "style", 1), "panel", "frameless -> panel"); eq(step(s, "style", -1), "panel", "and round")
    -- numbers: the step of each, from the defaults
    local want = { summary_autohide = 1, history_size = 1, window_x = 10, window_y = 10, opacity = 0.05, scale = 0.05,
        shadow = 0.1, bar_px = 1, enemy_hp_size = 0.1, damage_numbers_size = 0.1, enemy_plate_size = 0.1,
        hidden_stats_size = 0.1 }
    for key, by in pairs(want) do near(SettingsView.STEPS[key], by, 1e-12, "the step of " .. key) end
    for key in pairs(SettingsView.STEPS) do eq(want[key] ~= nil, true, key .. " is a number with a step") end
    for _, row in ipairs(SettingsView.ROWS) do
        if row.kind == "number" then eq(SettingsView.STEPS[row.key] ~= nil, true, row.key .. " has a step") end
    end
    eq(step(s, "history_size", 1), 11, "10 + 1"); eq(step(s, "history_size", -1), 9, "10 - 1")
    eq(math.type(step(s, "history_size", 1)), "integer", "a whole number")
    eq(step(s, "window_x", 1), 50, "40 + 10"); eq(step(s, "window_y", -1), 290, "300 - 10")
    eq(step(s, "summary_autohide", 1), 1, "0 + 1 s")
    eq(step(s, "bar_px", 1), 4, "3 + 1")
    near(step(s, "opacity", 1), 0.83, 1e-12, "0.78 + 0.05"); near(step(s, "opacity", -1), 0.73, 1e-12, "0.78 - 0.05")
    near(step(s, "scale", 1), 1.05, 1e-12, "1 + 0.05"); near(step(s, "shadow", 1), 0.9, 1e-12, "0.8 + 0.1")
    eq(step(s, "shadow", 1), 0.9, "no float dust: exactly 0.9")
    -- clamped by the limits; at an end there is no step
    eq(step(s, "summary_autohide", -1), nil, "0 is the least")
    s:set("history_size", 32); eq(step(s, "history_size", 1), nil, "32 is the most")
    s:set("scale", 2); eq(step(s, "scale", 1), nil, "scale 2 is the most")
    s:set("scale", 1.98); near(step(s, "scale", 1), 2, 1e-12, "a step past the end stops at it")
    s:set("opacity", 0.22); near(step(s, "opacity", -1), 0.2, 1e-12, "and at the least")
    s:set("window_x", 5); eq(step(s, "window_x", -1), 0, "window_x stops at 0")
    s:set("bar_px", 8); eq(step(s, "bar_px", 1), nil, "bar_px 8")
    s:set("shadow", 1); eq(step(s, "shadow", 1), nil, "shadow 1")
    -- the HP numbers go round their six formats, each on its own
    local order = { "off", "current", "current_max", "percent", "current_percent", "all" }
    for _, key in ipairs({ "enemy_hp_numbers", "boss_hp_numbers" }) do
        eq(step(s, key, 1), "off", key .. ": all -> off (round)")
        eq(step(s, key, -1), "current_percent", key .. ": all <- current_percent")
        for i, value in ipairs(order) do
            s:set(key, value)
            eq(step(s, key, 1), order[i % #order + 1], value .. " -> the next")
            eq(step(s, key, -1), order[(i - 2) % #order + 1], value .. " <- the previous")
        end
    end
    -- the sizes: 10 % a step, from 50 % to 300 %, no float dust
    for _, key in ipairs({ "enemy_hp_size", "damage_numbers_size", "enemy_plate_size", "hidden_stats_size" }) do
        eq(step(s, key, 1), 1.1, key .. ": 1 + 0.1"); eq(step(s, key, -1), 0.9, "1 - 0.1")
        s:set(key, 1.1); eq(step(s, key, 1), 1.2, "1.1 + 0.1 is exactly 1.2")
        s:set(key, 2.95); eq(step(s, key, 1), 3, "a step past the end stops at it")
        s:set(key, 3); eq(step(s, key, 1), nil, "300 % is the most")
        s:set(key, 0.5); eq(step(s, key, -1), nil, "50 % is the least")
        eq(step(s, key, 1), 0.6, "0.5 + 0.1")
    end
    -- the damage numbers: the switch flips, the style goes round its two
    eq(step(s, "damage_numbers", 1), false, "on: off")
    eq(step(s, "damage_numbers_style", 1), "plates", "rise -> plates")
    eq(step(s, "damage_numbers_style", -1), "plates", "rise <- plates (round)")
    s:set("damage_numbers_style", "plates")
    eq(step(s, "damage_numbers_style", 1), "rise", "plates -> rise (round)")
    -- the enemy plate: the switch flips; the player's numbers too
    eq(step(s, "enemy_plate", 1), false, "the plate on: off")
    eq(step(s, "player_numbers", 1), false, "the player's numbers on: off")
    eq(step(s, "hidden_stats", 1), false, "the hidden-stats panel on: off")
    -- a key row has no step: Enter waits for a key
    eq(step(s, "toggle_key", 1), nil, "a key"); eq(step(s, "settings_key", -1), nil, "the settings key")
    -- a step through the settings is valid
    local s2 = make_settings()
    for _, row in ipairs(SettingsView.ROWS) do
        for _, dir in ipairs({ -1, 1 }) do
            local v = step(s2, row.key, dir)
            if v ~= nil then eq(s2:set(row.key, v), true, row.key .. " " .. dir .. " is accepted") end
        end
    end
end)

test("the selection: Up/Down stop at the ends, PgUp/PgDn jump between groups", function()
    local s = make_settings()
    local function move(sel, a) return (SettingsView.move(s, sel, 1, a)) end
    local n = #SettingsView.ROWS
    eq(move(1, { select_step = -1 }), 1, "Up on the first row")
    eq(move(1, { select_step = 1 }), 2, "Down")
    eq(move(n, { select_step = 1 }), n, "Down on the last row")
    eq(move(5, { select = 9 }), 9, "a row clicked")
    eq(move(5, { select = 99 }), n, "clamped")
    eq(move(5, { select = 0 }), 1, "clamped to the first")
    eq(move(99, {}), n, "a selection past the end is clamped")
    eq(move(nil, {}), 1, "none: the first row")
    eq(move(5, { select = 3, select_step = 1 }), 4, "a click, then a step")
    eq(select(2, SettingsView.move(s, 1, nil, {})), 1, "no column: the first")
    -- the first row of each group
    local first, at = {}, 0
    for gi, want in ipairs(WANT) do
        first[gi] = at + 1
        at = at + #want[2]
    end
    eq(move(1, { group_step = 1 }), first[2], "PgDn: the next group's first row")
    eq(move(first[2] + 3, { group_step = 1 }), first[3], "from inside a group")
    eq(move(first[2] + 3, { group_step = -1 }), first[1], "PgUp: the previous group's first row")
    eq(move(first[3], { group_step = -1 }), first[2], "from a group's first row")
    eq(move(3, { group_step = -1 }), 3, "PgUp in the first group: nothing")
    for gi = 2, #WANT - 1 do eq(move(first[gi], { group_step = 1 }), first[gi + 1], "PgDn from group " .. gi) end
    local last = first[#WANT]
    eq(move(last + 1, { group_step = 1 }), last + 1, "PgDn in the last group: nothing")
    eq(last + 1, n, "language and debug are the last rows")
    -- the enemy plate's group right after the health numbers'
    local plate = index_of("enemy_plate")
    eq(SettingsView.ROWS[plate - 1].key, "enemy_hp_size", "after the health numbers")
    eq(SettingsView.ROWS[plate].group, SettingsView.ROWS[plate - 1].group + 1, "a group of its own")
    eq(SettingsView.ROWS[plate + 1].key, "enemy_plate_size", "its size under it")
    eq(move(index_of("boss_hp_numbers"), { group_step = 1 }), plate, "PgDn from the health numbers: the plate")
    -- the hidden-stats group right after the plate's
    local hidden = index_of("hidden_stats")
    eq(SettingsView.ROWS[hidden - 1].key, "enemy_plate_size", "after the plate")
    eq(SettingsView.ROWS[hidden].group, SettingsView.ROWS[plate].group + 1, "a group of its own")
    eq(SettingsView.ROWS[hidden + 1].key, "hidden_stats_size", "its size under it")
    eq(SettingsView.ROWS[hidden + 2].key, "journal", "then the journal's group")
    eq(move(plate, { group_step = 1 }), hidden, "PgDn from the plate: the hidden stats")
    eq(SettingsView.GROUPS[SettingsView.ROWS[hidden].group].id, "hidden_stats", "its id")
    eq(move(1, { group_step = 1, select_step = 1 }), first[2], "a step, then the jump")
end)

i18n.set("en")
T.finish()
