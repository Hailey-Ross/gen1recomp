-- nativeMons: pictures of a game's title screen, for the launcher's backgrounds. Written over the game's own GPL title code.
--
--   NATIVEMONS_TITLE_ART=<folder> POKEPORT_VERSION=<game> POKEPORT_DRIVER=src/nativemons/TitleArt.lua
--
-- The pictures are made from the player's own prepared game on their PC and stay there. Nothing here saves the game.

local COUNT, STEP = 48, 6

local function wait(n)
  for _ = 1, n do coroutine.yield() end
end

local function waitFor(test, frames)
  for _ = 1, frames do
    if test() then return true end
    coroutine.yield()
  end
  return false
end

local function fail(message)
  io.stderr:write("title art: " .. message .. "\n")
  love.event.quit(1)
  while true do coroutine.yield() end
end

local function gen1Title(game)
  local function onTitle()
    local top = game.stack:top()
    return top and top.screenId == "TitleState" and top or nil
  end
  for _ = 1, 40 do
    if onTitle() then break end
    table.insert(game.input.pressQueue, "start")
    wait(1)
    game.input.state.start = false
    wait(20)
  end
  local title = onTitle()
  if not title then fail("the title screen didn't come up") end
  waitFor(function() return title.phase == "loop" end, 1800)
end

local function gen2Title(game)
  wait(10)
  game:showTitle()
  local title = game.stack:top()
  waitFor(function() return title.entranceScx == nil or title.entranceScx == 0 end, 300)
  wait(30)
end

local function gen3Title(game)
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then fail("the game didn't reach its start") end
  local Boot = require("src.ui.game3.boot")
  if game.boot.custom then
    require("src.ui.game3.boot_modules").enterTitle(Boot, game.boot)
  else
    game.boot.phase = Boot.PHASE.TITLE
    require("src.ui.game3.title_screen").enter(game.boot)
  end
  wait(480)
end

return function(game)
  local folder = os.getenv("NATIVEMONS_TITLE_ART")
  if not folder then fail("no folder given") end
  local generation = require("src.core.GameVersion").generation(require("src.core.GameVersion").get())
  if generation == 1 then gen1Title(game)
  elseif generation == 2 then gen2Title(game)
  else gen3Title(game) end

  for i = 0, COUNT - 1 do
    local path = ("%s/shot-%02d.png"):format(folder, i)
    game.capturePath = path
    if not waitFor(function()
      if game.capturePath then return false end
      local f = io.open(path, "rb")
      if f then f:close() return true end
      return false
    end, 600) then fail("a picture didn't reach the disk") end
    wait(STEP)
  end
  love.event.quit(0)
end
