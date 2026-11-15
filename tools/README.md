# Tools (not part of the addon)

Scripts used to build and test QuestRoute's data. The game never loads these; `.pkgmeta` keeps them out
of packaged releases.

- `pipeline/` - builds `Data/NavEK.lua` and `Data/NavKalimdor.lua` from the VMaNGOS world database
  (`build_nav2.py` -> `bridge2.py` -> `shortcut.py` -> `shrink.py 24 12` -> `connectors.py` ->
  `roads_to_nav.py 0.72 0.32` -> `levels.py` -> `export_nav.py`), traces roads from the zone map art
  (`roadness*.py`, `darkdens.py`, `trace_roads.py`), and writes `Data/Transports.lua` (`gen_transports2.py`).
- `tests/` - a fake WoW environment (`harness.lua`) and route tests run with Lua 5.1:
  `lua5.1 harness.lua <addon dir>` (game-side tests), `lua5.1 alltest.lua <addon dir> walk|cross`
  (every flight-point pair), `lua5.1 questtest.lua <addon dir>` (every quest: giver -> objective -> turn-in).

Inputs that aren't in the repo: the VMaNGOS SQLite dump, the stitched map image and the zone placement
from `/qroute scan`.
