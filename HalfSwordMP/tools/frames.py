"""Swap the arena's two spawn viewpoints without moving either native player."""
import copy
from pathlib import Path
import math
import time

def read_frame(path:Path,owner=None):
    try:
        text=path.read_text(encoding="ascii")
        if len(text)>256 or not text.endswith("\n"):return None
        p=text.strip().split("|")
        if len(p)!=8 or p[0]not in("HSFRAME1","HSFRAME2") or time.time()-float(p[7])>3:return None
        frame_owner=int(p[1]);values=list(map(float,p[2:6]))
        if owner is not None and frame_owner!=owner:return None
        if not 1<=frame_owner<=9999999 or not all(math.isfinite(v) and abs(v)<1e7 for v in values):return None
        return False if p[0]=="HSFRAME2"else((values[0]+values[2])/2,(values[1]+values[3])/2)
    except (OSError,ValueError,UnicodeError):return None


class ArenaFrame:
    """The arena coordinate system lasts for the map, including respawns.

    The native writer pauses during reset. A missing/partial/old heartbeat is
    not a request to reflect every existing fighter back to the other spawn.
    """
    def __init__(self):
        self.map = None
        self.center = None

    def resolve(self, path, pose):
        if pose is not None:
            if pose["map"] != self.map:
                self.map, self.center = pose["map"], None
            candidate = read_frame(path, pose["vitals"].get("owner_id"))
            if self.center is None and candidate is not None:
                self.center = candidate
        return self.center

def point(values,center):
    values[0],values[1]=2*center[0]-values[0],2*center[1]-values[1]

def direction(values):values[0],values[1]=-values[0],-values[1]

def transform(values,center):
    point(values,center)
    x,y,z,w=values[3:7]
    values[3:7]=[-y,x,w,-z]  # World yaw 180 multiplied by the captured quaternion.

def pose_frame(pose,center):
    if pose is None or center is None or center is False:return pose
    result=copy.deepcopy(pose)
    if "velocity"in result:direction(result["velocity"])
    point(result["root"],center);result["root"][4]=(result["root"][4]+360)%360-180
    for bone in result["bones"]:
        t=bone[1:];transform(t,center);bone[1:]=t
    for part in result["parts"]:
        transform(part["transform"],center)
        for bone in part["bones"]:
            t=bone[1:];transform(t,center);bone[1:]=t
    for collider in result.get("colliders",[]):transform(collider["transform"],center)
    for item in result.get('drops',[]):transform(item['transform'],center)
    for effect in result["effects"]:
        transform(effect["transform"],center)
        for kind,name,values in effect["parameters"]:
            if kind=="V":
                label=name.lower()
                if "position" in label or "location" in label:point(values,center)
                elif "direction" in label or "velocity" in label or "impulse" in label:direction(values)
    return result

def damage_frame(damage,center):
    if damage is None or center is None or center is False:return damage
    result=copy.deepcopy(damage)
    for event in result["events"]:
        if event.get('kind')=='sever':
            transform(event['victim_frame'],center)
            for key in ('box1','box2'):transform(event[key]['transform'],center)
            continue
        point(event["point"],center)
        for key in ("normal","velocity","impulse"):direction(event[key])
        if 'box' in event:transform(event['box']['transform'],center)
        if 'victim_frame' in event:transform(event['victim_frame'],center)
    return result

def input_frame(control,center):
    if control is None or center is None or center is False or "view" not in control:return control
    result=copy.deepcopy(control)
    result["view"][1]=(result["view"][1]+360)%360-180
    return result
