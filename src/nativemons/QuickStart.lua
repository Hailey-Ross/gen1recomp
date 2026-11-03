-- nativeMons: quick start. The launcher can start a game two ways with this:
--
--   NATIVEMONS_TO_TITLE=1     the game goes straight to its title screen, past the copyright and intro
--   NATIVEMONS_QUICK_START=1  the same, out of sight and silent: once at the title it stops, prints
--                             "nativemons: quick-start ready", and waits. A "play" line on stdin shows it, with its
--                             sound, at that title screen. The end of stdin (the launcher closed) ends it.
--
-- The title is reached the way TitleArt.lua reaches it. Nothing here touches the save: Game Boy and Game Boy Color
-- games read it only at Continue, and the launcher checks a GBA game's save didn't change while it waited.

local QuickStart = {}

local preload = os.getenv("NATIVEMONS_QUICK_START") == "1"
local toTitle = preload or os.getenv("NATIVEMONS_TO_TITLE") == "1"

local function say(text)
  io.stdout:write("nativemons: " .. text .. "\n")
  io.stdout:flush()
end

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

local function top(game)
  return game.stack and game.stack.top and game.stack:top() or nil
end

-- Each returns true once the title screen is up and settled.
local function gen1(game)
  local function onTitle()
    local t = top(game)
    return t and t.screenId == "TitleState" and t or nil
  end
  for _ = 1, 40 do
    if onTitle() then break end
    table.insert(game.input.pressQueue, "start")
    wait(1)
    game.input.state.start = false
    wait(20)
  end
  if not onTitle() then return false end
  -- A moment for the last Start press to clear, so it can't carry on past the title.
  wait(30)
  return onTitle() ~= nil
end

local function gen2(game)
  wait(10)
  game:showTitle()
  local title = top(game)
  waitFor(function() return title.entranceScx == nil or title.entranceScx == 0 end, 300)
  wait(30)
  return top(game) == title
end

local function gen3(game)
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then return false end
  local Boot = require("src.ui.game3.boot")
  if game.boot.custom then
    require("src.ui.game3.boot_modules").enterTitle(Boot, game.boot)
  else
    game.boot.phase = Boot.PHASE.TITLE
    require("src.ui.game3.title_screen").enter(game.boot)
  end
  wait(60)
  return game.phase == "boot" and game.boot ~= nil and game.boot.phase == Boot.PHASE.TITLE
end

-- The game's windows, hidden or shown again. Windows only; elsewhere this does nothing.
local function windows(show)
  if not (jit and jit.os == "Windows") then return end
  pcall(function()
    local ffi = require("ffi")
    pcall(ffi.cdef, [[
      typedef int (__stdcall *NativemonsQuickProc)(void *window, intptr_t data);
      int EnumThreadWindows(unsigned long thread, NativemonsQuickProc proc, intptr_t data);
      unsigned long GetCurrentThreadId(void);
      int ShowWindow(void *window, int show);
      int SetForegroundWindow(void *window);
      int IsWindowVisible(void *window);
      int GetWindowTextLengthA(void *window);
    ]])
    local each = ffi.cast("NativemonsQuickProc", function(window)
      -- Only the game's own window, which has a title: not the helper windows the system adds.
      if ffi.C.GetWindowTextLengthA(window) > 0 then
        if show then
          ffi.C.ShowWindow(window, 5)
          ffi.C.SetForegroundWindow(window)
        else
          ffi.C.ShowWindow(window, 0)
        end
      end
      return 1
    end)
    ffi.C.EnumThreadWindows(ffi.C.GetCurrentThreadId(), each, 0)
    each:free()
  end)
end

function QuickStart.install(getGame)
  if not toTitle then return end

  -- Silent until shown: the game's own volume settings are kept and applied on Play.
  local realSetVolume, wantedVolume
  if preload and love.audio then
    realSetVolume = love.audio.setVolume
    wantedVolume = love.audio.getVolume()
    realSetVolume(0)
    love.audio.setVolume = function(v) wantedVolume = v end
    windows(false)
  end

  local lines, reader
  if preload and love.thread then
    -- stdin is read on a thread of its own, so the game never blocks waiting for the launcher.
    reader = love.thread.newThread([[
      local channel = love.thread.getChannel("nativemons-quick-start")
      while true do
        local line = io.read("*l")
        if not line then channel:push("eof") return end
        -- .NET puts a byte-order mark before the first line it writes, and Windows ends lines with \r.
        channel:push((line:gsub("^\239\187\191", ""):gsub("%s+$", "")))
      end
    ]])
    reader:start()
    lines = love.thread.getChannel("nativemons-quick-start")
  end

  local reach, state, paused = nil, toTitle and "reaching" or "done", nil

  local function reveal()
    if realSetVolume then
      love.audio.setVolume = realSetVolume
      realSetVolume(wantedVolume or 1)
    end
    if paused then love.audio.play(paused) end
    paused = nil
    -- Back where the window would have opened (conf.lua kept it), or centred.
    pcall(function()
      local at = NATIVEMONS_WINDOW or {}
      local display = at.display or 1
      if at.x and at.y then
        love.window.setPosition(at.x, at.y, display)
      else
        local w, h = love.window.getMode()
        local dw, dh = love.window.getDesktopDimensions(display)
        love.window.setPosition(math.floor((dw - w) / 2), math.floor((dh - h) / 2), display)
      end
    end)
    windows(true)
    state = "done"
    say("quick-start shown")
  end

  local gameUpdate, gameDraw = love.update, love.draw
  function love.update(dt)
    if state == "waiting" then
      -- Stopped at the title: nothing moves, so the title never times out back to the intro.
      local line = lines and lines:pop()
      local problem = reader and reader:getError()
      if problem then say("quick-start failed reading the launcher: " .. problem) love.event.quit(3) return end
      if line == "play" then reveal()
      elseif line == "eof" then love.event.quit(0) end
      love.timer.sleep(0.03)
      return
    end
    local a, b = gameUpdate(dt)
    if state == "reaching" then
      local game = getGame()
      if game then
        if not reach then
          local GameVersion = require("src.core.GameVersion")
          local generation = GameVersion.generation(GameVersion.get())
          reach = coroutine.create(generation == 1 and gen1 or generation == 2 and gen2 or gen3)
        end
        local ok, done = coroutine.resume(reach, game)
        if not ok or coroutine.status(reach) == "dead" then
          if ok and done then
            if preload then
              paused = love.audio.pause()
              state = "waiting"
              say("quick-start ready")
            else
              state = "done"
              say("quick-start title")
            end
          else
            -- Couldn't find the title: a preload is of no use, and a normal start just carries on.
            say("quick-start failed " .. tostring(done))
            if preload then love.event.quit(3) else state = "done" end
          end
        end
      end
    end
    return a, b
  end
  function love.draw(...)
    if state == "waiting" then return end
    return gameDraw(...)
  end
end

return QuickStart
