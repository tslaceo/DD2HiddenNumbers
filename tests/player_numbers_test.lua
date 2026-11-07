package.path = "mod/reframework/autorun/?.lua;tests/?.lua;" .. package.path

local T = require("testlib")
local test, eq, near = T.test, T.eq, T.near
local ui = require("stubs/ui").install()
local i18n = require("DD2DamageMeter/i18n")
local Settings = require("DD2DamageMeter/settings")
local EnemyBars = require("DD2DamageMeter/ui/enemy_bars")
local PlayerNumbers = require("DD2DamageMeter/ui/player_numbers")

-- The bars as gauges.player gives them, where the probe saw their full-length backgrounds: the HP bar's left
-- end and top, 780 × 7; the stamina bar's, 780 × 6.
local function hud()
    return { hp = { x = 669.8, y = 1010, width = 780, height = 7 },
             sp = { x = 669.8, y = 1026.6, width = 780, height = 6 } }
end

-- The numbers as game/player_vitals.lua gives them: after a few hits, the cut max, stamina while sprinting;
-- `over`'s values instead, its `none` (a name) unread.
local function vitals(over)
    local v = { hp = 3030.84, hp_max = 3030.84, hp_full = 3100, sp = 1202, sp_max = 1300, sp_full = 1300 }
    for k, x in pairs(over or {}) do v[k] = x end
    local none = v.none
    v.none = nil
    if none then v[none] = nil end
    return v
end

local BEIGE, SHADOW, OUTLINE = 0xFFB2DBEA, 0xAB000000, 0xFF000000

local function fresh(over)
    ui.reset()
    PlayerNumbers.reset()
    i18n.set("ru")
    local saved = over or {}
    return Settings.load({ read = function() return saved end, write = function(t) saved = t end })
end

-- One frame; a drawing error fails the test, the stacks must balance.
local function draw(bars, v, s)
    ui.clear_calls()
    local err = PlayerNumbers.draw(bars, v, s)
    if err then error("draw failed: " .. err, 2) end
    eq(ui.balanced(), true, "stacks balanced")
end

-- The texts drawn in the text colour (not the shadow or outline copies), in order.
local function texts()
    local list = {}
    for _, c in ipairs(ui.calls_of("add_text")) do
        if c.col == BEIGE then list[#list + 1] = c end
    end
    return list
end

local function joined()
    local out = {}
    for _, c in ipairs(texts()) do out[#out + 1] = c.text end
    return table.concat(out, "|")
end

-- The width the stub gives `text` at `px`.
local function width(text, px)
    return utf8.len(text) * ui.char_w * px / 14
end

test("the text: now / the cut max, and the full max in brackets while the two differ once rounded", function()
    i18n.set("ru")
    local text = PlayerNumbers.text
    eq(text(3030.84, 3030.84, 3100), "3 031 / 3 031 (3 100)", "after a few hits: the max cut")
    eq(text(3100, 3100, 3100), "3 100 / 3 100", "at the full max: no brackets")
    eq(text(1202, 1300, 1300), "1 202 / 1 300", "the stamina")
    eq(text(-120, 1300, 1300), "-120 / 1 300", "a stamina below 0, with its sign")
    eq(text(-120.4, 1300, 1300), "-120 / 1 300", "rounded as i18n.num does")
    eq(text(3099.6, 3099.6, 3100), "3 100 / 3 100", "maxima equal once rounded (3 099.6 and 3 100): no brackets")
    eq(text(3099.4, 3099.4, 3100), "3 099 / 3 099 (3 100)", "3 099.4 and 3 100 differ")
    eq(text(0, 310, 3100), "0 / 310 (3 100)", "down to its least, 10 %")
    -- a value that is not a finite number: no text
    for _, bad in ipairs({ { nil, 1, 1 }, { 1, nil, 1 }, { 1, 1, nil }, { "1", 1, 1 }, { 0 / 0, 1, 1 },
                           { 1, math.huge, 1 }, { 1, 1, -math.huge } }) do
        eq(text(bad[1], bad[2], bad[3]), nil, "no text for " .. tostring(bad[1]) .. ", " .. tostring(bad[2]) .. ", "
            .. tostring(bad[3]))
    end
    i18n.set("en")
    eq(text(3030.84, 3030.84, 3100), "3 031 / 3 031 (3 100)", "the same in English")
end)

test("HP above its bar's right end, stamina below its bar's right end, on 1920 × 1080 and 2560 × 1440", function()
    for _, case in ipairs({ { 1920, 1080, 1, 1 }, { 2560, 1440, 1, 1 }, { 2560, 1440, 1.18, 1 },
                            { 1920, 1080, 1.5, 2 } }) do
        local dw, dh, scale, size = case[1], case[2], case[3], case[4]
        local what = dw .. " × " .. dh .. " at scale " .. scale .. ", size " .. size
        local s = fresh({ scale = scale, enemy_hp_size = size })
        ui.display = { x = dw, y = dh }
        local bars = hud()
        draw(bars, vitals(), s)
        local list = texts()
        eq(#list, 2, "two texts at " .. what)
        local hp, sp = list[1], list[2]
        eq(hp.text, "3 031 / 3 031 (3 100)", "the HP at " .. what)
        eq(sp.text, "1 202 / 1 300", "the stamina at " .. what)
        local px = 15 * scale * size
        near(hp.px, px, 1e-9, "the enemy numbers' 15 px × scale × enemy_hp_size at " .. what)
        near(sp.px, px, 1e-9, "the stamina's too at " .. what)
        -- a bar's left end lands at x × W / 1920, its top at y × H / 1080; its width and height × H / 1080
        local unit = dh / 1080
        local hp_right = bars.hp.x * dw / 1920 + bars.hp.width * unit
        local hp_top = bars.hp.y * unit
        near(hp.x + width(hp.text, px), hp_right, 0.5, "the HP text's right edge at its bar's right end at " .. what)
        near(hp.y + px, hp_top - 3 * scale, 0.5, "its bottom 3 px × scale above the bar's top at " .. what)
        local sp_right = bars.sp.x * dw / 1920 + bars.sp.width * unit
        local sp_bottom = (bars.sp.y + bars.sp.height) * unit
        near(sp.x + width(sp.text, px), sp_right, 0.5, "the stamina text's right edge at its bar's right end at "
            .. what)
        near(sp.y, sp_bottom + 3 * scale, 0.5, "its top 3 px × scale below the bar's bottom at " .. what)
        for _, c in ipairs(list) do
            eq(c.x, math.floor(c.x), "a whole pixel"); eq(c.y, math.floor(c.y), "a whole pixel")
            eq(c.layer, "background", "on the background list: under every window")
        end
    end
    -- on 2560 × 1440: the HP bar ends at about 1933 px (its 780 units are the 1040 px of a screenshot)
    local s = fresh()
    ui.display = { x = 2560, y = 1440 }
    draw(hud(), vitals(), s)
    local hp = texts()[1]
    near(hp.x + width(hp.text, 15), 669.8 * 2560 / 1920 + 1040, 0.5, "the right end at 893 + 1040 px")
    near(hp.y + 15, 1010 * 1440 / 1080 - 3, 0.5, "the bottom 3 px over the bar's top, 1344 px")
    -- the size read each frame: a longer HP bar (a higher max HP) moves the HP text, not the stamina's
    local bars = hud()
    bars.hp.width = 806
    local sp_x = texts()[2].x
    draw(bars, vitals(), s)
    near(texts()[1].x + width(texts()[1].text, 15), 669.8 * 2560 / 1920 + 806 * 1440 / 1080, 0.5, "the new end")
    eq(texts()[2].x, sp_x, "the stamina text stays")
end)

test("in the enemy numbers' fixed look: beige over black outline copies over a black shadow, whatever the meter's look",
    function()
    local s = fresh()
    draw(hud(), vitals(), s)
    local calls = ui.calls_of("add_text")
    eq(#calls, 20, "for each text the shadow, eight outline copies, the text")
    for k = 0, 1 do
        local text = calls[k * 10 + 10]
        eq(text.col, BEIGE, "the text in the pawn names' beige")
        eq(text.col, EnemyBars.COLORS.text, "the enemy numbers' colour")
        local shadow = calls[k * 10 + 1]
        eq(shadow.col, SHADOW, "a black shadow"); eq(shadow.text, text.text, "the text again")
        eq(shadow.x - text.x, 2, "2 px right"); eq(shadow.y - text.y, 2, "2 px down")
        for i = 2, 9 do
            local c = calls[k * 10 + i]
            eq(c.col, OUTLINE, "black outline copies")
            eq(math.max(math.abs(c.x - text.x), math.abs(c.y - text.y)), 1, "one px off")
        end
    end
    eq(#ui.calls_of("add_rect_filled"), 0, "no halo, no plate")
    local function frame_of(over)
        draw(hud(), vitals(), fresh(over))
        local out = {}
        for _, c in ipairs(ui.calls_of("add_text")) do
            out[#out + 1] = string.format("%s,%s,%x,%s,%s", c.x, c.y, c.col, c.text, c.px)
        end
        return table.concat(out, "|") .. "|" .. #ui.calls_of("add_rect_filled")
    end
    local base = frame_of({})
    for _, over in ipairs({ { style = "panel" }, { shadow = 0 }, { outline = false }, { halo = true, opacity = 1 },
                            { enemy_hp_numbers = "off", boss_hp_numbers = "off" } }) do
        eq(frame_of(over), base, "the same with another look of the meter or the enemy numbers off")
    end
end)

test("a bar without its element or its numbers gets no text; nothing at all when neither has", function()
    local s = fresh()
    local bars = hud()
    bars.sp = nil
    draw(bars, vitals(), s)
    eq(joined(), "3 031 / 3 031 (3 100)", "no stamina bar: the HP alone")
    bars = hud()
    bars.hp = nil
    draw(bars, vitals(), s)
    eq(joined(), "1 202 / 1 300", "no HP bar: the stamina alone")
    draw(hud(), vitals({ none = "hp_full" }), s)
    eq(joined(), "1 202 / 1 300", "an HP value missing: the stamina alone")
    draw(hud(), vitals({ sp = "x" }), s)
    eq(joined(), "3 031 / 3 031 (3 100)", "a stamina value that is not a number: the HP alone")
    bars = hud()
    bars.hp.width = 0 / 0
    draw(bars, vitals(), s)
    eq(joined(), "1 202 / 1 300", "an HP bar whose width is not a number")
    -- neither: not even an imgui call
    for _, case in ipairs({ { {}, vitals(), "no bars" }, { hud(), {}, "no numbers" },
                            { { hp = hud().hp }, vitals({ none = "hp" }), "the HP bar without its numbers" } }) do
        draw(case[1], case[2], s)
        eq(#ui.calls, 0, case[3] .. ": no imgui call")
    end
end)

test("draw never raises and stays balanced; a missing imgui call is named, not tried again until reset", function()
    local s = fresh()
    local add_text = ui.draw_list.add_text
    ui.draw_list.add_text = function() error("draw list broke") end
    ui.clear_calls()
    local err = PlayerNumbers.draw(hud(), vitals(), s)
    eq(type(err), "string", "the error comes back")
    eq(ui.balanced(), true, "the font size popped again")
    ui.draw_list.add_text = add_text
    -- junk: nothing raises, nothing is drawn
    ui.clear_calls()
    for _, case in ipairs({ { nil, vitals(), s }, { 5, vitals(), s }, { hud(), nil, s }, { hud(), "x", s },
                            { { hp = 5, sp = "x" }, vitals(), s }, { { hp = { x = "a", y = 1, width = 2, height = 3 } },
                              vitals(), s } }) do
        eq(PlayerNumbers.draw(case[1], case[2], case[3]), nil, "junk: nothing, no error")
    end
    eq(type(PlayerNumbers.draw(hud(), vitals(), nil)), "string", "no settings")
    eq(type(PlayerNumbers.draw(hud(), vitals(), { values = { scale = "big", enemy_hp_size = 1 } })), "string",
        "a scale that is not a number")
    eq(ui.balanced(), true, "balanced")
    eq(#ui.calls_of("add_text"), 0, "nothing drawn")
    for _, name in ipairs({ "get_display_size", "get_background_draw_list" }) do
        local fn = imgui[name]
        imgui[name] = nil
        draw(hud(), vitals(), s)
        eq(#ui.calls_of("add_text"), 0, "no " .. name .. ": nothing")
        imgui[name] = fn
        draw(hud(), vitals(), s)
        eq(#texts(), 0, name .. " is not tried again")
        eq(table.concat(PlayerNumbers.missing(), ","), name, "and named")
        PlayerNumbers.reset()
        draw(hud(), vitals(), s)
        eq(#texts(), 2, "until reset")
    end
end)

i18n.set("en")
T.finish()
