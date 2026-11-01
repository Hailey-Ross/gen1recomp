-- nativeMons: the launcher plays its own splash, so this one finishes at once.
local NoSplash = {}
NoSplash.__index = NoSplash

function NoSplash.new() return setmetatable({ inputResumed = true }, NoSplash) end
function NoSplash:blocksInput() return false end
function NoSplash:update() return true end
function NoSplash:draw() end
function NoSplash:release() end

return NoSplash
