-- Two machines, one chamber: a connection over ENet (built into LÖVE) between
-- a host, who plays Blue and runs the rules, and the one who joins and plays
-- Orange. What travels on it is src/wire.lua's; this file only opens, polls
-- and closes the connection.
--
-- Channel 0 is reliable and ordered (chamber starts, events, hello); channel 1
-- is unreliable, ENet dropping any packet older than one already delivered
-- (snapshots and input, where only the latest matters).
--
-- Testing on one machine is the same thing on localhost:
--   love . --host          and in a second window   love . --join localhost

local Wire = require "src.wire"

local Net = {
    role = nil,        -- nil (one machine), "host" or "joiner"
    me = nil,          -- which robot this machine plays
    partner = false,   -- connected (and, for the host, said hello)
    PORT = 22122,
}

local enet
local host, peer
local connectingSince

-- ENet's own wait before calling a silent peer gone is up to half a minute;
-- a partner whose game has closed should be noticed sooner than that.
local TIMEOUT_MIN, TIMEOUT_MAX = 2000, 5000
local CONNECT_WAIT = 6

local function load()
    if enet == nil then
        local ok, lib = pcall(require, "enet")
        enet = ok and lib or false
    end
    return enet
end

function Net.host(port)
    Net.leave()
    port = port or Net.PORT
    if not load() then return false, "NO NETWORKING IN THIS BUILD OF LOVE" end
    host = enet.host_create("*:" .. port, 1, 2)
    if not host then return false, ("PORT %d IS IN USE"):format(port) end
    Net.role, Net.me, Net.port = "host", 1, port
    return true
end

-- `address` is a name or IP, with :port if it isn't the usual one.
function Net.join(address)
    Net.leave()
    if not load() then return false, "NO NETWORKING IN THIS BUILD OF LOVE" end
    if not address:find(":") then address = address .. ":" .. Net.PORT end
    host = enet.host_create(nil, 1, 2)
    if not host then return false, "NO NETWORK" end
    local ok, p = pcall(host.connect, host, address, 2)
    if not ok or not p then
        host:destroy()
        host = nil
        return false, "CAN'T FIND " .. address:upper()
    end
    peer = p
    peer:timeout(0, TIMEOUT_MIN, TIMEOUT_MAX)
    Net.role, Net.me, Net.address = "joiner", 2, address
    connectingSince = love.timer.getTime()
    return true
end

function Net.leave()
    if peer then peer:disconnect_now() end
    if host then
        host:flush()
        host:destroy()
    end
    host, peer, connectingSince = nil, nil, nil
    Net.role, Net.me, Net.partner = nil, nil, false
end

-- Everything that arrived since the last call, as messages, plus three the
-- connection itself makes: {t = "joined"} when a partner connects, {t = "left"}
-- when it goes, and {t = "failed"} when a join gets no answer.
function Net.poll()
    local out = {}
    if not host then return out end
    local ev = host:service(0)
    while ev do
        if ev.type == "connect" then
            if Net.role == "host" then
                peer = ev.peer
                peer:timeout(0, TIMEOUT_MIN, TIMEOUT_MAX)
            end
            connectingSince = nil
            out[#out + 1] = { t = "joined" }
        elseif ev.type == "disconnect" then
            if ev.peer == peer then
                peer = nil
                Net.partner = false
                out[#out + 1] = { t = "left" }
            end
        elseif ev.type == "receive" then
            local ok, msg = pcall(Wire.decode, ev.data)
            if ok and type(msg) == "table" and type(msg.t) == "string" then out[#out + 1] = msg end
        end
        if not host then break end
        ev = host:service(0)
    end
    if connectingSince and love.timer.getTime() - connectingSince > CONNECT_WAIT then
        out[#out + 1] = { t = "failed", address = Net.address }
    end
    return out
end

function Net.send(msg, reliable)
    if not peer then return end
    peer:send(Wire.encode(msg), reliable and 0 or 1, reliable and "reliable" or "unreliable")
end

-- Send what this frame queued now, rather than at the next poll.
function Net.flush()
    if host then host:flush() end
end

return Net
