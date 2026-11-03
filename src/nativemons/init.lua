-- nativeMons: Gen1Recomp without its proprietary launcher (see LICENSE.MD, term 2).
--
-- The launcher files are removed from this fork. Upstream code still asks for them by name, so
-- this file answers those names with small replacements. That keeps the change to upstream's own
-- files down to one line in main.lua, and upstream merges stay easy.
--
-- These are new code written for nativeMons, not copies of the launcher. The nativeMons launcher
-- (a separate program) picks the game, imports ROMs and manages mods.

local function preload(name, target)
  package.preload[name] = function() return require(target) end
end

preload("src.import.RomImporter", "src.nativemons.RomImporter")
preload("src.mods.LauncherMods", "src.nativemons.ModsShim")
preload("src.import.LauncherSplash", "src.nativemons.NoSplash")

-- Leaving a game ends the process, which returns the player to the nativeMons launcher.
require("src.core.HostShell").canRestart = function() return false end

local gameOptions = require("src.nativemons.GameOptions")
local installed, problem = pcall(gameOptions.install)
if not installed then io.stderr:write("game options: " .. tostring(problem) .. "\n") end

-- A background job for the launcher never shows up for the player. Preparing a game draws nothing anyone needs, so its
-- window is hidden outright, which also stops it drawing. A title screen or town picture is read from what the game drew,
-- and a hidden window doesn't draw: that window stays off-screen (conf.lua), with no taskbar button and never the focus.
local pictureJob = os.getenv("NATIVEMONS_TITLE_ART") or os.getenv("NATIVEMONS_TOWN_ART")
if jit and jit.os == "Windows" and (pictureJob or os.getenv("POKEPORT_IMPORT_ONLY") == "1") then
  local hidden, problem = pcall(function()
    local ffi = require("ffi")
    ffi.cdef([[
      typedef int (__stdcall *NativemonsWindowProc)(void *window, intptr_t data);
      int EnumThreadWindows(unsigned long thread, NativemonsWindowProc proc, intptr_t data);
      unsigned long GetCurrentThreadId(void);
      int ShowWindow(void *window, int show);
      long GetWindowLongA(void *window, int index);
      long SetWindowLongA(void *window, int index, long value);
    ]])
    local GWL_EXSTYLE, WS_EX_TOOLWINDOW, WS_EX_APPWINDOW, WS_EX_NOACTIVATE = -20, 0x80, 0x40000, 0x8000000
    local each = ffi.cast("NativemonsWindowProc", function(window)
      ffi.C.ShowWindow(window, 0)
      if pictureJob then
        local style = bit.bor(bit.band(ffi.C.GetWindowLongA(window, GWL_EXSTYLE), bit.bnot(WS_EX_APPWINDOW)), WS_EX_TOOLWINDOW, WS_EX_NOACTIVATE)
        ffi.C.SetWindowLongA(window, GWL_EXSTYLE, style)
        ffi.C.ShowWindow(window, 4) -- shown again without taking the focus
      end
      return 1
    end)
    ffi.C.EnumThreadWindows(ffi.C.GetCurrentThreadId(), each, 0)
    each:free()
  end)
  if not hidden then io.stderr:write("hiding the window: " .. tostring(problem) .. "\n") end
end

-- A launcher request with no game to start: answer it and end here.
local command = os.getenv("NATIVEMONS_CLI")
if command == "gameoptions" then
  io.stdout:write(gameOptions.report() .. "\n")
  io.stdout:flush()
  os.exit(0)
end
if command then
  local ok, code = pcall(function() return require("src.nativemons.ModsCli").run(command) end)
  if not ok then io.stderr:write(tostring(code) .. "\n") end
  io.stdout:flush()
  os.exit(ok and code or 1)
end
