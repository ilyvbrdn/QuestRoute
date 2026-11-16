# Add the traced map roads to the nav network (after connectors.py, before levels.py).
import pickle, numpy as np
from scipy.spatial import cKDTree
from skimage.morphology import skeletonize, binary_dilation, disk
nav=pickle.load(open("nav_v4.pkl","rb")); full=pickle.load(open("nav_v4_full.pkl","rb"))
import os
traced={0:pickle.load(open("traced.pkl","rb"))[0], 1:pickle.load(open("traced_1.pkl","rb"))[1]}
for m in (0,1):
    f="traced_dbl_%d.pkl" % m
    if os.path.exists(f): traced[m]=traced[m]+pickle.load(open(f,"rb"))[m]   # (both tracings: the filter picks); cal=pickle.load(open("imgcal5.pkl","rb"))
r2shape=np.load("land2.npy").shape
DS=2
def toserver(m,X,Y):
    c=cal[m]; return (Y*DS-c["by"]-c["dy"])/c["ay"], (X*DS-c["bx"]-c["dx"])/c["ax"]
STEP=4   # half-res px between nodes (~22 yd)
import sys
RMIN,DMAX=float(sys.argv[1]),float(sys.argv[2])
ALL_ROADS=len(sys.argv)>3 and sys.argv[3]=='all'
r2=np.load("road_r2.npy").astype(np.float32); land2=np.load("land2.npy")
BL=np.load("blu2.npy").astype(np.float32)
BD=np.load("road_dbl2.npy").astype(np.float32)
BMIN=float(os.environ.get("BMIN","0.45"))
base_nav=pickle.load(open("nav_v4_before_roads.pkl","rb"))
rn=np.clip(r2/np.percentile(r2[land2],98),0,1); DD=np.load("darkdens2.npy").astype(np.float32)
for m in (0,1):
    paths=[]
    BT=cKDTree(base_nav[m]["S"][:,:2])
    # the existing network as a graph (walking cost), to see where a drawn road is a real shortcut
    from scipy.sparse import coo_matrix
    from scipy.sparse.csgraph import dijkstra
    BS=base_nav[m]["S"]; BE=base_nav[m]["pairs"]; BK=base_nav[m]["road"]
    BW=np.hypot(*(BS[BE[:,0],:2]-BS[BE[:,1],:2]).T)*np.where(BK==1,1.0,1.6)
    nB=len(BS); BG=coo_matrix((np.r_[BW,BW],(np.r_[BE[:,0],BE[:,1]],np.r_[BE[:,1],BE[:,0]])),shape=(nB,nB)).tocsr()
    shortcut_runs=0
    for path,onr,a,b in traced[m]:
        if len(path)<16: continue
        k=np.ones(15)/15
        rm=np.convolve(rn[path[:,0],path[:,1]],k,"same"); dm=np.convolve(DD[path[:,0],path[:,1]],k,"same")
        bm=np.convolve(BL[path[:,0],path[:,1]],k,"same")
        bdm=np.convolve(BD[path[:,0],path[:,1]],k,"same")
        good=((rm>=RMIN)&(dm<=DMAX)&(bm<0.2)) | ((bdm>=BMIN)&(bm<0.2))   # a bright road, or a drawn double-line road
        # fill short gaps that are still fairly road-like
        n=len(good); t=0
        while t<n:
            if not good[t]:
                u=t
                while u<n and not good[u]: u+=1
                if t>0 and u<n and u-t<=14 and rm[t:u].mean()>=0.5 and dm[t:u].max()<=DMAX+0.05: good[t:u]=True
                t=u
            else: t+=1
        start=None
        for t,g in enumerate(list(good)+[False]):
            if g and start is None: start=t
            if not g and start is not None:
                if t-start>=25:
                    q=path[start:t:3]; gx,gy=toserver(m,q[:,1].astype(float),q[:,0].astype(float))
                    if ALL_ROADS or (BT.query(np.c_[gx,gy])[0]>60).mean()>=0.4: paths.append((path[start:t],onr,a,b))
                    else:
                        # covered by spawns, but is the network missing this road? compare the walk between its ends
                        L=np.hypot(np.diff(gx),np.diff(gy)).sum()
                        if L>=120:
                            d0,i0=BT.query((gx[0],gy[0])); d1,i1=BT.query((gx[-1],gy[-1]))
                            if d0<60 and d1<60:
                                g=dijkstra(BG,indices=int(i0),limit=2.2*L)[int(i1)]
                                if not np.isfinite(g) or g>1.8*L:
                                    paths.append((path[start:t],onr,a,b)); shortcut_runs+=1
                start=None
    print(f"map {m}: {len(paths)} strong road runs ({shortcut_runs} where the network goes far around)")
    if not paths: continue
    mask=np.zeros(r2shape,bool)
    for path,onr,a,b in paths: mask[path[:,0],path[:,1]]=True
    ys,xs=np.nonzero(mask); y0,y1,x0,x1=ys.min()-3,ys.max()+4,xs.min()-3,xs.max()+4
    sub=binary_dilation(mask[y0:y1,x0:x1],disk(1))
    sk=skeletonize(sub)
    # graph on skeleton pixels; keep every pixel, then thin to nodes STEP apart along chains
    py,px=np.nonzero(sk); idx=-np.ones(sk.shape,int); idx[py,px]=np.arange(len(py))
    nbrs=[[] for _ in range(len(py))]
    for dy in (-1,0,1):
        for dx in (-1,0,1):
            if dy==0 and dx==0: continue
            qy,qx=py+dy,px+dx
            okk=(qy>=0)&(qx>=0)&(qy<sk.shape[0])&(qx<sk.shape[1])
            j=np.full(len(py),-1); j[okk]=idx[qy[okk],qx[okk]]
            for a in np.nonzero(j>=0)[0]: nbrs[a].append(j[a])
    deg=np.array([len(n) for n in nbrs])
    keep=np.zeros(len(py),bool); keep[deg!=2]=True
    # walk chains, keep every STEP-th pixel
    seen=set(); edges=[]
    for s in np.nonzero(keep)[0]:
        for n0 in nbrs[s]:
            if (s,n0) in seen: continue
            prev,cur,run,last=s,n0,1,s
            chain=[s]
            while True:
                seen.add((prev,cur)); seen.add((cur,prev))
                if keep[cur]:
                    edges.append((last,cur)); break
                if run%STEP==0:
                    keep[cur]=True; edges.append((last,cur)); last=cur
                nx=[q for q in nbrs[cur] if q!=prev]
                if not nx: keep[cur]=True; edges.append((last,cur)); break
                prev,cur=cur,nx[0]; run+=1
    # loops with no junction are ignored (rare)
    ids=np.nonzero(keep)[0]; new_of={int(k):i for i,k in enumerate(ids)}
    sx,sy=toserver(m,px[ids]+x0,py[ids]+y0)
    NP=np.c_[sx,sy]
    E=set()
    for a,b in edges:
        if a==b: continue
        A,B=new_of[int(a)],new_of[int(b)]
        E.add((min(A,B),max(A,B)))
    # drop nodes in water (next to fishing pools / swimmers)
    W=cKDTree(full[m]["water"]); wet=W.query(NP)[0]<10
    N=nav[m]; S0=N["S"]; base=len(S0)
    T=cKDTree(S0[:,:2]); dd,jj=T.query(NP)
    z=S0[jj,2]
    S=np.vstack([S0,np.c_[NP,z]])
    pairs=list(map(tuple,N["pairs"])); road=list(N["road"])
    add=0
    for A,B in E:
        if wet[A] or wet[B]: continue
        pairs.append((base+A,base+B)); road.append(1); add+=1
    # join to the existing network
    join=0
    tdeg=np.zeros(len(NP),int)
    for A,B in E: tdeg[A]+=1; tdeg[B]+=1
    for A in range(len(NP)):
        if wet[A]: continue
        near=T.query_ball_point(NP[A],25)
        if not near and tdeg[A]<=1:
            # a road end: reach the network a little further (dry links only)
            dd,kk=T.query(NP[A],k=3,distance_upper_bound=80)
            for d_,k_ in zip(np.atleast_1d(dd),np.atleast_1d(kk)):
                if not np.isfinite(d_): continue
                seg=NP[A][None]*(1-np.linspace(0,1,8)[:,None])+S0[k_,:2][None]*np.linspace(0,1,8)[:,None]
                if np.all(W.query(seg)[0]>=20): near.append(int(k_))
        for k in near:
            pairs.append((k,base+A)); road.append(0); join+=1
    # road ends: bridge a gap (up to 220 yd) to another point when the map shows road along the way
    c=cal[m]
    def img(sx,sy): return (c["ax"]*sy+c["bx"]+c["dx"])/DS,(c["ay"]*sx+c["by"]+c["dy"])/DS
    ALL=np.vstack([S0[:,:2],NP]); AT=cKDTree(ALL)
    # neighbours of each traced point along its own chain (not to be "bridged" to)
    adjT=[set() for _ in range(len(NP))]
    for A,B in E: adjT[A].add(B); adjT[B].add(A)
    bridged=0
    for A in range(len(NP)):
        if wet[A] or tdeg[A]>1: continue
        # points of its own chain within reach: walk a few steps back
        own={A}; frontier=[A]
        for _ in range(12):
            frontier=[q for f in frontier for q in adjT[f] if q not in own]; own.update(frontier)
        best=[]
        for k in AT.query_ball_point(NP[A],220):
            if k>=len(S0) and (k-len(S0)) in own: continue
            q=ALL[k]; d=np.hypot(*(q-NP[A]))
            if d<20: continue
            ts=np.linspace(0,1,max(4,int(d//6)))
            seg=NP[A][None]*(1-ts[:,None])+q[None]*ts[:,None]
            if np.any(W.query(seg)[0]<20): continue
            X,Y=img(seg[:,0],seg[:,1]); X=np.clip(X.astype(int),0,rn.shape[1]-1); Y=np.clip(Y.astype(int),0,rn.shape[0]-1)
            # (a 3x3 neighbourhood: the road line is thin)
            rr=np.max([rn[np.clip(Y+dy,0,rn.shape[0]-1),np.clip(X+dx,0,rn.shape[1]-1)] for dy in (-1,0,1) for dx in (-1,0,1)],axis=0)
            if rr.mean()>=0.5 and (rr>0.3).mean()>=0.8: best.append((d,k))
        best.sort()
        for d,k in best[:2]:
            kk=k if k<len(S0) else base+(k-len(S0))
            pairs.append((kk,base+A)); road.append(0); bridged+=1
    print(f"map {m}: {bridged} road gaps bridged along the drawn road")
    # (lvl arrays are rebuilt by levels.py)
    N["S"]=S; N["pairs"]=np.array(pairs); N["road"]=np.array(road)
    for key in ("lvl","lvlA","lvlH"):
        if key in N: N[key]=np.concatenate([N[key],np.zeros(len(NP),N[key].dtype)])
    print(f"map {m}: {len(paths)} traced paths -> {len(NP)} road points, {add} road links, {join} joins, {wet.sum()} wet points dropped")
pickle.dump(nav,open("nav_v4.pkl","wb"))
