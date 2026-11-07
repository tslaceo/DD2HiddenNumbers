-- User settings: defaults, validation, saving through a store ({ read, write }, see Settings.load).
-- Pure Lua: the store is the only link to the file, so tests use an in-memory one.
local Settings = {}
Settings.__index = Settings

-- The full key list; a key not here does not exist. The type of a value is the type of its default.
Settings.DEFAULTS = {
    language = "auto",      -- "auto" follows the game's language
    toggle_key = 0x75,      -- virtual-key code, F6
    summary_autohide = 0,   -- seconds, 0 = never
    history_size = 10,      -- finished fights kept
    window_x = 40,
    window_y = 300,
    opacity = 0.78,
    scale = 1.0,
    show_allies = true,     -- the fight window's allies
    debug = false,
    -- the blocks of the fight window and of the summary; a block that is off is not built or drawn
    live_damage = true,
    live_taken = true,
    live_heal = true,
    live_other = true,
    summary_enemies = true,
    summary_damage = true,
    summary_armor = true,
    summary_heal = true,
    summary_allies = true,
    summary_other = true,
    -- the fight journal
    journal = true,
    journal_key = 0x76,     -- virtual-key code, F7
    settings_key = 0x77,    -- virtual-key code, F8: the mod's settings window; no two of the three keys are one key
    history_file = false,   -- keep the finished fights in history.json
    -- the look of the window
    style = "frameless",    -- "frameless": text and thin bars straight over the scene; "panel": on a dark panel
    halo = false,           -- frameless: a soft dark halo behind the text (as dark as `opacity`)
    bar_px = 3,             -- frameless: bar thickness, pixels at scale 1
    outline = true,         -- a thin dark outline around the numbers
    shadow = 0.8,           -- strength of the text shadow, 0 = none
    -- the numbers over the game's HP bar above an enemy's head: "off", "current", "current_max", "percent",
    -- "current_percent", "all" (current / full · percent)
    enemy_hp_numbers = "all",
    boss_hp_numbers = "all", -- the same, right of the game's boss bar at the top of the screen
    enemy_hp_size = 1.0,    -- the size of both: a factor of their 15 px (over heads), 18 px (the boss's) × scale
    -- the status buildup bars under the game's boss bar (how far the boss is from each status), sized by enemy_hp_size
    buildup_bars = true,
    -- the player's own HP and stamina numbers by the game's HUD bars (now / max (full max)), sized by enemy_hp_size
    player_numbers = true,
    -- the damage of each hit on an enemy at the point it landed: shown or not, "rise" (numbers that rise and fade)
    -- or "plates" (plates that stand), their size (a factor of their sizes × scale)
    damage_numbers = true,
    damage_numbers_style = "rise",
    damage_numbers_size = 1.0,
    -- the enemy plate in a fight (what the enemies near you are weak to and resist): shown or not, its size (a factor
    -- of its 14 px × scale)
    enemy_plate = true,
    enemy_plate_size = 1.0,
    -- the hidden-stats panel on the guild's augments, item and equipment screens (what the hovered augment or ring
    -- gives, in numbers): shown or not, its size (a factor of its 14 px × scale)
    hidden_stats = true,
    hidden_stats_size = 1.0,
}

-- What the HP numbers show, over heads and at the boss bar alike.
local HP_FORMATS = { values = { off = true, current = true, current_max = true, percent = true, current_percent = true,
    all = true } }

-- Limits per key: numbers are clamped to [min, max], `integer` ones are rounded too;
-- a `code` is an identifier, not a quantity: anything outside [min, max] or not a whole number
-- is refused, never clamped (0 must not turn into 1, the left mouse button);
-- a string setting lists its `values`. Booleans need no rule.
local RULES = {
    language = { values = { auto = true, en = true, ru = true } },
    toggle_key = { min = 1, max = 254, code = true },
    journal_key = { min = 1, max = 254, code = true },
    settings_key = { min = 1, max = 254, code = true },
    summary_autohide = { min = 0, max = 600, integer = true },
    history_size = { min = 1, max = 32, integer = true },
    window_x = { min = 0, max = 16384, integer = true },
    window_y = { min = 0, max = 16384, integer = true },
    opacity = { min = 0.2, max = 1 },
    scale = { min = 0.6, max = 2 },
    style = { values = { frameless = true, panel = true } },
    bar_px = { min = 1, max = 8, integer = true },
    shadow = { min = 0, max = 1 },
    enemy_hp_numbers = HP_FORMATS,
    boss_hp_numbers = HP_FORMATS,
    enemy_hp_size = { min = 0.5, max = 3 },
    damage_numbers_style = { values = { rise = true, plates = true } },
    damage_numbers_size = { min = 0.5, max = 3 },
    enemy_plate_size = { min = 0.5, max = 3 },
    hidden_stats_size = { min = 0.5, max = 3 },
}

-- A read-only view of `t`: reads pass through, writes fail, pairs() still walks it.
local function frozen(t)
    return setmetatable({}, {
        __index = t,
        __newindex = function() error("read-only table", 2) end,
        __pairs = function() return next, t, nil end,
        __metatable = false,
    })
end

-- The numeric ranges ({ min, max, integer?, code? } per key) for the settings window's steps,
-- so they are not written down twice. A read-only copy: the checks below keep their own.
Settings.LIMITS = (function()
    local limits = {}
    for key, rule in pairs(RULES) do
        if rule.min then
            local copy = {}
            for field, value in pairs(rule) do copy[field] = value end
            limits[key] = frozen(copy)
        end
    end
    return frozen(limits)
end)()

-- The value to keep for `key`, or nil when it cannot be used (unknown key, wrong type, nan,
-- a string outside the list, a code outside its range or not a whole number).
local function normalize(key, value)
    local default = Settings.DEFAULTS[key]
    if default == nil or type(value) ~= type(default) then return nil end
    local rule = RULES[key]
    if type(value) == "number" then
        if value ~= value then return nil end
        if rule.code then
            value = math.tointeger(value)
            if value == nil or value < rule.min or value > rule.max then return nil end
            return value
        end
        value = math.max(rule.min, math.min(rule.max, value))
        if rule.integer then value = math.tointeger(math.floor(value + 0.5)) end
    elseif type(value) == "string" and not rule.values[value] then
        return nil
    end
    return value
end

local function copy(t)
    local c = {}
    for k, v in pairs(t) do c[k] = v end
    return c
end

-- The keys that must never be one key: each refuses the code another one has. In this order they are mended at load.
local KEYS = { "toggle_key", "journal_key", "settings_key" }
local IS_KEY = { toggle_key = true, journal_key = true, settings_key = true }
local SPARE_FIRST, SPARE_LAST = 0x76, 0x7B -- F7..F12, tried in turn when a key clashes with one before it

-- `store.read()` returns the saved table or nil; `store.write(table)` saves the whole table.
-- A store that fails never breaks the mod: an unreadable file counts as missing, a failed
-- write leaves the new value live (and the settings dirty, to be written by a later flush).
-- Two things are mended while loading, without writing: a file from before the summary had its own
-- allies switch gives it the saved show_allies, and a journal key equal to the toggle key, or a settings key
-- equal to either of them, moves to the first of F7..F12 that no other key has.
function Settings.load(store)
    local ok, saved = pcall(store.read)
    if not ok or type(saved) ~= "table" then saved = {} end
    local values = {}
    for key, default in pairs(Settings.DEFAULTS) do
        local value = normalize(key, saved[key])
        if value == nil then value = default end
        values[key] = value
    end
    if normalize("summary_allies", saved.summary_allies) == nil then
        local shown = normalize("show_allies", saved.show_allies)
        if shown ~= nil then values.summary_allies = shown end
    end
    local taken = {}
    for _, key in ipairs(KEYS) do
        if taken[values[key]] then
            for vk = SPARE_FIRST, SPARE_LAST do
                if not taken[vk] then
                    values[key] = vk
                    break
                end
            end
        end
        taken[values[key]] = true
    end
    return setmetatable({ values = values, store = store, dirty = false }, Settings)
end

-- true when the value was accepted (quantities are clamped, not refused), false when it was not
-- (nothing changes then): a wrong value, or a key (toggle, journal, settings) equal to another one.
-- Does not write: a changed value only marks the settings dirty, so a
-- slider dragged through many values costs one write, made by flush.
function Settings:set(key, value)
    local kept = normalize(key, value)
    if kept == nil then return false end
    if IS_KEY[key] then
        for _, other in ipairs(KEYS) do
            if other ~= key and kept == self.values[other] then return false end
        end
    end
    if self.values[key] ~= kept then
        self.values[key] = kept
        self.dirty = true
    end
    return true
end

-- Writes the whole table through the store once if anything changed since the last write.
-- true when it wrote; false when there was nothing to write or the store failed (the settings
-- stay dirty then, so the next flush tries again).
function Settings:flush()
    if not self.dirty then return false end
    if not pcall(self.store.write, copy(self.values)) then return false end
    self.dirty = false
    return true
end

return Settings
