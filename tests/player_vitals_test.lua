package.path = "mod/reframework/autorun/?.lua;tests/?.lua;" .. package.path

local T = require("testlib")
local test, eq = T.test, T.eq
local R = require("stubs/reframework")
local PlayerVitals = require("DD2DamageMeter/game/player_vitals")

-- The player's character as the probes saw it: its get_Hit() app.HitController (get_Hp, get_ReducedMaxHp,
-- get_OriginalMaxHp) and its get_StaminaManager() app.StaminaManager (get_RemainingAmount, get_ReducedMaxValue,
-- get_MaxValue), each answering with v's value of the moment. The returned p has p.character, p.hc, p.sm.
local function player(v)
    R.new()
    local p = {}
    p.hc = R.object("app.HitController", {}, {
        get_Hp = function() return v.hp end,
        get_ReducedMaxHp = function() return v.hp_max end,
        get_OriginalMaxHp = function() return v.hp_full end,
    })
    p.sm = R.object("app.StaminaManager", {}, {
        get_RemainingAmount = function() return v.sp end,
        get_ReducedMaxValue = function() return v.sp_max end,
        get_MaxValue = function() return v.sp_full end,
    })
    p.character = R.character({ go = "ch000000_00", hp = 1, max_hp = 2 })
    p.character.methods.get_Hit = function() return p.hc end
    p.character.methods.get_StaminaManager = function() return p.sm end
    return p
end

local KEYS = { "hp", "hp_max", "hp_full", "sp", "sp_max", "sp_full" }

local function values(got)
    local out = {}
    for i, key in ipairs(KEYS) do out[i] = key .. "=" .. tostring(got[key]) end
    return table.concat(out, " ")
end

test("the six numbers from the player's hit controller and stamina manager, as the game gives them", function()
    local v = { hp = 3030.84, hp_max = 3030.84, hp_full = 3100, sp = 938, sp_max = 1300, sp_full = 1300 }
    local p = player(v)
    local got = PlayerVitals.read(p.character)
    eq(values(got), "hp=3030.84 hp_max=3030.84 hp_full=3100 sp=938 sp_max=1300 sp_full=1300", "the six values")
    -- the stamina can go below 0 (MinValue -400): kept as it is
    v.sp = -120.5
    eq(PlayerVitals.read(p.character).sp, -120.5, "a negative stamina")
    -- read anew each time: nothing kept
    v.hp = 3100
    eq(PlayerVitals.read(p.character).hp, 3100, "read again")
    -- from the character's own get_Hit, not the character's get_Hp
    eq(#R.calls_of("get_Hit"), 3, "get_Hit once a read")
    eq(#R.calls_of("get_StaminaManager"), 3, "get_StaminaManager once a read")
    for _, c in ipairs(R.calls_of("get_Hp")) do eq(c.this, p.hc, "get_Hp asked of the hit controller") end
end)

test("a value that cannot be read is nil, the others still come; it never raises", function()
    local v = { hp = 3100, hp_max = 3100, hp_full = 3100, sp = 1300, sp_max = 1300, sp_full = 1300 }
    local p = player(v)
    eq(values(PlayerVitals.read(nil)), "hp=nil hp_max=nil hp_full=nil sp=nil sp_max=nil sp_full=nil",
        "no character: all nil")
    -- no hit controller, or one that raises: the HP's three nil, the stamina's there
    p.character.methods.get_Hit = function() return nil end
    eq(values(PlayerVitals.read(p.character)), "hp=nil hp_max=nil hp_full=nil sp=1300 sp_max=1300 sp_full=1300",
        "no hit controller")
    p.character.methods.get_Hit = function() return p.hc end
    p.hc.poison = true
    eq(values(PlayerVitals.read(p.character)), "hp=nil hp_max=nil hp_full=nil sp=1300 sp_max=1300 sp_full=1300",
        "a hit controller that raises")
    p.hc.poison = false
    -- no stamina manager, or one that raises: the same for the stamina
    p.sm.poison = true
    eq(values(PlayerVitals.read(p.character)), "hp=3100 hp_max=3100 hp_full=3100 sp=nil sp_max=nil sp_full=nil",
        "a stamina manager that raises")
    p.sm.poison = false
    p.character.methods.get_StaminaManager = function() error("no manager") end
    eq(values(PlayerVitals.read(p.character)), "hp=3100 hp_max=3100 hp_full=3100 sp=nil sp_max=nil sp_full=nil",
        "its getter raises")
    p.character.methods.get_StaminaManager = function() return p.sm end
    -- a character that raises: all nil
    p.character.poison = true
    eq(values(PlayerVitals.read(p.character)), "hp=nil hp_max=nil hp_full=nil sp=nil sp_max=nil sp_full=nil",
        "a character that raises")
    p.character.poison = false
    -- one call that raises or gives what is not a finite number: that value nil
    p.hc.methods.get_ReducedMaxHp = function() error("boom") end
    v.sp_max, v.hp_full, v.sp, v.sp_full = "1300", 0 / 0, math.huge, nil
    eq(values(PlayerVitals.read(p.character)), "hp=3100 hp_max=nil hp_full=nil sp=nil sp_max=nil sp_full=nil",
        "each value on its own")
    -- junk for a character: nothing raises
    for _, junk in ipairs({ 5, "player", {}, true }) do
        local ok, got = pcall(PlayerVitals.read, junk)
        eq(ok, true, "never raises on " .. tostring(junk))
        eq(values(got), "hp=nil hp_max=nil hp_full=nil sp=nil sp_max=nil sp_full=nil", "all nil")
    end
end)

T.finish()
