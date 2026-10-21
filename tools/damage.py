"""Bounded native impact events; the receiving fighter runs the game's damage function."""
import math
from pathlib import Path
import re
import time

NAME=re.compile(r"^[A-Za-z0-9_./:-]{1,64}$")
EPOCH=re.compile(r"^[a-f0-9]{32}$")
MAP=re.compile(r"^/Game/Maps/[A-Za-z0-9_./:-]{1,220}$")
COMPONENT=re.compile(r"^[A-Za-z0-9_ -]{1,64}$")
SEVER_FIELDS={'kind','seq','victim','part','marker','source','bone','victim_frame','box1','box2','overlaps'}
FIELDS={"seq","victim","part","bone","point","normal","velocity","impulse","raw","cut","blunt","inside","lower","shock","stab"}
COMPLEX_FIELDS={"kind","seq","victim","part","bone","point","normal","velocity","impulse","cut","stab_rate","rigidity","blunt","lower","parent","kick"}

def vector(v):
    return isinstance(v,list) and len(v)==3 and all(type(n) in (int,float) and math.isfinite(n) and abs(n)<=1e7 for n in v)

def validate_damage(value):
    if value is None:return True
    if not isinstance(value,dict) or set(value)!={"epoch","map","events"}:return False
    if not isinstance(value["epoch"],str) or not EPOCH.fullmatch(value["epoch"]):return False
    if not isinstance(value["map"],str) or not MAP.fullmatch(value["map"]):return False
    if not isinstance(value["events"],list) or len(value["events"])>32:return False
    previous=-1
    for e in value["events"]:
        if not isinstance(e,dict):return False
        if e.get('kind')=='sever':
            from snapshot import transform
            if (set(e)!=SEVER_FIELDS or type(e['seq'])is not int or not previous<e['seq']<2**53
                    or type(e['victim'])is not int or not 1<=e['victim']<=9999999
                    or type(e['part'])is not int or not 0<=e['part']<=14
                    or not isinstance(e['marker'],str)or not COMPONENT.fullmatch(e['marker'])
                    or any(not isinstance(e[k],str)or not NAME.fullmatch(e[k])for k in ('source','bone'))
                    or not isinstance(e['victim_frame'],list)or len(e['victim_frame'])!=10 or not transform(e['victim_frame'])
                    or not isinstance(e['overlaps'],list)or len(e['overlaps'])>32
                    or any(not isinstance(n,str)or not COMPONENT.fullmatch(n)for n in e['overlaps'])):return False
            for key in ('box1','box2'):
                b=e[key]
                if (not isinstance(b,dict)or set(b)!={'transform','size'}or not isinstance(b['transform'],list)
                        or len(b['transform'])!=10 or not transform(b['transform'])or not vector(b['size'])
                        or any(not 0<=n<=10000 for n in b['size'])):return False
            previous=e['seq'];continue
        complex_hit=e.get("kind")=="complex"
        native='source' in e and not complex_hit
        extra={'box','victim_frame'} if complex_hit else {'box','victim_frame','source'} if native else set()
        if set(e)-extra!=(COMPLEX_FIELDS if complex_hit else FIELDS):return False
        if native and (not isinstance(e['source'],str) or not NAME.fullmatch(e['source']) or 'victim_frame' not in e):return False
        if 'victim_frame' in e:
            from snapshot import transform
            if not isinstance(e['victim_frame'],list) or len(e['victim_frame'])!=10 or not transform(e['victim_frame']):return False
        if 'box' in e:
            box=e['box'];t=box.get('transform') if isinstance(box,dict) else None
            if (not isinstance(box,dict) or set(box)!={'transform','size'} or not isinstance(t,list) or len(t)!=10
                    or any(type(n) not in (float,int) or not math.isfinite(n) or abs(n)>1e7 for n in t)
                    or not .5<=sum(n*n for n in t[3:7])<=1.5 or any(not 0<n<=100 for n in t[7:])
                    or not vector(box['size']) or any(not 0<=n<=10000 for n in box['size'])):return False
        if type(e["seq"]) is not int or not previous<e["seq"]<2**53:return False
        previous=e["seq"]
        if type(e["victim"]) is not int or not 1<=e["victim"]<=9999999:return False
        if any(not isinstance(e[k],str) or not NAME.fullmatch(e[k]) for k in ("part","bone")):return False
        if any(not vector(e[k]) for k in ("point","normal","velocity","impulse")):return False
        if any(type(e[k]) not in (int,float) or not math.isfinite(e[k]) or not 0<=e[k]<=1e6 for k in (("cut","stab_rate","rigidity","kick") if complex_hit else ("raw","cut"))):return False
        if type(e["blunt"]) is not int or not 0<=e["blunt"]<=16:return False
        if any(type(e[k]) is not bool for k in (("lower","parent") if complex_hit else ("inside","lower","shock","stab"))):return False
    return True

def damage_text(value):
    if value is None:return "OFF\n"
    lines=[f"HSDM1|{value['epoch']}|{value['map']}"]
    for e in value["events"]:
        if e.get('kind')=='sever':
            row=['S',e['seq'],e['victim'],e['part'],e['marker'],e['source'],e['bone'],*e['victim_frame']]
            for key in ('box1','box2'):row.extend([*e[key]['transform'],*e[key]['size']])
            row.extend([len(e['overlaps']),*e['overlaps']]);lines.append('|'.join(map(str,row)));continue
        complex_hit=e.get("kind")=="complex"
        values=["C" if complex_hit else "D",e["seq"],e["part"],e["bone"]]
        for k in ("point","normal","velocity","impulse"):values.extend(e[k])
        values.extend([e["cut"],e["stab_rate"],e["rigidity"],e["blunt"],int(e["lower"]),int(e["parent"]),e["kick"],e["victim"]] if complex_hit
            else [e["raw"],e["cut"],e["blunt"],int(e["inside"]),int(e["lower"]),int(e["shock"]),int(e["stab"]),e["victim"]])
        if not complex_hit and 'source' in e:
            values[0]='N';values.extend([e['source'],*e['victim_frame'],int('box'in e)])
            if 'box'in e:values.extend([*e['box']['transform'],*e['box']['size']])
        elif 'box' in e:values[0]='C2';values.extend([1,*e['box']['transform'],*e['box']['size']])
        if complex_hit and 'victim_frame' in e:
            if 'box' not in e:values.extend([0,0,0,0,0,0,0,1,1,1,1,0,0,0])
            values[0]='C3';values.extend(e['victim_frame'])
        lines.append("|".join(map(str,values)))
    lines.append(f"END|{len(lines)}")
    return "\n".join(lines)+"\n"

def read_damage(path:Path):
    try:
        stat=path.stat()
        if stat.st_size>32768 or time.time()-stat.st_mtime>2:return None
        text=path.read_text(encoding="ascii")
        if not text.endswith("\n"):return None
        lines=text.splitlines();h=lines[0].split("|")
        if len(h)!=3 or h[0]!="HSDM1" or lines[-1]!=f"END|{len(lines)-1}":return None
        events=[]
        for line in lines[1:-1]:
            p=line.split("|")
            if p[0]=='S':
                if len(p)<44 or not 0<=int(p[43])<=32 or len(p)!=44+int(p[43]):return None
                events.append({'kind':'sever','seq':int(p[1]),'victim':int(p[2]),'part':int(p[3]),'marker':p[4],
                    'source':p[5],'bone':p[6],'victim_frame':list(map(float,p[7:17])),
                    'box1':{'transform':list(map(float,p[17:27])),'size':list(map(float,p[27:30]))},
                    'box2':{'transform':list(map(float,p[30:40])),'size':list(map(float,p[40:43]))},'overlaps':p[44:]})
                continue
            if not ((len(p)==24 and p[0] in ('D','C')) or (len(p)==38 and p[0]=='C2' and p[24]=='1')
                    or (len(p)==48 and p[0]=='C3' and p[24] in ('0','1'))
                    or (p[0]=='N' and ((len(p)==36 and p[35]=='0')or(len(p)==49 and p[35]=='1')))):return None
            complex_hit=p[0] in ('C','C2','C3')
            if any(p[i] not in ("0","1") for i in ((20,21) if complex_hit else (19,20,21,22))):return None
            event={"seq":int(p[1]),"victim":int(p[23]),"part":p[2],"bone":p[3],
                "point":list(map(float,p[4:7])),"normal":list(map(float,p[7:10])),
                "velocity":list(map(float,p[10:13])),"impulse":list(map(float,p[13:16]))}
            event.update({"kind":"complex","cut":float(p[16]),"stab_rate":float(p[17]),"rigidity":float(p[18]),
                "blunt":int(p[19]),"lower":p[20]=="1","parent":p[21]=="1","kick":float(p[22])} if complex_hit else
                {"raw":float(p[16]),"cut":float(p[17]),"blunt":int(p[18]),"inside":p[19]=="1",
                 "lower":p[20]=="1","shock":p[21]=="1","stab":p[22]=="1"})
            if p[0] in ('C2','C3') and p[24]=='1':event['box']={'transform':list(map(float,p[25:35])),'size':list(map(float,p[35:38]))}
            if p[0]=='C3':event['victim_frame']=list(map(float,p[38:48]))
            if p[0]=='N':
                event.update(source=p[24],victim_frame=list(map(float,p[25:35])))
                if p[35]=='1':event['box']={'transform':list(map(float,p[36:46])),'size':list(map(float,p[46:49]))}
            events.append(event)
        value={"epoch":h[1],"map":h[2],"events":events}
        return value if validate_damage(value) else None
    except (OSError,ValueError,IndexError,UnicodeError):return None
