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
