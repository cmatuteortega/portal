-- tilemapper v0.0.5
-- Depends on:
--  - json.lua (https://github.com/rxi/json.lua)
--  - classic.lua (https://github.com/rxi/classic)
--  - bump.lua (https://github.com/kikito/bump.lua)
local json = require("lib.json")

local Tilemapper = Class:extend()

local Layer = Class:extend()
function Layer:new(tiles, name)
  self.tiles = tiles
  self.name = name
end

local TileLayer = Layer:extend()
function TileLayer:new(tiles, name, tileset, size, spacing, padding)
  TileLayer.super.new(self, tiles, name)
  self.type = "tile"
  self.tileset = love.graphics.newImage(tileset)
  self.size = size
  local quadInfo = {}
  for i = 1, #tiles do
    local tile = tiles[i]
    if not quadInfo[tile.t] then
      quadInfo[tile.t] = tile.src
    end
  end
  local quads = {}
  for k, info in pairs(quadInfo) do
    quads[k] = love.graphics.newQuad(
                   info[1], info[2], size, size, self.tileset:getWidth(),
                   self.tileset:getHeight())
  end
  self.quads = quads
end

local IntGrid = Layer:extend()
function IntGrid:new(tiles, name, size)
  IntGrid.super.new(self, tiles, name)
  self.type = "int"
  self.size = size
end

local AutoLayer = Layer:extend()
function AutoLayer:new(tiles, name, tileset, size, spacing, padding)
  AutoLayer.super.new(self, tiles, name)
  self.type = "auto"
  self.tileset = love.graphics.newImage(tileset)
  self.size = size
  local quadInfo = {}
  for i = 1, #tiles do
    local tile = tiles[i]
    if not quadInfo[tile.t] then
      quadInfo[tile.t] = tile.src
    end
  end
  local quads = {}
  for k, info in pairs(quadInfo) do
    quads[k] = love.graphics.newQuad(
                   info[1], info[2], size, size, self.tileset:getWidth(),
                   self.tileset:getHeight())
  end
  self.quads = quads
end

local function getIntGrid(layer, root, options, tilesets)
  local width = layer.__cWid
  local grid = layer.intGridCsv
  local collisions = options and options.collisions or {}
  local tiles = {}
  local size = layer.__gridSize
  local height = math.ceil(#grid / width)
  -- IntGrid value at cell (cx, cy); cells outside the level read as 0 (empty)
  local function cell(cx, cy)
    if cx < 0 or cx >= width or cy < 0 or cy >= height then return 0 end
    return grid[cy * width + cx + 1] or 0
  end
  for i = 0, #grid - 1 do
    if grid[i + 1] > 0 then
      local v = grid[i + 1]
      local c = collisions[v]
      if c then
        local y = math.floor(i / width)
        local x = i - y * width
        local tile = {
          x = x * size,
          y = y * size,
          v = v,
          h = size,
          w = size,
        }
        -- A collision entry may be a function of a neighbour accessor
        -- (at(dx, dy) → IntGrid value of the cell offset from this one),
        -- returning a rect table or nil for a full box.
        if type(c) == "function" then
          c = c(function(dx, dy) return cell(x + dx, y + dy) end)
        end
        -- A rect table { x, y, w, h } describes a partial box in tile-local
        -- pixels (e.g. spikes only occupy the half hugging their wall).
        if type(c) == "table" then
          tile.x = tile.x + (c.x or 0)
          tile.y = tile.y + (c.y or 0)
          tile.w = c.w or tile.w
          tile.h = c.h or tile.h
        end
        tiles[#tiles + 1] = tile
      end
    end
  end
  local ig = IntGrid(tiles, layer.__identifier, size)
  local autoTiles = layer.autoLayerTiles
  if autoTiles and #autoTiles > 0 and layer.__tilesetRelPath then
    local tilesetPath = root .. layer.__tilesetRelPath
    if options and options.aseprite then
      tilesetPath = tilesetPath:gsub("aseprite", "png")
    end
    ig.tileset = love.graphics.newImage(tilesetPath)
    local quadInfo = {}
    for i = 1, #autoTiles do
      local tile = autoTiles[i]
      if not quadInfo[tile.t] then quadInfo[tile.t] = tile.src end
    end
    local quads = {}
    for k, info in pairs(quadInfo) do
      quads[k] = love.graphics.newQuad(
                     info[1], info[2], size, size, ig.tileset:getWidth(),
                     ig.tileset:getHeight())
    end
    ig.quads = quads
    ig.autoTiles = autoTiles
  end
  return ig
end

local function getAutoLayer(layer, root, options, tilesets)
  local tilesetPath = root .. layer.__tilesetRelPath
  local tileset = tilesets[layer.__tilesetDefUid]
  if options and options.aseprite then
    tilesetPath = tilesetPath:gsub("aseprite", "png")
  end
  return AutoLayer(
             layer.autoLayerTiles, layer.__identifier, tilesetPath,
             layer.__gridSize, tileset.spacing, tileset.padding)
end

local function getTileLayer(layer, root, options, tilesets)
  local tilesetPath = root .. layer.__tilesetRelPath
  local tileset = tilesets[layer.__tilesetDefUid]
  if options and options.aseprite then
    tilesetPath = tilesetPath:gsub("aseprite", "png")
  end
  return TileLayer(
             layer.gridTiles, layer.__identifier, tilesetPath, layer.__gridSize,
             tileset.spacing, tileset.padding)
end

local function getEntities(layer)
  local instances = layer.entityInstances
  local entities = {}
  for i = 1, #instances do
    local entity = instances[i]
    if not entities[entity.__identifier] then
      entities[entity.__identifier] = {}
    end
    local pivot = entity.__pivot or {0, 0}
    local entity_obj = {
      x = entity.px[1] - pivot[1] * entity.width,
      y = entity.px[2] - pivot[2] * entity.height,
      w = entity.width,
      h = entity.height,
    }
    local _fields = entity.fieldInstances
    for j = 1, #_fields do
      local field = _fields[j]
      entity_obj[field.__identifier] = field.__value
    end
    entities[entity.__identifier][#entities[entity.__identifier] + 1] =
        entity_obj
  end
  entities.name = layer.__identifier
  entities.grid_size = layer.__gridSize
  return entities
end

local layerTypes = {
  AutoLayer = getAutoLayer,
  IntGrid = getIntGrid,
  Entities = getEntities,
  Tiles = getTileLayer,
}

local function getLayer(_layer, root, options, tilesets)
  local layer = {}
  local getLayerByType = layerTypes[_layer.__type]
  if getLayerByType then
    layer = getLayerByType(_layer, root, options, tilesets)
  else
    layer.name = _layer.__identifier
  end
  return layer
end

local function getLayers(_layers, root, options, tilesets)
  local layers = {}
  for i = 1, #_layers do
    local _layer = _layers[i]
    local layer = getLayer(_layer, root, options, tilesets)
    layer.z = i  -- LDtk index 1 = topmost; draw last
    layers[layer.name] = layer
  end
  return layers
end

local function getNeighbours(level, levelsByUid)
  local _neighbours = level.__neighbours
  local neighbours = {}
  for i = 1, #_neighbours do
    local neighbour = _neighbours[i]
    local dir = neighbour.dir
    if not neighbours[dir] then neighbours[dir] = {} end
    table.insert(neighbours[dir], levelsByUid[neighbour.levelIid or neighbour.levelUid])
  end
  return neighbours
end

local function getLevel(_level, root, options, tilesets, levelsByUid)
  local level = getLayers(_level.layerInstances, root, options, tilesets)
  for _, field in ipairs(_level.fieldInstances or {}) do
    level[field.__identifier] = field.__value
  end
  level.name = _level.identifier
  level.width = _level.pxWid
  level.height = _level.pxHei
  level.worldX = _level.worldX
  level.worldY = _level.worldY
  level.bgColor = _level.__bgColor
  level.next = getNeighbours(_level, levelsByUid)
  return level
end

local function getLevels(_levels, root, options, tilesets, levelsByUid)
  local levels = {}
  for i = 1, #_levels do
    local _level = _levels[i]
    local level = getLevel(_level, root, options, tilesets, levelsByUid)
    levels[level.name] = level
  end
  return levels
end

function Tilemapper:new(path, options)
  local root = path:gsub("[^/]+.ldtk", "")
  local data = love.filesystem.read(path)
  local raw = json.decode(data)
  local _levels = raw.levels
  local _tilesets = raw.defs.tilesets
  local tilesets = {}
  for i = 1, #_tilesets do
    local tileset = _tilesets[i]
    tilesets[tileset.uid] = {
      padding = tileset.padding,
      spacing = tileset.spacing,
    }
  end
  local levelsByUid = {}
  for i = 1, #_levels do
    local level = _levels[i]
    levelsByUid[level.uid] = level.identifier
    levelsByUid[level.iid] = level.identifier
  end
  local levels = getLevels(_levels, root, options, tilesets, levelsByUid)
  self.levels = levels
  self.no_physics = {}
  for _, name in ipairs((options and options.no_physics) or {}) do
    self.no_physics[name] = true
  end
end

function IntGrid:addCollisions(world)
  local tiles = self.tiles
  for i = 1, #tiles do
    local tile = tiles[i]
    world:add(tile, tile.x, tile.y, tile.w, tile.h)
  end
end

function Tilemapper:addCollisions()
  local layers = self.active
  for _, layer in pairs(layers) do
    local meta = getmetatable(layer)
    if meta and meta.addCollisions and not self.no_physics[layer.name] then
      layer:addCollisions(self.world)
    end
  end
end

function IntGrid:removeCollisions(world)
  local tiles = self.tiles
  for i = 1, #tiles do
    local tile = tiles[i]
    world:remove(tile)
  end
end

function Tilemapper:removeCollisions()
  local layers = self.active
  for _, layer in pairs(layers) do
    local meta = getmetatable(layer)
    if meta and meta.addCollisions and not self.no_physics[layer.name] then
      layer:removeCollisions(self.world)
    end
  end
end

local function draw_tile(tileset, quad, tile, size)
  local f = tile.f or 0
  local sx = (f == 1 or f == 3) and -1 or 1
  local sy = (f == 2 or f == 3) and -1 or 1
  local ox = sx == -1 and size or 0
  local oy = sy == -1 and size or 0
  love.graphics.draw(tileset, quad, tile.px[1], tile.px[2], 0, sx, sy, ox, oy)
end

function IntGrid:draw()
  if not self.autoTiles then return end
  for i = 1, #self.autoTiles do
    local tile = self.autoTiles[i]
    draw_tile(self.tileset, self.quads[tile.t], tile, self.size)
  end
end

function AutoLayer:draw()
  local tiles = self.tiles
  for i = 1, #tiles do
    draw_tile(self.tileset, self.quads[tiles[i].t], tiles[i], self.size)
  end
end

function TileLayer:draw()
  local tiles = self.tiles
  for i = 1, #tiles do
    draw_tile(self.tileset, self.quads[tiles[i].t], tiles[i], self.size)
  end
end

function Tilemapper:loadLevel(name, world)
  if not self.world and world then
    self.world = world
  end
  if not self.levels[name] then
    return false
  end
  self.current = name
  if self.active then
    self:removeCollisions()
  end
  self.active = self.levels[self.current]
  self:addCollisions()
end

function Tilemapper:nextLevel(dir, playerX, playerY)
  local candidates = self.active.next[dir]
  if not candidates or #candidates == 0 then
    return false
  end
  local name = candidates[1]
  if #candidates > 1 then
    local wx = (self.active.worldX or 0) + (playerX or 0)
    local wy = (self.active.worldY or 0) + (playerY or 0)
    for _, n in ipairs(candidates) do
      local lvl = self.levels[n]
      if dir == "w" or dir == "e" then
        if wy >= lvl.worldY and wy < lvl.worldY + lvl.height then name = n; break end
      else
        if wx >= lvl.worldX and wx < lvl.worldX + lvl.width then name = n; break end
      end
    end
  end
  self:loadLevel(name)
end

local function get_sorted_keys(t)
  local keys = {}
  for k in pairs(t) do
    table.insert(keys, k)
  end
  table.sort(keys)
  return keys
end

function Tilemapper:draw()
  local layers = self.active
  local drawable = {}
  for _, k in ipairs(get_sorted_keys(layers)) do
    local layer = layers[k]
    if getmetatable(layer) and getmetatable(layer).draw then
      drawable[#drawable + 1] = layer
    end
  end
  table.sort(drawable, function(a, b) return (a.z or 0) > (b.z or 0) end)
  for _, layer in ipairs(drawable) do
    if layer.pre_draw then layer.pre_draw() end
    layer:draw()
    if layer.post_draw then layer.post_draw() end
  end
end

return Tilemapper
