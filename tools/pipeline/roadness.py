# road-likeness of every pixel of the stitched map (half resolution), per continent
import pickle, numpy as np
from PIL import Image
from skimage.feature import hessian_matrix, hessian_matrix_eigvals
Image.MAX_IMAGE_PIXELS=None
im=np.asarray(Image.open("world_full.png").convert("RGB")).astype(np.float32)
L=im.mean(2)
Hh,Ww=L.shape
R=np.zeros_like(L)
T,P=2048,16
for y0 in range(0,Hh,T):
    for x0 in range(0,Ww,T):
        ya,yb,xa,xb=max(0,y0-P),min(Hh,y0+T+P),max(0,x0-P),min(Ww,x0+T+P)
        t=L[ya:yb,xa:xb]
        if t.max()<20: continue
        best=np.zeros_like(t)
        for s in (1.2,1.8):
            H=hessian_matrix(t,sigma=s,order="rc",use_gaussian_derivatives=False)
            e1,e2=hessian_matrix_eigvals(H)
            best=np.maximum(best,np.clip(-e2,0,None)*s*s)
        R[y0:min(Hh,y0+T),x0:min(Ww,x0+T)]=best[y0-ya:y0-ya+min(T,Hh-y0),x0-xa:x0-xa+min(T,Ww-x0)]
land=im.sum(2)>90
p99=np.percentile(R[land],99)
r=np.clip(R/p99,0,1)
r[~land]=0
# half resolution, keeping thin roads (max pool)
h2,w2=Hh//2,Ww//2
r2=r[:h2*2,:w2*2].reshape(h2,2,w2,2).max((1,3))
land2=land[:h2*2,:w2*2].reshape(h2,2,w2,2).mean((1,3))>0.5
np.save("road_r2.npy",r2.astype(np.float16)); np.save("land2.npy",land2)
# saturation (to tell water / snow from land), half res
mx=im.max(2); mn=im.min(2); sat=np.where(mx>0,(mx-mn)/np.maximum(mx,1),0)
sat2=sat[:h2*2,:w2*2].reshape(h2,2,w2,2).mean((1,3))
np.save("sat2.npy",sat2.astype(np.float16))
print("done",r2.shape,p99)
