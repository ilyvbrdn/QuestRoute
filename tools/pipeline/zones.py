import re, pickle, numpy as np
txt=open("/root/.claude/uploads/72b3e70d-394a-57dc-93ff-3d73c6e4caa0/958e86b8-QuestRoute.lua").read()
zones={}
for blk in re.finditer(r'\{\s*\["type"\] = (\d+),\s*\["name"\] = "([^"]*)",(.*?)\["id"\] = (\d+),(.*?)\n\},', txt, re.S):
    typ,name,mid,rest=int(blk.group(1)),blk.group(2),int(blk.group(4)),blk.group(3)+blk.group(5)
    w=re.search(r'\["world"\] = \{\s*([-\d.e]+),\s*([-\d.e]+),\s*([-\d.e]+),\s*([-\d.e]+),\s*([-\d.e]+),',rest)
    o=re.search(r'\["onWorld"\] = \{\s*([-\d.e]+),\s*([-\d.e]+),\s*([-\d.e]+),\s*([-\d.e]+),',rest)
    p=re.search(r'\["parent"\] = (\d+)',rest)
    if w and o:
        zones[mid]=dict(name=name,type=typ,parent=int(p.group(1)) if p else None,inst=int(float(w.group(1))),
            x0=float(w.group(2)),y0=float(w.group(3)),x1=float(w.group(4)),y1=float(w.group(5)),
            l=float(o.group(1)),r=float(o.group(2)),t=float(o.group(3)),b=float(o.group(4)))
pickle.dump(zones,open("zones.pkl","wb"))
print(len(zones),"maps with placement")
for z in zones.values(): 
    if z["type"]<=3: print(z["type"], z["name"], z["inst"])
