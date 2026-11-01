# Hails' additions

What this fork's `hails-additions` branch changes, for the nativeMons launcher.

## Launcher removed
`LICENSE.MD` term 2 makes the project launcher proprietary and says a fork must provide its own.
This branch removes the listed files, and `src/import/online/*`, which only worked through them.

**How upstream's code keeps working:** one line in `main.lua` loads `src/nativemons/`, which answers the
removed `require` names. `conf.lua` has one more line, for runs with no window. All new code is in `src/nativemons/`.

| Launcher need | Now done by |
|---|---|
| Choose a game | `love . --game=<version> [--slot=N]`; leaving the game ends the process |
| Import a ROM | `POKEPORT_IMPORT_ONLY=1 POKEPORT_IMPORT_ROM=<path> love .`, progress on stdout, exit code 2 on failure |
| List or switch mods | `NATIVEMONS_CLI="list <version>"`, `"set <version> <id> on|off"`, `"paths"` |

**Merging upstream:** a modify/delete conflict on a removed file stays deleted. Compare upstream's import steps with
`src/nativemons/RomImporter.lua` when they change. Run `tools/nativemons/check-removed.sh` afterwards.

**Known gaps:** carts, box tools, skins, save tools and mod asset-pack import were launcher screens and have no
replacement yet. Test drivers under `tests/` that open the launcher no longer apply.
