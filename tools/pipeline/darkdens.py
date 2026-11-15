import numpy as np, pickle, sys
from PIL import Image
from scipy.ndimage import gaussian_filter
from skimage.feature import hessian_matrix, hessian_matrix_eigvals
Image.MAX_IMAGE_PIXELS=None
h,w=np.load("land2.npy").shape
im=Image.open("world_full.png").convert("L")
L=np.asarray(im.resize((w,h),Image.BOX)).astype(np.float32)
H=hessian_matrix(L,sigma=1.0,order="rc",use_gaussian_derivatives=False)
e1,e2=hessian_matrix_eigvals(H)
dark=np.clip(e1,0,None)   # dark line: strongly positive eigenvalue
land=np.load("land2.npy")
dark=dark/np.percentile(dark[land],98)
dd=gaussian_filter(np.clip(dark,0,1),10)
np.save("darkdens2.npy",dd.astype(np.float16))
print(np.percentile(dd[land],[10,50,90]))
