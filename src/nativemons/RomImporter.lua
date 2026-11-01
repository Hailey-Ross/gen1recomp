-- nativeMons: ROM import with no launcher UI, used as:
--   POKEPORT_IMPORT_ONLY=1 POKEPORT_IMPORT_ROM=<path> love .
--
-- The import steps follow the GPL import, verification and cache logic of upstream's
-- src/import/RomImporter.lua (Copyright (C) 2026 BOIS CLUB GAMES, LLC; GPLv3, see LICENSE.MD).
-- The launcher UI of that file is not part of this one. Each upstream merge compares upstream's
-- version of these steps at each merge.
--
-- Progress goes to stdout as "nativemons: <percent> <text>" and failures to "nativemons: error
-- <text>", followed by exit code 2, for the nativeMons launcher to read.

local CacheContract = require("src.import.CacheContract")
local GameVersion = require("src.core.GameVersion")

local ROM_SIZES = { [1024 * 1024] = true, [2 * 1024 * 1024] = true, [16 * 1024 * 1024] = true }

local RomImporter = {}
RomImporter.__index = RomImporter

local function report(text)
  print("nativemons: " .. text)
  io.stdout:flush()
end

local function sha1(data)
  local digest = love.data.hash("sha1", data)
  if type(digest) == "userdata" and digest.getString then digest = digest:getString() end
  return love.data.encode("string", "hex", digest)
end

local function removeTree(path)
  local info = love.filesystem.getInfo(path)
  if not info then return end
  if info.type == "directory" then
    for _, child in ipairs(love.filesystem.getDirectoryItems(path)) do
      removeTree(path .. "/" .. child)
    end
    love.filesystem.remove(path)
    return
  end
  local SaveData = require("src.core.SaveData")
  local real = love.filesystem.getSaveDirectory() .. "/" .. path
  local ok, err = SaveData.removeNative(real)
  if not ok then error("could not remove stale cache " .. real .. ": " .. tostring(err)) end
end

-- A portable install reads its cache from the game folder. A save-directory copy would shadow it.
local saveDirPurged = false
local function purgeSaveDirCache()
  if saveDirPurged then return end
  saveDirPurged = true
  for _, version in ipairs(GameVersion.ORDER) do
    local prefix = GameVersion.cachePrefix(version)
    if love.filesystem.getInfo(prefix .. CacheContract.MARKER_PATH) then
      removeTree(prefix .. "data/generated")
      removeTree(prefix .. "assets/generated")
      love.filesystem.remove(prefix .. CacheContract.MARKER_PATH)
    end
  end
end

function RomImporter.isReady(version)
  version = version or "red"
  local CacheFs = require("src.import.CacheFs")
  if CacheFs.root() then purgeSaveDirCache() end
  return CacheContract.isReady(version, CacheFs)
end

-- With launcher = true upstream would open its menu here. Ours is a separate program, so leaving
-- a game, or starting with no game, simply ends the process.
function RomImporter.new(onComplete, opts)
  local self = setmetatable({ onComplete = onComplete, ready = {}, status = "", progress = 0 }, RomImporter)
  require("src.import.CacheFs").migrateLegacyRedCache()
  if opts and opts.launcher then
    self.exitOnUpdate = true
  end
  return self
end

function RomImporter:setError(message)
  self.failed = tostring(message)
  self._extract = nil
  report("error " .. self.failed)
  love.event.quit(2)
end

function RomImporter:startPath(path)
  if not path then return end
  local file, openError = require("src.core.SaveData").openNative(path, "rb")
  if not file then return self:setError("Could not read " .. path .. ": " .. tostring(openError)) end
  local data = file:read("*a")
  file:close()
  self:startData(data, path:match("[^/\\]+$") or path, path)
end

function RomImporter:startData(data, displayName, sourcePath)
  self._importSource = sourcePath
  local RomArchive = require("src.import.RomArchive")
  if RomArchive.kind(data) then
    local bytes, entry = RomArchive.unwrap(data, displayName, {
      isRomName = function(name) return name:lower():match("%.gb[ac]?$") ~= nil end,
      acceptedSize = function(n) return ROM_SIZES[n] == true end,
      prefer = function(candidate) return GameVersion.forSha1(sha1(candidate)) ~= nil end,
    })
    if not bytes then return self:setError(entry) end
    data = bytes
  end
  if not ROM_SIZES[#data] then
    return self:setError(("This file is %.2f MiB; expected a 1 or 2 MiB Game Boy ROM or a 16 MiB "
      .. "Game Boy Advance ROM."):format(#data / 1024 / 1024))
  end
  self.romSha1 = sha1(data)
  local version = GameVersion.forSha1(self.romSha1)
  if not version then
    return self:setError("This ROM is not a supported version (SHA-1 " .. self.romSha1 .. ").")
  end

  local info = GameVersion.info(version)
  local prefix = info.cachePrefix
  local CacheFs = require("src.import.CacheFs")
  local savedPrefix = CacheFs.prefix
  CacheFs.prefix = prefix
  local cleared, clearError = pcall(function()
    removeTree(prefix .. "data/generated")
    removeTree(prefix .. "assets/generated")
    love.filesystem.remove(prefix .. CacheContract.MARKER_PATH)
    CacheFs.removeTree("data/generated")
    CacheFs.removeTree("assets/generated")
    CacheFs.remove(CacheContract.MARKER_PATH)
  end)
  CacheFs.prefix = savedPrefix
  if not cleared then return self:setError(clearError) end

  local thread = love.thread.newThread("src/import/ExtractThread.lua")
  local progressName, resultName = "rom_import_progress", "rom_import_result"
  love.thread.getChannel(progressName):clear()
  love.thread.getChannel(resultName):clear()
  thread:start(version, prefix, data, progressName, resultName, self.romSha1)
  self._extract = {
    thread = thread, version = version, prefix = prefix, displayName = displayName,
    progress = love.thread.getChannel(progressName),
    result = love.thread.getChannel(resultName),
  }
  self.status = "Preparing " .. info.displayName
  report("0 " .. self.status)
end

function RomImporter:_completeImport(version, prefix, displayName)
  local CacheFs = require("src.import.CacheFs")
  local savedPrefix = CacheFs.prefix
  CacheFs.prefix = prefix
  local ok, writeError = CacheContract.publish(version, CacheFs, self.romSha1)
  CacheFs.prefix = savedPrefix
  if not ok then error("could not finish the private cache: " .. tostring(writeError)) end

  local SaveConvert = package.loaded["src.save_convert.SaveConvert"]
  if GameVersion.generation(version) == 2 and SaveConvert then
    SaveConvert.invalidateGen2Data(version)
  end
  local RomSources = require("src.import.RomSources")
  local source = self._importSource
  if RomSources.isAbsolute(source) then
    pcall(RomSources.remember, version, { sha1 = self.romSha1, at = os.time(), path = source })
  end
  report("100 Ready")
  if self.onComplete then self.onComplete(version) end
end

function RomImporter:update()
  if self.exitOnUpdate then
    love.event.quit(0)
    return
  end
  local job = self._extract
  if not job then return end
  local msg = job.progress:pop()
  while msg do
    self.status = msg.stage
    self.progress = msg.progress / msg.total
    report(("%d %s"):format(math.floor(self.progress * 100), tostring(self.status)))
    msg = job.progress:pop()
  end
  local res = job.result:pop()
  if not res then
    local threadError = job.thread:getError()
    if threadError then self:setError(threadError) end
    return
  end
  self._extract = nil
  if not res.ok then return self:setError(res.error) end
  local ok, err = pcall(self._completeImport, self, job.version, job.prefix, job.displayName)
  if not ok then self:setError(err) end
end

function RomImporter:draw()
  local w, h = love.graphics.getDimensions()
  love.graphics.clear(0.07, 0.08, 0.1)
  love.graphics.setColor(0.25, 0.27, 0.32)
  love.graphics.rectangle("fill", w * 0.15, h * 0.5, w * 0.7, 8)
  love.graphics.setColor(0.95, 0.75, 0.2)
  love.graphics.rectangle("fill", w * 0.15, h * 0.5, w * 0.7 * self.progress, 8)
  love.graphics.setColor(1, 1, 1)
  love.graphics.print(self.status or "", w * 0.15, h * 0.5 - 24)
end

-- Input and window events the game's main.lua forwards while an importer is active.
for _, event in ipairs({ "keypressed", "gamepadpressed", "gamepadreleased", "gamepadaxis",
    "joystickpressed", "joystickreleased", "joystickaxis", "joystickhat", "touchpressed",
    "touchmoved", "touchreleased", "mousepressed", "mousereleased", "mousemoved", "textinput",
    "focus", "wheelmoved", "filedropped", "autoUpdateAll" }) do
  RomImporter[event] = function() end
end

return RomImporter
