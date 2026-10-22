"""One host round clock for an owner-authoritative free-for-all."""
import secrets
from rounds import alive,defeat

class PartyRounds:
    def __init__(self):
        self.session=secrets.token_hex(16);self.id=0;self.phase='waiting';self.reason='waiting'
        self.participants={};self.previous={};self.eliminated=set();self.winner=0;self.deadline=0;self.map=None;self.missing={}
    def restart(self,players,connected=True,allow_respawning=False):
        if not connected or self.id<1:return False
        if self.phase in ('waiting','respawning')and not allow_respawning:return False
        if any(p and self.map is not None and p['map']!=self.map for p in players.values()):return False
        owners={slot:(p['vitals']['owner_id']if p else self.participants.get(slot))for slot,p in players.items()}
        owners={slot:owner for slot,owner in owners.items()if owner}
        if len(owners)<2:return False
        self.previous=owners
        self.participants=dict(self.previous);self.eliminated=set();self.winner=0
        self.missing={}
        self.id+=1;self.phase='respawning';self.reason='respawning';self.deadline=0
        return True
    def observe(self,players,connected,now):
        ready={slot:p for slot,p in players.items()if p and p['vitals'].get('owner_id')}
        if ready:
            game_map=ready[1]['map']if 1 in ready else self.map or next(iter(ready.values()))['map']
            ready={slot:p for slot,p in ready.items()if p['map']==game_map}
            if self.map is not None and game_map!=self.map:
                self.__init__()
            self.map=game_map
        if not connected:
            self.phase='waiting';self.reason='waiting'
        elif self.phase=='respawning':
            self.previous={slot:owner for slot,owner in self.previous.items()if slot in players}
            if len(self.previous)<2:
                self.phase='waiting';self.reason='waiting'
            elif (all(slot in ready and alive(ready[slot]) and
                    ready[slot]['vitals']['owner_id']!=owner for slot,owner in self.previous.items())):
                self.participants={slot:ready[slot]['vitals']['owner_id']for slot in self.previous}
                self.phase='playing';self.reason='ready'
        elif self.phase=='restart':
            if now>=self.deadline:self.restart(players,True)
        elif len(ready)>=2 or self.phase=='playing':
            if self.id==0:
                self.id=1;self.participants={slot:p['vitals']['owner_id']for slot,p in ready.items()}
                self.phase='playing';self.reason='ready'
            elif self.phase=='waiting':
                self.restart(players,True,allow_respawning=True)
            newcomers={slot for slot,p in ready.items()if slot not in self.participants
                       or p['vitals']['owner_id']!=self.participants[slot]}
            if newcomers and self.phase=='playing':
                self.restart(players,True)
            else:
                for slot,owner in self.participants.items():
                    p=ready.get(slot)
                    if p:self.missing.pop(slot,None)
                    else:self.missing.setdefault(slot,now)
                    confirmed=p and p['vitals']['owner_id']==owner and (
                        not alive(p)or any(defeat('guest',p,attacker)for other,attacker in ready.items()if other!=slot))
                    if slot not in players or confirmed:
                        self.eliminated.add(slot)
                    elif p is None and now-self.missing[slot]>2:self.eliminated.add(slot)
                survivors=set(self.participants)-self.eliminated
                if len(survivors)<=1:
                    self.winner=next(iter(survivors),0);self.phase='restart';self.reason='both_out'
                    self.deadline=now+3
        return {'session':self.session,'id':self.id,'phase':self.phase,'reason':self.reason,
                'remaining_ms':max(0,min(3000,int((self.deadline-now)*1000)))if self.phase=='restart'else 0}
