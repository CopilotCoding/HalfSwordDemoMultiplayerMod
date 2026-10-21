"""Bounded native equipment collision geometry; no executable actor classes."""
from snapshot import name,transform,finite

MAX_COLLIDERS=96

def validate_geometry(items):
    if not isinstance(items,list) or len(items)>MAX_COLLIDERS:return False
    seen=set()
    for g in items:
        if (not isinstance(g,dict) or set(g)!={"id","shape","asset","transform","size","object","responses","material","mode"}
                or not name(g["id"]) or g["id"] in seen or len(g["id"])>64
                or g["shape"] not in ("box","capsule","sphere","mesh")
                or not isinstance(g["transform"],list) or not transform(g["transform"])
                or not finite(g["size"],3,1000) or min(g["size"])<0
                or type(g["object"]) is not int or not 0<=g["object"]<32
                or type(g["mode"]) is not int or g["mode"] not in (1,2,3)
                or not isinstance(g["responses"],str) or len(g["responses"])!=32 or set(g["responses"])-set("012")
                or (g["material"]!="-" and (not name(g["material"]) or not g["material"].startswith("/Game/")))
                or any(".." in str(g[k]) for k in ("asset","material"))):return False
        if g["shape"]=="mesh":
            if not name(g["asset"]) or not g["asset"].startswith(("/Game/Assets/Weapons/","/Game/Assets/Armor/")):return False
        elif g["asset"]!="-":return False
        if g["shape"]=="box" and min(g["size"])<=0:return False
        if g["shape"] in ("capsule","sphere") and g["size"][0]<=0:return False
        if g["shape"]=="capsule" and g["size"][1]<g["size"][0]:return False
        seen.add(g["id"])
    return True
