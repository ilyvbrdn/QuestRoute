import sqlite3, numpy as np, sys, pickle
from collections import defaultdict
from scipy.spatial import cKDTree
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components

CELL, ZCELL, RADIUS = 12.0, 8.0, 40.0
c = sqlite3.connect("vdb/sqlite-dump/mangos.sqlite")
inh = dict(c.execute("select entry, inhabit_type from creature_template"))
walk = lambda e: inh.get(e, 1) in (1, 3)

# NPCs people need to reach: quest givers and turn-ins, and anyone with a service (flight master, vendor, inn)
important = set(r[0] for r in c.execute("select id from creature_questrelation union select id from creature_involvedrelation"))
important |= set(r[0] for r in c.execute("select entry from creature_template where npc_flags != 0"))
out = {}
for mapid in (0, 1):
    pts, isroad, imp = [], [], []
    paths = []  # list of lists of point indices (patrol order)
    for x, y, z, cid in c.execute("select position_x, position_y, position_z, id from creature where map=?", (mapid,)):
        if walk(cid): pts.append((x, y, z)); isroad.append(0); imp.append(1 if cid in important else 0)
    # gameobjects on the ground: herbs, ore, chests, decorations, benches, mailboxes...
    for x, y, z, t in c.execute("""select g.position_x, g.position_y, g.position_z, t.type from gameobject g
            join gameobject_template t on t.entry = g.id where g.map = ?""", (mapid,)):
        if t in (0, 1, 2, 3, 5, 6, 7, 8, 9, 10, 19, 23):
            pts.append((x, y, z)); isroad.append(0); imp.append(0)
    # individual patrols
    rows = defaultdict(list)
    for gid, pt, x, y, z, cid in c.execute("""select m.id, m.point, m.position_x, m.position_y, m.position_z, cr.id
            from creature_movement m join creature cr on cr.guid = m.id where cr.map = ?""", (mapid,)):
        if walk(cid): rows[("g", gid)].append((pt, x, y, z))
    # shared patrol templates (only entries that spawn on this map)
    for entry, pid, pt, x, y, z in c.execute("""select entry, path_id, point, position_x, position_y, position_z
            from creature_movement_template where entry in (select id from creature where map = ?)""", (mapid,)):
        if walk(entry): rows[("t", entry, pid)].append((pt, x, y, z))
    for key, lst in rows.items():
        lst.sort()
        idx = []
        for _, x, y, z in lst:
            idx.append(len(pts)); pts.append((x, y, z)); isroad.append(1); imp.append(0)
        paths.append(idx)
    P = np.array(pts); R = np.array(isroad)
    keyv = np.stack([np.floor(P[:, 0] / CELL), np.floor(P[:, 1] / CELL), np.floor(P[:, 2] / ZCELL)], 1).astype(np.int64)
    _, inv = np.unique(keyv, axis=0, return_inverse=True); inv = inv.ravel()
    n = inv.max() + 1
    S = np.zeros((n, 3)); cnt = np.zeros(n); road = np.zeros(n)
    np.add.at(S, inv, P); np.add.at(cnt, inv, 1); np.maximum.at(road, inv, R)
    impn = np.zeros(n); np.maximum.at(impn, inv, np.array(imp))
    S /= cnt[:, None]

    # water surface markers: swimming creatures and fishing pools (x, y, z)
    W = [(x, y, z) for x, y, z, cid in c.execute("select position_x, position_y, position_z, id from creature where map=?", (mapid,)) if inh.get(cid) == 2]
    W += list(c.execute("""select g.position_x, g.position_y, g.position_z from gameobject g join gameobject_template t on t.entry = g.id
            where g.map = ? and t.type = 25""", (mapid,)))
    W = np.array(W); wt = cKDTree(W[:, :2])
    def wet(a, b):
        # a link through water: some point of it within 15 yd of a marker and not well above its surface
        # (a bridge deck stands several yards over the water; a swimming patrol is at or under it)
        d = np.hypot(*(S[a, :2] - S[b, :2]))
        ts = np.linspace(0, 1, max(2, int(d // 6) + 1))
        seg = S[a][None] * (1 - ts[:, None]) + S[b][None] * ts[:, None]
        for q, near in zip(seg, wt.query_ball_point(seg[:, :2], 15)):
            for k in near:
                if q[2] <= W[k, 2] + 2.5: return True
        return False
    dropped = 0
    drops = [0]
    edges = {}  # (a,b) -> is_road
    def add(a, b, r):
        nonlocal_dropped = None
        if a == b: return
        if wet(a, b):
            drops[0] += 1; return
        k = (a, b) if a < b else (b, a)
        edges[k] = max(edges.get(k, 0), r)
    # 1) patrol order: guards walk straight between consecutive points
    for idx in paths:
        for u, v in zip(idx, idx[1:]):
            a, b = inv[u], inv[v]
            d = np.hypot(*(S[a, :2] - S[b, :2])); dz = abs(S[a, 2] - S[b, 2])
            if d < 250 and dz <= 0.7 * d + 10: add(a, b, 1)
    # 2) nearby points with a walkable slope
    tree = cKDTree(S[:, :2])
    pairs = tree.query_pairs(RADIUS, output_type="ndarray")
    d = np.hypot(S[pairs[:, 0], 0] - S[pairs[:, 1], 0], S[pairs[:, 0], 1] - S[pairs[:, 1], 1])
    dz = np.abs(S[pairs[:, 0], 2] - S[pairs[:, 1], 2])
    ok = dz <= 0.7 * d + 3
    order = np.argsort(d[ok]); pr = pairs[ok][order]
    deg = defaultdict(int)
    for a, b in pr:
        if deg[a] < 6 or deg[b] < 6:
            add(int(a), int(b), 0); deg[a] += 1; deg[b] += 1
    E = np.array(list(edges.keys())); ER = np.array(list(edges.values()))
    g = coo_matrix((np.ones(len(E)), (E[:, 0], E[:, 1])), shape=(n, n))
    ncomp, lab = connected_components(g, directed=False)
    sizes = np.bincount(lab)
    has_imp = np.zeros(ncomp); np.maximum.at(has_imp, lab, impn)
    good = (sizes[lab] >= 25) | (has_imp[lab] > 0)
    print(f"map {mapid}: kept {int(((sizes < 25) & (has_imp > 0)).sum())} small clusters with NPCs people need")
    remap = -np.ones(n, int); remap[good] = np.arange(good.sum())
    m = good[E[:, 0]] & good[E[:, 1]]
    E, ER = remap[E[m]], ER[m]
    S, road = S[good], road[good]
    big = np.sort(sizes)[::-1][:5]
    print(f"map {mapid}: wet links dropped {drops[0]}; {len(S)} nodes, {len(E)} links ({ER.sum()} road), largest components {big}")
    out[mapid] = dict(S=S, flag=road, pairs=E, road=ER)
pickle.dump(out, open("nav_v2.pkl", "wb"))
