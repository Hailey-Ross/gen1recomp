-- nativeMons: a picture of one of the game's towns, for the launcher's home screen wallpaper. Written over the game's own
-- screen, like TitleArt:
--
--   NATIVEMONS_TOWN_ART=<file> POKEPORT_VERSION=<game> POKEPORT_DRIVER=src/nativemons/TownArt.lua
--
-- The launcher runs this under a throwaway identity, so it starts a new game and never meets a real save. The picture is made
-- from the player's own prepared game on their PC and stays there.

-- Each town's middle, so the whole of it fits in the zoomed-out view.
local TOWNS = {
  red = { "PALLET_TOWN", 10, 9 }, blue = { "PALLET_TOWN", 10, 9 }, yellow = { "PALLET_TOWN", 10, 9 },
  gold = { "NEW_BARK_TOWN", 10, 9 }, silver = { "NEW_BARK_TOWN", 10, 9 }, crystal = { "NEW_BARK_TOWN", 10, 9 },
  firered = { "FR_PALLET_TOWN", 12, 10 }, leafgreen = { "FR_PALLET_TOWN", 12, 10 },
  ruby = { "RU_LITTLEROOT_TOWN", 10, 10 }, sapphire = { "RU_LITTLEROOT_TOWN", 10, 10 }, emerald = { "EM_LITTLEROOT_TOWN", 10, 10 },
}

-- Pixels per world pixel for the picture: the engines' survey zoom, with the town filling the view.
local SCALE = 2

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

local function gen1(game, town)
  wait(30)
  while game.stack:top() do game.stack:pop() end
  game.stack:push(require("src.world.OverworldController"), town[1], town[2], town[3], "down")
end

local function gen2(game, town)
  wait(60)
  if not (game.world and game.world.map) then fail("the world didn't start") end
  game.world:warpToMapId(town[1], town[2], town[3], "down")
end

local function gen3(game, town)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    wait(1)
  end
  if not game.boot then fail("the game didn't reach its title") end
  game:_handleBootAction({ action = "new_game", name = "RED", gender = 0 })
  wait(180)
  -- Past the moving-in scene, so the town is as a player knows it.
  pcall(function()
    local Flags, Space = require("src.core.game3.scripting.flags"), require("src.core.game3.scripting.space")
    local VARS = Flags.forVersion(require("src.core.GameVersion").get()).VAR_IDS
    Flags.setVar(Space.store, nil, VARS.VAR_LITTLEROOT_TOWN_STATE, 4)
    Flags.setVar(Space.store, nil, VARS.VAR_LITTLEROOT_INTRO_STATE, 7)
  end)
  require("src.core.game3.map").load(nil, game, town[1], { x = town[2], y = town[3], facing = "down" })
end

return function(game)
  local file = os.getenv("NATIVEMONS_TOWN_ART")
  if not file then fail("no file given") end
  local GameVersion = require("src.core.GameVersion")
  local version = GameVersion.get()
  local town = TOWNS[version]
  if not town then fail("no town for " .. tostring(version)) end
  local generation = GameVersion.generation(version)
  local ok, problem = pcall(generation == 1 and gen1 or generation == 2 and gen2 or gen3, game, town)
  if not ok then fail(tostring(problem)) end
  -- The name sign has to clear, and the options can put the zoom back while a map loads.
  local Zoom = require("src.render.Zoom")
  Zoom.allowSurvey = true
  for _ = 1, 400 do
    Zoom.offset = SCALE - Zoom.windowFitScale()
    hidePlayer(game, generation)
    coroutine.yield()
  end
  game.capturePath = file
  for _ = 1, 600 do
    if not game.capturePath then
      local f = io.open(file, "rb")
      if f then f:close() love.event.quit(0) return end
    end
    coroutine.yield()
  end
  fail("the picture didn't reach the disk")
end
