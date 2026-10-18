-- Portal Pals: a co-op 2D portal platformer for two robots on one screen.
--
-- Everything renders into a low-res canvas blown up by a whole number, so a
-- game pixel is always an exact block of screen pixels. The level is 320x176
-- and always shown whole; the zoom is the largest whole number that fits it,
-- and the canvas is grown to cover the window at that zoom, the level centred
-- in it, so nothing is stretched and a wide window shows more of the void.

local Game = require "src.game"
local Font = require "src.font"
local Sprites = require "src.sprites"
local Sfx = require "src.sfx"
local Input = require "src.input"
local D = require "src.defs"

local W, H = D.COLS * D.TILE, D.ROWS * D.TILE

local canvas
local scale, offX, offY = 1, 0, 0

local function fit()
    local w, h = love.graphics.getDimensions()
    scale = math.max(1, math.floor(math.min(w / W, h / H)))
    local cw, ch = math.ceil(w / scale), math.ceil(h / scale)
    if not canvas or canvas:getWidth() ~= cw or canvas:getHeight() ~= ch then
        if canvas then canvas:release() end
        canvas = love.graphics.newCanvas(cw, ch)
        canvas:setFilter("nearest", "nearest")
        Game.resize(cw, ch)
    end
    offX = math.floor((w - cw * scale) / 2)
    offY = math.floor((h - ch * scale) / 2)
end

-- Window pixels to canvas pixels.
local function toCanvas(x, y)
    return (x - offX) / scale, (y - offY) / scale
end

function love.load(args)
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.graphics.setLineStyle("rough")
    Font.load()
    Sprites.load()
    Sfx.load()
    love.window.setIcon(Sprites.icon())
    fit()
    Game.load()
    for _, a in ipairs(args or {}) do
        local n = tonumber(a)
        if n then Game.start(math.max(1, math.min(n, #require("src.levels")))) end
        if a == "--mute" then Sfx.on = false end
        if a == "--shots" then
            local ok, err = xpcall(require("src.shots").run, debug.traceback, canvas, { 0.35, 0.7 })
            if not ok then print(err) end
            os.exit(ok and 0 or 1)
        end
    end
end

function love.resize() fit() end

function love.update(dt)
    Game.update(math.min(dt, 0.1))
end

function love.draw()
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0)
    Game.draw()
    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(canvas, offX, offY, 0, scale, scale)
end

function love.keypressed(key)
    if key == "f11" or (key == "return" and love.keyboard.isDown("lalt", "ralt")) then
        love.window.setFullscreen(not love.window.getFullscreen(), "desktop")
        fit()
        return
    end
    if key == "m" then Sfx.on = not Sfx.on end
    Game.keypressed(key)
end

function love.mousepressed(x, y, button)
    local cx, cy = toCanvas(x, y)
    Game.mousepressed(cx, cy, button)
end

function love.mousemoved(x, y)
    local cx, cy = toCanvas(x, y)
    Game.mousemoved(cx, cy)
end

function love.gamepadpressed(joystick, button)
    Game.gamepadpressed(joystick, button)
end

function love.focus(f)
    if not f then Input.clear() end
end
