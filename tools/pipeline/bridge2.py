import pickle, numpy as np, sqlite3
from scipy.spatial import cKDTree
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components
nav = pickle.load(open("nav_v2.pkl", "rb"))
c = sqlite3.connect("vdb/sqlite-dump/mangos.sqlite")
inh = dict(c.execute("select entry, inhabit_type from creature_template"))
STAGES = [(150, 0.5, 5), (250, 0.35, 8), (400, 0.25, 10), (700, 0.4, 20)]
for mapid in (0, 1):
    N = nav[mapid]; S = N["S"]; E = N["pairs"]; ER = N["road"]; n = len(S)
    water = [(x, y) for x, y, cid in c.execute("select position_x, position_y, id from creature where map=?", (mapid,)) if inh.get(cid) == 2]
    water += list(c.execute("""select g.position_x, g.position_y from gameobject g join gameobject_template t on t.entry = g.id
            where g.map = ? and t.type = 25""", (mapid,)))  # fishing pools
    water = np.array(water)
    wtree = cKDTree(water)
    N["water"] = water
    tree = cKDTree(S[:, :2])
    for gap, slope, base in STAGES:
        for rnd in range(8):
            nc, lab = connected_components(coo_matrix((np.ones(len(E)), (E[:, 0], E[:, 1])), shape=(n, n)), directed=False)
            pr = tree.query_pairs(gap, output_type="ndarray")
            pr = pr[lab[pr[:, 0]] != lab[pr[:, 1]]]
            if gap > 400:  # long links only between real regions, not tiny islands
                sz = np.bincount(lab)
                pr = pr[(sz[lab[pr[:, 0]]] >= 100) & (sz[lab[pr[:, 1]]] >= 100)]
            if not len(pr): break
            d = np.hypot(*(S[pr[:, 0], :2] - S[pr[:, 1], :2]).T)
            dz = np.abs(S[pr[:, 0], 2] - S[pr[:, 1], 2])
            ok = dz <= slope * d + base
            pr, d = pr[ok], d[ok]
            best = {}
            for (a, b), dd in zip(pr, d):
                k = (min(lab[a], lab[b]), max(lab[a], lab[b]))
                if k not in best or dd < best[k][0]: best[k] = (dd, a, b)
            new = []
            for dd, a, b in sorted(best.values()):
                ts = np.linspace(0, 1, max(2, int(dd // 10)))
                seg = S[a, :2][None] * (1 - ts[:, None]) + S[b, :2][None] * ts[:, None]
                if np.any(wtree.query(seg)[0] < (40 if gap > 400 else 30)): continue
                new.append((a, b))
            if not new: break
            E = np.vstack([E, np.array(new)]); ER = np.concatenate([ER, (3 if gap > 400 else 2) * np.ones(len(new), int)])
        nc, lab = connected_components(coo_matrix((np.ones(len(E)), (E[:, 0], E[:, 1])), shape=(n, n)), directed=False)
        print(f"map {mapid} after gap {gap}: components {nc}, largest share {np.bincount(lab).max()/n:.1%}")
    # final: a large isolated region joins its nearest neighbour if it is close (harbours, causeways)
    nc, lab = connected_components(coo_matrix((np.ones(len(E)), (E[:, 0], E[:, 1])), shape=(n, n)), directed=False)
    sz = np.bincount(lab); main = sz.argmax()
    for comp in np.where(sz >= 150)[0]:
        if comp == main: continue
        idx = np.where(lab == comp)[0]
        others = np.where(lab != comp)[0]
        otree = cKDTree(S[others, :2])
        cand = []
        for ii, near in zip(idx, otree.query_ball_point(S[idx, :2], 450)):
            for jj in near:
                b = others[jj]
                dd = float(np.hypot(*(S[ii, :2] - S[b, :2])))
                if abs(S[ii, 2] - S[b, 2]) <= 0.4 * dd + 20:
                    cand.append((dd, ii, b))
        if cand:
            # prefer the shortest link that doesn't cross water; otherwise the shortest
            cand.sort()
            pick = None
            for dd, a, b in cand[:4000]:
                ts = np.linspace(0, 1, max(2, int(dd // 8)))
                seg = S[a, :2][None] * (1 - ts[:, None]) + S[b, :2][None] * ts[:, None]
                if not np.any(wtree.query(seg[1:-1] if len(seg) > 2 else seg)[0] < 20):
                    pick = (dd, a, b); break
            dd, a, b = pick or cand[0]
            E = np.vstack([E, [[a, b]]]); ER = np.concatenate([ER, [3]])
            print(f"   joined region of {sz[comp]} nodes with a {dd:.0f} yd link")
        else:
            print(f"   region of {sz[comp]} nodes left separate")
    N["pairs"], N["road"] = E, ER
pickle.dump(nav, open("nav_v4.pkl", "wb"))
