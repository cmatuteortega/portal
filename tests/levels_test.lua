-- Every level, played through to the exit by script under the real rules. If a
-- change to the physics or the maps makes a level unsolvable the way it was
-- meant to be solved, this is where it shows.

local Drive = require "tests.drive"
local Levels = require "src.levels"

local walk, hold, fire, grab, wait, waitUntil, par =
    Drive.walk, Drive.hold, Drive.fire, Drive.grab, Drive.wait, Drive.waitUntil, Drive.par

local function teleported(after)
    return function(_, p) return p.x > after end
end

local function won(w) return w.won end

-- Each solution is made fresh per run: the steps keep state as they go.
local solutions = {
    ["PORTALS 101"] = function() return {
        fire(1, 1, -1, 0),
        fire(1, 2, 1, 0),
        hold(1, { move = -1 }, teleported(200)),
        walk(1, 36),
        hold(2, { move = -1 }, teleported(200)),
        walk(2, 35),
        waitUntil(won),
    } end,

    ["HOLD THE DOOR"] = function() return {
        walk(1, 8.5),
        walk(2, 30.5),
        walk(1, 36),
        walk(2, 35),
        waitUntil(won),
    } end,

    ["BOOST"] = function() return {
        par(walk(2, 18), walk(1, 14)),
        -- Up onto the partner's head, then up the step.
        hold(1, { move = 1, jump = true }, function(_, p) return p.vy > 0 and p.x > 140 end),
        hold(1, { move = 1 }, function(w, p) return p.standOn == w.players[2] end),
        wait(0.1),
        hold(1, { move = 1, jump = true }, function(_, p) return p.ground and p.y + p.h <= 120 end),
        walk(1, 28.5),
        -- The door is open: through the chamber, onto the block, out the hole.
        walk(2, 35),
        hold(2, { move = 1, jump = true }, function(_, p) return p.ground and p.y + p.h <= 136 end),
        walk(2, 36.5),
        hold(2, { move = -1, jump = true }, function(_, p) return p.ground and p.y + p.h <= 120 end),
        par(walk(2, 23), walk(1, 22.5)),
        waitUntil(won),
    } end,

    ["CUBE"] = function() return {
        walk(1, 3),
        grab(1),
        fire(1, 1, -1, 0),
        walk(1, 11),
        fire(1, 2, 1, -1),
        hold(1, { move = -1 }, teleported(150)),
        waitUntil(function(w) return w.players[1].ground end),
        walk(1, 28),
        grab(1),
        waitUntil(function(w) return w.open.a end),
        hold(2, { move = -1 }, teleported(150)),
        waitUntil(function(w) return w.players[2].ground end),
        par(walk(1, 36), walk(2, 37)),
        waitUntil(won),
    } end,

    ["FLING"] = function() return {
        -- Robot 1: a wall at the floor into the ceiling over the pit floor.
        walk(1, 5.5),
        fire(1, 2, 0, -1),
        fire(1, 1, -1, 0),
        walk(1, 2.5),
        -- Robot 2: the pit floor out of the high wall.
        walk(2, 5.5),
        fire(2, 1, 0, 1),
        walk(2, 15),
        fire(2, 2, -1, -1),
        -- In, down, across.
        -- (Let go once through: holding left would steer off the pit floor.)
        hold(1, { move = -1 }, function(_, p) return p.y < 60 end),
        waitUntil(function(w) return w.players[1].x > 200 and w.players[1].ground end),
        walk(1, 37),
        -- Robot 2 hops its own floor portal on the way to the wall.
        hold(2, { move = -1 }, function(_, p) return p.x < 66 end),
        hold(2, { move = -1, jump = true }, function(_, p) return p.y < 60 end),
        waitUntil(function(w) return w.players[2].x > 200 and w.players[2].ground end),
        walk(2, 35),
        waitUntil(won),
    } end,

    ["TOGETHER"] = function() return {
        -- A boost to the ledge for the second cube.
        walk(2, 6),
        hold(1, { move = -1, jump = true }, function(_, p) return p.vy > 0 and p.x < 58 end),
        hold(1, { move = -1 }, function(w, p) return p.standOn == w.players[2] end),
        wait(0.1),
        hold(1, { move = -1, jump = true }, function(_, p) return p.ground and p.y + p.h <= 120 end),
        walk(1, 3),
        grab(1),
        hold(1, { move = 1 }, function(_, p) return p.ground and p.y + p.h >= 152 end),
        walk(2, 9.5),
        grab(2),
        walk(1, 7),
        fire(1, 1, -1, 0),
        fire(1, 2, 1, -1),
        hold(1, { move = -1 }, teleported(150)),
        waitUntil(function(w) return w.players[1].ground end),
        walk(1, 24),
        grab(1),
        walk(1, 30),
        hold(2, { move = -1 }, teleported(150)),
        waitUntil(function(w) return w.players[2].ground end),
        walk(2, 27),
        hold(2, { move = 1 }, function(_, p) return p.facing == 1 end),
        grab(2),
        waitUntil(function(w) return w.open.a end),
        par(walk(1, 36), walk(2, 35)),
        waitUntil(won),
    } end,
}

local tests = { solutions = solutions }
for i, level in ipairs(Levels) do
    tests[#tests + 1] = { ("level %d %s is solvable"):format(i, level.name), function()
        local script = assert(solutions[level.name], "no solution written for " .. level.name)
        local w = Drive.run(level, script())
        assert(w.won, "not won")
    end }
end
return tests
