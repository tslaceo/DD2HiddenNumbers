package.path = "mod/reframework/autorun/?.lua;tests/?.lua;" .. package.path

local T = require("testlib")
local test, eq = T.test, T.eq
local R = require("stubs/reframework")
local battle = require("DD2DamageMeter/game/battle")

-- app.BattleManager as read in the game: BattleModeEnum Normal 0, Ready 1, Battle 2.
local function manager(state)
    R.new()
    state = state or { mode = 0, ending = false, boss = false }
    R.singleton("app.BattleManager", R.object("app.BattleManager", {}, {
        get_BattleMode = function() return state.mode end,
        get_IsBattleEnding = function() return state.ending end,
        get_IsInBigEnemyOrBossEnemyCombat = function() return state.boss end,
    }))
    return state
end

test("battle poll maps modes and survives a missing singleton", function()
    local state = manager()
    local p = battle.poll()
    eq(p.mode, 0, "normal")
    eq(p.ending, false, "not ending")
    eq(p.boss, false, "no boss")
    state.mode = 1
    eq(battle.poll().mode, 1, "ready")
    state.mode, state.ending, state.boss = 2, true, true
    p = battle.poll()
    eq(p.mode, 2, "battle")
    eq(p.ending, true, "ending")
    eq(p.boss, true, "boss")

    R.new()
    eq(battle.poll(), nil, "no BattleManager at all")
    R.singleton("app.BattleManager", nil)
    eq(battle.poll(), nil, "singleton absent")
end)

test("battle poll survives failing calls", function()
    manager()
    -- the mode call raises: nothing to report
    R.singleton("app.BattleManager", R.object("app.BattleManager", {}, {
        get_BattleMode = function() error("boom") end,
        get_IsBattleEnding = function() return true end,
        get_IsInBigEnemyOrBossEnemyCombat = function() return true end,
    }))
    eq(battle.poll(), nil, "mode call raises")

    -- ending and boss calls raise: the mode still counts, the flags are false
    R.singleton("app.BattleManager", R.object("app.BattleManager", {}, {
        get_BattleMode = function() return 2 end,
        get_IsBattleEnding = function() error("boom") end,
        get_IsInBigEnemyOrBossEnemyCombat = function() error("boom") end,
    }))
    local p = battle.poll()
    eq(p.mode, 2, "mode")
    eq(p.ending, false, "ending call raises")
    eq(p.boss, false, "boss call raises")
end)

test("battle poll refuses modes it does not know", function()
    local state = manager()
    for _, bad in ipairs({ -1, 3, 99 }) do
        state.mode = bad
        eq(battle.poll(), nil, "mode " .. bad)
    end
    state.mode = nil
    eq(battle.poll(), nil, "no value")
    state.mode = "2"
    eq(battle.poll(), nil, "not a number")
    state.mode = 2.0
    eq(battle.poll().mode, 2, "whole float counts")
end)

test("battle poll reads only the three getters", function()
    manager()
    battle.poll()
    local sigs = {}
    for _, c in ipairs(R.calls) do sigs[#sigs + 1] = c.sig end
    table.sort(sigs)
    eq(table.concat(sigs, ","), "get_BattleMode,get_IsBattleEnding,get_IsInBigEnemyOrBossEnemyCombat", "calls")
end)

T.finish()
