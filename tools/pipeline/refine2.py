import pickle, numpy as np
from scipy.ndimage import map_coordinates
from scipy.optimize import minimize
ridge=np.load("ridge.npy").astype(np.float32)
from scipy.ndimage import gaussian_filter
nav=pickle.load(open("nav_v4_full.pkl","rb")); cal=pickle.load(open("imgcal2.pkl","rb"))
out={}
for m in (0,1):
    c=cal[m]; P=nav[m]["S"]; E=nav[m]["pairs"][nav[m]["road"]>0]
    pts=[]
    for a,b in E:
        d=np.hypot(*(P[a,:2]-P[b,:2]))
        if d<15: continue
        for t in np.linspace(0,1,int(d//6)+2)[1:-1]: pts.append(P[a,:2]*(1-t)+P[b,:2]*t)
    pts=np.array(pts); u=-pts[:,1]; v=-pts[:,0]
    mu,mv=u.mean(),v.mean()
    p=np.array([c["A"],c["A"],c["A"]*mu+c["Bx"],c["A"]*mv+c["By"]])  # sx, sy, X at mean, Y at mean
    best=None
    for sigma in (6,3,1.5):
        R=gaussian_filter(ridge,sigma) if sigma>1.5 else ridge
        f=lambda q: -map_coordinates(R,[q[1]*(v-mv)+q[3], q[0]*(u-mu)+q[2]],order=1).mean()
        # coarse grid on scales then NM
        g=None
        for sx in p[0]*np.linspace(0.95,1.05,11):
            for sy in p[1]*np.linspace(0.95,1.05,11):
                q=np.array([sx,sy,p[2],p[3]]); val=f(q)
                if g is None or val<g[0]: g=(val,q)
        r=minimize(f,g[1],method="Nelder-Mead",options=dict(initial_simplex=np.array([g[1],g[1]+[0.003,0,0,0],g[1]+[0,0.003,0,0],g[1]+[0,0,20,0],g[1]+[0,0,0,20]]),maxiter=600,xatol=1e-3,fatol=1e-5))
        p=r.x; print(m,sigma,-r.fun,p)
    sx,sy,X0,Y0=p
    out[m]=dict(Ax=sx,Ay=sy,Bx=X0-sx*mu,By=Y0-sy*mv)
    print(m,out[m], "ratio", sx/sy)
pickle.dump(out,open("imgcal3.pkl","wb"))
