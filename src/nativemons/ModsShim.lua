-- nativeMons: what the game's own code asks of the removed launcher's mod module.
-- The game's mod loader (src/mods/Loader.lua) reads translations once a game boots, and the
-- in-game manager handles mods from there, so there is nothing to do before that.
local ModsShim = {}

function ModsShim.translationStrings() return nil end
function ModsShim.list() return {} end

return ModsShim
