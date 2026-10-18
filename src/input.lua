-- Turns keys, mouse and gamepads into what each robot is doing this step (the
-- input table World:update takes). Co-op on one machine is the point, so there
-- are two keyboard halves, the mouse, and any number of gamepads, and each is
-- bound to a robot:
--
--   left hand:  WASD move and aim, SPACE jump, Q / E portals, F grab
--               (the mouse aims for this robot too: click left / right for
--               the portals, middle to grab)
--   right hand: arrows move and aim, / jump, , and . portals, ; grab
--               (or the number pad: 0 jump, 1 / 2 portals, 3 grab)
--   gamepad:    left stick / d-pad move, right stick aims (the left stick does
--               if the right is idle), A jump, LB / RB portals, X or B grab
--
-- With one pad it plays the right hand's robot; with two, one each. TAB (or a
-- pad's BACK) swaps which robot the halves drive -- that is how one person
-- plays both, which every co-op puzzle here allows, if slowly.
--
-- Aim is a direction, not a point: the keys give eight, a stick or the mouse
-- any. With nothing held a robot aims the way it faces.
--
-- Presses are latched between steps: the game runs its rules at a fixed rate
-- that need not match the frame rate, and a jump pressed on a frame with no
-- step in it still has to land on the next one.

local Input = {}

local KEYS = {
    {
        left = { "a" }, right = { "d" }, up = { "w" }, down = { "s" },
        jump = { "space" }, fire1 = { "q" }, fire2 = { "e" }, grab = { "f" },
    },
    {
        left = { "left" }, right = { "right" }, up = { "up" }, down = { "down" },
        jump = { "/", "kp0", "rctrl" }, fire1 = { ",", "kp1" }, fire2 = { ".", "kp2" }, grab = { ";", "kp3" },
    },
}
Input.KEYS = KEYS

local EDGES = { "jump", "fire1", "fire2", "grab" }

-- Which robot each keyboard half (and the mouse, with half 1) drives.
Input.owner = { 1, 2 }

local latched = { {}, {} }
local mouse = { x = 0, y = 0, until_ = -1, buttons = {} }
local padPrev = {}

local function down(list)
    for _, k in ipairs(list) do
        if love.keyboard.isDown(k) then return true end
    end
    return false
end

function Input.swap()
    Input.owner[1], Input.owner[2] = Input.owner[2], Input.owner[1]
end

function Input.keypressed(key)
    for half, map in ipairs(KEYS) do
        for _, name in ipairs(EDGES) do
            for _, k in ipairs(map[name]) do
                if k == key then latched[Input.owner[half]][name] = true end
            end
        end
    end
end

-- The mouse aims from where the game says the gun is (Input.gunAt), in game
-- pixels; main.lua converts the window position before handing it here.
function Input.mousemoved(x, y)
    mouse.x, mouse.y = x, y
    mouse.until_ = love.timer.getTime() + 3
end

function Input.mousepressed(x, y, button)
    Input.mousemoved(x, y)
    local robot = Input.owner[1]
    local name = ({ "fire1", "fire2", "grab" })[button]
    if name then latched[robot][name] = true end
end

local function pads()
    local list = {}
    for _, j in ipairs(love.joystick.getJoysticks()) do
        if j:isGamepad() then list[#list + 1] = j end
    end
    return list
end

local function padRobot(i, count)
    if count >= 2 then return i <= 2 and i or nil end
    return Input.owner[2]
end

function Input.gamepadpressed(joystick, button)
    local list = pads()
    for i, j in ipairs(list) do
        if j == joystick then
            local robot = padRobot(i, #list)
            if not robot then return end
            local name = ({ a = "jump", leftshoulder = "fire1", rightshoulder = "fire2", x = "grab", b = "grab" })[button]
            if name then latched[robot][name] = true end
            if button == "back" then Input.swap() end
        end
    end
end

-- The inputs for both robots this step. `gun(i)` gives robot i's gun position
-- in game pixels, for mouse aim. Latched presses are spent by this call.
function Input.collect(gun)
    local out = { {}, {} }
    for i = 1, 2 do
        out[i] = { move = 0, aimx = 0, aimy = 0 }
    end

    for half, map in ipairs(KEYS) do
        local o = out[Input.owner[half]]
        local x = (down(map.right) and 1 or 0) - (down(map.left) and 1 or 0)
        local y = (down(map.down) and 1 or 0) - (down(map.up) and 1 or 0)
        o.move = o.move + x
        if x ~= 0 or y ~= 0 then o.aimx, o.aimy = x, y end
        o.jumpHeld = o.jumpHeld or down(map.jump)
    end

    -- The mouse aims for half 1's robot while it has been moved lately.
    if love.timer.getTime() < mouse.until_ and gun then
        local robot = Input.owner[1]
        local gx, gy = gun(robot)
        if gx then
            local dx, dy = mouse.x - gx, mouse.y - gy
            if dx * dx + dy * dy > 4 then out[robot].aimx, out[robot].aimy = dx, dy end
        end
    end

    local list = pads()
    for i, j in ipairs(list) do
        local robot = padRobot(i, #list)
        if robot then
            local o = out[robot]
            local lx, ly = j:getGamepadAxis("leftx"), j:getGamepadAxis("lefty")
            if j:isGamepadDown("dpleft") then lx = -1 end
            if j:isGamepadDown("dpright") then lx = 1 end
            if j:isGamepadDown("dpup") then ly = -1 end
            if j:isGamepadDown("dpdown") then ly = 1 end
            if math.abs(lx) > 0.35 then o.move = o.move + (lx > 0 and 1 or -1) end
            local rx, ry = j:getGamepadAxis("rightx"), j:getGamepadAxis("righty")
            if rx * rx + ry * ry > 0.3 * 0.3 then
                o.aimx, o.aimy = rx, ry
            elseif lx * lx + ly * ly > 0.5 * 0.5 then
                -- The left stick aims in eight, so a flick is not a near-miss.
                o.aimx = math.abs(lx) > 0.38 and (lx > 0 and 1 or -1) or 0
                o.aimy = math.abs(ly) > 0.38 and (ly > 0 and 1 or -1) or 0
            end
            o.jumpHeld = o.jumpHeld or j:isGamepadDown("a")
            -- Triggers are axes, so their press is found here, by edge.
            local prev = padPrev[j] or {}
            local lt, rt = j:getGamepadAxis("triggerleft") > 0.5, j:getGamepadAxis("triggerright") > 0.5
            if lt and not prev.lt then latched[robot].fire1 = true end
            if rt and not prev.rt then latched[robot].fire2 = true end
            padPrev[j] = { lt = lt, rt = rt }
        end
    end

    for i = 1, 2 do
        local o = out[i]
        o.move = math.max(-1, math.min(1, o.move))
        for _, name in ipairs(EDGES) do
            o[name] = latched[i][name] or false
            latched[i][name] = nil
        end
    end
    return out
end

-- Forget presses (a level change should not carry a jump into the next one).
function Input.clear()
    latched = { {}, {} }
end

return Input
