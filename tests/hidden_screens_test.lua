package.path = "mod/reframework/autorun/?.lua;tests/?.lua;" .. package.path

local T = require("testlib")
local test, eq, near = T.test, T.eq, T.near
local R = require("stubs/reframework")

local STATIC = { static = true }
local FIND = "findComponents(System.Type)"
local GET_COMPONENT = "getComponent(System.Type)"
local DETAIL = "getAbilityDetail(app.HumanAbilityID)"
local GET_ABILITY = "getAbility(app.Character.JobEnum, app.AbilityContext.AbilitySlot)"
local AC_FIELD = "<AbilityContext>k__BackingField"

-- The CharacterIDs read in the game: the player Guts, the pawn Casca; another pawn of the party.
local PLAYER_ID, CASCA_ID, PAWN2_ID = 2891076981, 2283028347, 680912345

-- The 52 augments, Job01_00 .. Job09_04 and Job10_00 .. Job10_06, with the game's values (4 .. 55).
local AUGMENTS = {}
for job = 1, 10 do
    for slot = 0, job == 10 and 6 or 4 do AUGMENTS[#AUGMENTS + 1] = string.format("Job%02d_%02d", job, slot) end
end
-- Their app.HumanAbilityID values here: 4 .. 55 in that order.
local ID = {}
for i, name in ipairs(AUGMENTS) do ID[name] = i + 3 end

-- getAbilityDetail's texts, with the game's "\r\n" breaks, in two languages. The two «Господство» (Job01_03 and
-- Job08_03) have the same name and different descriptions, as in the game.
local function detail(name, lang)
    if name == "Job01_03" then
        return lang == "en" and "Allows you to lift up and pin down foes for an\r\nextended duration."
            or "Позволяет дольше поднимать и прижимать\r\nврагов к земле."
    elseif name == "Job08_03" then
        return lang == "en" and "Augments the Strength and Magick of pawns in your\r\nparty."
            or "Повышает силу и магию пешек\r\nв вашем отряде."
    end
    return (lang == "en" and "Description of " or "Описание усилителя ") .. name .. "\r\nsecond line."
end

local G -- the current test's world: G.guis (what findComponents gives), G.lang, G.player, G.calcs, ...

local function finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end

-- GUI elements from specs { name, pos = { x, y }, size = { w, h }, children = { spec... } }, each linked to its first
-- child (get_Child) and its next sibling (get_Next); a spec's values are read live. specs[name .. n] = the spec (the
-- first spec of that name is specs[name]). Returns the first one.
local function elements(list, specs)
    local first, prev
    for _, sp in ipairs(list) do
        local el
        el = R.object("via.gui.Control", {}, {
            get_Name = function() return sp.name end,
            get_Child = function() return el.child end,
            get_Next = function() return el.next end,
            get_GlobalPosition = function() return sp.pos and { x = sp.pos[1], y = sp.pos[2], z = 0 } end,
            get_Size = function() return sp.size and { w = sp.size[1], h = sp.size[2] } end,
        })
        sp.el = el
        if specs[sp.name] == nil then specs[sp.name] = sp end
        if sp.children then el.child = elements(sp.children, specs) end
        if prev then prev.next = el else first = el end
        prev = el
    end
    return first
end

-- The item screens' tree as the probes read it: the item grid first, with a txt_Name of its own deeper
-- down, then PNL_ItemInfo with the description block. Names: specs.txt_Name is the grid's, specs.info_name the
-- description's (spec.name stays "txt_Name").
local function item_tree(specs)
    local info_name = { name = "txt_Name", pos = { 1212, 192 } }
    specs.info_name = info_name
    return {
        { name = "PNL_Main", children = {
            { name = "PNL_Control", children = {
                { name = "PNL_ItemGrid", children = {
                    { name = "PNL_ItemList", children = {
                        { name = "SCG_ItemList", children = {
                            { name = "item18", children = {
                                { name = "PNL_item", children = {
                                    { name = "PNL_New", children = {
                                        { name = "PNL_Control", children = {
                                            { name = "txt_Name", pos = { 1062, 736 } },
                                        } },
                                    } },
                                } },
                            } },
                        } },
                    } },
                } },
                { name = "PNL_ItemInfo", size = { 480, 760 }, children = {
                    { name = "PNL_Control", children = {
                        info_name,
                        { name = "txt_Info", pos = { 1308, 220 } },
                        { name = "txt_WeightNum", pos = { 1228, 340 } },
                        { name = "SCL_PartyList", children = {
                            { name = "PNL_Party00", children = {
                                { name = "txt_StorageNum", pos = { 1233, 383 } },
                            } },
                            { name = "item1", children = {
                                { name = "txt_StorageNum", pos = { 1306, 390 } },
                            } },
                        } },
                    } },
                } },
            } },
        } },
    }
end

-- A screen's GUI: a GameObject called `name`, drawn while s.o.drawn (default true), with an app.<name> component
-- (s.comp) and a view (s.view) over `tree`. The GUI goes into the scene (G.guis) unless o.away.
local function gui(name, comp, tree, o)
    if o.drawn == nil then o.drawn = true end
    local s = { o = o, comp = comp, specs = {} }
    local first = tree and elements(tree, s.specs) or nil
    s.view = R.object("via.gui.View", {}, { get_Child = function() return first end })
    s.go = R.object("via.GameObject", {}, {
        get_Name = function() return name end,
        get_DrawSelf = function()
            -- the game destroyed it: the call raises (s.o.asked counts the asks)
            if s.o.destroyed then
                s.o.asked = (s.o.asked or 0) + 1
                error("Invoke threw an exception")
            end
            return s.o.drawn
        end,
        [GET_COMPONENT] = function(_, t)
            if t == nil or t.runtime_type ~= "app." .. name then return nil end
            return s.comp
        end,
    })
    s.gui = R.object("via.gui.GUI", {}, {
        get_GameObject = function() return s.go end,
        get_View = function() return s.view end,
    })
    if not o.away then G.guis[#G.guis + 1] = s.gui end
    return s
end

-- The item screen (ui060301_00) or the equipment-change screen (ui060401_00): o.item is the hovered item id (nil:
-- no Storage), o.owner its Storage's _CharaId, the owner of the bag it is in (default the player's id, as in his
-- own bag; false: none; "raise": its read raises; 65535 in the storage chest), o.chara the DispCharaId; the item
-- screen's CharaTab (s.tab) answers get_SelectedCharaID with o.selected, the character selected on the left (nil by
-- default; "raise": the call raises); o.tree replaces the elements (false: none).
local function item_screen(name, o)
    o = o or {}
    if o.owner == nil then o.owner = PLAYER_ID end
    local storage = R.object("app.ItemDefine.StorageData", {}, { get_ItemId = function() return o.item end })
    setmetatable(storage.fields, { __index = function(_, k)
        if k ~= "_CharaId" then return nil end
        if o.owner == "raise" then error("Invoke threw an exception") end
        if o.owner ~= false then return o.owner end
    end })
    local info = R.object("app.ItemInfo", {})
    setmetatable(info.fields, { __index = function(_, k)
        if k == "Storage" and o.item ~= nil then return storage end
    end })
    local ctrl = R.object("app.GUIBase.ItemCtrl", {}, { get_SelectedInfo = function() return info end })
    local grid = R.object("app.GUIBase.ItemGrid2Ref", { _ItemCtrl = ctrl })
    local comp = R.object("app." .. name, { ItemGrid = grid })
    setmetatable(comp.fields, { __index = function(_, k) if k == "DispCharaId" then return o.chara end end })
    local tab = nil
    if name == "ui060301_00" then
        tab = R.object("app.GUIBase.CharaChangeRef", {}, { get_SelectedCharaID = function()
            if o.selected == "raise" then error("Invoke threw an exception") end
            return o.selected
        end })
        comp.fields.CharaTab = tab
    end
    local s
    if o.tree == false then
        s = gui(name, comp, nil, o)
    else
        local specs = {}
        local tree = o.tree or item_tree(specs)
        s = gui(name, comp, tree, o)
        s.specs.info_name = specs.info_name
    end
    s.tab = tab
    return s
end

-- The guild screen's tree as a probe read it in the game: the augment set's panel PNL_AbilitySet with the
-- «Используемые усилители» header PNL_TitleBG (its global y 567, the bar's top line): its bar s9g_Bg (a Scale9Grid
-- centred at 1164, 591, 960 × 60), the title, the two lines; then the equipped list SCL_AbList, its rows' hit areas
-- as read in the game too (ITM_List's hit_List at 970.4, 631, 520 × 48; item1 .. item7's at the same x and
-- width). Before it, another tab's panel with a header of the same names. specs.title and specs.bar are the augment
-- set's header and bar, specs.hit ITM_List's hit_List.
local function guild_tree(specs)
    local bar = { name = "s9g_Bg", pos = { 1164, 591 }, size = { 960, 60 } }
    local title = { name = "PNL_TitleBG", pos = { 1164, 567 }, children = {
        bar,
        { name = "txt_ESkill", pos = { 1164, 591 } },
        { name = "mat_Line02", pos = { 1164, 567 }, size = { 960, 3 } },
        { name = "mat_Line03", pos = { 1164, 615 }, size = { 960, 3 } },
    } }
    local hit = { name = "hit_List", pos = { 970.4, 631 }, size = { 520, 48 } }
    local rows = { { name = "ITM_List", children = { hit } } }
    for i = 1, 7 do
        rows[#rows + 1] = { name = "item" .. i, children = {
            { name = "hit_List", pos = { 970.4, 631 + 52 * i }, size = { 520, 48 } },
        } }
    end
    specs.title, specs.bar, specs.hit = title, bar, hit
    return {
        { name = "PNL_Main", children = {
            { name = "PNL_Control", children = {
                { name = "PNL_SkillSet", pos = { 1164, 299 }, children = {
                    { name = "PNL_TitleBG", pos = { 1164, 467 }, children = {
                        { name = "s9g_Bg", pos = { 1164, 491 }, size = { 960, 60 } },
                    } },
                } },
                { name = "PNL_AbilitySet", pos = { 1164, 299 }, children = {
                    { name = "txt_Info1", pos = { 967.4, 355 } },
                    title,
                    { name = "SCL_AbList", pos = { 1164, 655 }, children = rows },
                } },
            } },
        } },
    }
end

-- An element's get_ActualVisible / get_Visible answering o[key .. "_actual"] / o[key .. "_visible"] (nil: no answer,
-- as a missing method; "raise": the call raises).
local function visibility(o, key)
    local function answer(v)
        if v == "raise" then error("Invoke threw an exception") end
        return v
    end
    return function() return answer(o[key .. "_actual"]) end, function() return answer(o[key .. "_visible"]) end
end

-- The guild's augments screen (ui040101_00): o.message is _TxtAbilityInfo's text, o.chara the _CharaTab's selected
-- CharacterID (default the player's); the text at o.text_pos (default 967.4, 355) of size o.text_size, the root
-- _PnlAbilityRoot of size o.root_size (nil: get_Size gives nothing); their visibility o.text_actual / o.text_visible
-- and o.root_actual / o.root_visible (visibility()); o.tree replaces the view's elements (default guild_tree; false:
-- none).
local function guild(o)
    o = o or {}
    if o.chara == nil then o.chara = PLAYER_ID end
    if o.message == nil then o.message = "" end
    o.text_pos = o.text_pos or { 967.4, 355 }
    local text_actual, text_visible = visibility(o, "text")
    local text = R.object("via.gui.Text", {}, {
        get_Message = function() return o.message end,
        get_GlobalPosition = function() return o.text_pos and { x = o.text_pos[1], y = o.text_pos[2], z = 0 } end,
        get_Size = function() return o.text_size and { w = o.text_size[1], h = o.text_size[2] } end,
        get_ActualVisible = text_actual,
        get_Visible = text_visible,
    })
    local root_actual, root_visible = visibility(o, "root")
    local root = R.object("via.gui.Panel", {}, {
        get_GlobalPosition = function() return { x = 1164, y = 299, z = 0 } end,
        get_Size = function() return o.root_size and { w = o.root_size[1], h = o.root_size[2] } end,
        get_ActualVisible = root_actual,
        get_Visible = root_visible,
    })
    local tab = R.object("app.GUIBase.CharaChangeJobGuildRef", {}, {
        get_SelectedCharaID = function() return o.chara end,
    })
    local name = R.object("via.gui.Text", {}, { get_Message = function() return "" end })
    local comp = R.object("app.ui040101_00", { _TxtAbilityInfo = text, _TxtAbilityInfoName = name,
                                               _PnlAbilityRoot = root, _CharaTab = tab })
    local specs = {}
    local tree = nil
    if o.tree ~= false then tree = o.tree or guild_tree(specs) end
    local s = gui("ui040101_00", comp, tree, o)
    s.specs.title, s.specs.bar, s.specs.hit = specs.title, specs.bar, specs.hit
    s.text, s.root = text, root
    return s
end

-- An app.AbilityContext whose getAbility(job, slot) is slots[job][slot] (each ask noted in G.asked as "job/slot").
local function ability_context(slots)
    return R.object("app.AbilityContext", {}, {
        [GET_ABILITY] = function(_, job, slot)
            G.asked[#G.asked + 1] = job .. "/" .. slot
            local s = slots[job]
            return s and s[slot]
        end,
    })
end

-- The app.Human of a character whose JobContext's CurrentJob is `job`; with `slots`, its AbilityContext's
-- (ability_context), none without.
local function human(job, slots)
    local ctx = R.object("app.JobContext", { CurrentJob = job })
    return R.object("app.Human", { [AC_FIELD] = slots and ability_context(slots) or nil },
        { get_JobContext = function() return ctx end })
end

-- An item in an equipment slot (app.ItemDefine.StorageData).
local function storage(id)
    return R.object("app.ItemDefine.StorageData", {}, { get_ItemId = function() return id end })
end

-- A status calculator whose calcBasicAttackDefence gives these numbers (read in the game); n.job: its field Human is
-- a character of that vocation (none without it), n.slots that Human's augments (ability_context). Read live from
-- `n` (the calculator's .n): n.total = { { basic, additional, armor } of the defence, the same of the magick
-- defence } is what calcAttackDefenceWithEquipmentAndBuff gives (nil: no struct); n.equips the item ids of
-- getEquipData().Data.Equips, a game array (false: a null slot; nil: no Equips).
local function calculator(n)
    local calc = R.object("app.PlayerStatusCalculator",
        { Human = n.job ~= nil and human(n.job, n.slots) or nil }, {
        calcBasicAttackDefence = function()
            return R.object("app.PlayerBasicAttackDefenceStatus", {
                ["<BasicDefence>k__BackingField"] = n.def, ["<BasicMagicDefence>k__BackingField"] = n.mdef,
                ["<BasicAttack>k__BackingField"] = n.atk, ["<BasicMagicAttack>k__BackingField"] = n.matk,
                ["<AdditionalDefence>k__BackingField"] = 159.0, ["<Blow>k__BackingField"] = 100.0,
            })
        end,
        calcAttackDefenceWithEquipmentAndBuff = function()
            if n.total == nil then return nil end
            local d, m = n.total[1], n.total[2]
            return R.object("app.PlayerAttackDefenceStatus", {
                ["<BasicDefence>k__BackingField"] = d[1], ["<AdditionalDefence>k__BackingField"] = d[2],
                ["<ArmorDefence>k__BackingField"] = d[3],
                ["<BasicMagicDefence>k__BackingField"] = m[1], ["<AdditionalMagicDefence>k__BackingField"] = m[2],
                ["<ArmorMagicDefence>k__BackingField"] = m[3],
                ["<BasicAttack>k__BackingField"] = n.atk, ["<ArmorAttack>k__BackingField"] = 1261.0,
            })
        end,
        getEquipData = function()
            local equips = nil
            if n.equips then
                local slots = {}
                for i, id in ipairs(n.equips) do slots[i] = id and storage(id) or false end
                equips = R.array(slots, "app.ItemDefine.StorageData[]")
            end
            return R.object("app.ReadOnlyEquipData", { Data = R.object("app.EquipData", { Equips = equips }) })
        end,
    })
    calc.n = n
    return calc
end

-- Dictionary<app.CharacterID, app.PlayerStatusCalculator> over G.calcs ({ { key, calculator } }): the enumerator
-- (G.no_enumerator: GetEnumerator gives nil), its KeyValuePair's key / value fields (G.kv_getters: only get_Key /
-- get_Value), ContainsKey / get_Item (G.no_lookup: they give nil).
local function calculators()
    local function key_of(k) return type(k) == "table" and k.fields.value__ or k end
    return R.object("System.Collections.Generic.Dictionary`2<app.CharacterID,app.PlayerStatusCalculator>", {}, {
        GetEnumerator = function()
            if G.no_enumerator then return nil end
            local i = 0
            return R.object("Enumerator", {}, {
                MoveNext = function() i = i + 1; return i <= #G.calcs end,
                get_Current = function()
                    local e = G.calcs[i]
                    if G.kv_getters then
                        return R.object("KeyValuePair", {}, { get_Key = function() return e[1] end,
                                                               get_Value = function() return e[2] end })
                    end
                    return R.object("KeyValuePair", { key = e[1], value = e[2] })
                end,
            })
        end,
        ContainsKey = function(_, k)
            if G.no_lookup then return nil end
            for _, e in ipairs(G.calcs) do if key_of(e[1]) == k then return true end end
            return false
        end,
        get_Item = function(_, k)
            if G.no_lookup then return nil end
            for _, e in ipairs(G.calcs) do if key_of(e[1]) == k then return e[2] end end
            return nil
        end,
    })
end

-- An item of ItemManager's table: a ring (EquipCategory 6) or a sword (a weapon, 0).
local function item(category, special)
    local equip = R.object("app.ItemEquipParam", { _EquipCategory = category })
    local armor = R.object("app.ItemArmorParam", { _PhysicalDefence = 0, _Special = special or 0, _SpecialValue = 200,
                                                   _SpecialValue2 = 0, _SpecialValue3 = 0 })
    return R.object("app.ItemCommonParam", {}, {
        get_EquipParam = function() return equip end,
        get_ArmorParam = function() return armor end,
    })
end

-- A fresh game and fresh modules: the scene (no GUIs yet), the 52 augments and their texts in G.lang (default
-- "ru"), the player (CurrentJob 4) with the calculators of the player and two pawns, and the item table (rings 3502,
-- 3507, 3518; a sword 1001).
local function fresh()
    for name in pairs(package.loaded) do
        if name:find("^DD2DamageMeter/") then package.loaded[name] = nil end
    end
    DD2DM_HOOKS = nil
    R.new({ containers = true })
    G = { guis = {}, lang = "ru", job = 4 }
    R.type("via.gui.GUI")
    R.type("app.ui060301_00")
    R.type("app.ui060401_00")
    R.type("app.ui040101_00")
    G.scene = R.object("via.Scene", {}, {
        [FIND] = function(_, t)
            if t == nil or t.runtime_type ~= "via.gui.GUI" then return nil end
            return R.array(G.guis, "via.gui.GUI[]")
        end,
    })
    R.method("via.SceneManager", "get_CurrentScene", function() return G.scene end, STATIC)
    R.native("via.SceneManager", R.object("via.SceneManager"))

    local values = {}
    for i, name in ipairs(AUGMENTS) do values[name] = i + 3 end
    R.enum("app.HumanAbilityID", values)
    local by_value = {}
    for name, v in pairs(values) do by_value[v] = name end
    R.method("app.GUIBase", DETAIL, function(id)
        local name = by_value[id]
        return name and detail(name, G.lang) or nil
    end, STATIC)

    local ctx = R.object("app.JobContext", {})
    setmetatable(ctx.fields, { __index = function(_, k) if k == "CurrentJob" then return G.job end end })
    local human = R.object("app.Human", {}, { get_JobContext = function() return ctx end })
    -- the player's augments (G.player_ac, its slots G.player_slots): Жизненная сила and Стойкость as a Thief
    G.asked = {}
    G.player_slots = { [4] = { [0] = ID.Job05_00, [1] = 0, [2] = ID.Job01_01, [3] = 0, [4] = 0, [5] = 0, [6] = 0 } }
    G.player_ac = ability_context(G.player_slots)
    setmetatable(human.fields, { __index = function(_, k) if k == AC_FIELD then return G.player_ac end end })
    G.player = R.character({ go = "ch000000_00", chara_id = PLAYER_ID })
    G.player.methods.get_Human = function() return human end
    -- the totals as read in the game: «1645 (380)», magick 373.8 + 157.14 + 964
    G.calcs = {
        { PLAYER_ID, calculator({ def = 380.0, mdef = 373.8, atk = 420.0, matk = 372.2,
                                  total = { { 380.0, 159.0, 1106.0 }, { 373.8, 157.14, 964.0 } },
                                  equips = { 1001, 0, false, 3502, 2003 } }) },
        { CASCA_ID, calculator({ def = 375.0, mdef = 440.0, atk = 410.0, matk = 440.0,
                                 total = { { 375.0, 0.0, 900.0 }, { 440.0, 0.0, 800.0 } }, equips = { 2001, 3509 } }) },
        { PAWN2_ID, calculator({ def = 300.0, mdef = 310.0, atk = 320.0, matk = 330.0 }) },
    }
    local holder = R.object("app.PlayerStatusCalculatorHolder", { Calculators = calculators() })
    G.cm = R.object("app.CharacterManager", {}, {
        get_ManualPlayer = function() return G.player end,
        get_PlayerStatusCalculatorHolder = function() return holder end,
    })
    R.singleton("app.CharacterManager", G.cm)

    -- app.ItemArmorParam's own fields, as the type gives them (game/hidden_stats.lua reads them from the type)
    local td = R.type("app.ItemArmorParam")
    for _, name in ipairs({ "_PhysicalDefence", "_Special", "_SpecialValue", "_SpecialValue2", "_SpecialValue3" }) do
        td.fields[#td.fields + 1] = {
            get_name = function() return name end,
            is_static = function() return false end,
            get_data = function(_, o) return o.fields[name] end,
        }
    end
    local items = { [3502] = item(6, 1), [3507] = item(6, 5), [3518] = item(6, 9), [1001] = item(0) }
    local dict = R.object("System.Collections.Generic.Dictionary`2<System.Int32,app.ItemCommonParam>", {}, {
        ContainsKey = function(_, id) return items[id] ~= nil end,
        get_Item = function(_, id) return items[id] end,
    })
    R.singleton("app.ItemManager", R.object("app.ItemManager", {}, { get_ItemDataDict = function() return dict end }))
    return require("DD2DamageMeter/game/hidden_screens"), require("DD2DamageMeter/game/hook")
end

local function scans() return #R.calls_of(FIND) end
local function detail_reads() return #R.calls_of(DETAIL) end

local function finite_anchor(h)
    assert(type(h.anchor) == "table", "anchor is a table")
    assert(finite(h.anchor.x) and finite(h.anchor.y) and finite(h.anchor.width), "anchor finite")
end

-- The anchor's read flags as "x y width", each "read" or "fell back".
local function read_flags(h)
    local r = h.anchor.read
    assert(type(r) == "table", "anchor.read is a table")
    local out = {}
    for _, part in ipairs({ "x", "y", "width" }) do
        assert(type(r[part]) == "boolean", "read." .. part .. " is a boolean")
        out[#out + 1] = r[part] and "read" or "fell back"
    end
    return table.concat(out, " ")
end

-- no screen ---------------------------------------------------------------------------------------------------------

test("no screen in the scene gives nil", function()
    local HS = fresh()
    eq(HS.current(0), nil, "no GUI at all")
    -- other GUIs are not the three screens
    local other = R.object("via.GameObject", {}, { get_Name = function() return "ui020601" end,
                                                    get_DrawSelf = function() return true end })
    G.guis[#G.guis + 1] = R.object("via.gui.GUI", {}, { get_GameObject = function() return other end })
    eq(HS.current(1), nil, "another GUI drawn")
end)

test("five calls 0.1 s apart with no screen look through the GUIs at most twice", function()
    local HS = fresh()
    for i = 0, 4 do eq(HS.current(i * 0.1), nil, "call " .. i) end
    assert(scans() >= 1 and scans() <= 2, "scans: " .. scans())
    -- and again 0.5 s after the last look
    HS.current(0.5)
    eq(scans(), 2, "a look 0.5 s later")
end)

-- the item screen ---------------------------------------------------------------------------------------------------

test("the items screen with 3502 hovered gives the ring, the player's, with a finite anchor", function()
    local HS = fresh()
    item_screen("ui060301_00", { item = 3502 })
    local h = HS.current(0)
    assert(h, "a hover")
    eq(h.kind, "ring", "kind")
    eq(h.id, 3502, "id")
    eq(h.screen, "items", "screen")
    eq(h.who, "player", "who")
    eq(h.chara_id, PLAYER_ID, "chara_id")
    eq(h.name, nil, "no augment name")
    finite_anchor(h)
end)

test("the items screen: whose is the bag's owner, the hovered item's Storage._CharaId", function()
    local HS = fresh()
    local s = item_screen("ui060301_00", { item = 3502, owner = PLAYER_ID })
    local h = HS.current(0)
    eq(h.who, "player", "his own bag")
    eq(h.chara_id, PLAYER_ID, "his id")
    -- Casca's tab: a ring in her bag is hers
    s.o.owner = CASCA_ID
    h = HS.current(0.016)
    eq(h.id, 3502, "the ring")
    eq(h.screen, "items", "screen")
    eq(h.who, "pawn", "Casca's bag")
    eq(h.chara_id, CASCA_ID, "her id")
    s.o.owner = PAWN2_ID
    h = HS.current(0.032)
    eq(h.who, "pawn", "the other pawn's bag")
    eq(h.chara_id, PAWN2_ID, "her id")
    -- a boxed CharacterID reads the same
    s.o.owner = R.object("app.CharacterID", { value__ = CASCA_ID })
    eq(HS.current(0.048).chara_id, CASCA_ID, "boxed")
    -- back in his bag
    s.o.owner = PLAYER_ID
    h = HS.current(0.064)
    eq(h.who, "player", "his again")
    eq(h.chara_id, PLAYER_ID, "his id again")
end)

test("the items screen: an owner's id above 2^31 read as a signed 32-bit number is turned back", function()
    local HS = fresh()
    local s = item_screen("ui060301_00", { item = 3502, owner = PLAYER_ID - 0x100000000 })
    local h = HS.current(0)
    eq(h.chara_id, PLAYER_ID, "his id, 2891076981")
    eq(h.who, "player", "his bag")
    s.o.owner = CASCA_ID - 0x100000000
    h = HS.current(0.016)
    eq(h.chara_id, CASCA_ID, "her id, 2283028347")
    eq(h.who, "pawn", "her bag")
    s.o.owner = PLAYER_ID + 0.0
    eq(HS.current(0.032).chara_id, PLAYER_ID, "a float with a whole value")
end)

test("the items screen: an owner that cannot be read or is not of the party, with no character selected, gives no "
    .. "whose, never the player's", function()
    local HS, Hook = fresh()
    local s = item_screen("ui060301_00", { item = 3502, owner = false })
    local function none(t, what)
        local h = HS.current(t)
        eq(h and h.id, 3502, what .. ": the ring still shown")
        eq(h.who, nil, what .. ": who unknown")
        eq(h.chara_id, nil, what .. ": chara_id unknown")
        finite_anchor(h)
    end
    none(0, "no _CharaId")
    s.o.owner = "raise"
    none(0.016, "its read raises")
    s.o.owner = 123456
    none(0.032, "an id with no calculator")
    s.o.owner = -5
    none(0.048, "a signed id with no calculator")
    s.o.owner = 0
    none(0.064, "0")
    s.o.owner = "2283028347"
    none(0.08, "not a number")
    -- a pawn whose calculator is gone (she left the party): not hers, and not the player's
    table.remove(G.calcs, 2)
    s.o.owner = CASCA_ID
    none(0.096, "Casca without a calculator")
    eq(Hook.info().errors, 0, "no error of the mod's own")
end)

test("the items screen: a party member's bag while the player's id cannot be read gives the id, who unknown",
    function()
    local HS = fresh()
    G.player.chara_id = nil
    local s = item_screen("ui060301_00", { item = 3502, owner = CASCA_ID })
    local h = HS.current(0)
    eq(h.chara_id, CASCA_ID, "her id")
    eq(h.who, nil, "who unknown, as on the other screens")
    s.o.owner = PLAYER_ID
    h = HS.current(0.016)
    eq(h.chara_id, PLAYER_ID, "his id")
    eq(h.who, nil, "not taken as his without his id")
end)

test("a ring in a pawn's bag reads that pawn's base, totals, what she has on and her vocation", function()
    local HS = fresh()
    -- Casca a Warrior (5); the player a Thief (4)
    G.calcs[2][2] = calculator({ def = 375.0, mdef = 440.0, atk = 410.0, matk = 440.0, job = 5,
                                 total = { { 375.0, 0.0, 900.0 }, { 440.0, 0.0, 800.0 } }, equips = { 2001, 3509 } })
    local s = item_screen("ui060301_00", { item = 3502, owner = CASCA_ID })
    local h = HS.current(0)
    local b = HS.base(h.chara_id)
    eq(b.who, "pawn", "base.who")
    near(b.phys_defence, 375, 1e-9, "her base defence, not his 380")
    near(b.strength, 410, 1e-9, "her strength, not his 420")
    local sums = HS.totals(h.chara_id)
    near(sums.phys, 1275, 1e-9, "her defence: 375 + 0 + 900")
    near(sums.magic, 1240, 1e-9, "her magick defence")
    local on = HS.equipped(h.chara_id).items
    eq(on[3509], true, "her gear")
    eq(on[3502], nil, "3502 is not on her")
    eq(HS.job(h.chara_id), 5, "her vocation")
    -- the same ring in his bag: his
    s.o.owner = PLAYER_ID
    h = HS.current(0.016)
    b = HS.base(h.chara_id)
    eq(b.who, "player", "his base")
    near(b.strength, 420, 1e-9, "his strength")
    near(HS.totals(h.chara_id).phys, 1645, 1e-9, "his defence")
    eq(HS.equipped(h.chara_id).items[3502], true, "3502 is on him")
    eq(HS.job(h.chara_id), 4, "his vocation")
end)

test("the storage chest: an item of no one's (_CharaId 65535) is the character selected on the left's", function()
    local HS = fresh()
    local s = item_screen("ui060301_00", { item = 3502, owner = 65535, selected = PLAYER_ID })
    local h = HS.current(0)
    eq(h.who, "player", "the player selected")
    eq(h.chara_id, PLAYER_ID, "his id")
    near(HS.base(h.chara_id).strength, 420, 1e-9, "his base")
    near(HS.totals(h.chara_id).phys, 1645, 1e-9, "his defence")
    -- C: Casca selected
    s.o.selected = CASCA_ID
    h = HS.current(0.016)
    eq(h.who, "pawn", "Casca selected")
    eq(h.chara_id, CASCA_ID, "her id")
    near(HS.base(h.chara_id).strength, 410, 1e-9, "her base")
    near(HS.totals(h.chara_id).phys, 1275, 1e-9, "her defence")
    -- read as a signed 32-bit number, or boxed: the same ids
    s.o.selected = CASCA_ID - 0x100000000
    eq(HS.current(0.032).chara_id, CASCA_ID, "signed")
    s.o.selected = R.object("app.CharacterID", { value__ = PLAYER_ID })
    eq(HS.current(0.048).chara_id, PLAYER_ID, "boxed")
    -- an item whose _CharaId cannot be read: the selected one too
    s.o.owner = false
    eq(HS.current(0.064).chara_id, PLAYER_ID, "no _CharaId")
end)

test("the storage chest: a selected character that cannot be read or is not of the party gives no whose",
    function()
    local HS, Hook = fresh()
    local s = item_screen("ui060301_00", { item = 3502, owner = 65535 })
    local function none(t, what)
        local h = HS.current(t)
        eq(h and h.id, 3502, what .. ": the ring still shown")
        eq(h.who, nil, what .. ": who unknown")
        eq(h.chara_id, nil, what .. ": chara_id unknown")
    end
    none(0, "nothing selected")
    s.o.selected = "raise"
    none(0.016, "get_SelectedCharaID raises")
    s.o.selected = 123456
    none(0.032, "an id with no calculator")
    s.o.selected = 65535
    none(0.048, "the chest's own id")
    s.tab.poison = true
    s.o.selected = PLAYER_ID
    none(0.064, "the tab raises")
    s.comp.fields.CharaTab = nil
    none(0.08, "no CharaTab")
    eq(Hook.info().errors, 0, "no error of the mod's own")
end)

test("the items screen: a party owner in Storage._CharaId wins over another character selected on the left",
    function()
    local HS = fresh()
    local s = item_screen("ui060301_00", { item = 3502, owner = CASCA_ID, selected = PLAYER_ID })
    local h = HS.current(0)
    eq(h.chara_id, CASCA_ID, "her bag, the player selected: hers")
    eq(h.who, "pawn", "a pawn's")
    s.o.owner, s.o.selected = PLAYER_ID, CASCA_ID
    h = HS.current(0.016)
    eq(h.chara_id, PLAYER_ID, "his bag, Casca selected: his")
    eq(h.who, "player", "the player's")
end)

test("the items screen: the character selected is asked only when the item is of no one in the party", function()
    local HS = fresh()
    local s = item_screen("ui060301_00", { item = 3502, owner = CASCA_ID, selected = PLAYER_ID })
    local function asks() return #R.calls_of("get_SelectedCharaID") end
    local before = asks()
    eq(HS.current(0).chara_id, CASCA_ID, "her bag")
    eq(asks() - before, 0, "a bag's owner: the selection not asked")
    s.o.owner = 65535
    before = asks()
    eq(HS.current(0.016).chara_id, PLAYER_ID, "the chest: the player selected")
    eq(asks() - before, 1, "the chest: asked once")
end)

test("the items screen: the player's own id without his calculator is not taken, nothing selected", function()
    local HS = fresh()
    table.remove(G.calcs, 1)
    item_screen("ui060301_00", { item = 3502, owner = PLAYER_ID })
    local h = HS.current(0)
    eq(h and h.id, 3502, "the ring still shown")
    eq(h.chara_id, nil, "not taken as his: no calculator")
    eq(h.who, nil, "who unknown")
end)

test("the items screen: the storage row is read anew when the same ring is hovered in another bag", function()
    local HS = fresh()
    local s = item_screen("ui060301_00", { item = 3502, owner = PLAYER_ID })
    near(HS.current(0).anchor.y, 423, 1e-9, "his bag")
    s.specs.PNL_Party00.children[1].pos = { 1233, 400 }
    near(HS.current(0.016).anchor.y, 423, 1e-9, "the same hover: the row as read for it")
    s.o.owner = CASCA_ID
    near(HS.current(0.032).anchor.y, 440, 1e-9, "her bag: another hover, the row read anew")
end)

test("the items screen's anchor: txt_Name's x, the storage row's y + 40, PNL_ItemInfo's width", function()
    local HS = fresh()
    local s = item_screen("ui060301_00", { item = 3502 })
    local h = HS.current(0)
    -- the description's txt_Name, not the item grid's one met first
    near(h.anchor.x, 1212, 1e-9, "x")
    near(h.anchor.y, 383 + 40, 1e-9, "y: the first row (PNL_Party00)")
    near(h.anchor.width, 480, 1e-9, "width")
    eq(h.anchor.up, nil, "under the anchor, as before (growing up is the guild's)")
    eq(read_flags(h), "read read read", "every part read")
    -- x read anew each frame; the storage row (a scroll list's) only when the hover changes
    s.specs.info_name.pos = { 1250, 200 }
    s.specs.PNL_Party00.children[1].pos = { 1233, 400 }
    h = HS.current(0.016)
    near(h.anchor.x, 1250, 1e-9, "x moved")
    near(h.anchor.y, 423, 1e-9, "the same ring: the row as read for it")
    s.o.item = 3507
    near(HS.current(0.032).anchor.y, 440, 1e-9, "another ring hovered: the row read anew")
end)

test("the items screen without a readable width takes 470; without its elements, the measured place", function()
    local HS = fresh()
    local s = item_screen("ui060301_00", { item = 3502 })
    s.specs.PNL_ItemInfo.size = nil
    local h = HS.current(0)
    near(h.anchor.width, 470, 1e-9, "width fallback")
    near(h.anchor.x, 1212, 1e-9, "x still read")
    eq(read_flags(h), "read read fell back", "the width fell back, the measured 470 told apart from a read")
    s.specs.info_name.pos = nil
    eq(read_flags(HS.current(0.016)), "fell back read fell back", "x too")

    HS = fresh()
    item_screen("ui060301_00", { item = 3502, tree = false })
    h = HS.current(0)
    assert(h, "still a hover")
    near(h.anchor.x, 1212, 1e-9, "x")
    near(h.anchor.y, 423, 1e-9, "y")
    near(h.anchor.width, 470, 1e-9, "width")
    eq(read_flags(h), "fell back fell back fell back", "nothing read")
end)

test("the items screen's elements are looked for again, at most every 0.5 s, while missing", function()
    local HS = fresh()
    local s = item_screen("ui060301_00", { item = 3502, tree = false })
    near(HS.current(0).anchor.y, 423, 1e-9, "the measured place")
    -- the tree appears
    local specs = {}
    local first = elements(item_tree(specs), s.specs)
    s.view.methods.get_Child = function() return first end
    s.specs.PNL_Party00.children[1].pos = { 1233, 500 }
    near(HS.current(0.2).anchor.y, 423, 1e-9, "not looked for again yet")
    near(HS.current(0.6).anchor.y, 540, 1e-9, "found 0.5 s later")
    local walks = #R.calls_of("get_Child")
    for i = 1, 10 do HS.current(0.6 + i * 0.1) end
    eq(#R.calls_of("get_Child"), walks, "found ones are kept: no walk")
end)

test("a sword hovered gives nil; nothing hovered gives nil", function()
    local HS = fresh()
    local s = item_screen("ui060301_00", { item = 1001 })
    eq(HS.current(0), nil, "a sword")
    s.o.item = nil
    eq(HS.current(0.1), nil, "no Storage")
    s.o.item = 0
    eq(HS.current(0.2), nil, "id 0")
    s.o.item = 99999
    eq(HS.current(0.3), nil, "an id not in the table")
end)

test("the cursor moves between two frames: the second call gives the new id", function()
    local HS = fresh()
    local s = item_screen("ui060301_00", { item = 3502 })
    eq(HS.current(0).id, 3502, "first")
    s.o.item = 3507
    eq(HS.current(0.016).id, 3507, "second")
    s.o.item = 1001
    eq(HS.current(0.032), nil, "then a sword")
end)

test("DrawSelf false gives nil, and the screen is found again when it is drawn", function()
    local HS = fresh()
    local s = item_screen("ui060301_00", { item = 3502, drawn = false })
    eq(HS.current(0), nil, "not drawn")
    s.o.drawn = true
    eq(HS.current(0.1).id, 3502, "drawn again: the kept GUI")
    s.o.drawn = false
    eq(HS.current(0.2), nil, "hidden again")
end)

test("a known screen's GUI is kept while it is drawn: no look through the GUIs", function()
    local HS = fresh()
    item_screen("ui060301_00", { item = 3502 })
    for i = 0, 30 do assert(HS.current(i * 0.1), "frame " .. i) end
    eq(scans(), 1, "one look")
end)

test("a kept screen whose GameObject raises is dropped; the next look finds the new one", function()
    local HS = fresh()
    local s = item_screen("ui060301_00", { item = 3502 })
    eq(HS.current(0).id, 3502, "found")
    s.o.destroyed = true
    G.guis = {}
    eq(HS.current(0.1), nil, "gone")
    eq(HS.current(0.2), nil, "still gone")
    eq(s.o.asked, 1, "a dropped screen is not asked again")
    item_screen("ui060301_00", { item = 3507 })
    eq(HS.current(0.6).id, 3507, "the new one")
end)

test("the drawn one of two GUIs of the same name is taken", function()
    local HS = fresh()
    item_screen("ui060301_00", { item = 3502, drawn = false })
    item_screen("ui060301_00", { item = 3507 })
    eq(HS.current(0).id, 3507, "the drawn one")
end)

test("reset forgets the screens: the next call looks at once", function()
    local HS = fresh()
    item_screen("ui060301_00", { item = 3502 })
    HS.current(0)
    HS.reset()
    HS.current(0.1)
    eq(scans(), 2, "a look right after the reset")
end)

-- The game calls made on `obj` so far.
local function asked(obj)
    local n = 0
    for _, c in ipairs(R.calls) do
        if c.this == obj then n = n + 1 end
    end
    return n
end

test("forget drops the screens kept and their elements, nothing kept is asked again; the texts read stay",
        function()
    local HS = fresh()
    local items = item_screen("ui060301_00", { item = 3502 })
    local g = guild({ message = detail("Job05_00", "ru"), drawn = false })
    eq(HS.current(0).id, 3502, "the item screen")
    eq(HS.kept(), 2, "both screens kept")
    items.o.drawn, g.o.drawn = false, true
    eq(HS.current(0.016).name, "Job05_00", "the guild, its texts read and its elements found")
    local texts, title = detail_reads(), g.specs.title.el
    HS.forget()
    eq(HS.kept(), 0, "nothing kept")
    -- the world goes: the screens leave the scene, and what was kept is never asked again
    local go_items, go_guild, title_asks = asked(items.go), asked(g.go), asked(title)
    G.guis = {}
    eq(HS.current(0.1), nil, "no screen")
    eq(scans(), 2, "the call right after forget looks at once")
    for i = 1, 20 do eq(HS.current(0.1 + i * 0.1), nil, "still none " .. i) end
    eq(asked(items.go), go_items, "the item screen's GameObject not asked")
    eq(asked(g.go), go_guild, "the guild's GameObject not asked")
    eq(asked(title), title_asks, "the header kept under it not asked")
    eq(HS.kept(), 0, "still nothing kept")
    -- the world comes back: the screens are found again, the 52 texts are not read again
    G.guis = { items.gui, g.gui }
    local h = HS.current(2.6)
    eq(h and h.name, "Job05_00", "found again by the next look")
    eq(HS.kept(), 2, "kept again")
    eq(detail_reads(), texts, "the texts read before are kept")
end)

test("gone counts the screens kept that were dropped because their GameObject raised (the last guard)", function()
    local HS = fresh()
    local s = item_screen("ui060301_00", { item = 3502 })
    eq(HS.current(0).id, 3502, "found")
    eq(HS.gone(), 0, "none yet")
    s.o.destroyed = true
    eq(HS.current(0.1), nil, "gone")
    eq(HS.gone(), 1, "one dropped by the last guard")
    eq(HS.kept(), 0, "not kept")
    HS.forget()
    HS.reset()
    eq(HS.gone(), 1, "counted since the mod was loaded, through forget and reset")
end)

-- via.GameObject's get_Valid as the game has it (game/safe.lua looks it up once): the GameObject's go.valid, true
-- when not set ("raise": the call raises).
local function declare_valid()
    R.method("via.GameObject", "get_Valid", function(go)
        if go.valid == "raise" then error("Invoke threw an exception") end
        if go.valid == nil then return true end
        return go.valid
    end)
end

-- The calls of `sig` made on `obj`.
local function calls_on(obj, sig)
    local n = 0
    for _, c in ipairs(R.calls_of(sig)) do
        if c.this == obj then n = n + 1 end
    end
    return n
end

test("get_Valid true: a kept screen read as before, its GameObject asked it before get_DrawSelf", function()
    local HS, Hook = fresh()
    declare_valid()
    local s = item_screen("ui060301_00", { item = 3502 })
    eq(HS.current(0).id, 3502, "found")
    eq(HS.current(0.016).id, 3502, "read again")
    eq(calls_on(s.go, "get_Valid"), 2, "asked once a read (the kept screen, not the look)")
    local order = {}
    for _, c in ipairs(R.calls) do
        if c.this == s.go and (c.sig == "get_Valid" or c.sig == "get_DrawSelf") then order[#order + 1] = c.sig end
    end
    -- the look's own get_DrawSelf on the GameObject it finds first, then each read of the kept one
    eq(table.concat(order, " "), "get_DrawSelf get_Valid get_DrawSelf get_Valid get_DrawSelf", "get_Valid first")
    s.o.drawn = false
    eq(HS.current(0.032), nil, "not drawn")
    eq(HS.kept(), 1, "still kept")
    eq(HS.invalid(), 0, "nothing dropped"); eq(HS.gone(), 0, "nothing gone")
    eq(Hook.info().errors, 0, "no error")
end)

test("a kept screen whose get_Valid gives false (a menu closed) is dropped quietly, its get_DrawSelf not called",
    function()
    local HS, Hook = fresh()
    declare_valid()
    local items = item_screen("ui060301_00", { item = 3502 })
    local equip = item_screen("ui060401_00", { item = 3518, drawn = false })
    eq(HS.current(0).id, 3502, "the item screen")
    eq(HS.kept(), 2, "both kept")
    -- the item screen closed: the game destroyed its GUI, and it left the scene
    items.o.drawn = false
    items.go.valid = false
    table.remove(G.guis, 1)
    local draws, from = calls_on(items.go, "get_DrawSelf"), #R.calls
    eq(HS.current(0.016), nil, "nothing drawn")
    eq(calls_on(items.go, "get_DrawSelf"), draws, "its get_DrawSelf not called")
    local others = 0
    for i = from + 1, #R.calls do
        local c = R.calls[i]
        if c.this == items.gui or c.this == items.comp or c.this == items.view then others = others + 1 end
    end
    eq(others, 0, "nor anything else of it")
    eq(HS.kept(), 1, "dropped; the equipment screen still kept")
    eq(HS.invalid(), 1, "counted as no longer valid"); eq(HS.gone(), 0, "not as gone")
    eq(Hook.info().errors, 0, "no error")
    eq(calls_on(items.go, "get_Valid"), 2, "asked in the read before and in this one")
    -- the other screen drawn: read as before
    equip.o.drawn = true
    eq(HS.current(0.032).id, 3518, "the equipment screen")
    for i = 1, 10 do HS.current(0.032 + i * 0.1) end
    eq(HS.invalid(), 1, "once")
    eq(calls_on(items.go, "get_Valid"), 2, "the screen dropped is never asked again")
    HS.forget()
    HS.reset()
    eq(HS.invalid(), 1, "counted since the mod was loaded, through forget and reset")
end)

test("a kept screen whose get_Valid raises is dropped like a raise (gone), its get_DrawSelf not called", function()
    local HS, Hook = fresh()
    declare_valid()
    local s = item_screen("ui060301_00", { item = 3502 })
    eq(HS.current(0).id, 3502, "found")
    s.go.valid = "raise"
    table.remove(G.guis, 1)
    local draws = calls_on(s.go, "get_DrawSelf")
    eq(HS.current(0.1), nil, "gone")
    eq(calls_on(s.go, "get_DrawSelf"), draws, "its get_DrawSelf not called")
    eq(s.o.asked, nil, "the destroyed GameObject's get_DrawSelf never asked")
    eq(HS.gone(), 1, "counted as gone"); eq(HS.invalid(), 0, "not as no longer valid")
    eq(HS.kept(), 0, "not kept")
    eq(Hook.info().errors, 0, "no error")
end)

test("without get_Valid in the game: get_DrawSelf alone, as before", function()
    local HS, Hook = fresh()
    local s = item_screen("ui060301_00", { item = 3502 })
    eq(HS.current(0).id, 3502, "found")
    eq(HS.current(0.016).id, 3502, "read again")
    eq(#R.calls_of("get_Valid"), 0, "no get_Valid asked")
    eq(calls_on(s.go, "get_DrawSelf"), 3, "the look's and each read's get_DrawSelf")
    s.o.destroyed = true
    eq(HS.current(0.1), nil, "the last guard")
    eq(HS.gone(), 1, "counted as gone"); eq(HS.invalid(), 0, "not as no longer valid")
    eq(Hook.info().errors, 0, "no error")
end)

-- the equipment-change screen ---------------------------------------------------------------------------------------

test("the equipment screen: the hovered ring, and whose by DispCharaId", function()
    local HS = fresh()
    local s = item_screen("ui060401_00", { item = 3518, chara = PLAYER_ID })
    local h = HS.current(0)
    eq(h.kind, "ring", "kind")
    eq(h.id, 3518, "id")
    eq(h.screen, "equipment", "screen")
    eq(h.who, "player", "the player")
    eq(h.chara_id, PLAYER_ID, "chara_id")
    near(h.anchor.x, 1212, 1e-9, "x")
    near(h.anchor.y, 423, 1e-9, "y")
    -- C switches to Casca
    s.o.chara = CASCA_ID
    h = HS.current(0.016)
    eq(h.who, "pawn", "Casca")
    eq(h.chara_id, CASCA_ID, "Casca's id")
    -- a boxed CharacterID reads the same
    s.o.chara = R.object("app.CharacterID", { value__ = PAWN2_ID })
    eq(HS.current(0.032).chara_id, PAWN2_ID, "boxed")
end)

test("the equipment screen: whose stays DispCharaId, whatever bag the item's Storage names", function()
    local HS = fresh()
    local s = item_screen("ui060401_00", { item = 3518, chara = CASCA_ID, owner = PLAYER_ID })
    local h = HS.current(0)
    eq(h.who, "pawn", "Casca shown")
    eq(h.chara_id, CASCA_ID, "her id")
    s.o.owner = false
    eq(HS.current(0.016).chara_id, CASCA_ID, "no owner: still hers")
end)

test("the equipment screen without a readable character: who and chara_id nil, the ring still shown", function()
    local HS = fresh()
    item_screen("ui060401_00", { item = 3518 })
    local h = HS.current(0)
    eq(h.id, 3518, "the ring")
    eq(h.who, nil, "who unknown")
    eq(h.chara_id, nil, "chara_id unknown")
end)

-- the guild's augments screen ---------------------------------------------------------------------------------------

test("the augments screen with Job01_03 hovered gives Job01_03, with Job08_03 hovered Job08_03", function()
    local HS = fresh()
    local s = guild({ message = detail("Job01_03", "ru") })
    local h = HS.current(0)
    eq(h.kind, "augment", "kind")
    eq(h.name, "Job01_03", "the first «Господство»")
    eq(h.screen, "augments", "screen")
    eq(h.who, "player", "who")
    eq(h.chara_id, PLAYER_ID, "chara_id")
    eq(h.id, nil, "no ring id")
    finite_anchor(h)
    s.o.message = detail("Job08_03", "ru")
    eq(HS.current(0.016).name, "Job08_03", "the second «Господство»")
end)

test("every one of the 52 descriptions gives its augment", function()
    local HS = fresh()
    local s = guild()
    for i, name in ipairs(AUGMENTS) do
        s.o.message = detail(name, "ru")
        local h = HS.current(i * 0.016)
        eq(h and h.name, name, name)
    end
    eq(detail_reads(), 52, "the texts read once")
end)

test("the description is matched with its whitespace normalised", function()
    local HS = fresh()
    local s = guild({ message = "Повышает силу и магию пешек в вашем отряде." })
    eq(HS.current(0).name, "Job08_03", "a space for the line break")
    s.o.message = "  Повышает силу и магию пешек  в вашем\r\n отряде.\r\n"
    eq(HS.current(0.1).name, "Job08_03", "spaces and line breaks around and between")
    s.o.message = "Повышает силу и магию пешек\nв\tвашем отряде."
    eq(HS.current(0.2).name, "Job08_03", "\\n and a tab")
    -- whitespace only: words run together or another word are a different text
    s.o.message = "Повышает силу и магию пешекв вашем отряде."
    eq(HS.current(0.3), nil, "two words run together")
    s.o.message = "Повышает силу и магию пешек в твоём отряде."
    eq(HS.current(0.4), nil, "another word")
end)

test("an empty or unmatched description gives nil", function()
    local HS = fresh()
    local s = guild({ message = "" })
    eq(HS.current(0), nil, "empty")
    s.o.message = "\r\n  "
    eq(HS.current(0.1), nil, "only whitespace")
    s.o.message = "Удаляет выбранный усилитель."
    eq(HS.current(0.2), nil, "not an augment's")
    s.o.message = nil
    eq(HS.current(0.3), nil, "no message")
end)

test("the texts are read again on a miss, at most once per few seconds; each language is kept", function()
    local HS = fresh()
    local s = guild({ message = detail("Job05_00", "ru") })
    eq(HS.current(0).name, "Job05_00", "ru")
    eq(detail_reads(), 52, "read once")
    -- the game's language changes
    G.lang = "en"
    s.o.message = detail("Job05_00", "en")
    local h = HS.current(0.5)
    eq(h, nil, "a miss within a few seconds of the last read")
    eq(detail_reads(), 52, "not read again yet")
    for i = 1, 10 do HS.current(0.5 + i * 0.2) end
    eq(detail_reads(), 52, "still not")
    h = HS.current(3.1)
    eq(h and h.name, "Job05_00", "en, after the texts were read again")
    eq(detail_reads(), 104, "read twice")
    -- back to Russian: still known, no read
    G.lang = "ru"
    s.o.message = detail("Job01_03", "ru")
    eq(HS.current(3.2).name, "Job01_03", "ru kept")
    eq(detail_reads(), 104, "no read")
    -- a text in neither language: one more read after a few seconds, then quiet again
    s.o.message = "Удаляет выбранный усилитель."
    for i = 0, 20 do HS.current(3.3 + i * 0.1) end
    eq(detail_reads(), 104, "within 3 s of the last read")
    HS.current(6.2)
    eq(detail_reads(), 156, "one read")
    HS.current(6.3)
    eq(detail_reads(), 156, "then quiet")
end)

test("the guild's anchor: the text's x, the header bar's top, the panel growing up", function()
    local HS = fresh()
    local s = guild({ message = detail("Job05_00", "ru"), text_size = { 560, 64 }, root_size = { 620, 700 } })
    local h = HS.current(0)
    near(h.anchor.x, 967.4, 1e-9, "x: the description's")
    near(h.anchor.y, 591 - 60 / 2, 1e-9, "y: the augment set's s9g_Bg's y less half its height, not the other tab's")
    eq(h.anchor.up, true, "up: the panel's bottom by y, growing upwards")
    eq(read_flags(h), "read read read", "every part read")
    -- read anew each frame; the description's height plays no part any more
    s.o.text_pos, s.o.text_size = { 980, 360 }, { 560, 200 }
    s.specs.bar.pos, s.specs.bar.size = { 1164, 600 }, { 960, 50 }
    h = HS.current(0.016)
    near(h.anchor.x, 980, 1e-9, "x read anew")
    near(h.anchor.y, 600 - 50 / 2, 1e-9, "y read anew")
end)

test("the guild's width: the equipped table's right edge, hit_List's x + w, less the anchor's x", function()
    local HS = fresh()
    local s = guild({ message = detail("Job05_00", "ru"), root_size = { 620, 700 } })
    local h = HS.current(0)
    near(h.anchor.width, 970.4 + 520 - 967.4, 1e-9, "523: the table's right edge, not the root's 620")
    eq(read_flags(h), "read read read", "every part read")
    -- the anchor's x read anew each frame; the table's row (a scroll list's) only when the hover changes
    s.specs.hit.pos, s.specs.hit.size = { 990, 640 }, { 500, 48 }
    near(HS.current(0.016).anchor.width, 523, 1e-9, "the same augment: the row as read for it")
    s.o.message = detail("Job05_01", "ru")
    near(HS.current(0.02).anchor.width, 990 + 500 - 967.4, 1e-9, "another augment: the row read anew")
    s.o.text_pos = { 980, 360 }
    h = HS.current(0.032)
    near(h.anchor.x + h.anchor.width, 990 + 500, 1e-9, "the right edge stays the table's when x moves")
    -- the anchor's x fell back: 967.4 is the x the width is measured from
    s.o.text_pos = nil
    h = HS.current(0.048)
    near(h.anchor.width, 990 + 500 - 967.4, 1e-9, "from the fallback x")
    eq(read_flags(h), "fell back read read", "the width still read")
end)

test("the guild's width falls back to 523 when the table's row or its size cannot be read", function()
    local function width_of(setup)
        local HS = fresh()
        local s = guild({ message = detail("Job05_00", "ru"), root_size = { 620, 700 } })
        setup(s)
        local h = HS.current(0)
        assert(h, "still a hover")
        return h
    end
    for _, case in ipairs({
        { "no size", function(s) s.specs.hit.size = nil end },
        { "a zero width", function(s) s.specs.hit.size = { 0, 48 } end },
        { "a NaN width", function(s) s.specs.hit.size = { 0 / 0, 48 } end },
        { "no position", function(s) s.specs.hit.pos = nil end },
        { "an infinite x", function(s) s.specs.hit.pos = { math.huge, 631 } end },
        { "the right edge left of the anchor", function(s) s.specs.hit.pos = { 400, 631 } end },
        { "no hit_List", function(s) s.specs.ITM_List.el.child = nil end },
        { "the row raises", function(s) s.specs.hit.el.poison = true end },
    }) do
        local h = width_of(case[2])
        near(h.anchor.width, 523, 1e-9, case[1] .. ": 523")
        eq(read_flags(h), "read read fell back", case[1] .. ": the width fell back, the rest read")
    end
end)

test("the guild's anchor falls back to the header's y, then to 567; the text's x to 967.4", function()
    local HS = fresh()
    local s = guild({ message = detail("Job05_00", "ru"), root_size = { 620, 700 } })
    -- the bar's size cannot be read: the header panel's own y
    s.specs.bar.size = nil
    local h = HS.current(0)
    near(h.anchor.y, 567, 1e-9, "PNL_TitleBG's y")
    eq(h.anchor.up, true, "up")
    eq(read_flags(h), "read fell back read", "the header panel's y is a fallback of the bar's")
    -- nor the bar's position
    s.specs.bar.size, s.specs.bar.pos = { 960, 60 }, nil
    near(HS.current(0.016).anchor.y, 567, 1e-9, "the bar's position unreadable: PNL_TitleBG's y")
    -- nor the header's: the probes' 567
    s.specs.title.pos = nil
    near(HS.current(0.032).anchor.y, 567, 1e-9, "neither readable: 567")
    -- no elements at all, the text's position unreadable
    HS = fresh()
    s = guild({ message = detail("Job05_00", "ru"), tree = false })
    s.o.text_pos = nil
    h = HS.current(0)
    assert(h, "still a hover")
    near(h.anchor.x, 967.4, 1e-9, "x")
    near(h.anchor.y, 567, 1e-9, "y")
    near(h.anchor.width, 523, 1e-9, "width")
    eq(h.anchor.up, true, "up")
    eq(read_flags(h), "fell back fell back fell back", "nothing read")
end)

test("the guild's header and table row are looked for again, at most every 0.5 s, while missing; found, kept",
    function()
    local HS = fresh()
    local s = guild({ message = detail("Job05_00", "ru"), tree = false })
    near(HS.current(0).anchor.y, 567, 1e-9, "567 without the elements")
    -- the tree appears
    local specs = {}
    local first = elements(guild_tree(specs), s.specs)
    s.view.methods.get_Child = function() return first end
    specs.bar.pos = { 1164, 581 }
    specs.hit.pos = { 980.4, 631 }
    near(HS.current(0.2).anchor.y, 567, 1e-9, "not looked for again yet")
    near(HS.current(0.2).anchor.width, 523, 1e-9, "523 meanwhile")
    local h = HS.current(0.6)
    near(h.anchor.y, 551, 1e-9, "found 0.5 s later")
    near(h.anchor.width, 980.4 + 520 - 967.4, 1e-9, "the row found with it")
    local walks = #R.calls_of("get_Child")
    for i = 1, 10 do HS.current(0.6 + i * 0.1) end
    eq(#R.calls_of("get_Child"), walks, "found ones are kept: no walk")
    -- a bar whose position stops being read is looked for again
    specs.bar.pos = nil
    near(HS.current(1.7).anchor.y, 567, 1e-9, "PNL_TitleBG's y meanwhile")
    near(HS.current(1.8).anchor.y, 567, 1e-9, "looked for again: still unreadable")
    specs.bar.pos = { 1164, 591 }
    near(HS.current(2.0).anchor.y, 567, 1e-9, "not looked for again within 0.5 s")
    near(HS.current(2.4).anchor.y, 561, 1e-9, "found again")
    -- the table row is a scroll list's: read anew only when the hover changes, then, while it cannot be
    -- read, at most every 0.5 s
    specs.hit.pos = nil
    near(HS.current(2.5).anchor.width, 980.4 + 520 - 967.4, 1e-9, "the same augment: the row as read for it")
    s.o.message = detail("Job05_01", "ru")
    near(HS.current(2.6).anchor.width, 523, 1e-9, "another augment: read anew, unreadable: 523")
    specs.hit.pos = { 990.4, 631 }
    near(HS.current(2.8).anchor.width, 523, 1e-9, "not read again within 0.5 s")
    near(HS.current(3.1).anchor.width, 990.4 + 520 - 967.4, 1e-9, "read again 0.5 s later")
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

test("the scroll lists' rows are not kept: read from the drawn screen when the hover changes or the screen is "
    .. "drawn again, never in between", function()
    local HS = fresh()
    -- the item screen's first storage row
    local s = item_screen("ui060301_00", { item = 3502 })
    local row = s.specs.PNL_Party00.children[1].el
    near(HS.current(0).anchor.y, 423, 1e-9, "read")
    local from = #R.calls
    for i = 1, 20 do HS.current(i * 0.016) end
    eq(asked_since({ row }, from), 0, "the same ring: the row not asked")
    s.o.item = 3507
    from = #R.calls
    near(HS.current(0.5).anchor.y, 423, 1e-9, "another ring: read")
    eq(asked_since({ row }, from) > 0, true, "the row asked once more")
    from = #R.calls
    HS.current(0.52)
    eq(asked_since({ row }, from), 0, "and not again")
    -- the screen hidden, then drawn again on the same ring: read anew
    s.o.drawn = false
    eq(HS.current(0.6), nil, "hidden")
    s.o.drawn = true
    from = #R.calls
    eq(HS.current(0.62).id, 3507, "drawn again")
    eq(asked_since({ row }, from) > 0, true, "the row read anew")

    -- the guild's equipped table: the game rebuilds its rows while the screen stays drawn
    HS = fresh()
    local g = guild({ message = detail("Job05_00", "ru") })
    local old = g.specs.hit.el
    near(HS.current(0).anchor.width, 523, 1e-9, "read")
    local fresh_specs = {}
    local hit = { name = "hit_List", pos = { 990.4, 631 }, size = { 520, 48 } }
    g.specs.SCL_AbList.el.child = elements({ { name = "ITM_List", children = { hit } } }, fresh_specs)
    from = #R.calls
    for i = 1, 20 do near(HS.current(i * 0.016).anchor.width, 523, 1e-9, "the same augment " .. i) end
    eq(asked_since({ old, hit.el }, from), 0, "neither row asked for the same augment")
    g.o.message = detail("Job05_01", "ru")
    from = #R.calls
    near(HS.current(0.5).anchor.width, 990.4 + 520 - 967.4, 1e-9, "another augment: the new row read")
    eq(asked_since({ old }, from), 0, "the old row never asked again")
end)

test("the guild gives a hover only while the Augments panel is shown: the root and the text visible", function()
    local HS = fresh()
    local s = guild({ message = detail("Job05_00", "ru"), root_actual = true, text_actual = true })
    eq(HS.current(0).name, "Job05_00", "both shown")
    -- Q / E to a skill tab (or Z / C, which goes back to Навыки оружия): the augment set's panel hidden while the
    -- description keeps its last text
    s.o.root_actual = false
    eq(HS.current(0.016), nil, "the root hidden: nil")
    s.o.root_actual, s.o.text_actual = true, false
    eq(HS.current(0.032), nil, "the text hidden: nil")
    s.o.text_actual = true
    eq(HS.current(0.048).name, "Job05_00", "the Augments tab again")
    -- without get_ActualVisible, get_Visible
    s.o.root_actual, s.o.text_actual = nil, nil
    s.o.root_visible = false
    eq(HS.current(0.064), nil, "the root's get_Visible false: nil")
    s.o.root_visible, s.o.text_visible = true, false
    eq(HS.current(0.08), nil, "the text's get_Visible false: nil")
    -- get_ActualVisible answers: it alone counts
    s.o.text_actual = true
    eq(HS.current(0.096).name, "Job05_00", "ActualVisible true, Visible false: shown")
    s.o.root_actual, s.o.root_visible = false, true
    eq(HS.current(0.112), nil, "ActualVisible false, Visible true: hidden")
end)

test("a visibility that cannot be read counts as shown", function()
    local HS, Hook = fresh()
    local s = guild({ message = detail("Job05_00", "ru") })
    eq(HS.current(0).name, "Job05_00", "neither method answers: shown")
    s.o.root_actual, s.o.root_visible, s.o.text_actual, s.o.text_visible = "raise", "raise", "raise", "raise"
    eq(HS.current(0.016).name, "Job05_00", "both raise: shown")
    s.o.root_actual, s.o.root_visible, s.o.text_actual, s.o.text_visible = nil, nil, nil, nil
    s.comp.fields._PnlAbilityRoot = nil
    eq(HS.current(0.032).name, "Job05_00", "no root at all: shown")
    eq(Hook.info().errors, 0, "no error of the mod's own")
end)

test("the pawn's augments give who = pawn, and base(chara_id) is the pawn's own numbers", function()
    local HS = fresh()
    local s = guild({ message = detail("Job04_04", "ru"), chara = CASCA_ID })
    local h = HS.current(0)
    eq(h.name, "Job04_04", "the augment")
    eq(h.who, "pawn", "who")
    eq(h.chara_id, CASCA_ID, "chara_id")
    local b = HS.base(h.chara_id)
    eq(b.who, "pawn", "base.who")
    near(b.phys_defence, 375, 1e-9, "phys_defence")
    near(b.magic_defence, 440, 1e-9, "magic_defence")
    near(b.strength, 410, 1e-9, "strength, not the player's 420")
    near(b.magic, 440, 1e-9, "magic")
    -- Z back to the player
    s.o.chara = PLAYER_ID
    h = HS.current(0.016)
    eq(h.who, "player", "the player")
    b = HS.base(h.chara_id)
    eq(b.who, "player", "the player's base")
    near(b.phys_defence, 380, 1e-9, "380")
    near(b.magic_defence, 373.8, 1e-9, "373.8")
    near(b.strength, 420, 1e-9, "420")
    near(b.magic, 372.2, 1e-9, "372.2")
end)

-- the base ----------------------------------------------------------------------------------------------------------

test("base of a character without a calculator is nil, never the player's", function()
    local HS = fresh()
    eq(HS.base(123456), nil, "unknown id")
    eq(HS.base(nil), nil, "no id")
    eq(HS.base("2891076981"), nil, "not a number")
    -- the pawn's calculator gone: nil, not the player's numbers
    table.remove(G.calcs, 2)
    eq(HS.base(CASCA_ID), nil, "Casca without a calculator")
    near(HS.base(PAWN2_ID).strength, 320, 1e-9, "another pawn's own")
end)

test("base reads the dictionary by its enumerator (fields or getters), else by ContainsKey / get_Item", function()
    local HS = fresh()
    G.no_lookup = true
    near(HS.base(CASCA_ID).strength, 410, 1e-9, "enumerator, key / value fields")
    G.kv_getters = true
    near(HS.base(CASCA_ID).strength, 410, 1e-9, "enumerator, get_Key / get_Value")
    G.kv_getters, G.no_lookup, G.no_enumerator = false, false, true
    near(HS.base(CASCA_ID).strength, 410, 1e-9, "ContainsKey / get_Item")
    G.no_enumerator = false
    G.calcs[2][1] = R.object("app.CharacterID", { value__ = CASCA_ID })
    near(HS.base(CASCA_ID).strength, 410, 1e-9, "a boxed key")
end)

test("base is nil when its numbers cannot be read", function()
    local HS = fresh()
    G.calcs[2][2] = R.object("app.PlayerStatusCalculator", {}, { calcBasicAttackDefence = function() return nil end })
    eq(HS.base(CASCA_ID), nil, "no status")
    G.calcs[2][2] = calculator({ def = 375.0, mdef = 0 / 0, atk = 410.0, matk = 440.0 })
    eq(HS.base(CASCA_ID), nil, "a NaN")
    G.calcs[2][2] = calculator({ def = 375.0, mdef = 440.0, atk = 410.0 })
    eq(HS.base(CASCA_ID), nil, "a number missing")
end)

test("base's who is unknown when the player's CharaID cannot be read", function()
    local HS = fresh()
    G.player.chara_id = nil
    local b = HS.base(CASCA_ID)
    near(b.strength, 410, 1e-9, "the numbers")
    eq(b.who, nil, "who")
end)

test("the player's CharaID is read from <CharaID>k__BackingField when get_CharaID gives nothing", function()
    local HS = fresh()
    G.player.chara_id = nil
    G.player.fields["<CharaID>k__BackingField"] = PLAYER_ID
    eq(HS.base(PLAYER_ID).who, "player", "base")
    guild({ message = detail("Job05_00", "ru") })
    eq(HS.current(0).who, "player", "hover")
end)

-- the calculator and the player's id, for game/stat_check.lua -----------------------------------------------------

test("calculator(chara_id) is the one base() reads for that character; player_id() is the player's CharaID", function()
    local HS = fresh()
    eq(HS.calculator(PLAYER_ID), G.calcs[1][2], "the player's")
    eq(HS.calculator(CASCA_ID), G.calcs[2][2], "Casca's")
    eq(HS.calculator(CASCA_ID - 0x100000000), G.calcs[2][2], "an id given as a signed 32-bit number")
    G.calcs[2][1] = R.object("app.CharacterID", { value__ = CASCA_ID })
    eq(HS.calculator(CASCA_ID), G.calcs[2][2], "a boxed key")
    eq(HS.calculator(123456), nil, "no calculator")
    eq(HS.calculator(nil), nil, "no id")
    eq(HS.calculator("2891076981"), nil, "not a number")
    eq(HS.player_id(), PLAYER_ID, "the player's CharaID")
    G.player.chara_id = nil
    G.player.fields["<CharaID>k__BackingField"] = PLAYER_ID - 0x100000000
    eq(HS.player_id(), PLAYER_ID, "by its backing field, signed")
    G.player = nil
    eq(HS.player_id(), nil, "no player")
    G.cm.poison = true
    eq(HS.calculator(PLAYER_ID), nil, "the manager raises: nil")
end)

-- job ---------------------------------------------------------------------------------------------------------------

test("job is the player's current vocation", function()
    local HS = fresh()
    eq(HS.job(), 4, "Thief")
    G.job = 10
    eq(HS.job(), 10, "Warfarer")
    G.job = R.object("app.Character.JobEnum", { value__ = 7 })
    eq(HS.job(), 7, "boxed")
    G.job = 0
    eq(HS.job(), nil, "None")
    G.job = nil
    eq(HS.job(), nil, "unreadable")
    G.player = nil
    eq(HS.job(), nil, "no player")
end)

test("job(chara_id) is that character's vocation by its calculator's Human; else the player's", function()
    local HS = fresh()
    G.calcs[2][2] = calculator({ def = 375.0, mdef = 440.0, atk = 410.0, matk = 440.0, job = 5 })
    G.calcs[3][2] = calculator({ def = 300.0, mdef = 310.0, atk = 320.0, matk = 330.0,
                                 job = R.object("app.Character.JobEnum", { value__ = 9 }) })
    eq(HS.job(CASCA_ID), 5, "Casca a Warrior, the player a Thief")
    eq(HS.job(PAWN2_ID), 9, "the other pawn a Trickster, boxed")
    eq(HS.job(), 4, "no id: the player's")
    eq(HS.job(nil), 4, "nil: the player's")
    eq(HS.job(PLAYER_ID), 4, "the player's calculator without Human: the player's by get_ManualPlayer")
    eq(HS.job(123456), 4, "no calculator: the player's")
    eq(HS.job("2283028347"), 4, "not a number: the player's")
    G.calcs[2][2] = calculator({ def = 375.0, mdef = 440.0, atk = 410.0, matk = 440.0, job = 0 })
    eq(HS.job(CASCA_ID), 4, "None: the player's")
    G.calcs[2][2].fields.Human.poison = true
    eq(HS.job(CASCA_ID), 4, "Human raises: the player's")
    G.calcs[2][2] = calculator({ def = 375.0, mdef = 440.0, atk = 410.0, matk = 440.0, job = 5 })
    G.job = nil
    eq(HS.job(CASCA_ID), 5, "the player's unreadable: Casca's still")
    G.calcs[2][2] = calculator({ def = 375.0, mdef = 440.0, atk = 410.0, matk = 440.0 })
    eq(HS.job(CASCA_ID), nil, "neither readable: nil")
end)

-- the totals and what is on, for the total line ---------------------------------------------------------------------

-- A set's keys, sorted, as one text ("nil" for no set).
local function keys(set)
    if set == nil then return "nil" end
    local out = {}
    for k, v in pairs(set) do
        assert(v == true, "a set: " .. tostring(k))
        out[#out + 1] = tostring(k)
    end
    table.sort(out)
    return table.concat(out, " ")
end

test("totals(chara_id): Basic + Additional + Armor of calcAttackDefenceWithEquipmentAndBuff, each one's own", function()
    local HS = fresh()
    local t = HS.totals(PLAYER_ID)
    near(t.phys, 1645, 1e-9, "the player's defence: 380 + 159 + 1106, the status screen's «1645 (380)»")
    near(t.magic, 373.8 + 157.14 + 964, 1e-9, "his magick defence, as read (the panel floors it)")
    local c = HS.totals(CASCA_ID)
    near(c.phys, 1275, 1e-9, "Casca's own defence")
    near(c.magic, 1240, 1e-9, "Casca's own magick defence")
    near(HS.totals(CASCA_ID - 0x100000000).phys, 1275, 1e-9, "an id given as a signed 32-bit number")
    eq(HS.totals(123456), nil, "no calculator: never another's")
    eq(HS.totals(nil), nil, "no id")
    eq(HS.totals("2891076981"), nil, "not a number")
    eq(HS.totals(PAWN2_ID), nil, "no struct")
end)

test("totals: a stat with a part that cannot be read is nil, the other stays; neither readable gives nil", function()
    local HS = fresh()
    local n = G.calcs[1][2].n
    n.total[1][3] = nil
    local t = HS.totals(PLAYER_ID)
    eq(t.phys, nil, "no ArmorDefence: no defence")
    near(t.magic, 1494.94, 1e-9, "the magick defence still")
    n.total[2][2] = 0 / 0
    eq(HS.totals(PLAYER_ID), nil, "a NaN part of the other: none left")
    n.total = { { 380.0, 159.0, 1106.0 }, { 373.8, 157.14, math.huge } }
    eq(HS.totals(PLAYER_ID).magic, nil, "an infinite part")
end)

-- Seven augment slots (No0..No6) of one vocation: `on` in the first ones, the rest empty (0).
local function slots_of(...)
    local s = { [0] = 0, [1] = 0, [2] = 0, [3] = 0, [4] = 0, [5] = 0, [6] = 0 }
    for i, v in ipairs({ ... }) do s[i - 1] = v end
    return s
end

test("equipped(chara_id): the player's augments for his vocation, by his Human, and his gear, as sets", function()
    local HS = fresh()
    local e = HS.equipped(PLAYER_ID)
    eq(keys(e.augments), "Job01_01 Job05_00", "his augments, empty slots left out")
    eq(table.concat(G.asked, " "), "4/0 4/1 4/2 4/3 4/4 4/5 4/6",
        "slots No0..No6 of his vocation, the Thief's (app.AbilityContext.AbilitySlot has seven)")
    eq(keys(e.items), "1001 2003 3502", "his gear: an empty or null slot left out")
    -- another vocation: its own slots; a boxed id
    G.job = 5
    G.player_slots[5] = slots_of(ID.Job03_00, R.object("app.HumanAbilityID", { value__ = ID.Job05_02 }))
    eq(keys(HS.equipped(PLAYER_ID).augments), "Job03_00 Job05_02", "the Warrior's")
    -- every slot empty: known, none on
    G.player_slots[5] = slots_of()
    eq(keys(HS.equipped(PLAYER_ID).augments), "", "none")
end)

test("equipped(chara_id): a pawn's by her calculator's Human, never the player's", function()
    local HS = fresh()
    G.calcs[2][2] = calculator({ def = 375.0, mdef = 440.0, atk = 410.0, matk = 440.0, job = 5,
                                 slots = { [5] = slots_of(ID.Job05_00, ID.Job01_01), [4] = slots_of(ID.Job04_04) },
                                 equips = { 2001, 3509, 3511 } })
    G.asked = {}
    local e = HS.equipped(CASCA_ID)
    eq(keys(e.augments), "Job01_01 Job05_00", "her augments, the Warrior's")
    eq(G.asked[1], "5/0", "asked for her vocation, not the player's 4")
    eq(keys(e.items), "2001 3509 3511", "her gear")
    eq(keys(HS.equipped(CASCA_ID - 0x100000000).items), "2001 3509 3511", "a signed id")
    -- her calculator without a Human: her augments unknown, not the player's
    G.calcs[2][2] = calculator({ def = 375.0, mdef = 440.0, atk = 410.0, matk = 440.0, equips = { 2001 } })
    e = HS.equipped(CASCA_ID)
    eq(e.augments, nil, "unknown")
    eq(keys(e.items), "2001", "her gear still")
    -- no calculator at all: nothing known
    e = HS.equipped(123456)
    eq(e.augments, nil, "no augments")
    eq(e.items, nil, "no items")
    eq(HS.equipped(nil), nil, "no id")
    eq(HS.equipped("2283028347"), nil, "not a number")
end)

test("equipped: a part that cannot be read is nil, the other stays", function()
    local function case(what, setup, check)
        local HS, Hook = fresh()
        setup()
        local ok, e = pcall(HS.equipped, PLAYER_ID)
        assert(ok, what .. ": " .. tostring(e))
        check(e)
        eq(Hook.info().errors, 0, what .. ": no error of the mod's own")
    end
    case("no slot gives anything", function() G.player_slots[4] = {} end, function(e)
        eq(e.augments, nil, "unknown, not empty")
        eq(keys(e.items), "1001 2003 3502", "the gear")
    end)
    case("no AbilityContext", function() G.player_ac = nil end, function(e) eq(e.augments, nil, "unknown") end)
    case("the vocation None", function() G.job = 0 end, function(e) eq(e.augments, nil, "unknown") end)
    case("the vocation unreadable", function() G.job = nil end, function(e) eq(e.augments, nil, "unknown") end)
    case("the AbilityContext raises", function() G.player_ac.poison = true end,
        function(e) eq(e.augments, nil, "unknown") end)
    case("no Equips", function() G.calcs[1][2].n.equips = nil end, function(e)
        eq(e.items, nil, "unknown")
        eq(keys(e.augments), "Job01_01 Job05_00", "the augments")
    end)
    case("get_elements raises", function()
        local calc = G.calcs[1][2]
        local get = calc.methods.getEquipData
        calc.methods.getEquipData = function(...)
            local roe = get(...)
            roe.fields.Data.fields.Equips.get_elements = function() error("get_elements raised") end
            return roe
        end
    end, function(e) eq(e.items, nil, "unknown") end)
    case("the calculator raises", function() G.calcs[1][2].poison = true end, function(e)
        eq(e.items, nil, "no gear")
        eq(keys(e.augments), "Job01_01 Job05_00", "the player's augments by his own Human")
    end)
    case("the player's Human cannot be read", function() G.player.methods.get_Human = function() return nil end end,
        function(e) eq(e.augments, nil, "his calculator has no Human either") end)
end)

-- An Equips array whose get_elements gives `elements` (a Lua sequence standing for the game's container).
local function equips_giving(elements)
    local arr = R.array({}, "app.ItemDefine.StorageData[]")
    arr.get_elements = function() return elements end
    return arr
end

test("equipped is unknown, not \"not on\", when one slot or entry is not read", function()
    local function case(what, setup, check)
        local HS, Hook = fresh()
        setup()
        local e = HS.equipped(PLAYER_ID)
        check(e)
        eq(Hook.info().errors, 0, what .. ": no error of the mod's own")
    end
    -- the augments: one slot gives no number, even with the hovered augment found in another
    case("a slot reads nil", function() G.player_slots[4][4] = nil end, function(e)
        eq(e.augments, nil, "a slot read nothing: unknown, Стойкость in slot 2 or not")
        eq(keys(e.items), "1001 2003 3502", "the gear stays")
    end)
    case("a slot reads no number", function() G.player_slots[4][6] = "Job04_00" end,
        function(e) eq(e.augments, nil, "not a number: unknown") end)
    case("a slot raises", function()
        local get = G.player_ac.methods[GET_ABILITY]
        G.player_ac.methods[GET_ABILITY] = function(this, job, slot)
            if slot == 3 then error("getAbility raised") end
            return get(this, job, slot)
        end
    end, function(e) eq(e.augments, nil, "unknown") end)
    case("an id with no name", function() G.player_slots[4][5] = 999 end,
        function(e) eq(e.augments, nil, "999 might be Стойкость under another value: unknown") end)
    case("a negative id", function() G.player_slots[4][5] = -3 end,
        function(e) eq(e.augments, nil, "not 0, so not an empty slot, and no name: unknown") end)
    -- the items: an entry that cannot be read, or more than MAX_EQUIPS (32)
    case("a null entry", function() G.calcs[1][2].n.equips = { 1001, 3502, false } end,
        function(e) eq(keys(e.items), "1001 3502", "a null entry is an empty slot: read") end)
    case("an entry whose id cannot be read", function()
        local calc = G.calcs[1][2]
        calc.n.equips = nil
        calc.methods.getEquipData = function()
            local bad = R.object("app.ItemDefine.StorageData", {}, { get_ItemId = function() return nil end })
            local arr = R.array({ storage(1001), bad }, "app.ItemDefine.StorageData[]")
            return R.object("app.ReadOnlyEquipData", { Data = R.object("app.EquipData", { Equips = arr }) })
        end
    end, function(e)
        eq(e.items, nil, "unknown")
        eq(keys(e.augments), "Job01_01 Job05_00", "the augments stay")
    end)
    case("an entry whose id raises", function()
        local calc = G.calcs[1][2]
        local get = calc.methods.getEquipData
        calc.methods.getEquipData = function(...)
            local roe = get(...)
            roe.fields.Data.fields.Equips.items[4].poison = true
            return roe
        end
    end, function(e) eq(e.items, nil, "unknown") end)
    case("an entry that cannot be had", function()
        local calc = G.calcs[1][2]
        calc.methods.getEquipData = function()
            local elements = setmetatable({}, {
                __len = function() return 2 end,
                __index = function(_, i) if i == 2 then error("element raised") end return storage(3502) end,
            })
            return R.object("app.ReadOnlyEquipData", { Data = R.object("app.EquipData",
                { Equips = equips_giving(elements) }) })
        end
    end, function(e) eq(e.items, nil, "unknown") end)
    case("an array with no length", function()
        local calc = G.calcs[1][2]
        calc.methods.getEquipData = function()
            local entries = { storage(3502), false, storage(1001) }
            local elements = setmetatable({}, {
                __len = function() error("no length") end,
                __index = function(_, i) return entries[i] end,
            })
            return R.object("app.ReadOnlyEquipData", { Data = R.object("app.EquipData",
                { Equips = equips_giving(elements) }) })
        end
    end, function(e)
        eq(e.items, nil, "walked, but a null entry and an unread one look alike: unknown")
        eq(keys(e.augments), "Job01_01 Job05_00", "the augments stay")
    end)
    case("33 entries", function()
        local ids = {}
        for i = 1, 33 do ids[i] = 0 end
        ids[1] = 3502
        G.calcs[1][2].n.equips = ids
    end, function(e) eq(e.items, nil, "past MAX_EQUIPS: the 33rd unread, unknown") end)
    case("32 entries", function()
        local ids = {}
        for i = 1, 32 do ids[i] = 0 end
        ids[32] = 3502
        G.calcs[1][2].n.equips = ids
    end, function(e) eq(keys(e.items), "3502", "all read") end)
end)

test("totals and equipped only read: the calc* method and getters, never a setter", function()
    local HS = fresh()
    local from = #R.calls + 1
    HS.totals(PLAYER_ID)
    HS.equipped(PLAYER_ID)
    local sigs, seen = {}, {}
    for i = from, #R.calls do
        local c = R.calls[i]
        if not seen[c.sig] then
            seen[c.sig] = true
            sigs[#sigs + 1] = c.sig
        end
    end
    table.sort(sigs)
    eq(table.concat(sigs, " "), "GetEnumerator MoveNext calcAttackDefenceWithEquipmentAndBuff "
        .. GET_ABILITY .. " getEquipData get_CharaID get_Current get_Human get_ItemId get_JobContext get_ManualPlayer "
        .. "get_PlayerStatusCalculatorHolder", "the calls made")
end)

test("augments(context, job) and equips(array): the reading game/stat_check.lua shares, and whether it is whole",
    function()
    local HS = fresh()
    local list, whole, all_read = HS.augments(G.player_ac, 4)
    eq(table.concat(list, " "), "Job01_01 Job05_00", "the names, sorted")
    eq(whole, true, "every slot read and named")
    eq(all_read, true, "every slot gave a number")
    list, whole, all_read = HS.augments(G.player_ac, 7)
    eq(tostring(list) .. " " .. tostring(whole) .. " " .. tostring(all_read), "nil false false",
        "no slot of that vocation read")
    eq(HS.augments(nil, 4), nil, "no context")
    -- a slot that gives nothing counts as empty while another reads; an unnamed id is its number
    G.player_slots[4] = { [0] = 999, [2] = ID.Job01_01 }
    list, whole, all_read = HS.augments(G.player_ac, 4)
    eq(table.concat(list, " "), "999 Job01_01", "the list as before")
    eq(whole, false, "not whole")
    eq(all_read, false, "a slot gave nothing")
    G.player_slots[4] = slots_of(999)
    list, whole, all_read = HS.augments(G.player_ac, 4)
    eq(whole, false, "an unnamed id alone: not whole")
    eq(all_read, true, "but every slot gave a number")
    -- a negative id is not an empty slot: listed by its number, and the read is not whole
    G.player_slots[4] = slots_of(-3, ID.Job01_01)
    list, whole, all_read = HS.augments(G.player_ac, 4)
    eq(table.concat(list, " ") .. " " .. tostring(whole) .. " " .. tostring(all_read), "-3 Job01_01 false true",
        "a negative id")
    local ids
    ids, whole = HS.equips(R.array({ storage(3502), false, storage(0), storage(1001) }, "app.ItemDefine.StorageData[]"))
    eq(table.concat(ids, " "), "3502 1001", "the ids above 0, in the array's order")
    eq(whole, true, "a null entry and a 0 are empty slots")
    eq(#HS.equips(R.array({}, "app.ItemDefine.StorageData[]")), 0, "an empty array")
    eq(HS.equips(nil), nil, "no array")
    local bad = R.object("app.ItemDefine.StorageData", {}, { get_ItemId = function() return nil end })
    ids, whole = HS.equips(R.array({ storage(3502), bad }, "app.ItemDefine.StorageData[]"))
    eq(table.concat(ids, " ") .. " " .. tostring(whole), "3502 false", "an unread entry: the rest, not whole")
    -- no length: walked as Safe.items walks it, never whole
    local entries = { storage(3502), false, storage(1001) }
    ids, whole = HS.equips(equips_giving(setmetatable({}, {
        __len = function() error("no length") end,
        __index = function(_, i) return entries[i] end,
    })))
    eq(table.concat(ids, " ") .. " " .. tostring(whole), "3502 1001 false", "no length: the ids walked, not whole")
end)

-- raising fakes -----------------------------------------------------------------------------------------------------

-- One case in a fresh world: setup() makes a fake raise, check(HS) checks the answers; no call raises, and none counts
-- an error of the mod's own (the reads go through Safe).
local function raising(what, setup, check)
    local HS, Hook = fresh()
    local ok, err = pcall(function() check(HS, setup()) end)
    assert(ok, what .. ": " .. tostring(err))
    eq(Hook.info().errors, 0, what .. ": no error of the mod's own")
end

test("fakes that raise give nil, and nothing raises", function()
    raising("the scene", function()
        G.scene.poison = true
        item_screen("ui060301_00", { item = 3502 })
    end, function(HS) eq(HS.current(0), nil, "the scene raises") end)
    raising("the GUI", function()
        local s = item_screen("ui060401_00", { item = 3518, chara = CASCA_ID })
        s.gui.poison = true
    end, function(HS) eq(HS.current(0), nil, "the GUI raises at the look") end)
    raising("the item screen's component", function()
        local s = item_screen("ui060301_00", { item = 3502 })
        s.comp.poison = true
    end, function(HS) eq(HS.current(0), nil, "the component raises") end)
    raising("the item screen's elements", function()
        local s = item_screen("ui060301_00", { item = 3502 })
        s.view.poison = true
    end, function(HS)
        local h = HS.current(0)
        eq(h and h.id, 3502, "the ring, at the measured place")
        near(h.anchor.y, 423, 1e-9, "y")
    end)
    raising("the guild's text", function()
        local s = guild({ message = detail("Job05_00", "ru") })
        s.comp.fields._TxtAbilityInfo.poison = true
    end, function(HS) eq(HS.current(0), nil, "the text raises") end)
    raising("the guild's elements", function()
        local s = guild({ message = detail("Job05_00", "ru") })
        s.view.poison = true
    end, function(HS)
        local h = HS.current(0)
        eq(h and h.name, "Job05_00", "the augment, by the header's measured place")
        near(h.anchor.y, 567, 1e-9, "y")
    end)
    raising("the guild's header bar", function()
        local s = guild({ message = detail("Job05_00", "ru") })
        s.specs.bar.el.poison = true
    end, function(HS) near(HS.current(0).anchor.y, 567, 1e-9, "PNL_TitleBG's y") end)
    raising("getAbilityDetail", function()
        guild({ message = detail("Job05_00", "ru") })
        R.method("app.GUIBase", DETAIL, function() error("getAbilityDetail raised") end, STATIC)
    end, function(HS) eq(HS.current(0), nil, "getAbilityDetail raises") end)
    raising("the character manager", function()
        G.cm.poison = true
        guild({ message = detail("Job05_00", "ru") })
    end, function(HS)
        eq(HS.base(PLAYER_ID), nil, "base")
        eq(HS.job(), nil, "job")
        local h = HS.current(0)
        eq(h.name, "Job05_00", "the augment still")
        eq(h.who, nil, "who unknown")
    end)
    raising("the calculator", function()
        G.calcs[2][2].poison = true
    end, function(HS) eq(HS.base(CASCA_ID), nil, "the calculator raises") end)
    raising("sdk.typeof", function()
        sdk.typeof = function() error("typeof raised") end
        item_screen("ui060301_00", { item = 3502 })
    end, function(HS) eq(HS.current(0), nil, "sdk.typeof raises") end)
end)

test("a raising read of the hovered thing does not drop the kept screen", function()
    local HS = fresh()
    local s = item_screen("ui060301_00", { item = 3502 })
    eq(HS.current(0).id, 3502, "found")
    s.comp.poison = true
    eq(HS.current(0.1), nil, "the component raises")
    s.comp.poison = false
    eq(HS.current(0.2).id, 3502, "back")
    eq(scans(), 1, "kept: no look")
end)

T.finish()
