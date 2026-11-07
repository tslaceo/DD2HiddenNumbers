package.path = "mod/reframework/autorun/?.lua;tests/?.lua;" .. package.path

local T = require("testlib")
local test, eq = T.test, T.eq
local R = require("stubs/reframework")
local Weapon = require("DD2DamageMeter/game/weapon")

local LEFT, RIGHT = 0, 1   -- WeaponElementInfo.<WeaponType>k__BackingField
local NONE = -1            -- app.AttackUserData.ElementType of a weapon without an element

local function world()
    R.new()
    Weapon.reset()
end

-- An app.Weapon as read in game: o.blunt (IsBlunt), o.element (ElementType and
-- get_OriginalElementType()), o.job; o.fields_only: the getter gives nothing.
local function weapon(o)
    local methods = {}
    if not o.fields_only then methods.get_OriginalElementType = function() return o.element end end
    return R.object("app.Weapon", { IsBlunt = o.blunt, ElementType = o.element, Job = o.job or 4 }, methods)
end

-- One hand's WeaponElementInfo: `hand` LEFT or RIGHT, `now` its NowElementType; no_type: the WeaponType field reads
-- nil (isLeft() still answers).
local function info(hand, now, no_type)
    return R.object("app.WeaponElementControllerBase.WeaponElementInfo", {
        ["<WeaponType>k__BackingField"] = (not no_type) and hand or nil,
        ["<IsDarkElement>k__BackingField"] = now == 5,
        NowElementType = now,
    }, { isLeft = function() return hand == LEFT end })
end

-- The player's app.Character: get_RightWeapon gives o.right, get_LeftWeapon o.left; get_WeaponElementController a
-- controller whose WeaponElementInfos array holds o.infos (as in game: the left hand's entry first); none without
-- o.infos.
local function player(o)
    local c = R.character{ go = "ch000000_00" }
    local ctrl = nil
    if o.infos then
        local arr = R.object("app.WeaponElementControllerBase.WeaponElementInfo[]", {}, {})
        arr.items = o.infos
        ctrl = R.object("app.WeaponElementController", { WeaponElementInfos = arr }, {})
    end
    c.methods.get_RightWeapon = function() return o.right end
    c.methods.get_LeftWeapon = function() return o.left end
    c.methods.get_WeaponElementController = function() return ctrl end
    return c
end

local function no_enchant() return { info(LEFT, NONE), info(RIGHT, NONE) } end

local function reads() return #R.calls_of("get_RightWeapon") end

-- Exactly the keys of `want`, each with its value, and nothing but strings.
local function is(got, want, what)
    eq(type(got), "table", what .. ": an answer")
    eq(getmetatable(got), nil, what .. ": a plain table")
    for k, v in pairs(got) do
        eq(type(v), "string", what .. "." .. tostring(k) .. " is a string")
        eq(v, want[k], what .. "." .. tostring(k))
    end
    for k, v in pairs(want) do eq(got[k], v, what .. "." .. k) end
end

test("the censer is blunt with nothing else", function()
    world()
    local c = player{ right = weapon{ blunt = true, element = NONE, job = 9 }, infos = no_enchant() }
    is(Weapon.read(c, 10), { phys = "Blow" }, "the censer")
end)

test("a Fighter's sword is slash", function()
    world()
    local c = player{ right = weapon{ blunt = false, element = NONE, job = 1 }, infos = no_enchant() }
    is(Weapon.read(c, 10), { phys = "Slash" }, "a sword")
end)

test("an Archer's bow in the left hand is shoot", function()
    world()
    local c = player{ left = weapon{ blunt = false, element = NONE, job = 2 }, infos = no_enchant() }
    is(Weapon.read(c, 10), { phys = "Shoot" }, "the bow")
    -- the enchant of the hand that holds it; the right hand's entry is stale
    world()
    c = player{ left = weapon{ blunt = false, element = NONE, job = 2 }, infos = { info(LEFT, 3), info(RIGHT, 1) } }
    is(Weapon.read(c, 10), { phys = "Shoot", enchant = "Thunder" }, "the left hand's enchant")
    world()
    c = player{ left = weapon{ blunt = false, element = NONE, job = 2 },
                infos = { info(RIGHT, 1, true), info(LEFT, 2, true) } }
    is(Weapon.read(c, 10), { phys = "Shoot", enchant = "Ice" }, "the left hand by isLeft()")
    -- the vocation comes before IsBlunt, which it does not need
    world()
    c = player{ left = weapon{ blunt = true, element = NONE, job = 2 }, infos = no_enchant() }
    is(Weapon.read(c, 10), { phys = "Shoot" }, "IsBlunt true")
    world()
    c = player{ left = weapon{ blunt = nil, element = NONE, job = 2 }, infos = no_enchant() }
    is(Weapon.read(c, 10), { phys = "Shoot" }, "IsBlunt unread")
end)

test("the right weapon before the left", function()
    world()
    local c = player{ right = weapon{ blunt = false, element = NONE, job = 1 },
                      left = weapon{ blunt = false, element = NONE, job = 2 },
                      infos = { info(LEFT, 3), info(RIGHT, 1) } }
    is(Weapon.read(c, 10), { phys = "Slash", enchant = "Fire" }, "the right hand's weapon and enchant")
    eq(#R.calls_of("get_LeftWeapon"), 0, "the left hand is not asked")
end)

test("a Sorcerer's staff is magic", function()
    world()
    local c = player{ right = weapon{ blunt = true, element = NONE, job = 6 }, infos = no_enchant() }
    is(Weapon.read(c, 10), { phys = "Magic" }, "the Sorcerer")
    world()
    c = player{ right = weapon{ blunt = false, element = NONE, job = 3 }, infos = no_enchant() }
    is(Weapon.read(c, 10), { phys = "Magic" }, "the Mage")
end)

test("a Magick Archer's bow is magic", function()
    world()
    local c = player{ right = weapon{ blunt = false, element = NONE, job = 8 }, infos = no_enchant() }
    is(Weapon.read(c, 10), { phys = "Magic" }, "the Magick Archer")
end)

test("every other vocation by IsBlunt", function()
    for _, job in ipairs({ 1, 4, 5, 7, 9, 10, 0, 11 }) do
        world()
        local c = player{ right = weapon{ blunt = true, element = NONE, job = job }, infos = no_enchant() }
        is(Weapon.read(c, 10), { phys = "Blow" }, "Job " .. job .. " blunt")
        world()
        c = player{ right = weapon{ blunt = false, element = NONE, job = job }, infos = no_enchant() }
        is(Weapon.read(c, 10), { phys = "Slash" }, "Job " .. job .. " not blunt")
    end
end)

test("a weapon's own element", function()
    world()
    local c = player{ right = weapon{ blunt = false, element = 2 }, infos = no_enchant() }
    is(Weapon.read(c, 10), { phys = "Slash", element = "Ice" }, "ElementType 2")
    -- every element by its number; 0 and -1 are none
    local names = { [1] = "Fire", [2] = "Ice", [3] = "Thunder", [4] = "Light", [5] = "Dark", [0] = nil, [-1] = nil }
    for n = -1, 6 do
        world()
        c = player{ right = weapon{ blunt = true, element = n }, infos = no_enchant() }
        eq(Weapon.read(c, 10).element, names[n], "ElementType " .. n)
    end
    -- the field when the getter gives nothing
    world()
    c = player{ right = weapon{ blunt = false, element = 3, fields_only = true }, infos = no_enchant() }
    is(Weapon.read(c, 10), { phys = "Slash", element = "Thunder" }, "from the ElementType field")
end)

test("an active enchant", function()
    world()
    -- as read in game: the Thief's daggers enchanted with fire, NowElementType 1 on both hands
    local c = player{ right = weapon{ blunt = false, element = NONE }, infos = { info(LEFT, 1), info(RIGHT, 1) } }
    is(Weapon.read(c, 10), { phys = "Slash", enchant = "Fire" }, "a fire enchant")
    -- the right hand's entry, wherever it is in the array
    world()
    c = player{ right = weapon{ blunt = true, element = NONE }, infos = { info(RIGHT, 3), info(LEFT, 1) } }
    is(Weapon.read(c, 10), { phys = "Blow", enchant = "Thunder" }, "the right hand's entry first")
    -- isLeft() tells the hand when WeaponType cannot be read
    world()
    c = player{ right = weapon{ blunt = false, element = NONE },
                infos = { info(LEFT, 4, true), info(RIGHT, 2, true) } }
    is(Weapon.read(c, 10), { phys = "Slash", enchant = "Ice" }, "by isLeft()")
end)

test("the Spearhand", function()
    world()
    -- as read in game: the Mystic Spearhand's duospear, Job 7, no left weapon
    local c = player{ right = weapon{ blunt = false, element = NONE, job = 7 }, infos = no_enchant() }
    is(Weapon.read(c, 10), { phys = "Slash" }, "the duospear")
end)

test("a stale left-hand entry gives no enchant", function()
    world()
    -- the watcher at 20:39:13: the enchant is over, the right hand's entry is -1, the left's still 1 (no left weapon)
    local c = player{ right = weapon{ blunt = false, element = NONE, job = 7 },
                      infos = { info(LEFT, 1), info(RIGHT, NONE) } }
    is(Weapon.read(c, 10), { phys = "Slash" }, "the left hand's 1 is not read")
    world()
    c = player{ right = weapon{ blunt = false, element = NONE }, infos = { info(LEFT, 1), info(RIGHT, 0) } }
    is(Weapon.read(c, 10), { phys = "Slash" }, "0 is no enchant either")
    -- no right hand's entry at all
    world()
    c = player{ right = weapon{ blunt = false, element = NONE }, infos = { info(LEFT, 1) } }
    is(Weapon.read(c, 10), { phys = "Slash" }, "only a left entry")
end)

test("an enchant of the weapon's own element is the weapon's", function()
    world()
    local c = player{ right = weapon{ blunt = false, element = 1 }, infos = { info(LEFT, NONE), info(RIGHT, 1) } }
    is(Weapon.read(c, 10), { phys = "Slash", element = "Fire" }, "fire on a fire weapon")
    world()
    c = player{ right = weapon{ blunt = false, element = 2 }, infos = { info(LEFT, NONE), info(RIGHT, 1) } }
    is(Weapon.read(c, 10), { phys = "Slash", element = "Ice", enchant = "Fire" }, "fire on an ice weapon")
end)

test("no controller: the weapon without an enchant", function()
    world()
    is(Weapon.read(player{ right = weapon{ blunt = true, element = NONE } }, 10), { phys = "Blow" }, "no controller")
    world()
    local c = player{ right = weapon{ blunt = true, element = NONE }, infos = no_enchant() }
    c.methods.get_WeaponElementController = function() error("boom") end
    is(Weapon.read(c, 10), { phys = "Blow" }, "a controller that raises")
end)

test("read once a second", function()
    world()
    local o = { right = weapon{ blunt = false, element = NONE }, infos = { info(LEFT, NONE), info(RIGHT, 1) } }
    local c = player(o)
    local w1 = Weapon.read(c, 10)
    eq(reads(), 1, "the first read")
    o.right = weapon{ blunt = true, element = NONE }   -- a weapon swap: seen at the next read
    eq(Weapon.read(c, 10.5), w1, "half a second later: the same answer")
    eq(reads(), 1, "one game read")
    local w2 = Weapon.read(c, 11.0)
    eq(reads(), 2, "a second later: read again")
    is(w2, { phys = "Blow", enchant = "Fire" }, "the new weapon")
    eq(Weapon.read(c, 11.9), w2, "the last answer in between")
    eq(reads(), 2, "still two reads")
    -- a clock that went back reads again
    Weapon.read(c, 5)
    eq(reads(), 3, "an earlier t")
end)

test("no weapon in either hand gives nil", function()
    world()
    eq(Weapon.read(player{ infos = { info(LEFT, 1), info(RIGHT, 1) } }, 10), nil, "no weapon")
    eq(reads(), 1, "the right hand was asked")
    eq(#R.calls_of("get_LeftWeapon"), 1, "then the left")
    -- IsBlunt that cannot be read, on a vocation that does not tell: no type, no answer
    world()
    eq(Weapon.read(player{ right = weapon{ blunt = nil, element = 1 }, infos = no_enchant() }, 10), nil, "no IsBlunt")
    -- a character that raises
    world()
    local c = player{ right = weapon{ blunt = true, element = NONE }, infos = no_enchant() }
    c.poison = true
    eq(Weapon.read(c, 10), nil, "a poisoned character")
    -- after a good read, the weapon gone: nil once read again, and nil in between
    world()
    local o = { right = weapon{ blunt = true, element = NONE }, infos = no_enchant() }
    c = player(o)
    is(Weapon.read(c, 10), { phys = "Blow" }, "a good read")
    o.right = nil
    eq(Weapon.read(c, 11), nil, "the weapon is gone")
    eq(Weapon.read(c, 11.5), nil, "nil in between")
    eq(reads(), 2, "the failed read waits its second too")
    o.right = weapon{ blunt = false, element = NONE }
    is(Weapon.read(c, 12), { phys = "Slash" }, "a weapon again")
end)

test("no character or no time", function()
    world()
    local c = player{ right = weapon{ blunt = true, element = NONE }, infos = no_enchant() }
    eq(Weapon.read(nil, 10), nil, "no character")
    eq(Weapon.read(c, nil), nil, "no time, nothing read yet")
    eq(Weapon.read(c, 0 / 0), nil, "NaN")
    eq(#R.calls, 0, "nothing was read")
    local w = Weapon.read(c, 10)
    eq(Weapon.read(c, nil), w, "no time: the last answer")
    eq(Weapon.read(nil, 20), nil, "no character: nil")
    eq(reads(), 1, "and nothing read")
    eq(Weapon.read(c, 10.5), w, "the last answer is kept")
end)

test("Weapon.peek reads now and keeps nothing; Weapon.now_element is a hand's NowElementType", function()
    world()
    local o = { right = weapon{ blunt = false, element = NONE }, infos = { info(LEFT, 3), info(RIGHT, 1) } }
    local c = player(o)
    local w = Weapon.read(c, 10)
    o.right = weapon{ blunt = true, element = 2 }   -- a weapon swap
    is(Weapon.peek(c), { phys = "Blow", element = "Ice", enchant = "Fire" }, "the swap, read now")
    eq(Weapon.read(c, 10.5), w, "Weapon.read's last answer untouched")
    eq(reads(), 2, "one read each")
    eq(Weapon.peek(nil), nil, "no character")
    eq(Weapon.now_element(c, RIGHT), 1, "the right hand's raw value"); eq(Weapon.now_element(c, LEFT), 3, "the left's")
    c = player{ right = weapon{ blunt = false, element = NONE },
                infos = { info(RIGHT, NONE, true), info(LEFT, 5, true) } }
    eq(Weapon.now_element(c, RIGHT), NONE, "-1, by isLeft()"); eq(Weapon.now_element(c, LEFT), 5, "Dark, by isLeft()")
    eq(Weapon.now_element(player{ right = weapon{ blunt = true, element = NONE } }, RIGHT), nil, "no controller")
    eq(Weapon.now_element(nil, RIGHT), nil, "no character")
end)

test("reset forgets", function()
    world()
    local c = player{ right = weapon{ blunt = true, element = NONE }, infos = no_enchant() }
    local w = Weapon.read(c, 10)
    Weapon.reset()
    eq(Weapon.read(c, nil), nil, "no last answer")
    local w2 = Weapon.read(c, 10)
    eq(reads(), 2, "read again at once")
    eq(w2 ~= w, true, "a new answer")
    eq(w.phys, "Blow", "the old one is untouched")
end)

T.finish()
