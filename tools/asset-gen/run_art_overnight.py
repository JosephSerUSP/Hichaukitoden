"""Deterministic, resume-safe, local-only overnight artwork scheduler.

The campaign JSON is the art-directorial plan. This process only selects an
already-defined job, invokes the repository's real gen.py pipeline, records
evidence, and writes reports. It never calls an LLM or invents a prompt.
"""
from __future__ import annotations
import argparse, base64, ctypes, datetime as dt, html, json, os, subprocess, sys, time, urllib.request
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]; TOOL=ROOT/'tools'/'asset-gen'
SPEC=TOOL/'batches'/'art_overnight_20260807.json'; OUT=TOOL/'out'/'art-overnight-20260807'
STATE=OUT/'status.json'; JOBS=OUT/'jobs.json'; SUMMARY=OUT/'summary.json'; MD=OUT/'summary.md'; REPORT=OUT/'report.html'; PID=OUT/'run.pid'
PYTHON=sys.executable; PREFIX='overnight16_20260807_'

def ts(): return dt.datetime.now().isoformat(timespec='seconds')
def atomic(p,v):
    p.parent.mkdir(parents=True,exist_ok=True); t=p.with_suffix(p.suffix+'.tmp'); t.write_text(json.dumps(v,indent=2,ensure_ascii=True)+'\n',encoding='utf-8'); t.replace(p)
def safe(s): return ''.join(c if c.isalnum() or c in '_-' else '_' for c in str(s))
def load(): return json.loads(SPEC.read_text(encoding='utf-8'))
def check(spec,jobs):
    errors=[]; ids=set()
    for s in spec['studies']:
        if s['studyId'] in ids: errors.append('duplicate study '+s['studyId'])
        ids.add(s['studyId'])
        if sum(1 for a in s['arms'] if a.get('control'))!=1: errors.append('study must have one control: '+s['studyId'])
        for a in s['arms']:
            if a.get('height') and not (ROOT/a['height']).is_file(): errors.append('missing height '+a['height'])
            for l in a.get('loras',s.get('base',{}).get('loras',[])):
                if not l.get('name'): errors.append('empty lora in '+s['studyId'])
    if not forge_ok(): errors.append('Forge unavailable')
    else:
        try:
            models={x.get('model_name') or x.get('title','').split('.')[0] for x in json.loads(urllib.request.urlopen('http://127.0.0.1:7860/sdapi/v1/sd-models',timeout=8).read())}
            loras={x.get('name') for x in json.loads(urllib.request.urlopen('http://127.0.0.1:7860/sdapi/v1/loras',timeout=8).read())}
            for j in jobs:
                if j['model'] not in models: errors.append('missing model '+j['model'])
                for l in j['loras']:
                    if l['name'] not in loras: errors.append('missing LoRA '+l['name'])
        except Exception as e: errors.append('inventory query: '+str(e))
    if errors: raise SystemExit('\n'.join(errors))
    print(json.dumps({'ok':True,'studies':len(spec['studies']),'jobs':len(jobs),'controls':sum(1 for j in jobs if j['control'])},indent=2))
def forge_ok():
    try: urllib.request.urlopen('http://127.0.0.1:7860/sdapi/v1/progress',timeout=8); return True
    except Exception: return False
def keep_awake(on):
    if os.name=='nt':
        try: ctypes.windll.kernel32.SetThreadExecutionState(0x80000000|(1 if on else 0) if on else 0x80000000)
        except Exception: pass

def expand(spec):
    jobs=[]; seen=set(); studies=spec['studies']
    for si,study in enumerate(studies):
        base=study.get('base',{}); policy=spec['providerPolicy']['fast' if study['tier'] in ('P3','P4') else 'quality']
        for ai,arm in enumerate(study['arms']):
            jid=f"{PREFIX}{study['studyId']}_{arm['id']}"
            if jid in seen: raise ValueError(f'duplicate job id {jid}')
            seen.add(jid); merged={**policy,**base,**arm}
            desc=merged.get('description',study['subjectId'])
            for key in ('promptSuffix','variation'):
                if merged.get(key): desc += ', '+str(merged[key])
            job={'jobId':jid,'studyId':study['studyId'],'category':study['category'],'tier':study['tier'],'priority':study['priority'],'class':study['class'],'subjectId':study['subjectId'],'subjectSource':study['subjectSource'],'question':study['question'],'variable':study['variable'],'armId':arm['id'],'control':bool(arm.get('control')),'name':jid,'description':desc,'provider':merged['provider'],'model':merged['model'],'steps':merged['steps'],'cfg':merged['cfg'],'sampler':merged['sampler'],'variants':int(merged.get('variants',study.get('variants',1 if study['tier'] in ('P3','P4') else 2))),'seed':410700+si*101+ai*17,'requestSize':merged.get('requestSize'),'height':merged.get('height'),'depthWeight':merged.get('depthWeight'),'loras':merged.get('loras',[])}
            jobs.append(job)
    return jobs
def run_for(job):
    for p in (TOOL/'out').glob(f"{job['class']}-{safe(job['name'])}-*"):
        mp=p/'manifest.json'
        if not mp.is_file(): continue
        try: m=json.loads(mp.read_text(encoding='utf-8'))
        except Exception: continue
        if m.get('name')!=job['name'] or len(m.get('variants',[]))<job['variants']: continue
        if any(not (p/v.get('file','')).is_file() for v in m.get('variants',[])): continue
        return p
    return None
def augment(job,p,status='success',error=None):
    mp=p/'manifest.json'; m=json.loads(mp.read_text(encoding='utf-8'))
    m['campaign']={'campaignId':PREFIX,'jobId':job['jobId'],'studyId':job['studyId'],'category':job['category'],'subjectId':job['subjectId'],'subjectSource':job['subjectSource'],'question':job['question'],'variable':job['variable'],'armId':job['armId'],'control':job['control'],'generationStatus':status,'error':error,'curation':{'decision':'unset','notes':''}}
    for v in m.get('variants',[]): v['candidateId']=f"{job['jobId']}#v{v.get('index')}"; v.setdefault('curation',{'decision':'unset','notes':''})
    atomic(mp,m); return m
def cmd(job):
    a=[PYTHON,'-u',str(TOOL/'gen.py'),'generate',job['class'],job['name'],job['description'],'--provider',job['provider'],'--model',job['model'],'--variants',str(job['variants']),'--steps',str(job['steps']),'--cfg',str(job['cfg']),'--sampler',job['sampler'],'--seed',str(job['seed']),'--request-size',job['requestSize']]
    if job.get('height'): a += ['--height',job['height'],'--depth-weight',str(job.get('depthWeight') or .1)]
    for l in job.get('loras',[]): a += ['--lora',f"{l['name']}:{l.get('weight',.55)}"]
    return a
def state0(jobs,hours,mode):
    start=time.time(); return {'schemaVersion':1,'mode':mode,'campaignId':PREFIX,'startedAt':ts(),'startEpoch':start,'requestedHours':hours,'deadlineEpoch':start+hours*3600,'generationCutoffEpoch':start+hours*3600-15*60,'updatedAt':ts(),'currentJob':None,'jobs':[{'jobId':j['jobId'],'status':'pending','attempts':0} for j in jobs],'timing':{},'errors':[]}
def load_state(jobs,hours,mode):
    if mode=='run' and STATE.is_file():
        try:
            s=json.loads(STATE.read_text(encoding='utf-8'))
            if [x['jobId'] for x in s.get('jobs',[])]==[j['jobId'] for j in jobs]: return s
        except Exception: pass
    return state0(jobs,hours,mode)
def report(jobs,s):
    groups={}
    for j in jobs:
        p=run_for(j)
        if not p: continue
        try: m=json.loads((p/'manifest.json').read_text(encoding='utf-8'))
        except Exception: continue
        groups.setdefault((j['category'],j['studyId']),[]).append((j,p,m))
    cards=[]
    for (cat,study),items in sorted(groups.items()):
        question=items[0][0]['question']; var=items[0][0]['variable']; cards.append(f'<section><h2>{html.escape(cat)} / {html.escape(study)}</h2><p><b>Single variable:</b> {html.escape(var)}<br>{html.escape(question)}</p><div class="grid">')
        for j,p,m in items:
            for v in m.get('variants',[]):
                def img(k):
                    f=p/v.get(k,''); return ('data:image/png;base64,'+base64.b64encode(f.read_bytes()).decode()) if f.is_file() else ''
                cards.append(f'<article><h3>{html.escape(j["armId"])}{" (control)" if j["control"] else ""}</h3><p>{html.escape(j["subjectId"])} · {html.escape(v.get("candidateId", ""))}</p><img src="{img("raw")}" alt="raw"><img src="{img("file")}" alt="processed"><details><summary>provenance</summary><pre>{html.escape(json.dumps(j,indent=2))}</pre></details></article>')
        cards.append('</div></section>')
    REPORT.write_text('<!doctype html><meta charset="utf-8"><title>Second Rite overnight16</title><style>body{background:#111;color:#eee;font:14px system-ui;max-width:1800px;margin:auto;padding:24px}section{border-top:1px solid #555;padding:18px 0}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(330px,1fr));gap:12px}article{background:#20242c;padding:10px}img{width:48%;height:220px;object-fit:contain;background:#090a0c}pre{white-space:pre-wrap;font-size:11px}</style>'+''.join(cards),encoding='utf-8')
def summary(jobs,s):
    counts={}; cat={}
    for j,r in zip(jobs,s['jobs']):
        counts[r['status']]=counts.get(r['status'],0)+1; x=cat.setdefault(j['category'],{'studies':set(),'jobs':0,'candidates':0,'seconds':0}); x['studies'].add(j['studyId']); x['jobs']+=1; x['candidates'] += j['variants'] if r['status']=='success' else 0; x['seconds'] += r.get('seconds',0)
    out={'generatedAt':ts(),'campaignId':PREFIX,'start':s.get('startedAt'),'finish':s.get('finishedAt'),'requestedHours':s.get('requestedHours'),'reasonStopped':s.get('reasonStopped'),'counts':counts,'plannedStudies':len({j['studyId'] for j in jobs}),'attemptedStudies':len({j['studyId'] for j,r in zip(jobs,s['jobs']) if r['status']!='pending'}),'jobs':len(jobs),'categories':{k:{**v,'studies':len(v['studies']),'percentageOfRenderSeconds':round(100*v['seconds']/max(1,sum(x['seconds'] for x in cat.values())),1)} for k,v in cat.items()},'review':load()['review'],'report':str(REPORT.relative_to(ROOT)).replace('\\','/'),'status':str(STATE.relative_to(ROOT)).replace('\\','/'),'manifest':str(SPEC.relative_to(ROOT)).replace('\\','/'),'errors':s.get('errors',[])}; atomic(SUMMARY,out); lines=['# Second Rite overnight16 campaign','',f"Campaign: `{PREFIX}`",f"Start: {out['start']}",f"Finish: {out['finish']}",f"Stop reason: {out['reasonStopped']}",'',f"Planned studies: {out['plannedStudies']} · jobs: {len(jobs)} · successful candidates: {sum(v['candidates'] for v in out['categories'].values())}",'','## Distribution','', '| Category | Studies | Jobs | Candidates | Render % |','|---|---:|---:|---:|---:|']; lines += [f"| {k} | {v['studies']} | {v['jobs']} | {v['candidates']} | {v['percentageOfRenderSeconds']}% |" for k,v in out['categories'].items()]; lines += ['', '## Review',f"- Report: `{out['report']}`",f"- Status: `{out['status']}`",f"- Manifest: `{out['manifest']}`",f"- Rating queue: {out['review']['url']}",'','No owner scores are fabricated; all candidates remain staged and unpromoted.']; MD.write_text('\n'.join(lines)+'\n',encoding='utf-8')
def main(argv=None):
    global SPEC,OUT,STATE,JOBS,SUMMARY,MD,REPORT,PID,PREFIX
    ap=argparse.ArgumentParser(); ap.add_argument('--hours',type=float,default=16); ap.add_argument('--spec'); ap.add_argument('--output'); ap.add_argument('--prefix'); ap.add_argument('--dry-run',action='store_true'); ap.add_argument('--check',action='store_true'); ap.add_argument('--smoke',action='store_true'); ap.add_argument('--report-only',action='store_true'); args=ap.parse_args(argv)
    if args.spec: SPEC=ROOT/args.spec if not os.path.isabs(args.spec) else Path(args.spec)
    if args.prefix: PREFIX=args.prefix
    if args.output: OUT=ROOT/args.output if not os.path.isabs(args.output) else Path(args.output); STATE=OUT/'status.json'; JOBS=OUT/'jobs.json'; SUMMARY=OUT/'summary.json'; MD=OUT/'summary.md'; REPORT=OUT/'report.html'; PID=OUT/'run.pid'
    if args.smoke:
        OUT=TOOL/'out'/'art-overnight-smoke-20260807'; STATE=OUT/'status.json'; JOBS=OUT/'jobs.json'; SUMMARY=OUT/'summary.json'; MD=OUT/'summary.md'; REPORT=OUT/'report.html'; PID=OUT/'run.pid'
    spec=load(); jobs=expand(spec); OUT.mkdir(parents=True,exist_ok=True); atomic(JOBS,jobs)
    if args.check: check(spec,jobs); return 0
    if args.dry_run: print(json.dumps({'studies':len(spec['studies']),'jobs':len(jobs),'candidates':sum(j['variants'] for j in jobs),'categories':{c:sum(1 for j in jobs if j['category']==c) for c in sorted({j['category'] for j in jobs})}},indent=2)); return 0
    if args.report_only:
        s=load_state(jobs,args.hours,'run'); report(jobs,s); summary(jobs,s); return 0
    if args.smoke:
        jobs=[next(j for j in jobs if j['category']=='texture'), next(j for j in jobs if j['category']=='portrait')]
        for j in jobs: j.update(provider='forge-lcm',model='dreamshaper_8LCM',steps=6,cfg=2,sampler='LCM',variants=1)
        args.hours=.25
    s=load_state(jobs,args.hours,'smoke' if args.smoke else 'run')
    if args.smoke: s['generationCutoffEpoch']=s['deadlineEpoch']-30
    keep_awake(True)
    try:
        for i,j in enumerate(jobs):
            r=s['jobs'][i]; p=run_for(j)
            if p: augment(j,p); r.update(status='success',runPath=str(p.relative_to(ROOT)).replace('\\','/'),updatedAt=ts()); atomic(STATE,s); continue
            if time.time() >= s['generationCutoffEpoch']: r.update(status='skipped',reason='generation cutoff'); continue
            r.update(status='running',attempts=r.get('attempts',0)+1); s['currentJob']=j['jobId']; s['updatedAt']=ts(); atomic(STATE,s)
            if not forge_ok():
                subprocess.run([PYTHON,str(TOOL/'forge.py'),'start'],cwd=ROOT,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,check=False)
                for _ in range(12):
                    if forge_ok(): break
                    time.sleep(5)
            if not forge_ok():
                s['errors'].append({'jobId':j['jobId'],'error':'Forge unavailable after bounded restart'}); r.update(status='failed',error='Forge unavailable'); atomic(STATE,s); continue
            start=time.time(); result=None
            for attempt in range(2):
                result=subprocess.run(cmd(j),cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,check=False); (OUT/'runner.log').open('a',encoding='utf-8').write(f"\n[{ts()}] {j['jobId']} attempt {attempt+1}\n{result.stdout}")
                p=run_for(j)
                if result.returncode==0 and p: break
            if p:
                augment(j,p); r.update(status='success',runPath=str(p.relative_to(ROOT)).replace('\\','/'),seconds=round(time.time()-start,1),updatedAt=ts())
            else: r.update(status='failed',seconds=round(time.time()-start,1),error=f'exit {getattr(result,"returncode",None)}'); s['errors'].append({'jobId':j['jobId'],'error':r['error']})
            s['currentJob']=None; s['updatedAt']=ts(); atomic(STATE,s); report(jobs,s); summary(jobs,s)
        s['finishedAt']=ts(); s['reasonStopped']='completed queue' if all(r['status'] in ('success','skipped') for r in s['jobs']) else 'queue ended with failures'; s['updatedAt']=ts(); atomic(STATE,s); report(jobs,s); summary(jobs,s)
    finally: keep_awake(False)
    return 0
if __name__=='__main__': raise SystemExit(main())
