-- Names and language from the game's own text (its messages, its language enum and its skill table), as the
-- `lookup` that Names.new takes. Every function gives nil instead of raising when a type or a call is missing. The
-- game answers in its own language; a UI language other than the game's (whatever the game's is) is asked where it
-- can (items by message name, skills through the message of the game's skill table), otherwise the game-language
-- text is returned, which is more useful than a raw id. A game message by its name (a status condition's page title,
-- the healing spot's name) is asked in the language wanted, else in the game's own.
local Safe = require("DD2DamageMeter/game/safe")

local NamesGame = {}

-- via.Language: Japanese 0, English 1, ... Russian 6.
local LANG_ID = { en = 1, ru = 6 }
local LANG_CODE = { [1] = "en", [6] = "ru" }
local JAPANESE = 0
local WARFARER = 10  -- uses other vocations' skills: its own list says nothing about a CS number

local SKILL_NAME = "getCustomSkillName(app.Character.JobEnum, app.HumanCustomSkillID, app.HumanCustomSkillLevelNo)"
-- HumanCustomSkillID -> HumanCustomSkillLevelNo -> CustomSkillInformationParam (its _SkillName is a message Guid)
local SKILL_TABLE = "CustomSkillDefineDictionary"
local MAX_ATTACKS = 512  -- remembered attack-name lookups
local MIN_PREFIX = 5     -- characters the shorter side of a match by the start needs (ブリザード)

local enum_maps = {}  -- enum type -> { by_name, by_value }, read once; false when it could not be read
local learned = {}    -- enemy base_id -> name, from live characters and earlier lookups
local memo = {}       -- "kind|key|lang" -> text found for skills and items
local failed = {}     -- "kind|key[|lang]" -> true: the game had nothing, do not ask again
local jobs = {}       -- job -> { values, names } in value order; by_ja and msg once the skill table was read
local attacks, n_attacks = {}, 0  -- "job|attack" -> { name, rule }, or false

-- Forgets what was read from the game, found or not (a new game session, tests).
function NamesGame.reset()
    enum_maps, learned, memo, failed, jobs = {}, {}, {}, {}, {}
    attacks, n_attacks = {}, 0
end

-- A usable text: not empty, not the game's "<REF job03_skill_00_lv2>" placeholder for a missing message.
local function text_of(value)
    if type(value) == "string" and value ~= "" and not value:find("^<REF") then return value end
    return nil
end

local function f_name(f) return f:get_name() end
local function f_static(f) return f:is_static() end
local function f_data(f) return f:get_data(nil) end
local function t_fields(td) return td:get_fields() end

-- Names and values of an enum's members, nil when the type cannot be read (remembered until reset).
local function enum_map(type_name)
    local map = enum_maps[type_name]
    if map ~= nil then return map or nil end
    local td = Safe.type(type_name)
    -- a sol container in the game, not a Lua table
    local fields = Safe.items(td and Safe.try(t_fields, td))
    local by_name, by_value, count = {}, {}, 0
    for _, f in ipairs(fields) do
        if Safe.try(f_static, f) == true then
            local name, value = Safe.try(f_name, f), Safe.try(f_data, f)
            if type(name) == "string" and type(value) == "number" then
                by_name[name], by_value[value] = value, name
                count = count + 1
            end
        end
    end
    if count == 0 then
        enum_maps[type_name] = false
        return nil
    end
    map = { by_name = by_name, by_value = by_value }
    enum_maps[type_name] = map
    return map
end

-- The member name of an enum value ("Job05_IndomitableLash" for app.HumanCustomSkillID 58), nil when unknown.
function NamesGame.enum_name(type_name, value)
    if type(value) ~= "number" or value ~= value then return nil end
    local map = enum_map(type_name)
    return map and map.by_value[value] or nil
end

-- The value of an enum member by name (app.HumanCustomSkillID "Job05_IndomitableLash" -> 58), nil when unknown.
function NamesGame.enum_value(type_name, name)
    if type(name) ~= "string" then return nil end
    local map = enum_map(type_name)
    return map and map.by_name[name] or nil
end

-- "en", "ru" or nil (any other language, or the game cannot say).
function NamesGame.language()
    return LANG_CODE[Safe.static("via.gui.GUISystem", "get_MessageLanguage")]
end

-- The name the party HUD shows: app.GUIBase.getName(character), else the pawn's own _Name, else the game object's
-- name. The second result tells a display name (true) from that last fallback (false).
function NamesGame.character_name(character)
    if character == nil then return nil end
    local name = text_of(Safe.static("app.GUIBase", "getName(app.Character)", character))
    if name then return name, true end
    local human = Safe.call(character, "get_Human")
    local pawn_data = Safe.call(human, "get_PawnDataContext")
    name = text_of(Safe.field(pawn_data, "_Name"))
    if name then return name, true end
    name = Safe.go_name(character)
    if name then return name, false end
    return nil
end

-- An enemy kind's name as seen on a live character; the lookup answers from it without asking the game.
function NamesGame.remember_enemy(base_id, name)
    if type(base_id) == "string" and base_id ~= "?" and text_of(name) then learned[base_id] = name end
end

local function enemy_name(base_id)
    if type(base_id) ~= "string" then return nil end
    if learned[base_id] then return learned[base_id] end
    local key = "enemy|" .. base_id
    if failed[key] then return nil end
    local map = enum_map("app.CharacterID")
    -- the game object name carries a spawn index, the CharacterID name ends in _00
    local value = map and (map.by_name[base_id] or map.by_name[base_id .. "_00"])
    local name = value ~= nil and text_of(Safe.static("app.GUIBase", "getName(app.CharacterID)", value)) or nil
    if name then learned[base_id] = name else failed[key] = true end
    return name
end

-- A message of the game in the language `lang_id` (via.gui.message).
local function message_text(message, lang_id)
    local guid = Safe.static("via.gui.message", "getGuidByName(System.String)", message)
    if guid == nil then return nil end
    return text_of(Safe.static("via.gui.message", "get(System.Guid, via.Language)", guid, lang_id))
end

-- The text of a message Guid in `lang_id`; a "<REF job03_skill_00_lv2>" text (the mage's Lv2 spells) is the message
-- it names.
local function guid_text(guid, lang_id)
    if guid == nil then return nil end
    local text = Safe.static("via.gui.message", "get(System.Guid, via.Language)", guid, lang_id)
    local ref = type(text) == "string" and text:match("^<REF ([%w_]+)>$")
    if ref then return message_text(ref, lang_id) end
    return text_of(text)
end

local function entry(dictionary, key)
    if Safe.call(dictionary, "ContainsKey", key) ~= true then return nil end
    return Safe.call(dictionary, "get_Item", key)
end

-- The game's skill table (app.GuiManager, filled for all skills), nil when it cannot be read.
local function skill_table()
    return Safe.field(Safe.singleton("app.GuiManager"), SKILL_TABLE)
end

-- The message Guid of a skill's name at a level in the game's skill table.
local function skill_guid(value, level, by_id)
    by_id = by_id or skill_table()
    return Safe.field(entry(entry(by_id, value), level), "_SkillName")
end

local function item_name(item_id, lang)
    if math.type(item_id) ~= "integer" then return nil end
    local key = "item|" .. item_id .. "|" .. tostring(lang)
    if memo[key] then return memo[key] end
    if failed[key] then return nil end
    if lang and LANG_ID[lang] and lang ~= NamesGame.language() then
        local text = message_text("item_name_" .. item_id, LANG_ID[lang])
        if text then
            memo[key] = text
            return text
        end
        text = text_of(Safe.static("app.GUIBase", "getItemName(System.Int32)", item_id))
        if not text then failed[key] = true end
        return text
    end
    local text = text_of(Safe.static("app.GUIBase", "getItemName(System.Int32)", item_id))
    if text then memo[key] = text else failed[key] = true end
    return text
end

-- Value and enum name of a HumanCustomSkillID given by name or by value.
local function skill_id(raw)
    local map = enum_map("app.HumanCustomSkillID")
    if not map then return nil end
    if type(raw) == "string" then
        if map.by_name[raw] then return map.by_name[raw], raw end
        raw = tonumber(raw)
    end
    if type(raw) == "number" and map.by_value[raw] then return raw, map.by_value[raw] end
    return nil
end

local function party_characters()
    local list = {}
    local player = Safe.call(Safe.singleton("app.CharacterManager"), "get_ManualPlayer")
    if player then list[1] = player end
    local pawns = Safe.call(Safe.singleton("app.PawnManager"), "get_PawnCharacterList")
    for _, pawn in ipairs(Safe.list(pawns, 8)) do
        if pawn then list[#list + 1] = pawn end
    end
    return list
end

-- The level any party member has learned the skill at (0 when nobody knows it).
local function known_level(value)
    local best = 0
    for _, character in ipairs(party_characters()) do
        local human = Safe.call(character, "get_Human")
        local skills = Safe.field(human, "<SkillContext>k__BackingField")
        local level = Safe.call(skills, "getCustomSkillLevel(app.HumanCustomSkillID)", value)
        if type(level) == "number" and level > best then best = level end
    end
    return best
end

-- GUIBase.getCustomSkillName(job, id, level) answers only for the skill's own job, so the job is the number
-- in the id's JobNN_ prefix; the level is the party's, else the upgraded name (2) and then the base one (1). In a
-- UI language other than the game's the name comes from the message of the game's skill table, else the game's text.
local function skill_name(ref, lang)
    local raw = ref and ref.id
    if raw == nil then return nil end
    local fail_key = "skill|" .. type(raw) .. "|" .. tostring(raw) .. "|" .. tostring(lang)
    if failed[fail_key] then return nil end
    local value, name = skill_id(raw)
    local job = value and tonumber(name:match("^Job(%d+)_"))
    if not job then
        failed[fail_key] = true
        return nil
    end
    local key = "skill|" .. name .. "|" .. tostring(lang)
    if memo[key] then return memo[key] end
    local levels, tried = {}, {}
    for _, level in ipairs({ known_level(value), 2, 1 }) do
        level = math.tointeger(level)
        if level and level > 0 and not tried[level] then
            tried[level] = true
            levels[#levels + 1] = level
        end
    end
    local text
    if lang and LANG_ID[lang] and lang ~= NamesGame.language() then
        for _, level in ipairs(levels) do
            text = guid_text(skill_guid(value, level), LANG_ID[lang])
            if text then break end
        end
    end
    if not text then
        for _, level in ipairs(levels) do
            text = text_of(Safe.static("app.GUIBase", SKILL_NAME, job, value, level))
            if text then break end
        end
    end
    if text then memo[key] = text else failed[fail_key] = true end
    return text
end

-- A vocation's skills in value order, read once from the enum (nil without it).
local function job_of(job)
    local js = jobs[job]
    if js ~= nil then return js or nil end
    local map = enum_map("app.HumanCustomSkillID")
    if not map then return nil end
    local prefix = string.format("Job%02d_", job)
    local values = {}
    for value, name in pairs(map.by_value) do
        if name:sub(1, #prefix) == prefix then values[#values + 1] = value end
    end
    table.sort(values)
    js = { values = values, names = {} }
    for i, value in ipairs(values) do js.names[i] = map.by_value[value] end
    jobs[job] = js
    return js
end

-- A skill's Japanese name without its level mark: a full-width 2, at times after a space.
local function ja_core(text)
    for _, mark in ipairs({ "\u{FF12}", "\u{3000}", " " }) do
        if text:sub(-#mark) == mark then text = text:sub(1, -#mark - 1) end
    end
    return text
end

-- What the game's skill table says about a vocation's skills, read once: by_ja = the skill by its Japanese name
-- (level 1, else level 2), msg[i] = the name of the i-th skill's level-1 message ("job05_skill_08"). nil, and
-- nothing kept, while the table cannot be read.
local function table_of(js)
    if js.by_ja then return js end
    local by_id = skill_table()
    if by_id == nil then return nil end
    local by_ja, msg = {}, {}
    for i, value in ipairs(js.values) do
        local guid = skill_guid(value, 1, by_id)
        msg[i] = guid and Safe.static("via.gui.message", "getName(System.Guid)", guid)
        local text = guid_text(guid, JAPANESE) or guid_text(skill_guid(value, 2, by_id), JAPANESE)
        if text then
            local core = ja_core(text)
            if core ~= "" and by_ja[core] == nil then by_ja[core] = js.names[i] end
        end
    end
    js.by_ja, js.msg = by_ja, msg
    return js
end

local function starts(s, prefix) return s:sub(1, #prefix) == prefix end

-- The one skill whose Japanese name the core starts with, or that starts with the core, the shorter of the two at
-- least MIN_PREFIX characters; nil when no skill or more than one matches.
local function by_prefix(by_ja, core)
    local found
    for ja, name in pairs(by_ja) do
        local shorter = #ja < #core and ja or core
        if (starts(core, ja) or starts(ja, core)) and (utf8.len(shorter) or 0) >= MIN_PREFIX then
            if found and found ~= name then return nil end
            found = name
        end
    end
    return found
end

-- The skill name and the rule that found it; the third result is true when the skill table could not be read (the
-- answer may change, so it is not kept).
local function attack_skill(attack, job)
    local js = job_of(job)
    if js == nil then return nil end
    local n = tonumber(attack:match("^CS_(%d+)_") or attack:match("^CSLv%d+_(%d+)_"))
    if n then
        -- the job's NN-th skill when its message is the job's NN-th (job05_skill_08 is CS_09), or one of the job's
        -- newer skills (job05_skill_05_TU)
        if job == WARFARER or js.names[n] == nil then return nil end
        local t = table_of(js)
        if t == nil then return nil, nil, true end
        local msg = t.msg[n]
        if msg == string.format("job%02d_skill_%02d", job, n - 1) then return js.names[n], "cs" end
        if type(msg) == "string" and msg:find(string.format("^job%02d_skill_%%d+_TU$", job)) then
            return js.names[n], "cs_tu"
        end
        return nil
    end
    local core = attack:match("^[^_]+")
    core = core and core:gsub("Lv%.?%d+$", "")
    if core == nil or core == "" then return nil end
    local t = table_of(js)
    if t == nil then return nil, nil, true end
    local name = t.by_ja[core]
    if name then return name, "ja" end
    name = by_prefix(t.by_ja, core)
    if name then return name, "ja_prefix" end
    return nil
end

-- { name, rule }, false for none, nil while the skill table cannot be read.
local function attack_entry(attack, job)
    local name, rule, unread = attack_skill(attack, job)
    if unread then return nil end
    return name and { name = name, rule = rule } or false
end

-- The HumanCustomSkillID (name, value) an attack name points at in a vocation, and the rule that found it; nil when
-- none. "cs": "CS_NN_..." / "CSLvL_NN_..." is the job's NN-th skill in value order when that skill's level-1 message
-- is the job's NN-th (jobJJ_skill_<NN-1>; in game thief CS_06 Job04_HollowOut, warrior CSLv2_03 Job05_CrescentSlash
-- and CSLv2_09 Job05_IndomitableLash; never for the Warfarer). "cs_tu": the same number when that skill's level-1
-- message is one of the job's newer skills', jobJJ_skill_MM_TU (warrior CS_13_地流駆け_EX_... Job05_DashSlashUp,
-- CS_14_緋染_... Job05_ScarletVow); less sure than "cs", the newer skills' order being seen only for those two; never
-- for the Warfarer. "ja": the name's core (before "_", without "Lv.2") is the Japanese name of one of the job's skills
-- in the game's skill table (Blink Strike, Compass Slash, Frigor; many attack names are spelled unlike that text).
-- "ja_prefix", when no name is the core: the core starts with a skill's Japanese name or is the start of one, the
-- shorter of the two at least 5 characters, and no other skill of the job matches so (メテオフォール着弾_対ノルド敵
-- Job06_MeteorFall, ロックビート発生_対ノルド敵 Job06_RockBeat, ブリザードLv.2_右奥 Job06_Blizzard by ブリザードガイザー).
-- Whether the attacker has it equipped is the caller's business.
function NamesGame.attack_skill(attack, job)
    job = math.type(job) and math.tointeger(job)
    if type(attack) ~= "string" or attack == "" or not job then return nil end
    local key = job .. "|" .. attack
    local found = attacks[key]
    if found == nil then
        local ok, entry_found = pcall(attack_entry, attack, job)
        found = ok and entry_found
        if found ~= nil then
            if n_attacks >= MAX_ATTACKS then attacks, n_attacks = {}, 0 end
            attacks[key] = found
            n_attacks = n_attacks + 1
        end
    end
    if not found then return nil end
    local map = enum_map("app.HumanCustomSkillID")
    return found.name, map and map.by_name[found.name], found.rule
end

-- The game's message called `name` (via.gui.message) in "en" or "ru"; any other `lang`, or none, is the game's own
-- language. nil when the game has no text for it (no such message, an empty text, a "<REF ...>" placeholder), found or
-- not remembered until reset.
function NamesGame.message(name, lang)
    if type(name) ~= "string" or name == "" then return nil end
    local lang_id = lang and LANG_ID[lang] or Safe.enum(Safe.static("via.gui.GUISystem", "get_MessageLanguage"))
    if lang_id == nil then return nil end
    local key = "message|" .. name .. "|" .. lang_id
    if memo[key] then return memo[key] end
    if failed[key] then return nil end
    local text = message_text(name, lang_id)
    if text then memo[key] = text else failed[key] = true end
    return text
end

local LOOKUP = {
    skill = function(ref, lang) return Safe.try(skill_name, ref, lang) end,
    enemy = function(base_id, lang) return Safe.try(enemy_name, base_id) end,
    item = function(item_id, lang) return Safe.try(item_name, item_id, lang) end,
    message = function(name, lang) return Safe.try(NamesGame.message, name, lang) end,
}

-- { skill = fn(ref, lang), enemy = fn(base_id, lang), item = fn(item_id, lang), message = fn(name, lang) } for
-- Names.new.
function NamesGame.lookup()
    return LOOKUP
end

return NamesGame
