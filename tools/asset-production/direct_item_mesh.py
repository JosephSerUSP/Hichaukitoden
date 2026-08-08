"""Small deterministic mesh/OBJ helpers for direct low-poly item fabrication."""
import math


def add(a,b): return a[0]+b[0],a[1]+b[1],a[2]+b[2]
def sub(a,b): return a[0]-b[0],a[1]-b[1],a[2]-b[2]
def mul(a,s): return a[0]*s,a[1]*s,a[2]*s
def length(a): return math.sqrt(a[0]**2+a[1]**2+a[2]**2)
def cross(a,b): return a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]
def normalize(a):
    n=length(a)
    if n<1e-9: raise ValueError("zero vector")
    return a[0]/n,a[1]/n,a[2]/n


class Mesh:
    def __init__(self,name): self.name=name; self.vertices=[]; self.faces=[]
    def v(self,p):
        self.vertices.append(tuple(round(x,6) for x in p)); return len(self.vertices)
    def tri(self,mat,a,b,c):
        pa,pb,pc=self.vertices[a-1],self.vertices[b-1],self.vertices[c-1]
        if length(cross(sub(pb,pa),sub(pc,pa)))<1e-8: raise ValueError(f"degenerate face in {self.name}: {a} {b} {c}")
        self.faces.append((mat,(a,b,c)))
    def quad(self,mat,a,b,c,d): self.tri(mat,a,b,c); self.tri(mat,a,c,d)
    def box(self,center,size,mat):
        cx,cy,cz=center; hx,hy,hz=size[0]/2,size[1]/2,size[2]/2
        p=[(cx-hx,cy-hy,cz-hz),(cx+hx,cy-hy,cz-hz),(cx+hx,cy+hy,cz-hz),(cx-hx,cy+hy,cz-hz),(cx-hx,cy-hy,cz+hz),(cx+hx,cy-hy,cz+hz),(cx+hx,cy+hy,cz+hz),(cx-hx,cy+hy,cz+hz)]
        i=[self.v(x) for x in p]
        for q in [(0,3,2,1),(4,5,6,7),(0,1,5,4),(3,7,6,2),(0,4,7,3),(1,2,6,5)]: self.quad(mat,*(i[k] for k in q))
    def extrude(self,points,z0,z1,mat):
        n=len(points); lo=[self.v((x,y,z0)) for x,y in points]; hi=[self.v((x,y,z1)) for x,y in points]
        for k in range(1,n-1): self.tri(mat,lo[0],lo[k+1],lo[k]); self.tri(mat,hi[0],hi[k],hi[k+1])
        for k in range(n):
            j=(k+1)%n; self.quad(mat,lo[k],lo[j],hi[j],hi[k])
    def prism_between(self,p0,p1,r0,r1,sides,mat,phase=0.0):
        axis=normalize(sub(p1,p0)); helper=(0,0,1) if abs(axis[2])<.85 else (1,0,0); u=normalize(cross(axis,helper)); v=cross(axis,u); rings=[]
        for p,r in [(p0,r0),(p1,r1)]:
            ring=[]
            for k in range(sides):
                a=phase+2*math.pi*k/sides; off=add(mul(u,math.cos(a)*r),mul(v,math.sin(a)*r)); ring.append(self.v(add(p,off)))
            rings.append(ring)
        c0,c1=self.v(p0),self.v(p1)
        for k in range(sides):
            j=(k+1)%sides; self.tri(mat,c0,rings[0][j],rings[0][k]); self.tri(mat,c1,rings[1][k],rings[1][j]); self.quad(mat,rings[0][k],rings[0][j],rings[1][j],rings[1][k])
    def diamond(self,center,radius,height,mat,sides=6):
        cx,cy,cz=center; eq=[self.v((cx+radius*math.cos(2*math.pi*k/sides),cy,cz+radius*math.sin(2*math.pi*k/sides))) for k in range(sides)]; top=self.v((cx,cy+height/2,cz)); bot=self.v((cx,cy-height/2,cz))
        for k in range(sides):
            j=(k+1)%sides; self.tri(mat,top,eq[k],eq[j]); self.tri(mat,bot,eq[j],eq[k])
    def center(self):
        lo=[min(p[i] for p in self.vertices) for i in range(3)]; hi=[max(p[i] for p in self.vertices) for i in range(3)]; c=[(lo[i]+hi[i])/2 for i in range(3)]
        self.vertices=[tuple(round(p[i]-c[i],6) for i in range(3)) for p in self.vertices]


def sword(m,*,length_,half_width,thickness,guard,grip,point,blade_mat="wrought_iron",accent=None,shoulder=0,fuller=False,split_tip=False):
    y0=-length_/2+grip+.25; y1=length_/2-point
    if split_tip:
        poly=[(-half_width,y0),(-half_width-shoulder,y0+.35),(-half_width*.72,y1),(-half_width*.35,y1+point*.48),(0,y1+point*.25),(half_width*.35,y1+point*.48),(half_width*.72,y1),(half_width+shoulder,y0+.35),(half_width,y0)]
    else:
        poly=[(-half_width,y0),(-half_width-shoulder,y0+.32),(-half_width*.78,y1),(0,y1+point),(half_width*.78,y1),(half_width+shoulder,y0+.32),(half_width,y0)]
    m.extrude(poly,-thickness/2,thickness/2,blade_mat); m.box((0,y0-.10,0),(guard,.16,thickness*2),accent or blade_mat); m.prism_between((0,y0-.16,0),(0,y0-grip,0),.11,.09,6,"dark_wood"); m.diamond((0,y0-grip-.08,0),.16,.20,accent or blade_mat,4)
    if fuller:
        m.box((0,(y0+y1)/2,thickness*.55),(half_width*.22,(y1-y0)*.72,thickness*.16),accent or "ritual_gold"); m.box((0,(y0+y1)/2,-thickness*.55),(half_width*.22,(y1-y0)*.72,thickness*.16),accent or "ritual_gold")


def write_model(mesh,path,label,mats):
    used=[]
    for mat,_ in mesh.faces:
        if mat not in used: used.append(mat)
    missing=[m for m in used if m not in mats]
    if missing: raise ValueError(f"unregistered materials in {path.stem}: {missing}")
    obj=["# Second Rite deterministic item batch 53-62",f"# {label}","mtllib item_batch_53_62.mtl",f"o {path.stem}","s off"]+[f"v {x:.6f} {y:.6f} {z:.6f}" for x,y,z in mesh.vertices]; current=None
    for mat,face in mesh.faces:
        if mat!=current: obj.append(f"usemtl {mat}"); current=mat
        obj.append("f "+" ".join(map(str,face)))
    path.write_text("\n".join(obj)+"\n",encoding="utf-8")
    lo=[min(p[i] for p in mesh.vertices) for i in range(3)]; hi=[max(p[i] for p in mesh.vertices) for i in range(3)]
    return {"vertices":len(mesh.vertices),"triangles":len(mesh.faces),"materials":used,"bounds":[lo,hi]}


def validate_obj(path):
    verts=[]; faces=[]; uses=[]; mtllib=None
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("v "): verts.append(tuple(map(float,line.split()[1:4])))
        elif line.startswith("f "): faces.append(tuple(int(x.split('/')[0]) for x in line.split()[1:]))
        elif line.startswith("usemtl "): uses.append(line.split(None,1)[1])
        elif line.startswith("mtllib "): mtllib=line.split(None,1)[1]
    if not verts or not faces or not mtllib: raise ValueError(f"incomplete OBJ {path}")
    mtl=path.with_name(mtllib)
    if not mtl.is_file(): raise ValueError(f"missing MTL {mtl}")
    declared={x.split(None,1)[1] for x in mtl.read_text(encoding="utf-8").splitlines() if x.startswith("newmtl ")}
    if not set(uses)<=declared: raise ValueError(f"undeclared material in {path}")
    for f in faces:
        if len(f)!=3 or min(f)<1 or max(f)>len(verts): raise ValueError(f"bad face in {path}")
        a,b,c=(verts[i-1] for i in f)
        if length(cross(sub(b,a),sub(c,a)))<1e-8: raise ValueError(f"degenerate triangle in {path}")
