#!/usr/bin/env python3
"""Build deterministic low-poly OBJ models for Second Rite items 53-62."""
import json, math
from pathlib import Path
from direct_item_mesh import Mesh, sword, write_model, validate_obj

ROOT=Path(__file__).resolve().parents[2]; OUT=ROOT/"assets"/"models"/"items"; MATERIALS=ROOT/"tools"/"asset-language"/"materials.json"
ITEMS={53:("celestial_fossil","Celestial Fossil"),54:("blackroot","Blackroot"),55:("molten_manacle","Molten Manacle"),56:("adamant_weight","Adamant Weight"),57:("iron_knife","Iron Knife"),58:("steel_sword","Steel Sword"),59:("knight_sword","Knight Sword"),60:("greatsword","Greatsword"),61:("adamant_blade","Adamant Blade"),62:("hazel_wand","Hazel Wand")}

def fossil():
    m=Mesh("celestial_fossil"); m.extrude([(-.72,-.48),(-.45,-.72),(.15,-.76),(.64,-.46),(.76,.12),(.47,.64),(-.08,.76),(-.61,.50)],-.16,.16,"old_limestone")
    for r,a in [(.53,.1),(.42,.72),(.32,1.35),(.23,2.05),(.15,2.75)]: m.prism_between((r*math.cos(a),r*math.sin(a),.18),((r-.14)*math.cos(a+.45),(r-.14)*math.sin(a+.45),.23),.07,.045,5,"bone")
    m.diamond((-.03,.04,.26),.18,.22,"crystal",6); m.center(); return m

def blackroot():
    m=Mesh("blackroot"); m.diamond((0,0,0),.42,.65,"dark_wood",7)
    for p0,p1,r0,r1 in [((-.12,-.08,0),(-.88,-.62,.15),.18,.055),((.08,-.10,0),(.78,-.72,-.06),.17,.05),((.05,.04,0),(.92,.22,.24),.16,.045),((-.08,.05,0),(-.75,.48,-.18),.15,.04),((0,.12,0),(.15,.85,.06),.14,.035)]: m.prism_between(p0,p1,r0,r1,6,"dark_wood",.3)
    m.prism_between((-.35,-.05,.12),(-.70,-.10,.45),.075,.025,5,"wet_residue"); m.prism_between((.26,.10,-.12),(.55,.44,-.36),.065,.022,5,"wet_residue"); m.center(); return m

def manacle():
    m=Mesh("molten_manacle"); radius=.62; angles=[-2.55,-2.05,-1.55,-1.05,-.55,0,.55,1.05,1.55,2.05]
    for a,b in zip(angles[:-1],angles[1:]): m.prism_between((radius*math.cos(a),radius*math.sin(a),0),(radius*math.cos(b),radius*math.sin(b),0),.13,.13,6,"wrought_iron")
    for a in (angles[0],angles[-1]): m.diamond((radius*math.cos(a),radius*math.sin(a),0),.17,.20,"wax",6)
    m.box((0,-.73,0),(.46,.25,.32),"wrought_iron"); m.box((0,-.87,.18),(.22,.08,.08),"ritual_gold"); m.center(); return m

def weight():
    m=Mesh("adamant_weight"); m.diamond((0,-.10,0),.58,1.05,"wrought_iron",8); m.box((0,.48,0),(.44,.22,.34),"ritual_gold"); m.prism_between((-.16,.56,0),(.16,.56,0),.09,.09,6,"wrought_iron"); m.prism_between((.16,.56,0),(.25,.76,0),.09,.075,6,"wrought_iron"); m.prism_betweeen((.25,.76,0),(-.25,.76,0),.075,.075,6,"wrought_iron"); m.prism_betwen((-.25,.76,0),(-.16,.56,0),.075,.09,6,"wrought_iron"); m.box((0,-.12,.59),(.12,.50,.05),"ritual_gold"); m.center(); return m

def knife():
    m=Mesh("iron_knife"); sword(m,length_=2.15,half_width=.20,thickness=.10,guard=.48,grip=.55,point=.32,shoulder=.02); m.center(); return m

def steel():
    m=Mesh("steel_sword"); sword(m,length_=3.35,half_width=.23,thickness=.105,guard=.78,grip=.72,point=.40,shoulder=.03); m.center(); return m

def knight():
    m=Mesh("knight_sword"); sword(m,length_=3.65,half_width=.27,thickness=.12,guard=1.05,grip=.78,point=.46,shoulder=.08,accent="ritual_gold",fuller=True); m.prism_between((-.50,-1,0),(-.66,-.84,0),.08,.05,5,"ritual_gold"); m.prism_between((.50,-1,0),(.66,-.84,0),.08,.05,5,"ritual_gold"); m.center(); return m

def greatsword():
    m=Mesh("greatsword"); sword(m,length_=4.65,half_width=.36,thickness=.15,guard=1.42,grip=1.05,point=.52,shoulder=.12,fuller=True); m.box((0,-1.47,0),(.56,.42,.22),"wrought_iron")
    for y in (-1.78,-1.98,-2.18): m.box((0,y,0),(.22,.08,.20),"aged_cloth")
    m.center(); return m

def adamant():
    m=Mesh("adamant_blade"); sword(m,length_=4.10,half_width=.40,thickness=.17,guard=1.25,grip=.86,point=.62,shoulder=.18,accent="ritual_gold",fuller=True,split_tip=True); m.extrude([(-.62,-1.10),(-.34,-1.36),(-.12,-.92),(-.42,-.72)],-.10,.10,"ritual_gold"); m.extrude([(.62,-1.10),(.34,-1.36),(.12,-.92),(.42,-.72)],-.10,.10,"ritual_gold"); m.diamond((0,-1.78,0),.24,.32,"crystal",6); m.center(); return m

def wand():
    m=Mesh("hazel_wand"); p=[(0,-1.35,0),(.06,-.72,.03),(-.05,-.08,-.02),(.08,.55,.04),(.02,1.12,0)]; r=[.105,.095,.085,.072,.06]
    for i in range(4): m.prism_between(p[i],p[i+1],r[i],r[i+1],6,"dark_wood",phase=.2*i)
    m.prism_between(p[-1],(-.28,1.48,.02),.06,.035,5,"dark_wood"); m.prism_between(p[-1],(.32,1.46,-.03),.06,.034,5,"dark_wood"); m.diamond((.03,1.37,0),.17,.25,"crystal",6); m.prism_between((-.11,1.28,.05),(.14,1.27,.05),.025,.025,5,"aged_cloth"); m.center(); return m

BUILD={53:fossil,54:blackroot,55:manacle,56:weight,57:knife,58:steel,59:knight,60:greatsword,61:adamant,62:wand}

def registry():
    d=json.loads(MATERIALS.read_text(encoding="utf-8")); return {m["id"]:tuple(m["legacyMtl"]["kd"]) for m in d["materials"]}

def patch_items():
    path=ROOT/"data"/"items.json"
    if not path.is_file(): return False
    data=json.loads(path.read_text(encoding="utf-8")); by_id={x.get("id"):x for x in data}
    for item_id,(stem,_) in ITEMS.items():
        item=by_id[item_id]; target=f"assets/models/items/{stem}.obj"
        if item.get("model") not in (None,target): raise ValueError(f"item {item_id} already has a different model: {item.get('model')}")
        item["model"]=target
    path.write_text(json.dumps(data,indent=2,ensure_ascii=False)+"\n",encoding="utf-8"); return True

def main():
    mats=registry(); OUT.mkdir(parents=True,exist_ok=True); lines=["# Shared semantic materials for deterministic item batch 53-62"]
    for mat,(r,g,b) in mats.items(): lines += [f"newmtl {mat}",f"Kd {r:.3f} {g:.3f} {b:.3f}",""]
    (OUT/"item_batch_53_62.mtl").write_text("\n".join(lines)+"\n",encoding="utf-8"); report={}
    for item_id,(stem,label) in ITEMS.items():
        path=OUT/f"{stem}.obj"; mesh=BUILD[item_id](); report[str(item_id)]={"name":label,"model":f"assets/models/items/{stem}.obj",**write_model(mesh,path,label,mats)}; validate_obj(path)
    print(json.dumps({"ok":True,"items":report,"itemsJsonPatched":patch_items()},indent=2)); return 0

if __name__=="__main__": raise SystemExit(main())
