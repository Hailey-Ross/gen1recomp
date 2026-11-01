-- nativeMons: the launcher's game options. NATIVEMONS_OPTIONS is a comma list such as text=fast,scene=off,style=set; anything
-- not listed stays as the player has it. Each generation keeps these differently, so the places that read options are wrapped
-- and upstream's files stay unchanged.

local GameOptions = {}

local function parse(text)
  local wanted = {}
  for key, value in (text or ""):gmatch("(%w+)=(%w+)") do wanted[key] = value end
  return wanted
end

local function wrap(module, name, apply)
  local original = module[name]
  module[name] = function(...)
    local result = original(...)
    if type(result) == "table" then apply(result) end
    return result
  end
end

local function gen1(o, w)
  if w.text then o.textSpeed = ({ slow = 5, mid = 3, fast = 1 })[w.text] end
  if w.scene then o.animations = w.scene == "on" end
  if w.style then o.battleStyle = w.style end
end

local function gen2(o, w)
  if w.text then o.textSpeed = ({ slow = "SLOW", mid = "MID", fast = "FAST" })[w.text] end
  if w.scene then o.battleScene = w.scene == "on" end
  if w.style then o.battleStyle = w.style:upper() end
  if w.sound then o.sound = w.sound:upper() end
end

local function gen3(o, w)
  if w.text then
    o.textSpeed = ({ slow = 0, mid = 1, fast = 2 })[w.text]
    o.text_speed = o.textSpeed
  end
  if w.scene then o.battleScene = w.scene == "on" and 0 or 1 end
  if w.style then o.battleStyle = w.style == "set" and 1 or 0 end
  if w.sound then o.sound = w.sound == "stereo" and 1 or 0 end
  if w.button then
    o.buttonMode = ({ normal = 0, alt = 1, lequalsa = 2 })[w.button]
    o.l_equals_a = o.buttonMode == 2
  end
  if w.frame then o.frameType = (tonumber(w.frame) or 1) - 1 end
end

function GameOptions.install()
  local wanted = parse(os.getenv("NATIVEMONS_OPTIONS"))
  if next(wanted) == nil then return end
  wrap(require("src.core.SaveData"), "loadOptions", function(o) gen1(o, wanted) end)
  wrap(require("src.core.gen2.Save"), "loadOptions", function(o) gen2(o, wanted) end)
  local Options3 = require("src.core.game3.options")
  wrap(Options3, "block", function(o) gen3(o, wanted) end)
  wrap(Options3, "ensure", function(o) gen3(o, wanted) end)
end

-- For testing: what each generation reads now.
function GameOptions.report()
  local a = require("src.core.SaveData").loadOptions()
  local b = require("src.core.gen2.Save").loadOptions()
  local c = require("src.core.game3.options").ensure({ options = {} })
  local function row(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    return table.concat(parts, " ")
  end
  return "gen1 " .. row(a.textSpeed, a.animations, a.battleStyle)
    .. " | gen2 " .. row(b.textSpeed, b.battleScene, b.battleStyle, b.sound)
    .. " | gen3 " .. row(c.textSpeed, c.battleScene, c.battleStyle, c.sound, c.buttonMode, c.frameType)
end

return GameOptions
