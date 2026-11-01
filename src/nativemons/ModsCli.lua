-- nativeMons: lets the launcher list and switch mods without opening a game window.
--   NATIVEMONS_CLI="paths"                      love .
--   NATIVEMONS_CLI="games"                      love .
--   NATIVEMONS_CLI="list <version>"             love .
--   NATIVEMONS_CLI="set <version> <id> on|off"  love .
--
-- Written for nativeMons over the game's GPL mod code (Manifest, ModTargets, SaveData). State is
-- stored where the game and its in-game manager already keep it. "list" prints one tab-separated
-- row per mod: id, name, version, on/off, runs-on-this-game yes/no, description.

local ModsCli = {}

local function clean(value)
  return (tostring(value or ""):gsub("[\t\r\n]+", " "))
end

local function readManifests()
  local Json = require("src.link.Json")
  local Manifest = require("src.mods.Manifest")
  local found = {}
  for _, name in ipairs(love.filesystem.getDirectoryItems("mods")) do
    local root = "mods/" .. name
    local raw = love.filesystem.read(root .. "/manifest.json")
    if raw then
      local data = Json.decode(raw)
      local ok, manifest = pcall(Manifest.validate, data, root)
      if data and ok then
        found[#found + 1] = manifest
      else
        io.stderr:write("mod ignored: " .. root .. "\n")
      end
    end
  end
  table.sort(found, function(a, b) return a.id < b.id end)
  return found
end

function ModsCli.run(command)
  local verb, version, id, state = command:match("^(%S+)%s*(%S*)%s*(%S*)%s*(%S*)")
  local SaveData = require("src.core.SaveData")
  local GameVersion = require("src.core.GameVersion")

  if verb == "paths" then
    print("save\t" .. love.filesystem.getSaveDirectory())
    print("mods\t" .. love.filesystem.getSaveDirectory() .. "/mods")
    return 0
  end
  if verb == "games" then
    -- One row per game: version, generation, imported yes/no, accepted ROM SHA-1s.
    local RomImporter = require("src.nativemons.RomImporter")
    for _, v in ipairs(GameVersion.ORDER) do
      local info = GameVersion.info(v)
      local hashes = { info.sha1 }
      for _, revision in ipairs(info.revisions or {}) do hashes[#hashes + 1] = revision.sha1 end
      print(table.concat({ v, tostring(GameVersion.generation(v)),
        RomImporter.isReady(v) and "yes" or "no", table.concat(hashes, ",") }, "\t"))
    end
    return 0
  end
  if not GameVersion.VERSIONS[version] then
    io.stderr:write("unknown game: " .. tostring(version) .. "\n")
    return 2
  end

  local ModTargets = require("src.mods.ModTargets")
  local generation = GameVersion.generation(version)
  local scope = SaveData.modScope(version)
  local options = SaveData.loadOptions()

  if verb == "list" then
    for _, m in ipairs(readManifests()) do
      local saved = SaveData.modEnabled(options, m.id, scope)
      -- Same default as the loader: on, unless the mod marks itself experimental.
      local on = saved
      if on == nil then on = not m.experimental end
      print(table.concat({ clean(m.id), clean(m.name), clean(m.version), on and "on" or "off",
        ModTargets.supports(m, version, generation) and "yes" or "no", clean(m.description) }, "\t"))
    end
    return 0
  end
  if verb == "set" and id ~= "" and (state == "on" or state == "off") then
    SaveData.setModEnabled(options, id, state == "on", scope)
    return SaveData.saveOptions(options) == false and 1 or 0
  end
  io.stderr:write("usage: paths | list <version> | set <version> <id> on|off\n")
  return 2
end

return ModsCli
