-- nativeMons: pictures of the game's towns, for the launcher's home screen wallpaper. Written over the game's own
-- screen, like TitleArt:
--
--   NATIVEMONS_TOWN_ART=<file.png>  the home town only
--   NATIVEMONS_TOWN_ART=<folder>    every town and city, one <MAP>.png each, home town first
--   POKEPORT_VERSION=<game> POKEPORT_DRIVER=src/nativemons/TownArt.lua
--
-- The launcher runs this under a throwaway identity, so it starts a new game and never meets a real save. The pictures
-- are made from the player's own prepared game on their PC and stay there.

local HOME = {
  red = "PALLET_TOWN", blue = "PALLET_TOWN", yellow = "PALLET_TOWN",
  gold = "NEW_BARK_TOWN", silver = "NEW_BARK_TOWN", crystal = "NEW_BARK_TOWN",
  firered = "MAP_PALLET_TOWN", leafgreen = "MAP_PALLET_TOWN",
  ruby = "MAP_LITTLEROOT_TOWN", sapphire = "MAP_LITTLEROOT_TOWN", emerald = "MAP_LITTLEROOT_TOWN",
}

-- Outdoor towns and cities by their names; Indigo Plateau is one too.
local function isTown(name)
  -- One word before ISLAND: Cinnabar and the Sevii towns, not places on them such as Six Island's Outcast Island.
  local island = name:gsub("^MAP_", ""):match("^[A-Z]+_ISLAND$")
  return name:match("_TOWN$") or name:match("_CITY$") or island or name:match("INDIGO_PLATEAU$")
    or name:match("INDIGO_PLATEAU_EXTERIOR$")
end

local function wait(n)
  for _ = 1, n do coroutine.yield() end
end

local function fail(message)
  io.stderr:write("town art: " .. message .. "\n")
  love.event.quit(1)
  while true do coroutine.yield() end
end

-- The picture is of the town, not of someone standing in it. Each generation hides its player differently.
local function hidePlayer(game, generation)
  if generation == 1 then
    local top = game.stack:top()
    if top then top.playerHidden = true end
  elseif generation == 2 then
    if game.world then game.world.playerHidden = true end
  else
    require("src.core.game3.player").visible = false
  end
end

-- Home first, then the rest by name.
local function ordered(names, home)
  table.sort(names)
  local out = {}
  for _, n in ipairs(names) do if n == home then table.insert(out, 1, n) else out[#out + 1] = n end end
  return out
end

-- Each generation: its list of towns, and a visit that stands in the middle of one and returns its size in pixels.
local gens = {}

gens[1] = {
  start = function() wait(30) end,
  towns = function(game, home)
    local names = {}
    for id in pairs(require("src.core.Game").data.maps) do
      if type(id) == "string" and isTown(id) then names[#names + 1] = id end
    end
    return ordered(names, home)
  end,
  visit = function(game, id)
    local def = require("src.core.Game").data.maps[id]
    if not def then return nil end
    while game.stack:top() do game.stack:pop() end
    game.stack:push(require("src.world.OverworldController"), id, def.width, def.height, "down")
    return def.width * 32, def.height * 32
  end,
}

gens[2] = {
  start = function(game)
    wait(60)
    if not (game.world and game.world.map) then fail("the world didn't start") end
  end,
  towns = function(game, home)
    local names = {}
    for id, def in pairs(game.world.maps or {}) do
      if type(id) == "string" and type(def) == "table" and isTown(id) then names[#names + 1] = id end
    end
    return ordered(names, home)
  end,
  visit = function(game, id)
    local def = game.world.maps[id]
    if not def then return nil end
    game.world:warpToMapId(id, def.width, def.height, "down")
    return def.width * 32, def.height * 32
  end,
}

gens[3] = {
  start = function(game)
    for _ = 1, 900 do
      if game.phase == "boot" and game.boot then break end
      wait(1)
    end
    if not game.boot then fail("the game didn't reach its title") end
    game:_handleBootAction({ action = "new_game", name = "RED", gender = 0 })
    wait(240)
    -- Past the moving-in scene, so Littleroot is as a player knows it.
    pcall(function()
      local Flags, Space = require("src.core.game3.scripting.flags"), require("src.core.game3.scripting.space")
      local VARS = Flags.forVersion(require("src.core.GameVersion").get()).VAR_IDS
      Flags.setVar(Space.store, nil, VARS.VAR_LITTLEROOT_TOWN_STATE, 4)
      Flags.setVar(Space.store, nil, VARS.VAR_LITTLEROOT_INTRO_STATE, 7)
    end)
  end,
  towns = function(game, home)
    local GameVersion = require("src.core.GameVersion")
    local C = require("src.core.game3.constants").of(GameVersion.get())
    -- The outdoor group: towns and cities sit in group 0 in Hoenn, 3 in Kanto.
    local group = GameVersion.layout(GameVersion.get()) == "rse" and 0 or 3
    local names = {}
    for name, row in pairs(C.map_groups.byName) do
      if row.group == group and isTown(name) then names[#names + 1] = name end
    end
    return ordered(names, home)
  end,
  visit = function(game, name)
    local Map = require("src.core.game3.map")
    local mapId = require("src.core.game3.map_ids").forConst(name)
    if not mapId then return nil end
    -- Its size is known once loaded: load, then stand in the middle.
    Map.load(nil, game, mapId, { x = 1, y = 1, facing = "down" })
    local def = Map.currentDef()
    local layout = def and def.midLayout
    if not (layout and layout.width) then return nil end
    local w, h = layout.width, layout.height
    Map.load(nil, game, mapId, { x = math.floor(w / 2), y = math.floor(h / 2), facing = "down" })
    return w * 16, h * 16
  end,
}

-- The largest whole zoom, up to 2, that fits the town in the window; big cities stay at 1 and get cut at the edges.
local function scaleFor(w, h)
  local ww, wh = love.graphics.getDimensions()
  local s = math.floor(math.min(ww / w, wh / h))
  return math.max(1, math.min(2, s))
end

local function picture(game, generation, file, scale)
  local Zoom = require("src.render.Zoom")
  Zoom.allowSurvey = true
  -- The name sign has to clear, and the options can put the zoom back while a map loads.
  for _ = 1, 400 do
    Zoom.offset = scale - Zoom.windowFitScale()
    hidePlayer(game, generation)
    coroutine.yield()
  end
  game.capturePath = file
  for _ = 1, 600 do
    if not game.capturePath then
      local f = io.open(file, "rb")
      if f then f:close() return true end
    end
    coroutine.yield()
  end
  return false
end

return function(game)
  local target = os.getenv("NATIVEMONS_TOWN_ART")
  if not target then fail("no file given") end
  local GameVersion = require("src.core.GameVersion")
  local version = GameVersion.get()
  local home = HOME[version]
  if not home then fail("no town for " .. tostring(version)) end
  local generation = GameVersion.generation(version)
  local gen = gens[generation] or gens[3]
  local one = target:lower():match("%.png$") ~= nil

  local ok, problem = pcall(gen.start, game)
  if not ok then fail(tostring(problem)) end
  local towns = { home }
  if not one then
    local okT, list = pcall(gen.towns, game, home)
    if not okT then fail(tostring(list)) end
    towns = list
  end

  local made = 0
  for _, town in ipairs(towns) do
    local okV, w, h = pcall(gen.visit, game, town)
    if okV and w then
      local file = one and target or (target .. "/" .. town:gsub("^MAP_", "") .. ".png")
      if picture(game, generation, file, scaleFor(w, h)) then
        made = made + 1
        print("town art: " .. town)
      else
        io.stderr:write("town art: " .. town .. " didn't reach the disk\n")
      end
    else
      io.stderr:write("town art: couldn't visit " .. town .. ": " .. tostring(w) .. "\n")
    end
  end
  if made == 0 then fail("no picture reached the disk") end
  love.event.quit(0)
end
