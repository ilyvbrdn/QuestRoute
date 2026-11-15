# Trace the roads drawn on the map art between known places; keep paths that stay on drawn roads.
import pickle, json, sqlite3, numpy as np, sys
from scipy.spatial import cKDTree
from scipy.ndimage import gaussian_filter
from skimage.graph import MCP_Geometric
r2=np.load("road_r2.npy").astype(np.float32); land2=np.load("land2.npy")
cal=pickle.load(open("imgcal5.pkl","rb")); full=pickle.load(open("nav_v4_full.pkl","rb"))
places=json.load(open("wh/places.json"))
CONT=[("kalimdor",1,0,0,0,0),("zephras",2991,24576,8192,21,22),("ek",0,32768,8192,23,20)]
def server(cx,cy):
    for key,m,x0,y0,oc,orow in sorted(CONT,key=lambda c:c[2],reverse=True):
        if cx>=x0:
            col=oc+(cx-x0)/512.0; row=orow+(cy-y0)/512.0
            return m,(32-row)*533.3333,(32-col)*533.3333
DS=2
def toimg(m,sx,sy):
    c=cal[m]; return (c["ax"]*sy+c["bx"]+c["dx"])/DS,(c["ay"]*sx+c["by"]+c["dy"])/DS
def toserver(m,X,Y):
    c=cal[m]; return (Y*DS-c["by"]-c["dy"])/c["ay"], (X*DS-c["bx"]-c["dx"])/c["ax"]
YDPX=DS/abs(cal[0]["ax"])   # yards per half-res pixel (~5.6)
ON=0.30                 # roadness counted as "on a drawn road"
c=sqlite3.connect("vdb/sqlite-dump/mangos.sqlite")
out={}
import sys
MAPS=[int(a) for a in sys.argv[1:]] or [0,1]
for m in MAPS:
    pts=[]
    for p in places:
        if p["kind"] in ("zone",): continue
        pm,X,Y=server(p["x"],p["y"])
        if pm==m: pts.append((X,Y,p["name"]))
    for i,mid,x,y,name in c.execute("select id,map_id,x,y,name from taxi_nodes"):
        if mid==m: pts.append((x,y,"FP "+str(name)))
    P=np.array([(a,b) for a,b,_ in pts])
    XY=np.array([toimg(m,a,b) for a,b in P])
    # crop region
    x0,y0=np.floor(XY.min(0)-200).astype(int); x1,y1=np.ceil(XY.max(0)+200).astype(int)
    x0,y0=max(x0,0),max(y0,0); x1,y1=min(x1,r2.shape[1]),min(y1,r2.shape[0])
    rr=gaussian_filter(r2[y0:y1,x0:x1],0.7); ll=land2[y0:y1,x0:x1]
    rr=np.clip(rr/np.percentile(rr[ll],98),0,1)
    cost=0.2+3.0*(1-rr)**3
    cost[~ll]=np.inf
    loc=np.round(XY-[x0,y0]).astype(int)
    ok=(loc[:,0]>=0)&(loc[:,1]>=0)&(loc[:,0]<x1-x0)&(loc[:,1]<y1-y0)
    tree=cKDTree(P)
    paths=[]; tried=0
    for i in range(len(P)):
        if not ok[i]: continue
        nb=[j for j in tree.query_ball_point(P[i],1800) if j>i and ok[j] and np.hypot(*(P[i]-P[j]))>150]
        if not nb: continue
        si=(loc[i,1],loc[i,0])
        if not np.isfinite(cost[si]): continue
        mcp=MCP_Geometric(cost,fully_connected=True)
        maxd=max(np.hypot(*(P[i]-P[j])) for j in nb)/YDPX
        mcp.find_costs([si],max_cumulative_cost=maxd*1.6*0.6+40)
        for j in nb:
            tj=(loc[j,1],loc[j,0]); tried+=1
            try: path=np.array(mcp.traceback(tj))
            except Exception: continue
            if len(path)<3: continue
            seg=np.hypot(*np.diff(path,axis=0).T).sum()*YDPX
            straight=np.hypot(*(P[i]-P[j]))
            if seg>1.5*straight+150: continue
            onr=(rr[path[:,0],path[:,1]]>ON).mean()
            if onr<0.80: continue
            paths.append((path+[y0,x0],onr,pts[i][2],pts[j][2]))
        if i%50==0: print(m,i,len(P),len(paths),file=sys.stderr)
    print(f"map {m}: {len(P)} places, {tried} pairs tried, {len(paths)} road paths kept")
    out[m]=paths
pickle.dump(out,open("traced_%s.pkl" % "_".join(map(str,MAPS)),"wb"))
