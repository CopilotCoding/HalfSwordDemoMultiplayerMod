"""Host coordinates round boundaries; each peer remains authoritative for its fighter."""
import re
import secrets

REASONS={"waiting","ready","host_dead","guest_dead","host_gave_up","guest_gave_up",
         "host_unconscious","guest_unconscious","both_out","respawning"}

def alive(pose):
    if not pose:return False
    v=pose["vitals"]
    return (v.get("health",100)>0 and v.get("consciousness",100)>0
        and not v.get("dead",0) and not v.get("headless",0) and not v.get("give_up",0))

def outcome(side,pose):
    v=pose["vitals"]
    if v.get("give_up"):return side+"_gave_up"
    if v.get("consciousness",100)<=0 and v.get("health",100)>0 and not v.get("headless"):return side+"_unconscious"
    return side+"_dead"


def defeat(side, victim, attacker):
    if not alive(victim):
        return outcome(side,victim)
    v=attacker["vitals"]
    # A native opponent can die before the victim's next injury update. Its
    # result is usable only for these exact two fighters in this round.
    if (v.get("hit_owner_id")==victim["vitals"].get("owner_id")
            and v.get("hit_attacker_id")==v.get("owner_id")
            and v.get("hit_revision",0)>0):
        if v.get("hit_health",100)<=0:return side+"_dead"
        if v.get("hit_consciousness",100)<=0:return side+"_unconscious"
    return None

def validate_round(value):
    if value is None:return True
    return (isinstance(value,dict) and set(value)=={"session","id","phase","remaining_ms","reason"}
        and isinstance(value["session"],str) and re.fullmatch(r"[a-f0-9]{32}",value["session"]) is not None
        and type(value["id"]) is int and 0<=value["id"]<2**31
        and isinstance(value["phase"],str) and value["phase"] in ("waiting","playing","restart","respawning")
        and type(value["remaining_ms"]) is int and 0<=value["remaining_ms"]<=3000
        and isinstance(value["reason"],str) and value["reason"] in REASONS)

class Rounds:
    def __init__(self):
        self.session=secrets.token_hex(16)
        self.id=0;self.phase="waiting";self.reason="waiting";self.deadline=0
        self.previous_owners=(None,None)
        self.map=None
    def restart(self,local,remote,connected):
        if (not connected or self.phase not in ("playing","restart") or self.id<1
                or not local or not remote or local["map"]!=remote["map"] or local["map"]!=self.map):
            return False
        owners=(local["vitals"].get("owner_id"),remote["vitals"].get("owner_id"))
        if not all(owners):return False
        self.previous_owners=owners
        self.id+=1;self.phase="respawning";self.reason="respawning";self.deadline=0
        return True
    def observe(self,local,remote,connected,now):
        if not connected:
            self.phase="waiting";self.reason="waiting"
        elif local and remote and local["map"]==remote["map"]:
            if self.map is not None and self.map!=local["map"]:
                self.session=secrets.token_hex(16);self.id=0;self.phase="waiting";self.previous_owners=(None,None)
            self.map=local["map"]
            owners=(local["vitals"].get("owner_id"),remote["vitals"].get("owner_id"))
            if self.phase=="restart":
                if now>=self.deadline:
                    self.id+=1;self.phase="respawning";self.reason="respawning"
            elif self.phase=="respawning":
                if all(owners) and all(a!=b for a,b in zip(owners,self.previous_owners)) and alive(local) and alive(remote):
                    self.phase="playing";self.reason="ready"
            elif all(owners):
                if self.id==0:self.id=1
                host_out,guest_out=defeat("host",local,remote),defeat("guest",remote,local)
                if host_out or guest_out:
                    self.previous_owners=owners;self.phase="restart";self.deadline=now+3
                    self.reason="both_out" if host_out and guest_out else host_out or guest_out
                else:self.phase="playing";self.reason="ready"
        elif local and remote and local["map"]!=remote["map"]:
            self.phase="waiting";self.reason="waiting"
        elif self.phase not in ("restart","respawning"):
            self.phase="waiting";self.reason="waiting"
        if connected and self.phase=="restart" and now>=self.deadline:
            self.id+=1;self.phase="respawning";self.reason="respawning"
        return {"session":self.session,"id":self.id,"phase":self.phase,
            "remaining_ms":max(0,min(3000,int((self.deadline-now)*1000))) if self.phase=="restart" else 0,"reason":self.reason}
