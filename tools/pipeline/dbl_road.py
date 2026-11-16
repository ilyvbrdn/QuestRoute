# Roads drawn as two thin dark lines with a lighter strip between them.
import numpy as np
from skimage.feature import hessian_matrix, hessian_matrix_eigvals
from scipy.ndimage import map_coordinates
def double_line(L):
    D=np.clip(hessian_matrix_eigvals(hessian_matrix(L,sigma=0.9,order="rc",use_gaussian_derivatives=False))[0],0,None)
    best=np.zeros_like(L)
    for s,off in ((1.4,(2.0,2.5,3.0)),(2.0,(3.0,3.5,4.5))):
        Hrr,Hrc,Hcc=hessian_matrix(L,sigma=s,order="rc",use_gaussian_derivatives=False)
        # eigenvector of the most negative eigenvalue (across a bright ridge)
        tmp=np.sqrt(((Hrr-Hcc)/2)**2+Hrc**2); lam=(Hrr+Hcc)/2-tmp
        nr=Hrc; nc=lam-Hrr
        bad=(np.abs(nr)+np.abs(nc))<1e-9
        nr=np.where(bad,1.0,nr); nc=np.where(bad,0.0,nc)
        nn=np.hypot(nr,nc); nr/=nn; nc/=nn
        rows,cols=np.indices(L.shape).astype(np.float32)
        ridge=np.clip(-lam,0,None)*s*s
        side=np.zeros_like(L)
        for o in off:
            a=map_coordinates(D,[rows+nr*o,cols+nc*o],order=1,mode="nearest")
            b=map_coordinates(D,[rows-nr*o,cols-nc*o],order=1,mode="nearest")
            side=np.maximum(side,np.minimum(a,b))
        best=np.maximum(best,np.sqrt(ridge*side))
    return best
