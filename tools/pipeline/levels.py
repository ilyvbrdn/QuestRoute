import sqlite3, pickle, numpy as np, re
from scipy.spatial import cKDTree
c = sqlite3.connect("vdb/sqlite-dump/mangos.sqlite")
FRIENDLY = {35, 12, 11, 55, 57, 64, 79, 80, 68, 71, 29, 85, 104, 105, 83, 126, 120, 121, 474, 475, 69, 123, 150,
            210, 534, 1054, 1078, 1514, 1515, 875, 694, 995, 1215, 1216, 1217, 1218, 1219, 1220, 1576, 1577, 31, 188}
GUARD = re.compile(r"Guard|Sentinel|Grunt|Watcher|Deathguard|Bruiser|Protector|Defender|Peacekeeper|Footman|Marshal|"
                   r"Knight|Captain|Warden|Brave|Rifleman|Mountaineer|Huntsman|Patroller|Officer|Guardian|Lieutenant|Militia", re.I)
HORDE_F = {29, 83, 85, 104, 105, 68, 71, 126, 1515, 1074}
ALLY_F = {11, 12, 55, 57, 64, 79, 80, 123, 150, 875, 1078, 1514, 1077, 210, 534}
side = {}
for e, fac, lmax in c.execute("select entry, faction, level_max from creature_template"):
    side[e] = ("H" if fac in HORDE_F else "A" if fac in ALLY_F else None, lmax or 0)
tmpl = {}
# spawns that only appear during holidays and events don't make an area dangerous
event_guids = set(r[0] for r in c.execute("select guid from game_event_creature"))
for e, name, lmin, lmax, fac, npcf, rank, ctype in c.execute("select entry, name, level_min, level_max, faction, npc_flags, rank, type from creature_template"):
    # not counted: invisible effect spawns (type 10, 'not specified'), lone rares (rank 2/4: one wandering creature)
    hostile = (npcf == 0 and fac not in FRIENDLY and not GUARD.search(name or "") and (lmax or 0) > 1
               and ctype != 10 and rank not in (2, 4))
    tmpl[e] = ((lmin + lmax) / 2 + (3 if rank in (1, 2, 4) else 0)) if hostile else None
nav = pickle.load(open("nav_v4.pkl", "rb"))
for m in (0, 1):
    pts, lv = [], []
    for guid, cid, x, y in c.execute("select guid, id, position_x, position_y from creature where map=?", (m,)):
        L = tmpl.get(cid)
        if L and guid not in event_guids: pts.append((x, y)); lv.append(L)
    tree = cKDTree(np.array(pts)); lv = np.array(lv)
    S = nav[m]["S"]
    out = np.zeros(len(S), int)
    for i, near in enumerate(tree.query_ball_point(S[:, :2], 80)):
        if near: out[i] = int(round(np.median(lv[near])))
    nav[m]["lvl"] = np.clip(out, 0, 63)
    # the other faction's guards and towns are deadly: max level of their NPCs within 80 yd
    for tag, other in (("lvlA", "H"), ("lvlH", "A")):
        fp, fl = [], []
        for guid, cid, x, y in c.execute("select guid, id, position_x, position_y from creature where map=?", (m,)):
            sd, lv_ = side.get(cid, (None, 0))
            if sd == other and guid not in event_guids: fp.append((x, y)); fl.append(lv_)
        arr = out.copy()
        if fp:
            ft = cKDTree(np.array(fp)); fl = np.array(fl)
            for i, near in enumerate(ft.query_ball_point(S[:, :2], 80)):
                if near: arr[i] = max(arr[i], int(fl[near].max()))
        nav[m][tag] = np.clip(arr, 0, 63)
        print(f"   {tag}: points made deadly by the other faction: {(arr > out).sum()}")
    print(f"map {m}: {len(pts)} monsters; nodes with a level: {(out > 0).mean():.0%}")
pickle.dump(nav, open("nav_v4.pkl", "wb"))
# spot checks near towns / areas
tn = {r[0]: (r[1], r[2], r[3]) for r in c.execute("select name, map_id, x, y from taxi_nodes")}
for name in ["Crossroads, The Barrens", "Camp Taurajo, The Barrens", "Freewind Post, Thousand Needles", "Sun Rock Retreat, Stonetalon Mountains",
             "Shadowprey Village, Desolace", "Ratchet, The Barrens", "Sentinel Hill, Westfall", "Darkshire, Duskwood", "Morgan's Vigil, Burning Steppes", "Stormwind, Elwynn"]:
    m, x, y = tn[name]; S = nav[m]["S"]
    d = np.hypot(S[:, 0] - x, S[:, 1] - y)
    ring = (d > 150) & (d < 900)
    vals = nav[m]["lvl"][ring]; vals = vals[vals > 0]
    print(f"  around {name:38s} median monster level {np.median(vals) if len(vals) else 0:4.0f}")
