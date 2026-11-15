import pickle, numpy as np
from PIL import Image
from scipy.optimize import minimize
nav=pickle.load(open("nav_v4_full.pkl","rb"))
big=Image.open("world_full.png").convert("RGB")
F=24  # coarse cell
im=np.asarray(big.resize((big.width//F,big.height//F),Image.BOX)).astype(int)
land=im.sum(2)>60; H,W=land.shape
res={}
for m,(xa,xb) in ((1,(0,W//2)),(0,(W//2,W))):
    P=nav[m]["S"]
    u=-P[:,1]; v=-P[:,0]   # image right = -serverY, image down = -serverX
    sub=land.copy(); sub[:,:xa]=False; sub[:,xb:]=False
    ys,xs=np.nonzero(sub)
    lo_u,hi_u=np.percentile(u,[0.5,99.5]); lo_v,hi_v=np.percentile(v,[0.5,99.5])
    s0=(np.percentile(xs,99)-np.percentile(xs,1))/(hi_u-lo_u)
    def place(p):
        s,bx,by=p
        return ((u-lo_u)*s+bx),((v-lo_v)*s+by)
    def score(p):
        X,Y=place(p); X=X.astype(int); Y=Y.astype(int)
        ok=(X>=0)&(X<W)&(Y>=0)&(Y<H)
        occ=np.zeros_like(sub); occ[Y[ok],X[ok]]=True
        inter=(occ&sub).sum(); uni=(occ|sub).sum()
        return -(inter/uni) - 0.5*sub[Y[ok],X[ok]].mean() + (1-ok.mean())*5
    best=None
    for sf in (0.85,0.95,1.05,1.15):
        for dx in (-20,-10,0,10,20):
            for dy in (-20,-10,0,10,20):
                p0=[s0*sf,np.percentile(xs,1)+dx,np.percentile(ys,1)+dy]
                sc=score(p0)
                if best is None or sc<best[0]: best=(sc,p0)
    r=minimize(score,best[1],method="Nelder-Mead",options=dict(xatol=1e-4,fatol=1e-6,maxiter=2000,initial_simplex=None))
    s,bx,by=r.x
    print(m,"score",-r.fun,"s",s*0+s,"px/yd full:",s/F)
    res[m]=dict(s=s/F*1.0, bx=bx*F - lo_u*s/F*F/ F*0, lo_u=lo_u, lo_v=lo_v, bxF=bx, byF=by, F=F)
pickle.dump(res,open("imgcal.pkl","wb"))
