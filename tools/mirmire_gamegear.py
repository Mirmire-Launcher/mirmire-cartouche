#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Converts the Game Gear CAD model (STEP) into app/carousel/consoles/gamegear/gamegear.glb: meshes each solid,
drops the battery pack, cable and cartridge, paints the parts, centres it in this app's units facing the front.

Needs OpenCascade for Python (pip install cadquery-ocp numpy).
Usage: python3 tools/mirmire_gamegear.py Sega_Gamegear_STEP.STEP app/carousel/consoles/gamegear/gamegear.glb 0.35 0.8
"""
import sys, json, struct
import numpy as np
from OCP.STEPCAFControl import STEPCAFControl_Reader
from OCP.TDocStd import TDocStd_Document
from OCP.TCollection import TCollection_ExtendedString
from OCP.XCAFDoc import XCAFDoc_DocumentTool
from OCP.collections import Sequence_TDF_Label
from OCP.TDataStd import TDataStd_Name
from OCP.TDF import TDF_Label
from OCP.TopExp import TopExp_Explorer
from OCP.TopAbs import TopAbs_SOLID, TopAbs_SHELL, TopAbs_FACE, TopAbs_REVERSED
from OCP.TopLoc import TopLoc_Location
from OCP.BRepMesh import BRepMesh_IncrementalMesh
from OCP.BRep import BRep_Tool
from OCP.TopoDS import TopoDS
src, out, lin, ang = sys.argv[1], sys.argv[2], float(sys.argv[3]), float(sys.argv[4])
doc = TDocStd_Document(TCollection_ExtendedString("doc"))
r = STEPCAFControl_Reader(); r.SetNameMode(True); r.ReadFile(src); r.Transfer(doc)
st = XCAFDoc_DocumentTool.ShapeTool_s(doc.Main())
def name(l):
    a = TDataStd_Name()
    return a.Get().ToExtString() if l.FindAttribute(TDataStd_Name.GetID_s(), a) else "?"
solids = []
def walk(label, loc, comp_name):
    if st.IsAssembly_s(label):
        comps = Sequence_TDF_Label(); st.GetComponents_s(label, comps)
        for i in range(1, comps.Length()+1):
            c = comps.Value(i); ref = TDF_Label(); st.GetReferredShape_s(c, ref)
            walk(ref, loc * st.GetLocation_s(c), name(ref))
    else:
        shape = st.GetShape_s(label).Moved(loc)
        ex = TopExp_Explorer(shape, TopAbs_SOLID)
        while ex.More():
            solids.append((comp_name or name(label), ex.Current())); ex.Next()
        ex = TopExp_Explorer(shape, TopAbs_SHELL, TopAbs_SOLID)
        while ex.More():
            solids.append(((comp_name or name(label)) + "_shell", ex.Current())); ex.Next()
free = Sequence_TDF_Label(); st.GetFreeShapes(free)
for i in range(1, free.Length()+1): walk(free.Value(i), TopLoc_Location(), None)
meshes = []
for part, solid in solids:
    BRepMesh_IncrementalMesh(solid, lin, False, ang, True)
    P = []; I = []; base = 0
    fx = TopExp_Explorer(solid, TopAbs_FACE)
    while fx.More():
        f = TopoDS.Face(fx.Current()); l = TopLoc_Location()
        t = BRep_Tool.Triangulation_s(f, l)
        if t is not None:
            tr = l.Transformation()
            for k in range(1, t.NbNodes()+1):
                p = t.Node(k).Transformed(tr); P.append((p.X(), p.Y(), p.Z()))
            rev = f.Orientation() == TopAbs_REVERSED
            for k in range(1, t.NbTriangles()+1):
                a, b, c = t.Triangle(k).Get()
                I.append((base+a-1, base+c-1, base+b-1) if rev else (base+a-1, base+b-1, base+c-1))
            base += t.NbNodes()
        fx.Next()
    meshes.append((part, np.array(P, np.float32), np.array(I, np.uint32)))
# GLB: flat shading avoided by letting Godot compute normals? glTF needs normals or viewer computes flat; compute smooth-ish per-vertex normals per face group.
def normals(P, I):
    n = np.zeros_like(P); v = P[I]; fn = np.cross(v[:,1]-v[:,0], v[:,2]-v[:,0])
    for k in range(3): np.add.at(n, I[:,k], fn)
    l = np.linalg.norm(n, axis=1, keepdims=True); l[l == 0] = 1; return (n/l).astype(np.float32)
MATS = {  # name: (linear rgb, roughness, metallic)
    "body": ((0.028, 0.028, 0.030), 0.6, 0.0), "bezel": ((0.010, 0.010, 0.012), 0.25, 0.0),
    "glass": ((0.004, 0.005, 0.006), 0.05, 0.0), "lcd": ((0.012, 0.018, 0.016), 0.3, 0.0),
    "button": ((0.016, 0.016, 0.018), 0.45, 0.0), "start": ((0.028, 0.11, 0.48), 0.4, 0.0),
    "metal": ((0.4, 0.4, 0.42), 0.35, 1.0),
}
PAINT = {"GameGear_mainconsole__5": "bezel", "GameGear_mainconsole__1": "glass", "GameGear_mainconsole__0": "lcd",
         "GameGear_mainconsole__2": "button", "GameGear_mainconsole__6": "button", "GameGear_mainconsole__7": "button",
         "GameGear_mainconsole__4": "start", "GameGear_mainconsole__23": "metal", "GameGear_mainconsole__24": "metal",
         "GameGear_mainconsole__25": "metal", "GameGear_mainconsole__26": "metal"}
DROP = ("GameGear_cartridge", "DC_plugend", "DCwire", "BatteryPack")
mat_names = list(MATS)
materials = [{"name": k, "pbrMetallicRoughness": {"baseColorFactor": [*v[0], 1.0], "roughnessFactor": v[1], "metallicFactor": v[2]}} for k, v in MATS.items()]
kept = []
cnt = {}
for part, P, I in meshes:
    cnt[part] = cnt.get(part, 0) + 1
    nm = f"{part}__{cnt[part]-1}"
    if part.startswith(DROP) or len(I) == 0: continue
    kept.append((nm, P, I))
allP = np.concatenate([P for _, P, _ in kept]); lo, hi = allP.min(0), allP.max(0); centre = (lo + hi) / 2
UNIT = 0.01  # Cartouche: 1 unit = 100 mm
def frame(P):  # STEP: front +X, up +Y, D-pad at +Z  ->  front +Z, up +Y, D-pad at -X; centred
    q = P - centre
    return (np.stack([-q[:, 2], q[:, 1], q[:, 0]], 1) * UNIT).astype(np.float32)
meshes = [(nm, frame(P), I) for nm, P, I in kept]
print("size mm", (hi - lo)[[2, 1, 0]])
bin_ = bytearray(); views = []; accs = []; gm = []; nodes = []; info = []
def add(data, target, comp, typ, count, mn=None, mx=None):
    while len(bin_) % 4: bin_.append(0)
    views.append({"buffer": 0, "byteOffset": len(bin_), "byteLength": len(data), "target": target}); bin_.extend(data)
    a = {"bufferView": len(views)-1, "componentType": comp, "count": count, "type": typ}
    if mn is not None: a["min"] = mn; a["max"] = mx
    accs.append(a); return len(accs)-1
for idx, (nm, P, I) in enumerate(meshes):
    N = normals(P, I)
    pa = add(P.tobytes(), 34962, 5126, "VEC3", len(P), P.min(0).tolist(), P.max(0).tolist())
    na = add(N.tobytes(), 34962, 5126, "VEC3", len(N))
    ia = add(I.astype(np.uint32).tobytes(), 34963, 5125, "SCALAR", I.size)
    gm.append({"primitives": [{"attributes": {"POSITION": pa, "NORMAL": na}, "indices": ia, "material": mat_names.index(PAINT.get(nm, "body"))}]})
    nodes.append({"name": nm, "mesh": len(gm)-1})
    info.append({"name": nm, "tris": len(I), "min": [round(x,2) for x in P.min(0).tolist()], "max": [round(x,2) for x in P.max(0).tolist()]})
j = {"asset": {"version": "2.0"}, "scene": 0, "scenes": [{"nodes": list(range(len(nodes)))}], "nodes": nodes, "meshes": gm, "materials": materials,
     "accessors": accs, "bufferViews": views, "buffers": [{"byteLength": len(bin_)}]}
js = json.dumps(j).encode(); js += b" " * (-len(js) % 4); bin_ += b"\0" * (-len(bin_) % 4)
with open(out, "wb") as f:
    f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(bin_)))
    f.write(struct.pack("<II", len(js), 0x4E4F534A)); f.write(js)
    f.write(struct.pack("<II", len(bin_), 0x004E4942)); f.write(bin_)
json.dump(info, open(out.replace(".glb", ".json"), "w"), indent=0)
print(len(info), "solids", sum(i["tris"] for i in info), "tris")
