# Transports from the game's own tables (via OpenMap's Places.lua): docks, directions and loops.
CAL={0:(1415,-2.8402092891789313e-05,0.45456991573281436,-4.261220244903351e-05,0.31817552105114527),
     1:(1414,-2.717400445200379e-05,0.46376835583779386,-4.076109746408814e-05,0.52173788731071)}
def dock(cont,X,Y,name):
    if cont==2991: return f'{{ inst = 2991, wx = {Y:.1f}, wy = {X:.1f}, name = "{name}" }}'
    m,fx0,fx1,fy0,fy1=CAL[cont]
    return f'{{ map = {m}, x = {fx0*Y+fx1:.5f}, y = {fy0*X+fy1:.5f}, name = "{name}" }}'
# (kind, fac, time, a, b, oneway): times are average wait + crossing, kept from the earlier data
R=[
 ("boat",0,289,(1,-1005.6,-3841.6,"Ratchet"),(0,-14277.7,582.9,"Booty Bay"),False),
 ("zeppelin",1,262,(0,-12464.0,231.6,"Grom'gol Base Camp"),(1,1360.9,-4631.3,"Orgrimmar"),False),
 ("boat",2,253,(0,-3905.2,-585.8,"Menethil Harbor"),(1,-4016.4,-4740.6,"Theramore Isle"),False),
 ("boat",2,235,(1,8532.0,1023.7,"Rut'theran Village"),(1,6594.4,759.8,"Auberdine"),False),
 ("zeppelin",1,292,(0,-12406.9,211.8,"Grom'gol Base Camp"),(0,2062.6,235.3,"Undercity"),False),
 ("zeppelin",1,339,(1,1318.1,-4658.0,"Orgrimmar"),(0,2062.4,293.0,"Undercity"),False),
 ("boat",2,277,(1,-4197.3,3286.6,"Feathermoon Stronghold"),(1,-4347.8,2444.4,"Feathermoon Ferry"),False),
 # one ship sails a loop: Menethil -> Southshore -> Auberdine -> Menethil (the wait is for the whole loop)
 ("boat",2,600,(0,-3709.5,-575.1,"Menethil Harbor"),(0,-1102.6,-554.7,"Southshore"),True),
 ("boat",2,660,(0,-1102.6,-554.7,"Southshore"),(1,6406.2,823.1,"Auberdine"),True),
 ("boat",2,660,(1,6406.2,823.1,"Auberdine"),(0,-3709.5,-575.1,"Menethil Harbor"),True),
 ("boat",0,182,(1,-6932.6,-4950.8,"Steamwheedle Port"),(0,-8232.3,-5800.8,"Powderfuse Port"),False),
 ("airship",0,345,(0,544.8,424.2,"Dalaran"),(2991,1848.3,569.1,"Valanaar Skydocks"),False),
 ("airship",1,351,(1,-802.0,366.5,"Thunder Bluff"),(2991,1952.5,1019.1,"Valanaar"),False),
 ("boat",2,175,(1,6548.3,942.2,"Auberdine"),(0,-8654.5,1344.4,"Stormwind Harbor"),False),
 # the magic portals between Rut'theran Village and Darnassus (the game's teleport triggers)
 ("portal",0,5,(1,8799.4,969.8,"Rut'theran Village"),(1,9946.3,2613.0,"Darnassus"),True),
 ("portal",0,5,(1,9947.5,2630.0,"Darnassus"),(1,8785.8,967.0,"Rut'theran Village"),True),
]
out=['''-- Boats, zeppelins, airships and the Deeprun Tram in WoW Forever. Routes, directions and dock
-- positions from the game's own tables (as OpenMap lists them: Data/Forever/Places.lua), converted to
-- continent map coordinates. Facts only: which ship sails where, and from which dock.
-- fac: 0 anyone, 1 Horde, 2 Alliance. time: average wait plus the crossing, in seconds.
-- oneway = true: the ship only sails from a to b (the Menethil - Southshore - Auberdine ship sails a loop).
local _, ns = ...
ns.TransportData = {''']
for kind,fac,t,a,b,ow in R:
    out.append(f'    {{ kind = "{kind}", fac = {fac}, time = {t},{" oneway = true," if ow else ""}\n      a = {dock(*a)},\n      b = {dock(*b)} }},')
out.append('''    { kind = "tram", fac = 2, time = 100,
      a = { map = 1415, x = 0.43997, y = 0.67384, name = "Stormwind City" },
      b = { map = 1415, x = 0.49236, y = 0.52443, name = "Ironforge" } },
}''')
open("/home/user/QuestRoute/Data/Transports.lua","w").write("\n".join(out)+"\n")
