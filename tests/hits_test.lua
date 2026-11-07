package.path = "mod/reframework/autorun/?.lua;tests/?.lua;" .. package.path

local T = require("testlib")
local test, eq, near = T.test, T.eq, T.near
local R = require("stubs/reframework")
local names_game = require("DD2DamageMeter/game/names_game")
local actors = require("DD2DamageMeter/game/actors")
local enemies = require("DD2DamageMeter/game/enemies")
local Attrib = require("DD2DamageMeter/attrib")
local Fight = require("DD2DamageMeter/fight")
local JournalTabs = require("DD2DamageMeter/journal_tabs")
local Names = require("DD2DamageMeter/names")
local i18n = require("DD2DamageMeter/i18n")
local DamageNumbers = require("DD2DamageMeter/damage_numbers")
local hits = require("DD2DamageMeter/game/hits")

local STATIC = { static = true }
local HC, PDC, EDC, CDC = "app.HitController", "app.PlayerDamageCalculator", "app.ExceptPlayerDamageCalculator",
    "app.CharacterDamageCalculator"
local SIG = {
    damageProc = "damageProc(app.HitController.DamageInfo)",
    defence = "calcDamageValueDefence(app.HitController.DamageInfo)",
    region = "calcRegionDamageRate(app.HitController.DamageInfo)",
    updateDamage = "updateDamage(app.HitController.DamageInfo, System.UInt32, System.Single, System.Boolean)",
    subGuardHp = "subGuardHp(System.Single, app.HitController.DamageInfo)",
    status = "applyStatusDamage(app.HitController.DamageInfo, app.StatusConditionDef.StatusConditionEnum, System.Single)",
}
local ACTIVE = "IsStatusConditionActive(app.StatusConditionDef.StatusConditionEnum, System.Boolean)"
local CAUSED = "getStatusConditionCausedCharacterId(app.StatusConditionDef.StatusConditionEnum)"
local NOBODY = 1857826560    -- getStatusConditionCausedCharacterId out of combat (as read in game)
local ELECTRIC, POISON, FAINT = 13, 1, 3

-- A party as seen in game, with its CharacterIDs, enemies by hostility; every character has a
-- HitController (`hc`), a Human with a CustomSkillState (`human`) and a StatusConditionCtrl whose active statuses
-- are `status[value] = causer chara id`.
local W

local function char(go, o)
    o = o or {}
    local c = R.character{ go = go, hp = o.hp or 1000, max_hp = o.max_hp or 1000, chara_id = o.chara_id }
    W.names[c] = o.name
    c.methods["isHostile(app.Character)"] = function() return o.hostile == true end
    c.hc = R.object(HC, {}, {
        get_Hp = function() return c.hp end,
        get_CachedCharacter = function() return c end,
    })
    c.human = R.object("app.Human", { ["<CustomSkillState>k__BackingField"] = o.state or 0 }, {})
    c.methods.get_Human = function() return c.human end
    c.status = {}
    c.sc = R.object("app.StatusConditionCtrl", {}, {
        [ACTIVE] = function(_, s) return c.status[s] ~= nil end,
        [CAUSED] = function(_, s) return c.status[s] or NOBODY end,
    })
    c.methods.get_StatusConditionCtrl = function() return c.sc end
    return c
end

local function set_state(c, state) c.human.fields["<CustomSkillState>k__BackingField"] = state end

local function world(opts)
    R.new(opts)
    DD2DM_HOOKS = nil            -- a fresh Lua state: nothing hooked yet
    names_game.reset()
    actors.reset()
    hits.reset()
    enemies.reset()
    W = { names = {}, t = 10.0, frame = 600 }
    R.method("app.GUIBase", "getName(app.Character)", function(c) return W.names[c] end, STATIC)
    R.enum("app.HumanCustomSkillID", { None = 0, Job05_CrescentSlash = 52, Job05_IndomitableLash = 58,
        Job03_Firestorm = 24, Job03_GuardBit = 28, Job03_ThunderBoon = 31 })
    R.method(HC, SIG.damageProc, function() return true end)
    R.method(PDC, SIG.defence, function() end)
    R.method(EDC, SIG.defence, function() end)
    R.method(HC, SIG.region, function() end)
    R.method(HC, SIG.updateDamage, function() end)
    R.method(HC, SIG.subGuardHp, function() return false end)
    R.method(CDC, SIG.status, function() end)
    R.type(PDC, CDC)
    R.type(EDC, CDC)

    W.player = char("ch000000_00", { name = "Guts", chara_id = 2891076981, hp = 2245.86, max_hp = 2400 })
    W.casca = char("ch100000_00", { name = "Casca", chara_id = 2283028347 })
    W.godwin = char("ch111007", { name = "Godwin", chara_id = 1188289343 })
    W.yves = char("ch111002", { name = "Yves", chara_id = 112032848 })
    W.pawns = { W.casca, W.godwin, W.yves }
    R.singleton("app.CharacterManager", R.object("app.CharacterManager", {}, {
        get_ManualPlayer = function() return W.player end,
    }))
    R.singleton("app.PawnManager", R.object("app.PawnManager", {}, {
        get_PawnCharacterList = function() return R.list(W.pawns) end,
    }))
    W.goblin = char("ch220003_00_15", { name = "Живодёр", hostile = true, hp = 3053.035, max_hp = 3700 })
    W.chimera = char("ch254000_00_207", { name = "Химера", hostile = true, hp = 80000, max_hp = 80000 })
    W.guard = char("ch300656_00_3", { name = "Форрест", chara_id = 300656 })
    actors.refresh()
    return W
end

-- Everything the adapter hands over.
local function new_sink()
    local s = { hits = {}, touches = {}, statuses = {}, party_hits = {}, party_keys = {}, order = {} }
    s.now = function() return W.t end
    s.frame = function() return W.frame end
    s.hit = function(h)
        s.hits[#s.hits + 1] = h
        s.order[#s.order + 1] = "hit"
    end
    s.touch = function(frame, healer, target_key, ref, t)
        s.touches[#s.touches + 1] = { frame = frame, healer = healer, target_key = target_key, ref = ref, t = t }
    end
    s.status = function(t, victim_key, status, applier)
        s.statuses[#s.statuses + 1] = { t = t, victim_key = victim_key, status = status, applier = applier }
    end
    s.party_hit = function(t, enemy_key)
        s.party_hits[#s.party_hits + 1] = t
        s.party_keys[#s.party_hits] = enemy_key
        s.order[#s.order + 1] = "party_hit"
    end
    return s
end

local function hook(type_name, name)
    local hk = R.hook_of(type_name, name)
    assert(hk, "not hooked: " .. type_name .. "." .. name)
    return hk
end

local function slot(o) return R.obj_slot(o) end

local function aud(name, element)
    return R.object("app.AttackUserData", { _ElementType = element or -1 }, { get_Name = function() return name end })
end

-- A DamageInfo; `o.attacker` hits in melee (its own HitController) or, with `o.shell`, through a shell it owns;
-- `o.element` is what get_ElementType answers (a number or a boxed enum), none: no such method.
local function damage_info(o)
    local fields = {
        ["<DamageHitController>k__BackingField"] = o.victim and (o.victim_hc or o.victim.hc),
        ["<AttackUserData>k__BackingField"] = o.aud,
    }
    if o.attacker and o.shell then
        local shell = R.object("app.Shell", { ["<OwnerCharacter>k__BackingField"] = o.attacker }, {})
        fields["<AttackHitController>k__BackingField"] = R.object(HC, { ["<CachedShell>k__BackingField"] = shell }, {})
    elseif o.attacker then
        fields["<AttackHitController>k__BackingField"] = o.attacker.hc
    end
    local methods = {}
    if o.element ~= nil then methods.get_ElementType = function() return o.element end end
    return R.object("app.HitController.DamageInfo", fields, methods)
end

-- The region step on `di`: `step.before` / `step.after` are the DamageInfo fields around calcRegionDamageRate,
-- `step.no` the RegionStatusNo it leaves behind.
local function region_step(di, hc, step)
    for k, v in pairs(step.before or {}) do di.fields[k] = v end
    R.enter(hook(HC, "calcRegionDamageRate"), { R.CTX, slot(hc), slot(di) })
    for k, v in pairs(step.after or {}) do di.fields[k] = v end
    if step.no ~= nil then di.fields.RegionStatusNo = step.no end
    return R.leave(nil)
end

-- One damageProc in the real call order (the sword hit logged in game): damageProc pre -> defence pre ->
-- defence post -> region pre -> region post -> updateDamage pre -> updateDamage post -> damageProc post.
-- `o.before` / `o.after` are the DamageInfo fields around the defence step, `o.calc` its calculator type (none: no
-- defence step), `o.region` the region step (see region_step; none: no such step), `o.final` the Single of
-- updateDamage (none: no updateDamage), `o.hp1` the victim's HP after it, `o.inside(di)` runs after the region step.
local function run(o)
    local victim = o.victim
    local di = o.di or damage_info(o)
    local hc = o.victim_hc or victim.hc
    R.enter(hook(HC, "damageProc"), { R.CTX, slot(hc), slot(di) })
    if o.calc then
        for k, v in pairs(o.before or {}) do di.fields[k] = v end
        R.enter(hook(o.calc, "calcDamageValueDefence"), { R.CTX, slot(R.object(o.calc)), slot(di) })
        for k, v in pairs(o.after or {}) do di.fields[k] = v end
        R.leave(nil)
    end
    if o.region then region_step(di, hc, o.region) end
    if o.inside then o.inside(di) end
    if o.final then
        R.enter(hook(HC, "updateDamage"), { R.CTX, slot(hc), slot(di), R.int_slot(0xFFFFFFFF), R.f32_slot(o.final),
            R.int_slot(0) })
        if o.hp1 then victim.hp = o.hp1 end
        R.leave(nil)
    end
    return R.leave(o.ret == nil and true or o.ret), di
end

local function sword_hit(extra)
    local o = {
        attacker = W.casca, victim = W.goblin, aud = aud("弱攻撃_ヒットスロー小"), calc = EDC,
        before = { SlashDamage = 479.45 },
        after = { SlashDamage = 339.45, BlowDamage = -140, ShootDamage = -140 },
        final = 405.1336, hp1 = 2647.901,
    }
    for k, v in pairs(extra or {}) do o[k] = v end
    return run(o)
end

local function count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

test("one hit, one event, exact numbers", function()
    world()
    local s = new_sink()
    hits.install(s)
    local ret = sword_hit()
    eq(ret, true, "damageProc's own result is returned")
    eq(#s.hits, 1, "one hit")
    local h = s.hits[1]
    eq(h.t, 10.0, "time from the sink clock")
    eq(h.attacker, actors.of(W.casca), "attacker: the main pawn")
    eq(h.attacker.kind, "pawn", "attacker kind")
    eq(h.victim, actors.of(W.goblin), "victim: the goblin")
    eq(h.victim.kind, "enemy", "victim kind")
    eq(h.skill.attack, "弱攻撃_ヒットスロー小", "attack name")
    eq(h.skill.id, nil, "skill state None: a normal attack")
    near(h.final, 405.1336, 1e-9, "final = the Single of updateDamage")
    near(h.hp0, 3053.035, 1e-9, "hp0 before updateDamage")
    near(h.hp1, 2647.901, 1e-9, "hp1 after updateDamage")
    near(h.before, 479.45, 1e-9, "before defence")
    near(h.after, 339.45, 1e-9, "after defence: negative types count as nothing")
    eq(count(h.types), 1, "one damage type")
    near(h.types.Slash, 339.45, 1e-9, "Slash after defence")
    eq(h.guard, nil, "no guard")
    eq(h.status, nil, "no status")
    eq(h.element, nil, "the game gave no element: none")
    eq(h.region, nil, "no region step: no region")
    eq(#s.party_hits, 1, "a party hit on an enemy")
    eq(s.party_hits[1], 10.0, "party hit time")
    eq(s.party_keys[1], actors.of(W.goblin).key, "party hit: the enemy's key")
    eq(s.order[1], "party_hit", "party_hit comes first, so that a fight can start before the hit")
    eq(s.order[2], "hit", "then the hit")
    eq(#R.bad, 0, "no slot read with the wrong kind")
end)

test("applyStatusDamage called twice does not split the hit", function()
    world()
    local s = new_sink()
    hits.install(s)
    local calc = R.object(EDC)
    sword_hit({ inside = function(di)
        R.fire(hook(CDC, "applyStatusDamage"), { R.CTX, slot(calc), slot(di), R.int_slot(POISON), R.f32_slot(25) })
        R.fire(hook(CDC, "applyStatusDamage"), { R.CTX, slot(calc), slot(di), R.int_slot(FAINT), R.f32_slot(40) })
        R.fire(hook(CDC, "applyStatusDamage"), { R.CTX, slot(calc), slot(di), R.int_slot(ELECTRIC), R.f32_slot(0) })
    end })
    eq(#s.hits, 1, "still one hit")
    near(s.hits[1].final, 405.1336, 1e-9, "with its numbers")
    near(s.hits[1].before, 479.45, 1e-9, "and its defence step")
    -- the poison buildup is a status applied by the attacker; stun buildup and a zero value are not
    eq(#s.statuses, 1, "one status applied")
    local st = s.statuses[1]
    eq(st.status, "Poison", "status name")
    eq(st.applier, actors.of(W.casca), "applier")
    eq(st.victim_key, actors.of(W.goblin).key, "victim")
    eq(st.t, 10.0, "time")
end)

test("no updateDamage means no hit event", function()
    world()
    local s = new_sink()
    hits.install(s)
    eq(run({ attacker = W.yves, shell = true, victim = W.casca, aud = aud("ガードビット"), calc = PDC,
        before = { MagicDamage = 10 }, after = { MagicDamage = 0 } }), true, "retval")
    run({ attacker = W.player, victim = W.goblin, aud = aud("CheckHitSearchDeadBody") })
    eq(#s.hits, 0, "no hit")
    eq(#s.touches, 0, "not a healing touch")
    eq(#s.party_hits, 0, "no party hit")
    -- the next real hit is not mixed up with them
    sword_hit()
    eq(#s.hits, 1, "the real hit")
    near(s.hits[1].before, 479.45, 1e-9, "its own defence step")
end)

test("healing-spot touch goes to the touch sink", function()
    world()
    local s = new_sink()
    hits.install(s)
    W.frame, W.t = 1234, 42.5
    run({ attacker = W.yves, shell = true, victim = W.player, aud = aud("ヒーリングスポット") })
    eq(#s.hits, 0, "a touch is not a hit")
    eq(#s.touches, 1, "one touch")
    local touch = s.touches[1]
    eq(touch.frame, 1234, "frame from the sink")
    eq(touch.t, 42.5, "time from the sink: a heal can go on after the last touch")
    eq(touch.healer, actors.of(W.yves), "healer: the shell's owner")
    eq(touch.target_key, actors.of(W.player).key, "target")
    eq(touch.ref.attack, "ヒーリングスポット", "the heal area's attack name")
    eq(#s.party_hits, 0, "a touch starts no fight")
    -- the touch sink plugs into Attrib
    local attrib = Attrib.new()
    s.touch = function(...) attrib:touch(...) end
    run({ attacker = W.yves, shell = true, victim = W.casca, aud = aud("ヒーリングスポット") })
    eq(attrib:healer_for(1235, actors.of(W.casca).key), actors.of(W.yves), "Attrib finds the healer")
    eq(attrib:healer_for(1400, actors.of(W.casca).key, 46.5), actors.of(W.yves), "and 4 s later too")
end)

test("nested damageProc keeps two contexts", function()
    world()
    local s = new_sink()
    hits.install(s)
    local outer = damage_info({ attacker = W.player, victim = W.goblin, aud = aud("N_軽") })
    local inner = damage_info({ attacker = W.yves, shell = true, victim = W.chimera, aud = aud("ラピッドショット") })
    R.enter(hook(HC, "damageProc"), { R.CTX, slot(W.goblin.hc), slot(outer) })
    outer.fields.SlashDamage = 600
    R.enter(hook(EDC, "calcDamageValueDefence"), { R.CTX, slot(R.object(EDC)), slot(outer) })
    outer.fields.SlashDamage = 450
    R.leave(nil)
    -- a second hit runs inside the first one
    R.enter(hook(HC, "damageProc"), { R.CTX, slot(W.chimera.hc), slot(inner) })
    inner.fields.MagicDamage = 200
    R.enter(hook(EDC, "calcDamageValueDefence"), { R.CTX, slot(R.object(EDC)), slot(inner) })
    inner.fields.MagicDamage = 150
    R.leave(nil)
    R.enter(hook(HC, "updateDamage"), { R.CTX, slot(W.chimera.hc), slot(inner), R.int_slot(0), R.f32_slot(115.5),
        R.int_slot(0) })
    W.chimera.hp = 80000 - 115.5
    R.leave(nil)
    eq(R.leave(true), true, "inner retval")
    eq(#s.hits, 1, "the inner hit is done first")
    -- back in the first hit
    R.enter(hook(HC, "updateDamage"), { R.CTX, slot(W.goblin.hc), slot(outer), R.int_slot(0), R.f32_slot(346.5),
        R.int_slot(0) })
    W.goblin.hp = 3053.035 - 346.5
    R.leave(nil)
    eq(R.leave(false), false, "outer retval")
    eq(#s.hits, 2, "two hits")
    local a, b = s.hits[1], s.hits[2]
    eq(a.victim, actors.of(W.chimera), "inner victim")
    eq(a.attacker, actors.of(W.yves), "inner attacker")
    near(a.final, 115.5, 1e-9, "inner final"); near(a.before, 200, 1e-9, "inner before"); near(a.after, 150, 1e-9)
    near(a.types.Magic, 150, 1e-9, "inner type")
    eq(b.victim, actors.of(W.goblin), "outer victim")
    eq(b.attacker, actors.of(W.player), "outer attacker")
    near(b.final, 346.5, 1e-9, "outer final"); near(b.before, 600, 1e-9, "outer before"); near(b.after, 450, 1e-9)
    near(b.hp0, 3053.035, 1e-9, "outer hp0"); near(b.hp1, 3053.035 - 346.5, 1e-9, "outer hp1")
    eq(b.types.Magic, nil, "no type leaked from the inner hit")
end)

test("post-hooks return retval and never raise", function()
    world()
    local s = new_sink()
    s.hit = function() error("sink broken") end
    s.party_hit = function() error("clock broken") end
    s.touch = function() error("attrib broken") end
    s.status = function() error("attrib broken") end
    hits.install(s)
    eq(sword_hit({ ret = "RET" }), "RET", "retval with a failing sink")
    eq(run({ attacker = W.yves, shell = true, victim = W.player, aud = aud("ヒーリングスポット"), ret = 0 }), 0,
        "touch with a failing sink")
    -- every hook, fed garbage, still hands back the retval and lets the original run
    for _, hk in ipairs(R.hooks) do
        for _, args in ipairs({ { R.CTX }, {}, { R.CTX, R.int_slot(1), R.int_slot(2), R.f32_slot(3), R.int_slot(4),
            R.int_slot(5) }, { R.CTX, R.null_slot(), R.null_slot(), R.null_slot(), R.null_slot(), R.null_slot() } }) do
            local pre_ret = "unset"
            R.enter({ pre = function(a) pre_ret = hk.pre(a) end, post = function(r) return hk.post(r) end }, args)
            eq(R.leave("x"), "x", hk.m.sig .. " retval")
            eq(pre_ret, nil, hk.m.sig .. ": the pre-hook never asks to skip the original")
        end
    end
    -- a game object that raises in the middle of a hit
    local di = damage_info({ attacker = W.casca, victim = W.goblin, aud = aud("N_軽") })
    di.poison = true
    eq(run({ di = di, victim = W.goblin, calc = EDC, final = 10, hp1 = 3000 }), true, "poisoned DamageInfo")
    -- no storage at all (thread.get_hook_storage() nil), or a REFramework API that raises
    local saved = thread.get_hook_storage
    thread.get_hook_storage = function() return nil end
    eq(sword_hit({ ret = 5 }), 5, "no hook storage")
    thread.get_hook_storage = function() error("no thread API") end
    eq(sword_hit({ ret = 6 }), 6, "the hook storage call raises")
    thread.get_hook_storage = saved
    -- hooks that run after a failure keep working; a broken party_hit costs only itself
    s.hit = function(h) s.hits[#s.hits + 1] = h end
    sword_hit()
    eq(#s.hits, 1, "the next hit arrives although party_hit still fails")
    eq(hits.info().errors > 0, true, "the failures were counted")
end)

test("a handler failing on every call is reported a few times only", function()
    world()
    local Hook = require("DD2DamageMeter/game/hook")
    local reports = {}
    Hook.on_error(function(where, err, n) reports[#reports + 1] = n end)
    local s = new_sink()
    s.hit = function() error("sink broken") end
    hits.install(s)
    for _ = 1, 2500 do sword_hit() end
    eq(hits.info().errors >= 2500, true, "every failure counted")
    eq(#reports, 12, "the first 10, then the 1000th and the 2000th")
    eq(reports[11], 1000, "count passed along")
    Hook.on_error(nil)
end)

test("hook count within budget", function()
    world()
    local n, missing = hits.install(new_sink())
    eq(n, 7, "damageProc, two defence steps, the region step, updateDamage, subGuardHp, applyStatusDamage")
    assert(n <= 9, "hits budget")
    eq(#missing, 0, "nothing missing")
    eq(#R.hooks, 7, "seven sdk.hook calls")

    -- a reload: no second hook, the new sink gets the events, the old one nothing
    local old = new_sink()
    world()
    hits.install(old)
    local fresh = new_sink()
    n = hits.install(fresh)
    eq(n, 7, "count after a reload")
    eq(#R.hooks, 7, "no hook installed twice")
    sword_hit()
    eq(#old.hits, 0, "old handlers replaced")
    eq(#fresh.hits, 1, "new handlers called")

    -- an older game build without some of the methods
    R.new()
    DD2DM_HOOKS = nil
    R.method(HC, SIG.damageProc, function() return true end)
    R.method(HC, SIG.updateDamage, function() end)
    n, missing = hits.install(new_sink())
    eq(n, 2, "only what exists is hooked")
    eq(#missing, 5, "the rest is reported")
    local text = table.concat(missing, " ")
    assert(text:find("app.HitController.subGuardHp", 1, true), "missing names the method: " .. text)
end)

test("a method found only on a parent type is not hooked", function()
    world()
    -- a game update dropped the player calculator's own defence step: get_method would find the parent's
    R.undeclare(PDC)
    R.type(PDC, CDC)
    R.method(CDC, SIG.defence, function() end)
    DD2DM_HOOKS = nil
    local n, missing = hits.install(new_sink())
    eq(n, 6, "the inherited method is left alone")
    eq(R.hook_of(CDC, "calcDamageValueDefence"), nil, "the parent's method is not hooked")
    assert(table.concat(missing, " "):find(PDC, 1, true), "and reported missing")
    -- and the refusal reaches the error report (the debug log)
    local info = hits.info()
    eq(info.errors, 1, "one refusal counted")
    assert(info.last_error:find("hook refused " .. PDC .. "." .. SIG.defence, 1, true), info.last_error)
    assert(info.last_error:find("declared by " .. CDC, 1, true), info.last_error)
end)

test("skill: the attacker's skill state at hit time", function()
    world()
    local s = new_sink()
    hits.install(s)
    set_state(W.player, 58)
    run({ attacker = W.player, victim = W.goblin, aud = aud("CSLv2_09_魔人斬り_溜_1_極"), final = 900, hp1 = 2000 })
    eq(s.hits[1].skill.id, "Job05_IndomitableLash", "the state's enum name")
    eq(s.hits[1].skill.attack, "CSLv2_09_魔人斬り_溜_1_極", "and the attack name")
    eq(s.hits[1].skill.normal, nil, "a skill is no normal attack")
    set_state(W.player, 0)
    run({ attacker = W.player, victim = W.goblin, aud = aud("N_軽"), final = 100, hp1 = 1900 })
    eq(s.hits[2].skill.id, nil, "None: no skill id")
    eq(s.hits[2].skill.normal, true, "None: a normal attack, said by the game")
    eq(s.hits[2].skill.attack, "N_軽", "attack name")
    -- a core skill's attack name that looks like nothing in particular: still the state None
    run({ attacker = W.player, victim = W.goblin, aud = aud("刀牙昇斬_上昇"), final = 100, hp1 = 1850 })
    eq(s.hits[3].skill.normal, true, "a core skill is a normal attack")
    -- a state the enum does not know is not invented, and not called a normal attack either
    set_state(W.player, 777)
    run({ attacker = W.player, victim = W.goblin, aud = aud("N_軽"), final = 100, hp1 = 1800 })
    eq(s.hits[4].skill.id, nil, "unknown state value")
    eq(s.hits[4].skill.normal, nil, "unknown state: not normal")
    -- no AttackUserData: nothing said about the skill
    run({ attacker = W.player, victim = W.goblin, final = 100, hp1 = 1700 })
    eq(s.hits[5].skill.normal, nil, "no attack: not normal")
    eq(s.hits[5].skill.id, nil, "no attack: no id")
end)

test("skill: the state is named from the game's enum containers", function()
    world({ containers = true })
    local s = new_sink()
    hits.install(s)
    set_state(W.player, 58)
    run({ attacker = W.player, victim = W.goblin, aud = aud("CS_09_魔人斬り"), final = 900, hp1 = 2000 })
    eq(s.hits[1].skill.id, "Job05_IndomitableLash", "the state's enum name")
end)

-- The attacker's vocation and equipped skills (app.Human: JobContext.CurrentJob, SkillContext.hasEquipedSkill).
local EQUIPPED = "hasEquipedSkill(app.Character.JobEnum, app.HumanCustomSkillID)"
local function vocation(c, job, equipped)
    local jc = R.object("app.JobContext", { CurrentJob = job }, {})
    local sc = R.object("app.HumanSkillContext", {}, {
        [EQUIPPED] = function(_, j, id) return j == job and equipped[id] == true end,
    })
    c.human.methods.get_JobContext = function() return jc end
    c.human.fields["<SkillContext>k__BackingField"] = sc
end

-- The game's skill table (app.GuiManager.CustomSkillDefineDictionary): id -> its level-1 message and the Japanese
-- text of that message.
local function skill_table(list)
    local function dictionary(get)
        return R.object("System.Collections.Generic.Dictionary`2", {}, {
            ContainsKey = function(_, k) return get(k) ~= nil end,
            get_Item = function(_, k) return get(k) end,
        })
    end
    R.singleton("app.GuiManager", R.object("app.GuiManager", { CustomSkillDefineDictionary = dictionary(function(id)
        local e = list[id]
        return e and dictionary(function(level)
            return level == 1 and R.object("app.CustomSkillInformationParam", { _SkillName = { guid = e[1] } }, {}) or nil
        end)
    end) }, {}))
    local ja = {}
    for _, e in pairs(list) do ja[e[1]] = e[2] end
    R.method("via.gui.message", "getName(System.Guid)", function(guid) return guid.guid end, STATIC)
    R.method("via.gui.message", "get(System.Guid, via.Language)", function(guid, lang)
        return lang == 0 and ja[guid.guid] or nil
    end, STATIC)
end

-- The thief's, the warrior's and some of the mage's skills, so that CS_NN finds the NN-th, and their table entries.
local function vocation_skills()
    R.enum("app.HumanCustomSkillID", { None = 0, Job04_CuttingWind = 38, Job04_Guillotine = 39, Job04_Attract = 40,
        Job04_ParryCounter = 41, Job04_AbsoluteAvoidance = 42, Job04_HollowOut = 43,
        Job05_HeavyRunningThrust = 50, Job05_HorizontalSlash = 51, Job05_CrescentSlash = 52, Job05_CycloneSlash = 53,
        Job05_GroundDrill = 54, Job05_CounterAttack = 55, Job05_WarCry = 56, Job05_LandSlide = 57,
        Job05_IndomitableLash = 58, Job03_Firestorm = 24, Job03_Frigor = 26, Job03_GuardBit = 28 })
    skill_table({
        [40] = { "job04_skill_02", "引き寄せ" }, [42] = { "job04_skill_04", "虚心の極み" },
        [43] = { "job04_skill_05", "えぐり抜き" }, [52] = { "job05_skill_02", "蒼天斬り" },
        [58] = { "job05_skill_08", "魔人斬り" }, [26] = { "job03_skill_01", "フロストスパイク" },
        [28] = { "job03_skill_06", "エスコートアニマ" },
    })
    names_game.reset()
end

test("skill: a skill attack the state did not name is found by its name, when it is equipped", function()
    world()
    vocation_skills()
    local s = new_sink()
    hits.install(s)
    vocation(W.godwin, 4, { [43] = true })
    set_state(W.godwin, 0)
    run({ attacker = W.godwin, victim = W.goblin, aud = aud("CS_06_抉り抜き_1_押"), final = 300, hp1 = 2700 })
    eq(s.hits[1].skill.id, "Job04_HollowOut", "the thief's 6th skill")
    eq(s.hits[1].skill.normal, nil, "no normal attack")
    eq(s.hits[1].skill.attack, "CS_06_抉り抜き_1_押", "the attack name stays")
    -- a state the enum cannot name
    set_state(W.godwin, 777)
    run({ attacker = W.godwin, victim = W.goblin, aud = aud("CS_06_抉り抜き_2_押"), final = 300, hp1 = 2400 })
    eq(s.hits[2].skill.id, "Job04_HollowOut", "unknown state")
    -- a CS number never overrides a state that names a skill
    set_state(W.godwin, 42)
    vocation(W.godwin, 4, { [42] = true, [43] = true })
    run({ attacker = W.godwin, victim = W.goblin, aud = aud("CS_06_抉り抜き_2_押"), final = 300, hp1 = 2100 })
    eq(s.hits[3].skill.id, "Job04_AbsoluteAvoidance", "the state")
end)

test("skill: no skill by name when it is not equipped, for an enemy, or for a normal attack", function()
    world()
    vocation_skills()
    local s = new_sink()
    hits.install(s)
    vocation(W.godwin, 4, { [40] = true })
    set_state(W.godwin, 0)
    run({ attacker = W.godwin, victim = W.goblin, aud = aud("CS_06_抉り抜き_1_押"), final = 300, hp1 = 2700 })
    eq(s.hits[1].skill.id, nil, "not equipped")
    eq(s.hits[1].skill.normal, true, "the state None stands")
    -- an enemy whose attack is named like a skill (a hobgoblin's 一閃突き): no vocation
    run({ attacker = W.goblin, victim = W.godwin, aud = aud("CS_06_x"), final = 10, hp1 = 990 })
    eq(s.hits[2].skill.id, nil, "enemy")
    vocation(W.player, 5, { [58] = true })
    set_state(W.player, 0)
    run({ attacker = W.player, victim = W.goblin, aud = aud("N_軽"), final = 100, hp1 = 2600 })
    eq(s.hits[3].skill.id, nil, "normal attack")
    eq(s.hits[3].skill.normal, true, "still normal")
    eq(#R.calls_of(EQUIPPED), 1, "only a name that points at a skill asks the game")
end)

test("skill: an exact Japanese name overrides a state or a shell majority that names another skill", function()
    world()
    vocation_skills()
    local s = new_sink()
    hits.install(s)
    vocation(W.yves, 3, { [26] = true, [28] = true })
    set_state(W.yves, 28)
    for i = 1, 3 do
        run({ attacker = W.yves, shell = true, victim = W.chimera, aud = aud("フロストスパイク_奥"), final = 10,
            hp1 = 80000 - 10 * i })
        eq(s.hits[i].skill.id, "Job03_Frigor", "the frost spike, tick " .. i)
    end
    vocation(W.casca, 5, { [52] = true, [58] = true })
    set_state(W.casca, 52)
    run({ attacker = W.casca, victim = W.goblin, aud = aud("魔人斬り_溜_1"), final = 100, hp1 = 2900 })
    eq(s.hits[4].skill.id, "Job05_IndomitableLash", "melee, the state said another skill")
    -- not equipped: the state stands
    vocation(W.casca, 5, { [52] = true })
    run({ attacker = W.casca, victim = W.goblin, aud = aud("魔人斬り_溜_1"), final = 100, hp1 = 2800 })
    eq(s.hits[5].skill.id, "Job05_CrescentSlash", "not equipped")
    -- the name and the state agree: nothing to ask
    local asked = #R.calls_of(EQUIPPED)
    set_state(W.casca, 58)
    run({ attacker = W.casca, victim = W.goblin, aud = aud("魔人斬り_溜_1"), final = 100, hp1 = 2700 })
    eq(s.hits[6].skill.id, "Job05_IndomitableLash", "agree")
    eq(#R.calls_of(EQUIPPED), asked, "no equipment check")
end)

-- The Warrior's skills in value order with the newer two last (Job05_DashSlashUp 110, Job05_ScarletVow 111, whose
-- messages end in _TU), so that CS_13 and CS_14 find them.
local function warrior_skills()
    R.enum("app.HumanCustomSkillID", { None = 0, Job05_HeavyRunningThrust = 50, Job05_HorizontalSlash = 51,
        Job05_CrescentSlash = 52, Job05_CycloneSlash = 53, Job05_GroundDrill = 54, Job05_CounterAttack = 55,
        Job05_WarCry = 56, Job05_LandSlide = 57, Job05_IndomitableLash = 58, Job05_Guts = 59, Job05_Springboard = 60,
        Job05_ArcOfObliteration = 61, Job05_DashSlashUp = 110, Job05_ScarletVow = 111 })
    skill_table({
        [52] = { "job05_skill_02", "蒼天斬り" }, [58] = { "job05_skill_08", "魔人斬り" },
        [110] = { "job05_skill_04_TU", "剛流斬り" }, [111] = { "job05_skill_05_TU", "血染の契り" },
    })
    names_game.reset()
end

test("skill: a newer skill's CS number names an unnamed hit when equipped, never over another state", function()
    world()
    warrior_skills()
    local s = new_sink()
    hits.install(s)
    vocation(W.player, 5, { [111] = true })
    set_state(W.player, 0)
    run({ attacker = W.player, victim = W.goblin, aud = aud("CS_14_緋染_N軽攻撃"), final = 300, hp1 = 2700 })
    eq(s.hits[1].skill.id, "Job05_ScarletVow", "Blood Pact, equipped")
    eq(s.hits[1].skill.normal, nil, "no normal attack")
    eq(s.hits[1].skill.attack, "CS_14_緋染_N軽攻撃", "the attack name stays")
    local asked = R.calls_of(EQUIPPED)
    eq(#asked, 1, "the game asked once")
    eq(asked[1].args[1], 5, "for the Warrior")
    eq(asked[1].args[2], 111, "and Blood Pact")
    -- not equipped: the state None stands
    vocation(W.player, 5, { [58] = true, [110] = true })
    run({ attacker = W.player, victim = W.goblin, aud = aud("CS_14_緋染の契り_BM発動"), final = 300, hp1 = 2400 })
    eq(s.hits[2].skill.id, nil, "not equipped")
    eq(s.hits[2].skill.normal, true, "the state None stands")
    -- a state the enum cannot name is no name either
    vocation(W.player, 5, { [58] = true, [111] = true })
    set_state(W.player, 777)
    run({ attacker = W.player, victim = W.goblin, aud = aud("CS_14_緋染の契り_BM発動"), final = 300, hp1 = 2100 })
    eq(s.hits[3].skill.id, "Job05_ScarletVow", "unknown state")
    -- a state that names another skill stands, as for an older skill's number; the game is not even asked
    set_state(W.player, 58)
    local before = #R.calls_of(EQUIPPED)
    run({ attacker = W.player, victim = W.goblin, aud = aud("CS_14_緋染_N軽攻撃"), final = 300, hp1 = 1800 })
    eq(s.hits[4].skill.id, "Job05_IndomitableLash", "the state, though Blood Pact is equipped")
    eq(#R.calls_of(EQUIPPED), before, "no equipment check")
    -- Iron Cleave, the 13th: equipped or not
    set_state(W.player, 0)
    vocation(W.player, 5, { [58] = true, [110] = true })
    run({ attacker = W.player, victim = W.goblin, aud = aud("CS_13_地流駆け_EX_1"), final = 300, hp1 = 1500 })
    eq(s.hits[5].skill.id, "Job05_DashSlashUp", "Iron Cleave equipped")
    vocation(W.player, 5, { [58] = true })
    run({ attacker = W.player, victim = W.goblin, aud = aud("CS_13_地流駆け_EX_1"), final = 300, hp1 = 1200 })
    eq(s.hits[6].skill.id, nil, "Iron Cleave not equipped")
    eq(s.hits[6].skill.normal, true, "the state None stands")
end)

test("skill: no name lookup for an enemy or a hit without an attacker; one get_Human per hit", function()
    world()
    vocation_skills()
    local s = new_sink()
    hits.install(s)
    -- a human enemy with a vocation and the skill equipped
    vocation(W.goblin, 4, { [43] = true })
    run({ attacker = W.goblin, victim = W.godwin, aud = aud("CS_06_抉り抜き_1_押"), final = 10, hp1 = 990 })
    eq(s.hits[1].skill.id, nil, "enemy")
    run({ victim = W.goblin, aud = aud("CS_06_抉り抜き_1_押"), final = 10, hp1 = 2990 })
    eq(s.hits[2].skill.id, nil, "no attacker")
    eq(#R.calls_of("get_JobContext"), 0, "the vocation was never read")
    vocation(W.godwin, 4, { [43] = true })
    local function human_calls()
        local n = 0
        for _, c in ipairs(R.calls_of("get_Human")) do
            if c.this == W.godwin then n = n + 1 end
        end
        return n
    end
    local before = human_calls()
    run({ attacker = W.godwin, victim = W.goblin, aud = aud("CS_06_抉り抜き_1_押"), final = 300, hp1 = 2600 })
    eq(s.hits[3].skill.id, "Job04_HollowOut", "the party's hit is named")
    eq(human_calls() - before, 1, "the state read and the name lookup share one get_Human")
end)

test("skill: a shell whose majority state is None is its skill when its name says so", function()
    world()
    vocation_skills()
    local s = new_sink()
    hits.install(s)
    vocation(W.casca, 5, { [58] = true })
    set_state(W.casca, 0)
    run({ attacker = W.casca, shell = true, victim = W.goblin, aud = aud("CSLv2_09_魔人斬り_溜_1"), final = 50,
        hp1 = 2900 })
    eq(s.hits[1].skill.id, "Job05_IndomitableLash", "named by the attack")
    eq(s.hits[1].skill.normal, nil, "no normal attack")
end)

test("skill: without the skill enum only the state None is known", function()
    world()
    R.undeclare("app.HumanCustomSkillID")
    names_game.reset()
    local s = new_sink()
    hits.install(s)
    set_state(W.player, 58)
    run({ attacker = W.player, victim = W.goblin, aud = aud("x"), final = 100, hp1 = 2900 })
    eq(s.hits[1].skill.id, nil, "no name for the state")
    eq(s.hits[1].skill.normal, nil, "a state that is not None is no normal attack")
    set_state(W.yves, 24)
    for i = 1, 3 do
        run({ attacker = W.yves, shell = true, victim = W.chimera, aud = aud("ファイヤーストーム_Lv.2"), final = 10,
            hp1 = 80000 - 10 * i })
    end
    eq(s.hits[4].skill.normal, nil, "a shell whose state cannot be named: not normal")
    set_state(W.player, 0)
    run({ attacker = W.player, victim = W.goblin, aud = aud("x"), final = 100, hp1 = 2800 })
    eq(s.hits[5].skill.normal, true, "None needs no enum")
end)

test("skill: a shell hit uses the state learned for its attack name", function()
    world()
    local s = new_sink()
    hits.install(s)
    local function tick(state)
        set_state(W.yves, state)
        run({ attacker = W.yves, shell = true, victim = W.chimera, aud = aud("ファイヤーストーム_Lv.2"), element = 1,
            final = 300, hp1 = W.chimera.hp - 300 })
        return s.hits[#s.hits]
    end
    eq(tick(24).skill.id, "Job03_Firestorm", "first tick")
    tick(24)
    -- Yves has moved on while the flames last: the majority state of this attack wins
    eq(tick(28).skill.id, "Job03_Firestorm", "late tick during another skill")
    local late = tick(0)
    eq(late.skill.id, "Job03_Firestorm", "late tick after the skill")
    eq(late.skill.normal, nil, "the skill's late tick is no normal attack")
    eq(tick(31).skill.id, "Job03_Firestorm", "still the majority")
    eq(s.hits[#s.hits].element, "Fire", "element of the attack")
    -- a shell attack seen only without a state is the mage's normal bolt
    set_state(W.yves, 0)
    run({ attacker = W.yves, shell = true, victim = W.chimera, aud = aud("ラピッドショット"), final = 50, hp1 = 70000 })
    local h = s.hits[#s.hits]
    eq(h.skill.id, nil, "no skill learned")
    eq(h.skill.normal, true, "the majority is None: a normal attack")
    eq(h.skill.attack, "ラピッドショット", "the attack name is the key")
    -- the normal bolt once fired during Thunder Boon: its hits without a state outvote that one
    local function bolt(state)
        set_state(W.yves, state)
        run({ attacker = W.yves, shell = true, victim = W.chimera, aud = aud("ラピッドショット"), final = 50,
            hp1 = W.chimera.hp - 50 })
        return s.hits[#s.hits].skill
    end
    bolt(0)
    local during = bolt(31)
    eq(during.id, nil, "one sighting during a skill does not make it that skill")
    eq(during.normal, true, "it stays a normal attack")
    eq(bolt(0).normal, true, "normal attack")
    -- reset forgets what was learned
    hits.reset()
    local fresh = tick(0)
    eq(fresh.skill.id, nil, "forgotten")
    eq(fresh.skill.normal, true, "a first sighting without a state: normal until a skill outvotes it")
end)

-- Maya, a Sorcerer pawn (vocation 6) in Godwin's party slot, and Yves the Mage (vocation 3); the skill enum knows
-- their spells (the Sorcerer's Levin and Firestorm are Job03 ids, as in game), the skill table the Sorcerer's Japanese
-- names. `equipped` is Maya's equipment, by default Firestorm, Levin, Blizzard, Meteor and Vortex.
local function sorcerer(equipped)
    R.enum("app.HumanCustomSkillID", { None = 0, Job03_Firestorm = 24, Job03_Levin = 25, Job03_Frigor = 26,
        Job03_SpellStock = 27, Job03_GuardBit = 28, Job03_ThunderBoon = 31, Job06_Blizzard = 64, Job06_RockBeat = 67,
        Job06_MeteorFall = 68, Job06_VortexRage = 69 })
    skill_table({ [64] = { "job06_skill_04", "ブリザードガイザー" }, [67] = { "job06_skill_07", "ロックビート" },
        [68] = { "job06_skill_10", "メテオフォール" }, [69] = { "job06_skill_11", "ヴォルテクスレイジ" } })
    names_game.reset()
    W.maya = char("ch111010", { name = "Maya", chara_id = 52011 })
    W.pawns = { W.casca, W.maya, W.yves }
    actors.refresh()
    vocation(W.maya, 6, equipped or { [24] = true, [25] = true, [64] = true, [68] = true, [69] = true })
    vocation(W.yves, 3, { [24] = true, [25] = true, [26] = true })
    return W.maya
end

-- Meteor's attack names in game: the cast, the rocks' impact and their graze.
local CAST, IMPACT, GRAZE = "メテオフォール", "メテオフォール着弾_対ノルド敵", "メテオフォール着弾_対ノルド敵_カスアタリ"

-- One hit of `c` on the chimera at time `t` in the skill state `state`, a shell unless o.shell == false, taking o.taken
-- HP (default 100); gives the hit's skill.
local function spell(s, c, t, state, attack, o)
    o = o or {}
    W.t = t
    set_state(c, state)
    local taken = o.taken or 100
    run({ attacker = c, shell = o.shell ~= false, victim = W.chimera, aud = aud(attack), final = taken,
        hp1 = W.chimera.hp - taken })
    return s.hits[#s.hits].skill
end

test("skill: Meteor's rocks landing during Levin are Meteor's by their name, when Meteor is equipped", function()
    world()
    local maya = sorcerer()
    local s = new_sink()
    hits.install(s)
    eq(spell(s, maya, 0, 68, CAST, { shell = false, taken = 0 }).id, "Job06_MeteorFall", "the cast")
    -- she casts Levin while the rocks fall: their own votes say Levin
    for t = 1, 4 do
        eq(spell(s, maya, t, 25, "サンダーレイン").id, "Job03_Levin", "Levin, t " .. t)
        local rock = spell(s, maya, t, 25, IMPACT, { taken = 2000 })
        eq(rock.id, "Job06_MeteorFall", "an impact during Levin, t " .. t)
        eq(rock.normal, nil, "no normal attack, t " .. t)
        eq(rock.attack, IMPACT, "its own attack name")
    end
    eq(spell(s, maya, 5, 25, GRAZE).id, "Job06_MeteorFall", "a graze during Levin")
    local late = spell(s, maya, 6, 0, IMPACT)
    eq(late.id, "Job06_MeteorFall", "an impact in None")
    eq(late.normal, nil, "no normal attack")
    eq(hits.info().errors, 0, "nothing raised")
end)

test("skill: Meteor's rocks without Meteor equipped keep what the votes say", function()
    world()
    local maya = sorcerer({ [24] = true, [25] = true })
    local s = new_sink()
    hits.install(s)
    for t = 1, 3 do eq(spell(s, maya, t, 25, IMPACT).id, "Job03_Levin", "the votes say Levin, t " .. t) end
    eq(spell(s, maya, 4, 0, IMPACT).id, "Job03_Levin", "an impact in None: still the majority")
    local graze = spell(s, maya, 5, 0, GRAZE)
    eq(graze.id, nil, "a graze first seen in None: no skill")
    eq(graze.normal, true, "its vote: a normal attack")
end)

test("skill: Blizzard's shells landing in another spell's state are Blizzard's", function()
    world()
    local maya = sorcerer()
    local s = new_sink()
    hits.install(s)
    eq(spell(s, maya, 0, 24, "ファイヤーストーム_Lv.2").id, "Job03_Firestorm", "Firestorm")
    for i, attack in ipairs({ "ブリザードLv.2_右奥", "ブリザードLv.2_左奥", "ブリザードLv.2_左手前" }) do
        eq(spell(s, maya, i, 24, attack).id, "Job06_Blizzard", attack .. " in Firestorm's state")
    end
    eq(spell(s, maya, 4, 69, "ブリザードLv.2_左手前").id, "Job06_Blizzard", "in Vortex's state")
    eq(spell(s, maya, 5, 64, "ファイヤーストーム_Lv.2").id, "Job03_Firestorm", "Firestorm's own shell stays")
end)

test("skill: a bolt fired just after a skill, landing in None, is a normal attack", function()
    world()
    local maya = sorcerer()
    local s = new_sink()
    hits.install(s)
    for t = 0, 4 do eq(spell(s, maya, t, 0, "ラピッドショット").normal, true, "bolt at t " .. t) end
    eq(spell(s, maya, 10, 24, "ファイヤーストーム_Lv.2").id, "Job03_Firestorm", "a skill")
    local bolt = spell(s, maya, 12, 0, "ラピッドショット")
    eq(bolt.id, nil, "2 s after the skill: no skill")
    eq(bolt.normal, true, "still a normal attack")
    -- a bolt name first seen just after a skill is a normal attack too
    local first = spell(s, maya, 12, 0, "バーストショット")
    eq(first.id, nil, "first seen 2 s after a skill: no skill")
    eq(first.normal, true, "a normal attack")
    eq(spell(s, maya, 12.5, 0, "バーストショット_追撃").normal, true, "its follow-up too")
end)

test("skill: a Mage's state does not change the Sorcerer's votes for the same attack name", function()
    world()
    local maya = sorcerer()
    local s = new_sink()
    hits.install(s)
    for t = 0, 2 do eq(spell(s, W.yves, t, 25, "サンダーレイン").id, "Job03_Levin", "the Mage's Levin, t " .. t) end
    -- the Sorcerer's spell of that name, in None just after the Mage's Levin
    local hers = spell(s, maya, 3, 0, "サンダーレイン")
    eq(hers.id, nil, "the Mage's state is not the Sorcerer's")
    eq(hers.normal, true, "her own vote: None")
    for t = 20, 23 do spell(s, maya, t, 0, "サンダーレイン") end
    -- nor do her votes outvote his
    local his = spell(s, W.yves, 40, 0, "サンダーレイン")
    eq(his.id, "Job03_Levin", "the Mage's majority stands")
    eq(hits.info().learned, 2, "one entry per attacker and attack name")
end)

test("skill: attackers without an actor are told apart by their human", function()
    world()
    local s = new_sink()
    hits.install(s)
    local a, b = char("ch300100_00_1", { name = "A" }), char("ch300100_00_2", { name = "B" })
    a.addr, b.addr = nil, nil   -- the characters' addresses cannot be read: no actor
    eq(spell(s, a, 0, 24, "火球").id, "Job03_Firestorm", "a's skill")
    eq(s.hits[#s.hits].attacker, nil, "no actor")
    local other = spell(s, b, 1, 0, "火球")
    eq(other.id, nil, "b's shell of that name: not a's votes")
    eq(other.normal, true, "b's own vote: None")
    eq(spell(s, a, 2, 0, "火球").id, "Job03_Firestorm", "a's own majority stands")
end)

test("skill: Firestorm burning on while the Mage casts Levin stays Firestorm", function()
    world()
    sorcerer()
    local s = new_sink()
    hits.install(s)
    local function flame(t, state) return spell(s, W.yves, t, state, "ファイヤーストーム_Lv.2") end
    for t = 0, 2 do eq(flame(t, 24).id, "Job03_Firestorm", "during the cast, t " .. t) end
    eq(flame(3, 0).id, "Job03_Firestorm", "after the cast")
    eq(spell(s, W.yves, 4, 25, "サンダーレイン").id, "Job03_Levin", "Levin")
    eq(flame(4, 25).id, "Job03_Firestorm", "a flame during Levin")
    local after = flame(5, 0)
    eq(after.id, "Job03_Firestorm", "a flame after Levin")
    eq(after.normal, nil, "no normal attack")
end)

test("skill: Meteor's rocks are in the Skills tab's Meteor row, not in Levin's or normal attacks", function()
    world()
    local maya = sorcerer()
    local fight = Fight.new(0)
    local s = new_sink()
    local keep = s.hit
    s.hit = function(h)
        keep(h)
        fight:add_hit(h)
    end
    hits.install(s)
    for t = 0, 3 do spell(s, maya, t, 0, "ラピッドショット") end
    spell(s, maya, 10, 68, CAST, { shell = false, taken = 0 })
    -- the rocks land while she casts Levin, the last one after it
    for t = 11, 14 do
        spell(s, maya, t, 25, "サンダーレイン")
        spell(s, maya, t, 25, IMPACT, { taken = 2000 })
    end
    spell(s, maya, 15, 25, GRAZE, { taken = 500 })
    spell(s, maya, 16, 0, IMPACT, { taken = 1500 })
    for t = 40, 41 do spell(s, maya, t, 0, "ラピッドショット") end
    i18n.set("ru")
    local SKILL = { Job06_MeteorFall = "Метеор", Job03_Levin = "Молния" }
    local ctx = { i18n = i18n, names = Names.new({
        skill = function(ref) return ref and SKILL[ref.id] or nil end,
    }) }
    local m = JournalTabs.skills(fight:snapshot(50), ctx, 1)
    local rows = {}
    for _, r in ipairs(m.rows) do rows[r.label] = r end
    local meteor, levin, normal = rows["Метеор"] or {}, rows["Молния"] or {}, rows["Обычные атаки"] or {}
    eq(meteor.value, i18n.num(10000), "the rocks' damage in the Meteor row")
    eq(meteor.hits, i18n.num(7), "the cast and the rocks")
    eq(meteor.who, "Maya", "hers")
    eq(levin.value, i18n.num(400), "Levin: its own bolts only")
    eq(levin.hits, i18n.num(4), "four Levin hits")
    eq(normal.value, i18n.num(600), "normal attacks: the bolts only")
    eq(normal.hits, i18n.num(6), "six bolts")
    eq(#m.rows, 3, "three rows")
end)

test("the skill memory stays bounded", function()
    world()
    local s = new_sink()
    hits.install(s)
    -- one attacker, many shell names
    for i = 1, 3000 do
        run({ attacker = W.yves, shell = true, victim = W.chimera, aud = aud("shot_" .. i), final = 1,
            hp1 = W.chimera.hp - 1 })
    end
    local learned = hits.info().learned
    assert(learned > 0 and learned <= 1024, "learned bounded: " .. learned)
    -- many attackers, one shell name
    for i = 1, 1100 do
        local c = char("ch300100_00_" .. i, { name = "N" .. i, state = 24 })
        run({ attacker = c, shell = true, victim = W.chimera, aud = aud("shot"), final = 1, hp1 = W.chimera.hp - 1 })
    end
    learned = hits.info().learned
    assert(learned > 0 and learned <= 1024, "learned bounded across attackers: " .. learned)
    eq(hits.info().recent, nil, "no recent states kept")
    hits.reset()
    eq(hits.info().learned, 0, "reset drops the learned skills")
end)

test("DoT: credited to whoever caused the active status", function()
    world()
    local attrib = Attrib.new()
    local s = new_sink()
    hits.install(s, attrib)
    local function tick(final)
        run({ victim = W.chimera, final = final, hp1 = W.chimera.hp - final })
        return s.hits[#s.hits]
    end
    -- the Electric status on the sphinx/chimera was caused by the player
    W.chimera.status[ELECTRIC] = 2891076981
    local h = tick(186.8)
    eq(h.attacker, actors.of(W.player), "the status's causer")
    eq(h.status, "Electric", "status name")
    eq(h.skill.attack, nil, "no attack")
    eq(h.skill.status, "Electric", "the tick's skill is its status")
    eq(h.skill.normal, nil, "a tick is no normal attack")
    eq(#s.party_hits, 0, "a tick is no party hit: it starts no fight, nor keeps one going")
    -- the main pawn refreshed it
    W.chimera.status[ELECTRIC] = 2283028347
    eq(tick(498.1).attacker, actors.of(W.casca), "follows the last causer")
    -- an active status whose causer is not party or ally: what Attrib saw applied, else nobody
    W.chimera.status[ELECTRIC] = NOBODY
    h = tick(101)
    eq(h.attacker, nil, "nobody known")
    eq(h.status, "Electric", "the status is still named")
    attrib:status_applied(5.0, actors.of(W.chimera).key, "Electric", actors.of(W.godwin))
    eq(tick(50).attacker, actors.of(W.godwin), "Attrib's applier of that status")
    -- no status active: «прочее», even though Attrib knows an applier
    W.chimera.status = {}
    h = tick(19)
    eq(h.attacker, nil, "environment / unknown")
    eq(h.status, nil, "no status")
    eq(h.skill.status, nil, "and no status as the skill")
    -- the StatusConditionCtrl cannot be asked at all: Attrib's last applier of any status
    W.chimera.methods.get_StatusConditionCtrl = function() error("boom") end
    h = tick(20)
    eq(h.attacker, actors.of(W.godwin), "Attrib fallback when the game call fails")
    eq(#R.bad, 0, "no slot misuse")
end)

test("DoT: an ally's status, found by CharacterID", function()
    world()
    local s = new_sink()
    hits.install(s)
    -- the guard fought for the party, then his fire burnt a goblin
    local guard = actors.of(W.guard)
    actors.mark_fighting(guard)
    W.goblin.status[5] = 300656
    run({ victim = W.goblin, final = 30, hp1 = W.goblin.hp - 30 })
    eq(s.hits[1].attacker, guard, "an ally by CharacterID")
    eq(s.hits[1].status, "FireSpread", "burning")
    eq(#s.party_hits, 0, "an ally's DoT does not start a party fight")
end)

-- The victim's own damage, as logged in game: a hit with no attacker
-- owner whose DamageInfo names the victim's own GameObject as the attacking one; Blood Pact's HP cost on a pawn every
-- frame, an enemy's fall. `o.by`: another AttackGameObject, `o.dgo` another DamageGameObject; `o.attacker`, `o.aud`,
-- `o.final` as for run. Gives the hit it emitted (one there must be).
local AGO, DGO = "<AttackGameObject>k__BackingField", "<DamageGameObject>k__BackingField"
local function own_hit(victim, o)
    o = o or {}
    o.victim = victim
    o.final = o.final or 1.6
    o.hp1 = o.hp1 or victim.hp - o.final
    o.di = damage_info(o)
    o.di.fields[AGO] = o.by or victim.go
    o.di.fields[DGO] = o.dgo or victim.go
    local n = #W.sink.hits
    run(o)
    eq(#W.sink.hits, n + 1, "one hit emitted")
    return W.sink.hits[#W.sink.hits]
end

-- The next Blood Pact check: past the second a member's check is kept.
local function later()
    W.t = W.t + 1.0
end

test("own damage: a party member's HP cost is his own, «Blood Pact» while he has it equipped", function()
    world()
    warrior_skills()
    W.sink = new_sink()
    hits.install(W.sink, Attrib.new())
    local godwin = actors.of(W.godwin)
    vocation(W.godwin, 5, { [111] = true })
    local h = own_hit(W.godwin)
    eq(h.own, "blood_pact", "Blood Pact equipped in his vocation")
    eq(h.attacker, nil, "nobody else did it"); eq(h.victim, godwin, "the victim")
    eq(h.status, nil, "no status"); near(h.final, 1.6, 1e-6, "the HP cost")
    eq(#W.sink.party_hits, 0, "no party hit: it starts no fight")
    local asked = R.calls_of(EQUIPPED)
    eq(asked[#asked].args[1], 5, "the game asked for his vocation"); eq(asked[#asked].args[2], 111, "and Blood Pact")
    eq(own_hit(W.godwin, { aud = aud("緋染_代償") }).own, "blood_pact", "with an attack too")
    -- not equipped, or equipped in a vocation he does not use now (each a second later: the check is kept that long)
    later()
    vocation(W.godwin, 5, { [58] = true })
    eq(own_hit(W.godwin).own, "self", "not equipped: his own all the same")
    later()
    vocation(W.godwin, 5, { [111] = true })
    local fighter = R.object("app.JobContext", { CurrentJob = 1 }, {})
    W.godwin.human.methods.get_JobContext = function() return fighter end
    eq(own_hit(W.godwin).own, "self", "equipped as a Warrior, but he is a Fighter now")
    later()
    W.godwin.human.methods.get_JobContext = function() error("boom") end
    eq(own_hit(W.godwin).own, "self", "the vocation cannot be read")
    -- the attacker resolves to the victim himself
    later()
    vocation(W.godwin, 5, { [111] = true })
    h = own_hit(W.godwin, { attacker = W.godwin, aud = aud("緋染_代償") })
    eq(h.own, "blood_pact", "his own hit controller"); eq(h.attacker, nil, "no attacker: not friendly fire")
    -- another GameObject attacking, or none named: not his own
    h = own_hit(W.godwin, { by = W.goblin.go })
    eq(h.own, nil, "another character's GameObject"); eq(h.attacker, nil, "and still nobody known")
    local n = #W.sink.hits
    run({ victim = W.godwin, final = 2, hp1 = W.godwin.hp - 2 })
    eq(#W.sink.hits, n + 1, "a new hit")
    h = W.sink.hits[#W.sink.hits]
    near(h.final, 2, 1e-9, "this one"); eq(h.victim, godwin, "on him"); eq(h.attacker, nil, "no attacker")
    eq(h.own, nil, "no AttackGameObject: as before")
    eq(#R.bad, 0, "no slot misuse")
end)

test("own damage: a member's Blood Pact check is kept for a second, then asked again", function()
    world()
    warrior_skills()
    W.sink = new_sink()
    hits.install(W.sink, Attrib.new())
    local function asked() return #R.calls_of(EQUIPPED) end
    vocation(W.godwin, 5, { [111] = true })
    vocation(W.casca, 5, {})
    local t0 = W.t
    eq(own_hit(W.godwin).own, "blood_pact", "equipped"); eq(asked(), 1, "asked once")
    for _ = 1, 49 do
        W.t = W.t + 0.02
        own_hit(W.godwin)
    end
    eq(asked(), 1, "a tick every frame for 0.98 s: not asked again")
    vocation(W.godwin, 5, { [58] = true })
    eq(own_hit(W.godwin).own, "blood_pact", "taken off inside the second: the kept answer")
    eq(own_hit(W.casca).own, "self", "another member has his own check"); eq(asked(), 2, "asked for him")
    W.t = t0 + 1.0
    eq(own_hit(W.godwin).own, "self", "a second later: asked again"); eq(asked(), 3, "once more")
    W.t = t0
    eq(own_hit(W.godwin).own, "self", "a clock that went back: asked again"); eq(asked(), 4, "once more")
    vocation(W.godwin, 5, { [111] = true })
    hits.reset()
    eq(own_hit(W.godwin).own, "blood_pact", "a reset forgets the kept answers"); eq(asked(), 5, "asked")
end)

test("own damage: the DamageGameObject stands in only when a member's character gives no GameObject", function()
    world()
    W.sink = new_sink()
    hits.install(W.sink, Attrib.new())
    local go = W.godwin.go
    W.godwin.methods.get_GameObject = function() return nil end
    eq(own_hit(W.godwin).own, "self", "the DamageGameObject is his own")
    eq(own_hit(W.godwin, { dgo = W.casca.go }).own, nil, "it names another")
    W.godwin.methods.get_GameObject = function() error("boom") end
    eq(own_hit(W.godwin).own, "self", "the character's call fails")
    W.godwin.methods.get_GameObject = function() return go end
    eq(own_hit(W.godwin, { dgo = W.casca.go }).own, "self", "the character answers: his own comes first")
    eq(#R.bad, 0, "no slot misuse")
end)

-- Logged in game: goblins slammed after being blown away (DamageType 14 Slam_S, OverThresholdType 1)
-- and the giant's part breaks (DamageType 8 Hitback_LL, 9 Hitback_LLL) as hits with no attacker and no AttackGameObject.
test("every hit with no attacker on an enemy that is no DoT tick is its own; nothing more is read", function()
    world()
    W.sink = new_sink()
    hits.install(W.sink, Attrib.new())
    local function sourceless(victim, fields, final)
        local reads = {}
        local di = damage_info({ victim = victim })
        for k, v in pairs(fields) do di.fields[k] = v end
        setmetatable(di.fields, { __index = function(_, k) reads[k] = true end })
        local n = #W.sink.hits
        run({ di = di, victim = victim, final = final, hp1 = victim.hp - final })
        eq(#W.sink.hits, n + 1, "a new hit")
        return W.sink.hits[#W.sink.hits], reads
    end
    local h, reads = sourceless(W.goblin, { DamageType = 14, OverThresholdType = 1, Flag = 10753 }, 1700)
    eq(h.own, "self", "a slam after being blown away"); eq(h.attacker, nil, "no attacker"); eq(h.status, nil, "no status")
    eq(reads[AGO], nil, "AttackGameObject not read"); eq(reads[DGO], nil, "nor DamageGameObject")
    h = sourceless(W.chimera, { DamageType = 8, Flag = 562949953432065 }, 37440)
    eq(h.own, "self", "a part break (Hitback_LL)")
    h = sourceless(W.chimera, { DamageType = 9 }, 37440)
    eq(h.own, "self", "a part break (Hitback_LLL)")
    -- a DoT tick nobody known caused stays one («Прочее»)
    W.goblin.status[5] = NOBODY
    h = sourceless(W.goblin, {}, 30)
    eq(h.own, nil, "a burn tick"); eq(h.status, "FireSpread", "its status"); eq(h.attacker, nil, "nobody")
    W.goblin.status = {}
    -- a party member's sourceless hit without his GameObject named stays nobody's
    h = sourceless(W.godwin, { DamageType = 14 }, 20)
    eq(h.own, nil, "not his own"); eq(h.attacker, nil, "nobody")
end)

test("own damage: an enemy's fall; a DoT tick stays one; a hit with an attacker reads nothing more", function()
    world()
    W.sink = new_sink()
    hits.install(W.sink, Attrib.new())
    local h = own_hit(W.goblin, { final = 1000 })
    eq(h.own, "self", "the enemy's own damage"); eq(h.attacker, nil, "no attacker"); eq(h.status, nil, "no status")
    eq(h.victim, actors.of(W.goblin), "the enemy")
    eq(#R.calls_of("get_JobContext"), 0, "an enemy's vocation is never read")
    -- a burn tick names the same GameObject: still the status's tick
    W.goblin.status[5] = 2891076981
    h = own_hit(W.goblin, { final = 30 })
    eq(h.attacker, actors.of(W.player), "the causer"); eq(h.status, "FireSpread", "burning"); eq(h.own, nil, "a DoT tick")
    W.goblin.status[5] = NOBODY
    h = own_hit(W.goblin, { final = 30 })
    eq(h.attacker, nil, "nobody known caused it"); eq(h.status, "FireSpread", "still a burn"); eq(h.own, nil, "no fall")
    W.goblin.status = {}
    -- a hit with an attacker never reads the GameObjects
    local reads = {}
    local di = damage_info({ attacker = W.casca, victim = W.goblin, aud = aud("N_軽") })
    setmetatable(di.fields, { __index = function(_, k) reads[k] = true end })
    local n = #W.sink.hits
    run({ di = di, victim = W.goblin, final = 100, hp1 = W.goblin.hp - 100 })
    eq(#W.sink.hits, n + 1, "a new hit")
    h = W.sink.hits[#W.sink.hits]
    near(h.final, 100, 1e-9, "this blow"); eq(h.attacker, actors.of(W.casca), "Casca's"); eq(h.own, nil, "not own")
    eq(reads[AGO], nil, "AttackGameObject not read"); eq(reads[DGO], nil, "DamageGameObject not read")
    -- a hit with no attacker on someone the fight drops (a neutral character, an ally) reads nothing more either
    for _, victim in ipairs({ W.guard, W.guard }) do
        reads = {}
        di = damage_info({ victim = victim })
        setmetatable(di.fields, { __index = function(_, k)
            reads[k] = true
            if k == AGO or k == DGO then return victim.go end -- his own: it would be own damage on a party member
        end })
        n = #W.sink.hits
        run({ di = di, victim = victim, final = 10, hp1 = victim.hp - 10 })
        eq(#W.sink.hits, n + 1, "a new hit on " .. W.sink.hits[#W.sink.hits].victim.kind)
        h = W.sink.hits[#W.sink.hits]
        eq(h.victim, actors.of(victim), "on him"); eq(h.own, nil, "not own: " .. h.victim.kind)
        eq(reads[AGO], nil, "AttackGameObject not read: " .. h.victim.kind)
        actors.mark_fighting(actors.of(W.guard))
    end
end)

-- An enemy's own damage (a slam after being blown away) at most 3 s after a friend's hit on it is that friend's,
-- in the knocking hit's skill. Eir is an ally who casts Frost Spike from a grimoire (a ghoul fight in game); the
-- hits go to W.sink and to a Fight (W.fight) as the entry file passes them on.
local FROST = "フロストスパイクLv2_冷気_対ノルド敵"

local function knock_world()
    world()
    vocation_skills()
    W.sink = new_sink()
    W.fight = Fight.new(0)
    local keep = W.sink.hit
    W.sink.hit = function(h)
        keep(h)
        W.fight:add_hit(h)
    end
    hits.install(W.sink, Attrib.new())
    W.ghoul = char("ch225000_00_3", { name = "Вурдалак", hostile = true, hp = 5000, max_hp = 5000 })
    W.eir = char("ch300700_00_1", { name = "Эйр", chara_id = 300700 })
    actors.mark_fighting(actors.of(W.eir))
    set_state(W.eir, 26)   -- Job03_Frigor: her Frost Spike
    return W
end

-- At time t, `attacker` hits `victim` for `final` HP (o: more of run's fields; a melee "N_軽" by default); the hit.
local function blow_at(t, attacker, victim, final, o)
    W.t = t
    local r = { attacker = attacker, victim = victim, aud = aud("N_軽"), final = final,
        hp1 = math.max(0, victim.hp - final) }
    for k, v in pairs(o or {}) do r[k] = v end
    run(r)
    return W.sink.hits[#W.sink.hits]
end

-- At time t, `victim`'s own damage: a hit with no attacker and no status; the hit.
local function slam_at(t, victim, final)
    W.t = t
    local n = #W.sink.hits
    run({ victim = victim, final = final, hp1 = math.max(0, victim.hp - final) })
    eq(#W.sink.hits, n + 1, "a new hit")
    return W.sink.hits[#W.sink.hits]
end

test("knock: an enemy's own damage 2.2 s after an ally's Frost Spike on it is hers, in that skill", function()
    knock_world()
    local eir, guts, ghoul = actors.of(W.eir), actors.of(W.player), actors.of(W.ghoul)
    blow_at(5, W.player, W.ghoul, 100)                         -- Guts engages the ghoul
    local spike = blow_at(10, W.eir, W.ghoul, 400, { shell = true, aud = aud(FROST) })
    eq(spike.attacker, eir, "her spell"); eq(spike.skill.id, "Job03_Frigor", "Frost Spike")
    local h = slam_at(12.2, W.ghoul, 1000)
    eq(h.attacker, eir, "Eir knocked it down"); eq(h.own, nil, "not its own"); eq(h.knock, true, "a knock hit")
    eq(h.skill.id, "Job03_Frigor", "her skill"); eq(h.skill.attack, FROST, "her attack")
    eq(h.skill.normal, spike.skill.normal, "the same normal flag")
    eq(h.skill ~= spike.skill, true, "a copy of her hit's skill reference")
    eq(h.status, nil, "no status"); eq(h.mirror, nil, "no mirror")
    eq(#W.sink.party_hits, 1, "an ally's knock opens no party fight: Guts' blow only")
    local snap = W.fight:snapshot(13, true)
    local her = snap.actors[eir.key]
    near(her.dealt, 1400, 1e-9, "her dealt: the spike and the slam"); eq(her.hits, 2, "two hits")
    near(her.skills[FROST].total, 1400, 1e-9, "the Frost Spike row: +1000"); eq(her.skills[FROST].hits, 2, "two hits")
    eq(snap.actors.env, nil, "nothing for «Падения и среда»"); eq(snap.actors.other, nil, "nor «Прочее»")
    near(snap.actors[ghoul.key].taken_from[eir.key], 1400, 1e-9, "the ghoul took it from her")
    eq(snap.actors[ghoul.key].taken_from.env, nil, "not from the environment")
    near(snap.actors[guts.key].dealt, 100, 1e-9, "Guts' blow only")
    near(snap.detail.foes[ghoul.key].by[eir.key].dealt, 1400, 1e-9, "the enemy card: hers")
    eq(#R.bad, 0, "no slot misuse")
end)

test("knock: 3.5 s after the friend's hit, or before it (a clock that went back), it is ENV's as before",
        function()
    knock_world()
    local ghoul = actors.of(W.ghoul)
    blow_at(5, W.player, W.ghoul, 100)
    blow_at(10, W.eir, W.ghoul, 400, { shell = true, aud = aud(FROST) })
    local h = slam_at(13.5, W.ghoul, 1000)
    eq(h.own, "self", "its own"); eq(h.attacker, nil, "nobody's"); eq(h.knock, nil, "no knock")
    h = slam_at(9.5, W.ghoul, 500)
    eq(h.own, "self", "before the kept hit: its own"); eq(h.knock, nil, "no knock")
    local snap = W.fight:snapshot(14)
    near(snap.actors.env.dealt, 1500, 1e-9, "«Падения и среда»: both")
    near(snap.actors[actors.of(W.eir).key].dealt, 400, 1e-9, "Eir: her spike only")
    near(snap.actors[ghoul.key].taken_from.env, 1500, 1e-9, "taken from the environment")
end)

test("knock: the last friend's hit, not the last hit: another enemy's collision in between", function()
    knock_world()
    local hob = char("ch221000_00_7", { name = "Хобгоблин", hostile = true, hp = 2000, max_hp = 2000 })
    local hob2 = char("ch221000_00_8", { name = "Хобгоблин", hostile = true, hp = 2000, max_hp = 2000 })
    blow_at(20, W.player, hob, 300, { aud = aud("弱攻撃_ヒットスロー大") })   -- Guts' throw
    local bump = blow_at(20.4, hob2, hob, 50, { aud = aud("t:Blow") })        -- the other one's collision
    local h = slam_at(20.5, hob, 540)
    eq(h.attacker, actors.of(W.player), "Guts' throw"); eq(h.skill.attack, "弱攻撃_ヒットスロー大", "his throw")
    eq(h.knock, true, "a knock hit"); eq(h.own, nil, "not its own")
    eq(bump.attacker, actors.of(hob2), "an enemy's hit on an enemy keeps its attacker"); eq(bump.knock, nil, "no knock")
    -- a friend's newer hit replaces the older one
    blow_at(21, W.casca, hob, 10)
    eq(slam_at(21.5, hob, 150).attacker, actors.of(W.casca), "Casca's blow is the last friend's")
end)

test("knock: a DoT tick and a mirror are neither knock hits nor knocking hits", function()
    knock_world()
    local casca = actors.of(W.casca)
    blow_at(10, W.casca, W.goblin, 100)
    -- a link mirror 0.5 s later: still a mirror, nobody's
    W.t = 10.5
    local di = damage_info({ victim = W.goblin })
    di.fields.Flag = 566935691817
    run({ di = di, victim = W.goblin, final = 100, hp1 = W.goblin.hp - 100 })
    local h = W.sink.hits[#W.sink.hits]
    eq(h.mirror, true, "a mirror"); eq(h.attacker, nil, "nobody's"); eq(h.knock, nil, "no knock")
    -- a burn tick nobody known caused: still a tick, nobody's
    W.goblin.status[5] = NOBODY
    h = slam_at(11, W.goblin, 30)
    eq(h.status, "FireSpread", "a tick"); eq(h.attacker, nil, "nobody's"); eq(h.knock, nil, "no knock")
    eq(h.own, nil, "not its own")
    -- the player's burn tick is his, and no knocking hit
    W.goblin.status[5] = W.player.chara_id
    h = slam_at(12, W.goblin, 30)
    eq(h.attacker, actors.of(W.player), "the burner's tick"); eq(h.knock, nil, "no knock")
    W.goblin.status = {}
    h = slam_at(12.9, W.goblin, 220)
    eq(h.attacker, casca, "Casca's blow 2.9 s before, not the tick nor the mirror"); eq(h.knock, true, "a knock")
    -- a knock hit is no knocking hit itself: 3.5 s after Casca's blow, 0.6 s after the knock
    h = slam_at(13.5, W.goblin, 150)
    eq(h.own, "self", "its own"); eq(h.attacker, nil, "nobody's")
end)

test("knock: a party member's own damage stays his own; a knock that kills is the friend's kill", function()
    knock_world()
    warrior_skills()
    vocation(W.godwin, 5, { [111] = true })
    local casca, goblin = actors.of(W.casca), actors.of(W.goblin)
    blow_at(10, W.godwin, W.goblin, 100)
    W.t = 10.5
    local h = own_hit(W.godwin)
    eq(h.own, "blood_pact", "his Blood Pact"); eq(h.attacker, nil, "nobody else"); eq(h.knock, nil, "no knock")
    -- Casca throws the goblin; its slam takes its last HP
    W.goblin.hp = 3000
    blow_at(20, W.casca, W.goblin, 2500, { aud = aud("弱攻撃_ヒットスロー大") })
    h = slam_at(21, W.goblin, 1000)
    eq(h.attacker, casca, "Casca's"); eq(h.knock, true, "a knock"); near(h.hp1, 0, 1e-9, "dead")
    local snap = W.fight:snapshot(22)
    local e = snap.enemies[goblin.key]
    eq(e.killed, true, "killed"); eq(e.killer, casca.key, "by Casca")
    eq(snap.actors[casca.key].kills, 1, "her kill"); near(snap.actors[casca.key].dealt, 3000, 1e-9, "2500 + 500")
    near(snap.actors[casca.key].skills["弱攻撃_ヒットスロー大"].total, 3000, 1e-9, "in her throw")
    eq(snap.actors.env, nil, "nothing for «Падения и среда»")
    eq(#W.sink.party_hits, 3, "her knock is her blow: a party hit, as Godwin's and her throw")
end)

test("knock: the friends' hits are kept for 64 enemies, the oldest dropped, and forgotten on reset", function()
    world()
    W.sink = new_sink()
    hits.install(W.sink, Attrib.new())
    local foes = {}
    for i = 1, 65 do
        foes[i] = char("ch220003_00_" .. (100 + i), { name = "G" .. i, hostile = true })
        blow_at(10 + i * 0.01, W.casca, foes[i], 1)
    end
    eq(slam_at(11, foes[1], 5).own, "self", "the oldest of 65 was dropped")
    eq(slam_at(11, foes[2], 5).knock, true, "the next one is kept")
    eq(slam_at(11, foes[65], 5).knock, true, "the newest too")
    hits.reset()
    eq(slam_at(11, foes[65], 5).own, "self", "a reset forgets them")
end)

test("knock: with sink.debug a knock hit carries its DamageType, Flag and gap; off, none is read", function()
    knock_world()
    local debug = false
    W.sink.debug = function() return debug end
    local function slam(t)
        local reads = {}
        local di = damage_info({ victim = W.goblin })
        setmetatable(di.fields, { __index = function(_, k)
            reads[k] = true
            return ({ DamageType = 14, Flag = 10753 })[k]
        end })
        W.t = t
        run({ di = di, victim = W.goblin, final = 1000, hp1 = W.goblin.hp - 1000 })
        return W.sink.hits[#W.sink.hits], reads
    end
    blow_at(10, W.casca, W.goblin, 100)
    local h, reads = slam(11)
    eq(h.knock, true, "a knock"); eq(reads.DamageType, nil, "debug off: DamageType not read")
    eq(h.damage_type, nil, "none"); eq(h.flag, nil, "no Flag"); eq(h.knock_gap, nil, "no gap")
    debug = true
    h, reads = slam(12)
    eq(h.knock, true, "a knock"); eq(h.damage_type, 14, "its DamageType"); eq(h.flag, 10753, "its Flag")
    near(h.knock_gap, 2, 1e-9, "2 s after Casca's blow")
end)

-- The game heals a member's lifesteal inside his own damageProc, before the hit is counted at its end.
test("strike: a party member's hit on an enemy is noted as it starts; no other hit is one", function()
    world()
    local s = new_sink()
    s.strikes = {}
    s.strike = function(frame, key) s.strikes[#s.strikes + 1] = { frame = frame, key = key } end
    hits.install(s, Attrib.new())
    local casca = actors.of(W.casca)
    -- Casca's blow: noted as its damageProc starts, before updateDamage and before the hit is counted
    local di = damage_info({ attacker = W.casca, victim = W.goblin, aud = aud("N_軽") })
    R.enter(hook(HC, "damageProc"), { R.CTX, slot(W.goblin.hc), slot(di) })
    eq(#s.strikes, 1, "noted at the start"); eq(s.strikes[1].key, casca.key, "his key"); eq(s.strikes[1].frame, 600, "frame")
    eq(#s.hits, 0, "the hit is not counted yet")
    R.enter(hook(HC, "updateDamage"), { R.CTX, slot(W.goblin.hc), slot(di), R.int_slot(0xFFFFFFFF), R.f32_slot(100),
        R.int_slot(0) })
    W.goblin.hp = W.goblin.hp - 100
    R.leave(nil)
    R.leave(true)
    eq(#s.hits, 1, "then counted"); eq(s.hits[1].attacker, casca, "his"); eq(#s.strikes, 1, "noted once")
    -- a hit that ends uncounted (no updateDamage: blocked, absorbed) was a strike all the same
    W.frame = 601
    run({ attacker = W.player, victim = W.goblin, aud = aud("N_軽") })
    eq(#s.hits, 1, "no hit"); eq(#s.strikes, 2, "a strike"); eq(s.strikes[2].key, actors.of(W.player).key, "the player's")
    eq(s.strikes[2].frame, 601, "in its frame")
    -- a shell strikes for its owner
    run({ attacker = W.yves, shell = true, victim = W.goblin, aud = aud("shot"), final = 10, hp1 = W.goblin.hp - 10 })
    eq(s.strikes[3].key, actors.of(W.yves).key, "the shell's owner")
    -- no strike: friendly fire, a healing-spot touch on a friend, a member on a neutral character or on himself, an
    -- enemy's blow, a tick with no attacker
    run({ attacker = W.casca, victim = W.player, aud = aud("N_軽"), final = 10, hp1 = W.player.hp - 10 })
    run({ attacker = W.yves, victim = W.casca, aud = aud("ヒーリングスポット") })
    run({ attacker = W.player, victim = W.guard, aud = aud("N_軽"), final = 10, hp1 = W.guard.hp - 10 })
    run({ attacker = W.godwin, victim = W.godwin, final = 2, hp1 = W.godwin.hp - 2 })
    run({ attacker = W.goblin, victim = W.casca, aud = aud("x"), final = 10, hp1 = W.casca.hp - 10 })
    run({ victim = W.goblin, final = 5, hp1 = W.goblin.hp - 5 })
    eq(#s.strikes, 3, "none of them")
    -- an ally's blow on an enemy is a strike too (her lifesteal), not a neutral character's
    local guard = actors.of(W.guard)
    W.frame = 602
    run({ attacker = W.guard, victim = W.goblin, aud = aud("斬り"), final = 1, hp1 = W.goblin.hp - 1 })
    eq(#s.strikes, 3, "a neutral character's blow: none (he is an ally only from its end)")
    run({ attacker = W.guard, victim = W.goblin, aud = aud("斬り"), final = 1, hp1 = W.goblin.hp - 1 })
    eq(guard.kind, "ally", "an ally now")
    eq(#s.strikes, 4, "an ally's blow"); eq(s.strikes[4].key, guard.key, "his key"); eq(s.strikes[4].frame, 602, "frame")
    eq(#s.hits, 9, "every hit but the blocked one and the touch reached the sink")
    eq(#R.bad, 0, "no slot misuse")
end)

test("strike: the attacker is read once per hit, as it starts, and the hit is the same", function()
    world()
    local s = new_sink()
    hits.install(s)
    local function reads()
        local n = 0
        for _, c in ipairs(R.calls_of("get_CachedCharacter")) do
            if c.this == W.casca.hc then n = n + 1 end
        end
        return n
    end
    sword_hit()
    eq(reads(), 1, "Casca's hit controller asked once")
    eq(s.hits[1].attacker, actors.of(W.casca), "the attacker"); near(s.hits[1].final, 405.1336, 1e-9, "the hit")
    eq(#s.party_hits, 1, "a party hit as before")
end)

-- The Evil Eye's two bodies share one HP pool; a hit on one is mirrored on the other by a sourceless hit whose
-- Flag has bit 39 set (logged in game: 566935691817; a sync with no loss 549755822665; normal hits 8201).
test("link mirror: a sourceless hit on an enemy with Flag bit 39 is a mirror, not its own; Flag read only there",
        function()
    world()
    W.sink = new_sink()
    hits.install(W.sink, Attrib.new())
    -- the Flag is served by __index, so that a read of it is seen
    local function sourceless(victim, flag, final, more)
        local reads = {}
        local di = damage_info(more or { victim = victim })
        setmetatable(di.fields, { __index = function(_, k)
            reads[k] = true
            if k == "Flag" then return flag end
        end })
        local n = #W.sink.hits
        run({ di = di, victim = victim, final = final or 100, hp1 = victim.hp - (final or 100) })
        eq(#W.sink.hits, n + 1, "a new hit")
        return W.sink.hits[#W.sink.hits], reads
    end
    local h, reads = sourceless(W.chimera, 566935691817)
    eq(h.mirror, true, "bit 39: a mirror"); eq(h.own, nil, "not its own"); eq(h.attacker, nil, "no attacker")
    eq(h.frame, 600, "the hit's frame"); eq(reads.Flag, true, "the Flag read")
    eq(sourceless(W.chimera, 549755822665, 0).mirror, true, "the sync with no loss")
    eq(sourceless(W.chimera, 566935691817.0).mirror, true, "a float flag")
    eq(sourceless(W.chimera, R.object("System.UInt64", { value__ = 566935691817 }, {})).mirror, true, "a boxed flag")
    eq(sourceless(W.chimera, -9223371487098961920).mirror, true, "bit 63 and 39 (a negative int64)")
    eq(sourceless(W.chimera, 2 ^ 63 + 2 ^ 39).mirror, true, "a float of 2^63 and more, bit 39 set")
    eq(sourceless(W.chimera, 2 ^ 63 + 2 ^ 40).own, "self", "a float of 2^63 and more, bit 39 clear")
    h = sourceless(W.chimera, 8201)
    eq(h.mirror, nil, "Flag 8201: no mirror"); eq(h.own, "self", "falls and environment")
    eq(sourceless(W.chimera, 562949953432065).own, "self", "the giant's part break (bit 49): its own")
    eq(sourceless(W.chimera, nil).own, "self", "no Flag: its own")
    -- a party member's sourceless hit is no mirror whatever its Flag, and its Flag is not read
    h, reads = sourceless(W.godwin, 566935691817, 2)
    eq(h.mirror, nil, "on a party member: none"); eq(reads.Flag, nil, "Flag not read")
    -- a hit with an attacker never reads the Flag
    h, reads = sourceless(W.goblin, 566935691817, 100, { attacker = W.casca, victim = W.goblin, aud = aud("N_軽") })
    eq(h.attacker, actors.of(W.casca), "Casca's blow"); eq(h.mirror, nil, "no mirror"); eq(reads.Flag, nil, "Flag not read")
    -- a burning body mirrors too: the Flag is read before the DoT check, and a mirror is no tick
    W.goblin.status[5] = 2891076981
    local asked = #R.calls_of(ACTIVE)
    h, reads = sourceless(W.goblin, 566935691817, 30)
    eq(h.mirror, true, "a mirror on a burning body"); eq(h.status, nil, "no tick"); eq(h.attacker, nil, "nobody's")
    eq(h.skill.status, nil, "no status"); eq(#R.calls_of(ACTIVE), asked, "no status asked")
    h, reads = sourceless(W.goblin, 8201, 30)
    eq(h.status, "FireSpread", "a burn tick"); eq(h.attacker, actors.of(W.player), "the burner's")
    eq(h.mirror, nil, "no mirror"); eq(reads.Flag, true, "its Flag read: one read per enemy tick")
    W.goblin.status = {}
end)

test("link mirror: a mirror reads no hit point or IsWeakDamage and carries no enemy-state bonus", function()
    world()
    local s = new_sink()
    s.points = function() return true end
    hits.install(s, Attrib.new())
    local reads = {}
    local di = damage_info({ victim = W.goblin })
    setmetatable(di.fields, { __index = function(_, k)
        reads[k] = true
        if k == "Flag" then return 566935691817 end
    end })
    run({ di = di, victim = W.goblin, final = 100, hp1 = W.goblin.hp - 100 })
    local h = s.hits[#s.hits]
    eq(h.mirror, true, "a mirror"); eq(h.point, nil, "no point"); eq(h.weak_damage, nil, "no weak point")
    eq(h.target_bonus, nil, "no bonus")
    eq(reads["<Position>k__BackingField"], nil, "Position not read"); eq(reads.IsWeakDamage, nil, "IsWeakDamage not read")
    eq(reads.DamageRate, nil, "DamageRate not read")
    -- one whose enemy defence step raised the rate (the step cannot tell a mirror): none all the same
    di = damage_info({ victim = W.goblin })
    di.fields.Flag = 566935691817
    run({ di = di, victim = W.goblin, calc = EDC, before = { DamageRate = 1 }, after = { DamageRate = 1.5 },
        final = 100, hp1 = W.goblin.hp - 100 })
    h = s.hits[#s.hits]
    eq(h.mirror, true, "a mirror through the step"); eq(h.target_bonus, nil, "no bonus: never a crit")
    -- a fall is read as before
    reads = {}
    di = damage_info({ victim = W.goblin })
    setmetatable(di.fields, { __index = function(_, k) reads[k] = true end })
    run({ di = di, victim = W.goblin, final = 100, hp1 = W.goblin.hp - 100 })
    eq(reads.IsWeakDamage, true, "a fall's IsWeakDamage read")
    eq(reads.DamageRate, nil, "no defence step: no DamageRate read")
end)

test("a neutral character that fights an enemy becomes an ally", function()
    world()
    local s = new_sink()
    hits.install(s)
    local guard = actors.of(W.guard)
    eq(guard.kind, "other", "not hostile, not seen fighting")
    run({ attacker = W.guard, victim = W.goblin, aud = aud("斬り"), final = 100, hp1 = 2900 })
    eq(s.hits[1].attacker.kind, "ally", "an ally once he hits an enemy")
    eq(#s.party_hits, 0, "an ally's hit does not start a party fight")
    -- hit by an enemy
    local villager = char("ch300522_00_1", { name = "Клаудия" })
    run({ attacker = W.goblin, victim = villager, aud = aud("振り下ろし"), final = 40, hp1 = 960 })
    eq(s.hits[2].victim.kind, "ally", "an ally once an enemy hits her")
    -- neutral against neutral changes nothing
    local a, b = char("ch300100_00_4", { name = "A" }), char("ch300100_00_5", { name = "B" })
    run({ attacker = a, victim = b, aud = aud("x"), final = 1, hp1 = 999 })
    eq(s.hits[3].attacker.kind, "other", "attacker stays other")
    eq(s.hits[3].victim.kind, "other", "victim stays other")
end)

test("party hits: party against an enemy only", function()
    world()
    local s = new_sink()
    hits.install(s)
    run({ attacker = W.goblin, victim = W.player, aud = aud("ジャンプ片手"), calc = PDC,
        before = { SlashDamage = 900 }, after = { SlashDamage = 106.072 }, final = 137.8936, hp1 = 2107.967 })
    eq(#s.party_hits, 1, "an enemy hits the player")
    eq(s.party_keys[1], actors.of(W.goblin).key, "the key of the enemy that hit")
    local h = s.hits[1]
    near(h.before, 900, 1e-9, "armor before"); near(h.after, 106.072, 1e-9, "armor after")
    near(h.hp0, 2245.86, 1e-9, "hp0"); near(h.hp1, 2107.967, 1e-9, "hp1")
    run({ attacker = W.casca, victim = W.player, aud = aud("N_軽"), final = 33, hp1 = 2070 })
    eq(#s.party_hits, 1, "friendly fire starts no fight")
    run({ victim = W.player, final = 50, hp1 = 2020 })
    eq(#s.party_hits, 1, "fall damage starts no fight")
    eq(s.hits[3].attacker, nil, "and has no attacker")
    -- the game still runs updateDamage on a dead enemy; such a hit is reported, but it is no party hit
    W.goblin.hp = 0
    run({ attacker = W.player, victim = W.goblin, aud = aud("N_軽"), final = 400, hp1 = 0 })
    eq(#s.hits, 4, "the corpse hit is still a hit")
    eq(s.hits[4].hp0, 0, "on a victim with no HP left")
    eq(#s.party_hits, 1, "a hit on a corpse starts no fight")
    -- the killing blow itself had HP to take
    W.goblin.hp = 25
    run({ attacker = W.player, victim = W.goblin, aud = aud("N_軽"), final = 400, hp1 = 0 })
    eq(#s.party_hits, 2, "the killing blow is a party hit")
end)

test("guard from subGuardHp, enchant damage and the types", function()
    world()
    local s = new_sink()
    hits.install(s)
    -- a blocked chimera hit on Yves: guard HP takes it, updateDamage runs with 0
    run({ attacker = W.chimera, victim = W.yves, aud = aud("ロックビート"), final = 0, hp1 = 1000,
        inside = function(di)
            R.fire(hook(HC, "subGuardHp"), { R.CTX, slot(W.yves.hc), R.f32_slot(930), slot(di) }, false)
        end })
    eq(#s.hits, 1, "a blocked hit is still a hit")
    near(s.hits[1].guard, 930, 1e-9, "guard")
    near(s.hits[1].final, 0, 1e-9, "no HP damage")
    -- enchanted weapon: EnchantDamage * EnchantRate counts with the other types
    run({ attacker = W.player, victim = W.goblin, aud = aud("N_軽"), calc = EDC,
        before = { SlashDamage = 400, EnchantDamage = 400, EnchantRate = 0.25, FixedDamage = 0 },
        after = { SlashDamage = 260, EnchantDamage = 120, EnchantRate = 0.25, BlowDamage = -140 },
        final = 300, hp1 = 2700 })
    local h = s.hits[2]
    near(h.before, 400 + 100, 1e-9, "before with enchant")
    near(h.after, 260 + 30, 1e-9, "after with enchant")
    near(h.types.Slash, 260, 1e-9, "Slash"); near(h.types.Enchant, 30, 1e-9, "Enchant")
    eq(count(h.types), 2, "only types with damage")
    eq(h.guard, nil, "no guard")
end)

test("region step gives before and after per type", function()
    world()
    local s = new_sink()
    hits.install(s)
    -- an enchanted blunt hit: the defence step leaves Blow and Enchant at 312.625 (EnchantRate 0.17), the region step
    -- lifts the enchant to 375.15 on the part RegionStatusNo 1
    run({ attacker = W.player, victim = W.goblin, aud = aud("N_軽"), calc = EDC,
        before = { BlowDamage = 500, EnchantDamage = 500, EnchantRate = 0.17 },
        after = { BlowDamage = 312.625, EnchantDamage = 312.625 },
        region = { after = { EnchantDamage = 375.15 }, no = 1 },
        final = 400, hp1 = 2600 })
    eq(#s.hits, 1, "one hit")
    local h = s.hits[1]
    near(h.region.before.Enchant, 53.14625, 1e-4, "Enchant before the step: x EnchantRate")
    near(h.region.after.Enchant, 63.7755, 1e-4, "Enchant after the step")
    eq(h.region.before.Blow, 312.625, "Blow before")
    eq(h.region.after.Blow, 312.625, "Blow after: the step left it")
    eq(count(h.region.before), 2, "only types with damage, before")
    eq(count(h.region.after), 2, "and after")
    eq(h.region.no, 1, "RegionStatusNo")
    eq(h.region.part, nil, "this enemy has no CharaID: no part")
    near(h.after, 312.625 + 53.14625, 1e-9, "the defence step's numbers are untouched")
    near(h.types.Enchant, 53.14625, 1e-9, "and its types")
    eq(#R.bad, 0, "no slot misuse")
end)

test("region step: a type the step takes to nothing is only in before", function()
    world()
    local s = new_sink()
    hits.install(s)
    run({ attacker = W.casca, victim = W.goblin, aud = aud("N_軽"), calc = EDC,
        before = { SlashDamage = 300 }, after = { SlashDamage = 250 },
        region = { after = { SlashDamage = 0 }, no = 4 }, final = 0, hp1 = W.goblin.hp })
    local h = s.hits[1]
    eq(h.region.before.Slash, 250, "damage before the step")
    eq(h.region.after.Slash, nil, "none after it")
    eq(h.region.no, 4, "the part")
end)

test("no region step: region is nil", function()
    world()
    local s = new_sink()
    hits.install(s)
    sword_hit()
    eq(s.hits[1].region, nil, "no region")
    near(s.hits[1].types.Slash, 339.45, 1e-9, "the defence step's types stay")
    -- a hit without any step at all
    run({ victim = W.goblin, final = 30, hp1 = W.goblin.hp - 30 })
    eq(s.hits[2].region, nil, "a tick has none either")
end)

test("a region step outside damageProc is ignored", function()
    world()
    local s = new_sink()
    hits.install(s)
    -- a step before the hit's damageProc opened: nothing to attach it to
    local di = damage_info({ attacker = W.casca, victim = W.goblin, aud = aud("N_軽") })
    region_step(di, W.goblin.hc, { before = { SlashDamage = 400 }, after = { SlashDamage = 200 }, no = 2 })
    run({ di = di, victim = W.goblin, calc = EDC, before = { SlashDamage = 479.45 }, after = { SlashDamage = 339.45 },
        final = 405.1336, hp1 = 2647.901 })
    eq(#s.hits, 1, "the hit itself is counted")
    eq(s.hits[1].region, nil, "the stray step is not its region")
    -- a step on another DamageInfo while a hit is open
    local other = damage_info({ attacker = W.player, victim = W.chimera, aud = aud("N_軽") })
    run({ attacker = W.casca, victim = W.goblin, aud = aud("N_軽"), calc = EDC, before = { SlashDamage = 100 },
        after = { SlashDamage = 90 }, final = 90, hp1 = 2500,
        inside = function()
            region_step(other, W.chimera.hc, { before = { SlashDamage = 50 }, after = { SlashDamage = 5 }, no = 3 })
        end })
    eq(s.hits[2].region, nil, "nor is a step on another DamageInfo")
    eq(#R.bad, 0, "no slot misuse")
end)

test("a second region step keeps the first", function()
    world()
    local s = new_sink()
    hits.install(s)
    run({ attacker = W.casca, victim = W.goblin, aud = aud("N_軽"), calc = EDC,
        before = { BlowDamage = 400 }, after = { BlowDamage = 300 },
        region = { after = { BlowDamage = 240 }, no = 1 },
        inside = function(di)
            region_step(di, W.goblin.hc, { after = { BlowDamage = 180 }, no = 2 })
        end,
        final = 200, hp1 = 2800 })
    local h = s.hits[1]
    eq(h.region.before.Blow, 300, "before of the first step")
    eq(h.region.after.Blow, 240, "after of the first step")
    eq(h.region.no, 1, "the part of the first step")
end)

test("region post returns retval and never raises", function()
    world()
    local s = new_sink()
    hits.install(s)
    local Safe = require("DD2DamageMeter/game/safe")
    local di = damage_info({ attacker = W.casca, victim = W.goblin, aud = aud("N_軽") })
    local hc = W.goblin.hc
    R.enter(hook(HC, "damageProc"), { R.CTX, slot(hc), slot(di) })
    local errors = hits.info().errors
    local real_field, real_to_object = Safe.field, sdk.to_managed_object
    local ok, err = pcall(function()
        -- the pre-hook cannot take the DamageInfo
        sdk.to_managed_object = function() error("no object") end
        eq(R.fire(hook(HC, "calcRegionDamageRate"), { R.CTX, slot(hc), slot(di) }, "RET"), "RET", "pre failed: retval")
        sdk.to_managed_object = real_to_object
        eq(hits.info().errors, errors + 1, "the pre-hook's failure is counted")
        -- the post-hook cannot read the DamageInfo
        R.enter(hook(HC, "calcRegionDamageRate"), { R.CTX, slot(hc), slot(di) })
        Safe.field = function() error("no field") end
        eq(R.leave("RET2"), "RET2", "post failed: retval")
        Safe.field = real_field
        eq(hits.info().errors, errors + 2, "the post-hook's failure is counted")
    end)
    Safe.field, sdk.to_managed_object = real_field, real_to_object
    assert(ok, err)
    di.fields.SlashDamage = 10
    R.enter(hook(HC, "updateDamage"), { R.CTX, slot(hc), slot(di), R.int_slot(0), R.f32_slot(10), R.int_slot(0) })
    W.goblin.hp = W.goblin.hp - 10
    R.leave(nil)
    eq(R.leave(true), true, "damageProc's own result")
    eq(#s.hits, 1, "the hit still arrives")
    eq(s.hits[1].region, nil, "without the region that could not be read")
end)

test("element from get_ElementType, not _ElementType", function()
    world()
    local s = new_sink()
    hits.install(s)
    local function element_of(o)
        o.attacker, o.victim, o.final, o.hp1 = o.attacker or W.player, W.goblin, 1, W.goblin.hp - 1
        run(o)
        return s.hits[#s.hits].element
    end
    -- an enchanted weapon: _ElementType -1, the hit's own element Thunder
    eq(element_of({ aud = aud("N_軽", -1), element = 3 }), "Thunder", "get_ElementType")
    -- _ElementType alone says nothing; nor does it overrule the hit
    eq(element_of({ aud = aud("N_軽", 1) }), nil, "no get_ElementType: no element")
    eq(element_of({ aud = aud("N_軽", 1), element = 2 }), "Ice", "the hit's element, not the attack's")
    local names = { [0] = "None", "Fire", "Ice", "Thunder", "Light", "Dark" }
    for value = 0, 5 do
        eq(element_of({ aud = aud("N_軽"), element = value }), names[value], "element " .. value)
    end
    eq(element_of({ aud = aud("N_軽"), element = 3.0 }), "Thunder", "a float from the game")
    -- values the mod has no name for
    for _, value in ipairs({ -1, 6, 2.5, "x" }) do
        eq(element_of({ aud = aud("N_軽"), element = value }), nil, "no name for " .. tostring(value))
    end
    -- every finished hit has one: a tick without an attack too
    run({ victim = W.goblin, element = 4, final = 1, hp1 = W.goblin.hp - 1 })
    eq(s.hits[#s.hits].element, "Light", "no AttackUserData")
    eq(#R.bad, 0, "no slot misuse")
end)

test("a boxed element reads value__", function()
    world()
    local s = new_sink()
    hits.install(s)
    local function boxed(v) return R.object("app.AttackUserData.ElementType", { value__ = v }, {}) end
    local function element_of(value)
        run({ attacker = W.player, victim = W.goblin, aud = aud("N_軽"), element = value, final = 1,
            hp1 = W.goblin.hp - 1 })
        return s.hits[#s.hits].element
    end
    eq(element_of(boxed(3)), "Thunder", "boxed Thunder")
    eq(element_of(boxed(0)), "None", "boxed None")
    eq(element_of(boxed(5)), "Dark", "boxed Dark")
    eq(element_of(boxed(9)), nil, "boxed, unknown value")
    eq(element_of(R.object("app.AttackUserData.ElementType", {}, {})), nil, "an object without value__")
end)

-- The damage calculator of an enemy as the game has it: the flags, the defences, the status mask and the region table
-- (`o.regions`: RegionStatusNo -> RegionType).
local function give_calculator(c, o)
    local params = {}
    for no, region_type in pairs(o.regions or {}) do
        params[no] = R.object("app.IntermediateRegionParam", {}, { get_RegionType = function() return region_type end })
    end
    local rsc = R.object("app.RegionStatusCtrl", {}, {
        ["getActiveRegionParam(System.Int32)"] = function(_, no) return params[no] end,
    })
    local calc = R.object(EDC, {}, {
        get_WeakPointSettings = function() return o.weak end,
        get_ResistSettings = function() return o.resist end,
        get_Defence = function() return o.defence end,
        get_MagicDefence = function() return o.magic_defence end,
        get_RegionStatusCtrl = function() return rsc end,
    })
    c.sc.fields.EnableStatusConditionFlag = o.enabled
    c.methods.get_DamageCalculator = function() return calc end
end

local function calls_of(sig) return #R.calls_of(sig) end

test("a hit carries the enemy's data and the part", function()
    world()
    local s = new_sink()
    hits.install(s)
    local boss = char("ch227001_50_9", { name = "Вурдалак", hostile = true, chara_id = 2270, hp = 140000,
        max_hp = 140000 })
    give_calculator(boss, { weak = 64, resist = 16, defence = 300, magic_defence = 280, enabled = 8395888,
        regions = { [1] = 0, [2] = 1, [3] = 2 } })
    -- the enemy is the victim: its data, and the part of the region the hit landed on
    run({ attacker = W.casca, victim = boss, aud = aud("N_軽"), calc = EDC, before = { SlashDamage = 400 },
        after = { SlashDamage = 300 }, region = { after = { SlashDamage = 330 }, no = 1 }, final = 330,
        hp1 = boss.hp - 330 })
    local h = s.hits[1]
    eq(h.foe.chara_id, 2270, "the victim's CharaID")
    eq(h.foe.weak, 64, "weak")
    eq(h.foe.resist, 16, "resist")
    eq(h.foe.defence, 300, "defence")
    eq(h.foe.magic_defence, 280, "magic defence")
    eq(h.foe.enabled, 8395888, "status mask")
    eq(h.region.part, "head", "RegionStatusNo 1 is a head")
    eq(h.region.no, 1, "the region number stays")
    eq(h.region.after.Slash, 330, "and the damage")
    -- the next hit on the same kind asks the game nothing about the kind or the part
    local asked = calls_of("get_DamageCalculator")
    run({ attacker = W.player, victim = boss, aud = aud("N_軽"), region = { after = { SlashDamage = 100 }, no = 1 },
        final = 100, hp1 = boss.hp - 100 })
    eq(s.hits[2].foe, h.foe, "the same record")
    eq(s.hits[2].region.part, "head", "the same part")
    eq(calls_of("get_DamageCalculator"), asked, "both remembered")
    -- another region of the body
    run({ attacker = W.player, victim = boss, aud = aud("N_軽"), region = { after = { BlowDamage = 100 }, no = 2 },
        final = 100, hp1 = boss.hp - 100 })
    eq(s.hits[3].region.part, "body", "RegionStatusNo 2")
    run({ attacker = W.player, victim = boss, aud = aud("N_軽"), region = { after = { BlowDamage = 100 }, no = 3 },
        final = 100, hp1 = boss.hp - 100 })
    eq(s.hits[4].region.part, "other", "RegionStatusNo 3")
    run({ attacker = W.player, victim = boss, aud = aud("N_軽"), region = { after = { BlowDamage = 100 }, no = 9 },
        final = 100, hp1 = boss.hp - 100 })
    eq(s.hits[5].region.part, nil, "a region the table does not have")
    eq(s.hits[5].region.no, 9, "its number stays")
    -- no region number: no part
    run({ attacker = W.player, victim = boss, aud = aud("N_軽"), region = { after = { BlowDamage = 100 } },
        final = 100, hp1 = boss.hp - 100 })
    eq(s.hits[6].region.no, nil, "no RegionStatusNo")
    eq(s.hits[6].region.part, nil, "no number: no part")
    eq(s.hits[6].foe, h.foe, "the data are there all the same")
    -- a hit without a region step has the data and no region
    run({ attacker = W.player, victim = boss, aud = aud("N_軽"), final = 100, hp1 = boss.hp - 100 })
    eq(s.hits[7].region, nil, "no region step")
    eq(s.hits[7].foe, h.foe, "the data")
    -- a DoT tick on the enemy: the enemy is the victim
    run({ victim = boss, final = 30, hp1 = boss.hp - 30 })
    eq(s.hits[8].foe, h.foe, "a tick has the victim's data")
    eq(#R.bad, 0, "no slot misuse")
end)

test("an enemy attacker's hit carries the attacker's data, no part", function()
    world()
    local s = new_sink()
    hits.install(s)
    local boss = char("ch227001_50_9", { name = "Вурдалак", hostile = true, chara_id = 2270, hp = 140000,
        max_hp = 140000 })
    give_calculator(boss, { weak = 64, resist = 16, defence = 300, magic_defence = 280,
        regions = { [1] = 0, [2] = 1 } })
    -- the player has a table too: it must not be asked
    give_calculator(W.player, { weak = 1, resist = 2, regions = { [1] = 1 } })
    -- the first thing met about this kind is its attack on the player
    run({ attacker = boss, victim = W.player, aud = aud("Claw"), calc = PDC, before = { BlowDamage = 200 },
        after = { BlowDamage = 150 }, region = { after = { BlowDamage = 150 }, no = 1 }, final = 150,
        hp1 = W.player.hp - 150 })
    local h = s.hits[1]
    eq(h.attacker, actors.of(boss), "the enemy attacks")
    eq(h.victim, actors.of(W.player), "the player takes it")
    eq(h.foe.chara_id, 2270, "the attacker's CharaID")
    eq(h.foe.weak, 64, "the attacker's data")
    eq(h.foe.defence, 300, "the attacker's defence")
    eq(h.region.no, 1, "the player's region number is kept")
    eq(h.region.part, nil, "a part is the enemy's as a victim only")
    eq(calls_of("getActiveRegionParam(System.Int32)"), 0, "the game was not asked about the player's part")
    -- the same record when it is the victim later
    run({ attacker = W.casca, victim = boss, aud = aud("N_軽"), region = { after = { SlashDamage = 50 }, no = 2 },
        final = 50, hp1 = boss.hp - 50 })
    eq(s.hits[2].foe, h.foe, "one record per kind")
    eq(s.hits[2].region.part, "body", "as a victim it has a part")
    -- a shell of the enemy is the enemy's too
    run({ attacker = boss, shell = true, victim = W.casca, aud = aud("Bolt"), final = 20, hp1 = W.casca.hp - 20 })
    eq(s.hits[3].foe, h.foe, "the shell's owner")
    eq(s.hits[3].region, nil, "no region step")
end)

test("hits with no enemy or no readable data have no foe", function()
    world()
    local s = new_sink()
    hits.install(s)
    -- the party among itself, and an enemy with no CharaID (W.goblin)
    give_calculator(W.casca, { weak = 1, resist = 2, regions = { [1] = 2 } })
    run({ attacker = W.player, victim = W.casca, aud = aud("N_軽"), region = { after = { SlashDamage = 5 }, no = 1 },
        final = 5, hp1 = W.casca.hp - 5 })
    eq(s.hits[1].foe, nil, "friend to friend")
    eq(s.hits[1].region.part, nil, "no part")
    eq(calls_of("get_DamageCalculator"), 0, "nothing was read")
    give_calculator(W.goblin, { weak = 2, resist = 4, regions = { [1] = 0 } })
    run({ attacker = W.casca, victim = W.goblin, aud = aud("N_軽"), region = { after = { SlashDamage = 5 }, no = 1 },
        final = 5, hp1 = W.goblin.hp - 5 })
    eq(s.hits[2].foe, nil, "an enemy without a CharaID")
    eq(s.hits[2].region.part, nil, "and no part")
    eq(calls_of("get_DamageCalculator"), 0, "nothing was read")
    -- a hit on a neutral character by an enemy that the game has no data for
    local ghost = char("ch300100_00", { hostile = true, chara_id = 3001 })
    ghost.methods.get_DamageCalculator = function() return nil end
    for _ = 1, 5 do
        run({ attacker = W.casca, victim = ghost, aud = aud("N_軽"), region = { after = { SlashDamage = 5 }, no = 1 },
            final = 5, hp1 = ghost.hp - 5 })
    end
    eq(#s.hits, 7, "every hit arrives")
    for i = 3, 7 do
        eq(s.hits[i].foe, nil, "no data " .. i)
        eq(s.hits[i].region.part, nil, "no part " .. i)
    end
    eq(calls_of("get_DamageCalculator"), 3 + 3, "asked 3 times for the data and 3 for the part, not on every hit")
    eq(hits.info().errors, 0, "nothing raised")
end)

test("a hit on a non-enemy has no part even with a region number", function()
    world()
    local s = new_sink()
    hits.install(s)
    local ally = char("ch300656_00_4", { name = "Форрест", chara_id = 300656 })
    give_calculator(ally, { weak = 2, resist = 4, regions = { [1] = 0 } })
    run({ attacker = W.casca, victim = ally, aud = aud("N_軽"), region = { after = { SlashDamage = 5 }, no = 1 },
        final = 5, hp1 = ally.hp - 5 })
    eq(s.hits[1].foe, nil, "an ally is no enemy")
    eq(s.hits[1].region.part, nil, "no part")
    eq(calls_of("get_DamageCalculator"), 0, "nothing was read")
end)

test("two updateDamage calls in one damageProc are one hit", function()
    world()
    local s = new_sink()
    hits.install(s)
    W.goblin.hp = 3000
    run({ attacker = W.player, victim = W.goblin, aud = aud("N_軽"), final = 100, hp1 = 2900,
        inside = function(di)
            -- a first part of the damage, before the one run() does
            R.enter(hook(HC, "updateDamage"), { R.CTX, slot(W.goblin.hc), slot(di), R.int_slot(0), R.f32_slot(40),
                R.int_slot(0) })
            W.goblin.hp = 2960
            R.leave(nil)
        end })
    eq(#s.hits, 1, "one hit")
    near(s.hits[1].final, 140, 1e-9, "damage summed")
    near(s.hits[1].hp0, 3000, 1e-9, "HP before the first part")
    near(s.hits[1].hp1, 2900, 1e-9, "HP after the last part")
end)

test("a second updateDamage on another hit controller is not merged", function()
    world()
    local s = new_sink()
    hits.install(s)
    W.goblin.hp, W.chimera.hp = 3000, 80000
    -- the first updateDamage is on the goblin; a stray one with the same DamageInfo lands on the chimera
    run({ attacker = W.player, victim = W.goblin, aud = aud("N_軽"), final = nil,
        inside = function(di)
            R.enter(hook(HC, "updateDamage"), { R.CTX, slot(W.goblin.hc), slot(di), R.int_slot(0), R.f32_slot(100),
                R.int_slot(0) })
            W.goblin.hp = 2900
            R.leave(nil)
            R.enter(hook(HC, "updateDamage"), { R.CTX, slot(W.chimera.hc), slot(di), R.int_slot(0), R.f32_slot(500),
                R.int_slot(0) })
            W.chimera.hp = 79500
            R.leave(nil)
        end })
    eq(#s.hits, 1, "one hit")
    eq(s.hits[1].victim, actors.of(W.goblin), "the first victim")
    near(s.hits[1].final, 100, 1e-9, "its damage only")
    near(s.hits[1].hp0, 3000, 1e-9, "its hp0"); near(s.hits[1].hp1, 2900, 1e-9, "its hp1")
end)

test("hits on objects and hits with incomplete numbers are dropped", function()
    world()
    local s = new_sink()
    hits.install(s)
    -- a barrel: its hit controller has no character
    local barrel_hc = R.object(HC, {}, { get_Hp = function() return 550 end })
    local barrel = { hc = barrel_hc, hp = 550 }
    run({ attacker = W.player, victim = barrel, aud = aud("N_軽"), final = 550 })
    eq(#s.hits, 0, "no victim character")
    -- HP that cannot be read
    W.goblin.hc.methods.get_Hp = function() error("boom") end
    run({ attacker = W.player, victim = W.goblin, aud = aud("N_軽"), final = 100 })
    eq(#s.hits, 0, "no hp0/hp1")
    W.goblin.hc.methods.get_Hp = function() return W.goblin.hp end
    run({ attacker = W.player, victim = W.goblin, aud = aud("N_軽"), final = 0 / 0, hp1 = 2000 })
    eq(#s.hits, 0, "final is not a number")
    run({ attacker = W.player, victim = W.goblin, aud = aud("N_軽"), final = 100, hp1 = 1900 })
    eq(#s.hits, 1, "a good hit")
    eq(type(s.hits[1].final) == "number" and type(s.hits[1].hp0) == "number" and type(s.hits[1].hp1) == "number",
        true, "complete numbers")
end)

-- The damage numbers' fields of a DamageInfo: Position, IsWeakDamage, DamageRate, served through a proxy that counts
-- their reads.
local NUMBER_FIELDS = { ["<Position>k__BackingField"] = true, IsWeakDamage = true, DamageRate = true }
local function counted_fields(di, values)
    local reads = { n = 0 }
    setmetatable(di.fields, { __index = function(_, k)
        if NUMBER_FIELDS[k] then reads.n = reads.n + 1 end
        return values[k]
    end })
    return reads
end

test("the hit point, IsWeakDamage and the defence step's DamageRate are read only while the sink asks", function()
    world()
    local s = new_sink()
    hits.install(s)
    local values = { ["<Position>k__BackingField"] = { x = -66.35, y = -8.66, z = 36.21 }, IsWeakDamage = true,
        DamageRate = 3 }
    -- no `points` in the sink: nothing read
    local di = damage_info({ attacker = W.casca, victim = W.goblin, aud = aud("弱攻撃") })
    local reads = counted_fields(di, values)
    sword_hit({ di = di })
    eq(reads.n, 0, "no points asked: nothing read")
    eq(s.hits[1].point, nil, "no point"); eq(s.hits[1].weak_damage, nil, "no flag")
    eq(s.hits[1].target_bonus, nil, "no bonus")
    -- the sink says no
    local on = false
    s.points = function() return on end
    di = damage_info({ attacker = W.casca, victim = W.goblin, aud = aud("弱攻撃") })
    reads = counted_fields(di, values)
    sword_hit({ di = di })
    eq(reads.n, 0, "points off: nothing read")
    -- the sink says yes: the three fields, the DamageRate before and after the enemy's defence step
    on = true
    di = damage_info({ attacker = W.casca, victim = W.goblin, aud = aud("弱攻撃") })
    reads = counted_fields(di, values)
    sword_hit({ di = di })
    local h = s.hits[3]
    eq(reads.n, 4, "on: the Position, IsWeakDamage and the DamageRate twice")
    eq(h.point, values["<Position>k__BackingField"], "the hit point as the game gives it")
    eq(h.weak_damage, true, "IsWeakDamage"); eq(h.target_bonus, 0, "a DamageRate of 3 the step left as it was")
    near(h.final, 405.1336, 1e-9, "the rest of the hit as before")
    -- a hit on someone who is not an enemy: nothing read
    di = damage_info({ attacker = W.goblin, victim = W.casca, aud = aud("攻撃") })
    reads = counted_fields(di, values)
    run({ di = di, victim = W.casca, final = 30, hp1 = 970 })
    eq(reads.n, 0, "a hit on the party: nothing read")
    eq(s.hits[4].point, nil, "no point")
    -- a flag that is not a boolean and a rate that is not a number say nothing
    di = damage_info({ attacker = W.casca, victim = W.goblin, aud = aud("弱攻撃") })
    counted_fields(di, { ["<Position>k__BackingField"] = values["<Position>k__BackingField"], IsWeakDamage = 1,
        DamageRate = 0 / 0 })
    sword_hit({ di = di })
    eq(s.hits[5].weak_damage, false, "not true: false"); eq(s.hits[5].target_bonus, nil, "nan: none")
    -- a sink whose points raises: nothing read, the hit still comes
    s.points = function() error("broken") end
    di = damage_info({ attacker = W.casca, victim = W.goblin, aud = aud("弱攻撃") })
    reads = counted_fields(di, values)
    sword_hit({ di = di })
    eq(reads.n, 0, "raising: nothing read")
    eq(#s.hits, 6, "the hit came")
    eq(#R.bad, 0, "no slot read with the wrong kind")
end)

-- A Single as the game keeps it: the DamageRate is one.
local function f32(x) return string.unpack("f", string.pack("f", x)) end

-- The DamageInfo's DamageRate kept aside and its reads counted in reads.n; the steps set it through the proxy too.
local function rate_reads(di)
    local reads, rate = { n = 0 }, nil
    setmetatable(di.fields, {
        __index = function(_, k)
            if k ~= "DamageRate" then return nil end
            reads.n = reads.n + 1
            return rate
        end,
        __newindex = function(t, k, v)
            if k == "DamageRate" then rate = v else rawset(t, k, v) end
        end,
    })
    return reads
end

test("the enemy's defence step: what it added to the DamageRate is Hit.target_bonus, a crit when it rose", function()
    world()
    local s = new_sink()
    local on = true
    s.points = function() return on end
    hits.install(s)
    local crit = DamageNumbers.crit
    -- Casca's sword hit whose DamageRate goes from `from` to `to` inside the enemy calculator's step; `o`: more
    local function stepped(from, to, o)
        local steps = { before = { SlashDamage = 479.45, DamageRate = f32(from) },
            after = { SlashDamage = 339.45, BlowDamage = -140, DamageRate = f32(to) } }
        for k, v in pairs(o or {}) do steps[k] = v end
        sword_hit(steps)
        return s.hits[#s.hits]
    end
    local h = stepped(1, 1.5)
    eq(h.target_bonus, 0.5, "1 -> 1.5: a downed enemy"); eq(crit(h), true, "a crit")
    near(h.before, 479.45, 1e-9, "the step's damage as before"); near(h.after, 339.45, 1e-9, "after it")
    h = stepped(2.2, 2.7)
    near(h.target_bonus, 0.5, 1e-6, "2.2 -> 2.7: a downed enemy under the incense"); eq(crit(h), true, "a crit")
    h = stepped(2.2, 2.2)
    eq(h.target_bonus, 0, "a final 2.2 the step left as it was: the incense"); eq(crit(h), false, "a buff: no crit")
    eq(crit(stepped(1.2, 1.2)), false, "1.2 from a jump: no crit")
    h = stepped(1, 0.8)
    near(h.target_bonus, -0.2, 1e-6, "a lowered rate"); eq(crit(h), false, "no crit")
    -- read before and after the step, and only while points are wanted
    local di = damage_info({ attacker = W.casca, victim = W.goblin, aud = aud("弱攻撃") })
    local reads = rate_reads(di)
    eq(crit(stepped(1, 1.5, { di = di })), true, "counted: a crit"); eq(reads.n, 2, "two reads")
    on = false
    di = damage_info({ attacker = W.casca, victim = W.goblin, aud = aud("弱攻撃") })
    reads = rate_reads(di)
    h = stepped(1, 1.5, { di = di })
    eq(reads.n, 0, "points not wanted: not read in the step"); eq(h.target_bonus, nil, "no bonus")
    on = true
    -- only the enemy calculator's step: the player calculator's (a pawn's victim side) is not read
    di = damage_info({ attacker = W.goblin, victim = W.casca, aud = aud("攻撃") })
    reads = rate_reads(di)
    run({ di = di, victim = W.casca, calc = PDC, before = { DamageRate = 1 }, after = { DamageRate = 1.5 },
        final = 30, hp1 = W.casca.hp - 30 })
    eq(reads.n, 0, "the player calculator: not read"); eq(s.hits[#s.hits].target_bonus, nil, "no bonus")
    -- a neutral character through the enemy calculator: read (the step cannot tell its victim), carried by no hit
    di = damage_info({ attacker = W.goblin, victim = W.guard, aud = aud("攻撃") })
    reads = rate_reads(di)
    run({ di = di, victim = W.guard, calc = EDC, before = { DamageRate = 1 }, after = { DamageRate = 1.5 },
        final = 30, hp1 = W.guard.hp - 30 })
    eq(reads.n, 2, "read in the step"); eq(s.hits[#s.hits].target_bonus, nil, "no enemy: no bonus")
    -- no step: no reading
    run({ attacker = W.casca, victim = W.goblin, aud = aud("弱攻撃"), final = 50, hp1 = W.goblin.hp - 50 })
    h = s.hits[#s.hits]
    eq(h.target_bonus, nil, "no step: none"); eq(crit(h), false, "no crit")
    -- a DoT tick: whatever its step did, no crit
    W.goblin.status[5] = W.casca.chara_id
    run({ victim = W.goblin, calc = EDC, before = { DamageRate = 1 }, after = { DamageRate = 1.5 }, final = 40,
        hp1 = W.goblin.hp - 40 })
    h = s.hits[#s.hits]
    eq(h.status, "FireSpread", "a burn tick"); eq(crit(h), false, "never a crit")
    W.goblin.status = {}
    -- a hit that runs the step twice: the last counts, as for the damage around it
    di = damage_info({ attacker = W.casca, victim = W.goblin, aud = aud("弱攻撃") })
    R.enter(hook(HC, "damageProc"), { R.CTX, slot(W.goblin.hc), slot(di) })
    for _, step in ipairs({ { 1, 1.5, 600, 450 }, { 1.5, 1.5, 450, 400 } }) do
        di.fields.DamageRate, di.fields.SlashDamage = f32(step[1]), step[3]
        R.enter(hook(EDC, "calcDamageValueDefence"), { R.CTX, slot(R.object(EDC)), slot(di) })
        di.fields.DamageRate, di.fields.SlashDamage = f32(step[2]), step[4]
        R.leave(nil)
    end
    R.enter(hook(HC, "updateDamage"), { R.CTX, slot(W.goblin.hc), slot(di), R.int_slot(0), R.f32_slot(300),
        R.int_slot(0) })
    W.goblin.hp = W.goblin.hp - 300
    R.leave(nil)
    R.leave(true)
    h = s.hits[#s.hits]
    eq(h.before, 450, "the last step's damage"); eq(h.target_bonus, 0, "and its rate: no rise, no crit")
    eq(#R.bad, 0, "no slot read with the wrong kind")
end)

test("a hit point that is missing or the origin: 1 m above the victim's root, else none", function()
    world()
    local s = new_sink()
    s.points = function() return true end
    hits.install(s)
    local root = { x = -66.26, y = -9.38, z = 36.21 }
    local transform = R.object("via.Transform", {}, { get_Position = function() return root end })
    W.goblin.go.methods.get_Transform = function() return transform end
    local function above_root(p, what)
        eq(type(p), "table", what .. ": a point")
        eq(p ~= root, true, what .. ": a new vector (Vector3f.new), the game's own untouched")
        eq(p.x, root.x, what .. ": x"); near(p.y, root.y + 1, 1e-9, what .. ": 1 m up"); eq(p.z, root.z, what .. ": z")
    end
    -- a burn tick: a DamageInfo with no attack, its Position the origin
    W.goblin.status[5] = W.casca.chara_id
    local di = damage_info({ victim = W.goblin })
    di.fields["<Position>k__BackingField"] = { x = 0, y = 0, z = 0 }
    run({ di = di, victim = W.goblin, final = 40, hp1 = W.goblin.hp - 40 })
    eq(s.hits[1].status, "FireSpread", "a burn tick")
    above_root(s.hits[1].point, "the origin is no place")
    eq(root.y, -9.38, "the root as it was")
    -- no Position at all
    di = damage_info({ attacker = W.casca, victim = W.goblin, aud = aud("弱攻撃") })
    sword_hit({ di = di })
    above_root(s.hits[2].point, "no Position")
    -- a Position that cannot be read as numbers
    di = damage_info({ attacker = W.casca, victim = W.goblin, aud = aud("弱攻撃") })
    di.fields["<Position>k__BackingField"] = { x = "a", y = 1, z = 2 }
    sword_hit({ di = di })
    above_root(s.hits[3].point, "not numbers")
    -- a real hit point is kept as the game gives it
    local spot = { x = -66.35, y = -8.66, z = 36.21 }
    di = damage_info({ attacker = W.casca, victim = W.goblin, aud = aud("弱攻撃") })
    di.fields["<Position>k__BackingField"] = spot
    sword_hit({ di = di })
    eq(s.hits[4].point, spot, "a hit point: as it is")
    -- without Vector3f.new: the root itself
    local vector = Vector3f
    Vector3f = nil
    di = damage_info({ attacker = W.casca, victim = W.goblin, aud = aud("弱攻撃") })
    sword_hit({ di = di })
    eq(s.hits[5].point, root, "no Vector3f.new: the root")
    Vector3f = vector
    -- neither: no point
    W.goblin.go.methods.get_Transform = nil
    di = damage_info({ attacker = W.casca, victim = W.goblin, aud = aud("弱攻撃") })
    sword_hit({ di = di })
    eq(s.hits[6].point, nil, "no place at all: none")
    eq(#s.hits, 6, "every hit still comes")
end)

-- The debug collector's fields (sink.debug, game/collector.lua) -------------------------------------------------

test("with sink.debug, a hit on an enemy carries the enemy step's bonus and rate, the damage numbers' fields unread",
        function()
    world()
    local s = new_sink()
    local debug, points = false, false
    s.debug = function() return debug end
    s.points = function() return points end
    hits.install(s)
    -- Casca's sword hit through the enemy calculator's step, its DamageRate 1 -> 1.5; the reads of the damage
    -- numbers' fields counted
    local function stepped()
        local di = damage_info({ attacker = W.casca, victim = W.goblin, aud = aud("強攻撃") })
        local rate, reads = nil, { n = 0, rate = 0 }
        setmetatable(di.fields, {
            __index = function(_, k)
                if NUMBER_FIELDS[k] then reads.n = reads.n + 1 end
                if k == "DamageRate" then
                    reads.rate = reads.rate + 1
                    return rate
                end
            end,
            __newindex = function(t, k, v)
                if k == "DamageRate" then rate = v else rawset(t, k, v) end
            end,
        })
        sword_hit({ di = di, before = { SlashDamage = 479.45, DamageRate = 1 },
            after = { SlashDamage = 339.45, DamageRate = 1.5 } })
        return s.hits[#s.hits], reads
    end
    -- debug and the numbers both off: no DamageRate read, as before
    local h, reads = stepped()
    eq(reads.n, 0, "both off: nothing read"); eq(h.target_bonus, nil, "no bonus"); eq(h.target_rate, nil, "no rate")
    -- debug on, the numbers off: the DamageRate around the step only
    debug = true
    h, reads = stepped()
    eq(reads.rate, 2, "the DamageRate before and after the step"); eq(reads.n, 2, "nothing else of the numbers'")
    eq(h.target_bonus, 0.5, "the bonus"); eq(h.target_rate, 1, "the rate before the step")
    eq(h.point, nil, "no hit point"); eq(h.weak_damage, nil, "no weak point")
    -- both on: the numbers' fields as before, the rate too
    points = true
    h, reads = stepped()
    eq(reads.n, 4, "the Position, IsWeakDamage and the DamageRate twice"); eq(h.target_bonus, 0.5, "the bonus")
    eq(h.target_rate, 1, "the rate"); eq(h.weak_damage, false, "IsWeakDamage read")
    -- the numbers on, debug off: no rate on the hit
    debug = false
    h = stepped()
    eq(h.target_bonus, 0.5, "the numbers' bonus"); eq(h.target_rate, nil, "no rate without debug")
    -- a sink whose debug raises: nothing read
    debug, points = nil, false
    s.debug = function() error("broken") end
    h, reads = stepped()
    eq(reads.rate, 0, "raising: not read"); eq(h.target_bonus, nil, "no bonus")
    eq(#R.bad, 0, "no slot read with the wrong kind")
end)

test("with sink.debug, a sourceless hit on an enemy carries its DamageType and Flag; off, DamageType is not read",
        function()
    world()
    W.sink = new_sink()
    local debug = false
    W.sink.debug = function() return debug end
    hits.install(W.sink, Attrib.new())
    local function sourceless(victim, fields, final, more)
        local reads = {}
        local di = damage_info(more or { victim = victim })
        setmetatable(di.fields, { __index = function(_, k)
            reads[k] = true
            return fields[k]
        end })
        run({ di = di, victim = victim, final = final or 100, hp1 = victim.hp - (final or 100) })
        return W.sink.hits[#W.sink.hits], reads
    end
    local h, reads = sourceless(W.goblin, { DamageType = 14, Flag = 10753 })
    eq(h.own, "self", "a slam"); eq(reads.DamageType, nil, "debug off: DamageType not read")
    eq(h.damage_type, nil, "none"); eq(h.flag, nil, "no Flag on the hit")
    debug = true
    h, reads = sourceless(W.goblin, { DamageType = 14, Flag = 10753 })
    eq(h.damage_type, 14, "DamageType"); eq(h.flag, 10753, "Flag"); eq(h.own, "self", "still its own")
    h = sourceless(W.goblin, { DamageType = R.object("app.DamageType", { value__ = 8 }, {}), Flag = 562949953432065 })
    eq(h.damage_type, 8, "a boxed DamageType"); eq(h.flag, 562949953432065, "bit 49")
    -- a burn nobody known caused («Прочее») and a mirror
    W.goblin.status[5] = NOBODY
    h = sourceless(W.goblin, { DamageType = -1, Flag = 8713 }, 30)
    eq(h.status, "FireSpread", "a burn tick"); eq(h.damage_type, -1, "its DamageType"); eq(h.flag, 8713, "its Flag")
    W.goblin.status = {}
    h = sourceless(W.chimera, { DamageType = -1, Flag = 566935691817 })
    eq(h.mirror, true, "a mirror"); eq(h.flag, 566935691817, "its Flag"); eq(h.damage_type, -1, "its DamageType")
    -- a burn the player caused, a blow with an attacker, a sourceless hit on the party: none
    W.goblin.status[5] = W.player.chara_id
    h, reads = sourceless(W.goblin, { DamageType = -1, Flag = 8713 }, 30)
    eq(h.attacker, actors.of(W.player), "the burner's tick"); eq(reads.DamageType, nil, "DamageType not read")
    eq(h.damage_type, nil, "none"); eq(h.flag, nil, "no Flag")
    W.goblin.status = {}
    h, reads = sourceless(W.goblin, { DamageType = 3 }, 100,
        { attacker = W.casca, victim = W.goblin, aud = aud("N_軽") })
    eq(reads.DamageType, nil, "a blow: not read"); eq(h.damage_type, nil, "none")
    h, reads = sourceless(W.godwin, { DamageType = 14, Flag = 1 }, 2)
    eq(reads.DamageType, nil, "on a party member: not read"); eq(h.flag, nil, "none")
end)

test("with sink.debug, a hit on an enemy hands its victim's character to sink.met before sink.hit", function()
    world()
    local s = new_sink()
    local debug = false
    s.debug = function() return debug end
    s.met_calls = {}
    s.met = function(c, actor, t)
        s.met_calls[#s.met_calls + 1] = { c = c, actor = actor, t = t }
        s.order[#s.order + 1] = "met"
    end
    hits.install(s, Attrib.new())
    sword_hit()
    eq(#s.met_calls, 0, "debug off: none")
    debug = true
    s.order = {}
    sword_hit()
    eq(#s.met_calls, 1, "debug on: one"); eq(s.met_calls[1].c, W.goblin, "the victim's character")
    eq(s.met_calls[1].actor, actors.of(W.goblin), "its Actor"); eq(s.met_calls[1].t, W.t, "the hit's time")
    eq(table.concat(s.order, " "), "party_hit met hit", "before the hit")
    -- a burn tick and a fall on an enemy meet it too; a hit on the party does not
    W.goblin.status[5] = W.player.chara_id
    run({ victim = W.goblin, final = 30, hp1 = W.goblin.hp - 30 })
    W.goblin.status = {}
    run({ victim = W.goblin, final = 30, hp1 = W.goblin.hp - 30 })
    eq(#s.met_calls, 3, "the tick and the fall")
    run({ attacker = W.goblin, victim = W.casca, aud = aud("x"), final = 10, hp1 = W.casca.hp - 10 })
    eq(#s.met_calls, 3, "a hit on the party: none")
    -- a blow on a corpse and a tick on one (the game runs updateDamage on the dead): none, the hits come
    local n = #s.hits
    W.goblin.hp = 0
    run({ attacker = W.casca, victim = W.goblin, aud = aud("N_軽"), final = 10, hp1 = 0 })
    W.goblin.status[5] = W.player.chara_id
    run({ victim = W.goblin, final = 30, hp1 = 0 })
    W.goblin.status = {}
    eq(#s.met_calls, 3, "on a corpse: none"); eq(#s.hits, n + 2, "both hits came")
    W.goblin.hp = 3000
    -- a met that raises costs nothing but itself
    s.met = function() error("boom") end
    local n = #s.hits
    sword_hit()
    eq(#s.hits, n + 1, "the hit still comes")
end)

test("many hits whose damageProc never ends keep memory bounded", function()
    world()
    local s = new_sink()
    hits.install(s)
    -- pre-hooks without their post-hooks (a game exception between them)
    for _ = 1, 5000 do
        local di = damage_info({ attacker = W.player, victim = W.goblin, aud = aud("N_軽") })
        R.enter(hook(HC, "damageProc"), { R.CTX, slot(W.goblin.hc), slot(di) })
    end
    assert(hits.info().open <= 64, "open contexts bounded: " .. hits.info().open)
    hits.reset()
    eq(hits.info().open, 0, "reset drops them")
end)

T.finish()
