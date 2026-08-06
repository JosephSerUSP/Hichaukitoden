import argparse, json, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from lib.validation import validate_contract, validate_record, load, ROOT
from lib.regression import snapshot, compare

def print_diagnostics(items):
    for item in items:
        print(json.dumps(item, sort_keys=True) if isinstance(item, dict) else item)

def main(argv=None):
    p=argparse.ArgumentParser(prog="asset-check"); sub=p.add_subparsers(dest="cmd")
    sub.add_parser("contract"); r=sub.add_parser("record"); r.add_argument("files",nargs="+"); sub.add_parser("regression"); sub.add_parser("all"); s=sub.add_parser("snapshot"); s.add_argument("--output",required=True); s.add_argument("--force",action="store_true")
    a=p.parse_args(argv)
    if not a.cmd: p.print_help(); return 2
    if a.cmd=="contract":
        ds=validate_contract()
        if ds: print("ASSET CONTRACT FAIL"); [print(json.dumps(d,sort_keys=True)) for d in ds]; return 1
        print("ASSET CONTRACT OK"); return 0
    if a.cmd=="record":
        bad=0
        for f in a.files:
            d,ds=load(f)
            if not ds: ds=validate_record(d,f)
            if ds: bad=1; print(f"ASSET RECORD FAIL {f}"); [print(json.dumps(x,sort_keys=True)) for x in ds]
            else: print(f"ASSET RECORD OK {f}")
        return bad
    if a.cmd=="snapshot":
        out=Path(a.output); out=out if out.is_absolute() else ROOT/out
        if out.exists() and not a.force: print(f"refusing to overwrite {a.output}",file=sys.stderr); return 2
        out.parent.mkdir(parents=True,exist_ok=True); out.write_text(json.dumps(snapshot(),indent=2)+"\n",encoding="utf-8"); return 0
    if a.cmd=="all" and main(["contract"]): return 1
    base=ROOT/"docs/asset-pipeline/baseline/asset-regression.json"
    try: ds=compare(ROOT,json.loads(base.read_text(encoding="utf-8")))
    except Exception as e: print(f"ASSET REGRESSION FAIL\n{e}"); return 1
    if ds: print("ASSET REGRESSION FAIL"); print_diagnostics(ds); return 1
    print("ASSET REGRESSION OK")
    if a.cmd=="all": print("ASSET LANGUAGE OK")
    return 0
if __name__=="__main__": raise SystemExit(main())
