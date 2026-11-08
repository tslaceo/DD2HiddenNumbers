package.path = "mod/reframework/autorun/?.lua;tests/?.lua;" .. package.path

local T = require("testlib")
local test, eq, near = T.test, T.eq, T.near
local R = require("stubs/reframework")
local ui = require("stubs/ui")
local json_decode = require("json_decode")

local ENTRY = "mod/reframework/autorun/DD2DamageMeter.lua"
local SETTINGS_FILE = "DD2DamageMeter/settings.json"
local LOG_FILE = "DD2DamageMeter/debug.log"
local HISTORY_FILE = "DD2DamageMeter/history.json"
local LOG_MAX = 5 * 1024 * 1024
local STATIC = { static = true }
local F6, F8 = 0x75, 0x77

local HC, PDC, EDC, CDC = "app.HitController", "app.PlayerDamageCalculator", "app.ExceptPlayerDamageCalculator",
    "app.CharacterDamageCalculator"
local IM, GM, BM = "app.ItemManager", "app.GuiManager", "app.BattleManager"
local DI = "app.HitController.DamageInfo"
local SIG = {
    damageProc = "damageProc(" .. DI .. ")",
    defence = "calcDamageValueDefence(" .. DI .. ")",
    region = "calcRegionDamageRate(" .. DI .. ")",
    updateDamage = "updateDamage(" .. DI .. ", System.UInt32, System.Single, System.Boolean)",
    subGuardHp = "subGuardHp(System.Single, " .. DI .. ")",
    status = "applyStatusDamage(" .. DI .. ", app.StatusConditionDef.StatusConditionEnum, System.Single)",
    recoverHp = "recoverHp(System.Single, System.Boolean, System.Int32, System.Boolean)",
    useItem = "useItem(System.Int32, app.Character, app.Character)",
    convert = "convertHealHp(System.Single, app.Character, app.CharacterID, app.ItemIDEnum, System.Boolean)",
    -- the mod looks the scene change up by its name, so the parameter list here is only an example
    scene = "OnChangeSceneType(System.Int32)",
}
-- Every hooked method as DD2DM.info().missing names it, and the battle mode getter that is polled.
local HOOKED = {
    HC .. "." .. SIG.damageProc, PDC .. "." .. SIG.defence, EDC .. "." .. SIG.defence, HC .. "." .. SIG.region,
    HC .. "." .. SIG.updateDamage, HC .. "." .. SIG.subGuardHp, CDC .. "." .. SIG.status, HC .. "." .. SIG.recoverHp,
    IM .. "." .. SIG.useItem, IM .. "." .. SIG.convert, GM .. ".OnChangeSceneType",
}
local BATTLE_MODE = BM .. ".get_BattleMode"
-- The game methods the mod calls without hooking them, as DD2DM.info().missing names them.
local CALLED = {
    "app.CharacterManager.get_ManualPlayer", "app.PawnManager.get_PawnCharacterList", HC .. ".get_Hp",
    HC .. ".get_CachedCharacter", "app.GUIBase.getName(app.Character)",
    DI .. ".get_ElementType", EDC .. ".get_WeakPointSettings", "app.RegionStatusCtrl.getActiveRegionParam(System.Int32)",
}
local ACTIVE = "IsStatusConditionActive(app.StatusConditionDef.StatusConditionEnum, System.Boolean)"
local CAUSED = "getStatusConditionCausedCharacterId(app.StatusConditionDef.StatusConditionEnum)"
local FIRE_SPREAD = 5

local W

-- A new Lua state: no module of the mod loaded, none of its globals.
local function new_state()
    for name in pairs(package.loaded) do
        if name:find("^DD2DamageMeter/") then package.loaded[name] = nil end
    end
    DD2DM, DD2DM_HOOKS = nil, nil
end

-- A module of the mod as the entry file loaded it.
local function mod(name)
    return require("DD2DamageMeter/" .. name)
end

local function char(go, o)
    o = o or {}
    local c = R.character{ go = go, hp = o.hp or 1000, max_hp = o.max_hp or 2000, chara_id = o.chara_id }
    W.names[c] = o.name
    c.methods["isHostile(app.Character)"] = function() return o.hostile == true end
    c.hc = R.object(HC, {}, {
        get_Hp = function() return c.hp end,
        get_CachedCharacter = function() return c end,
    })
    if o.job then
        local jobs = R.object("app.JobContext", { CurrentJob = o.job })
        local human = R.object("app.Human", {}, { get_JobContext = function() return jobs end })
        c.methods.get_Human = function() return human end
    end
    return c
end

-- The game of hits_test.lua and heals_test.lua, plus the battle mode (W.mode, W.ending) and the scene change.
local function declare_game()
    R.method("app.GUIBase", "getName(app.Character)", function(c) return W.names[c] end, STATIC)
    R.method(HC, SIG.damageProc, function() return true end)
    R.method(PDC, SIG.defence, function() end)
    R.method(EDC, SIG.defence, function() end)
    R.method(HC, SIG.region, function() end)
    R.method(HC, SIG.updateDamage, function() end)
    R.method(HC, SIG.subGuardHp, function() return false end)
    R.method(CDC, SIG.status, function() end)
    R.type(PDC, CDC)
    R.type(EDC, CDC)
    -- called, not hooked (the hit's element, the enemy's data and its parts)
    R.method(DI, "get_ElementType", function() end)
    R.method(EDC, "get_WeakPointSettings", function() end)
    R.method("app.RegionStatusCtrl", "getActiveRegionParam(System.Int32)", function() end)
    R.method(HC, SIG.recoverHp, function() end)
    R.method(IM, SIG.useItem, function() return true end)
    R.method(IM, SIG.convert, function(amount) return math.floor(amount) end, STATIC)
    R.method(GM, SIG.scene, function() end)
    R.method(BM, "get_BattleMode", function() return W.mode end)
    R.method(BM, "get_IsBattleEnding", function() return W.ending end)
    R.method(BM, "get_IsInBigEnemyOrBossEnemyCombat", function() return false end)
    R.singleton(BM, R.object(BM))
    W.gui = R.object(GM)
    W.im = R.object(IM)
    W.player = char("ch000000_00", { name = "Guts", chara_id = 2891076981, hp = 1913.991, max_hp = 2400 })
    W.casca = char("ch100000_00", { name = "Casca", chara_id = 2283028347, hp = 1500, max_hp = 1800 })
    W.goblin = char("ch220003_00_15", { name = "Goblin", hostile = true, hp = 3053.035, max_hp = 3700 })
    -- the goblin's active statuses: W.burning[status value] = the causer's CharacterID, as the game records it
    W.burning = {}
    local sc = R.object("app.StatusConditionCtrl", {}, {
        [ACTIVE] = function(_, s) return W.burning[s] ~= nil end,
        [CAUSED] = function(_, s) return W.burning[s] or 0 end,
    })
    W.goblin.methods.get_StatusConditionCtrl = function() return sc end
    W.pawns = { W.casca }
    R.method("app.CharacterManager", "get_ManualPlayer", function() return W.player end)
    R.singleton("app.CharacterManager", R.object("app.CharacterManager"))
    R.method("app.PawnManager", "get_PawnCharacterList", function() return R.list(W.pawns) end)
    R.singleton("app.PawnManager", R.object("app.PawnManager"))
    -- each character's hit controller answers for itself (char); declared so that the self-check finds them
    R.method(HC, "get_Hp", function() return nil end)
    R.method(HC, "get_CachedCharacter", function() return nil end)
end

-- A fresh game and Lua state. opts.settings: the saved settings.json; opts.game = false: no game types at all.
-- The mod's clock is W.t; the callbacks it registers are kept in W.
local function world(opts)
    opts = opts or {}
    new_state()
    R.new({ io = true })
    ui.install()
    W = { t = 100, mode = 0, ending = false, names = {}, entries = {}, draw_ui = {}, entry_regs = 0, frame_regs = 0 }
    local on_frame = re.on_frame
    re.on_pre_application_entry = function(name, fn)
        W.entry_regs = W.entry_regs + 1
        W.entries[#W.entries + 1] = { name = name, fn = fn }
    end
    re.on_frame = function(fn)
        W.frame_regs = W.frame_regs + 1
        return on_frame(fn)
    end
    re.on_draw_ui = function(fn) W.draw_ui[#W.draw_ui + 1] = fn end
    if opts.settings then R.json_files[SETTINGS_FILE] = opts.settings end
    if opts.game ~= false then declare_game() end
    DD2DM = { clock = function() return W.t end }
    return W
end

local function load()
    return dofile(ENTRY)
end

-- One game frame `dt` seconds after the last one: BeginRendering (a callback that returns STOP is removed, as in
-- REFramework builds since 2026-08), then the frame callbacks. ui.calls holds what this frame drew.
local function frame(dt)
    W.t = W.t + (dt or 0.02)
    for i = #W.entries, 1, -1 do
        local e = W.entries[i]
        if e.name == "BeginRendering" and e.fn() == re.CallbackNextAction.STOP then table.remove(W.entries, i) end
    end
    ui.clear_calls()
    R.advance(1)
end

-- The REFramework menu draws the scripts' UI.
local function draw_ui()
    ui.clear_calls()
    for _, fn in ipairs(W.draw_ui) do fn() end
end

local function shown()
    return ui.find("begin_window") ~= nil
end

local F7, F9, F10 = 0x76, 0x78, 0x79
local PGUP, PGDN, HOME, END, UP, DOWN, LEFT, RIGHT = 0x21, 0x22, 0x24, 0x23, 0x26, 0x28, 0x25, 0x27
local ENTER, ESC = 0x0D, 0x1B
local JOURNAL_WINDOW, OVERLAY_WINDOW, SETTINGS_WINDOW = "DD2DamageMeter journal", "DD2DamageMeter overlay",
    "DD2DamageMeter settings"

local function journal_shown()
    return ui.find("begin_window", JOURNAL_WINDOW) ~= nil
end

local function overlay_shown()
    return ui.find("begin_window", OVERLAY_WINDOW) ~= nil
end

local function settings_shown()
    return ui.find("begin_window", SETTINGS_WINDOW) ~= nil
end

-- `vk` held for one frame, then released for one; ui.calls hold the second frame.
local function press(vk)
    ui.keys_down[vk] = true
    frame()
    ui.keys_down[vk] = nil
    frame()
end

-- A click on the settings window's button `id` ("dd2dm_srow:<key>", "dd2dm_snext:<key>"...) with the REFramework
-- menu open; the window is opened with F8 first when it is closed (and left open). The click is one frame.
local function window_click(id)
    ui.drawing_ui = true
    if not DD2DM.state.settings_window.open then press(F8) end
    ui.press(id)
    frame()
end

-- A switch set to `value` in the settings window (a click on its row when it differs).
local function window_set(key, value)
    if DD2DM.state.settings.values[key] ~= value then
        window_click("dd2dm_srow:" .. key)
    elseif not DD2DM.state.settings_window.open then
        ui.drawing_ui = true
        press(F8)
    end
end

local function contains(list, value)
    for _, v in ipairs(list) do
        if v == value then return true end
    end
    return false
end

local function hook(type_name, name)
    local hk = R.hook_of(type_name, name)
    assert(hk, "not hooked: " .. type_name .. "." .. name)
    return hk
end

local slot = R.obj_slot

-- One melee hit in the game's call order: damageProc > updateDamage, the victim's HP changes inside updateDamage.
-- `fields`: more fields of the DamageInfo (its Position, IsWeakDamage, DamageRate...); a metatable of theirs serves
-- the fields the DamageInfo lacks. `defence`: the enemy calculator's defence step runs first and sets these fields
-- (none: no such step).
local function hit(attacker, victim, final, hp1, fields, defence)
    local aud = R.object("app.AttackUserData", { _ElementType = -1 }, { get_Name = function() return "弱攻撃" end })
    local di = R.object(DI, {
        ["<DamageHitController>k__BackingField"] = victim.hc,
        ["<AttackHitController>k__BackingField"] = attacker.hc,
        ["<AttackUserData>k__BackingField"] = aud,
    }, {})
    for k, v in pairs(fields or {}) do di.fields[k] = v end
    if getmetatable(fields or {}) then setmetatable(di.fields, getmetatable(fields)) end
    R.enter(hook(HC, "damageProc"), { R.CTX, slot(victim.hc), slot(di) })
    if defence then
        R.enter(hook(EDC, "calcDamageValueDefence"), { R.CTX, slot(R.object(EDC)), slot(di) })
        for k, v in pairs(defence) do di.fields[k] = v end
        R.leave(nil)
    end
    R.enter(hook(HC, "updateDamage"), { R.CTX, slot(victim.hc), slot(di), R.int_slot(0xFFFFFFFF), R.f32_slot(final),
        R.int_slot(0) })
    victim.hp = hp1
    R.leave(nil)
    return R.leave(true)
end

-- A small hit of Casca's on the goblin: enough for a fight to be kept.
local function strike()
    hit(W.casca, W.goblin, 10, W.goblin.hp - 10)
end

-- A burn tick: a DamageInfo without attack or attacker; the victim's active status names who caused it.
local function dot_tick(victim, final, hp1)
    local di = R.object(DI, { ["<DamageHitController>k__BackingField"] = victim.hc }, {})
    R.enter(hook(HC, "damageProc"), { R.CTX, slot(victim.hc), slot(di) })
    R.enter(hook(HC, "updateDamage"), { R.CTX, slot(victim.hc), slot(di), R.int_slot(0xFFFFFFFF), R.f32_slot(final),
        R.int_slot(0) })
    victim.hp = hp1
    R.leave(nil)
    return R.leave(true)
end

-- `user` drinks item `id` (useItem > convertHealHp, then recoverHp on him; the target slot is null).
local function use_item(id, user, requested, hp1)
    R.enter(hook(IM, "useItem"), { R.CTX, slot(W.im), R.int_slot(id), slot(user), R.null_slot() })
    R.fire(hook(IM, "convertHealHp"), { R.CTX, R.f32_slot(requested), slot(user), R.int_slot(user.chara_id or 0),
        R.int_slot(id), R.int_slot(0) }, R.int_slot(requested))
    R.enter(hook(HC, "recoverHp"), { R.CTX, slot(user.hc), R.f32_slot(requested), R.int_slot(0), R.int_slot(0),
        R.int_slot(0) })
    user.hp = hp1
    R.leave(nil)
    return R.leave(true)
end

local function scene_change()
    return R.fire(hook(GM, "OnChangeSceneType"), { R.CTX, slot(W.gui), R.int_slot(3) }, nil)
end

-- `healer`'s healing spot touches `target`: a damageProc without updateDamage.
local function spot_touch(healer, target)
    local aud = R.object("app.AttackUserData", { _ElementType = -1 },
        { get_Name = function() return "ヒーリングスポット" end })
    local di = R.object(DI, {
        ["<DamageHitController>k__BackingField"] = target.hc,
        ["<AttackHitController>k__BackingField"] = healer.hc,
        ["<AttackUserData>k__BackingField"] = aud,
    }, {})
    R.enter(hook(HC, "damageProc"), { R.CTX, slot(target.hc), slot(di) })
    return R.leave(true)
end

-- recoverHp on `c` with no item use around it: its HP rises by `amount`.
local function spot_heal(c, amount)
    R.enter(hook(HC, "recoverHp"), { R.CTX, slot(c.hc), R.f32_slot(amount), R.int_slot(0), R.int_slot(0),
        R.int_slot(0) })
    c.hp = c.hp + amount
    R.leave(nil)
end

-- The battle mode drops to Normal and stays there: the fight finishes when the 3 s end grace is over.
local function end_battle()
    W.mode = 0
    frame()
    frame(3.1)
end

-- Battle music starts and ends around `inside`.
local function fight(inside)
    W.mode = 2
    frame()
    if inside then inside() end
    end_battle()
end

local function party_dealt(snap)
    local sum = 0
    for _, s in pairs(snap.actors) do sum = sum + s.dealt end
    return sum
end

local function lines_with(text, needle)
    local n = 0
    for line in (text or ""):gmatch("[^\n]+") do
        if line:find(needle, 1, true) then n = n + 1 end
    end
    return n
end

test("loads with no game types and reports them missing", function()
    world({ game = false })
    local M = load()
    local info = M.info()
    eq(info.version, "1.0.0", "version")
    eq(info.hooks, 0, "nothing hooked")
    eq(#R.hooks, 0, "no sdk.hook call")
    eq(#info.missing, #HOOKED + 1 + #CALLED, "every hooked method, the battle mode and the called ones are missing")
    for _, name in ipairs(HOOKED) do eq(contains(info.missing, name), true, "missing " .. name) end
    eq(contains(info.missing, BATTLE_MODE), true, "missing " .. BATTLE_MODE)
    for _, name in ipairs(CALLED) do eq(contains(info.missing, name), true, "missing " .. name) end
    eq(info.fighting, false, "fighting")
    eq(info.history, 0, "history")
    eq(mod("i18n").lang(), "en", "auto language without an answer from the game: English")

    frame()
    frame(1)
    frame(5)
    eq(M.info().frame, 3, "frames run")
    eq(M.info().errors, 0, "and raise nothing")
    eq(shown(), false, "no window without a fight")
    draw_ui()
    eq(ui.has_text(mod("i18n").t("missing_methods", #HOOKED + 1 + #CALLED)), true, "the notice in the REFramework menu")
    eq(#R.bad, 0, "no slot read with the wrong kind")
end)

test("the self-check also lists the game methods the meter calls without a hook", function()
    world()
    R.undeclare("app.GUIBase")
    local hc = R.type(HC)
    for i = #hc.methods, 1, -1 do
        if hc.methods[i].sig == "get_Hp" then table.remove(hc.methods, i) end
    end
    local M = load()
    local missing = M.info().missing
    eq(#missing, 2, "two missing: " .. T.str(missing))
    eq(contains(missing, HC .. ".get_Hp"), true, "HitController.get_Hp")
    eq(contains(missing, "app.GUIBase.getName(app.Character)"), true, "GUIBase.getName")
    eq(M.info().hooks, #HOOKED, "every hook is still installed")
    local notice = mod("i18n").t("missing_methods", 2)
    frame() -- the menu callback is registered from the first frame
    draw_ui()
    eq(ui.has_text(notice), true, "the notice in the REFramework menu")
    W.mode = 2
    frame()
    eq(ui.has_text(notice), true, "and under the live window")
    local logged = false
    for _, line in ipairs(R.logs) do
        if line:find("not found", 1, true) and line:find(HC .. ".get_Hp", 1, true) then logged = true end
    end
    eq(logged, true, "REFramework's log names them")
    -- the rest keeps working: the hit controllers still answer for themselves
    strike()
    end_battle()
    eq(M.info().history, 1, "the fight is counted")
end)

test("a full fake fight: mode 2, two hits, one heal, mode 0 → one history entry with the right totals", function()
    world({ settings = { debug = true } })
    local M = load()
    eq(#M.info().missing, 0, "nothing missing")
    eq(M.info().hooks, #HOOKED, "every method hooked")
    eq(M.info().hooks, 11, "v1's ten and the region step")
    frame()
    eq(M.info().fighting, false, "no fight in mode 0")
    eq(shown(), false, "nothing to show before the first fight")

    W.mode = 2
    frame()
    eq(M.info().fighting, true, "mode 2 starts the fight")
    eq(shown(), true, "the live window appears with the battle music")
    hit(W.casca, W.goblin, 405.1336, 2647.901)
    frame()
    hit(W.player, W.goblin, 500, 2147.901)
    frame()
    use_item(38, W.player, 550, 2144.926)
    frame(1)
    eq(ui.has_text("Casca"), true, "Casca's bar in the live window")
    eq(ui.has_text("Guts"), true, "Guts' bar in the live window")

    W.mode = 0
    frame()
    eq(M.info().fighting, true, "mode 0 only opens the end grace")
    eq(M.info().history, 0, "nothing is kept yet")
    eq(ui.has_text("Casca"), true, "the live window stays")
    frame(3.1)
    local info = M.info()
    eq(info.fighting, false, "the end of the grace ends it")
    eq(info.history, 1, "one history entry")
    local snap = M.state.history:get(1)
    local actors = mod("game/actors")
    local guts, casca, goblin = actors.of(W.player), actors.of(W.casca), actors.of(W.goblin)
    eq(snap.outcome, "end", "outcome")
    near(snap.actors[casca.key].dealt, 405.134, 1e-6, "Casca dealt")
    near(snap.actors[guts.key].dealt, 500, 1e-6, "Guts dealt")
    near(party_dealt(snap), 905.134, 1e-6, "party dealt")
    near(snap.actors[goblin.key].taken, 905.134, 1e-6, "the goblin took it all")
    eq(snap.actors[goblin.key].hits_taken, 2, "in two hits")
    near(snap.actors[guts.key].heal_done, 230.935, 1e-6, "Guts healed himself")
    near(snap.actors[guts.key].heal_sources["item:38"], 230.935, 1e-6, "with item 38")
    eq(shown(), true, "the window turns into the summary")
    eq(ui.has_text(mod("i18n").t("fight_over")), true, "summary title")

    local log = R.files[LOG_FILE] or ""
    eq(lines_with(log, "fight end"), 1, "one debug line for the fight")
    eq(lines_with(log, "dealt=905 taken=0 healed=231"), 1, "with its totals")

    -- after the fight nothing is counted anywhere
    use_item(38, W.player, 550, 2300)
    frame()
    eq(M.state.fight, nil, "no open fight")
    eq(M.info().fighting, false, "a heal starts no fight")
    eq(M.info().history, 1, "still one entry")
    eq(M.info().errors, 0, "no error caught")
    eq(#R.bad, 0, "no slot read with the wrong kind")
end)

test("scene change abandons the fight", function()
    world()
    local M = load()
    frame()
    W.mode = 2
    frame()
    hit(W.casca, W.goblin, 405.1336, 2647.901)
    local actors = mod("game/actors")
    local goblin = actors.of(W.goblin)
    eq(M.info().fighting, true, "fighting")

    -- a loaded save: the game has a new player character and is back in mode 0 (the party read on the frame after
    -- the hook sees the other player)
    W.player = char("ch000000_00", { name = "Guts", chara_id = 2891076981, hp = 2000, max_hp = 2400 })
    W.mode = 0
    scene_change()
    eq(M.info().fighting, true, "the hook itself only asks for a party read")
    local reads = #R.calls_of("get_PawnCharacterList")
    frame()
    eq(#R.calls_of("get_PawnCharacterList") > reads, true, "the party is read on the next frame")
    eq(M.info().fighting, false, "the open fight is over")
    eq(M.info().history, 1, "and is kept")
    local snap = M.state.history:get(1)
    eq(snap.outcome, "abandoned", "abandoned, not ended by the new world's battle mode")
    near(party_dealt(snap), 405.134, 1e-6, "with its hit")
    eq(mod("game/hits").info().open, 0, "no hit context left")
    eq(actors.of(W.goblin) ~= goblin, true, "cached actors dropped")
    eq(actors.of(W.goblin).key, goblin.key, "the same character gets the same key again")
    eq(shown(), true, "the abandoned fight's summary")
    eq(M.info().errors, 0, "no error caught")
end)

test("a player swap found by the party read resets once; the scene hook then only re-reads", function()
    world()
    local M = load()
    frame()
    W.mode = 2
    frame()
    frame() -- the party read the fight start asked for
    hit(W.casca, W.goblin, 405.1336, 2647.901)
    local actors = mod("game/actors")
    local reset, resets = actors.reset, 0
    actors.reset = function()
        resets = resets + 1
        return reset()
    end
    -- no hook at all: the once-a-second party read sees the new player
    W.player = char("ch000000_00", { name = "Guts", chara_id = 2891076981, hp = 2000, max_hp = 2400 })
    frame()
    eq(resets, 0, "not before the party is read")
    W.mode = 0 -- the new world's battle mode is read after the party, so the fight is abandoned, not ended
    frame(1)
    eq(resets, 1, "the read after a second resets")
    eq(M.info().fighting, false, "the fight is over")
    eq(M.state.history:get(1).outcome, "abandoned", "abandoned")
    -- the scene hook comes late, with the new player already remembered
    scene_change()
    frame()
    frame(1)
    actors.reset = reset
    eq(resets, 1, "reset happened once")
    eq(M.info().history, 1, "one fight")
    eq(M.info().errors, 0, "no error caught")
end)

test("a scene change with the same player keeps the open fight; a missing player resets", function()
    world()
    local M = load()
    frame()
    W.mode = 2
    frame()
    hit(W.casca, W.goblin, 405.1336, 2647.901)
    local actors = mod("game/actors")
    local goblin = actors.of(W.goblin)
    local reads = #R.calls_of("get_PawnCharacterList")
    scene_change()
    eq(M.info().fighting, true, "same player: the fight goes on")
    eq(actors.of(W.goblin), goblin, "cached actors kept")
    eq(#R.calls_of("get_PawnCharacterList"), reads, "nothing read inside the hook")
    frame()
    eq(#R.calls_of("get_PawnCharacterList") > reads, true, "the party is read again on the next frame")
    hit(W.player, W.goblin, 500, 2147.901)
    end_battle()
    eq(M.info().history, 1, "one fight")
    eq(M.state.history:get(1).outcome, "end", "it ended by the battle mode")
    near(party_dealt(M.state.history:get(1)), 905.134, 1e-6, "with both hits, before and after the scene change")

    -- no player (a load in progress): everything is reset
    W.mode = 2
    frame()
    strike()
    W.player = nil
    scene_change()
    eq(M.info().fighting, false, "no player: the fight is abandoned")
    eq(M.state.history:get(1).outcome, "abandoned", "outcome")
    eq(actors.of(W.goblin) ~= goblin, true, "cached actors dropped")
    W.mode = 0
    frame()
    eq(M.info().errors, 0, "no error caught")
end)

test("scene reset forgets enemy data", function()
    world()
    local calc = R.object(EDC, {}, {
        get_WeakPointSettings = function() return 64 end,
        get_ResistSettings = function() return 16 end,
        get_Defence = function() return 250 end,
        get_MagicDefence = function() return 250 end,
    })
    W.goblin.chara_id = 5201
    W.goblin.methods.get_DamageCalculator = function() return calc end
    local M = load()
    local actors, enemies = mod("game/actors"), mod("game/enemies")
    local function reads() return #R.calls_of("get_DamageCalculator") end
    frame()
    W.mode = 2
    frame()
    strike()
    eq(reads(), 1, "the first hit on the kind reads it")
    strike()
    eq(reads(), 1, "the second does not")
    local foe = enemies.data(W.goblin, actors.of(W.goblin))
    eq(foe.weak, 64, "the record")
    eq(foe.defence, 250, "with its numbers")
    eq(reads(), 1, "kept")
    -- a scene change that keeps the player keeps the data
    scene_change()
    eq(enemies.data(W.goblin, actors.of(W.goblin)), foe, "same player: the record stays")
    eq(reads(), 1, "nothing read again")
    -- no player: a new world, nothing is kept
    W.player = nil
    scene_change()
    local after = enemies.data(W.goblin, actors.of(W.goblin))
    eq(reads(), 2, "read again after the reset")
    eq(after ~= foe, true, "a new record")
    eq(after.weak, 64, "from the game")
    W.mode = 0
    frame()
    eq(M.info().errors, 0, "no error caught")
end)

test("the healing spot's heal goes on after its touches, but not into the next fight nor past a load", function()
    world()
    local M = load()
    local actors = mod("game/actors")
    frame()
    spot_touch(W.casca, W.player)       -- the frame before the fight opens
    W.mode = 2
    frame()
    strike()
    for _ = 1, 5 do frame(0.4) end      -- 2 s later, no touch since
    spot_heal(W.player, 1.5)
    spot_touch(W.casca, W.player)
    spot_heal(W.player, 1.5)            -- in the touch's frame
    for _ = 1, 5 do frame(0.5) end      -- 5 frames and 2.5 s later the spot no longer touches
    spot_heal(W.player, 1.5)
    frame(4)                            -- 6.5 s after the touch
    spot_heal(W.player, 1.5)
    -- touched as the battle ends; healed 4 frames and 3.2 s later, in the next fight
    spot_touch(W.casca, W.player)
    end_battle()
    frame()
    W.mode = 2
    frame()
    strike()
    spot_heal(W.player, 1.5)
    end_battle()
    eq(M.info().history, 2, "two fights")
    local casca = actors.of(W.casca).key
    local first, second = M.state.history:get(2), M.state.history:get(1)
    near(first.actors[casca].heal_done, 4.5, 1e-6, "2 s after the touch before the fight, the touch's frame and 2.5 s "
        .. "later: Casca")
    -- a heal on a party member that nobody can be found for is his own; the player did not hit: regeneration
    local player = actors.of(W.player).key
    near(first.actors[player].heal_sources["self:regen"], 1.5, 1e-6, "6.5 s later: his own")
    near(second.actors[player].heal_sources["self:regen"], 1.5, 1e-6, "the next fight: his own")
    eq(first.actors.other, nil, "nothing is «other»'s"); eq(second.actors.other, nil, "nor in the next fight")
    eq(second.actors[casca].heal_done, 0, "not Casca")

    -- a load forgets the touches
    W.mode = 2
    frame()
    spot_touch(W.casca, W.player)
    local key, f, t = actors.of(W.player).key, M.info().frame, M.state.t
    eq(M.state.attrib:healer_for(f, key, t), actors.of(W.casca), "the touch is known")
    W.player = nil
    scene_change()
    eq(M.state.attrib:healer_for(f, key, t), nil, "forgotten when the player is gone")
    eq(M.state.attrib:healer_for(f + 10, key, t + 1), nil, "and its lingering heal too")
    eq(M.info().errors, 0, "no error caught")
end)

-- What «Прочее» held turned out, logged in game, to be self-effects (a member's own damage and heals).
local EQUIPPED = "hasEquipedSkill(app.Character.JobEnum, app.HumanCustomSkillID)"

-- `c` is a Warrior; `pact`: with Blood Pact (Job05_ScarletVow) equipped.
local function warrior(c, pact)
    R.enum("app.HumanCustomSkillID", { None = 0, Job05_IndomitableLash = 58, Job05_ScarletVow = 111 })
    local jobs = R.object("app.JobContext", { CurrentJob = 5 })
    local skills = R.object("app.HumanSkillContext", {}, {
        [EQUIPPED] = function(_, job, id) return pact and job == 5 and id == 111 end,
    })
    local human = R.object("app.Human", { ["<SkillContext>k__BackingField"] = skills },
        { get_JobContext = function() return jobs end })
    c.methods.get_Human = function() return human end
end

-- A hit `victim` does to himself: no attacker, the DamageInfo names his own GameObject (Blood Pact's cost, a fall).
-- `fields`: more fields of the DamageInfo (its Position).
local function own_tick(victim, final, fields)
    local di = R.object(DI, {
        ["<DamageHitController>k__BackingField"] = victim.hc,
        ["<AttackGameObject>k__BackingField"] = victim.go, ["<DamageGameObject>k__BackingField"] = victim.go,
    }, {})
    for k, v in pairs(fields or {}) do di.fields[k] = v end
    R.enter(hook(HC, "damageProc"), { R.CTX, slot(victim.hc), slot(di) })
    R.enter(hook(HC, "updateDamage"), { R.CTX, slot(victim.hc), slot(di), R.int_slot(0xFFFFFFFF), R.f32_slot(final),
        R.int_slot(0) })
    victim.hp = victim.hp - final
    R.leave(nil)
    return R.leave(true)
end

local function row_names(rows)
    local out = {}
    for _, r in ipairs(rows or {}) do out[#out + 1] = r.name or r.label end
    return table.concat(out, ", ")
end

test("self-effects: Blood Pact's cost and a member's sourceless heals are his own, an enemy's fall a row of its own", function()
    world()
    warrior(W.casca, true)
    local M = load()
    local actors = mod("game/actors")
    frame()
    W.mode = 2
    frame()
    strike()                            -- Casca's own hit
    spot_heal(W.casca, 100)             -- in its frame: lifesteal
    frame(); frame(); frame()
    spot_heal(W.casca, 50)              -- 3 frames after it: lifesteal
    frame()
    spot_heal(W.casca, 2)               -- 4 frames after it: regeneration
    hit(W.player, W.goblin, 10, W.goblin.hp - 10)
    spot_heal(W.casca, 1)               -- the player's hit does not make Casca's heal lifesteal
    own_tick(W.casca, 1.6)              -- Blood Pact's cost, every frame
    frame()
    own_tick(W.casca, 1.6)
    own_tick(W.player, 5)               -- the player has no Blood Pact
    frame(3.1)
    own_tick(W.goblin, 1000)            -- the goblin falls, over 3 s after the party's last hit on it
    frame(1)
    local live = M.state.live_model
    eq(row_names(live.damage.rows), "Guts, Casca, Falls and environment", "the fall: a grey row after the party")
    eq(live.damage.rows[3].kind, "other", "grey"); eq(live.damage.total, "20", "outside the party's total")
    eq(row_names(live.taken.rows), "Self → Guts, Blood Pact → Casca", "each one's own, by source")
    eq(row_names(live.heal.rows), "Casca", "his own heals: his healing row"); eq(live.heal.total, "153", "in the total")
    end_battle()
    eq(M.info().history, 1, "the fight is kept")
    local snap = M.state.history:get(1)
    local casca, guts = snap.actors[actors.of(W.casca).key], snap.actors[actors.of(W.player).key]
    near(casca.heal_sources["self:lifesteal"], 150, 1e-6, "lifesteal: 0 and 3 frames after his hit")
    near(casca.heal_sources["self:regen"], 3, 1e-6, "regeneration: 4 frames after, and after another's hit")
    near(casca.taken_from["self:blood_pact"], 3.2, 1e-5, "Blood Pact's cost"); eq(casca.taken_from.other, nil, "not Other")
    near(casca.dealt, 10, 1e-9, "never dealt: his blow only")
    near(guts.taken_from["self:self"], 5, 1e-6, "the player's own"); near(guts.dealt, 10, 1e-9, "his blow only")
    near(snap.actors.env.dealt, 1000, 1e-6, "the fall"); eq(snap.actors.other, nil, "nothing left for «Прочее»")
    local summary = M.state.summary_model
    eq(row_names(summary.allies.rows), "Falls and environment", "the summary's grey rows")
    eq(row_names(summary.heal.rows), "Casca", "the summary's healing")
    eq(M.info().errors, 0, "no error caught")
    eq(#R.bad, 0, "no slot read with the wrong kind")
end)

-- Lifesteal is a heal the game asked to be at least 10 HP (logged in game: 30-507 HP; regeneration 1-4 HP).
test("self-effects: a heal of less than 10 HP right after his hit is regeneration; the amount asked decides", function()
    world()
    local M = load()
    local actors = mod("game/actors")
    frame()
    W.mode = 2
    frame()
    strike()
    spot_heal(W.casca, 9)               -- in the hit's frame, 9 HP: regeneration
    spot_heal(W.casca, 10)              -- 10 HP: lifesteal
    -- 50 HP asked, 5 gained (near his full HP): the amount asked says lifesteal
    R.enter(hook(HC, "recoverHp"), { R.CTX, slot(W.casca.hc), R.f32_slot(50), R.int_slot(0), R.int_slot(0),
        R.int_slot(0) })
    W.casca.hp = W.casca.hp + 5
    R.leave(nil)
    end_battle()
    local casca = M.state.history:get(1).actors[actors.of(W.casca).key]
    near(casca.heal_sources["self:regen"], 9, 1e-6, "the 9 HP heal")
    near(casca.heal_sources["self:lifesteal"], 15, 1e-6, "the 10 HP heal and the 5 HP one asked as 50")
end)

-- The in-game check found no lifesteal at all: the game heals inside his damageProc, before the hit is counted.
test("self-effects: lifesteal from the start of his hit, inside it too; a blow that removed nothing counts", function()
    world()
    local M = load()
    local actors = mod("game/actors")
    frame()
    W.mode = 2
    frame()
    strike()                            -- opens the fight
    for _ = 1, 5 do frame() end         -- that hit is too old now
    -- Casca's blow on the goblin: the game heals him inside it, before updateDamage
    local function di_of()
        local aud = R.object("app.AttackUserData", { _ElementType = -1 },
            { get_Name = function() return "CS_14_緋染_N軽攻撃" end })
        return R.object(DI, { ["<DamageHitController>k__BackingField"] = W.goblin.hc,
            ["<AttackHitController>k__BackingField"] = W.casca.hc, ["<AttackUserData>k__BackingField"] = aud }, {})
    end
    local di = di_of()
    R.enter(hook(HC, "damageProc"), { R.CTX, slot(W.goblin.hc), slot(di) })
    spot_heal(W.casca, 120)             -- inside the hit, before it is counted: lifesteal
    R.enter(hook(HC, "updateDamage"), { R.CTX, slot(W.goblin.hc), slot(di), R.int_slot(0xFFFFFFFF), R.f32_slot(300),
        R.int_slot(0) })
    W.goblin.hp = W.goblin.hp - 300
    R.leave(nil)
    R.leave(true)
    frame(); frame(); frame()
    spot_heal(W.casca, 40)              -- 3 frames after the start: lifesteal
    frame()
    spot_heal(W.casca, 30)              -- 4 frames: regeneration
    for _ = 1, 4 do frame() end
    -- a blow that removed nothing (blocked: no updateDamage) began all the same
    R.enter(hook(HC, "damageProc"), { R.CTX, slot(W.goblin.hc), slot(di_of()) })
    R.leave(true)
    spot_heal(W.casca, 25)              -- lifesteal
    for _ = 1, 4 do frame() end
    hit(W.player, W.goblin, 10, W.goblin.hp - 10)
    spot_heal(W.casca, 20)              -- the player's hit: regeneration
    end_battle()
    local casca = M.state.history:get(1).actors[actors.of(W.casca).key]
    near(casca.heal_sources["self:lifesteal"], 185, 1e-6, "inside his hit, 3 frames after it, after the blocked blow")
    near(casca.heal_sources["self:regen"], 50, 1e-6, "4 frames after, and after the player's hit")
    near(casca.dealt, 310, 1e-6, "his hits counted as before"); eq(casca.hits, 2, "two that took HP")
    eq(M.info().errors, 0, "no error caught")
end)

-- A strike is a hit on an enemy; the mage's healing-spot touch on a friend is none.
test("self-effects: a healing-spot touch on a friend does not make the mage's own heal lifesteal", function()
    world()
    local M = load()
    local actors = mod("game/actors")
    frame()
    W.mode = 2
    frame()
    hit(W.player, W.goblin, 10, W.goblin.hp - 10) -- opens the fight; the player's hit
    for _ = 1, 5 do frame() end
    spot_touch(W.casca, W.player)       -- Casca's healing spot touches the player
    spot_heal(W.casca, 50)              -- in the touch's frame, 50 HP on Casca with no source
    frame()
    strike()                            -- her blow on the goblin
    spot_heal(W.casca, 40)              -- lifesteal
    end_battle()
    local casca = M.state.history:get(1).actors[actors.of(W.casca).key]
    near(casca.heal_sources["self:regen"], 50, 1e-6, "after the touch: regeneration")
    near(casca.heal_sources["self:lifesteal"], 40, 1e-6, "after her blow on an enemy: lifesteal")
end)

-- Eir, an ally who casts from grimoires, healed herself and it went to «Прочее»: an ally's heal with no source is her
-- own, as a party member's.
test("self-effects: an ally's sourceless heals are her own, lifesteal after her blow; the party's and others' as before",
        function()
    world()
    -- the heal sink, to hand it a heal the game passes for friends only
    local heals = mod("game/heals")
    local install = heals.install
    heals.install = function(sink, attrib)
        W.heal_sink = sink
        return install(sink, attrib)
    end
    local M = load()
    local actors = mod("game/actors")
    local eir = char("ch300700_00_1", { name = "Eir", hp = 1200, max_hp = 1500 })
    local villager = char("ch300522_00_1", { name = "Claudia", hp = 500, max_hp = 800 })
    frame()
    W.mode = 2
    frame()
    strike()                            -- Casca's blow opens the fight
    hit(eir, W.goblin, 10, W.goblin.hp - 10)   -- Eir fights for the party: an ally from the end of this blow
    eq(actors.of(eir).kind, "ally", "an ally")
    for _ = 1, 5 do frame() end
    spot_heal(eir, 100)                 -- no blow of hers just before: her regeneration
    hit(eir, W.goblin, 10, W.goblin.hp - 10)   -- her blow
    spot_heal(eir, 100)                 -- in its frame: lifesteal
    frame(); frame(); frame()
    spot_heal(eir, 50)                  -- 3 frames after it: lifesteal
    frame()
    spot_heal(eir, 2)                   -- 4 frames after it: regeneration
    strike()
    spot_heal(W.casca, 40)              -- a party member's as before: lifesteal after her blow
    -- a neutral character in the fight (the player's blow) healed with no source: «Прочее»'s as before
    hit(W.player, villager, 5, villager.hp - 5)
    W.heal_sink.heal({ t = W.t, target = actors.of(villager), amount = 30, effective = 30, source = { kind = "other" } })
    end_battle()
    eq(M.info().history, 1, "the fight is kept")
    local snap = M.state.history:get(1)
    local her = snap.actors[actors.of(eir).key]
    near(her.heal_sources["self:lifesteal"], 150, 1e-6, "lifesteal: 0 and 3 frames after her blow")
    near(her.heal_sources["self:regen"], 102, 1e-6, "regeneration: before her blow, and 4 frames after it")
    near(her.heal_done, 252, 1e-6, "she healed"); near(her.heal_received, 252, 1e-6, "herself")
    eq(her.heal_sources.other, nil, "nothing of hers is «Прочее»'s")
    near(snap.actors[actors.of(W.casca).key].heal_sources["self:lifesteal"], 40, 1e-6, "Casca's lifesteal")
    near(snap.actors.other.heal_done, 30, 1e-6, "the neutral character's heal: «Прочее»'s")
    near(snap.actors.other.heal_sources.other, 30, 1e-6, "with no source")
    near(snap.actors[actors.of(villager).key].heal_received, 30, 1e-6, "on her")
    eq(M.info().errors, 0, "no error caught")
end)

-- Argent Tonic heals the party as the mage's Job03_FullRecover state ends; states are read only in a fight.
test("Argent Tonic: the mage's heal on the party is hers; her state is read only while a fight is open", function()
    world()
    R.enum("app.HumanCustomSkillID", { None = 0, Job03_FullRecover = 210 })
    local reads, value = 0, 0
    local human = R.object("app.Human", {}, {})
    setmetatable(human.fields, { __index = function(_, k)
        if k == "<CustomSkillState>k__BackingField" then reads = reads + 1; return value end
    end })
    W.casca.methods.get_Human = function() return human end
    local M = load()
    local actors = mod("game/actors")
    frame()
    -- no fight: her state is not read, so a Tonic just before the fight opens is not seen
    value = 210
    frame(); frame()
    value = 0
    eq(reads, 0, "nothing read outside a fight")
    W.mode = 2
    frame()
    strike()
    W.player.hp = 1000
    spot_heal(W.player, 1400)           -- 2 frames after her state ended, but it was never read
    eq(reads > 0, true, "read in the fight")
    for _ = 1, 12 do frame() end
    -- in the fight: her Tonic, then the heal as the state ends
    value = 210
    frame(); frame()
    value = 0
    frame()
    W.player.hp = 1000
    spot_heal(W.player, 1400)           -- 1 frame after her last frame in the state: hers
    for _ = 1, 10 do frame() end
    W.player.hp = 1000
    spot_heal(W.player, 1400)           -- 11 frames after it: the player's own
    end_battle()
    local snap = M.state.history:get(1)
    local casca, player = actors.of(W.casca).key, actors.of(W.player).key
    near(snap.actors[casca].heal_sources.skill, 1400, 1e-6, "Casca's Argent Tonic")
    near(snap.actors[player].heal_sources["self:regen"], 2800, 1e-6, "the other two: the player's own")
    eq(snap.detail.heals[casca][player]["skill_id:Job03_FullRecover"].n, 1, "by the skill")
    local after = reads
    for _ = 1, 5 do frame() end
    eq(reads, after, "no reads once the fight is over")
    eq(M.info().errors, 0, "no error caught")
end)

-- A slam or a part break on an enemy has no attacker and no AttackGameObject: «Падения и среда».
test("self-effects: a sourceless hit on an enemy with no AttackGameObject is «Падения и среда»; a DoT tick «Прочее»",
        function()
    world()
    local M = load()
    frame()
    W.mode = 2
    frame()
    strike()
    frame(3.1)                                    -- over 3 s after the party's last hit on it
    dot_tick(W.goblin, 1700, W.goblin.hp - 1700)  -- no attacker, no status: a slam
    W.burning[FIRE_SPREAD] = 0                    -- a burn nobody known caused
    dot_tick(W.goblin, 30, W.goblin.hp - 30)
    W.burning = {}
    end_battle()
    local snap = M.state.history:get(1)
    near(snap.actors.env.dealt, 1700, 1e-6, "the slam"); near(snap.actors.other.dealt, 30, 1e-6, "the burn tick")
end)

-- The Evil Eye's two bodies (one CharaID, one HP pool); a hit on one is mirrored on the other by a sourceless hit
-- whose Flag has bit 39 set.
test("linked bodies: the Evil Eye's hits are counted once, on one enemy", function()
    world()
    local eye_a = char("ch270000_00", { name = "Лихое око", chara_id = 469873306, hostile = true, hp = 650000,
        max_hp = 650000 })
    local eye_b = char("ch270000_00", { name = "Лихое око", chara_id = 469873306, hostile = true, hp = 650000,
        max_hp = 650000 })
    -- both bodies burn, by Casca's fire: a mirror on a burning body is still no tick of hers
    local burning = R.object("app.StatusConditionCtrl", {}, {
        [ACTIVE] = function(_, st) return st == FIRE_SPREAD end,
        [CAUSED] = function() return W.casca.chara_id end,
    })
    eye_a.methods.get_StatusConditionCtrl = function() return burning end
    eye_b.methods.get_StatusConditionCtrl = function() return burning end
    local function mirror(body, final, flag)
        local di = R.object(DI, { ["<DamageHitController>k__BackingField"] = body.hc, Flag = flag or 566935691817 }, {})
        R.enter(hook(HC, "damageProc"), { R.CTX, slot(body.hc), slot(di) })
        R.enter(hook(HC, "updateDamage"), { R.CTX, slot(body.hc), slot(di), R.int_slot(0xFFFFFFFF), R.f32_slot(final),
            R.int_slot(0) })
        body.hp = body.hp - final
        R.leave(nil)
        return R.leave(true)
    end
    local M = load()
    local actors = mod("game/actors")
    frame()
    W.mode = 2
    frame()
    hit(W.casca, eye_a, 1000, eye_a.hp - 1000)
    mirror(eye_b, 1000)                         -- the same frame
    frame()
    hit(W.player, eye_a, 2000, eye_a.hp - 2000)
    frame()
    mirror(eye_b, 2000)                         -- the next frame
    mirror(eye_b, 0, 549755822665)              -- a sync with no loss
    frame()
    hit(W.player, eye_b, 3000, eye_b.hp - 3000)  -- the party hits the other body
    mirror(eye_a, 3000)
    frame(1)
    local live = M.state.live_model
    eq(live.damage.total, "6 000", "the party's damage, once"); eq(#live.damage.rows, 2, "no grey row")
    end_battle()
    local snap = M.state.history:get(1)
    local a, b = actors.of(eye_a).key, actors.of(eye_b).key
    eq(snap.enemies[b], nil, "one body is no enemy of its own"); near(snap.actors[a].taken, 6000, 1e-6, "the pool's loss")
    near(snap.actors[actors.of(W.casca).key].dealt, 1000, 1e-6, "Casca's own hit only: no mirror as her burn tick")
    eq(snap.actors.env, nil, "nothing for «Падения и среда»")
    eq(#M.state.summary_model.enemies, 1, "one enemy row in the summary")
    eq(M.info().errors, 0, "no error caught")
end)

-- In a fight with Gagana the game made each pawn anew (two actor keys per pawn, one CharaID).
test("a pawn the game makes anew mid-fight stays one row; a late hit of his old object is his", function()
    world()
    local M = load()
    local actors = mod("game/actors")
    frame()
    W.mode = 2
    frame()
    frame()
    local old = W.casca
    hit(old, W.goblin, 100, W.goblin.hp - 100)
    local casca = actors.of(old)
    W.casca = char("ch100000_00", { name = "Casca", chara_id = old.chara_id, hp = 1500, max_hp = 1800 })
    W.pawns = { W.casca }
    hit(W.casca, W.goblin, 200, W.goblin.hp - 200)   -- before the next party read
    frame(1)                                          -- the party read
    hit(W.casca, W.goblin, 300, W.goblin.hp - 300)
    hit(old, W.goblin, 50, W.goblin.hp - 50)          -- the old object's late hit
    hit(W.goblin, old, 30, old.hp - 30)               -- and a late hit on it
    hit(W.goblin, W.casca, 40, W.casca.hp - 40)
    frame(1)
    local live = M.state.live_model
    eq(row_names(live.damage.rows), "Casca", "one row"); eq(live.damage.total, "650", "all her damage")
    eq(row_names(live.taken.rows), "Goblin → Casca", "one row of damage taken")
    end_battle()
    local snap = M.state.history:get(1)
    local rows = 0
    for _, s in pairs(snap.actors) do
        if s.actor.name == "Casca" then rows = rows + 1 end
    end
    eq(rows, 1, "one Casca in the fight")
    near(snap.actors[casca.key].dealt, 650, 1e-6, "before, after and the old object's late hit")
    near(snap.actors[casca.key].taken, 70, 1e-6, "taken on both objects")
    eq(actors.of(W.casca), casca, "the same actor"); eq(casca.kind, "pawn", "still a pawn")
    eq(M.info().errors, 0, "no error caught")
end)

test("self-effects: «Падения и среда» follows the «Прочее» switches", function()
    world({ settings = { live_other = false, summary_other = false, language = "ru" } })
    local M = load()
    frame()
    W.mode = 2
    frame()
    strike()
    frame(3.1)                          -- over 3 s after the party's last hit on it
    own_tick(W.goblin, 1000)
    frame(1)
    eq(row_names(M.state.live_model.damage.rows), "Casca", "no grey row in the live window")
    end_battle()
    eq(row_names(M.state.summary_model.allies.rows), "", "nor in the summary")
    near(M.state.history:get(1).actors.env.dealt, 1000, 1e-6, "still counted")
end)

test("a fight without a hit between the party and an enemy is not kept", function()
    world({ settings = { debug = true } })
    local M = load()
    frame()
    fight()
    eq(M.info().history, 0, "empty fight not pushed")
    eq(M.info().fighting, false, "not fighting")
    eq(shown(), false, "the window goes back to showing nothing")

    fight(strike)
    eq(M.info().history, 1, "a real fight is pushed")
    local real = M.state.history:get(1)
    eq(shown(), true, "its summary")

    -- battle music with only Casca's burn ticks in it: not a real fight either
    W.burning[FIRE_SPREAD] = W.casca.chara_id
    fight(function()
        dot_tick(W.goblin, 30, W.goblin.hp - 30)
        frame()
        dot_tick(W.goblin, 30, W.goblin.hp - 30)
    end)
    W.burning = {}
    eq(M.info().fighting, false, "ended with the music")
    eq(M.info().history, 1, "DoT-only fight not pushed")
    eq(M.state.history:get(1), real, "the real fight is still the newest")
    eq(shown(), true, "its summary is back")
    eq(ui.has_text(mod("i18n").t("fight_over")), true, "the summary title")
    local log = R.files[LOG_FILE] or ""
    eq(lines_with(log, "fight end"), 1, "one kept fight in the debug log")
    eq(lines_with(log, "dropped end"), 2, "two dropped ones")

    -- hidden before an empty fight, hidden after it
    ui.keys_down[F6] = true
    frame()
    ui.keys_down[F6] = nil
    eq(shown(), false, "hidden")
    fight()
    eq(shown(), false, "still hidden")
    eq(M.info().history, 1, "still one fight")

    -- an enemy's blow on the party counts too
    fight(function() hit(W.goblin, W.casca, 50, W.casca.hp - 50) end)
    eq(M.info().history, 2, "enemy -> party is a real fight")
    eq(#R.bad, 0, "no slot read with the wrong kind")
end)

test("a corpse hit after the end opens no fight", function()
    world()
    local M = load()
    frame()
    fight(function() hit(W.casca, W.goblin, 4000, 0) end) -- the goblin dies
    eq(M.info().history, 1, "the real fight")
    local real = M.state.history:get(1)
    eq(real.enemies[mod("game/actors").of(W.goblin).key].killed, true, "with its kill")

    -- the game still runs updateDamage on the dead goblin (hp0 = 0)
    hit(W.player, W.goblin, 500, 0)
    eq(M.info().fighting, false, "a hit on a corpse starts no fight")
    frame()
    hit(W.casca, W.goblin, 300, 0)
    frame(10.5)
    eq(M.info().history, 1, "no phantom fight")
    eq(M.state.history:get(1), real, "the real fight is still the newest")
    eq(M.state.mode, "summary", "its summary stays")
    eq(ui.has_text(mod("i18n").t("fight_over")), true, "the summary title")

    -- battle music with only corpse hits in it is not kept either
    fight(function() hit(W.player, W.goblin, 500, 0) end)
    eq(M.info().history, 1, "music and corpse hits only: not kept")
    eq(M.state.history:get(1), real, "still the real fight")
    eq(M.info().errors, 0, "no error caught")
end)

test("a burn tick after the end keeps the summary", function()
    world()
    local M = load()
    frame()
    fight(strike)
    eq(M.info().history, 1, "the real fight")
    local real = M.state.history:get(1)

    -- Casca's fire burns on after the music stopped
    W.burning[FIRE_SPREAD] = W.casca.chara_id
    dot_tick(W.goblin, 30, W.goblin.hp - 30)
    eq(M.info().fighting, false, "a burn tick starts no fight")
    frame()
    eq(M.state.mode, "summary", "the summary stays")
    eq(shown(), true, "on screen")
    eq(ui.has_text(mod("i18n").t("fight_over")), true, "the summary title")
    dot_tick(W.goblin, 30, W.goblin.hp - 30)
    frame(10.5)
    eq(M.info().history, 1, "nothing added")
    eq(M.state.history:get(1), real, "the real fight is still the newest")
    eq(M.info().errors, 0, "no error caught")
end)

test("toggle key hides and shows on the press edge", function()
    world()
    local M = load()
    frame()
    fight(strike)
    eq(shown(), true, "summary shown")
    ui.keys_down[F6] = true
    frame()
    eq(shown(), false, "pressed: hidden")
    frame()
    eq(shown(), false, "held: still hidden")
    ui.keys_down[F6] = nil
    frame()
    eq(shown(), false, "released: still hidden")
    ui.keys_down[F6] = true
    frame()
    eq(shown(), true, "pressed again: shown")
    frame()
    eq(shown(), true, "held: still shown")
    ui.keys_down[F6] = nil
    frame(600)
    eq(shown(), true, "summary_autohide 0: the summary stays")

    -- hidden during the summary, the next fight brings the window back
    ui.keys_down[F6] = true
    frame()
    ui.keys_down[F6] = nil
    eq(shown(), false, "hidden")
    W.mode = 2
    frame()
    eq(shown(), true, "a new fight shows the live window")
    eq(M.info().fighting, true, "fighting")

    -- the key comes from the settings (F8 is the settings window's)
    eq(M.state.settings:set("toggle_key", F9), true, "F9 set")
    ui.keys_down[F6] = true
    frame()
    eq(shown(), true, "F6 is no longer the key")
    ui.keys_down[F9] = true
    frame()
    eq(shown(), false, "F9 is")
end)

test("reload does not install hooks twice", function()
    world()
    load()
    frame()
    eq(#R.hooks, #HOOKED, "every method hooked once")
    W.mode = 2
    frame()
    hit(W.casca, W.goblin, 405.1336, 2647.901)

    local M = load() -- the same Lua state: DD2DM and DD2DM_HOOKS stay
    eq(#R.hooks, #HOOKED, "no method hooked twice")
    eq(M.info().hooks, #HOOKED, "all still counted as hooked")
    eq(W.entry_regs, 1, "BeginRendering asked for once")
    frame()
    eq(W.frame_regs, 1, "one frame callback")
    eq(#W.draw_ui, 1, "one menu callback")
    local f0 = M.info().frame
    frame()
    eq(M.info().frame, f0 + 1, "one step per frame")
    eq(M.info().loads, 2, "two loads")
    eq(M.info().fighting, true, "the open fight survived the reload")

    -- the hooks of the first load reach the handlers of the second, and the same fight
    hit(W.player, W.goblin, 500, 2147.901)
    end_battle()
    eq(M.info().history, 1, "one fight")
    near(party_dealt(M.state.history:get(1)), 905.134, 1e-6, "both hits, before and after the reload")
    eq(M.info().errors, 0, "no error caught")
end)

test("a missing method shows a one-line notice in the window, the rest keeps working", function()
    world()
    R.undeclare(CDC)
    local M = load()
    eq(#M.info().missing, 1, "one missing")
    eq(M.info().missing[1], CDC .. "." .. SIG.status, "applyStatusDamage")
    eq(M.info().hooks, #HOOKED - 1, "the others are hooked")
    frame()
    W.mode = 2
    frame()
    local notice = mod("i18n").t("missing_methods", 1)
    eq(ui.has_text(notice), true, "the notice under the live window")
    eq(ui.texts()[#ui.texts()], notice, "as its last line")
    hit(W.casca, W.goblin, 405.1336, 2647.901)
    end_battle()
    eq(ui.has_text(notice), true, "and under the summary")
    near(party_dealt(M.state.history:get(1)), 405.134, 1e-6, "hits are still counted")

    -- in Russian too, uncut (auto -> en -> ru in the settings window). On the stub's 1920 × 1080 the window pages
    -- by design and the Language row is on page 2 since the player's numbers' row came in; 1200 px give it one
    -- page, as a 1440p screen does
    ui.display = { x = 1920, y = 1200 }
    window_click("dd2dm_snext:language")
    window_click("dd2dm_snext:language")
    eq(mod("i18n").lang(), "ru", "in Russian")
    eq(ui.has_text(mod("i18n").t("missing_methods", 1)), true, "the Russian notice fits the window")
end)

test("the language follows the game; the settings window changes it at once and the save waits", function()
    world()
    R.method("via.gui.GUISystem", "get_MessageLanguage", function() return 6 end, STATIC)
    load()
    local i18n = mod("i18n")
    eq(i18n.lang(), "ru", "auto: the game's Russian")

    -- the settings window with its keys, the REFramework menu closed: the language is the first row of its last group
    frame()
    press(F8)
    for _ = 1, 8 do press(PGDN) end
    press(RIGHT) -- auto -> en
    eq(i18n.lang(), "en", "English at once")
    frame(1)
    eq(R.json_files[SETTINGS_FILE], nil, "not saved within 5 s")
    frame(4.1)
    eq(R.json_files[SETTINGS_FILE].language, "en", "saved after 5 s with the window open")
    press(RIGHT) -- en -> ru
    eq(i18n.lang(), "ru", "Russian at once")
    frame()
    eq(R.json_files[SETTINGS_FILE].language, "en", "the next save waits again")
    press(F8)
    eq(R.json_files[SETTINGS_FILE].language, "ru", "saved when the window closes")

    -- with the REFramework menu open too: saved once both are closed
    ui.drawing_ui = true
    window_click("dd2dm_sprev:language") -- ru -> en
    eq(i18n.lang(), "en", "English by the mouse")
    press(F8)
    eq(R.json_files[SETTINGS_FILE].language, "ru", "the menu is still open: the save waits")
    ui.drawing_ui = false
    frame()
    eq(R.json_files[SETTINGS_FILE].language, "en", "saved when the menu closes")

    -- auto again: the game is asked again now and then
    world()
    local lang = 1
    R.method("via.gui.GUISystem", "get_MessageLanguage", function() return lang end, STATIC)
    load()
    eq(mod("i18n").lang(), "en", "auto: the game's English")
    lang = 6
    frame(3)
    eq(mod("i18n").lang(), "ru", "the game switched to Russian")
end)

test("the summary hides itself after summary_autohide seconds", function()
    world({ settings = { summary_autohide = 5 } })
    load()
    frame()
    fight(strike)
    eq(shown(), true, "summary")
    frame(4.9)
    eq(shown(), true, "4.9 s")
    frame(0.2)
    eq(shown(), false, "5.1 s: hidden")
    ui.keys_down[F6] = true
    frame()
    eq(shown(), true, "the key shows it again")
    ui.keys_down[F6] = nil
    frame(5.1)
    eq(shown(), false, "and it hides again")
end)

test("window actions: history, details, back, hide and move", function()
    world()
    local M = load()
    frame()
    fight(function() hit(W.casca, W.goblin, 405.1336, 2647.901) end)
    fight(function() hit(W.player, W.goblin, 500, 2147.901) end)
    eq(M.info().history, 2, "two fights")
    local actors = mod("game/actors")
    ui.drawing_ui = true
    frame()
    eq(ui.has_text("Guts"), true, "the newest fight: Guts")
    eq(ui.has_text("Casca"), false, "Casca not in it")

    ui.press("history_next")
    frame()
    frame()
    eq(M.state.history_index, 2, "one step back")
    eq(ui.has_text("Casca"), true, "the older fight: Casca")
    ui.press("history_next")
    frame()
    eq(M.state.history_index, 2, "the oldest is the end")
    eq(ui.find("invisible_button", "history_next"), nil, "› is disabled there")
    ui.pressed = {}

    ui.press("damage:" .. actors.of(W.casca).key)
    frame()
    frame()
    eq(ui.find("invisible_button", "back") ~= nil, true, "Casca's details")
    ui.press("back")
    frame()
    frame()
    eq(ui.find("invisible_button", "back"), nil, "back to the summary")
    ui.press("damage:" .. actors.of(W.casca).key)
    frame()
    frame()
    eq(M.state.details_key, actors.of(W.casca).key, "details again")
    ui.drawing_ui = false
    frame()
    eq(M.state.details_key, nil, "dropped when the REFramework menu closes")
    frame()
    eq(ui.find("invisible_button", "back"), nil, "the summary again")

    ui.drawing_ui = true
    ui.press("hide")
    frame()
    frame()
    eq(shown(), false, "× hides")
    ui.keys_down[F6] = true
    frame()
    ui.keys_down[F6] = nil
    eq(shown(), true, "the key shows it")

    ui.mouse_down = true
    frame()
    ui.window_pos = { x = 220, y = 140 }
    frame()
    ui.mouse_down = false
    frame()
    eq(M.state.settings.values.window_x, 220, "dragged to x")
    eq(M.state.settings.values.window_y, 140, "and y")
    ui.drawing_ui = false
    frame()
    eq(R.json_files[SETTINGS_FILE].window_x, 220, "saved when the menu closes")
end)

test("a switched-off block is not built", function()
    world({ settings = { live_taken = false, summary_armor = false, summary_allies = false, summary_other = false } })
    local M = load()
    local i18n = mod("i18n")
    frame()
    W.mode = 2
    frame()
    strike()
    frame(1)
    local live = M.state.live_model
    eq(live.taken, nil, "the damage to the party is off")
    eq(live.damage ~= nil and live.heal ~= nil, true, "damage and healing are built")
    eq(ui.has_text(i18n.t("damage_to_party")), false, "and the window does not show it")
    eq(ui.has_text(i18n.t("damage_to_enemies")), true, "while the others it does")

    end_battle()
    frame()
    local summary = M.state.summary_model
    eq(summary.armor, nil, "the armor block is off"); eq(summary.allies, nil, "so is the allies block: both its switches")
    eq(summary.enemies ~= nil and summary.damage ~= nil and summary.heal ~= nil, true, "the others are built")
    eq(ui.has_text(i18n.t("armor")), false, "not shown either"); eq(ui.has_text(i18n.t("enemies")), true, "enemies are")
end)

test("the window is built with the settings' switches", function()
    world({ settings = { live_damage = false, live_other = false, show_allies = false, summary_enemies = false,
        summary_allies = false, summary_heal = false } })
    local M = load()
    local View = mod("view")
    local live, summary, live_show, summary_show = View.live, View.summary, nil, nil
    View.live = function(snap, t, ctx, show)
        live_show = show
        return live(snap, t, ctx, show)
    end
    View.summary = function(snap, ctx, show)
        summary_show = show
        return summary(snap, ctx, show)
    end
    frame()
    fight(strike)
    View.live, View.summary = live, summary
    local function show_of(show)
        local keys = {}
        for key, value in pairs(show) do keys[#keys + 1] = key .. "=" .. tostring(value) end
        table.sort(keys)
        return table.concat(keys, ",")
    end
    eq(show_of(live_show), "allies=false,damage=false,heal=true,other=false,taken=true", "live: live_*, show_allies")
    eq(show_of(summary_show), "allies=false,armor=true,damage=true,enemies=false,heal=false,other=true", "summary_*")
    eq(M.state.live_model, nil, "the live model went with the fight")
    eq(M.state.summary_model.enemies, nil, "and the summary was built with them")
end)

test("a switch change rebuilds the windows at once", function()
    world()
    local M = load()
    local i18n = mod("i18n")
    frame()
    fight(strike)
    eq(M.state.summary_model.heal ~= nil, true, "the summary has a healing block")
    window_set("summary_heal", false)
    eq(M.state.summary_model.heal, nil, "the summary is rebuilt without the block, in the frame of the click")
    eq(ui.has_text(i18n.t("healed")), false, "and drawn without it")
    window_set("summary_heal", true)
    eq(M.state.summary_model.heal ~= nil, true, "and with it again")

    -- every switch rebuilds the models, and a look setting does not
    local keys = { "live_damage", "live_taken", "live_heal", "show_allies", "live_other", "summary_enemies",
        "summary_damage", "summary_armor", "summary_heal", "summary_allies", "summary_other" }
    for _, key in ipairs(keys) do
        frame()
        local before = M.state.summary_model
        window_set(key, not M.state.settings.values[key])
        eq(M.state.summary_model ~= before, true, key .. " rebuilds the summary")
    end
    frame()
    local before = M.state.summary_model
    window_set("outline", false)
    eq(M.state.settings.values.outline, false, "the outline is off")
    eq(M.state.summary_model, before, "the look of the window needs no rebuild")

    -- in a fight the live window changes within the frame, not within 0.1 s
    world()
    M = load()
    frame()
    W.mode = 2
    frame()
    strike()
    frame(1)
    eq(M.state.live_model.taken ~= nil, true, "the damage to the party is there")
    window_set("live_taken", false)
    eq(M.state.live_model.taken, nil, "gone in the frame of the click")
end)

test("the live window is rebuilt at most 10 times a second", function()
    world()
    load()
    frame()
    W.mode = 2
    frame()
    local View = mod("view")
    local live, builds = View.live, 0
    View.live = function(...)
        builds = builds + 1
        return live(...)
    end
    for _ = 1, 60 do
        hit(W.casca, W.goblin, 10, W.goblin.hp - 10)
        frame(1 / 60)
    end
    View.live = live
    -- 6 or 7 frames of 1/60 s per build, depending on float rounding
    eq(builds >= 8 and builds <= 11, true, "about 10 builds in one second, got " .. builds)
end)

test("a failing view build is tried again only every 0.1 s and the window keeps drawing", function()
    world()
    local M = load()
    frame()
    W.mode = 2
    frame()
    strike()
    frame(1)
    eq(shown(), true, "a good live window")
    local View = mod("view")
    local live, summary, tries = View.live, View.summary, 0
    View.live = function()
        tries = tries + 1
        error("view broke")
    end
    local drawn = 0
    for _ = 1, 60 do
        frame(1 / 60)
        if shown() then drawn = drawn + 1 end
    end
    View.live = live
    eq(tries >= 8 and tries <= 11, true, "about 10 tries in one second, got " .. tries)
    eq(drawn, 60, "the last good live window stays on screen")
    eq(M.info().errors, tries, "every failure counted")

    -- a failing summary is not rebuilt on every frame either
    local summaries = 0
    View.summary = function()
        summaries = summaries + 1
        error("summary broke")
    end
    end_battle()
    frame()
    frame()
    View.summary = summary
    eq(summaries, 1, "one try")
    eq(M.info().history, 1, "the fight is kept anyway")
end)

test("a failing first live build is tried again only every 0.1 s too", function()
    world()
    local M = load()
    frame()
    local View = mod("view")
    local live, tries = View.live, 0
    View.live = function()
        tries = tries + 1
        error("view broke")
    end
    W.mode = 2
    frame()
    eq(M.info().fighting, true, "the fight is open")
    eq(tries, 1, "the first build is tried at once")
    for _ = 1, 59 do frame(1 / 60) end
    View.live = live
    eq(tries >= 8 and tries <= 11, true, "about 10 tries in one second, got " .. tries)
    eq(M.info().errors, tries, "every failure counted")
    frame(0.2)
    eq(M.state.live_model ~= nil, true, "a good build follows")
end)

test("each step of the game frame is guarded on its own", function()
    world()
    local M = load()
    frame()
    local battle, heals = mod("game/battle"), mod("game/heals")
    local poll, heals_poll, heal_polls = battle.poll, heals.poll, 0
    battle.poll = function() error("battle broke") end
    heals.poll = function(...)
        heal_polls = heal_polls + 1
        return heals_poll(...)
    end
    frame()
    frame()
    frame()
    eq(heal_polls, 3, "the HP poll runs although the battle poll raises")
    eq(M.info().errors, 3, "one error per frame")
    -- the clock still ticks: a hit-started fight ends by its idle timeout
    strike()
    eq(M.info().fighting, true, "a party hit starts a fight")
    frame(10.5)
    eq(M.info().fighting, false, "the idle timeout ends it")
    eq(M.info().history, 1, "and it is kept")
    battle.poll, heals.poll = poll, heals_poll
end)

test("the toggle key does nothing while the settings window waits for a new key, nor when it is the new key", function()
    world()
    local M = load()
    local Menu = mod("ui/menu")
    frame()
    fight(strike)
    eq(shown(), true, "summary")
    -- the settings window with its keys: PgDn to the keys group (the toggle key its first row), Enter waits for a key
    press(F8)
    for _ = 1, 7 do press(PGDN) end
    press(ENTER)
    eq(Menu.waiting_for(), "toggle_key", "the window waits for the toggle key")
    ui.keys_down[F6] = true
    frame()
    eq(M.state.hidden, false, "F6 while the window waits: no toggle")
    eq(M.state.settings.values.toggle_key, F6, "F6 is its own key: taken again, the wait is over")
    ui.keys_down[F6] = nil
    frame()
    press(ENTER)
    eq(Menu.capturing(), true, "waiting again")
    ui.keys_down[F9] = true
    frame()
    eq(M.state.settings.values.toggle_key, F9, "the window took F9")
    eq(Menu.capturing(), false, "the wait is over")
    eq(M.state.hidden, false, "F9 pressed for the wait: no toggle")
    frame()
    eq(M.state.hidden, false, "F9 still held right after it was chosen: no toggle")
    ui.keys_down[F9] = nil
    frame()
    press(F9)
    eq(M.state.hidden, true, "the next F9 press toggles")
    eq(overlay_shown(), true, "the meter stays while the settings window is open")
    press(F8)
    eq(overlay_shown(), false, "and hides when it closes")
    press(F9)
    eq(shown(), true, "F9 shows it again")

    -- a wait of the REFramework menu's button left behind by closing the menu does not keep the keys dead
    ui.drawing_ui = true
    frame()
    ui.press("dd2dm_settings_key")
    draw_ui()
    eq(Menu.waiting_for(), "settings_key", "the menu waits")
    ui.keys_down[F9] = true
    frame()
    eq(M.state.hidden, false, "the menu open and waiting: F9 does not toggle")
    ui.keys_down[F9] = nil
    ui.drawing_ui = false
    frame()
    press(F9)
    eq(M.state.hidden, true, "the menu is closed: F9 toggles")
    press(F8)
    eq(settings_shown(), true, "and F8 opens the settings window")
    eq(M.info().errors, 0, "no error caught")
end)

test("a short break of the game's battle does not split the fight; the debug log notes it", function()
    world({ settings = { debug = true } })
    local M = load()
    frame()
    W.mode = 2
    frame()
    hit(W.casca, W.goblin, 405.1336, 2647.901)
    local open = M.state.fight
    -- the game drops to Normal (the battle is ending) for two frames, then back to Battle
    W.mode, W.ending = 0, true
    frame()
    frame(0.03)
    eq(M.info().fighting, true, "the fight is still open")
    eq(M.state.mode, "live", "the window still shows it")
    W.mode = 2
    frame(0.03)
    W.ending = false
    eq(M.state.fight, open, "the same fight")
    eq(M.state.mode, "live", "nothing changed on screen")
    eq(M.info().history, 0, "nothing was finished")
    eq(lines_with(R.files[LOG_FILE], "fight resumed after 0.1s"), 1, "the debug log says so")
    hit(W.player, W.goblin, 500, 2147.901)
    end_battle()
    eq(M.info().history, 1, "one fight")
    local snap = M.state.history:get(1)
    near(party_dealt(snap), 905.134, 1e-6, "with the hits from before and after the break")
    eq(snap.outcome, "win", "the ending flag seen at the break stays")
    local log = R.files[LOG_FILE]
    eq(lines_with(log, "fight win"), 1, "one fight line")
    eq(lines_with(log, "resumed"), 1, "one resume line")
    eq(M.info().errors, 0, "no error caught")
end)

test("a party blow in the end grace takes the end back; the fight ends 3 s after the last mode 0", function()
    world({ settings = { debug = true } })
    local M = load()
    frame()
    W.mode = 2
    frame()
    strike()
    W.mode = 0
    frame()
    frame(1)
    strike() -- the blow comes while the mode is still Normal
    eq(M.info().fighting, true, "the same fight")
    eq(lines_with(R.files[LOG_FILE], "fight resumed after 1.0s"), 1, "the gap is in the debug log")
    -- the mode is still Normal: the next frame opens the grace again, from there
    frame()
    local at = M.state.t
    frame(2.9)
    eq(M.info().fighting, true, "2.9 s")
    frame(0.2)
    eq(M.info().fighting, false, "3.1 s")
    local snap = M.state.history:get(1)
    near(snap.t1, at, 1e-6, "it ends where the mode dropped, the grace is not in its length")
    eq(M.info().errors, 0, "no error caught")
end)

test("a party hit on a new enemy in the end grace starts a new fight: the minotaur and the deer", function()
    world({ settings = { debug = true } })
    W.deer = char("ch221001_00_1", { name = "Doe", hostile = true, hp = 250, max_hp = 250 })
    local M = load()
    frame()
    W.mode = 2
    frame()
    strike()                              -- the first enemy, W.goblin
    local first = M.state.fight
    W.mode, W.ending = 0, true            -- it dies, the battle ends
    frame()
    local ended_at = M.state.t
    frame(0.3)
    hit(W.player, W.deer, 100, 150)       -- the player hits a deer in the break
    eq(M.info().fighting, true, "a fight is open")
    eq(M.state.fight ~= first, true, "it is a new one")
    eq(M.info().history, 1, "the old fight was finished and kept")
    local actors = mod("game/actors")
    local old = M.state.history:get(1)
    eq(old.outcome, "win", "as a win")
    near(old.t1, ended_at, 1e-6, "at the moment the battle ended")
    eq(old.enemies[actors.of(W.goblin).key] ~= nil, true, "with its enemy")
    eq(old.enemies[actors.of(W.deer).key], nil, "and without the deer")
    near(party_dealt(old), 10, 1e-6, "and without the deer's damage")
    -- the deer's hit is in the new fight
    local snap = M.state.fight:snapshot(M.state.t)
    near(party_dealt(snap), 100, 1e-6, "the hit lands in the new fight")
    eq(snap.enemies[actors.of(W.deer).key] ~= nil, true, "the deer is its enemy")
    eq(snap.enemies[actors.of(W.goblin).key], nil, "not the goblin")
    eq(M.state.mode, "live", "the window shows the new fight")
    -- the game's battle mode stays at Normal; a fight that started with a hit ends by the idle timeout
    frame(10.5)
    eq(M.info().fighting, false, "the new fight ended")
    eq(M.info().history, 2, "and was kept")
    eq(M.state.history:get(1).enemies[actors.of(W.deer).key] ~= nil, true, "the newest is the deer's")
    eq(M.state.history:get(1).outcome, "end", "by the idle timeout")
    local log = R.files[LOG_FILE] or ""
    eq(lines_with(log, "fight win"), 1, "the first fight's line"); eq(lines_with(log, "fight end"), 1, "the second's")
    eq(lines_with(log, "resumed"), 0, "no resume")
    eq(M.info().errors, 0, "no error caught")
end)

test("a critter is no enemy: a party hit on a 1-HP hostile opens no fight, lists nothing, keeps none going", function()
    world()
    W.chicken = char("ch280000_00_4", { name = "Курица", hostile = true, hp = 1, max_hp = 1 })
    W.hen = char("ch280000_00_5", { name = "Курица", hostile = true, hp = 1, max_hp = 1 })
    W.deer = char("ch221001_00_1", { name = "Doe", hostile = true, hp = 250, max_hp = 250 })
    local M = load()
    frame()
    hit(W.player, W.chicken, 5, 0)          -- Uri's lightning on a chicken
    eq(M.info().fighting, false, "no fight")
    frame(1)
    hit(W.player, W.deer, 100, 150)         -- a deer of 250 HP still is a fight of its own
    eq(M.info().fighting, true, "the deer opens a fight")
    frame(6)
    hit(W.casca, W.hen, 5, 0)               -- 6 s later: Casca's blow on a critter is no party hit
    local actors = mod("game/actors")
    local snap = M.state.fight:snapshot(M.state.t, true)
    eq(snap.enemies[actors.of(W.hen).key], nil, "the hen is not its enemy")
    eq(snap.enemies[actors.of(W.deer).key] ~= nil, true, "the deer is")
    eq(snap.detail.foes[actors.of(W.hen).key], nil, "no enemy card")
    frame(4.5)                              -- 10.5 s after the deer: the idle timeout, the hen kept nothing going
    eq(M.info().fighting, false, "the fight ended")
    eq(M.info().history, 1, "one fight kept")
    local kept = M.state.history:get(1)
    eq(kept.enemies[actors.of(W.chicken).key], nil, "without the chicken")
    eq(kept.enemies[actors.of(W.hen).key], nil, "without the hen")
    local m = mod("journal").enemies(kept, { names = mod("names").new({}), i18n = mod("i18n") }, 1)
    eq(#m.list.rows, 1, "the journal lists the deer only")
    eq(M.info().errors, 0, "no error caught")
end)

test("the debug log writes every mode resume but only the first hit resume of a fight", function()
    world({ settings = { debug = true } })
    local M = load()
    frame()
    W.mode = 2
    frame()
    strike()
    W.mode = 0
    frame()
    strike()                      -- resumed by a hit on the goblin
    frame()                       -- the mode is still Normal: the grace opens again
    strike()                      -- and again
    frame()
    W.mode = 2
    frame()                       -- resumed by the mode
    W.mode = 0
    frame()
    W.mode = 2
    frame()                       -- and again
    W.mode = 0
    frame()
    strike()                      -- a hit again: not logged twice for this fight
    local log = R.files[LOG_FILE] or ""
    eq(lines_with(log, "fight resumed"), 3, "one hit resume and two mode resumes: " .. log)
    eq(lines_with(log, "by hit"), 1, "one by hit")
    eq(lines_with(log, "by mode"), 2, "two by mode")
    frame()
    frame(3.1)
    eq(M.info().history, 1, "one fight")
    -- the next fight logs its own first hit resume
    W.mode = 2
    frame()
    strike()
    W.mode = 0
    frame()
    strike()
    eq(lines_with(R.files[LOG_FILE], "by hit"), 2, "the next fight's first one")
    eq(M.info().errors, 0, "no error caught")
end)

test("a new world in the end grace ends the fight as the end said, not abandoned", function()
    world()
    local M = load()
    frame()
    W.mode = 2
    frame()
    frame()
    strike()
    W.mode, W.ending = 0, true
    frame()
    W.player = char("ch000000_00", { name = "Guts", chara_id = 2891076981, hp = 2000, max_hp = 2400 })
    frame(1)
    eq(M.info().fighting, false, "the load ends the fight")
    eq(M.state.history:get(1).outcome, "win", "with the outcome of the pending end")
end)

test("the fight line counts the hits that waited for an enemy the party never fought", function()
    world({ settings = { debug = true } })
    W.goblin2 = char("ch220003_00_16", { name = "Goblin", hostile = true, hp = 3000, max_hp = 3700 })
    W.hermit = char("ch300001_00", { name = "Hermit" })
    local M = load()
    frame()
    fight(function()
        strike()
        -- an NPC fights another goblin far away: its numbers do not join this fight
        hit(W.hermit, W.goblin2, 50, W.goblin2.hp - 50)
        hit(W.goblin2, W.hermit, 20, W.hermit.hp - 20)
        hit(W.hermit, W.goblin2, 50, W.goblin2.hp - 50)
    end)
    eq(M.info().history, 1, "one fight")
    local snap = M.state.history:get(1)
    local count = 0
    for _ in pairs(snap.enemies) do count = count + 1 end
    eq(count, 1, "only the goblin the party fought")
    near(party_dealt(snap), 10, 1e-6, "only Casca's blow")
    local log = R.files[LOG_FILE] or ""
    eq(lines_with(log, "enemies=1 killed=0 held=3"), 1, "three hits waited and were not counted: " .. log)
    -- the party touches the other goblin: the ally's blow that waited for it is counted, in front of the party's
    fight(function()
        strike()
        hit(W.hermit, W.goblin2, 50, W.goblin2.hp - 50)
        hit(W.casca, W.goblin2, 10, W.goblin2.hp - 10)
    end)
    snap = M.state.history:get(1)
    near(party_dealt(snap), 70, 1e-6, "Casca's two blows and the hermit's")
    eq(lines_with(R.files[LOG_FILE], "held=0"), 1, "nothing held in that fight")
    eq(M.info().errors, 0, "no error caught")
end)

-- A returning enemy continues the fight ------------------------------------------------------------------

-- A lesser demon (CharaID 7 unless said, 260 000 HP) at `hp`: each call a new game object, as the game makes it anew.
-- It can burn by Casca's fire (W.burning).
local function demon(hp, chara_id)
    local c = char("ch255000_00", { name = "Lesser demon", chara_id = chara_id or 7, hostile = true, hp = hp or 260000,
        max_hp = 260000 })
    local sc = R.object("app.StatusConditionCtrl", {}, {
        [ACTIVE] = function(_, s) return W.burning[s] ~= nil end,
        [CAUSED] = function(_, s) return W.burning[s] or 0 end,
    })
    c.methods.get_StatusConditionCtrl = function() return sc end
    return c
end

-- One frame at time `t` exactly.
local function frame_at(t)
    W.t = t
    frame(0)
end

-- Fight A: battle music from t = 50, the player takes the demon down to `left` (22 612 unless said), the battle ends
-- at t = 100 as a win, and the fight is finished at 103.1. `blow` replaces the player's blow. Gives the demon.
local function demon_fight(left, blow)
    local d = demon()
    W.mode = 2
    frame_at(50)
    if blow then blow(d) else hit(W.player, d, 237388, left or 22612) end
    W.mode, W.ending = 0, true
    frame_at(100)
    frame_at(103.1)
    W.ending = false
    return d
end

local function count_of(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

test("a returning enemy continues the fight: one fight, one enemy, the gap no fighting time", function()
    world({ settings = { debug = true, history_file = true } })
    local M = load()
    local actors = mod("game/actors")
    frame()
    local d1 = demon_fight()
    eq(M.info().history, 1, "fight A is kept")
    local a = M.state.history:get(1)
    near(a.duration, 50, 1e-6, "A: 50 s"); eq(a.outcome, "win", "as a win")
    -- the game makes the demon anew: a new object and key, the same CharaID, the HP it was left with
    local d2 = demon(22612)
    frame_at(115.5)
    hit(W.player, d2, 1000, 21612)
    eq(actors.of(d2).key ~= actors.of(d1).key, true, "a new key")
    eq(M.info().fighting, true, "a fight is open")
    eq(M.info().history, 1, "nothing more is kept")
    eq(M.state.history:get(1), a, "A's entry stays while it goes on")
    local open = M.state.fight:snapshot(M.state.t)
    eq(open.t0, 50, "the open fight is A, going on")
    eq(count_of(open.enemies), 1, "one enemy")
    near(open.enemies[actors.of(d1).key].hp, 21612, 1e-6, "the new object's hit lands on the old enemy")
    near(open.duration, 50, 1e-6, "the 15.5 s gap is no fighting time")
    eq(lines_with(R.files[LOG_FILE], "fight continued after 15.5s by a returning Lesser demon"), 1, "the debug line")
    -- the battle music comes back, Casca kills the demon, the battle ends
    W.mode = 2
    frame_at(116)
    frame_at(120)
    hit(W.casca, d2, 21612, 0)
    W.mode, W.ending = 0, true
    frame_at(125)
    eq(M.info().history, 1, "still one entry in the end grace")
    frame_at(128.1)
    eq(M.info().fighting, false, "it ended")
    eq(M.info().history, 1, "kept once: still one entry")
    local snap = M.state.history:get(1)
    eq(snap ~= a, true, "A's entry is replaced")
    eq(snap.t0, 50, "from A's start"); eq(snap.t1, 125, "to the new end"); eq(snap.outcome, "win", "its own outcome")
    near(snap.duration, 125 - 50 - 15.5, 1e-6, "without the gap"); near(snap.paused, 15.5, 1e-6, "the gap")
    eq(count_of(snap.enemies), 1, "one enemy")
    local e = snap.enemies[actors.of(d1).key]
    eq(e.killed, true, "the kill lands on the one enemy"); eq(e.killer, actors.of(W.casca).key, "Casca's")
    near(e.killed_at, 120 - 50 - 15.5, 1e-6, "killed at, in fighting time")
    near(snap.actors[actors.of(d1).key].taken, 260000, 1e-6, "all its HP, on one row")
    eq(snap.actors[actors.of(d2).key], nil, "no row for the new object")
    near(party_dealt(snap), 260000, 1e-6, "the party's damage, A's and the rest")
    eq(M.state.mode, "summary", "its summary")
    eq(M.state.history_index, 1, "the newest")
    frame()
    local back = json_decode(R.files[HISTORY_FILE])
    eq(#back, 1, "one fight in history.json"); near(back[1].duration, 59.5, 1e-6, "the continued one")
    local log = R.files[LOG_FILE]
    eq(lines_with(log, "fight win"), 2, "A's line and the continued fight's")
    eq(lines_with(log, "fight win 59.5s"), 1, "the continued fight's, with its fighting time")
    eq(M.info().errors, 0, "no error caught")
end)

test("the enemy's own blow first, then the party's: the blow before is the continued fight's too", function()
    world({ settings = { debug = true } })
    local M = load()
    local actors = mod("game/actors")
    frame()
    local d1 = demon_fight()
    local d2 = demon(22612)
    frame_at(115.5)
    hit(d2, W.player, 300, W.player.hp - 300)     -- it opens a fight of its own first
    eq(M.info().fighting, true, "a fight is open")
    eq(M.state.fight:snapshot(M.state.t).t0, 115.5, "a new one so far")
    frame_at(116)
    hit(W.player, d2, 1000, 21612)               -- the party's first blow decides
    local open = M.state.fight:snapshot(M.state.t)
    eq(open.t0, 50, "A goes on")
    near(open.duration, 50 + 0.5, 1e-6, "from the moment the new fight opened")
    eq(count_of(open.enemies), 1, "one enemy")
    near(open.actors[actors.of(W.player).key].taken_from[actors.of(d1).key], 300, 1e-6,
        "the blow before is counted, as the old enemy's")
    near(open.actors[actors.of(d1).key].taken, 237388 + 1000, 1e-6, "and the party's blow")
    eq(lines_with(R.files[LOG_FILE], "fight continued after 15.5s by a returning Lesser demon"), 1, "the debug line")
    frame(10.5)                                   -- no battle music: the idle timeout ends it
    eq(M.info().history, 1, "kept once")
    eq(M.info().errors, 0, "no error caught")
end)

test("no continuation when the hit is late, another kind, another HP, the enemy was killed or the fight dropped",
    function()
    -- `fight_a` makes the fight before (nil: the demon left at 22 612), then `first` lands the new fight's first blows
    -- at 115.5 unless said; the new fight is a fight of its own
    local function separate(what, first, fight_a)
        world({ settings = { debug = true } })
        local M = load()
        frame()
        if fight_a then fight_a() else demon_fight() end
        local kept = M.info().history
        local before = M.state.history:get(1)
        first()
        eq(M.info().fighting, true, what .. ": a fight is open")
        eq(M.state.fight:snapshot(M.state.t).t0 > 103.1, true, what .. ": a new one")
        eq(M.info().history, kept, what .. ": nothing kept yet")
        eq(lines_with(R.files[LOG_FILE], "fight continued"), 0, what .. ": no debug line")
        W.mode = 0
        frame()
        frame(10.5)                               -- the music's end grace, or the idle timeout
        eq(M.info().history, kept + 1, what .. ": kept as a fight of its own")
        eq(M.state.history:get(2), before, what .. ": the one before untouched")
        eq(M.info().errors, 0, what .. ": no error caught")
    end
    separate("31 s after", function()
        frame_at(131)
        hit(W.player, demon(22612), 1000, 21612)
    end)
    -- the battle music opens the fight inside the 30 s, the first blow lands after them
    separate("the music at 125, the blow 31 s after", function()
        W.mode = 2
        frame_at(125)
        frame_at(131)
        hit(W.player, demon(22612), 1000, 21612)
    end)
    separate("another CharaID", function()
        frame_at(115.5)
        hit(W.player, demon(22612, 8), 1000, 21612)
    end)
    separate("hp0 30 000", function()
        frame_at(115.5)
        hit(W.player, demon(30000), 1000, 29000)
    end)
    -- it never comes back healed (at most 0.1 % of its max HP above) nor more than 2 % lower
    separate("hp0 300 above", function()
        frame_at(115.5)
        hit(W.player, demon(22612 + 300), 1000, 22612 + 300 - 1000)
    end)
    separate("hp0 5 300 below, past 2 %", function()
        frame_at(115.5)
        hit(W.player, demon(22612 - 5300), 1000, 22612 - 5300 - 1000)
    end)
    separate("a full-HP enemy of the kind", function()
        frame_at(115.5)
        hit(W.player, demon(260000), 1000, 259000)
    end)
    -- killed: its 0 HP is within 260 of the new object's 100
    separate("the old enemy was killed", function()
        frame_at(115.5)
        hit(W.player, demon(100), 50, 50)
    end, function() demon_fight(0) end)
    -- only Casca's burn ticks on the demon in fight A: no hit between them, not kept, nothing to continue
    separate("the old fight was dropped", function()
        frame_at(115.5)
        hit(W.player, demon(22612), 1000, 21612)
    end, function()
        demon_fight(nil, function(d)
            W.burning[FIRE_SPREAD] = W.casca.chara_id
            dot_tick(d, 237388, 22612)
            W.burning = {}
        end)
    end)
    separate("the first blow on another kind", function()
        frame_at(115.5)
        hit(W.player, W.goblin, 10, W.goblin.hp - 10)
        hit(W.player, demon(22612), 1000, 21612)  -- too late: the first blow decided
    end)
end)

test("the demon's real numbers: left at 22 612, back at 21 504.8 (0.43 % lower), it continues the fight",
    function()
    world({ settings = { debug = true } })
    local M = load()
    local actors = mod("game/actors")
    frame()
    local d1 = demon_fight()
    local d2 = demon(21504.8)
    frame_at(115.5)
    hit(W.player, d2, 21504.8, 0)               -- the party takes what was there and kills it
    eq(M.state.fight:snapshot(M.state.t).t0, 50, "A goes on")
    eq(lines_with(R.files[LOG_FILE], "fight continued after 15.5s by a returning Lesser demon"), 1, "the debug line")
    frame(10.5)
    eq(M.info().history, 1, "one fight")
    local snap = M.state.history:get(1)
    eq(count_of(snap.enemies), 1, "one enemy")
    local e = snap.enemies[actors.of(d1).key]
    eq(e.killed, true, "killed, on the one enemy"); eq(e.killer, actors.of(W.player).key, "by the player")
    near(snap.actors[actors.of(d1).key].taken, 237388 + 21504.8, 1e-6, "what each fight's blows took")
    eq(M.info().errors, 0, "no error caught")
end)

test("at most 30 s: a blow 30 s after the end still continues the fight", function()
    world({ settings = { debug = true } })
    local M = load()
    frame()
    demon_fight()
    W.mode = 2
    frame_at(120)                                 -- the battle music first
    frame_at(130)
    hit(W.player, demon(22612), 1000, 21612)
    eq(M.state.fight:snapshot(M.state.t).t0, 50, "A goes on")
    eq(lines_with(R.files[LOG_FILE], "fight continued after 20.0s by a returning Lesser demon"), 1,
        "the gap ends where the new fight opened")
    near(M.state.fight:snapshot(M.state.t).duration, 50 + 10, 1e-6, "from 120 on it is fighting time")
    eq(M.info().errors, 0, "no error caught")
end)

test("two kept fights in a row: only the newest can be continued", function()
    world({ settings = { debug = true } })
    local M = load()
    frame()
    local d = demon_fight()
    -- B: the goblin, kept at 111.1
    W.mode = 2
    frame_at(105)
    strike()
    W.mode = 0
    frame_at(108)
    frame_at(111.1)
    eq(M.info().history, 2, "A and B kept")
    local b = M.state.history:get(1)
    frame_at(115.5)
    hit(W.player, demon(22612), 1000, 21612)      -- A's demon, back: A is not the newest
    eq(M.state.fight:snapshot(M.state.t).t0, 115.5, "a fight of its own")
    eq(lines_with(R.files[LOG_FILE], "fight continued"), 0, "no debug line")
    frame(10.5)
    eq(M.info().history, 3, "kept as a third fight")
    eq(M.state.history:get(2), b, "B untouched")
    eq(d ~= nil, true, "A's demon was left alive")

    -- the newest fight is the demon's: it is continued, and once it ends it can be continued again
    world({ settings = { debug = true } })
    M = load()
    frame()
    W.mode = 2
    frame_at(20)
    strike()
    W.mode = 0
    frame_at(25)
    frame_at(28.1)
    demon_fight()
    frame_at(115.5)
    hit(W.player, demon(22612), 1000, 21612)
    frame(10.5)
    eq(M.info().history, 2, "the goblin's fight and the demon's")
    eq(M.state.history:get(1).t1, 126, "it ended by the idle timeout at 126")
    frame_at(130)
    hit(W.player, demon(21612), 1000, 20612)      -- back again, 4 s after the continued fight ended
    eq(M.state.fight:snapshot(M.state.t).t0, 50, "the demon's fight goes on again")
    frame(10.5)
    eq(M.info().history, 2, "still two")
    near(M.state.history:get(1).paused, 15.5 + 4, 1e-6, "both gaps")
    eq(lines_with(R.files[LOG_FILE], "fight continued"), 2, "two debug lines")
    eq(M.info().errors, 0, "no error caught")
end)

test("a continued fight that ends again is kept once, in place of the old entry; the journal shows it newest",
    function()
    world({ settings = { history_file = true } })
    local M = load()
    local i18n = mod("i18n")
    frame()
    W.mode = 2
    frame_at(20)
    strike()
    W.mode = 0
    frame_at(25)
    frame_at(28.1)
    local goblin = M.state.history:get(1)
    demon_fight()
    eq(M.info().history, 2, "the goblin's fight and A")
    press(F7)
    local J = M.state.journal
    eq(J.index, 1, "the journal on A")
    frame_at(115.5)
    hit(W.player, demon(22612), 1000, 21612)
    W.mode = 2
    frame_at(116)
    W.mode = 0
    frame_at(120)
    frame_at(123.1)
    eq(M.info().fighting, false, "it ended")
    eq(M.info().history, 2, "kept once: still two fights")
    eq(M.state.history:get(2), goblin, "the goblin's fight still second")
    eq(J.index, 1, "the journal on the newest")
    eq(J.model.header.fight, i18n.t("jfight_of", 1, 2), "of two")
    eq(J.model.header.line:find(i18n.time(120 - 50 - 15.5), 1, true) ~= nil, true,
        "with the continued fight's time: " .. tostring(J.model.header.line))
    frame()
    local back = json_decode(R.files[HISTORY_FILE])
    eq(#back, 2, "two fights in history.json")
    near(back[1].duration, 54.5, 1e-6, "the newest is the continued fight")
    eq(back[1].t0, 50, "from A's start")
    eq(M.info().errors, 0, "no error caught")
end)

test("debug log: one line per fight and per caught error, only when on, at most 5 MB", function()
    world()
    load()
    frame()
    fight(strike)
    eq(R.files[LOG_FILE], nil, "debug off: no file")

    world({ settings = { debug = true } })
    local M = load()
    frame()
    W.mode = 2
    frame()
    local begin_window = imgui.begin_window
    imgui.begin_window = function() error("boom") end
    frame()
    local log = R.files[LOG_FILE] or ""
    eq(lines_with(log, "error overlay"), 1, "the drawing error is logged")
    eq(lines_with(log, "boom"), 1, "with its message")
    for _ = 1, 50 do frame() end
    imgui.begin_window = begin_window
    eq(lines_with(R.files[LOG_FILE], "boom"), 10, "an error of every frame: its first 10 only")
    eq(M.info().errors, 51, "but all counted")
    eq(ui.balanced(), true, "imgui stacks balanced")

    -- the cap: one more line fits, then a last line says the log is full
    world({ settings = { debug = true } })
    M = load()
    M.state.log_bytes = LOG_MAX - 200
    frame()
    fight(strike)
    fight(strike)
    fight(strike)
    log = R.files[LOG_FILE] or ""
    eq(lines_with(log, "fight end"), 1, "one fight line fits")
    eq(lines_with(log, "5 MB"), 1, "then the log says it is full")
    eq(M.state.log_bytes <= LOG_MAX, true, "never past 5 MB")

    -- each game session starts the log afresh, then appends; a reload is the same session
    world({ settings = { debug = true } })
    R.files[LOG_FILE] = "an earlier session, with room left\n"
    load()
    frame()
    fight(strike)
    log = R.files[LOG_FILE]
    eq(log:find("an earlier session", 1, true), nil, "the earlier session's log is gone")
    eq(lines_with(log, "fight end"), 1, "the first fight of the session")
    fight(strike)
    eq(lines_with(R.files[LOG_FILE], "fight end"), 2, "the next one is appended")
    load()
    frame()
    fight(strike)
    eq(lines_with(R.files[LOG_FILE], "fight end"), 3, "a reload appends too")
end)

test("a draw call the overlay finds missing is named in info() and once in the debug log", function()
    world({ settings = { debug = true } })
    local M = load()
    frame()
    W.mode = 2
    frame()
    eq(#M.info().draw_missing, 0, "nothing missing")
    eq(lines_with(R.files[LOG_FILE], "draw call missing"), 0, "nothing logged")

    -- a REFramework without the gradient: the bands fade in steps, and the mod says so
    local multi = ui.draw_list.add_rect_filled_multi_color
    ui.draw_list.add_rect_filled_multi_color = nil
    frame()
    for _ = 1, 5 do frame() end
    ui.draw_list.add_rect_filled_multi_color = multi
    eq(table.concat(M.info().draw_missing, ","), "add_rect_filled_multi_color", "named in info()")
    eq(lines_with(R.files[LOG_FILE], "draw call missing: add_rect_filled_multi_color"), 1, "one debug line, not one a frame")
    eq(M.info().errors, 0, "no error: the overlay draws without it")

    -- without the debug log nothing is written, info() still tells
    world()
    M = load()
    frame()
    W.mode = 2
    ui.draw_list.add_rect_filled_multi_color = nil
    frame()
    ui.draw_list.add_rect_filled_multi_color = multi
    eq(table.concat(M.info().draw_missing, ","), "add_rect_filled_multi_color", "info() with debug off")
    eq(R.files[LOG_FILE], nil, "no debug.log")
end)

-- history.json ---------------------------------------------------------------------------------------

-- A fight as the file holds it once decoded; i = 1 is the newest.
local function saved_fight(i)
    return { v = 2, t0 = 1000 - i, t1 = 1001 - i, outcome = "end", duration = i, actors = {}, enemies = {}, types = {} }
end

local function saved_fights(n)
    local list = {}
    for i = 1, n do list[i] = saved_fight(i) end
    return list
end

-- What the mod does to history.json from now on: seen.reads (json.load_file calls), seen.opens (the modes of io.open
-- calls); seen.fail makes opening it fail, seen.broken makes reading it raise.
local function watch_history_file()
    local seen = { reads = 0, opens = {} }
    local load_file, open = json.load_file, io.open
    json.load_file = function(path, ...)
        if path == HISTORY_FILE then
            seen.reads = seen.reads + 1
            if seen.broken then error("not json") end
        end
        return load_file(path, ...)
    end
    io.open = function(path, mode, ...)
        if path == HISTORY_FILE then
            seen.opens[#seen.opens + 1] = mode or "r"
            if seen.fail then return nil end
        end
        return open(path, mode, ...)
    end
    return seen
end

test("history_file off: nothing read or written", function()
    world()
    R.json_files[HISTORY_FILE] = saved_fights(3)
    R.files[HISTORY_FILE] = "an earlier session's file"
    local seen = watch_history_file()
    local M = load()
    eq(M.info().history, 0, "nothing loaded")
    frame()
    fight(strike)
    fight(strike)
    eq(M.info().history, 2, "the two fights of this session only")
    ui.drawing_ui = true
    frame()
    draw_ui()
    frame()
    eq(seen.reads, 0, "never read")
    eq(#seen.opens, 0, "never opened")
    eq(R.files[HISTORY_FILE], "an earlier session's file", "the file is left alone")
    window_set("history_file", false)
    eq(#seen.opens, 0, "and switching it off writes nothing")
    eq(M.info().errors, 0, "no error caught")
end)

test("a kept fight writes history.json", function()
    world({ settings = { history_file = true } })
    local seen = watch_history_file()
    local M = load()
    frame()
    fight()
    eq(M.info().history, 0, "a fight with no blow is dropped")
    eq(R.files[HISTORY_FILE], nil, "and writes nothing")
    fight(strike)
    local text = R.files[HISTORY_FILE]
    eq(text:sub(1, 2), "[{", "an array of fights")
    eq(text:find('"v":2', 1, true) ~= nil, true, "with the version")
    local actors = mod("game/actors")
    local goblin, casca = actors.of(W.goblin).key, actors.of(W.casca).key
    local back = json_decode(text)
    eq(#back, 1, "one fight")
    near(back[1].actors[casca].dealt, 10, 1e-6, "Casca's damage")
    near(back[1].detail.foes[goblin].by[casca].dealt, 10, 1e-6, "the detail is there")
    eq(#back[1].detail.record, 1, "with the record")
    eq(#seen.opens, 1, "one write")
    eq(seen.opens[1], "w", "that replaces the file")

    fight(strike)
    back = json_decode(R.files[HISTORY_FILE])
    eq(#back, 2, "the whole history")
    eq(back[1].t0 > back[2].t0, true, "newest first")
    eq(#seen.opens, 2, "one write per kept fight")
    eq(M.info().errors, 0, "no error caught")
end)

test("history loads at start, newest first, capped by history_size", function()
    world({ settings = { history_file = true, history_size = 32 } })
    R.json_files[HISTORY_FILE] = saved_fights(40)
    local seen = watch_history_file()
    local M = load()
    eq(M.info().history, 32, "32 of the 40")
    eq(M.state.history:get(1).duration, 1, "the newest first")
    eq(M.state.history:get(32).duration, 32, "down to the 32nd")
    eq(seen.reads, 1, "read once")
    eq(#seen.opens, 0, "loading writes nothing")
    load()
    eq(seen.reads, 1, "a reload of the script is the same Lua state: not read again")
    eq(M.info().history, 32, "and the history stays")

    frame()
    fight(strike)
    local back = json_decode(R.files[HISTORY_FILE])
    eq(#back, 32, "the loaded fights are written back with the new one, the oldest gone")
    eq(back[2].duration, 1, "the loaded newest follows the new fight")
    eq(back[32].duration, 31, "(the 32nd is the 31st of the file)")
    eq(M.info().errors, 0, "no error caught")

    world({ settings = { history_file = true, history_size = 5 } })
    R.json_files[HISTORY_FILE] = saved_fights(40)
    M = load()
    eq(M.info().history, 5, "history_size caps it")
    eq(M.state.history:get(1).duration, 1, "the newest of the file first")
    eq(M.state.history:get(5).duration, 5, "the fifth")
end)

test("the fights of the file are made into text at the load, not in the frame of the first kept fight", function()
    world({ settings = { history_file = true } })
    local walked = 0
    local old = setmetatable(saved_fight(1), { __pairs = function(t)
        walked = walked + 1
        return next, t, nil
    end })
    R.json_files[HISTORY_FILE] = { old }
    local M = load()
    eq(M.info().history, 1, "loaded")
    eq(walked, 1, "written out once, at the load")
    frame()
    fight(strike)
    eq(walked, 1, "and not again when the next fight is kept")
    eq(#json_decode(R.files[HISTORY_FILE]), 2, "yet it is in the file")
end)

test("a broken history.json is ignored", function()
    local junk = { "garbage", 42, true, { "x", 1, { v = 1 } }, { v = 2, actors = {}, enemies = {}, duration = 1 },
        { { v = 2, actors = {}, enemies = {} } } }
    for i, content in ipairs(junk) do
        world({ settings = { history_file = true } })
        R.json_files[HISTORY_FILE] = content
        local M = load()
        eq(M.info().history, 0, "junk " .. i .. ": no history")
        eq(M.info().errors, 0, "junk " .. i .. ": no error")
        frame()
        fight(strike)
        eq(M.info().history, 1, "junk " .. i .. ": the mod works")
        eq(R.files[HISTORY_FILE]:sub(1, 2), "[{", "junk " .. i .. ": the file is made afresh")
    end

    world({ settings = { history_file = true, debug = true } })
    local seen = watch_history_file()
    seen.broken = true
    local M = load()
    eq(seen.reads, 1, "a reader that raises was tried")
    eq(M.info().history, 0, "no history")
    eq(M.info().errors, 0, "and no error")
    frame()
    fight(strike)
    eq(M.info().history, 1, "the mod works")

    world({ settings = { history_file = true } })
    R.json_files[HISTORY_FILE] = { saved_fight(2), "junk", saved_fight(1) }
    M = load()
    eq(M.info().history, 2, "the valid fights of a half-broken file")
    eq(M.state.history:get(1).duration, 2, "in their order")
end)

test("switching history_file on writes at once", function()
    world()
    local seen = watch_history_file()
    local M = load()
    frame()
    fight(strike)
    eq(R.files[HISTORY_FILE], nil, "off: nothing written")
    ui.drawing_ui = true
    frame()
    window_set("history_file", true)
    eq(#seen.opens, 1, "written within the frame of the click")
    eq(seen.opens[1], "w", "as a whole")
    local back = json_decode(R.files[HISTORY_FILE])
    eq(#back, 1, "the fight of this session")
    eq(M.state.settings.values.history_file, true, "the setting is on")
    eq(R.json_files[SETTINGS_FILE].history_file, true, "and saved with the settings")
    frame()
    eq(#seen.opens, 1, "once, not on every frame")

    window_set("history_file", false)
    eq(#seen.opens, 1, "switching it off writes nothing")
    ui.drawing_ui = false
    frame()
    fight(strike)
    eq(#seen.opens, 1, "and a fight while it is off does not touch the file")
    eq(#json_decode(R.files[HISTORY_FILE]), 1, "the file keeps what it had")

    -- nothing to write yet: the history of this session is empty, so is the file
    world()
    load()
    frame()
    ui.drawing_ui = true
    frame()
    window_set("history_file", true)
    eq(R.files[HISTORY_FILE], "[]", "an empty history")
end)

test("switching history_file on keeps the fights the file already has", function()
    -- an earlier game session kept 3 fights in the file, then the setting was switched off
    world({ settings = { history_file = true } })
    load()
    frame()
    for _ = 1, 3 do fight(strike) end
    local earlier = json_decode(R.files[HISTORY_FILE])
    eq(#earlier, 3, "the earlier session wrote 3 fights")

    -- this game session starts with the setting off, so the file is not read at the start
    world()
    R.json_files[HISTORY_FILE] = earlier
    local seen = watch_history_file()
    local M = load()
    eq(seen.reads, 0, "off at the start: not read")
    eq(M.info().history, 0, "nothing loaded")
    ui.drawing_ui = true
    frame()
    window_set("history_file", true)
    eq(seen.reads, 1, "read when the setting is switched on")
    local back = json_decode(R.files[HISTORY_FILE])
    eq(#back, 3, "the 3 fights of the earlier session are still in the file")
    eq(back[1].t0, earlier[1].t0, "newest first")
    eq(back[3].t0, earlier[3].t0, "down to the oldest")
    eq(M.info().history, 3, "and in the history")

    -- off and on again in the same Lua state: the file is not read again, so nothing is in it twice
    window_set("history_file", false)
    window_set("history_file", true)
    eq(seen.reads, 1, "read once per Lua state")
    eq(#json_decode(R.files[HISTORY_FILE]), 3, "nothing twice")
    eq(M.info().history, 3, "nor in the history")
    eq(M.info().errors, 0, "no error caught")

    -- fights of this session kept before the switch-on are newer than the file's: they come first
    world()
    R.json_files[HISTORY_FILE] = saved_fights(3)
    M = load()
    frame()
    fight(strike)
    local this_one = M.state.history:get(1)
    ui.drawing_ui = true
    frame()
    window_set("history_file", true)
    back = json_decode(R.files[HISTORY_FILE])
    eq(#back, 4, "1 fight of this session and the 3 of the file")
    near(back[1].t0, this_one.t0, 1e-6, "this session's fight first")
    eq(back[2].duration, 1, "then the file's newest")
    eq(back[4].duration, 3, "down to its oldest")
    eq(M.state.history:get(1), this_one, "the history in the same order")
    eq(M.info().history, 4, "4 fights")

    -- history_size caps the two together, the file's oldest go first
    world({ settings = { history_size = 5 } })
    R.json_files[HISTORY_FILE] = saved_fights(40)
    M = load()
    frame()
    fight(strike)
    fight(strike)
    ui.drawing_ui = true
    frame()
    window_set("history_file", true)
    eq(M.info().history, 5, "5 in all")
    eq(M.state.history:get(3).duration, 1, "after this session's 2, the file's newest")
    eq(M.state.history:get(5).duration, 3, "and the file's third")
    eq(#json_decode(R.files[HISTORY_FILE]), 5, "the file holds the same 5")
    eq(M.info().errors, 0, "no error caught")
end)

test("a history.json that cannot be written costs one debug line", function()
    world({ settings = { history_file = true, debug = true } })
    local seen = watch_history_file()
    seen.fail = true
    local M = load()
    frame()
    fight(strike)
    eq(M.info().history, 1, "the fight is kept")
    eq(M.info().errors, 0, "no error caught")
    eq(lines_with(R.files[LOG_FILE], "history: could not write DD2DamageMeter/history.json"), 1, "one debug line")
    seen.fail = false
    fight(strike)
    eq(#json_decode(R.files[HISTORY_FILE]), 2, "the next fight writes it all")
    eq(lines_with(R.files[LOG_FILE], "history: could not write"), 1, "and says nothing more")

    -- without the debug log nothing is said
    world({ settings = { history_file = true } })
    seen = watch_history_file()
    seen.fail = true
    M = load()
    frame()
    fight(strike)
    eq(R.files[LOG_FILE], nil, "no debug.log")
    eq(M.info().history, 1, "the fight is kept")
end)

test("the history keeps 32 fights", function()
    world({ settings = { history_size = 32, history_file = true } })
    local M = load()
    frame()
    for _ = 1, 33 do fight(strike) end
    eq(M.info().history, 32, "32 of the 33")
    for i = 1, 31 do
        eq(M.state.history:get(i).t0 > M.state.history:get(i + 1).t0, true, "newest first at " .. i)
    end
    eq(M.state.history:get(1).detail ~= nil, true, "each with its detail")
    local text = R.files[HISTORY_FILE]
    eq(#json_decode(text), 32, "the file holds the same 32")
    eq(#text <= mod("history_file").MAX_BYTES, true, "under 4 MB")
    eq(M.info().errors, 0, "no error caught")
end)

test("a kept fight takes one full snapshot, a dropped one and the live window none", function()
    world()
    local M = load()
    local Fight = mod("fight")
    local snapshot, full = Fight.snapshot, 0
    Fight.snapshot = function(self, now, is_full)
        if is_full then full = full + 1 end
        return snapshot(self, now, is_full)
    end
    frame()
    W.mode = 2
    frame()
    strike()
    for _ = 1, 5 do frame(0.2) end
    eq(full, 0, "the live window takes none")
    end_battle()
    eq(full, 1, "one at the end of a kept fight")
    local goblin = mod("game/actors").of(W.goblin).key
    local detail = M.state.history:get(1).detail
    eq(type(detail), "table", "the kept fight carries its detail")
    eq(detail.foes[goblin] ~= nil, true, "with the enemy")
    eq(#detail.record, 1, "and the record")
    fight()
    eq(full, 1, "a dropped fight takes none")
    Fight.snapshot = snapshot
    eq(M.info().errors, 0, "no error caught")
end)

-- The journal ---------------------------------------------------------------------------------------

-- The keys the mod asks reframework:is_key_down about from now on: vk -> times asked.
local function watch_keys()
    local asked = {}
    local is_key_down = reframework.is_key_down
    reframework.is_key_down = function(self, vk)
        asked[vk] = (asked[vk] or 0) + 1
        return is_key_down(self, vk)
    end
    return asked
end

test("F7 opens and closes the journal", function()
    world()
    local M = load()
    local i18n = mod("i18n")
    frame()
    fight(strike)
    eq(M.info().journal, false, "closed at the start")
    eq(journal_shown(), false, "not drawn")
    ui.keys_down[F7] = true
    frame()
    eq(M.info().journal, true, "pressed: open")
    eq(journal_shown(), true, "drawn")
    frame()
    eq(M.info().journal, true, "held: still open")
    ui.keys_down[F7] = nil
    frame()
    eq(journal_shown(), true, "released: still open")
    eq(M.state.journal.index, 1, "on the newest fight")
    eq(ui.has_text(i18n.t("journal_hint", "F7")), true, "the hint names the key")
    press(F7)
    eq(M.info().journal, false, "pressed again: closed")
    eq(journal_shown(), false, "not drawn")

    -- opening takes the fight the summary shows; the × closes it too
    fight(strike)
    ui.drawing_ui = true
    ui.press("history_next")
    frame()
    eq(M.state.history_index, 2, "the summary shows the older fight")
    press(F7)
    eq(M.state.journal.index, 2, "the journal opens on it")
    ui.press("jclose")
    frame()
    eq(M.info().journal, false, "× closes it")
    ui.drawing_ui = false
    frame()

    -- the key comes from the settings
    M.state.settings:set("journal_key", F9)
    press(F7)
    eq(M.info().journal, false, "F7 is no longer the key")
    press(F9)
    eq(M.info().journal, true, "F9 is")
    eq(ui.has_text(i18n.t("journal_hint", "F9")), true, "and the hint says so")
    eq(M.info().errors, 0, "no error caught")
end)

test("journal keys act only while it is open", function()
    world({ settings = { language = "ru" } })
    local M = load()
    local i18n = mod("i18n")
    frame()
    fight(strike)
    press(PGDN)
    eq(M.state.journal.tab, "enemies", "PgDn with the journal closed: nothing")
    eq(M.info().journal, false, "still closed")
    press(F7)
    eq(i18n.t("jtab_" .. M.state.journal.tab), "Враги", "it opens on «Враги»")
    press(PGDN)
    eq(i18n.t("jtab_" .. M.state.journal.tab), "Навыки", "PgDn: «Навыки»")
    frame()
    eq(type(M.state.journal.model.body.choices), "table", "the Skills model is built")
    press(PGUP)
    eq(M.state.journal.tab, "enemies", "PgUp: back")
    press(PGUP)
    press(PGUP)
    eq(M.state.journal.tab, "record", "PgUp wraps from the first tab to the last")
    press(PGDN)
    eq(M.state.journal.tab, "summary", "and PgDn back to the first")
    press(F7)
    press(PGDN)
    press(END)
    eq(M.state.journal.tab, "summary", "closed again: nothing")
    eq(M.state.journal.index, 1, "nor End")
    eq(M.info().errors, 0, "no error caught")
end)

test("a journal key that is also the toggle key acts only for the journal", function()
    world()
    local M = load()
    frame()
    fight(strike)
    M.state.settings:set("toggle_key", PGDN)
    press(F7)
    press(PGDN)
    eq(M.state.journal.tab, "skills", "the journal takes PgDn")
    eq(M.state.hidden, false, "the window does not hide")
    press(F7)
    eq(overlay_shown(), true, "closed: the summary is back")
    press(PGDN)
    eq(overlay_shown(), false, "PgDn is the toggle key again")
    eq(M.state.journal.tab, "skills", "and leaves the journal alone")
end)

test("the journal setting off ignores F7", function()
    world({ settings = { journal = false } })
    local asked = watch_keys()
    local M = load()
    frame()
    fight(strike)
    press(F7)
    eq(M.info().journal, false, "F7: still closed")
    eq(journal_shown(), false, "nothing drawn")
    eq(asked[F7], nil, "F7 is never asked")
    for vk in pairs(mod("ui/journal").KEYS) do eq(asked[vk], nil, "nor the journal's key " .. vk) end

    -- on again, F7 opens it; switched off while open, it closes
    M.state.settings:set("journal", true)
    frame()
    press(F7)
    eq(M.info().journal, true, "on: F7 opens it")
    M.state.settings:set("journal", false)
    frame()
    eq(M.info().journal, false, "switched off: closed")
    eq(journal_shown(), false, "not drawn")
    eq(overlay_shown(), true, "the summary is back")
    eq(M.info().errors, 0, "no error caught")
end)

test("a key capture does not reach the journal", function()
    world()
    local M = load()
    local Menu = mod("ui/menu")
    frame()
    fight(strike)
    -- the settings window waits for the journal key (its row clicked with the menu open; on the stub's 1080 px the
    -- window pages and the keys are on page 2 since the hidden stats' group: 1200 px give it one page)
    ui.display = { x = 1920, y = 1200 }
    window_click("dd2dm_srow:journal_key")
    eq(Menu.waiting_for(), "journal_key", "the window waits for a key")
    ui.keys_down[F9] = true
    frame()
    eq(M.info().journal, false, "F9 while the window waits: still closed")
    eq(M.state.settings.values.journal_key, F9, "the window took F9")
    eq(Menu.capturing(), false, "the wait is over")
    frame()
    eq(M.info().journal, false, "F9 still held right after it was chosen: still closed")
    ui.keys_down[F9] = nil
    frame()
    press(F9)
    eq(M.info().journal, true, "the next F9 press opens it")
    eq(settings_shown(), false, "and closes the settings window")

    -- open: a wait of the REFramework menu's button keeps the journal's own keys from it too
    ui.press("dd2dm_settings_key")
    draw_ui()
    eq(Menu.waiting_for(), "settings_key", "the menu waits")
    ui.keys_down[PGDN] = true
    frame()
    eq(M.state.journal.tab, "enemies", "PgDn while the menu waits: no tab change")
    ui.keys_down[PGDN] = nil
    frame()
    ui.keys_down[F10] = true
    draw_ui()
    eq(M.state.settings.values.settings_key, F10, "the menu took F10")
    frame()
    eq(settings_shown(), false, "F10 still held right after it was chosen: no settings window")
    eq(M.info().journal, true, "the journal stays")
    ui.keys_down[F10] = nil
    frame()
    press(PGDN)
    eq(M.state.journal.tab, "skills", "the next PgDn press is the journal's")
    eq(M.info().errors, 0, "no error caught")
end)

test("the journal draws nothing while closed", function()
    world()
    local asked = watch_keys()
    local M = load()
    local Journal = mod("journal")
    local header, built = Journal.header, 0
    Journal.header = function(...)
        built = built + 1
        return header(...)
    end
    frame()
    W.mode = 2
    frame()
    strike()
    frame(0.2)
    eq(journal_shown(), false, "no journal window during a fight")
    end_battle()
    eq(journal_shown(), false, "nor with the summary")
    ui.drawing_ui = true
    frame()
    eq(journal_shown(), false, "nor with the REFramework menu open")
    ui.drawing_ui = false
    frame()
    eq(built, 0, "no journal model built")
    for vk in pairs(mod("ui/journal").KEYS) do eq(asked[vk], nil, "the journal's key " .. vk .. " is not asked") end
    eq(asked[F7], asked[F6], "the journal key is asked once a frame, as the toggle key")

    -- open, its models are built once and again only after a change
    press(F7)
    for _ = 1, 5 do frame() end
    eq(built, 1, "built once while nothing changes")
    press(PGDN)
    eq(built, 2, "a tab change builds it again")
    press(F7)
    for _ = 1, 5 do frame() end
    eq(built, 2, "closed: built no more")
    Journal.header = header
    eq(M.info().errors, 0, "no error caught")
end)

test("the overlay is hidden while the journal is open", function()
    world({ settings = { summary_autohide = 5 } })
    local M = load()
    frame()
    fight(strike)
    eq(overlay_shown(), true, "the summary")
    press(F7)
    eq(journal_shown(), true, "the journal")
    eq(overlay_shown(), false, "the summary is hidden")
    -- a fight starts while it is open: the live window stays hidden too
    W.mode = 2
    frame()
    strike()
    frame(0.2)
    eq(M.info().fighting, true, "fighting")
    eq(overlay_shown(), false, "the live window is hidden")
    press(F7)
    eq(journal_shown(), false, "closed")
    eq(overlay_shown(), true, "the live window is back")

    -- the summary does not hide itself behind the journal
    end_battle()
    eq(overlay_shown(), true, "the summary")
    press(F7)
    frame(10)
    press(F7)
    eq(overlay_shown(), true, "after 10 s in the journal the summary is back")
    frame(4.8)
    eq(overlay_shown(), true, "its auto-hide counts from the journal's closing")
    frame(0.3)
    eq(overlay_shown(), false, "and hides it 5 s after")
    eq(M.info().errors, 0, "no error caught")
end)

test("a kept fight while the journal is open", function()
    world({ settings = { history_size = 4 } })
    local M = load()
    local i18n = mod("i18n")
    frame()
    fight(strike)
    fight(strike)
    press(F7)
    local J = M.state.journal
    eq(J.index, 1, "open on the newest")
    fight(strike)
    eq(M.info().history, 3, "a third fight is kept")
    eq(J.index, 1, "index 1 stays on the newest: the new fight")
    eq(J.model.header.fight, i18n.t("jfight_of", 1, 3), "the header is rebuilt")
    press(END)
    eq(J.index, 2, "End: the older fight")
    local seen = M.state.history:get(2)
    fight(strike)
    eq(J.index, 3, "index 2 becomes 3")
    eq(M.state.history:get(J.index), seen, "the same fight")
    eq(J.model.header.fight, i18n.t("jfight_of", 3, 4), "rebuilt again")
    press(END)
    eq(J.index, 4, "the oldest")
    fight(strike)
    eq(M.info().history, 4, "the history is full")
    eq(J.index, 4, "the viewed fight is gone: the oldest one left")
    eq(M.info().journal, true, "the journal stays open through the fights")
    eq(M.info().errors, 0, "no error caught")
end)

test("a language switch rebuilds the journal", function()
    world({ settings = { language = "ru" } })
    local M = load()
    local i18n = mod("i18n")
    frame()
    fight(strike)
    press(F7)
    eq(ui.has_text("Враги"), true, "the tab title in Russian")
    eq(ui.has_text("Навыки"), true, "and the other tabs")
    eq(ui.has_text(i18n.t("journal_hint", "F7")), true, "the hint in Russian")
    local J = M.state.journal
    local title, line = J.model.body.list.title, J.model.header.line
    -- the settings window (it closes the journal): the language, first row of the last group: ru -> auto -> en, then
    -- the journal again
    press(F8)
    eq(M.info().journal, false, "the settings window closed the journal")
    for _ = 1, 8 do press(PGDN) end
    press(RIGHT)
    press(RIGHT)
    eq(i18n.lang(), "en", "English")
    press(F7)
    eq(settings_shown(), false, "the journal closed the settings window")
    eq(ui.has_text("Enemies"), true, "the tab title in English")
    eq(ui.has_text("Skills"), true, "and the other tabs")
    eq(ui.has_text("Враги"), false, "no Russian title left")
    eq(ui.has_text(i18n.t("journal_hint", "F7")), true, "the hint in English")
    eq(J.model.body.list.title ~= title, true, "the enemy list rebuilt: " .. tostring(J.model.body.list.title))
    eq(J.model.header.line ~= line, true, "the fight's line rebuilt: " .. tostring(J.model.header.line))
    eq(M.info().errors, 0, "no error caught")

    -- "auto": the game switches its language while the journal is open, with the menu closed
    world()
    local lang = 6
    R.method("via.gui.GUISystem", "get_MessageLanguage", function() return lang end, STATIC)
    M = load()
    i18n = mod("i18n")
    eq(i18n.lang(), "ru", "auto: the game's Russian")
    frame()
    fight(strike)
    press(F7)
    J = M.state.journal
    title = J.model.body.list.title
    lang = 1
    frame(3)
    eq(i18n.lang(), "en", "the game switched to English")
    frame()
    eq(J.model.body.list.title ~= title, true, "the enemy list rebuilt: " .. tostring(J.model.body.list.title))
    eq(ui.has_text(i18n.t("journal_hint", "F7")), true, "the hint in English")
    eq(M.info().errors, 0, "no error caught")
end)

test("journal actions: fights clamp, the selection does not build up, pages clamp", function()
    world()
    local M = load()
    frame()
    fight(strike)
    W.mode = 2
    frame()
    for _ = 1, 60 do strike() end
    end_battle()
    press(F7)
    local J = M.state.journal
    press(HOME)
    eq(J.index, 1, "Home on the newest: stays")
    press(END)
    eq(J.index, 2, "End: the older")
    press(END)
    eq(J.index, 2, "End on the oldest: stays")
    press(HOME)
    eq(J.index, 1, "Home: the newest")

    -- Skills: the choices are the whole party and its members
    press(PGDN)
    frame()
    local n = #J.model.body.choices
    eq(n >= 2, true, "the whole party and its members")
    press(DOWN)
    eq(J.sel.skills, 2, "Down: the next choice")
    for _ = 1, n + 2 do press(DOWN) end
    eq(J.sel.skills, n, "Down past the last: the last")
    press(UP)
    eq(J.sel.skills, n - 1, "one Up goes back one")
    ui.drawing_ui = true
    ui.press("jchoice:1")
    frame()
    eq(J.sel.skills, 1, "a click picks a choice")
    ui.press("jtab:record")
    frame()
    eq(J.tab, "record", "a click picks a tab")
    ui.drawing_ui = false
    frame()

    -- Record: 60 events take more than one page
    eq(J.pages >= 2, true, "pages: " .. tostring(J.pages))
    press(RIGHT)
    eq(J.page.record, 2, "Right: page 2")
    for _ = 1, J.pages + 1 do press(RIGHT) end
    eq(J.page.record, J.pages, "Right past the last page: the last")
    press(UP)
    eq(J.page.record, J.pages, "the Record has no selection: Up keeps the page")
    press(LEFT)
    eq(J.page.record, J.pages - 1, "Left: one back")
    press(END)
    eq(J.index, 2, "End: the older fight")
    eq(J.page.record or 1, 1, "on its first page")
    eq(M.info().errors, 0, "no error caught")
end)

-- Journal.header, counted: one call per build of the journal's models. Gives the counter and a function that puts
-- the original back.
local function count_builds()
    local Journal = mod("journal")
    local header, seen = Journal.header, { n = 0 }
    Journal.header = function(...)
        seen.n = seen.n + 1
        return header(...)
    end
    return seen, function() Journal.header = header end
end

-- A screen so low that the goblin's card takes more than one page.
local LOW_SCREEN = { x = 1920, y = 300 }

test("a page change draws the next page and builds no model", function()
    world()
    local M = load()
    local i18n = mod("i18n")
    local built, restore = count_builds()
    frame()
    W.mode = 2
    frame()
    for _ = 1, 60 do strike() end
    end_battle()
    press(F7)
    press(PGUP)
    press(PGUP)
    local J = M.state.journal
    eq(J.tab, "record", "the Record tab")
    eq(J.pages >= 2, true, "pages: " .. tostring(J.pages))
    eq(ui.has_text(i18n.t("jpage", 1, J.pages)), true, "page 1 drawn")
    local before = built.n
    press(RIGHT)
    eq(J.page.record, 2, "Right: page 2")
    eq(ui.has_text(i18n.t("jpage", 2, J.pages)), true, "page 2 drawn")
    eq(built.n, before, "no model built for a page")
    press(LEFT)
    eq(ui.has_text(i18n.t("jpage", 1, J.pages)), true, "back on page 1")
    eq(built.n, before, "nor for the way back")
    restore()
    eq(M.info().errors, 0, "no error caught")
end)

test("Down on the last row changes nothing: the card keeps its page, no model is built", function()
    world()
    ui.display = LOW_SCREEN
    local M = load()
    local built, restore = count_builds()
    frame()
    fight(strike) -- one enemy: one row
    press(F7)
    local J = M.state.journal
    eq(J.tab, "enemies", "the Enemies tab")
    eq(#J.model.body.list.rows, 1, "one row")
    eq(J.pages >= 2, true, "the card pages: " .. tostring(J.pages))
    press(RIGHT)
    eq(J.page.enemies, 2, "the card's page 2")
    local before = built.n
    press(DOWN)
    eq(J.sel.enemies, 1, "Down on the last row: the same row")
    eq(J.page.enemies, 2, "the card stays on its page")
    eq(built.n, before, "no model built")
    press(UP)
    eq(J.page.enemies, 2, "Up on the first row: the same")
    eq(built.n, before, "no model built")

    -- the Skills choices: Down on the last one
    press(PGDN)
    local n = #J.model.body.choices
    for _ = 1, n do press(DOWN) end
    eq(J.sel.skills, n, "the last choice")
    before = built.n
    press(DOWN)
    eq(J.sel.skills, n, "Down: still the last")
    eq(built.n, before, "no model built")
    press(UP)
    eq(J.sel.skills, n - 1, "Up moves")
    eq(built.n, before + 1, "and builds")
    restore()
    eq(M.info().errors, 0, "no error caught")
end)

-- Casca and the player each hit the goblin: two party members with damage.
local function two_strikes()
    strike()
    hit(W.player, W.goblin, 10, W.goblin.hp - 10)
end

test("Down on the last bar of the Chart builds nothing", function()
    world()
    local M = load()
    local built, restore = count_builds()
    frame()
    fight(two_strikes)
    press(F7)
    for _ = 1, 4 do press(PGDN) end
    local J = M.state.journal
    eq(J.tab, "chart", "the Chart tab")
    local n = #J.model.body.bars
    eq(n, 2, "a bar per party member")
    for _ = 1, n do press(DOWN) end
    eq(J.sel.chart, n, "the last bar")
    local before = built.n
    press(DOWN)
    eq(J.sel.chart, n, "Down: still the last")
    eq(built.n, before, "no model built")
    press(UP)
    eq(J.sel.chart, n - 1, "Up moves")
    eq(built.n, before + 1, "and builds")
    restore()
    eq(M.info().errors, 0, "no error caught")
end)

test("the journal opened on another fight starts its selections and pages afresh", function()
    world()
    local M = load()
    frame()
    fight(strike)
    fight(two_strikes)
    press(F7)
    local J = M.state.journal
    press(PGDN)
    press(DOWN)
    eq(J.sel.skills, 2, "Skills: a member chosen")
    press(F7)
    ui.drawing_ui = true
    ui.press("history_next")
    frame()
    ui.drawing_ui = false
    eq(M.state.history_index, 2, "the summary shows the older fight")
    press(F7)
    eq(J.index, 2, "the journal opens on it")
    eq(J.sel.skills or 1, 1, "no member chosen")
    -- opened again on the fight it showed: the selection stays
    press(DOWN)
    eq(J.sel.skills, 2, "a member chosen")
    press(F7)
    press(F7)
    eq(J.index, 2, "the same fight")
    eq(J.sel.skills, 2, "the member still chosen")
    eq(M.info().errors, 0, "no error caught")
end)

test("a kept fight that changes the fight the journal shows starts its selections and pages afresh", function()
    world({ settings = { history_size = 4 } })
    ui.display = LOW_SCREEN
    local M = load()
    frame()
    fight(strike)
    press(F7)
    local J = M.state.journal
    press(PGDN)
    press(DOWN)
    eq(J.sel.skills, 2, "Skills: a member chosen")
    press(PGUP)
    press(RIGHT)
    eq(J.page.enemies, 2, "the card on page 2")
    fight(strike)
    eq(J.index, 1, "index 1: the new fight")
    eq(J.page.enemies or 1, 1, "its card from page 1")
    eq(J.sel.skills or 1, 1, "and no member chosen")

    -- the fight shown moves one further down: the same fight, its page kept
    press(END)
    press(RIGHT)
    eq(J.page.enemies, 2, "the older fight's card on page 2")
    local shown = M.state.history:get(J.index)
    fight(strike)
    eq(J.index, 3, "one further down")
    eq(M.state.history:get(J.index), shown, "the same fight")
    eq(J.page.enemies, 2, "on the same page")

    -- the fight shown falls out of a full history: the oldest left is another fight
    fight(strike)
    eq(M.info().history, 4, "the history is full")
    eq(J.index, 4, "the same fight, now the oldest")
    eq(J.page.enemies, 2, "still on its page")
    fight(strike)
    eq(M.info().history, 4, "still 4")
    eq(J.index, 4, "the oldest left")
    eq(J.page.enemies or 1, 1, "another fight: from page 1")
    eq(M.info().errors, 0, "no error caught")
end)

test("a fight kept inside a hit is written to history.json on the next frame, once", function()
    local function kept_inside_a_hit()
        W.deer = char("ch221001_00_1", { name = "Doe", hostile = true, hp = 250, max_hp = 250 })
        local M = load()
        frame()
        W.mode = 2
        frame()
        strike()
        W.mode, W.ending = 0, true
        frame()
        frame(0.3)
        local seen = watch_history_file()
        hit(W.player, W.deer, 100, 150) -- a new enemy in the end grace: the goblin's fight ends inside the hit
        eq(M.info().history, 1, "the fight is kept inside the hit")
        return M, seen
    end
    world({ settings = { history_file = true } })
    local M, seen = kept_inside_a_hit()
    eq(#seen.opens, 0, "nothing written inside the hook")
    eq(R.files[HISTORY_FILE], nil, "no file yet")
    frame()
    eq(#seen.opens, 1, "written on the next frame")
    eq(#json_decode(R.files[HISTORY_FILE]), 1, "with the kept fight")
    frame()
    eq(#seen.opens, 1, "once")
    eq(M.info().errors, 0, "no error caught")

    -- switched off before that frame: the file is not touched
    world({ settings = { history_file = true } })
    M, seen = kept_inside_a_hit()
    M.state.settings:set("history_file", false)
    eq(M.state.settings.values.history_file, false, "switched off")
    frame()
    eq(#seen.opens, 0, "never written")
    eq(M.info().errors, 0, "no error caught")
end)

test("info reports 1.0.0, 11 hooks and the journal", function()
    world()
    local M = load()
    local info = M.info()
    eq(info.version, "1.0.0", "version")
    eq(M.version, "1.0.0", "DD2DM.version")
    -- the line the README's "Report a bug" asks for: the name players see and the version, tagged with the files' name
    local named = 0
    for _, line in ipairs(R.logs) do
        if line:find("[DD2DamageMeter] Hidden Numbers 1.0.0 loaded (load ", 1, true) then named = named + 1 end
    end
    eq(named, 1, "REFramework's log names the mod and its version, once")
    eq(info.hooks, 11, "hooks")
    eq(#HOOKED, 11, "the hooked methods")
    eq(info.journal, false, "the journal is closed")
    eq(type(info.journal_missing), "table", "journal_missing")
    eq(type(info.enemy_bars_missing), "table", "enemy_bars_missing")
    eq(type(info.enemy_plate_missing), "table", "enemy_plate_missing")
    eq(#info.journal_missing, 0, "nothing missing before it is drawn")
    frame()
    press(F7)
    eq(M.info().journal, true, "open")
    eq(#M.info().journal_missing, 0, "nothing missing: " .. T.str(M.info().journal_missing))
    local get = imgui.get_display_size
    imgui.get_display_size = nil
    frame()
    imgui.get_display_size = get
    eq(contains(M.info().journal_missing, "get_display_size"), true, "a missing imgui call is named")
    eq(journal_shown(), true, "and the journal still draws")
    eq(M.info().errors, 0, "no error caught")
end)

-- The enemy HP numbers ---------------------------------------------------------------------------------

-- The game calls that read the scene's GUIs and whether one is drawn.
local GUI_READS = { get_CurrentScene = true, ["findComponents(System.Type)"] = true, get_DrawSelf = true }

-- The game's HP bars over heads (game/gauges.lua): the current scene's GUIs are W.guis. The hidden-stats panel looks
-- through the same GUIs for its screens (game/hidden_screens.lua, every 0.5 s while none is drawn, paused or not):
-- the reads made inside HiddenScreens.current are counted apart, in W.hidden_reads.
local function bars_scene()
    W.guis = {}
    R.type("via.gui.GUI")
    R.type("app.ui020601")
    W.scene = R.object("via.Scene", {}, {
        ["findComponents(System.Type)"] = function(_, t)
            if t == nil or t.runtime_type ~= "via.gui.GUI" then return nil end
            local arr = R.object("via.gui.GUI[]")
            arr.items = W.guis
            return arr
        end,
    })
    R.method("via.SceneManager", "get_CurrentScene", function() return W.scene end, STATIC)
    R.native("via.SceneManager", R.object("via.SceneManager"))
    local HS = mod("game/hidden_screens")
    local current = HS.current
    W.hidden_reads = {}
    HS.current = function(...)
        local from = #R.calls
        local hover = current(...)
        for i = from + 1, #R.calls do
            local sig = R.calls[i].sig
            if GUI_READS[sig] then W.hidden_reads[sig] = (W.hidden_reads[sig] or 0) + 1 end
        end
        return hover
    end
end

-- A bar over `c`, drawn and hostile unless o says otherwise (g.drawn, g.hostile change it later), centred at
-- (o.x, o.y) in GUI space (960, 400 by default).
local function gauge(c, o)
    o = o or {}
    local g = { drawn = o.drawn ~= false, hostile = o.hostile ~= false }
    g.panel = R.object("via.gui.Panel", {}, {
        get_GlobalPosition = function() return { x = o.x or 960, y = o.y or 400, z = 0 } end,
    })
    g.comp = R.object("app.ui020601", { CompChara = c, All = g.panel })
    setmetatable(g.comp.fields, { __index = function(_, k) if k == "IsHostile" then return g.hostile end end })
    g.go = R.object("via.GameObject", {}, {
        get_Name = function() return "ui020601" end,
        get_DrawSelf = function() return g.drawn end,
        ["getComponent(System.Type)"] = function() return g.comp end,
    })
    g.gui = R.object("via.gui.GUI", {}, { get_GameObject = function() return g.go end })
    W.guis[#W.guis + 1] = g.gui
    return g
end

-- The enemy plate's backing drawn this frame on the background list, nil without one.
local function plate_box()
    local back = mod("ui/enemy_plate").COLORS.back
    for _, c in ipairs(ui.calls_of("add_rect_filled")) do
        if c.layer == "background" and c.col == back then return c end
    end
    return nil
end

-- Whether the text call `c` lies inside `box` (nil: no box).
local function inside(c, box)
    return box ~= nil and c.x >= box.x0 and c.x <= box.x1 and c.y >= box.y0 and c.y <= box.y1
end

-- The enemy numbers drawn this frame: the texts in the meter's text colour on the background list, joined by "|";
-- not the enemy plate's names, which have that colour too.
local function numbers()
    local list = {}
    local text, box = mod("ui/enemy_bars").COLORS.text, plate_box()
    for _, c in ipairs(ui.calls_of("add_text")) do
        if c.layer == "background" and c.col == text and not inside(c, box) then list[#list + 1] = c.text end
    end
    return table.concat(list, "|")
end

-- The font size of the first enemy number drawn this frame.
local function numbers_px()
    local text = mod("ui/enemy_bars").COLORS.text
    for _, c in ipairs(ui.calls_of("add_text")) do
        if c.layer == "background" and c.col == text then return c.px end
    end
    return nil
end

-- The game calls that read the bars: those that read the scene's GUIs, but the hidden-stats panel's (bars_scene).
local function bar_reads()
    local n = 0
    for sig in pairs(GUI_READS) do n = n + #R.calls_of(sig) - ((W.hidden_reads or {})[sig] or 0) end
    return n
end

test("enemy HP numbers over the hostile bars the game draws, with the meter's HP, under the windows", function()
    world()
    bars_scene()
    local M = load()
    gauge(W.goblin)
    local guard = gauge(char("ch300659_00", { hp = 900, max_hp = 900 }), { hostile = false, x = 200 })
    local hidden = gauge(char("ch220003_00_16", { hostile = true }), { drawn = false, x = 300 })
    local ghost = R.character({ go = "ch220003_00_17", max_hp = 3700 }) -- no current HP
    gauge(ghost, { x = 400 })
    frame()
    eq(numbers(), "3 053 / 3 700 · 83%", "the goblin's HP, all by default; nothing for the others")
    -- a hit: the numbers and the meter say the same
    W.mode = 2
    frame()
    strike()
    frame(0.2)
    eq(numbers(), "3 043 / 3 700 · 82%", "after a hit")
    eq(ui.has_text("3 043 / 3 700"), true, "the meter's header says the same")
    -- the game shows and hides the bars
    hidden.drawn, guard.hostile = true, true
    frame()
    eq(numbers(), "3 043 / 3 700 · 82%|900 / 900 · 100%|1 000 / 2 000 · 50%", "every bar drawn and hostile")
    hidden.drawn, guard.hostile = false, false
    -- a format from the settings window; the numbers are drawn before its panel, so they lie under it
    window_click("dd2dm_sprev:enemy_hp_numbers")
    eq(M.state.settings.values.enemy_hp_numbers, "current_percent", "all <- current_percent")
    frame()
    eq(numbers(), "3 043 · 82%", "the new format")
    local panel = mod("ui/kit").COLORS.panel
    local first_number, first_panel
    for i, c in ipairs(ui.calls) do
        if c.fn == "add_text" and c.layer == "background" and not first_number then first_number = i end
        if c.fn == "add_rect_filled" and c.col == panel and c.layer == "background" and not first_panel then
            first_panel = i
        end
    end
    eq(first_number ~= nil and first_panel ~= nil and first_number < first_panel, true, "under the settings panel")
    -- their size from the settings window: 15 px × scale × the setting, 10 % a step
    eq(numbers_px(), 15, "15 px at scale 1 and 100 %")
    window_click("dd2dm_snext:enemy_hp_size")
    eq(M.state.settings.values.enemy_hp_size, 1.1, "100 % -> 110 %")
    frame()
    eq(numbers_px(), 16.5, "15 px × 1.1")
    window_click("dd2dm_snext:scale")
    frame()
    near(numbers_px(), 15 * 1.05 * 1.1, 1e-9, "and × the meter's scale")
    press(F8)
    ui.drawing_ui = false
    end_battle()
    eq(numbers(), "3 043 · 82%", "with the summary too")
    eq(M.info().errors, 0, "no error caught")
    eq(#M.info().enemy_bars_missing, 0, "no imgui call missing")
end)

test("enemy HP numbers off, or the journal open: the game's bars are neither read nor drawn", function()
    -- the enemy plate, the buildup bars and the player's numbers off too: they read the bars for themselves
    world({ settings = { enemy_hp_numbers = "off", boss_hp_numbers = "off", enemy_plate = false,
        buildup_bars = false, player_numbers = false } })
    bars_scene()
    local M = load()
    gauge(W.goblin)
    frame()
    fight(strike)
    for _ = 1, 5 do frame() end
    eq(bar_reads(), 0, "off: nothing read")
    eq(numbers(), "", "nor drawn")
    -- on from the settings window: read and drawn at once
    window_click("dd2dm_snext:enemy_hp_numbers")
    eq(M.state.settings.values.enemy_hp_numbers, "current", "off -> current")
    press(F8)
    ui.drawing_ui = false
    frame()
    eq(numbers(), "3 043", "the current HP")
    eq(bar_reads() > 0, true, "read")
    -- the journal open: nothing read, nothing drawn; closed: back
    press(F7)
    eq(M.info().journal, true, "the journal is open")
    local reads = bar_reads()
    for _ = 1, 5 do frame(0.5) end
    eq(bar_reads(), reads, "the journal open: nothing read")
    eq(numbers(), "", "nor drawn")
    press(F7)
    eq(numbers(), "3 043", "closed: back")
    -- switched off: the bars found are forgotten, nothing more is read
    eq(mod("game/gauges").count(), 1, "one bar kept")
    window_click("dd2dm_sprev:enemy_hp_numbers")
    eq(M.state.settings.values.enemy_hp_numbers, "off", "current -> off")
    eq(mod("game/gauges").count(), 0, "forgotten")
    press(F8)
    ui.drawing_ui = false
    reads = bar_reads()
    for _ = 1, 5 do frame(0.5) end
    eq(bar_reads(), reads, "off again: nothing read")
    eq(numbers(), "", "nor drawn")
    eq(M.info().errors, 0, "no error caught")
end)

test("a bar or a character that raises does not break the frame; a new world forgets the bars", function()
    world()
    bars_scene()
    local M = load()
    local goblin = gauge(W.goblin)
    local other = char("ch220003_00_16", { hostile = true, hp = 500, max_hp = 1000 })
    gauge(other, { x = 300 })
    frame()
    fight(strike)
    eq(numbers(), "3 043 / 3 700 · 82%|500 / 1 000 · 50%", "two bars")
    -- a character that raises: no numbers for it, nothing else changes
    other.poison = true
    frame()
    eq(numbers(), "3 043 / 3 700 · 82%", "the other one's numbers are gone")
    eq(M.info().errors, 0, "no error: its HP could not be read")
    other.poison = false
    -- a bar whose game calls raise (the game destroyed it): dropped without an error, the rest of the frame goes on
    goblin.go.poison = true
    frame()
    eq(numbers(), "500 / 1 000 · 50%", "the other bar still")
    eq(overlay_shown(), true, "the meter still draws")
    for _ = 1, 10 do frame() end
    eq(M.info().errors, 0, "no error: normal play")
    local gauges = mod("game/gauges")
    eq(gauges.gone(), 1, "counted as gone, once")
    -- the whole step raising is caught like the others
    local shown = gauges.shown
    gauges.shown = function() error("reader broke") end
    frame()
    eq(M.info().errors, 1, "caught")
    eq(overlay_shown(), true, "the meter still draws")
    gauges.shown = shown
    -- a new world: the bars found are forgotten
    frame(1)
    eq(gauges.count(), 1, "one bar kept")
    R.method("app.CharacterManager", "get_ManualPlayer", function() return nil end)
    scene_change()
    eq(gauges.count(), 0, "forgotten with the old world")
end)

-- The boss bar at the top of the screen (ui020501) over `c`: drawn unless o.drawn is false (b.drawn changes it later),
-- its base element s9g_Base under All, 776 × 7, at (564, 106) in GUI space as on a 16:9 display (b.x, b.y move it).
-- As in the game, its Target is c's GameObject (whose getComponent(System.Type) gives c for app.Character) and its
-- TargetHitCtrl c's hit controller (get_CachedCharacter gives c).
local function boss_bar(c, o)
    o = o or {}
    R.type("app.ui020501")
    c.go.methods["getComponent(System.Type)"] = function(_, t)
        if t ~= nil and t.runtime_type == "app.Character" then return c end
        return nil
    end
    local b = { drawn = o.drawn ~= false, x = 564, y = 106 }
    b.base = R.object("via.gui.Scale9Grid", {}, {
        get_Name = function() return "s9g_Base" end,
        get_GlobalPosition = function() return { x = b.x, y = b.y, z = 0 } end,
        get_Size = function() return { w = 776, h = 7 } end,
    })
    b.all = R.object("via.gui.Panel", {}, { get_Child = function() return b.base end })
    b.comp = R.object("app.ui020501", { Target = c.go, TargetHitCtrl = c.hc, All = b.all })
    b.go = R.object("via.GameObject", {}, {
        get_Name = function() return "ui020501" end,
        get_DrawSelf = function() return b.drawn end,
        ["getComponent(System.Type)"] = function() return b.comp end,
    })
    b.gui = R.object("via.gui.GUI", {}, { get_GameObject = function() return b.go end })
    W.guis[#W.guis + 1] = b.gui
    return b
end

-- The enemy number drawn this frame whose text is `text` (its text-coloured copy), nil without one.
local function number_call(text)
    local beige = mod("ui/enemy_bars").COLORS.text
    for _, c in ipairs(ui.calls_of("add_text")) do
        if c.layer == "background" and c.col == beige and c.text == text then return c end
    end
    return nil
end

test("boss HP numbers right of the boss bar the game draws, with the meter's HP, under the windows", function()
    world()
    bars_scene()
    local M = load()
    local griffin = char("ch250000_00", { name = "Griffin", hostile = true, hp = 40000, max_hp = 90000 })
    local b = boss_bar(griffin)
    frame()
    eq(numbers(), "40 000 / 90 000 · 44%", "the griffin's HP, all by default")
    -- its place on the stub's 1920 × 1080 display: the bar's right end at 564 + 776, the text 10 px after it, its
    -- middle on the bar's (106 + 7 / 2), 18 px
    local c = number_call("40 000 / 90 000 · 44%")
    eq(c.x, 1340 + 10, "10 px after the bar's right end")
    eq(c.y, math.floor(109.5 - 9 + 0.5), "its middle on the bar's")
    eq(c.px, 18, "18 px at scale 1 and 100 %")
    -- with the bars over heads: both, the overhead ones first
    gauge(W.goblin)
    frame(1)
    eq(numbers(), "3 053 / 3 700 · 83%|40 000 / 90 000 · 44%", "both")
    -- a hit on the griffin: the numbers follow its HP
    griffin.hp = 35500
    frame()
    eq(numbers(), "3 053 / 3 700 · 83%|35 500 / 90 000 · 39%", "after a hit")
    -- the game hides the bar, or has no target for it: none
    b.drawn = false
    frame()
    eq(numbers(), "3 053 / 3 700 · 83%", "not drawn: none")
    b.drawn = true
    b.comp.fields.Target, b.comp.fields.TargetHitCtrl = nil, nil
    frame()
    eq(numbers(), "3 053 / 3 700 · 83%", "no target: none")
    b.comp.fields.Target, b.comp.fields.TargetHitCtrl = griffin.go, griffin.hc
    -- the Target GameObject is never read as if it were the character (its name is the griffin's own GameObject's,
    -- read for the enemy plate's Actor of the boss)
    local asked = 0
    for _, call in ipairs(R.calls) do
        if call.this == griffin.go and call.sig ~= "getComponent(System.Type)" and call.sig ~= "get_Name" then
            asked = asked + 1
        end
    end
    eq(asked, 0, "nothing but its app.Character component and its name asked of the GameObject")
    -- the format from the settings window; drawn before its panel, so under it
    window_click("dd2dm_sprev:boss_hp_numbers")
    eq(M.state.settings.values.boss_hp_numbers, "current_percent", "all <- current_percent")
    eq(M.state.settings.values.enemy_hp_numbers, "all", "the numbers over enemies keep theirs")
    frame()
    eq(numbers(), "3 053 / 3 700 · 83%|35 500 · 39%", "the new format")
    local panel = mod("ui/kit").COLORS.panel
    local boss_at, panel_at
    for i, call in ipairs(ui.calls) do
        if call.fn == "add_text" and call.text == "35 500 · 39%" and not boss_at then boss_at = i end
        if call.fn == "add_rect_filled" and call.col == panel and call.layer == "background" and not panel_at then
            panel_at = i
        end
    end
    eq(boss_at ~= nil and panel_at ~= nil and boss_at < panel_at, true, "under the settings panel")
    -- the size of both from «Размер цифр»: 18 px × 1.1
    window_click("dd2dm_snext:enemy_hp_size")
    frame()
    near(number_call("35 500 · 39%").px, 18 * 1.1, 1e-9, "18 px × 1.1")
    -- the numbers over enemies off: the boss's stay
    M.state.settings:set("enemy_hp_size", 1)
    for _ = 1, 5 do window_click("dd2dm_sprev:enemy_hp_numbers") end
    eq(M.state.settings.values.enemy_hp_numbers, "off", "the numbers over enemies off")
    frame()
    eq(numbers(), "35 500 · 39%", "the boss's alone")
    -- the bar moves: read every frame
    b.x = 600
    frame()
    eq(number_call("35 500 · 39%").x, 600 + 776 + 10, "after the moved bar")
    press(F8)
    ui.drawing_ui = false
    end_battle()
    eq(numbers(), "35 500 · 39%", "with the summary too")
    eq(M.info().errors, 0, "no error caught")
    eq(#M.info().enemy_bars_missing, 0, "no imgui call missing")
end)

-- The game calls made on `c` itself (its own methods, not its hit controller's or its GameObject's) so far.
local function calls_on_char(c)
    local n = 0
    for _, call in ipairs(R.calls) do
        if call.this == c then n = n + 1 end
    end
    return n
end

test("the meter's enemy line shows the HP the boss bar's numbers show, in the same frame, from their one read",
        function()
    -- seen in game: the meter's line said 151 551 while the boss bar and its numbers said 149 232
    world({ settings = { enemy_hp_numbers = "off", enemy_plate = false, buildup_bars = false } })
    bars_scene()
    local M = load()
    local drake = char("ch255000_00", { name = "Drake", hostile = true, hp = 160000, max_hp = 200000 })
    boss_bar(drake)
    W.mode = 2
    frame()
    hit(W.casca, drake, 8449, 151551)
    frame(0.2)
    eq(numbers(), "151 551 / 200 000 · 76%", "the boss bar's numbers")
    eq(ui.has_text("151 551 / 200 000"), true, "the meter's line says the same")
    -- a hit right after the live window's last build: both follow it in the next frame
    hit(W.casca, drake, 2319, 149232)
    frame()
    eq(numbers(), "149 232 / 200 000 · 75%", "the numbers after the hit")
    eq(ui.has_text("149 232 / 200 000"), true, "the meter's line in the same frame")
    eq(ui.has_text("151 551 / 200 000"), false, "not the HP before the hit")
    -- HP the game takes away outside the hits the mod sees: the line follows the bar all the same
    drake.hp = 148000
    frame()
    eq(numbers(), "148 000 / 200 000 · 74%", "the numbers")
    eq(ui.has_text("148 000 / 200 000"), true, "the meter's line in the same frame")
    frame(0.2)
    eq(ui.has_text("148 000 / 200 000"), true, "and after the live window's next build")
    -- no game read of its own: the drake's HP is read once a frame, for the numbers
    local before = calls_on_char(drake)
    frame()
    eq(calls_on_char(drake) - before, 2, "get_Hp and get_OriginalMaxHp, once each, by the numbers")
    -- the fight keeps it: the summary's enemy row
    end_battle()
    local row = M.state.summary_model.enemies[1]
    eq(row.label, "Drake", "the drake's row"); eq(row.hp_text, "148 000 / 200 000 HP", "its HP as the bar showed it")
    eq(M.info().errors, 0, "no error caught")
end)

test("the meter's enemy line and the numbers over heads: the enemy the line is about takes their HP", function()
    world({ settings = { boss_hp_numbers = "off", enemy_plate = false, buildup_bars = false } })
    bars_scene()
    local M = load()
    gauge(W.goblin)
    W.mode = 2
    frame()
    strike()
    frame(0.2)
    eq(numbers(), "3 043 / 3 700 · 82%", "the goblin's numbers")
    eq(ui.has_text("3 043 / 3 700"), true, "the meter's line says the same")
    hit(W.casca, W.goblin, 500, 2543.035)
    frame()
    eq(numbers(), "2 543 / 3 700 · 69%", "after a hit")
    eq(ui.has_text("2 543 / 3 700"), true, "the meter's line in the same frame")
    W.goblin.hp = 2000
    frame(0.2)
    eq(ui.has_text("2 000 / 3 700"), true, "HP lost outside the hits")
    -- an ogre with more HP heads the line: the goblin's numbers leave it alone, its own HP is the ogre's
    local ogre = char("ch230001_00_1", { name = "Ogre", hostile = true, hp = 9000, max_hp = 9000 })
    hit(W.casca, ogre, 1000, 8000)
    frame(0.2)
    eq(M.state.live_model.header.title, "Ogre", "the ogre heads the line")
    eq(ui.has_text("8 000 / 9 000"), true, "with its HP")
    W.goblin.hp = 1500
    frame()
    eq(numbers(), "1 500 / 3 700 · 41%", "the goblin's numbers")
    eq(ui.has_text("8 000 / 9 000"), true, "the line still the ogre's")
    -- the numbers over heads off: nothing read, the line goes by the hits as before
    for _ = 1, 5 do window_click("dd2dm_sprev:enemy_hp_numbers") end
    eq(M.state.settings.values.enemy_hp_numbers, "off", "off")
    press(F8)
    ui.drawing_ui = false
    local before = calls_on_char(W.goblin)
    W.goblin.hp = 1000
    frame(0.2)
    eq(calls_on_char(W.goblin), before, "nothing read of the goblin")
    end_battle()
    local rows = M.state.summary_model.enemies
    eq(rows[2].hp_text, "1 500 / 3 700 HP", "the goblin's HP as its numbers last showed it")
    eq(M.info().errors, 0, "no error caught")
end)

test("boss HP numbers off, or the journal open: the boss bar is neither read nor drawn", function()
    -- the enemy plate, the buildup bars and the player's numbers off too: they read the game's bars for themselves
    world({ settings = { enemy_hp_numbers = "off", boss_hp_numbers = "off", enemy_plate = false,
        buildup_bars = false, player_numbers = false } })
    bars_scene()
    local M = load()
    boss_bar(char("ch250000_00", { hostile = true, hp = 40000, max_hp = 90000 }))
    local overhead = gauge(W.goblin)
    frame()
    fight(strike)
    for _ = 1, 5 do frame(0.5) end
    eq(bar_reads(), 0, "both off: nothing read")
    eq(numbers(), "", "nor drawn")
    -- on from the settings window: read and drawn at once; the numbers over enemies stay off
    window_click("dd2dm_snext:boss_hp_numbers")
    eq(M.state.settings.values.boss_hp_numbers, "current", "off -> current")
    press(F8)
    ui.drawing_ui = false
    frame()
    eq(numbers(), "40 000", "the boss's current HP alone")
    eq(bar_reads() > 0, true, "read")
    local overhead_reads = 0
    for _, call in ipairs(R.calls) do
        if (call.this == overhead.go and call.sig == "get_DrawSelf") or call.this == overhead.panel then
            overhead_reads = overhead_reads + 1
        end
    end
    eq(overhead_reads, 0, "the overhead bar found in the look, but never read")
    -- the journal open: nothing read, nothing drawn; closed: back
    press(F7)
    eq(M.info().journal, true, "the journal is open")
    local reads = bar_reads()
    for _ = 1, 5 do frame(0.5) end
    eq(bar_reads(), reads, "the journal open: nothing read")
    eq(numbers(), "", "nor drawn")
    press(F7)
    eq(numbers(), "40 000", "closed: back")
    -- switched off: forgotten, nothing more is read
    window_click("dd2dm_sprev:boss_hp_numbers")
    eq(M.state.settings.values.boss_hp_numbers, "off", "current -> off")
    eq(mod("game/gauges").count(), 0, "the bars found forgotten")
    press(F8)
    ui.drawing_ui = false
    reads = bar_reads()
    for _ = 1, 5 do frame(0.5) end
    eq(bar_reads(), reads, "off again: nothing read")
    eq(numbers(), "", "nor drawn")
    eq(M.info().errors, 0, "no error caught")
end)

test("boss HP numbers off, the overhead ones on: the looks take nothing of the boss bar", function()
    -- the enemy plate and the buildup bars off too: they take the boss bar for themselves
    world({ settings = { boss_hp_numbers = "off", enemy_plate = false, buildup_bars = false } })
    bars_scene()
    local M = load()
    local griffin = char("ch250000_00", { hostile = true, hp = 40000, max_hp = 90000 })
    local b = boss_bar(griffin)
    gauge(W.goblin)
    for _ = 1, 5 do frame(0.5) end
    eq(numbers(), "3 053 / 3 700 · 83%", "the overhead numbers alone")
    eq(#R.calls_of("findComponents(System.Type)") >= 2, true, "the scene looked through")
    local touched = 0
    for _, c in ipairs(R.calls) do
        if (c.this == b.go and c.sig ~= "get_Name") or c.this == b.comp or c.this == b.all or c.this == b.base
                or c.this == griffin.hc or c.this == griffin.go then
            touched = touched + 1
        end
    end
    eq(touched, 0, "of the boss bar only its GameObject's name, as of every GUI")
    -- on: taken at once
    window_click("dd2dm_snext:boss_hp_numbers")
    press(F8)
    ui.drawing_ui = false
    frame()
    eq(numbers(), "3 053 / 3 700 · 83%|40 000", "on: its numbers at once")
    eq(M.info().errors, 0, "no error caught")
end)

test("a boss bar or a target that raises does not break the frame; a new world forgets the boss bar", function()
    world()
    bars_scene()
    local M = load()
    local griffin = char("ch250000_00", { hostile = true, hp = 40000, max_hp = 90000 })
    local b = boss_bar(griffin)
    frame()
    fight(strike)
    eq(numbers(), "40 000 / 90 000 · 44%", "drawn")
    eq(overlay_shown(), true, "the meter shows the fight")
    -- a target that raises: no numbers, no error (its HP cannot be read)
    griffin.poison = true
    frame()
    eq(numbers(), "", "none")
    eq(M.info().errors, 0, "no error")
    griffin.poison = false
    -- its hit controller raising or without a character: the Target GameObject's app.Character, the same numbers
    griffin.hc.poison = true
    frame()
    eq(numbers(), "40 000 / 90 000 · 44%", "a raising hit controller: through the GameObject")
    griffin.hc.poison = false
    b.comp.fields.TargetHitCtrl = R.object("app.HitController", {}, { get_CachedCharacter = function() end })
    frame()
    eq(numbers(), "40 000 / 90 000 · 44%", "no cached character: through the GameObject")
    b.comp.fields.TargetHitCtrl = griffin.hc
    eq(M.info().errors, 0, "no error")
    -- a base that raises (the game destroyed it): dropped without an error, the rest of the frame goes on
    local gauges = mod("game/gauges")
    b.base.poison = true
    frame()
    eq(numbers(), "", "none")
    eq(overlay_shown(), true, "the meter still draws")
    for _ = 1, 10 do frame() end
    eq(M.info().errors, 0, "no error: normal play")
    eq(gauges.gone(), 1, "counted as gone, once")
    b.base.poison = false
    frame(1)
    eq(numbers(), "40 000 / 90 000 · 44%", "back at the next look")
    -- the whole step raising is caught like the others
    local boss = gauges.boss
    gauges.boss = function() error("reader broke") end
    frame()
    eq(M.info().errors, 1, "caught")
    eq(overlay_shown(), true, "the meter still draws")
    gauges.boss = boss
    -- a drawing that fails is reported, the meter still draws
    local draw_boss = mod("ui/enemy_bars").draw_boss
    mod("ui/enemy_bars").draw_boss = function() return "boom" end
    frame()
    eq(M.info().errors, 2, "reported")
    eq(overlay_shown(), true, "the meter still draws")
    mod("ui/enemy_bars").draw_boss = draw_boss
    -- a new world: the boss bar found is forgotten and looked for again
    frame()
    local FIND = "findComponents(System.Type)"
    local looks, hidden_looks = #R.calls_of(FIND) - (W.hidden_reads[FIND] or 0), W.hidden_reads[FIND] or 0
    R.method("app.CharacterManager", "get_ManualPlayer", function() return nil end)
    scene_change()
    -- nothing is looked for or read while there is no player character
    frame()
    eq(#R.calls_of(FIND) - (W.hidden_reads[FIND] or 0), looks, "no look without a player character")
    eq(W.hidden_reads[FIND] or 0, hidden_looks, "nor of the hidden-stats panel's screens")
    eq(numbers(), "", "no numbers")
    -- the new world's player character
    R.method("app.CharacterManager", "get_ManualPlayer", function() return W.player end)
    frame()
    -- the overhead numbers' look first (the reset forgot that the boss bar and the player's HUD were asked for), then
    -- the boss bar's own, then the HUD's own
    eq(#R.calls_of(FIND) - W.hidden_reads[FIND], looks + 3, "looked for again at once")
    -- and the hidden-stats panel's screens, forgotten too
    eq(W.hidden_reads[FIND], hidden_looks + 1, "its screens looked for again at once")
    eq(numbers(), "40 000 / 90 000 · 44%", "and found")
end)

-- The damage numbers --------------------------------------------------------------------------------------

local POSITION = "<Position>k__BackingField"

-- A DamageInfo's fields at the world point (x, y) (the stub's projection puts it there on the screen), plus `extra`.
local function at(x, y, extra)
    local f = { [POSITION] = { x = x, y = y, z = 3 } }
    for k, v in pairs(extra or {}) do f[k] = v end
    return f
end

-- The texts drawn this frame on the background list whose colour, without its alpha, is `color`'s.
local function texts_in(color)
    local list = {}
    for _, c in ipairs(ui.calls_of("add_text")) do
        if c.layer == "background" and c.col & 0xFFFFFF == color & 0xFFFFFF then list[#list + 1] = c.text end
    end
    return table.concat(list, "|")
end

-- A world with a projection, the player (a Fighter) and two Warrior pawns.
local function numbers_world(settings)
    world({ settings = settings })
    R.state.project = function(p) return { x = p.x, y = p.y } end
    W.player = char("ch000000_00", { name = "Guts", chara_id = 2891076981, hp = 1913.991, max_hp = 2400, job = 1 })
    W.casca = char("ch100000_00", { name = "Casca", chara_id = 2283028347, hp = 1500, max_hp = 1800, job = 5 })
    W.rook = char("ch100001_00", { name = "Rook", chara_id = 2283028348, hp = 1500, max_hp = 1800, job = 5 })
    W.pawns = { W.casca, W.rook }
    return W
end

-- DamageInfo fields at the world point (x, y), a DamageRate of 1, that count their reads of the Position,
-- IsWeakDamage and DamageRate in reads.n (the victim's own position would be read through get_Transform).
local function counted_at(reads, x, y)
    return setmetatable({}, { __index = function(_, k)
        if k == POSITION or k == "IsWeakDamage" or k == "DamageRate" then
            reads.n = reads.n + 1
            if k == POSITION then return { x = x, y = y, z = 3 } end
            if k == "DamageRate" then return 1 end
        end
    end })
end

test("damage numbers: each counted hit on an enemy at its point, in the meter's colours, over the enemy numbers", function()
    numbers_world()
    bars_scene()
    local M = load()
    gauge(W.goblin)
    local kit = mod("ui/kit")
    -- on, but no fight open: an ally's hit on the goblin opens none, and nothing of it is read
    local reads = { n = 0 }
    hit(char("ch111003_00", { hp = 1500 }), W.goblin, 10, W.goblin.hp - 10, counted_at(reads, 1, 1), {})
    frame()
    eq(M.state.fight, nil, "no fight")
    eq(reads.n, 0, "on, no fight: nothing read")
    eq(#R.calls_of("get_Transform"), 0, "nor the victim's position")
    eq(#M.state.numbers.items, 0, "no number")
    W.mode = 2
    frame()
    hit(W.player, W.goblin, 100, W.goblin.hp - 100, at(300, 400))
    hit(W.casca, W.goblin, 10, W.goblin.hp - 10, at(800, 500))
    hit(W.rook, W.goblin, 20, W.goblin.hp - 20, at(1000, 500))
    frame()
    local fighter, first, second = kit.actor_color("player", 1, 1), kit.actor_color("pawn", 5, 1),
        kit.actor_color("pawn", 5, 2)
    eq(first ~= second, true, "two Warriors, two shades")
    eq(texts_in(fighter), "100", "the player's hit")
    eq(texts_in(first), "10", "the first Warrior's in its shade")
    eq(texts_in(second), "20", "the second Warrior's in the other shade")
    -- the order: the enemy numbers, then the damage numbers, then the settings window's panel
    window_click("dd2dm_srow:damage_numbers_size")
    hit(W.casca, W.goblin, 15, W.goblin.hp - 15, at(800, 500))
    frame()
    local beige, panel = mod("ui/enemy_bars").COLORS.text, kit.COLORS.panel
    local enemy_at, number_at, panel_at
    for i, c in ipairs(ui.calls) do
        if c.fn == "add_text" and c.layer == "background" then
            if c.col == beige then enemy_at = enemy_at or i end
            if c.col & 0xFFFFFF == first & 0xFFFFFF then number_at = number_at or i end
        end
        if c.fn == "add_rect_filled" and c.col == panel and c.layer == "background" then panel_at = panel_at or i end
    end
    eq(enemy_at ~= nil and number_at ~= nil and panel_at ~= nil, true, "all three drawn")
    eq(enemy_at < number_at, true, "over the enemy HP numbers")
    eq(number_at < panel_at, true, "under the settings window's panel")
    -- Casca's second hit came within 0.3 s of the first: one number, the sum; the numbers add up to the meter
    eq(texts_in(first), "25", "merged with the first")
    local dealt = M.state.fight:snapshot(W.t).actors[mod("game/actors").of(W.casca).key].dealt
    eq(dealt, 25, "the meter counts the same")
    press(F8)
    ui.drawing_ui = false
    -- a hit on the party, a hit the fight holds, a hit with no HP: no number
    local ogre = char("ch221004_60_24", { hostile = true, hp = 9000, max_hp = 9000 })
    frame(1)
    hit(W.goblin, W.casca, 30, W.casca.hp - 30, at(600, 600))
    hit(char("ch111003_00", { hp = 1500 }), ogre, 500, 8500, at(600, 600))
    hit(W.player, W.goblin, 0, W.goblin.hp, at(600, 600))
    frame()
    eq(#M.state.numbers.items, 0, "none of them")
    eq(M.info().errors, 0, "no error caught")
    eq(#M.info().damage_numbers_missing, 0, "no call missing")
end)

test("damage numbers off, or the journal open: the hit point is not read and nothing is drawn", function()
    numbers_world({ damage_numbers = false })
    local M = load()
    local first = mod("ui/kit").actor_color("pawn", 5, 1)
    local reads = { n = 0 }
    local function strike_at(x, y)
        hit(W.casca, W.goblin, 10, W.goblin.hp - 10, counted_at(reads, x, y), {})
    end
    -- without a fight nothing is read either
    hit(char("ch111003_00", { hp = 1500 }), W.goblin, 10, W.goblin.hp - 10, counted_at(reads, 1, 1), {})
    eq(reads.n, 0, "no fight: nothing read")
    W.mode = 2
    frame()
    strike_at(800, 500)
    for _ = 1, 3 do frame() end
    eq(reads.n, 0, "off: nothing read")
    eq(#R.calls_of("get_Transform"), 0, "nor the victim's position")
    eq(texts_in(first), "", "nothing drawn")
    -- on from the settings window: read and drawn
    window_click("dd2dm_srow:damage_numbers")
    eq(M.state.settings.values.damage_numbers, true, "on")
    press(F8)
    ui.drawing_ui = false
    strike_at(800, 500)
    frame()
    eq(reads.n, 4, "on: the Position, IsWeakDamage and the DamageRate around the enemy's defence step")
    eq(texts_in(first), "10", "drawn")
    -- the journal open: the numbers live are forgotten, nothing is read or drawn
    press(F7)
    eq(M.info().journal, true, "the journal is open")
    eq(#M.state.numbers.items, 0, "forgotten")
    reads.n = 0
    strike_at(800, 500)
    frame()
    eq(reads.n, 0, "the journal open: nothing read")
    eq(texts_in(first), "", "nor drawn")
    press(F7)
    strike_at(800, 500)
    frame()
    eq(texts_in(first), "10", "closed: a new hit is drawn")
    -- off again: forgotten, nothing read or drawn
    window_click("dd2dm_srow:damage_numbers")
    eq(M.state.settings.values.damage_numbers, false, "off")
    eq(#M.state.numbers.items, 0, "forgotten")
    press(F8)
    ui.drawing_ui = false
    reads.n = 0
    strike_at(800, 500)
    for _ = 1, 3 do frame() end
    eq(reads.n, 0, "off again: nothing read")
    eq(texts_in(first), "", "nor drawn")
    eq(M.info().errors, 0, "no error caught")
end)

test("damage numbers: the style and the size from the settings window; a crit and a weak point", function()
    numbers_world()
    local M = load()
    local first = mod("ui/kit").actor_color("pawn", 5, 1)
    W.mode = 2
    frame()
    -- the enemy's defence step raised the DamageRate (a downed enemy): a crit; a weak point too
    hit(W.casca, W.goblin, 380, W.goblin.hp - 380, at(800, 500, { DamageRate = 1, IsWeakDamage = true }),
        { DamageRate = 1.5 })
    -- a DamageRate of 2.2 the step left as it was (the Trickster's incense, a buff): no crit
    hit(W.player, W.goblin, 220, W.goblin.hp - 220, at(300, 400, { DamageRate = 2.2 }), {})
    frame()
    eq(texts_in(first), "380!", "a crit: «!»")
    eq(texts_in(mod("ui/kit").actor_color("player", 1, 1)), "220", "the incense: no «!»")
    eq(#ui.calls_of("add_quad_filled") >= 2, true, "a weak point: its diamond")
    -- plates
    window_click("dd2dm_snext:damage_numbers_style")
    eq(M.state.settings.values.damage_numbers_style, "plates", "rise -> plates")
    eq(#M.state.numbers.items, 0, "a new style starts afresh")
    press(F8)
    ui.drawing_ui = false
    hit(W.casca, W.goblin, 50, W.goblin.hp - 50, at(800, 500))
    frame()
    local plate
    for _, r in ipairs(ui.calls_of("add_rect_filled")) do
        if r.layer == "background" and r.col & 0xFFFFFF == first & 0xFFFFFF then plate = r end
    end
    eq(plate ~= nil, true, "a plate in Casca's colour on the background list")
    near((plate.x0 + plate.x1) / 2, 800, 0.5, "on the hit point")
    -- the size: × 1.1 a step
    local function px_of(text)
        for _, c in ipairs(ui.calls_of("add_text")) do
            if c.text == text and c.layer == "background" then return c.px end
        end
    end
    eq(px_of("50"), 14, "14 px")
    window_click("dd2dm_snext:damage_numbers_size")
    eq(M.state.settings.values.damage_numbers_size, 1.1, "100 % -> 110 %")
    press(F8)
    ui.drawing_ui = false
    hit(W.rook, W.goblin, 60, W.goblin.hp - 60, at(1000, 500))
    frame()
    near(px_of("60"), 14 * 1.1, 1e-9, "14 px × 1.1")
    eq(M.info().errors, 0, "no error caught")
end)

test("a projection that raises does not break the frame; a new world forgets the numbers", function()
    numbers_world()
    local M = load()
    W.mode = 2
    frame()
    R.state.project = function() error("projection broke") end
    hit(W.casca, W.goblin, 10, W.goblin.hp - 10, at(800, 500))
    frame()
    eq(M.info().errors, 1, "caught")
    eq(overlay_shown(), true, "the meter still draws")
    eq(#M.state.numbers.items, 1, "the number lives on")
    R.method("app.CharacterManager", "get_ManualPlayer", function() return nil end)
    scene_change()
    eq(#M.state.numbers.items, 0, "forgotten with the old world")
end)

-- An enemy's slam within 3 s of a friend's hit on it is that friend's hit, so its number takes the friend's colour
-- where it lands; nothing else is drawn.
test("damage numbers: an enemy's slam within 3 s of a friend's hit on it is in that friend's colour", function()
    numbers_world()
    local M = load()
    local kit = mod("ui/kit")
    local actors = mod("game/actors")
    local first = kit.actor_color("pawn", 5, 1)
    local eir = char("ch300700_00_1", { name = "Eir", hp = 1200, max_hp = 1500 })
    local function has(texts, text) return ("|" .. texts .. "|"):find("|" .. text .. "|", 1, true) ~= nil end
    W.mode = 2
    frame()
    hit(W.casca, W.goblin, 10, W.goblin.hp - 10, at(800, 500))   -- Casca's blow
    frame(0.5)
    own_tick(W.goblin, 900, at(600, 300))                       -- the goblin slams down 0.5 s later
    frame()
    eq(has(texts_in(first), "900"), true, "the slam in Casca's shade: " .. texts_in(first))
    eq(texts_in(kit.COLORS.other), "", "nothing grey")
    near(M.state.fight:snapshot(W.t).actors[actors.of(W.casca).key].dealt, 910, 1e-6, "the meter counts it hers")
    hit(eir, W.goblin, 20, W.goblin.hp - 20, at(900, 500))       -- Eir's spell, an ally from its end
    frame(0.5)
    own_tick(W.goblin, 540, at(650, 300))
    frame()
    eq(has(texts_in(kit.COLORS.ally), "540"), true, "an ally's slam in the ally colour: " .. texts_in(kit.COLORS.ally))
    eq(texts_in(kit.COLORS.other), "", "still nothing grey")
    -- no friend's hit on it in the 3 s before: «Падения и среда», grey as before
    frame(3.5)
    own_tick(W.goblin, 150, at(700, 300))
    frame()
    eq(texts_in(kit.COLORS.other), "150", "a slam nobody caused: grey")
    eq(M.info().errors, 0, "no error caught")
end)

-- The settings window ----------------------------------------------------------------------------------

-- The settings window's row of `key`: its index.
local function row_index(key)
    for i, row in ipairs(mod("settings_view").ROWS) do
        if row.key == key then return i end
    end
end

test("F8 opens and closes the settings window, also with the journal off", function()
    world({ settings = { journal = false } })
    local M = load()
    frame()
    eq(settings_shown(), false, "closed at the start")
    ui.keys_down[F8] = true
    frame()
    eq(settings_shown(), true, "pressed: open")
    frame()
    eq(settings_shown(), true, "held: still open")
    ui.keys_down[F8] = nil
    frame()
    eq(settings_shown(), true, "released: still open")
    eq(ui.has_text("Hidden Numbers · " .. mod("i18n").t("settings_title")), true, "its title")
    press(F8)
    eq(settings_shown(), false, "pressed again: closed")
    eq(M.state.settings_window.open, false, "closed")

    -- the button in REFramework's menu opens it; the × in the window closes it
    ui.drawing_ui = true
    frame()
    ui.press("dd2dm_open_settings")
    draw_ui()
    frame()
    eq(settings_shown(), true, "the menu's button opens it")
    ui.press("dd2dm_open_settings")
    draw_ui()
    frame()
    eq(settings_shown(), true, "and leaves it open")
    ui.press("dd2dm_sclose")
    frame()
    frame()
    eq(settings_shown(), false, "× closes it")
    ui.drawing_ui = false
    frame()

    -- the key comes from the settings
    M.state.settings:set("settings_key", F10)
    press(F8)
    eq(settings_shown(), false, "F8 is no longer the key")
    press(F10)
    eq(settings_shown(), true, "F10 is")
    eq(ui.has_text(mod("i18n").t("settings_hint", "F10"):match("[^\n]+$")), true, "and the hint says so")
    eq(M.info().errors, 0, "no error caught")
end)

test("the settings window and the journal never open together", function()
    world()
    local M = load()
    frame()
    fight(strike)
    press(F7)
    eq(journal_shown(), true, "the journal")
    press(F8)
    eq(settings_shown(), true, "F8: the settings window")
    eq(journal_shown(), false, "the journal closed")
    eq(M.info().journal, false, "closed")
    press(F7)
    eq(journal_shown(), true, "F7: the journal")
    eq(settings_shown(), false, "the settings window closed")
    eq(M.state.settings_window.open, false, "closed")
    -- the menu's button too
    ui.drawing_ui = true
    frame()
    ui.press("dd2dm_open_settings")
    draw_ui()
    frame()
    eq(settings_shown(), true, "the menu's button opens it")
    eq(M.info().journal, false, "and closes the journal")
    eq(M.info().errors, 0, "no error caught")
end)

test("the meter is shown while the settings window is open; the hidden state comes back after", function()
    world({ settings = { summary_autohide = 5 } })
    local M = load()
    frame()
    -- no fight: the meter shows nothing, the window or not
    press(F8)
    eq(settings_shown(), true, "the settings window")
    eq(overlay_shown(), false, "no fight: no meter")
    press(F8)
    fight(strike)
    eq(overlay_shown(), true, "the summary")
    press(F6)
    eq(overlay_shown(), false, "hidden by the toggle key")
    press(F8)
    eq(overlay_shown(), true, "the settings window shows it")
    eq(M.state.hidden, true, "the hidden state is kept")
    frame(10)
    eq(overlay_shown(), true, "and stays")
    press(F8)
    eq(overlay_shown(), false, "closed: hidden again")

    -- shown, it does not hide itself while the window is open; its auto-hide counts from the closing
    press(F6)
    eq(overlay_shown(), true, "shown again")
    press(F8)
    frame(10)
    eq(overlay_shown(), true, "10 s with the window open: still there")
    press(F8)
    eq(overlay_shown(), true, "closed: the summary")
    frame(4.8)
    eq(overlay_shown(), true, "its auto-hide counts from the closing")
    frame(0.3)
    eq(overlay_shown(), false, "and hides it 5 s after")
    eq(M.state.hidden, true, "hidden")

    -- a fight: the live window, hidden or not
    press(F8)
    W.mode = 2
    frame()
    strike()
    frame(0.2)
    eq(M.state.mode, "live", "fighting")
    press(F6)
    eq(M.state.hidden, true, "hidden by the key")
    eq(overlay_shown(), true, "the live window still shows")
    eq(M.state.live_model ~= nil, true, "and is built")
    press(F8)
    eq(overlay_shown(), false, "closed: hidden again")
    eq(M.info().errors, 0, "no error caught")
end)

test("with no fight of this session the settings window shows the last fight of history.json", function()
    world({ settings = { history_file = true } })
    R.json_files[HISTORY_FILE] = saved_fights(2)
    local M = load()
    frame()
    eq(M.info().history, 2, "two fights from the file")
    eq(M.state.mode, "idle", "no summary yet")
    eq(overlay_shown(), false, "nothing shown")
    press(F8)
    eq(overlay_shown(), true, "the settings window shows the last fight's summary")
    eq(M.state.summary_model ~= nil, true, "built for it")
    press(F8)
    eq(overlay_shown(), false, "closed: nothing again")
    eq(M.state.mode, "idle", "the mode it had")
    eq(M.info().errors, 0, "no error caught")
end)

test("a toggle key that is one of the settings window's keys acts only for the window", function()
    world()
    local M = load()
    frame()
    fight(strike)
    M.state.settings:set("toggle_key", DOWN)
    press(F8)
    press(DOWN)
    eq(M.state.settings_window.sel, 2, "the window takes Down")
    eq(M.state.hidden, false, "the meter does not hide")
    press(F8)
    press(DOWN)
    eq(M.state.hidden, true, "closed: Down is the toggle key again")
    eq(M.state.settings_window.sel, 2, "and leaves the window alone")
end)

test("the settings window's keys: select, change, groups; only while it is open", function()
    world()
    local M = load()
    local SW = M.state.settings_window
    frame()
    press(DOWN)
    eq(SW.sel, 1, "Down with the window closed: nothing")
    press(F8)
    eq(SW.sel, row_index("style"), "it opens on the first row, the style")
    press(DOWN)
    eq(SW.sel, row_index("scale"), "Down")
    press(RIGHT)
    eq(M.state.settings.values.scale, 1.05, "Right: scale + 0.05")
    press(LEFT)
    press(LEFT)
    eq(M.state.settings.values.scale, 0.95, "Left twice")
    press(PGUP)
    eq(SW.sel, row_index("scale"), "PgUp in the first group: nothing")
    press(UP)
    press(UP)
    eq(SW.sel, 1, "Up on the first row stays")
    -- Enter flips a switch, Left/Right too
    for _ = 1, 4 do press(DOWN) end
    eq(SW.sel, row_index("outline"), "the outline switch")
    press(ENTER)
    eq(M.state.settings.values.outline, false, "Enter: off")
    press(ENTER)
    eq(M.state.settings.values.outline, true, "and on")
    press(RIGHT)
    eq(M.state.settings.values.outline, false, "Right flips it too")
    press(DOWN)
    eq(SW.sel, row_index("halo"), "without the panel: the halo next")
    -- the panel: the halo and the bars are skipped
    for _ = 1, 5 do press(UP) end
    press(RIGHT)
    eq(M.state.settings.values.style, "panel", "the panel")
    for _ = 1, 5 do press(DOWN) end
    eq(SW.sel, row_index("window_x"), "Down from the outline: the position, past the halo and the bars")
    -- closed: the keys are the game's again
    press(F8)
    press(RIGHT)
    eq(M.state.settings.values.window_x, 40, "closed: nothing changes")
    press(F8)
    eq(SW.sel, row_index("window_x"), "opened again on the row it had")
    eq(M.info().errors, 0, "no error caught")
end)

test("the settings window's table: Left/Right between cells, past a «—»; Enter flips the cell", function()
    world()
    local M = load()
    local SW = M.state.settings_window
    local v = M.state.settings.values
    frame()
    press(F8)
    press(PGDN)
    eq(SW.sel, row_index("section_enemies"), "PgDn: the table's first row")
    eq(SW.col, 2, "on its only cell, the summary's")
    press(LEFT)
    eq(SW.col, 2, "Left: no fight cell there")
    eq(v.summary_enemies, true, "nothing flipped")
    press(ENTER)
    eq(v.summary_enemies, false, "Enter flips the summary's enemies")
    press(DOWN)
    eq(SW.sel, row_index("section_damage"), "Down: the next row of the table")
    eq(SW.col, 2, "the same column")
    press(LEFT)
    eq(SW.col, 1, "Left: the fight cell")
    eq(v.live_damage, true, "Left flips nothing")
    press(ENTER)
    eq(v.live_damage, false, "Enter flips the fight's damage")
    eq(v.summary_damage, true, "not the summary's")
    press(DOWN)
    eq(SW.sel, row_index("section_taken"), "the damage taken")
    press(RIGHT)
    eq(SW.col, 1, "Right: no summary cell there")
    press(ENTER)
    eq(v.live_taken, false, "Enter flips the fight's damage taken")
    press(DOWN)
    press(DOWN)
    eq(SW.sel, row_index("section_armor"), "the armor")
    eq(SW.col, 2, "its only cell, the summary's")
    press(ENTER)
    eq(v.summary_armor, false, "flipped")
    press(UP)
    eq(SW.col, 2, "the healing: the summary cell kept")
    press(ENTER)
    eq(v.summary_heal, false, "the summary's healing")
    eq(v.live_heal, true, "not the fight's")
    -- the other rows of the table, then the auto-hide under it
    for _ = 1, 4 do press(DOWN) end
    eq(SW.sel, row_index("summary_autohide"), "under the table: the auto-hide")
    press(RIGHT)
    eq(v.summary_autohide, 1, "Right steps it: 1 s")
    eq(M.info().errors, 0, "no error caught")
end)

test("a change from the settings window has the side effects of one from the menu", function()
    world({ settings = { history_size = 3 } })
    local M = load()
    local i18n = mod("i18n")
    frame()
    for _ = 1, 3 do fight(strike) end
    eq(M.info().history, 3, "three fights")
    -- the language: at once, and the journal is rebuilt
    local J = M.state.journal
    J.dirty = false
    -- one page for the whole window, as on a 1440p screen: on the stub's 1920 × 1080 it pages by design and
    -- the Language row is on page 2 since the player's numbers' row came in
    ui.display = { x = 1920, y = 1200 }
    window_click("dd2dm_snext:language") -- auto -> en
    window_click("dd2dm_snext:language") -- en -> ru
    eq(i18n.lang(), "ru", "Russian at once")
    eq(J.dirty, true, "the journal will be built again")
    frame()
    eq(ui.has_text("Hidden Numbers · Настройки"), true, "the window itself in Russian, from the next frame")
    -- history_size: the history shrinks
    ui.press("history_next")
    frame()
    ui.press("history_next")
    frame()
    eq(M.state.history_index, 3, "the summary shows the oldest fight")
    window_click("dd2dm_sprev:history_size")
    eq(M.state.settings.values.history_size, 2, "history_size 2")
    eq(M.info().history, 2, "the history keeps two")
    eq(M.state.history_index, 2, "the summary on the oldest left")
    -- history_file: written at once
    local seen = watch_history_file()
    window_set("history_file", true)
    eq(#seen.opens, 1, "history.json written in the frame of the click")
    eq(#json_decode(R.files[HISTORY_FILE]), 2, "with the two fights")
    eq(R.json_files[SETTINGS_FILE].history_file, true, "and the settings saved first")
    eq(M.info().errors, 0, "no error caught")
end)

test("the settings window's key wait: the next new key; Esc gives up; another key's code is refused", function()
    world()
    local M = load()
    local Menu = mod("ui/menu")
    local v = M.state.settings.values
    frame()
    press(F8)
    for _ = 1, 7 do press(PGDN) end -- the keys group, the toggle key first
    -- Enter waits; the Enter still held is not taken
    ui.keys_down[ENTER] = true
    frame()
    eq(Menu.waiting_for(), "toggle_key", "waiting for the toggle key")
    frame()
    eq(ui.has_text(mod("i18n").t("press_a_key")), true, "the row says so")
    eq(v.toggle_key, F6, "the held Enter is not taken")
    ui.keys_down[ENTER] = nil
    frame()
    -- F8 and F7 are the other keys' codes: refused, the wait goes on, F8 does not close the window
    press(F8)
    eq(settings_shown(), true, "F8 while the window waits: still open")
    eq(Menu.capturing(), true, "still waiting")
    eq(v.toggle_key, F6, "F8 not taken")
    press(F7)
    eq(M.info().journal, false, "F7 does not open the journal")
    eq(v.toggle_key, F6, "F7 not taken")
    eq(Menu.capturing(), true, "still waiting")
    -- the window's own keys do nothing while it waits; PgDn is free, so it is taken
    press(PGDN)
    eq(M.state.settings_window.sel, row_index("toggle_key"), "PgDn while waiting: no move")
    eq(v.toggle_key, PGDN, "PgDn taken as the toggle key")
    -- Esc gives up
    press(ENTER)
    eq(Menu.capturing(), true, "waiting again")
    press(ESC)
    eq(Menu.capturing(), false, "Esc: the wait is over")
    eq(v.toggle_key, PGDN, "unchanged")
    -- a free key is taken
    press(ENTER)
    eq(Menu.capturing(), true, "waiting")
    press(0x41)
    eq(v.toggle_key, 0x41, "A taken")
    eq(Menu.capturing(), false, "the wait is over")
    eq(ui.has_text("A"), true, "the row shows it")
    press(DOWN)
    eq(M.state.settings_window.sel, row_index("journal_key"), "the keys move the selection again")
    -- the settings key itself, from its row
    press(DOWN)
    press(ENTER)
    press(F10)
    eq(v.settings_key, F10, "the settings window's own key")
    eq(settings_shown(), true, "still open: F10 was the key that was chosen")
    press(F10)
    eq(settings_shown(), false, "F10 closes it now")
    eq(M.info().errors, 0, "no error caught")
end)

test("closing the settings window ends its key wait, not the menu's", function()
    world()
    local M = load()
    local Menu = mod("ui/menu")
    frame()
    ui.display = { x = 1920, y = 1200 } -- one page: the keys' rows drawn
    window_click("dd2dm_srow:journal_key")
    eq(Menu.waiting_for(), "journal_key", "the window waits")
    ui.press("dd2dm_sclose")
    frame()
    eq(Menu.capturing(), false, "× closed it, and its wait")
    frame()
    eq(settings_shown(), false, "not drawn")
    -- a wait of the menu's button stays through the window's closing
    window_click("dd2dm_srow:scale")
    ui.press("dd2dm_settings_key")
    draw_ui()
    eq(Menu.waiting_for(), "settings_key", "the menu waits")
    ui.press("dd2dm_sclose")
    frame()
    frame()
    eq(settings_shown(), false, "closed")
    eq(Menu.waiting_for(), "settings_key", "the menu still waits")
    eq(M.info().errors, 0, "no error caught")
end)

test("window closed: one more key read a frame; open: its model only when something changed", function()
    world()
    local asked = watch_keys()
    local M = load()
    local SettingsView = mod("settings_view")
    local build, built = SettingsView.build, 0
    SettingsView.build = function(...)
        built = built + 1
        return build(...)
    end
    frame()
    fight(strike)
    for vk in pairs(asked) do asked[vk] = nil end
    for _ = 1, 10 do frame() end
    local total = 0
    for _, n in pairs(asked) do total = total + n end
    eq(asked[F8], 10, "the settings key once a frame")
    eq(asked[F6], 10, "as the toggle key"); eq(asked[F7], 10, "and the journal key")
    eq(total, 30, "nothing else")
    eq(built, 0, "no model built")
    eq(settings_shown(), false, "nothing drawn")
    -- the journal off: two
    M.state.settings:set("journal", false)
    frame()
    for vk in pairs(asked) do asked[vk] = nil end
    for _ = 1, 10 do frame() end
    total = 0
    for _, n in pairs(asked) do total = total + n end
    eq(total, 20, "the toggle and the settings key")

    -- open: built once, again after a change, not for a move of the selection
    press(F8)
    for _ = 1, 5 do frame() end
    eq(built, 1, "built once while nothing changes")
    for vk in pairs(mod("ui/settings_window").KEYS) do eq(asked[vk] ~= nil, true, "its key " .. vk .. " is read") end
    press(DOWN)
    eq(built, 1, "a move of the selection builds nothing")
    press(PGDN)
    press(DOWN)
    press(LEFT) -- the table: from the summary cell to the fight cell
    eq(built, 1, "nor a move between groups or between a table row's cells")
    for _ = 1, 6 do press(DOWN) end
    press(RIGHT) -- summary_autohide 0 -> 1
    eq(M.state.settings.values.summary_autohide, 1, "a change")
    eq(built, 2, "builds it again")
    press(LEFT)
    press(LEFT) -- at 0: no step, nothing changed
    eq(built, 3, "only a change builds")
    press(F8)
    for _ = 1, 5 do frame() end
    eq(built, 3, "closed: built no more")
    SettingsView.build = build
    eq(M.info().errors, 0, "no error caught")
end)

test("a settings window that fails to draw is reported and the meter still draws", function()
    world()
    local M = load()
    frame()
    fight(strike)
    local UI = mod("ui/settings_window")
    local draw = UI.draw
    UI.draw = function() return {}, "drawing exploded" end
    press(F8)
    eq(overlay_shown(), true, "the meter still draws")
    eq(M.info().errors > 0, true, "the error is caught and counted")
    UI.draw = draw
    frame()
    eq(settings_shown(), true, "and the window draws again")
end)

test("a key wait ends when REFramework's menu opens or closes", function()
    world()
    local M = load()
    local Menu = mod("ui/menu")
    local i18n = mod("i18n")
    local v = M.state.settings.values
    local INSERT = 0x2D
    frame()
    -- the menu's button waits, the menu closes without a key: the wait is gone, not a prompt in the window
    ui.drawing_ui = true
    frame()
    ui.press("dd2dm_settings_key")
    draw_ui()
    eq(Menu.waiting_for(), "settings_key", "the menu waits")
    ui.drawing_ui = false
    frame()
    eq(Menu.capturing(), false, "closed: the wait is over")
    press(F8)
    eq(settings_shown(), true, "F8 opens the window")
    eq(ui.has_text(i18n.t("press_a_key")), false, "no key prompt in it")
    press(F10)
    eq(v.settings_key, F8, "F10 does not become the settings key")
    for _ = 1, 7 do press(PGDN) end
    press(DOWN)
    press(DOWN)
    eq(M.state.settings_window.sel, row_index("settings_key"), "the settings key's row")
    press(ENTER)
    local key, by = Menu.waiting_for()
    eq(key, "settings_key", "Enter starts a fresh wait"); eq(by, "window", "the window's")
    press(ESC)

    -- a wait started by a click: the Insert that closes the menu does not become the key (1200 px: one page, the
    -- keys' rows drawn)
    ui.display = { x = 1920, y = 1200 }
    window_click("dd2dm_srow:toggle_key")
    eq(Menu.waiting_for(), "toggle_key", "a click waits")
    ui.keys_down[INSERT] = true
    ui.drawing_ui = false
    frame()
    eq(Menu.capturing(), false, "the menu closed: the wait is over")
    eq(v.toggle_key, F6, "Insert is not the toggle key")
    ui.keys_down[INSERT] = nil
    frame()
    eq(settings_shown(), true, "the window stays open")

    -- a wait started by Enter with the menu closed goes on until a key; opening the menu ends it
    eq(M.state.settings_window.sel, row_index("toggle_key"), "the toggle key's row, from the click")
    press(ENTER)
    for _ = 1, 5 do frame() end
    eq(Menu.waiting_for(), "toggle_key", "still waiting after five frames")
    ui.keys_down[INSERT] = true
    ui.drawing_ui = true
    frame()
    eq(Menu.capturing(), false, "the menu opened: the wait is over")
    eq(v.toggle_key, F6, "Insert is not the toggle key")
    ui.keys_down[INSERT] = nil
    frame()
    eq(M.info().errors, 0, "no error caught")
end)

test("the journal key and the settings key act only for the window that has them", function()
    world()
    local M = load()
    frame()
    fight(strike)
    -- the journal key is Down, one of the settings window's keys
    M.state.settings:set("journal_key", DOWN)
    press(F8)
    press(DOWN)
    eq(M.state.settings_window.sel, 2, "the window takes Down")
    eq(M.info().journal, false, "the journal does not open")
    eq(settings_shown(), true, "the window stays")
    press(F8)
    press(DOWN)
    eq(M.info().journal, true, "the window closed: Down opens the journal")
    -- the settings key is End, one of the journal's keys
    fight(strike)
    M.state.settings:set("settings_key", END)
    press(END)
    eq(M.state.journal.index, 2, "the journal takes End: the older fight")
    eq(M.state.settings_window.open, false, "the settings window does not open")
    eq(M.info().journal, true, "the journal stays")
    press(DOWN)
    eq(M.info().journal, false, "closed")
    press(END)
    eq(M.state.settings_window.open, true, "the journal closed: End opens the settings window")
    eq(M.info().errors, 0, "no error caught")
end)

test("info names the imgui calls the settings window found missing", function()
    world()
    local M = load()
    eq(type(M.info().settings_missing), "table", "settings_missing")
    eq(#M.info().settings_missing, 0, "nothing before it is drawn")
    frame()
    press(F8)
    eq(#M.info().settings_missing, 0, "nothing missing: " .. T.str(M.info().settings_missing))
    local get = imgui.get_display_size
    imgui.get_display_size = nil
    frame()
    imgui.get_display_size = get
    eq(contains(M.info().settings_missing, "get_display_size"), true, "a missing imgui call is named")
    eq(settings_shown(), true, "and the window still draws")
    eq(M.info().errors, 0, "no error caught")
end)

test("a settings window that cannot begin leaves its place and size to no other window", function()
    world()
    local M = load()
    frame()
    fight(strike)
    local begin = imgui.begin_window
    local pending
    imgui.begin_window = function(name, ...)
        if name == SETTINGS_WINDOW then error("no window") end
        if name == OVERLAY_WINDOW then pending = { pos = ui.next_pos, size = ui.next_size } end
        return begin(name, ...)
    end
    press(F8)
    imgui.begin_window = begin
    eq(pending ~= nil, true, "the meter was drawn after it")
    eq(pending.size, nil, "the meter gets no size of the settings window's")
    eq(pending.pos, nil, "nor its place")
    eq(M.info().errors > 0, true, "the failure is caught")
    eq(ui.balanced(), true, "balanced")
end)

-- The game's pause ---------------------------------------------------------------------------------------

-- app.PauseManager as read in game: isPausedAny() is true while a menu of the game is open (W.paused). Gives
-- the manager.
local function pause_manager()
    W.paused = false
    R.method("app.PauseManager", "isPausedAny", function() return W.paused end)
    local manager = R.object("app.PauseManager")
    R.singleton("app.PauseManager", manager)
    return manager
end

-- The game calls made on any of `objects` from now on: a function that counts them.
local function calls_on(objects)
    local set = {}
    for _, o in ipairs(objects) do set[o] = true end
    local from = #R.calls
    return function()
        local n = 0
        for i = from + 1, #R.calls do
            if set[R.calls[i].this] then n = n + 1 end
        end
        return n
    end
end

test("paused in a menu: no meter, no enemy or boss numbers, no damage numbers; all back when it closes", function()
    numbers_world()
    bars_scene()
    pause_manager()
    local M = load()
    gauge(W.goblin)
    local griffin = char("ch250000_00", { name = "Griffin", hostile = true, hp = 40000, max_hp = 90000 })
    boss_bar(griffin)
    local first = mod("ui/kit").actor_color("pawn", 5, 1)
    W.mode = 2
    frame()
    hit(W.casca, W.goblin, 10, W.goblin.hp - 10, at(800, 500))
    frame()
    eq(overlay_shown(), true, "the live meter")
    eq(numbers(), "3 043 / 3 700 · 82%|40 000 / 90 000 · 44%", "the enemy and the boss numbers")
    eq(texts_in(first), "10", "the damage number")
    -- the map opens
    W.paused = true
    frame()
    eq(overlay_shown(), false, "no meter")
    eq(numbers(), "", "no enemy or boss numbers")
    eq(texts_in(first), "", "no damage number")
    eq(#M.state.numbers.items, 0, "the numbers live are forgotten")
    -- nothing of the bars or of their characters' HP is read
    local bars_before = bar_reads()
    local on_them = calls_on({ W.goblin, W.goblin.hc, griffin, griffin.hc, griffin.go })
    for _ = 1, 5 do frame(0.5) end
    eq(bar_reads(), bars_before, "no bar read")
    eq(on_them(), 0, "nor the HP of their characters")
    eq(overlay_shown(), false, "still no meter")
    -- a hit meanwhile: counted by the fight, its point not read, no number
    local reads = { n = 0 }
    hit(W.casca, W.goblin, 10, W.goblin.hp - 10, counted_at(reads, 800, 500))
    frame()
    eq(reads.n, 0, "no hit point read")
    eq(#M.state.numbers.items, 0, "no number made")
    eq(M.state.fight:snapshot(W.t).actors[mod("game/actors").of(W.casca).key].dealt, 20, "the fight counts it")
    eq(M.state.mode, "live", "the fight goes on")
    -- the menu closes: all back, no stale number; the next hit makes one
    W.paused = false
    frame()
    eq(overlay_shown(), true, "the meter back")
    eq(numbers(), "3 033 / 3 700 · 82%|40 000 / 90 000 · 44%", "the enemy and the boss numbers back")
    eq(texts_in(first), "", "no stale damage number")
    hit(W.casca, W.goblin, 10, W.goblin.hp - 10, at(800, 500))
    frame()
    eq(texts_in(first), "10", "a new damage number")
    eq(M.info().errors, 0, "no error caught")
end)

test("paused: the journal and the settings window work as before; the meter shows with the settings window", function()
    world()
    pause_manager()
    local M = load()
    frame()
    fight(strike)
    eq(overlay_shown(), true, "the summary")
    W.paused = true
    frame()
    eq(overlay_shown(), false, "paused: no summary")
    -- the journal: its key, its keys, its window
    press(F7)
    eq(journal_shown(), true, "F7 opens the journal")
    press(PGDN)
    eq(M.state.journal.tab, "skills", "PgDn: the next tab")
    eq(journal_shown(), true, "drawn")
    press(F7)
    eq(journal_shown(), false, "F7 closes it")
    eq(overlay_shown(), false, "still paused: no summary")
    -- the settings window: its key, its keys, its window, and the meter beside it
    press(F8)
    eq(settings_shown(), true, "F8 opens the settings window")
    eq(overlay_shown(), true, "and shows the meter")
    local sel = M.state.settings_window.sel
    press(DOWN)
    eq(M.state.settings_window.sel, sel + 1, "Down: the next row")
    eq(settings_shown() and overlay_shown(), true, "both drawn")
    press(F8)
    eq(settings_shown(), false, "F8 closes it")
    eq(overlay_shown(), false, "still paused: no summary")
    W.paused = false
    frame()
    eq(overlay_shown(), true, "the pause over: the summary")
    eq(M.info().errors, 0, "no error caught")
end)

test("a pause keeps the shown or hidden state; the summary's auto-hide counts from its end", function()
    world({ settings = { summary_autohide = 5 } })
    pause_manager()
    local M = load()
    frame()
    fight(strike)
    eq(overlay_shown(), true, "the summary")
    -- 20 s in the map: the summary does not hide itself meanwhile
    W.paused = true
    frame()
    frame(20)
    eq(M.state.hidden, false, "not hidden")
    W.paused = false
    frame()
    eq(overlay_shown(), true, "the summary back")
    frame(4.8)
    eq(overlay_shown(), true, "its auto-hide counts from the pause's end")
    frame(0.3)
    eq(overlay_shown(), false, "and hides it 5 s after")
    -- hidden: hidden after a pause too
    W.paused = true
    frame()
    W.paused = false
    frame()
    eq(overlay_shown(), false, "still hidden")
    -- a fight hidden with the toggle key: hidden after a pause, shown with the key
    W.mode = 2
    frame()
    strike()
    frame(0.2)
    press(F6)
    eq(M.state.hidden, true, "hidden by the key")
    W.paused = true
    frame()
    W.paused = false
    frame()
    eq(overlay_shown(), false, "still hidden after the pause")
    press(F6)
    eq(overlay_shown(), true, "the key shows it")
    W.paused = true
    frame()
    eq(M.state.hidden, false, "the pause hides it, the hidden state stays")
    W.paused = false
    frame()
    eq(overlay_shown(), true, "shown after the pause")
    eq(M.info().errors, 0, "no error caught")
end)

test("a PauseManager that is missing, raises or gives no answer counts as not paused", function()
    numbers_world()
    bars_scene()
    local M = load()
    gauge(W.goblin)
    local first = mod("ui/kit").actor_color("pawn", 5, 1)
    local function all_drawn(what)
        hit(W.casca, W.goblin, 10, W.goblin.hp - 10, at(800, 500))
        frame()
        eq(overlay_shown(), true, what .. ": the meter")
        eq(numbers() ~= "", true, what .. ": the enemy numbers")
        eq(texts_in(first) ~= "", true, what .. ": the damage numbers")
        frame(1)
    end
    W.mode = 2
    frame()
    all_drawn("no PauseManager")
    local manager = pause_manager()
    W.paused = true
    manager.poison = true
    all_drawn("its call raises")
    manager.poison = false
    for _, odd in ipairs({ 1, "true" }) do
        W.paused = odd
        all_drawn("an answer of " .. tostring(odd))
    end
    W.paused = nil
    all_drawn("no answer")
    local lookup = sdk.get_managed_singleton
    sdk.get_managed_singleton = function(name)
        if name == "app.PauseManager" then error("no singleton") end
        return lookup(name)
    end
    all_drawn("its lookup raises")
    sdk.get_managed_singleton = lookup
    W.paused = true
    frame()
    eq(overlay_shown(), false, "it answers again: paused")
    eq(M.info().errors, 0, "no error caught")
end)

test("the pause costs one game call a frame, none while the journal is open", function()
    world()
    pause_manager()
    local lookups = 0
    local lookup = sdk.get_managed_singleton
    sdk.get_managed_singleton = function(name)
        if name == "app.PauseManager" then lookups = lookups + 1 end
        return lookup(name)
    end
    local M = load()
    frame()
    fight(strike)
    local function reads() return #R.calls_of("isPausedAny") end
    local at_start, looked = reads(), lookups
    for _ = 1, 10 do frame() end
    eq(reads() - at_start, 10, "one isPausedAny a frame")
    eq(lookups - looked, 10, "the manager looked up by name each frame, not kept")
    W.paused = true
    at_start, looked = reads(), lookups
    for _ = 1, 10 do frame() end
    eq(reads() - at_start, 10, "paused: the same")
    eq(lookups - looked, 10, "paused: looked up each frame")
    W.paused = false
    frame()
    -- the journal open: not read
    press(F7)
    eq(M.info().journal, true, "the journal is open")
    at_start, looked = reads(), lookups
    for _ = 1, 5 do frame() end
    eq(reads(), at_start, "the journal open: not read")
    eq(lookups, looked, "the journal open: not looked up")
    press(F7)
    eq(M.info().errors, 0, "no error caught")
end)

-- The status buildup bars ---------------------------------------------------------------------------------

local STATUS_ENUM = "app.StatusConditionDef.StatusConditionEnum"

-- The boss bar's boss, its statuses building: statuses = { { id, value, max } } (a test changes value), a status set
-- off with active = true, remain (frames left) and frames (its param's ActiveTimerMaxFrame); every object of its
-- status controller in c.status_objects, for calls_on.
local LEAN, BLOWN = "getDmgReactionLeanPoint(System.Int32)", "getDmgReactionBlownPoint(System.Int32)"
local THRESHOLD = "getNextThreshold(System.Boolean, System.Int32)"

local function building_boss(statuses, poise)
    R.enum(STATUS_ENUM, { Poison = 1, Faint = 3, FireSpread = 5 })
    local c = char("ch250000_00", { name = "Griffin", hostile = true, hp = 40000, max_hp = 90000, chara_id = 1303 })
    -- its hit controller's poise: poise = { lean, blown } its points, Fimbul's thresholds 65 000 and 195 000
    if poise then
        c.hc.methods[LEAN] = function() return poise.lean end
        c.hc.methods[BLOWN] = function() return poise.blown end
        c.hc.methods[THRESHOLD] = function(_, blown) return blown and 195000 or 65000 end
    end
    local objects, infos = {}, {}
    for i, o in ipairs(statuses) do
        local param = R.object("app.StatusConditionActionParam", { EnduranceMax = o.max,
            ActiveTimerMaxFrame = o.frames })
        local res = R.object("app.StatusConditionParamRes", { _ActionParamList = R.list({ param }) })
        infos[i] = R.object("app.StatusConditionInfo", {}, {
            get_StatusConditionId = function() return o.id end,
            getEnduranceValue = function() return o.value end,
            get_ParamRes = function() return res end,
            get_IsActive = function() return o.active == true end,
            get_ActiveRemainTime = function() return o.remain or -1 end,
        })
        for _, obj in ipairs({ infos[i], res, param }) do objects[#objects + 1] = obj end
    end
    local list = R.list(infos)
    local ctrl = R.object("app.StatusConditionCtrl", { StatusConditionInfoList = list })
    objects[#objects + 1], objects[#objects + 1] = ctrl, list
    c.methods.get_StatusConditionCtrl = function() return ctrl end
    c.status_objects = objects
    return c
end

-- The buildup rows drawn this frame: the texts on the background list under the boss bar (FULL HD: x 564 to 1340,
-- under y 113), each SceneText's own copy, a row's joined by " ", the rows by " | "; "" without one.
local function buildup_text()
    local st = mod("ui/scene_text").COLORS
    local rows, y = {}, nil
    for _, c in ipairs(ui.calls_of("add_text")) do
        if c.layer == "background" and c.x >= 564 and c.x <= 1340 and c.y > 113 and c.col ~= st.shadow
                and c.col ~= st.outline then
            if c.y ~= y then
                rows[#rows + 1] = c.text
                y = c.y
            else
                rows[#rows] = rows[#rows] .. " " .. c.text
            end
        end
    end
    return table.concat(rows, " | ")
end

-- The rows read: each read asks every status's value once.
local function buildup_reads(statuses)
    return #R.calls_of("getEnduranceValue") / statuses
end

-- The poise calls made so far.
local function poise_reads()
    return #R.calls_of(LEAN) + #R.calls_of(BLOWN) + #R.calls_of(THRESHOLD)
end

test("the poise rows: stagger and knock-down from the boss bar's TargetHitCtrl, over the status rows", function()
    world()
    bars_scene()
    local M = load()
    local poise = { lean = 41841, blown = 41841 }
    local griffin = building_boss({ { id = 3, value = 313, max = 1400 } }, poise)
    local b = boss_bar(griffin)
    frame()
    eq(buildup_text(), "Stagger 41 841 / 65 000 | Knock down 41 841 / 195 000 | Faint 313 / 1 400",
        "the poise first, then the statuses")
    poise.lean, poise.blown = 42841, 42841
    frame(0.15)
    eq(buildup_text(), "Stagger 42 841 / 65 000 · ≈ 23 hits | Knock down 42 841 / 195 000 | Faint 313 / 1 400",
        "a rise of 1 000 on both: the stagger ceil(22 159 / 1 000), the knock-down no estimate")
    poise.lean, poise.blown = 0, 0
    frame(0.15)
    eq(buildup_text(), "Faint 313 / 1 400", "staggered and reset: the poise rows gone")
    -- no boss bar: nothing of it read
    b.drawn = false
    local reads = poise_reads()
    for _ = 1, 5 do frame(0.2) end
    eq(poise_reads(), reads, "the bar gone: nothing read")
    eq(M.info().errors, 0, "no error caught")
end)

test("the buildup bars: under the boss bar while it is drawn, from the frame's one boss read, 10 reads a second",
    function()
    world()
    bars_scene()
    local M = load()
    local faint = { id = 3, value = 313, max = 1400 }
    local griffin = building_boss({ faint, { id = 5, value = 0, max = 5000 } })
    local b = boss_bar(griffin)
    frame()
    eq(buildup_text(), "Faint 313 / 1 400", "the status building, under the bar; the burning at 0 has no row")
    -- one boss read a frame for the HP numbers, the plate and the buildup bars together
    local sizes = #R.calls_of("get_Size")
    frame()
    eq(#R.calls_of("get_Size") - sizes, 1, "the boss bar's size read once")
    -- at most 10 reads a second, the last answer drawn in between
    local reads = buildup_reads(2)
    for _ = 1, 50 do frame(0.02) end
    local n = buildup_reads(2) - reads
    eq(n >= 8 and n <= 10, true, "a second of 50 frames: " .. n .. " reads")
    eq(buildup_text(), "Faint 313 / 1 400", "drawn every frame")
    -- the party's hits raise it: the hits left from the rises
    for _, v in ipairs({ 413, 513 }) do
        faint.value = v
        frame(0.15)
    end
    eq(buildup_text(), "Faint 513 / 1 400 · ≈ 9 hits", "two rises of 100: ceil(887 / 100)")
    -- the bar gone: nothing read, nothing drawn
    b.drawn = false
    reads = buildup_reads(2)
    for _ = 1, 5 do frame(0.2) end
    eq(buildup_reads(2), reads, "the bar gone: nothing read")
    eq(buildup_text(), "", "nor drawn")
    eq(M.info().errors, 0, "no error caught")
    eq(#M.info().buildup_bars_missing, 0, "no imgui call missing")
end)

test("a status set off drains every frame, between the reads: the frame's t reaches the buildup bars", function()
    world()
    bars_scene()
    local M = load()
    -- Faint set off: 420.6 frames (7.01 s) left of its 480
    boss_bar(building_boss({ { id = 3, value = 0, max = 1400, active = true, remain = 420.6, frames = 480 } }))
    frame()
    eq(buildup_text(), "Faint 8 s left", "read: 7.01 s, 8 whole seconds rounded up")
    local reads = buildup_reads(1)
    frame(0.05)
    eq(buildup_reads(1), reads, "0.05 s later: not read again")
    eq(buildup_text(), "Faint 7 s left", "but drawn at the frame's t: 6.96 s")
    eq(M.info().errors, 0, "no error caught")
end)

test("nothing is read for the buildup bars while paused, with the journal open, or with the setting off", function()
    -- the HP numbers, the plate and the player's numbers off: the buildup bars alone want the game's bars
    world({ settings = { enemy_hp_numbers = "off", boss_hp_numbers = "off", enemy_plate = false,
        player_numbers = false } })
    bars_scene()
    pause_manager()
    local M = load()
    local griffin = building_boss({ { id = 3, value = 313, max = 1400 } }, { lean = 0, blown = 0 })
    boss_bar(griffin)
    frame()
    eq(buildup_text(), "Faint 313 / 1 400", "on: shown")
    eq(poise_reads() > 0, true, "the poise read too")
    local function none(what)
        local before, on_them, poised = bar_reads(), calls_on(griffin.status_objects), poise_reads()
        for _ = 1, 5 do frame(0.5) end
        eq(on_them(), 0, what .. ": nothing of the boss's statuses read")
        eq(poise_reads(), poised, what .. ": nor its poise")
        eq(bar_reads(), before, what .. ": nor the boss bar")
        eq(buildup_text(), "", what .. ": nothing drawn")
    end
    W.paused = true
    none("paused")
    W.paused = false
    frame()
    eq(buildup_text(), "Faint 313 / 1 400", "the pause over: back")
    press(F7)
    eq(M.info().journal, true, "the journal is open")
    none("the journal open")
    press(F7)
    eq(buildup_text(), "Faint 313 / 1 400", "closed: back")
    -- switched off: the bars found forgotten, the boss bar read no more
    window_set("buildup_bars", false)
    eq(M.state.settings.values.buildup_bars, false, "off")
    eq(mod("game/gauges").count(), 0, "the bars found forgotten")
    press(F8)
    ui.drawing_ui = false
    none("off")
    window_set("buildup_bars", true)
    press(F8)
    ui.drawing_ui = false
    eq(buildup_text(), "Faint 313 / 1 400", "on again: read and drawn")
    eq(M.info().errors, 0, "no error caught")
end)

-- The player's own numbers ---------------------------------------------------------------------------------

-- The player's HUD (ui020901) as read in game: its GUI's view holds PNL_Playergauge/PNL_All, under it PNL_Sp
-- and PNL_Hp. Each holds its bar's fill (PNL_Hp/PNL_Line/PNL_Mline/s9g_Line, 469.7 × 6 at 60 % HP;
-- PNL_Sp/PNL_Spline/PNL_Mspline/rec_Line, 710.6 × 2), then its full-length background, the one the numbers go by:
-- PNL_Hp/PNL_Hpbg/PNL_Mhpbg/s9g_Base (669.8, 1010, 780 × 7 in GUI space) and
-- PNL_Sp/PNL_Spbg/PNL_Mspbg/s9g_Base (669.8, 1026.6, 780 × 6). Drawn unless o.drawn is false (h.drawn changes it
-- later). The player's get_Hit and get_StaminaManager give h.hc and h.sm, which answer with h.v's numbers (a test
-- changes them). h.lines: the view and its elements; h.numbers: h.hc and h.sm (for calls_on).
local function player_hud(o)
    o = o or {}
    local h = { drawn = o.drawn ~= false, lines = {} }
    h.v = { hp = 3030.84, hp_max = 3030.84, hp_full = 3100, sp = 1202, sp_max = 1300, sp_full = 1300 }
    local function el(name, children, pos, size)
        local e = R.object("via.gui.Control", {}, {
            get_Name = function() return name end,
            get_Child = function() return children and children[1] end,
            get_GlobalPosition = function() return pos and { x = pos[1], y = pos[2], z = 0 } end,
            get_Size = function() return size and { w = size[1], h = size[2] } end,
        })
        for i, child in ipairs(children or {}) do
            local nxt = children[i + 1]
            child.methods.get_Next = function() return nxt end
        end
        h.lines[#h.lines + 1] = e
        return e
    end
    local hp = el("PNL_Hp", {
        el("PNL_Line", { el("PNL_Mline", { el("s9g_Line", nil, { 669.8, 1013.5 }, { 469.7, 6 }) }) }),
        el("PNL_Hpbg", { el("PNL_Mhpbg", { el("s9g_Base", nil, { 669.8, 1010 }, { 780, 7 }) }) }),
    })
    local sp = el("PNL_Sp", {
        el("PNL_Spline", { el("PNL_Mspline", { el("rec_Line", nil, { 669.8, 1028.6 }, { 710.6, 2 }) }) }),
        el("PNL_Spbg", { el("PNL_Mspbg", { el("s9g_Base", nil, { 669.8, 1026.6 }, { 780, 6 }) }) }),
    })
    local root = el("PNL_Playergauge", { el("PNL_All", { sp, hp }, { 671.3, 1010 }) })
    h.view = R.object("via.gui.View", {}, { get_Child = function() return root end })
    h.lines[#h.lines + 1] = h.view
    h.go = R.object("via.GameObject", {}, {
        get_Name = function() return "ui020901" end,
        get_DrawSelf = function() return h.drawn end,
    })
    h.gui = R.object("via.gui.GUI", {}, {
        get_GameObject = function() return h.go end,
        get_View = function() return h.view end,
    })
    W.guis[#W.guis + 1] = h.gui
    h.hc = R.object(HC, {}, {
        get_Hp = function() return h.v.hp end,
        get_ReducedMaxHp = function() return h.v.hp_max end,
        get_OriginalMaxHp = function() return h.v.hp_full end,
    })
    h.sm = R.object("app.StaminaManager", {}, {
        get_RemainingAmount = function() return h.v.sp end,
        get_ReducedMaxValue = function() return h.v.sp_max end,
        get_MaxValue = function() return h.v.sp_full end,
    })
    h.numbers = { h.hc, h.sm }
    W.player.methods.get_Hit = function() return h.hc end
    W.player.methods.get_StaminaManager = function() return h.sm end
    return h
end

-- The player's numbers drawn this frame: the texts in the enemy numbers' beige on the background list at the bottom
-- of the screen (under y 900), joined by "|".
local function player_numbers()
    local beige, list = mod("ui/enemy_bars").COLORS.text, {}
    for _, c in ipairs(ui.calls_of("add_text")) do
        if c.layer == "background" and c.col == beige and c.y > 900 then list[#list + 1] = c.text end
    end
    return table.concat(list, "|")
end

test("the player's numbers: HP above its HUD bar, stamina below its bar, from the player; under the windows",
    function()
    world()
    bars_scene()
    local M = load()
    local h = player_hud()
    frame()
    eq(player_numbers(), "3 031 / 3 031 (3 100)|1 202 / 1 300", "the HP with its full max in brackets, the stamina")
    -- on 1920 × 1080, by the bars' full-length backgrounds, not their fills: the HP text's right edge at the HP
    -- bar's right end (669.8 + 780), its bottom 3 px above the bar's top (1010); the stamina text's right edge at
    -- its bar's right end (669.8 + 780), its top 3 px under the bar's bottom (1026.6 + 6)
    local function width(text) return utf8.len(text) * ui.char_w * 15 / 14 end
    local hp, sp = number_call("3 031 / 3 031 (3 100)"), number_call("1 202 / 1 300")
    near(hp.x + width(hp.text), 669.8 + 780, 0.5, "the HP text's right edge"); near(hp.y + 15, 1010 - 3, 0.5, "y")
    near(sp.x + width(sp.text), 669.8 + 780, 0.5, "the stamina text's right edge"); near(sp.y, 1032.6 + 3, 0.5, "y")
    -- read every frame: healed up to the full max, a sprint below 0
    h.v.hp, h.v.hp_max, h.v.sp = 3100, 3100, -120
    frame()
    eq(player_numbers(), "3 100 / 3 100|-120 / 1 300", "no brackets at the full max; the sign")
    -- only the player's numbers: no pawn's
    eq(#R.calls_of("get_Hit") > 0, true, "read")
    for _, c in ipairs(R.calls_of("get_Hit")) do eq(c.this, W.player, "asked of the player alone") end
    -- their size: the enemy numbers', from the settings window; drawn before its panel, so they lie under it
    window_click("dd2dm_snext:enemy_hp_size")
    eq(M.state.settings.values.enemy_hp_size, 1.1, "100 % -> 110 %")
    frame()
    eq(number_call("3 100 / 3 100").px, 16.5, "15 px × 1.1")
    local panel = mod("ui/kit").COLORS.panel
    local first_number, first_panel
    for i, c in ipairs(ui.calls) do
        if c.fn == "add_text" and c.text == "3 100 / 3 100" and not first_number then first_number = i end
        if c.fn == "add_rect_filled" and c.col == panel and c.layer == "background" and not first_panel then
            first_panel = i
        end
    end
    eq(first_number ~= nil and first_panel ~= nil and first_number < first_panel, true, "under the settings panel")
    press(F8)
    ui.drawing_ui = false
    -- the game hides its HUD: none, and the numbers are not read
    h.drawn = false
    local on_numbers = calls_on(h.numbers)
    for _ = 1, 3 do frame() end
    eq(player_numbers(), "", "the HUD hidden: none")
    eq(on_numbers(), 0, "the player's numbers not read")
    h.drawn = true
    frame()
    eq(player_numbers(), "3 100 / 3 100|-120 / 1 300", "shown again")
    eq(M.info().errors, 0, "no error caught")
    eq(#M.info().player_numbers_missing, 0, "no imgui call missing")
end)

test("nothing is read for the player's numbers while paused, with the journal open, or with the setting off", function()
    -- the enemy numbers, the plate and the buildup bars off: the player's numbers alone want the game's bars
    world({ settings = { enemy_hp_numbers = "off", boss_hp_numbers = "off", enemy_plate = false,
        buildup_bars = false } })
    bars_scene()
    pause_manager()
    local M = load()
    local h = player_hud()
    frame()
    eq(player_numbers(), "3 031 / 3 031 (3 100)|1 202 / 1 300", "on: shown")
    local function none(what)
        local before, on_lines, on_numbers = bar_reads(), calls_on(h.lines), calls_on(h.numbers)
        for _ = 1, 5 do frame(0.5) end
        eq(bar_reads(), before, what .. ": the HUD not read")
        eq(on_lines(), 0, what .. ": nor its lines")
        eq(on_numbers(), 0, what .. ": nor the player's numbers")
        eq(player_numbers(), "", what .. ": nothing drawn")
    end
    W.paused = true
    none("paused")
    W.paused = false
    frame()
    eq(player_numbers(), "3 031 / 3 031 (3 100)|1 202 / 1 300", "the pause over: back")
    press(F7)
    eq(M.info().journal, true, "the journal is open")
    none("the journal open")
    press(F7)
    eq(player_numbers(), "3 031 / 3 031 (3 100)|1 202 / 1 300", "closed: back")
    -- switched off: the bars found forgotten, nothing read
    local gauges = mod("game/gauges")
    local reset, resets = gauges.reset, 0
    gauges.reset = function()
        resets = resets + 1
        return reset()
    end
    window_set("player_numbers", false)
    gauges.reset = reset
    eq(M.state.settings.values.player_numbers, false, "off")
    eq(resets, 1, "the bars found forgotten")
    press(F8)
    ui.drawing_ui = false
    none("off")
    window_set("player_numbers", true)
    press(F8)
    ui.drawing_ui = false
    eq(player_numbers(), "3 031 / 3 031 (3 100)|1 202 / 1 300", "on again: read and drawn")
    eq(M.info().errors, 0, "no error caught")
end)

test("a HUD or a reader that raises does not break the frame", function()
    world()
    bars_scene()
    local M = load()
    local h = player_hud()
    frame()
    fight(strike)
    eq(player_numbers(), "3 031 / 3 031 (3 100)|1 202 / 1 300", "both")
    -- the stamina manager raises: the HP alone, no error
    h.sm.poison = true
    frame()
    eq(player_numbers(), "3 031 / 3 031 (3 100)", "the HP alone")
    h.sm.poison = false
    -- the HUD's GameObject raises (the game destroyed it): none until the next look, without an error
    h.go.poison = true
    frame()
    eq(player_numbers(), "", "none")
    eq(mod("game/gauges").gone(), 1, "counted as gone")
    h.go.poison = false
    frame(1)
    eq(player_numbers(), "3 031 / 3 031 (3 100)|1 202 / 1 300", "back at the next look")
    eq(M.info().errors, 0, "no error: normal play")
    -- the whole step raising is caught like the others
    local gauges = mod("game/gauges")
    local player = gauges.player
    gauges.player = function() error("reader broke") end
    frame()
    eq(M.info().errors, 1, "caught")
    eq(overlay_shown(), true, "the meter still draws")
    gauges.player = player
    frame()
    eq(player_numbers(), "3 031 / 3 031 (3 100)|1 202 / 1 300", "and the numbers again")
end)

-- The enemy plate ------------------------------------------------------------------------------------------

-- A hostile character of the enemy kind `chara_id`, called `name` (o.hp, o.max_hp: 3000 by default).
local function foe(go, name, chara_id, o)
    o = o or {}
    return char(go, { name = name, hostile = true, chara_id = chara_id, hp = o.hp or 3000, max_hp = o.max_hp or 3000 })
end

-- The lines the enemy plate drew this frame: the texts on the background list inside its backing, a line's pieces
-- joined, with a space where a gap lies between two (the table's cells), the lines joined by " / "; "" without a
-- plate.
local function plate_text()
    local box = plate_box()
    if box == nil then return "" end
    local lines, y, right = {}, nil, nil
    for _, c in ipairs(ui.calls_of("add_text")) do
        if c.layer == "background" and inside(c, box) then
            if c.y ~= y then
                lines[#lines + 1] = ""
                y, right = c.y, nil
            end
            if right and c.x > right + 0.5 then lines[#lines] = lines[#lines] .. " " end
            lines[#lines] = lines[#lines] .. c.text
            right = c.x + utf8.len(c.text) * ui.char_w * c.px / 14
        end
    end
    return table.concat(lines, " / ")
end

-- The font size of the plate's first text this frame.
local function plate_px()
    local box = plate_box()
    for _, c in ipairs(ui.calls_of("add_text")) do
        if c.layer == "background" and inside(c, box) then return c.px end
    end
    return nil
end

-- The builds of the plate's model from now on: { t, kinds, weapon, boss_id } each.
local function watch_builds(M)
    local built, model = {}, M.state.plate
    local build = model.build
    model.build = function(self, t, kinds, weapon, boss_id)
        built[#built + 1] = { t = t, kinds = kinds, weapon = weapon, boss_id = boss_id }
        return build(self, t, kinds, weapon, boss_id)
    end
    return built
end

-- A build's kinds: "1101 Goblin ×3, 1202 Ogre ×1".
local function kinds_of(b)
    local out = {}
    for _, k in ipairs(b and b.kinds or {}) do
        out[#out + 1] = string.format("%d %s ×%d", k.chara_id, k.name, k.count)
    end
    return table.concat(out, ", ")
end

test("a player's hit on an enemy feeds the plate model, only while enemy_plate is on", function()
    world()
    local M = load()
    local fed = {}
    local model = M.state.plate
    local add_hit = model.add_hit
    model.add_hit = function(self, t, parts)
        fed[#fed + 1] = { t = t, parts = parts }
        return add_hit(self, t, parts)
    end
    local ogre = foe("ch221004_00_01", "Ogre", 1202)
    W.mode = 2
    frame()
    hit(W.player, ogre, 100, ogre.hp - 100, nil, { SlashDamage = 100 })
    eq(#fed, 1, "the player's hit")
    eq(fed[1].t, W.t, "at its time")
    eq(fed[1].parts.Slash ~= nil and fed[1].parts.Slash.w, 100, "its parts as the ledger splits them")
    eq(#model.hits, 1, "kept by the model")
    -- the ogre slams down right after his blow: his damage, but no attack of his
    own_tick(ogre, 300)
    local guts = mod("game/actors").of(W.player).key
    near(M.state.fight:snapshot(W.t).actors[guts].dealt, 400, 1e-6, "the slam is the player's")
    eq(#fed, 1, "but feeds no plate")
    -- a pawn's hit, an enemy's hit on the player, the player's hit on a pawn: none
    hit(W.casca, ogre, 10, ogre.hp - 10, nil, { SlashDamage = 10 })
    hit(ogre, W.player, 50, W.player.hp - 50, nil, { BlowDamage = 50 })
    hit(W.player, W.casca, 5, W.casca.hp - 5, nil, { SlashDamage = 5 })
    eq(#fed, 1, "only the player's hits on enemies")
    -- a burn tick the player caused: his, but no attack of his
    local player_key = mod("game/actors").of(W.player).key
    local dealt = M.state.fight:snapshot(W.t).actors[player_key].dealt
    W.burning[FIRE_SPREAD] = W.player.chara_id
    dot_tick(W.goblin, 5, W.goblin.hp - 5)
    eq(M.state.fight:snapshot(W.t).actors[player_key].dealt, dealt + 5, "the tick is the player's")
    eq(#fed, 1, "but feeds no plate")
    -- off from the settings window: the hits are forgotten, none is fed
    window_set("enemy_plate", false)
    eq(M.state.settings.values.enemy_plate, false, "off")
    eq(#M.state.plate.hits, 0, "the hits forgotten")
    press(F8)
    ui.drawing_ui = false
    hit(W.player, ogre, 100, ogre.hp - 100, nil, { SlashDamage = 100 })
    eq(#fed, 1, "off: not fed")
    -- on again: fed again
    window_set("enemy_plate", true)
    press(F8)
    ui.drawing_ui = false
    hit(W.player, ogre, 100, ogre.hp - 100, nil, { SlashDamage = 100 })
    eq(#fed, 2, "on: fed")
    eq(M.info().errors, 0, "no error caught")
end)

test("the plate lists kinds from the hostile bars and the fight's living enemies, one row per chara_id with the count",
    function()
    world()
    bars_scene()
    local M = load()
    local built = watch_builds(M)
    local g1, g2, g3 = foe("ch220003_00_20", "Goblin", 1101), foe("ch220003_00_21", "Goblin", 1101),
        foe("ch220003_00_22", "Goblin", 1101)
    local ogre = foe("ch221004_00_01", "Ogre", 1202)
    local b1 = gauge(g1, { x = 300 })
    gauge(ogre, { x = 500 })
    local b2 = gauge(g2, { x = 700 })
    gauge(W.goblin, { x = 900 }) -- no CharaID: no kind
    frame()
    eq(kinds_of(built[#built]), "1101 Goblin ×2, 1202 Ogre ×1", "the bars: one entry per kind, in the scene's order")
    eq(plate_text(), "Goblin ×2 no data / Ogre no data", "drawn: one row per kind")
    eq(numbers(), "3 000 / 3 000 · 100%|3 000 / 3 000 · 100%|3 000 / 3 000 · 100%|3 053 / 3 700 · 83%",
        "the HP numbers as before")
    -- a fight: its living enemies count too, out of sight or not, each enemy once
    W.mode = 2
    frame()
    hit(W.casca, g3, 10, g3.hp - 10)
    hit(W.casca, g1, 10, g1.hp - 10)
    frame(0.2)
    eq(kinds_of(built[#built]), "1101 Goblin ×3, 1202 Ogre ×1", "the goblin out of sight counts, those in sight once")
    eq(plate_text(), "Goblin ×3 no data / Ogre no data", "drawn")
    -- one killed: no longer counted, though its bar is still drawn
    hit(W.casca, g1, g1.hp, 0)
    frame(0.2)
    eq(kinds_of(built[#built]), "1101 Goblin ×2, 1202 Ogre ×1", "the killed one is gone")
    -- the goblins out of sight or dead: the ogre alone; one back, the goblins keep their first place
    b1.drawn, b2.drawn = false, false
    hit(W.casca, g3, g3.hp, 0)
    frame(0.2)
    eq(plate_text(), "Ogre no data", "the ogre alone")
    b2.drawn = true
    frame(0.2)
    eq(plate_text(), "Goblin no data / Ogre no data", "the goblins back in their first place")
    eq(built[#built].boss_id, nil, "no boss")
    eq(M.info().errors, 0, "no error caught")
end)

test("the plate counts a returning enemy's new object as the enemy it continues, once", function()
    world()
    bars_scene()
    local M = load()
    local built = watch_builds(M)
    frame()
    demon_fight()
    local d2 = demon(22612)
    gauge(d2)
    frame_at(115.5)
    eq(kinds_of(built[#built]), "7 Lesser demon ×1", "its bar, before the fight")
    hit(W.player, d2, 1000, 21612)
    frame_at(115.7)
    eq(M.state.fight:snapshot(M.state.t).t0, 50, "the demon's fight goes on")
    eq(kinds_of(built[#built]), "7 Lesser demon ×1", "its bar and the fight's living enemy are one demon")
    eq(M.info().errors, 0, "no error caught")
end)

test("the boss bar's boss heads the plate, left of its bar; its kind is always listed", function()
    world()
    bars_scene()
    local M = load()
    local built = watch_builds(M)
    local griffin = foe("ch250000_00", "Griffin", 1303, { hp = 40000, max_hp = 90000 })
    local b = boss_bar(griffin)
    gauge(foe("ch220003_00_20", "Goblin", 1101))
    frame()
    local last = built[#built]
    eq(last.boss_id, 1303, "the boss bar's boss")
    eq(kinds_of(last), "1303 Griffin ×1, 1101 Goblin ×1", "first, the others after it")
    eq(plate_text(), "Griffin no data / Goblin no data", "its row first, then the goblin's")
    local box = plate_box()
    local left = mod("ui/enemy_bars").boss_left({ x = b.x, y = b.y + 3.5, width = 776 }, 1920, 1080)
    eq(box.x1 <= left - mod("ui/enemy_plate").GAP, true, "left of the boss bar: " .. box.x1 .. " < " .. left)
    -- the boss in the fight and in sight: counted once
    W.mode = 2
    frame()
    hit(W.casca, griffin, 100, griffin.hp - 100)
    frame(0.2)
    eq(kinds_of(built[#built]), "1303 Griffin ×1, 1101 Goblin ×1", "the boss once")
    -- the bar gone: still the boss for HOLD (1 s), then a living enemy of the fight without a boss bar
    b.drawn = false
    frame(0.2)
    eq(built[#built].boss_id, 1303, "the bar gone 0.2 s: still the boss")
    frame(1)
    eq(built[#built].boss_id, nil, "gone 1.2 s: no boss bar, no boss")
    eq(kinds_of(built[#built]), "1303 Griffin ×1, 1101 Goblin ×1", "in the order the kinds were first seen")
    eq(M.info().errors, 0, "no error caught")
end)

test("the boss's block holds HOLD (1 s) after its bar went, with its cached table; then crowd lines", function()
    world()
    bars_scene()
    local M = load()
    local built = watch_builds(M)
    local ET, E = mod("game/enemy_table"), mod("game/enemies")
    -- the griffin's table, read from it in sight, the last one taken out of sight
    local GRIFFIN = { chara_id = 1303, state = "Normal", body = { Fire = 1.5 }, parts = {} }
    local read, cache, data = ET.read, ET.cached, E.data
    local seen = {}
    ET.read = function(c, id, t)
        if id ~= 1303 then return read(c, id, t) end
        seen[#seen + 1] = "read"
        return GRIFFIN
    end
    ET.cached = function(id)
        if id ~= 1303 then return cache(id) end
        seen[#seen + 1] = "cached"
        return GRIFFIN
    end
    E.data = function(c, actor)
        if actor and actor.chara_id == 1303 then seen[#seen + 1] = c == nil and "data:none" or "data:character" end
        return data(c, actor)
    end
    local griffin = foe("ch250000_00", "Griffin", 1303, { hp = 40000, max_hp = 90000 })
    local b = boss_bar(griffin)
    gauge(foe("ch220003_00_20", "Goblin", 1101))
    W.mode = 2
    frame()
    hit(W.casca, griffin, 100, griffin.hp - 100)
    frame(0.2)
    eq(built[#built].boss_id, 1303, "the boss")
    local BLOCK = "Slash Blunt Rngd Fire Ice Thndr Holy Mag / Griffin ? ? ? 1.5 ? ? ? ? / Goblin no data"
    eq(plate_text(), BLOCK, "its row first (the columns its table has no number of «?»), then the goblin's")
    -- the bar off for one build, then back
    b.drawn = false
    seen = {}
    frame(0.2)
    local last = built[#built]
    eq(last.boss_id, 1303, "the bar gone: still the boss")
    eq(kinds_of(last), "1303 Griffin ×1, 1101 Goblin ×1", "first, once")
    eq(table.concat(seen, " "), "cached data:none", "its last table and its data, without a character")
    eq(plate_text(), BLOCK, "the block kept")
    b.drawn = true
    frame(0.2)
    eq(built[#built].boss_id, 1303, "the bar back: the boss"); eq(plate_text(), BLOCK, "the block")
    -- gone for longer than HOLD: crowd lines (the griffin a living enemy of the fight)
    b.drawn = false
    frame(0.5)
    frame(0.4)
    eq(built[#built].boss_id, 1303, "0.9 s: still the boss"); eq(plate_text(), BLOCK, "the block")
    frame(0.2)
    eq(built[#built].boss_id, nil, "1.1 s: no boss")
    eq(plate_text(), BLOCK, "the same rows, the griffin a living enemy of the fight")
    local box = plate_box()
    near((box.x0 + box.x1) / 2, 960, 1, "centred: no boss bar to stand by")
    -- a boss killed while held is left out
    b.drawn = true
    frame(0.2)
    eq(built[#built].boss_id, 1303, "the bar back")
    b.drawn = false
    hit(W.casca, griffin, griffin.hp, 0)
    frame(0.2)
    eq(built[#built].boss_id, nil, "killed: no boss"); eq(kinds_of(built[#built]), "1101 Goblin ×1", "nor listed")
    eq(M.info().errors, 0, "no error caught")
end)

test("the plate tries a kind's enemy data with a character at most once a second; without one it spends no try",
    function()
    world()
    bars_scene()
    local M = load()
    local E, actors = mod("game/enemies"), mod("game/actors")
    local data, asked = E.data, {}
    E.data = function(c, actor)
        asked[#asked + 1] = c ~= nil and "c" or "-"
        return data(c, actor)
    end
    -- no DamageCalculator yet: each try from the goblin fails and spends one of its kind's 3
    local goblin = foe("ch220003_00_20", "Goblin", 1101)
    gauge(goblin)
    frame()
    for _ = 1, 3 do frame(0.3) end
    eq(table.concat(asked), "c---", "four builds in 0.9 s: one try with the character, the others without")
    -- readable now: the next try, a second after the first, finds it (the budget not spent)
    local calc = R.object(EDC, {}, {
        get_WeakPointSettings = function() return 64 end,
        get_ResistSettings = function() return 16 end,
    })
    goblin.methods.get_DamageCalculator = function() return calc end
    frame(0.3)
    eq(table.concat(asked), "c---c", "1.2 s after the first: tried again")
    local record = data(nil, actors.of(goblin))
    eq(record ~= nil and record.weak, 64, "the kind's record read")
    eq(M.info().errors, 0, "no error caught")
end)

test("only enemies make rows: a critter under a hostile bar (a chicken) gets none", function()
    world()
    bars_scene()
    local M = load()
    local built = watch_builds(M)
    local chicken = foe("ch280000_00_01", "Chicken", 1999, { hp = 1, max_hp = 1 })
    eq(mod("game/actors").of(chicken).kind, "other", "a critter is no enemy")
    local bar = gauge(chicken)
    gauge(foe("ch220003_00_20", "Goblin", 1101))
    frame()
    eq(kinds_of(built[#built]), "1101 Goblin ×1", "the goblin only")
    eq(plate_text(), "Goblin no data", "drawn")
    -- the chicken's bar alone: no kind, no plate
    W.guis = { bar.gui }
    frame(1.2)
    eq(plate_text(), "Goblin no data", "the last plate kept a while")
    frame(3)
    eq(plate_text(), "", "then none: the chicken never listed")
    eq(M.info().errors, 0, "no error caught")
end)

test("a fight enemy with no bar now uses EnemyTable.cached; one in sight is read; each kind's statuses", function()
    world()
    bars_scene()
    local M = load()
    local ET, E = mod("game/enemy_table"), mod("game/enemies")
    local reads, cached, asked = {}, {}, {}
    local read, cache, data = ET.read, ET.cached, E.data
    ET.read = function(c, id, t)
        reads[#reads + 1] = { c = c, id = id, t = t }
        return read(c, id, t)
    end
    ET.cached = function(id)
        cached[#cached + 1] = id
        if id ~= 1202 then return cache(id) end
        return { chara_id = 1202, state = "Normal", body = { Fire = 1.5, Ice = 0.5 }, parts = {} }
    end
    -- the ogre: every status but sleep works on it
    local mask = 0
    for _, st in ipairs(mod("journal").STATUSES) do
        if st.name ~= "Sleep" then mask = mask | st.bit end
    end
    E.data = function(c, actor)
        asked[#asked + 1] = { c = c, id = actor and actor.chara_id }
        if actor and actor.chara_id == 1202 then return { chara_id = 1202, weak = 0, resist = 0, enabled = mask } end
        return data(c, actor)
    end
    local goblin, ogre = foe("ch220003_00_20", "Goblin", 1101), foe("ch221004_00_01", "Ogre", 1202)
    gauge(goblin)
    W.mode = 2
    frame()
    hit(W.casca, ogre, 10, ogre.hp - 10) -- the ogre in the fight, out of sight
    reads, cached, asked = {}, {}, {}
    frame(1.2) -- a second after the first build: the goblin's data tried with its character again
    eq(#reads, 1, "one kind read"); eq(reads[1].c, goblin, "the goblin, from its character in sight")
    eq(reads[1].id, 1101, "by its kind"); eq(reads[1].t, W.t, "at the frame's time")
    eq(T.str(cached), "1202", "the ogre out of sight: its last table")
    local who = {}
    for _, a in ipairs(asked) do
        who[#who + 1] = a.id .. (a.c == goblin and ":goblin" or a.c == nil and ":none" or ":?")
    end
    eq(table.concat(who, " "), "1101:goblin 1202:none", "the enemy data with the character in sight, else without")
    eq(plate_text(), "Slash Blunt Rngd Fire Ice Thndr Holy Mag / Goblin no data / Ogre ? ? ? 1.5 0.5 ? ? ? / Ogre: immune to Sleep",
        "the ogre's table and statuses; the goblin has none")
    eq(M.info().errors, 0, "no error caught")
end)

test("nothing is read for the plate while paused, with the journal open, or with the setting off", function()
    -- the buildup bars and the player's numbers off: they read the game's bars for themselves
    world({ settings = { enemy_hp_numbers = "off", boss_hp_numbers = "off", buildup_bars = false,
        player_numbers = false } })
    bars_scene()
    pause_manager()
    local M = load()
    local goblin = foe("ch220003_00_20", "Goblin", 1101)
    local griffin = foe("ch250000_00", "Griffin", 1303, { hp = 40000, max_hp = 90000 })
    gauge(goblin)
    boss_bar(griffin)
    -- the plate's own reads: its modules' and the game calls on the characters it shows
    local n = 0
    for _, f in ipairs({ { "game/enemy_table", "read" }, { "game/enemy_table", "cached" }, { "game/weapon", "read" },
                         { "game/enemies", "data" } }) do
        local m = mod(f[1])
        local fn = m[f[2]]
        m[f[2]] = function(...)
            n = n + 1
            return fn(...)
        end
    end
    local function reads() return n + bar_reads() end
    W.mode = 2
    frame()
    eq(plate_text(), "Griffin no data / Goblin no data", "on: shown")
    eq(n > 0 and bar_reads() > 0, true, "and read")
    local function none(what)
        local before, on_them = reads(), calls_on({ goblin, griffin, goblin.go, griffin.go, griffin.hc })
        for _ = 1, 5 do frame(0.5) end
        eq(reads(), before, what .. ": nothing read")
        eq(on_them(), 0, what .. ": nothing of its enemies")
        eq(plate_text(), "", what .. ": nothing drawn")
    end
    -- paused in a menu
    W.paused = true
    none("paused")
    W.paused = false
    frame()
    eq(plate_text(), "Griffin no data / Goblin no data", "the pause over: back")
    -- the journal open
    press(F7)
    eq(M.info().journal, true, "the journal is open")
    none("the journal open")
    press(F7)
    eq(plate_text(), "Griffin no data / Goblin no data", "closed: back")
    -- switched off: the bars found are forgotten
    window_set("enemy_plate", false)
    eq(mod("game/gauges").count(), 0, "the bars found forgotten")
    press(F8)
    ui.drawing_ui = false
    none("off")
    -- on again: read and drawn at once
    window_set("enemy_plate", true)
    press(F8)
    ui.drawing_ui = false
    eq(plate_text(), "Griffin no data / Goblin no data", "on again: drawn")
    eq(M.info().errors, 0, "no error caught")
end)

test("the plate shows while a fight is open or a hostile bar is drawn, and for LINGER (3 s) after neither, then not",
    function()
    world()
    bars_scene()
    local M = load()
    local goblin = foe("ch220003_00_20", "Goblin", 1101)
    local bar = gauge(goblin)
    frame()
    eq(M.state.fight, nil, "no fight")
    eq(plate_text(), "Goblin no data", "a hostile bar drawn: shown")
    bar.drawn = false
    frame(1)
    eq(plate_text(), "Goblin no data", "the bar gone: still there")
    frame(1.9)
    eq(plate_text(), "Goblin no data", "2.9 s after")
    frame(0.2)
    eq(plate_text(), "", "3 s after: gone")
    frame(5)
    eq(plate_text(), "", "and stays gone")
    -- a fight, the goblin out of sight: shown; gone 3 s after the fight
    W.mode = 2
    frame()
    hit(W.casca, goblin, 10, goblin.hp - 10)
    frame(0.2)
    eq(plate_text(), "Goblin no data", "a fight: its living enemy")
    W.mode = 0
    for _ = 1, 100 do
        if M.state.fight == nil then break end
        frame(0.1)
    end
    eq(M.state.fight, nil, "the fight is over")
    eq(plate_text(), "Goblin no data", "still there")
    frame(2.8)
    eq(plate_text(), "Goblin no data", "2.9 s after the fight")
    frame(0.2)
    eq(plate_text(), "", "3 s after: gone")
    -- a fight whose last enemy is killed: its plate for 3 s more, then none, the fight going on
    W.mode = 2
    frame()
    hit(W.casca, goblin, 10, goblin.hp - 10)
    frame(0.2)
    eq(plate_text(), "Goblin no data", "a new fight")
    hit(W.casca, goblin, goblin.hp, 0)
    frame(0.2)
    eq(plate_text(), "Goblin no data", "its last enemy killed: the plate stays")
    frame(2.7)
    eq(plate_text(), "Goblin no data", "2.9 s after it last listed one")
    frame(0.2)
    eq(plate_text(), "", "3 s after: gone")
    eq(M.state.fight ~= nil, true, "the fight goes on")
    eq(M.info().errors, 0, "no error caught")
end)

test("gauges.shown is looked at for the plate even with enemy_hp_numbers off, the boss bar with boss_hp_numbers off",
    function()
    world({ settings = { enemy_hp_numbers = "off", boss_hp_numbers = "off" } })
    bars_scene()
    local M = load()
    gauge(foe("ch220003_00_20", "Goblin", 1101))
    frame()
    eq(plate_text(), "Goblin no data", "the plate")
    eq(numbers(), "", "no HP numbers")
    eq(bar_reads() > 0, true, "the bars read for it")
    boss_bar(foe("ch250000_00", "Griffin", 1303, { hp = 40000, max_hp = 90000 }))
    frame(1)
    eq(plate_text(), "Griffin no data / Goblin no data", "the boss bar's boss too")
    eq(numbers(), "", "still no HP numbers")
    -- the HP numbers on as well: the bars and the boss bar read once a frame for both
    M.state.settings:set("enemy_hp_numbers", "all")
    M.state.settings:set("boss_hp_numbers", "all")
    frame()
    local draws, bosses = #R.calls_of("get_GlobalPosition"), #R.calls_of("get_Size")
    frame()
    eq(#R.calls_of("get_GlobalPosition") - draws, 2, "the overhead bar's and the boss bar's position once each")
    eq(#R.calls_of("get_Size") - bosses, 1, "the boss bar's size once")
    eq(numbers(), "3 000 / 3 000 · 100%|40 000 / 90 000 · 44%", "and their HP numbers")
    eq(plate_text(), "Griffin no data / Goblin no data", "with the plate")
    eq(M.info().errors, 0, "no error caught")
end)

test("the plate lies over the HP numbers, under the damage numbers and the windows; its size from the settings",
    function()
    numbers_world()
    bars_scene()
    local M = load()
    local goblin = foe("ch220003_00_20", "Goblin", 1101)
    gauge(goblin)
    W.mode = 2
    frame()
    eq(plate_px(), 14, "14 px at scale 1 and 100 %")
    window_click("dd2dm_snext:enemy_plate_size")
    eq(M.state.settings.values.enemy_plate_size, 1.1, "100 % -> 110 %")
    hit(W.casca, goblin, 10, goblin.hp - 10, at(800, 500))
    frame()
    near(plate_px(), 14 * 1.1, 1e-9, "14 px × 1.1")
    local kit = mod("ui/kit")
    local back, beige, panel = mod("ui/enemy_plate").COLORS.back, mod("ui/enemy_bars").COLORS.text, kit.COLORS.panel
    local casca = kit.actor_color("pawn", 5, 1)
    local hp_at, plate_at, number_at, panel_at
    for i, c in ipairs(ui.calls) do
        if c.layer == "background" then
            if c.fn == "add_text" and c.col == beige then hp_at = hp_at or i end
            if c.fn == "add_rect_filled" and c.col == back then plate_at = plate_at or i end
            if c.fn == "add_text" and c.col & 0xFFFFFF == casca & 0xFFFFFF then number_at = number_at or i end
            if c.fn == "add_rect_filled" and c.col == panel then panel_at = panel_at or i end
        end
    end
    eq(hp_at ~= nil and plate_at ~= nil and number_at ~= nil and panel_at ~= nil, true, "all four drawn")
    eq(hp_at < plate_at, true, "over the HP numbers")
    eq(plate_at < number_at, true, "under the damage numbers")
    eq(number_at < panel_at, true, "under the settings window's panel")
    eq(M.info().errors, 0, "no error caught")
    eq(#M.info().enemy_plate_missing, 0, "no imgui call missing")
end)

test("a new world resets EnemyTable, Weapon, Buildup and the model", function()
    world()
    bars_scene()
    local M = load()
    local resets = {}
    for _, name in ipairs({ "game/enemy_table", "game/weapon", "ui/enemy_plate", "game/buildup" }) do
        local m = mod(name)
        local reset = m.reset
        m.reset = function(...)
            resets[name] = (resets[name] or 0) + 1
            return reset(...)
        end
    end
    local goblin = foe("ch220003_00_20", "Goblin", 1101)
    gauge(goblin)
    W.mode = 2
    frame()
    hit(W.player, goblin, 100, goblin.hp - 100, nil, { SlashDamage = 100 })
    frame(0.2)
    eq(#M.state.plate.hits, 1, "a hit in the model")
    eq(plate_text(), "Goblin no data / you: Slash", "and on the plate")
    R.method("app.CharacterManager", "get_ManualPlayer", function() return nil end)
    scene_change()
    eq(resets["game/enemy_table"], 1, "EnemyTable reset")
    eq(resets["game/weapon"], 1, "Weapon reset")
    eq(resets["ui/enemy_plate"], 1, "the plate's drawing reset")
    eq(resets["game/buildup"], 1, "the buildup's rises forgotten")
    eq(#M.state.plate.hits, 0, "the model's hits forgotten")
    eq(next(M.state.plate_view.order), nil, "and the order of its kinds")
    eq(M.info().errors, 0, "no error caught")
end)

test("with debug on, the plate's cost is in the debug log at each fight's end", function()
    world({ settings = { debug = true } })
    bars_scene()
    local M = load()
    local goblin = foe("ch220003_00_20", "Goblin", 1101)
    gauge(goblin)
    frame()
    W.mode = 2
    frame()
    hit(W.casca, goblin, 10, goblin.hp - 10)
    for _ = 1, 5 do frame(0.05) end
    end_battle()
    local log = R.files[LOG_FILE] or ""
    eq(lines_with(log, "plate frames="), 1, "one line, after the fight's")
    local frames, builds, avg, max = log:match("plate frames=(%d+) builds=(%d+) avg=([%d.]+)ms max=([%d.]+)ms")
    -- the fight ends in the game step of the last frame, before that frame's plate
    eq(tonumber(frames), 8, "the frames it was shown before the fight's end")
    eq(tonumber(builds) >= 3 and tonumber(builds) < 9, true, "a build every 0.1 s at most: " .. tostring(builds))
    eq(tonumber(avg) <= tonumber(max), true, "the average and the largest, in ms")
    -- the next fight's line counts its own frames: the last one of the fight before, its two
    fight(strike)
    eq(tonumber(R.files[LOG_FILE]:match(".*plate frames=(%d+)")), 3, "counted afresh")
    eq(lines_with(R.files[LOG_FILE], "plate frames="), 2, "a line per fight")
    -- off: not measured
    M.state.settings:set("debug", false)
    local measured = M.state.plate_cost.frames
    for _ = 1, 5 do frame() end
    eq(M.state.plate_cost.frames, measured, "debug off: no frame measured")
    eq(M.info().errors, 0, "no error caught")
end)

-- The debug collector: collect.jsonl ----------------------------------------------------------------------------

local COLLECT_FILE = "DD2DamageMeter/collect.jsonl"
local COLLECT_MAX = 200 * 1024 * 1024
local PYS = "getDamageAdjustRatePys(app.AttackUserData.AttrPhysicsEnum)"
local MGC = "getDamageAdjustRateMgc(app.AttackUserData.ElementType)"

-- The records of collect.jsonl, decoded; of `kind` only when given (a line that is no JSON is left out).
local function collected(kind)
    local out = {}
    for line in (R.files[COLLECT_FILE] or ""):gmatch("[^\n]+") do
        local ok, r = pcall(json_decode, line)
        if ok and type(r) == "table" and (kind == nil or r.kind == kind) then out[#out + 1] = r end
    end
    return out
end

-- `c`'s damage calculator with its enemy data and a table of two states, Normal (a Body r0, a Head r1) and Down (a
-- Body r2); its state in use is the returned table's `prio` (Normal).
local function region_table(c)
    local function part(no, kind, v)
        return R.object("app.IntermediateRegionParam", { _RegionNo = no, _RegionType = kind, _Attr = 0 }, {
            get_RegionNo = function() return no end,
            get_RegionType = function() return kind end,
            [PYS] = function() return v end,
            [MGC] = function() return v end,
        })
    end
    local o = { prio = "Normal", states = { { id = "Normal", parts = { part(0, 1, 0.8), part(1, 0, 1.5) } },
        { id = "Down", parts = { part(2, 1, 1.2) } } } }
    local states = {}
    for i, s in ipairs(o.states) do
        local list = R.list(s.parts, "System.Collections.Generic.List`1<app.IntermediateRegionParam>")
        states[i] = R.object("app.IntermediateRegionStatusParam", {}, {
            get_StatusId = function() return s.id end,
            get_IntermediateRegionParams = function() return list end,
        })
    end
    local list = R.list(states, "System.Collections.Generic.List`1<app.IntermediateRegionStatusParam>")
    local data = R.object("app.IntermediateRegionStatusData", {}, {
        get_IntermediateRegionStatusParams = function() return list end,
    })
    local rsc = R.object("app.RegionStatusCtrl", {}, {
        get_PrioStatusId = function() return o.prio end,
        get_RegionStatusDataProp = function() return data end,
        ["getActiveRegionParam(System.Int32)"] = function(_, no)
            for _, s in ipairs(o.states) do
                if s.id == o.prio then
                    for _, p in ipairs(s.parts) do
                        if p.fields._RegionNo == no then return p end
                    end
                end
            end
            return nil
        end,
    })
    local calc = R.object(EDC, {}, {
        get_RegionStatusCtrl = function() return rsc end,
        get_WeakPointSettings = function() return 64 end,
        get_ResistSettings = function() return 16 end,
    })
    c.methods.get_DamageCalculator = function() return calc end
    return o
end

-- The player holds a weapon (a GameObject named `id`) in his right hand; NowElementType of that hand is o.now.
local function armed(id, o)
    o = o or { now = -1 }
    local go = R.object("via.GameObject", {}, { get_Name = function() return id end })
    local weapon = R.object("app.Weapon", { IsBlunt = false, ElementType = -1, Job = 1 },
        { get_GameObject = function() return go end })
    W.player.methods.get_RightWeapon = function() return weapon end
    W.player.methods.get_WeaponElementController = function()
        local arr = R.object("app.WeaponElementControllerBase.WeaponElementInfo[]", {}, {})
        arr.items = { R.object("app.WeaponElementControllerBase.WeaponElementInfo",
            { ["<WeaponType>k__BackingField"] = 1, NowElementType = o.now }, {}) }
        return R.object("app.WeaponElementController", { WeaponElementInfos = arr }, {})
    end
    return o
end

-- A hit with no attacker on `victim` whose DamageInfo has this DamageType and Flag (a slam: Falls and environment).
local function slam(victim, final, damage_type, flag)
    local di = R.object(DI, { ["<DamageHitController>k__BackingField"] = victim.hc, DamageType = damage_type,
        Flag = flag }, {})
    R.enter(hook(HC, "damageProc"), { R.CTX, slot(victim.hc), slot(di) })
    R.enter(hook(HC, "updateDamage"), { R.CTX, slot(victim.hc), slot(di), R.int_slot(0xFFFFFFFF), R.f32_slot(final),
        R.int_slot(0) })
    victim.hp = victim.hp - final
    R.leave(nil)
    return R.leave(true)
end

-- The player's blow on `victim` through the enemy's defence step, its DamageRate 1 -> `to`.
local function bonus_hit(victim, to)
    hit(W.player, victim, 100, victim.hp - 100, { DamageRate = 1 }, { DamageRate = to, SlashDamage = 100 })
end

local function counts()
    local n = {}
    for _, r in ipairs(collected()) do n[r.kind] = (n[r.kind] or 0) + 1 end
    return string.format("enemy=%d weapon=%d enchant=%d bonus=%d sourceless=%d party_join=%d", n.enemy or 0,
        n.weapon or 0, n.enchant or 0, n.bonus or 0, n.sourceless or 0, n.party_join or 0)
end

test("collect.jsonl: with debug on, what the plate and the hits meet, each once; with debug off or paused nothing",
    function()
    world({ settings = { debug = true } })
    bars_scene()
    pause_manager()
    local M = load()
    local ogre = foe("ch221004_00_01", "Ogre", 1202)
    local ogre_table = region_table(ogre)
    gauge(ogre)
    local hand = armed("wp01_000_00")
    frame()
    eq(counts(), "enemy=1 weapon=1 enchant=1 bonus=0 sourceless=0 party_join=0", "the ogre in sight, the sword")
    local r = collected("enemy")[1]
    eq(r.name, "Ogre", "the ogre"); eq(r.chara_id, 1202, "its kind"); eq(r.state, "Normal", "its state")
    eq(#r.states, 2, "both states"); eq(r.has_body, true, "a Body part"); eq(r.table.body.Slash, 0.8, "the body")
    eq(r.data.weak, 64, "its enemy data")
    eq(collected("weapon")[1].id, "wp01_000_00", "the sword"); eq(collected("weapon")[1].answer.phys, "Slash", "slash")
    for _ = 1, 5 do frame(0.3) end
    eq(counts(), "enemy=1 weapon=1 enchant=1 bonus=0 sourceless=0 party_join=0", "seen: nothing more")
    -- the ogre downed: its new state; an enchant
    ogre_table.prio = "Down"
    hand.now = 3
    frame(1)
    eq(counts(), "enemy=2 weapon=1 enchant=2 bonus=0 sourceless=0 party_join=0", "Down and the enchant")
    eq(collected("enemy")[2].state, "Down", "the state Down"); eq(collected("enchant")[2].value, 3, "Thunder")
    -- the hit path: a goblin out of sight, a blow with a bonus, a slam; each once
    local goblin = foe("ch220003_00_20", "Goblin", 1101)
    region_table(goblin)
    W.mode = 2
    frame()
    bonus_hit(goblin, 3)
    bonus_hit(goblin, 3)
    frame(3.1)                          -- the slams over 3 s after his blows: «Падения и среда»
    slam(goblin, 300, 14, 10753)
    slam(goblin, 300, 14, 10753)
    eq(counts(), "enemy=3 weapon=1 enchant=2 bonus=1 sourceless=1 party_join=0", "each once")
    local b = collected("bonus")[1]
    eq(b.attack, "弱攻撃", "the attack"); eq(b.bonus, 2, "the bonus"); eq(b.rate_before, 1, "the rate before")
    eq(b.victim, "Goblin", "on the goblin"); eq(b.chara_id, 1101, "its kind")
    eq(b.attacker_kind, "player", "the player's")
    local s = collected("sourceless")[1]
    eq(s.damage_type, 14, "DamageType"); eq(s.flag, 10753, "Flag"); eq(s.own, "self", "its own")
    eq(s.damage, 300, "its damage")
    eq(collected("enemy")[3].name, "Goblin", "the goblin met by the hit")
    -- Casca made anew by the game, joined at the next party read
    local old = W.casca
    W.casca = char("ch100000_00", { name = "Casca", chara_id = old.chara_id, hp = 1500, max_hp = 1800 })
    W.pawns = { W.casca }
    frame(1)
    eq(counts(), "enemy=3 weapon=1 enchant=2 bonus=1 sourceless=1 party_join=1", "her join")
    local j = collected("party_join")[1]
    eq(j.name, "Casca", "Casca"); eq(j.old, string.format("0x%X", old.addr), "her old address")
    eq(j.new, string.format("0x%X", W.casca.addr), "the new one")
    -- debug off: nothing
    M.state.settings:set("debug", false)
    local file = R.files[COLLECT_FILE]
    local imp = foe("ch222000_00_01", "Imp", 1303)
    region_table(imp)
    gauge(imp)
    armed("wp02_000_00")
    frame(1)
    bonus_hit(imp, 2)
    slam(imp, 10, 8, 1)
    eq(R.files[COLLECT_FILE], file, "debug off: nothing written")
    -- paused: nothing either, and no game read for it
    M.state.settings:set("debug", true)
    W.paused = true
    frame()
    frame(1)
    bonus_hit(imp, 2)
    slam(imp, 10, 8, 1)
    eq(R.files[COLLECT_FILE], file, "paused: nothing written")
    -- the pause over: the imp, the bow and the next blow and slam
    W.paused = false
    frame()
    bonus_hit(imp, 2)
    frame(3.1)
    slam(imp, 10, 8, 1)
    eq(counts(), "enemy=4 weapon=2 enchant=3 bonus=2 sourceless=2 party_join=1", "all of it now")
    eq(M.info().errors, 0, "no error caught")
end)

test("collect.jsonl: a slam within 3 s of a friend's hit is a knock record, once per attack and kind, no sourceless one",
        function()
    world({ settings = { debug = true } })
    local M = load()
    local goblin = foe("ch220003_00_20", "Goblin", 1101)
    region_table(goblin)
    W.mode = 2
    frame()
    hit(W.casca, goblin, 100, goblin.hp - 100)
    frame(1)
    slam(goblin, 300, 14, 10753)
    slam(goblin, 200, 14, 10753)
    eq(#collected("knock"), 1, "once per (attack, kind)"); eq(#collected("sourceless"), 0, "no sourceless record")
    local k = collected("knock")[1]
    eq(k.attack, "弱攻撃", "the knocking attack"); eq(k.attacker_kind, "pawn", "a pawn's"); eq(k.attacker, "Casca", "hers")
    near(k.gap, 1, 1e-6, "a second after her blow")
    eq(k.damage, 300, "its damage"); eq(k.removed, 300, "the HP it took")
    eq(k.damage_type, 14, "its DamageType"); eq(k.flag, 10753, "its Flag")
    eq(k.victim, "Goblin", "on the goblin"); eq(k.chara_id, 1101, "its kind")
    frame(3.1)
    slam(goblin, 100, 14, 10753)
    eq(#collected("sourceless"), 1, "over 3 s later: a sourceless one"); eq(#collected("knock"), 1, "no knock")
    eq(M.info().errors, 0, "no error caught")
end)

test("collect.jsonl is kept across game sessions and stops at 200 MB with one debug line", function()
    world({ settings = { debug = true } })
    R.files[COLLECT_FILE] = '{"t":"2026-11-03T20:00:00","kind":"bonus","attack":"earlier"}\n'
    local earlier = R.files[COLLECT_FILE]
    local M = load()
    frame()
    W.mode = 2
    frame()
    bonus_hit(W.goblin, 1.5)
    local file = R.files[COLLECT_FILE]
    eq(file:sub(1, #earlier), earlier, "the earlier session's records kept")
    eq(#collected("bonus"), 2, "this one appended"); eq(M.state.collect_bytes, #file, "its size counted from the file")
    local at_start = string.format("collect.jsonl: %d bytes at start", #earlier)
    eq(lines_with(R.files[LOG_FILE], at_start), 1, "debug.log: its size at the session's first record")
    bonus_hit(W.goblin, 1.8)
    eq(#collected("bonus"), 3, "the next one"); eq(lines_with(R.files[LOG_FILE], "bytes at start"), 1, "said once")
    file = R.files[COLLECT_FILE]
    -- a record that would take it past 200 MB is not written, nor any after it; debug.log says so once
    M.state.collect_bytes = COLLECT_MAX - 50
    bonus_hit(W.goblin, 2)
    bonus_hit(W.goblin, 3)
    slam(W.goblin, 10, 14, 1)
    eq(R.files[COLLECT_FILE], file, "nothing more written")
    eq(lines_with(R.files[LOG_FILE], "collect.jsonl reached 200 MB"), 1, "one debug line")
    eq(M.state.collect_bytes <= COLLECT_MAX, true, "never past 200 MB")
    -- a reload is the same session: still full
    load()
    frame()
    bonus_hit(W.goblin, 4)
    eq(R.files[COLLECT_FILE], file, "full after a reload too")
    eq(lines_with(R.files[LOG_FILE], "200 MB"), 1, "and said once")
    -- a new session whose file is full already: its first record is not written and says so
    world({ settings = { debug = true } })
    R.files[COLLECT_FILE] = "x\n"
    local open = io.open
    io.open = function(path, mode)
        local f = open(path, mode)
        if f and path == COLLECT_FILE then f.seek = function() return COLLECT_MAX - 5 end end
        return f
    end
    M = load()
    frame()
    W.mode = 2
    frame()
    bonus_hit(W.goblin, 1.5)
    io.open = open
    eq(R.files[COLLECT_FILE], "x\n", "nothing written to a full file")
    eq(lines_with(R.files[LOG_FILE], "collect.jsonl reached 200 MB"), 1, "the debug line")
    eq(lines_with(R.files[LOG_FILE], string.format("collect.jsonl: %d bytes at start", COLLECT_MAX - 5)), 1,
        "after the size the file had")
    eq(M.info().errors, 0, "no error caught")
end)

test("with debug and the damage numbers off a hit reads no DamageRate; with debug on it does, for its bonus record",
    function()
    world({ settings = { damage_numbers = false } })
    local M = load()
    frame()
    W.mode = 2
    frame()
    -- the DamageInfo's DamageRate (1 before the step) and its hit point, their reads counted
    local reads = { DamageRate = 0, ["<Position>k__BackingField"] = 0 }
    local function rate()
        return setmetatable({}, { __index = function(_, k)
            if reads[k] then reads[k] = reads[k] + 1 end
            if k == "DamageRate" then return 1 end
        end })
    end
    hit(W.player, W.goblin, 100, W.goblin.hp - 100, rate(), { SlashDamage = 100, DamageRate = 1.5 })
    eq(reads.DamageRate, 0, "debug and the numbers off: no DamageRate read")
    eq(R.files[COLLECT_FILE], nil, "no collect.jsonl")
    M.state.settings:set("debug", true)
    hit(W.player, W.goblin, 100, W.goblin.hp - 100, rate(), { SlashDamage = 100, DamageRate = 1.5 })
    eq(reads.DamageRate, 1, "debug on: read before the step (after it, the step's own value)")
    eq(collected("bonus")[1].bonus, 0.5, "the bonus written")
    eq(reads["<Position>k__BackingField"], 0, "the numbers off: no hit point read")
    eq(M.info().errors, 0, "no error caught")
end)

-- The hit path's read must not fill the plate's table cache.
test("with debug on, a kind hit but never in sight shows on the plate as with debug off", function()
    local function plate_of(debug)
        world({ settings = { debug = debug } })
        bars_scene()
        local M = load()
        local built = watch_builds(M)
        local goblin = foe("ch220003_00_20", "Goblin", 1101)
        region_table(goblin)
        W.mode = 2
        frame()
        hit(W.casca, goblin, 10, goblin.hp - 10)
        frame(0.2)
        local kind = built[#built] and built[#built].kinds[1]
        eq(kind ~= nil and kind.chara_id, 1101, "the goblin listed")
        eq(M.info().errors, 0, "no error caught")
        return plate_text(), kind.table
    end
    local off_text, off_table = plate_of(false)
    local on_text, on_table = plate_of(true)
    eq(#collected("enemy"), 1, "debug on: the collector read the goblin")
    eq(off_table, nil, "debug off: no table for a kind never in sight")
    eq(on_table, nil, "debug on: none either")
    eq(on_text, off_text, "the same plate: " .. off_text)
end)

-- The plate's cost line is the plate's alone; the collector's meets have their own.
test("with debug on, the collector's meets are timed apart from the plate, in a line of their own after each fight",
    function()
    world({ settings = { debug = true } })
    bars_scene()
    local M = load()
    local ogre = foe("ch221004_00_01", "Ogre", 1202)
    region_table(ogre)
    gauge(ogre)
    -- os.clock stands still but for each meet of the collector, which takes 5 ms
    local C = mod("game/collector")
    local meet, clock, now = C.enemy, os.clock, 0
    os.clock = function() return now end
    C.enemy = function(...)
        now = now + 0.005
        return meet(...)
    end
    frame()
    W.mode = 2
    frame()
    hit(W.casca, ogre, 10, ogre.hp - 10)
    for _ = 1, 5 do frame(0.05) end
    end_battle()
    os.clock, C.enemy = clock, meet
    local log = R.files[LOG_FILE] or ""
    eq(lines_with(log, "collect calls="), 1, "one collector line")
    local plate_max = log:match("plate frames=%d+ builds=%d+ avg=[%d.]+ms max=([%d.]+)ms")
    eq(tonumber(plate_max), 0, "the plate's time holds none of the collector's")
    local calls, avg, max = log:match("collect calls=(%d+) avg=([%d.]+)ms max=([%d.]+)ms")
    eq(tonumber(max), 5, "the collector's largest: one meet"); eq(tonumber(avg), 5, "each meet 5 ms")
    eq(tonumber(calls) >= 3, true, "the plate's meets and the hit's: " .. tostring(calls))
    local fight_at, plate_at = log:find("fight end", 1, true), log:find("plate frames=", 1, true)
    local collect_at = log:find("collect calls=", 1, true)
    eq(fight_at < plate_at and plate_at < collect_at, true, "after the fight's line, next to the plate's")
    -- the next fight counts afresh; with debug off nothing is timed
    fight(strike)
    eq(lines_with(R.files[LOG_FILE], "collect calls="), 2, "a line per fight")
    M.state.settings:set("debug", false)
    local calls_now = M.state.collect_cost.calls
    for _ = 1, 5 do frame(0.3) end
    hit(W.casca, ogre, 10, ogre.hp - 10)
    eq(M.state.collect_cost.calls, calls_now, "debug off: nothing timed")
    eq(M.info().errors, 0, "no error caught")
end)

test("the collector reads nothing in the frames between its looks once its keys are seen", function()
    -- the game calls of 20 frames 0.02 s apart, after the frame that met the ogre and the sword
    local function window(debug)
        world({ settings = { debug = debug } })
        bars_scene()
        local M = load()
        local ogre = foe("ch221004_00_01", "Ogre", 1202)
        region_table(ogre)
        gauge(ogre)
        armed("wp01_000_00")
        frame()
        frame()
        local from = #R.calls
        for _ = 1, 20 do frame(0.02) end
        local sigs = {}
        for i = from + 1, #R.calls do sigs[#sigs + 1] = R.calls[i].sig end
        return sigs, M
    end
    local off = window(false)
    local on, M = window(true)
    eq(#collected("enemy"), 1, "the ogre recorded"); eq(#collected("weapon"), 1, "the sword recorded")
    eq(#off > 0, true, "the plate reads the game in those frames: " .. #off .. " calls")
    eq(#on, #off, "as many game calls with debug on as off")
    eq(table.concat(on, ","), table.concat(off, ","), "the same calls")
    for _, sig in ipairs(on) do
        eq(sig ~= "get_PrioStatusId" and sig ~= "get_RightWeapon" and sig ~= "get_RegionStatusDataProp", true,
            "no look at the table or the weapon: " .. sig)
    end
    eq(M.info().errors, 0, "no error caught")
end)

-- The hidden-stats panel ---------------------------------------------------------------------------------------------

local PLAYER_ID, CASCA_ID, PAWN2_ID = 2891076981, 2283028347, 3459096238
-- The anchors game/hidden_screens.lua gives: the item screens', the guild's (above the header, growing up).
local ITEMS_ANCHOR = { x = 1212, y = 423, width = 470 }
local GUILD_ANCHOR = { x = 967.4, y = 561, width = 600, up = true }
-- Кольцо признания (3502) and Кольцо ликования (3501) as game/hidden_stats.lua reads them: type 1, max health.
local RING_3502 = { special = 1, v1 = 200, v2 = 0, v3 = 0, fields = {} }
local RING_3501 = { special = 1, v1 = 100, v2 = 0, v3 = 0, fields = {} }
-- Стойкость (Job01_01): +45 and +30 % of the base defence.
local AUG_0101 = { v1 = 45, v2 = 30 }

-- A Base as HiddenScreens.base gives it, with this base defence.
local function base_of(who, phys_defence)
    return { who = who, phys_defence = phys_defence, magic_defence = 373.8, strength = 420, magic = 372.2 }
end

-- The hidden-stats screens and the game's numbers faked at the modules' edge (game/hidden_screens.lua and
-- game/hidden_stats.lua have their own tests); the data, the model and the panel's drawing are the mod's own.
-- HiddenScreens.current gives W.hover (its calls counted in W.hs.current); base(chara_id) W.bases[chara_id] (each
-- chara_id asked in W.hs.base); job(chara_id) W.jobs[chara_id], else W.jobs.player (the fallback);
-- HiddenStatsGame.ring(id, job) W.rings[id], or W.rings[id](job) when it is a function (each job in
-- W.hs.ring_jobs); augment(name) W.augments[name]; totals(chara_id) a copy of W.totals[chara_id] (read anew each
-- call, as the game's) and equipped(chara_id) W.equipped[chara_id] (each chara_id asked in W.hs.totals /
-- W.hs.equipped).
local function hidden_screens()
    local HS, HG = mod("game/hidden_screens"), mod("game/hidden_stats")
    W.hs = { current = 0, base = {}, ring_jobs = {}, totals = {}, equipped = {} }
    W.rings, W.augments, W.bases, W.jobs = {}, {}, {}, { player = 4 }
    W.totals, W.equipped = {}, {}
    HS.current = function()
        W.hs.current = W.hs.current + 1
        return W.hover
    end
    HS.base = function(id)
        W.hs.base[#W.hs.base + 1] = id
        return W.bases[id]
    end
    HS.totals = function(id)
        W.hs.totals[#W.hs.totals + 1] = id
        local t = W.totals[id]
        return t and { phys = t.phys, magic = t.magic }
    end
    HS.equipped = function(id)
        W.hs.equipped[#W.hs.equipped + 1] = id
        return W.equipped[id]
    end
    HS.job = function(id) return id ~= nil and W.jobs[id] or W.jobs.player end
    HG.ring = function(id, job)
        W.hs.ring_jobs[#W.hs.ring_jobs + 1] = job
        local r = W.rings[id]
        if type(r) == "function" then return r(job) end
        return r
    end
    HG.augment = function(name) return W.augments[name] end
end

-- A ring hovered on the item screen (the player's), or on the equipment screen (`who`, `chara_id`: whose).
local function ring_hover(id, screen, who, chara_id)
    if screen == nil then screen, who, chara_id = "items", "player", PLAYER_ID end
    return { kind = "ring", id = id, screen = screen, who = who, chara_id = chara_id, anchor = ITEMS_ANCHOR }
end

local function augment_hover(name, who, chara_id)
    return { kind = "augment", name = name, screen = "augments", who = who, chara_id = chara_id,
             anchor = GUILD_ANCHOR }
end

-- The panel's lines drawn this frame: the texts on the background list in the plate's beige or grey (not
-- SceneText's shadow or outline copies), in order.
local function hidden_lines()
    local C = mod("ui/enemy_plate").COLORS
    local out = {}
    for _, c in ipairs(ui.calls_of("add_text")) do
        if c.layer == "background" and (c.col == C.name or c.col == C.immune) then out[#out + 1] = c.text end
    end
    return out
end

local function hidden_text()
    return table.concat(hidden_lines(), " / ")
end

test("paused, Кольцо признания hovered on the item screen: the panel is drawn and the meter is not", function()
    world({ settings = { language = "ru" } })
    pause_manager()
    local M = load()
    hidden_screens()
    frame()
    fight(strike)
    eq(overlay_shown(), true, "the summary")
    eq(hidden_text(), "", "no panel without a hover")
    -- the item screen opens (it pauses the game) with 3502 under the cursor
    W.paused = true
    W.rings[3502] = RING_3502
    W.hover = ring_hover(3502)
    frame()
    eq(overlay_shown(), false, "paused: no meter")
    eq(hidden_text(), "+200 к макс. здоровью", "the ring's panel")
    eq(#ui.calls_of("add_rect_filled") > 0, true, "on its panel")
    frame()
    eq(hidden_text(), "+200 к макс. здоровью", "drawn each frame")
    eq(W.hs.ring_jobs[#W.hs.ring_jobs], 4, "read by the player's vocation")
    -- the screen closes
    W.hover = nil
    frame()
    eq(hidden_text(), "", "no panel")
    eq(M.info().errors, 0, "no error caught")
    eq(#M.info().hidden_stats_missing, 0, "no imgui call missing")
end)

test("with hidden_stats off, HiddenScreens.current is never called; on, it is; off again, the panel is forgotten",
    function()
    world({ settings = { language = "ru", hidden_stats = false } })
    local M = load()
    hidden_screens()
    W.rings[3502] = RING_3502
    W.hover = ring_hover(3502)
    for _ = 1, 5 do frame() end
    eq(W.hs.current, 0, "never called")
    eq(hidden_text(), "", "no panel")
    -- switched on in the settings window
    window_set("hidden_stats", true)
    eq(M.state.settings.values.hidden_stats, true, "on")
    frame()
    eq(W.hs.current > 0, true, "called")
    eq(hidden_text(), "+200 к макс. здоровью", "the panel, by the settings window")
    window_set("hidden_stats", false)
    eq(M.state.settings.values.hidden_stats, false, "off")
    eq(M.state.hidden_view.panel, nil, "the panel kept is forgotten")
    local calls = W.hs.current
    for _ = 1, 5 do frame() end
    eq(W.hs.current, calls, "not called again")
    eq(hidden_text(), "", "no panel")
    eq(M.info().errors, 0, "no error caught")
end)

test("with the journal open: no panel and no screen read; closed: the panel is back", function()
    world({ settings = { language = "ru" } })
    local M = load()
    hidden_screens()
    W.rings[3502] = RING_3502
    W.hover = ring_hover(3502)
    frame()
    eq(hidden_text(), "+200 к макс. здоровью", "the panel")
    local calls = W.hs.current
    press(F7)
    eq(journal_shown(), true, "F7 opens the journal")
    for _ = 1, 3 do frame() end
    eq(W.hs.current, calls, "the screens not read while it is open")
    eq(hidden_text(), "", "no panel")
    press(F7)
    eq(journal_shown(), false, "F7 closes it")
    eq(hidden_text(), "+200 к макс. здоровью", "the panel back")
    eq(M.info().errors, 0, "no error caught")
end)

test("the hover goes from 3502 to 3501: the next frame's panel is 3501's", function()
    world({ settings = { language = "ru" } })
    pause_manager()
    local M = load()
    hidden_screens()
    W.paused = true
    W.rings[3502], W.rings[3501] = RING_3502, RING_3501
    W.hover = ring_hover(3502)
    frame()
    eq(hidden_text(), "+200 к макс. здоровью", "3502")
    W.hover = ring_hover(3501)
    frame()
    eq(hidden_text(), "+100 к макс. здоровью", "3501 at once")
    W.hover = ring_hover(3502)
    frame()
    eq(hidden_text(), "+200 к макс. здоровью", "3502 again")
    eq(M.info().errors, 0, "no error caught")
end)

test("a ring with no number found, then a silent one (no game numbers read for either): no stale line", function()
    world({ settings = { language = "ru" } })
    local M = load()
    hidden_screens()
    W.hover = ring_hover(3554) -- Кольцо насмешки: a number should exist, none was found
    frame()
    eq(hidden_text(), "числа в игре не нашлось", "its one line")
    W.hover = ring_hover(10213) -- Кольцо возвращения: no number to show
    frame()
    eq(hidden_text(), "", "no panel, not the last one")
    W.hover = ring_hover(3554)
    frame()
    eq(hidden_text(), "числа в игре не нашлось", "back")
    eq(#W.hs.ring_jobs, 0, "the game's numbers not read for either")
    eq(M.info().errors, 0, "no error caught")
end)

test("the language set from ru to en between frames: the next frame's text is en", function()
    world({ settings = { language = "ru" } })
    local M = load()
    hidden_screens()
    W.rings[3502] = RING_3502
    W.hover = ring_hover(3502)
    frame()
    eq(hidden_text(), "+200 к макс. здоровью", "ru")
    mod("i18n").set("en")
    frame()
    eq(hidden_text(), "+200 max health", "en at once")
    -- through the settings window as well: ru -> en (the language already en), then en -> ru; 1200 px give the
    -- window one page, its Language row drawn
    ui.display = { x = 1920, y = 1200 }
    window_click("dd2dm_sprev:language")
    eq(M.state.settings.values.language, "en", "the setting en")
    frame()
    eq(hidden_text(), "+200 max health", "en still")
    window_click("dd2dm_snext:language")
    eq(mod("i18n").lang(), "ru", "the window's step: en -> ru")
    frame()
    eq(hidden_text(), "+200 к макс. здоровью", "ru again")
    eq(M.info().errors, 0, "no error caught")
end)

test("the panel is built again only when what it shows changed: the thing, whose, the base, the numbers, the language",
    function()
    world({ settings = { language = "ru" } })
    local M = load()
    hidden_screens()
    local Model = mod("hidden_stats_model")
    local panel, builds = Model.panel, 0
    Model.panel = function(...)
        builds = builds + 1
        return panel(...)
    end
    W.augments.Job01_01 = AUG_0101
    W.bases[PLAYER_ID] = base_of("player", 380)
    W.hover = augment_hover("Job01_01", "player", PLAYER_ID)
    for _ = 1, 5 do frame() end
    eq(builds, 1, "built once for five frames")
    eq(hidden_text(), "+45 и +30% от базовой защиты (у тебя 380) — сейчас +159", "45 + 30 % × 380")
    W.bases[PLAYER_ID] = base_of("player", 380)
    frame()
    eq(builds, 1, "the same numbers read anew: not built again")
    W.bases[PLAYER_ID] = base_of("player", 400)
    frame()
    eq(builds, 2, "the base changed")
    eq(hidden_text(), "+45 и +30% от базовой защиты (у тебя 400) — сейчас +165", "45 + 30 % × 400")
    -- Z on the guild screen: Casca's augments, her own base
    W.bases[CASCA_ID] = base_of("pawn", 375)
    W.hover = augment_hover("Job01_01", "pawn", CASCA_ID)
    frame()
    eq(builds, 3, "whose changed")
    eq(hidden_text(), "+45 и +30% от базовой защиты (у пешки 375) — сейчас +158", "45 + 30 % × 375")
    eq(W.hs.base[#W.hs.base], CASCA_ID, "the base of the chara id the screen shows")
    -- the game's numbers read anew
    W.augments.Job01_01 = { v1 = 50, v2 = 30 }
    frame()
    eq(builds, 4, "the numbers changed")
    eq(hidden_text(), "+50 и +30% от базовой защиты (у пешки 375) — сейчас +163", "50 + 30 % × 375")
    mod("i18n").set("en")
    frame()
    eq(builds, 5, "the language changed")
    eq(hidden_text(), "+50 and +30% of the pawn's base defense (375) — +163 now", "en")
    for _ = 1, 3 do frame() end
    eq(builds, 5, "then not again")
    -- another augment
    W.augments.Job01_02 = { v1 = 15, v2 = 0 }
    W.hover = augment_hover("Job01_02", "pawn", CASCA_ID)
    frame()
    eq(builds, 6, "the thing changed")
    eq(hidden_text(), "+15 kg max carry weight", "Job01_02")
    eq(M.info().errors, 0, "no error caught")
end)

test("whose unknown: no base is read and the line keeps its hint; a ring with no such line reads none",
    function()
    world({ settings = { language = "ru" } })
    local M = load()
    hidden_screens()
    W.augments.Job01_01 = AUG_0101
    W.bases[PLAYER_ID], W.bases[CASCA_ID] = base_of("player", 380), base_of("pawn", 375)
    W.hover = augment_hover("Job01_01", nil, CASCA_ID)
    frame()
    eq(#W.hs.base, 0, "no base read")
    eq(hidden_text(), "+45 и +30% от базовой защиты (число в скобках на экране статуса)", "the hint")
    W.hover = augment_hover("Job01_01", nil, nil)
    frame()
    eq(#W.hs.base, 0, "nor without a chara id")
    W.rings[3502] = RING_3502
    W.hover = ring_hover(3502)
    frame()
    eq(#W.hs.base, 0, "none for a ring without a personal number")
    eq(hidden_text(), "+200 к макс. здоровью", "the ring")
    W.hover = augment_hover("Job01_01", "player", PLAYER_ID)
    frame()
    eq(W.hs.base[1], PLAYER_ID, "known: the base of that chara id")
    eq(hidden_text(), "+45 и +30% от базовой защиты (у тебя 380) — сейчас +159", "the personal number")
    eq(M.info().errors, 0, "no error caught")
end)

test("a ring with a personal number reads the base of the one the screen shows", function()
    world({ settings = { language = "ru" } })
    local M = load()
    hidden_screens()
    -- Кольцо нападения (10218, type 44): +20 % of the base strength without pawns
    W.rings[10218] = { special = 44, v1 = 20, v2 = 0, v3 = 0, fields = {} }
    W.bases[PLAYER_ID] = base_of("player", 380)
    W.bases[CASCA_ID] = { who = "pawn", phys_defence = 375, magic_defence = 370, strength = 380, magic = 300 }
    -- the item screen: the player's
    W.hover = ring_hover(10218)
    frame()
    eq(W.hs.base[#W.hs.base], PLAYER_ID, "his base")
    eq(hidden_text(), "без пешек: +20% от базовой силы (у тебя 420) — сейчас +84", "20 % × 420")
    -- the equipment screen on Casca: hers, for Кольцо раздора (10224, type 50); Кольцо нападения gives her nothing,
    -- a pawn being in the party, so no personal number
    W.rings[10224] = { special = 50, v1 = 50, v2 = 0, v3 = 0, fields = {} }
    W.hover = ring_hover(10224, "equipment", "pawn", CASCA_ID)
    frame()
    eq(W.hs.base[#W.hs.base], CASCA_ID, "her base")
    eq(hidden_text(), "голыми руками: +50% от базовой силы (у пешки 380) — сейчас +190", "50 % × 380")
    W.hover = ring_hover(10218, "equipment", "pawn", CASCA_ID)
    frame()
    eq(hidden_text(), "без пешек: +20% от базовой силы", "no personal number for a pawn")
    -- her base cannot be read: still a pawn's, so the ring without pawns gets no hint either; the bare-handed one
    -- gets the hint in place of her number
    local casca = W.bases[CASCA_ID]
    W.bases[CASCA_ID] = nil
    frame()
    eq(W.hs.base[#W.hs.base], CASCA_ID, "her base asked")
    eq(hidden_text(), "без пешек: +20% от базовой силы", "unread base, a pawn: no hint")
    W.hover = ring_hover(10224, "equipment", "pawn", CASCA_ID)
    frame()
    eq(table.concat(hidden_lines(), " "), "голыми руками: +50% от базовой силы (число в скобках на экране статуса)",
        "unread base: the hint")
    W.bases[CASCA_ID] = casca
    frame()
    eq(hidden_text(), "голыми руками: +50% от базовой силы (у пешки 380) — сейчас +190", "read again: her number")
    -- whose unknown: no base read, the hint
    local asked = #W.hs.base
    W.hover = ring_hover(10218, "equipment", nil, CASCA_ID)
    frame()
    eq(#W.hs.base, asked, "no base read")
    -- the hint is longer than the panel is wide: drawn on two lines, wrapped at a space
    eq(table.concat(hidden_lines(), " "), "без пешек: +20% от базовой силы (число в скобках на экране статуса)",
        "the hint")
    eq(M.info().errors, 0, "no error caught")
end)

test("the totals and what is on reach the panel, read only for an entry with a total line", function()
    world({ settings = { language = "ru" } })
    local M = load()
    hidden_screens()
    local Model = mod("hidden_stats_model")
    local panel, builds = Model.panel, 0
    Model.panel = function(...)
        builds = builds + 1
        return panel(...)
    end
    local legend = "≈ другие моды не подтверждают · ? догадка"
    -- Стойкость on the player: his totals and his augments, by the chara id shown
    W.augments.Job01_01 = AUG_0101
    W.bases[PLAYER_ID] = base_of("player", 380)
    W.totals[PLAYER_ID] = { phys = 1645, magic = 1494.94 }
    W.equipped[PLAYER_ID] = { augments = { Job01_01 = true, Job05_00 = true }, items = { [3502] = true } }
    W.hover = augment_hover("Job01_01", "player", PLAYER_ID)
    for _ = 1, 3 do frame() end
    eq(hidden_text(), "+45 и +30% от базовой защиты (у тебя 380) — сейчас +159 / защита 1486 → 1645 (+11%)"
        .. " / ≈ -10% физ. урона по тебе / " .. legend, "on him: the 159 is in his 1645")
    eq(W.hs.totals[1], PLAYER_ID, "his totals")
    eq(W.hs.equipped[1], PLAYER_ID, "what he has on")
    eq(builds, 1, "the same totals read anew: built once")
    -- not on him: the 159 comes on top
    W.totals[PLAYER_ID] = { phys = 1486, magic = 1337.8 }
    W.equipped[PLAYER_ID] = { augments = { Job05_00 = true }, items = {} }
    frame()
    eq(builds, 2, "the totals and what is on changed")
    eq(hidden_lines()[2], "защита 1486 → 1645 (+11%)", "not on him")
    -- what he has on cannot be read: no total line, no damage line
    W.equipped[PLAYER_ID] = { items = {} }
    frame()
    eq(hidden_text(), "+45 и +30% от базовой защиты (у тебя 380) — сейчас +159", "unknown: the line alone")
    W.equipped[PLAYER_ID] = nil
    frame()
    eq(hidden_text(), "+45 и +30% от базовой защиты (у тебя 380) — сейчас +159", "none read: the line alone")
    -- Кольцо стойкости on Casca's equipment screen: her totals, her gear, the pawn's damage line
    W.rings[3509] = { special = 0, v1 = 0, v2 = 0, v3 = 0, fields = { PhysicalDefence = 50 } }
    W.totals[CASCA_ID] = { phys = 1325, magic = 1240 }
    W.equipped[CASCA_ID] = { augments = {}, items = { [2001] = true, [3509] = true } }
    W.hover = ring_hover(3509, "equipment", "pawn", CASCA_ID)
    frame()
    eq(hidden_text(), "+50 к физ. защите / защита 1275 → 1325 (+4%) / ≈ -4% физ. урона по пешке / " .. legend,
        "on her")
    eq(W.hs.totals[#W.hs.totals], CASCA_ID, "her totals")
    eq(W.hs.equipped[#W.hs.equipped], CASCA_ID, "her gear")
    W.totals[CASCA_ID] = { phys = 1425, magic = 1240 }
    frame()
    eq(hidden_lines()[2], "защита 1375 → 1425 (+4%)", "her totals changed: built again")
    -- whose unknown: the total line, no damage line
    W.hover = ring_hover(3509, "equipment", nil, CASCA_ID)
    frame()
    eq(hidden_text(), "+50 к физ. защите / защита 1375 → 1425 (+4%)", "no damage line for nobody known")
    -- a ring without a total line: neither is read
    local asked = #W.hs.totals + #W.hs.equipped
    W.rings[3502] = RING_3502
    W.hover = ring_hover(3502)
    for _ = 1, 3 do frame() end
    eq(#W.hs.totals + #W.hs.equipped, asked, "not read for 3502")
    eq(hidden_text(), "+200 к макс. здоровью", "its panel")
    eq(M.info().errors, 0, "no error caught")
end)

-- app.HumanAbilityID for the tests that read what is on as the game gives it: Job01_00 .. Job10_06 = 4 .. 55.
local ABILITY_IDS = {}
do
    local i = 0
    for job = 1, 10 do
        for slot = 0, job == 10 and 6 or 4 do
            i = i + 1
            ABILITY_IDS[string.format("Job%02d_%02d", job, slot)] = i + 3
        end
    end
end

local STOUT_LINE = "+45 и +30% от базовой защиты (у тебя 380) — сейчас +159"
local HS_LEGEND = "≈ другие моды не подтверждают · ? догадка"

-- A world where what the player has on is read by the real HiddenScreens.equipped, the rest of the
-- hidden-stats screens faked as hidden_screens() fakes them: his Human (a Thief, 4) with an AbilityContext whose
-- getAbility(4, slot) is W.slots[slot] (Жизненная сила and Стойкость in No0..No6, the rest 0), and the calculators'
-- dictionary with his calculator, whose getEquipData().Data.Equips is the game array of W.equips (an item id; false:
-- a null entry; "unread": an entry whose get_ItemId gives nothing). His totals 1645 / 1494.94, his base 380;
-- Стойкость's and Кольцо стойкости's (3509) numbers.
local function equipped_world()
    world({ settings = { language = "ru" } })
    R.enum("app.HumanAbilityID", ABILITY_IDS)
    local M = load()
    local HS = mod("game/hidden_screens")
    local equipped = HS.equipped
    hidden_screens()
    HS.equipped = equipped
    W.slots = { [0] = ABILITY_IDS.Job05_00, [1] = 0, [2] = ABILITY_IDS.Job01_01, [3] = 0, [4] = 0, [5] = 0, [6] = 0 }
    W.equips = { 1001, 3509, 0, false }
    local jobs = R.object("app.JobContext", { CurrentJob = 4 })
    local ac = R.object("app.AbilityContext", {}, {
        ["getAbility(app.Character.JobEnum, app.AbilityContext.AbilitySlot)"] = function(_, job, slot)
            if job ~= 4 then return nil end
            return W.slots[slot]
        end,
    })
    local human = R.object("app.Human", { ["<AbilityContext>k__BackingField"] = ac },
        { get_JobContext = function() return jobs end })
    W.player.methods.get_Human = function() return human end
    local calc = R.object("app.PlayerStatusCalculator", {}, {
        getEquipData = function()
            local entries = {}
            for i, id in ipairs(W.equips) do
                entries[i] = id ~= false and R.object("app.ItemDefine.StorageData", {}, {
                    get_ItemId = function() if id ~= "unread" then return id end end,
                }) or false
            end
            local equips = R.array(entries, "app.ItemDefine.StorageData[]")
            return R.object("app.ReadOnlyEquipData", { Data = R.object("app.EquipData", { Equips = equips }) })
        end,
    })
    local dict = R.object("System.Collections.Generic.Dictionary`2<app.CharacterID,app.PlayerStatusCalculator>", {}, {
        GetEnumerator = function()
            local given = false
            return R.object("Enumerator", {}, {
                MoveNext = function()
                    local more = not given
                    given = true
                    return more
                end,
                get_Current = function() return R.object("KeyValuePair", { key = PLAYER_ID, value = calc }) end,
            })
        end,
    })
    local holder = R.object("app.PlayerStatusCalculatorHolder", { Calculators = dict })
    R.method("app.CharacterManager", "get_PlayerStatusCalculatorHolder", function() return holder end)
    W.augments.Job01_01 = AUG_0101
    W.bases[PLAYER_ID] = base_of("player", 380)
    W.totals[PLAYER_ID] = { phys = 1645, magic = 1494.94 }
    W.rings[3509] = { special = 0, v1 = 0, v2 = 0, v3 = 0, fields = { PhysicalDefence = 50 } }
    return M
end

test("an augment slot that reads nothing leaves out the total and damage lines, never «not on»", function()
    local M = equipped_world()
    W.hover = augment_hover("Job01_01", "player", PLAYER_ID)
    frame()
    eq(hidden_text(), STOUT_LINE .. " / защита 1486 → 1645 (+11%) / ≈ -10% физ. урона по тебе / " .. HS_LEGEND,
        "every slot read: Стойкость on him")
    W.slots[4] = nil
    frame()
    eq(hidden_text(), STOUT_LINE, "slot No4 read nothing: neither line")
    -- Стойкость not in the slots read: still unknown, not «защита 1645 → 1804 (+10%)»
    W.slots[2] = 0
    frame()
    eq(hidden_text(), STOUT_LINE, "a slot unread is never «not on»")
    W.slots[4] = 0
    frame()
    eq(hidden_text(), STOUT_LINE .. " / защита 1645 → 1804 (+10%) / ≈ -9% физ. урона по тебе / " .. HS_LEGEND,
        "every slot read and Стойкость in none: not on him")
    eq(M.info().errors, 0, "no error caught")
end)

test("an augment id with no name in app.HumanAbilityID leaves out the total and damage lines", function()
    local M = equipped_world()
    W.slots[5] = 999
    W.hover = augment_hover("Job01_01", "player", PLAYER_ID)
    frame()
    eq(hidden_text(), STOUT_LINE, "999 has no name: neither line, Стойкость found or not")
    W.slots[2] = 0
    frame()
    eq(hidden_text(), STOUT_LINE, "999 might be Стойкость: never «not on»")
    W.slots[2], W.slots[5] = ABILITY_IDS.Job01_01, 0
    frame()
    eq(hidden_text(), STOUT_LINE .. " / защита 1486 → 1645 (+11%) / ≈ -10% физ. урона по тебе / " .. HS_LEGEND,
        "every id named: the lines")
    eq(M.info().errors, 0, "no error caught")
end)

test("an Equips entry that cannot be read leaves out the ring's total and damage lines", function()
    local M = equipped_world()
    W.totals[PLAYER_ID] = { phys = 1536, magic = 1494.94 }
    W.hover = ring_hover(3509)
    frame()
    eq(hidden_text(), "+50 к физ. защите / защита 1486 → 1536 (+3%) / ≈ -3% физ. урона по тебе / " .. HS_LEGEND,
        "every entry read (a null one is an empty slot): Кольцо стойкости on him")
    W.equips[3] = "unread"
    frame()
    eq(hidden_text(), "+50 к физ. защите", "an entry unread: neither line")
    W.equips = { 1001, "unread", false }
    frame()
    eq(hidden_text(), "+50 к физ. защите", "the ring not among those read: never «not on»")
    W.equips = { 1001, 0, false }
    frame()
    eq(hidden_text(), "+50 к физ. защите / защита 1536 → 1586 (+3%) / ≈ -3% физ. урона по тебе / " .. HS_LEGEND,
        "every entry read, the ring in none: not on him")
    eq(M.info().errors, 0, "no error caught")
end)

test("a ring's numbers are read by the vocation of the character the screen shows", function()
    world({ settings = { language = "ru" } })
    local M = load()
    hidden_screens()
    -- Кольцо ограбления (10231): the player a Thief (4), Casca a Warrior (5), the other pawn a Trickster (9)
    W.jobs = { player = 4, [CASCA_ID] = 5, [PAWN2_ID] = 9 }
    local factors = { [4] = 0.4, [5] = 1.0, [9] = 2.5 }
    local raws = {}
    W.rings[10231] = function(job)
        raws[job] = raws[job] or { special = 57, v1 = 0, v2 = 0, v3 = 0, fields = {},
                                   pickpocket = { base = 1.5, factor = factors[job] } }
        return raws[job]
    end
    W.hover = ring_hover(10231, "equipment", "pawn", CASCA_ID)
    frame()
    eq(W.hs.ring_jobs[#W.hs.ring_jobs], 5, "Casca's vocation")
    eq(hidden_text(), "≈ базовый шанс 1,5% забрать реликвию обычной атакой / ≈ шанс у текущего призвания ×1"
        .. " / ≈ другие моды не подтверждают · ? догадка", "her factor")
    -- C: the next pawn, a pawn too: built again by her own numbers
    W.hover = ring_hover(10231, "equipment", "pawn", PAWN2_ID)
    frame()
    eq(W.hs.ring_jobs[#W.hs.ring_jobs], 9, "the other pawn's vocation")
    eq(hidden_lines()[2], "≈ шанс у текущего призвания ×2,5", "her factor")
    -- the item screen: the player's
    W.hover = ring_hover(10231)
    frame()
    eq(W.hs.ring_jobs[#W.hs.ring_jobs], 4, "the player's vocation")
    eq(hidden_lines()[2], "≈ шанс у текущего призвания ×0,4", "his factor")
    eq(M.info().errors, 0, "no error caught")
end)

test("a new world resets the hidden-stats modules and forgets the panel kept", function()
    world({ settings = { language = "ru" } })
    local M = load()
    local resets = {}
    for _, name in ipairs({ "game/hidden_screens", "game/hidden_stats", "ui/hidden_stats" }) do
        local m = mod(name)
        local reset = m.reset
        m.reset = function(...)
            resets[name] = (resets[name] or 0) + 1
            return reset(...)
        end
    end
    hidden_screens()
    W.rings[3502] = RING_3502
    W.hover = ring_hover(3502)
    frame()
    eq(M.state.hidden_view.panel ~= nil, true, "a panel kept")
    R.method("app.CharacterManager", "get_ManualPlayer", function() return nil end)
    scene_change()
    eq(resets["game/hidden_screens"], 1, "the screens forgotten")
    eq(resets["game/hidden_stats"], 1, "the game's numbers read forgotten")
    eq(resets["ui/hidden_stats"], 1, "the panel's drawing reset")
    eq(M.state.hidden_view.panel, nil, "the panel kept forgotten")
    eq(M.info().errors, 0, "no error caught")
end)

test("with debug on, the panel's cost is in the debug log each time it stops being shown, HiddenScreens.current's "
    .. "time included", function()
    world({ settings = { language = "ru", debug = true } })
    local M = load()
    hidden_screens()
    W.rings[3502] = RING_3502
    -- os.clock stands still but for HiddenScreens.current, which takes 1 ms
    local HS = mod("game/hidden_screens")
    local current, clock, now = HS.current, os.clock, 0
    os.clock = function() return now end
    HS.current = function(...)
        now = now + 0.001
        return current(...)
    end
    frame()
    frame()
    local before = R.files[LOG_FILE] or ""
    W.hover = ring_hover(3502)
    for _ = 1, 3 do frame() end
    local during = R.files[LOG_FILE] or ""
    W.hover = nil
    frame()
    local first = R.files[LOG_FILE] or ""
    -- a second look at the ring
    W.hover = ring_hover(3502)
    frame()
    frame()
    W.hover = nil
    frame()
    os.clock = clock
    local log = R.files[LOG_FILE] or ""
    eq(lines_with(before, "hidden stats"), 0, "nothing hovered yet: no line")
    eq(lines_with(during, "hidden stats"), 0, "none while it is shown")
    eq(lines_with(first, "hidden stats"), 1, "one when it stops")
    local pattern = "hidden stats frames=(%d+) builds=(%d+) avg=([%d.]+)ms max=([%d.]+)ms idle=(%d+) "
        .. "idle_avg=([%d.]+)ms idle_max=([%d.]+)ms"
    local frames, builds, avg, max, idle, idle_avg, idle_max = first:match(pattern)
    eq(tonumber(frames), 3, "the frames it was shown")
    eq(tonumber(builds), 1, "built once")
    eq(avg, "1.000", "HiddenScreens.current's time in each frame"); eq(max, "1.000", "the largest")
    eq(tonumber(idle), 2, "the frames before with nothing hovered")
    eq(idle_avg, "1.000", "their time: HiddenScreens.current's"); eq(idle_max, "1.000", "the largest")
    eq(lines_with(log, "hidden stats"), 2, "a line per look")
    frames, builds, avg, max, idle = log:match(".*" .. pattern)
    eq(tonumber(frames), 2, "counted afresh"); eq(tonumber(builds), 1, "built again for the new look")
    eq(tonumber(idle), 1, "the frame it stopped in, then idle")
    -- debug off: nothing measured, nothing written
    M.state.settings:set("debug", false)
    local cost = M.state.hidden_cost
    local idle_now = cost.idle
    W.hover = ring_hover(3502)
    frame()
    W.hover = nil
    frame()
    eq(M.state.hidden_cost.frames, 0, "debug off: no frame measured")
    eq(M.state.hidden_cost.idle, idle_now, "nor an idle one")
    eq(lines_with(R.files[LOG_FILE] or "", "hidden stats"), 2, "no line")
    eq(M.info().errors, 0, "no error caught")
end)

test("with debug on, the first time a screen's panel is placed by an anchor with a part fallen back, debug.log names "
    .. "the parts, once per screen", function()
    world({ settings = { language = "ru", debug = true } })
    local M = load()
    hidden_screens()
    W.rings[3502] = RING_3502
    W.augments.Job05_00 = { v1 = 200, v2 = 0 }
    -- a hover whose anchor's parts read as `read` says (true: read, false: fell back)
    local function with(hover, x, y, width, read)
        hover.anchor = { x = x, y = y, width = width, up = hover.anchor.up, read = read }
        return hover
    end
    local function log() return R.files[LOG_FILE] or "" end
    W.hover = with(ring_hover(3502), 1212, 423, 480, { x = true, y = true, width = true })
    frame()
    eq(lines_with(log(), "anchor fell back"), 0, "every part read: no line")
    -- the item screen's width fell back
    W.hover = with(ring_hover(3502), 1212, 423, 470, { x = true, y = true, width = false })
    for _ = 1, 3 do frame() end
    eq(lines_with(log(), "hidden stats: items anchor fell back: width (x=1212 y=423 width=470)"), 1,
        "one line naming the part and the place taken")
    W.hover = nil
    frame()
    W.hover = with(ring_hover(3502), 1212, 423, 470, { x = true, y = true, width = false })
    frame()
    eq(lines_with(log(), "anchor fell back"), 1, "once for the screen, however often it is shown")
    -- the guild: its own line
    W.hover = with(augment_hover("Job05_00", "player", PLAYER_ID), 967.4, 567, 600,
        { x = true, y = false, width = false })
    frame()
    eq(lines_with(log(), "hidden stats: augments anchor fell back: y, width (x=967.4 y=567 width=600)"), 1,
        "the guild's line")
    -- a hover with no panel (a ring with no number to show) places nothing: no line
    W.hover = with(ring_hover(10213, "equipment", "player", PLAYER_ID), 1212, 423, 470,
        { x = false, y = true, width = true })
    frame()
    eq(lines_with(log(), "equipment anchor"), 0, "no panel shown: no line")
    -- debug off: nothing written, nothing noted; on again, the first time it is shown
    M.state.settings:set("debug", false)
    W.hover = with(ring_hover(3502, "equipment", "player", PLAYER_ID), 1212, 423, 470,
        { x = false, y = true, width = true })
    frame()
    eq(lines_with(log(), "equipment anchor"), 0, "debug off: no line")
    M.state.settings:set("debug", true)
    frame()
    eq(lines_with(log(), "hidden stats: equipment anchor fell back: x (x=1212 y=423 width=470)"), 1, "on again: written")
    frame()
    eq(lines_with(log(), "anchor fell back"), 3, "one line per screen")
    eq(M.info().errors, 0, "no error caught")
end)

-- The hidden-stats evidence -------------------------------------------------------------------------------------------

-- game/stat_check.lua faked at the module's edge (it has its own tests): snapshot() gives W.snap and W.why, each call
-- counted in W.snaps. The collector is the mod's own.
local function stat_snapshots()
    local SC = mod("game/stat_check")
    W.snaps = 0
    SC.snapshot = function()
        W.snaps = W.snaps + 1
        return W.snap, W.why
    end
end

-- A snapshot of the Warfarer with these rings and this max HP.
local function stat_snap(rings, hp_max)
    return { numbers = { ["total.BasicDefence"] = 380, ["total.AdditionalDefence"] = 159,
                         ["total.ArmorDefence"] = 1106, hp_max = hp_max },
             equipped = { job = 10, augments = { "Job01_01", "Job05_00" }, rings = rings, items = { 1001, 2001 } } }
end

test("hidden-stats evidence: with debug on and the game not paused, a snapshot at most every 2 s and 1 s after a "
    .. "pause's end (none before it); paused or with debug off, none", function()
    world({ settings = { debug = true } })
    pause_manager()
    local M = load()
    stat_snapshots()
    frame()
    eq(W.snaps, 1, "the first frame")
    for _ = 1, 9 do frame(0.2) end
    eq(W.snaps, 1, "not again within 2 s")
    frame(0.2)
    eq(W.snaps, 2, "2 s after the last")
    -- a short pause (a menu): none in it, one 1 s after its end (quitting from the pause menu ends a pause as the
    -- world starts going), before 2 s are over
    frame(0.2)
    W.paused = true
    frame(0.2)
    frame(0.2)
    eq(W.snaps, 2, "paused: none")
    W.paused = false
    frame(0.2)
    eq(W.snaps, 2, "the first frame after the pause: none")
    frame(0.5)
    eq(W.snaps, 2, "0.5 s after it: none")
    frame(0.6)
    eq(W.snaps, 3, "1 s after the pause's end, 1.9 s after the last")
    frame(0.2)
    eq(W.snaps, 3, "then 2 s apart again")
    -- a long one: none however long, and none in the second after it, though the last was long ago
    W.paused = true
    for _ = 1, 10 do frame(1) end
    eq(W.snaps, 3, "paused 10 s: none")
    W.paused = false
    frame()
    frame(0.5)
    eq(W.snaps, 3, "not at once, though the last is 10 s old")
    frame(0.6)
    eq(W.snaps, 4, "1 s after it")
    -- debug off: none
    M.state.settings:set("debug", false)
    for _ = 1, 10 do frame(1) end
    eq(W.snaps, 4, "debug off: none")
    M.state.settings:set("debug", true)
    frame()
    eq(W.snaps, 5, "on again: at once")
    eq(M.info().errors, 0, "no error caught")
end)

test("hidden-stats evidence: a ring changed on the paused equipment screen is one stat_check record, written 1 s "
    .. "after the pause's end", function()
    world({ settings = { debug = true } })
    pause_manager()
    local M = load()
    stat_snapshots()
    W.snap = stat_snap({ 10223, 10227 }, 3100)
    frame()
    frame(2)
    eq(W.snaps, 2, "two looks"); eq(#collected("stat_check"), 0, "nothing changed")
    -- the equipment screen pauses the game: Кольцо признания in place of Кольцо бескорыстия, max HP 3100 -> 3300
    W.paused = true
    frame()
    W.snap = stat_snap({ 3502, 10227 }, 3300)
    for _ = 1, 5 do frame(1) end
    eq(#collected("stat_check"), 0, "none while paused")
    W.paused = false
    frame()
    eq(#collected("stat_check"), 0, "none at the first frame after the pause")
    frame(1)
    local list = collected("stat_check")
    eq(#list, 1, "one record 1 s after the pause's end")
    local r = list[1]
    eq(T.str(r.added), "3502", "Кольцо признания in"); eq(T.str(r.removed), "10223", "Кольцо бескорыстия out")
    eq(r.changed.hp_max.from, 3100, "max HP from 3100"); eq(r.changed.hp_max.to, 3300, "to 3300")
    eq(r.job, 10, "the Warfarer")
    for _ = 1, 5 do frame(1) end
    eq(#collected("stat_check"), 1, "the same snapshot after it: no more")
    eq(M.info().errors, 0, "no error caught")
end)

test("hidden-stats evidence: augments that cannot be read are told in debug.log once a game session", function()
    world({ settings = { debug = true } })
    local M = load()
    stat_snapshots()
    W.snap = stat_snap({ 10223, 10227 }, 3100)
    frame()
    local told = "stat_check: the augment slots cannot be read (getAbility gave nothing for all 7)"
    eq(lines_with(R.files[LOG_FILE] or "", told), 0, "readable: no line")
    -- a snapshot that is nil for another reason (no calculator...) says nothing
    W.snap = nil
    frame(2)
    eq(lines_with(R.files[LOG_FILE] or "", "stat_check:"), 0, "no line for another reason")
    -- getAbility gives nothing for all 7 slots: no snapshot
    W.snap, W.why = nil, "augments"
    for _ = 1, 5 do frame(2) end
    eq(W.snaps, 7, "looked every 2 s")
    eq(lines_with(R.files[LOG_FILE], told), 1, "one line, not one a look")
    -- readable again, then not: still the one line in this game session
    W.snap, W.why = stat_snap({ 10223, 10227 }, 3100), nil
    frame(2)
    W.snap, W.why = nil, "augments"
    frame(2)
    eq(lines_with(R.files[LOG_FILE], told), 1, "once a game session")
    eq(#collected("stat_check"), 0, "no record")
    eq(M.info().errors, 0, "no error caught")
end)

test("hidden-stats evidence: Debug off and on again starts afresh: what changed while it was off is no record",
    function()
    world({ settings = { debug = true } })
    local M = load()
    stat_snapshots()
    -- 1200 px: the settings window on one page, its Debug row drawn
    ui.display = { x = 1920, y = 1200 }
    W.snap = stat_snap({ 10223, 10227 }, 3100)
    frame()
    eq(W.snaps, 1, "a snapshot")
    window_set("debug", false)
    eq(M.state.settings.values.debug, false, "Debug off in the settings window")
    -- while it is off: a ring changed and the numbers with it (and a meal, a level up...)
    W.snap = stat_snap({ 3502, 10227 }, 3300)
    for _ = 1, 5 do frame(1) end
    eq(W.snaps, 1, "none while it is off")
    window_set("debug", true)
    eq(M.state.settings.values.debug, true, "on again")
    frame(2)
    eq(W.snaps >= 2, true, "looked again")
    eq(#collected("stat_check"), 0, "no record of what changed while it was off")
    -- the next change is one, against the snapshot taken after it came on
    W.snap = stat_snap({ 3501, 10227 }, 3000)
    frame(2)
    local list = collected("stat_check")
    eq(#list, 1, "the next change is one")
    eq(T.str(list[1].removed), "3502", "from the ring worn when Debug came on")
    eq(M.info().errors, 0, "no error caught")
end)

test("hidden-stats evidence: a new world (a loaded save) is no equipment change", function()
    world({ settings = { debug = true } })
    local M = load()
    stat_snapshots()
    W.snap = stat_snap({ 10223, 10227 }, 3100)
    frame()
    -- a save loaded: the player gone at a scene change, then back with other rings and numbers
    local player = W.player
    R.method("app.CharacterManager", "get_ManualPlayer", function() return nil end)
    scene_change()
    R.method("app.CharacterManager", "get_ManualPlayer", function() return player end)
    W.snap = stat_snap({ 3501 }, 2500)
    frame(2)
    eq(W.snaps, 2, "looked again")
    eq(#collected("stat_check"), 0, "no record for the loaded save")
    W.snap = stat_snap({ 3502 }, 2600)
    frame(2)
    eq(#collected("stat_check"), 1, "the next change is one")
    eq(T.str(collected("stat_check")[1].removed), "3501", "from the loaded save's ring")
    eq(M.info().errors, 0, "no error caught")
end)

-- No game object kept across a scene change --------------------------------------------------------------------------

-- A screen of the hidden-stats panel in the scene of bars_scene (the item screen, ui060301_00), not drawn: the real
-- game/hidden_screens.lua finds and keeps it, and asks its GameObject each frame whether it is drawn.
local function item_gui()
    R.type("app.ui060301_00")
    local s = { drawn = false }
    s.comp = R.object("app.ui060301_00", {})
    s.go = R.object("via.GameObject", {}, {
        get_Name = function() return "ui060301_00" end,
        get_DrawSelf = function() return s.drawn end,
        ["getComponent(System.Type)"] = function() return s.comp end,
    })
    s.gui = R.object("via.gui.GUI", {}, { get_GameObject = function() return s.go end })
    W.guis[#W.guis + 1] = s.gui
    return s
end

test("without a player character nothing kept is read and the screens and bars kept are dropped; when he is "
    .. "back they are found again", function()
    world()
    bars_scene()
    local M = load()
    local bar = gauge(W.goblin)
    local screen = item_gui()
    frame()
    local HS, gauges = mod("game/hidden_screens"), mod("game/gauges")
    eq(HS.kept(), 1, "the item screen kept")
    eq(gauges.count(), 1, "the bar kept")
    eq(numbers(), "3 053 / 3 700 · 83%", "the bar's numbers")
    local asked = calls_on({ screen.go, screen.gui, bar.go, bar.gui, bar.panel })
    frame()
    eq(asked() > 0, true, "while the world is there, both are asked each frame")
    -- the world goes (a title screen, a load): the objects kept may be destroyed under the mod from now on
    local player = W.player
    W.player = nil
    asked = calls_on({ screen.go, screen.gui, bar.go, bar.gui, bar.panel, player })
    for _ = 1, 30 do frame(0.1) end
    eq(asked(), 0, "nothing kept is asked: the screen, the bar, the player's character")
    eq(HS.kept(), 0, "no screen kept")
    eq(gauges.count(), 0, "no bar kept")
    eq(numbers(), "", "nothing drawn")
    eq(M.info().errors, 0, "no error caught")
    -- he is back: looked for again at once
    W.player = player
    frame()
    eq(HS.kept(), 1, "the screen found again")
    eq(gauges.count(), 1, "the bar found again")
    eq(numbers(), "3 053 / 3 700 · 83%", "drawn again")
    eq(M.info().errors, 0, "no error caught")
end)

test("a scene-type change drops the screens and bars kept, whatever the player; with him the fight goes on",
        function()
    world()
    bars_scene()
    local M = load()
    local bar = gauge(W.goblin)
    local screen = item_gui()
    frame()
    W.mode = 2
    frame()
    strike()
    local HS, gauges = mod("game/hidden_screens"), mod("game/gauges")
    eq(HS.kept(), 1, "the screen kept"); eq(gauges.count(), 1, "the bar kept")
    local asked = calls_on({ screen.go, screen.gui, bar.go, bar.gui, bar.panel })
    scene_change()
    eq(HS.kept(), 0, "the screen dropped by the hook"); eq(gauges.count(), 0, "the bar too")
    eq(asked(), 0, "neither asked in the hook")
    eq(M.info().fighting, true, "the player is there: the fight goes on")
    frame()
    eq(HS.kept(), 1, "the screen found again"); eq(gauges.count(), 1, "the bar found again")
    eq(numbers(), "3 043 / 3 700 · 82%", "its numbers")
    eq(M.info().errors, 0, "no error caught")
end)

test("with debug on, debug.log tells by frame the world's changes, each scene-type change and the last guard",
        function()
    world({ settings = { debug = true } })
    bars_scene()
    local M = load()
    local screen = item_gui()
    local function log() return R.files[LOG_FILE] or "" end
    frame()
    eq(lines_with(log(), "world:"), 0, "the first frame tells nothing")
    local player = W.player
    W.player = nil
    frame()
    eq(lines_with(log(), "world: no player character at frame 2: the screens and bars kept dropped"), 1, "gone")
    frame()
    eq(lines_with(log(), "world:"), 1, "once")
    W.player = player
    frame()
    eq(lines_with(log(), "world: player character back at frame 4"), 1, "back")
    scene_change()
    eq(lines_with(log(), "scene type changed after frame 4 (player here)"), 1, "the hook, with the player")
    frame()
    eq(mod("game/hidden_screens").kept(), 1, "the screen found again")
    -- the last guard: the game destroyed the kept screen under the mod while the player was still there
    screen.go.methods.get_DrawSelf = function() error("Invoke threw an exception") end
    frame()
    eq(lines_with(log(), "hidden screens: a kept screen raised at frame 6 (the game destroyed it): dropped"), 1,
        "the last guard")
    frame()
    eq(lines_with(log(), "hidden screens:"), 1, "once")
    W.player = nil
    scene_change()
    eq(lines_with(log(), "scene type changed after frame 7 (no player)"), 1, "the hook, without him")
    eq(M.info().errors, 0, "no error caught")
end)

test("no hidden-stats evidence is taken without a player character", function()
    world({ settings = { debug = true } })
    pause_manager()
    local M = load()
    stat_snapshots()
    frame()
    eq(W.snaps, 1, "the first frame")
    local player = W.player
    W.player = nil
    for _ = 1, 5 do frame(1) end
    -- a pause that ends while he is gone: its snapshot waits for him, and for its second
    W.paused = true
    frame()
    W.paused = false
    frame()
    eq(W.snaps, 1, "none without him")
    W.player = player
    frame()
    eq(W.snaps, 1, "he is back within the second: not yet")
    frame(1)
    eq(W.snaps, 2, "1 s after the pause's end and his return, with him there")
    eq(M.info().errors, 0, "no error caught")
end)

test("the snapshot after a pause is taken 1 s after its end and only with the player character there then",
        function()
    world({ settings = { debug = true } })
    pause_manager()
    local M = load()
    stat_snapshots()
    frame()
    eq(W.snaps, 1, "the first frame")
    -- the pause menu, then «save and return to the title»: the pause ends, the player goes within the second
    W.paused = true
    for _ = 1, 5 do frame(1) end
    W.paused = false
    frame()
    frame(0.4)
    local player = W.player
    W.player = nil
    for _ = 1, 10 do frame(0.2) end
    eq(W.snaps, 1, "no snapshot: the player went before the second was over")
    -- a pause that ends with him there all along: one, 1 s after
    W.player = player
    frame()
    eq(W.snaps, 1, "he is back, the pause's second long over: none yet (he waits a second of his own)")
    frame(1)
    eq(W.snaps, 2, "1 s after his return")
    W.paused = true
    frame(1)
    W.paused = false
    frame()
    for _ = 1, 4 do frame(0.2) end
    eq(W.snaps, 2, "0.8 s after: none")
    frame(0.3)
    eq(W.snaps, 3, "1 s after")
    eq(M.info().errors, 0, "no error caught")
end)

test("the pause manager is never kept: a scene change's new manager is read, the old one never asked again",
        function()
    world()
    local old = pause_manager()
    local lookups = 0
    local lookup = sdk.get_managed_singleton
    sdk.get_managed_singleton = function(name)
        if name == "app.PauseManager" then lookups = lookups + 1 end
        return lookup(name)
    end
    local M = load()
    frame()
    frame()
    eq(lookups, 2, "looked up in each frame")
    -- a scene-type change with the player there, the game's manager made anew: the next frame reads the new one
    local fresh = R.object("app.PauseManager")
    R.singleton("app.PauseManager", fresh)
    scene_change()
    local on_old, on_fresh = calls_on({ old }), calls_on({ fresh })
    W.paused = true
    frame()
    eq(M.state.paused, true, "the new manager's pause is read")
    eq(on_old(), 0, "the old manager not asked")
    eq(on_fresh(), 1, "the new one asked once")
    W.paused = false
    frame()
    -- the player gone (a load): still looked up in each frame it is read, never kept into the next
    local player = W.player
    W.player = nil
    local looked = lookups
    frame()
    frame()
    eq(lookups - looked, 2, "looked up in each frame without him")
    W.player = player
    frame()
    eq(lookups - looked, 3, "and with him back")
    eq(on_old(), 0, "the old manager never asked")
    eq(M.info().errors, 0, "no error caught")
end)

test("the party listing is read once a frame, shared by the world read, the HP poll and the skill states",
        function()
    world()
    R.enum("app.HumanCustomSkillID", { None = 0, Job03_FullRecover = 210 })
    local M = load()
    frame()
    W.mode = 2
    frame()
    strike()
    frame() -- the party read the fight start asked for
    eq(M.info().fighting, true, "a fight is open: the skill states are read too")
    local players, lists = #R.calls_of("get_ManualPlayer"), #R.calls_of("get_PawnCharacterList")
    for _ = 1, 10 do frame(0.02) end
    eq(#R.calls_of("get_PawnCharacterList") - lists, 10, "the pawn list once a frame")
    eq(#R.calls_of("get_ManualPlayer") - players, 10, "the player once a frame")
    eq(M.info().errors, 0, "no error caught")
end)

test("a scene-type change with the player there costs the bars one look, not one for each kind", function()
    world()
    bars_scene()
    local M = load()
    gauge(W.goblin)
    boss_bar(char("ch250000_00", { hostile = true, hp = 40000, max_hp = 90000 }))
    frame()
    frame(1)
    local FIND = "findComponents(System.Type)"
    local function bar_looks() return #R.calls_of(FIND) - (W.hidden_reads[FIND] or 0) end
    local looks, hidden = bar_looks(), W.hidden_reads[FIND] or 0
    scene_change()
    frame()
    eq(bar_looks(), looks + 1, "one look takes the bars over heads, the boss bar and the HUD again")
    eq(W.hidden_reads[FIND] or 0, hidden + 1, "and one for the hidden-stats screens")
    eq(numbers(), "3 053 / 3 700 · 83%|40 000 / 90 000 · 44%", "both drawn again at once")
    eq(M.info().errors, 0, "no error caught")
end)

test("the evidence snapshot waits 1 s after the player character comes back (a load), as after a pause",
        function()
    world({ settings = { debug = true } })
    pause_manager()
    local M = load()
    stat_snapshots()
    frame()
    eq(W.snaps, 1, "the first frame of the mod")
    local player = W.player
    W.player = nil
    for _ = 1, 5 do frame(1) end
    W.player = player
    frame()
    eq(W.snaps, 1, "the frame he is back: none, though the last is 5 s old")
    frame(0.5)
    eq(W.snaps, 1, "0.5 s after: none")
    frame(0.6)
    eq(W.snaps, 2, "1 s after he is back")
    eq(M.info().errors, 0, "no error caught")
end)

test("in the frame the player character comes back the party is read: a pawn's hit right after is the pawn's",
        function()
    world()
    local M = load()
    frame()
    local actors = mod("game/actors")
    eq(actors.of(W.casca).kind, "pawn", "Casca is a pawn")
    -- a load: the player gone at a scene change; the party read without him finds nobody
    local player = W.player
    W.player = nil
    scene_change()
    frame()
    eq(#actors.party(), 0, "no party without him")
    frame(0.1)
    -- he is back, well within the second of the once-a-second party read
    W.player = player
    local reads = #R.calls_of("get_PawnCharacterList")
    frame(0.1)
    eq(#actors.party(), 2, "the party read in that very frame: the player and Casca")
    eq(#R.calls_of("get_PawnCharacterList") > reads, true, "the pawn list read")
    -- Casca's hit before the next frame
    strike()
    local casca = actors.of(W.casca)
    eq(casca.kind, "pawn", "her hit is the pawn's, not «other» or an ally's")
    eq(actors.of(W.player).kind, "player", "and he is the player")
    eq(M.info().errors, 0, "no error caught")
end)

T.finish()
