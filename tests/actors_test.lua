package.path = "mod/reframework/autorun/?.lua;tests/?.lua;" .. package.path

local T = require("testlib")
local test, eq = T.test, T.eq
local R = require("stubs/reframework")
local names_game = require("DD2DamageMeter/game/names_game")
local actors = require("DD2DamageMeter/game/actors")

local STATIC = { static = true }

-- The party as read in the game (player ch000000_00, main pawn ch100000_00, two support pawns), the HUD names
-- of app.GUIBase.getName, and hostility as the game answers it. W.names maps a character to its HUD name.
local W

local function char(go, o)
    o = o or {}
    local c = R.character{ go = go, hp = o.hp or 1000, max_hp = o.max_hp or 1000, chara_id = o.chara_id }
    W.names[c] = o.name
    c.methods["isHostile(app.Character)"] = function() return o.hostile == true end
    return c
end

local function world()
    R.new()
    names_game.reset()
    actors.reset()
    W = { names = {}, relation = {} }
    R.method("app.GUIBase", "getName(app.Character)", function(c) return W.names[c] end, STATIC)
    W.player = char("ch000000_00", { name = "Guts", max_hp = 2000, hp = 1500 })
    W.player.methods["getBattleRelationshipTo(app.Character)"] = function(_, c) return W.relation[c] or 0 end
    W.pawns = {
        char("ch100000_00", { name = "Casca", max_hp = 1800 }),
        char("ch111007", { name = "Godwin" }),
        char("ch111002", { name = "Yves" }),
    }
    R.singleton("app.CharacterManager", R.object("app.CharacterManager", {}, {
        get_ManualPlayer = function() return W.player end,
    }))
    R.singleton("app.PawnManager", R.object("app.PawnManager", {}, {
        get_PawnCharacterList = function() return R.list(W.pawns) end,
    }))
    return W
end

-- The character Actors.present() gives for `actor` now, nil when it lists none for him.
local function present_char(actor)
    for _, m in ipairs(actors.present()) do
        if m.actor == actor then return m.character end
    end
    return nil
end

test("player and pawns get roles in order", function()
    world()
    actors.refresh()
    local p = actors.of(W.player)
    eq(p.kind, "player", "kind")
    eq(p.order, 0, "order")
    eq(p.name, "Guts", "name from GUIBase.getName")
    eq(p.key, "a" .. W.player:get_address(), "key is a + address")
    eq(p.max_hp, 2000, "max hp from get_OriginalMaxHp")
    for i, c in ipairs(W.pawns) do
        local a = actors.of(c)
        eq(a.kind, "pawn", "pawn " .. i)
        eq(a.order, i, "order " .. i)
        eq(a.key, "a" .. c:get_address(), "key " .. i)
    end
    eq(actors.of(W.pawns[2]).name, "Godwin", "pawn name")
    local party = actors.party()
    eq(#party, 4, "party size")
    eq(party[1], p, "player first")
    eq(party[2], actors.of(W.pawns[1]), "main pawn second")
    eq(party[4].name, "Yves", "last support pawn")
    eq(actors.of(W.player), p, "same table every time")
end)

test("a goblin is an enemy, a guard an ally", function()
    world()
    actors.refresh()
    local goblin = char("ch220003_00_15", { name = "Живодёр", hostile = true, max_hp = 3053 })
    local g = actors.of(goblin)
    eq(g.kind, "enemy", "hostile character")
    eq(g.name, "Живодёр", "name")
    eq(g.max_hp, 3053, "max hp")
    eq(g.order, nil, "enemies have no order")
    eq(actors.of(goblin), g, "cached")
    eq(#actors.party(), 4, "an enemy is not in the party")

    -- a guard: neutral to the player; an ally only once he is seen fighting an enemy
    local guard = char("ch300656_00_3", { name = "Форрест" })
    local f = actors.of(guard)
    eq(f.kind, "other", "not hostile and not seen fighting")
    actors.mark_fighting(f)
    eq(f.kind, "ally", "seen fighting")
    eq(actors.of(guard), f, "still the same actor")
    eq(actors.of(guard).kind, "ally", "stays an ally")

    -- marking never changes an enemy or a party member
    actors.mark_fighting(g)
    actors.mark_fighting(actors.of(W.player))
    eq(g.kind, "enemy", "enemy stays")
    eq(actors.of(W.player).kind, "player", "player stays")
    actors.mark_fighting(nil)
end)

test("a critter (full HP below 100) is never an enemy, a deer still is", function()
    world()
    actors.refresh()
    local chicken = char("ch280000_00_4", { name = "Курица", hostile = true, hp = 1, max_hp = 1 })
    local c = actors.of(chicken)
    eq(c.kind, "other", "a hostile chicken of 1 HP is neutral")
    actors.mark_fighting(c)
    eq(c.kind, "other", "and stays neutral when it is seen in a fight")
    eq(actors.of(chicken).kind, "other", "cached")
    eq(actors.of(char("ch280001_00_1", { hostile = true, max_hp = 99 })).kind, "other", "99 HP")
    eq(actors.of(char("ch280002_00_1", { hostile = true, max_hp = 100 })).kind, "enemy", "100 HP is an enemy")
    eq(actors.of(char("ch221001_00_1", { name = "Doe", hostile = true, hp = 250, max_hp = 250 })).kind, "enemy",
        "a deer of 250 HP")
    -- the full HP not known: hostility decides, as before
    local unread = char("ch280003_00_1", { hostile = true })
    unread.methods.get_OriginalMaxHp = function() error("boom") end
    eq(actors.of(unread).kind, "enemy", "no full HP read")
    eq(actors.of(char("ch280004_00_1", { hostile = true, max_hp = 0 })).kind, "enemy", "a full HP of 0 is none")
    -- a neutral critter that turns hostile stays neutral, and the game is not asked again
    local hen = char("ch280000_00_5", { name = "Курица", max_hp = 1 })
    eq(actors.of(hen).kind, "other", "neutral")
    hen.methods["isHostile(app.Character)"] = function() return true end
    local asked = #R.calls_of("isHostile(app.Character)")
    eq(actors.of(hen).kind, "other", "hostile now, still a critter")
    eq(#R.calls_of("isHostile(app.Character)"), asked, "no hostility asked for a critter")
end)

test("hostility: isHostile or a Hostile battle relationship", function()
    world()
    actors.refresh()
    -- the relationship says Hostile (1) although isHostile cannot be called
    local wolf = char("ch223001_00_8", { name = "Красный волк" })
    wolf.methods["isHostile(app.Character)"] = function() error("boom") end
    W.relation[wolf] = 1
    eq(actors.of(wolf).kind, "enemy", "relationship 1")
    -- Neutral 0 and Friend 2 are not enemies
    local townsman = char("ch300522_00_1", { name = "Клаудия" })
    W.relation[townsman] = 0
    eq(actors.of(townsman).kind, "other", "neutral")
    local friend = char("ch310068_00_1", { name = "Фульвио" })
    W.relation[friend] = 2
    eq(actors.of(friend).kind, "other", "friend")
    -- the question asked of the game: is the character hostile to the player
    local asked = R.calls_of("isHostile(app.Character)")
    eq(asked[#asked].args[1], W.player, "isHostile(player)")
end)

test("a character whose hostility is unknown is asked again", function()
    world()
    actors.refresh()
    local orc = char("ch225000_00_2", { name = "Орк" })
    orc.methods["isHostile(app.Character)"] = function() error("boom") end
    W.player.methods["getBattleRelationshipTo(app.Character)"] = function() error("boom") end
    eq(actors.of(orc).kind, "other", "both calls fail")
    orc.methods["isHostile(app.Character)"] = function() return true end
    eq(actors.of(orc).kind, "enemy", "hostile now")

    -- an NPC that starts a fight with the player turns into an enemy even after being marked
    local npc = char("ch300100_00_4", { name = "Страж" })
    local a = actors.of(npc)
    actors.mark_fighting(a)
    eq(a.kind, "ally", "marked")
    npc.methods["isHostile(app.Character)"] = function() return true end
    eq(actors.of(npc).kind, "enemy", "became hostile")
    eq(a.kind, "enemy", "same actor")
end)

test("without a player nothing is hostile yet", function()
    world()
    W.player = nil
    local goblin = char("ch220003_00_15", { name = "Живодёр", hostile = true })
    eq(actors.of(goblin).kind, "other", "no player to be hostile to")
    W.player = char("ch000000_00", { name = "Guts" })
    eq(actors.of(goblin).kind, "enemy", "player is back")
end)

test("base_id strips the instance number", function()
    world()
    actors.refresh()
    local cases = {
        { "ch220003_00_15", "ch220003_00" },
        { "ch254000_00_207", "ch254000_00" },
        { "ch221001_00_266", "ch221001_00" },
        { "ch253000_00_322", "ch253000_00" },
    }
    for _, case in ipairs(cases) do
        eq(actors.of(char(case[1], { hostile = true })).base_id, case[2], case[1])
    end
    eq(actors.of(char("Goblin", { hostile = true })).base_id, "Goblin", "no suffix, nothing to strip")
    -- the same kind of enemy shares a base id, the instances keep their own keys
    local a = actors.of(char("ch220003_00_1", { hostile = true }))
    local b = actors.of(char("ch220003_00_2", { hostile = true }))
    eq(a.base_id, b.base_id, "same kind")
    assert(a.key ~= b.key, "different instances, different keys")
end)

test("an unreadable game object gives a placeholder base id and the HUD name", function()
    world()
    actors.refresh()
    local c = char(nil, { name = "Химера", hostile = true })
    c.methods.get_GameObject = function() error("boom") end
    local a = actors.of(c)
    eq(a.base_id, "?", "placeholder")
    eq(a.name, "Химера", "name")
    eq(a.kind, "enemy", "kind")
end)

test("an enemy's name is remembered for its kind", function()
    world()
    actors.refresh()
    actors.of(char("ch254000_00_207", { name = "Химера", hostile = true }))
    local before = #R.calls
    eq(names_game.lookup().enemy("ch254000_00", "ru"), "Химера", "learned from the live character")
    eq(#R.calls, before, "no game call needed")
    -- a fallback (game object) name is not a display name and is not remembered
    local c = char("ch999000_00_1", { hostile = true })
    actors.of(c)
    eq(names_game.lookup().enemy("ch999000_00", "ru"), nil, "nothing learned")
end)

test("roster refresh keeps old actors", function()
    world()
    actors.refresh()
    local casca = actors.of(W.pawns[1])
    local godwin = actors.of(W.pawns[2])
    local old_yves = W.pawns[3]
    local yves = actors.of(old_yves)
    eq(yves.order, 3, "support pawn 2")

    -- Yves is dismissed and a new pawn is hired in the list's second place
    local newcomer = char("ch111010", { name = "Mercedes" })
    W.pawns = { W.pawns[1], newcomer, W.pawns[2] }
    actors.refresh()
    local n = actors.of(newcomer)
    eq(n.kind, "pawn", "new pawn")
    eq(n.order, 2, "new pawn takes the second place")
    eq(actors.of(W.pawns[1]), casca, "main pawn is the same actor")
    eq(actors.of(W.pawns[3]), godwin, "kept pawn is the same actor")
    eq(godwin.order, 3, "kept pawn moved down the list")

    -- Yves left the party, but what was counted for him keeps his name
    eq(yves.name, "Yves", "dismissed pawn keeps its name")
    eq(actors.of(old_yves), yves, "a late event of the dismissed pawn still resolves to his actor")
    eq(yves.kind, "other", "but he is no party member any more: classified as anybody else")
    eq(yves.order, nil, "and has no party order")
    local party = actors.party()
    eq(#party, 4, "party size")
    for _, a in ipairs(party) do assert(a ~= yves, "a dismissed pawn is not in the party") end
    eq(present_char(yves), nil, "no HP polling for a pawn that left")
end)

test("a dismissed pawn is reclassified by the normal rules", function()
    world()
    actors.refresh()
    local godwin = actors.of(W.pawns[2])
    local yves = actors.of(W.pawns[3])
    -- both leave; Godwin turns on the party (a stray pawn can), Yves is just a passer-by
    local old_godwin, old_yves = W.pawns[2], W.pawns[3]
    W.pawns = { W.pawns[1] }
    old_godwin.methods["isHostile(app.Character)"] = function() return true end
    actors.refresh()
    eq(godwin.kind, "pawn", "unchanged until he shows up again")
    eq(actors.of(old_godwin).kind, "enemy", "hostile: an enemy")
    eq(actors.of(old_yves).kind, "other", "neutral: other")
    actors.mark_fighting(yves)
    eq(actors.of(old_yves).kind, "ally", "an ally once seen fighting")
    -- hired again
    W.pawns = { W.pawns[1], old_yves }
    actors.refresh()
    eq(actors.of(old_yves), yves, "same actor")
    eq(yves.kind, "pawn", "a pawn again")
    eq(yves.order, 2, "with his new place")
    -- a pawn list that cannot be read is no reason to throw the pawns out
    R.singleton("app.PawnManager", R.object("app.PawnManager", {}, {
        get_PawnCharacterList = function() error("boom") end,
    }))
    actors.refresh()
    eq(actors.of(old_yves).kind, "pawn", "kept while the roster is unknown")
end)

test("by_chara_id finds party members and allies", function()
    world()
    W.player.chara_id = 2891076981
    W.pawns[1].chara_id = 2283028347
    W.pawns[3].chara_id = 112032848
    actors.refresh()
    eq(actors.by_chara_id(2891076981), actors.of(W.player), "player")
    eq(actors.by_chara_id(2283028347), actors.of(W.pawns[1]), "main pawn")
    eq(actors.by_chara_id(112032848), actors.of(W.pawns[3]), "support pawn")
    eq(actors.by_chara_id(2891076981.0), actors.of(W.player), "a float id")
    -- enemies share their kind's id, neutral characters are nobody's
    local goblin = char("ch220003_00_15", { name = "Живодёр", hostile = true, chara_id = 2774043831 })
    actors.of(goblin)
    eq(actors.by_chara_id(2774043831), nil, "not an enemy")
    local guard = char("ch300656_00_3", { name = "Форрест", chara_id = 300656 })
    local g = actors.of(guard)
    eq(actors.by_chara_id(300656), nil, "not a neutral character")
    actors.mark_fighting(g)
    eq(actors.by_chara_id(300656), g, "an ally")
    eq(actors.by_chara_id(1857826560), nil, "the nobody id")
    eq(actors.by_chara_id(nil), nil, "no id")
    eq(actors.by_chara_id("2891076981"), nil, "not a number")
    -- a party member whose id cannot be read
    W.pawns[2].methods.get_CharaID = function() error("boom") end
    actors.refresh()
    eq(actors.by_chara_id(0), nil, "nothing matches")
end)

test("actors carry chara_id", function()
    world()
    actors.refresh()
    local goblin = char("ch220001_50_1256", { name = "Hobgoblin", hostile = true, chara_id = 5201 })
    local g = actors.of(goblin)
    eq(g.chara_id, 5201, "an enemy's CharaID")
    eq(math.type(g.chara_id), "integer", "an integer")
    -- the game answers a float: stored as an integer, or the kind key would be "c5201.0"
    local wolf = char("ch223001_00_8", { name = "Wolf", hostile = true, chara_id = 5202.0 })
    eq(actors.of(wolf).chara_id, 5202, "a float CharaID")
    eq(math.type(actors.of(wolf).chara_id), "integer", "stored as an integer")
    -- a character whose CharaID cannot be read has none
    local unknown = char("ch220003_00_15", { hostile = true })
    unknown.methods.get_CharaID = function() error("boom") end
    eq(actors.of(unknown).chara_id, nil, "unreadable")
    -- party members carry it too, and a refresh keeps it
    W.player.chara_id = 2891076981
    actors.refresh()
    local p = actors.of(W.player)
    eq(p.chara_id, 2891076981, "the player's")
    actors.refresh()
    eq(p.chara_id, 2891076981, "kept by a refresh")
    -- a refresh that cannot read it keeps the one known
    W.player.methods.get_CharaID = function() error("boom") end
    actors.refresh()
    eq(p.chara_id, 2891076981, "kept after a failed read")
    -- and takes a new one
    W.player.methods.get_CharaID = function() return 77 end
    actors.refresh()
    eq(p.chara_id, 77, "re-read")
    eq(actors.by_chara_id(77), p, "by_chara_id follows")
end)

test("refresh renames cached actors the way the HUD does", function()
    world()
    actors.refresh()
    local godwin = actors.of(W.pawns[2])
    eq(godwin.name, "Godwin", "before")
    -- GUIBase.getName flips between _Name and _Nickname (seen in game for pawns' names)
    W.names[W.pawns[2]] = "Torinald"
    eq(godwin.name, "Godwin", "not before a refresh")
    actors.refresh()
    eq(godwin.name, "Torinald", "after the refresh")
    eq(actors.of(W.pawns[2]), godwin, "same table")
    local asked = R.calls_of("getName(app.Character)")
    eq(asked[#asked].args[1] ~= nil, true, "asked about a character")

    -- a failing name call keeps the name already known, it does not fall back to the object name
    W.names[W.pawns[2]] = nil
    actors.refresh()
    eq(godwin.name, "Torinald", "kept")
end)

test("refresh falls back to the creator's name and keeps max HP current", function()
    world()
    actors.refresh()
    local c = W.pawns[2]
    local a = actors.of(c)
    W.names[c] = nil
    local pdc = R.object("app.PawnDataContext", { _Name = "Torinald", _Nickname = "Godwin" }, {})
    c.methods.get_Human = function()
        return R.object("app.Human", {}, { get_PawnDataContext = function() return pdc end })
    end
    c.max_hp = 2500
    actors.refresh()
    eq(a.name, "Torinald", "_Name")
    eq(a.max_hp, 2500, "max hp")
end)

test("reset drops the cache", function()
    world()
    actors.refresh()
    local goblin = char("ch220003_00_15", { name = "Живодёр", hostile = true })
    local g = actors.of(goblin)
    local p = actors.of(W.player)
    actors.reset()
    -- the game is gone too: no singletons
    R.singleton("app.CharacterManager", nil)
    R.singleton("app.PawnManager", nil)
    eq(#actors.party(), 0, "no party")
    eq(present_char(p), nil, "no live character any more"); eq(#actors.present(), 0, "nobody")
    W.names[goblin] = "Гоблин"
    local g2 = actors.of(goblin)
    assert(g2 ~= g, "a new actor after the reset")
    eq(g2.name, "Гоблин", "read again")
    eq(g2.key, g.key, "same address, same key")
end)

test("a roster is read by itself when nobody refreshed after a reset", function()
    world()
    actors.reset()
    eq(actors.of(W.player).kind, "player", "player known without refresh")
    actors.reset()
    eq(#actors.party(), 4, "party known without refresh")
end)

test("present(true): each listed member's app.Human, read once per party read", function()
    world()
    local humans = {}
    for i, c in ipairs({ W.player, W.pawns[1] }) do
        humans[i] = R.object("app.Human", {}, {})
        c.methods.get_Human = function() return humans[i] end
    end
    W.pawns[2].methods.get_Human = function() return nil end
    actors.refresh()
    local base = #R.calls_of("get_Human") -- a party read asks for the vocation through it too
    local function asked() return #R.calls_of("get_Human") - base end
    local function human_of(c)
        local actor = actors.of(c)
        for _, m in ipairs(actors.present(true)) do
            if m.actor == actor then return m.human end
        end
        return "not listed"
    end
    eq(human_of(W.player), humans[1], "the player's")
    eq(human_of(W.pawns[1]), humans[2], "the main pawn's")
    eq(human_of(W.player), humans[1], "again"); eq(asked(), 3, "asked once for each of the three listed")
    eq(human_of(W.pawns[2]), nil, "a pawn without one")
    eq(human_of(W.pawns[2]), nil, "still none")
    eq(asked(), 3, "not asked again for him either")
    for _, m in ipairs(actors.present()) do eq(m.human, nil, "without the flag: no Human") end
    eq(asked(), 3, "nor asked")
    local goblin = char("ch220003_00_15", { hostile = true })
    goblin.methods.get_Human = function() return R.object("app.Human", {}, {}) end
    eq(human_of(goblin), "not listed", "nobody outside the party")
    actors.refresh()
    base = #R.calls_of("get_Human")
    eq(human_of(W.player), humans[1], "after a party read"); eq(asked(), 3, "asked again once each")
    eq(human_of(W.player), humans[1], "and kept"); eq(asked(), 3, "once")
end)

-- The game calls made on any of `objects` from call number `from` on.
local function asked_since(objects, from)
    local set, n = {}, 0
    for _, o in ipairs(objects) do set[o] = true end
    for i = from + 1, #R.calls do
        if set[R.calls[i].this] then n = n + 1 end
    end
    return n
end

test("without a player character a party read reads no pawn list and asks no pawn, as present", function()
    world()
    actors.refresh()
    eq(#actors.party(), 4, "the party")
    local player = W.player
    W.player = nil
    local reads, from = #R.calls_of("get_PawnCharacterList"), #R.calls
    actors.refresh()
    eq(#R.calls_of("get_PawnCharacterList"), reads, "the pawn list not read")
    eq(asked_since(W.pawns, from), 0, "no pawn asked")
    eq(#actors.party(), 0, "nobody")
    -- read by itself after a reset (ensure_roster), the same
    actors.reset()
    eq(#actors.party(), 0, "nobody after a reset")
    eq(#R.calls_of("get_PawnCharacterList"), reads, "still not read")
    W.player = player
    actors.refresh()
    eq(#actors.party(), 4, "back with him")
end)

test("listed() is the party listing of one read; present takes it and reads nothing more", function()
    world()
    actors.refresh()
    W.pawns = { W.pawns[1], false, W.pawns[3] }   -- a null entry in the game's list
    local now = actors.listed()
    eq(now[W.player:get_address()], W.player, "the player at his address")
    eq(now[W.pawns[1]:get_address()], W.pawns[1], "a pawn at hers")
    eq(now[false], nil, "a null entry is no entry")
    local n = 0
    for _ in pairs(now) do n = n + 1 end
    eq(n, 3, "the player and the two pawns listed")
    local before = #R.calls
    local list = actors.present(nil, now)
    eq(#list, 3, "the members it lists"); eq(#R.calls, before, "no game call: the listing given is used")
    eq(#actors.present(nil, {}), 0, "an empty listing: nobody")
    -- without a player: an empty listing, the pawn list not read
    W.player = nil
    local reads = #R.calls_of("get_PawnCharacterList")
    eq(next(actors.listed()), nil, "empty")
    eq(#R.calls_of("get_PawnCharacterList"), reads, "the pawn list not read")
end)

test("present: the party members the game lists now, each with the character it lists, read anew", function()
    world()
    actors.refresh()
    local p, casca, godwin, yves = actors.of(W.player), actors.of(W.pawns[1]), actors.of(W.pawns[2]),
        actors.of(W.pawns[3])
    local list = actors.present()
    eq(#list, 4, "the player and three pawns")
    eq(list[1].actor, p, "the player first"); eq(list[1].character, W.player, "his character")
    eq(list[1].addr, W.player:get_address(), "its address")
    eq(list[2].actor, casca, "then the pawns in order"); eq(list[4].actor, yves, "Yves last")
    eq(present_char(godwin), W.pawns[2], "Godwin's")
    -- the game drops Yves from its list before the next party read: he is not given, nothing of him is asked
    local yves_char, before = W.pawns[3], #R.calls
    W.pawns = { W.pawns[1], W.pawns[2] }
    eq(present_char(yves), nil, "a member the game no longer lists")
    for i = before + 1, #R.calls do
        assert(R.calls[i].this ~= yves_char, "his kept object asked: " .. R.calls[i].sig)
    end
    eq(#actors.party(), 4, "the roster is as the last party read left it")
    -- read anew on each call
    local reads = #R.calls_of("get_ManualPlayer")
    actors.present()
    eq(#R.calls_of("get_ManualPlayer"), reads + 1, "the player read again")
    -- the world goes: no player character, so nobody, the pawns the game still lists included
    local player = W.player
    W.player = nil
    eq(#actors.present(), 0, "nobody without a player character")
    -- nor read: after a reset the party is not read by present while the player is gone
    actors.reset()
    local pawn_reads = #R.calls_of("get_PawnCharacterList")
    eq(#actors.present(true), 0, "nobody after a reset")
    eq(#R.calls_of("get_PawnCharacterList"), pawn_reads, "the pawn list not read")
    W.player = player
    eq(#actors.present(), 3, "back")
    -- nobody outside the party, nothing that cannot be read
    local goblin = actors.of(char("ch220003_00_15", { hostile = true }))
    eq(present_char(goblin), nil, "enemies are not given")
    R.singleton("app.PawnManager", nil)
    eq(#actors.present(), 1, "no pawn list: the player alone")
    R.singleton("app.CharacterManager", nil)
    eq(#actors.present(), 0, "no character manager: nobody")
end)

test("health reads any character's current and full HP the way the meter does", function()
    world()
    local goblin = char("ch220003_00_15", { hostile = true, hp = 12340, max_hp = 18000 })
    local hp, full = actors.health(goblin)
    eq(hp, 12340, "get_Hp"); eq(full, 18000, "get_OriginalMaxHp")
    goblin.hp = 0.4
    hp, full = actors.health(goblin)
    eq(hp, 0.4, "as the game gives it"); eq(full, 18000, "full")
    -- the full HP is at least the current one, as a fight's record takes it
    goblin.hp = 19000
    hp, full = actors.health(goblin)
    eq(hp, 19000, "current"); eq(full, 19000, "full raised to the current")
    -- no actor is made, nothing is cached: a character the meter has never seen
    eq(#actors.party(), 4, "the party only")
    local calls = #R.calls_of("isHostile(app.Character)")
    actors.health(goblin)
    eq(#R.calls_of("isHostile(app.Character)"), calls, "no hostility asked")
    -- either one unreadable: nothing
    goblin.max_hp = nil
    eq(actors.health(goblin), nil, "no full HP")
    goblin.max_hp, goblin.hp = 18000, nil
    eq(actors.health(goblin), nil, "no current HP")
    goblin.hp, goblin.max_hp = 100, 0
    eq(actors.health(goblin), nil, "a full HP of 0 is none read yet")
    goblin.max_hp = 0 / 0
    eq(actors.health(goblin), nil, "nan")
    goblin.max_hp, goblin.hp = 18000, math.huge
    eq(actors.health(goblin), nil, "an infinite HP")
    goblin.hp = 100
    goblin.poison = true
    eq(actors.health(goblin), nil, "a character that raises")
    goblin.poison = false
    eq(actors.health(nil), nil, "no character")
    eq(select(2, actors.health(goblin)), 18000, "back")
end)

test("a reused address builds a new actor", function()
    world()
    actors.refresh()
    local c = char("ch220003_00_15", { name = "Живодёр", hostile = true })
    local a = actors.of(c)
    -- the game freed the goblin and put a chimera at the same address
    c.go.methods.get_Name = function() return "ch254000_00_207" end
    W.names[c] = "Химера"
    local b = actors.of(c)
    assert(b ~= a, "a new actor")
    eq(b.name, "Химера", "new name")
    eq(b.base_id, "ch254000_00", "new base id")
    eq(a.name, "Живодёр", "the old actor is left as it was")
end)

test("every game call failing gives nil, never an error", function()
    world()
    eq(actors.of(nil), nil, "no character")
    eq(actors.of(42), nil, "not an object")
    local poisoned = char("ch220003_00_15", { hostile = true })
    poisoned.poison = true
    eq(actors.of(poisoned), nil, "address unreadable")

    -- singletons that raise or are missing
    R.singleton("app.CharacterManager", R.object("app.CharacterManager", {}, {
        get_ManualPlayer = function() error("boom") end,
    }))
    R.singleton("app.PawnManager", nil)
    actors.refresh()
    eq(#actors.party(), 0, "nothing to poll")

    -- a pawn list that cannot be read
    R.singleton("app.PawnManager", R.object("app.PawnManager", {}, {
        get_PawnCharacterList = function() error("boom") end,
    }))
    actors.refresh()
    eq(#actors.party(), 0, "still nothing")

    -- a character whose every call fails still gets an actor, with placeholders
    local c = R.character{ go = "ch220003_00_16" }
    for _, name in ipairs({ "get_GameObject", "get_OriginalMaxHp", "get_CharaID" }) do
        c.methods[name] = function() error("boom") end
    end
    local a = actors.of(c)
    eq(a.base_id, "?", "no game object")
    eq(a.max_hp, nil, "no max hp")
    eq(a.kind, "other", "no hostility info")
end)

test("the party is the player and at most three pawns, positions kept", function()
    world()
    local extra = { char("ch111020", { name = "Extra 1" }), char("ch111021", { name = "Extra 2" }) }
    W.pawns = { W.pawns[1], W.pawns[2], W.pawns[3], extra[1], extra[2] }
    actors.refresh()
    eq(#actors.party(), 4, "player and three pawns")
    eq(actors.of(extra[1]).kind, "other", "a fourth pawn is not in the party")

    -- a null entry in the pawn list still takes its place
    W.pawns = { false, W.pawns[2] }
    actors.refresh()
    local party = actors.party()
    eq(#party, 2, "player and one pawn")
    eq(party[2].order, 2, "second place in the list")

    -- the returned list is a copy
    party[1] = nil
    eq(#actors.party(), 2, "the party list cannot be changed from outside")
end)

-- The vocation the game reports for a character (app.Human -> JobContext.CurrentJob, app.Character.JobEnum).
local function set_job(c, job)
    local jc = R.object("app.JobContext", { CurrentJob = job }, {})
    local human = R.object("app.Human", {}, { get_JobContext = function() return jc end })
    c.methods.get_Human = function() return human end
end

test("party members carry their vocation, read on every refresh", function()
    world()
    set_job(W.player, 5)
    set_job(W.pawns[1], 1)
    set_job(W.pawns[2], 4)
    set_job(W.pawns[3], 3)
    actors.refresh()
    local p, casca = actors.of(W.player), actors.of(W.pawns[1])
    eq(p.job, 5, "player: Warrior")
    eq(casca.job, 1, "main pawn: Fighter")
    eq(actors.of(W.pawns[2]).job, 4, "support pawn: Thief")
    eq(actors.of(W.pawns[3]).job, 3, "support pawn: Mage")
    eq(math.type(p.job), "integer", "an integer")
    local asked = R.calls_of("get_JobContext")
    eq(#asked >= 4, true, "asked through get_Human -> get_JobContext")

    -- a change of vocation (at an inn) shows after the next refresh, not before
    set_job(W.player, 2.0)
    eq(p.job, 5, "not before a refresh")
    actors.refresh()
    eq(p.job, 2, "after the refresh")
    eq(math.type(p.job), "integer", "a float from the game is stored as an integer")

    -- a vocation that cannot be read keeps the one already known; a character never read has none
    W.player.methods.get_Human = function() error("boom") end
    actors.refresh()
    eq(p.job, 2, "kept after a failed read")
    local newcomer = char("ch111030", { name = "Mercedes" })
    W.pawns = { W.pawns[1], newcomer }
    actors.refresh()
    eq(actors.of(newcomer).job, nil, "no human: unknown")
    set_job(newcomer, 0)
    actors.refresh()
    eq(actors.of(newcomer).job, nil, "JobEnum 0 (none): unknown")
    set_job(newcomer, "Fighter")
    actors.refresh()
    eq(actors.of(newcomer).job, nil, "not a number: unknown")
    set_job(newcomer, 9)
    actors.refresh()
    eq(actors.of(newcomer).job, 9, "read once the game answers")
end)

test("enemies and allies have no vocation; a pawn that leaves loses it", function()
    world()
    set_job(W.pawns[3], 3)
    actors.refresh()
    local goblin = char("ch220003_00_15", { name = "Живодёр", hostile = true })
    set_job(goblin, 2)
    eq(actors.of(goblin).job, nil, "an enemy is not asked")
    local guard = char("ch300656_00_3", { name = "Форрест" })
    set_job(guard, 1)
    local g = actors.of(guard)
    actors.mark_fighting(g)
    eq(g.job, nil, "an ally neither")

    local yves = actors.of(W.pawns[3])
    eq(yves.job, 3, "a pawn has one")
    local old_yves = W.pawns[3]
    W.pawns = { W.pawns[1], W.pawns[2] }
    actors.refresh()
    actors.of(old_yves)
    eq(yves.kind, "other", "dismissed")
    eq(yves.job, nil, "and no party vocation any more")
    -- hired again: read again
    W.pawns = { W.pawns[1], W.pawns[2], old_yves }
    actors.refresh()
    eq(yves.job, 3, "read again")

    -- a party member met by Actors.of before any refresh gets its vocation too
    world()
    set_job(W.pawns[1], 6)
    eq(actors.of(W.pawns[1]).job, 6, "built from the roster")
end)

test("a finished fight keeps the vocation it had", function()
    local Fight = require("DD2DamageMeter/fight")
    world()
    set_job(W.player, 5)
    actors.refresh()
    local p = actors.of(W.player)
    local goblin = actors.of(char("ch220003_00_15", { name = "Живодёр", hostile = true, max_hp = 3000 }))
    local f = Fight.new(0)
    f:add_hit({ t = 1, attacker = p, victim = goblin, skill = { attack = "N_軽" }, final = 100, hp0 = 3000, hp1 = 2900 })
    local before = f:snapshot(2)
    eq(before.actors[p.key].actor.job, 5, "in the snapshot")
    set_job(W.player, 10)
    actors.refresh()
    eq(before.actors[p.key].actor.job, 5, "the snapshot keeps the old vocation")
    eq(f:snapshot(3).actors[p.key].actor.job, 10, "a new snapshot shows the new one")
end)

-- The game can make a new character object for a party member mid-fight (the Gagana fight: each pawn at a second
-- address, with the same CharaID, game object, vocation and place). A new object for `old`: its game object name, HUD
-- name and CharaID at another address; o.hp, o.max_hp as char's.
local function anew(old, o)
    o = o or {}
    return char(old.go.methods.get_Name(), { name = W.names[old], chara_id = old.chara_id,
        hp = o.hp or old.hp, max_hp = o.max_hp or old.max_hp })
end

local function party_reads()
    return #R.calls_of("get_PawnCharacterList")
end

test("a pawn the game makes anew keeps his actor: the same table, key and place", function()
    world()
    W.player.chara_id = 2891076981
    W.pawns[1].chara_id = 2283028347
    W.pawns[2].chara_id = 112032848
    set_job(W.pawns[1], 1)
    actors.refresh()
    local old = W.pawns[1]
    local casca = actors.of(old)
    local new = anew(old, { hp = 1234, max_hp = 1900 })
    set_job(new, 6)
    W.names[new] = "Касса"
    W.pawns[1] = new
    actors.refresh()
    eq(actors.of(new), casca, "the same actor table")
    eq(casca.key, "a" .. old:get_address(), "the key of her first object")
    eq(casca.kind, "pawn", "a pawn"); eq(casca.order, 1, "in her place")
    eq(casca.max_hp, 1900, "synced: the new object's full HP"); eq(casca.job, 6, "its vocation")
    eq(casca.name, "Касса", "its HUD name")
    local party = actors.party()
    eq(#party, 4, "party size"); eq(party[2], casca, "in the party once")
    for i, a in ipairs(party) do
        if i ~= 2 then assert(a ~= casca, "not twice") end
    end
    eq(present_char(casca), new, "the new object, polled"); eq(new.hp, 1234, "its HP")
    eq(actors.by_chara_id(2283028347), casca, "by_chara_id")
    -- an event of the old object after the switch: her actor, a pawn in her place (not one who left), even hostile
    old.methods["isHostile(app.Character)"] = function() return true end
    eq(actors.of(old), casca, "the old object's late event")
    eq(casca.kind, "pawn", "not re-classified"); eq(casca.order, 1, "her place kept"); eq(casca.job, 6, "her vocation")
    actors.refresh()
    eq(actors.of(new), casca, "the next party read changes nothing"); eq(actors.of(old), casca, "both objects")
    eq(actors.of(W.pawns[2]).key, "a" .. W.pawns[2]:get_address(), "the other pawns as before")
end)

test("the player made anew keeps his actor too", function()
    world()
    W.player.chara_id = 2891076981
    actors.refresh()
    local old = W.player
    local guts = actors.of(old)
    W.player = anew(old)
    W.player.methods["getBattleRelationshipTo(app.Character)"] = function(_, c) return W.relation[c] or 0 end
    actors.refresh()
    eq(actors.of(W.player), guts, "the same actor table")
    eq(guts.key, "a" .. old:get_address(), "the same key")
    eq(guts.kind, "player", "the player"); eq(guts.order, 0, "first")
    eq(actors.party()[1], guts, "first in the party"); eq(#actors.party(), 4, "party size")
    eq(actors.of(old), guts, "the old object's late event"); eq(guts.kind, "player", "still the player")
end)

test("another CharaID, or none, at a new address is a new actor", function()
    world()
    W.pawns[1].chara_id = 2283028347
    W.pawns[2].chara_id = 112032848
    actors.refresh()
    local godwin, yves = actors.of(W.pawns[2]), actors.of(W.pawns[3])
    -- Godwin dismissed, a pawn of another CharaID hired in his place
    local mercedes = char("ch111010", { name = "Mercedes", chara_id = 5551 })
    W.pawns[2] = mercedes
    actors.refresh()
    local m = actors.of(mercedes)
    assert(m ~= godwin, "a new actor"); eq(m.key, "a" .. mercedes:get_address(), "its own key")
    eq(m.kind, "pawn", "a pawn"); eq(m.order, 2, "in the second place")
    -- Casca made anew, but the new object's CharaID cannot be read: a new actor, as before
    local casca = actors.of(W.pawns[1])
    local unread = anew(W.pawns[1])
    unread.methods.get_CharaID = function() error("boom") end
    W.pawns[1] = unread
    actors.refresh()
    local u = actors.of(unread)
    assert(u ~= casca, "no CharaID: a new actor"); eq(u.key, "a" .. unread:get_address(), "its own key")
    eq(u.chara_id, nil, "none")
    -- Yves's actor has no CharaID (none was read): his new object with one matches nothing
    local new_yves = anew(W.pawns[3])
    new_yves.chara_id = 112032999
    W.pawns[3] = new_yves
    actors.refresh()
    assert(actors.of(new_yves) ~= yves, "an actor without a CharaID is nobody's match")
end)

test("a member's new object met before the next party read: the party is read again, once", function()
    world()
    W.pawns[1].chara_id = 2283028347
    actors.refresh()
    local casca = actors.of(W.pawns[1])
    local new = anew(W.pawns[1])
    W.pawns[1] = new
    local reads = party_reads()
    eq(actors.of(new), casca, "her actor at once (a hit of the new object, or on it)")
    eq(party_reads(), reads + 1, "the party was read again")
    eq(actors.party()[2], casca, "in her place")
    eq(actors.of(new), casca, "cached"); eq(party_reads(), reads + 1, "read once")
    -- nobody else costs a party read: an enemy, a character with no CharaID
    actors.of(char("ch220003_00_15", { hostile = true, chara_id = 5201 }))
    actors.of(char("ch220003_00_16", { hostile = true }))
    eq(party_reads(), reads + 1, "no read for anybody else")
    eq(present_char(casca), new, "the new object polled")
end)

test("a member's new object not in the pawn list yet is somebody else until the list has it", function()
    world()
    W.pawns[1].chara_id = 2283028347
    actors.refresh()
    local casca = actors.of(W.pawns[1])
    local new = anew(W.pawns[1])
    local early = actors.of(new)
    assert(early ~= casca, "not in the party: classified as anybody else"); eq(early.kind, "other", "neutral")
    eq(casca.kind, "pawn", "she stays a pawn")
    W.pawns[1] = new
    actors.refresh()
    eq(actors.of(new), casca, "her actor once the party has the new object")
    eq(actors.party()[2], casca, "in her place"); eq(early.kind, "other", "the early actor is left as it was")
    -- the roster path of Actors.of: a roster address whose game object name changed since the party read
    new.go.methods.get_Name = function() return "ch100000_01" end
    eq(actors.of(new), casca, "joins her too")
end)

test("the normal rules and enemies as before: a member who left, an enemy with a member's CharaID", function()
    world()
    W.pawns[3].chara_id = 112032848
    actors.refresh()
    local old = W.pawns[3]
    local yves = actors.of(old)
    local new = anew(old)
    W.pawns[3] = new
    actors.refresh()
    eq(actors.of(new), yves, "made anew: the same actor")
    -- he leaves the party: a late event of either object re-classifies him by the normal rules
    W.pawns = { W.pawns[1], W.pawns[2] }
    actors.refresh()
    eq(actors.of(old), yves, "the old object"); eq(yves.kind, "other", "he left"); eq(yves.order, nil, "no place")
    eq(actors.of(new), yves, "the new object")
    -- hired again with yet another object: a member who left counts too
    local third = anew(old)
    W.pawns = { W.pawns[1], W.pawns[2], third }
    actors.refresh()
    eq(actors.of(third), yves, "the same actor again"); eq(yves.kind, "pawn", "a pawn"); eq(yves.order, 3, "third")
    -- an enemy with a party member's CharaID: an enemy of its own, the member untouched
    local imp = char("ch220003_00_15", { name = "Живодёр", hostile = true, chara_id = 112032848 })
    local e = actors.of(imp)
    assert(e ~= yves, "not the member"); eq(e.kind, "enemy", "an enemy"); eq(e.key, "a" .. imp:get_address(), "own key")
    eq(yves.kind, "pawn", "the member stays a pawn"); eq(actors.by_chara_id(112032848), yves, "by_chara_id: the member")
    eq(actors.of(imp), e, "cached")
    -- the member leaves again and his object turns hostile: an enemy by the normal rules, as before
    W.pawns = { W.pawns[1], W.pawns[2] }
    actors.refresh()
    third.methods["isHostile(app.Character)"] = function() return true end
    eq(actors.of(third), yves, "his actor"); eq(yves.kind, "enemy", "hostile: an enemy")
end)

test("a member's two objects listed at once: one actor, in the party once", function()
    world()
    W.pawns[1].chara_id = 2283028347
    actors.refresh()
    local old = W.pawns[1]
    local casca = actors.of(old)
    local new = anew(old)
    W.pawns = { new, W.pawns[2], old }
    actors.refresh()
    eq(actors.of(new), casca, "the new object"); eq(actors.of(old), casca, "the old one")
    local party = actors.party()
    eq(#party, 3, "the player, Casca and Godwin"); eq(party[2], casca, "Casca in her first place")
    eq(party[3], actors.of(W.pawns[2]), "Godwin next")
    eq(present_char(casca), new, "polled on the first object listed")
    eq(actors.address(casca), new:get_address(), "its address")
end)

test("a member's two objects listed at once: his order is his first place, as the party lists him", function()
    world()
    W.pawns[1].chara_id = 2283028347
    actors.refresh()
    local old, godwin = W.pawns[1], W.pawns[2]
    local casca = actors.of(old)
    local new = anew(old)
    W.pawns = { godwin, new, old }
    actors.refresh()
    eq(actors.party()[3], casca, "her first place: the second pawn")
    eq(casca.order, 2, "her order from it, not from the third")
    eq(actors.address(casca), new:get_address(), "the address of that place")
    W.pawns = { old, godwin, new }
    actors.refresh()
    eq(actors.party()[2], casca, "first now"); eq(casca.order, 1, "her order follows")
    -- the roster path of Actors.of (the third place's game object name changed since the party read) keeps it too
    new.go.methods.get_Name = function() return "ch100000_01" end
    eq(actors.of(new), casca, "her actor"); eq(casca.order, 1, "still her first place")
    W.pawns = { godwin, new }
    actors.refresh()
    eq(casca.order, 2, "one object again: its place")
end)

test("enemies of one CharaID at different addresses stay apart", function()
    world()
    W.pawns[1].chara_id = 2283028347
    actors.refresh()
    local a = actors.of(char("ch220003_00_1", { hostile = true, chara_id = 5201 }))
    local b = actors.of(char("ch220003_00_2", { hostile = true, chara_id = 5201 }))
    local c = actors.of(char("ch220003_00_1", { hostile = true, chara_id = 5201 }))
    assert(a ~= b and a ~= c and b ~= c, "three actors")
    assert(a.key ~= b.key and a.key ~= c.key, "three keys")
    eq(a.kind, "enemy", "enemies"); eq(c.kind, "enemy", "all of them")
end)

test("a pawn made anew is one row of the fight: what he did before and after adds up", function()
    local Fight = require("DD2DamageMeter/fight")
    world()
    W.pawns[1].chara_id = 2283028347
    actors.refresh()
    local old = W.pawns[1]
    local goblin = actors.of(char("ch220003_00_15", { name = "Живодёр", hostile = true, max_hp = 3000 }))
    local f = Fight.new(0)
    f:add_hit({ t = 1, attacker = actors.of(old), victim = goblin, skill = { attack = "N_軽" }, final = 100,
        hp0 = 3000, hp1 = 2900 })
    local new = anew(old)
    W.pawns[1] = new
    actors.refresh()
    f:add_hit({ t = 2, attacker = actors.of(new), victim = goblin, skill = { attack = "N_軽" }, final = 200,
        hp0 = 2900, hp1 = 2700 })
    f:add_hit({ t = 3, attacker = actors.of(old), victim = goblin, skill = { attack = "N_軽" }, final = 50,
        hp0 = 2700, hp1 = 2650 })
    local snap = f:snapshot(4)
    local rows = 0
    for _, s in pairs(snap.actors) do
        if s.actor.name == "Casca" then rows = rows + 1 end
    end
    eq(rows, 1, "one row")
    eq(snap.actors[actors.of(new).key].dealt, 350, "before, after and the old object's late hit")
    eq(snap.actors[actors.of(new).key].hits, 3, "three hits")
end)

test("a prune keeps a member's old address: a late event of his old object is still his", function()
    world()
    W.pawns[1].chara_id = 2283028347
    actors.refresh()
    local old = W.pawns[1]
    local casca = actors.of(old)
    local new = anew(old)
    W.pawns[1] = new
    actors.refresh()
    eq(actors.of(new), casca, "made anew: the same actor")
    local first = char("ch220003_00_0", { hostile = true })
    local e = actors.of(first)
    for i = 1, 1100 do actors.of(char("ch220003_00_" .. i, { hostile = true })) end
    assert(actors.of(first) ~= e, "a prune came: an old enemy was dropped")
    local reads = party_reads()
    eq(actors.of(old), casca, "the old object's late event: her actor, not a second table under her key")
    eq(casca.kind, "pawn", "still a pawn"); eq(casca.order, 1, "in her place"); eq(party_reads(), reads, "cached")
    eq(actors.of(new), casca, "the new object too"); eq(actors.party()[2], casca, "in the party once")
end)

test("each join of a new object is reported: the member's actor, the address he was at and the new one", function()
    world()
    local joins = {}
    actors.on_join(function(actor, old, new) joins[#joins + 1] = { actor = actor, old = old, new = new } end)
    W.player.chara_id = 2891076981
    W.pawns[1].chara_id = 2283028347
    W.pawns[2].chara_id = 112032848
    W.pawns[3].chara_id = 1188289343
    actors.refresh()
    eq(#joins, 0, "the party's first read: no join")
    local old = W.pawns[1]
    local casca = actors.of(old)
    local new = anew(old)
    W.pawns[1] = new
    actors.refresh()
    eq(#joins, 1, "her new object joins her actor")
    eq(joins[1].actor, casca, "her actor"); eq(joins[1].old, old:get_address(), "the old address")
    eq(joins[1].new, new:get_address(), "the new one")
    actors.refresh()
    eq(actors.of(old), casca, "the old object's late event")
    eq(#joins, 1, "the next party read and a late event: none")
    -- a third object, met before the next party read
    local third = anew(new)
    W.pawns[1] = third
    eq(actors.of(third), casca, "her actor at once")
    eq(#joins, 2, "one more join"); eq(joins[2].old, new:get_address(), "from the second address")
    eq(joins[2].new, third:get_address(), "to the third")
    -- another CharaID at a new address, the player made anew
    W.pawns[2] = char("ch111010", { name = "Mercedes", chara_id = 5551 })
    actors.refresh()
    eq(#joins, 2, "a new member: no join")
    local guts = actors.of(W.player)
    local first = W.player
    W.player = anew(first)
    actors.refresh()
    eq(#joins, 3, "the player's new object"); eq(joins[3].actor, guts, "his actor")
    eq(joins[3].old, first:get_address(), "his old address")
    -- the watcher stays through a reset; one that raises breaks no party read
    actors.reset()
    actors.refresh()
    local yves = actors.of(W.pawns[3])
    actors.on_join(function() error("boom") end)
    W.pawns[3] = anew(W.pawns[3])
    actors.refresh()
    eq(actors.of(W.pawns[3]), yves, "joined all the same"); eq(actors.party()[4], yves, "in his place")
    actors.on_join(nil)
    W.pawns[3] = anew(W.pawns[3])
    actors.refresh()
    eq(actors.of(W.pawns[3]), yves, "no watcher: joined as before")
end)

test("the cache stays bounded and keeps the party", function()
    world()
    actors.refresh()
    local p = actors.of(W.player)
    local first = char("ch220003_00_0", { hostile = true })
    local a = actors.of(first)
    for i = 1, 1500 do actors.of(char("ch220003_00_" .. i, { hostile = true })) end
    eq(actors.of(W.player), p, "party actor survives")
    assert(actors.of(first) ~= a, "an old enemy was dropped")
    eq(actors.of(first).kind, "enemy", "and is simply rebuilt")
end)

T.finish()
