-- Plays a level by script, headless: the same World:update the game runs, fed
-- the same inputs a player's keys would make. A script is a list of steps run
-- one after another; each step drives one or both robots for as many frames as
-- it takes to be done. tests/levels_test.lua is the solutions written this way.

local D = require "src.defs"
local World = require "src.world"

local Drive = {}

local DT = 1 / 120
local T = D.TILE

local function centre(p) return p.x + p.w / 2 end

-- Walk robot `pi` until its middle is over tile column `col` (fractions fine:
-- 5.5 is the line between columns 5 and 6). Arrives at a stop.
function Drive.walk(pi, col)
    local target = col * T + T / 2
    return function(w, inputs)
        local p = w.players[pi]
        local d = target - centre(p)
        if math.abs(d) < 1 and math.abs(p.vx) < 1 then return true end
        local move = 0
        if math.abs(d) >= 1 then
            -- Ease off near the mark so the robot does not overshoot it.
            move = d > 0 and 1 or -1
            if math.abs(d) < 3 and math.abs(p.vx) > 20 then move = 0 end
        end
        inputs[pi] = { move = move }
        return false
    end
end

-- Hold some inputs on a robot until fn(world, robot) says stop. `jump` is only
-- "pressed" on the first frame; jumpHeld lasts as long as the step.
function Drive.hold(pi, input, untilFn, timeout)
    local first = true
    local t = 0
    return function(w, inputs)
        local p = w.players[pi]
        if untilFn(w, p) then return true end
        t = t + DT
        assert(t < (timeout or 6), "hold timed out")
        local i = {}
        for k, v in pairs(input) do i[k] = v end
        i.jump = first and input.jump or false
        i.jumpHeld = input.jump or false
        inputs[pi] = i
        first = false
        return false
    end
end

function Drive.fire(pi, slot, ax, ay, expect)
    local done = false
    return function(w, inputs)
        if done then return true end
        local p = w.players[pi]
        if p.cooldown > 0 then return false end
        local opened = 0
        local before = w.portals[pi][slot]
        inputs[pi] = { aimx = ax, aimy = ay, ["fire" .. slot] = true }
        w.onAfter = function()
            local now = w.portals[pi][slot]
            opened = now ~= before and now
            if expect ~= false then
                assert(opened, ("robot %d portal %d did not open"):format(pi, slot))
            end
        end
        done = true
        return false
    end
end

function Drive.grab(pi)
    local done = false
    return function(_, inputs)
        if done then return true end
        inputs[pi] = { grab = true }
        done = true
        return false
    end
end

function Drive.wait(secs)
    local t = 0
    return function()
        t = t + DT
        return t >= secs
    end
end

function Drive.waitUntil(fn, timeout)
    local t = 0
    return function(w)
        t = t + DT
        assert(t < (timeout or 6), "waitUntil timed out")
        return fn(w)
    end
end

-- Steps run side by side, until all of them are done.
function Drive.par(...)
    local steps = { ... }
    local done = {}
    return function(w, inputs)
        local all = true
        for i, s in ipairs(steps) do
            if not done[i] then
                done[i] = s(w, inputs)
                if not done[i] then all = false end
            end
        end
        return all
    end
end

-- Run a script on a level. Returns the world at the end and the frames it
-- took; `opts.stopAt` stops it early at that frame (for screenshots). `trace(w)` if given
-- is called every frame (for printing while writing a solution).
function Drive.run(level, script, opts)
    opts = opts or {}
    local w = World.new(level)
    local i = 1
    local frames = 0
    while i <= #script do
        local inputs = {}
        local ok, done = pcall(script[i], w, inputs)
        if not ok then error(("step %d: %s"):format(i, done), 0) end
        w:update(DT, inputs)
        if w.onAfter then w.onAfter(); w.onAfter = nil end
        if opts.trace then opts.trace(w, i) end
        w:drainEvents()
        if done then i = i + 1 end
        frames = frames + 1
        if opts.stopAt and frames >= opts.stopAt then return w, frames end
        assert(frames < 120 * 120, "script ran over two minutes")
    end
    return w, frames
end

Drive.DT = DT
return Drive
