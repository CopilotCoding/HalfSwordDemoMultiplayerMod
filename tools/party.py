"""Authenticated host relay. Each player still owns their native fighter.

Each forwarded datagram carries one fighter, avoiding aggregate snapshot limits.
Passwords, replay checks, fragmentation and native pose validation reuse network.py.
"""
import json,secrets,socket,time
from pathlib import Path
from network import Peer,Reassembly,pack,unpack,fragments,MAX_DATAGRAM,TIMEOUT,NONCE,atomic_write
from snapshot import read_pose,validate_pose,pose_text
from damage import read_damage,validate_damage,damage_text
from frames import ArenaFrame,pose_frame,damage_frame
from party_rounds import PartyRounds
from network import Bridge as LegacyBridge
import admission

DEFAULT_PLAYERS=4
MAX_PLAYERS=16
def player_limit(value):
    if type(value)is not int or not 2<=value<=MAX_PLAYERS:raise ValueError(f'Choose a host limit from 2 to {MAX_PLAYERS} players.')
    return value
def slot_id(value):return type(value)is int and 1<=value<=MAX_PLAYERS

class Bridge:
    write_round=LegacyBridge.write_round
    local_pose=LegacyBridge.local_pose
    respawn_retry_ready=LegacyBridge.respawn_retry_ready
    restart_ready=LegacyBridge.restart_ready
    def __init__(self,role,code,build,runtime,port=7777,address=None,bind='0.0.0.0',*,password='',transport=None,target=None,max_players=DEFAULT_PLAYERS):
        if not 1<=port<=65535:raise ValueError('Port must be between 1 and 65535')
        self.max_players=player_limit(max_players);self.runtime=Path(runtime);self.runtime.mkdir(parents=True,exist_ok=True)
        if transport is None:target=(socket.gethostbyname(address),port)if role=='join'and address else None
        if role=='join'and target is None:raise ValueError("Joining requires the host's IP or hostname")
        self.peer=Peer(role,code,build,target,password)
        self.socket=transport or socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
        try:
            if transport is None:self.socket.bind((bind,port if role=='host'else 0))
            self.socket.setblocking(False)
        except OSError:self.socket.close();raise
        self.links={};self.slots={};self.members={1:self.peer.session}if role=='host'else{}
        self.slot=1 if role=='host'else 0;self.party_session=self.peer.session if role=='host'else None
        self.roster_revision=0;self.roster_sequence=-1;self.member_sequences={};self.member_counter=0
        self.players={};self.damage_maps={};self.written={};self.counter=0;self.last_primary=0
        self.directories=set();self.last_roster=None;self.last_roster_write=-1e9
        self.rounds=PartyRounds()if role=='host'else None;self.round_state=None
        self.eliminated=set();self.winner=0
        self.restart_request=None;self.restart_sequence=0
        self.round_mark=None;self.round_mark_at=time.monotonic()
        self.last_send=self.last_hello=self.last_ping=self.last_status=self.last_files=-1e9
        self.last_round_signature=None;self.last_round_write=-1e9
        self.frame=None;self.arena_frame=ArenaFrame();self.cached_local_pose=None;self.cached_local_pose_at=-1e9
        self.assembly=Reassembly(self.peer.key);self.rejected=0;self.send_errors=0;self.last_send_error=''
        self.was_connected=False;self.last_phase=None
        for name,text in (('remote.pose','OFF|0\n'),('remote.input','OFF\n'),('local.input','OFF\n'),
                          ('remote.damage','OFF\n'),('local.damage','OFF\n'),('round.cfg','OFF\n'),('frame.cfg','OFF\n'),('roster.cfg','OFF\n')):
            atomic_write(self.runtime/name,text)
    def peer_addresses(self):
        return {a for a,p in self.links.items()if p.connected}if self.peer.role=='host'else({self.peer.address}if self.peer.connected else set())
    @property
    def population(self):return 1+len(self.peer_addresses())if self.peer.role=='host'else len(self.members)
    def send(self,message,address):
        try:
            for datagram in fragments(pack(message,self.peer.key),self.peer.key):self.socket.sendto(datagram,address)
        except (ValueError,OSError)as exc:self.send_errors+=1;self.last_send_error=str(exc)
    def directory(self,slot):return self.runtime/'opponents'/str(slot)
    def primary(self):return min((slot for slot in self.members if slot!=self.slot),default=0)
    def outgoing_damage(self):
        result={};primary=self.primary()
        for slot in self.members:
            if slot==self.slot:continue
            value=read_damage((self.runtime if slot==primary else self.directory(slot))/'local.damage')
            if value is not None:result[slot]=value
        return result
    def validate_impacts(self,value):
        return (isinstance(value,dict)and len(value)<=MAX_PLAYERS and
                all(isinstance(k,str)and k.isascii()and k.isdigit()and slot_id(int(k))and validate_damage(v)for k,v in value.items()))
    def metadata(self,slot):
        return {'slot':slot,'limit':self.max_players,'session':self.party_session,'revision':self.roster_revision,
                'members':[[s,t]for s,t in sorted(self.members.items())],
                'eliminated':sorted(self.eliminated&self.members.keys()),'winner':self.winner if self.winner in self.members else 0}
    def valid_metadata(self,m):
        if (not isinstance(m,dict)or set(m)!={'slot','limit','session','revision','members','eliminated','winner'}
                or not slot_id(m['slot'])or not 2<=m['slot']<=MAX_PLAYERS or type(m['limit'])is not int
                or not 2<=m['limit']<=MAX_PLAYERS or not isinstance(m['session'],str)or not NONCE.fullmatch(m['session'])
                or type(m['revision'])is not int or not 0<=m['revision']<2**53
                or not isinstance(m['members'],list)or not 2<=len(m['members'])<=m['limit']):return False
        ids=[]
        for member in m['members']:
            if (not isinstance(member,list)or len(member)!=2 or not slot_id(member[0])or member[0]>m['limit']
                    or not isinstance(member[1],str)or not NONCE.fullmatch(member[1])):return False
            ids.append(member[0])
        return (len(set(ids))==len(ids)and 1 in ids and m['slot']in ids
                and isinstance(m['eliminated'],list)and len(m['eliminated'])<=len(ids)
                and all(slot_id(s)and s in ids for s in m['eliminated'])
                and type(m['winner'])is int and(m['winner']==0 or m['winner']in ids))
    def adopt(self,m):
        if m['session']==self.party_session and m['revision']<self.roster_sequence:return False
        if self.party_session!=m['session']:
            self.players.clear();self.member_sequences.clear();self.roster_sequence=-1
        self.party_session=m['session'];self.roster_sequence=m['revision'];self.slot=m['slot'];self.max_players=m['limit']
        self.members=dict(m['members']);self.eliminated=set(m['eliminated']);self.winner=m['winner']
        for s in list(self.players):
            if s not in self.members:self.players.pop(s,None);self.damage_maps.pop(s,None)
        return True
    def receive(self,message,address,now):
        if self.peer.role=='host':
            link=self.links.get(address)
            if link is None:
                if message.get('kind')!='hello':return
                if sum(p.connected for p in self.links.values())>=self.max_players-1:
                    self.send({'kind':'full','build':self.peer.build,'peer':message.get('session'),'session':self.peer.session},address);return
                if len(self.links)>=32:return
                link=Peer('host',None,self.peer.build)
                link.password=self.peer.password;link.password_salt=self.peer.password_salt;link.password_base=self.peer.password_base
                link.key=self.peer.key;link.created_at=now;self.links[address]=link
            if not self.validate_impacts(message.get('impacts',{})):self.rejected+=1;return
            before=link.remote_pose_counter
            for response,destination in link.receive(message,address,now):self.send(response,destination)
            if link.connected and address not in self.slots:
                free=next((s for s in range(2,self.max_players+1)if s not in self.members),None)
                if free is None:
                    self.send(admission.seal({'kind':'full','build':link.build,'session':link.session,'peer':link.remote_session},link.auth_key),address)
                    self.links.pop(address);return
                self.slots[address]=free;self.members[free]=link.remote_session;self.roster_revision+=1
            if link.remote_pose_counter!=before and address in self.slots:
                slot=self.slots[address];self.players[slot]=link.remote_pose
                self.damage_maps[slot]={int(k):v for k,v in message.get('impacts',{}).items()}
                if link.remote_damage:self.damage_maps[slot][1]=link.remote_damage
        else:
            if address!=self.peer.target:return
            if message.get('kind')=='full'and message.get('build')==self.peer.build and message.get('peer')==self.peer.session:
                if self.peer.address is None or(message.get('session')==self.peer.remote_session and admission.verify(message,self.peer.auth_key)):
                    self.peer.error_message='Host is full. Ask the host to raise its player limit or wait for a slot.'
                return
            if message.get('kind')=='member':
                p=self.peer;slot=message.get('slot');seq=message.get('seq')
                if(not p.connected or message.get('session')!=p.remote_session or message.get('peer')!=p.session
                   or message.get('build')!=p.build or not admission.verify(message,p.auth_key)
                   or not slot_id(slot)or slot in(1,self.slot)or slot not in self.members
                   or message.get('token')!=self.members[slot]or type(seq)is not int
                   or not self.member_sequences.get(slot,-1)<seq<2**53
                   or not validate_pose(message.get('pose'))or not validate_damage(message.get('damage'))):return
                self.member_sequences[slot]=seq;self.players[slot]=message.get('pose')
                self.damage_maps[slot]={self.slot:message.get('damage')};return
            if message.get('kind')=='state'and not self.valid_metadata(message.get('party')):return
            before=self.peer.remote_pose_counter
            for response,destination in self.peer.receive(message,address,now):self.send(response,destination)
            if self.peer.remote_pose_counter!=before and self.adopt(message['party']):
                self.players[1]=self.peer.remote_pose;self.damage_maps[1]={self.slot:self.peer.remote_damage}
    def restart_round(self):
        if self.peer.role=='join':
            if not self.restart_ready():return False
            self.restart_sequence+=1;r=self.round_state
            self.restart_request={'session':r['session'],'round':r['id'],'request':self.restart_sequence}
            self.last_send=-1e9;return True
        return self.rounds.restart(self.players,self.peer.connected,allow_respawning=self.respawn_retry_ready())
    def publish(self,now):
        if not self.slot:return
        primary=self.primary()
        if primary!=self.last_primary:
            self.written.pop(primary,None);self.written.pop(self.last_primary,None);self.last_primary=primary
        rows=[f'HSPARTY1|{self.slot}|{self.max_players}|{primary}|{self.party_session}|{time.time()}|{int(self.slot in self.eliminated)}']
        for slot in sorted(self.members):
            if slot==self.slot:continue
            rows.append(f'P|{slot}|{self.members[slot]}')
            value=self.players.get(slot);damage=self.damage_maps.get(slot,{}).get(self.slot)
            destination=self.runtime if slot==primary else self.directory(slot)
            if destination not in self.directories:destination.mkdir(parents=True,exist_ok=True);self.directories.add(destination)
            signature=(id(value),id(damage))
            if self.written.get(slot)!=signature:
                self.counter+=1
                okay=atomic_write(destination/'remote.pose',pose_text(pose_frame(value,self.frame),self.counter))
                okay=atomic_write(destination/'remote.damage',damage_text(damage_frame(damage,self.frame)))and okay
                if okay:self.written[slot]=signature
        signature=(self.slot,self.max_players,primary,self.party_session,self.slot in self.eliminated,tuple(rows[1:]))
        if signature!=self.last_roster or now-self.last_roster_write>=.5:
            if atomic_write(self.runtime/'roster.cfg','\n'.join(rows)+'\n'):
                self.last_roster=signature;self.last_roster_write=now
        if not primary:atomic_write(self.runtime/'remote.pose','OFF|0\n')
    def step(self,now=None):
        now=time.monotonic()if now is None else now
        for _ in range(512):
            try:packet,address=self.socket.recvfrom(MAX_DATAGRAM+1)
            except(BlockingIOError,ConnectionResetError):break
            complete,okay=self.assembly.receive(packet,address,now)
            if not okay:self.rejected+=1;continue
            if complete is None:continue
            message=unpack(complete,self.peer.key)
            if message is None:self.rejected+=1;continue
            self.receive(message,address,now)
        if self.peer.role=='host':
            for address,link in list(self.links.items()):
                if link.expire(now)or not link.connected and now-getattr(link,'created_at',now)>TIMEOUT:
                    slot=self.slots.pop(address,None);self.links.pop(address,None)
                    if slot:self.members.pop(slot,None);self.players.pop(slot,None);self.damage_maps.pop(slot,None);self.written.pop(slot,None);self.roster_revision+=1
            active=[p for p in self.links.values()if p.connected]
            self.peer.connected=bool(active);self.peer.address=active[0].address if active else None
            primary=self.primary();self.peer.remote_pose=self.players.get(primary)
            self.peer.remote_pose_counter=sum(p.remote_pose_counter for p in active)
            self.peer.rtt_ms=active[0].rtt_ms if active else None
        elif self.peer.expire(now):
            self.members={};self.players={};self.damage_maps={};self.slot=0;self.round_state=None
            atomic_write(self.runtime/'roster.cfg','OFF\n');atomic_write(self.runtime/'remote.pose','OFF|0\n');atomic_write(self.runtime/'round.cfg','OFF\n')
        if self.peer.role=='join'and self.peer.address is None and now-self.last_hello>=.5:
            self.send(self.peer.hello(),self.peer.target);self.last_hello=now
        if now-self.last_ping>=1:
            for p in(self.links.values()if self.peer.role=='host'else[self.peer]):
                if p.connected:self.send(p.ping(now),p.address)
            self.last_ping=now
        if now-self.last_send>=1/30:
            own=self.local_pose(now)
            if self.peer.role=='join':
                self.frame=self.arena_frame.resolve(self.runtime/'frame.cfg',own)
                if self.frame is None:own=None
            if self.slot:self.players[self.slot]=pose_frame(own,self.frame)
            impacts={s:damage_frame(d,self.frame)for s,d in self.outgoing_damage().items()}
            if self.peer.role=='host':
                self.damage_maps[1]=impacts
                for link in self.links.values():
                    request=link.remote_restart_request
                    if request and request['session']==self.rounds.session and request['round']==self.rounds.id:
                        self.rounds.restart(self.players,True,allow_respawning=self.respawn_retry_ready(now))
                self.round_state=self.rounds.observe(self.players,self.peer.connected,now)
                self.eliminated=set(self.rounds.eliminated);self.winner=self.rounds.winner
                self.member_counter+=1
                for address,slot in list(self.slots.items()):
                    link=self.links[address]
                    if not link.connected:continue
                    message=link.state(own,impacts.get(slot),self.round_state)
                    message.pop('auth',None);message['party']=self.metadata(slot)
                    self.send(admission.seal(message,link.auth_key),address)
                    for other in self.members:
                        if other in(1,slot):continue
                        message={'kind':'member','build':link.build,'session':link.session,'peer':link.remote_session,
                            'seq':self.member_counter,'slot':other,'token':self.members[other],
                            'pose':self.players.get(other),'damage':self.damage_maps.get(other,{}).get(slot)}
                        self.send(admission.seal(message,link.auth_key),address)
            elif self.peer.address is not None:
                self.round_state=self.peer.remote_round
                if self.restart_request and self.round_state and(self.restart_request['session']!=self.round_state['session']or self.restart_request['round']!=self.round_state['id']):self.restart_request=None
                message=self.peer.state(pose_frame(own,self.frame),impacts.get(1),None,self.restart_request)
                message.pop('auth',None);message['impacts']={str(s):d for s,d in impacts.items()if s!=1}
                self.send(admission.seal(message,self.peer.auth_key),self.peer.address)
            if self.round_state:
                mark=(self.round_state['session'],self.round_state['id'],self.round_state['phase'])
                if mark!=self.round_mark:self.round_mark=mark;self.round_mark_at=now
            self.write_round(now);self.publish(now);self.last_send=now
        if now-self.last_status>=.5:
            own=self.players.get(self.slot);remotes=[p for s,p in self.players.items()if s!=self.slot and p]
            same_map=bool(own and remotes and all(p['map']==own['map']for p in remotes))
            phase='waiting_for_peer'if not self.peer.connected else'enter_fight'if not own else'waiting_for_peer_fighter'if not remotes else'map_mismatch'if not same_map else'playing'
            latencies=[{'slot':self.slots[a],'rtt_ms':p.rtt_ms}for a,p in self.links.items()if a in self.slots]if self.peer.role=='host'else[{'slot':1,'rtt_ms':self.peer.rtt_ms}]
            state={'role':self.peer.role,'phase':phase,'connected':self.peer.connected,'local_fighter':bool(own),
                   'remote_fighter':bool(remotes),'round':self.round_state,'same_map':same_map,'rtt_ms':self.peer.rtt_ms,
                   'players':len(self.members),'max_players':self.max_players,'slot':self.slot,'latencies':latencies,
                   'eliminated':sorted(self.eliminated),'winner':self.winner,'rejected_packets':self.rejected,
                   'send_errors':self.send_errors,'last_send_error':self.last_send_error,'connection_error':self.peer.error_message}
            atomic_write(self.runtime/'status.json',json.dumps(state,indent=2))
            atomic_write(self.runtime/'bridge.heartbeat',str(time.time())+'\n')
            atomic_write(self.runtime/'role.cfg',f'HSROLE1|{self.peer.role}|{int(self.peer.connected)}|{self.party_session or self.peer.session}|{time.time()}\n')
            self.last_status=now
    def close(self):
        self.socket.close();self.peer.connected=False
        for name,text in(('role.cfg','OFF\n'),('roster.cfg','OFF\n'),('remote.pose','OFF|0\n'),('remote.damage','OFF\n'),('round.cfg','OFF\n'),('bridge.heartbeat','OFF\n')):atomic_write(self.runtime/name,text)
        atomic_write(self.runtime/'status.json',json.dumps({'role':self.peer.role,'phase':'stopped','connected':False}))
