-- Whether the game is paused in a menu (the pause menu, the map and the other menus): app.PauseManager's
-- isPausedAny(), read-only, under Safe.
--
--   pause.paused() -> boolean   true only when the game answers true; anything that cannot be read (no manager, a
--     lookup or a call that raises, an answer that is not a boolean) is false. The manager is looked up once and
--     kept, so a read is one game call; a read that gives no boolean forgets it and the next read looks it up again.
--   pause.reset()   forgets the manager (a new world)
local Safe = require("DD2DamageMeter/game/safe")

local Pause = {}

local MANAGER, METHOD = "app.PauseManager", "isPausedAny"

local manager = nil

function Pause.reset()
    manager = nil
end

function Pause.paused()
    if manager == nil then
        manager = Safe.singleton(MANAGER)
        if manager == nil then return false end
    end
    local paused = Safe.call(manager, METHOD)
    if type(paused) ~= "boolean" then
        manager = nil
        return false
    end
    return paused
end

return Pause
