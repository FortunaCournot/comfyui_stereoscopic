import cv2
import numpy as np
import sys

print("python:", sys.executable)
print("cv2.__version__:", cv2.__version__)
try:
    bi = cv2.getBuildInformation()
    print("cv2.getBuildInformation() first line:", bi.splitlines()[0])
except Exception as e:
    print("getBuildInformation() failed:", repr(e))

# helper
def try_umat(arr, name):
    try:
        print(f"Trying UMat creation for {name}, nbytes={arr.nbytes}")
        u = cv2.UMat(arr)
        print(f"UMat {name} created: {type(u)}")
        try:
            r = cv2.resize(u, dsize=(max(1, arr.shape[1]//2), max(1, arr.shape[0]//2)), interpolation=cv2.INTER_LINEAR)
            print(f"resize UMat {name} ok, result type: {type(r)}")
        except Exception as e:
            print(f"resize UMat {name} failed:", repr(e))
    except Exception as e:
        print(f"UMat {name} creation failed:", repr(e))

# small
# small
small = np.zeros((100,100,3), dtype=np.uint8)
print("small nbytes:", small.nbytes)
try_umat(small, 'small')

# medium
# medium
med = np.zeros((1000,1000,3), dtype=np.uint8)
print("med nbytes:", med.nbytes)
try_umat(med, 'med')

# large (approx 48 MB at 4000x4000)
# large (approx 48 MB at 4000x4000)
large = np.zeros((4000,4000,3), dtype=np.uint8)
print("large nbytes:", large.nbytes)
try_umat(large, 'large')

# final: cpu resize test
try:
    r = cv2.resize(large, dsize=(2000,2000), interpolation=cv2.INTER_LINEAR)
    print("cv2.resize numpy large OK, shape:", r.shape)
except Exception as e:
    print("cv2.resize numpy large failed:", repr(e))

print("DONE")
