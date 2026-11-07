package.path = "mod/reframework/autorun/?.lua;tests/?.lua;" .. package.path

local T = require("testlib")
local test, eq = T.test, T.eq
local Attrib = require("DD2DamageMeter/attrib")

local function actor(key, name, kind, base_id, max_hp, order)
    return { key = key, name = name, kind = kind, base_id = base_id, max_hp = max_hp, order = order }
end

local MAGE = actor("ch111002_00", "Yves", "pawn", "ch111002_00", 2600, 3)
local MAGE2 = actor("ch111007_00", "Torinald", "pawn", "ch111007_00", 2470, 2)
local PL = actor("ch000000_00", "Guts", "player", "ch000000_00", 2400)
local PAWN = actor("ch100000_00", "Casca", "pawn", "ch100000_00", 2500, 1)
local GOB = actor("ch220003_00_15", "Goblin", "enemy", "ch220003_00", 3700)
local SPOT = { attack = "ヒーリングスポット" }
local SPOT2 = { attack = "ヒーリングスポット_大" }

-- Number of entries in all tables reachable from `root`, each table counted once;
-- the shared objects in `skip` (actors, skill refs) are not the module's own memory.
local function table_size(root, skip)
    local seen, n = {}, 0
    local function walk(t)
        if seen[t] or skip[t] then return end
        seen[t] = true
        for k, v in pairs(t) do
            n = n + 1
            if type(k) == "table" then walk(k) end
            if type(v) == "table" then walk(v) end
        end
    end
    walk(root)
    return n
end

test("touch within 3 frames attributes", function()
    local a = Attrib.new()
    a:touch(100, MAGE, PL.key, SPOT)
    for _, frame in ipairs({ 97, 98, 99, 100, 101, 102, 103 }) do
        local healer, skill = a:healer_for(frame, PL.key)
        eq(healer, MAGE, "healer at frame " .. frame)
        eq(skill, SPOT, "skill at frame " .. frame)
    end
end)

test("touch 4 frames away does not", function()
    local a = Attrib.new()
    a:touch(100, MAGE, PL.key, SPOT)
    for _, frame in ipairs({ 96, 104, 500 }) do
        local healer, skill = a:healer_for(frame, PL.key)
        eq(healer, nil, "healer at frame " .. frame)
        eq(skill, nil, "skill at frame " .. frame)
    end
end)

test("a touch counts for its own target only", function()
    local a = Attrib.new()
    a:touch(100, MAGE, PL.key, SPOT)
    eq(a:healer_for(100, PAWN.key), nil, "other target")
    eq(a:healer_for(100, PL.key), MAGE, "touched target")
end)

test("nearest of two healers wins", function()
    local a = Attrib.new()
    a:touch(100, MAGE, PL.key, SPOT)
    a:touch(102, MAGE2, PL.key, SPOT2)
    local cases = { { 98, MAGE, SPOT }, { 100, MAGE, SPOT }, { 102, MAGE2, SPOT2 }, { 103, MAGE2, SPOT2 }, { 105, MAGE2, SPOT2 } }
    for _, c in ipairs(cases) do
        local healer, skill = a:healer_for(c[1], PL.key)
        eq(healer, c[2], "healer at frame " .. c[1])
        eq(skill, c[3], "skill at frame " .. c[1])
    end

    -- Recording order does not decide it.
    local b = Attrib.new()
    b:touch(102, MAGE2, PL.key, SPOT2)
    b:touch(100, MAGE, PL.key, SPOT)
    eq(b:healer_for(99, PL.key), MAGE, "frame 99, touches recorded in reverse")
    eq(b:healer_for(103, PL.key), MAGE2, "frame 103, touches recorded in reverse")
end)

test("equally near healers: the touch recorded first wins", function()
    local a = Attrib.new()
    a:touch(100, MAGE, PL.key, SPOT)
    a:touch(102, MAGE2, PL.key, SPOT2)
    local healer, skill = a:healer_for(101, PL.key)
    eq(healer, MAGE, "healer")
    eq(skill, SPOT, "skill")
end)

test("dot goes to the last applier of that status", function()
    local a = Attrib.new()
    a:status_applied(1, GOB.key, "Burn", PL)
    a:status_applied(5, GOB.key, "Burn", PAWN)
    a:status_applied(7, GOB.key, "Poison", MAGE)
    eq(a:dot_source(10, GOB.key, "Burn"), PAWN, "burn")
    eq(a:dot_source(10, GOB.key, "Poison"), MAGE, "poison")
    eq(a:dot_source(10, GOB.key, "Freeze"), nil, "a status nobody applied")
    eq(a:dot_source(10, PL.key, "Burn"), nil, "another victim")
end)

test("dot without status type goes to the last applier of any status", function()
    local a = Attrib.new()
    a:status_applied(1, GOB.key, "Burn", PL)
    a:status_applied(7, GOB.key, "Poison", MAGE)
    eq(a:dot_source(10, GOB.key, nil), MAGE, "last of any")
    eq(a:dot_source(10, PL.key, nil), nil, "another victim")

    -- An application with unknown status is the last of any status but takes no typed slot.
    a:status_applied(8, GOB.key, nil, PAWN)
    eq(a:dot_source(10, GOB.key, nil), PAWN, "untyped application is the latest")
    eq(a:dot_source(10, GOB.key, "Poison"), MAGE, "poison keeps its applier")
    eq(a:dot_source(10, GOB.key, "Burn"), PL, "burn keeps its applier")
end)

test("dot after 30 s is unknown", function()
    local a = Attrib.new()
    a:status_applied(10, GOB.key, "Burn", PL)
    eq(a:dot_source(39.9, GOB.key, "Burn"), PL, "typed, just inside")
    eq(a:dot_source(40, GOB.key, "Burn"), PL, "typed, exactly 30 s")
    eq(a:dot_source(40.1, GOB.key, "Burn"), nil, "typed, just outside")
    eq(a:dot_source(39.9, GOB.key, nil), PL, "any status, just inside")
    eq(a:dot_source(40.1, GOB.key, nil), nil, "any status, just outside")

    -- A fresh application restarts the window.
    a:status_applied(35, GOB.key, "Burn", PAWN)
    eq(a:dot_source(60, GOB.key, "Burn"), PAWN, "renewed")
end)

test("options change the windows", function()
    local a = Attrib.new({ touch_frames = 1, dot_seconds = 5 })
    a:touch(100, MAGE, PL.key, SPOT)
    eq(a:healer_for(101, PL.key), MAGE, "1 frame away")
    eq(a:healer_for(102, PL.key), nil, "2 frames away")
    a:status_applied(0, GOB.key, "Burn", PL)
    eq(a:dot_source(5, GOB.key, "Burn"), PL, "5 s")
    eq(a:dot_source(5.1, GOB.key, "Burn"), nil, "5.1 s")
end)

test("prune keeps what is still in the window", function()
    local a = Attrib.new()
    a:touch(100, MAGE, PL.key, SPOT)
    a:status_applied(0, GOB.key, "Burn", PL)
    a:status_applied(0, GOB.key, nil, PAWN)
    a:prune(103, 30)
    eq(a:healer_for(103, PL.key), MAGE, "touch 3 frames old")
    eq(a:dot_source(30, GOB.key, "Burn"), PL, "typed applier 30 s old")
    eq(a:dot_source(30, GOB.key, nil), PAWN, "untyped applier 30 s old")
end)

test("prune keeps memory bounded", function()
    local a = Attrib.new()
    local skip = { [MAGE] = true, [SPOT] = true }
    local targets = { "ch000000_00", "ch100000_00", "ch111007_00", "ch111002_00" }
    local peak = 0
    for frame = 1, 10000 do
        a:touch(frame, MAGE, targets[frame % 4 + 1], SPOT, frame / 60)
        a:prune(frame, frame / 60)
        peak = math.max(peak, table_size(a, skip))
    end
    if peak >= 50 then error("internal tables grew to " .. peak .. " entries") end
    eq(a:healer_for(10000, targets[10000 % 4 + 1]), MAGE, "recent touch survives")

    a:prune(10004, 10000 / 60 + 6.1)
    eq(table_size(a, skip), table_size(Attrib.new(), skip), "nothing left once every touch is stale")
end)

-- The healing spot heals for about 4 s after its last touch (up to 4.8 s, logged in game).
test("a heal after the touches stopped goes to the last toucher for 6 s", function()
    local a = Attrib.new()
    a:touch(100, MAGE, PL.key, SPOT, 10.0)
    for _, c in ipairs({ { 104, 10.1 }, { 300, 13.3 }, { 460, 16.0 } }) do
        local healer, skill = a:healer_for(c[1], PL.key, c[2])
        eq(healer, MAGE, "healer at " .. c[2] .. " s")
        eq(skill, SPOT, "skill at " .. c[2] .. " s")
    end
    eq(a:healer_for(461, PL.key, 16.1), nil, "6.1 s after the last touch")
    eq(a:healer_for(300, PAWN.key, 13.3), nil, "another target")
    eq(a:healer_for(300, PL.key), nil, "a heal without its time: the frame window only")
    -- each touch starts the window again
    a:touch(470, MAGE, PL.key, SPOT, 16.2)
    eq(a:healer_for(800, PL.key, 22.0), MAGE, "5.8 s after the newer touch")
end)

test("two healers: a lingering heal goes to the latest toucher", function()
    local a = Attrib.new()
    a:touch(100, MAGE, PL.key, SPOT, 10.0)
    a:touch(110, MAGE2, PL.key, SPOT2, 10.2)
    local healer, skill = a:healer_for(300, PL.key, 13.0)
    eq(healer, MAGE2, "the latest toucher")
    eq(skill, SPOT2, "its skill")
    eq(a:healer_for(101, PL.key, 10.02), MAGE, "inside the frame window the nearest touch still wins")
    eq(a:healer_for(600, PL.key, 16.1), MAGE2, "6.1 s after the first healer, 5.9 s after the second")
    eq(a:healer_for(700, PL.key, 16.3), nil, "6.1 s after the latest touch")

    -- recording order does not decide it
    local b = Attrib.new()
    b:touch(110, MAGE2, PL.key, SPOT2, 10.2)
    b:touch(100, MAGE, PL.key, SPOT, 10.0)
    eq(b:healer_for(300, PL.key, 13.0), MAGE2, "touches recorded in reverse")
end)

test("a new fight forgets the lingering touches, a reset forgets everything", function()
    local a = Attrib.new()
    a:touch(100, MAGE, PL.key, SPOT, 10.0)
    a:status_applied(10.0, GOB.key, "Burn", PL)
    a:new_fight(104)
    eq(a:healer_for(102, PL.key, 10.03), MAGE, "the frame window stays")
    eq(a:healer_for(200, PL.key, 11.5), nil, "no lingering heal from before the fight")
    eq(a:dot_source(11.5, GOB.key, "Burn"), PL, "status appliers stay")
    a:touch(300, MAGE, PL.key, SPOT, 13.0)
    eq(a:healer_for(400, PL.key, 14.5), MAGE, "touches of the new fight linger")

    a:reset()
    eq(a:healer_for(300, PL.key, 13.0), nil, "touch forgotten")
    eq(a:healer_for(400, PL.key, 14.5), nil, "lingering touch forgotten")
    eq(a:dot_source(14.5, GOB.key, "Burn"), nil, "status applier forgotten")
    eq(table_size(a, {}), table_size(Attrib.new(), {}), "as new")
end)

test("a new fight keeps the lingering touches of its last touch_frames frames", function()
    local a = Attrib.new()
    a:touch(100, MAGE, PL.key, SPOT, 10.0)
    a:touch(97, MAGE2, PAWN.key, SPOT2, 9.95)
    a:new_fight(103)  -- opened 3 frames after the touch on PL, 6 after the one on PAWN
    eq(a:healer_for(220, PL.key, 12.0, 1.5), MAGE, "the touch just before the fight goes on into it")
    eq(a:healer_for(220, PAWN.key, 12.0, 1.5), nil, "an older one does not")
    a:new_fight(104)
    eq(a:healer_for(220, PL.key, 12.0, 1.5), nil, "4 frames after the touch: forgotten")
end)

test("the linger window is an option, at most 10 s", function()
    local a = Attrib.new({ linger_seconds = 2 })
    a:touch(100, MAGE, PL.key, SPOT, 10.0)
    eq(a:healer_for(200, PL.key, 12.0), MAGE, "2 s")
    eq(a:healer_for(201, PL.key, 12.1), nil, "2.1 s")
    local b = Attrib.new({ linger_seconds = 60 })
    b:touch(100, MAGE, PL.key, SPOT, 10.0)
    eq(b:healer_for(700, PL.key, 20.0), MAGE, "10 s")
    eq(b:healer_for(701, PL.key, 20.1), nil, "capped at 10 s")
end)

-- Spot ticks are under 3 HP; the jumps to full HP seen 2 s after a touch were 594-749 HP (logged in game).
test("only a heal of at most 50 HP lingers; the frame window has no cap", function()
    local a = Attrib.new()
    a:touch(100, MAGE, PL.key, SPOT, 10.0)
    eq(a:healer_for(220, PL.key, 12.0, 1.5), MAGE, "a 1.5 HP tick 2 s later")
    eq(a:healer_for(220, PL.key, 12.0, 50), MAGE, "50 HP")
    eq(a:healer_for(220, PL.key, 12.0, 50.1), nil, "50.1 HP")
    eq(a:healer_for(220, PL.key, 12.0, 749), nil, "a jump of 749 HP 2 s later")
    local healer, skill = a:healer_for(102, PL.key, 10.03, 749)
    eq(healer, MAGE, "749 HP within 3 frames of the touch")
    eq(skill, SPOT, "its skill")
    local b = Attrib.new({ linger_max_hp = 10 })
    b:touch(100, MAGE, PL.key, SPOT, 10.0)
    eq(b:healer_for(220, PL.key, 12.0, 10), MAGE, "10 HP with the option at 10")
    eq(b:healer_for(220, PL.key, 12.0, 11), nil, "11 HP")
end)

test("prune keeps a lingering touch for its window, then drops it", function()
    local a = Attrib.new()
    local skip = { [MAGE] = true, [SPOT] = true }
    a:touch(100, MAGE, PL.key, SPOT, 10.0)
    a:prune(460, 16.0)
    eq(a:healer_for(460, PL.key, 16.0), MAGE, "6 s old, kept")
    a:prune(461, 16.1)
    eq(table_size(a, skip), table_size(Attrib.new(), skip), "dropped after 6 s")
end)

test("prune forgets expired status appliers", function()
    local skip = { [PL] = true, [PAWN] = true }
    local function apply(a, i)
        a:status_applied(i, "victim" .. i, "Burn", PL)
        a:status_applied(i, "victim" .. i, nil, PAWN)
    end
    local a = Attrib.new()
    for i = 1, 100 do apply(a, i) end

    a:prune(0, 130) -- victim 99 was hit 31 s ago, victim 100 exactly 30 s ago
    local only_last = Attrib.new()
    apply(only_last, 100)
    eq(table_size(a, skip), table_size(only_last, skip), "only the 30 s old applier is left")
    eq(a:dot_source(130, "victim100", "Burn"), PL, "typed applier kept")
    eq(a:dot_source(130, "victim100", nil), PAWN, "untyped applier kept")

    a:prune(0, 131)
    eq(table_size(a, skip), table_size(Attrib.new(), skip), "nothing left")
end)

-- A heal the game gave no source for, on a party member, is his own (100 HP: big enough for lifesteal).
test("an own heal 0-3 frames after his own counted hit is lifesteal, 4 frames after it regeneration", function()
    local a = Attrib.new()
    eq(a:own_heal(100, PL.key, 100), "regen", "no hit of his: regeneration")
    a:struck(100, PL.key)
    for _, frame in ipairs({ 100, 101, 102, 103 }) do
        eq(a:own_heal(frame, PL.key, 100), "lifesteal", "frame " .. frame)
    end
    eq(a:own_heal(104, PL.key, 100), "regen", "4 frames after")
    eq(a:own_heal(99, PL.key, 100), "regen", "before the hit")
    -- another member's hit says nothing about this one's heals
    a:struck(110, PAWN.key)
    eq(a:own_heal(111, PL.key, 100), "regen", "the pawn hit, not him")
    eq(a:own_heal(111, PAWN.key, 100), "lifesteal", "the pawn's own heal")
    -- the latest hit counts; an older frame reported late does not move it back
    a:struck(120, PL.key)
    a:struck(118, PL.key)
    eq(a:own_heal(123, PL.key, 100), "lifesteal", "3 frames after the latest")
    eq(a:own_heal(124, PL.key, 100), "regen", "4 after it")
    eq(Attrib.new({ lifesteal_frames = 5 }):own_heal(5, PL.key, 100), "regen", "an option, no hit yet")
    local b = Attrib.new({ lifesteal_frames = 5 })
    b:struck(100, PL.key)
    eq(b:own_heal(105, PL.key, 100), "lifesteal", "the window is an option")
end)

test("prune and reset forget the hits a lifesteal follows", function()
    local skip = {}
    local a = Attrib.new()
    a:struck(100, PL.key)
    a:struck(101, PAWN.key)
    a:prune(103, 10.0)
    eq(a:own_heal(103, PL.key, 100), "lifesteal", "3 frames old, kept")
    a:prune(104, 10.1)
    eq(a:own_heal(104, PAWN.key, 100), "lifesteal", "the pawn's is 3 frames old")
    a:prune(105, 10.2)
    eq(table_size(a, skip), table_size(Attrib.new(), skip), "both dropped")
    a:struck(200, PL.key)
    a:new_fight(201)
    eq(a:own_heal(201, PL.key, 100), "lifesteal", "a new fight keeps them")
    a:reset()
    eq(a:own_heal(201, PL.key, 100), "regen", "a reset forgets them")
    eq(table_size(a, skip), table_size(Attrib.new(), skip), "as new")
end)

-- Logged in game: lifesteal heals were 30-507 HP, the regeneration ticks 1-4 HP.
test("lifesteal is a heal of at least 10 HP: a smaller one right after his hit is regeneration", function()
    local a = Attrib.new()
    a:struck(100, PL.key)
    eq(a:own_heal(101, PL.key, 10), "lifesteal", "10 HP")
    eq(a:own_heal(101, PL.key, 9), "regen", "9 HP")
    eq(a:own_heal(101, PL.key, 9.99), "regen", "just under 10")
    eq(a:own_heal(101, PL.key, 2), "regen", "a regeneration tick")
    eq(a:own_heal(101, PL.key, nil), "regen", "no amount")
    eq(a:own_heal(104, PL.key, 500), "regen", "a big heal 4 frames after: still regeneration")
    local b = Attrib.new({ lifesteal_min_hp = 50 })
    b:struck(100, PL.key)
    eq(b:own_heal(100, PL.key, 49), "regen", "the floor is an option")
    eq(b:own_heal(100, PL.key, 50), "lifesteal", "at it")
end)

T.finish()
