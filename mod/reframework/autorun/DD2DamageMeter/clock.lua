-- Fight start and end, fed with timestamps and the game's battle mode (0 Normal, 1 Ready,
-- 2 Battle). Pure state machine: it returns events and never reads the game itself.
--   event = { kind = "start" | "finish" | "resume", t = number,
--             outcome = "win" | "end" | "abandoned" | nil (finish only),
--             gap = seconds, by = "mode" | "hit" (resume only) }
-- The game drops the battle mode for a frame or two inside one fight now and then, so mode 0 after mode 2 does not
-- finish a fight at once: the end waits `end_grace` seconds (default 3). Mode 2, or a party hit on an enemy of the
-- fight, inside that time takes the end back (a "resume" event); a party hit on another enemy ends the fight at the
-- time of the mode 0 and starts a new one (both events at once). Else the fight finishes at the time of the mode 0, so
-- the grace is not in its length.
local Clock = {}
Clock.__index = Clock

function Clock.new(opts)
    return setmetatable({
        idle_timeout = opts and opts.idle_timeout or 10,
        end_grace = opts and opts.end_grace or 3,
        open = false,
        battle = false,    -- mode 2 was seen during the open fight: the mode decides its end
        ending = false,    -- the game reported the battle ending during the open fight
        last_hit = nil,    -- time of the last party hit of the open fight
        pending = nil,     -- { t, outcome } of a mode 0 that may end the open fight
    }, Clock)
end

local function start(self, t)
    self.open, self.battle, self.ending, self.last_hit, self.pending = true, false, false, t, nil
    return { kind = "start", t = t }
end

local function finish(self, t, outcome)
    self.open, self.pending = false, nil
    return { kind = "finish", t = t, outcome = outcome }
end

local function finish_pending(self)
    return finish(self, self.pending.t, self.pending.outcome)
end

-- A pending end whose grace is over finishes the fight, whatever comes first: a late mode 2 or party hit is too late
-- for it (the next one starts another fight).
local function expired(self, t)
    return self.pending ~= nil and t - self.pending.t >= self.end_grace
end

-- The fight goes on. When the battle mode came back, the ending flag of the break is forgotten (the pending end has
-- kept it), so the real end is a win only if the game says "ending" again. A hit resume keeps it: the mode never left
-- Normal, so no new flag can come.
local function resume(self, t, by)
    local gap = t - self.pending.t
    self.pending = nil
    if by == "mode" then self.ending = false end
    return { kind = "resume", t = t, gap = gap, by = by }
end

function Clock:on_mode(t, mode, ending)
    if self.open and expired(self, t) then return finish_pending(self) end
    local event
    if mode == 2 and not self.open then event = start(self, t) end
    if not self.open then return nil end

    if mode == 2 then
        self.battle = true
        if self.pending then event = resume(self, t, "mode") end
    end
    if ending then
        self.ending = true
        if self.pending then self.pending.outcome = "win" end
    end
    -- Mode 0 ends only a fight the mode took part in; a hit-started fight sits in mode 0 all along.
    if mode == 0 and self.battle and not self.pending then
        self.pending = { t = t, outcome = self.ending and "win" or "end" }
    end
    return event
end

-- `joins` (false = the hit is on an enemy the open fight does not know; nil = unknown, taken as known) matters only
-- while an end is pending: a hit on another enemy is another fight, so the pending one finishes and a new one starts
-- at this hit (two events, in this order); a hit after the grace is over does the same.
function Clock:on_party_hit(t, joins)
    if not self.open then return start(self, t) end
    if self.pending and (joins == false or expired(self, t)) then
        local finished = finish_pending(self)
        return finished, start(self, t)
    end
    self.last_hit = t
    if self.pending then return resume(self, t, "hit") end
    return nil
end

-- A fight whose end is pending finishes when the grace is over; one that mode 2 never confirmed ends after
-- idle_timeout seconds without party hits.
function Clock:tick(t)
    if not self.open then return nil end
    if self.pending then
        if expired(self, t) then return finish_pending(self) end
        return nil
    end
    if not self.battle and t - self.last_hit >= self.idle_timeout then
        return finish(self, t, "end")
    end
    return nil
end

-- The world changes under the clock (scene change, save load): an open fight is abandoned, unless its end was already
-- pending: then it ends as that end said.
function Clock:reset(t)
    if not self.open then return nil end
    if self.pending then return finish_pending(self) end
    return finish(self, t, "abandoned")
end

-- True during the grace too: hits still belong to the fight.
function Clock:fighting()
    return self.open
end

return Clock
