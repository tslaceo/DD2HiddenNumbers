-- Battle mode of the game, polled once per frame (app.BattleManager).
local Safe = require("DD2DamageMeter/game/safe")

local Battle = {}

-- { mode = 0|1|2, ending = boolean, boss = boolean }, or nil when the game cannot be asked.
-- mode: BattleModeEnum Normal 0, Ready 1, Battle 2; a value outside that is not reported.
function Battle.poll()
    local manager = Safe.singleton("app.BattleManager")
    if manager == nil then return nil end
    local mode = Safe.call(manager, "get_BattleMode")
    if type(mode) ~= "number" then return nil end
    mode = math.tointeger(mode)
    if mode == nil or mode < 0 or mode > 2 then return nil end
    return {
        mode = mode,
        ending = Safe.call(manager, "get_IsBattleEnding") == true,
        boss = Safe.call(manager, "get_IsInBigEnemyOrBossEnemyCombat") == true,
    }
end

return Battle
