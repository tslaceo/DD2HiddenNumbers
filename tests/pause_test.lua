package.path = "mod/reframework/autorun/?.lua;tests/?.lua;" .. package.path

local T = require("testlib")
local test, eq = T.test, T.eq
local R = require("stubs/reframework")
local pause = require("DD2DamageMeter/game/pause")

-- A fresh game whose app.PauseManager answers state.paused; state.lookups counts sdk.get_managed_singleton.
local function game()
    R.new()
    local state = { paused = false, lookups = 0 }
    R.method("app.PauseManager", "isPausedAny", function() return state.paused end)
    state.manager = R.object("app.PauseManager")
    R.singleton("app.PauseManager", state.manager)
    local lookup = sdk.get_managed_singleton
    sdk.get_managed_singleton = function(name)
        state.lookups = state.lookups + 1
        return lookup(name)
    end
    return state
end

-- The game calls made on `object` so far.
local function calls_on(object)
    local n = 0
    for _, c in ipairs(R.calls) do
        if c.this == object then n = n + 1 end
    end
    return n
end

test("paused follows the game's isPausedAny", function()
    local state = game()
    eq(pause.paused(), false, "playing")
    state.paused = true
    eq(pause.paused(), true, "a menu open")
    state.paused = false
    eq(pause.paused(), false, "closed")
end)

test("one call a frame: the manager is looked up by name at each read, never kept", function()
    local state = game()
    for _ = 1, 10 do pause.paused() end
    eq(state.lookups, 10, "one lookup a read")
    eq(#R.calls_of("isPausedAny"), 10, "one call a read")
    eq(#R.calls, 10, "nothing else asked")
end)

test("a manager the game made anew is read at once; the old one is never asked again", function()
    local state = game()
    state.paused = true
    eq(pause.paused(), true, "the first manager answers")
    local old = state.manager
    local fresh = R.object("app.PauseManager")
    R.singleton("app.PauseManager", fresh)
    local before = calls_on(old)
    eq(pause.paused(), true, "the new manager answers")
    eq(pause.paused(), true, "and again")
    eq(calls_on(old), before, "the old manager not asked")
    eq(calls_on(fresh), 2, "the new one asked each read")
end)

test("nothing to read counts as not paused", function()
    local state = game()
    -- no manager: nothing but the lookup, again on the next frame
    R.singleton("app.PauseManager", nil)
    eq(pause.paused(), false, "no manager")
    eq(pause.paused(), false, "still none")
    eq(state.lookups, 2, "looked up each frame")
    eq(#R.calls, 0, "nothing called")
    -- the lookup raises
    sdk.get_managed_singleton = function() error("no singletons") end
    eq(pause.paused(), false, "the lookup raises")
end)

test("a raising or odd answer counts as not paused", function()
    local state = game()
    eq(pause.paused(), false, "read once")
    -- the call raises (the game destroyed the manager): not paused; the next frame reads the new one
    state.manager.poison = true
    state.paused = true
    eq(pause.paused(), false, "a call that raises")
    R.singleton("app.PauseManager", R.object("app.PauseManager"))
    eq(pause.paused(), true, "the new manager answers")
    -- an answer that is not a boolean
    for _, odd in ipairs({ 1, "true", {} }) do
        state.paused = odd
        eq(pause.paused(), false, "answer " .. tostring(odd))
    end
    state.paused = nil
    eq(pause.paused(), false, "no answer")
    -- the method is gone after a game update: an unknown method gives nil
    R.undeclare("app.PauseManager")
    R.singleton("app.PauseManager", R.object("app.PauseManager"))
    eq(pause.paused(), false, "no isPausedAny")
end)

T.finish()
