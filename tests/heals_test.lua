package.path = "mod/reframework/autorun/?.lua;tests/?.lua;" .. package.path

local T = require("testlib")
local test, eq, near = T.test, T.eq, T.near
local R = require("stubs/reframework")
local names_game = require("DD2DamageMeter/game/names_game")
local actors = require("DD2DamageMeter/game/actors")
local Attrib = require("DD2DamageMeter/attrib")
local Fight = require("DD2DamageMeter/fight")
local heals = require("DD2DamageMeter/game/heals")

local STATIC = { static = true }
local HC, IM = "app.HitController", "app.ItemManager"
local SIG = {
    recoverHp = "recoverHp(System.Single, System.Boolean, System.Int32, System.Boolean)",
    full = "recoverHpAndMaxHpCompletely(System.Boolean)",
    useItem = "useItem(System.Int32, app.Character, app.Character)",
    useItemSub = "useItemSub(app.Character, app.Character, app.ItemDataParam, System.Boolean)",
    convert = "convertHealHp(System.Single, app.Character, app.CharacterID, app.ItemIDEnum, System.Boolean)",
}

-- A party as seen in game; each character has a HitController (`hc`) with the same HP.
local W

local function char(go, o)
    o = o or {}
    local c = R.character{ go = go, hp = o.hp or 1000, max_hp = o.max_hp or 2000, chara_id = o.chara_id }
    W.names[c] = o.name
    c.methods["isHostile(app.Character)"] = function() return o.hostile == true end
    c.hc = R.object(HC, {}, {
        get_Hp = function() return c.hp end,
        get_CachedCharacter = function() return c end,
    })
    return c
end

local function world()
    R.new()
    DD2DM_HOOKS = nil
    names_game.reset()
    actors.reset()
    heals.reset()
    W = { names = {}, t = 20.0, frame = 100 }
    R.method("app.GUIBase", "getName(app.Character)", function(c) return W.names[c] end, STATIC)
    R.method(HC, SIG.recoverHp, function() end)
    R.method(HC, SIG.full, function() end)
    R.method(IM, SIG.useItem, function() return true end)
    R.method(IM, SIG.useItemSub, function() end)
    R.method(IM, "eatItem(System.Int32, app.Character, app.Character)", function() return true end)
    R.method(IM, SIG.convert, function(amount) return math.floor(amount) end, STATIC)
    R.method("app.Character", "recoverAll", function() end)
    R.method("app.Character", "reviveFromFallDead(System.Boolean)", function() end)
    W.im = R.object(IM)

    W.player = char("ch000000_00", { name = "Guts", chara_id = 2891076981, hp = 1913.991, max_hp = 2400 })
    W.casca = char("ch100000_00", { name = "Casca", chara_id = 2283028347, hp = 224.4405, max_hp = 1800 })
    W.yves = char("ch111002", { name = "Yves", chara_id = 112032848 })
    W.pawns = { W.casca, W.yves }
    R.singleton("app.CharacterManager", R.object("app.CharacterManager", {}, {
        get_ManualPlayer = function() return W.player end,
    }))
    R.singleton("app.PawnManager", R.object("app.PawnManager", {}, {
        get_PawnCharacterList = function() return R.list(W.pawns) end,
    }))
    W.goblin = char("ch220003_00_15", { name = "Живодёр", hostile = true })
    W.stranger = char("ch111003", { name = "Ada" })
    actors.refresh()
    return W
end

local function new_sink()
    local s = { heals = {} }
    s.now = function() return W.t end
    s.frame = function() return W.frame end
    s.heal = function(h) s.heals[#s.heals + 1] = h end
    return s
end

local function hook(type_name, name)
    local hk = R.hook_of(type_name, name)
    assert(hk, "not hooked: " .. type_name .. "." .. name)
    return hk
end

local function slot(o) return R.obj_slot(o) end

-- HitController.recoverHp(amount, false, 0, false) on `c`, whose HP becomes `hp1`.
local function recover(c, amount, hp1)
    R.enter(hook(HC, "recoverHp"), { R.CTX, slot(c.hc), R.f32_slot(amount), R.int_slot(0), R.int_slot(0),
        R.int_slot(0) })
    c.hp = hp1
    return R.leave(nil)
end

-- ItemManager.useItem(id, user, target) around ItemManager.convertHealHp and the recoverHp it leads to
-- (as logged in game: useItem > useItemSub > convertHealHp, then recoverHp; useItemSub is not hooked).
local function use_item(id, user, target, requested, hp1)
    R.enter(hook(IM, "useItem"), { R.CTX, slot(W.im), R.int_slot(id), slot(user), target and slot(target) or R.null_slot() })
    local healed = target or user
    if requested then
        R.fire(hook(IM, "convertHealHp"), { R.CTX, R.f32_slot(requested), slot(healed), R.int_slot(healed.chara_id or 0),
            R.int_slot(id), R.int_slot(0) }, R.int_slot(requested))
    end
    recover(healed, requested or 100, hp1)
    return R.leave(true)
end

test("item use: 550 requested, 230.9 effective, item 38, user = target = player", function()
    world()
    local s = new_sink()
    heals.install(s, Attrib.new())
    heals.poll(W.frame, W.t)
    eq(use_item(38, W.player, nil, 550, 2144.926), true, "useItem's own result is returned")
    eq(#s.heals, 1, "one heal")
    local h = s.heals[1]
    local pl = actors.of(W.player)
    eq(h.target, pl, "target: the player")
    eq(h.healer, pl, "healer: the user")
    eq(h.amount, 550, "requested amount from convertHealHp")
    near(h.effective, 230.935, 1e-6, "effective = hp1 - hp0")
    eq(h.source.kind, "item", "item")
    eq(h.source.item_id, 38, "item id")
    eq(math.type(h.source.item_id), "integer", "an integer, not 38.0")
    eq(h.t, 20.0, "time")
    -- the poll sees the rise already explained
    W.frame = W.frame + 1
    heals.poll(W.frame, W.t)
    eq(#s.heals, 1, "not counted twice by the HP poll")
    -- into a fight: the heal of the item's user
    local f = Fight.new(0)
    f:add_heal(h)
    near(f:snapshot(1).actors[pl.key].heal_sources["item:38"], 230.935, 1e-6, "Guts (pills)")
    eq(#R.bad, 0, "no slot read with the wrong kind")
end)

test("useItem and useItemSub do not double count", function()
    world()
    local s = new_sink()
    local n = heals.install(s, Attrib.new())
    eq(R.hook_of(IM, "useItemSub"), nil, "useItemSub is not hooked")
    eq(R.hook_of(IM, "eatItem"), nil, "eatItem is not hooked")
    eq(n, 3, "recoverHp, useItem, convertHealHp")
    -- Casca uses a panacea on herself: 1000 requested, 1000 healed
    use_item(67, W.casca, W.casca, 1000, 1224.4405)
    eq(#s.heals, 1, "one heal for one item")
    local h = s.heals[1]
    eq(h.healer, actors.of(W.casca), "the pawn used it")
    eq(h.target, actors.of(W.casca), "on herself")
    near(h.effective, 1000, 1e-9, "effective")
    eq(h.source.item_id, 67, "panacea")
    -- the player gives Yves an item without a convertHealHp step: the requested amount is recoverHp's own
    use_item(1, W.player, W.yves, nil, 1100)
    eq(#s.heals, 2, "second item")
    eq(s.heals[2].healer, actors.of(W.player), "user")
    eq(s.heals[2].target, actors.of(W.yves), "target")
    eq(s.heals[2].amount, 100, "recoverHp's amount")
    -- after useItem ended, a heal on the same character is no item heal
    recover(W.casca, 5, 1229.4405)
    eq(s.heals[3].source.kind, "other", "the scope is closed")
end)

test("recoverHp inside a healing-spot window credits the mage", function()
    world()
    local attrib = Attrib.new()
    local s = new_sink()
    heals.install(s, attrib)
    local yves, pl = actors.of(W.yves), actors.of(W.player)
    attrib:touch(100, yves, pl.key, { attack = "ヒーリングスポット" })
    W.frame = 102
    W.player.hp = 1000
    recover(W.player, 1.5, 1001.5)
    eq(#s.heals, 1, "one heal")
    local h = s.heals[1]
    eq(h.healer, yves, "the heal area's owner")
    eq(h.target, pl, "target")
    eq(h.source.kind, "skill", "skill")
    eq(h.source.name, "ヒーリングスポット", "the area's attack name")
    near(h.amount, 1.5, 1e-9, "amount"); near(h.effective, 1.5, 1e-9, "effective")
    -- 4 frames after the touch: nobody to credit
    W.frame = 104
    recover(W.player, 1.5, 1003)
    eq(s.heals[2].healer, nil, "outside the window")
    eq(s.heals[2].source.kind, "other", "other")
    -- a heal capped by full HP is no heal
    recover(W.player, 1.5, 1003)
    eq(#s.heals, 2, "nothing healed")
end)

-- The healing spot goes on healing for about 4 s after its last touch (measured in game); 6 s are credited.
test("a heal that goes on after the spot's last touch credits the mage for 6 s", function()
    world()
    local attrib = Attrib.new()
    local s = new_sink()
    heals.install(s, attrib)
    local yves, pl = actors.of(W.yves), actors.of(W.player)
    attrib:touch(100, yves, pl.key, { attack = "ヒーリングスポット" }, 20.0)
    W.frame, W.t = 330, 24.0
    W.player.hp = 1000
    recover(W.player, 1.5, 1001.5)
    local h = s.heals[1]
    eq(h.healer, yves, "4 s and 230 frames after the last touch: the mage")
    eq(h.source.kind, "skill", "her skill")
    eq(h.source.name, "ヒーリングスポット", "the area's attack name")
    near(h.effective, 1.5, 1e-9, "effective")
    W.frame, W.t = 460, 26.0
    recover(W.player, 1.5, 1003)
    eq(s.heals[2].healer, yves, "6 s after: still the mage")
    W.frame, W.t = 470, 26.2
    recover(W.player, 1.5, 1004.5)
    eq(s.heals[3].healer, nil, "6.2 s after: nobody")
    eq(s.heals[3].source.kind, "other", "«other»")
end)

test("a 749 HP jump 2 s after the touch is «other»; a 1.5 HP tick, or the jump near the touch, the mage's", function()
    world()
    local attrib = Attrib.new()
    local s = new_sink()
    heals.install(s, attrib)
    local yves, pl = actors.of(W.yves), actors.of(W.player)
    attrib:touch(100, yves, pl.key, { attack = "ヒーリングスポット" }, 20.0)
    W.player.hp = 1000
    W.frame, W.t = 102, 20.03
    recover(W.player, 749, 1749)
    eq(s.heals[1].healer, yves, "749 HP within 3 frames: the mage, as before")
    W.player.hp = 1000
    W.frame, W.t = 240, 22.0
    recover(W.player, 749, 1749)
    eq(s.heals[2].healer, nil, "749 HP 2 s later: nobody")
    eq(s.heals[2].source.kind, "other", "«other»")
    near(s.heals[2].effective, 749, 1e-9, "the whole jump")
    W.frame, W.t = 241, 22.02
    recover(W.player, 1.5, 1750.5)
    eq(s.heals[3].healer, yves, "a 1.5 HP tick 2 s later: the mage")
end)

test("the 50 HP cap is on the HP really gained, not on the amount asked for", function()
    world()
    local attrib = Attrib.new()
    local s = new_sink()
    heals.install(s, attrib)
    local yves, pl = actors.of(W.yves), actors.of(W.player)
    attrib:touch(100, yves, pl.key, { attack = "ヒーリングスポット" }, 20.0)
    W.player.hp = 1000
    W.frame, W.t = 240, 22.0
    recover(W.player, 100, 1001.5)
    eq(s.heals[1].healer, yves, "100 asked, 1.5 gained 2 s later: the mage")
    near(s.heals[1].amount, 100, 1e-9, "the amount asked for")
    near(s.heals[1].effective, 1.5, 1e-9, "the HP gained")
end)

test("a lingering heal goes to the healer whose spot touched the target last", function()
    world()
    local attrib = Attrib.new()
    local s = new_sink()
    heals.install(s, attrib)
    local yves, ada, pl = actors.of(W.yves), actors.of(W.stranger), actors.of(W.player)
    attrib:touch(100, yves, pl.key, { attack = "ヒーリングスポット" }, 20.0)
    attrib:touch(110, ada, pl.key, { attack = "ヒーリングスポット_大" }, 20.2)
    W.frame, W.t = 300, 23.0
    recover(W.player, 1.5, W.player.hp + 1.5)
    eq(s.heals[1].healer, ada, "the latest toucher")
    eq(s.heals[1].source.name, "ヒーリングスポット_大", "her spot")
end)

test("inside the lingering window an item stays the item's and a polled rise stays «other»", function()
    world()
    local attrib = Attrib.new()
    local s = new_sink()
    heals.install(s, attrib)
    local yves, pl = actors.of(W.yves), actors.of(W.player)
    attrib:touch(100, yves, pl.key, { attack = "ヒーリングスポット" }, 20.0)
    W.frame, W.t = 200, 21.5
    heals.poll(W.frame, W.t)
    -- 40 HP 1.5 s after the touch: small enough to linger, but it is the item's
    use_item(38, W.player, nil, 550, W.player.hp + 40)
    eq(s.heals[1].healer, pl, "the item's user")
    eq(s.heals[1].source.kind, "item", "an item heal")
    near(s.heals[1].effective, 40, 1e-9, "40 HP")
    -- a rise the poll sees with no heal call since the last poll
    W.frame, W.t = 201, 21.52
    heals.poll(W.frame, W.t)
    W.player.hp = W.player.hp + 40
    W.frame, W.t = 202, 21.54
    heals.poll(W.frame, W.t)
    eq(#s.heals, 2, "the poll's heal")
    eq(s.heals[2].healer, nil, "nobody")
    eq(s.heals[2].source.kind, "other", "«other»")
end)

test("full restore is not a heal", function()
    world()
    local s = new_sink()
    heals.install(s, Attrib.new())
    eq(R.hook_of(HC, "recoverHpAndMaxHpCompletely"), nil, "full restore not hooked")
    eq(R.hook_of("app.Character", "recoverAll"), nil, "recoverAll not hooked")
    eq(R.hook_of("app.Character", "reviveFromFallDead"), nil, "revive not hooked")
    heals.poll(1, 1.0)
    -- an inn rest / NPC spawn: straight to full HP without a heal call
    W.player.hp = 2400
    heals.poll(2, 1.1)
    eq(#s.heals, 0, "a jump to full HP is a restore")
    -- a revive from 0
    W.casca.hp = 0
    heals.poll(3, 1.2)
    W.casca.hp = 300
    heals.poll(4, 1.3)
    eq(#s.heals, 0, "a revive is not a heal")
    -- not even when it runs through recoverHp
    W.yves.hp = 0
    heals.poll(5, 1.4)
    recover(W.yves, 500, 500)
    heals.poll(6, 1.5)
    eq(#s.heals, 0, "recoverHp from 0 HP is a revive")
end)

test("unexplained party HP rise is an \"other\" heal", function()
    world()
    local s = new_sink()
    heals.install(s, Attrib.new())
    W.player.hp = 1000
    heals.poll(1, 1.0)
    W.player.hp = 1100
    heals.poll(2, 1.5)
    eq(#s.heals, 1, "one heal")
    local h = s.heals[1]
    eq(h.target, actors.of(W.player), "target")
    eq(h.healer, nil, "nobody")
    eq(h.source.kind, "other", "other")
    near(h.amount, 100, 1e-9, "amount"); near(h.effective, 100, 1e-9, "effective")
    eq(h.t, 1.5, "time of the poll")
    heals.poll(3, 1.6)
    eq(#s.heals, 1, "no change, no heal")
    W.player.hp = 900
    heals.poll(4, 1.7)
    eq(#s.heals, 1, "a drop is no heal")
    -- a rise explained by recoverHp since the last poll is counted once, by the hook
    recover(W.player, 50, 950)
    heals.poll(5, 1.8)
    eq(#s.heals, 2, "only the hook's heal")
    eq(s.heals[2].source.kind, "other", "unattributed recoverHp")
    -- into a fight: the «other» pseudo-actor
    local f = Fight.new(0)
    f:add_heal(h)
    near(f:snapshot(2).actors.other.heal_done, 100, 1e-9, "other heal_done")
end)

-- The game can make a new character object for a party member; his actor stays, his HP is polled anew.
test("the HP poll starts afresh on a member's new character object; his heals stay his", function()
    world()
    local s = new_sink()
    heals.install(s, Attrib.new())
    local casca = actors.of(W.casca)
    heals.poll(1, 1.0)
    -- Casca made anew, with more HP than her old object had at the last poll
    local old = W.casca
    local new = char("ch100000_00", { name = "Casca", chara_id = old.chara_id, hp = 900, max_hp = 1800 })
    W.pawns = { new, W.yves }
    actors.refresh()
    eq(actors.of(new), casca, "her actor")
    heals.poll(2, 1.1)
    eq(#s.heals, 0, "the new object's first poll is no heal")
    new.hp = 1000
    heals.poll(3, 1.2)
    eq(#s.heals, 1, "a rise on the new object is a heal")
    eq(s.heals[1].target, casca, "hers"); near(s.heals[1].effective, 100, 1e-9, "the rise")
    -- recoverHp on the new object or on the old one: hers
    recover(new, 50, 1050)
    recover(old, 20, old.hp + 20)
    eq(#s.heals, 3, "two heals")
    eq(s.heals[2].target, casca, "on the new object"); eq(s.heals[3].target, casca, "on the old one")
    heals.poll(4, 1.3)
    eq(#s.heals, 3, "explained: no polled heal")
end)

-- The mage's Argent Tonic («Серебряный тоник», Job03_FullRecover) heals the party as her state ends (logged in
-- game: the heal landed in the frame her state was last seen); `state` gives `c` that skill state.
local FULL_RECOVER, FIRESTORM = 210, 24
local function human_of(c)
    if c.human == nil then
        c.human = R.object("app.Human", { ["<CustomSkillState>k__BackingField"] = 0 }, {})
        c.methods.get_Human = function() return c.human end
    end
    return c.human
end
local function state(c, value) human_of(c).fields["<CustomSkillState>k__BackingField"] = value end
local function skills()
    R.enum("app.HumanCustomSkillID", { None = 0, Job03_Firestorm = FIRESTORM, Job03_FullRecover = FULL_RECOVER })
    names_game.reset()
    for _, c in ipairs({ W.player, W.casca, W.yves }) do human_of(c) end
    actors.refresh()
end

test("Argent Tonic: a heal with no other source 0-10 frames after the mage's state is hers, 11 frames after nobody's",
        function()
    world()
    skills()
    local s = new_sink()
    heals.install(s, Attrib.new())
    local casca, pl = actors.of(W.casca), actors.of(W.player)
    state(W.casca, FULL_RECOVER)
    heals.sample(100)
    heals.sample(101)
    state(W.casca, 0)
    heals.sample(102)
    W.frame, W.player.hp = 101, 1000
    recover(W.player, 1400, 2400)        -- in her last frame in the state
    W.frame, W.player.hp = 111, 1000
    recover(W.player, 1400, 2400)        -- 10 frames after it
    W.frame, W.player.hp = 112, 1000
    recover(W.player, 1400, 2400)        -- 11 frames after it
    eq(s.heals[1].healer, casca, "her last frame: the mage")
    eq(s.heals[1].source.kind, "skill", "a skill heal"); eq(s.heals[1].source.id, "Job03_FullRecover", "Argent Tonic")
    eq(s.heals[1].source.name, nil, "no attack name")
    eq(s.heals[2].healer, casca, "10 frames after: still hers")
    eq(s.heals[3].healer, nil, "11 frames after: nobody"); eq(s.heals[3].source.kind, "other", "«other»")
    eq(s.heals[1].target, pl, "on the player")
    -- into a fight: her healing, by the skill
    local f = Fight.new(0)
    f:add_heal(s.heals[1])
    local snap = f:snapshot(1, true)
    near(snap.actors[casca.key].heal_done, 1400, 1e-6, "Casca healed")
    near(snap.actors[casca.key].heal_sources.skill, 1400, 1e-6, "with a skill")
    eq(snap.detail.heals[casca.key][pl.key]["skill_id:Job03_FullRecover"].n, 1, "the detail names the skill")
end)

test("Argent Tonic: another skill's state is none; the latest cast counts; allies, items, the spot and the poll",
        function()
    world()
    skills()
    local attrib = Attrib.new()
    local s = new_sink()
    heals.install(s, attrib)
    local casca, yves, pl = actors.of(W.casca), actors.of(W.yves), actors.of(W.player)
    -- another member in another skill's state: no heal skill
    state(W.yves, FIRESTORM)
    heals.sample(100)
    W.frame, W.player.hp = 100, 1000
    recover(W.player, 50, 1050)
    eq(s.heals[1].healer, nil, "Firestorm heals nobody"); eq(s.heals[1].source.kind, "other", "«other»")
    -- two casters: the latest
    state(W.casca, FULL_RECOVER)
    heals.sample(101)
    state(W.casca, 0)
    state(W.yves, FULL_RECOVER)
    heals.sample(105)
    state(W.yves, 0)
    W.frame = 106
    recover(W.player, 50, 1100)
    eq(s.heals[2].healer, yves, "the latest caster")
    -- an ally is healed by it too
    actors.mark_fighting(actors.of(W.stranger))
    recover(W.stranger, 100, W.stranger.hp + 100)
    eq(s.heals[3].healer, yves, "an ally"); eq(s.heals[3].target, actors.of(W.stranger), "the ally")
    -- an item and the healing spot keep their heals
    use_item(38, W.player, nil, 550, W.player.hp + 300)
    eq(s.heals[4].source.kind, "item", "the item's"); eq(s.heals[4].healer, pl, "its user")
    attrib:touch(106, casca, pl.key, { attack = "ヒーリングスポット" })
    recover(W.player, 1.5, W.player.hp + 1.5)
    eq(s.heals[5].healer, casca, "the spot's"); eq(s.heals[5].source.name, "ヒーリングスポット", "by its touch")
    -- a rise the poll sees with no heal call
    heals.poll(106, 20)
    W.player.hp = W.player.hp + 40
    heals.poll(107, 20.02)
    eq(s.heals[6].healer, yves, "the poll's rise: hers"); eq(s.heals[6].source.id, "Job03_FullRecover", "the skill")
    -- 5 frames after the latest cast, past the spot's touch: hers; after a reset: nobody's
    W.frame = 110
    recover(W.player, 50, W.player.hp + 50)
    eq(s.heals[7].healer, yves, "5 frames after her cast")
    heals.reset()
    recover(W.player, 50, W.player.hp + 50)
    eq(s.heals[8].healer, nil, "a reset forgets the casts")
end)

test("Argent Tonic: sampling reads one field per party member, the Human once per party read", function()
    world()
    skills()
    heals.install(new_sink(), Attrib.new())
    local reads = 0
    for _, c in ipairs({ W.player, W.casca, W.yves }) do
        local h = human_of(c)
        local value = h.fields["<CustomSkillState>k__BackingField"]
        h.fields["<CustomSkillState>k__BackingField"] = nil
        setmetatable(h.fields, { __index = function(_, k)
            if k == "<CustomSkillState>k__BackingField" then reads = reads + 1; return value end
        end })
    end
    local humans = #R.calls_of("get_Human")
    for frame = 1, 10 do heals.sample(frame) end
    eq(reads, 30, "three members, ten frames: one read each per frame")
    eq(#R.calls_of("get_Human") - humans, 3, "the Human once per member")
end)

-- The game calls made on `obj` from call number `from` on.
local function asked_since(obj, from)
    local n = 0
    for i = from + 1, #R.calls do
        if R.calls[i].this == obj then n = n + 1 end
    end
    return n
end

test("the HP poll and the skill states read only the characters the game lists now; none without a player",
        function()
    world()
    skills()
    local s = new_sink()
    heals.install(s, Attrib.new())
    W.player.hp = 1000
    heals.poll(1, 1.0)
    heals.sample(1)
    -- the game drops Casca's object before the next party read (a scene change destroying it): never asked again
    local casca_char, from = W.casca, #R.calls
    W.pawns = { W.yves }
    casca_char.methods.get_Hp = function() error("a destroyed object") end
    for frame = 2, 5 do
        heals.sample(frame)
        heals.poll(frame, 1.0 + frame / 100)
    end
    eq(asked_since(casca_char, from), 0, "Casca's kept object not asked")
    eq(asked_since(casca_char.human, from), 0, "nor her Human")
    eq(asked_since(W.player, from) > 0, true, "the player still polled")
    -- no player character: the world is going, nobody is asked, the pawns the game still lists included
    local player = W.player
    W.player = nil
    from = #R.calls
    W.yves.hp = W.yves.hp + 100
    for frame = 6, 8 do
        heals.sample(frame)
        heals.poll(frame, 1.0 + frame / 100)
    end
    eq(asked_since(player, from), 0, "the player's kept object not asked")
    eq(asked_since(W.yves, from), 0, "nor a pawn the game still lists")
    eq(#s.heals, 0, "no heal")
    -- the world back: polled afresh, a rise across the gap is no heal
    W.player = player
    player.hp = 1500
    heals.poll(9, 1.2)
    eq(#s.heals, 0, "the first poll after the gap is no heal")
    player.hp = 1600
    heals.poll(10, 1.3)
    eq(#s.heals, 1, "a rise after it is"); near(s.heals[1].effective, 100, 1e-9, "the rise")
end)

test("the poll and the sampling take the frame's party listing when given, and read none of their own",
        function()
    world()
    skills()
    local s = new_sink()
    heals.install(s, Attrib.new())
    local now = actors.listed()
    local players, lists = #R.calls_of("get_ManualPlayer"), #R.calls_of("get_PawnCharacterList")
    W.player.hp = 1000
    heals.sample(1, now)
    heals.poll(1, 1.0, now)
    W.player.hp = 1100
    heals.poll(2, 1.1, now)
    eq(#R.calls_of("get_ManualPlayer"), players, "the player not read again")
    eq(#R.calls_of("get_PawnCharacterList"), lists, "nor the pawn list")
    eq(#s.heals, 1, "the rise is a heal"); eq(s.heals[1].target, actors.of(W.player), "his")
    -- the listing says who is there: a member it does not list is not asked
    local from = #R.calls
    heals.poll(3, 1.2, { [W.player:get_address()] = W.player })
    eq(asked_since(W.casca, from), 0, "Casca not in the listing: not asked")
    eq(asked_since(W.player, from) > 0, true, "the player polled")
    heals.poll(4, 1.3, {})
    heals.sample(4, {})
    eq(#s.heals, 1, "an empty listing: nobody, no heal")
end)

test("heals of enemies and strangers are not the party's", function()
    world()
    local attrib = Attrib.new()
    local s = new_sink()
    heals.install(s, attrib)
    attrib:touch(100, actors.of(W.yves), actors.of(W.stranger).key, { attack = "ヒーリングスポット" })
    recover(W.stranger, 1.5, 1001.5)
    recover(W.goblin, 50, 1050)
    eq(#s.heals, 0, "no heal")
    -- an ally is healed like the party
    local stranger = actors.of(W.stranger)
    actors.mark_fighting(stranger)
    recover(W.stranger, 1.5, 1003)
    eq(#s.heals, 1, "an ally's heal")
    eq(s.heals[1].healer, actors.of(W.yves), "credited")
end)

test("heal hooks return retval and never raise", function()
    world()
    local s = new_sink()
    s.heal = function() error("sink broken") end
    heals.install(s, Attrib.new())
    eq(use_item(38, W.player, nil, 550, 2144.926), true, "useItem retval")
    for _, hk in ipairs(R.hooks) do
        for _, args in ipairs({ { R.CTX }, {}, { R.CTX, R.int_slot(1), R.f32_slot(2), R.int_slot(3), R.int_slot(4),
            R.int_slot(5) }, { R.CTX, R.null_slot(), R.null_slot(), R.null_slot(), R.null_slot(), R.null_slot() } }) do
            local pre_ret = "unset"
            R.enter({ pre = function(a) pre_ret = hk.pre(a) end, post = function(r) return hk.post(r) end }, args)
            eq(R.leave("x"), "x", hk.m.sig .. " retval")
            eq(pre_ret, nil, hk.m.sig .. ": the pre-hook never asks to skip the original")
        end
    end
    -- a broken party list does not break the poll
    R.singleton("app.PawnManager", R.object("app.PawnManager", {}, { get_PawnCharacterList = function() error("x") end }))
    actors.refresh()
    heals.poll(1, 1.0)
    W.player.methods.get_Hp = function() error("boom") end
    heals.poll(2, 1.1)
    -- an attrib that raises
    local bad = setmetatable({}, { __index = function() error("attrib broken") end })
    heals.install(new_sink(), bad)
    W.player.methods.get_Hp = nil
    eq(recover(W.casca, 1, 300), nil, "recoverHp with a broken attrib")
end)

test("heal hook count within budget, reload-safe", function()
    world()
    local n, missing = heals.install(new_sink(), Attrib.new())
    eq(n, 3, "three hooks")
    assert(n <= 4, "heals budget")
    eq(#missing, 0, "nothing missing")
    local fresh = new_sink()
    eq(heals.install(fresh, Attrib.new()), 3, "reload")
    eq(#R.hooks, 3, "no hook installed twice")
    use_item(38, W.player, nil, 550, 2144.926)
    eq(#fresh.heals, 1, "the new sink gets the heal")
    -- frames without a sink clock: the last poll's frame and time
    local attrib = Attrib.new()
    local plain = { heals = {} }
    plain.heal = function(h) plain.heals[#plain.heals + 1] = h end
    heals.install(plain, attrib)
    heals.poll(500, 42.0)
    attrib:touch(501, actors.of(W.yves), actors.of(W.casca).key, { attack = "ヒーリングスポット" })
    recover(W.casca, 2, W.casca.hp + 2)
    eq(plain.heals[1].t, 42.0, "time of the last poll")
    eq(plain.heals[1].healer, actors.of(W.yves), "frame of the last poll")
end)

test("an item scope whose useItem never ended does not outlive its frame", function()
    world()
    local attrib = Attrib.new()
    local s = new_sink()
    heals.install(s, attrib)
    -- useItem's post-hook is skipped (a game exception): the scope stays open
    W.frame = 300
    R.enter(hook(IM, "useItem"), { R.CTX, slot(W.im), R.int_slot(38), slot(W.player), R.null_slot() })
    -- inside the same frame the heal is still the item's (it is synchronous inside useItem)
    recover(W.player, 550, W.player.hp + 200)
    eq(s.heals[1].source.kind, "item", "same frame: item")
    -- the next frame too: the frame counter can tick between two hooks of one useItem
    W.frame = 301
    recover(W.player, 550, W.player.hp + 200)
    eq(s.heals[2].source.kind, "item", "next frame: item")
    -- the healing spot ticks on in later frames: no item heals
    attrib:touch(302, actors.of(W.yves), actors.of(W.player).key, { attack = "ヒーリングスポット" })
    W.frame = 302
    recover(W.player, 1.5, W.player.hp + 1.5)
    eq(s.heals[3].source.kind, "skill", "a later frame: the heal area")
    eq(s.heals[3].healer, actors.of(W.yves), "credited to the mage")
    eq(heals.info().scopes, 0, "the stale scope is dropped")
    W.frame = 303
    recover(W.player, 1.5, W.player.hp + 1.5)
    eq(s.heals[4].source.kind, "skill", "and stays dropped")
    -- a convertHealHp of a later frame does not write into the stale scope either
    W.frame = 400
    R.enter(hook(IM, "useItem"), { R.CTX, slot(W.im), R.int_slot(67), slot(W.casca), slot(W.casca) })
    W.frame = 402
    R.fire(hook(IM, "convertHealHp"), { R.CTX, R.f32_slot(1000), slot(W.casca), R.int_slot(0), R.int_slot(67),
        R.int_slot(0) }, R.int_slot(1000))
    recover(W.casca, 5, W.casca.hp + 5)
    eq(s.heals[5].source.kind, "other", "not an item heal")
    eq(s.heals[5].amount, 5, "recoverHp's own amount")
    eq(heals.info().scopes, 0, "dropped too")
end)

test("open item scopes stay bounded", function()
    world()
    heals.install(new_sink(), Attrib.new())
    for i = 1, 500 do
        local c = char("ch111" .. i, { name = "P" .. i })
        R.enter(hook(IM, "useItem"), { R.CTX, slot(W.im), R.int_slot(38), slot(c), R.null_slot() })
    end
    assert(heals.info().scopes <= 16, "scopes bounded: " .. heals.info().scopes)
    heals.reset()
    eq(heals.info().scopes, 0, "reset drops them")
end)

T.finish()
