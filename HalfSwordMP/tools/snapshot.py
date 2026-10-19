"""Bounded portable avatar state, shared by the file and network adapters."""
import math
from pathlib import Path
import re
import time

MAX_BODY = 262144
NAME = re.compile(r"^[A-Za-z0-9_./:-]{1,240}$")
PARAMETER = re.compile(r"^[A-Za-z0-9_ ./:-]{1,64}$")
VITALS = {"health", "consciousness", "head", "chest", "abdomen", "arm_r", "arm_l",
          "leg_r", "leg_l", "neck", "dead", "headless", "blood_rate", "bloody_feet", "owner_id", "give_up"}
INJURY_FIELDS={"health","consciousness","head","chest","abdomen","arm_r","arm_l","leg_r","leg_l","neck"}
VITALS|={"hit_"+key for key in INJURY_FIELDS}|{"hit_owner_id","hit_attacker_id","hit_revision"}


def finite(values, count, limit):
    return (isinstance(values, list) and len(values) == count
            and all(type(v) in (int, float) and abs(v) <= limit and math.isfinite(v) for v in values))


def name(value):
    return isinstance(value, str) and NAME.fullmatch(value) is not None


def transform(value):
    return (finite(value[:3], 3, 10_000_000) and finite(value[3:7], 4, 1.01)
            and finite(value[7:], 3, 100) and 0.95 <= sum(q*q for q in value[3:7]) <= 1.05)


def bones_ok(bones):
    if not isinstance(bones, list) or len(bones) > 128:
        return False
    seen = set()
    for bone in bones:
        if (not isinstance(bone, list) or len(bone) != 11 or not name(bone[0])
                or len(bone[0]) > 64 or bone[0] in seen or not transform(bone[1:])):
            return False
        seen.add(bone[0])
    return True


def materials_ok(materials):
    return (isinstance(materials, list) and len(materials) <= 16
            and all(m == "-" or name(m) for m in materials))


def hidden_ok(hidden):
    return (isinstance(hidden, list) and len(hidden) <= 128
            and all(name(n) and len(n) <= 64 for n in hidden) and len(set(hidden)) == len(hidden))


def parameters_ok(parameters, materials):
    if not isinstance(parameters, list) or len(parameters) > 128:
        return False
    seen = set()
    for p in parameters:
        if (not isinstance(p, list) or len(p) != 5 or type(p[0]) is not int
                or not 0 <= p[0] < len(materials) or not isinstance(p[1], str) or not PARAMETER.fullmatch(p[1])
                or type(p[2]) is not int or p[2] not in (0, 1, 2)
                or type(p[3]) is not int or not -1 <= p[3] <= 63
                or (p[0], p[1], p[2], p[3]) in seen or not isinstance(p[4], list)
                or len(p[4]) not in (1, 4) or not finite(p[4], len(p[4]), 10_000_000)):
            return False
        seen.add((p[0], p[1], p[2], p[3]))
    return True


def validate_pose(pose):
    if pose is None:
        return True
    required={"map", "mesh", "root", "bones", "parts", "materials", "hidden", "vitals", "parameters", "effects"}
    if not isinstance(pose, dict) or set(pose)-{"colliders","equipment","velocity","drops","pickups"}!=required:
        return False
    from dropped import validate_items,validate_requests
    if not validate_items(pose.get('drops',[]))or not validate_requests(pose.get('pickups',[])):return False
    if "velocity"in pose and not finite(pose["velocity"],3,5000):return False
    if "equipment" in pose:
        from equipment import validate_equipment
        if not validate_equipment(pose["equipment"]):return False
    if "colliders" in pose:
        from geometry import validate_geometry
        if not validate_geometry(pose["colliders"]):return False
    if (not name(pose["map"]) or not name(pose["mesh"])
            or not finite(pose["root"], 6, 10_000_000) or not bones_ok(pose["bones"])
            or not materials_ok(pose["materials"]) or not hidden_ok(pose["hidden"])
            or not parameters_ok(pose["parameters"], pose["materials"])):
        return False
    parts, vitals = pose["parts"], pose["vitals"]
    if (not isinstance(parts, list) or len(parts) > 48 or not isinstance(vitals, dict)
            or not set(vitals) <= VITALS
            or any(not finite([v], 1, 10_000_000) for v in vitals.values())):
        return False
    if "owner_id" in vitals and (type(vitals["owner_id"]) is not int or not 1<=vitals["owner_id"]<=9999999):
        return False
    for key in ("hit_owner_id","hit_attacker_id"):
        if key in vitals and (type(vitals[key])is not int or not 1<=vitals[key]<=9999999):return False
    if "hit_revision"in vitals and (type(vitals["hit_revision"])is not int or not 0<=vitals["hit_revision"]<10000000):return False
    seen, total = set(), len(pose["bones"])
    for part in parts:
        if not isinstance(part, dict) or set(part) != {
                "id", "kind", "asset", "transform", "bones", "materials", "hidden", "parameters"}:
            return False
        if (not name(part["id"]) or part["id"] == "body" or part["id"] in seen
                or part["kind"] not in ("S", "K", "L", "D", "T") or not name(part["asset"])
                or not isinstance(part["transform"], list) or not transform(part["transform"])
                or not bones_ok(part["bones"]) or not materials_ok(part["materials"])
                or not hidden_ok(part["hidden"]) or not parameters_ok(part["parameters"], part["materials"])):
            return False
        if part["kind"] in ("S","D","T") and (part["bones"] or part["hidden"]):
            return False
        if part["kind"] in ("D","T") and (not part["asset"].startswith("/Game/Assets/Weapons/")
                                     or "/Collisions/" in part["asset"]):
            return False
        if part["kind"] == "L" and part["bones"]:
            return False
        seen.add(part["id"])
        total += len(part["bones"])
    effects=pose["effects"]
    if not isinstance(effects,list) or len(effects)>16:
        return False
    seen=set()
    lengths={"F":1,"I":1,"V":3,"C":4}
    for effect in effects:
        if (not isinstance(effect,dict) or set(effect)!={"id","asset","transform","parameters"}
                or not name(effect["id"]) or effect["id"] in seen
                or not name(effect["asset"]) or not effect["asset"].startswith("/Game/Effects/Blood/")
                or not isinstance(effect["transform"],list) or not transform(effect["transform"])
                or not isinstance(effect["parameters"],list) or len(effect["parameters"])>64):
            return False
        seen.add(effect["id"])
        names=set()
        for p in effect["parameters"]:
            if (not isinstance(p,list) or len(p)!=3 or not isinstance(p[0],str) or p[0] not in lengths
                    or not isinstance(p[1],str) or not PARAMETER.fullmatch(p[1]) or not p[1].startswith("User.")
                    or p[1] in names or not finite(p[2],lengths[p[0]],10000000)
                    or (p[0]=="I" and (type(p[2][0]) is not int or abs(p[2][0])>1000000))):
                return False
            names.add(p[1])
    return total <= 2048


def pose_text(pose, counter):
    if pose is None:
        return f"OFF|{counter}\n"
    lines = ["|".join(["HSMP2", str(counter), pose["map"], pose["mesh"],
                       *(str(n) for n in pose["root"])])]
    if "velocity"in pose:lines.append("|".join(["S",*(str(n)for n in pose["velocity"])]))
    def mesh_lines(identifier, mesh):
        for b in mesh["bones"]:
            lines.append("|".join(["B", identifier, *(str(n) for n in b)]))
        for slot, material in enumerate(mesh["materials"]):
            lines.append(f"M|{identifier}|{slot}|{material}")
        for slot, parameter, association, index, value in mesh["parameters"]:
            lines.append("|".join(["P", identifier, str(slot), parameter, str(association), str(index), *(str(n) for n in value)]))
        lines.extend(f"H|{identifier}|{bone}" for bone in mesh["hidden"])
    mesh_lines("body", pose)
    for part in pose["parts"]:
        lines.append("|".join(["C", part["id"], part["kind"], part["asset"],
                               *(str(n) for n in part["transform"])]))
        mesh_lines(part["id"], part)
    lines.extend(f"V|{k}|{v}" for k, v in pose["vitals"].items())
    if "equipment" in pose:
        from equipment import equipment_lines
        lines.append("GEAR|1")
        lines.extend(equipment_lines(pose["equipment"]))
    if 'drops'in pose or 'pickups'in pose:
        from dropped import item_lines
        lines.extend(item_lines(pose.get('drops',[]),pose.get('pickups',[])))
    for g in pose.get("colliders",[]):
        lines.append("|".join(["G",g["id"],g["shape"],g["asset"],
            *(str(n) for n in g["transform"]),*(str(n) for n in g["size"]),
            str(g["object"]),g["responses"],g["material"],str(g["mode"])]))
    for effect in pose["effects"]:
        lines.append("|".join(["N",effect["id"],effect["asset"],*(str(n) for n in effect["transform"])]))
        for kind,name,value in effect["parameters"]:
            lines.append("|".join(["Q",effect["id"],kind,name,*(str(n) for n in value)]))
    lines.append(f"E|{counter}|{len(lines)}")
    return "\n".join(lines) + "\n"


def read_pose(path: Path):
    try:
        stat = path.stat()
        if time.time() - stat.st_mtime > 1.0 or stat.st_size > MAX_BODY:
            return None
        text = path.read_text(encoding="ascii")
        if len(text) > MAX_BODY or not text.endswith("\n"):
            return None
        lines = text.splitlines()
        h = lines[0].split("|")
        if len(h) != 10 or h[0] != "HSMP2":
            return None
        if lines[-1].split("|") != ["E", h[1], str(len(lines) - 1)]:
            return None
        pose = {"map": h[2], "mesh": h[3], "root": [float(n) for n in h[4:]],
                "bones": [], "parts": [], "materials": [], "hidden": [], "vitals": {}, "parameters": [], "effects": []}
        meshes = {"body": pose}
        effects={}
        weapons={}
        drops={}
        for line in lines[1:-1]:
            f = line.split("|")
            if f[0]=='DW'and len(f)==14 and f[1]not in drops:
                item={'id':f[1],'class':f[2],'transform':[float(n)for n in f[3:13]],'grant':int(f[13])}
                drops[f[1]]=item;pose.setdefault('drops',[]).append(item)
            elif f[0]=='DR'and len(f)==4:
                pose.setdefault('pickups',[]).append({'owner':int(f[1]),'id':f[2],'hand':f[3]})
            elif f[0]in('DK','DZ','DL','DY','DO')and len(f)>1 and f[1]in drops:
                from equipment import read_construction
                read_construction(drops[f[1]],[f[0][1:],*f[1:]])
            elif f[0]=="S"and len(f)==4 and "velocity"not in pose:
                pose["velocity"]=[float(n)for n in f[1:]]
            elif f==["GEAR","1"] and "equipment" not in pose:
                pose["equipment"]={"weapons":[],"armor":[]}
            elif f[0]=="W" and len(f)==3 and f[1] not in weapons and "equipment" in pose:
                w={"slot":f[1],"class":f[2],"components":[]};weapons[f[1]]=w
                pose["equipment"]["weapons"].append(w)
            elif f[0]=="I" and len(f)==5 and f[1] in weapons:
                weapons[f[1]]["components"].append(f[2:])
            elif f[0] in ("K","Z","L","Y","O") and len(f)>1 and f[1] in weapons:
                from equipment import read_construction
                read_construction(weapons[f[1]],f)
            elif f[0]=="J" and len(f)==4 and f[1] in weapons:
                properties=weapons[f[1]].setdefault("state",{})
                if f[2] in properties:return None
                value=float(f[3])
                if f[2] in ("Dismemberment Level Sharp","Dismemberment Level Blunt") and value.is_integer():value=int(value)
                properties[f[2]]=value
            elif f[0]=="A" and len(f)==3 and "equipment" in pose:
                pose["equipment"]["armor"].append([int(f[1]),f[2]])
            elif f[0]=='DYE'and len(f)==14 and 'equipment'in pose:
                matches=[a for a in pose['equipment']['armor']if a[0]==int(f[1])and len(a)==2]
                if len(matches)!=1:return None
                matches[0].extend([[float(n)for n in f[i:i+4]]for i in (2,6,10)])
            elif f[0] == "C" and len(f) == 14 and f[1] not in meshes and len(pose["parts"]) < 48:
                part = {"id": f[1], "kind": f[2], "asset": f[3],
                        "transform": [float(n) for n in f[4:]], "bones": [], "materials": [], "hidden": [], "parameters": []}
                meshes[f[1]] = part
                pose["parts"].append(part)
            elif f[0] == "B" and len(f) == 13:
                meshes[f[1]]["bones"].append([f[2], *(float(n) for n in f[3:])])
            elif f[0] == "M" and len(f) == 4:
                materials = meshes[f[1]]["materials"]
                if int(f[2]) != len(materials):
                    return None
                materials.append(f[3])
            elif f[0] == "H" and len(f) == 3:
                meshes[f[1]]["hidden"].append(f[2])
            elif f[0] == "P" and len(f) in (7, 10):
                meshes[f[1]]["parameters"].append([int(f[2]), f[3], int(f[4]), int(f[5]), [float(n) for n in f[6:]]])
            elif f[0]=="N" and len(f)==13 and f[1] not in effects and len(effects)<16:
                effect={"id":f[1],"asset":f[2],"transform":[float(n) for n in f[3:]],"parameters":[]}
                effects[f[1]]=effect
                pose["effects"].append(effect)
            elif f[0]=="Q" and len(f) in (5,7,8):
                effects[f[1]]["parameters"].append([f[2],f[3],[(int(n) if f[2]=="I" else float(n)) for n in f[4:]]])
            elif f[0]=="G" and len(f)==21:
                pose.setdefault("colliders",[]).append({"id":f[1],"shape":f[2],"asset":f[3],
                    "transform":[float(n) for n in f[4:14]],"size":[float(n) for n in f[14:17]],
                    "object":int(f[17]),"responses":f[18],"material":f[19],"mode":int(f[20])})
            elif f[0] == "V" and len(f) == 3 and f[1] not in pose["vitals"]:
                pose["vitals"][f[1]] = int(f[2]) if f[1] in ("owner_id","hit_owner_id","hit_attacker_id","hit_revision") else float(f[2])
            else:
                return None
        return pose if validate_pose(pose) else None
    except (OSError, ValueError, KeyError, IndexError, UnicodeError):
        return None

