import json, re
from pathlib import Path
try:
    from PIL import Image
except ImportError:
    Image=None
ROOT=Path(__file__).resolve().parents[3]
def walk_models(data, source, node=None, path='$'):
    node=data if node is None else node; out=[]
    if isinstance(node,dict):
        for k,v in node.items(): out += walk_models(data,source,v,path+'.'+k)
        if isinstance(node.get('model'),str) and node['model'].lower().endswith('.obj'): out.append({'source':source,'jsonPath':path+'.model','model':node['model']})
    elif isinstance(node,list):
        for i,v in enumerate(node): out += walk_models(data,source,v,f'{path}[{i}]')
    return out
def obj_metrics(root, ref):
    p=root/ref; vs=[]; uvs=[]; ns=[]; faces=uses=0; lib=None
    for line in p.read_text(encoding='utf-8').splitlines():
        if line.startswith('v '): vs.append([float(x) for x in line.split()[1:4]])
        elif line.startswith('vt '): uvs.append(line)
        elif line.startswith('vn '): ns.append(line)
        elif line.startswith('f '): faces+=1
        elif line.startswith('usemtl '): uses+=1
        elif line.startswith('mtllib '): lib=line.split(None,1)[1].strip()
    return {'path':str(ref).replace('\\','/'),'vertexCount':len(vs),'uvCount':len(uvs),'normalCount':len(ns),'faceCount':faces,'materialUseCount':uses,'mtllib':lib,'bounds':{'min':[round(min(v[i] for v in vs),6) for i in range(3)] if vs else [0,0,0],'max':[round(max(v[i] for v in vs),6) for i in range(3)] if vs else [0,0,0]}}
def snapshot(root=ROOT):
    def read(rel): return json.loads((root/rel).read_text(encoding='utf-8'))
    items=walk_models(read('data/items.json'),'data/items.json'); worlds=walk_models(read('data/tilesets.json'),'data/tilesets.json'); refs=sorted(items+worlds,key=lambda x:(x['source'],x['jsonPath'],x['model']))
    assets=[]
    for ap in sorted((root/'assets/geometry').rglob('asset.json')):
        rel=ap.relative_to(root).as_posix(); d=json.loads(ap.read_text(encoding='utf-8')); imgs=[]
        for name in ('albedo.png','height.png'):
            ip=ap.parent/name
            with Image.open(ip) as im: imgs.append({'path':name,'width':im.width,'height':im.height,'mode':im.mode})
        assets.append({'assetJson':rel,'id':d.get('id'),'topology':d.get('topology'),'role':d.get('role'),'requiredImages':imgs})
    manifest=read('assets/geometry/1_blender_depth_maps/manifest.json'); depths=[{k:m.get(k) for k in ('preset','surface','view','tileAxes','size','wrapOk')} for m in manifest.get('maps',[])]
    models=[]
    for x in refs:
        if (root/x['model']).is_file(): models.append(obj_metrics(root,x['model']))
    return {'snapshotVersion':1,'sourceCommit':git_commit(root),'contractVersion':1,'itemModelReferences':sorted(items,key=lambda x:(x['jsonPath'],x['model'])),'worldModelReferences':sorted(worlds,key=lambda x:(x['jsonPath'],x['model'])),'geometryAssets':assets,'depthPresets':sorted(depths,key=lambda x:x['preset']),'referencedModels':sorted(models,key=lambda x:x['path'])}
def git_commit(root):
    import subprocess
    try: return subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()
    except Exception: return None
def compare(root, baseline):
    cur=snapshot(root); ds=[]
    for key in ('itemModelReferences','worldModelReferences','geometryAssets','depthPresets','referencedModels'):
        b=baseline.get(key,[]); c=cur.get(key,[])
        if key in ('itemModelReferences','worldModelReferences'):
            cm={(x['source'],x['jsonPath']):x['model'] for x in c}
            for x in b:
                if cm.get((x['source'],x['jsonPath']))!=x['model']: ds.append(f'{key}: changed {x}')
            for x in c:
                if not (root/x['model']).is_file(): ds.append(f'{key}: missing model {x["model"]}')
        else:
            bm={json.dumps(x,sort_keys=True):x for x in b}; cm={json.dumps(x,sort_keys=True):x for x in c}
            if key=='geometryAssets':
                for x in b:
                    match=next((y for y in c if y['assetJson']==x['assetJson']),None)
                    if match and match!=x: ds.append(f'{key}: changed {x["assetJson"]}')
            elif key=='depthPresets':
                for x in b:
                    match=next((y for y in c if y['preset']==x['preset']),None)
                    if match and match!=x: ds.append(f'{key}: changed {x["preset"]}')
            else:
                for x in b:
                    match=next((y for y in c if y['path']==x['path']),None)
                    if match and match!=x: ds.append(f'{key}: changed {x["path"]}')
    return sorted(ds)
