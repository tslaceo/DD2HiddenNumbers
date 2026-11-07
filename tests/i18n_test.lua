package.path = "mod/reframework/autorun/?.lua;tests/?.lua;" .. package.path

local T = require("testlib")
local test, eq = T.test, T.eq
local i18n = require("DD2DamageMeter/i18n")
local en = require("DD2DamageMeter/lang/en")
local ru = require("DD2DamageMeter/lang/ru")

-- Keys the mod relies on, plus the settings labels.
local KEYS = {
    "damage_to_enemies", "damage_to_party", "healing", "per_sec", "fight_over", "victory", "enemies",
    "more_enemies", "dealt", "healed", "armor", "enemy_defence_saved", "party_armor_saved",
    "allies", "other", "normal_attacks", "skill", "item", "killed", "history", "details_hits",
    "details_total", "details_max", "type_Slash", "type_Blow", "type_Shoot", "type_Magic", "type_Enchant",
    "type_NonMagicElement", "type_Fixed",
    "setting_language", "setting_toggle_key", "setting_summary_autohide", "setting_history_size",
    "setting_window_x", "setting_window_y", "setting_opacity", "setting_scale", "setting_show_allies",
    "setting_debug", "lang_auto", "lang_en", "lang_ru",
    -- summary enemy rows and the character details
    "enemy_group_hp", "killed_count", "more_enemies_same_hp", "details_perfect", "details_full_damage", "details_armor_saved",
    "details_guard",
    -- DoT rows in the character details
    "dot_burn", "dot_poison", "dot_shock", "dot_frost", "dot",
    -- the look of the window: its settings and the names of the styles
    "setting_style", "setting_halo", "setting_bar_px", "setting_outline", "setting_shadow",
    "style_frameless", "style_panel",
    -- 0.2: the block switches and the journal's settings; the settings window and the menu's line about it
    "settings_title", "sgroup_journal",
    "switch_on", "switch_off", "settings_hint", "settings_in_window", "open_settings", "setting_settings_key",
    "setting_live_damage", "setting_live_taken", "setting_live_heal", "setting_live_other",
    "setting_summary_enemies", "setting_summary_damage", "setting_summary_armor", "setting_summary_heal",
    "setting_summary_allies", "setting_summary_other",
    "setting_journal", "setting_journal_key", "setting_history_file",
    -- the numbers over the enemies' HP bars: their setting and its six choices as they look
    "setting_enemy_hp_numbers", "hpnum_off", "hpnum_current", "hpnum_current_max",
    "hpnum_percent", "hpnum_current_percent", "hpnum_all", "setting_enemy_hp_size", "setting_boss_hp_numbers",
    -- the damage numbers at the hit point: their group, their settings and the two styles
    "sgroup_damage_numbers", "setting_damage_numbers", "setting_damage_numbers_style", "setting_damage_numbers_size",
    "dnum_rise", "dnum_plates",
    -- the settings window's new look: groups, the table, values with units, the HP formats by name, the menu's label
    "sgroup_look", "sgroup_show", "sgroup_hp_numbers", "sgroup_keys", "sgroup_other", "scol_live", "scol_summary",
    "svalue_pct", "svalue_px", "svalue_sec", "svalue_never", "hpfmt_off", "hpfmt_current", "hpfmt_current_max",
    "hpfmt_percent", "hpfmt_current_percent", "hpfmt_all", "menu_settings_key",
    -- the enemies' own damage, a party member's own damage and heals by source
    "env", "own_blood_pact", "own_self", "own_lifesteal", "own_regen", "setting_help_section_other",
    -- the enemy plate's texts, and its table's column headers
    "plate_more", "plate_immune", "plate_you", "plate_head", "plate_weak", "plate_enchant", "plate_no_data",
    "plate_others", "plate_col_Slash", "plate_col_Blow", "plate_col_Shoot", "plate_col_Fire", "plate_col_Ice",
    "plate_col_Thunder", "plate_col_Light", "plate_col_Magic",
    -- the enemy's state next to its name
    "plate_state_Angry", "plate_state_Injured", "plate_state_Down", "plate_state_Flight", "plate_state_HeartExposure",
    "plate_state_Rampage", "plate_state_Possess", "plate_state_GhostWrapped",   -- seen by the collector
    -- the status buildup bars under the boss bar: their switch, and the hits left in every plural form
    "setting_buildup_bars", "setting_help_buildup_bars", "buildup_hits_one", "buildup_hits_few", "buildup_hits_many",
    "buildup_hits_other", "status_WetElectric", "buildup_lean", "buildup_blown",
    -- an active status's time left and the resistance
    "buildup_left", "buildup_resist",
    -- the player's own numbers by the HUD's bars: their switch
    "setting_player_numbers", "setting_help_player_numbers",
    -- the enemy plate's settings group
    "sgroup_enemy_plate", "setting_enemy_plate", "setting_enemy_plate_size", "setting_help_enemy_plate",
    "setting_help_enemy_plate_size",
    -- the hidden-stats panel's own texts
    "hs_none", "hs_legend", "hs_yours", "hs_pawns", "hs_base_hint",
    -- whose base in English, the total line, the damage taken
    "hs_whose_yours", "hs_whose_pawns", "hs_whose_none", "hs_total_phys", "hs_total_magic", "hs_damage_phys_yours",
    "hs_damage_phys_pawns", "hs_damage_magic_yours", "hs_damage_magic_pawns",
    -- the hidden-stats panel's settings group
    "sgroup_hidden_stats", "setting_hidden_stats", "setting_hidden_stats_size", "setting_help_hidden_stats",
    "setting_help_hidden_stats_size",
}

-- The hidden-stats panel's texts, key -> { ru, en }.
local HS_TEXTS = {
    hs_none = { "числа в игре не нашлось", "no number found in the game" },
    hs_legend = { "≈ другие моды не подтверждают · ? догадка", "≈ not confirmed by other mods · ? a guess" },
    -- the base in brackets, then what it gives now; English says whose base before the stat
    hs_yours = { "(у тебя %s) — сейчас %s", "(%s) — %s now" },
    hs_pawns = { "(у пешки %s) — сейчас %s", "(%s) — %s now" },
    hs_base_hint = { "(число в скобках на экране статуса)", "(the number in brackets on the status screen)" },
    hs_whose_yours = { "", "your" },
    hs_whose_pawns = { "", "the pawn's" },
    hs_whose_none = { "", "the" },
    -- the total before → after; the damage taken
    hs_total_phys = { "защита %s → %s (%s)", "defense %s → %s (%s)" },
    hs_total_magic = { "маг. защита %s → %s (%s)", "magick defense %s → %s (%s)" },
    hs_damage_phys_yours = { "%s физ. урона по тебе", "%s physical damage taken" },
    hs_damage_phys_pawns = { "%s физ. урона по пешке", "%s physical damage the pawn takes" },
    hs_damage_magic_yours = { "%s маг. урона по тебе", "%s magick damage taken" },
    hs_damage_magic_pawns = { "%s маг. урона по пешке", "%s magick damage the pawn takes" },
}

-- The settings window's texts (its new look: short names, a table, units, help lines), key -> { ru, en }.
local SETTINGS_TEXTS = {
    settings_title = { "Настройки", "Settings" },
    switch_on = { "вкл", "on" },
    switch_off = { "выкл", "off" },
    settings_in_window = { "Настройки — в окне мода, клавиша %s", "The settings are in the mod's own window, key %s" },
    open_settings = { "Открыть окно настроек", "Open the settings window" },
    menu_settings_key = { "Клавиша окна настроек", "Settings window key" },
    -- the groups
    sgroup_look = { "Вид метра", "Meter look" },
    sgroup_show = { "Что показывать", "What to show" },
    sgroup_damage_numbers = { "Цифры урона", "Damage numbers" },
    sgroup_hp_numbers = { "Цифры здоровья", "Health numbers" },
    sgroup_enemy_plate = { "Плашка врагов", "Enemy plate" },
    sgroup_hidden_stats = { "Скрытые числа", "Hidden stats" },
    sgroup_journal = { "Журнал", "Journal" },
    sgroup_keys = { "Клавиши", "Keys" },
    sgroup_other = { "Прочее", "Other" },
    -- the rows
    setting_style = { "Стиль", "Style" },
    setting_scale = { "Размер", "Size" },
    setting_opacity = { "Фон", "Background" },
    setting_shadow = { "Тень", "Shadow" },
    setting_outline = { "Обводка", "Outline" },
    setting_halo = { "Ореол", "Halo" },
    setting_bar_px = { "Полосы", "Bars" },
    setting_window_x = { "Позиция X", "Position X" },
    setting_window_y = { "Позиция Y", "Position Y" },
    scol_live = { "Бой", "Fight" },
    scol_summary = { "Сводка", "Summary" },
    setting_section_enemies = { "Враги", "Enemies" },
    setting_section_damage = { "Нанесено", "Dealt" },
    setting_section_taken = { "Получено", "Taken" },
    setting_section_heal = { "Лечение", "Healing" },
    setting_section_armor = { "Броня", "Armor" },
    setting_section_allies = { "Союзники", "Allies" },
    setting_section_other = { "Прочее", "Other" },
    setting_summary_autohide = { "Сводка гаснет через", "Summary hides after" },
    setting_damage_numbers = { "Показывать", "Show" },
    setting_damage_numbers_style = { "Вид", "Style" },
    setting_damage_numbers_size = { "Размер", "Size" },
    setting_boss_hp_numbers = { "У босса", "At the boss" },
    setting_enemy_hp_numbers = { "Над врагами", "Over enemies" },
    setting_enemy_hp_size = { "Размер", "Size" },
    setting_player_numbers = { "Моё здоровье и выносливость", "My health and stamina" },
    setting_enemy_plate = { "Показывать", "Show" },
    setting_enemy_plate_size = { "Размер", "Size" },
    setting_hidden_stats = { "Показывать", "Show" },
    setting_hidden_stats_size = { "Размер", "Size" },
    setting_journal = { "Вести журнал", "Keep a journal" },
    setting_history_size = { "Хранить боёв", "Fights kept" },
    setting_history_file = { "Сохранять между запусками", "Save between sessions" },
    setting_toggle_key = { "Метр", "Meter" },
    setting_journal_key = { "Журнал", "Journal" },
    setting_settings_key = { "Настройки", "Settings" },
    setting_language = { "Язык", "Language" },
    setting_debug = { "Отладка", "Debug" },
    -- the switches of the sections keep their own names
    setting_live_damage = { "Урон по врагам", "Damage to enemies" },
    setting_live_taken = { "Урон по группе", "Damage to party" },
    setting_live_heal = { "Лечение", "Healing" },
    setting_show_allies = { "Союзники", "Allies" },
    setting_live_other = { "Прочее", "Other" },
    setting_summary_enemies = { "Враги", "Enemies" },
    setting_summary_damage = { "Нанесено", "Dealt" },
    setting_summary_armor = { "Броня", "Armor" },
    setting_summary_heal = { "Лечение", "Healing" },
    setting_summary_allies = { "Союзники", "Allies" },
    setting_summary_other = { "Прочее", "Other" },
    -- the values
    style_frameless = { "Без панели", "No panel" },
    style_panel = { "Панель", "Panel" },
    lang_auto = { "Как в игре", "Same as game" },
    dnum_rise = { "Взлетают", "Rise" },
    dnum_plates = { "Плашки", "Plates" },
    hpfmt_off = { "выкл", "off" },
    hpfmt_current = { "HP", "HP" },
    hpfmt_current_max = { "HP / макс.", "HP / max" },
    hpfmt_percent = { "%", "%" },
    hpfmt_current_percent = { "HP и %", "HP and %" },
    hpfmt_all = { "HP / макс. и %", "HP / max and %" },
    svalue_pct = { "%d %%", "%d%%" },
    svalue_px = { "%d px", "%d px" },
    svalue_sec = { "%d с", "%d s" },
    svalue_never = { "никогда", "never" },
    -- each HP format as it looks (the help line of the HP rows shows it)
    hpnum_off = { "выкл", "off" },
    hpnum_current = { "12 340", "12 340" },
    hpnum_current_max = { "12 340 / 18 000", "12 340 / 18 000" },
    hpnum_percent = { "69%", "69%" },
    hpnum_current_percent = { "12 340 · 69%", "12 340 · 69%" },
    hpnum_all = { "12 340 / 18 000 · 69%", "12 340 / 18 000 · 69%" },
    -- the help lines (the table's line without «этот», to fit two lines)
    setting_help_style = { "Панель — тёмная подложка под метром. Без панели — только текст и полосы.",
        "Panel: a dark backing under the meter. No panel: only the text and the bars." },
    setting_help_scale = { "Размер всего метра: текста, полос и отступов.",
        "The size of the whole meter: text, bars and spacing." },
    setting_help_opacity = { "Насколько тёмная подложка: больше — темнее. Без панели — плотность ореола.",
        "How dark the backing is: more is darker. Without the panel, how dense the halo is." },
    setting_help_shadow = { "Тень под текстом и цифрами.", "A shadow under the text and the numbers." },
    setting_help_outline = { "Тёмная обводка вокруг цифр, чтобы читались на светлом фоне.",
        "A dark outline around the numbers, so they read on a bright background." },
    setting_help_halo = { "Мягкое тёмное пятно за текстом. Работает только без панели.",
        "A soft dark patch behind the text. Only without the panel." },
    setting_help_bar_px = { "Толщина полос урона. Работает только без панели.",
        "How thick the damage bars are. Only without the panel." },
    setting_help_window_x = { "Левый край метра от левого края экрана.",
        "The meter's left edge from the left of the screen." },
    setting_help_window_y = { "Верхний край метра от верха экрана.", "The meter's top edge from the top of the screen." },
    setting_help_section = {
        "„%s“ — показывать ли раздел в метре во время боя и в сводке после боя. — значит, такого раздела там нет.",
        "“%s”: whether the meter shows this section in a fight and in the summary after it. — means none there." },
    setting_help_summary_autohide = { "Через сколько секунд после боя прятать сводку. 0 — никогда не прятать.",
        "How many seconds after a fight the summary hides. 0: never." },
    setting_help_damage_numbers = { "Числа урона в точке удара по врагу, в цвете бойца.",
        "Damage numbers where a hit lands on an enemy, in the fighter's color." },
    setting_help_damage_numbers_style = { "Плашки — стоят на месте. Взлетают — поднимаются и тают.",
        "Plates stand in place. Rise: they float up and fade." },
    setting_help_damage_numbers_size = { "Размер чисел урона.", "The size of the damage numbers." },
    setting_help_hp_numbers = { "Как показывать здоровье. Сейчас: «%s».", "How health is shown. Now: “%s”." },
    setting_help_enemy_hp_size = { "Размер цифр здоровья у босса и над врагами.",
        "The size of the health numbers at the boss and over enemies." },
    setting_help_player_numbers = {
        "Числа у твоих полос здоровья и выносливости: сейчас / предел, в скобках полный предел, когда он урезан.",
        "Numbers by your health and stamina bars: now / max, with the full max in brackets when it is cut." },
    setting_help_enemy_plate = { "В бою: к чему уязвимы враги рядом, что их не берёт и как по ним проходит твой урон.",
        "In a fight: what the enemies near you are weak to, what does not work on them and how your damage fares." },
    setting_help_enemy_plate_size = { "Размер плашки врагов.", "The size of the enemy plate." },
    setting_help_hidden_stats = {
        "Сколько на деле даёт усилитель или кольцо под курсором: в гильдии, в предметах и при смене снаряжения.",
        "What the augment or ring under the cursor really gives, in numbers: at the guild, in your items and when "
            .. "changing equipment." },
    setting_help_hidden_stats_size = { "Размер панели скрытых чисел.", "The size of the hidden stats panel." },
    setting_help_journal = { "Запоминать бои для журнала (%s).", "Remember fights for the journal (%s)." },
    setting_help_history_size = { "Сколько последних боёв помнить, до %d.",
        "How many recent fights to remember, up to %d." },
    setting_help_history_file = { "Хранить бои в файле history.json, чтобы они не пропадали после выхода из игры.",
        "Keep the fights in history.json, so they are still there after you quit the game." },
    setting_help_toggle_key = { "Показать или скрыть метр.", "Show or hide the meter." },
    setting_help_journal_key = { "Открыть журнал боёв.", "Open the fight journal." },
    setting_help_settings_key = { "Открыть это окно.", "Open this window." },
    setting_help_key = { "%s Enter — назначить другую клавишу.", "%s Enter: choose another key." },
    setting_help_language = { "Язык мода. «Как в игре» — тот же, что выбран в игре.",
        "The mod's language. “Same as game”: the one the game is in." },
    setting_help_debug = { "Записывать отладочный лог для разработчика. Обычно не нужно.",
        "Write a debug log for the developer. Usually not needed." },
    -- the hint: two lines of text in three, to fit the narrower window
    settings_hint = {
        "Вверх/Вниз — выбор · Влево/Вправо — изменить\nEnter — вкл/выкл · PgUp/PgDn — группы\n"
            .. "%s — закрыть · мышь — с меню REFramework",
        "Up/Down — select · Left/Right — change\nEnter — on/off · PgUp/PgDn — groups\n"
            .. "%s — close · mouse — with the REFramework menu" },
}

-- The journal's texts, key -> { ru, en }.
local JOURNAL_TEXTS = {
    decimal_sep = { ",", "." },
    element_Fire = { "Огонь", "Fire" }, element_Ice = { "Лёд", "Ice" }, element_Thunder = { "Молния", "Lightning" },
    element_Light = { "Свет", "Holy" }, element_Dark = { "Тьма", "Dark" },
    weak_magic_all = { "Вся магия", "All magick" }, weak_physics_all = { "Вся физика", "All physical" },
    status_Poison = { "Отравление", "Poison" }, status_VirulentPoison = { "Сильный яд", "Virulent poison" },
    status_Sleep = { "Сон", "Sleep" }, status_Faint = { "Обморок", "Faint" },
    status_Frostbite = { "Обморожение", "Frostbite" }, status_Freeze = { "Заморозка", "Freeze" },
    status_Electric = { "Электричество", "Shock" }, status_Wet = { "Намокание", "Wet" },
    status_Oil = { "Смола", "Tar" }, status_FireSpread = { "Горение", "Burning" },
    status_OilSpread = { "Горящая смола", "Burning tar" }, status_Silence = { "Немота", "Silence" },
    status_Stone = { "Окаменение", "Petrification" }, status_Blind = { "Ослепление", "Blindness" },
    job_1 = { "Боец", "Fighter" }, job_2 = { "Лучник", "Archer" }, job_3 = { "Маг", "Mage" },
    job_4 = { "Вор", "Thief" }, job_5 = { "Воин", "Warrior" }, job_6 = { "Чародей", "Sorcerer" },
    job_7 = { "Мистический копейщик", "Mystic Spearhand" }, job_8 = { "Маг-лучник", "Magick Archer" },
    job_9 = { "Иллюзионист", "Trickster" }, job_10 = { "Ратник", "Warfarer" },
    jtab_summary = { "Сводка", "Summary" }, jtab_enemies = { "Враги", "Enemies" }, jtab_skills = { "Навыки", "Skills" },
    jtab_party = { "Получено", "Taken" }, jtab_heal = { "Лечение", "Healing" },
    jtab_chart = { "Диаграмма", "Chart" }, jtab_record = { "Запись", "Record" },
    jfight_of = { "бой %d из %d", "fight %d of %d" }, jno_fights = { "Боёв пока нет", "No fights yet" },
    jmore_kinds = { "ещё %d", "%d more" },
    jnum_dps = { "Урон в секунду", "Damage per second" }, jnum_taken = { "Получено", "Taken" },
    jenemies_count = { "Враги · %d", "Enemies · %d" }, jkilled_at = { "убит на %s", "killed at %s" },
    jkilled_by = { "добил %s", "finished by %s" },
    jgame_says = { "Что говорит игра", "What the game says" }, jweak = { "Уязвим:", "Weak to:" },
    jresist = { "Устойчив:", "Resists:" }, jimmune = { "Не действует:", "Immune to:" }, jnone = { "нет", "none" },
    jdefence = { "Защита", "Defense" }, jmagic_defence = { "Маг. защита", "Magick defense" },
    jhit_with = { "Чем его били", "What hit it" }, jparts_type = { "%s: голова %s · туловище %s", "%s: head %s · body %s" },
    jwho = { "Кто чем нанёс", "Who dealt what" }, jattacks = { "Кого бил сам", "Whom it hit" },
    no_data = { "нет данных", "no data" }, jno_hits = { "Ударов не было", "No hits" },
    jno_damage = { "Урона не было", "No damage" },
    eff_invalid = { "не действует", "no effect" }, eff_resist = { "плохо", "poor" },
    eff_effective = { "хорошо", "good" },
    jcol_skill = { "Навык · тип", "Skill · type" }, jcol_damage = { "Урон", "Damage" },
    jcol_avg = { "Средний", "Average" }, jcol_share = { "Доля", "Share" }, jcol_mult = { "Множ.", "Mult." },
    jcol_skill_only = { "Навык", "Skill" },
}

-- The journal's new look (the redesign): renamed and new texts, key -> { ru, en }.
local REDESIGN_TEXTS = {
    jtab_party = { "Получено", "Taken" }, jnum_taken = { "Получено", "Taken" },
    enemy_defence_saved = { "Срезано защитой врагов", "Cut by enemy defense" },
    party_armor_saved = { "Поглотила броня группы", "Absorbed by party armor" },
    details_armor_saved = { "Броня поглотила", "Armor absorbed" },
    unknown_skill = { "Неизвестный навык", "Unknown skill" },
    jtimes_one = { "%s раз", "%s time" }, jtimes_few = { "%s раза", "%s times" },
    jtimes_many = { "%s раз", "%s times" }, jtimes_other = { "%s раза", "%s times" },
    journal_hint = { "%s закрыть · PgUp/PgDn вкладки · Home/End бои · Вверх/Вниз выбор · Влево/Вправо страницы",
                     "%s closes · PgUp/PgDn tabs · Home/End fights · Up/Down select · Left/Right pages" },
    journal_mouse = { "мышь — с меню REFramework", "mouse with the REFramework menu" },
    -- the meter keeps its own words for the damage to the party
    damage_to_party = { "Урон по группе", "Damage to party" }, setting_live_taken = { "Урон по группе", "Damage to party" },
}

-- The enemy plate's table, key -> { ru, en }: the short column headers, the immunity line with its kind's name.
local PLATE_TEXTS = {
    plate_col_Slash = { "Реж", "Slash" }, plate_col_Blow = { "Дроб", "Blunt" }, plate_col_Shoot = { "Стрел", "Rngd" },
    plate_col_Fire = { "Огонь", "Fire" }, plate_col_Ice = { "Лёд", "Ice" }, plate_col_Thunder = { "Молн", "Thndr" },
    plate_col_Light = { "Свет", "Holy" }, plate_col_Magic = { "Маг", "Mag" },
    plate_immune = { "%s: не действует %s", "%s: immune to %s" },
    -- the enemy's state next to its name
    plate_state_Angry = { "в ярости", "enraged" }, plate_state_Injured = { "ранен", "injured" },
    plate_state_Down = { "повален", "downed" }, plate_state_Flight = { "в полёте", "flying" },
    plate_state_HeartExposure = { "сердце открыто", "heart exposed" }, -- Fimbul's second state
    -- three more states the collector saw: Rampage (Низший демон), Possess (Блуждающий огонь),
    -- GhostWrapped (Дуллахан)
    plate_state_Rampage = { "в бешенстве", "rampaging" }, plate_state_Possess = { "вселился", "possessing" },
    plate_state_GhostWrapped = { "в призрачном покрове", "ghost-shrouded" },
    -- the status buildup bars' hits left: ru «удар / удара / ударов», en "hit / hits"
    buildup_hits_one = { "≈ %s удар", "≈ %s hit" }, buildup_hits_few = { "≈ %s удара", "≈ %s hits" },
    buildup_hits_many = { "≈ %s ударов", "≈ %s hits" }, buildup_hits_other = { "≈ %s удара", "≈ %s hits" },
    -- a wet enemy's shock, built up as a status of its own
    status_WetElectric = { "Электричество (мокрый)", "Shock (wet)" },
    -- the poise rows
    buildup_lean = { "Пошатнуть", "Stagger" }, buildup_blown = { "Опрокинуть", "Knock down" },
    -- an active status's time left and the resistance earlier triggers raised
    buildup_left = { "ещё %s с", "%s s left" }, buildup_resist = { "сопротивление %s %%", "resistance %s%%" },
    -- and the switch's help names both
    setting_help_buildup_bars = {
        "Под полосой босса: сколько до каждого статуса, примерно сколько ещё ударов, а у сработавшего — сколько он ещё "
            .. "длится и сопротивление к нему.",
        "Under the boss's bar: how far each status is from setting off and about how many more hits; once set off, how "
            .. "long it still lasts and the resistance." },
}

-- The string.format conversions of a text in order, e.g. "dss"; "%%" is a literal percent.
local function specs(text)
    text = text:gsub("%%%%", "")
    local out = {}
    for conv in text:gmatch("%%[%-%d%.]*(%a)") do out[#out + 1] = conv end
    return table.concat(out)
end

test("num groups thousands", function()
    eq(i18n.num(52898), "52 898", "52898")
    eq(i18n.num(908), "908", "908")
    eq(i18n.num(130642.4), "130 642", "130642.4")
    eq(i18n.num(0), "0", "0")
    eq(i18n.num(1000), "1 000", "1000")
    eq(i18n.num(1234567), "1 234 567", "1234567")
    eq(i18n.num(999.5), "1 000", "rounds before grouping")
    eq(i18n.num(-52898), "-52 898", "negative")
    eq(i18n.num(-0.2), "0", "no minus on a rounded zero")
end)

test("num, time and pct survive nil and non-finite input", function()
    eq(i18n.num(0 / 0), "0", "nan")
    eq(i18n.num(math.huge), "0", "inf")
    eq(i18n.num(nil), "0", "nil")
    eq(i18n.time(0 / 0), "0:00", "time nan")
    eq(i18n.pct(0 / 0), "0%", "pct nan")
    eq(i18n.pct(nil), "0%", "pct nil")
end)

test("time", function()
    eq(i18n.time(318.5), "5:18", "318.5")
    eq(i18n.time(0), "0:00", "0")
    eq(i18n.time(5), "0:05", "5")
    eq(i18n.time(59.99), "0:59", "truncates, never shows 0:60")
    eq(i18n.time(600), "10:00", "600")
    eq(i18n.time(3725), "62:05", "minutes keep growing past an hour")
    eq(i18n.time(-3), "0:00", "negative")
end)

test("pct is a whole percent of a 0..1 share", function()
    eq(i18n.pct(0.43), "43%", "0.43")
    eq(i18n.pct(44463 / 103428), "43%", "Guts share in the chimera fight")
    eq(i18n.pct(1), "100%", "1")
    eq(i18n.pct(0), "0%", "0")
    eq(i18n.pct(0.004), "0%", "rounds down")
    eq(i18n.pct(0.006), "1%", "rounds up")
end)

test("language defaults to English and set switches it", function()
    i18n.set("en")
    eq(i18n.lang(), "en", "en")
    i18n.set("ru")
    eq(i18n.lang(), "ru", "ru")
    eq(i18n.t("healing"), ru.healing, "ru text")
    i18n.set("en")
    eq(i18n.t("healing"), en.healing, "en text")
end)

test("an unknown language falls back to English", function()
    i18n.set("ru")
    i18n.set("de")
    eq(i18n.lang(), "en", "unknown code")
    i18n.set("ru")
    i18n.set(nil)
    eq(i18n.lang(), "en", "nil")
end)

test("t formats its arguments", function()
    i18n.set("en")
    eq(i18n.t("more_enemies", 9, "3 000", "4 000"), "More enemies: 9 (HP 3 000 to 4 000)", "en")
    i18n.set("ru")
    eq(i18n.t("more_enemies", 9, "3 000", "4 000"), "Ещё врагов: 9 (HP от 3 000 до 4 000)", "ru")
    i18n.set("en")
end)

test("t without arguments returns the text untouched", function()
    i18n.set("en")
    eq(i18n.t("more_enemies"), en.more_enemies, "template kept, no format error")
end)

test("missing key returns the key", function()
    i18n.set("en")
    eq(i18n.t("no_such_key"), "no_such_key", "en")
    i18n.set("ru")
    eq(i18n.t("no_such_key"), "no_such_key", "ru")
    i18n.set("en")
end)

test("missing ru key falls back to en", function()
    local saved = ru.fight_over
    ru.fight_over = nil
    i18n.set("ru")
    local ok, text = pcall(i18n.t, "fight_over")
    ru.fight_over = saved
    i18n.set("en")
    eq(ok, true, "t must not raise")
    eq(text, en.fight_over, "English text")
end)

test("every required key is in both language files", function()
    for _, key in ipairs(KEYS) do
        eq(type(en[key]), "string", "en." .. key)
        eq(type(ru[key]), "string", "ru." .. key)
    end
end)

test("the 0.2 settings texts, word for word", function()
    for key, text in pairs(SETTINGS_TEXTS) do
        eq(ru[key], text[1], "ru." .. key)
        eq(en[key], text[2], "en." .. key)
    end
    -- the old groups are gone
    for _, key in ipairs({ "sgroup_general", "sgroup_window", "sgroup_live", "sgroup_summary", "sgroup_enemy_bars" }) do
        eq(ru[key], nil, "ru." .. key .. " gone"); eq(en[key], nil, "en." .. key .. " gone")
    end
    -- a label for every setting of the file
    local Settings = require("DD2DamageMeter/settings")
    for key in pairs(Settings.DEFAULTS) do
        eq(type(en["setting_" .. key]), "string", "en.setting_" .. key)
        eq(type(ru["setting_" .. key]), "string", "ru.setting_" .. key)
    end
end)

test("the journal's texts, word for word", function()
    for key, text in pairs(JOURNAL_TEXTS) do
        eq(ru[key], text[1], "ru." .. key)
        eq(en[key], text[2], "en." .. key)
    end
end)

test("the redesign's texts, word for word; «Эффект» is gone", function()
    for key, text in pairs(REDESIGN_TEXTS) do
        eq(ru[key], text[1], "ru." .. key)
        eq(en[key], text[2], "en." .. key)
    end
    eq(ru.jcol_effect, nil, "ru: no effect column"); eq(en.jcol_effect, nil, "en: no effect column")
end)

test("the enemy plate's table texts, word for word; «все типы ×1,0» is gone", function()
    for key, text in pairs(PLATE_TEXTS) do
        eq(ru[key], text[1], "ru." .. key)
        eq(en[key], text[2], "en." .. key)
    end
    eq(ru.plate_all_normal, nil, "ru: every cell shows its ×1,0"); eq(en.plate_all_normal, nil, "en too")
end)

test("the self-effects texts, word for word", function()
    local want = {
        env = { "Падения и среда", "Falls and environment" },
        own_blood_pact = { "Пакт крови", "Blood Pact" }, own_self = { "Сам себе", "Self" },
        own_lifesteal = { "Вампиризм", "Lifesteal" }, own_regen = { "Восстановление", "Regeneration" },
        setting_help_section_other = { "Сюда же входят «Падения и среда».", "It also covers “Falls and environment”." },
    }
    for key, text in pairs(want) do
        eq(ru[key], text[1], "ru." .. key)
        eq(en[key], text[2], "en." .. key)
    end
end)

test("plural forms: Russian one, few and many; English one and other", function()
    local want = {
        [0] = "many", [1] = "one", [2] = "few", [3] = "few", [4] = "few", [5] = "many", [11] = "many", [12] = "many",
        [14] = "many", [20] = "many", [21] = "one", [22] = "few", [24] = "few", [25] = "many", [30] = "many",
        [101] = "one", [111] = "many", [112] = "many", [114] = "many", [862] = "few", [1001] = "one",
    }
    for n, form in pairs(want) do eq(i18n.plural(n, "ru"), form, "ru " .. n) end
    eq(i18n.plural(1, "en"), "one", "en 1")
    for _, n in ipairs({ 0, 2, 5, 11, 21, 101, 862 }) do eq(i18n.plural(n, "en"), "other", "en " .. n) end
    -- the form of the number shown: a float count from history.json, a rounded one, nothing usable
    eq(i18n.plural(2.0, "ru"), "few", "a whole float"); eq(i18n.plural(0.6, "ru"), "one", "shown as 1")
    eq(i18n.plural(-3, "ru"), "few", "the sign does not count")
    eq(i18n.plural(0 / 0, "ru"), "many", "NaN as 0"); eq(i18n.plural(nil, "en"), "other", "nil as 0")
    -- the current language by default; an unknown one counts as English
    i18n.set("ru")
    eq(i18n.plural(3), "few", "current: ru")
    i18n.set("en")
    eq(i18n.plural(3), "other", "current: en")
    eq(i18n.plural(1, "de"), "one", "unknown language: English rule"); eq(i18n.plural(3, "de"), "other", "other")
end)

test("tn: a counted text in its plural form, the count as num shows it", function()
    i18n.set("ru")
    for n, text in pairs({ [1] = "1 раз", [21] = "21 раз", [101] = "101 раз", [2] = "2 раза", [4] = "4 раза",
                           [22] = "22 раза", [24] = "24 раза", [0] = "0 раз", [5] = "5 раз", [20] = "20 раз",
                           [25] = "25 раз", [30] = "30 раз", [111] = "111 раз", [114] = "114 раз", [862] = "862 раза",
                           [1234] = "1 234 раза" }) do
        eq(i18n.tn("jtimes", n), text, "ru " .. n)
    end
    i18n.set("en")
    eq(i18n.tn("jtimes", 1), "1 time", "en 1"); eq(i18n.tn("jtimes", 862), "862 times", "en 862")
    eq(i18n.tn("jtimes", 0), "0 times", "en 0")
    eq(i18n.tn("no_such_key", 3), "no_such_key_other", "a missing text: its key")
end)

test("upper_first: the first letter a capital, Latin a-z and Cyrillic а-я, ё", function()
    local up = i18n.upper_first
    eq(up("осмоление"), "Осмоление", "а..п"); eq(up("пар"), "Пар", "п")
    eq(up("рана"), "Рана", "р..я"); eq(up("яд"), "Яд", "я"); eq(up("а"), "А", "one letter")
    eq(up("ёж"), "Ёж", "ё"); eq(up("poison"), "Poison", "Latin"); eq(up("z"), "Z", "z"); eq(up("a"), "A", "a")
    eq(up("Быстродействующий яд"), "Быстродействующий яд", "already a capital"); eq(up("Ё"), "Ё", "Ё")
    eq(up("Poison"), "Poison", "Latin capital")
    eq(up("«яд»"), "«яд»", "another first character"); eq(up("1 яд"), "1 яд", "a digit"); eq(up(" яд"), " яд", "a space")
    eq(up("éclair"), "éclair", "a letter outside a..z and а..я"); eq(up("ӑ"), "ӑ", "Cyrillic outside а..я and ё")
    eq(up("ъ"), "Ъ", "ъ"); eq(up("ѐ"), "ѐ", "U+0450 is not ё")
    eq(up(""), "", "empty"); eq(up(nil), nil, "nil"); eq(up(5), 5, "not a string")
    eq(up("\208"), "\208", "a cut UTF-8 sequence"); eq(up("я\255"), "Я\255", "the rest as it is")
end)

test("mult formats by language", function()
    i18n.set("ru")
    eq(i18n.mult(1), "×1,0", "ru 1"); eq(i18n.mult(0.75), "×0,75", "ru 0.75"); eq(i18n.mult(1.2), "×1,2", "ru 1.2")
    eq(i18n.mult(0), "×0,0", "ru 0"); eq(i18n.mult(0.4), "×0,4", "ru 0.4"); eq(i18n.mult(2.5), "×2,5", "ru 2.5")
    eq(i18n.mult(0.7549), "×0,75", "two decimals"); eq(i18n.mult(1.0049), "×1,0", "rounded to 1")
    eq(i18n.mult(12.34), "×12,34", "two digits before the comma")
    i18n.set("en")
    eq(i18n.mult(1.5), "×1.5", "en 1.5"); eq(i18n.mult(0.75), "×0.75", "en 0.75")
    eq(i18n.mult(nil), "", "nil"); eq(i18n.mult(0 / 0), "", "NaN"); eq(i18n.mult(math.huge), "", "inf")
    eq(i18n.mult("1.5"), "", "not a number")
end)

test("the hidden-stats texts, word for word", function()
    for key, text in pairs(HS_TEXTS) do
        eq(ru[key], text[1], "ru." .. key)
        eq(en[key], text[2], "en." .. key)
    end
end)

test("dec: up to 2 decimals, grouped, by language", function()
    i18n.set("ru")
    eq(i18n.dec(1.5), "1,5", "ru 1.5"); eq(i18n.dec(62.7), "62,7", "62.7"); eq(i18n.dec(3), "3", "3")
    eq(i18n.dec(0.3), "0,3", "0.3"); eq(i18n.dec(1.05), "1,05", "1.05"); eq(i18n.dec(0.66), "0,66", "0.66")
    eq(i18n.dec(373.8), "373,8", "373.8"); eq(i18n.dec(157.14), "157,14", "157.14")
    eq(i18n.dec(1.004), "1", "rounds to 2 decimals"); eq(i18n.dec(1.996), "2", "carries into the whole part")
    eq(i18n.dec(2.10), "2,1", "trailing zero dropped"); eq(i18n.dec(0), "0", "0")
    eq(i18n.dec(1234.5), "1 234,5", "grouped as num"); eq(i18n.dec(2000), "2 000", "a whole thousand")
    eq(i18n.dec(-1.5), "-1,5", "minus"); eq(i18n.dec(-0.001), "0", "no minus on a rounded zero")
    i18n.set("en")
    eq(i18n.dec(1.5), "1.5", "en 1.5"); eq(i18n.dec(1234.5), "1 234.5", "en grouped")
    eq(i18n.dec(nil), "", "nil"); eq(i18n.dec(0 / 0), "", "NaN"); eq(i18n.dec(math.huge), "", "inf")
    eq(i18n.dec(-math.huge), "", "-inf"); eq(i18n.dec("1.5"), "", "not a number")
end)

-- Every entry of a language file is a text (no skill names ship with the mod: the game names them).
test("both language files have the same keys", function()
    for key, value in pairs(en) do
        eq(type(ru[key]), type(value), "ru is missing " .. key)
        eq(type(value), "string", "kind of en." .. key)
    end
    for key, value in pairs(ru) do
        eq(type(en[key]), type(value), "en is missing " .. key)
    end
end)

test("both language files take the same arguments", function()
    for key, text in pairs(en) do
        if type(text) == "string" then eq(specs(ru[key]), specs(text), "format conversions of " .. key) end
    end
    eq(specs(en.enemy_group_hp), "s", "enemy_group_hp takes the HP text")
    eq(specs(en.killed_count), "dd", "killed_count takes killed and total")
    eq(specs(en.more_enemies_same_hp), "ds", "more_enemies_same_hp takes the count and one HP")
    eq(specs(en.settings_hint), "s", "settings_hint takes the settings key's name")
    eq(specs(en.settings_in_window), "s", "settings_in_window too")
    -- the hint of the settings window is three lines in both languages
    for _, lang in ipairs({ en, ru }) do
        local _, breaks = lang.settings_hint:gsub("\n", "")
        eq(breaks, 2, "three hint lines")
    end
end)

test("Russian text lives only in lang/ru.lua", function()
    for key, text in pairs(en) do
        if type(text) == "string" then eq(text:find("[\208\209]") == nil, true, "Cyrillic in en." .. key) end
    end
    eq(ru.healing:find("[\208\209]") ~= nil, true, "ru.healing is Russian")
end)

test("each language names itself in its own script", function()
    eq(ru.lang_en, "English", "ru.lang_en")
    eq(ru.lang_ru, "Русский", "ru.lang_ru")
    eq(en.lang_en, "English", "en.lang_en")
end)

test("enemy_group_hp and killed_count format", function()
    i18n.set("en")
    eq(i18n.t("more_enemies_same_hp", 4, "900"), "More enemies: 4 (HP 900)", "en same HP")
    i18n.set("ru")
    eq(i18n.t("more_enemies_same_hp", 4, "900"), "Ещё врагов: 4 (HP 900)", "ru same HP")
    i18n.set("en")
    eq(i18n.t("enemy_group_hp", "3 700"), "3 700 HP each", "en group HP")
    eq(i18n.t("killed_count", 2, 3), "killed: 2 of 3", "en killed")
    i18n.set("ru")
    eq(i18n.t("enemy_group_hp", "3 700"), "по 3 700 HP", "ru group HP")
    eq(i18n.t("killed_count", 2, 3), "убито: 2 из 3", "ru killed")
    i18n.set("en")
end)

T.finish()
