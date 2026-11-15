import pickle, numpy as np
from scipy.ndimage import map_coordinates, gaussian_filter
from PIL import Image, ImageDraw
Image.MAX_IMAGE_PIXELS=None
Z=pickle.load(open("zones.pkl","rb")); w=pickle.load(open("w947.pkl","rb"))
byname={z["name"]:z for z in Z.values()}
nav=pickle.load(open("nav_v4_before_roads.pkl","rb"))
ridge=np.load("ridge.npy").astype(np.float32); R3=gaussian_filter(ridge,2)
def lin(zname):
    z=byname[zname]
    # img = ax*(sy) + bx ; img_y = ay*(sx) + by
    ax=w["B"]*(z["r"]-z["l"])/(z["y1"]-z["y0"]); bx=w["A"]+w["B"]*z["l"]-ax*z["y0"]
    ay=w["D"]*(z["b"]-z["t"])/(z["x1"]-z["x0"]); by=w["C"]+w["D"]*z["t"]-ay*z["x0"]
    return ax,bx,ay,by
out={}
for inst,zn in ((0,"Elwynn Forest"),(1,"Ashenvale")):
    ax,bx,ay,by=lin(zn)
    N=nav[inst]; P=N["S"]; E=N["pairs"][N["road"]==1]
    pts=[]
    for a,b in E:
        d=np.hypot(*(P[a,:2]-P[b,:2]))
        for t in np.linspace(0,1,max(2,int(d//8)+1)): pts.append(P[a,:2]*(1-t)+P[b,:2]*t)
    pts=np.array(pts)
    def score(dx,dy,s,R):
        X=(ax*pts[:,1]+bx)*s+dx; Y=(ay*pts[:,0]+by)*s+dy
        return map_coordinates(R,[Y,X],order=1).mean()
    if inst==0:
        print("EK zero-shift score",score(0,0,1,ridge)); out[0]=dict(ax=ax,bx=bx,ay=ay,by=by,dx=0,dy=0,s=1); continue
    best=(score(-240,-16,1,R3),-240,-16,1)
    for st,rng,srng in ((8,80,0.02),(2,10,0.004),(0.5,2,0.001)):
        b=best
        for s in np.linspace(b[3]-srng,b[3]+srng,5):
            # scale about the image centre of Kalimdor
            for dx in np.arange(b[1]-rng,b[1]+rng+1e-9,st):
                for dy in np.arange(b[2]-rng,b[2]+rng+1e-9,st):
                    v=score(dx,dy,s,R3 if st>2 else ridge)
                    if v>best[0]: best=(v,dx,dy,s)
        print(best)
    _,dx,dy,s=best
    out[1]=dict(ax=ax,bx=bx,ay=ay,by=by,dx=dx,dy=dy,s=s)
pickle.dump(out,open("imgcal4.pkl","wb"))
c=out[1]
def toimg(sx,sy): return (c["ax"]*sy+c["bx"])*c["s"]+c["dx"], (c["ay"]*sx+c["by"])*c["s"]+c["dy"]
big=Image.open("world_full.png").convert("RGB")
X,Y=toimg(2828.38,-284.25)
crop=big.crop((int(X-300),int(Y-300),int(X+300),int(Y+300))); d=ImageDraw.Draw(crop)
for sx,sy,col in ((2828.38,-284.25,(0,0,255)),(2781.16,-432.99,(255,0,0))):
    a,b=toimg(sx,sy); d.ellipse((a-X+300-5,b-Y+300-5,a-X+300+5,b-Y+300+5),fill=col)
crop.resize((600,600)).save("astr_check2.png")
