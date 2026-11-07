-- The player's own HP and stamina, for the numbers by the game's HUD bars (ui/player_numbers.lua; the calls and
-- fields below as read in the game). Read-only, every game access under Safe, no hooks; nothing kept between reads.
--
--   PlayerVitals.read(character) -> { hp, hp_max, hp_full, sp, sp_max, sp_full }   from the player's app.Character
--     (app.CharacterManager:get_ManualPlayer()): on its get_Hit() app.HitController, hp = get_Hp() (the HP now),
--     hp_max = get_ReducedMaxHp() (the max as cut by damage; the HP heals up to it, down to MinRatioReducedMaxHp 0.10
--     of the full one) and hp_full = get_OriginalMaxHp() (the full max); on its get_StaminaManager()
--     app.StaminaManager, sp = get_RemainingAmount() (the stamina now; it goes below 0, to MinValue -400),
--     sp_max = get_ReducedMaxValue() (the max as cut) and sp_full = get_MaxValue() (the full max). The floats as the
--     game gives them (3030.84). Each value is nil when its call fails or does not give a finite number: all of them
--     without a character, the three of a manager without it. Never raises.
local Safe = require("DD2DamageMeter/game/safe")

local PlayerVitals = {}

-- The finite number obj:name() gives, nil for anything else.
local function number(obj, name)
    local v = Safe.call(obj, name)
    if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
    return v
end

function PlayerVitals.read(character)
    local hit = Safe.call(character, "get_Hit")
    local stamina = Safe.call(character, "get_StaminaManager")
    return {
        hp = number(hit, "get_Hp"), hp_max = number(hit, "get_ReducedMaxHp"),
        hp_full = number(hit, "get_OriginalMaxHp"),
        sp = number(stamina, "get_RemainingAmount"), sp_max = number(stamina, "get_ReducedMaxValue"),
        sp_full = number(stamina, "get_MaxValue"),
    }
end

return PlayerVitals
