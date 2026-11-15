import pickle, numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter, map_coordinates
Image.MAX_IMAGE_PIXELS=None
im=np.asarray(Image.open("world_full.png").convert("L")).astype(np.float32)
ridge=np.clip(im-gaussian_filter(im,4),0,None); ridge=gaussian_filter(ridge,1.2)
np.save("ridge.npy",ridge.astype(np.float16))
nav=pickle.load(open("nav_v4_full.pkl","rb")); cal=pickle.load(open("imgcal.pkl","rb"))
out={}
for m in (0,1):
    c=cal[m]; F=c["F"]; s0=c["s"]*F
    P=nav[m]["S"]; E=nav[m]["pairs"][nav[m]["road"]>0]
    pts=[]
    for a,b in E:
        d=np.hypot(*(P[a,:2]-P[b,:2]))
        if d<15: continue
        for t in np.linspace(0,1,int(d//6)+2)[1:-1]: pts.append(P[a,:2]*(1-t)+P[b,:2]*t)
    pts=np.array(pts); u=-pts[:,1]-c["lo_u"]; v=-pts[:,0]-c["lo_v"]
    def sc(s,ox,oy):
        X=(u*s+c["bxF"])*F+ox; Y=(v*s+c["byF"])*F+oy
        return map_coordinates(ridge,[Y,X],order=1,mode="constant").mean()
    best=(sc(s0,0,0),s0,0,0); print(m,"start",best[0],len(pts))
    for rng,st,srng in ((60,4,0.03),(10,1,0.006),(3,0.5,0.0015)):
        b=best
        for s in np.linspace(b[1]*(1-srng),b[1]*(1+srng),7):
            for ox in np.arange(b[2]-rng,b[2]+rng+1e-9,st):
                for oy in np.arange(b[3]-rng,b[3]+rng+1e-9,st):
                    v_=sc(s,ox,oy)
                    if v_>best[0]: best=(v_,s,ox,oy)
        print(m,best)
    _,s,ox,oy=best
    # final transform: img = A*(-sy)+B, img_y = A*(-sx)+C
    A=s*F
    out[m]=dict(A=A, Bx=(-c["lo_u"]*s+c["bxF"])*F+ox, By=(-c["lo_v"]*s+c["byF"])*F+oy)
    print(m,out[m])
pickle.dump(out,open("imgcal2.pkl","wb"))
