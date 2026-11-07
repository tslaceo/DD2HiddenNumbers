-- A boss's status buildup and poise, for the buildup bars under the boss bar (ui/buildup_bars.lua): how far it is from
-- a stagger and a knock-down, and for each status that can work on it, how far its buildup is from setting the status
-- off, with about how many more hits that takes, or, once set off, how long it still lasts.
-- Read-only, every game access under Safe, no hooks (the readings below as measured in game: the buildup, the
-- poise and the durations).
--
--   Buildup.read(character, t, hc) -> { row } | nil
--     First the poise rows, from hc (the boss's app.HitController, gauges.boss's hc; none without it), each while its
--     points are above 0: { id = "lean", value, max, hits } (a stagger: getDmgReactionLeanPoint, the threshold
--     getNextThreshold(false)), then { id = "blown", value, max } (a knock-down: getDmgReactionBlownPoint,
--     getNextThreshold(true); no hits left), both at index -1 (the whole body; every index gave the same in
--     game), at 0 when -1 gives no number. Every hit adds its DamageReaction to both; they drain about 60 a second and
--     go back to 0 after a reaction. A threshold that is not above 0 is none.
--     Then the status rows, by id, one per status that is in effect with time left (an active row) or else whose
--     buildup is above 0 (a building row). None for a status whose enum name starts with "Enchant" (EnchantFire,
--     EnchantIce, EnchantThunder...: an enemy's own elemental aura, in effect a whole fight); one with no name
--     is shown. None either for a status the boss is immune to: its bit 1 << id is clear in the controller's
--     EnableStatusConditionFlag (read once a read, by Safe.enum, as game/enemies.lua does for the plate); an unreadable
--     flag hides nothing, and an id outside 0..62 has no bit and is shown. Neither kind keeps rises. A building row is
--     { id, name, value, max, hits, resistance, immunity }, its active, remain, duration and at nil:
--       id: its app.StatusConditionDef.StatusConditionEnum value (get_StatusConditionId); name: that value's member
--         name (names_game.enum_name: "Faint", "FireSpread"...), nil when the enum has none;
--       value: getEnduranceValue(), the buildup now (0 at rest; it decays about 6 a second);
--       max: the threshold, EnduranceMax of the first action param that has one above 0 (get_ParamRes()'s
--         _ActionParamList), nil without one;
--       hits: about how many more hits set it off, ceil((max - value) / the average of the last INCREMENTS rises),
--         nil before its first rise, without a threshold and once value reaches it;
--       resistance, immunity: get_ResistanceRate() and get_ImmunityLevel(), what earlier triggers raised (0.2, 0.5,
--         0.8 at levels 1, 2, 3); nil when unreadable.
--     An active row is { id, name, active = true, remain, duration, at, resistance, immunity }, no value, max or hits
--     (what getEnduranceValue gives while a status is in effect is not known, so the row does not stand on it):
--       remain: the seconds left at the read, get_ActiveRemainTime() (frames, 60 a second; -1 while not in effect)
--         / 60, given while get_IsActive() is true and it is above 0 (a status in effect with no time, at -1, has no
--         active row);
--       duration: the status's seconds in all, ActiveTimerMaxFrame of the first action param that has one above 0
--         (found in the same pass as EnduranceMax) / 60, nil without one;
--       at: the t of the read.
--     The statuses are the boss's get_StatusConditionCtrl() field StatusConditionInfoList (those that can work on
--     it). A rise is a read whose value is above the read before (of that character and that status or poise); a
--     falling value (the decay, the drain) adds none. A status's rises are forgotten, that read's too, when its
--     immunity differs from the one last read for it (a trigger raised the resistance; the hits left start
--     anew). The game is read at most every READ_EVERY s (t: seconds) for one character, the last answer given in
--     between; another character, or a clock that went back, is read at once; without a time, the character's last
--     answer and nothing read. nil when neither the poise nor any entry of the status list can be read (no character,
--     no controller, no list...); never raises. The rises of MAX_KEPT characters are kept, then all are forgotten.
--   Buildup.reset()   forgets the last answer and every rise (a new world)
--   Buildup.READ_EVERY (0.1 s), Buildup.INCREMENTS (5)
local Safe = require("DD2DamageMeter/game/safe")
local names_game = require("DD2DamageMeter/game/names_game")

local Buildup = {}

local READ_EVERY = 0.1   -- s between two reads of one character
local INCREMENTS = 5     -- the last rises the hits left are taken from
local MAX_STATUSES = 32  -- entries of the list looked at (the game has 14 statuses)
local MAX_PARAMS = 8     -- action params looked through for EnduranceMax and ActiveTimerMaxFrame
local MAX_KEPT = 16      -- characters whose rises are kept
local ENUM = "app.StatusConditionDef.StatusConditionEnum"
local ENCHANT = "Enchant" -- the start of an enchant's enum name: an enemy's own, no row
local MAX_BIT = 62        -- the highest status id with a bit tested in EnableStatusConditionFlag
-- The poise: each row's id, the getter of its points, getNextThreshold's first argument and whether the row has the
-- hits left (not the knock-down's).
local THRESHOLD = "getNextThreshold(System.Boolean, System.Int32)"
local POISE = {
    { id = "lean", points = "getDmgReactionLeanPoint(System.Int32)", blown = false, hits = true },
    { id = "blown", points = "getDmgReactionBlownPoint(System.Int32)", blown = true, hits = false },
}
local INDEXES = { -1, 0 } -- the whole body; 0 when -1 gives nothing
Buildup.READ_EVERY, Buildup.INCREMENTS = READ_EVERY, INCREMENTS

local last           -- { key, t, rows }: the last read, of the character `key`
local kept, n_kept   -- key -> { [id] = { value, rises, immunity } }: each character's statuses as last read

function Buildup.reset()
    last, kept, n_kept = nil, {}, 0
end
Buildup.reset()

local function finite(x)
    if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge then return nil end
    return x
end

local function above_0(x)
    x = finite(x)
    return x and x > 0 and x or nil
end

-- In one pass over the action params: EnduranceMax and ActiveTimerMaxFrame, each the first above 0, nil without one.
local function params(info)
    local list = Safe.field(Safe.call(info, "get_ParamRes"), "_ActionParamList")
    local max, frames
    for _, p in ipairs(Safe.list(list, MAX_PARAMS)) do
        if p then
            max = max or above_0(Safe.field(p, "EnduranceMax"))
            frames = frames or above_0(Safe.field(p, "ActiveTimerMaxFrame"))
            if max and frames then break end
        end
    end
    return max, frames
end

-- The frames left of a status in effect (get_ActiveRemainTime, 60 a second), nil when it is not or none are left.
local function frames_left(info)
    if Safe.call(info, "get_IsActive") ~= true then return nil end
    return above_0(Safe.call(info, "get_ActiveRemainTime"))
end

-- A poise's points and threshold at the first index that gives a number; nil without one.
local function poise_of(hc, p)
    for _, i in ipairs(INDEXES) do
        local value = finite(Safe.call(hc, p.points, i))
        if value then
            local max = finite(Safe.call(hc, THRESHOLD, p.blown, i))
            return value, max and max > 0 and max or nil
        end
    end
    return nil
end

local function hits_left(max, value, rises)
    if max == nil or value >= max or #rises == 0 then return nil end
    local sum = 0
    for _, r in ipairs(rises) do sum = sum + r end
    return math.max(1, math.ceil((max - value) / (sum / #rises)))
end

-- The statuses of `key`'s character as last read, made when it has none (the kept ones forgotten past MAX_KEPT).
local function statuses_of(key)
    local s = kept[key]
    if s then return s end
    if n_kept >= MAX_KEPT then kept, n_kept = {}, 0 end
    s = {}
    kept[key], n_kept = s, n_kept + 1
    return s
end

-- `value` of the status or poise `id` as read now, its rise noted: its last INCREMENTS rises. An `immunity` other than
-- the one last read for it forgets them all, this read's too; nil (unread) changes nothing.
local function rises_of(statuses, id, value, immunity)
    local s = statuses[id]
    if s == nil then
        s = { rises = {} }
        statuses[id] = s
    end
    if s.value and value > s.value then
        s.rises[#s.rises + 1] = value - s.value
        if #s.rises > INCREMENTS then table.remove(s.rises, 1) end
    end
    s.value = value
    if immunity ~= nil then
        if s.immunity ~= nil and immunity ~= s.immunity then s.rises = {} end
        s.immunity = immunity
    end
    return s.rises
end

-- Whether the boss's EnableStatusConditionFlag `enabled` (an integer, nil unread) turns the status `id` off: its bit
-- 1 << id is clear. An id outside 0..MAX_BIT has no bit: never off.
local function off(enabled, id)
    return enabled ~= nil and id >= 0 and id <= MAX_BIT and (enabled >> id) & 1 == 0
end

-- A status's row, nil when it is neither building nor in effect with time left, an enemy's own enchant or a status
-- the boss is immune to; its value's rise noted (none for those two). Second: whether the entry could be read (its id,
-- and its value or its time left; an enchant's or an immune status's id alone).
local function status_row(info, statuses, t, enabled)
    local id = Safe.enum(Safe.call(info, "get_StatusConditionId"))
    if id == nil then return nil, false end
    local name = names_game.enum_name(ENUM, id)
    if name and name:sub(1, #ENCHANT) == ENCHANT or off(enabled, id) then return nil, true end
    local value = finite(Safe.call(info, "getEnduranceValue"))
    local left = frames_left(info)
    if value == nil and left == nil then return nil, false end
    local row
    if left or value > 0 then
        row = { id = id, name = name,
            resistance = finite(Safe.call(info, "get_ResistanceRate")),
            immunity = finite(Safe.call(info, "get_ImmunityLevel")) }
    end
    local rises = value and rises_of(statuses, id, value, row and row.immunity)
    if row == nil then return nil, true end
    local max, frames = params(info)
    if left then
        row.active, row.remain, row.duration, row.at = true, left / 60, frames and frames / 60, t
    else
        row.value, row.max, row.hits = value, max, hits_left(max, value, rises)
    end
    return row, true
end

local function read(character, key, hc, t)
    local statuses, rows, any = statuses_of(key), {}, false
    for _, p in ipairs(hc and POISE or {}) do
        local value, max = poise_of(hc, p)
        if value then
            any = true
            local rises = rises_of(statuses, p.id, value)
            if value > 0 then
                rows[#rows + 1] = { id = p.id, value = value, max = max,
                    hits = p.hits and hits_left(max, value, rises) or nil }
            end
        end
    end
    local ctrl = Safe.call(character, "get_StatusConditionCtrl")
    local list = Safe.field(ctrl, "StatusConditionInfoList")
    local enabled = Safe.enum(Safe.field(ctrl, "EnableStatusConditionFlag"))
    local found = {}
    for _, info in ipairs(list and Safe.list(list, MAX_STATUSES) or {}) do
        if info then
            local row, readable = status_row(info, statuses, t, enabled)
            any = any or readable
            if row then found[#found + 1] = row end
        end
    end
    if not any then return nil end
    table.sort(found, function(a, b) return a.id < b.id end)
    for _, r in ipairs(found) do rows[#rows + 1] = r end
    return rows
end

function Buildup.read(character, t, hc)
    if character == nil then return nil end
    local key = Safe.address(character) or character
    local same = last ~= nil and last.key == key
    if finite(t) == nil then return same and last.rows or nil end
    if same and t >= last.t and t - last.t < READ_EVERY then return last.rows end
    local rows = Safe.try(read, character, key, hc, t)
    last = { key = key, t = t, rows = rows }
    return rows
end

return Buildup
