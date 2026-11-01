-- nativeMons: lets the launcher list and switch mods without opening a game window.
--   NATIVEMONS_CLI="paths"                      love .
--   NATIVEMONS_CLI="games"                      love .
--   NATIVEMONS_CLI="active <version>" | "activate <version> <slot>" | "delete <version> <slot>" | "new <version>" | "duplicate <version> <slot>" | "adopt <version> <file>"   save slots
--   NATIVEMONS_CLI="options"                    love .   the settings the launcher shows
--   NATIVEMONS_CLI="option <key> <value>"       love .
--   NATIVEMONS_CLI="export <version>"           love .   prints the exported .sav's path
--   NATIVEMONS_CLI="import <version> <file>"    love .
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
  -- Settings the launcher shows, stored where the game's own options menu keeps them.
  local OPTIONS = { textSpeed = "number", musicVol = "number", sfxVol = "number",
    videoMode = "string", battleLayout = "string", animations = "boolean" }
  if verb == "options" then
    local options = SaveData.loadOptions()
    for key in pairs(OPTIONS) do print(key .. "\t" .. tostring(options[key])) end
    return 0
  end
  if verb == "option" then
    -- Here the words after the verb are a key and a value.
    local key, raw = version, id
    local kind = OPTIONS[key]
    local value
    if kind == "number" then value = tonumber(raw)
    elseif kind == "boolean" then value = raw == "true"
    elseif kind == "string" and raw ~= "" then value = raw end
    if value == nil then
      io.stderr:write("unknown setting or value\n")
      return 2
    end
    local options = SaveData.loadOptions()
    options[key] = value
    return SaveData.saveOptions(options) == false and 1 or 0
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

  if verb == "active" then
    print(tostring(SaveData.activeSlot(version)))
    return 0
  end
  if verb == "activate" then
    return SaveData.setActiveSlot(version, id) and 0 or 1
  end
  if verb == "delete" then
    return SaveData.deleteSlot(version, id) and 0 or 1
  end
  if verb == "new" then
    -- A new empty slot in use, so the title screen offers NEW GAME. Other slots stay.
    local slot = SaveData.createSlot(version)
    if not slot or not SaveData.setActiveSlot(version, slot) then return 1 end
    print(slot)
    return 0
  end
  if verb == "duplicate" then
    -- A copy of a slot, which leaves the slot in use as it is.
    local slot, err = SaveData.duplicateSlot(version, id)
    if not slot then
      io.stderr:write(tostring(err or "could not copy the slot") .. "\n")
      return 1
    end
    print(slot)
    return 0
  end
  if verb == "adopt" then
    -- A slot file from another install of this game. It's data, so it runs with access to nothing,
    -- and it must be this game's. The new slot is read back before it goes in use. Other slots stay.
    local path = command:match("^%S+%s+%S+%s+(.+)$")
    local file = path and io.open(path, "rb")
    if not file then io.stderr:write("can't read that file\n") return 2 end
    local text = file:read("*a")
    file:close()
    local chunk = loadstring(text, "=save")
    if not chunk then io.stderr:write("that isn't a save slot\n") return 2 end
    setfenv(chunk, {})
    local ok, save = pcall(chunk)
    if not ok or type(save) ~= "table" or type(save.player) ~= "table" then
      io.stderr:write("that isn't a save slot\n")
      return 2
    end
    if save.version ~= version then
      io.stderr:write("that save is for " .. tostring(save.version) .. ", not " .. version .. "\n")
      return 2
    end
    local slot = SaveData.createSlot(version)
    if not slot or not SaveData.writeSlot(version, slot, save) or not SaveData.readSlotSource(version, slot) then
      if slot then SaveData.deleteSlot(version, slot) end
      io.stderr:write("the save couldn't be written and read back\n")
      return 1
    end
    if not SaveData.setActiveSlot(version, slot) then return 1 end
    print(slot)
    return 0
  end
  if verb == "export" or verb == "import" then
    -- Cartridge saves, for moving Pokemon. Importing makes a new active slot, so older slots stay.
    GameVersion.set(version)
    require("src.import.CacheFs").mountVersion(version)
    local IO = require("src.import.SaveFileIO")
    local ok, res, info
    if verb == "export" then ok, res, info = IO.exportActiveSlot(version)
    else ok, res, info = IO.importToSlot(command:match("^%S+%s+%S+%s+(.+)$"), version, false) end
    if not ok then
      io.stderr:write(tostring(res or (info and info.note) or "save conversion failed") .. "\n")
      return 2
    end
    print(tostring(res))
    return 0
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
