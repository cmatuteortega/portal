-- Dev only (`love . --shots`): plays each level's scripted solution from
-- tests/levels_test.lua part way and writes what the screen shows then to
-- shots/ in the save directory, plus the title. A quick look at every chamber
-- without playing it, and the pictures in the README.

local Game = require "src.game"
local Draw = require "src.draw"

local Shots = {}

function Shots.run(canvas, fractions)
    package.path = "./?.lua;" .. package.path
    local Drive = require "tests.drive"
    local solutions = require("tests.levels_test").solutions
    local Levels = require "src.levels"
    love.filesystem.createDirectory("shots")
    local function snap(name)
        love.graphics.setCanvas(canvas)
        love.graphics.clear(0, 0, 0)
        Game.draw()
        love.graphics.setCanvas()
        canvas:newImageData():encode("png", "shots/" .. name .. ".png")
    end
    Game.state = "title"
    snap("title")
    for i, level in ipairs(Levels) do
        local _, total = Drive.run(level, solutions[level.name]())
        for k, f in ipairs(fractions) do
            Game.start(i)
            Game.banner = 0
            Draw.reset()
            local w = Drive.run(level, solutions[level.name](), {
                stopAt = math.floor(total * f),
                trace = function(world)
                    for _, e in ipairs(world.events) do
                        if e.name == "shot" or e.name == "portal_open" then Game.react(e) end
                    end
                    Draw.update(1 / 120)
                end,
            })
            Game.world = w
            Game.time = total * f / 120
            snap(("%d-%s-%d"):format(i, level.name:lower():gsub("[^%w]+", "-"), k))
        end
    end
    print("shots written to " .. love.filesystem.getSaveDirectory() .. "/shots")
end

return Shots
