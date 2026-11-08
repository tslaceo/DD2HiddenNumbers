-- Whether the game is paused in a menu (the pause menu, the map and the other menus): app.PauseManager's
-- isPausedAny(), read-only, under Safe.
--
--   pause.paused() -> boolean   true only when the game answers true; anything that cannot be read (no manager, a
--     lookup or a call that raises, an answer that is not a boolean) is false. The manager is looked up by name at
--     each read and never kept: a scene change can destroy it between two frames, and a game method called on a
--     destroyed object can fault inside the game. A read is that lookup and one game call.
local Safe = require("DD2DamageMeter/game/safe")

local Pause = {}

local MANAGER, METHOD = "app.PauseManager", "isPausedAny"

function Pause.paused()
    local manager = Safe.singleton(MANAGER)
    if manager == nil then return false end
    local paused = Safe.call(manager, METHOD)
    if type(paused) ~= "boolean" then return false end
    return paused
end

return Pause
