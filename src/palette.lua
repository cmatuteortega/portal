-- The palette: every colour on screen is one of these, keyed by a single
-- character so sprites can be drawn as ASCII (src/sprites.lua). Most of it is
-- the test chamber -- black void, steel, and the white panels that take a
-- portal -- so that the only saturated things are the robots, their portals and
-- the stuff that matters: buttons, doors, goo, the exit.
--
-- Each robot is a hue and owns two portals of it: robot 1 blue and violet,
-- robot 2 orange and red. You read whose portal is whose, and which end is
-- which, by colour alone.

local function hex(s)
    return { tonumber(s:sub(1, 2), 16) / 255, tonumber(s:sub(3, 4), 16) / 255, tonumber(s:sub(5, 6), 16) / 255 }
end

local P = {
    k = hex("1a1c2c"), -- void, outlines
    d = hex("333c57"), -- metal
    s = hex("566c86"), -- steel, seams
    m = hex("94b0c2"), -- mist, panel seams
    w = hex("f4f4f4"), -- white panel
    b = hex("41a6f6"), -- robot 1, portal 1
    v = hex("a77bf0"), -- robot 1, portal 2
    c = hex("73eff7"), -- robot 1 light
    o = hex("ef7d57"), -- robot 2, portal 1
    r = hex("b13e53"), -- robot 2, portal 2; buttons up, doors shut
    y = hex("ffcd75"), -- robot 2 light
    g = hex("a7f070"), -- goo top, exit lit, buttons down
    t = hex("38b764"), -- goo
    n = hex("29366f"), -- deep blue: the void's grid
}

-- Per robot: body, light, and the colour of each of its two portals.
P.robots = {
    { body = "b", light = "c", portal = { "b", "v" }, name = "BLUE" },
    { body = "o", light = "y", portal = { "o", "r" }, name = "ORANGE" },
}

function P.set(key)
    local c = P[key]
    love.graphics.setColor(c[1], c[2], c[3])
end

return P
