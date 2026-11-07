-- The last `max` finished fights, newest first; the newest can be replaced by the same fight continued.
local History = {}
History.__index = History

function History.new(max)
    return setmetatable({ max = max, items = {} }, History)
end

-- Drops the oldest items beyond the limit.
local function trim(self)
    for i = #self.items, self.max + 1, -1 do self.items[i] = nil end
end

function History:push(item)
    table.insert(self.items, 1, item)
    trim(self)
end

-- The newest item becomes `item` (a fight continued): the others and the count stay. With none, it is pushed.
function History:replace_newest(item)
    if #self.items == 0 then return self:push(item) end
    self.items[1] = item
end

function History:count()
    return #self.items
end

-- 1 = newest; nil outside 1..count.
function History:get(i)
    return self.items[i]
end

function History:resize(max)
    self.max = max
    trim(self)
end

return History
