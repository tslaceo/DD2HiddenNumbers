package.path = "mod/reframework/autorun/?.lua;tests/?.lua;" .. package.path

local T = require("testlib")
local test, eq, near = T.test, T.eq, T.near
local Fight = require("DD2DamageMeter/fight")
local HistoryFile = require("DD2DamageMeter/history_file")
local json_decode = require("json_decode")
local i18n = require("DD2DamageMeter/i18n")
local Names = require("DD2DamageMeter/names")
local View = require("DD2DamageMeter/view")
local JournalTabs = require("DD2DamageMeter/journal_tabs")

local function actor(key, name, kind, chara_id)
    return { key = key, name = name, kind = kind, base_id = key, max_hp = 3000, chara_id = chara_id }
end

local PL = actor("ch000000_00", "Guts", "player", 2891076981)
local CASCA = actor("ch100000_00", "Casca", "pawn", 2283028347)
local GOB = actor("ch220003_00_15", "Goblin", "enemy", 52)

-- A fight with damage, a heal, an attack on the party and the enemy's data, as a full snapshot.
local function sample_snapshot()
    local f = Fight.new(10)
    f:add_hit({ t = 11, attacker = CASCA, victim = GOB, skill = { attack = "連なり撃ち_近距離", id = "CS_01", normal = nil },
        final = 405.1336, hp0 = 3053.035, hp1 = 2647.901, before = 479.45, after = 339.45, types = { Slash = 339.45 },
        element = "None", region = { before = { Slash = 339.45 }, after = { Slash = 339.45 }, no = 3, part = "head" },
        foe = { chara_id = 52, weak = 3, resist = 0, defence = 12.5, magic_defence = 8, enabled = 255 } })
    f:add_hit({ t = 12, attacker = GOB, victim = PL, skill = { attack = "enemy" }, final = 80, hp0 = 2400, hp1 = 2320,
        types = { Blow = 80 } })
    f:add_heal({ t = 13, target = PL, healer = CASCA, amount = 100, effective = 90,
        source = { kind = "skill", name = "Bolt\"Mend\\" } })
    f:finish(15, "end")
    return f:snapshot(15, true)
end

-- Deep equality; numbers within a tolerance (the text keeps 10 significant digits).
local function same(a, b, path)
    path = path or "snapshot"
    if type(a) ~= type(b) then error(path .. ": " .. type(a) .. " against " .. type(b), 0) end
    if type(a) == "number" then
        if math.abs(a - b) > 1e-6 * math.max(1, math.abs(a)) then error(path .. ": " .. a .. " against " .. b, 0) end
    elseif type(a) == "table" then
        for k, v in pairs(a) do same(v, b[k], path .. "." .. tostring(k)) end
        for k in pairs(b) do
            if a[k] == nil then error(path .. "." .. tostring(k) .. ": unexpected", 0) end
        end
    elseif a ~= b then
        error(path .. ": " .. tostring(a) .. " against " .. tostring(b), 0)
    end
end

-- A snapshot-shaped table of about `size` bytes in the file.
local function fat(id, size)
    return { duration = id, actors = {}, enemies = {}, pad = string.rep("x", size - 60) }
end

local function count(text, needle)
    return select(2, text:gsub(needle, ""))
end

test("round trip keeps a fight", function()
    local snap = sample_snapshot()
    local text = HistoryFile.encode_fight(snap)
    eq(text:sub(1, 7), '{"v":2,', "the version leads the object")
    local back = HistoryFile.unpack({ json_decode(text) })
    eq(#back, 1, "one fight")
    local s = back[1]
    near(s.duration, 5, 1e-9, "duration")
    near(s.actors[CASCA.key].dealt, 405.134, 1e-6, "an actor's dealt")
    near(s.detail.foes[GOB.key].types.Slash.dealt, 405.134, 1e-6, "the enemy's damage by type")
    near(s.detail.foes[GOB.key].by_part.head.Slash.before, 339.45, 1e-6, "the head's damage by type, before")
    near(s.detail.foes[GOB.key].by_part.head.Slash.after, 339.45, 1e-6, "and after the region step")
    eq(type(s.detail.foes[GOB.key].by_part.body), "table", "the body, not hit, still there")
    eq(#s.detail.record, 3, "the record")
    eq(s.detail.foes[GOB.key].by[CASCA.key].skills["連なり撃ち_近距離"].ref.id, "CS_01", "a skill's name")
    eq(s.detail.kinds.c52.weak, 3, "the enemy's data")
    eq(s.detail.heals[CASCA.key][PL.key]["skill:Bolt\"Mend\\"].n, 1, "a heal with a key that needs escaping")
    eq(s.v, nil, "a snapshot in memory has no version")
    same(snap, s)
end)

test("round trip keeps the time of an enemy's latest hit; an entry kept without it loads", function()
    local f = Fight.new(36500.5)
    f:add_hit({ t = 36512.125, attacker = CASCA, victim = GOB, skill = { attack = "x" }, final = 10, hp0 = 3000,
        hp1 = 2990 })
    f:finish(36520, "end")
    local snap = f:snapshot(36520)
    eq(snap.enemies[GOB.key].last_hit, 36512.125, "the hit's time")
    local text = HistoryFile.encode_fight(snap)
    local back = HistoryFile.unpack({ json_decode(text) })[1]
    near(back.enemies[GOB.key].last_hit, 36512.125, 1e-9, "kept")
    -- a fight kept before the time was: it loads, without one
    local old = json_decode(text)
    old.enemies[GOB.key].last_hit = nil
    local loaded = HistoryFile.unpack({ old })
    eq(#loaded, 1, "it loads")
    eq(loaded[1].enemies[GOB.key].last_hit, nil, "no time")
    near(loaded[1].enemies[GOB.key].hp, 2990, 1e-9, "the rest as it was")
end)

test("the snapshot is left as it was, and a loaded one encodes with one version", function()
    local snap = sample_snapshot()
    local keys = 0
    for _ in pairs(snap) do keys = keys + 1 end
    local text = HistoryFile.encode_fight(snap)
    eq(snap.v, nil, "no version on the snapshot")
    local after = 0
    for _ in pairs(snap) do after = after + 1 end
    eq(after, keys, "no field added")
    local loaded = HistoryFile.unpack({ json_decode(text) })[1]
    local again = HistoryFile.encode_fight(loaded)
    eq(count(again, '"v":2'), 1, "one version, not two")
    eq(count(again, '^{"v":2,'), 1, "and first")
    same(snap, HistoryFile.unpack({ json_decode(again) })[1])
end)

test("encode: arrays, objects and the skipped", function()
    eq(HistoryFile.encode({ 1, 2, 3 }), "[1,2,3]", "an array")
    eq(HistoryFile.encode({}), "{}", "an empty table is an object")
    eq(HistoryFile.encode({ a = 1 }), '{"a":1}', "an object")
    eq(HistoryFile.encode({ { n = 1 }, { n = 2 } }), '[{"n":1},{"n":2}]', "nested")
    eq(HistoryFile.encode({ true, false }), "[true,false]", "booleans")
    local sparse = json_decode(HistoryFile.encode({ [1] = "a", [3] = "c" }))
    eq(sparse["1"], "a", "keys that are not 1..n make an object (key 1)")
    eq(sparse["3"], "c", "(key 3)")
    eq(HistoryFile.encode({ a = 1, f = print, u = io.stdout }), '{"a":1}', "functions and userdata are skipped")
    eq(HistoryFile.encode({ 1, print, 3 }), "[1,null,3]", "and leave a null in an array")
    eq(HistoryFile.encode(print), "null", "alone too")
    eq(HistoryFile.encode(nil), "null", "nil too")
    eq(HistoryFile.encode(true), "true", "a boolean")
    local mixed = json_decode(HistoryFile.encode({ 1, 2, name = "x" }))
    eq(mixed["1"], 1, "a table with an array part and a field is an object")
    eq(mixed.name, "x", "with its field")
end)

test("encode: integers as %d, other numbers as %.10g", function()
    eq(HistoryFile.encode(7), "7", "integer")
    eq(HistoryFile.encode(-3), "-3", "negative integer")
    eq(HistoryFile.encode(2891076981), "2891076981", "a CharaID")
    eq(HistoryFile.encode(2.5), "2.5", "float")
    eq(HistoryFile.encode(5.0), "5", "a whole float")
    eq(HistoryFile.encode(1 / 3), "0.3333333333", "ten digits")
    eq(HistoryFile.encode(52898.123456789), "52898.12346", "ten significant digits")
    eq(math.type(json_decode(HistoryFile.encode(7))), "integer", "an integer reads back as one")
end)

test("non-finite numbers become 0", function()
    local back = json_decode(HistoryFile.encode({ nan = 0 / 0, up = math.huge, down = -math.huge, ok = 1.5 }))
    eq(back.nan, 0, "nan")
    eq(back.up, 0, "+inf")
    eq(back.down, 0, "-inf")
    eq(back.ok, 1.5, "a finite one stays")
    eq(HistoryFile.encode({ [math.huge] = 1 }), '{"0":1}', "an infinite key")
end)

-- Runs fn(name) under each of these locales of `category` that the system has (on a system without them fn does not
-- run) and goes back to the locale it found, also when fn raises.
local function under_locales(category, names, fn)
    local before = os.setlocale(nil, category)
    for _, name in ipairs(names) do
        if os.setlocale(name, category) then
            local ok, err = pcall(fn, name)
            os.setlocale(before, category)
            if not ok then error(err, 0) end
        end
    end
    os.setlocale(before, category)
end

test("the bytes escaped do not depend on the locale", function()
    -- the control bytes, " and \ are escaped, every other ASCII byte is written as it is
    for byte = 0, 127 do
        local c = string.char(byte)
        local want = (byte < 32 or byte == 127) and string.format('"\\u%04x"', byte)
            or (c == '"' and '"\\""') or (c == "\\" and '"\\\\"') or ('"' .. c .. '"')
        eq(HistoryFile.encode(c), want, "byte " .. byte)
    end
    -- Windows code pages count some bytes over 127 as control characters (1252: 0x81 0x8d 0x8f 0x90 0x9d, 1251:
    -- 0x98); the UTF-8 of Japanese attack names (0x83, 0x9d) and of Cyrillic names (0x81, 0x8d, 0x98) has them
    local texts = { "ヒーリングスポット", "しがみ付き", "Гость", "Иван", "Шэрон" }
    under_locales("ctype", { ".1252", ".1251", "de-DE", "ru-RU" }, function(locale)
        for _, s in ipairs(texts) do eq(HistoryFile.encode(s), '"' .. s .. '"', s .. " under " .. locale) end
        eq(HistoryFile.encode("a\1b\127"), '"a\\u0001b\\u007f"', "control bytes under " .. locale)
        eq(HistoryFile.encode("ab\255"), '"ab\\u00ff"', "a string that is not UTF-8 under " .. locale)
    end)
end)

test("numbers keep their decimal point under a decimal-comma locale", function()
    -- a C library that writes 1,5 (simulated)
    local format = string.format
    string.format = function(spec, ...)
        return (format(spec, ...):gsub("%.", ","))
    end
    local ok, a, b, c = pcall(function()
        return HistoryFile.encode(1.5), HistoryFile.encode({ x = 1 / 3 }), HistoryFile.encode({ [2.5] = 1 })
    end)
    string.format = format
    eq(ok, true, "encode: " .. tostring(a))
    eq(a, "1.5", "a float"); eq(b, '{"x":0.3333333333}', "in an object"); eq(c, '{"2.5":1}', "as a key")
    -- the system's own locales that write a comma
    under_locales("numeric", { "ru-RU", "de-DE", "Russian_Russia.1251" }, function(locale)
        if string.format("%.1f", 1.5) ~= "1,5" then return end
        eq(HistoryFile.encode(1.5), "1.5", "a float under " .. locale)
        eq(HistoryFile.encode(52898.123456789), "52898.12346", "ten digits under " .. locale)
        eq(HistoryFile.encode(7), "7", "an integer under " .. locale)
    end)
end)

test("strings are escaped", function()
    local tricky = 'a"b\\c\nd\te\0f\1'
    local text = HistoryFile.encode({ s = tricky, [tricky] = 1 })
    eq(text:find("\n", 1, true), nil, "no raw newline in the text")
    eq(text:find("%c"), nil, "no raw control character")
    local back = json_decode(text)
    eq(back.s, tricky, "the string comes back")
    eq(back[tricky], 1, "so does a key")
    eq(HistoryFile.encode("連なり撃ち"), '"連なり撃ち"', "UTF-8 passes as it is")
    eq(json_decode(HistoryFile.encode("連なり撃ち")), "連なり撃ち", "and reads back")
    eq(HistoryFile.encode("a\1b"), '"a\\u0001b"', "a control character as \\uXXXX")
end)

test("a string that is not UTF-8 cannot spoil the file", function()
    local text = HistoryFile.encode({ s = "ab\255\254c" })
    eq(text:find("[\128-\255]"), nil, "only ASCII is written")
    eq(utf8.len(text), #text, "and it is valid UTF-8")
    eq(HistoryFile.encode("é"), '"é"', "a valid one is still written as it is")
end)

test("encode_fight is remembered", function()
    local snap = { duration = 1, actors = {}, enemies = {} }
    local first = HistoryFile.encode_fight(snap)
    snap.duration = 99
    eq(HistoryFile.encode_fight(snap), first, "the second call gives the first text without looking again")
    eq(HistoryFile.encode_fight({ duration = 99, actors = {}, enemies = {} }) ~= first, true, "another snapshot is its own")
    local watch = setmetatable({}, { __mode = "v" })
    local function encode_and_forget()
        local gone = { duration = 2, actors = {}, enemies = {} }
        HistoryFile.encode_fight(gone)
        watch[1] = gone
    end
    encode_and_forget()
    collectgarbage()
    collectgarbage()
    eq(watch[1], nil, "the memory of a fight does not keep the snapshot alive")
end)

test("pack stops at the byte cap", function()
    local a, b, c = fat(3, 1000), fat(2, 1000), fat(1, 1000)
    local size = #HistoryFile.encode_fight(a)
    eq(size >= 950 and size <= 1050, true, "about 1000 bytes each, got " .. size)
    local text, kept = HistoryFile.pack({ a, b, c }, 2500)
    eq(kept, 2, "two fights fit")
    local back = json_decode(text)
    eq(#back, 2, "and are in the text")
    eq(back[1].duration, 3, "the newest first")
    eq(back[2].duration, 2, "then the next")
    eq(#text <= 2500, true, "under the cap")

    local exact = 2 + #HistoryFile.encode_fight(a) + 1 + #HistoryFile.encode_fight(b)
    eq(select(2, HistoryFile.pack({ a, b, c }, exact)), 2, "a text that is exactly the cap fits")
    eq(select(2, HistoryFile.pack({ a, b, c }, exact - 1)), 1, "one byte less and the older fight stays out")
    local none, zero = HistoryFile.pack({ a, b }, 500)
    eq(none, "[]", "a first fight over the cap leaves nothing")
    eq(zero, 0, "kept 0")
    local empty, n = HistoryFile.pack({}, 100)
    eq(empty, "[]", "no fights")
    eq(n, 0, "kept 0")
    eq(select(2, HistoryFile.pack({ a, b, c })), 3, "the default cap is MAX_BYTES")
    eq(HistoryFile.MAX_BYTES, 4 * 1024 * 1024, "4 MB")
    eq(HistoryFile.FORMAT, 2, "format")
end)

test("pack does not encode the fights past the one that stopped it", function()
    local untouched = setmetatable({}, { __pairs = function() error("a fight past the cap was encoded") end })
    local text, kept = HistoryFile.pack({ fat(3, 1000), fat(2, 1000), untouched }, 1200)
    eq(kept, 1, "one fits")
    eq(#json_decode(text), 1, "one in the text")
end)

test("unpack drops foreign entries", function()
    local good = { v = 2, actors = {}, enemies = {}, duration = 4, marker = "good" }
    local list = {
        { v = 1, actors = {}, enemies = {}, duration = 1 },                    -- another format
        { v = 2, enemies = {}, duration = 2 },                                 -- no actors
        { v = 2, actors = {}, duration = 2 },                                  -- no enemies
        { v = 2, actors = {}, enemies = {}, duration = "3" },                  -- duration not a number
        { v = 2, actors = "x", enemies = {}, duration = 3 },                   -- actors not a table
        "a string",
        good,
        { actors = {}, enemies = {}, duration = 5 },                           -- no version
        { v = 2, actors = {}, enemies = {}, duration = 6, marker = "second" },
    }
    local back = HistoryFile.unpack(list)
    eq(#back, 2, "two valid fights")
    eq(back[1].marker, "good", "in the order of the file")
    eq(back[2].marker, "second", "(second)")
    eq(#HistoryFile.unpack("x"), 0, "a string is no file")
    eq(#HistoryFile.unpack(nil), 0, "nil is no file")
    eq(#HistoryFile.unpack(42), 0, "a number is no file")
    eq(#HistoryFile.unpack({}), 0, "an empty file")
    eq(#HistoryFile.unpack({ v = 2, actors = {}, enemies = {}, duration = 1 }), 0, "one fight that is not in an array")
    eq(#HistoryFile.unpack(setmetatable({}, { __len = function() error("boom") end })), 0, "a table that raises")
end)

-- A fight kept before the self-effects were told apart (Blood Pact's cost, the heals with no source and an
-- enemy's fall under «Прочее») loads as it was written; nothing of it moves to a member or to «Падения и среда».
test("an old fight's «Прочее» loads unchanged", function()
    local f = Fight.new(10)
    f:add_hit({ t = 11, attacker = CASCA, victim = GOB, skill = { attack = "N_軽" }, final = 100, hp0 = 3000, hp1 = 2900 })
    f:add_hit({ t = 12, attacker = nil, victim = PL, skill = {}, final = 1.6, hp0 = 3000, hp1 = 2998.4 })
    f:add_hit({ t = 13, attacker = nil, victim = GOB, skill = {}, final = 1000, hp0 = 2900, hp1 = 1900 })
    f:add_heal({ t = 14, target = PL, amount = 100, effective = 100, source = { kind = "other" } })
    f:finish(15, "end")
    local old = f:snapshot(15, true)
    local text = HistoryFile.encode_fight(old)
    local loaded = HistoryFile.unpack({ json_decode(text) })[1]
    same(old, loaded)
    same(old, HistoryFile.unpack({ json_decode(HistoryFile.encode_fight(loaded)) })[1])
    i18n.set("ru")
    local ctx = { names = Names.new({ enemy = function() return "Гоблин" end }), i18n = i18n }
    local m = View.live(loaded, 15, ctx)
    local names = {}
    for _, r in ipairs(m.damage.rows) do names[#names + 1] = r.name end
    eq(table.concat(names, ", "), "Casca, Прочее", "the fall stays «Прочее»'s")
    eq(m.taken.rows[1].label, "Прочее → Guts", "the HP cost stays «Прочее»'s")
    eq(m.heal.rows[1].name, "Прочее", "the heal too")
    eq(JournalTabs.party(loaded, ctx).members[1].rows[1].name, "Прочее", "the journal's «Получено»")
    eq(JournalTabs.heal(loaded, ctx).healers[1].key, "other", "the journal's «Лечение»")
    eq(loaded.actors.env, nil, "no «Падения и среда» made up")
    i18n.set("en")
end)

-- A fight with a member's own damage and heals and an enemy's fall is saved and loaded with them.
test("a fight with «Падения и среда» and a member's own entries round-trips", function()
    local f = Fight.new(10)
    f:add_hit({ t = 11, attacker = CASCA, victim = GOB, skill = { attack = "N_軽" }, final = 100, hp0 = 3000, hp1 = 2900 })
    f:add_hit({ t = 12, attacker = nil, victim = PL, skill = {}, final = 1.6, hp0 = 3000, hp1 = 2998.4,
        own = "blood_pact" })
    f:add_hit({ t = 12.5, attacker = nil, victim = CASCA, skill = {}, final = 4, hp0 = 3000, hp1 = 2996, own = "self" })
    f:add_hit({ t = 13, attacker = nil, victim = GOB, skill = {}, final = 5000, hp0 = 2900, hp1 = 0, own = "self",
        types = { Fixed = 5000 } })
    f:add_heal({ t = 14, target = PL, healer = PL, amount = 120, effective = 120,
                 source = { kind = "self", name = "lifesteal" } })
    f:add_heal({ t = 14.5, target = PL, healer = PL, amount = 2, effective = 2, source = { kind = "self", name = "regen" } })
    f:finish(15, "win")
    local snap = f:snapshot(15, true)
    local loaded = HistoryFile.unpack({ json_decode(HistoryFile.encode_fight(snap)) })[1]
    same(snap, loaded)
    near(loaded.actors.env.dealt, 2900, 1e-6, "«Падения и среда»'s damage")
    eq(loaded.enemies[GOB.key].killer, "env", "its kill")
    near(loaded.actors[PL.key].taken_from["self:blood_pact"], 1.6, 1e-6, "Blood Pact's cost")
    near(loaded.actors[CASCA.key].taken_from["self:self"], 4, 1e-6, "his own")
    near(loaded.actors[PL.key].heal_sources["self:lifesteal"], 120, 1e-6, "lifesteal")
    eq(loaded.detail.heals[PL.key][PL.key]["self:regen"].n, 1, "the detail's own heal")
    eq(loaded.detail.foes[GOB.key].by.env.hits, 1, "the card's dealer")
    i18n.set("ru")
    local ctx = { names = Names.new({ enemy = function() return "Гоблин" end }), i18n = i18n }
    local m = View.live(loaded, 15, ctx)
    local rows = {}
    for _, r in ipairs(m.damage.rows) do rows[#rows + 1] = r.name end
    eq(table.concat(rows, ", "), "Casca, Падения и среда", "the meter's damage rows")
    rows = {}
    for _, r in ipairs(m.taken.rows) do rows[#rows + 1] = r.label end
    eq(table.concat(rows, ", "), "Сам себе → Casca, Пакт крови → Guts", "the meter's damage to the party")
    local what = {}
    for _, r in ipairs(JournalTabs.record(loaded, ctx).rows) do what[#what + 1] = r.who .. ":" .. r.what end
    eq(table.concat(what, ", "), "Casca:Обычные атаки, Guts:Пакт крови, Casca:Сам себе, Падения и среда:Прочее, "
        .. "Guts:Вампиризм, Guts:Восстановление", "the record")
    i18n.set("en")
end)

-- A fight kept before linked bodies has both Evil Eye bodies; it loads with both, nothing merged.
test("an old fight with two bodies of one pool loads unchanged", function()
    local A = { key = "a301", name = "ch270000_00", kind = "enemy", base_id = "ch270000_00", chara_id = 469873306,
                max_hp = 650000 }
    local B = { key = "a302", name = "ch270000_00", kind = "enemy", base_id = "ch270000_00", chara_id = 469873306,
                max_hp = 650000 }
    local f = Fight.new(10)
    f:add_hit({ t = 11, attacker = CASCA, victim = A, skill = { attack = "x" }, final = 1000, hp0 = 650000, hp1 = 649000 })
    f:add_hit({ t = 11, victim = B, skill = {}, final = 1000, hp0 = 650000, hp1 = 649000, own = "self" })
    f:add_hit({ t = 12, attacker = CASCA, victim = B, skill = { attack = "x" }, final = 500, hp0 = 649000, hp1 = 648500 })
    f:add_hit({ t = 12, victim = A, skill = {}, final = 500, hp0 = 649000, hp1 = 648500, own = "self" })
    f:finish(15, "end")
    local old = f:snapshot(15, true)
    local loaded = HistoryFile.unpack({ json_decode(HistoryFile.encode_fight(old)) })[1]
    same(old, loaded)
    eq(loaded.enemies[A.key] ~= nil and loaded.enemies[B.key] ~= nil, true, "both bodies, as kept")
    near(loaded.actors.env.dealt, 1500, 1e-6, "its «Падения и среда» as kept")
end)

test("unpack gives a CharaID back as an integer", function()
    local fight = { v = 2, actors = { a1 = { actor = { chara_id = 2891076981.0 } }, a2 = { actor = { chara_id = 5 } },
        a3 = { actor = {} }, a4 = "x" }, enemies = { e1 = { actor = { chara_id = 52.0 } } }, duration = 1 }
    local s = HistoryFile.unpack({ fight })[1]
    eq(math.type(s.actors.a1.actor.chara_id), "integer", "a whole float becomes an integer")
    eq(s.actors.a1.actor.chara_id, 2891076981, "(value)")
    eq(s.actors.a2.actor.chara_id, 5, "an integer stays")
    eq(math.type(s.enemies.e1.actor.chara_id), "integer", "an enemy's too")
    eq("c" .. s.enemies.e1.actor.chara_id, "c52", "the key of its kind")
end)

T.finish()
