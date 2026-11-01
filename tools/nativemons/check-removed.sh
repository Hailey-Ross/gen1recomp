#!/bin/sh
# Fails if a file the licence forbids us to ship is back in the tree (LICENSE.MD, term 2).
cd "$(dirname "$0")/../.." || exit 2
found=$(git ls-files src/import/LauncherView.lua src/import/LauncherSettings.lua src/import/OnlinePanel.lua \
  src/import/CartLabelArt.lua src/import/CartShape.lua src/import/RomImporter.lua src/mods/LauncherMods.lua \
  src/import/online assets/launcher assets/labels)
if [ -n "$found" ]; then echo "Removed launcher files are back:"; echo "$found"; exit 1; fi
echo "OK: no launcher files in the tree"
