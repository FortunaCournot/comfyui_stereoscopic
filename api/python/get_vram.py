import GPUtil

gpus = GPUtil.getGPUs()

if not gpus:
    print("0")
else:
    for i, gpu in enumerate(gpus):
        gb = int( (gpu.memoryTotal + 512) / 1024 )
        print(f"{gb}")
        break
  
