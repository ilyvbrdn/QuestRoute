# Quest legs for the route test: giver -> objective (nearest required creature) -> turn-in. From the VMaNGOS world DB.
import sqlite3, numpy as np
from collections import defaultdict
c=sqlite3.connect("vdb/sqlite-dump/mangos.sqlite")
spawns=defaultdict(list)
for cid,m,x,y in c.execute("select id,map,position_x,position_y from creature where map in (0,1)"): spawns[("c",cid)].append((m,x,y))
for gid,m,x,y in c.execute("select id,map,position_x,position_y from gameobject where map in (0,1)"): spawns[("g",gid)].append((m,x,y))
givers=defaultdict(list); enders=defaultdict(list)
for t,k,dst in (("creature_questrelation","c",givers),("gameobject_questrelation","g",givers),("creature_involvedrelation","c",enders),("gameobject_involvedrelation","g",enders)):
    for i,q in c.execute(f"select id,quest from {t}"): dst[q].append((k,i))
Q={}
for row in c.execute("select entry,QuestLevel,MinLevel,RequiredRaces,Title,ReqCreatureOrGOId1,ReqCreatureOrGOId2,ReqCreatureOrGOId3,ReqCreatureOrGOId4 from quest_template"):
    Q[row[0]]=row
ALLY,HORDE=1|4|8|64,2|16|32|128
def nearest(key,ref):
    best=None
    for s in spawns.get(key,[]):
        if ref and s[0]!=ref[0]: continue
        d=0 if not ref else (s[1]-ref[1])**2+(s[2]-ref[2])**2
        if best is None or d<best[0]: best=(d,s)
    return best and best[1]
legs=[]
for q,(e,ql,ml,races,title,*req) in Q.items():
    if not givers.get(q): continue
    fac= 0 if not races else (2 if races&ALLY and not races&HORDE else 1 if races&HORDE and not races&ALLY else 0)
    g=None
    for key in givers[q]:
        g=nearest(key,None)
        if g: break
    if not g: continue
    level=max(1,ql if ql and ql>0 else ml or 1)
    title=(title or "").replace('"',"'")
    obj=None
    for r in req:
        if r: 
            obj=nearest(("c",r) if r>0 else ("g",-r),g)
            if obj: break
    end=None
    for key in enders.get(q,[]):
        end=nearest(key,obj or g)
        if end: break
    for kind,a,b in (("objective",g,obj),("turn-in",obj or g,end)):
        if a and b and a[0]==b[0] and (a[1]-b[1])**2+(a[2]-b[2])**2>150**2:
            for f in ((1,2) if fac==0 else (fac,)):
                legs.append((q,kind,f,level,a[0],a[1],a[2],b[1],b[2],title))
print(len(legs),"legs from",len(Q),"quests")
with open("test/questlegs.lua","w") as f:
    f.write("return {\n")
    for q,kind,fac,lvl,m,x0,y0,x1,y1,t in legs:
        f.write(f'{{ {q}, "{kind}", {fac}, {lvl}, {m}, {x0:.1f}, {y0:.1f}, {x1:.1f}, {y1:.1f}, "{t}" }},\n')
    f.write("}\n")
import collections
print(collections.Counter((l[2],(l[3]-1)//10*10) for l in legs).most_common(14))
