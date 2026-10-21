"""Bounded references to the demo's native equipment, never arbitrary actors."""
import re
import math
from snapshot import name

COMPONENT=re.compile(r"^[A-Za-z0-9_ -]{1,64}$")
BOOLEAN={"Double Edged","NoStab","Shield"}
INTEGER={"Dismemberment Level Sharp","Dismemberment Level Blunt"}
PROPERTIES={"Rigidity","Edge Sharpness","Tip Sharpness","Stab Rate","Mat Density","Weapon Length",
            "Wound Shape","Brush Scale","Draw Cut Rate","Dismemberment Level Sharp","Dismemberment Level Blunt"}|BOOLEAN
PART_ASSETS={"grip_mesh","grip","head","guard","pommel","sub1","sub2"}
PART_SIZES={"head","guard","pommel"}


def validate_construction(p):
    if not isinstance(p,dict) or set(p)!={"assets","sizes","layers","colors","coat"}:return False
    assets,sizes=p["assets"],p["sizes"]
    if not isinstance(assets,dict) or set(assets)!=PART_ASSETS:return False
    for key,value in assets.items():
        if value=="-":continue
        if (not name(value) or not value.startswith("/Game/Assets/Weapons/") or ".." in value or ":" in value
                or (key!="grip_mesh" and not value.endswith("_C"))):return False
    if not isinstance(sizes,dict) or set(sizes)!=PART_SIZES:return False
    for v in sizes.values():
        if (not isinstance(v,list) or len(v)!=3 or any(type(n) not in (int,float)
                or not math.isfinite(n) or not 0<n<=100 for n in v)):return False
    if type(p["coat"])is not int or not 0<=p["coat"]<=1000000:return False
    for key,length in (("layers",2),("colors",5)):
        rows=p[key]
        if not isinstance(rows,list) or len(rows)>4:return False
        seen=set()
        for row in rows:
            if (not isinstance(row,list) or len(row)!=length or type(row[0])is not int
                    or not 0<=row[0]<4 or row[0] in seen):return False
            seen.add(row[0])
            if key=="layers":
                if type(row[1])is not int or not 0<=row[1]<16:return False
            elif any(type(n)not in(int,float)or not math.isfinite(n)or not 0<=n<=100 for n in row[1:]):return False
    return True


def construction_lines(slot,p):
    lines=[f"K|{slot}|{k}|{v}" for k,v in p["assets"].items()]
    lines.extend("|".join(map(str,["Z",slot,k,*v])) for k,v in p["sizes"].items())
    lines.extend("|".join(map(str,[tag,slot,*row])) for tag,key in (("L","layers"),("Y","colors")) for row in p[key])
    lines.append(f"O|{slot}|{p['coat']}")
    return lines


def read_construction(w,row):
    tag=row[0]
    p=w.setdefault("construction",{"assets":{},"sizes":{},"layers":[],"colors":[]})
    if tag=="K" and len(row)==4 and row[2] not in p["assets"]:p["assets"][row[2]]=row[3]
    elif tag=="Z" and len(row)==6 and row[2] not in p["sizes"]:p["sizes"][row[2]]=[float(n)for n in row[3:]]
    elif tag=="L" and len(row)==4:p["layers"].append([int(n)for n in row[2:]])
    elif tag=="Y" and len(row)==7:p["colors"].append([int(row[2]),*(float(n)for n in row[3:])])
    elif tag=="O" and len(row)==3 and "coat"not in p:p["coat"]=int(row[2])
    else:raise ValueError("Malformed native weapon construction")


def class_path(value,kind):
    prefix={"weapon":"/Game/Assets/Weapons/", "armor":"/Game/Assets/Armor/Blueprints/"}[kind]
    return (name(value) and value.startswith(prefix) and value.endswith("_C")
            and ".." not in value and ":" not in value)


def validate_equipment(value):
    if not isinstance(value,dict) or set(value)!={"weapons","armor"}:return False
    weapons,armor=value["weapons"],value["armor"]
    if not isinstance(weapons,list) or len(weapons)>2 or not isinstance(armor,list) or len(armor)>32:return False
    slots=set();ids=set();count=0
    for w in weapons:
        if (not isinstance(w,dict) or set(w)-{"state","construction"}!={"slot","class","components"}
                or w["slot"] not in ("right","left") or w["slot"] in slots
                or not class_path(w["class"],"weapon") or not isinstance(w["components"],list)):
            return False
        if "construction" in w and not validate_construction(w["construction"]):return False
        state=w.get("state",{})
        if (not isinstance(state,dict) or not set(state)<=PROPERTIES
                or any(type(v) not in (float,int) or not math.isfinite(v) or abs(v)>10000000
                       or (k in INTEGER and (v!=int(v) or not 0<=v<=100))
                       or (k in BOOLEAN and v not in (0,1)) for k,v in state.items())):return False
        slots.add(w["slot"]);components=set()
        for c in w["components"]:
            count+=1
            if (count>96 or not isinstance(c,list) or len(c)!=3
                    or not isinstance(c[0],str) or not COMPONENT.fullmatch(c[0]) or c[0] in components
                    or not name(c[1]) or len(c[1])>64 or not name(c[2]) or len(c[2])>64
                    or c[2] in ids):return False
            components.add(c[0]);ids.add(c[2])
    slots=set()
    for a in armor:
        if (not isinstance(a,list) or len(a)not in (2,5) or type(a[0]) is not int or not 0<=a[0]<32
                or a[0] in slots or not class_path(a[1],"armor")):return False
        if len(a)==5 and any(not isinstance(c,list)or len(c)!=4 or any(type(n)not in(int,float)
                or not math.isfinite(n)or not 0<=n<=100 for n in c)for c in a[2:]):return False
        slots.add(a[0])
    return True


def equipment_lines(value):
    lines=[]
    for w in value["weapons"]:
        lines.append(f"W|{w['slot']}|{w['class']}")
        if "construction" in w:lines.extend(construction_lines(w["slot"],w["construction"]))
        lines.extend("|".join(["I",w["slot"],*c]) for c in w["components"])
        lines.extend(f"J|{w['slot']}|{key}|{value}" for key,value in w.get("state",{}).items())
    for a in value['armor']:
        lines.append(f'A|{a[0]}|{a[1]}')
        if len(a)==5:lines.append('|'.join(map(str,['DYE',a[0],*(n for c in a[2:]for n in c)])))
    return lines
