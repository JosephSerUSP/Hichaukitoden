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
MATERIALS = ["old_limestone","rough_limestone","ritual_gold","oxidized_bronze","wrought_iron","dark_wood","aged_cloth","smoked_glass","wet_residue","bone","wax","crystal"]
REPOSITORY_PATTERN = r"^(?!/)(?![A-Za-z]:)(?!.*\\)(?!.*(?:^|/)\.\.(?:/|$)).+$"

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
def validate_schema_agreement(schema, contract, path="<schema>"):
    """Check the portable schema against the version-1 contract vocabularies."""
    ds=[]
    sp=schema.get("properties",{}) if isinstance(schema,dict) else {}
    defs=schema.get("$defs",{}) if isinstance(schema,dict) else {}
    required_expected=["contractVersion","id","displayName","representation","role","authoringSpace","placementFrame","materials","states","defaultState","variants","sockets","sources","products","provenance"]
    if schema.get("$schema") != "https://json-schema.org/draft/2020-12/schema": ds.append(diag("schema_dialect",path,"$.$schema","must use Draft 2020-12"))
    if schema.get("additionalProperties") is not True: ds.append(diag("schema_additional_properties",path,"$ .additionalProperties","top-level additionalProperties must be true"))
    if set(schema.get("required",[])) != set(required_expected): ds.append(diag("schema_required",path,"$.required","must match future record fields"))
    if sp.get("contractVersion",{}).get("const") != contract.get("contractVersion"): ds.append(diag("schema_version",path,"$.properties.contractVersion","must match contract"))
    expected_enums={"representation":list(contract.get("representations",{})),"role":list(contract.get("roles",{})),"authoringSpace":list(contract.get("authoringSpaces",{})),"placementFrame":list(contract.get("placementFrames",{}))}
    for key, expected in expected_enums.items():
        if sp.get(key,{}).get("enum") != expected: ds.append(diag("schema_enum",path,f"$.properties.{key}.enum","must match contract"))
    if sp.get("id",{}).get("pattern") != ID.pattern: ds.append(diag("schema_id_pattern",path,"$.properties.id.pattern","must match contract"))
    for key in ("materials","states","variants"):
        if sp.get(key,{}).get("uniqueItems") is not True: ds.append(diag("schema_unique",path,f"$.properties.{key}.uniqueItems","identity arrays must be unique"))
    socket_schema=sp.get("sockets",{}).get("items",{})
    if set(socket_schema.get("required",[])) != {"id","kind","position"}: ds.append(diag("schema_socket_required",path,"$.properties.sockets.items.required","must require id, kind, and position"))
    if socket_schema.get("properties",{}).get("kind",{}).get("enum") != list(contract.get("socketKinds",{})): ds.append(diag("schema_socket_enum",path,"$.properties.sockets.items.properties.kind.enum","must match contract"))
    vector=defs.get("vector3",{})
    if vector.get("minItems") != 3 or vector.get("maxItems") != 3 or vector.get("items") is not False: ds.append(diag("schema_vector",path,"$.$defs.vector3","must contain exactly three numbers"))
    source_schema=sp.get("sources",{}).get("properties",{})
    source_fields=["blenderScript","blendInspection","sourceImages","prompt","referenceImages","metadataSource"]
    if set(source_schema) != set(source_fields): ds.append(diag("schema_sources",path,"$.properties.sources.properties","recognized sources must match contract"))
    for key in ("blenderScript","blendInspection","prompt","metadataSource"):
        if source_schema.get(key,{}).get("$ref") != "#/$defs/repositoryPath": ds.append(diag("schema_sources",path,f"$.properties.sources.properties.{key}","must use repositoryPath"))
    for key in ("sourceImages","referenceImages"):
        if source_schema.get(key,{}).get("uniqueItems") is not True or source_schema.get(key,{}).get("items",{}).get("$ref") != "#/$defs/repositoryPath": ds.append(diag("schema_sources",path,f"$.properties.sources.properties.{key}","must be unique repository paths"))
    product_schema=sp.get("products",{}).get("properties",{})
    product_fields=["model","materialLibrary","albedo","heightMetric","depthGuide","legacyHeight","runtimeMetadata","preview","report","manifest"]
    if set(product_schema) != set(product_fields): ds.append(diag("schema_products",path,"$.properties.products.properties","recognized products must match contract"))
    for key in ("model","materialLibrary","albedo","depthGuide","legacyHeight","runtimeMetadata","preview","report","manifest"):
        if product_schema.get(key,{}).get("$ref") != "#/$defs/repositoryPath": ds.append(diag("schema_products",path,f"$.properties.products.properties.{key}","must use repositoryPath"))
    metric=product_schema.get("heightMetric",{})
    if set(metric.get("required",[])) != {"path","rangeCells"} or metric.get("properties",{}).get("path",{}).get("$ref") != "#/$defs/repositoryPath" or metric.get("properties",{}).get("rangeCells",{}).get("exclusiveMinimum") != 0: ds.append(diag("schema_metric_height",path,"$.properties.products.properties.heightMetric","path and positive rangeCells are required"))
    provenance=sp.get("provenance",{})
    prov_fields={"generator","generatorVersion","sourceCommit","command","inputs","outputs"}
    if set(provenance.get("required",[])) != prov_fields: ds.append(diag("schema_provenance",path,"$.properties.provenance.required","provenance fields are incomplete"))
    for key in ("inputs","outputs"):
        if provenance.get("properties",{}).get(key,{}).get("items",{}).get("$ref") != "#/$defs/provenanceFile": ds.append(diag("schema_provenance",path,f"$.properties.provenance.properties.{key}","must contain provenance files"))
    sha=defs.get("provenanceFile",{}).get("properties",{}).get("sha256",{}).get("pattern")
    if sha != r"^[0-9a-f]{64}$": ds.append(diag("schema_sha256",path,"$.$defs.provenanceFile.properties.sha256.pattern","must be lowercase 64-character hex"))
    repo=defs.get("repositoryPath",{})
    if repo.get("type") != "string" or repo.get("minLength") != 1 or repo.get("pattern") != REPOSITORY_PATTERN: ds.append(diag("schema_repository_path",path,"$.$defs.repositoryPath","must be non-empty repository-relative slash-separated path"))
    return ds

def validate_contract(root=ROOT, contract_data=None, materials_data=None, schema_data=None):
    p=root/"tools/asset-language/contract.json"; c, ds=(contract_data,[]) if contract_data is not None else load(p)
    if ds: return ds
    if c.get("contractVersion")!=1: ds.append(diag("contract_version",p,"$.contractVersion","must be 1"))
    if c.get("cellMetres")!=2.5: ds.append(diag("cell_scale",p,"$.cellMetres","must be 2.5"))
    exact={"representations":REPS,"roles":ROLES,"authoringSpaces":SPACES,"placementFrames":FRAMES,"socketKinds":SOCKETS,"states":["default","inactive","active","closed","open","sealed","unsealed","locked","unlocked","intact","damaged","broken","empty","filled","spent"]}
    for key, expected in exact.items():
        got=list(c.get(key,{})) if isinstance(c.get(key),dict) else c.get(key,[])
        if set(got)!=set(expected) or len(got)!=len(expected): ds.append(diag("vocabulary_mismatch",p,f"$.{key}","does not match version-1 vocabulary"))
    co=c.get("coordinateSystems",{}); checks={"$.blender.upAxis":"+Z","$.obj.upAxis":"+Y","$.obj.exportForwardAxis":"-Z","$.obj.exportUpAxis":"Y","$.engine.upAxis":"+Z","$.objToEngine.formula":"(x, y, z) -> (x, -z, y)"}
    for f,v in checks.items():
        cur=co
        for part in f[2:].split("."): cur=cur.get(part,{}) if isinstance(cur,dict) else {}
        if cur!=v: ds.append(diag("coordinate_contract",p,f,"unexpected coordinate value"))
    m, md=(materials_data,[]) if materials_data is not None else load(root/"tools/asset-language/materials.json"); ds+=md
    if m:
        mids=[x.get("id") for x in m.get("materials",[])]
        ds+=ids(mids,root/"tools/asset-language/materials.json","$.materials")
        if mids != MATERIALS: ds.append(diag("material_identity",p,"$.materials","must match exact seed materials"))
        for i,x in enumerate(m.get("materials",[])):
            for k in ("displayName","family","baseColorSrgb","metallicHint","roughnessHint","opacityMode","generationTags","legacyMtl","notes"):
                if k not in x: ds.append(diag("missing_field",p,f"$.materials[{i}]",f"missing {k}"))
            if not (isinstance(x.get("baseColorSrgb"),list) and len(x.get("baseColorSrgb",[]))==3 and all(type(v) is int and 0<=v<=255 for v in x["baseColorSrgb"])): ds.append(diag("material_color",p,f"$.materials[{i}].baseColorSrgb","must be three bytes"))
            for k in ("metallicHint","roughnessHint"):
                if not isinstance(x.get(k),(int,float)) or not 0<=x[k]<=1: ds.append(diag("material_hint",p,f"$.materials[{i}].{k}","must be 0..1"))
            if x.get("opacityMode") not in ("opaque","mask","blend"): ds.append(diag("material_opacity",p,f"$.materials[{i}].opacityMode","must be opaque, mask, or blend"))
            if not isinstance(x.get("generationTags"),list) or not x.get("generationTags") or not all(isinstance(v,str) and v for v in x.get("generationTags",[])): ds.append(diag("material_tags",p,f"$.materials[{i}].generationTags","must be a non-empty string array"))
            kd=x.get("legacyMtl",{}).get("kd") if isinstance(x.get("legacyMtl"),dict) else None
            if not isinstance(kd,list) or len(kd)!=3 or not all(isinstance(v,(int,float)) and 0<=v<=1 for v in kd): ds.append(diag("material_mtl",p,f"$.materials[{i}].legacyMtl.kd","must be three normalized numbers"))
        if m.get("version")!=c.get("materialRegistry",{}).get("version"): ds.append(diag("material_version",p,"$.materialRegistry","version mismatch"))
    dp=c.get("depthProducts",{})
    required_depth={"height_metric","depth_guide","legacy_height"}
    if set(dp)!=required_depth: ds.append(diag("depth_products",p,"$.depthProducts","must contain exactly three products"))
    hm=dp.get("height_metric",{}); dg=dp.get("depth_guide",{}); lh=dp.get("legacy_height",{})
    expected_hm={"neutral":32768,"defaultRangeCells":0.25,"requiresExplicitRangeCells":True,"normalization":"none","clipping":"must be reported","seamChecks":"raw or decoded metric relief"}
    for k,v in expected_hm.items():
        if hm.get(k)!=v: ds.append(diag("depth_contract",p,f"$.depthProducts.height_metric.{k}","unexpected value"))
    if not hm.get("positiveRelief"): ds.append(diag("depth_contract",p,"$.depthProducts.height_metric.positiveRelief","required"))
    if dg.get("neutral")!=128 or dg.get("contrast")!=112 or dg.get("metric") is not False or not dg.get("normalization"): ds.append(diag("depth_contract",p,"$.depthProducts.depth_guide","unexpected value"))
    if lh.get("metric")!="ambiguous" or not lh.get("migration"): ds.append(diag("depth_contract",p,"$.depthProducts.legacy_height","unexpected value"))
    s, sd=(schema_data,[]) if schema_data is not None else load(root/"tools/asset-language/asset-record.schema.json"); ds+=sd
    if s:
        ds += validate_schema_agreement(s,c,str(root/"tools/asset-language/asset-record.schema.json"))
    return sorted(ds,key=lambda d:(d["path"],d["field"],d["code"],d["message"]))
def validate_record(record, path="<record>", root=ROOT):
    if not isinstance(record,dict): return [diag("record_type",path,"$","must be an object")]
    ds=[]
    req=["contractVersion","id","displayName","representation","role","authoringSpace","placementFrame","materials","states","defaultState","variants","sockets","sources","products","provenance"]
    for k in req:
        if k not in record: ds.append(diag("missing_field",path,f"$.{k}","required"))
    if record.get("contractVersion")!=1: ds.append(diag("contract_version",path,"$.contractVersion","must be 1"))
    if not isinstance(record.get("id"),str) or not ID.fullmatch(record.get("id","")): ds.append(diag("invalid_id",path,"$.id","must be lower snake case"))
    if not isinstance(record.get("displayName"),str) or not record.get("displayName").strip(): ds.append(diag("display_name",path,"$.displayName","must be a non-empty string"))
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
        if not isinstance(x.get("id"),str) or not ID.fullmatch(x.get("id","")): ds.append(diag("socket_id",path,f"$.sockets[{i}].id","must be lower snake case"))
        if x.get("id") in seen: ds.append(diag("duplicate_socket",path,f"$.sockets[{i}].id","duplicate"))
        seen.add(x.get("id"));
        if x.get("kind") not in SOCKETS: ds.append(diag("socket_kind",path,f"$.sockets[{i}].kind","unknown"))
        if "position" not in x: ds.append(diag("vector",path,f"$.sockets[{i}].position","required"))
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
        if k in sources:
            if not isinstance(sources[k],list): ds.append(diag("path_type",path,f"$.sources.{k}","must be an array of repository paths"))
            else: ds+=paths(sources[k],f"$.sources.{k}")
    prod=record.get("products",{})
    if not isinstance(prod,dict): ds.append(diag("object_type",path,"$.products","must be an object")); prod={}
    metric=prod.get("heightMetric")
    if metric is not None and not isinstance(metric,dict):
        ds.append(diag("product_type",path,"$.products.heightMetric","must be an object")); ds.append(diag("invalid_path",path,"$.products.heightMetric.path","metric product is malformed")); metric=None
    if metric:
        if not valid_path(metric.get("path")): ds.append(diag("invalid_path",path,"$.products.heightMetric.path","invalid"))
        if not isinstance(metric.get("rangeCells"),(int,float)) or not math.isfinite(metric.get("rangeCells",0)) or metric.get("rangeCells",0)<=0: ds.append(diag("range_cells",path,"$.products.heightMetric.rangeCells","must be positive finite"))
    for k in ("albedo","depthGuide","legacyHeight","model","preview","report","manifest","runtimeMetadata","materialLibrary"):
        if k in prod and not valid_path(prod[k]): ds.append(diag("invalid_path",path,f"$.products.{k}","invalid"))
    if metric and prod.get("depthGuide")==metric.get("path"): ds.append(diag("path_collision",path,"$.products","metric and guide paths must differ"))
    if "legacyHeight" in prod and "depthGuide" in prod and prod.get("legacyHeight")==prod.get("depthGuide"): ds.append(diag("path_collision",path,"$.products","legacy and guide paths must differ"))
    prov=record.get("provenance",{})
    if not isinstance(prov,dict): ds.append(diag("object_type",path,"$.provenance","must be an object")); prov={}
    for k in ("generator","generatorVersion","sourceCommit","command"):
        if not isinstance(prov.get(k),str) or not prov.get(k).strip(): ds.append(diag("provenance_field",path,f"$.provenance.{k}","must be a non-empty string"))
    seen=set()
    for group in ("inputs","outputs"):
        if group not in prov: ds.append(diag("provenance_type",path,f"$.provenance.{group}","must be an array"))
        entries=prov.get(group,[])
        if not isinstance(entries,list): ds.append(diag("provenance_type",path,f"$.provenance.{group}","must be an array")); entries=[]
        for i,x in enumerate(entries):
            if not isinstance(x,dict): ds.append(diag("provenance_entry",path,f"$.provenance.{group}[{i}]","must be an object")); continue
            if not valid_path(x.get("path")): ds.append(diag("invalid_path",path,f"$.provenance.{group}[{i}].path","invalid"))
            if x.get("path") in seen: ds.append(diag("duplicate_provenance_path",path,f"$.provenance.{group}[{i}].path","duplicate"))
            seen.add(x.get("path"));
            if "sha256" in x and (not isinstance(x["sha256"],str) or not re.fullmatch(r"[0-9a-f]{64}",x["sha256"])): ds.append(diag("sha256",path,f"$.provenance.{group}[{i}].sha256","must be lowercase hex") )
    source_paths=set()
    for key in ("blenderScript","blendInspection","prompt","referenceImages","sourceImages","metadataSource"):
        value=sources.get(key)
        if isinstance(value,str): source_paths.add(value)
        elif isinstance(value,list): source_paths.update(x for x in value if isinstance(x,str))
    output_paths={x.get("path") for x in prov.get("outputs",[]) if isinstance(x,dict)}
    for collision in sorted(source_paths & output_paths): ds.append(diag("source_output_collision",path,"$.provenance.outputs",f"output also declared as source: {collision}"))
    return sorted(ds,key=lambda d:(d["path"],d["field"],d["code"],d["message"]))
