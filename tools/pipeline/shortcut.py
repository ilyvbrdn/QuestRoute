import pickle, numpy as np
from scipy.spatial import cKDTree
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import dijkstra
FACT = {0: 1.25, 1: 1.0, 2: 1.6, 3: 2.5}
nav = pickle.load(open("nav_v4_full.pkl", "rb"))
for m in (0, 1):
    N = nav[m]; S = N["S"]; E = N["pairs"]; R = N["road"]; n = len(S)
    w = np.hypot(*(S[E[:, 0], :2] - S[E[:, 1], :2]).T) * np.array([FACT[r] for r in R])
    G = coo_matrix((np.concatenate([w, w]), (np.concatenate([E[:, 0], E[:, 1]]), np.concatenate([E[:, 1], E[:, 0]]))), shape=(n, n)).tocsr()
    tree = cKDTree(S[:, :2]); wtree = cKDTree(N["water"])
    sources = np.arange(0, n, 3)
    cands = []
    for k in range(0, len(sources), 300):
        batch = sources[k:k + 300]
        D = dijkstra(G, directed=False, indices=batch, limit=2000)
        for bi, s in enumerate(batch):
            for t in tree.query_ball_point(S[s, :2], 250):
                if t <= s: continue
                d = np.hypot(*(S[s, :2] - S[t, :2]))
                if d < 60: continue
                if abs(S[s, 2] - S[t, 2]) > 0.15 * d + 6: continue
                g = D[bi, t]
                if g > 6 * d:
                    cands.append((d, s, t))
    cands.sort()
    added = []
    for d, s, t in cands:
        if any(np.hypot(*(S[s, :2] - S[a, :2])) < 200 and np.hypot(*(S[t, :2] - S[b, :2])) < 200 or
               np.hypot(*(S[s, :2] - S[b, :2])) < 200 and np.hypot(*(S[t, :2] - S[a, :2])) < 200 for a, b in added):
            continue
        ts = np.linspace(0, 1, max(3, int(d // 8)))
        seg = S[s, :2][None] * (1 - ts[:, None]) + S[t, :2][None] * ts[:, None]
        if np.any(wtree.query(seg[1:-1])[0] < 25): continue
        added.append((s, t))
    # roads that stop where the spawns stop (a quiet stretch of road): join two road ends that point at
    # each other, up to 900 yd apart, when the network goes far around
    JOIN_ROAD_ENDS = False  # needs terrain to tell a quiet road from a ridge: off
    deg = np.zeros(n, int); nb = {}
    for (a, b), r in zip(E, R):
        if r == 1:
            deg[a] += 1; deg[b] += 1; nb.setdefault(a, []).append(b); nb.setdefault(b, []).append(a)
    ends = [i for i in range(n) if deg[i] == 1]
    def heading(i):
        # direction the road runs out of its end: from a point ~60 yd back along it
        prev, cur, L = i, nb[i][0], 0
        for _ in range(8):
            L += np.hypot(*(S[cur, :2] - S[prev, :2]))
            if L >= 60 or deg[cur] != 2: break
            nxt = [q for q in nb[cur] if q != prev]
            if not nxt: break
            prev, cur = cur, nxt[0]
        v = S[i, :2] - S[cur, :2]; l = np.hypot(*v)
        return v / l if l > 0 else None
    H = {i: heading(i) for i in ends}
    et = cKDTree(S[ends, :2]); ends = np.array(ends)
    long_added = 0
    for ii, s in enumerate(ends if JOIN_ROAD_ENDS else []):
        if H[s] is None: continue
        for jj in et.query_ball_point(S[s, :2], 900):
            t = ends[jj]
            if t <= s or H[t] is None: continue
            v = S[t, :2] - S[s, :2]; d = np.hypot(*v)
            if d < 150: continue
            u = v / d
            if np.dot(H[s], u) < 0.82 or np.dot(H[t], -u) < 0.82: continue   # both point at each other (35 deg)
            if abs(S[s, 2] - S[t, 2]) > 0.12 * d + 8: continue
            g = dijkstra(G, directed=False, indices=s, limit=3 * d)[t]
            if g <= 2.5 * d: continue
            ts = np.linspace(0, 1, max(3, int(d // 8)))
            seg = S[s, :2][None] * (1 - ts[:, None]) + S[t, :2][None] * ts[:, None]
            if np.any(wtree.query(seg[1:-1])[0] < 25): continue
            added.append((s, t)); long_added += 1
            print(f"  map {m}: road gap {int(d)} yd joined at {S[s,0]:.0f},{S[s,1]:.0f} - {S[t,0]:.0f},{S[t,1]:.0f} (network {('%d' % g) if np.isfinite(g) else 'none'})")
    print(f"map {m}: {long_added} road gaps joined")
    if added:
        N["pairs"] = np.vstack([E, np.array(added)]); N["road"] = np.concatenate([R, 2 * np.ones(len(added), int)])
    print(f"map {m}: {len(cands)} candidate pairs, {len(added)} pass links added")
    N["shortcuts"] = added
pickle.dump(nav, open("nav_v4_full.pkl", "wb"))
