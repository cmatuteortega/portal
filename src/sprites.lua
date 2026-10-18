-- The art, as ASCII: one character per pixel, a palette key (src/palette.lua),
-- `.` for nothing. A robot is drawn once as a template in which `P` is its body
-- colour and `L` its light, and baked per robot. Facing left is the same image
-- mirrored, never rotated.

local P = require "src.palette"

local Sprites = {}

-- Head and torso, eye on the right (the way it faces).
local TOP = {
    "..ss..",
    ".wwww.",
    "wwwwLw",
    "wwwwkw",
    ".wwww.",
    "..ss..",
    ".PPPP.",
    "PPPPPP",
    "PwwPPP",
    "PPPPPP",
    ".PPPP.",
}

local LEGS = {
    stand = { ".s..s.", ".s..s.", "ss..ss" },
    walk1 = { ".s..s.", "s...s.", "s....s" },
    walk2 = { ".s..s.", ".s..s.", ".ss.s." },
    air   = { ".s..s.", "s....s", "......" },
}

local CUBE = {
    "dmmmmmmd",
    "mwwwwwwm",
    "mwswwswm",
    "mwwrrwwm",
    "mwwrrwwm",
    "mwswwswm",
    "mwwwwwwm",
    "dmmmmmmd",
}

local function bake(rows, map)
    local h, w = #rows, #rows[1]
    local data = love.image.newImageData(w, h)
    for y = 1, h do
        assert(#rows[y] == w, "ragged sprite row")
        for x = 1, w do
            local ch = rows[y]:sub(x, x)
            ch = map and map[ch] or ch
            if ch ~= "." then
                local c = assert(P[ch], "colour not in palette: " .. ch)
                data:setPixel(x - 1, y - 1, c[1], c[2], c[3], 1)
            end
        end
    end
    local img = love.graphics.newImage(data)
    img:setFilter("nearest", "nearest")
    return img, data
end

function Sprites.load()
    Sprites.robot = {}
    for i, look in ipairs(P.robots) do
        local frames = {}
        for name, legs in pairs(LEGS) do
            local rows = {}
            for _, r in ipairs(TOP) do rows[#rows + 1] = r end
            for _, r in ipairs(legs) do rows[#rows + 1] = r end
            frames[name] = bake(rows, { P = look.body, L = look.light })
        end
        Sprites.robot[i] = frames
    end
    Sprites.cube = bake(CUBE)
end

-- The window icon: robot 1 at four times on the void.
function Sprites.icon()
    local rows = {}
    for _, r in ipairs(TOP) do rows[#rows + 1] = r end
    for _, r in ipairs(LEGS.stand) do rows[#rows + 1] = r end
    local size, scale = 64, 4
    local ox, oy = (size - #rows[1] * scale) / 2, (size - #rows * scale) / 2
    local data = love.image.newImageData(size, size)
    local bg = P.k
    data:mapPixel(function(x, y)
        local gx, gy = math.floor((x - ox) / scale), math.floor((y - oy) / scale)
        local row = rows[gy + 1]
        if x >= ox and y >= oy and row and gx < #row then
            local ch = row:sub(gx + 1, gx + 1)
            ch = ({ P = "b", L = "c" })[ch] or ch
            if ch ~= "." then
                local c = P[ch]
                return c[1], c[2], c[3], 1
            end
        end
        return bg[1], bg[2], bg[3], 1
    end)
    return data
end

return Sprites
