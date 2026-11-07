-- Display names of skills, enemies and items, the game's own messages by name, and the grouping key that merges the
-- game's fine-grained attack names (charge levels, perfect timing, follow-ups) into one skill.
-- Game text comes from `lookup` (adapter functions returning a string or nil); this module
-- only knows the fallbacks (none for a message: the caller has its own).
local i18n = require("DD2DamageMeter/i18n")

local Names = {}
Names.__index = Names

-- Attack names (logged in game) of blows that are not a learned skill; only a guess for a hit that has no word
-- from the game (ref.normal, the attacker's skill state None).
local NORMAL = { "^N_", "^NS_", "^N%(", "弱攻撃", "強攻撃", "ダッシュ", "しがみ付き", "ジャンプ" }

-- Statuses that tick damage (game/hits.lua) by the family their rows are named after (lang key dot_<family>).
local DOT_FAMILY = { Poison = "poison", VirulentPoison = "poison", FireSpread = "burn", Electric = "shock",
                     WetElectric = "shock", Frostbite = "frost", Freeze = "frost" }
local FAMILIES = {}
for _, family in pairs(DOT_FAMILY) do FAMILIES[family] = true end

-- Parts of an attack name that only say how it was made: charge level, skill level (with or
-- without an underscore: 円月斬りLv.2, ファイヤーストーム_Lv.2), follow-up, perfect timing, main
-- hit. A trailing hand marker (_L/_R) is dropped after them.
local SUFFIXES = { "_溜_%d+", "_?Lv%.?%d+", "_追撃", "_極", "_main%d*" }

function Names.new(lookup)
    return setmetatable({ lookup = lookup or {} }, Names)
end

local function attack_name(ref)
    local name = ref and ref.attack
    if type(name) == "string" and name ~= "" then return name end
end

-- Skills ("CS" attacks): CSLv2_09_魔人斬り_溜_2_極 -> 魔人斬り.
local function skill_core(name)
    return name:match("^CS_%d+_([^_]+)") or name:match("^CSLv%d+_%d+_([^_]+)")
end

-- A "CS" name is a skill even if it also contains a normal-attack word (CSLv2_05_ジャンプ斬り_溜_1)
-- or the attacker's state said None when it landed, so is_normal, skill_key and skill always agree on it.
-- Otherwise the game's word (ref.normal) decides, and the name patterns only when it is missing.
function Names:is_normal(ref)
    if not ref or ref.id ~= nil then return false end
    local name = attack_name(ref)
    if name and skill_core(name) then return false end
    if ref.normal == true then return true end
    if not name then return false end
    for _, pattern in ipairs(NORMAL) do
        if name:find(pattern) then return true end
    end
    return false
end

-- Grouping key of a skill, always a string so that keys merge and sort together: the game's
-- skill id, else the core of its attack name; "normal" for normal attacks, "dot:<family>" for
-- a DoT tick, "?" when nothing is known.
function Names:skill_key(ref)
    if ref and ref.id ~= nil then return tostring(ref.id) end
    local name = attack_name(ref)
    local core = name and skill_core(name)
    if core then return core end
    if self:is_normal(ref) then return "normal" end
    if not name then
        local status = ref and ref.status
        if type(status) == "string" and status ~= "" then return "dot:" .. (DOT_FAMILY[status] or status) end
        return "?"
    end
    local key = name
    for _, suffix in ipairs(SUFFIXES) do key = key:gsub(suffix, "") end
    key = key:gsub("_[LR]$", "")
    if key == "" then return name end
    return key
end

-- A non-empty string from an adapter lookup, or nil.
local function from_game(fn, ...)
    if not fn then return nil end
    local text = fn(...)
    if type(text) == "string" and text ~= "" then return text end
end

function Names:skill(ref, lang)
    lang = lang or i18n.lang()
    local text = from_game(self.lookup.skill, ref, lang)
    if text then return text end
    local key = self:skill_key(ref)
    if key == "normal" then return i18n.t("normal_attacks") end
    if key == "?" then return i18n.t("unknown_skill") end
    local dot = key:match("^dot:(.+)$")
    if dot then
        if FAMILIES[dot] then return i18n.t("dot_" .. dot) end
        return i18n.t("dot") .. " (" .. dot .. ")"
    end
    return i18n.t("skill") .. " (" .. tostring(key) .. ")"
end

-- The game's name of an enemy kind; "Unnamed enemy" when the game has none for it (some kinds have no name at all),
-- the base id only without an enemy lookup.
function Names:enemy(base_id, lang)
    if not self.lookup.enemy then return base_id end
    return from_game(self.lookup.enemy, base_id, lang or i18n.lang()) or i18n.t("unnamed_enemy")
end

function Names:item(item_id, lang)
    return from_game(self.lookup.item, item_id, lang or i18n.lang()) or (i18n.t("item") .. " #" .. tostring(item_id))
end

-- The game's message called `name` in `lang` (default: the interface language), nil when the game has none.
function Names:message(name, lang)
    return from_game(self.lookup.message, name, lang or i18n.lang())
end

return Names
