package.path = "mod/reframework/autorun/?.lua;tests/?.lua;" .. package.path

local T = require("testlib")
local test, eq = T.test, T.eq
local I18n = require("DD2DamageMeter/i18n")
local Data = require("DD2DamageMeter/hidden_stats_data")
local Model = require("DD2DamageMeter/hidden_stats_model")

-- The 52 augments: Job01_00..Job09_04 and Job10_00..Job10_06.
local AUGMENTS = {}
for job = 1, 10 do
    for i = 0, job == 10 and 6 or 4 do AUGMENTS[#AUGMENTS + 1] = string.format("Job%02d_%02d", job, i) end
end

-- The 90 rings, in a fixed order.
local RINGS = {
    3509, 3511, 3512, 3513, 3514, 3515, 3518, 3519, 3520, 3521, 3522, 3524, 3525, 3526, 3527, 3528, 8600, 10200,
    10201, 10202, 10205, 10206, 10233,
    3501, 3502, 3503, 3504, 3505, 3506, 3507, 3508, 3510, 3530, 3531, 3532, 3533, 3534, 3535, 3536, 3537, 3538, 3539,
    3540, 3541, 3543, 3544, 3545, 3548, 3549, 3550, 3551, 3552, 3553, 3554, 3555,
    10203, 10204, 10207, 10208, 10209, 10210, 10211, 10212, 10213, 10214, 10215, 10216, 10217, 10218, 10219, 10220,
    10221, 10222, 10223, 10234, 10235, 10236, 10237, 10238, 10239, 10224, 10225, 10226, 10227, 10228, 10229, 10230,
    10231, 10232, 10240,
}

local function aug(name, v1, v2) return Model.panel(Data.augment(name), { v1 = v1, v2 = v2 or 0 }) end

-- A ring's raw record (game/hidden_stats.lua's RingRaw); `o` adds or overrides fields.
local function ring_raw(o)
    local r = { special = 0, v1 = 0, v2 = 0, v3 = 0, fields = {} }
    for k, v in pairs(o or {}) do r[k] = v end
    return r
end

local function texts(panel)
    if panel == nil then return "nil" end
    local out = {}
    for _, l in ipairs(panel.lines) do out[#out + 1] = l.mark .. ":" .. l.text end
    return table.concat(out, " | ")
end

local function ends_with(s, tail) return type(s) == "string" and s:sub(-#tail) == tail end
local function starts_with(s, head) return type(s) == "string" and s:sub(1, #head) == head end

test("every augment and ring has an entry", function()
    eq(#AUGMENTS, 52, "52 augments")
    eq(#RINGS, 90, "90 rings")
    local seen = {}
    for _, id in ipairs(RINGS) do
        eq(seen[id], nil, "ring listed once: " .. id)
        seen[id] = true
    end
    for _, name in ipairs(AUGMENTS) do eq(type(Data.augment(name)), "table", "augment " .. name) end
    for _, id in ipairs(RINGS) do eq(type(Data.ring(id)), "table", "ring " .. id) end
end)

test("nothing for other names and items", function()
    eq(Data.augment("Job11_00"), nil, "no such augment")
    eq(Data.augment("Job01_05"), nil, "Fighter has 5")
    eq(Data.augment(nil), nil, "nil name")
    eq(Data.ring(1), nil, "not a ring")
    eq(Data.ring(3500), nil, "a gap in the ring ids")
    eq(Data.ring(nil), nil, "nil id")
    eq(Data.ring("3502"), nil, "a string id")
    eq(Data.ring(3502.5), nil, "not a whole id")
    eq(Data.ring(3502.0), Data.ring(3502), "a whole float is the id")
end)

test("silent and none entries", function()
    for _, e in ipairs({ Data.augment("Job10_02"), Data.ring(10213), Data.ring(3553), Data.ring(10230) }) do
        eq(e.silent, true, "silent")
        eq(e.lines, nil, "no lines")
    end
    -- Кольцо насмешки (3554, type 29) has no number either: the minimum it brings attacks down to is not known
    for _, e in ipairs({ Data.ring(10212), Data.ring(10240), Data.ring(10226), Data.ring(3554) }) do
        eq(e.none, true, "none")
        eq(e.lines, nil, "no lines")
    end
    -- Везение has its lines (read from its AdditionalItemParam), and the none line when they cannot be read
    local fortuity = Data.augment("Job10_03")
    eq(fortuity.none, nil, "Везение is not a none entry")
    eq(#fortuity.lines, 2, "its two lines")
    eq(fortuity.or_none, true, "the none line when no line can be written")
end)

test("marks: plain only where a developers' note, a field, a check in game or both other mods settle it", function()
    local want = {
        plain = { "Job05_00", "Job01_01", "Job03_00", "Job06_03", 3509, 10205, 3502, 3501, 3507, 3508, 3510,
                  -- both Clear Effect Descriptions and Better Better Item Description read them as we do
                  "Job02_00", "Job02_03", "Job04_02", "Job07_02", "Job08_02", 10201, 10202, 10227, 3530, 3531, 3532,
                  3535, 3536, 3537, 3545, 3550, 3552, 10220, 10222,
                  -- the ? lines both of them read as we do
                  3538, 3540, 3548, 3551, 3555, 10210,
                  -- both agree with each other against us: their reading taken
                  3541, 10218, 10219, 10221, 10224, 10225, 10209, 10215, 10203,
                  -- checked in the game (Проворство) or read where the other mods read them (Везение)
                  3544, "Job10_03" },
        approx = { "Job03_04", 3533, 3534, 3543, 3549, 10208, 10214, 10216, 10217, 10231, 10223 },
        guess = { "Job09_00", 10204, 3539, 10232 },
    }
    for mark, list in pairs(want) do
        for _, key in ipairs(list) do
            local e = type(key) == "string" and Data.augment(key) or Data.ring(key)
            eq(e.lines[1].mark, mark, tostring(key))
        end
    end
    -- the found-table rings: the bane rings plain, Храбрость and Ограбление ≈ on every line
    for _, id in ipairs({ 10201, 10202, 10227 }) do
        for i, l in ipairs(Data.ring(id).lines) do eq(l.mark, "plain", id .. " line " .. i) end
    end
    for _, id in ipairs({ 10214, 10231 }) do
        for i, l in ipairs(Data.ring(id).lines) do eq(l.mark, "approx", id .. " line " .. i) end
    end
    -- the drop rings: the count plain; the chance ≈ (BBID reads it as a lottery weight) and the wins over
    -- Satanakia ≈ (BBID does not show them)
    for _, id in ipairs({ 10223, 10234, 10239 }) do
        local lines = Data.ring(id).lines
        eq(lines[1].mark, "approx", id .. " chance")
        eq(lines[2].mark, "plain", id .. " count")
        eq(lines[3].mark, "approx", id .. " wins")
    end
    -- Везение: both lines plain; the curve rings: the steps and the top they fall back to, plain
    for i, l in ipairs(Data.augment("Job10_03").lines) do eq(l.mark, "plain", "Job10_03 line " .. i) end
    for _, id in ipairs({ 3538, 3548 }) do
        for i, l in ipairs(Data.ring(id).lines) do eq(l.mark, "plain", id .. " line " .. i) end
    end
    local stasis = Data.augment("Job06_01").lines
    eq(stasis[1].mark, "approx", "Стаз line 1")
    eq(stasis[2].mark, "guess", "Стаз line 2")
    -- Кольцо победы: three plain lines (flat adds, as Кольцо признания's was checked in game)
    local triumph = Data.ring(3507).lines
    eq(#triumph, 3, "three numbers")
    for i = 1, 3 do eq(triumph[i].mark, "plain", "3507 line " .. i) end
end)

-- Every ≈ and ? line after the cross-check with Clear Effect Descriptions 2.04 and Better Better Item Description:
-- ≈ stays where either mod is silent or reads it otherwise, ? where what the number does is not clear; where both
-- agree with each other against us, their reading; a ? line both read as we do is plain, and the drop rings' chance
-- is ≈ (BBID reads it as a lottery weight). Each line by its entry and place.
test("every ≈ and ? line after the cross-check with the other two mods", function()
    local found = {}
    local function scan(label, e)
        for i, l in ipairs(e.lines or {}) do
            if l.mark ~= "plain" then found[#found + 1] = label .. "/" .. i .. "=" .. l.mark end
        end
    end
    for _, name in ipairs(AUGMENTS) do scan(name, Data.augment(name)) end
    for _, id in ipairs(RINGS) do scan(tostring(id), Data.ring(id)) end
    table.sort(found)
    local want = {
        -- Возвышение (developers' note against CED's «10 в секунду»), Стаз (BBID gives no meaning), Обнаружение
        "Job03_04/1=approx", "Job06_01/1=approx", "Job06_01/2=guess", "Job09_00/1=guess",
        -- cast time (10, 11, 43: BBID's speed), Кольцо декламации's health is plain
        "3533/1=approx", "3534/1=approx", "10217/1=approx",
        -- Благодать (the mods differ)
        "3539/1=guess",
        -- Немилость, Преобразование (both silent); Отвага (BBID's label); Безмятежность. Проворство is plain: the
        -- check in the game settled it
        "3543/1=approx", "10208/1=approx", "10208/2=approx", "3549/1=approx", "3549/2=approx",
        "10216/1=approx",
        -- Метательность's characters (BBID only)
        "10203/3=approx",
        -- Невидимость, Воздаяние (Retaliation), Любопытство, Воздушное планирование, Возвращение, Омоложение
        "10204/1=guess", "10207/1=guess", "10211/1=guess", "10228/1=guess", "10229/1=guess", "10232/1=guess",
        -- Храбрость, Ограбление (BBID silent)
        "10214/1=approx", "10214/2=approx", "10231/1=approx", "10231/2=approx",
        -- the drop rings' chance (BBID: a lottery weight) and the wins over Satanakia (BBID silent)
        "10223/1=approx", "10234/1=approx", "10235/1=approx", "10236/1=approx", "10237/1=approx", "10238/1=approx",
        "10239/1=approx",
        "10223/3=approx", "10234/3=approx", "10235/3=approx", "10236/3=approx", "10237/3=approx", "10238/3=approx",
        "10239/3=approx",
    }
    table.sort(want)
    eq(table.concat(found, " "), table.concat(want, " "), "the ≈ and ? lines")
end)

-- Every line can be written: a known mark and conversion, sources the raw records have, the same places in both
-- languages, no mark of its own (the model adds it).
test("the data is well formed", function()
    local MARKS = { plain = true, approx = true, guess = true }
    local CONV = { num = true, signed = true, dec = true, pct = true, signed_pct = true, mult = true, add = true,
                   share = true, list = true }
    local BASES = { phys_defence = true, magic_defence = true, strength = true, magic = true }
    local RING_SRC = {
        v1 = true, v2 = true, v3 = true, ["efficacy.rate"] = true, ["efficacy.kinds"] = true,
        ["efficacy.unnamed"] = true, ["drop.rate_up"] = true, ["drop.count_up"] = true, ["drop.defeat"] = true,
        ["always.per_sec"] = true, ["always.cool"] = true, ["always.cool_dodge"] = true, ["pickpocket.base"] = true,
        ["pickpocket.factor"] = true, ["rejuv.factor"] = true, ["rejuv.cap"] = true, ["curve.top"] = true,
    }
    -- a curve's steps, up to the four game/hidden_stats.lua reads
    for n = 1, 4 do
        RING_SRC["curve.steps." .. n .. ".y"], RING_SRC["curve.steps." .. n .. ".to"] = true, true
    end
    -- an augment's row, or Везение's AdditionalItemParam
    local AUGMENT_SRC = { v1 = true, v2 = true, ["additional.cash"] = true, ["additional.meat"] = true,
                          ["additional.cash_min"] = true, ["additional.cash_max"] = true }
    local function places(text)
        local set, n = {}, 0
        for i in text:gmatch("{(%d+)}") do
            set[tonumber(i)] = true
            n = n + 1
        end
        local _, segments = text:gsub("%[", "")
        return set, n, segments
    end
    local function check(label, e, ring)
        if e.silent or e.none then return end
        eq(type(e.lines), "table", label .. " lines")
        eq(#e.lines > 0, true, label .. " has a line")
        for i, l in ipairs(e.lines) do
            local where = label .. " line " .. i
            eq(MARKS[l.mark], true, where .. " mark")
            eq(type(l.ru), "string", where .. " ru")
            eq(type(l.en), "string", where .. " en")
            eq(l.en:find("[\208\209]"), nil, where .. " en has no Cyrillic")
            for _, text in ipairs({ l.ru, l.en }) do
                eq(starts_with(text, "≈") or starts_with(text, "?"), false, where .. " carries no mark")
                eq(text:find("≤", 1, true), nil, where .. " no ≤ (not checked in the game's font)")
            end
            eq(#l.nums > 0, true, where .. " nums")
            local ru_set, _, ru_seg = places(l.ru)
            local en_set, _, en_seg = places(l.en)
            eq(ru_seg, en_seg, where .. " segments in both languages")
            for n = 1, #l.nums do
                eq(ru_set[n], true, where .. " ru shows {" .. n .. "}")
                eq(en_set[n], true, where .. " en shows {" .. n .. "}")
            end
            for n in pairs(ru_set) do eq(l.nums[n] ~= nil, true, where .. " ru {" .. n .. "} has a num") end
            for n in pairs(en_set) do eq(l.nums[n] ~= nil, true, where .. " en {" .. n .. "} has a num") end
            for _, num in ipairs(l.nums) do
                eq(CONV[num.as], true, where .. " conversion " .. tostring(num.as))
                if ring then
                    eq(RING_SRC[num.src] or (num.src or ""):match("^fields%.%u%a+$") ~= nil, true,
                        where .. " source " .. tostring(num.src))
                else
                    eq(AUGMENT_SRC[num.src], true, where .. " source " .. tostring(num.src))
                end
            end
            if l.base ~= nil then
                eq(BASES[l.base], true, where .. " base")
                eq(type(l.base_pct), "string", where .. " base_pct")
                -- English says whose base it is before the stat
                eq(l.en:find("{whose}", 1, true) ~= nil, true, where .. " en has {whose}")
            else
                eq(l.en:find("{whose}", 1, true), nil, where .. " {whose} only with a base")
            end
            eq(l.ru:find("{whose}", 1, true), nil, where .. " ru says whose in the brackets")
            -- no_pawn only on a line with a base, and only true
            if l.no_pawn ~= nil then
                eq(l.no_pawn, true, where .. " no_pawn true")
                eq(l.base ~= nil, true, where .. " no_pawn with a base")
            end
            if l.total ~= nil then
                eq(l.total == "phys" or l.total == "magic", true, where .. " total")
                eq(l.base ~= nil or type(l.total_add) == "string", true, where .. " a bonus for the total")
            end
            -- fallback: only true, never on the first line (it stands in for the lines before it)
            if l.fallback ~= nil then
                eq(l.fallback, true, where .. " fallback true")
                eq(i > 1, true, where .. " fallback after a line")
            end
        end
        eq(e.or_none == nil or e.or_none == true, true, label .. " or_none true")
    end
    for _, name in ipairs(AUGMENTS) do check(name, Data.augment(name), false) end
    for _, id in ipairs(RINGS) do check(tostring(id), Data.ring(id), true) end
end)

test("the total lines are Стойкость's, Изгнание's and the defence rings', nothing else", function()
    local found = {}
    local function scan(label, e)
        for i, l in ipairs(e.lines or {}) do
            if l.total ~= nil then found[#found + 1] = label .. "/" .. i .. "=" .. l.total end
        end
    end
    for _, name in ipairs(AUGMENTS) do scan(name, Data.augment(name)) end
    for _, id in ipairs(RINGS) do scan(tostring(id), Data.ring(id)) end
    table.sort(found)
    eq(table.concat(found, " "), "3509/1=phys 3511/1=magic 8600/1=phys 8600/2=magic Job01_01/1=phys "
        .. "Job03_00/1=magic", "the lines with a total")
    eq(Data.ring(3509).lines[1].total_add, "fields.PhysicalDefence", "a ring adds its field")
    eq(Data.ring(8600).lines[2].total_add, "fields.MagicDefence", "8600's second")
    eq(Data.augment("Job01_01").lines[1].total_add, nil, "an augment adds its personal number")
end)

test("panel texts", function()
    I18n.set("ru")
    local p = aug("Job05_00", 200, 0)
    eq(p.lines[1].text, "+200 к макс. здоровью", "Жизненная сила")
    eq(p.lines[1].mark, "plain", "plain")
    eq(#p.lines, 1, "one line")
    eq(p.legend, false, "no legend")
    I18n.set("en")
    eq(aug("Job05_00", 200, 0).lines[1].text, "+200 max health", "Vitality in English")
    I18n.set("ru")
    local mettle = Model.panel(Data.augment("Job01_01"), { v1 = 45, v2 = 30 }, { who = "player", phys_defence = 380 })
    eq(mettle.lines[1].text, "+45 и +30% от базовой защиты (у тебя 380) — сейчас +159", "Стойкость, the player")
    eq(mettle.legend, false, "Стойкость is plain")
    local pawn = Model.panel(Data.augment("Job01_01"), { v1 = 45, v2 = 30 }, { who = "pawn", phys_defence = 380 })
    eq(ends_with(pawn.lines[1].text, "(у пешки 380) — сейчас +159"), true, "the pawn: " .. pawn.lines[1].text)
    local nobase = Model.panel(Data.augment("Job01_01"), { v1 = 45, v2 = 30 }, nil)
    eq(ends_with(nobase.lines[1].text, "от базовой защиты (число в скобках на экране статуса)"), true,
        "no base: " .. nobase.lines[1].text)
    -- Засада: both other mods read +10 %
    local ambush = aug("Job02_00", 0.1, 0)
    eq(texts(ambush), "plain:+10% урона по врагам не в боевой стойке", "Засада")
    eq(ambush.legend, false, "no legend")
    local exaltation = aug("Job03_04", 0.1, 0)
    eq(exaltation.lines[1].text, "≈ +10% к скорости восстановления выносливости", "Возвышение")
    eq(exaltation.lines[1].mark, "approx", "approx")
    eq(exaltation.legend, true, "legend")
    local stasis = aug("Job06_01", 75, 90)
    eq(#stasis.lines, 2, "Стаз: two lines")
    eq(starts_with(stasis.lines[1].text, "≈ "), true, "Стаз line 1: " .. stasis.lines[1].text)
    eq(starts_with(stasis.lines[2].text, "? "), true, "Стаз line 2: " .. stasis.lines[2].text)
    eq(stasis.lines[2].text:find("90", 1, true) ~= nil, true, "Стаз line 2 names 90")
    eq(stasis.lines[2].mark, "guess", "guess")
    local none = Model.panel(Data.ring(10212), {})
    eq(#none.lines, 1, "one line")
    eq(none.lines[1].text, "числа в игре не нашлось", "Кольцо хозяина")
    eq(none.lines[1].mark, "none", "mark none")
    eq(none.legend, false, "no legend")
    eq(Model.panel(Data.ring(10213), {}), nil, "Кольцо возвращения (Rearrival): no panel")
    I18n.set("en")
    eq(Model.panel(Data.ring(10212), {}).lines[1].text, "no number found in the game", "none in English")
    I18n.set("ru")
end)

test("Щедрость (Job10_05): pawns get a share of the effect, not a bonus on it", function()
    I18n.set("ru")
    local bounty = aug("Job10_05", 10, 0.3)
    eq(texts(bounty), "plain:пешки в 10 м получают 30% эффекта лечащего предмета", "ru")
    eq(bounty.legend, false, "plain")
    -- the numbers stay the game's: the range from v1, the share from v2
    eq(aug("Job10_05", 15, 0.5).lines[1].text, "пешки в 15 м получают 50% эффекта лечащего предмета", "other numbers")
    I18n.set("en")
    eq(aug("Job10_05", 10, 0.3).lines[1].text, "pawns within 10 m get 30% of a restorative's effect", "en")
    I18n.set("ru")
end)

test("the personal number's words: the base in brackets, then what it gives now", function()
    I18n.set("ru")
    local mettle = Data.augment("Job01_01")
    local raw = { v1 = 45, v2 = 30 }
    eq(texts(Model.panel(mettle, raw, { who = "player", phys_defence = 380 })),
        "plain:+45 и +30% от базовой защиты (у тебя 380) — сейчас +159", "Стойкость, the player")
    -- the personal number as before: 45 + 30 % × 375 = 157,5, whole
    eq(texts(Model.panel(mettle, raw, { who = "pawn", phys_defence = 375 })),
        "plain:+45 и +30% от базовой защиты (у пешки 375) — сейчас +158", "Стойкость, a pawn")
    eq(texts(Model.panel(mettle, raw, nil)),
        "plain:+45 и +30% от базовой защиты (число в скобках на экране статуса)", "no base")
    -- the base in brackets as the status screen shows it: floored, grouped as I18n.num groups
    local apo = Model.panel(Data.augment("Job03_00"), raw, { who = "player", magic_defence = 373.8 })
    eq(apo.lines[1].text, "+45 и +30% от базовой маг. защиты (у тебя 373) — сейчас +157",
        "Изгнание: 373,8 floored in brackets, 157,14 as a whole")
    eq(Model.panel(mettle, raw, { who = "player", phys_defence = 1234.9 }).lines[1].text,
        "+45 и +30% от базовой защиты (у тебя 1 234) — сейчас +415", "a base of four digits")
    -- Полярность: its flat part is 0 in the game, so no «+0 и»; plain since both other mods read it so
    local base = { who = "player", strength = 420, magic = 372.2 }
    local pol = Model.panel(Data.augment("Job07_02"), { v1 = 0, v2 = 5 }, base)
    eq(texts(pol), "plain:+5% от базовой силы днём (у тебя 420) — сейчас +21"
        .. " | plain:+5% от базовой магии ночью (у тебя 372) — сейчас +19", "day and night")
    eq(pol.legend, false, "no ≈ line")
    eq(texts(Model.panel(Data.augment("Job07_02"), { v1 = 0, v2 = 5 }, nil)),
        "plain:+5% от базовой силы днём (число в скобках на экране статуса)"
        .. " | plain:+5% от базовой магии ночью (число в скобках на экране статуса)", "Полярность, no base")
    -- its flat part v1 counts in the personal number, as Стойкость's and Изгнание's do, and is shown
    eq(Data.augment("Job07_02").lines[1].base_add, "v1", "day: base_add v1")
    eq(Data.augment("Job07_02").lines[2].base_add, "v1", "night: base_add v1")
    local flat = Model.panel(Data.augment("Job07_02"), { v1 = 10, v2 = 5 }, base)
    eq(flat.lines[1].text, "+10 и +5% от базовой силы днём (у тебя 420) — сейчас +31", "day: 10 + 5 % × 420")
    eq(flat.lines[2].text, "+10 и +5% от базовой магии ночью (у тебя 372) — сейчас +29", "night: 10 + 5 % × 372.2")
    -- Стойкость's flat part 0 is not written either
    eq(Model.panel(mettle, { v1 = 0, v2 = 30 }, { who = "player", phys_defence = 380 }).lines[1].text,
        "+30% от базовой защиты (у тебя 380) — сейчас +114", "no «+0 и» for Стойкость")
    -- a base without that stat, or of nobody known: the hint, never another stat's number
    local hint = "от базовой защиты (число в скобках на экране статуса)"
    local other = Model.panel(mettle, raw, { who = "player", magic_defence = 373.8 })
    eq(ends_with(other.lines[1].text, hint), true, "no phys_defence: " .. other.lines[1].text)
    local who = Model.panel(mettle, raw, { phys_defence = 380 })
    eq(ends_with(who.lines[1].text, hint), true, "no who: " .. who.lines[1].text)
    local nan = Model.panel(mettle, raw, { who = "pawn", phys_defence = 0 / 0 })
    eq(ends_with(nan.lines[1].text, hint), true, "NaN base: " .. nan.lines[1].text)
    I18n.set("en")
    eq(Model.panel(mettle, raw, { who = "player", phys_defence = 380 }).lines[1].text,
        "+45 and +30% of your base defense (380) — +159 now", "en player")
    eq(Model.panel(mettle, raw, { who = "pawn", phys_defence = 375 }).lines[1].text,
        "+45 and +30% of the pawn's base defense (375) — +158 now", "en pawn")
    eq(Model.panel(mettle, raw).lines[1].text,
        "+45 and +30% of the base defense (the number in brackets on the status screen)", "en no base")
    eq(Model.panel(Data.augment("Job03_00"), raw, { who = "player", magic_defence = 373.8 }).lines[1].text,
        "+45 and +30% of your base magick defense (373) — +157 now", "en Изгнание")
    eq(texts(Model.panel(Data.augment("Job07_02"), { v1 = 0, v2 = 5 }, base)),
        "plain:+5% of your base strength by day (420) — +21 now"
        .. " | plain:+5% of your base magick at night (372) — +19 now", "en Полярность")
    I18n.set("ru")
end)

-- The shown character's totals, whether the thing is on them and whose they are, as the wiring passes them;
-- `who` "player" unless given.
local function on(phys, magic, who) return { phys = phys, magic = magic, equipped = true, who = who or "player" } end
local function off(phys, magic, who) return { phys = phys, magic = magic, equipped = false, who = who or "player" } end

test("the total line: under a defence line, the total before → after and the percent", function()
    I18n.set("ru")
    local mettle, raw, base = Data.augment("Job01_01"), { v1 = 45, v2 = 30 }, { who = "player", phys_defence = 380 }
    -- equipped: the status screen's 1645 has the 159 in it; then the damage taken
    local p = Model.panel(mettle, raw, base, on(1645, 1494.94))
    eq(texts(p), "plain:+45 и +30% от базовой защиты (у тебя 380) — сейчас +159 | plain:защита 1486 → 1645 (+11%)"
        .. " | approx:≈ -10% физ. урона по тебе", "Стойкость equipped")
    -- not equipped: the 159 comes on top of the total
    eq(Model.panel(mettle, raw, base, off(1486, 1337.8)).lines[2].text, "защита 1486 → 1645 (+11%)",
        "Стойкость not equipped")
    -- Изгнание: magick defence, the totals floored as the status screen floors them (1494,94 shows as 1494)
    local apo = Model.panel(Data.augment("Job03_00"), raw, { who = "player", magic_defence = 373.8 },
        on(1645, 373.8 + 157.14 + 964))
    eq(apo.lines[2].text, "маг. защита 1337 → 1494 (+12%)", "Изгнание equipped")
    eq(Model.panel(Data.augment("Job03_00"), raw, { who = "pawn", magic_defence = 373.8 }, off(1645, 1337.8, "pawn"))
        .lines[2].text, "маг. защита 1337 → 1494 (+12%)", "Изгнание not equipped, a pawn's")
    -- a pawn's personal number is her own: 45 + 30 % × 375 = 157,5
    eq(Model.panel(mettle, raw, { who = "pawn", phys_defence = 375 }, on(1600.5, 1400, "pawn")).lines[2].text,
        "защита 1443 → 1600 (+11%)", "a pawn equipped")
    -- the rings: the ArmorParam's field is what they add
    local steel = Model.panel(Data.ring(3509), ring_raw({ fields = { PhysicalDefence = 50 } }), nil, off(1486, 1337))
    eq(texts(steel), "plain:+50 к физ. защите | plain:защита 1486 → 1536 (+3%) | approx:≈ -3% физ. урона по тебе",
        "Кольцо стойкости not equipped")
    eq(Model.panel(Data.ring(3509), ring_raw({ fields = { PhysicalDefence = 50 } }), nil, on(1536, 1337)).lines[2]
        .text, "защита 1486 → 1536 (+3%)", "Кольцо стойкости equipped")
    eq(texts(Model.panel(Data.ring(3511), ring_raw({ fields = { MagicDefence = 50 } }), nil, on(1645, 1494.94))),
        "plain:+50 к маг. защите | plain:маг. защита 1444 → 1494 (+3%) | approx:≈ -3% маг. урона по тебе",
        "Кольцо сохранения equipped")
    I18n.set("en")
    eq(Model.panel(mettle, raw, base, on(1645, 1494.94)).lines[2].text, "defense 1486 → 1645 (+11%)", "en")
    eq(Model.panel(Data.augment("Job03_00"), raw, { who = "player", magic_defence = 373.8 }, on(1645, 1494.94))
        .lines[2].text, "magick defense 1337 → 1494 (+12%)", "en magick")
    I18n.set("ru")
end)

test("the damage taken: ≈, under each total line, 1 − before / after, for you or the pawn", function()
    I18n.set("ru")
    local mettle, raw = Data.augment("Job01_01"), { v1 = 45, v2 = 30 }
    local player, pawn = { who = "player", phys_defence = 380 }, { who = "pawn", phys_defence = 380 }
    -- Стойкость equipped, 1486 → 1645: 1 − 1486 / 1645 = 9,67 %, whole and with its sign
    local p = Model.panel(mettle, raw, player, on(1645, 1494.94))
    eq(#p.lines, 3, "the line, its total, the damage")
    eq(p.lines[3].text, "≈ -10% физ. урона по тебе", "the player")
    eq(p.lines[3].mark, "approx", "approx")
    eq(p.legend, true, "the only ≈ line brings the legend")
    eq(Model.panel(mettle, raw, pawn, on(1645, 1494.94, "pawn")).lines[3].text, "≈ -10% физ. урона по пешке",
        "the pawn")
    -- not equipped: the same before and after
    eq(Model.panel(mettle, raw, player, off(1486, 0)).lines[3].text, "≈ -10% физ. урона по тебе", "not equipped")
    -- the magick form: Изгнание, 1337,8 → 1494,94 = 10,5 %
    local apo, mbase = Data.augment("Job03_00"), { who = "player", magic_defence = 373.8 }
    eq(Model.panel(apo, raw, mbase, on(1645, 1494.94)).lines[3].text, "≈ -11% маг. урона по тебе", "magick")
    eq(Model.panel(apo, raw, { who = "pawn", magic_defence = 373.8 }, on(1645, 1494.94, "pawn")).lines[3].text,
        "≈ -11% маг. урона по пешке", "magick, the pawn")
    I18n.set("en")
    eq(Model.panel(mettle, raw, player, on(1645, 1494.94)).lines[3].text, "≈ -10% physical damage taken", "en")
    eq(Model.panel(mettle, raw, pawn, on(1645, 1494.94, "pawn")).lines[3].text,
        "≈ -10% physical damage the pawn takes", "en pawn")
    eq(Model.panel(apo, raw, mbase, on(1645, 1494.94)).lines[3].text, "≈ -11% magick damage taken", "en magick")
    eq(Model.panel(apo, raw, { who = "pawn", magic_defence = 373.8 }, on(1645, 1494.94, "pawn")).lines[3].text,
        "≈ -11% magick damage the pawn takes", "en magick, the pawn")
    I18n.set("ru")
    -- no total line, no damage line
    eq(#Model.panel(mettle, raw, player, nil).lines, 1, "no totals")
    eq(Model.panel(mettle, raw, player, nil).legend, false, "no ≈ line: no legend")
    eq(#Model.panel(mettle, raw, player, { phys = 1645, equipped = nil, who = "player" }).lines, 1,
        "the equipped check unknown")
    -- whose unknown: the total line, no damage line (never guessed)
    local steel = Model.panel(Data.ring(3509), ring_raw({ fields = { PhysicalDefence = 50 } }), nil,
        { phys = 1486, equipped = false })
    eq(texts(steel), "plain:+50 к физ. защите | plain:защита 1486 → 1536 (+3%)", "whose unknown")
    eq(steel.legend, false, "no legend then")
end)

test("Кольцо спокойствия (8600) has two total lines, each under its own line, each with its damage line", function()
    I18n.set("ru")
    local calm = ring_raw({ fields = { PhysicalDefence = 10, MagicDefence = 10 } })
    eq(texts(Model.panel(Data.ring(8600), calm, nil, on(1645, 1494.94))),
        "plain:+10 к физ. защите | plain:защита 1635 → 1645 (+1%) | approx:≈ -1% физ. урона по тебе"
        .. " | plain:+10 к маг. защите | plain:маг. защита 1484 → 1494 (+1%) | approx:≈ -1% маг. урона по тебе",
        "equipped")
    eq(texts(Model.panel(Data.ring(8600), calm, nil, off(1645, nil))),
        "plain:+10 к физ. защите | plain:защита 1645 → 1655 (+1%) | approx:≈ -1% физ. урона по тебе"
        .. " | plain:+10 к маг. защите", "the magick total unread: its line only")
    I18n.set("ru")
end)

test("no total line when anything it needs cannot be read; none for other lines", function()
    I18n.set("ru")
    local mettle, raw, base = Data.augment("Job01_01"), { v1 = 45, v2 = 30 }, { who = "player", phys_defence = 380 }
    local function count(total, b)
        if b == nil then b = base elseif b == false then b = nil end
        return #Model.panel(mettle, raw, b, total).lines
    end
    eq(count(nil), 1, "no totals")
    eq(count({ equipped = true, who = "player" }), 1, "no phys total")
    eq(count(on(0 / 0, 1494)), 1, "a NaN total")
    eq(count(on(math.huge, 1494)), 1, "an infinite total")
    eq(count(on("1645", 1494)), 1, "not a number")
    eq(count({ phys = 1645, magic = 1494, who = "player" }), 1, "the equipped check unknown")
    eq(count({ phys = 1645, magic = 1494, equipped = "yes", who = "player" }), 1, "the equipped check not a boolean")
    eq(count(on(1645, 1494), false), 1, "no base: no bonus")
    eq(count(on(1645, 1494), { who = "player", magic_defence = 373.8 }), 1, "the base lacks that stat")
    eq(count(on(1645, 1494), { phys_defence = 380 }), 1, "whose unknown")
    eq(count(on(159, 1494)), 1, "nothing left before it: no percent")
    eq(count(on(1645, 1494)), 3, "all there: the total line and the damage line")
    -- a ring whose field is missing has no line, so no total line
    eq(Model.panel(Data.ring(3509), ring_raw(), nil, on(1645, 1494)), nil, "3509 without its field")
    -- the lines without a total get none
    eq(texts(Model.panel(Data.augment("Job05_00"), { v1 = 200, v2 = 0 }, nil, on(1645, 1494))),
        "plain:+200 к макс. здоровью", "Жизненная сила")
    eq(#Model.panel(Data.augment("Job08_00"), { v1 = 30, v2 = 0 }, nil, on(1645, 1494)).lines, 1,
        "the pawns' defence augment")
    -- Кольцо сохранности: its two lines, no total under either (the bonus holds only without pawns)
    eq(texts(Model.panel(Data.ring(10221), ring_raw({ special = 47, v1 = 20 }), nil, on(1645, 1494))),
        "plain:без пешек: +20% от базовой защиты (число в скобках на экране статуса)"
        .. " | plain:без пешек: +20% от базовой маг. защиты (число в скобках на экране статуса)", "Кольцо сохранности")
    I18n.set("ru")
end)

test("the total line keeps the mark of the line it follows; the damage line is always ≈", function()
    I18n.set("ru")
    local e = { lines = { { mark = "approx", ru = "{1} к физ. защите", en = "{1} defense",
                            nums = { { src = "fields.PhysicalDefence", as = "signed" } }, total = "phys",
                            total_add = "fields.PhysicalDefence" } } }
    local p = Model.panel(e, ring_raw({ fields = { PhysicalDefence = 50 } }), nil, off(1000, 900))
    eq(texts(p), "approx:≈ +50 к физ. защите | approx:≈ защита 1000 → 1050 (+5%) | approx:≈ -5% физ. урона по тебе",
        "≈ on all three")
    eq(p.legend, true, "legend")
    e.lines[1].mark = "guess"
    eq(texts(Model.panel(e, ring_raw({ fields = { PhysicalDefence = 50 } }), nil, off(1000, 900))),
        "guess:? +50 к физ. защите | guess:? защита 1000 → 1050 (+5%) | approx:≈ -5% физ. урона по тебе", "a guess")
    I18n.set("ru")
end)

test("missing numbers drop lines", function()
    I18n.set("ru")
    eq(Model.panel(Data.augment("Job05_00"), nil), nil, "no raw")
    eq(Model.panel(Data.ring(3509), ring_raw()), nil, "a defence ring with no fields")
    eq(aug("Job05_00", 0, 0), nil, "all 0")
    eq(Model.panel(nil, { v1 = 1 }), nil, "no entry")
    eq(Model.panel(Data.augment("Job05_00"), {}), nil, "an empty raw")
    eq(Model.panel(Data.augment("Job05_00"), { v1 = 0 / 0, v2 = 0 }), nil, "NaN is no number")
    -- one line per effect: Кольцо победы with its stamina at 0 keeps the other two
    local triumph = Model.panel(Data.ring(3507), ring_raw({ special = 4, v1 = 100, v2 = 0, v3 = 5 }))
    eq(texts(triumph), "plain:+100 к макс. здоровью | plain:+5 кг к пределу веса", "3507 without stamina")
    -- Стаз without its second number keeps the first
    eq(#aug("Job06_01", 75, 0).lines, 1, "Стаз, v2 0")
    -- Ограбление without a vocation: the factor's line goes, the base chance stays
    local plunder = Model.panel(Data.ring(10231), ring_raw({ special = 57, pickpocket = { base = 1.5 } }))
    eq(#plunder.lines, 1, "no factor: " .. texts(plunder))
    -- a bane ring whose table could not be read
    eq(Model.panel(Data.ring(10201), ring_raw()), nil, "no efficacy")
    -- a line whose shown number is missing while another is there is not written half
    local half = { lines = { { mark = "plain", ru = "{1} и {2}", en = "{1} and {2}",
                               nums = { { src = "v1", as = "num" }, { src = "v2", as = "num" } } } } }
    eq(Model.panel(half, { v1 = 5 }), nil, "v2 missing")
    eq(Model.panel(half, { v1 = 5, v2 = 0 }).lines[1].text, "5 и 0", "a 0 next to a number is written")
end)

test("conversions", function()
    I18n.set("ru")
    local function conv(as, value)
        local e = { lines = { { mark = "plain", ru = "{1}", en = "{1}", nums = { { src = "v1", as = as } } } } }
        local p = Model.panel(e, { v1 = value })
        return p and p.lines[1].text
    end
    eq(conv("mult", 0.85), "-15%", "mult 0.85")
    eq(conv("mult", 1.1), "+10%", "mult 1.1")
    eq(conv("mult", 0.66), "-34%", "mult 0.66")
    eq(conv("mult", 0.8), "-20%", "mult 0.8")
    eq(conv("mult", 2), "+100%", "mult 2")
    eq(conv("add", 0.05), "+5%", "add 0.05")
    eq(conv("add", 0.1), "+10%", "add 0.1")
    eq(conv("add", 1), "+100%", "add 1")
    eq(conv("share", 0.3), "30%", "share 0.3: a share, no sign")
    eq(conv("share", 0.05), "5%", "share 0.05")
    eq(conv("share", 1), "100%", "share 1")
    eq(conv("share", 0.125), "12,5%", "share with decimals")
    eq(conv("num", 200), "200", "num")
    eq(conv("num", 1234.4), "1 234", "num groups and rounds")
    eq(conv("signed", 200), "+200", "signed")
    eq(conv("signed", -5), "-5", "signed minus")
    eq(conv("signed", 0.3), "+0,3", "signed keeps decimals")
    eq(conv("dec", 1.5), "1,5", "dec")
    eq(conv("pct", 30), "30%", "pct: a percent number")
    eq(conv("pct", 1.5), "1,5%", "pct with decimals")
    eq(conv("signed_pct", 30), "+30%", "signed_pct")
    eq(conv("signed_pct", -20), "-20%", "signed_pct minus")
    I18n.set("en")
    eq(conv("pct", 1.5), "1.5%", "en decimal mark")
    eq(conv("signed", 0.3), "+0.3", "en signed")
    local list = { lines = { { mark = "plain", ru = "{1}", en = "{1}", nums = { { src = "kinds", as = "list" } } } } }
    eq(Model.panel(list, { kinds = { "A", "B", "C" } }).lines[1].text, "A, B, C", "list")
    eq(Model.panel(list, { kinds = {} }), nil, "an empty list is a 0")
    I18n.set("ru")
    eq(I18n.dec(1.5), "1,5", "dec ru")
    eq(I18n.dec(62.7), "62,7", "62.7")
    eq(I18n.dec(3), "3", "a whole number")
    eq(I18n.dec(nil), "", "nil")
    I18n.set("en")
    eq(I18n.dec(1.5), "1.5", "dec en")
    I18n.set("ru")
end)

test("optional parts of a line", function()
    I18n.set("ru")
    local e = { lines = { { mark = "plain", ru = "{1}[ и {2}]", en = "{1}[ and {2}]",
                            nums = { { src = "v1", as = "num" }, { src = "v2", as = "num" } } } } }
    eq(Model.panel(e, { v1 = 1, v2 = 2 }).lines[1].text, "1 и 2", "kept")
    eq(Model.panel(e, { v1 = 1, v2 = 0 }).lines[1].text, "1", "a 0 drops the part")
    eq(Model.panel(e, { v1 = 1 }).lines[1].text, "1", "a missing number drops the part")
    eq(Model.panel(e, { v2 = 2 }), nil, "the line's own number missing")
end)

test("the language: the current one, else English", function()
    local e = { lines = { { mark = "plain", en = "{1} only English", nums = { { src = "v1", as = "num" } } } } }
    I18n.set("ru")
    eq(Model.panel(e, { v1 = 3 }).lines[1].text, "3 only English", "no ru text: en")
    I18n.set("de")
    eq(aug("Job05_00", 200).lines[1].text, "+200 max health", "an unknown language is English")
    I18n.set("ru")
end)

test("the found-table rings with the numbers read on 2026-11-06", function()
    I18n.set("ru")
    local exo = Model.panel(Data.ring(10201), ring_raw({ efficacy = { rate = 60, kinds = { "Лич", "Вурдалак", "Смерть" },
                                                                       unnamed = 5 } }))
    -- the bane rings are plain: both other mods read the same percent
    eq(exo.lines[1].text, "+60% к атаке против: Лич, Вурдалак, Смерть и ещё 5", "Экзорцизм")
    eq(exo.legend, false, "no legend")
    local dragons = Model.panel(Data.ring(10202), ring_raw({ efficacy = { rate = 50, unnamed = 3, kinds = {
        "Низший дракон", "Каратель", "Разоритель Священного сада", "Разоритель Агамена", "Губитель Вермунда",
        "Губитель островного лагеря" } } }))
    eq(dragons.lines[1].text, "+50% к атаке против: Низший дракон, Каратель, Разоритель Священного сада, "
        .. "Разоритель Агамена, Губитель Вермунда, Губитель островного лагеря и ещё 3", "Драконья погибель")
    local demons = Model.panel(Data.ring(10227), ring_raw({ special = 53,
        efficacy = { rate = 20, kinds = { "Барбатос" }, unnamed = 1 } }))
    eq(demons.lines[1].text, "+20% к атаке против: Барбатос и ещё 1", "Погибель демонов")
    local named = Model.panel(Data.ring(10227), ring_raw({ efficacy = { rate = 20, kinds = { "Барбатос" }, unnamed = 0 } }))
    eq(named.lines[1].text, "+20% к атаке против: Барбатос", "no unnamed kinds: no «и ещё 0»")
    I18n.set("en")
    eq(Model.panel(Data.ring(10227), ring_raw({ efficacy = { rate = 20, kinds = { "Barbatos" }, unnamed = 1 } }))
        .lines[1].text, "+20% attack against: Barbatos and 1 more", "en")
    I18n.set("ru")
    local audacity = Model.panel(Data.ring(10214), ring_raw({ special = 40,
        always = { per_sec = 120, cool = 1.0, cool_dodge = 0.3 } }))
    eq(#audacity.lines, 2, "Храбрость: " .. texts(audacity))
    eq(audacity.lines[1].text:find("120", 1, true) ~= nil, true, "120 per second")
    eq(audacity.lines[2].text:find("0,3", 1, true) ~= nil, true, "0,3 after a perfect dodge")
    local virtue = Model.panel(Data.ring(10223), ring_raw({ special = 49, drop = { rate_up = 8, count_up = 0, defeat = 0 } }))
    eq(#virtue.lines, 1, "Бескорыстие: only the chance: " .. texts(virtue))
    eq(virtue.lines[1].text:find("+8%", 1, true) ~= nil, true, "+8%")
    local wicked = Model.panel(Data.ring(10235), ring_raw({ special = 49, drop = { rate_up = 12, count_up = 1, defeat = 3 } }))
    eq(#wicked.lines, 3, "10235: chance, count, defeats: " .. texts(wicked))
    local blood = Model.panel(Data.ring(10239), ring_raw({ special = 49, drop = { rate_up = 100, count_up = 5, defeat = 100 } }))
    eq(blood.lines[1].text:find("+100%", 1, true) ~= nil, true, "10239: +100%")
    local thief = Model.panel(Data.ring(10231), ring_raw({ special = 57, pickpocket = { base = 1.5, factor = 0.4 } }))
    eq(#thief.lines, 2, "Ограбление: " .. texts(thief))
    eq(thief.lines[1].text:find("1,5%", 1, true) ~= nil, true, "1,5%")
    eq(thief.lines[2].text:find("×0,4", 1, true) ~= nil, true, "×0,4 for the Thief")
    local warfarer = Model.panel(Data.ring(10231), ring_raw({ special = 57, pickpocket = { base = 1.5, factor = 1.0 } }))
    eq(warfarer.lines[2].text:find("×1", 1, true) ~= nil, true, "×1 for the Warfarer")
    local rejuv = Model.panel(Data.ring(10232), ring_raw({ special = 58, rejuv = { factor = 2000, cap = 150 } }))
    eq(rejuv.lines[1].mark, "guess", "Омоложение is a guess")
    eq(rejuv.lines[1].text:find("2 000", 1, true) ~= nil and rejuv.lines[1].text:find("150", 1, true) ~= nil, true,
        "2 000 and 150: " .. rejuv.lines[1].text)
    local brawn = Model.panel(Data.ring(3538), ring_raw({ special = 15, curve = { top = 20 } }))
    eq(brawn.lines[1].text:find("20", 1, true) ~= nil, true, "Атлетичность: 20")
    local prox = Model.panel(Data.ring(3548), ring_raw({ special = 23, curve = { top = 30 } }))
    eq(prox.lines[1].text:find("30", 1, true) ~= nil, true, "Близость: 30")
end)

-- The curves' steps as evaluate gave them on 2026-11-07: x the carried weight (the party screen's number) for
-- Brawn, the distance to the target for Proximity, with no unit claimed (no source names one).
local BRAWN = { top = 20, steps = { { y = 20, to = 10 }, { y = 10, to = 20 } } }
local PROXIMITY = { top = 30, steps = { { y = 30, to = 5 }, { y = 20, to = 10 }, { y = 10, to = 15 } } }

test("Кольцо атлетичности and Кольцо близости (types 15, 23): each step of the curve, plain", function()
    I18n.set("ru")
    -- a base given: still no personal number (each step holds only at its own load)
    local base = { who = "player", strength = 420 }
    local brawn = Model.panel(Data.ring(3538), ring_raw({ special = 15, curve = BRAWN }), base)
    eq(texts(brawn), "plain:+20% от базовой силы при поклаже до 10, +10% — до 20", "Атлетичность")
    eq(brawn.legend, false, "plain")
    local prox = Model.panel(Data.ring(3548), ring_raw({ special = 23, curve = PROXIMITY }))
    eq(texts(prox), "plain:+30% к силе выстрела из лука на расстоянии до 5 от цели, +20% — до 10, +10% — до 15",
        "Близость, in the game's words for what it raises")
    eq(prox.legend, false, "plain")
    -- one step, four steps, an edge between whole numbers
    eq(texts(Model.panel(Data.ring(3538), ring_raw({ curve = { top = 20, steps = { { y = 20, to = 7.5 } } } }))),
        "plain:+20% от базовой силы при поклаже до 7,5", "one step")
    local four = { top = 40, steps = { { y = 40, to = 5 }, { y = 30, to = 10 }, { y = 20, to = 15 },
                                       { y = 10, to = 20 } } }
    eq(texts(Model.panel(Data.ring(3548), ring_raw({ curve = four }))),
        "plain:+40% к силе выстрела из лука на расстоянии до 5 от цели, +30% — до 10, +20% — до 15, +10% — до 20",
        "four steps")
    -- places for four steps: as many as game/hidden_stats.lua gives (a curve with more has none)
    for _, id in ipairs({ 3538, 3548 }) do
        eq(#Data.ring(id).lines[1].nums, 8, id .. ": four steps, a value and an edge each")
        eq(Data.ring(id).lines[2].fallback, true, id .. ": the top line falls back")
    end
    I18n.set("en")
    eq(texts(Model.panel(Data.ring(3538), ring_raw({ special = 15, curve = BRAWN }), base)),
        "plain:+20% of the base strength with a load of up to 10, +10% up to 20", "en Brawn")
    eq(texts(Model.panel(Data.ring(3548), ring_raw({ special = 23, curve = PROXIMITY }))),
        "plain:+30% bow attack strength within 5 of the target, +20% within 10, +10% within 15", "en Proximity")
    I18n.set("ru")
end)

test("the curve rings fall back to the curve's top when its steps cannot be read", function()
    I18n.set("ru")
    local function ring(id, curve) return texts(Model.panel(Data.ring(id), ring_raw({ curve = curve }))) end
    eq(ring(3538, { top = 20 }), "plain:до +20% от базовой силы при лёгкой поклаже", "Атлетичность, the top only")
    eq(ring(3548, { top = 30 }), "plain:до +30% к силе выстрела из лука вблизи цели", "Близость, the top only")
    -- steps there: only the steps line, never both
    eq(#Model.panel(Data.ring(3538), ring_raw({ curve = BRAWN })).lines, 1, "the steps, not the top too")
    -- an empty list of steps is no steps
    eq(ring(3538, { top = 20, steps = {} }), "plain:до +20% от базовой силы при лёгкой поклаже", "empty steps")
    eq(ring(3538, nil), "nil", "no curve: no panel")
    I18n.set("en")
    eq(ring(3538, { top = 20 }), "plain:up to +20% of the base strength with a light load", "en Brawn's top")
    eq(ring(3548, { top = 30 }), "plain:up to +30% bow attack strength close to the target", "en Proximity's top")
    I18n.set("ru")
end)

test("a fallback line is written only when no line before it was; or_none gives the none line", function()
    I18n.set("ru")
    local e = { lines = {
        { mark = "plain", ru = "А {1}", en = "A {1}", nums = { { src = "v1", as = "num" } } },
        { mark = "approx", ru = "Б {1}", en = "B {1}", nums = { { src = "v2", as = "num" } }, fallback = true },
    } }
    eq(texts(Model.panel(e, { v1 = 1, v2 = 2 })), "plain:А 1", "the first line written: no fallback")
    eq(texts(Model.panel(e, { v2 = 2 })), "approx:≈ Б 2", "the first dropped: the fallback")
    eq(Model.panel(e, { v2 = 2 }).legend, true, "the fallback's mark brings the legend")
    eq(texts(Model.panel(e, {})), "nil", "neither: no panel")
    e.or_none = true
    eq(texts(Model.panel(e, {})), "none:числа в игре не нашлось", "or_none: the none line")
    eq(Model.panel(e, {}).legend, false, "no legend with it")
    eq(texts(Model.panel(e, nil)), "none:числа в игре не нашлось", "no raw at all")
    eq(texts(Model.panel(e, { v1 = 1 })), "plain:А 1", "a line written: no none line")
end)

test("Везение (Job10_03): the chance of gold with its sums and the chance of meat; none when unread", function()
    I18n.set("ru")
    local fortuity = Data.augment("Job10_03")
    local raw = { additional = { cash = 50, meat = 20, cash_min = 100, cash_max = 10000 } }
    local p = Model.panel(fortuity, raw)
    eq(texts(p), "plain:50% шанс получить дополнительное золото из сундуков и тому подобного: от 100 до 10 000"
        .. " | plain:20% шанс получить мясо с определённых чудовищ и животных", "ru")
    eq(p.legend, false, "plain")
    -- the game's numbers, whatever they are
    eq(texts(Model.panel(fortuity, { additional = { cash = 35, meat = 12.5, cash_min = 50, cash_max = 2500 } })),
        "plain:35% шанс получить дополнительное золото из сундуков и тому подобного: от 50 до 2 500"
        .. " | plain:12,5% шанс получить мясо с определённых чудовищ и животных", "other numbers")
    -- unread: the none line, as before
    eq(texts(Model.panel(fortuity, nil)), "none:числа в игре не нашлось", "not read")
    eq(texts(Model.panel(fortuity, {})), "none:числа в игре не нашлось", "an empty raw")
    I18n.set("en")
    eq(texts(Model.panel(fortuity, raw)), "plain:50% chance of extra gold from chests and the like: 100 to 10 000"
        .. " | plain:20% chance of meat from certain monsters and animals", "en")
    eq(texts(Model.panel(fortuity, nil)), "none:no number found in the game", "en not read")
    I18n.set("ru")
end)

-- Where Clear Effect Descriptions and Better Better Item Description agree with each other against us, their
-- reading; the numbers are the game's as read on 2026-11-06.
local PLAYER_BASE = { who = "player", phys_defence = 380, magic_defence = 373.8, strength = 420, magic = 372.2 }

test("Кольцо превосходства (type 18): at full health, +v1 % of the base strength; v2 not shown", function()
    I18n.set("ru")
    local predominance = Data.ring(3541)
    local raw = ring_raw({ special = 18, v1 = 100, v2 = 10 })
    local p = Model.panel(predominance, raw, PLAYER_BASE)
    eq(texts(p), "plain:при полном здоровье: +100% от базовой силы (у тебя 420) — сейчас +420", "the player")
    eq(p.legend, false, "plain")
    -- v2 is not read: another v2 gives the same text
    eq(texts(Model.panel(predominance, ring_raw({ special = 18, v1 = 100, v2 = 0 }), PLAYER_BASE)), texts(p),
        "v2 not shown")
    eq(texts(Model.panel(predominance, raw, { who = "pawn", strength = 380 })),
        "plain:при полном здоровье: +100% от базовой силы (у пешки 380) — сейчас +380", "a pawn")
    eq(texts(Model.panel(predominance, raw, nil)),
        "plain:при полном здоровье: +100% от базовой силы (число в скобках на экране статуса)", "no base")
    eq(predominance.lines[1].base, "strength", "its base")
    eq(predominance.lines[1].base_pct, "v1", "v1 is the percent")
    eq(predominance.lines[1].base_add, nil, "no flat part")
    I18n.set("en")
    eq(Model.panel(predominance, raw, PLAYER_BASE).lines[1].text,
        "at full health: +100% of your base strength (420) — +420 now", "en")
    eq(Model.panel(predominance, raw, { who = "pawn", strength = 380 }).lines[1].text,
        "at full health: +100% of the pawn's base strength (380) — +380 now", "en pawn")
    eq(Model.panel(predominance, raw, nil).lines[1].text,
        "at full health: +100% of the base strength (the number in brackets on the status screen)", "en no base")
    I18n.set("ru")
end)

test("no-pawn and bare-handed rings (44, 45, 47, 50, 51): the condition first, then % of the base", function()
    I18n.set("ru")
    local function ring(id, special, v1, base)
        return texts(Model.panel(Data.ring(id), ring_raw({ special = special, v1 = v1 }), base))
    end
    eq(ring(10218, 44, 20, PLAYER_BASE), "plain:без пешек: +20% от базовой силы (у тебя 420) — сейчас +84",
        "Кольцо нападения: 20 % × 420")
    eq(ring(10219, 45, 20, PLAYER_BASE), "plain:без пешек: +20% от базовой магии (у тебя 372) — сейчас +74",
        "Кольцо колдовства: 20 % × 372,2")
    eq(ring(10221, 47, 20, PLAYER_BASE), "plain:без пешек: +20% от базовой защиты (у тебя 380) — сейчас +76"
        .. " | plain:без пешек: +20% от базовой маг. защиты (у тебя 373) — сейчас +75",
        "Кольцо сохранности: one line per defence")
    eq(ring(10224, 50, 50, PLAYER_BASE), "plain:голыми руками: +50% от базовой силы (у тебя 420) — сейчас +210",
        "Кольцо раздора: 50 % × 420")
    -- knockdown power has no base the mod reads: the percent alone
    eq(ring(10225, 51, 100, PLAYER_BASE), "plain:голыми руками: +100% к силе сбивания", "Кольцо опрокидывания")
    eq(Data.ring(10225).lines[1].base, nil, "no base for knockdown power")
    -- a pawn on the screen means a party with pawns: the rings without pawns give it nothing, so no personal number
    -- and no hint; the bare-handed ring keeps the pawn's own
    local PAWN_BASE = { who = "pawn", phys_defence = 375, magic_defence = 370, strength = 380, magic = 300 }
    eq(ring(10218, 44, 20, PAWN_BASE), "plain:без пешек: +20% от базовой силы", "a pawn's: 44")
    eq(ring(10219, 45, 20, PAWN_BASE), "plain:без пешек: +20% от базовой магии", "a pawn's: 45")
    eq(ring(10221, 47, 20, PAWN_BASE),
        "plain:без пешек: +20% от базовой защиты | plain:без пешек: +20% от базовой маг. защиты", "a pawn's: 47")
    eq(ring(10224, 50, 50, PAWN_BASE), "plain:голыми руками: +50% от базовой силы (у пешки 380) — сейчас +190",
        "a pawn's: 50 keeps it")
    for _, id in ipairs({ 10218, 10219, 10221 }) do
        for i, l in ipairs(Data.ring(id).lines) do eq(l.no_pawn, true, id .. " line " .. i .. " no_pawn") end
    end
    eq(Data.ring(10224).lines[1].no_pawn, nil, "50 without the flag")
    eq(Data.ring(3541).lines[1].no_pawn, nil, "18 without the flag")
    -- whose unknown: the hint, as for any line with a base
    eq(ring(10218, 44, 20, { strength = 380 }),
        "plain:без пешек: +20% от базовой силы (число в скобках на экране статуса)", "whose unknown: 44")
    eq(ring(10224, 50, 50, nil), "plain:голыми руками: +50% от базовой силы (число в скобках на экране статуса)",
        "no base")
    I18n.set("en")
    eq(ring(10218, 44, 20, PLAYER_BASE), "plain:without pawns: +20% of your base strength (420) — +84 now", "en 44")
    eq(ring(10219, 45, 20, PLAYER_BASE), "plain:without pawns: +20% of your base magick (372) — +74 now", "en 45")
    eq(ring(10221, 47, 20, PLAYER_BASE), "plain:without pawns: +20% of your base defense (380) — +76 now"
        .. " | plain:without pawns: +20% of your base magick defense (373) — +75 now", "en 47")
    eq(ring(10224, 50, 50, PLAYER_BASE), "plain:bare-handed: +50% of your base strength (420) — +210 now", "en 50")
    eq(ring(10225, 51, 100, PLAYER_BASE), "plain:bare-handed: +100% knockdown power", "en 51")
    eq(ring(10218, 44, 20, PAWN_BASE), "plain:without pawns: +20% of the base strength", "en 44, a pawn's")
    eq(ring(10221, 47, 20, PAWN_BASE), "plain:without pawns: +20% of the base defense"
        .. " | plain:without pawns: +20% of the base magick defense", "en 47, a pawn's")
    I18n.set("ru")
end)

test("Кольцо отмены (type 35): health lost each second in battle, enemy hits heal", function()
    I18n.set("ru")
    local p = Model.panel(Data.ring(10209), ring_raw({ special = 35, v1 = 120 }))
    eq(texts(p), "plain:в бою -120 здоровья в секунду, а удары врагов лечат", "ru")
    eq(p.legend, false, "plain")
    I18n.set("en")
    eq(texts(Model.panel(Data.ring(10209), ring_raw({ special = 35, v1 = 120 }))),
        "plain:-120 health per second in battle; enemy hits heal you", "en")
    I18n.set("ru")
end)

test("Кольцо бессилия (type 41): v1 % of the stamina spent on the skill comes back", function()
    I18n.set("ru")
    local p = Model.panel(Data.ring(10215), ring_raw({ special = 41, v1 = 20 }))
    eq(texts(p), "plain:возвращает 20% выносливости, потраченной на навык, если его первый удар попал", "ru")
    eq(p.legend, false, "plain")
    I18n.set("en")
    eq(texts(Model.panel(Data.ring(10215), ring_raw({ special = 41, v1 = 20 }))),
        "plain:20% of the stamina spent on a weapon skill comes back when its first hit lands", "en")
    I18n.set("ru")
end)

test("Кольцо метательности (type 31): thrown objects and explosives plain, creatures ≈", function()
    I18n.set("ru")
    local raw = ring_raw({ special = 31, v1 = 50, v2 = 100, v3 = 50 })
    local p = Model.panel(Data.ring(10203), raw)
    eq(texts(p), "plain:+50% урона брошенными предметами | plain:+100% урона брошенной взрывчаткой"
        .. " | approx:≈ +50% урона брошенными существами", "ru")
    eq(p.legend, true, "the ≈ line brings the legend")
    -- each number its own line: one at 0 leaves the others
    eq(texts(Model.panel(Data.ring(10203), ring_raw({ special = 31, v1 = 50, v2 = 100, v3 = 0 }))),
        "plain:+50% урона брошенными предметами | plain:+100% урона брошенной взрывчаткой", "v3 0")
    I18n.set("en")
    eq(texts(Model.panel(Data.ring(10203), raw)), "plain:+50% damage with thrown objects"
        .. " | plain:+100% damage with thrown explosives | approx:≈ +50% damage with thrown creatures", "en")
    I18n.set("ru")
end)

-- Checked in the game on 2026-11-07: ≈ +12 % faster in both phases of the refill, so v1 adds to a multiplier (not
-- CED's flat 10 per second, the reading once taken from it)
test("Кольцо проворства (type 21): +v1 % to the stamina recovery speed, plain", function()
    I18n.set("ru")
    local p = Model.panel(Data.ring(3544), ring_raw({ special = 21, v1 = 10 }))
    eq(texts(p), "plain:+10% к скорости восстановления выносливости", "ru: as Возвышение and Безмятежность say it")
    eq(p.legend, false, "plain")
    I18n.set("en")
    eq(texts(Model.panel(Data.ring(3544), ring_raw({ special = 21, v1 = 10 }))),
        "plain:+10% stamina recovery speed", "en")
    I18n.set("ru")
end)

test("Кольцо благодати (type 16): BBID's Lua reading, ?", function()
    I18n.set("ru")
    eq(texts(Model.panel(Data.ring(3539), ring_raw({ special = 16, v1 = 25, v2 = 3 }))),
        "guess:? после удара больше 25% макс. здоровья — лечение 3 с", "ru")
    I18n.set("en")
    eq(texts(Model.panel(Data.ring(3539), ring_raw({ special = 16, v1 = 25, v2 = 3 }))),
        "guess:? after a hit of more than 25% of max health, heals for 3 s", "en")
    I18n.set("ru")
end)

test("Яркость: the light ×2 in neutral words, plain", function()
    I18n.set("ru")
    local p = aug("Job02_02", 0.66, 2)
    eq(texts(p), "plain:-34% к расходу масла | plain:свет ×2", "ru")
    eq(p.legend, false, "plain")
    I18n.set("en")
    eq(texts(aug("Job02_02", 0.66, 2)), "plain:-34% lantern oil use | plain:light ×2", "en")
    I18n.set("ru")
end)

test("the ? lines both other mods read as we do are plain; Лунатик per second; the drop chance ≈", function()
    I18n.set("ru")
    local function ring(id, o) return Model.panel(Data.ring(id), ring_raw(o)) end
    -- 15 and 17: both mods say % of the base strength; 15 and 23 by their curve's top when no steps
    eq(texts(ring(3538, { special = 15, curve = { top = 20 } })), "plain:до +20% от базовой силы при лёгкой поклаже",
        "Атлетичность")
    eq(texts(ring(3540, { special = 17, v1 = 25, v2 = 100 })),
        "plain:при здоровье не выше 25%: +100% от базовой силы (число в скобках на экране статуса)", "Вознаграждение")
    eq(texts(ring(3548, { special = 23, curve = { top = 30 } })), "plain:до +30% к силе выстрела из лука вблизи цели",
        "Близость")
    eq(texts(ring(3551, { special = 26, v1 = 50, v2 = 20 })),
        "plain:+50 к защите пешки на 20 с после того, как ты её поднял", "Уверенность")
    eq(texts(ring(3555, { special = 30, v1 = 10 })), "plain:+10% к росту симпатии, пока кольцо надето", "Вечные узы")
    -- Лунатик: both mods say per second, so it says per second
    local night = ring(10210, { special = 36, v1 = 5, v2 = 10 })
    eq(texts(night), "plain:днём -5 здоровья в секунду, ночью +10 в секунду", "Лунатик")
    eq(night.legend, false, "plain")
    -- the drop rings' chance: BBID reads DropRateUp as a lottery weight, not a chance
    local virtue = ring(10223, { special = 49, drop = { rate_up = 8, count_up = 0, defeat = 0 } })
    eq(texts(virtue), "approx:≈ +8% к шансу редких материалов", "Бескорыстие")
    eq(texts(ring(10235, { special = 49, drop = { rate_up = 12, count_up = 1, defeat = 3 } })),
        "approx:≈ +12% к шансу редких материалов | plain:+1 к количеству редких материалов"
        .. " | approx:≈ побед над Сатанакией для этого уровня: 3", "нечестивая выгода")
    I18n.set("en")
    eq(texts(ring(10210, { special = 36, v1 = 5, v2 = 10 })),
        "plain:-5 health per second by day, +10 per second at night", "en Лунатик")
    I18n.set("ru")
end)

test("Кольцо вознаграждения, the condition first, then +v2 % of the base strength with its personal number",
    function()
    I18n.set("ru")
    local recompense, raw = Data.ring(3540), ring_raw({ special = 17, v1 = 25, v2 = 100 })
    local p = Model.panel(recompense, raw, PLAYER_BASE)
    eq(texts(p), "plain:при здоровье не выше 25%: +100% от базовой силы (у тебя 420) — сейчас +420", "the player")
    eq(p.legend, false, "plain")
    eq(texts(Model.panel(recompense, raw, { who = "pawn", strength = 380 })),
        "plain:при здоровье не выше 25%: +100% от базовой силы (у пешки 380) — сейчас +380", "a pawn")
    eq(texts(Model.panel(recompense, raw, nil)),
        "plain:при здоровье не выше 25%: +100% от базовой силы (число в скобках на экране статуса)", "no base")
    eq(recompense.lines[1].base, "strength", "its base")
    eq(recompense.lines[1].base_pct, "v2", "v2 is the percent")
    eq(recompense.lines[1].base_add, nil, "no flat part")
    -- v1 is the health threshold, not the bonus: another v1 changes only the threshold
    eq(texts(Model.panel(recompense, ring_raw({ special = 17, v1 = 30, v2 = 100 }), PLAYER_BASE)),
        "plain:при здоровье не выше 30%: +100% от базовой силы (у тебя 420) — сейчас +420", "v1 the threshold")
    -- Атлетичность: no personal number, steps or top (each holds only at its own load)
    local brawn = Model.panel(Data.ring(3538), ring_raw({ special = 15, curve = { top = 20 } }), PLAYER_BASE)
    eq(texts(brawn), "plain:до +20% от базовой силы при лёгкой поклаже", "Атлетичность, a base given")
    for i, l in ipairs(Data.ring(3538).lines) do eq(l.base, nil, "15 has no base line: " .. i) end
    I18n.set("en")
    eq(texts(Model.panel(recompense, raw, PLAYER_BASE)),
        "plain:at 25% health or less: +100% of your base strength (420) — +420 now", "en")
    eq(texts(Model.panel(recompense, raw, { who = "pawn", strength = 380 })),
        "plain:at 25% health or less: +100% of the pawn's base strength (380) — +380 now", "en pawn")
    eq(texts(Model.panel(recompense, raw, nil)),
        "plain:at 25% health or less: +100% of the base strength (the number in brackets on the status screen)",
        "en no base")
    eq(texts(Model.panel(Data.ring(3538), ring_raw({ special = 15, curve = { top = 20 } }))),
        "plain:up to +20% of the base strength with a light load", "en Атлетичность")
    I18n.set("ru")
end)

test("the ring's own numbers read on 2026-11-06", function()
    I18n.set("ru")
    eq(texts(Model.panel(Data.ring(3502), ring_raw({ special = 1, v1 = 200 }))), "plain:+200 к макс. здоровью",
        "Кольцо признания: a plain flat add")
    eq(texts(Model.panel(Data.ring(3507), ring_raw({ special = 4, v1 = 100, v2 = 100, v3 = 5 }))),
        "plain:+100 к макс. здоровью | plain:+100 к макс. выносливости | plain:+5 кг к пределу веса", "Кольцо победы")
    eq(texts(Model.panel(Data.ring(3509), ring_raw({ fields = { PhysicalDefence = 50 } }))), "plain:+50 к физ. защите",
        "Кольцо стойкости")
    local nine = {}
    for _, f in ipairs({ "FireResist", "IceResist", "PoisonResist", "SleepResist", "SilentResist", "StoneResist",
                         "WaterResist", "OilResist", "FaintResist" }) do nine[f] = 40 end
    eq(texts(Model.panel(Data.ring(10205), ring_raw({ fields = nine }))), "plain:+40% устойчивости ко всем 9 недугам",
        "Кольцо освобождения")
    local frost = Model.panel(Data.ring(10206), ring_raw({ fields = { IceResist = 100, ColdResist = 100 } }))
    eq(#frost.lines, 2, "Морозное кольцо: two fields")
end)

T.finish()
