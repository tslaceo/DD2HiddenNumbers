-- English texts: key -> string. Keys must match lang/ru.lua; a text with %s/%d takes the
-- arguments listed next to it, already formatted (numbers through i18n.num).
return {
    -- window blocks and header
    damage_to_enemies = "Damage to enemies",
    damage_to_party = "Damage to party",
    healing = "Healing",
    per_sec = "/s", -- unit suffix after a number: 325/s
    allies = "Allies",
    other = "Other",
    env = "Falls and environment", -- the grey row of the damage enemies did to themselves (a fall)
    -- a party member's own damage and heals, by source: "Blood Pact → Guts", "→ Guts · Lifesteal"
    own_blood_pact = "Blood Pact",
    own_self = "Self",
    own_lifesteal = "Lifesteal",
    own_regen = "Regeneration",

    -- summary
    fight_over = "Fight over",
    victory = "Victory",
    enemies = "Enemies",
    more_enemies = "More enemies: %d (HP %s to %s)", -- count, lowest HP, highest HP
    more_enemies_same_hp = "More enemies: %d (HP %s)", -- count, HP when they all have the same
    enemy_group_hp = "%s HP each", -- HP of one enemy of a merged group, e.g. "3 700"
    killed_count = "killed: %d of %d", -- killed, total
    killed = "killed",
    dealt = "Dealt",
    healed = "Healed",
    armor = "Armor",
    enemy_defence_saved = "Cut by enemy defense",
    party_armor_saved = "Absorbed by party armor",
    history = "History",
    unnamed_enemy = "Unnamed enemy", -- an enemy kind the game has no name for

    -- skills and items
    normal_attacks = "Normal attacks",
    skill = "Skill",
    unknown_skill = "Unknown skill", -- a skill the game gave nothing to name it by
    item = "Item",
    -- damage-over-time rows in a character's details, by status family
    dot_burn = "Burning",
    dot_poison = "Poison",
    dot_shock = "Shock",
    dot_frost = "Frost",
    dot = "Status damage", -- a status of no known family: "Status damage (<the game's status name>)"

    -- character details
    details_hits = "Hits",
    details_total = "Total",
    details_max = "Max",
    details_perfect = "Perfect",
    details_full_damage = "Full damage (with overkill)",
    details_armor_saved = "Armor absorbed",
    details_guard = "Blocked by shield",

    -- damage types (the game's DamageType names)
    type_Slash = "Slash",
    type_Blow = "Blunt",
    type_Shoot = "Ranged",
    type_Magic = "Magic",
    type_Enchant = "Enchantment",
    type_NonMagicElement = "Elemental",
    type_Fixed = "Fixed",

    -- the settings window: the names of its rows, short (the group's heading says what they are about)
    setting_style = "Style",
    setting_scale = "Size", -- of the whole meter, a percent
    setting_opacity = "Background", -- how dark the panel (or the halo) is, a percent
    setting_shadow = "Shadow",
    setting_outline = "Outline",
    setting_halo = "Halo",
    setting_bar_px = "Bars", -- their thickness in px
    setting_window_x = "Position X",
    setting_window_y = "Position Y",
    -- the rows of the table "What to show": a section of the meter, its cells the fight window's and the summary's
    setting_section_enemies = "Enemies",
    setting_section_damage = "Dealt",
    setting_section_taken = "Taken",
    setting_section_heal = "Healing",
    setting_section_armor = "Armor",
    setting_section_allies = "Allies",
    setting_section_other = "Other",
    setting_summary_autohide = "Summary hides after",
    setting_damage_numbers = "Show",
    setting_damage_numbers_style = "Style",
    setting_damage_numbers_size = "Size",
    setting_boss_hp_numbers = "At the boss",
    setting_enemy_hp_numbers = "Over enemies",
    setting_enemy_hp_size = "Size",
    setting_buildup_bars = "Status buildup",
    setting_player_numbers = "My health and stamina",
    setting_enemy_plate = "Show",
    setting_enemy_plate_size = "Size",
    setting_hidden_stats = "Show",
    setting_hidden_stats_size = "Size",
    setting_journal = "Keep a journal",
    setting_history_size = "Fights kept",
    setting_history_file = "Save between sessions",
    setting_toggle_key = "Meter", -- under "Keys": the key that shows / hides the meter
    setting_journal_key = "Journal",
    setting_settings_key = "Settings",
    setting_language = "Language",
    setting_debug = "Debug",
    -- the switches of the meter's sections by their own names (the window shows them as the cells of its table)
    setting_live_damage = "Damage to enemies",
    setting_live_taken = "Damage to party",
    setting_live_heal = "Healing",
    setting_show_allies = "Allies",
    setting_live_other = "Other",
    setting_summary_enemies = "Enemies",
    setting_summary_damage = "Dealt",
    setting_summary_armor = "Armor",
    setting_summary_heal = "Healing",
    setting_summary_allies = "Allies",
    setting_summary_other = "Other",

    -- the settings window: the values as text (svalue_*: %d a whole number of percent, pixels or seconds; the HP
    -- formats by name: what the numbers show)
    lang_auto = "Same as game",
    lang_en = "English",
    lang_ru = "Russian",
    style_frameless = "No panel",
    style_panel = "Panel",
    dnum_rise = "Rise",
    dnum_plates = "Plates",
    hpfmt_off = "off",
    hpfmt_current = "HP",
    hpfmt_current_max = "HP / max",
    hpfmt_percent = "%",
    hpfmt_current_percent = "HP and %",
    hpfmt_all = "HP / max and %",
    switch_on = "on",
    switch_off = "off",
    svalue_pct = "%d%%",
    svalue_px = "%d px",
    svalue_sec = "%d s",
    svalue_never = "never",
    press_a_key = "Press a key (Esc cancels)", -- shown on the key row while it waits

    -- the HP numbers, each format as it looks (in the help line of its rows; an example: 12 340 HP of 18 000)
    hpnum_off = "off",
    hpnum_current = "12 340",
    hpnum_current_max = "12 340 / 18 000",
    hpnum_percent = "69%",
    hpnum_current_percent = "12 340 · 69%",
    hpnum_all = "12 340 / 18 000 · 69%",

    -- the settings window: its title (after the mod's name), the headings of its groups, the columns of its table,
    -- the help line of the selected row (setting_help_section: the row's name; setting_help_hp_numbers: the format as
    -- it looks; setting_help_journal: the journal key's name; setting_help_history_size: the most fights;
    -- setting_help_key: what the key does), the hint lines (one per "\n"; %s: the settings key's name, e.g. "F8")
    settings_title = "Settings",
    sgroup_look = "Meter look",
    sgroup_show = "What to show",
    sgroup_damage_numbers = "Damage numbers",
    sgroup_hp_numbers = "Health numbers",
    sgroup_enemy_plate = "Enemy plate",
    sgroup_hidden_stats = "Hidden stats",
    sgroup_journal = "Journal",
    sgroup_keys = "Keys",
    sgroup_other = "Other",
    scol_live = "Fight",
    scol_summary = "Summary",
    setting_help_style = "Panel: a dark backing under the meter. No panel: only the text and the bars.",
    setting_help_scale = "The size of the whole meter: text, bars and spacing.",
    setting_help_opacity = "How dark the backing is: more is darker. Without the panel, how dense the halo is.",
    setting_help_shadow = "A shadow under the text and the numbers.",
    setting_help_outline = "A dark outline around the numbers, so they read on a bright background.",
    setting_help_halo = "A soft dark patch behind the text. Only without the panel.",
    setting_help_bar_px = "How thick the damage bars are. Only without the panel.",
    setting_help_window_x = "The meter's left edge from the left of the screen.",
    setting_help_window_y = "The meter's top edge from the top of the screen.",
    setting_help_section = "“%s”: whether the meter shows this section in a fight and in the summary after it. — "
        .. "means none there.",
    setting_help_section_other = "It also covers “Falls and environment”.", -- after setting_help_section on that row
    setting_help_summary_autohide = "How many seconds after a fight the summary hides. 0: never.",
    setting_help_damage_numbers = "Damage numbers where a hit lands on an enemy, in the fighter's color.",
    setting_help_damage_numbers_style = "Plates stand in place. Rise: they float up and fade.",
    setting_help_damage_numbers_size = "The size of the damage numbers.",
    setting_help_hp_numbers = "How health is shown. Now: “%s”.",
    setting_help_enemy_hp_size = "The size of the health numbers at the boss and over enemies.",
    setting_help_buildup_bars = "Under the boss's bar: how far each status is from setting off and about how many "
        .. "more hits; once set off, how long it still lasts and the resistance.",
    setting_help_player_numbers = "Numbers by your health and stamina bars: now / max, with the full max in brackets "
        .. "when it is cut.",
    setting_help_enemy_plate = "In a fight: what the enemies near you are weak to, what does not work on them and how "
        .. "your damage fares.",
    setting_help_enemy_plate_size = "The size of the enemy plate.",
    setting_help_hidden_stats = "What the augment or ring under the cursor really gives, in numbers: at the guild, in "
        .. "your items and when changing equipment.",
    setting_help_hidden_stats_size = "The size of the hidden stats panel.",
    setting_help_journal = "Remember fights for the journal (%s).",
    setting_help_history_size = "How many recent fights to remember, up to %d.",
    setting_help_history_file = "Keep the fights in history.json, so they are still there after you quit the game.",
    setting_help_toggle_key = "Show or hide the meter.",
    setting_help_journal_key = "Open the fight journal.",
    setting_help_settings_key = "Open this window.",
    setting_help_key = "%s Enter: choose another key.",
    setting_help_language = "The mod's language. “Same as game”: the one the game is in.",
    setting_help_debug = "Write a debug log for the developer. Usually not needed.",
    settings_hint = "Up/Down — select · Left/Right — change\nEnter — on/off · PgUp/PgDn — groups\n"
        .. "%s — close · mouse — with the REFramework menu",
    -- REFramework's menu: where the settings are (%s: the settings key's name), the button that opens the window, the
    -- label of the settings key's button
    settings_in_window = "The settings are in the mod's own window, key %s",
    open_settings = "Open the settings window",
    menu_settings_key = "Settings window key",

    -- self-check at load: how many game methods the mod needs and could not find; one short line in the window
    missing_methods = "Game update? Methods not found: %d",

    -- numbers: the decimal mark of a multiplier (×1.5)
    decimal_sep = ".",

    -- the journal: elements (the game has no word for them), the weakness tags "all magick" / "all physical"
    element_Fire = "Fire",
    element_Ice = "Ice",
    element_Thunder = "Lightning",
    element_Light = "Holy",
    element_Dark = "Dark",
    weak_magic_all = "All magick",
    weak_physics_all = "All physical",

    -- the journal: status names when the game's message is missing (with a capital, as the game's are shown); the
    -- buildup bars name the statuses so too, WetElectric (a wet enemy's shock) theirs alone
    status_Poison = "Poison",
    status_VirulentPoison = "Virulent poison",
    status_Sleep = "Sleep",
    status_Faint = "Faint",
    status_Frostbite = "Frostbite",
    status_Freeze = "Freeze",
    status_Electric = "Shock",
    status_Wet = "Wet",
    status_Oil = "Tar",
    status_FireSpread = "Burning",
    status_OilSpread = "Burning tar",
    status_Silence = "Silence",
    status_Stone = "Petrification",
    status_Blind = "Blindness",
    status_WetElectric = "Shock (wet)",

    -- the enemy plate in the fight (ui/enemy_plate.lua): the kinds not listed, a kind's statuses that do not work on
    -- it (its name, then the list), the "you" line (what the player hits with and what it gets), the part rows'
    -- labels, an enchant's element; a row with no table read, the "you" line's other kinds at the mult ×1; the
    -- table's column headers, short; an enemy's state next to its name (the game's ids)
    plate_more = "+%d more",
    plate_immune = "%s: immune to %s",
    plate_you = "you: %s",
    plate_head = "head",
    plate_weak = "weak spot",
    plate_enchant = "%s (enchant)",
    plate_no_data = "no data",
    plate_others = "others %s",
    plate_col_Slash = "Slash",
    plate_col_Blow = "Blunt",
    plate_col_Shoot = "Rngd",
    plate_col_Fire = "Fire",
    plate_col_Ice = "Ice",
    plate_col_Thunder = "Thndr",
    plate_col_Light = "Holy",
    plate_col_Magic = "Mag",
    plate_state_Angry = "enraged",
    plate_state_Injured = "injured",
    plate_state_Down = "downed",
    plate_state_Flight = "flying",
    plate_state_HeartExposure = "heart exposed",
    plate_state_Rampage = "rampaging",
    plate_state_Possess = "possessing",
    plate_state_GhostWrapped = "ghost-shrouded",

    -- the status buildup bars under the boss bar (ui/buildup_bars.lua): about how many more hits set a status off;
    -- the boss's poise rows, how far it is from a stagger and from a knock-down
    buildup_lean = "Stagger",
    buildup_blown = "Knock down",
    buildup_hits_one = "≈ %s hit",
    buildup_hits_few = "≈ %s hits",
    buildup_hits_many = "≈ %s hits",
    buildup_hits_other = "≈ %s hits",
    -- a status set off: how long it still lasts; the resistance earlier triggers raised
    buildup_left = "%s s left",
    buildup_resist = "resistance %s%%",

    -- the hidden-stats panel on the augments and item screens (hidden_stats_model.lua): the line of a thing with no
    -- number in the game, the legend of the marks (≈ not confirmed by other mods, ? a guess); after a % of a
    -- base stat the base in brackets and the personal number (%s: "380", "+159") for the player or the
    -- pawn, and the hint when the base is not known; the word for whose base it is ({whose} of the data's English
    -- texts: "of your base defense"); under a defence line the total before → after and its percent, then the
    -- damage taken (%s: "-10%")
    hs_none = "no number found in the game",
    hs_legend = "≈ not confirmed by other mods · ? a guess",
    hs_yours = "(%s) — %s now",
    hs_pawns = "(%s) — %s now",
    hs_base_hint = "(the number in brackets on the status screen)",
    hs_whose_yours = "your",
    hs_whose_pawns = "the pawn's",
    hs_whose_none = "the",
    hs_total_phys = "defense %s → %s (%s)",
    hs_total_magic = "magick defense %s → %s (%s)",
    hs_damage_phys_yours = "%s physical damage taken",
    hs_damage_phys_pawns = "%s physical damage the pawn takes",
    hs_damage_magic_yours = "%s magick damage taken",
    hs_damage_magic_pawns = "%s magick damage the pawn takes",

    -- the journal: vocations (the game's JobEnum order)
    job_1 = "Fighter",
    job_2 = "Archer",
    job_3 = "Mage",
    job_4 = "Thief",
    job_5 = "Warrior",
    job_6 = "Sorcerer",
    job_7 = "Mystic Spearhand",
    job_8 = "Magick Archer",
    job_9 = "Trickster",
    job_10 = "Warfarer",

    -- the journal: tabs, header and numbers
    jtab_summary = "Summary",
    jtab_enemies = "Enemies",
    jtab_skills = "Skills",
    jtab_party = "Taken",
    jtab_heal = "Healing",
    jtab_chart = "Chart",
    jtab_record = "Record",
    jfight_of = "fight %d of %d", -- this fight's place in the history (1 = newest), fights kept
    jno_fights = "No fights yet",
    jmore_kinds = "%d more", -- kinds of enemy not named in the fight's line
    jnum_dps = "Damage per second",
    jnum_taken = "Taken",

    -- the journal: the enemy list and the enemy card
    jenemies_count = "Enemies · %d", -- enemies of the fight
    jkilled_at = "killed at %s", -- fight time, e.g. "4:12"
    jkilled_by = "finished by %s", -- who dealt the killing blow
    jgame_says = "What the game says",
    jweak = "Weak to:",
    jresist = "Resists:",
    jimmune = "Immune to:",
    jnone = "none",
    jdefence = "Defense",
    jmagic_defence = "Magick defense",
    jhit_with = "What hit it",
    jparts_type = "%s: head %s · body %s", -- a damage type, its multipliers on the head and on the body ("×1.4")
    jwho = "Who dealt what",
    jattacks = "Whom it hit",
    no_data = "no data",
    jno_hits = "No hits",
    jno_damage = "No damage", -- hits that took no HP
    eff_invalid = "no effect",
    eff_resist = "poor",
    eff_effective = "good",
    jcol_skill = "Skill · type",
    jcol_damage = "Damage",
    jcol_avg = "Average",
    jcol_share = "Share", -- of the damage the enemy took
    jcol_mult = "Mult.", -- the multiplier the game applied

    -- the journal: the Skills and Chart tabs
    jparty_all = "Whole party", -- the choice that shows every party member's skills
    jcol_skill_only = "Skill", -- the Skills table's first heading (its rows name the skill only, no damage type)
    jcol_who = "Who",
    jcol_dps = "DPS",
    jrest = "Rest", -- a chart column's skills outside its largest

    -- the journal: the Healing tab's count of heals (%s: the count, I18n.tn picks one or other; few and many are
    -- Russian forms)
    jtimes_one = "%s time",
    jtimes_few = "%s times",
    jtimes_many = "%s times",
    jtimes_other = "%s times",

    -- the journal: the Record tab
    jcol_time = "Time",
    jcol_whom = "Whom",
    jcol_what = "With",
    jcol_amount = "Amount",
    jrecord_dropped = "Earlier events not kept: %d", -- events of the fight older than the record keeps

    -- the journal window: the pager and the hint line (%s: the journal key's name, e.g. "F7")
    jpage = "page %d of %d",
    journal_hint = "%s closes · PgUp/PgDn tabs · Home/End fights · Up/Down select · Left/Right pages",
    journal_mouse = "mouse with the REFramework menu", -- at the right end of the hint line
}
