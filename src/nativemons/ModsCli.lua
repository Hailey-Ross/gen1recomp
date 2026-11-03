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
        -- Shipped with the engine (in its own folder), not installed by the player.
        local okDir, dir = pcall(love.filesystem.getRealDirectory, root .. "/manifest.json")
        manifest.bundled = okDir and dir ~= nil and dir == love.filesystem.getSource()
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

  -- default-off <id>: that mod off in every game, as a new default applied once to settings written before it
  -- (the launcher keeps a note that it's done, so the player's own choice afterwards stands).
  if verb == "default-off" and version ~= "" then
    local options = SaveData.loadOptions()
    for _, v in ipairs(GameVersion.ORDER) do SaveData.setModEnabled(options, version, false, SaveData.modScope(v)) end
    SaveData.setModEnabled(options, version, false, nil)
    return SaveData.saveOptions(options) == false and 1 or 0
  end
  -- enable-new <id>: a mod the player just installed is on in every game it runs, unless there it clashes with a mod
  -- that's on (either naming the other, within the range). One line per game: version, then on, or clash and the
  -- other mod's id and name.
  if verb == "enable-new" and version ~= "" then
    local Semver = require("src.mods.Semver")
    local ModTargets = require("src.mods.ModTargets")
    local options = SaveData.loadOptions()
    local all, byId = readManifests(), {}
    for _, m in ipairs(all) do byId[m.id] = m end
    local new = byId[version]
    if not new then io.stderr:write("no such mod\n") return 2 end
    local function names(a, b)
      for _, spec in ipairs(a.conflictSpecs or {}) do
        if spec.id == b.id and (not spec.range or spec.range == "" or Semver.satisfies(b.version, spec.range)) then return true end
      end
      return false
    end
    for _, v in ipairs(GameVersion.ORDER) do
      local generation = GameVersion.generation(v)
      if ModTargets.supports(new, v, generation) then
        local scope = SaveData.modScope(v)
        local against
        for _, m in ipairs(all) do
          if m.id ~= new.id and ModTargets.supports(m, v, generation) then
            local saved = SaveData.modEnabled(options, m.id, scope)
            local on = saved
            if on == nil then on = not (m.experimental or (m.bundled and type(m.required_assets) == "table" and #m.required_assets > 0)) end
            if on and (names(new, m) or names(m, new)) then against = m break end
          end
        end
        SaveData.setModEnabled(options, new.id, against == nil, scope)
        print(v .. "\t" .. (against and ("clash\t" .. clean(against.id) .. "\t" .. clean(against.name)) or "on"))
      end
    end
    return SaveData.saveOptions(options) == false and 1 or 0
  end
  if verb == "paths" then
    -- The portable folder when there is one (NATIVEMONS_DATA_DIR), else LOVE's.
    local root = SaveData.portableBaseDir() or love.filesystem.getSaveDirectory()
    print("save\t" .. root)
    print("mods\t" .. root .. "/mods")
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
      -- Same default as the loader: on, unless the mod marks itself experimental or came with the engine and needs an import first.
      local on = saved
      if on == nil then on = not (m.experimental or (m.bundled and type(m.required_assets) == "table" and #m.required_assets > 0)) end
      print(table.concat({ clean(m.id), clean(m.name), clean(m.version), on and "on" or "off",
        ModTargets.supports(m, version, generation) and "yes" or "no", clean(m.description) }, "\t"))
    end
    return 0
  end
  -- deps <version>: every dependency of the mods this game runs, by the engine's own rules (Manifest specs, its
  -- version ranges and game targets), one line each: mod id, mod name, required|optional, the dependency's id, its
  -- range, its GitHub repo when the mod names one, then ok | missing | version (installed, but outside the range),
  -- and the installed version. The launcher offers to install what's missing.
  if verb == "deps" then
    local Semver = require("src.mods.Semver")
    local all, byId = readManifests(), {}
    for _, m in ipairs(all) do byId[m.id] = m end
    for _, m in ipairs(all) do
      if ModTargets.supports(m, version, generation) then
        for _, pair in ipairs({ { "required", m.dependencySpecs }, { "optional", m.optionalSpecs } }) do
          for _, spec in ipairs(pair[2] or {}) do
            local here = true
            if type(spec.games) == "table" and #spec.games > 0 then
              here = false
              for _, v in ipairs(spec.games) do if v == version then here = true end end
            end
            if here then
              local have = byId[spec.id]
              local status = "ok"
              if not have then status = "missing"
              elseif spec.range and spec.range ~= "" and not Semver.satisfies(have.version, spec.range) then status = "version" end
              print(table.concat({ clean(m.id), clean(m.name), pair[1], clean(spec.id), clean(spec.range or ""),
                clean(spec.github or ""), status, clean(have and have.version or "") }, "\t"))
            end
          end
        end
      end
    end
    return 0
  end
  -- conflicts <version>: every clash a mod this game runs declares (conflicts / incompatible) against another installed
  -- mod it also runs, within the declared version range, one line each: the declaring mod's id, name and on|off, the
  -- other's id, name and on|off, and the range. While both are on, the engine skips the declaring mod
  -- (Loader:_enforceConflicts), so the launcher says so and lets the player choose.
  if verb == "conflicts" then
    local Semver = require("src.mods.Semver")
    local all, byId = readManifests(), {}
    for _, m in ipairs(all) do byId[m.id] = m end
    local function isOn(m)
      local saved = SaveData.modEnabled(options, m.id, scope)
      if saved ~= nil then return saved end
      return not (m.experimental or (m.bundled and type(m.required_assets) == "table" and #m.required_assets > 0))
    end
    for _, m in ipairs(all) do
      if ModTargets.supports(m, version, generation) then
        for _, spec in ipairs(m.conflictSpecs or {}) do
          local other = byId[spec.id]
          if other and other.id ~= m.id and ModTargets.supports(other, version, generation)
              and (not spec.range or spec.range == "" or Semver.satisfies(other.version, spec.range)) then
            print(table.concat({ clean(m.id), clean(m.name), isOn(m) and "on" or "off",
              clean(other.id), clean(other.name), isOn(other) and "on" or "off", clean(spec.range or "") }, "\t"))
          end
        end
      end
    end
    return 0
  end
  if verb == "set" and id ~= "" and (state == "on" or state == "off") then
    SaveData.setModEnabled(options, id, state == "on", scope)
    return SaveData.saveOptions(options) == false and 1 or 0
  end
  io.stderr:write("usage: paths | list <version> | deps <version> | conflicts <version> | set <version> <id> on|off | default-off <id>\n")
  return 2
end

return ModsCli
