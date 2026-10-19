-- The screens and the loop between them: the title (pick a level), play, the
-- "chamber clear" card, and the end. The rules are src/world.lua; this file
-- feeds it input at a fixed rate, turns what it reports (World.events) into
-- sounds and sparks, and keeps which levels are open.
--
-- The rules step at a fixed 120Hz whatever the frame rate, so a fling goes the
-- same distance on every machine and the scripted solutions in tests/ hold on
-- screen too.
--
-- Online (src/net.lua, src/wire.lua) the host's game is this same loop, with
-- Orange's input arriving from the network and the world sent back after each
-- frame. The joiner's game steps nothing: it sends its input, draws the
-- host's snapshots, follows the host from screen to screen, and plays the
-- host's events as its own.

local D = require "src.defs"
local P = require "src.palette"
local Font = require "src.font"
local Draw = require "src.draw"
local Input = require "src.input"
local Sfx = require "src.sfx"
local World = require "src.world"
local Levels = require "src.levels"
local Net = require "src.net"
local Wire = require "src.wire"

local floor = math.floor
local STEP = 1 / 120
local SAVE = "progress.txt"
local W, H = D.COLS * D.TILE, D.ROWS * D.TILE
-- How often the host sends the world: a frame of a 60Hz screen. More is lost
-- on the joiner's display; less shows as judder.
local SNAP_EVERY = 1 / 60

local Game = {
    state = "title",
    time = 0,
    vw = 320, vh = 180,
    ox = 0, oy = 0,     -- where the map sits in the canvas
    cursor = 1,
    unlocked = 1,
    run = 0,            -- chamber starts, for telling an old snapshot from a new one
    address = "localhost",
}

--- progress ------------------------------------------------------------------------------------

local function loadProgress()
    local data = love.filesystem.getInfo(SAVE) and love.filesystem.read(SAVE)
    local n = data and tonumber(data:match("%d+"))
    Game.unlocked = math.max(1, math.min(#Levels, n or 1))
end

local function saveProgress()
    love.filesystem.write(SAVE, tostring(Game.unlocked) .. "\n")
end

--- states --------------------------------------------------------------------------------------

function Game.load()
    loadProgress()
    Game.cursor = Game.unlocked
end

function Game.resize(vw, vh)
    Game.vw, Game.vh = vw, vh
    Game.ox = floor((vw - W) / 2)
    Game.oy = floor((vh - H) / 2)
end

local function begin(index, level)
    Game.index = index
    Game.world = World.new(level)
    Game.state = "play"
    Game.acc = 0
    Game.snapAcc = 0
    Game.banner = 2.2
    Game.clearTime = 0
    Draw.reset()
    Input.clear()
    Sfx.play("spawn")
end

local function sendStart()
    Net.send({ t = "start", i = Game.index, run = Game.run, level = Game.world.level }, true)
end

function Game.start(index)
    begin(index, Levels[index])
    Game.run = Game.run + 1
    if Net.role == "host" then
        Wire.forget(Game.remote)
        sendStart()
    end
end

-- Back to the title, the host told (it shows the joiner the same screen).
local function toTitle()
    Game.state = "title"
    Game.world = nil
    if Net.role == "host" then Net.send({ t = "screen", s = "title" }, true) end
end

local function say(text, key, secs)
    Game.notice, Game.noticeKey, Game.noticeTime = text, key or "g", secs or 4
end

-- Where robot i's gun is, in the canvas's pixels (for aiming with the mouse).
function Game.gun(i)
    local w = Game.world
    if not w then return nil end
    local gx, gy = w:gun(w.players[i])
    return gx, gy
end

local SOUND = {
    portal_open = "open", portal_fail = "fail", portal_close = "close", teleport = "teleport",
    jump = "jump", grab = "grab", drop = "drop", die = "die", fizzle = "fizzle", grill = "grill",
    respawn = "spawn", cube_spawn = "spawn", win = "win", exit_ready = "ready",
}

function Game.react(e)
    local name = e.name
    if name == "shot" then
        local look = P.robots[e.owner]
        Sfx.play(e.slot == 1 and "shoot1" or "shoot2")
        Draw.trace(e.x, e.y, e.x1, e.y1, look.portal[e.slot])
    elseif name == "door_open" or name == "door_shut" then
        Sfx.play("door", name == "door_open" and 1.2 or 0.9)
        Sfx.play("button")
    elseif SOUND[name] then
        Sfx.play(SOUND[name])
    end
    if name == "portal_open" then
        Draw.burst(e.x, e.y, P.robots[e.owner].portal[e.slot], 14, 70)
    elseif name == "portal_fail" then
        Draw.burst(e.x, e.y, "s", 6, 40)
    elseif name == "teleport" then
        Draw.burst(e.x, e.y, "w", 5, 30, 0.2)
        Draw.burst(e.x1, e.y1, "w", 8, 50, 0.3)
    elseif name == "die" then
        Draw.burst(e.x, e.y, "g", 18, 90, 0.6)
        Draw.burst(e.x, e.y, P.robots[e.id].body, 10, 70, 0.5)
    elseif name == "fizzle" or name == "grill" then
        Draw.burst(e.x, e.y, "c", 12, 60)
    elseif name == "respawn" or name == "cube_spawn" then
        Draw.burst(e.x, e.y, "w", 10, 50)
    end
end

--- online ------------------------------------------------------------------------------------

local function title()
    love.window.setTitle(Net.role and ("Portal Pals (%s, %s)"):format(P.robots[Net.me].name,
        Net.role == "host" and "hosting" or "joined") or "Portal Pals")
end

function Game.host(port)
    local ok, err = Net.host(port)
    if not ok then say(err, "r"); Sfx.play("fail"); return false end
    Input.solo(Net.me)
    Game.remote = Wire.receiver()
    say(("HOSTING ON PORT %d: WAITING FOR A PARTNER"):format(Net.port), "g", 6)
    title()
    Sfx.play("ready")
    return true
end

function Game.join(address)
    local ok, err = Net.join(address)
    if not ok then say(err, "r"); Sfx.play("fail"); return false end
    Input.solo(Net.me)
    Game.sender = Wire.sender()
    Game.state = "title"
    Game.world = nil
    say(("CONNECTING TO %s"):format(Net.address:upper()), "m", 7)
    title()
    return true
end

-- Back to one machine. `why`, if any, is said on the title screen.
function Game.leave(why)
    local was = Net.role
    Net.leave()
    Input.solo(nil)
    title()
    if was == "joiner" then
        Game.state = "title"
        Game.world = nil
    end
    if why then say(why, "r"); Sfx.play("fail") end
end

local function hostHears(m)
    if m.t == "hello" then
        if m.v ~= Wire.VERSION then
            Net.send({ t = "bye", why = "THE HOST RUNS ANOTHER VERSION OF PORTAL PALS" }, true)
            return
        end
        Net.partner = true
        Game.remote = Wire.receiver()
        Net.send({ t = "welcome" }, true)
        -- Mid-chamber, the partner drops straight into it as it stands.
        if Game.state == "play" then sendStart() else Net.send({ t = "screen", s = Game.state }, true) end
        say("YOUR PARTNER IS HERE", "g")
        Sfx.play("ready")
    elseif m.t == "left" then
        Game.remote = Wire.receiver()
        say("YOUR PARTNER LEFT", "r")
    elseif m.t == "in" then
        Wire.receive(Game.remote, m)
    elseif m.t == "restart" then
        if Game.state == "play" then Game.start(Game.index) end
    end
end

local function joinerHears(m)
    if m.t == "joined" then
        Net.send({ t = "hello", v = Wire.VERSION }, true)
    elseif m.t == "welcome" then
        Net.partner = true
        say("CONNECTED. YOU ARE ORANGE", "g")
        Sfx.play("ready")
    elseif m.t == "start" then
        Game.run = m.run
        begin(m.i, m.level)
    elseif m.t == "screen" then
        Game.state = m.s == "end" and "end" or "title"
        Game.world = nil
    elseif m.t == "snap" then
        if Game.state == "play" and m.run == Game.run then Wire.apply(Game.world, m) end
    elseif m.t == "ev" then
        if Game.state == "play" and m.run == Game.run then
            for _, e in ipairs(m.list) do Game.react(e) end
        end
    elseif m.t == "left" then
        Game.leave("LOST THE HOST")
    elseif m.t == "failed" then
        Game.leave(("NO ANSWER FROM %s"):format((m.address or ""):upper()))
    elseif m.t == "bye" then
        Game.leave(m.why)
    end
end

function Game.network()
    for _, m in ipairs(Net.poll()) do
        if Net.role == "host" then hostHears(m) elseif Net.role == "joiner" then joinerHears(m) end
        if not Net.role then break end
    end
end

--- the loop ------------------------------------------------------------------------------------

function Game.update(dt)
    Game.time = Game.time + dt
    Game.noticeTime = math.max(0, (Game.noticeTime or 0) - dt)
    Game.swallow = nil
    Draw.update(dt)
    if Net.role then Game.network() end
    if Game.state ~= "play" then Net.flush(); return end
    local w = Game.world
    Game.banner = math.max(0, Game.banner - dt)
    if Net.role == "joiner" then
        -- Nothing steps here: what this player does goes to the host, and the
        -- world comes back in the next snapshot.
        if Net.partner then Net.send(Wire.pack(Game.sender, Input.collect(Game.gun)[Net.me])) end
        Net.flush()
        return
    end
    Game.acc = math.min(Game.acc + dt, STEP * 8)
    local inputs
    local sent = {}
    while Game.acc >= STEP do
        Game.acc = Game.acc - STEP
        -- Presses go to the first step after them and no other.
        inputs = Input.collect(Game.gun)
        if Net.role == "host" then inputs[2] = Wire.step(Game.remote) end
        w:update(STEP, inputs)
        for _, e in ipairs(w:drainEvents()) do
            Game.react(e)
            sent[#sent + 1] = e
        end
    end
    if Net.role == "host" and Net.partner then
        if #sent > 0 then Net.send({ t = "ev", run = Game.run, list = sent }, true) end
        Game.snapAcc = Game.snapAcc + dt
        if Game.snapAcc >= SNAP_EVERY then
            Game.snapAcc = math.min(Game.snapAcc - SNAP_EVERY, SNAP_EVERY)
            Net.send(Wire.snapshot(w, Game.run))
        end
        Net.flush()
    end
    if w.won then
        Game.clearTime = Game.clearTime + dt
        if Game.clearTime > 1.4 then
            if Game.index >= #Levels then
                Game.state = "end"
                if Net.role == "host" then Net.send({ t = "screen", s = "end" }, true) end
            else
                Game.unlocked = math.max(Game.unlocked, Game.index + 1)
                saveProgress()
                Game.start(Game.index + 1)
            end
        end
    end
end

-- F5: read levels.ldtk again (after a save in LDtk) and restart the chamber
-- being played, or stay on the list. A broken file leaves the chambers as they
-- were and says why on screen, rather than taking the game down mid-edit.
function Game.reload()
    if Net.role == "joiner" then say("THE HOST'S CHAMBERS ARE THE ONES PLAYED", "m"); return end
    local ok, err = pcall(Levels.reload)
    if ok then
        Game.notice, Game.noticeKey = ("RELOADED %d CHAMBERS"):format(#Levels), "g"
        Game.unlocked = math.min(Game.unlocked, #Levels)
        Game.cursor = math.min(Game.cursor, #Levels)
        if Game.state == "play" then Game.start(math.min(Game.index, #Levels)) end
        Sfx.play("ready")
    else
        Game.notice, Game.noticeKey = tostring(err):gsub("^.-:%d+: ", ""):upper(), "r"
        print(err)
        Sfx.play("fail")
    end
    Game.noticeTime = 4
end

--- keys ----------------------------------------------------------------------------------------

local function menuMove(d)
    Game.cursor = (Game.cursor - 1 + d) % #Levels + 1
    Sfx.play("tick")
end

local CONFIRM = { ["return"] = true, kpenter = true, space = true, ["/"] = true, kp0 = true }

-- The address prompt (J on the title) takes typed text; keys that are
-- letters too must not also do their usual thing while it is open.
function Game.typing() return Game.state == "join" end

function Game.textinput(text)
    -- The J that opened the prompt arrives as text too, in the same frame.
    if Game.state ~= "join" or Game.swallow then return end
    text = text:gsub("[^%w%.%-:%[%]]", "")
    if text == "" then return end
    -- The last address comes up selected: typing replaces it, Enter reuses it.
    if Game.fresh then Game.address, Game.fresh = "", false end
    Game.address = (Game.address .. text):sub(1, 60)
end

local function joinKey(key)
    if key == "escape" then
        Game.state = "title"
    elseif key == "backspace" then
        Game.address = Game.fresh and "" or Game.address:sub(1, -2)
        Game.fresh = false
    elseif key == "return" or key == "kpenter" then
        if Game.address ~= "" then Game.join(Game.address) end
    end
end

function Game.keypressed(key)
    if Game.state == "join" then joinKey(key); return end
    if key == "tab" and not Input.only then Input.swap(); Sfx.play("tick") end
    if key == "f5" then Game.reload(); return end
    local joiner = Net.role == "joiner"
    if Game.state == "title" then
        if key == "escape" then
            if Net.role then Game.leave() else love.event.quit() end
            return
        end
        if joiner then return end
        if key == "up" or key == "w" then menuMove(-1) end
        if key == "down" or key == "s" then menuMove(1) end
        if key == "h" and not Net.role then Game.host() end
        if key == "j" and not Net.role then
            Game.state, Game.swallow, Game.fresh = "join", true, true
            Sfx.play("tick")
        end
        if CONFIRM[key] then
            if Game.cursor <= Game.unlocked then Game.start(Game.cursor) else Sfx.play("fail") end
        end
    elseif Game.state == "play" then
        if key == "escape" then
            if joiner then Game.leave(); return end
            Game.cursor = Game.index
            toTitle()
            return
        end
        if key == "r" then
            if joiner then Net.send({ t = "restart" }, true) else Game.start(Game.index) end
            return
        end
        Input.keypressed(key)
    elseif Game.state == "end" then
        if joiner then
            if key == "escape" then Game.leave() end
        elseif key == "escape" or CONFIRM[key] then
            Game.unlocked = #Levels
            saveProgress()
            toTitle()
        end
    end
end

function Game.gamepadpressed(joystick, button)
    if Game.state == "title" then
        if button == "dpup" then menuMove(-1) end
        if button == "dpdown" then menuMove(1) end
        if button == "a" or button == "start" then Game.keypressed("return") end
    elseif Game.state == "play" then
        if button == "start" then Game.keypressed("escape") return end
        Input.gamepadpressed(joystick, button)
    elseif Game.state == "end" then
        if button == "a" or button == "start" then Game.keypressed("return") end
    end
end

function Game.mousepressed(x, y, button)
    if Game.state == "play" then
        Input.mousepressed(x - Game.ox, y - Game.oy, button)
    elseif Game.state == "title" then
        if button == 1 then Game.keypressed("return") end
    end
end

function Game.mousemoved(x, y)
    if Game.state == "play" then Input.mousemoved(x - Game.ox, y - Game.oy) end
end

--- drawing -------------------------------------------------------------------------------------

local function controlsCard(x, y)
    if Input.only then
        -- One robot per machine: every key, the mouse and any pad drive it.
        local look = P.robots[Input.only]
        Font.shadow(look.name, x, y, look.body, P)
        Font.shadow("WASD OR ARROWS MOVE/AIM  SPACE JUMP  Q E PORTALS  F GRAB  C CLEAR", x + 28, y, "m", P)
        Font.shadow("MOUSE AIMS: LEFT / RIGHT CLICK PORTALS, MIDDLE GRAB", x + 28, y + 8, "m", P)
        Font.shadow("PADS: STICKS  A JUMP  LB RB PORTALS  X GRAB  Y CLEAR", x, y + 18, "s", P)
        return
    end
    local half = { "WASD MOVE/AIM  SPACE JUMP  Q E PORTALS  F GRAB  C CLEAR (OR MOUSE)",
        "ARROWS MOVE/AIM  / JUMP  , . PORTALS  ; GRAB  ' CLEAR (OR NUM 0-4)" }
    for i = 1, 2 do
        local robot = Input.owner[i]
        Font.shadow(P.robots[robot].name, x, y + (i - 1) * 8, P.robots[robot].body, P)
        Font.shadow(half[i], x + 28, y + (i - 1) * 8, "m", P)
    end
    Font.shadow("PADS: STICKS  A JUMP  LB RB PORTALS  X GRAB  Y CLEAR   TAB: SWAP ROBOTS", x, y + 18, "s", P)
end

-- Under the chamber list: how to go online, or how it is going.
local function onlineLine()
    if Net.role == "host" then
        if Net.partner then return "PLAYING ONLINE AS BLUE. ESC TO STOP HOSTING", "g" end
        return ("HOSTING ON PORT %d: WAITING FOR A PARTNER  (ESC STOPS)"):format(Net.port), "m"
    elseif Net.role == "joiner" then
        if Net.partner then return "CONNECTED AS ORANGE: THE HOST PICKS THE CHAMBER", "g" end
        return ("CONNECTING TO %s  (ESC GIVES UP)"):format(Net.address:upper()), "m"
    end
    return "TWO MACHINES?  H HOST A GAME   J JOIN ONE", "s"
end

local function drawTitle()
    P.set("k")
    love.graphics.rectangle("fill", 0, 0, Game.vw, Game.vh)
    local cx = floor(Game.vw / 2)
    local top = Game.oy + 14
    -- The name, twice the size: a 3x5 face scaled by a whole number.
    love.graphics.push()
    love.graphics.translate(cx - Font.width("PORTAL PALS") , top)
    love.graphics.scale(2, 2)
    P.set("k"); Font.print("PORTAL PALS", 1, 1)
    P.set("w"); Font.print("PORTAL PALS", 0, 0)
    love.graphics.pop()
    local blue, orange = P.robots[1], P.robots[2]
    P.set(blue.portal[1]); love.graphics.rectangle("fill", cx - Font.width("PORTAL PALS") - 10, top, 3, 10)
    P.set(orange.portal[1]); love.graphics.rectangle("fill", cx + Font.width("PORTAL PALS") + 7, top, 3, 10)
    Font.shadow("A CO-OP TESTING INITIATIVE FOR TWO ROBOTS", cx - Font.width("A CO-OP TESTING INITIATIVE FOR TWO ROBOTS") / 2, top + 16, "s", P)

    local listY = top + 32
    for i, level in ipairs(Levels) do
        local y = listY + (i - 1) * 9
        local open = i <= Game.unlocked
        local label = ("%d  %s"):format(i, level.name)
        local key = open and (i == Game.cursor and "w" or "m") or "d"
        if i == Game.cursor then
            P.set(floor(Game.time * 4) % 2 == 0 and "b" or "o")
            Font.print(">", cx - 46, y)
        end
        Font.shadow(open and label or (("%d  ????"):format(i)), cx - 38, y, key, P)
    end
    local promptY = listY + #Levels * 9 + 6
    if Net.role ~= "joiner" then
        Font.shadow("ENTER / SPACE / A TO START", cx - Font.width("ENTER / SPACE / A TO START") / 2,
            promptY, floor(Game.time * 2) % 2 == 0 and "g" or "t", P)
    end
    local line, key = onlineLine()
    Font.shadow(line, cx - Font.width(line) / 2, promptY + 10, key, P)
    controlsCard(Game.ox + 6, Game.oy + D.ROWS * D.TILE - 26)
end

local function drawJoin()
    drawTitle()
    local cx, cy = floor(Game.vw / 2), floor(Game.vh / 2)
    local bw, bh = 220, 40
    P.set("k")
    love.graphics.rectangle("fill", cx - bw / 2, cy - bh / 2, bw, bh)
    P.set("d")
    local x0, y0 = cx - bw / 2, cy - bh / 2
    love.graphics.rectangle("fill", x0, y0, bw, 1)
    love.graphics.rectangle("fill", x0, y0 + bh - 1, bw, 1)
    love.graphics.rectangle("fill", x0, y0, 1, bh)
    love.graphics.rectangle("fill", x0 + bw - 1, y0, 1, bh)
    local head = "JOIN A GAME: THE HOST'S ADDRESS"
    Font.shadow(head, cx - Font.width(head) / 2, cy - 13, "w", P)
    local text = Game.address:upper() .. (floor(Game.time * 3) % 2 == 0 and "_" or " ")
    local tx = cx - Font.width(text) / 2
    if Game.fresh and Game.address ~= "" then
        P.set("d")
        love.graphics.rectangle("fill", tx - 1, cy - 3, Font.width(Game.address) + 2, 7)
    end
    Font.shadow(text, tx, cy - 2, "o", P)
    local foot = "ENTER JOINS   ESC CANCELS"
    Font.shadow(foot, cx - Font.width(foot) / 2, cy + 9, "s", P)
end

local function drawEnd()
    P.set("k")
    love.graphics.rectangle("fill", 0, 0, Game.vw, Game.vh)
    local cx, cy = floor(Game.vw / 2), floor(Game.vh / 2)
    local lines = { "ALL TESTS COMPLETE.", "", "THE TWO OF YOU MAKE AN EXCELLENT TEAM.", "THIS WILL NOT BE GOING ON YOUR RECORD.", "",
        Net.role == "joiner" and "ESC TO LEAVE" or "PRESS ENTER" }
    for i, l in ipairs(lines) do
        Font.shadow(l, cx - Font.width(l) / 2, cy - 24 + i * 8, i == 1 and "g" or "m", P)
    end
end

local function drawPlay()
    local w = Game.world
    P.set("k")
    love.graphics.rectangle("fill", 0, 0, Game.vw, Game.vh)
    love.graphics.push()
    love.graphics.translate(Game.ox, Game.oy)
    Draw.world(w, Game.time, true)

    -- The bottom strip, on the floor's metal: the level, the robots, the keys.
    local name = ("%d  %s"):format(Game.index, w.level.name)
    Font.shadow(name, 4, H - 13, "m", P)
    local keys = Net.role == "joiner" and "R RESTART  ESC LEAVE" or Net.role and "R RESTART  ESC MENU"
        or "R RESTART  ESC MENU  TAB SWAP"
    Font.shadow(keys, W - 4 - Font.width(keys), H - 13, "s", P)
    for i = 1, 2 do
        local p = w.players[i]
        -- Each robot's name and its two portals: lit if placed. Online, this
        -- machine's robot is YOU.
        local x = 84 + (i - 1) * 52
        local name = Net.me == i and "YOU" or P.robots[i].name
        Font.shadow(name, x, H - 13, p.alive and P.robots[i].body or "s", P)
        for s = 1, 2 do
            P.set(w.portals[i][s] and P.robots[i].portal[s] or "s")
            love.graphics.rectangle("fill", x + Font.width(name) + 3 + (s - 1) * 4, H - 13, 3, 5)
        end
    end

    if Game.banner > 0 then
        local text = ("TEST CHAMBER %02d"):format(Game.index)
        Font.shadow(text, W / 2 - Font.width(text) / 2, 10, "w", P)
        Font.shadow(w.level.name, W / 2 - Font.width(w.level.name) / 2, 18, "g", P)
    end
    if w.won then
        local text = "CHAMBER CLEAR"
        Font.shadow(text, W / 2 - Font.width(text) / 2, 2, floor(Game.time * 6) % 2 == 0 and "g" or "w", P)
    elseif w.exitTime == 0 then
        local inside = 0
        for _, p in ipairs(w.players) do
            local cx, cy = p.x + p.w / 2, p.y + p.h / 2
            if p.alive and w:tile(floor(cx / D.TILE), floor(cy / D.TILE)) == "*" then inside = inside + 1 end
        end
        if inside == 1 then
            local text = "WAITING FOR YOUR PARTNER"
            Font.shadow(text, W / 2 - Font.width(text) / 2, 2, "m", P)
        elseif Net.role == "host" and not Net.partner then
            local text = ("ORANGE HAS NOT JOINED YET (PORT %d)"):format(Net.port)
            Font.shadow(text, W / 2 - Font.width(text) / 2, 2, "s", P)
        end
    end
    love.graphics.pop()
end

function Game.draw()
    if Game.state == "title" then drawTitle()
    elseif Game.state == "join" then drawJoin()
    elseif Game.state == "end" then drawEnd()
    else drawPlay() end
    if (Game.noticeTime or 0) > 0 then
        local text = Game.notice
        -- An error can be long: wrapped at the canvas's width, a line each.
        local per = math.floor((Game.vw - 8) / Font.ADVANCE)
        local y = Game.vh - 8
        local lines = {}
        for i = 1, #text, per do lines[#lines + 1] = text:sub(i, i + per - 1) end
        for i = #lines, 1, -1 do
            P.set("k")
            love.graphics.rectangle("fill", 0, y - 2, Game.vw, 8)
            Font.shadow(lines[i], 4, y, Game.noticeKey, P)
            y = y - 8
        end
    end
end

return Game
