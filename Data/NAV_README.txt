QuestRoute road and terrain network (NavEK.lua, NavKalimdor.lua) and dock positions (Transports.lua)
=====================================================================================

How it was made
---------------
WoW gives addons no road or terrain data, so QuestRoute ships its own walkable-ground network:

* Source: the VMaNGOS classic world database (https://github.com/vmangos/core, development database
  snapshot). VMaNGOS is free software released under the GNU General Public License v2.
* Every creature and ground object spawn (herbs, ore, chests, lamps, benches, mailboxes...) marks
  ground a player can stand on. Swimming-only and flying creatures are left out.
* Guard and NPC patrol routes are the roads: patrols walk them point to point.
* Nearby points are linked when the height difference is walkable. Gaps are bridged in stages,
  never across water (sea creatures and fishing pools mark water) and never up steep slopes.
* Continent map coordinates come from matching VMaNGOS flight point positions to the in-game
  WoW Forever flight points (accuracy about 3 yards).
* Zeppelin towers, the Booty Bay and Ratchet docks and the Deeprun Tram exits are taken from the
  positions of the zeppelin masters, shipmasters and tram teleports in the same database.

Known limits
------------
* WoW Forever's new areas (Riverglades, Mount Hyjal, Shen'dralas, Darkspear Islands, Zephras Isle)
  are not in the classic database. QuestRoute learns roads there as people play.
* A few classic passes have no spawns along them and so aren't in the network yet (for example the
  Talondeep Path tunnel, the Hillsbrad - Hinterlands road and the eastern Feralas road). Routes still
  work but go the long way until the road is learned.

Roads traced from the map
-------------------------
Where the spawn data has gaps (for example the road east of Astranaar), extra ground points follow the
roads drawn on the zone maps, placed with each zone's real coordinates as the game reports them
(/qroute scan). Only positions were taken from the map images; no images are included in QuestRoute.

Licence note
------------
These data files are derived from GPL-licensed data. If you redistribute QuestRoute, keep this
file and credit VMaNGOS; distributing the addon under the GPL is the simple way to stay compatible.
