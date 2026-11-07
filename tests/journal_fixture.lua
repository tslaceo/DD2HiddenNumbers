-- The ogre fight of the journal tests, built through Fight: Guts (the player, an archer), Torinald (a pawn, a thief)
-- and Leo (an ally) against an ogre and two lizards, with the names lookup of its game texts.
--   Fixture.build() -> fight, snap   a fresh fight, finished at 255 ("win"), and its full snapshot
--   Fixture.snap                      the snapshot of a fight built at load, for tests that only read it
--   Fixture.build_chart() -> fight, snap   the chart's fight: Guts (6 100) and Torinald (9 900) on the ogre with seven
--                                     skills between them, normal attacks by both (finished at 100); Fixture.chart its
--                                     snapshot built at load
--   Fixture.ctx(lang) -> ctx          { names, i18n } with the language set (default "ru")
--   Fixture.hit(fight, t, attacker, victim, hp0, hp1, o)   one more hit (o: Hit fields such as skill, region, element)
--   Fixture.region(before, after, part) -> Hit.region
--   Fixture.GUTS, TORI, LEO, OGRE, LIZ1, LIZ2, NORMAL, OGRE_FOE
local i18n = require("DD2DamageMeter/i18n")
local Names = require("DD2DamageMeter/names")
local Fight = require("DD2DamageMeter/fight")

local F = {}

F.GUTS = { key = "a1", name = "Guts", kind = "player", base_id = "ch000000_00", max_hp = 2000, job = 2 }
F.TORI = { key = "a2", name = "Torinald", kind = "pawn", base_id = "ch100000_00", max_hp = 2400, order = 1, job = 4 }
F.LEO = { key = "a3", name = "Leo", kind = "ally", base_id = "ch300000_00", max_hp = 1800 }
F.OGRE = { key = "a10", name = "ch230000_00", kind = "enemy", base_id = "ch230000_00", chara_id = 2300, max_hp = 75000 }
F.LIZ1 = { key = "a11", name = "ch221002_00", kind = "enemy", base_id = "ch221002_00", chara_id = 2210, max_hp = 7600 }
F.LIZ2 = { key = "a12", name = "ch221002_00", kind = "enemy", base_id = "ch221002_00", chara_id = 2210, max_hp = 7600 }

F.NORMAL = { attack = "N_連斬_1", normal = true }
F.OGRE_FOE = { chara_id = 2300, weak = 130, resist = 32, defence = 250, magic_defence = 180, enabled = 8395888 }

local ENEMIES = { ch230000_00 = "Огр", ch221002_00 = "Ящер", ch221001_00 = "Волк" }
local SKILLS = { Job02_ThreefoldArrow = "Дождь стрел", Job03_Frigor = "Мороз", Job02_Explosive = "Взрывная стрела",
                 Job04_Cutthroat = "Перерезать горло", Job04_Pilfer = "Кража", Job04_Shadow = "Тень",
                 Job03_FullRecover = "Серебряный тоник" }
local ITEMS = { [38] = "Фруктовые пилюли" }
local MESSAGES = {
    ru = {
        ui080101_40 = "Недуг: отравление", ui080101_41 = "Недуг: быстродействующий яд", ui080101_42 = "Недуг: сон",
        ui080101_43 = "Недуг: обморок", ui080101_37 = "Недуг: обморожение", ui080101_38 = "Недуг: ледяные оковы",
        Status_1 = "Защита", Status_3 = "Маг. защита", job03_act_01 = "Исцеление",
    },
    en = {
        ui080101_40 = "Debilitation: Blighted", ui080101_41 = "Debilitation: Fulminant Poison",
        ui080101_42 = "Debilitation: Sleep", ui080101_43 = "Debilitation: Unconscious",
        ui080101_37 = "Debilitation: Frostbite", ui080101_38 = "Debilitation: Ice-Bound",
        Status_1 = "Defense", Status_3 = "Magick Defense", job03_act_01 = "Anodyne",
    },
}

local NAMES = Names.new({
    enemy = function(base_id) return ENEMIES[base_id] end,
    skill = function(ref) return ref and ref.id and SKILLS[ref.id] or nil end,
    item = function(id) return ITEMS[id] end,
    message = function(name, lang) return (MESSAGES[lang] or {})[name] end,
})

function F.ctx(lang)
    i18n.set(lang or "ru")
    return { names = NAMES, i18n = i18n }
end

function F.region(before, after, part)
    return { before = before, after = after, part = part }
end

function F.hit(f, t, attacker, victim, hp0, hp1, o)
    local h = { t = t, attacker = attacker, victim = victim, skill = {}, final = hp0 - hp1, hp0 = hp0, hp1 = hp1 }
    for k, v in pairs(o or {}) do h[k] = v end
    f:add_hit(h)
end

function F.build()
    local hit, region = F.hit, F.region
    local GUTS, TORI, LEO, OGRE, LIZ1, LIZ2 = F.GUTS, F.TORI, F.LEO, F.OGRE, F.LIZ1, F.LIZ2
    local f = Fight.new(0)
    hit(f, 0, TORI, OGRE, 75000, 74000,
        { skill = F.NORMAL, region = region({ Slash = 1000 }, { Slash = 1000 }, "body"), foe = F.OGRE_FOE })
    hit(f, 5, GUTS, OGRE, 74000, 73300, { skill = { id = "Job02_ThreefoldArrow" }, element = "Fire",
        region = region({ Shoot = 100, Enchant = 400 }, { Shoot = 100, Enchant = 600 }, "head") })
    hit(f, 6, LEO, OGRE, 73300, 72800,
        { skill = { attack = "N_斬り", normal = true }, region = region({ Slash = 500 }, { Slash = 500 }, "body") })
    for i = 0, 4 do
        hit(f, 10 + i, OGRE, GUTS, 2000 - 100 * i, 1900 - 100 * i, { types = { Blow = 100 } })
    end
    hit(f, 15, OGRE, GUTS, 1500, 1300, { element = "Fire", types = { Magic = 200 } })
    hit(f, 62, TORI, LIZ1, 7600, 0, { skill = F.NORMAL, region = region({ Slash = 7600 }, { Slash = 7600 }) })
    hit(f, 70, GUTS, LIZ2, 7600, 7200,
        { skill = { id = "Job03_Frigor" }, element = "Ice", region = region({ Magic = 1000 }, { Magic = 400 }) })
    f:add_heal({ t = 100, target = GUTS, amount = 230.9, effective = 230.9, source = { kind = "item", item_id = 38 } })
    f:add_heal({ t = 200, target = GUTS, amount = 15, effective = 15, source = { kind = "other" } })
    hit(f, 252, TORI, OGRE, 72800, 0,
        { skill = F.NORMAL, region = region({ Slash = 72800 }, { Slash = 72800 }, "body") })
    f:finish(255, "win")
    return f, f:snapshot(255, true)
end

-- By the party's sums: normal attacks 5 000 (Torinald 4 000, Guts 1 000), Перерезать горло 3 500, Дождь стрел 3 000,
-- Кража 2 000, Взрывная стрела 1 500 (the top five), then Мороз 600 and Тень 400 (the rest).
function F.build_chart()
    local f = Fight.new(0)
    local hp = F.OGRE.max_hp
    local function blow(t, who, skill, amount)
        F.hit(f, t, who, F.OGRE, hp, hp - amount, { skill = skill })
        hp = hp - amount
    end
    blow(1, F.TORI, F.NORMAL, 2500)
    blow(2, F.GUTS, { attack = "N_矢_1", normal = true }, 1000)
    blow(3, F.TORI, { id = "Job04_Cutthroat" }, 3500)
    blow(4, F.GUTS, { id = "Job02_ThreefoldArrow" }, 3000)
    blow(5, F.TORI, { id = "Job04_Pilfer" }, 2000)
    blow(6, F.GUTS, { id = "Job02_Explosive" }, 1500)
    blow(7, F.GUTS, { id = "Job03_Frigor" }, 600)
    blow(8, F.TORI, { id = "Job04_Shadow" }, 400)
    blow(9, F.TORI, F.NORMAL, 1500)
    f:finish(100, "win")
    return f, f:snapshot(100, true)
end

local _, snap = F.build()
F.snap = snap
local _, chart = F.build_chart()
F.chart = chart

return F
