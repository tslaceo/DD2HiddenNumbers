-- The player's weapon, for the enemy plate's "you:" line before his first hit: its damage type, its own element and
-- an active enchant's element (the fields as probed in game). Read-only, every game access under
-- Safe.
--
--   Weapon.read(player_character, t)
--       -> { phys = "Slash" | "Blow" | "Shoot" | "Magic", element = jt | nil, enchant = jt | nil } | nil
--     t: seconds. The game is read when the last read, good or not, is READ_EVERY old (or later than t: a clock that
--     went back); in between, the last answer is given, nil when that read found no weapon. Without a character, nil
--     and nothing is read; without a time, the last answer and nothing is read.
--     The weapon: character:get_RightWeapon(), else get_LeftWeapon() (a bow may sit in the left hand), an app.Weapon;
--     nil when neither hand has one.
--     phys: by the weapon's vocation first, its Job field (app.Character.JobEnum): 2 (Archer) "Shoot";
--     3 (Mage), 6 (Sorcerer), 8 (Magick Archer) "Magic". Any other Job by IsBlunt: true "Blow" (the Trickster's
--     censer, Job 9), false "Slash" (the Thief's daggers, Job 4; the Mystic Spearhand's duospear, Job 7: its magick
--     shows only in its hits); nil when IsBlunt is then no boolean.
--     element: the weapon's own, get_OriginalElementType(), else its ElementType field.
--     enchant: character:get_WeaponElementController(), its WeaponElementInfos array (one entry per hand), the entry
--     of the hand whose weapon is read: <WeaponType>k__BackingField 1 right, 0 left, or isLeft() when that cannot be
--     read. Its NowElementType. Never the other hand's entry: a hand without a weapon keeps a stale value. Never
--     app.Weapon.OverwriteElementType: a Nullable that get_field cannot read. An enchant of the weapon's own element
--     is left out: it changes nothing, and the entry may name that element without any enchant (not seen in the game).
--     jt from app.AttackUserData.ElementType: 1 Fire, 2 Ice, 3 Thunder, 4 Light, 5 Dark; 0, -1 and the rest are none.
--     Plain strings only.
--   Weapon.peek(player_character) -> the answer as Weapon.read gives it, read now and kept nowhere (the debug
--     collector, game/collector.lua: a weapon just swapped in, which Weapon.read may not have read yet); nil and
--     nothing read without a character
--   Weapon.now_element(player_character, hand) -> integer | nil
--     the NowElementType of the WeaponElementInfos entry of `hand` (0 left, 1 right; found as above) as an integer,
--     whatever it means; nil when there is none or it cannot be read
--   Weapon.reset()   forgets the last answer (a new world)
local Safe = require("DD2DamageMeter/game/safe")

local Weapon = {}

local READ_EVERY = 1   -- s between two reads
local MAX_HANDS = 4    -- WeaponElementInfos entries looked through (the game has 2)
local LEFT, RIGHT = 0, 1   -- WeaponElementInfo.<WeaponType>k__BackingField
local ELEMENT = { "Fire", "Ice", "Thunder", "Light", "Dark" }   -- app.AttackUserData.ElementType 1..5
-- The weapon's Job (app.Character.JobEnum) whose damage type IsBlunt does not tell: Archer; Mage, Sorcerer, Magick
-- Archer.
local JOB_PHYS = { [2] = "Shoot", [3] = "Magic", [6] = "Magic", [8] = "Magic" }

local answer = nil    -- the last answer
local read_at = nil   -- t of the last read, good or not

function Weapon.reset()
    answer, read_at = nil, nil
end

local function finite(x)
    if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge then return nil end
    return x
end

local function element(v)
    return ELEMENT[Safe.enum(v)]
end

local function on_hand(info, hand)
    local h = Safe.enum(Safe.field(info, "<WeaponType>k__BackingField"))
    if h ~= nil then return h == hand end
    return Safe.call(info, "isLeft") == (hand == LEFT)
end

function Weapon.now_element(character, hand)
    local infos = Safe.field(Safe.call(character, "get_WeaponElementController"), "WeaponElementInfos")
    for _, info in ipairs(Safe.list(infos, MAX_HANDS)) do
        if info and on_hand(info, hand) then return Safe.enum(Safe.field(info, "NowElementType")) end
    end
    return nil
end

-- The element on `hand` now, nil when none.
local function enchant(character, hand)
    return ELEMENT[Weapon.now_element(character, hand)]
end

-- The weapon's damage type: by its vocation, else by IsBlunt; nil when neither tells.
local function phys(weapon)
    local by_job = JOB_PHYS[Safe.enum(Safe.field(weapon, "Job"))]
    if by_job ~= nil then return by_job end
    local blunt = Safe.field(weapon, "IsBlunt")
    if type(blunt) ~= "boolean" then return nil end
    return blunt and "Blow" or "Slash"
end

local function read(character)
    local hand, weapon = RIGHT, Safe.call(character, "get_RightWeapon")
    if weapon == nil then hand, weapon = LEFT, Safe.call(character, "get_LeftWeapon") end
    if weapon == nil then return nil end
    local kind = phys(weapon)
    if kind == nil then return nil end
    local own = Safe.call(weapon, "get_OriginalElementType")
    if Safe.enum(own) == nil then own = Safe.field(weapon, "ElementType") end
    local found = { phys = kind, element = element(own), enchant = enchant(character, hand) }
    if found.enchant == found.element then found.enchant = nil end
    return found
end

function Weapon.peek(character)
    if character == nil then return nil end
    return Safe.try(read, character)
end

function Weapon.read(character, t)
    if character == nil then return nil end
    if finite(t) == nil then return answer end
    if read_at ~= nil and t >= read_at and t - read_at < READ_EVERY then return answer end
    read_at = t
    answer = Safe.try(read, character)
    return answer
end

return Weapon
