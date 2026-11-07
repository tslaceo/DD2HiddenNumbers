package.path = "mod/reframework/autorun/?.lua;tests/?.lua;" .. package.path

local T = require("testlib")
local test, eq = T.test, T.eq
local R = require("stubs/reframework")
local i18n = require("DD2DamageMeter/i18n")
local Names = require("DD2DamageMeter/names")
local names_game = require("DD2DamageMeter/game/names_game")

local STATIC = { static = true }
local SKILL_SIG = "getCustomSkillName(app.Character.JobEnum, app.HumanCustomSkillID, app.HumanCustomSkillLevelNo)"

-- The names as the game gives them when it runs in Russian (via.Language 6).
local function world(opts)
    R.new(opts)
    names_game.reset()
    local W = { language = 6, skill_names = {}, levels = {}, messages = {}, items = {}, enemies = {}, names = {} }

    R.method("via.gui.GUISystem", "get_MessageLanguage", function() return W.language end, STATIC)
    R.method("app.GUIBase", "getName(app.Character)", function(c) return W.names[c] end, STATIC)
    R.method("app.GUIBase", "getName(app.CharacterID)", function(id) return W.enemies[id] end, STATIC)
    R.method("app.GUIBase", "getItemName(System.Int32)", function(id) return W.items[id] end, STATIC)
    R.method("app.GUIBase", SKILL_SIG, function(job, id, level)
        return W.skill_names[job .. "/" .. id .. "/" .. level] or ""
    end, STATIC)
    R.enum("app.CharacterID", { ch220000_00 = 1500, ch220003_00 = 2774043831, ch254000_00 = 3550884773 })
    W.enemies[2774043831] = "Живодёр"
    W.enemies[3550884773] = "Химера"
    R.enum("app.HumanCustomSkillID", {
        None = 0, Job03_Firestorm = 24, Job05_HorizontalSlash = 51, Job05_CrescentSlash = 52,
        Job05_IndomitableLash = 58, Job01_BravesRaid = 12,
    })
    W.skill_names["5/58/2"] = "Неукротимая злоба"
    W.skill_names["5/52/2"] = "Удар в небеса"
    W.skill_names["5/52/1"] = "Небесный удар"
    W.skill_names["3/24/2"] = "Великое пламя"

    -- via.gui.message: any language by message name
    R.method("via.gui.message", "getGuidByName(System.String)", function(name) return { guid = name } end, STATIC)
    R.method("via.gui.message", "getName(System.Guid)", function(guid) return guid.guid end, STATIC)
    R.method("via.gui.message", "get(System.Guid, via.Language)", function(guid, lang)
        return W.messages[guid.guid .. "/" .. lang]
    end, STATIC)
    W.items[38] = "Фруктовые пилюли"
    W.messages["item_name_38/1"] = "Fruit Roborant"
    W.messages["item_name_38/6"] = "Фруктовые пилюли"

    -- the game's skill table (GuiManager.CustomSkillDefineDictionary): id -> level -> the message of its name; the
    -- mage's Lv2 spells point at a <REF> message (as in the game)
    W.skill_table = {
        [58] = { [1] = "job05_skill_08", [2] = "job05_skill_08_lv2" },
        [52] = { [1] = "job05_skill_02", [2] = "job05_skill_02_lv2" },
        [55] = { [1] = "job05_skill_05", [2] = "job05_skill_05_lv2" },
        [51] = { [2] = "job05_skill_01_lv2" },
        [43] = { [1] = "job04_skill_05", [2] = "job04_skill_05_lv2" },
        [101] = { [1] = "job04_skill_12", [2] = "job04_skill_12" },
        [24] = { [1] = "job03_skill_00", [2] = "job06_skill_00_lv2" },
        [12] = { [1] = "job01_skill_05", [2] = "job01_skill_05" },
        [1] = { [1] = "job01_skill_00", [2] = "job01_skill_00_lv2" },
        [2] = { [1] = "job01_skill_02", [2] = "job01_skill_02_lv2" },
        [100] = { [1] = "job10_skill_00", [2] = "job10_skill_00" },
    }
    local function msg(name, ja, en, ru)
        W.messages[name .. "/0"], W.messages[name .. "/1"], W.messages[name .. "/6"] = ja, en, ru
    end
    msg("job05_skill_08", "魔人斬り", "Savage Lash", "Дикая злоба")
    msg("job05_skill_08_lv2", "魔人斬り２", "Indomitable Lash", "Неукротимая злоба")
    msg("job05_skill_02", "蒼天斬り", "Skyward Sunder", "Небесное разрушение")
    msg("job05_skill_02_lv2", "蒼天斬り２", "Heavenward Sunder", "Удар в небеса")
    msg("job05_skill_01_lv2", "地平斬り２", "Razing Sweep", "Разрушительный выпад")
    msg("job03_skill_00", "ファイアストーム", "Flagration", "Пламя")
    msg("job06_skill_00_lv2", "<REF job03_skill_00_lv2>", "<REF job03_skill_00_lv2>", "<REF job03_skill_00_lv2>")
    msg("job03_skill_00_lv2", "ファイアストーム２", "High Flagration", "Великое пламя")
    msg("job01_skill_05", "フュリオスレイド", "Riotous Fury", "Ярость бунтарей")
    msg("ui080101_40", "毒", "Debilitation: Blighted", "Недуг: отравление")
    local function dictionary(get)
        return R.object("System.Collections.Generic.Dictionary`2", {}, {
            ContainsKey = function(_, k) return get(k) ~= nil end,
            get_Item = function(_, k)
                local v = get(k)
                if v == nil then error("KeyNotFoundException") end
                return v
            end,
        })
    end
    local skill_table = dictionary(function(id)
        local levels = W.skill_table[id]
        return levels and dictionary(function(level)
            local name = levels[level]
            return name and R.object("app.CustomSkillInformationParam",
                { _SkillID = id, _Level = level, _SkillName = { guid = name } }, {})
        end)
    end)
    W.table = skill_table
    W.gui = R.object("app.GuiManager", { CustomSkillDefineDictionary = skill_table }, {})
    R.singleton("app.GuiManager", W.gui)

    -- the party, whose SkillContext knows the skill levels
    local function member(levels)
        local ctx = R.object("app.HumanSkillContext", {}, {
            ["getCustomSkillLevel(app.HumanCustomSkillID)"] = function(_, id) return levels[id] or 0 end,
        })
        local human = R.object("app.Human", { ["<SkillContext>k__BackingField"] = ctx }, {})
        local c = R.character{ go = "ch000000_00" }
        c.methods.get_Human = function() return human end
        return c
    end
    W.player = member({ [58] = 2, [52] = 1 })
    W.pawns = { member({ [24] = 2 }) }
    R.singleton("app.CharacterManager", R.object("app.CharacterManager", {}, {
        get_ManualPlayer = function() return W.player end,
    }))
    R.singleton("app.PawnManager", R.object("app.PawnManager", {}, {
        get_PawnCharacterList = function() return R.list(W.pawns) end,
    }))
    W.member = member
    return W
end

local function last_call(sig)
    local calls = R.calls_of(sig)
    return calls[#calls]
end

test("language: Russian 6, English 1, anything else unknown", function()
    local W = world()
    eq(names_game.language(), "ru", "6")
    W.language = 1
    eq(names_game.language(), "en", "1")
    for _, other in ipairs({ 0, 2, 7, 27, 33 }) do
        W.language = other
        eq(names_game.language(), nil, "language " .. other)
    end
    W.language = nil
    eq(names_game.language(), nil, "no value")
end)

test("language survives a failing or missing call", function()
    world()
    R.method("via.gui.GUISystem", "get_MessageLanguage", function() error("boom") end, STATIC)
    eq(names_game.language(), nil, "raises")
    R.undeclare("via.gui.GUISystem")
    eq(names_game.language(), nil, "type missing")
end)

test("character_name: the HUD name, then _Name, then the game object", function()
    local W = world()
    local pawn = R.character{ go = "ch111007" }
    W.names[pawn] = "Godwin"
    eq(names_game.character_name(pawn), "Godwin", "GUIBase.getName")
    eq(last_call("getName(app.Character)").args[1], pawn, "asked about this character")

    -- getName gives nothing: the creator's name from PawnDataContext
    W.names[pawn] = nil
    local pdc = R.object("app.PawnDataContext", { _Name = "Torinald", _Nickname = "Godwin" }, {})
    pawn.methods.get_Human = function()
        return R.object("app.Human", {}, { get_PawnDataContext = function() return pdc end })
    end
    eq(names_game.character_name(pawn), "Torinald", "_Name")

    -- an empty answer counts as no answer
    W.names[pawn] = ""
    eq(names_game.character_name(pawn), "Torinald", "empty string")

    -- no pawn data (an enemy): the game object name
    local goblin = R.character{ go = "ch220003_00_15" }
    eq(names_game.character_name(goblin), "ch220003_00_15", "game object")

    -- nothing at all
    local ghost = R.character{}
    eq(names_game.character_name(ghost), nil, "nothing known")
    eq(names_game.character_name(nil), nil, "nil character")
end)

test("character_name tells a display name from a fallback", function()
    local W = world()
    local c = R.character{ go = "ch220003_00_15" }
    local name, real = names_game.character_name(c)
    eq(name, "ch220003_00_15", "fallback text")
    eq(real, false, "not a display name")
    W.names[c] = "Живодёр"
    name, real = names_game.character_name(c)
    eq(name, "Живодёр", "display name")
    eq(real, true, "from the game")
end)

test("enemy: base_id to CharacterID to GUIBase.getName", function()
    world()
    local lookup = names_game.lookup()
    eq(lookup.enemy("ch220003_00", "ru"), "Живодёр", "ru")
    eq(last_call("getName(app.CharacterID)").args[1], 2774043831, "the CharacterID value")
    eq(lookup.enemy("ch254000_00", "ru"), "Химера", "second kind")
    -- a name without the _00 part still finds its enum entry
    eq(lookup.enemy("ch254000", "ru"), "Химера", "base id without _00")
    eq(lookup.enemy("ch999999_00", "ru"), nil, "unknown kind")
    eq(lookup.enemy("other", "ru"), nil, "not a character")
    eq(lookup.enemy(nil, "ru"), nil, "no id")
end)

test("enemy: the game only speaks its own language", function()
    world()
    -- English UI over a Russian game: the game's name is still better than the raw id
    eq(names_game.lookup().enemy("ch254000_00", "en"), "Химера", "game-language fallback")
end)

test("enemy: a name learned from a live character needs no game call", function()
    world()
    names_game.remember_enemy("ch777777_00", "Тролль")
    local before = #R.calls
    eq(names_game.lookup().enemy("ch777777_00", "ru"), "Тролль", "remembered")
    eq(#R.calls, before, "no game call")
    names_game.remember_enemy("ch777777_00", "")
    eq(names_game.lookup().enemy("ch777777_00", "ru"), "Тролль", "an empty name does not replace it")
end)

test("enemy: a found name is kept", function()
    local W = world()
    local lookup = names_game.lookup()
    eq(lookup.enemy("ch220003_00", "ru"), "Живодёр", "first lookup")
    local calls = #R.calls
    W.enemies[2774043831] = "changed"
    eq(lookup.enemy("ch220003_00", "ru"), "Живодёр", "second lookup")
    eq(#R.calls, calls, "no second game call")
end)

test("item: game language through GUIBase, other languages through the message text", function()
    world()
    local lookup = names_game.lookup()
    eq(lookup.item(38, "ru"), "Фруктовые пилюли", "game language")
    eq(last_call("getItemName(System.Int32)").args[1], 38, "item id")
    eq(lookup.item(38, "en"), "Fruit Roborant", "english message")
    local get = last_call("get(System.Guid, via.Language)")
    eq(get.args[1].guid, "item_name_38", "message name")
    eq(get.args[2], 1, "via.Language English")
end)

test("item: a game language the meter has no UI for still gets the UI's language", function()
    local W = world()
    W.language = 0
    eq(names_game.lookup().item(38, "en"), "Fruit Roborant", "English UI over a Japanese game")
    eq(last_call("get(System.Guid, via.Language)").args[2], 1, "via.Language English")
end)

test("item: nil when the game has no such item or a call fails", function()
    local W = world()
    local lookup = names_game.lookup()
    eq(lookup.item(99999, "ru"), nil, "unknown id")
    eq(lookup.item(nil, "ru"), nil, "no id")
    -- the message path fails: the game's own name is better than nothing
    W.messages = {}
    eq(lookup.item(38, "en"), "Фруктовые пилюли", "fallback to the game language")
    R.method("app.GUIBase", "getItemName(System.Int32)", function() error("boom") end, STATIC)
    eq(lookup.item(38, "ru"), nil, "raises")
end)

test("message in the asked language", function()
    world()
    local lookup = names_game.lookup()
    eq(lookup.message("ui080101_40", "ru"), "Недуг: отравление", "Russian")
    local get = last_call("get(System.Guid, via.Language)")
    eq(get.args[1].guid, "ui080101_40", "message name")
    eq(get.args[2], 6, "via.Language Russian")
    eq(lookup.message("ui080101_40", "en"), "Debilitation: Blighted", "English")
    eq(last_call("get(System.Guid, via.Language)").args[2], 1, "via.Language English")
    eq(names_game.message("ui080101_40", "ru"), "Недуг: отравление", "the module's own function")
    -- no language: the game's own, whatever it is
    eq(lookup.message("ui080101_40"), "Недуг: отравление", "the game runs in Russian")
    eq(lookup.message("ui080101_40", "de"), "Недуг: отравление", "a language the meter has no UI for: the game's")
end)

test("message with the game in a language the meter has no UI for", function()
    local W = world()
    W.language = 0
    local lookup = names_game.lookup()
    eq(lookup.message("ui080101_40"), "毒", "the game's language, Japanese")
    eq(last_call("get(System.Guid, via.Language)").args[2], 0, "via.Language Japanese")
    eq(lookup.message("ui080101_40", "en"), "Debilitation: Blighted", "the UI's language over a Japanese game")
    W.language = nil
    eq(lookup.message("ui080101_40"), nil, "no language to ask: nothing")
end)

test("message missing, empty or <REF> is nil", function()
    local W = world()
    local lookup = names_game.lookup()
    eq(lookup.message("ui080101_999", "ru"), nil, "no such message")
    W.messages["ui_empty/6"] = ""
    W.messages["ui_ref/6"] = "<REF ui080101_40>"
    W.messages["ui_number/6"] = 5
    eq(lookup.message("ui_empty", "ru"), nil, "empty text")
    eq(lookup.message("ui_ref", "ru"), nil, "the game's placeholder for a missing message")
    eq(lookup.message("ui_number", "ru"), nil, "not a text")
    eq(lookup.message(nil, "ru"), nil, "no name")
    eq(lookup.message("", "ru"), nil, "empty name")
    eq(lookup.message(5, "ru"), nil, "not a name")
    -- a message the game has in one language only
    W.messages["ui_only_en/1"] = "Only English"
    eq(lookup.message("ui_only_en", "en"), "Only English", "English")
    eq(lookup.message("ui_only_en", "ru"), nil, "no Russian")
end)

test("message is remembered, found or not, until reset", function()
    local W = world()
    local lookup = names_game.lookup()
    eq(lookup.message("ui080101_40", "ru"), "Недуг: отравление", "found")
    eq(lookup.message("ui080101_999", "ru"), nil, "not found")
    local before = #R.calls
    for _ = 1, 3 do
        eq(lookup.message("ui080101_40", "ru"), "Недуг: отравление", "found again")
        eq(lookup.message("ui080101_999", "ru"), nil, "not found again")
    end
    eq(#R.calls, before, "no game call for a known answer")
    -- each language is its own answer
    eq(lookup.message("ui080101_40", "en"), "Debilitation: Blighted", "another language is asked")
    -- the game's own language is asked as the game's: a change of the game's language shows
    eq(lookup.message("ui080101_40"), "Недуг: отравление", "the game's language, Russian")
    W.language = 1
    eq(lookup.message("ui080101_40"), "Debilitation: Blighted", "the game's language, now English")
    W.messages["ui080101_999/6"] = "Появилось"
    eq(lookup.message("ui080101_999", "ru"), nil, "still remembered as missing")
    names_game.reset()
    eq(lookup.message("ui080101_999", "ru"), "Появилось", "asked again after a reset")
end)

test("skill: id name to job, id value and the party's level", function()
    world()
    local lookup = names_game.lookup()
    eq(lookup.skill({ id = "Job05_IndomitableLash" }, "ru"), "Неукротимая злоба", "enum name")
    local call = last_call(SKILL_SIG)
    eq(call.args[1], 5, "job from the JobNN_ prefix")
    eq(call.args[2], 58, "enum value")
    eq(call.args[3], 2, "level from the player's SkillContext")
    eq(lookup.skill({ id = 58 }, "ru"), "Неукротимая злоба", "enum value")
    eq(lookup.skill({ id = "58" }, "ru"), "Неукротимая злоба", "value as text")
    eq(lookup.skill({ id = "Job03_Firestorm" }, "ru"), "Великое пламя", "a pawn's skill, other job")
    eq(last_call(SKILL_SIG).args[1], 3, "mage job")
end)

test("skill: a Lv1 skill is named at the level the party has", function()
    world()
    eq(names_game.lookup().skill({ id = "Job05_CrescentSlash" }, "ru"), "Небесный удар", "Lv1 text")
    eq(last_call(SKILL_SIG).args[3], 1, "level 1")
end)

test("skill: nobody knows the level, the upgraded name first then the base one", function()
    local W = world()
    local lookup = names_game.lookup()
    W.player, W.pawns = W.member({}), {}
    eq(lookup.skill({ id = "Job05_CrescentSlash" }, "ru"), "Удар в небеса", "Lv2")
    W.skill_names["5/52/2"] = nil
    names_game.reset()
    eq(lookup.skill({ id = "Job05_CrescentSlash" }, "ru"), "Небесный удар", "Lv1 when Lv2 is empty")
end)

test("skill: no text means nil", function()
    local W = world()
    local lookup = names_game.lookup()
    -- Lv0 text is "", a missing message is "<REF ...>"
    W.skill_names["5/51/2"] = "<REF job05_skill_01_lv2>"
    W.skill_names["5/51/1"] = ""
    eq(lookup.skill({ id = "Job05_HorizontalSlash" }, "ru"), nil, "<REF> is not a name")
    eq(lookup.skill({ id = "Job01_BravesRaid" }, "ru"), nil, "text empty at every level")
    eq(lookup.skill({ id = "None" }, "ru"), nil, "None has no job")
    eq(lookup.skill({ id = 0 }, "ru"), nil, "id 0")
    eq(lookup.skill({ id = "Bogus" }, "ru"), nil, "not an enum name")
    eq(lookup.skill({ id = 12345 }, "ru"), nil, "not an enum value")
    eq(lookup.skill({ attack = "CS_09_地平斬り" }, "ru"), nil, "attack name only")
    eq(lookup.skill({}, "ru"), nil, "empty ref")
    eq(lookup.skill(nil, "ru"), nil, "no ref")
end)

test("skill: the other job's text is empty, so the id's own job is used", function()
    world()
    -- the game answers "" for a wrong job (a pitfall seen in game); 51 must be asked with job 5, never the player's job
    local seen = {}
    R.method("app.GUIBase", SKILL_SIG, function(job, id, level)
        seen[#seen + 1] = job
        return job == 5 and id == 51 and "Разрушительный выпад" or ""
    end, STATIC)
    eq(names_game.lookup().skill({ id = "Job05_HorizontalSlash" }, "ru"), "Разрушительный выпад", "text")
    eq(seen[1], 5, "first ask uses job 5")
end)

test("skill in another language: the game's skill table and the message of its name", function()
    world()
    local lookup = names_game.lookup()
    eq(lookup.skill({ id = "Job05_IndomitableLash" }, "en"), "Indomitable Lash", "the party's level 2")
    eq(lookup.skill({ id = 52 }, "en"), "Skyward Sunder", "the player has 52 at level 1")
    eq(lookup.skill({ id = "Job05_IndomitableLash" }, "ru"), "Неукротимая злоба", "the game's language")
    eq(last_call(SKILL_SIG).args[2], 58, "the game's language asks getCustomSkillName")
end)

test("skill in another language: a <REF> message is followed to the one it names", function()
    world()
    eq(names_game.lookup().skill({ id = "Job03_Firestorm" }, "en"), "High Flagration", "the pawn's level 2 spell")
    local get = last_call("getGuidByName(System.String)")
    eq(get.args[1], "job03_skill_00_lv2", "the message named by <REF>")
end)

test("skill in another language: the game-language name when the table has nothing", function()
    local W = world()
    local lookup = names_game.lookup()
    W.skill_table[58] = nil
    eq(lookup.skill({ id = "Job05_IndomitableLash" }, "en"), "Неукротимая злоба", "not in the table")
    eq(lookup.skill({ id = "Job05_IndomitableLash" }, "en"), "Неукротимая злоба", "the same again")
    names_game.reset()
    W.gui.fields.CustomSkillDefineDictionary = nil
    eq(lookup.skill({ id = "Job05_CrescentSlash" }, "en"), "Небесный удар", "no table at all")
    names_game.reset()
    R.singleton("app.GuiManager", nil)
    eq(lookup.skill({ id = "Job05_CrescentSlash" }, "en"), "Небесный удар", "no GuiManager")
end)

test("skill in another language: a game language the meter has no UI for still gets the UI's language", function()
    local W = world()
    local lookup = names_game.lookup()
    W.language = 0
    eq(lookup.skill({ id = "Job05_CrescentSlash" }, "en"), "Skyward Sunder", "English UI over a Japanese game")
    eq(lookup.skill({ id = "Job05_CrescentSlash" }, "ru"), "Небесное разрушение", "Russian UI over a Japanese game")
    W.language = nil
    names_game.reset()
    eq(lookup.skill({ id = "Job05_CrescentSlash" }, "en"), "Skyward Sunder", "the game cannot say its language")
end)

test("skill in another language is kept like the game-language one", function()
    world()
    local lookup = names_game.lookup()
    eq(lookup.skill({ id = "Job05_IndomitableLash" }, "en"), "Indomitable Lash", "first")
    eq(lookup.skill({ id = "Job05_IndomitableLash" }, "ru"), "Неукротимая злоба", "the other language")
    local before = #R.calls
    eq(lookup.skill({ id = "Job05_IndomitableLash" }, "en"), "Indomitable Lash", "again")
    eq(lookup.skill({ id = "Job05_IndomitableLash" }, "ru"), "Неукротимая злоба", "again, game language")
    eq(#R.calls - before, 0, "no game call")
end)

-- Every skill of two vocations, for the attack-name lookups.
local function vocations()
    R.enum("app.HumanCustomSkillID", {
        None = 0, Job03_Firestorm = 24, Job01_BlinkStrike = 1, Job01_RisingLunge = 2, Job01_BravesRaid = 12,
        Job10_00 = 100,
        Job04_CuttingWind = 38, Job04_Guillotine = 39, Job04_Attract = 40, Job04_ParryCounter = 41,
        Job04_AbsoluteAvoidance = 42, Job04_HollowOut = 43, Job04_FakeMaster = 101,
        Job05_HeavyRunningThrust = 50, Job05_HorizontalSlash = 51, Job05_CrescentSlash = 52, Job05_CycloneSlash = 53,
        Job05_GroundDrill = 54, Job05_CounterAttack = 55, Job05_WarCry = 56, Job05_LandSlide = 57,
        Job05_IndomitableLash = 58,
    })
    names_game.reset()
end

test("attack_skill: CS_NN is the job's NN-th skill when its message is jobJJ_skill_(NN-1)", function()
    world()
    vocations()
    local name, value, rule = names_game.attack_skill("CS_06_抉り抜き_1_押", 4)
    eq(name, "Job04_HollowOut", "thief, 6th, job04_skill_05")
    eq(value, 43, "its value")
    eq(rule, "cs", "found by its number")
    eq((names_game.attack_skill("CSLv2_09_魔人斬り_溜_1_極", 5)), "Job05_IndomitableLash", "CSLv, warrior 9th")
    eq((names_game.attack_skill("CSLv2_03_三日月斬り_溜_2_main_極", 5)), "Job05_CrescentSlash", "warrior 3rd")
    eq((names_game.attack_skill("CS_06_抉り抜き_1_押", 5)), "Job05_CounterAttack", "the job decides")
    eq((names_game.attack_skill("CS_01_x", 1)), "Job01_BlinkStrike", "fighter 1st, job01_skill_00")
    eq(names_game.attack_skill("CS_02_x", 1), nil, "fighter 2nd is RisingLunge, whose message is job01_skill_02")
    eq(names_game.attack_skill("CS_07_x", 4), nil, "a later skill's message (job04_skill_12) is not the 7th")
    eq(names_game.attack_skill("CS_05_x", 5), nil, "a skill without a message in the table")
    eq(names_game.attack_skill("CS_01_x", 10), nil, "no CS rule for the Warfarer")
    eq(names_game.attack_skill("CS_20_x", 4), nil, "past the job's skills")
    eq(names_game.attack_skill("CS_00_x", 4), nil, "no 0th")
    eq(names_game.attack_skill("CS_06_x", 9), nil, "a job without skills")
    eq(names_game.attack_skill("CS_06_x", nil), nil, "no job")
    eq(names_game.attack_skill(nil, 4), nil, "no attack")
end)

-- The Warrior's skills in value order as the game has them: twelve whose level-1 message is
-- job05_skill_<NN-1>, then the newer Job05_DashSlashUp (110) and Job05_ScarletVow (111), whose messages end in _TU;
-- and the Warfarer's one skill.
local WARRIOR = { "Job05_HeavyRunningThrust", "Job05_HorizontalSlash", "Job05_CrescentSlash", "Job05_CycloneSlash",
    "Job05_GroundDrill", "Job05_CounterAttack", "Job05_WarCry", "Job05_LandSlide", "Job05_IndomitableLash",
    "Job05_Guts", "Job05_Springboard", "Job05_ArcOfObliteration" }
local function warrior(W)
    local enum = { None = 0, Job05_DashSlashUp = 110, Job05_ScarletVow = 111, Job10_00 = 100 }
    for i, name in ipairs(WARRIOR) do
        enum[name] = 49 + i
        W.skill_table[49 + i] = { [1] = string.format("job05_skill_%02d", i - 1) }
    end
    W.skill_table[110] = { [1] = "job05_skill_04_TU", [2] = "job05_skill_04_TU_00" }
    W.skill_table[111] = { [1] = "job05_skill_05_TU", [2] = "job05_skill_05_TU_00" }
    R.enum("app.HumanCustomSkillID", enum)
    names_game.reset()
end

test("attack_skill: CS_NN is a newer skill when the NN-th skill's message is jobJJ_skill_MM_TU (cs_tu)", function()
    local W = world()
    warrior(W)
    local name, value, rule = names_game.attack_skill("CS_14_緋染_N軽攻撃", 5)
    eq(name, "Job05_ScarletVow", "Blood Pact, the 14th, job05_skill_05_TU")
    eq(value, 111, "its value")
    eq(rule, "cs_tu", "found by its number, a newer skill")
    eq((names_game.attack_skill("CS_14_緋染_N軽攻撃_カス", 5)), "Job05_ScarletVow", "its graze")
    eq((names_game.attack_skill("CS_14_緋染の契り_BM発動", 5)), "Job05_ScarletVow", "its other attack")
    local dash, dash_value, dash_rule = names_game.attack_skill("CS_13_地流駆け_EX_1", 5)
    eq(dash, "Job05_DashSlashUp", "Iron Cleave, the 13th, job05_skill_04_TU")
    eq(dash_value, 110, "its value")
    eq(dash_rule, "cs_tu", "a newer skill too")
    eq((names_game.attack_skill("CSLv2_14_x", 5)), "Job05_ScarletVow", "the CSLv form")
    local old, _, old_rule = names_game.attack_skill("CS_09_魔人斬り", 5)
    eq(old, "Job05_IndomitableLash", "an older skill as before")
    eq(old_rule, "cs", "by the cs rule")
    eq((names_game.attack_skill("CS_12_x", 5)), "Job05_ArcOfObliteration", "the 12th, job05_skill_11")
    eq(names_game.attack_skill("CS_15_x", 5), nil, "past the job's skills")
end)

test("attack_skill: only the job's own _TU message makes a newer skill; the Warfarer has none", function()
    local W = world()
    warrior(W)
    W.skill_table[59] = { [1] = "job05_skill_11" }         -- the 10th with another number, no _TU
    W.skill_table[110] = { [1] = "job04_skill_04_TU" }     -- another job's
    W.skill_table[111] = { [1] = "job05_skill_05_TU_00" }  -- more after _TU
    names_game.reset()
    eq(names_game.attack_skill("CS_10_x", 5), nil, "a wrongly numbered message without _TU is still no skill")
    eq(names_game.attack_skill("CS_13_x", 5), nil, "another job's _TU message")
    eq(names_game.attack_skill("CS_14_x", 5), nil, "a message that only starts like a _TU one")
    W.skill_table[111] = { [2] = "job05_skill_05_TU_00" }
    names_game.reset()
    eq(names_game.attack_skill("CS_14_x", 5), nil, "no level-1 message")
    W.skill_table[100] = { [1] = "job10_skill_00_TU" }
    names_game.reset()
    eq(names_game.attack_skill("CS_01_x", 10), nil, "no CS rule for the Warfarer, _TU or not")
end)

test("attack_skill: another name by the skill's Japanese name in the game's table", function()
    world()
    vocations()
    local name, value, rule = names_game.attack_skill("魔人斬り", 5)
    eq(name, "Job05_IndomitableLash", "the level 1 name")
    eq(value, 58, "its value")
    eq(rule, "ja", "found by its Japanese name")
    eq((names_game.attack_skill("地平斬り_溜_1", 5)), "Job05_HorizontalSlash", "level 2 only: its ２ dropped")
    eq((names_game.attack_skill("ファイアストームLv.2_炎", 3)), "Job03_Firestorm", "Lv dropped from the core")
    eq((names_game.attack_skill("フュリオスレイド", 1)), "Job01_BravesRaid", "fighter")
    eq(names_game.attack_skill("ファイヤーストーム_Lv.2", 3), nil, "spelled unlike the game's text")
    eq(names_game.attack_skill("魔人斬り", 4), nil, "another job's skill")
    eq(names_game.attack_skill("N_軽", 5), nil, "a normal attack")
    eq(names_game.attack_skill("", 5), nil, "empty")
end)

-- The Sorcerer's skills (vocation 6) with the Japanese names the game gave them in 2026-10-28's fights.
local SORCERER = {
    { "Job06_AddFlare", 60, "ギャザリングフレア" }, { "Job06_Salamander", 61, "サラマンダーテイル" },
    { "Job06_ThunderWhip", 62, "サンダーウィップ" }, { "Job06_FrozenStorm", 63, "フローズンウォール" },
    { "Job06_Blizzard", 64, "ブリザードガイザー" }, { "Job06_MineVolt", 65, "マインボルト" },
    { "Job06_SaintDrain", 66, "ライフスティール" }, { "Job06_RockBeat", 67, "ロックビート" },
    { "Job06_MeteorFall", 68, "メテオフォール" }, { "Job06_VortexRage", 69, "ヴォルテクスレイジ" },
}

-- The Sorcerer's skills in the enum and the game's skill table, plus `extra` ones of the same shape.
local function sorcerer(W, extra)
    local enum, list = { None = 0, Job03_Firestorm = 24 }, {}
    for _, s in ipairs(SORCERER) do list[#list + 1] = s end
    for _, s in ipairs(extra or {}) do list[#list + 1] = s end
    for i, s in ipairs(list) do
        local message = string.format("job06_skill_%02d", i - 1)
        enum[s[1]] = s[2]
        W.skill_table[s[2]] = { [1] = message }
        W.messages[message .. "/0"] = s[3]
    end
    R.enum("app.HumanCustomSkillID", enum)
    names_game.reset()
end

test("attack_skill: an attack whose core starts a skill's Japanese name, or starts with one, is that skill", function()
    local W = world()
    sorcerer(W)
    local name, value, rule = names_game.attack_skill("メテオフォール着弾_対ノルド敵", 6)
    eq(name, "Job06_MeteorFall", "Meteor's impact starts with メテオフォール")
    eq(value, 68, "its value")
    eq(rule, "ja_prefix", "found by the start of its name")
    eq((names_game.attack_skill("メテオフォール着弾_対ノルド敵_カスアタリ", 6)), "Job06_MeteorFall", "Meteor's graze")
    eq((names_game.attack_skill("ロックビート発生_対ノルド敵", 6)), "Job06_RockBeat", "Rock Beat's start")
    local _, _, shell_rule = names_game.attack_skill("ブリザードLv.2_右奥", 6)
    eq((names_game.attack_skill("ブリザードLv.2_右奥", 6)), "Job06_Blizzard", "ブリザード starts ブリザードガイザー")
    eq(shell_rule, "ja_prefix", "by the start")
    eq((names_game.attack_skill("ブリザードLv.2_左手前", 6)), "Job06_Blizzard", "another Blizzard shell")
    eq((names_game.attack_skill("ロックビー_x", 6)), "Job06_RockBeat", "five characters are enough")
    -- the exact names as before
    local exact, _, exact_rule = names_game.attack_skill("メテオフォール", 6)
    eq(exact, "Job06_MeteorFall", "Meteor's cast")
    eq(exact_rule, "ja", "by its exact name")
    eq((names_game.attack_skill("ブリザードガイザー_x", 6)), "Job06_Blizzard", "Blizzard's exact name")
    eq((names_game.attack_skill("ヴォルテクスレイジ", 6)), "Job06_VortexRage", "Vortex's exact name")
end)

test("attack_skill: the Sorcerer's other attacks and a start of four characters match no skill", function()
    local W = world()
    sorcerer(W)
    for _, attack in ipairs({ "ラピッドショット", "バーストショット", "バーストショット_追撃", "サンダーレイン",
        "サンダーレイン_追撃", "ファイヤーストーム_Lv.2", "CatchLarge", "Catch", "投げられアタリ" }) do
        eq(names_game.attack_skill(attack, 6), nil, attack)
    end
    eq(names_game.attack_skill("ロックビ_x", 6), nil, "the core is ロックビート's first four characters")
    vocations()
    eq(names_game.attack_skill("魔人斬り溜め_1", 5), nil, "the core starts with 魔人斬り, four characters")
end)

test("attack_skill: a start that two skills of the vocation share names neither", function()
    local W = world()
    sorcerer(W, { { "Job06_Extra", 70, "ブリザードウォール" } })
    eq(names_game.attack_skill("ブリザードLv.2_右奥", 6), nil, "ブリザード starts two skills")
    eq((names_game.attack_skill("ブリザードガイザー", 6)), "Job06_Blizzard", "an exact name still")
    sorcerer(W, { { "Job06_Extra", 70, "ロックビート発生強化" } })
    eq(names_game.attack_skill("ロックビート発生_対ノルド敵", 6), nil, "starts with one skill and starts the other")
    eq((names_game.attack_skill("メテオフォール着弾", 6)), "Job06_MeteorFall", "another skill's start is still found")
end)

test("attack_skill: a match by the start is kept like the others", function()
    local W = world()
    sorcerer(W)
    eq((names_game.attack_skill("メテオフォール着弾_対ノルド敵", 6)), "Job06_MeteorFall", "first")
    eq(names_game.attack_skill("ラピッドショット", 6), nil, "a miss")
    local before = #R.calls
    eq((names_game.attack_skill("メテオフォール着弾_対ノルド敵", 6)), "Job06_MeteorFall", "again")
    eq(names_game.attack_skill("ラピッドショット", 6), nil, "the miss again")
    eq(#R.calls - before, 0, "no game call")
end)

test("attack_skill: a skill table that cannot be read yet is asked again later", function()
    local W = world()
    vocations()
    W.gui.fields.CustomSkillDefineDictionary = nil
    eq(names_game.attack_skill("魔人斬り", 5), nil, "no table yet")
    eq(names_game.attack_skill("CS_09_x", 5), nil, "no table yet, CS")
    W.gui.fields.CustomSkillDefineDictionary = W.table
    eq((names_game.attack_skill("魔人斬り", 5)), "Job05_IndomitableLash", "asked again without a reset")
    eq((names_game.attack_skill("CS_09_x", 5)), "Job05_IndomitableLash", "CS too")
    R.singleton("app.GuiManager", nil)
    eq(names_game.attack_skill("フュリオスレイド", 1), nil, "no GuiManager yet")
    R.singleton("app.GuiManager", W.gui)
    eq((names_game.attack_skill("フュリオスレイド", 1)), "Job01_BravesRaid", "GuiManager there now")
end)

test("attack_skill: read once until reset, and never raises", function()
    local W = world()
    vocations()
    eq((names_game.attack_skill("魔人斬り", 5)), "Job05_IndomitableLash", "first")
    eq((names_game.attack_skill("CS_06_x", 4)), "Job04_HollowOut", "CS, first")
    local before = #R.calls
    eq((names_game.attack_skill("魔人斬り", 5)), "Job05_IndomitableLash", "again")
    eq(names_game.attack_skill("N_軽", 5), nil, "a miss")
    eq(names_game.attack_skill("N_軽", 5), nil, "the miss again")
    eq((names_game.attack_skill("CS_06_x", 4)), "Job04_HollowOut", "CS again")
    eq((names_game.attack_skill("CS_09_x", 5)), "Job05_IndomitableLash", "CS of a job whose table was read")
    eq(#R.calls - before, 0, "no game call")
    W.skill_table[58] = nil
    names_game.reset()
    eq(names_game.attack_skill("魔人斬り", 5), nil, "asked again after reset")
    W.gui.fields.CustomSkillDefineDictionary = R.object("System.Collections.Generic.Dictionary`2", {}, {
        ContainsKey = function() error("boom") end,
    })
    names_game.reset()
    eq(names_game.attack_skill("魔人斬り", 5), nil, "a table that raises")
    eq(names_game.attack_skill("CS_09_x", 5), nil, "CS needs the table too")
    W.gui.fields.CustomSkillDefineDictionary = W.table
    R.undeclare("app.HumanCustomSkillID")
    names_game.reset()
    eq(names_game.attack_skill("CS_09_x", 5), nil, "no enum")
end)

test("names lookup returns nil instead of raising when a game call fails", function()
    local W = world()
    local function boom() error("boom") end
    R.method("via.gui.GUISystem", "get_MessageLanguage", boom, STATIC)
    R.method("app.GUIBase", "getName(app.Character)", boom, STATIC)
    R.method("app.GUIBase", "getName(app.CharacterID)", boom, STATIC)
    R.method("app.GUIBase", "getItemName(System.Int32)", boom, STATIC)
    R.method("app.GUIBase", SKILL_SIG, boom, STATIC)
    R.method("via.gui.message", "getGuidByName(System.String)", boom, STATIC)
    R.method("via.gui.message", "get(System.Guid, via.Language)", boom, STATIC)
    local lookup = names_game.lookup()
    eq(lookup.skill({ id = "Job05_IndomitableLash" }, "ru"), nil, "skill")
    eq(lookup.enemy("ch254000_00", "ru"), nil, "enemy")
    eq(lookup.item(38, "ru"), nil, "item")
    eq(lookup.item(38, "en"), nil, "item in another language")
    eq(lookup.message("ui080101_40", "ru"), nil, "message")
    eq(names_game.language(), nil, "language")
    eq(names_game.character_name(R.character{}), nil, "character name")

    -- the party cannot be read either
    R.singleton("app.CharacterManager", R.object("app.CharacterManager", {}, { get_ManualPlayer = boom }))
    eq(lookup.skill({ id = "Job05_IndomitableLash" }, "ru"), nil, "skill without a party")
    W.player = nil
end)

test("names lookup returns nil when the game types are missing", function()
    R.new()
    names_game.reset()
    local lookup = names_game.lookup()
    eq(lookup.skill({ id = "Job05_IndomitableLash" }, "ru"), nil, "skill")
    eq(lookup.enemy("ch254000_00", "ru"), nil, "enemy")
    eq(lookup.item(38, "ru"), nil, "item")
    eq(lookup.message("ui080101_40", "ru"), nil, "message")
    eq(names_game.language(), nil, "language")
    eq(names_game.character_name(R.character{ go = "x" }), "x", "the game object name needs no GUIBase")
    eq(names_game.character_name({}), nil, "not a managed object")
end)

test("failed lookups are remembered until reset", function()
    local W = world()
    local lookup = names_game.lookup()
    eq(lookup.enemy("ch999999_00", "ru"), nil, "unknown enemy")
    eq(lookup.item(99999, "ru"), nil, "unknown item")
    eq(lookup.skill({ id = "Job01_BravesRaid" }, "ru"), nil, "skill without text")
    eq(lookup.skill({ id = "Bogus" }, "ru"), nil, "not a skill id")
    local before = #R.calls
    for _ = 1, 3 do
        eq(lookup.enemy("ch999999_00", "ru"), nil, "enemy again")
        eq(lookup.item(99999, "ru"), nil, "item again")
        eq(lookup.skill({ id = "Job01_BravesRaid" }, "ru"), nil, "skill again")
        eq(lookup.skill({ id = "Bogus" }, "ru"), nil, "bogus again")
    end
    eq(#R.calls, before, "no game call for a known failure")
    -- a name seen later on a live character wins over the remembered failure
    names_game.remember_enemy("ch999999_00", "Тролль")
    eq(lookup.enemy("ch999999_00", "ru"), "Тролль", "learned")
    -- reset asks the game again
    W.items[99999] = "Новый предмет"
    W.skill_names["1/12/2"] = "Ярость бунтарей"
    eq(lookup.item(99999, "ru"), nil, "still remembered")
    names_game.reset()
    eq(lookup.item(99999, "ru"), "Новый предмет", "asked again after reset")
    eq(lookup.skill({ id = "Job01_BravesRaid" }, "ru"), "Ярость бунтарей", "skill asked again")
end)

test("enum_name: a member name by value", function()
    world()
    eq(names_game.enum_name("app.HumanCustomSkillID", 58), "Job05_IndomitableLash", "value to name")
    eq(names_game.enum_name("app.HumanCustomSkillID", 58.0), "Job05_IndomitableLash", "a float value")
    eq(names_game.enum_name("app.HumanCustomSkillID", 999), nil, "unknown value")
    eq(names_game.enum_name("app.Missing", 1), nil, "missing type")
    eq(names_game.enum_name("app.HumanCustomSkillID", nil), nil, "no value")
    R.enum("app.Missing", { One = 1 })
    eq(names_game.enum_name("app.Missing", 1), nil, "a type missing at first stays missing until reset")
    names_game.reset()
    eq(names_game.enum_name("app.Missing", 1), "One", "read after reset")
end)

test("enum_value: a member's value by name", function()
    world()
    eq(names_game.enum_value("app.HumanCustomSkillID", "Job05_IndomitableLash"), 58, "name to value")
    eq(names_game.enum_value("app.HumanCustomSkillID", "Job05_Bogus"), nil, "unknown name")
    eq(names_game.enum_value("app.Missing", "One"), nil, "missing type")
    eq(names_game.enum_value("app.HumanCustomSkillID", nil), nil, "no name")
end)

test("enum maps read the game's field container (sol userdata, not a plain table)", function()
    world({ containers = true })
    eq(type(sdk.find_type_definition("app.HumanCustomSkillID"):get_fields()), "userdata", "as in the game")
    eq(names_game.enum_name("app.HumanCustomSkillID", 58), "Job05_IndomitableLash", "value to name")
    local lookup = names_game.lookup()
    eq(lookup.skill({ id = "Job05_IndomitableLash" }, "ru"), "Неукротимая злоба", "skill by id name")
    eq(lookup.skill({ id = 52 }, "ru"), "Небесный удар", "skill by value")
    eq(lookup.enemy("ch220003_00", "ru"), "Живодёр", "enemy through the CharacterID enum")
end)

test("the lookup plugs into Names and falls back when the game has no text", function()
    world()
    i18n.set("ru")
    local names = Names.new(names_game.lookup())
    eq(names:skill({ id = "Job05_IndomitableLash" }), "Неукротимая злоба", "game text")
    eq(names:enemy("ch220003_00"), "Живодёр", "enemy text")
    eq(names:enemy("ch999999_00"), "Безымянный враг", "enemy fallback: «Unnamed enemy», never the id")
    eq(names:item(38), "Фруктовые пилюли", "item text")
    eq(names:skill({ id = "Bogus" }), i18n.t("skill") .. " (Bogus)", "skill fallback")
    i18n.set("en")
end)

T.finish()
