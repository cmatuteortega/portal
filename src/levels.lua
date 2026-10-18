-- The chambers, in order, read from levels.ldtk (src/ldtk.lua says how the
-- LDtk project maps onto the game). The list is filled in place, so `reload`
-- (F5 in game) picks up a save from LDtk without anyone holding a stale copy.

local Ldtk = require "src.ldtk"

local Levels = {}

function Levels.reload()
    local fresh = Ldtk.load("levels.ldtk")
    for i = #Levels, 1, -1 do Levels[i] = nil end
    for i, l in ipairs(fresh) do Levels[i] = l end
    return Levels
end

Levels.reload()
return Levels
