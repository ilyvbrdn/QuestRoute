# Inside capitals and towns every street is walkable: count their ground links as roads, so the
# "prefer roads" setting doesn't send routes round the outside of a city.
import json, pickle, numpy as np
nav=pickle.load(open("nav_v4.pkl","rb")); places=json.load(open("wh/places.json"))
CONT=[("kalimdor",1,0,0,0,0),("zephras",2991,24576,8192,21,22),("ek",0,32768,8192,23,20)]
def server(cx,cy):
    for key,m,x0,y0,oc,orow in sorted(CONT,key=lambda c:c[2],reverse=True):
        if cx>=x0:
            col=oc+(cx-x0)/512.0; row=orow+(cy-y0)/512.0
            return m,(32-row)*533.3333,(32-col)*533.3333
for m in (0,1):
    N=nav[m]; S=N["S"]; E=N["pairs"]; R=N["road"].copy()
    inside=np.zeros(len(S),bool); n_areas=0
    for p in places:
        if p["kind"] not in ("capital","town"): continue
        pm,X,Y=server(p["x"],p["y"])
        if pm!=m: continue
        if p["kind"]=="capital" and p.get("rect"):
            (ax,ay),(bx,by)=p["rect"]; m1,X1,Y1=server(ax,ay); m2,X2,Y2=server(bx,by)
            lo=np.minimum([X1,Y1],[X2,Y2]); hi=np.maximum([X1,Y1],[X2,Y2])
            inside|=np.all((S[:,:2]>=lo)&(S[:,:2]<=hi),axis=1)
        else:
            inside|=np.hypot(S[:,0]-X,S[:,1]-Y)<180
        n_areas+=1
    sel=inside[E[:,0]]&inside[E[:,1]]&(R==0)
    R[sel]=1; N["road"]=R
    print(f"map {m}: {n_areas} towns and capitals, {sel.sum()} street links now count as roads")
pickle.dump(nav,open("nav_v4.pkl","wb"))
