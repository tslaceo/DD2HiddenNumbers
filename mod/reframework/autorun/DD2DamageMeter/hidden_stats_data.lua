-- The meanings of the augments' and rings' hidden numbers (the hidden-stats panel): what each line says and how
-- sure its reading is. The readings come from the game's descriptions and field names, the developers' notes and
-- checks in the game, cross-checked with two other mods (see `mark` below); the
-- numbers are not here: they are the game's, read live (game/hidden_stats.lua), and only placed by these texts.
-- Pure data, no game access; hidden_stats_model.lua writes the lines.
--
--   HiddenStatsData.augment(name) -> Entry | nil   name "Job01_00".."Job10_06" (app.HumanAbilityID), the 52 augments
--   HiddenStatsData.ring(id) -> Entry | nil        the 90 rings (EquipCategory 6) by item id
--   Entry = { silent = true }          no panel: the effect has no number (Внимательность, Кольцо возвращения 10213,
--                                      Бирюзовое кольцо, Кольцо лёгкости)
--         | { none = true }            the one line «числа в игре не нашлось»: a number should exist, none was found
--         | { lines = { Line, ... }, or_none = true | nil }
--                                      one line per effect, in the order of the game's description; or_none: the
--                                      none line when none of them can be written (Везение unread)
--   Line = { mark, ru, en, nums = { { src, as }, ... }, base = BaseKey | nil, base_pct = src | nil,
--            base_add = src | nil, total = "phys" | "magic" | nil, total_add = src | nil, no_pawn = true | nil,
--            fallback = true | nil }
--     mark: "plain" when a developers' note, a field name or an in-game check settles the line, or
--       when both Clear Effect Descriptions 2.04 (Filipe Ramos) and Better Better Item Description (xyzkljl1) read
--       its number as we do: the same meaning, unit and scale (each number compared with both on 2026-11-07);
--       "approx" (≈) when the meaning is clear but either mod is silent or reads it otherwise; "guess" (?) when
--       what the number means is not clear. Where both mods agreed with each other against us, their reading is
--       taken.
--     ru / en: the text without its mark, "{n}" for nums[n]; a "[...]" part is left out when a number it shows is
--       0 or missing (hidden_stats_model.lua); "{whose}" (an English text with a base only) is whose base it is
--       ("your", "the pawn's", "the"): Russian says it in the brackets after the line
--     src: a dotted path into the game's record: an augment's v1 / v2, Везение's additional.cash / meat / cash_min /
--       cash_max; a ring's v1 / v2 / v3, fields.<Name>, efficacy.rate / kinds / unnamed, drop.rate_up / count_up /
--       defeat, always.per_sec / cool / cool_dodge, pickpocket.base / factor, rejuv.factor / cap, curve.top,
--       curve.steps.<n>.y / to (the n-th step's value and the x where it ends, n 1..4)
--     as: num | signed | dec | pct | signed_pct | mult | add | share | list (hidden_stats_model.lua says how each is
--       shown)
--     base: "phys_defence" | "magic_defence" | "strength" | "magic", for a line that is a % of a base
--       stat: the line ends with that base in brackets and base_add + base × base_pct / 100 for the one whose
--       augments the screen shows; its flat part is in a "[...]" part, so a 0 is not written
--     no_pawn: a line with a base whose bonus holds only without pawns; on a pawn's screen it has no personal
--       number (that pawn is in the party)
--     fallback: written only when no line before it was (a curve's top when its steps cannot be read)
--     total: the line is followed by the line of that total ("защита 1486 → 1645 (+11%)") and of the damage
--       taken; what the line adds to the total is its personal number (a line with a base) or total_add's
--       value (a ring's armour field). Стойкость, Изгнание and the defence rings 3509, 3511, 8600 only.
-- The tables are shared: not to be changed by the caller.
local HiddenStatsData = {}

local P, A, G = "plain", "approx", "guess"
local SILENT, NONE = { silent = true }, { none = true }

-- A line: its mark, its ru and en texts, then one { src, as } per place {1}, {2}, ...
local function L(mark, ru, en, ...)
    local nums = {}
    for i, n in ipairs({ ... }) do nums[i] = { src = n[1], as = n[2] } end
    return { mark = mark, ru = ru, en = en, nums = nums }
end

-- The line with the personal number of a % of the base stat `base`; `total`: the total line under it.
local function based(line, base, base_pct, base_add, total)
    line.base, line.base_pct, line.base_add, line.total = base, base_pct, base_add, total
    return line
end

-- A line with a base whose bonus holds only without pawns: no personal number for a pawn.
local function no_pawn(line)
    line.no_pawn = true
    return line
end

-- A line that stands in for the lines before it when none of them can be written.
local function fallback(line)
    line.fallback = true
    return line
end

local function E(...) return { lines = { ... } } end

-- An entry that shows the none line when none of its lines can be written.
local function or_none(entry)
    entry.or_none = true
    return entry
end

-- The places of a curve's steps: {1} {2} the first step's value and the x where it ends, {3} {4} the second's,
-- up to the four game/hidden_stats.lua gives (a curve with more steps has none).
local function step_nums()
    local nums = {}
    for n = 1, 4 do
        nums[#nums + 1] = { "curve.steps." .. n .. ".y", "signed_pct" }
        nums[#nums + 1] = { "curve.steps." .. n .. ".to", "dec" }
    end
    return table.unpack(nums)
end

-- augments -----------------------------------------------------------------------------------------------------------
-- The 52 augments. Plain: a developers' note gives the formula or the unit, or a check in game
-- (Стойкость, Изгнание, Мускулатура, the flat adds); and the lines both other mods read as we do (Засада,
-- Летальность, Равновесие, Полярность, Рог изобилия) and Яркость's light in neutral words, ×2, as all three say;
-- Везение from its own table. ≈: Возвышение (its note against CED's «10 в секунду»; ours kept), Стаз's
-- first number (BBID gives no meaning). ?: Стаз's second number, Обнаружение.

local AUGMENTS = {
    -- Боец (Fighter)
    Job01_00 = E(L(P, "{1} к постоянной угрозе", "{1} constant threat", { "v1", "mult" })),
    Job01_01 = E(based(L(P, "[{1} и ]{2} от базовой защиты", "[{1} and ]{2} of {whose} base defense",
        { "v1", "signed" }, { "v2", "signed_pct" }), "phys_defence", "v2", "v1", "phys")),
    Job01_02 = E(L(P, "{1} кг к пределу веса", "{1} kg max carry weight", { "v1", "signed" })),
    Job01_03 = E(L(P, "{1} с к удержанию поднятого врага", "{1} s holding a lifted enemy", { "v1", "signed" }),
        L(P, "{1} с к удержанию прижатого врага", "{1} s pinning an enemy down", { "v2", "signed" })),
    Job01_04 = E(L(P, "-{1} с на подъём после падения", "-{1} s getting up after a fall", { "v1", "dec" }),
        L(P, "-{1} с на ползание", "-{1} s crawling", { "v2", "dec" })),
    -- Лучник (Archer)
    Job02_00 = E(L(P, "{1} урона по врагам не в боевой стойке", "{1} damage to enemies not in a combat stance",
        { "v1", "add" })),
    Job02_01 = E(L(P, "{1} к макс. выносливости", "{1} max stamina", { "v1", "signed" })),
    -- the light: range or area, the note's 照らす範囲 says either; all three readings say ×2
    Job02_02 = E(L(P, "{1} к расходу масла", "{1} lantern oil use", { "v1", "mult" }),
        L(P, "свет ×{1}", "light ×{1}", { "v2", "dec" })),
    Job02_03 = E(L(P, "{1} урона по уязвимым местам", "{1} damage to weak points", { "v1", "add" })),
    Job02_04 = E(L(P, "{1} к скорости подъёма на уступы", "{1} speed climbing ledges", { "v1", "mult" }),
        L(P, "{1} к скорости лазания по врагу", "{1} speed climbing an enemy", { "v2", "mult" })),
    -- Маг (Mage)
    Job03_00 = E(based(L(P, "[{1} и ]{2} от базовой маг. защиты", "[{1} and ]{2} of {whose} base magick defense",
        { "v1", "signed" }, { "v2", "signed_pct" }), "magic_defence", "v2", "v1", "magic")),
    Job03_01 = E(L(P, "{1} к лечению предметами и магией", "{1} healing from items and magick", { "v1", "signed_pct" })),
    Job03_02 = E(L(P, "{1} к длительности недугов на тебе", "{1} duration of debilitations on you", { "v1", "mult" })),
    Job03_03 = E(L(P, "{1} к длительности чар и воодушевления", "{1} duration of enchantments and boons",
        { "v1", "mult" })),
    Job03_04 = E(L(A, "{1} к скорости восстановления выносливости", "{1} stamina recovery speed", { "v1", "add" })),
    -- Вор (Thief)
    Job04_00 = E(L(P, "{1} к постоянной угрозе", "{1} constant threat", { "v1", "mult" })),
    Job04_01 = E(L(P, "{1} здоровья за добивание", "{1} health per finishing blow", { "v1", "signed_pct" })),
    Job04_02 = E(L(P, "{1} к расходу выносливости в захвате врага", "{1} stamina use while held by an enemy",
        { "v1", "mult" })),
    Job04_03 = E(L(P, "{1} к расходу выносливости, пока висишь на враге или прижимаешь его",
        "{1} stamina use while clinging to or pinning an enemy", { "v1", "mult" })),
    Job04_04 = E(L(P, "{1} к силе", "{1} strength", { "v1", "signed" })),
    -- Воин (Warrior)
    Job05_00 = E(L(P, "{1} к макс. здоровью", "{1} max health", { "v1", "signed" })),
    Job05_01 = E(L(P, "{1} к силе толчка и тяги в захвате", "{1} push and pull power while grappling",
        { "v1", "mult" })),
    Job05_02 = E(L(P, "{1} к пробиванию блока врага", "{1} guard-breaking power", { "v1", "signed_pct" })),
    Job05_03 = E(L(P, "{1} к силе сбивания с ног", "{1} knockdown power", { "v1", "signed_pct" })),
    Job05_04 = E(L(P, "{1} к потере макс. здоровья от урона (серая часть шкалы)",
        "{1} max health lost to damage (the grey part of the bar)", { "v1", "mult" })),
    -- Чародей (Sorcerer)
    Job06_00 = E(L(P, "{1} к накоплению недугов от твоих атак", "{1} debilitation buildup from your attacks",
        { "v1", "signed_pct" })),
    Job06_01 = E(L(A, "скорость порчи {1} от обычной", "spoiling at {1} of the normal speed", { "v1", "pct" }),
        L(G, "второе число {1} — смысл не известен", "the second number {1}: its meaning is unknown", { "v2", "dec" })),
    Job06_02 = E(L(P, "{1} к сопротивлению сбиванию", "{1} knockdown resistance", { "v1", "signed_pct" })),
    Job06_03 = E(L(P, "{1} урона стихией, к которой враг уязвим", "{1} damage with the element the enemy is weak to",
        { "v1", "signed_pct" })),
    Job06_04 = E(L(P, "{1} к магии", "{1} magick", { "v1", "signed" })),
    -- Мистический копейщик (Mystic Spearhand)
    Job07_00 = E(L(P, "{1} к скорости, пока что-то несёшь или поднял", "{1} speed while carrying or lifting",
        { "v1", "mult" })),
    Job07_01 = E(L(P, "{1} золота из мешочков", "{1} gold from pouches", { "v1", "mult" })),
    Job07_02 = E(
        based(L(P, "[{1} и ]{2} от базовой силы днём", "[{1} and ]{2} of {whose} base strength by day",
            { "v1", "signed" }, { "v2", "signed_pct" }), "strength", "v2", "v1"),
        based(L(P, "[{1} и ]{2} от базовой магии ночью", "[{1} and ]{2} of {whose} base magick at night",
            { "v1", "signed" }, { "v2", "signed_pct" }), "magic", "v2", "v1")),
    Job07_03 = E(L(P, "{1} кристаллов Разлома", "{1} Rift Crystals", { "v1", "mult" })),
    Job07_04 = E(L(P, "{1} к расходу выносливости на рывок", "{1} stamina use when sprinting", { "v1", "mult" })),
    -- Маг-лучник (Magick Archer)
    Job08_00 = E(L(P, "{1} к физ. и маг. защите пешек", "{1} defense and magick defense for pawns", { "v1", "signed" })),
    Job08_01 = E(L(P, "{1} выносливости за добивание", "{1} stamina per finishing blow", { "v1", "signed_pct" })),
    Job08_02 = E(L(P, "{1} к шансу добычи с мелких врагов", "{1} drop chance from smaller enemies", { "v1", "mult" })),
    Job08_03 = E(L(P, "{1} к силе и магии пешек", "{1} strength and magick for pawns", { "v1", "signed" })),
    Job08_04 = E(L(P, "-{1} с на подъём павшей пешки", "-{1} s to revive a fallen pawn", { "v1", "dec" })),
    -- Иллюзионист (Trickster)
    Job09_00 = E(L(G, "числа игры: {1}", "the game's numbers: {1}", { "v1", "dec" })),
    Job09_01 = E(L(P, "{1} шанс получить +1 изделие при сочетании", "{1} chance of +1 item when combining",
        { "v1", "pct" })),
    Job09_02 = E(L(P, "{1} к шансу нападения в лагере и на повозке", "{1} chance of an ambush at camp or on an oxcart",
        { "v1", "mult" })),
    Job09_03 = E(L(P, "{1} к зрению врагов, пока ты не в боевой стойке",
        "{1} enemy sight while you are not in a combat stance", { "v1", "mult" })),
    Job09_04 = E(L(P, "{1} к росту симпатии", "{1} affinity gain", { "v1", "mult" })),
    -- Ратник (Warfarer)
    Job10_00 = E(L(P, "{1} к расходу выносливости на навыки оружия", "{1} stamina use of weapon skills",
        { "v1", "mult" })),
    Job10_01 = E(L(P, "ступень веса при движении: -{1}", "weight class when moving: -{1}", { "v1", "num" })),
    Job10_02 = SILENT,
    -- Везение: no row in the ability table; its numbers are AbilityParam.AdditionalItemParam's, read live on
    -- 2026-11-07 (CashProbability 50, MeatProbability 20, LotteryCashInfos' sums 100 to 10 000), in the order of the
    -- game's description. Plain: the field names say what each is, and both other mods read the chances as % (CED
    -- 50 % and 20 %, BBID the same fields). Unread: the none line, as before, never half of it.
    Job10_03 = or_none(E(
        L(P, "{1} шанс получить дополнительное золото из сундуков и тому подобного: от {2} до {3}",
            "{1} chance of extra gold from chests and the like: {2} to {3}",
            { "additional.cash", "pct" }, { "additional.cash_min", "num" }, { "additional.cash_max", "num" }),
        L(P, "{1} шанс получить мясо с определённых чудовищ и животных",
            "{1} chance of meat from certain monsters and animals", { "additional.meat", "pct" }))),
    Job10_04 = E(L(P, "{1} к расходу выносливости на прыжки и рывки рядом с гончей",
        "{1} stamina use of jumps and sprints with a hound nearby", { "v1", "mult" })),
    -- Щедрость: pawns get v2 of the effect, a share of it, not a bonus on it
    Job10_05 = E(L(P, "пешки в {1} м получают {2} эффекта лечащего предмета",
        "pawns within {1} m get {2} of a restorative's effect", { "v1", "dec" }, { "v2", "share" })),
    Job10_06 = E(L(P, "{1} к расходу выносливости на высший навык оружия", "{1} stamina use of the top weapon skill",
        { "v1", "mult" })),
}

-- rings: Special 0 ------------------------------------------------------------------------------------------------
-- The ring's armour fields, named by the game: plain (checked: Кольцо очищения's poison resist +5 % -> +105 %).
-- The two defences are followed by their total line: the field's value is what the ring adds.

local FIELDS = {
    PhysicalDefence = { "{1} к физ. защите", "{1} defense", "signed", "phys" },
    MagicDefence = { "{1} к маг. защите", "{1} magick defense", "signed", "magic" },
    SlashDefenceRate = { "-{1} получаемого рубящего урона", "-{1} slash damage taken", "pct" },
    StrikeDefenceRate = { "-{1} получаемого дробящего урона", "-{1} blunt damage taken", "pct" },
    FireDefence = { "-{1} урона от огня", "-{1} fire damage taken", "pct" },
    IceDefence = { "-{1} урона от льда", "-{1} ice damage taken", "pct" },
    ThunderDefence = { "-{1} урона от молнии", "-{1} lightning damage taken", "pct" },
    PoisonResist = { "{1} устойчивости к отравлению", "{1} poison resistance", "signed_pct" },
    SleepResist = { "{1} устойчивости ко сну", "{1} sleep resistance", "signed_pct" },
    WaterResist = { "{1} устойчивости к намоканию", "{1} drenched resistance", "signed_pct" },
    OilResist = { "{1} устойчивости к осмолению", "{1} tarred resistance", "signed_pct" },
    SilentResist = { "{1} устойчивости к немоте", "{1} silence resistance", "signed_pct" },
    StoneResist = { "{1} устойчивости к окаменению", "{1} petrification resistance", "signed_pct" },
    FireResist = { "{1} устойчивости к воспламенению", "{1} burning resistance", "signed_pct" },
    IceResist = { "{1} устойчивости к ледяным оковам", "{1} frozen resistance", "signed_pct" },
    FaintResist = { "{1} устойчивости к обмороку", "{1} fainting resistance", "signed_pct" },
    ColdResist = { "{1} устойчивости к холоду (потере выносливости)", "{1} cold resistance (stamina loss)",
        "signed_pct" },
}

-- One plain line per named field (a defence with its total line).
local function fields(...)
    local lines = {}
    for i, name in ipairs({ ... }) do
        local f = FIELDS[name]
        lines[i] = L(P, f[1], f[2], { "fields." .. name, f[3] })
        if f[4] ~= nil then lines[i].total, lines[i].total_add = f[4], "fields." .. name end
    end
    return { lines = lines }
end

-- Экзорцизм, Драконья погибель (Special 0, no fields) and Погибель демонов (53): ArmorSpecialEfficacyParam's
-- AttackRate against its kinds, named by the game; plain, both other mods read the same percent.
local BANE = E(L(P, "{1} к атаке против:[ {2}][ и ещё {3}]", "{1} attack against:[ {2}][ and {3} more]",
    { "efficacy.rate", "signed_pct" }, { "efficacy.kinds", "list" }, { "efficacy.unnamed", "num" }))

-- rings: by Special type -------------------------------------------------------------------------------------------
-- The rings by their Special type. Plain: types 1-6 (Кольцо признания gave +200 max HP in
-- game); the lines both other mods read as we do (7, 8, 9, 11's health, 12, 13, 14, 22, 25, 27, 46, 48, 49's
-- count, and the former ? lines 15, 17, 23, 26, 30, 36); the reading both share, taken over ours, for 18, 31's objects
-- and explosives, 35, 41, 44, 45, 47, 50, 51; checked in the game on 2026-11-07: 21, 35's drain, 41. ≈: one of them
-- silent or reading it otherwise (10, 11's cast time, 20, 24, 31's creatures, 34, 40, 42, 43, 49's chance and wins,
-- 57). ?: what the number does is not clear (16, 32, 33, 37, 54, 55, 58). The numbers of 40, 49, 53, 57, 58 and of
-- the curves (15, 23) are in the game's other tables (read by game/hidden_stats.lua).

local TYPES = {
    [1] = E(L(P, "{1} к макс. здоровью", "{1} max health", { "v1", "signed" })),
    [2] = E(L(P, "{1} к макс. выносливости", "{1} max stamina", { "v1", "signed" })),
    [3] = E(L(P, "{1} кг к пределу веса", "{1} kg max carry weight", { "v1", "signed" })),
    [4] = E(L(P, "{1} к макс. здоровью", "{1} max health", { "v1", "signed" }),
        L(P, "{1} к макс. выносливости", "{1} max stamina", { "v2", "signed" }),
        L(P, "{1} кг к пределу веса", "{1} kg max carry weight", { "v3", "signed" })),
    [5] = E(L(P, "{1} к силе", "{1} strength", { "v1", "signed" })),
    [6] = E(L(P, "{1} к магии", "{1} magick", { "v1", "signed" })),
    [7] = E(L(P, "{1} опыта за врагов", "{1} experience from enemies", { "v1", "signed_pct" })),
    [8] = E(L(P, "{1} дисциплины за врагов", "{1} discipline from enemies", { "v1", "signed_pct" })),
    [9] = E(L(P, "{1} здоровья за победу над врагом", "{1} health per enemy defeated", { "v1", "signed" })),
    -- cast time: BBID reads v1 as a cast speed (+15 % speed is -13 % time), so ≈ (ours kept)
    [10] = E(L(A, "-{1} времени чтения заклинаний", "-{1} spell casting time", { "v1", "pct" })),
    [11] = E(L(A, "-{1} времени чтения заклинаний", "-{1} spell casting time", { "v1", "pct" }),
        L(P, "-{1} макс. здоровья", "-{1} max health", { "v2", "pct" })),
    [12] = E(L(P, "{1} к сопротивлению сбиванию и оглушению", "{1} knockdown and stagger resistance",
        { "v1", "signed" })),
    [13] = E(L(P, "-{1} выносливости на блок щитом", "-{1} stamina for shield blocks", { "v1", "pct" })),
    [14] = E(L(P, "{1} силы на {2} с после парирования", "{1} strength for {2} s after a parry",
        { "v1", "signed_pct" }, { "v2", "dec" })),
    -- Кольцо атлетичности: a % of the base strength as both other mods read it, by the steps of its curve over
    -- the carried weight, the number the party screen shows (read live on 2026-11-07: up to 10 → 20, up to 20 → 10,
    -- then 0, as CED and BBID give them); no personal number, since each step holds only at its own load. Its curve's
    -- top when the steps cannot be read.
    [15] = E(L(P, "{1} от базовой силы при поклаже до {2}[, {3} — до {4}][, {5} — до {6}][, {7} — до {8}]",
            "{1} of the base strength with a load of up to {2}[, {3} up to {4}][, {5} up to {6}][, {7} up to {8}]",
            step_nums()),
        fallback(L(P, "до {1} от базовой силы при лёгкой поклаже", "up to {1} of the base strength with a light load",
            { "curve.top", "signed_pct" }))),
    -- Кольцо благодати: BBID's Lua reading (its JSON and CED read it otherwise), ?
    [16] = E(L(G, "после удара больше {1} макс. здоровья — лечение {2} с",
        "after a hit of more than {1} of max health, heals for {2} s", { "v1", "pct" }, { "v2", "dec" })),
    -- Кольцо вознаграждения: v1 the health threshold, v2 a % of the base strength, as both other mods read it (BBID
    -- cites the game's getJewelryPhysicalAttackStatusFactor, like 18's), with its personal number; the
    -- condition first
    [17] = E(based(L(P, "при здоровье не выше {1}: {2} от базовой силы", "at {1} health or less: {2} of {whose} base "
        .. "strength", { "v1", "pct" }, { "v2", "signed_pct" }), "strength", "v2")),
    -- Кольцо превосходства: v1 is the bonus at full health, v2 is not used (both other mods; BBID cites the game's
    -- getJewelryPhysicalAttackStatusFactor); the condition first
    [18] = E(based(L(P, "при полном здоровье: {1} от базовой силы", "at full health: {1} of {whose} base strength",
        { "v1", "signed_pct" }), "strength", "v1")),
    [20] = E(L(A, "{1} к угрозе", "{1} threat", { "v1", "add" })),
    -- Кольцо проворства: checked in the game on 2026-11-07: with the ring the stamina refilled ≈ 12 % faster in
    -- both phases (after exhaustion 45.7 → 51.0 a second, then 88.6 → 100.0), so v1 adds to a multiplier; CED's
    -- "10 per second" is wrong
    [21] = E(L(P, "{1} к скорости восстановления выносливости", "{1} stamina recovery speed", { "v1", "signed_pct" })),
    [22] = E(L(P, "{1} к силе сбивания", "{1} knockdown power", { "v1", "signed" })),
    -- Кольцо близости: by the steps of its curve over the distance to the target (read live on 2026-11-07: up to 5 →
    -- 30, up to 10 → 20, up to 15 → 10, then 0); what it raises in the game's words («силу выстрела из лука», "bow
    -- attack" in the Japanese text too); no unit, since no source names one (CED says only "the closer", BBID
    -- "distance"). Its curve's top when the steps cannot be read.
    [23] = E(L(P, "{1} к силе выстрела из лука на расстоянии до {2} от цели[, {3} — до {4}][, {5} — до {6}]"
            .. "[, {7} — до {8}]",
            "{1} bow attack strength within {2} of the target[, {3} within {4}][, {5} within {6}][, {7} within {8}]",
            step_nums()),
        fallback(L(P, "до {1} к силе выстрела из лука вблизи цели", "up to {1} bow attack strength close to the target",
            { "curve.top", "signed_pct" }))),
    -- Кольцо отваги: ours, by the game's description; BBID's label reads both as damage dealt / taken
    [24] = E(L(A, "-{1} урона от дальних атак спереди", "-{1} damage from ranged attacks from the front",
        { "v1", "pct" }),
        L(A, "{1} урона от попаданий в спину", "{1} damage from hits in the back", { "v2", "signed_pct" })),
    [25] = E(L(P, "{1} урона при атаке в спину", "{1} damage when attacking from behind", { "v1", "signed_pct" })),
    [26] = E(L(P, "{1} к защите пешки на {2} с после того, как ты её поднял",
        "{1} defense for a pawn for {2} s after you help it up", { "v1", "signed" }, { "v2", "dec" })),
    [27] = E(L(P, "{1} к лечению от предметов", "{1} healing from items", { "v1", "signed_pct" })),
    [28] = SILENT,
    [29] = NONE,
    [30] = E(L(P, "{1} к росту симпатии, пока кольцо надето", "{1} affinity gain while worn", { "v1", "signed_pct" })),
    -- Кольцо метательности: thrown objects and explosives (both other mods), creatures (BBID only)
    [31] = E(L(P, "{1} урона брошенными предметами", "{1} damage with thrown objects", { "v1", "signed_pct" }),
        L(P, "{1} урона брошенной взрывчаткой", "{1} damage with thrown explosives", { "v2", "signed_pct" }),
        L(A, "{1} урона брошенными существами", "{1} damage with thrown creatures", { "v3", "signed_pct" })),
    [32] = E(L(G, "при здоровье не выше {1} скрывает на {2} с, перезарядка {3} с",
        "at {1} health or less hides you for {2} s, cooldown {3} s", { "v1", "pct" }, { "v2", "dec" }, { "v3", "dec" })),
    [33] = E(L(G, "{1} шанс замедлить нападающего; {2} и {3} — смысл не известен",
        "{1} chance to slow the attacker; {2} and {3}: meaning unknown", { "v1", "pct" }, { "v2", "dec" },
        { "v3", "dec" })),
    [34] = E(L(A, "-{1} макс. выносливости", "-{1} max stamina", { "v1", "pct" }),
        L(A, "{1} макс. здоровья", "{1} max health", { "v2", "signed_pct" })),
    -- Кольцо отмены: v1 is the health lost each second in battle; the heal from enemy hits has no number. The
    -- drain is checked in the game on 2026-11-07: from the battle's start the wearer lost 120 health a second
    -- (the hired pawn Alex, 11 s steady); the heal from enemy hits was not settled by it and stays as both other mods
    -- read it
    [35] = E(L(P, "в бою -{1} здоровья в секунду, а удары врагов лечат",
        "-{1} health per second in battle; enemy hits heal you", { "v1", "dec" })),
    -- Кольцо лунатика: per second, as both other mods read it
    [36] = E(L(P, "днём -{1} здоровья в секунду, ночью +{2} в секунду",
        "-{1} health per second by day, +{2} per second at night", { "v1", "dec" }, { "v2", "dec" })),
    [37] = E(L(G, "{1} шанс, что подойдут кролики", "{1} chance that rabbits come", { "v1", "pct" })),
    [38] = NONE,
    [39] = SILENT,
    [40] = E(L(A, "{1} урона в секунду, пока не атакуешь", "{1} damage per second while you do not attack",
        { "always.per_sec", "num" }),
        L(A, "урон начинается через {1} с после атаки[, через {2} с после идеального уклонения]",
            "the damage starts {1} s after an attack[, {2} s after a perfect dodge]",
            { "always.cool", "dec" }, { "always.cool_dodge", "dec" })),
    -- Кольцо бессилия: v1 % of the stamina the skill cost comes back (both other mods). Checked in the game on
    -- 2026-11-07: each weapon skill cost 104.5 stamina and about a second later 20.9 (20 %) came back, every time
    [41] = E(L(P, "возвращает {1} выносливости, потраченной на навык, если его первый удар попал",
        "{1} of the stamina spent on a weapon skill comes back when its first hit lands", { "v1", "pct" })),
    -- Кольцо безмятежности: ≈ on its own. The "%" is read as type 21's, which the check in the game showed to be
    -- a % on the recovery speed, and as BBID's "Stamina Recovery when exhausted +v1%" (another condition);
    -- CED's 7,5 % has no source in the ring's data. The ring itself is not checked
    [42] = E(L(A, "{1} к скорости восстановления выносливости без пешек", "{1} stamina recovery speed without pawns",
        { "v1", "signed_pct" })),
    [43] = E(L(A, "-{1} времени чтения заклинаний без пешек", "-{1} spell casting time without pawns",
        { "v1", "pct" })),
    -- 44, 45, 47, 50: a % of the base stat, as both other mods read them, with its personal number;
    -- 47 one line per defence; 51's knockdown power has no base the mod reads. 44, 45, 47 hold only without pawns:
    -- none for a pawn. The condition first, so that the base in brackets follows the stat (as for 17 and 18)
    [44] = E(no_pawn(based(L(P, "без пешек: {1} от базовой силы", "without pawns: {1} of {whose} base strength",
        { "v1", "signed_pct" }), "strength", "v1"))),
    [45] = E(no_pawn(based(L(P, "без пешек: {1} от базовой магии", "without pawns: {1} of {whose} base magick",
        { "v1", "signed_pct" }), "magic", "v1"))),
    [46] = E(L(P, "-{1} выносливости на рывок без пешек", "-{1} stamina for sprinting without pawns", { "v1", "pct" })),
    [47] = E(no_pawn(based(L(P, "без пешек: {1} от базовой защиты", "without pawns: {1} of {whose} base defense",
            { "v1", "signed_pct" }), "phys_defence", "v1")),
        no_pawn(based(L(P, "без пешек: {1} от базовой маг. защиты", "without pawns: {1} of {whose} base magick defense",
            { "v1", "signed_pct" }), "magic_defence", "v1"))),
    [48] = E(L(P, "{1} золота с врагов", "{1} gold from enemies", { "v1", "signed_pct" }),
        L(P, "-{1} опыта", "-{1} experience", { "v2", "pct" })),
    -- the chance ≈: BBID reads DropRateUp as a weight in the drop lottery, not a chance; the wins over
    -- Satanakia ≈: BBID does not show them
    [49] = E(L(A, "{1} к шансу редких материалов", "{1} rare material chance", { "drop.rate_up", "signed_pct" }),
        L(P, "{1} к количеству редких материалов", "{1} rare materials per drop", { "drop.count_up", "signed" }),
        L(A, "побед над Сатанакией для этого уровня: {1}", "wins over Satanakia for this level: {1}",
            { "drop.defeat", "num" })),
    [50] = E(based(L(P, "голыми руками: {1} от базовой силы", "bare-handed: {1} of {whose} base strength",
        { "v1", "signed_pct" }), "strength", "v1")),
    [51] = E(L(P, "голыми руками: {1} к силе сбивания", "bare-handed: {1} knockdown power", { "v1", "signed_pct" })),
    [52] = NONE,
    [53] = BANE,
    [54] = E(L(G, "с попутным ветром: прыжок +{1}, снаряды +{2} (метры или %)",
        "with a tailwind: jump +{1}, projectiles +{2} (meters or %)", { "v1", "dec" }, { "v2", "dec" })),
    [55] = E(L(G, "после смертельного удара останется {1} здоровья", "{1} health left after a fatal blow",
        { "v1", "num" })),
    [56] = SILENT,
    [57] = E(L(A, "базовый шанс {1} забрать реликвию обычной атакой", "base chance {1} to take a relic with a normal "
        .. "attack", { "pickpocket.base", "pct" }),
        L(A, "шанс у текущего призвания ×{1}", "chance for the current vocation ×{1}", { "pickpocket.factor", "dec" })),
    [58] = E(L(G, "выносливость за обычный удар: множитель {1}, предел {2}",
        "stamina per normal hit: factor {1}, cap {2}", { "rejuv.factor", "dec" }, { "rejuv.cap", "dec" })),
    [59] = NONE,
}

-- rings: by id -----------------------------------------------------------------------------------------------------

local RINGS = {
    -- Special 0
    [3509] = fields("PhysicalDefence"),                  -- Кольцо стойкости
    [3511] = fields("MagicDefence"),                     -- Кольцо сохранения
    [3512] = fields("SlashDefenceRate"),                 -- Кольцо отражения
    [3513] = fields("StrikeDefenceRate"),                -- Кольцо безразличия
    [3514] = fields("FireDefence"),                      -- Кольцо хлада
    [3515] = fields("IceDefence"),                       -- Кольцо тепла
    [3518] = fields("PoisonResist"),                     -- Кольцо очищения
    [3519] = fields("SleepResist"),                      -- Кольцо настороженности
    [3520] = fields("SleepResist"),                      -- Кольцо бессонницы
    [3521] = fields("WaterResist"),                      -- Кольцо иссушения
    [3522] = fields("OilResist"),                        -- Кольцо чистоты
    [3524] = fields("SilentResist"),                     -- Кольцо болтливости
    [3525] = fields("StoneResist"),                      -- Кольцо податливости
    [3526] = fields("StoneResist"),                      -- Кольцо подвижности
    [3527] = fields("FireResist"),                       -- Кольцо закалки
    [3528] = fields("IceResist"),                        -- Кольцо оттепели
    [8600] = fields("PhysicalDefence", "MagicDefence"),  -- Кольцо спокойствия
    [10200] = fields("ThunderDefence"),                  -- Кольцо громостойкости
    [10201] = BANE,                                      -- Кольцо экзорцизма
    [10202] = BANE,                                      -- Кольцо драконьей погибели
    -- Кольцо освобождения: its nine resists are equal (40 each), one line by the first
    [10205] = E(L(P, "{1} устойчивости ко всем 9 недугам", "{1} resistance to all 9 debilitations",
        { "fields.PoisonResist", "signed_pct" })),
    [10206] = fields("IceResist", "ColdResist"),         -- Морозное кольцо
    [10233] = fields("FaintResist"),                     -- Кольцо ясности сознания
    -- by type
    [3501] = TYPES[1], [3502] = TYPES[1],                -- ликования, признания
    [3503] = TYPES[2], [3504] = TYPES[2],                -- упорства, побуждения
    [3505] = TYPES[3], [3506] = TYPES[3],                -- накопления, изобилия
    [3507] = TYPES[4],                                   -- победы
    [3508] = TYPES[5],                                   -- агрессии
    [3510] = TYPES[6],                                   -- восприятия
    [3530] = TYPES[7],                                   -- устремлённости
    [3531] = TYPES[8],                                   -- стараний
    [3532] = TYPES[9],                                   -- восстановления
    [3533] = TYPES[10],                                  -- оратора
    [3534] = TYPES[11],                                  -- декламации
    [3535] = TYPES[12],                                  -- решимости
    [3536] = TYPES[13],                                  -- мужества
    [3537] = TYPES[14],                                  -- воздаяния (Requital)
    [3538] = TYPES[15],                                  -- атлетичности
    [3539] = TYPES[16],                                  -- благодати
    [3540] = TYPES[17],                                  -- вознаграждения
    [3541] = TYPES[18],                                  -- превосходства
    [3543] = TYPES[20],                                  -- немилости
    [3544] = TYPES[21],                                  -- проворства
    [3545] = TYPES[22],                                  -- бешенства
    [3548] = TYPES[23],                                  -- близости
    [3549] = TYPES[24],                                  -- отваги
    [3550] = TYPES[25],                                  -- надувательства
    [3551] = TYPES[26],                                  -- уверенности
    [3552] = TYPES[27],                                  -- преувеличения
    [3553] = TYPES[28],                                  -- Бирюзовое кольцо
    [3554] = TYPES[29],                                  -- насмешки
    [3555] = TYPES[30],                                  -- Вечные узы
    [10203] = TYPES[31],                                 -- метательности
    [10204] = TYPES[32],                                 -- невидимости
    [10207] = TYPES[33],                                 -- воздаяния (Retaliation)
    [10208] = TYPES[34],                                 -- преобразования
    [10209] = TYPES[35],                                 -- отмены
    [10210] = TYPES[36],                                 -- лунатика
    [10211] = TYPES[37],                                 -- любопытства
    [10212] = TYPES[38],                                 -- хозяина
    [10213] = TYPES[39],                                 -- возвращения (Rearrival)
    [10214] = TYPES[40],                                 -- храбрости
    [10215] = TYPES[41],                                 -- бессилия
    [10216] = TYPES[42],                                 -- безмятежности
    [10217] = TYPES[43],                                 -- монолога
    [10218] = TYPES[44],                                 -- нападения
    [10219] = TYPES[45],                                 -- колдовства
    [10220] = TYPES[46],                                 -- бега
    [10221] = TYPES[47],                                 -- сохранности
    [10222] = TYPES[48],                                 -- алчности
    [10223] = TYPES[49],                                 -- бескорыстия
    [10234] = TYPES[49], [10235] = TYPES[49], [10236] = TYPES[49],   -- нечестивой жажды, выгоды, ненасытности
    [10237] = TYPES[49], [10238] = TYPES[49], [10239] = TYPES[49],   -- нечестивого пира, жадности, крови
    [10224] = TYPES[50],                                 -- раздора
    [10225] = TYPES[51],                                 -- опрокидывания
    [10226] = TYPES[52],                                 -- уклонения
    [10227] = TYPES[53],                                 -- погибели демонов
    [10228] = TYPES[54],                                 -- воздушного планирования
    [10229] = TYPES[55],                                 -- возвращения (Contingency)
    [10230] = TYPES[56],                                 -- лёгкости
    [10231] = TYPES[57],                                 -- ограбления
    [10232] = TYPES[58],                                 -- омоложения
    [10240] = TYPES[59],                                 -- наёмника
}

function HiddenStatsData.augment(name)
    return type(name) == "string" and AUGMENTS[name] or nil
end

function HiddenStatsData.ring(id)
    if type(id) ~= "number" then return nil end
    local key = math.tointeger(id)
    return key and RINGS[key] or nil
end

return HiddenStatsData
