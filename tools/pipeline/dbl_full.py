import numpy as np, sys
sys.path.insert(0,".")
from dbl_road import double_line
from PIL import Image
Image.MAX_IMAGE_PIXELS=None
im=np.asarray(Image.open("world_full.png").convert("L")).astype(np.float32)
H,W=im.shape; out=np.zeros((H,W),np.float32); T,P=1024,12
for y0 in range(0,H,T):
    for x0 in range(0,W,T):
        ya,yb,xa,xb=max(0,y0-P),min(H,y0+T+P),max(0,x0-P),min(W,x0+T+P)
        t=im[ya:yb,xa:xb]
        if t.max()<20: continue
        b=double_line(t)
        out[y0:min(H,y0+T),x0:min(W,x0+T)]=b[y0-ya:y0-ya+min(T,H-y0),x0-xa:x0-xa+min(T,W-x0)]
land=np.load("land2.npy")
h2,w2=H//2,W//2
o2=out[:h2*2,:w2*2].reshape(h2,2,w2,2).max((1,3))
o2=np.clip(o2/np.percentile(o2[land],97),0,1); o2[~land]=0
np.save("road_dbl2.npy",o2.astype(np.float16)); print("done")
