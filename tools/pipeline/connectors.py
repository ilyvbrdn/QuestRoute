import json, pickle, numpy as np
from scipy.spatial import cKDTree
nav = pickle.load(open("nav_v4.pkl", "rb")); full = pickle.load(open("nav_v4_full.pkl", "rb"))
places = json.load(open("wh/places.json"))
CONT = [("kalimdor", 1, 0, 0, 0, 0), ("zephras", 2991, 24576, 8192, 21, 22), ("ek", 0, 32768, 8192, 23, 20)]
def server(cx, cy):
    for key, m, x0, y0, oc, orow in sorted(CONT, key=lambda c: c[2], reverse=True):
        if cx >= x0:
            col = oc + (cx - x0) / 512.0; row = orow + (cy - y0) / 512.0
            return m, (32 - row) * 533.3333, (32 - col) * 533.3333
added = {0: 0, 1: 0}; links = {0: 0, 1: 0}
for m in (0, 1):
    N = nav[m]; S = list(map(tuple, N["S"])); E = [tuple(e) for e in N["pairs"]]; R = list(N["road"]); L = list(N.get("lvl", np.zeros(len(S))))
    W = cKDTree(full[m]["water"])
    base_tree = cKDTree(np.array(S)[:, :2])
    def dry(a, b):
        d = np.hypot(a[0] - b[0], a[1] - b[1]); n = max(3, int(d // 10))
        ts = np.linspace(0, 1, n)[1:-1]
        seg = np.c_[a[0] + (b[0] - a[0]) * ts, a[1] + (b[1] - a[1]) * ts]
        return len(seg) == 0 or not np.any(W.query(seg)[0] < 20)
    pidx = {}  # place name -> list of node indices
    for p in places:
        if p["kind"] not in ("town", "landmark", "capital"): continue
        pm, X, Y = server(p["x"], p["y"])
        if pm != m: continue
        d, j = base_tree.query((X, Y))
        if d < 40:
            idx = int(j)
        else:
            near = base_tree.query_ball_point((X, Y), 300)
            near = sorted(near, key=lambda k: np.hypot(S[k][0] - X, S[k][1] - Y))[:4]
            near = [k for k in near if dry((X, Y), S[k])]
            if not near: continue
            z = S[near[0]][2]
            idx = len(S); S.append((X, Y, z)); L.append(0); added[m] += 1
            for k in near:
                E.append((k, idx)); R.append(2); links[m] += 1
        pidx.setdefault(p["name"], []).append(idx)
    # tunnels / passes with two ends: connect the ends
    for name, ids in pidx.items():
        if len(ids) == 2:
            a, b = ids
            if np.hypot(S[a][0] - S[b][0], S[a][1] - S[b][1]) < 1500:
                E.append((a, b)); R.append(2); links[m] += 1
                print(f"  map {m}: connected the two ends of {name}")
    N["S"] = np.array(S); N["pairs"] = np.array(E); N["road"] = np.array(R); N["lvl"] = np.array(L)
    print(f"map {m}: {added[m]} place points added, {links[m]} links")
pickle.dump(nav, open("nav_v4.pkl", "wb"))
