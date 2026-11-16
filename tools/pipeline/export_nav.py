import pickle, numpy as np, sqlite3, re
nav = pickle.load(open("nav_v4.pkl", "rb"))
c = sqlite3.connect("vdb/sqlite-dump/mangos.sqlite")
tn = {r[0]: (r[1], r[2], r[3]) for r in c.execute("select id, map_id, x, y from taxi_nodes")}
fd = open("/home/user/questroute/Data/Flights.lua").read()
ours = {int(m[0]): (int(m[1]), float(m[2]), float(m[3])) for m in re.findall(r'id = (\d+), name = "[^"]*", fac = \d+, cont = (\d+), x = ([\d.-]+), y = ([\d.-]+)', fd)}
B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
def enc3(v):
    assert 0 <= v < 262144, v
    return B64[v >> 12] + B64[(v >> 6) & 63] + B64[v & 63]
OFF, SCALE = 0.25, 131072.0
for mapid, cont, fname in ((0, 1415, "NavEK"), (1, 1414, "NavKalimdor")):
    pts = [(tn[i][1], tn[i][2], ours[i][1], ours[i][2]) for i in ours if i in tn and tn[i][0] == mapid and ours[i][0] == cont]
    P = np.array(pts)
    fx = np.polyfit(P[:, 1], P[:, 2], 1)  # cont_x from world y
    fy = np.polyfit(P[:, 0], P[:, 3], 1)  # cont_y from world x
    N = nav[mapid]; S = N["S"]
    cx = np.polyval(fx, S[:, 1]); cy = np.polyval(fy, S[:, 0])
    qx = np.round((cx + OFF) * SCALE).astype(int); qy = np.round((cy + OFF) * SCALE).astype(int)
    nodes = "".join(enc3(a) + enc3(b) for a, b in zip(qx, qy))
    edges = "".join(enc3(int(a)) + enc3(int(b)) + B64[int(r)] for (a, b), r in zip(N["pairs"], N["road"]))
    with open(f"/home/user/questroute/Data/{fname}.lua", "w") as f:
        f.write(f"-- Walkable-ground network for continent map {cont}: {len(S)} points, {len(N['pairs'])} links.\n")
        f.write("-- Built from the VMaNGOS classic world database (creature and object spawns, guard patrol routes);\n")
        f.write("-- see Data/NAV_README.txt. Coordinates are continent map coordinates, base64-packed.\n-- levels: typical level of the hostile monsters around each point (0 = none).\n")
        f.write("local _, ns = ...\nns.NavData = ns.NavData or {}\n")
        f.write(f"ns.NavData[{cont}] = {{ count = {len(S)}, links = {len(N['pairs'])},\n")
        f.write(f"nodes = \"{nodes}\",\n")
        f.write(f"edges = \"{edges}\",\n")
        lv = "".join(B64[int(v)] for v in N["lvl"])
        la = "".join(B64[int(v)] for v in N["lvlA"])
        lh = "".join(B64[int(v)] for v in N["lvlH"])
        f.write(f"levels = \"{lv}\",\n")
        f.write(f"levelsAlliance = \"{la}\",\n")
        f.write(f"levelsHorde = \"{lh}\",\n")
        full = pickle.load(open("nav_v4_full.pkl", "rb"))
        Wt = full[mapid]["water"]
        wx = np.polyval(fx, Wt[:, 1]); wy = np.polyval(fy, Wt[:, 0])
        keep = (wx > -0.2) & (wx < 1.7) & (wy > -0.2) & (wy < 1.7)
        ws = "".join(enc3(int(round((a + OFF) * SCALE))) + enc3(int(round((b + OFF) * SCALE))) for a, b in zip(wx[keep], wy[keep]))
        f.write(f"water = \"{ws}\" }}\n")
    print(fname, len(S), len(N["pairs"]), "range x", cx.min(), cx.max(), "y", cy.min(), cy.max())
