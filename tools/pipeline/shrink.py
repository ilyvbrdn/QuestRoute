import pickle, numpy as np, sys
CELL, ZC = float(sys.argv[1]), float(sys.argv[2])
FACT = {0: 1.25, 1: 1.0, 2: 1.6, 3: 2.5}
nav = pickle.load(open("nav_v4_full.pkl", "rb"))
for mapid in (0, 1):
    N = nav[mapid]; S = N["S"]; E = N["pairs"]; R = N["road"]
    key = np.stack([np.floor(S[:, 0] / CELL), np.floor(S[:, 1] / CELL), np.floor(S[:, 2] / ZC)], 1).astype(np.int64)
    _, inv = np.unique(key, axis=0, return_inverse=True); inv = inv.ravel(); n = inv.max() + 1
    S2 = np.zeros((n, 3)); cnt = np.zeros(n); np.add.at(S2, inv, S); np.add.at(cnt, inv, 1); S2 /= cnt[:, None]
    best = {}
    for (a, b), r in zip(E, R):
        A, B = inv[a], inv[b]
        if A == B: continue
        k = (min(A, B), max(A, B))
        if k not in best or FACT[r] < FACT[best[k]]: best[k] = r
    N["S"] = S2; N["pairs"] = np.array(list(best.keys())); N["road"] = np.array(list(best.values()))
    print(f"map {mapid}: {len(S)} -> {n} nodes, {len(E)} -> {len(best)} links")
pickle.dump(nav, open("nav_v4.pkl", "wb"))
