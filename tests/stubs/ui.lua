-- Fake REFramework UI for tests: the `imgui` table, `reframework:is_drawing_ui()` /
-- `is_key_down(vk)` and the window and background draw lists. Every call is recorded in `ui.calls`; the layout is
-- simulated just enough (a cursor that moves down after each item) to check where things land.
--
--   local ui = require("stubs/ui").install()   -- sets the globals and resets the state
--   ui.drawing_ui = true                        -- the REFramework menu is open
--   ui.press("damage:ch000000_00")              -- the next button with that id (or label) reports a click
--   ui.inputs["Opacity"] = 0.5                  -- the next widget with that label reports a change
--
-- Only calls that the mod uses and that exist in REFramework's imgui binding
-- are faked; calling anything else fails like it would in the game (nil).
local ui = {}

local PAD = 8       -- window padding
local SPACING = 4   -- ImGui item spacing (y)
local FONT_BASE = 14

-- Records one call: { fn = name, n = argument count, ... }.
local function rec(fn, ...)
    local r = table.pack(...)
    r.fn = fn
    ui.calls[#ui.calls + 1] = r
    return r
end

local function xy(p)
    if type(p) ~= "table" then error("expected a {x, y} position, got " .. tostring(p), 3) end
    return p.x or p[1], p.y or p[2]
end

local function font_px()
    return ui.fonts[#ui.fonts] or 16
end

-- Takes `h` of vertical space at the cursor and moves the cursor to the next line.
local function item(w, h)
    local it = { x = ui.cursor.x, y = ui.cursor.y, w = w, h = h }
    ui.items[#ui.items + 1] = it
    ui.last_item = it
    ui.cursor = { x = ui.line_x, y = it.y + h + SPACING }
    return it
end

-- A press queued by ui.press: matches the whole id/label or the part after "##".
local function take_press(id)
    for i, want in ipairs(ui.pressed) do
        if want == id or id:match("##(.*)$") == want then
            table.remove(ui.pressed, i)
            return true
        end
    end
    return false
end

-- A value queued by ui.inputs for the widget `label` (the whole label or the visible part
-- before "##"): reports a change once.
local function take_input(label, current)
    local name = ui.inputs[label] ~= nil and label or label:match("^(.-)##")
    local v = name and ui.inputs[name]
    if v == nil then return false, current end
    ui.inputs[name] = nil
    return true, v
end

local imgui = {}

function imgui.begin_window(name, open, flags)
    if open == false then return false end -- the binding skips Begin then
    ui.window_stack = ui.window_stack + 1
    ui.window = { name = name, flags = flags or 0 }
    if ui.next_pos then
        ui.window_pos = { x = ui.next_pos.x, y = ui.next_pos.y }
        ui.next_pos = nil
    end
    if ui.next_size then
        ui.window_size = { x = ui.next_size.x, y = ui.next_size.y }
        ui.next_size = nil
    end
    ui.line_x = ui.window_pos.x + PAD
    ui.cursor = { x = ui.line_x, y = ui.window_pos.y + PAD }
    rec("begin_window", name, open, flags)
    return true
end

function imgui.end_window()
    if ui.window_stack == 0 then error("end_window without begin_window", 2) end
    ui.window_stack = ui.window_stack - 1
    rec("end_window")
end

function imgui.set_next_window_pos(pos, cond, pivot)
    local x, y = xy(pos)
    ui.next_pos = { x = x, y = y }
    local r = rec("set_next_window_pos", pos, cond, pivot)
    r.x, r.y, r.cond = x, y, cond
end

-- The size of the next window: recorded (w, h, cond); the window keeps it as ui.window_size.
function imgui.set_next_window_size(size, cond)
    local w, h = xy(size)
    ui.next_size = { x = w, y = h }
    local r = rec("set_next_window_size", size, cond)
    r.w, r.h, r.cond = w, h, cond
end

-- The screen: ui.display ({ x, y }, 1920 x 1080 by default).
function imgui.get_display_size()
    return { x = ui.display.x, y = ui.display.y }
end

function imgui.get_window_pos()
    return { x = ui.window_pos.x, y = ui.window_pos.y }
end

function imgui.get_cursor_screen_pos()
    return { x = ui.cursor.x, y = ui.cursor.y }
end

function imgui.set_cursor_screen_pos(pos)
    local x, y = xy(pos)
    ui.cursor = { x = x, y = y }
    rec("set_cursor_screen_pos", pos)
end

function imgui.item_size(min, max)
    local x0, y0 = xy(min)
    local x1, y1 = xy(max)
    rec("item_size", min, max)
    item(x1 - x0, y1 - y0)
end

function imgui.invisible_button(id, size, flags)
    local w, h = xy(size)
    local r = rec("invisible_button", id, size, flags)
    r.id, r.w, r.h, r.x, r.y = id, w, h, ui.cursor.x, ui.cursor.y
    item(w, h)
    ui.last_item.id = id
    return take_press(id)
end

function imgui.button(label, size)
    local w, h
    if size then w, h = xy(size) else w, h = imgui.calc_text_size(label).x + 16, font_px() + 6 end
    local r = rec("button", label, size)
    r.label, r.w, r.h, r.x, r.y = label, w, h, ui.cursor.x, ui.cursor.y
    item(w, h)
    ui.last_item.id = label
    return take_press(label)
end

function imgui.is_item_hovered()
    local it = ui.last_item
    return it ~= nil and it.id ~= nil and ui.hovered[it.id] == true
end

function imgui.same_line()
    rec("same_line")
    local it = ui.last_item
    if it then ui.cursor = { x = it.x + it.w + SPACING, y = it.y } end
end

function imgui.text(s)
    local r = rec("text", s)
    r.text = s
    local size = imgui.calc_text_size(s)
    item(size.x, size.y)
end

function imgui.calc_text_size(s)
    local n = utf8.len(s) or #s
    return { x = n * ui.char_w * font_px() / FONT_BASE, y = font_px() }
end

function imgui.push_font_size(px)
    ui.fonts[#ui.fonts + 1] = px
    rec("push_font_size", px)
end

function imgui.pop_font_size()
    if #ui.fonts == 0 then error("pop_font_size without push_font_size", 2) end
    ui.fonts[#ui.fonts] = nil
    rec("pop_font_size")
end

function imgui.get_default_font_size()
    return 16
end

function imgui.push_style_color(idx, col)
    ui.styles[#ui.styles + 1] = { idx = idx, col = col }
    rec("push_style_color", idx, col)
end

function imgui.pop_style_color(n)
    n = n or 1
    if #ui.styles < n then error("pop_style_color without push_style_color", 2) end
    for _ = 1, n do ui.styles[#ui.styles] = nil end
    rec("pop_style_color", n)
end

function imgui.is_mouse_down(button)
    return button == 0 and ui.mouse_down
end

function imgui.get_mouse()
    return { x = ui.mouse.x, y = ui.mouse.y }
end

-- Widgets of the settings menu. Each returns what the binding returns: (changed, value).
function imgui.collapsing_header(name)
    rec("collapsing_header", name)
    return ui.header_open
end

function imgui.checkbox(label, v)
    rec("checkbox", label, v)
    return take_input(label, v)
end

function imgui.slider_int(label, v, min, max, fmt)
    rec("slider_int", label, v, min, max, fmt)
    return take_input(label, v)
end

function imgui.slider_float(label, v, min, max, fmt)
    rec("slider_float", label, v, min, max, fmt)
    return take_input(label, v)
end

function imgui.drag_int(label, v, speed, min, max, fmt)
    rec("drag_int", label, v, speed, min, max, fmt)
    return take_input(label, v)
end

function imgui.combo(label, selection, values)
    rec("combo", label, selection, values)
    return take_input(label, selection)
end

-- Draw lists: the window's own and the background one (behind every window). Each call records
-- its `layer` ("window" or "background").
local dl = {}
dl.__index = dl

function dl:add_rect_filled(min, max, col, rounding, flags)
    local x0, y0 = xy(min)
    local x1, y1 = xy(max)
    local r = rec("add_rect_filled", min, max, col, rounding, flags)
    r.x0, r.y0, r.x1, r.y1, r.col, r.rounding, r.layer = x0, y0, x1, y1, col, rounding, self.layer
end

-- An outline `thickness` px wide, its corners rounded.
function dl:add_rect(min, max, col, rounding, flags, thickness)
    local x0, y0 = xy(min)
    local x1, y1 = xy(max)
    local r = rec("add_rect", min, max, col, rounding, flags, thickness)
    r.x0, r.y0, r.x1, r.y1, r.col, r.rounding, r.thickness, r.layer = x0, y0, x1, y1, col, rounding, thickness,
        self.layer
end

-- `px`: the font size pushed when the text was drawn (the draw list uses that font).
function dl:add_text(pos, col, text)
    local x, y = xy(pos)
    local r = rec("add_text", pos, col, text)
    r.x, r.y, r.col, r.text, r.layer, r.px = x, y, col, text, self.layer, font_px()
end

-- A rectangle whose corners have their own colours (upper left, upper right, bottom right, bottom left).
function dl:add_rect_filled_multi_color(min, max, ul, ur, br, bl)
    local x0, y0 = xy(min)
    local x1, y1 = xy(max)
    local r = rec("add_rect_filled_multi_color", min, max, ul, ur, br, bl)
    r.x0, r.y0, r.x1, r.y1, r.ul, r.ur, r.br, r.bl, r.layer = x0, y0, x1, y1, ul, ur, br, bl, self.layer
end

-- A filled quadrilateral (p1..p4 clockwise) and its outline.
local function quad(fn, self, p1, p2, p3, p4, col, thickness)
    local r = rec(fn, p1, p2, p3, p4, col, thickness)
    r.points = {}
    for i, p in ipairs({ p1, p2, p3, p4 }) do
        local x, y = xy(p)
        r.points[i] = { x = x, y = y }
    end
    r.col, r.thickness, r.layer = col, thickness, self.layer
end

function dl:add_quad_filled(p1, p2, p3, p4, col)
    quad("add_quad_filled", self, p1, p2, p3, p4, col)
end

function dl:add_quad(p1, p2, p3, p4, col, thickness)
    quad("add_quad", self, p1, p2, p3, p4, col, thickness)
end

-- The draw lists' methods: a test can take one away to see the mod do without it.
ui.draw_list = dl

function imgui.get_window_draw_list()
    return setmetatable({ layer = "window" }, dl)
end

function imgui.get_background_draw_list()
    return setmetatable({ layer = "background" }, dl)
end

ui.imgui = imgui

local reframework_methods = {}

function reframework_methods:is_drawing_ui()
    return ui.drawing_ui
end

function reframework_methods:is_key_down(vk)
    return ui.keys_down[vk] == true
end

-- Queues a click for the button whose id (or label) matches; consumed by the first match.
function ui.press(id)
    ui.pressed[#ui.pressed + 1] = id
end

-- Forgets every recorded call and resets all simulated state.
function ui.reset()
    ui.calls = {}
    ui.items = {}
    ui.drawing_ui = false      -- reframework:is_drawing_ui()
    ui.mouse_down = false      -- left mouse button
    ui.mouse = { x = 0, y = 0 }
    ui.keys_down = {}          -- vk -> true
    ui.window_pos = { x = 0, y = 0 }
    ui.window_size = nil       -- set by set_next_window_size
    ui.display = { x = 1920, y = 1080 } -- imgui.get_display_size()
    ui.header_open = true      -- collapsing_header result
    ui.hovered = {}            -- button id -> true
    ui.pressed = {}
    ui.inputs = {}
    ui.char_w = 7              -- text width per character at 14 px
    ui.fonts = {}
    ui.styles = {}
    ui.window_stack = 0
    ui.cursor = { x = 0, y = 0 }
    ui.line_x = 0
    ui.last_item = nil
    ui.next_pos = nil
    ui.next_size = nil
end

-- Forgets the calls recorded so far but keeps the simulated state (window position, mouse...).
function ui.clear_calls()
    ui.calls = {}
    ui.items = {}
end

function ui.calls_of(fn)
    local list = {}
    for _, c in ipairs(ui.calls) do
        if c.fn == fn then list[#list + 1] = c end
    end
    return list
end

-- Every string that was drawn, in order (text and draw-list text).
function ui.texts()
    local list = {}
    for _, c in ipairs(ui.calls) do
        if c.fn == "text" then
            list[#list + 1] = c.text
        elseif c.fn == "add_text" then
            list[#list + 1] = c.text
        end
    end
    return list
end

function ui.has_text(s)
    for _, t in ipairs(ui.texts()) do
        if t == s then return true end
    end
    return false
end

-- The first recorded call to `fn` whose first argument is `first`, or nil.
function ui.find(fn, first)
    for _, c in ipairs(ui.calls) do
        if c.fn == fn and (first == nil or c[1] == first) then return c end
    end
    return nil
end

-- True when every begin/push has its matching end/pop.
function ui.balanced()
    return ui.window_stack == 0 and #ui.fonts == 0 and #ui.styles == 0
end

-- Sets the globals the mod reads (`imgui`, `reframework`); an existing `reframework` table
-- (the sdk/re stub) is extended, not replaced.
function ui.install()
    _G.imgui = imgui
    local fw = rawget(_G, "reframework")
    if type(fw) ~= "table" then
        fw = {}
        _G.reframework = fw
    end
    for k, f in pairs(reframework_methods) do fw[k] = f end
    ui.reset()
    return ui
end

return ui
