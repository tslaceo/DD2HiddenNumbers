package.path = "mod/reframework/autorun/?.lua;tests/?.lua;" .. package.path

local T = require("testlib")
local test, eq = T.test, T.eq
local R = require("stubs/reframework")

test("a type is missing until something declares it", function()
    R.new()
    eq(sdk.find_type_definition("app.GUIBase"), nil, "undeclared")
    R.method("app.GUIBase", "getItemName(System.Int32)", function(id) return "item " .. id end, { static = true })
    eq(sdk.find_type_definition("app.GUIBase"):get_full_name(), "app.GUIBase", "declared by its first method")
    R.undeclare("app.GUIBase")
    eq(sdk.find_type_definition("app.GUIBase"), nil, "missing again")
end)

test("a method signature needs ', ' between parameter types", function()
    R.new()
    R.method("via.gui.message", "get(System.Guid, via.Language)", function() return "text" end, { static = true })
    local td = sdk.find_type_definition("via.gui.message")
    eq(td:get_method("get(System.Guid,via.Language)"), nil, "no space after the comma")
    eq(td:get_method("get(System.Guid, via.Language)"):call(nil, 1, 2), "text", "exact signature")
    eq(td:get_method("get"):call(nil), "text", "bare name")
end)

test("objects: an unknown method gives nil, a recorded call keeps its arguments", function()
    R.new()
    local o = R.object("app.Character", { hp = 5 }, { get_Hp = function(self) return self.fields.hp end })
    eq(o:call("get_Hp"), 5, "known method")
    eq(o:call("get_Nothing"), nil, "unknown method")
    eq(o:get_field("hp"), 5, "field")
    local calls = R.calls_of("get_Hp")
    eq(#calls, 1, "one call recorded")
    eq(calls[1].this, o, "this")
    eq(o:get_type_definition():get_full_name(), "app.Character", "type")
    o.poison = true
    local ok = pcall(o.call, o, "get_Hp")
    eq(ok, false, "a poisoned object raises")
end)

test("static methods get no this, instance methods need one", function()
    R.new()
    R.method("app.GUIBase", "getName(app.Character)", function(c) return "static " .. tostring(c) end, { static = true })
    R.method("app.Character", "get_Hp", function(self) return self.fields.hp end)
    local m = sdk.find_type_definition("app.GUIBase"):get_method("getName(app.Character)")
    eq(m:call(nil, "x"), "static x", "static")
    local hp = sdk.find_type_definition("app.Character"):get_method("get_Hp")
    eq(pcall(hp.call, hp, nil), false, "instance method without this")
    eq(hp:call(R.object("app.Character", { hp = 7 })), 7, "instance method with this")
end)

test("enum types list their members as static fields", function()
    R.new()
    R.enum("app.BattleModeEnum", { Normal = 0, Ready = 1, Battle = 2 })
    local td = sdk.find_type_definition("app.BattleModeEnum")
    eq(td:is_enum(), true, "enum")
    local found = {}
    for _, f in ipairs(td:get_fields()) do
        if f:is_static() then found[f:get_name()] = f:get_data(nil) end
    end
    eq(found.Normal, 0, "Normal")
    eq(found.Battle, 2, "Battle")
end)

test("containers like sol's: a length and 1-based indexes, no raw entries, userdata to type()", function()
    R.new()
    local c = R.container({ "a", "b", "c" })
    eq(type(c), "userdata", "not a table to type()")
    eq(#c, 3, "length")
    eq(c[1], "a", "first")
    eq(c[3], "c", "last")
    eq(c[0], nil, "no index 0")
    eq(c[4], nil, "past the end")
    eq(rawlen(c), 0, "no raw entries")
    eq(next(c), nil, "nothing to next()")
    local seen = {}
    for i, v in ipairs(c) do seen[i] = v end
    eq(table.concat(seen), "abc", "ipairs")
    eq(type({}), "table", "type() of anything else is unchanged")
end)

test("R.new{ containers = true }: fields, methods and array elements come in containers", function()
    R.new({ containers = true })
    R.enum("app.BattleModeEnum", { Normal = 0, Battle = 2 })
    local td = sdk.find_type_definition("app.BattleModeEnum")
    local fields = td:get_fields()
    eq(type(fields), "userdata", "fields")
    eq(#fields, 3, "value__ and two members")
    eq(fields[2]:get_name(), "Battle", "members by name")
    R.method("app.GUIBase", "getName(app.Character)", function() end, { static = true })
    eq(type(sdk.find_type_definition("app.GUIBase"):get_methods()), "userdata", "methods")
    local arr = R.object("app.HumanSkillContext.EquipedSkill[]")
    arr.items = { "x", "y" }
    local el = arr:get_elements()
    eq(type(el), "userdata", "elements")
    eq(#el, 2, "two elements")
    eq(el[2], "y", "second element")
    R.new()
    eq(type(td:get_fields()), "table", "a plain world keeps plain tables")
end)

test("lists answer get_Count and get_Item", function()
    R.new()
    local list = R.list({ "a", "b" })
    eq(list:call("get_Count"), 2, "count")
    eq(list:call("get_Item", 1), "b", "item")
end)

test("arrays answer get_Count, give nil for get_Item and their items through get_elements, as in the game", function()
    R.new({ containers = true })
    local arr = R.array({ "a", "b" }, "app.JewelryAdditionalParameter[]")
    eq(arr:call("get_Count"), 2, "count")
    eq(arr:call("get_Item", 0), nil, "no item by get_Item")
    local el = arr:get_elements()
    eq(type(el), "userdata", "a container")
    eq(el[2], "b", "the items by get_elements")
end)

test("hooks are captured and fired with a hook storage", function()
    R.new()
    local m = R.method("app.HitController", "damageProc", function() end)
    local seen = {}
    sdk.hook(m, function(args)
        thread.get_hook_storage().arg = sdk.to_int64(args[2])
        seen.pre = true
    end, function(retval)
        seen.stored = thread.get_hook_storage().arg
        return retval
    end)
    local hk = R.hook_of("app.HitController", "damageProc")
    eq(R.fire(hk, { {}, R.int_slot(41) }, "ret"), "ret", "post returns the retval")
    eq(seen.pre, true, "pre ran")
    eq(seen.stored, 41, "pre and post share the storage")
    eq(thread.get_hook_storage(), nil, "storage popped after the call")
    eq(sdk.to_managed_object(R.int_slot(1)), nil, "a non-reference slot is refused")
    eq(#R.bad, 1, "and recorded")
end)

test("nested hooked calls: each has its own storage, none is current after a nested one ended", function()
    R.new()
    local outer_m = R.method("app.HitController", "damageProc", function() end)
    local inner_m = R.method("app.HitController", "updateDamage", function() end)
    local seen = {}
    sdk.hook(outer_m, function() thread.get_hook_storage().who = "outer" end,
        function(retval)
            seen.outer_post = thread.get_hook_storage().who
            return retval
        end)
    sdk.hook(inner_m, function() thread.get_hook_storage().who = "inner" end,
        function(retval)
            seen.inner_post = thread.get_hook_storage().who
            return retval
        end)
    R.enter(R.hook_of("app.HitController", "damageProc"))
    eq(R.fire(R.hook_of("app.HitController", "updateDamage"), nil, 7), 7, "inner retval")
    eq(thread.get_hook_storage(), nil, "no current storage after the nested call ended")
    eq(R.leave(true), true, "outer retval")
    eq(seen.inner_post, "inner", "inner storage")
    eq(seen.outer_post, "outer", "outer storage")
end)

test("slots and declaring types", function()
    R.new()
    local o = R.object("app.HitController.DamageInfo")
    eq(sdk.to_int64(R.obj_slot(o)), o:get_address(), "a reference slot read as an integer is the address")
    eq(sdk.to_managed_object(R.null_slot()), nil, "a null reference")
    eq(#R.bad, 0, "a null reference is not a misuse")
    R.method("app.CharacterDamageCalculator", "calcDamageValueDefence(app.HitController.DamageInfo)", function() end)
    R.type("app.PlayerDamageCalculator", "app.CharacterDamageCalculator")
    local m = sdk.find_type_definition("app.PlayerDamageCalculator")
        :get_method("calcDamageValueDefence(app.HitController.DamageInfo)")
    eq(m:get_declaring_type():get_full_name(), "app.CharacterDamageCalculator", "found on the parent")
end)

test("frames, keys and the data folder", function()
    R.new({ io = true })
    local frames = 0
    re.on_frame(function() frames = frames + 1 end)
    R.advance(3)
    eq(frames, 3, "frames")
    eq(reframework:is_drawing_ui(), false, "menu closed")
    R.state.drawing_ui = true
    R.state.keys_down[0x75] = true
    eq(reframework:is_drawing_ui(), true, "menu open")
    eq(reframework:is_key_down(0x75), true, "key down")
    eq(reframework:is_key_down(0x76), false, "key up")
    json.dump_file("DD2DamageMeter/settings.json", { a = 1 })
    eq(json.load_file("DD2DamageMeter/settings.json").a, 1, "json round trip")
    local f = io.open("DD2DamageMeter/debug.log", "w")
    f:write("line\n")
    eq(R.files["DD2DamageMeter/debug.log"], "line\n", "io.open writes into the fake folder")
    f = io.open("DD2DamageMeter/debug.log", "a")
    eq(f:seek("end"), 5, "seek(\"end\") gives the size")
    f:write("more\n")
    eq(R.files["DD2DamageMeter/debug.log"], "line\nmore\n", "\"a\" appends")
    eq(pcall(fs.write, "../escape.txt", "x"), false, "paths outside the data folder are refused")
end)

T.finish()
