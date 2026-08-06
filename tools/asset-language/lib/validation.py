import json, math, re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
ID = re.compile(r"^[a-z][a-z0-9_]*$")
PATH = re.compile(r"^[^\\]+$")
REPS = ["plane","shell","radial","full_model"]
ROLES = ["surface_material","surface_fixture","object_fixture","item_display","structural_opening","event_prop","overlay","preview_only"]
SPACES = ["world_cell","item_display","depth_tile","preview"]
FRAMES = ["floor_center","wall_center","ceiling_center","opening_center","item_viewport","surface_domain","preview_frame"]
SOCKETS = ["interaction","actor","camera_focus","vfx","loot","hinge","light","audio","attachment"]

def diag(code, path, field, message): return {"code": code, "path": str(path), "field": field, "message": message}
def load(path):
    try: return json.loads(Path(path).read_text(encoding="utf-8")), []
    except Exception as e: return None, [diag("malformed_json", path, "$", str(e))]
def ids(values, path, field):
    out=[]
    if not isinstance(values, list): return [diag("not_array",path,field,"must be an array")]
    seen=set()
    for i,v in enumerate(values):
        if not isinstance(v,str) or not ID.fullmatch(v): out.append(diag("invalid_id",path,f"{field}[{i}]","must be lower snake case"))
        elif v in seen: out.append(diag("duplicate_id",path,f"{field}[{i}]",f"duplicate '{v}'"))
        seen.add(v)
    return out
def valid_path(v):
    return isinstance(v,str) and v and PATH.match(v) and not v.startswith("/") and not re.match(r"^[A-Za-z]:",v) and ".." not in v.split("/")
def validate_contract(root=ROOT):
    p=root/"tools/asset-language/contract.json"; c, ds=load(p)
    if ds: return ds
    if c.get("contractVersion")!=1: ds.append(diag("contract_version",p,"$.contractVersion","must be 1"))
    if c.get("cellMetres")!=2.5: ds.append(diag("cell_scale",p,"$.cellMetres","must be 2.5"))
    for key, expected in [("representations",REPS),("roles",ROLES),("authoringSpaces",SPACES),("placementFrames",FRAMES),("socketKinds",SOCKETS)]:
        got=list(c.get(key,{}));
        if got != expected if key in ("representations","roles","authoringSpaces","placementFrames","socketKinds") else False: ds.append(diag("vocabulary_mismatch",p,f"$.{key}","does not match version-1 vocabulary"))
    co=c.get("coordinateSystems",{}); checks={"$.blender.upAxis":"+Z","$.obj.upAxis":"+Y","$.obj.exportForwardAxis":"-Z","$.obj.exportUpAxis":"Y","$.engine.upAxis":"+Z","$.objToEngine.formula":"(x, y, z) -> (x, -z, y)"}
    for f,v in checks.items():
        cur=co
        for part in f[2:].split("."): cur=cur.get(part,{}) if isinstance(cur,dict) else {}
        if cur!=v: ds.append(diag("coordinate_contract",p,f,"unexpected coordinate value"))
    m, md=load(root/"tools/asset-language/materials.json"); ds+=md
    if m:
        mids=[x.get("id") for x in m.get("materials",[])]
        ds+=ids(mids,root/"tools/asset-language/materials.json","$.materials")
        if len(mids)!=12: ds.append(diag("material_count",p,"$.materials","must contain 12 seed materials"))
        for i,x in enumerate(m.get("materials",[])):
            for k in ("displayName","family","baseColorSrgb","metallicHint","roughnessHint","opacityMode","generationTags","legacyMtl","notes"):
                if k not in x: ds.append(diag("missing_field",p,f"$.materials[{i}]",f"missing {k}"))
            if not (isinstance(x.get("baseColorSrgb"),list) and len(x.get("baseColorSrgb",[]))==3 and all(type(v) is int and 0<=v<=255 for v in x["baseColorSrgb"])): ds.append(diag("material_color",p,f"$.materials[{i}].baseColorSrgb","must be three bytes"))
            for k in ("metallicHint","roughnessHint"):
                if not isinstance(x.get(k),(int,float)) or not 0<=x[k]<=1: ds.append(diag("material_hint",p,f"$.materials[{i}].{k}","must be 0..1"))
        if m.get("version")!=c.get("materialRegistry",{}).get("version"): ds.append(diag("material_version",p,"$.materialRegistry","version mismatch"))
    s, sd=load(root/"tools/asset-language/asset-record.schema.json"); ds+=sd
    if s:
        if s.get("$schema")!="https://json-schema.org/draft/2020-12/schema": ds.append(diag("schema_dialect",root/"tools/asset-language/asset-record.schema.json","$.$schema","must use Draft 2020-12"))
        if s.get("properties",{}).get("representation",{}).get("enum")!=REPS: ds.append(diag("schema_enum",root/"tools/asset-language/asset-record.schema.json","$.properties.representation.enum","must match contract"))
    return sorted(ds,key=lambda d:(d["path"],d["field"],d["code"],d["message"]))
def validate_record(record, path="<record>", root=ROOT):
    if not isinstance(record,dict): return [diag("record_type",path,"$","must be an object")]
    ds=[]
    req=["contractVersion","id","displayName","representation","role","authoringSpace","placementFrame","materials","states","defaultState","variants","sockets","sources","products","provenance"]
    for k in req:
        if k not in record: ds.append(diag("missing_field",path,f"$.{k}","required"))
    if record.get("contractVersion")!=1: ds.append(diag("contract_version",path,"$.contractVersion","must be 1"))
    if not isinstance(record.get("id"),str) or not ID.fullmatch(record.get("id","")): ds.append(diag("invalid_id",path,"$.id","must be lower snake case"))
    for k in ("materials","states","variants"):
        ds+=ids(record.get(k,[]),path,f"$.{k}")
    if record.get("defaultState") not in record.get("states",[]): ds.append(diag("default_state",path,"$.defaultState","must appear in states"))
    if set(record.get("states",[])) & set(record.get("variants",[])): ds.append(diag("state_variant_overlap",path,"$.variants","states and variants must be distinct"))
    if record.get("representation") not in REPS: ds.append(diag("vocabulary",path,"$.representation","unknown representation"))
    if record.get("role") not in ROLES: ds.append(diag("vocabulary",path,"$.role","unknown role"))
    if record.get("authoringSpace") not in SPACES or record.get("placementFrame") not in FRAMES: ds.append(diag("vocabulary",path,"$.authoringSpace","unknown space or frame"))
    pairs={"world_cell":{"floor_center","wall_center","ceiling_center","opening_center"},"item_display":{"item_viewport"},"depth_tile":{"surface_domain"},"preview":{"preview_frame"}}
    if record.get("placementFrame") not in pairs.get(record.get("authoringSpace"),set()): ds.append(diag("space_frame",path,"$.placementFrame","incompatible with authoringSpace"))
    combos={"item_display":("full_model","item_display","item_viewport"),"surface_material":("plane","depth_tile","surface_domain"),"overlay":("plane","depth_tile","surface_domain"),"structural_opening":("full_model","world_cell","opening_center"),"preview_only":(None,"preview","preview_frame")}
    if record.get("role") in combos:
        a=combos[record["role"]]
        if (a[0] and record.get("representation")!=a[0]) or record.get("authoringSpace")!=a[1] or record.get("placementFrame")!=a[2]: ds.append(diag("role_compatibility",path,"$.role","incompatible representation/space/frame"))
    if record.get("role") in ("object_fixture","event_prop") and (record.get("representation") not in ("shell","radial","full_model") or record.get("authoringSpace")!="world_cell" or record.get("placementFrame") not in ("floor_center","wall_center","ceiling_center")): ds.append(diag("role_compatibility",path,"$.role","invalid world role combination"))
    if record.get("role")=="surface_fixture" and not ((record.get("representation")=="plane" and record.get("authoringSpace")=="depth_tile" and record.get("placementFrame")=="surface_domain") or (record.get("representation")=="full_model" and record.get("authoringSpace")=="world_cell" and record.get("placementFrame") in ("floor_center","wall_center","ceiling_center"))): ds.append(diag("role_compatibility",path,"$.role","invalid surface fixture combination"))
    mids=set(); m,_=load(root/"tools/asset-language/materials.json")
    if m: mids={x.get("id") for x in m.get("materials",[])}
    for i,x in enumerate(record.get("materials",[])):
        if x not in mids: ds.append(diag("unknown_material",path,f"$.materials[{i}]",x))
    sockets=record.get("sockets",[]); seen=set(); states=set(record.get("states",[])) if isinstance(record.get("states",[]),list) else set()
    if not isinstance(record.get("sockets"),list):
        ds.append(diag("not_array",path,"$.sockets","must be an array")); sockets=[]
    for i,x in enumerate(sockets):
        if not isinstance(x,dict):
            ds.append(diag("socket_type",path,f"$.sockets[{i}]","must be an object")); continue
        if x.get("id") in seen: ds.append(diag("duplicate_socket",path,f"$.sockets[{i}].id","duplicate"))
        seen.add(x.get("id"));
        if x.get("kind") not in SOCKETS: ds.append(diag("socket_kind",path,f"$.sockets[{i}].kind","unknown"))
        if x.get("state") and x["state"] not in states: ds.append(diag("socket_state",path,f"$.sockets[{i}].state","not listed in states"))
        for k in ("position","rotationDegrees","forward","up"):
            if k in x:
                v=x[k]
                if not isinstance(v,list) or len(v)!=3 or not all(isinstance(n,(int,float)) and math.isfinite(n) for n in v): ds.append(diag("vector",path,f"$.sockets[{i}].{k}","must be three finite numbers"))
        for k in ("forward","up"):
            if k in x and isinstance(x[k],list) and len(x[k])==3:
                n=math.sqrt(sum(v*v for v in x[k]));
                if abs(n-1)>1e-4: ds.append(diag("vector_normalization",path,f"$.sockets[{i}].{k}","must be normalized"))
        if "forward" in x and "up" in x and isinstance(x["forward"],list) and isinstance(x["up"],list):
            if abs(sum(a*b for a,b in zip(x["forward"],x["up"])))>=.999: ds.append(diag("parallel_vectors",path,f"$.sockets[{i}]","forward and up are parallel"))
    def paths(v, field):
        if isinstance(v,str): vals=[v]
        elif isinstance(v,list): vals=v
        else: return [diag("path_type",path,field,"must be path or path array")]
        return [diag("invalid_path",path,f"{field}[{i}]", "must be repository-relative") for i,x in enumerate(vals) if not valid_path(x)]
    sources=record.get("sources",{})
    if not isinstance(sources,dict): ds.append(diag("object_type",path,"$.sources","must be an object")); sources={}
    for k in ("blenderScript","blendInspection","prompt","metadataSource"):
        if k in sources: ds+=paths(sources[k],f"$.sources.{k}")
    for k in ("sourceImages","referenceImages"):
        if k in sources: ds+=paths(sources[k],f"$.sources.{k}")
    prod=record.get("products",{})
    if not isinstance(prod,dict): ds.append(diag("object_type",path,"$.products","must be an object")); prod={}
    metric=prod.get("heightMetric")
    if metric:
        if not valid_path(metric.get("path")): ds.append(diag("invalid_path",path,"$.products.heightMetric.path","invalid"))
        if not isinstance(metric.get("rangeCells"),(int,float)) or not math.isfinite(metric.get("rangeCells",0)) or metric.get("rangeCells",0)<=0: ds.append(diag("range_cells",path,"$.products.heightMetric.rangeCells","must be positive finite"))
    for k in ("albedo","depthGuide","legacyHeight","model","preview","report","manifest","runtimeMetadata","materialLibrary"):
        if k in prod and isinstance(prod[k],str) and not valid_path(prod[k]): ds.append(diag("invalid_path",path,f"$.products.{k}","invalid"))
    if metric and prod.get("depthGuide")==metric.get("path"): ds.append(diag("path_collision",path,"$.products","metric and guide paths must differ"))
    if "legacyHeight" in prod and "depthGuide" in prod and prod.get("legacyHeight")==prod.get("depthGuide"): ds.append(diag("path_collision",path,"$.products","legacy and guide paths must differ"))
    prov=record.get("provenance",{})
    if not isinstance(prov,dict): ds.append(diag("object_type",path,"$.provenance","must be an object")); prov={}
    for k in ("generator","generatorVersion","sourceCommit","command"):
        if not isinstance(prov.get(k),str) or not prov.get(k).strip(): ds.append(diag("provenance_field",path,f"$.provenance.{k}","must be a non-empty string"))
    seen=set()
    for group in ("inputs","outputs"):
        entries=prov.get(group,[])
        if not isinstance(entries,list): ds.append(diag("provenance_type",path,f"$.provenance.{group}","must be an array")); entries=[]
        for i,x in enumerate(entries):
            if not isinstance(x,dict): ds.append(diag("provenance_entry",path,f"$.provenance.{group}[{i}]","must be an object")); continue
            if not valid_path(x.get("path")): ds.append(diag("invalid_path",path,f"$.provenance.{group}[{i}].path","invalid"))
            if x.get("path") in seen: ds.append(diag("duplicate_provenance_path",path,f"$.provenance.{group}[{i}].path","duplicate"))
            seen.add(x.get("path"));
            if "sha256" in x and (not isinstance(x["sha256"],str) or not re.fullmatch(r"[0-9a-f]{64}",x["sha256"])): ds.append(diag("sha256",path,f"$.provenance.{group}[{i}].sha256","must be lowercase hex") )
    return sorted(ds,key=lambda d:(d["path"],d["field"],d["code"],d["message"]))
