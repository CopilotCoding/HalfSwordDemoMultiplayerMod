"""Two-peer UDP transport for HalfSwordMP, with direct-IP and keyed modes.

The network accepts bounded avatar state, native impacts and round boundaries.
"""
from __future__ import annotations

import hashlib
import hmac
import json
from pathlib import Path
import re
import struct
import secrets
import socket
import time
import zlib

from snapshot import MAX_BODY, validate_pose, pose_text, read_pose
from damage import validate_damage,damage_text,read_damage
from rounds import Rounds,validate_round
from frames import ArenaFrame,pose_frame,damage_frame,input_frame
from controls import validate_input,read_input,input_text
import admission

MAGIC = b"HSMPJ"
MAX_PACKET = 65536
MAX_DATAGRAM = 1200
FRAGMENT = b"HSF22"
CHUNK = 1100
TIMEOUT = 5.0
NONCE = re.compile(r"^[a-f0-9]{32}$")

def valid_restart_request(value):
    return value is None or (isinstance(value,dict)and set(value)=={'session','round','request'}
        and isinstance(value['session'],str)and NONCE.fullmatch(value['session'])is not None
        and type(value['round'])is int and 1<=value['round']<2**31
        and type(value['request'])is int and 1<=value['request']<2**53)


def signature(payload: bytes, key: bytes | None) -> bytes:
    # Direct-IP mode has an integrity checksum, not shared-secret authentication.
    return hashlib.sha256(payload).digest() if key is None else hmac.digest(key,payload,"sha256")


def pack(message: dict, key: bytes | None) -> bytes:
    raw = json.dumps(message, separators=(",", ":"), allow_nan=False).encode()
    if len(raw) > MAX_BODY:
        raise ValueError("Snapshot exceeds uncompressed budget")
    body = zlib.compress(raw)
    packet = MAGIC + signature(MAGIC + body,key) + body
    if len(packet) > MAX_PACKET:
        raise ValueError("Snapshot exceeds packet budget")
    return packet


def unpack(packet: bytes, key: bytes | None) -> dict | None:
    if not 38 <= len(packet) <= MAX_PACKET or not packet.startswith(MAGIC):
        return None
    received_signature, compressed = packet[5:37], packet[37:]
    if not hmac.compare_digest(received_signature, signature(MAGIC + compressed,key)):
        return None
    try:
        inflater = zlib.decompressobj()
        body = inflater.decompress(compressed, MAX_BODY + 1)
        if len(body) > MAX_BODY or not inflater.eof or inflater.unused_data:
            return None
        result = json.loads(body)
        return result if isinstance(result, dict) else None
    except (ValueError, zlib.error, RecursionError):
        return None


def fragments(packet: bytes, key: bytes | None) -> list[bytes]:
    """Keep each UDP datagram below the path MTU; loss drops one whole snapshot."""
    if len(packet) <= MAX_DATAGRAM:
        return [packet]
    identifier = secrets.randbits(64)
    count = (len(packet) + CHUNK - 1) // CHUNK
    result = []
    for index in range(count):
        body = struct.pack("!QHH", identifier, index, count) + packet[index*CHUNK:(index+1)*CHUNK]
        result.append(FRAGMENT + signature(FRAGMENT + body,key) + body)
    return result


class Reassembly:
    def __init__(self, key):
        self.key, self.pending = key, {}

    def receive(self, packet, address, now):
        self.pending = {k: v for k, v in self.pending.items() if now - v[0] < 0.5}
        if len(packet) > MAX_DATAGRAM:
            return None, False
        if packet.startswith(MAGIC):
            return packet, True
        if not packet.startswith(FRAGMENT) or len(packet) <= 49:
            return None, False
        received_signature, body = packet[5:37], packet[37:]
        if not hmac.compare_digest(received_signature, signature(FRAGMENT + body,self.key)):
            return None, False
        identifier, index, count = struct.unpack("!QHH", body[:12])
        chunk = body[12:]
        if (not 2 <= count <= 60 or index >= count or len(chunk) > CHUNK
                or (index < count - 1 and len(chunk) != CHUNK)):
            return None, False
        k = (address, identifier)
        if k not in self.pending:
            if len(self.pending) >= 16 or sum(a == address for a, _ in self.pending) >= 4:
                return None, False
            self.pending[k] = (now, count, {})
        _, old_count, chunks = self.pending[k]
        if count != old_count or (index in chunks and chunks[index] != chunk):
            del self.pending[k]
            return None, False
        chunks[index] = chunk
        if len(chunks) != count:
            return None, True
        del self.pending[k]
        complete = b"".join(chunks[i] for i in range(count))
        return (complete, True) if len(complete) <= MAX_PACKET else (None, False)


def atomic_write(path: Path, text: str) -> bool:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(text, encoding="ascii")
    try:
        temporary.replace(path)
        return True
    except PermissionError:
        # A brief Windows reader handle can delay replacement; retry next tick.
        return False


class Peer:
    """State machine independent of sockets so handshake and replay rules are testable."""
    def __init__(self, role: str, code: str | None, build: str, target=None, password=""):
        if role not in ("host", "join"):
            raise ValueError("Choose host or join")
        if code is not None and (not isinstance(code,str) or not 16 <= len(code) <= 128):
            raise ValueError("Invalid private transport key")
        self.role, self.build, self.target = role, build, target
        self.password=admission.password(password)
        self.password_salt=secrets.token_hex(16)
        self.password_base=admission.base_key(self.password,self.password_salt)if self.password and role=='host'else None
        self.password_cache={};self.auth_key=None;self.error_message=''
        self.key = hashlib.sha256(code.encode("utf-8")).digest() if code is not None else None
        self.session = secrets.token_hex(16)
        self.remote_session = None
        self.address = None
        self.pending = {}  # address -> (client nonce, fresh host nonce, creation time)
        self.sequence, self.received_sequence = 0, -1
        self.last_seen = 0.0
        self.remote_pose = None
        self.remote_input = None
        self.input_sequence,self.received_input_sequence=0,-1
        self.remote_input_counter=0
        self.remote_damage = None
        self.remote_round = None
        self.remote_restart_request = None
        self.remote_pose_counter = 0
        self.connected = False
        self.probes={};self.rtt_ms=None;self.rtt_samples=[]

    def ping(self,now):
        self.probes={token:stamp for token,stamp in self.probes.items()if now-stamp<TIMEOUT}
        token=secrets.token_hex(16);self.probes[token]=now
        return admission.seal({'kind':'ping','build':self.build,'session':self.session,'peer':self.remote_session,'token':token},self.auth_key)

    def hello(self) -> dict:
        return {"kind": "hello", "build": self.build, "session": self.session}

    def state(self, pose, damage=None,round_state=None,restart_request=None) -> dict:
        self.sequence += 1
        return admission.seal({"kind": "state", "build": self.build, "session": self.session,
                "peer": self.remote_session, "seq": self.sequence, "pose": pose,
                "damage": damage,"round":round_state,"restart_request":restart_request},self.auth_key)

    def controls(self,control):
        self.input_sequence+=1
        return admission.seal({"kind":"input","build":self.build,"session":self.session,"peer":self.remote_session,
                "seq":self.input_sequence,"input":control},self.auth_key)

    def welcome(self,client,host):
        key=admission.session_key(self.password_base,client,host,self.build)if self.password_base else None
        return {'kind':'welcome','build':self.build,'session':host,'peer':client,
                'password_required':key is not None,'password_salt':self.password_salt if key else '',
                'password_proof':admission.proof(key)if key else ''}

    def receive(self, message: dict, address, now: float) -> list[tuple[dict, tuple]]:
        if message.get("build") != self.build:
            return []
        session = message.get("session")
        if not isinstance(session, str) or not NONCE.fullmatch(session):
            return []
        kind = message.get("kind")
        if kind not in ('hello','welcome'):
            key=self.auth_key
            if self.role=='host'and self.address is None and self.password_base:
                candidate=self.pending.get(address)
                if candidate is None or now-candidate[2]>=TIMEOUT:return []
                key=admission.session_key(self.password_base,candidate[0],candidate[1],self.build)
            if not admission.verify(message,key):return []
        if kind in ('ping','pong'):
            token=message.get('token')
            if (not self.connected or address!=self.address or session!=self.remote_session
                    or message.get('peer')!=self.session or not isinstance(token,str)or not NONCE.fullmatch(token)):return []
            if kind=='ping':
                return [(admission.seal({'kind':'pong','build':self.build,'session':self.session,'peer':session,'token':token},self.auth_key),address)]
            sent=self.probes.pop(token,None)
            if sent is not None and 0<=now-sent<TIMEOUT:
                self.rtt_ms=(now-sent)*1000;self.rtt_samples=(self.rtt_samples+[self.rtt_ms])[-20:]
            return []
        if self.role == "host" and kind == "hello":
            if self.address is not None:
                # A repeated hello may be a lost welcome, but cannot replace an active session.
                if self.address == address and self.remote_session == session:
                    return [(self.welcome(session,self.session),address)]
                return []
            self.pending = {a: p for a, p in self.pending.items() if now - p[2] < TIMEOUT}
            old = self.pending.get(address)
            if old is None or old[0] != session:
                if len(self.pending) >= 8:
                    return []
                old = (session, secrets.token_hex(16), now)
                self.pending[address] = old
            return [(self.welcome(session,old[1]),address)]
        if self.role == "join" and kind == "welcome":
            if address != self.target or message.get("peer") != self.session:
                return []
            key=None
            if self.password and message.get('password_required')is not True:
                self.error_message='Host has no password. Clear the password field only if that is expected.';return []
            if message.get('password_required')is True:
                salt=message.get('password_salt')
                if not isinstance(salt,str)or not NONCE.fullmatch(salt):return []
                if not self.password:self.error_message='Password required. Enter it and join again.';return []
                if salt not in self.password_cache:
                    if len(self.password_cache)>=8:return []
                    self.password_cache[salt]=admission.base_key(self.password,salt)
                key=admission.session_key(self.password_cache[salt],self.session,session,self.build)
                claimed=message.get('password_proof')
                if not isinstance(claimed,str)or not hmac.compare_digest(claimed,admission.proof(key)):
                    self.error_message='Incorrect password. Enter it and join again.';return []
            if self.address is None:
                self.auth_key=key;self.error_message=''
                self.address, self.remote_session = address, session
                self.last_seen = now
            return []
        if kind=="input":
            seq=message.get("seq")
            if (self.address!=address or session!=self.remote_session or message.get("peer")!=self.session
                    or type(seq) is not int or not self.received_input_sequence<seq<2**53
                    or not validate_input(message.get("input"))):return []
            self.received_input_sequence=seq;self.remote_input=message.get("input");self.remote_input_counter+=1
            return []
        if kind != "state" or type(message.get("seq")) is not int:
            return []
        if not 0 <= message["seq"] < 2**53 or not validate_pose(message.get("pose")):
            return []
        if (not validate_damage(message.get("damage")) or "controls" in message or "guest" in message
                or not validate_round(message.get("round")) or (self.role=="host" and message.get("round") is not None)
                or not valid_restart_request(message.get('restart_request'))
                or(self.role!='host'and message.get('restart_request')is not None)):
            return []
        if self.role == "host" and self.address is None:
            candidate = self.pending.get(address)
            if (candidate is None or now - candidate[2] >= TIMEOUT or candidate[0] != session
                    or message.get("peer") != candidate[1]):
                return []
            self.session = candidate[1]
            self.auth_key=admission.session_key(self.password_base,session,self.session,self.build)if self.password_base else None
            self.address, self.remote_session = address, session
            self.pending.clear()
        if (address != self.address or session != self.remote_session
                or message.get("peer") != self.session or message["seq"] <= self.received_sequence):
            return []
        self.received_sequence = message["seq"]
        self.last_seen, self.connected = now, True
        self.remote_pose = message.get("pose")
        self.remote_damage = message.get("damage")
        self.remote_round = message.get("round")
        self.remote_restart_request=message.get('restart_request')
        self.remote_pose_counter += 1
        return []

    def expire(self, now: float) -> bool:
        if self.address is None or now - self.last_seen <= TIMEOUT:
            return False
        self.address = self.remote_session = None
        self.session = secrets.token_hex(16)
        self.sequence, self.received_sequence = 0, -1
        self.remote_pose = None
        self.remote_restart_request=None
        self.remote_input=None;self.remote_input_counter+=1
        self.input_sequence,self.received_input_sequence=0,-1
        self.remote_damage = None
        self.remote_round = None
        self.remote_pose_counter += 1
        self.connected = False
        self.probes={};self.rtt_ms=None;self.rtt_samples=[]
        self.pending.clear()
        self.auth_key=None;self.error_message='';self.password_cache.clear()
        return True


class Bridge:
    def __init__(self, role: str, code: str | None, build: str, runtime: Path,
                 port: int = 7777, address: str | None = None, bind: str = "0.0.0.0", *,password="",transport=None,target=None):
        if not 1 <= port <= 65535:
            raise ValueError("Port must be between 1 and 65535")
        if transport is None:target = (socket.gethostbyname(address), port) if role == "join" and address else None
        if role == "join" and target is None:
            raise ValueError("Joining requires the host's IP or hostname")
        self.peer = Peer(role, code, build, target,password)
        self.runtime = runtime
        runtime.mkdir(parents=True, exist_ok=True)
        self.socket = transport or socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        # No reuse: two hosts must not silently share a port.
        try:
            if transport is None:self.socket.bind((bind, port if role == "host" else 0))
        except OSError:
            self.socket.close()
            raise
        self.socket.setblocking(False)
        self.last_send = self.last_hello = self.last_status = -1e9
        self.last_input_send=-1e9;self.last_written_input=-1
        self.was_connected = False
        self.last_phase=None
        self.inbound_counter = 0
        self.last_written_pose = -1
        self.last_damage_text = None
        self.last_round_signature = None
        self.last_round_write = -1e9
        self.rejected = 0
        self.send_errors = 0
        self.assembly = Reassembly(self.peer.key)
        self.last_send_error = ""
        self.rounds=Rounds() if role=="host" else None
        self.round_state=None
        self.restart_request=None;self.restart_sequence=0
        self.round_mark=None;self.round_mark_at=time.monotonic()
        self.last_ping=-1e9
        self.frame=None
        self.arena_frame=ArenaFrame()
        self.cached_local_pose=None;self.cached_local_pose_at=-1e9
        atomic_write(runtime / "remote.pose", "OFF|0\n")
        atomic_write(runtime / "remote.input", "OFF\n")
        atomic_write(runtime / "local.input", "OFF\n")
        atomic_write(runtime / "remote.damage", "OFF\n")
        atomic_write(runtime / "local.damage", "OFF\n")
        atomic_write(runtime / "round.cfg", "OFF\n")
        atomic_write(runtime / "frame.cfg", "OFF\n")

    def write_round(self, now):
        """Publish transitions immediately; refresh an unchanged round twice/s."""
        if not self.round_state:
            return
        r=self.round_state
        remaining=(r['remaining_ms']//100)*100
        signature=(r['session'],r['id'],r['phase'],remaining,r['reason'])
        if signature==self.last_round_signature and now-self.last_round_write<.5:
            return
        text=f"HSROUND1|{r['session']}|{r['id']}|{r['phase']}|{remaining}|{r['reason']}|{time.time()}\n"
        if atomic_write(self.runtime/'round.cfg',text):
            self.last_round_signature=signature
            self.last_round_write=now

    def send(self, message: dict, address) -> None:
        try:
            for packet in fragments(pack(message, self.peer.key), self.peer.key):
                self.socket.sendto(packet, address)
        except (OSError, ValueError) as exc:
            self.send_errors += 1
            self.last_send_error = str(exc)
            if self.send_errors == 1:
                print(f"UDP send failed: {exc}", flush=True)

    def local_pose(self,now):
        value=read_pose(self.runtime/'local.pose')
        if value is not None:self.cached_local_pose,self.cached_local_pose_at=value,now
        elif now-self.cached_local_pose_at<.5:value=self.cached_local_pose
        return value

    def respawn_retry_ready(self,now=None):
        now=time.monotonic()if now is None else now;r=self.round_state
        return bool(r and r['phase']in('respawning','waiting')and now-self.round_mark_at>=6
            and(not self.rounds or self.rounds.id==r['id']))

    def restart_ready(self,now=None):
        r=self.round_state
        return bool(self.peer.connected and r and r['id']>0 and(not self.restart_request)
            and(r['phase']in('playing','restart')or self.respawn_retry_ready(now)))

    def restart_round(self):
        if self.peer.role=='join':
            r=self.peer.remote_round;local=self.local_pose(time.monotonic());remote=self.peer.remote_pose
            if not self.restart_ready():return False
            self.restart_sequence+=1
            self.restart_request={'session':r['session'],'round':r['id'],'request':self.restart_sequence}
            self.last_send=-1e9;return True
        if self.peer.role!="host" or self.rounds is None:return False
        if not self.rounds.restart(self.local_pose(time.monotonic()),self.peer.remote_pose,self.peer.connected,
                allow_respawning=self.respawn_retry_ready()):return False
        self.last_send=-1e9
        return True

    def step(self, now=None) -> None:
        now = time.monotonic() if now is None else now
        for _ in range(256):  # Bound receive work so traffic cannot starve the game bridge.
            try:
                packet, address = self.socket.recvfrom(MAX_DATAGRAM + 1)
            except (BlockingIOError, ConnectionResetError):
                break
            complete, okay = self.assembly.receive(packet, address, now)
            if not okay:
                self.rejected += 1
                continue
            if complete is None:
                continue
            message = unpack(complete, self.peer.key)
            if message is None:
                self.rejected += 1
                continue
            for response, destination in self.peer.receive(message, address, now):
                self.send(response, destination)
        if self.peer.expire(now):
            print("Peer timed out; waiting for reconnect.", flush=True)
            self.round_state=None
            self.restart_request=None
            self.last_round_signature=None
            if self.rounds:self.rounds=Rounds()
            atomic_write(self.runtime / "round.cfg", "OFF\n")
        if self.peer.role == "join" and self.peer.address is None and now - self.last_hello >= 0.5:
            self.send(self.peer.hello(), self.peer.target)
            self.last_hello = now
        if self.peer.connected and self.peer.address is not None and now-self.last_ping>=1:
            self.send(self.peer.ping(now),self.peer.address);self.last_ping=now
        if self.peer.address is not None and now - self.last_send >= 1/30:
            damage=read_damage(self.runtime / "local.damage")
            local_pose=self.local_pose(now)
            if self.peer.role=="join":
                self.frame=self.arena_frame.resolve(self.runtime/"frame.cfg",local_pose)
                # Never publish a guest fighter in host coordinates until its
                # native arena frame has been established.
                if self.frame is None:local_pose=None
                r=self.peer.remote_round
                if self.restart_request and r and(r['session']!=self.restart_request['session']or r['id']!=self.restart_request['round']):
                    self.restart_request=None
            else:
                request=self.peer.remote_restart_request
                if(request and self.peer.connected and request['session']==self.rounds.session
                        and request['round']==self.rounds.id):
                    self.rounds.restart(local_pose,self.peer.remote_pose,True,allow_respawning=self.respawn_retry_ready(now))
            self.round_state=(self.rounds.observe(local_pose,self.peer.remote_pose,self.peer.connected,now)
                if self.rounds else self.peer.remote_round)
            if self.round_state:
                mark=(self.round_state['session'],self.round_state['id'],self.round_state['phase'])
                if mark!=self.round_mark:self.round_mark=mark;self.round_mark_at=now
            self.send(self.peer.state(pose_frame(local_pose,self.frame),damage_frame(damage,self.frame),self.round_state if self.rounds else None,self.restart_request),self.peer.address)
            self.write_round(now)
            self.last_send = now
        frame_ready=self.peer.role!="join" or self.frame is not None
        if self.peer.connected and frame_ready and now-self.last_input_send>=1/30:
            control=read_input(self.runtime/"local.input")
            if control is not None:self.send(self.peer.controls(input_frame(control,self.frame)),self.peer.address)
            self.last_input_send=now
        if frame_ready and self.peer.remote_input_counter!=self.last_written_input:
            if atomic_write(self.runtime/"remote.input",input_text(input_frame(self.peer.remote_input,self.frame))):
                self.last_written_input=self.peer.remote_input_counter
        if frame_ready and self.peer.remote_pose_counter != self.last_written_pose:
            self.inbound_counter += 1
            pose_written=atomic_write(self.runtime / "remote.pose", pose_text(pose_frame(self.peer.remote_pose,self.frame), self.inbound_counter))
            damage_value=damage_text(damage_frame(self.peer.remote_damage,self.frame))
            damage_written=(damage_value==self.last_damage_text or atomic_write(self.runtime / "remote.damage",damage_value))
            if damage_written:self.last_damage_text=damage_value
            if pose_written and damage_written:
                self.last_written_pose = self.peer.remote_pose_counter
        if self.peer.connected and not self.was_connected:
            print("Connected to peer. Waiting for in-game fighters.", flush=True)
        self.was_connected = self.peer.connected
        if now - self.last_status >= 1.0:
            local = self.local_pose(now)
            remote = self.peer.remote_pose
            local_map=local["map"] if local else None
            remote_map=remote["map"] if remote else None
            same_map=bool(local_map and remote_map and local_map==remote_map)
            phase=("waiting_for_peer" if not self.peer.connected else "enter_fight" if not local_map
                   else "waiting_for_peer_fighter" if not remote_map else "map_mismatch" if not same_map
                   else "playing")
            if phase!=self.last_phase:
                messages={"waiting_for_peer":"Waiting for peer connection.","enter_fight":"Enter a fight on this PC.",
                          "waiting_for_peer_fighter":"Waiting for the other player to enter a fight.",
                          "map_mismatch":"Map mismatch: enter the same map on both PCs.",
                          "playing":"Connected: each PC controls its own native fighter."}
                print(messages[phase],flush=True);self.last_phase=phase
            status = {"role":self.peer.role,"phase":phase,"connected": self.peer.connected, "local_fighter": local_map is not None,
                      "remote_fighter": remote_map is not None,"authority":"owner_movement_native_injury",
                      "movement_authority":"owner","injury_authority":"attacker_native_opponent",
                      "state_target_hz":30,"input_target_hz":30,
                      "remote_controls":self.peer.remote_input_counter,
                      "round":self.round_state,
                      "rtt_ms":self.peer.rtt_ms,
                      "rtt_min_ms":min(self.peer.rtt_samples)if self.peer.rtt_samples else None,
                      "rtt_max_ms":max(self.peer.rtt_samples)if self.peer.rtt_samples else None,
                      "same_map": same_map,
                      "received_snapshots": self.peer.remote_pose_counter,
                      "rejected_packets": self.rejected, "send_errors": self.send_errors,
                      "last_send_error": self.last_send_error}
            status['connection_error']=self.peer.error_message
            atomic_write(self.runtime / "status.json", json.dumps(status, indent=2))
            atomic_write(self.runtime / "bridge.heartbeat", str(time.time()) + "\n")
            atomic_write(self.runtime / "role.cfg",f"HSROLE1|{self.peer.role}|{int(self.peer.connected)}|{self.peer.session}|{time.time()}\n")
            self.last_status = now

    def close(self):
        self.socket.close()
        self.peer.connected=False
        atomic_write(self.runtime / "status.json",json.dumps({"role":self.peer.role,"phase":"stopped",
            "connected":False,"send_errors":self.send_errors},indent=2))
        atomic_write(self.runtime / "bridge.heartbeat", "OFF\n")
        atomic_write(self.runtime / "role.cfg","OFF\n")
        atomic_write(self.runtime / "remote.damage","OFF\n")
        atomic_write(self.runtime / "remote.input","OFF\n")
        atomic_write(self.runtime / "round.cfg","OFF\n")
        atomic_write(self.runtime / "remote.pose", "OFF|0\n")
