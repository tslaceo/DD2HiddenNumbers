package.path = "mod/reframework/autorun/?.lua;tests/?.lua;" .. package.path

local T = require("testlib")
local test, eq, near = T.test, T.eq, T.near
local ui = require("stubs/ui").install()
local i18n = require("DD2DamageMeter/i18n")
local Settings = require("DD2DamageMeter/settings")
local Kit = require("DD2DamageMeter/ui/kit")
local SceneText = require("DD2DamageMeter/ui/scene_text")
local DamageNumbers = require("DD2DamageMeter/damage_numbers")
local UI = require("DD2DamageMeter/ui/damage_numbers")

local C = Kit.COLORS

-- REFramework's draw.world_to_screen: by default a world point's x and y are its place on the screen.
local project
local function on_screen(p) return { x = p.x, y = p.y } end
rawset(_G, "draw", { world_to_screen = function(p) return project(p) end })

local function make_settings(over)
    local saved = over or {}
    return Settings.load({ read = function() return saved end, write = function(t) saved = t end })
end

local function fresh(over)
    ui.reset()
    UI.reset()
    SceneText.reset()
    i18n.set("ru")
    project = on_screen
    return make_settings(over)
end

local function actor(key, kind, job)
    return { key = key, name = key, kind = kind, job = job }
end

local GUTS = actor("ch000000_00", "player", 10)
local CASCA = actor("ch100000_00", "pawn", 5)
local ALLY = actor("ch111003_00", "ally")
local GOB = actor("a10", "enemy")
local OGRE = actor("a12", "enemy")

local function at(x, y) return { x = x, y = y, z = 7 } end

local function hit(attacker, victim, o)
    local h = { t = 0, attacker = attacker, victim = victim, skill = { attack = "atk" }, final = 100, hp0 = 1000,
        hp1 = 900, point = at(800, 500), weak_damage = false, target_bonus = 0 }
    for k, v in pairs(o or {}) do h[k] = v end
    return h
end

-- One frame; a drawing error fails the test, the stacks must balance.
local function draw(list, s, t)
    ui.clear_calls()
    local err = UI.draw(list, s, t)
    if err then error("draw failed: " .. err, 2) end
    eq(ui.balanced(), true, "stacks balanced")
end

-- The texts drawn whose colour without its alpha is `color`'s.
local function texts_in(color)
    local list = {}
    for _, c in ipairs(ui.calls_of("add_text")) do
        if c.col & 0xFFFFFF == color & 0xFFFFFF then list[#list + 1] = c end
    end
    return list
end

local function alpha_of(color) return (color >> 24) & 0xFF end

-- The width the stub gives `text` at `px`.
local function width(text, px)
    return utf8.len(text) * ui.char_w * px / 14
end

test("rise: centred on the hit point, rising 40 px, fading out over the last 40 % of its second", function()
    local s = fresh()
    local list = DamageNumbers.new()
    list:add(hit(CASCA, GOB), 1234, 0, 1)
    local color = Kit.actor_color("pawn", 5, 1)
    draw(list, s, 0)
    local c = texts_in(color)
    eq(#c, 1, "one text in the pawn's colour")
    c = c[1]
    eq(c.text, "1 234", "the HP, as the meter writes it")
    eq(c.px, 18, "18 px at scale 1 and 100 %")
    eq(c.layer, "background", "on the background list")
    near(c.x + width("1 234", 18) / 2, 800, 0.5, "centred on the point")
    near(c.y + 18 / 2, 500, 0.5, "its middle on the point")
    eq(alpha_of(c.col), 255, "opaque")
    local calls = ui.calls_of("add_text")
    eq(#calls, 10, "the shadow, eight outline copies, the text")
    eq(calls[1].col, SceneText.COLORS.shadow, "the shadow first, in the enemy numbers' look")
    eq(calls[2].col, SceneText.COLORS.outline, "then the outline")
    eq(calls[10], c, "the text last")
    -- up 30 px at half its life, 40 px at its end; opaque until 0.6 s, then fading out
    draw(list, s, 0.5)
    c = texts_in(color)[1]
    near(c.y + 9, 500 - 30, 0.5, "half its life: 30 of 40 px up (fast, then slower)")
    eq(alpha_of(c.col), 255, "still opaque")
    draw(list, s, 0.6)
    eq(alpha_of(texts_in(color)[1].col), 255, "opaque at 0.6 s")
    draw(list, s, 0.8)
    c = texts_in(color)[1]
    near(alpha_of(c.col), 127.5, 0.5, "half faded at 0.8 s")
    near(alpha_of(ui.calls_of("add_text")[1].col), 85.5, 0.5, "its shadow too")
    near(alpha_of(ui.calls_of("add_text")[2].col), 127.5, 0.5, "and its outline")
    near(c.y + 9, 500 - 40 * 0.96, 0.5, "38.4 px up")
    -- re-projected every frame: it follows its point
    project = function(p) return { x = p.x + 100, y = p.y - 50 } end
    draw(list, s, 0.8)
    c = texts_in(color)[1]
    near(c.x + width("1 234", 18) / 2, 900, 0.5, "the point moved right on the screen")
    near(c.y + 9, 450 - 38.4, 0.5, "and up")
    project = on_screen
    -- its second is over: not drawn, then forgotten
    draw(list, s, 1.0)
    eq(#ui.calls, 0, "faded out: nothing drawn")
    draw(list, s, 1.01)
    eq(#list.items, 0, "forgotten")
    eq(#ui.calls, 0, "nothing at all for no number")
    eq(UI.life("rise"), 1.0, "a second"); eq(UI.life("plates"), 1.5, "plates: 1.5 s")
end)

test("the size: × the meter's scale × damage_numbers_size, the rise too", function()
    local s = fresh({ scale = 1.5, damage_numbers_size = 2 })
    local list = DamageNumbers.new()
    list:add(hit(CASCA, GOB), 50, 0, 1)
    draw(list, s, 0.5)
    local c = texts_in(Kit.actor_color("pawn", 5, 1))[1]
    near(c.px, 18 * 3, 1e-9, "18 px × 1.5 × 2")
    near(c.y + c.px / 2, 500 - 30 * 3, 0.5, "30 px × 3 up at half its life")
    near(UI.rise(1, 3), 120, 1e-9, "40 px × 3 at its end")
    eq(UI.rise(0, 1), 0, "none at the start"); eq(UI.rise(5, 1), 40, "never further")
end)

test("the colour: a party member's vocation in their shade, an ally's, everything else grey", function()
    local s = fresh()
    local list = DamageNumbers.new()
    list:add(hit(actor("ch000000_00", "player", 5), GOB, { point = at(100, 100) }), 10, 0, 1)
    list:add(hit(CASCA, GOB, { point = at(300, 100) }), 20, 0, 2)
    list:add(hit(ALLY, GOB, { point = at(500, 100) }), 30, 0)
    list:add(hit(nil, GOB, { point = at(700, 100), status = "FireSpread", skill = { status = "FireSpread" } }), 40, 0)
    list:add(hit(OGRE, GOB, { point = at(900, 100) }), 50, 0)
    draw(list, s, 0)
    local first, second = Kit.actor_color("player", 5, 1), Kit.actor_color("pawn", 5, 2)
    eq(first ~= second, true, "two Warriors: two shades")
    eq(first, C.vocation[5], "the first one the vocation's own colour")
    eq(texts_in(first)[1].text, "10", "the player's number in the first shade")
    eq(texts_in(second)[1].text, "20", "the pawn's in the second")
    eq(texts_in(C.ally)[1].text, "30", "an ally's in the meter's ally colour")
    local grey = texts_in(C.other)
    eq(#grey, 2, "two in the meter's Other grey")
    eq(grey[1].text, "40", "nobody's burn tick"); eq(grey[2].text, "50", "an enemy's blow on an enemy")
end)

test("off the display a number is not drawn, and comes back on it", function()
    local s = fresh()
    local list = DamageNumbers.new()
    local n = list:add(hit(CASCA, GOB), 99, 0, 1)
    local color = Kit.actor_color("pawn", 5, 1)
    project = function() return nil end
    draw(list, s, 0.1)
    eq(#ui.calls, 0, "behind the camera (nil): nothing drawn, not even an imgui call")
    for _, p in ipairs({ at(-1, 500), at(1921, 500), at(800, -1), at(800, 1081), at(14759, -765), at(0 / 0, 5) }) do
        project = function() return { x = p.x, y = p.y } end
        draw(list, s, 0.1)
        eq(#texts_in(color), 0, "off the display at " .. tostring(p.x) .. ", " .. tostring(p.y))
    end
    project = on_screen
    draw(list, s, 0.2)
    eq(#texts_in(color), 1, "back on it")
    eq(n.point.x, 800, "its point never changed")
end)

test("a crit: 1.4 × bigger with «!», popping from 1.35 × to its size within 0.25 s", function()
    local s = fresh()
    local list = DamageNumbers.new()
    list:add(hit(CASCA, GOB, { target_bonus = 0.5 }), 3800, 0, 1)
    local color = Kit.actor_color("pawn", 5, 1)
    local base = 18 * 1.4
    draw(list, s, 0)
    local c = texts_in(color)[1]
    eq(c.text, "3 800!", "«!» after the number")
    near(c.px, base * 1.35, 1e-9, "1.35 × its size at first")
    eq(ui.find("push_font_size")[1], c.px, "through the pushed font size")
    draw(list, s, 0.125)
    near(texts_in(color)[1].px, base * (1 + 0.35 * 0.25), 1e-9, "settling")
    draw(list, s, 0.25)
    near(texts_in(color)[1].px, base, 1e-9, "its size after 0.25 s")
    draw(list, s, 0.7)
    near(texts_in(color)[1].px, base, 1e-9, "and so on")
    eq(UI.pop(0), 1.35, "pop at 0"); eq(UI.pop(0.3), 1, "none after 0.25 s"); eq(UI.pop(-1), 1.35, "nor before")
    -- a number that becomes a crit later pops from then
    list:clear()
    local n = list:add(hit(GUTS, GOB), 1300, 0, 1)
    list:add(hit(GUTS, GOB, { target_bonus = 0.5 }), 1610, 0.2)
    eq(n.crit_t, 0.2, "a crit since 0.2 s")
    draw(list, s, 0.2)
    c = texts_in(Kit.actor_color("player", 10, 1))[1]
    eq(c.text, "2 910!", "the sum, with «!»")
    near(c.px, base * 1.35, 1e-9, "its pop starts then")
end)

test("a weak point: a diamond in its colour before the number, drawn as quads; not bigger, no «!»", function()
    local s = fresh()
    local list = DamageNumbers.new()
    list:add(hit(CASCA, GOB, { weak_damage = true }), 2710, 0, 1)
    local color = Kit.actor_color("pawn", 5, 1)
    draw(list, s, 0)
    local c = texts_in(color)[1]
    eq(c.text, "2 710", "no «!»"); eq(c.px, 18, "not bigger")
    local quads = ui.calls_of("add_quad_filled")
    eq(#quads, 2, "a dark edge and the diamond")
    eq(quads[1].col, SceneText.COLORS.outline, "the edge black, like the text's outline")
    eq(quads[2].col, color, "the diamond in the number's colour")
    local p = quads[2].points
    near(p[1].x, p[3].x, 1e-9, "top and bottom on one line")
    near(p[2].y, p[4].y, 1e-9, "left and right on one line")
    local r = 0.28 * 18
    near(p[3].y - p[1].y, 2 * r, 1e-9, "its height: about half the text's")
    eq(p[2].x < c.x, true, "before the number")
    near(p[2].y, c.y + 9, 0.5, "on the text's middle")
    near((p[4].x + c.x + width("2 710", 18)) / 2, 800, 1, "the diamond and the number centred together")
    eq(#ui.calls_of("add_text"), 10, "the text as before")
    -- a crit and a weak point at once: both
    list:add(hit(GUTS, GOB, { point = at(300, 300), weak_damage = true, target_bonus = 0.5 }), 450, 0, 1)
    draw(list, s, 0.3)
    local both = texts_in(Kit.actor_color("player", 10, 1))[1]
    eq(both.text, "450!", "the crit's «!»"); near(both.px, 18 * 1.4, 1e-9, "the crit's size")
    eq(#ui.calls_of("add_quad_filled"), 4, "and both diamonds")
    -- without add_quad_filled: a square, the call named and not tried again
    local quad = ui.draw_list.add_quad_filled
    ui.draw_list.add_quad_filled = nil
    draw(list, s, 0.3)
    eq(#ui.calls_of("add_rect_filled"), 4, "a dark square and a square for each")
    eq(table.concat(UI.missing(), ","), "add_quad_filled", "named")
    ui.draw_list.add_quad_filled = quad
    draw(list, s, 0.3)
    eq(#ui.calls_of("add_quad_filled"), 0, "not tried again")
    UI.reset()
    draw(list, s, 0.3)
    eq(#ui.calls_of("add_quad_filled"), 4, "until reset")
end)

test("a DoT tick: 0.8 × smaller, no pop", function()
    local s = fresh()
    local list = DamageNumbers.new()
    list:add(hit(nil, GOB, { status = "FireSpread", skill = { status = "FireSpread" }, target_bonus = 0.5 }), 41, 0)
    draw(list, s, 0)
    local c = texts_in(C.other)[1]
    eq(c.text, "41", "no «!»")
    near(c.px, 18 * 0.8, 1e-9, "0.8 × at once: no pop")
end)

test("an amount that shows as 0 waits for a hit to join it", function()
    local s = fresh()
    local list = DamageNumbers.new()
    list:add(hit(CASCA, GOB), 0.3, 0, 1)
    draw(list, s, 0)
    eq(#ui.calls, 0, "0.3 HP: nothing drawn")
    list:add(hit(CASCA, GOB), 0.3, 0.1, 1)
    draw(list, s, 0.1)
    eq(texts_in(Kit.actor_color("pawn", 5, 1))[1].text, "1", "0.6 HP: «1»")
end)

-- The plates' filled rectangles in `color` (whatever their alpha), in order.
local function rects_in(color)
    local list = {}
    for _, r in ipairs(ui.calls_of("add_rect_filled")) do
        if r.col & 0xFFFFFF == color & 0xFFFFFF then list[#list + 1] = r end
    end
    return list
end

test("plates: the attacker's colour at 80 %, a 1 px dark border, light text, 1.5 s, fading over the last 0.4 s", function()
    local s = fresh({ damage_numbers_style = "plates" })
    local list = DamageNumbers.new()
    list:add(hit(CASCA, GOB), 1234, 0, 1)
    local color = Kit.actor_color("pawn", 5, 1)
    draw(list, s, 0)
    local plate = rects_in(color)
    eq(#plate, 1, "one plate")
    plate = plate[1]
    eq(alpha_of(plate.col), 204, "at 80 %")
    eq(plate.layer, "background", "on the background list")
    local text = texts_in(C.text)
    eq(#text, 1, "light text")
    text = text[1]
    eq(text.text, "1 234", "the HP"); eq(text.px, 14, "14 px")
    local w = width("1 234", 14)
    near(plate.x1 - plate.x0, w + 10, 0.5, "5 px on each side of the text")
    near(plate.y1 - plate.y0, 14 + 4, 0.5, "2 px over and under it")
    near((plate.x0 + plate.x1) / 2, 800, 0.5, "centred on the point"); near((plate.y0 + plate.y1) / 2, 500, 0.5, "")
    near(text.x + w / 2, 800, 0.5, "the text in the middle of the plate")
    local edges = rects_in(C.shadow)
    eq(#edges, 4, "a border of four strips")
    local thick = 0
    for _, e in ipairs(edges) do thick = math.max(thick, math.min(e.x1 - e.x0, e.y1 - e.y0)) end
    eq(thick, 1, "1 px")
    eq(#texts_in(C.shadow), 1, "a dark shadow under the text")
    eq(#ui.calls_of("add_quad_filled"), 0, "no diamond")
    -- it stands: the same place later; opaque until 1.1 s, half faded at 1.3 s, gone at 1.5 s
    draw(list, s, 1.1)
    local later = rects_in(color)[1]
    eq(later.y0, plate.y0, "it does not rise"); eq(alpha_of(later.col), 204, "still at 80 %")
    draw(list, s, 1.3)
    eq(alpha_of(rects_in(color)[1].col), 102, "half faded: 40 %")
    near(alpha_of(texts_in(C.text)[1].col), 127.5, 0.5, "the text too")
    draw(list, s, 1.5)
    eq(#ui.calls, 0, "gone at 1.5 s")
    draw(list, s, 1.51)
    eq(#list.items, 0, "forgotten")
end)

test("plates: a crit's bigger with a 2 px gold border, a weak point's diamond, a DoT tick's smaller", function()
    local s = fresh({ damage_numbers_style = "plates" })
    local list = DamageNumbers.new()
    list:add(hit(CASCA, GOB, { target_bonus = 0.5, point = at(200, 200) }), 3800, 0, 1)
    draw(list, s, 0)
    local text = texts_in(C.text)[1]
    eq(text.text, "3 800", "no «!» on a plate")
    near(text.px, 14 * 1.4, 1e-9, "1.4 × bigger, no pop")
    local gold = rects_in(UI.GOLD)
    eq(#gold, 4, "a gold border")
    local thick = 0
    for _, e in ipairs(gold) do thick = math.max(thick, math.min(e.x1 - e.x0, e.y1 - e.y0)) end
    eq(thick, 2, "2 px")
    eq(#rects_in(C.shadow), 0, "no dark border")
    list:clear()
    list:add(hit(CASCA, GOB, { weak_damage = true, point = at(200, 200) }), 717, 0, 1)
    draw(list, s, 0)
    local quads = ui.calls_of("add_quad_filled")
    eq(#quads, 1, "a diamond")
    eq(quads[1].col, C.text, "in the text's colour")
    text = texts_in(C.text)[1]
    eq(text.px, 14, "not bigger")
    eq(quads[1].points[2].x < text.x, true, "before the number")
    eq(#rects_in(C.shadow), 4, "the plain border")
    list:clear()
    list:add(hit(nil, GOB, { status = "Poison", skill = { status = "Poison" }, point = at(200, 200) }), 12, 0)
    draw(list, s, 0)
    near(texts_in(C.text)[1].px, 14 * 0.8, 1e-9, "a DoT tick's plate smaller")
    eq(#rects_in(C.other), 1, "in grey")
end)

test("plates spacing: up, down, left, right, the diagonals, two up, two down, else the point", function()
    local place = UI.place
    local box = { 100, 100, 140, 120 } -- 40 × 20
    eq(select("#", place(box, {}, 2)), 2, "an offset")
    local dx, dy = place(box, {}, 2)
    eq(dx, 0, "nothing in the way: the point"); eq(dy, 0, "")
    local want = { { 0, -22 }, { 0, 22 }, { -42, 0 }, { 42, 0 }, { -42, -22 }, { 42, -22 }, { -42, 22 }, { 42, 22 },
        { 0, -44 }, { 0, 44 } }
    local taken = { { 100, 100, 140, 120 } }
    for i, w in ipairs(want) do
        dx, dy = place(box, taken, 2)
        eq(dx .. "," .. dy, w[1] .. "," .. w[2], "spot " .. i)
        taken[#taken + 1] = { box[1] + dx, box[2] + dy, box[3] + dx, box[4] + dy }
    end
    dx, dy = place(box, taken, 2)
    eq(dx .. "," .. dy, "0,0", "no free spot: the point")
    -- touching is no overlap; taken.n limits the list
    dx, dy = place(box, { { 140, 100, 180, 120 } }, 2)
    eq(dx .. "," .. dy, "0,0", "side by side is free")
    dx, dy = place(box, { { 100, 100, 140, 120 }, n = 0 }, 2)
    eq(dx .. "," .. dy, "0,0", "none of them counts")
    -- in a frame: a second plate over the first goes one plate height up, the third down; the offsets stay
    local s = fresh({ damage_numbers_style = "plates" })
    local list = DamageNumbers.new()
    list:add(hit(GUTS, GOB), 100, 0, 1)
    list:add(hit(CASCA, GOB), 200, 0.05, 1)
    list:add(hit(ALLY, GOB), 300, 0.1)
    draw(list, s, 0.1)
    local a = rects_in(Kit.actor_color("player", 10, 1))[1]
    local b = rects_in(Kit.actor_color("pawn", 5, 1))[1]
    local c = rects_in(C.ally)[1]
    local h = a.y1 - a.y0
    near((a.y0 + a.y1) / 2, 500, 0.5, "the first on the point")
    eq(b.y0, a.y0 - h - 2, "the second one plate height (and 2 px) up")
    eq(c.y0, a.y0 + h + 2, "the third down")
    eq(b.x0 + b.x1, a.x0 + a.x1, "centred above it")
    project = function(p) return { x = p.x + 50, y = p.y + 30 } end
    draw(list, s, 0.2)
    local a2, b2 = rects_in(Kit.actor_color("player", 10, 1))[1], rects_in(Kit.actor_color("pawn", 5, 1))[1]
    eq(a2.y0 - a.y0, 30, "the point moved"); eq(b2.y0 - b.y0, 30, "the moved plate with it")
    eq(b2.x0 - b.x0, 50, "")
end)

test("a projection that raises costs its number; draw never raises and stays balanced", function()
    local s = fresh()
    local list = DamageNumbers.new()
    list:add(hit(GUTS, GOB, { point = at(100, 100) }), 10, 0, 1)
    list:add(hit(CASCA, GOB, { point = at(300, 100) }), 20, 0, 1)
    project = function(p)
        if p.x == 100 then error("world_to_screen broke") end
        return { x = p.x, y = p.y }
    end
    ui.clear_calls()
    local err = UI.draw(list, s, 0)
    eq(type(err), "string", "the error comes back")
    eq(err:find("world_to_screen broke", 1, true) ~= nil, true, "its message")
    eq(#texts_in(Kit.actor_color("player", 10, 1)), 0, "that number is not drawn")
    eq(#texts_in(Kit.actor_color("pawn", 5, 1)), 1, "the other one is")
    eq(ui.balanced(), true, "balanced")
    project = function() return { x = "a", y = 1 } end
    draw(list, s, 0)
    eq(#ui.calls_of("add_text"), 0, "a projection that is not numbers: nothing")
    project = on_screen
    -- a draw list that breaks: the error comes back, the font size is popped
    local add_text = ui.draw_list.add_text
    ui.draw_list.add_text = function() error("draw list broke") end
    ui.clear_calls()
    eq(type(UI.draw(list, s, 0)), "string", "the error comes back")
    eq(ui.balanced(), true, "the font size popped again")
    ui.draw_list.add_text = add_text
    -- no list, no settings, a list that is not one
    eq(type(UI.draw(nil, s, 0)), "string", "no list")
    eq(type(UI.draw(list, nil, 0)), "string", "no settings")
    eq(type(UI.draw(5, s, 0)), "string", "a list that is not one")
    eq(ui.balanced(), true, "balanced")
    -- no world_to_screen, no display size, no background list: nothing drawn, the call named, not tried again
    local d = rawget(_G, "draw")
    rawset(_G, "draw", nil)
    draw(list, s, 0)
    eq(#ui.calls, 0, "no draw.world_to_screen: nothing")
    rawset(_G, "draw", d)
    draw(list, s, 0)
    eq(#ui.calls, 0, "not tried again")
    eq(table.concat(UI.missing(), ","), "world_to_screen", "named")
    UI.reset()
    for _, name in ipairs({ "get_display_size", "get_background_draw_list" }) do
        local fn = imgui[name]
        imgui[name] = nil
        draw(list, s, 0)
        eq(#ui.calls_of("add_text"), 0, "no " .. name .. ": nothing")
        imgui[name] = fn
        draw(list, s, 0)
        eq(#ui.calls_of("add_text"), 0, name .. " is not tried again")
        eq(table.concat(UI.missing(), ","), name, "and named")
        UI.reset()
        draw(list, s, 0)
        eq(#ui.calls_of("add_text"), 20, "until reset")
    end
end)

i18n.set("en")
T.finish()
