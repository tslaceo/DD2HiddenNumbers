package.path = "mod/reframework/autorun/?.lua;tests/?.lua;" .. package.path

local T = require("testlib")
local test, eq = T.test, T.eq
local i18n = require("DD2DamageMeter/i18n")
local Names = require("DD2DamageMeter/names")

local function atk(name) return { attack = name } end

-- Attack names seen in game that the damage meter must treat as normal attacks.
local NORMAL = {
    "N_軽", "N_軽_早繋ぎ", "N_軽_カス", "N_軽(2連撃用)", "NS_重", "N(空中)", "弱攻撃_ヒットスロー小",
    "強攻撃_溜め", "ダッシュ攻撃", "しがみ付き攻撃", "ジャンプ片手",
}

test("skill_key merges charge levels", function()
    local names = Names.new()
    local a = names:skill_key(atk("CSLv2_09_魔人斬り_溜_2_極"))
    local b = names:skill_key(atk("CSLv2_09_魔人斬り_溜_1_極"))
    eq(a, "魔人斬り", "core of the charged skill")
    eq(b, a, "charge 1 and charge 2 share a key")
    eq(names:skill_key(atk("CSLv2_03_三日月斬り_溜_2_main_極")), "三日月斬り", "perfect-timing main hit")
    eq(names:skill_key(atk("CS_09_地平斬り")), "地平斬り", "no level in the name")
    eq(names:skill_key(atk("CSLv10_12_魔人斬り")), "魔人斬り", "two-digit level")
end)

test("normal attacks group", function()
    local names = Names.new()
    for _, name in ipairs(NORMAL) do
        eq(names:is_normal(atk(name)), true, "is_normal " .. name)
        eq(names:skill_key(atk(name)), "normal", "key of " .. name)
    end
end)

test("skills and unnamed attacks are not normal", function()
    local names = Names.new()
    eq(names:is_normal(atk("CSLv2_09_魔人斬り_溜_2_極")), false, "charged skill")
    eq(names:is_normal(atk("円月斬りLv.2_追撃")), false, "pawn skill")
    eq(names:is_normal(atk("感電")), false, "shock")
    eq(names:is_normal({}), false, "no attack name")
    eq(names:is_normal(nil), false, "no ref")
end)

test("a CS skill stays a skill even with a normal-attack word in its name", function()
    i18n.set("en")
    local names = Names.new()
    local ref = atk("CSLv2_05_ジャンプ斬り_溜_1")
    eq(names:is_normal(ref), false, "is_normal")
    eq(names:skill_key(ref), "ジャンプ斬り", "key")
    eq(names:skill(ref, "en"), "Skill (ジャンプ斬り)", "name")
end)

test("is_normal, skill_key and skill agree on every attack name", function()
    i18n.set("en")
    local names = Names.new()
    local samples = {
        "CSLv2_05_ジャンプ斬り_溜_1", "CS_01_強攻撃_溜_2", "CSLv3_07_ダッシュ斬り_極", "CS_02_N_軽",
        "CSLv2_09_魔人斬り_溜_2_極", "円月斬りLv.2_追撃", "感電", "Foo_Bar",
    }
    for _, name in ipairs(NORMAL) do samples[#samples + 1] = name end
    for _, name in ipairs(samples) do
        local ref = atk(name)
        local normal = names:is_normal(ref)
        eq(names:skill_key(ref) == "normal", normal, "key vs is_normal for " .. name)
        eq(names:skill(ref, "en") == i18n.t("normal_attacks"), normal, "name vs is_normal for " .. name)
    end
end)

test("a game skill id beats the attack name", function()
    local names = Names.new()
    eq(names:skill_key({ id = 77, attack = "N_軽" }), "77", "id is the key")
    eq(names:is_normal({ id = 77, attack = "N_軽" }), false, "an id means a skill, not a normal attack")
    eq(names:skill_key({ id = "skill_12", attack = "CSLv2_09_魔人斬り" }), "skill_12", "string id")
end)

test("skill_key is always a string", function()
    local names = Names.new()
    eq(type(names:skill_key({ id = 77 })), "string", "numeric id")
    eq(math.type(names:skill_key({ id = 77 })), nil, "not a number")
    eq(names:skill_key({ id = 77 }), names:skill_key({ id = "77" }), "numeric and string id merge")
    eq(type(names:skill_key({ id = 0 })), "string", "id 0 is still an id")
    eq(names:skill_key({ id = 0 }), "0", "id 0")
    eq(type(names:skill_key(atk("N_軽"))), "string", "normal")
    eq(type(names:skill_key({})), "string", "unknown")
    -- the view merges rows by key and sorts them: mixed id and name keys must be comparable.
    local keys = { names:skill_key({ id = 77 }), names:skill_key(atk("魔人斬り")), names:skill_key({ id = 5 }) }
    table.sort(keys)
    eq(#keys, 3, "keys sort without a compare error")
end)

test("pawn skill names keep their core", function()
    local names = Names.new()
    local a = names:skill_key(atk("円月斬りLv.2_追撃"))
    local b = names:skill_key(atk("円月斬り"))
    eq(a, "円月斬り", "follow-up of a levelled skill")
    eq(a, b, "same key as the bare name")
    eq(names:skill_key(atk("円月斬りLv3")), "円月斬り", "level without a dot")
    eq(names:skill_key(atk("円月斬り_極")), "円月斬り", "perfect timing")
    eq(names:skill_key(atk("円月斬り_main2")), "円月斬り", "numbered main hit")
    eq(names:skill_key(atk("円月斬り_溜_3")), "円月斬り", "charge level")
    eq(names:skill_key(atk("円月斬り_L")), "円月斬り", "left hand")
    eq(names:skill_key(atk("円月斬り_R")), "円月斬り", "right hand")
    eq(names:skill_key(atk("感電")), "感電", "a plain name stays")
    -- a skill level after an underscore goes with the underscore
    eq(names:skill_key(atk("ファイヤーストーム_Lv.2")), "ファイヤーストーム", "_Lv.2")
    eq(names:skill_key(atk("ファイヤーストーム_Lv3")), "ファイヤーストーム", "_Lv3")
    eq(names:skill_key(atk("ファイヤーストーム_Lv.2_追撃")), "ファイヤーストーム", "_Lv.2 with a follow-up")
    eq(names:skill_key(atk("ファイヤーストーム")), names:skill_key(atk("ファイヤーストーム_Lv.2")), "same key as the bare name")
end)

test("the game's normal-attack flag beats the name patterns", function()
    i18n.set("en")
    local names = Names.new()
    for _, name in ipairs({ "ラピッドショット", "刀牙昇斬_上昇", "Foo_Bar" }) do
        local ref = { attack = name, normal = true }
        eq(names:is_normal(ref), true, "is_normal " .. name)
        eq(names:skill_key(ref), "normal", "key of " .. name)
        eq(names:skill(ref, "en"), i18n.t("normal_attacks"), "name of " .. name)
    end
    eq(names:skill_key({ normal = true }), "normal", "the flag without an attack name")
    eq(names:skill_key(atk("ラピッドショット")), "ラピッドショット", "without the flag the name decides")
    -- a CS name is a custom skill whatever the state said at the moment the blow landed
    local cs = { attack = "CSLv2_09_魔人斬り_溜_1", normal = true }
    eq(names:is_normal(cs), false, "a CS name stays a skill")
    eq(names:skill_key(cs), "魔人斬り", "with its core as the key")
end)

test("a DoT tick is named after its status", function()
    local names = Names.new()
    eq(names:skill_key({ status = "FireSpread" }), "dot:burn", "burning")
    eq(names:skill_key({ status = "Electric" }), names:skill_key({ status = "WetElectric" }), "both shocks merge")
    eq(names:skill_key({ status = "Poison" }), names:skill_key({ status = "VirulentPoison" }), "both poisons merge")
    eq(names:skill_key({ status = "Frostbite" }), names:skill_key({ status = "Freeze" }), "both frosts merge")
    eq(names:is_normal({ status = "Poison" }), false, "a tick is no normal attack")
    i18n.set("en")
    eq(names:skill({ status = "FireSpread" }, "en"), "Burning", "en burning")
    eq(names:skill({ status = "VirulentPoison" }, "en"), "Poison", "en poison")
    eq(names:skill({ status = "WetElectric" }, "en"), "Shock", "en shock")
    eq(names:skill({ status = "Freeze" }, "en"), "Frost", "en frost")
    eq(names:skill({ status = "Mystery" }, "en"), "Status damage (Mystery)", "a status with no family of its own")
    i18n.set("ru")
    eq(names:skill({ status = "FireSpread" }, "ru"), i18n.t("dot_burn"), "ru burning")
    eq(names:skill({ status = "Poison" }, "ru"), i18n.t("dot_poison"), "ru poison")
    i18n.set("en")
end)

test("skill_key without a usable name", function()
    local names = Names.new()
    eq(names:skill_key({}), "?", "empty ref")
    eq(names:skill_key(nil), "?", "nil ref")
    eq(names:skill_key(atk("")), "?", "empty name")
    eq(names:skill_key(atk("_極")), "_極", "a name that is only suffix keeps itself")
end)


test("no skill names ship with the mod: without the game's text a skill shows its key", function()
    i18n.set("ru")
    local names = Names.new()
    local label = i18n.t("skill")
    eq(names:skill(atk("CSLv2_03_三日月斬り_溜_2_main_極"), "ru"), label .. " (三日月斬り)", "三日月斬り")
    eq(names:skill(atk("地平斬り"), "ru"), label .. " (地平斬り)", "地平斬り")
    eq(names:skill(atk("CSLv2_09_魔人斬り_溜_1_極"), "ru"), label .. " (魔人斬り)", "魔人斬り")
    i18n.set("en")
    eq(names:skill(atk("CSLv2_09_魔人斬り_溜_1_極"), "en"), "Skill (魔人斬り)", "English")
    eq(require("DD2DamageMeter/lang/ru").known_skills, nil, "no table in lang/ru.lua")
    eq(require("DD2DamageMeter/lang/en").known_skills, nil, "no table in lang/en.lua")
end)

test("game lookup wins over the table", function()
    i18n.set("en")
    local got
    local names = Names.new({ skill = function(ref, lang)
        got = { ref = ref, lang = lang }
        return "From the game"
    end })
    local ref = atk("CSLv2_09_魔人斬り_溜_2_極")
    eq(names:skill(ref, "ru"), "From the game", "game name")
    eq(got.ref, ref, "lookup gets the ref")
    eq(got.lang, "ru", "lookup gets the language")
end)

test("a lookup that finds nothing falls through to the key", function()
    i18n.set("en")
    local names = Names.new({ skill = function() return nil end })
    eq(names:skill(atk("魔人斬り"), "en"), "Skill (魔人斬り)", "nil result")
    names = Names.new({ skill = function() return "" end })
    eq(names:skill(atk("魔人斬り"), "en"), "Skill (魔人斬り)", "empty result")
end)

test("the language defaults to the interface language", function()
    local seen
    local names = Names.new({ skill = function(_, lang) seen = lang end })
    i18n.set("ru")
    names:skill(atk("魔人斬り"))
    eq(seen, "ru", "lookup language")
    eq(names:skill(atk("魔人斬り")), i18n.t("skill") .. " (魔人斬り)", "fallback label in the interface language")
    i18n.set("en")
end)

test("unknown skill shows its key", function()
    local names = Names.new()
    i18n.set("en")
    eq(names:skill(atk("CSLv2_99_Foo_溜_2"), "en"), "Skill (Foo)", "grouped key")
    eq(names:skill(atk("Foo_Bar"), "en"), "Skill (Foo_Bar)", "plain name")
    eq(names:skill({ id = 123 }, "en"), "Skill (123)", "id")
    eq(names:skill({}, "en"), "Unknown skill", "nothing known")
    eq(names:skill(nil, "en"), "Unknown skill", "no ref at all")
    i18n.set("ru")
    eq(names:skill(atk("Foo_Bar"), "ru"), i18n.t("skill") .. " (Foo_Bar)", "label in the interface language")
    eq(names:skill({}, "ru"), "Неизвестный навык", "nothing known, Russian")
    i18n.set("en")
end)

test("normal attacks get one name", function()
    local names = Names.new()
    i18n.set("en")
    eq(names:skill(atk("N_軽"), "en"), i18n.t("normal_attacks"), "N_軽")
    eq(names:skill(atk("弱攻撃_ヒットスロー小"), "en"), i18n.t("normal_attacks"), "弱攻撃")
    i18n.set("ru")
    eq(names:skill(atk("ジャンプ片手"), "ru"), i18n.t("normal_attacks"), "ru")
    i18n.set("en")
end)

test("enemy name: game lookup, else «Unnamed enemy»; no lookup at all: the base id", function()
    local seen
    local names = Names.new({ enemy = function(base_id, lang)
        seen = { base_id, lang }
        if base_id == "ch254000_00" then return "Chimera" end
        if base_id == "ch272001_00" then return "" end
    end })
    i18n.set("en")
    eq(names:enemy("ch254000_00", "en"), "Chimera", "found")
    eq(seen[1], "ch254000_00", "lookup id"); eq(seen[2], "en", "lookup language")
    eq(names:enemy("ch272002_00", "en"), "Unnamed enemy", "the game gives nil")
    eq(names:enemy("ch272001_00", "en"), "Unnamed enemy", "the game gives an empty text")
    i18n.set("ru")
    eq(names:enemy("ch272002_00", "ru"), "Безымянный враг", "nil, Russian")
    eq(names:enemy("ch272001_00", "ru"), "Безымянный враг", "empty, Russian")
    eq(names:enemy("ch254000_00", "ru"), "Chimera", "found, Russian")
    i18n.set("en")
    eq(Names.new():enemy("ch220003_00", "en"), "ch220003_00", "no lookup at all")
end)

test("item name: game lookup, else item and number", function()
    i18n.set("en")
    local names = Names.new({ item = function(item_id, lang)
        if item_id == 38 then return "Potato pills (" .. lang .. ")" end
    end })
    eq(names:item(38, "en"), "Potato pills (en)", "found")
    eq(names:item(67, "en"), i18n.t("item") .. " #67", "not found")
    eq(Names.new():item(5, "en"), i18n.t("item") .. " #5", "no lookup at all")
end)

test("message goes to the lookup", function()
    local seen
    local names = Names.new({ message = function(name, lang)
        seen = { name, lang }
        if name == "ui080101_40" then return "Blighted (" .. lang .. ")" end
    end })
    eq(names:message("ui080101_40", "en"), "Blighted (en)", "found")
    eq(seen[1], "ui080101_40", "lookup name"); eq(seen[2], "en", "lookup language")
    eq(names:message("ui080101_999", "en"), nil, "not found: nil, the caller has its own fallback")
    i18n.set("ru")
    names:message("ui080101_40")
    eq(seen[2], "ru", "the interface language by default")
    i18n.set("en")
    eq(Names.new():message("ui080101_40", "en"), nil, "no lookup at all")
    eq(Names.new({ message = function() return "" end }):message("x", "en"), nil, "an empty text is nothing")
    eq(Names.new({ message = function() return 5 end }):message("x", "en"), nil, "so is a non-text")
end)

test("a lookup table with only some functions is fine", function()
    i18n.set("en")
    local names = Names.new({ enemy = function() return "Goblin" end })
    eq(names:enemy("ch220003_00", "en"), "Goblin", "enemy")
    eq(names:skill(atk("Foo"), "en"), "Skill (Foo)", "skill without a lookup")
    eq(names:item(3, "en"), "Item #3", "item without a lookup")
end)

T.finish()
