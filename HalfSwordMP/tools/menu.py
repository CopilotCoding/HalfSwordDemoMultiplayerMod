"""Local companion for the in-game multiplayer panel."""
import json
import errno
from pathlib import Path
import re
import socket
import time

from network import Bridge,atomic_write
from updater import Updates,UpdateServer
from version import VERSION

HOST=re.compile(r"^[A-Za-z0-9_.-]{1,240}$")


def lan_ipv4():
    try:
        with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as route:
            route.connect(("192.0.2.1",9));return route.getsockname()[0]
    except OSError:return "this PC's LAN IP"


class Menu:
    def __init__(self,root:Path,runtime:Path,build:str):
        self.root,self.runtime,self.build=root,runtime,build
        self.bridge=None;self.server=None
        self.updates=Updates(root,runtime)
        self.last_poll=self.last_state=self.last_check=-1e9
        self.last_command=""
        self.message="Offline — choose Host or Join"
        self.restart=False
        self.settings={"automatic_updates":False,"host":"","port":7777}
        try:
            saved=json.loads((runtime/"preferences.json").read_text())
            self.settings["automatic_updates"]=saved.get("automatic_updates") is True
            if isinstance(saved.get("host"),str) and HOST.fullmatch(saved["host"]):self.settings["host"]=saved["host"]
            if type(saved.get("port")) is int and 1<=saved["port"]<=65534:self.settings["port"]=saved["port"]
        except (OSError,ValueError):pass
        atomic_write(runtime/"role.cfg","OFF\n")
        atomic_write(runtime/"match.request","OFF\n")
    def save(self):atomic_write(self.runtime/"preferences.json",json.dumps(self.settings,indent=2))
    def disconnect(self):
        if self.bridge:self.bridge.close();self.bridge=None
        if self.server:self.server.close();self.server=None
        self.message="Offline — choose Host or Join"
        atomic_write(self.runtime/"match.request","OFF\n")
    def command(self,line:str):
        p=line.strip().split("|")
        if len(p)!=6 or p[0]!="HSUI1" or p[1]==self.last_command:return
        action=p[2]
        port=self.settings["port"]
        if action in ("host","join","check_updates"):
            port=int(p[3])
            if not 1<=port<=65534:raise ValueError("Choose a port from 1 to 65534")
        host="" if p[4]=="-" else p[4]
        if action=="host":host=""
        if action in ("join","check_updates") and host and not HOST.fullmatch(host):raise ValueError("Enter a host IP or hostname")
        self.last_command=p[1]
        if action in ("host","join"):
            if action=="join" and not host:raise ValueError("Enter the host IP address")
            self.disconnect()
            try:self.bridge=Bridge(action,None,self.build,self.runtime,port,host or None)
            except OSError as exc:
                if action=="host" and (exc.errno in (errno.EADDRINUSE,10048) or getattr(exc,"winerror",None)==10048):
                    raise ValueError(f"Port {port} is already in use. Close the other multiplayer launcher, then click Host again.") from None
                raise
            if action=="host":
                try:self.server=UpdateServer(self.root,port+1)
                except OSError as exc:self.updates.message="Update sharing unavailable: "+str(exc)
                self.message=f"Hosting at {lan_ipv4()}:{port} — waiting for guest"
            else:self.message=f"Connecting to {host}:{port}"
            self.settings["port"]=port
            if action=="join":self.settings["host"]=host
            self.save()
        elif action=="disconnect":self.disconnect()
        elif action=="enter_match":
            if not self.bridge:raise ValueError("Choose Host or Join before entering the multiplayer match")
            atomic_write(self.runtime/"match.request",f"HSMPMATCH1|{time.time_ns()}|{time.time()}\n")
            self.message="Entering multiplayer with your selected fighter"
        elif action=="restart_round":
            if not self.bridge:
                raise ValueError("Connect before restarting a round")
            if not self.bridge.restart_round():
                raise ValueError("Both fighters must be in the multiplayer match before restarting")
            self.message="Starting the next multiplayer round"
        elif action=="auto_updates":
            self.settings["automatic_updates"]=p[5]=="1";self.save()
        elif action=="check_updates":
            if not host:host=self.settings["host"]
            if not host:raise ValueError("Enter the host address to check for updates")
            self.updates.check(f"http://{host}:{port+1}")
        elif action=="apply_update":
            if self.updates.pending:
                self.updates.apply_requested=True
                self.message="Quit the game to apply the update and restart"
            else:self.message="Check for an update first"
        else:raise ValueError("Unknown multiplayer action")
    def step(self):
        now=time.monotonic()
        if self.bridge:self.bridge.step()
        if now-self.last_poll>=.05:
            self.last_poll=now
            path=self.runtime/"ui.command"
            try:
                line=path.read_text(encoding="ascii")
                if len(line)>1024:raise ValueError("Invalid menu command")
                if line.endswith("\n"):
                    self.command(line)
                    path.unlink(missing_ok=True)
            except FileNotFoundError:pass
            except (ValueError,OSError) as exc:self.message=str(exc)
        if (self.settings["automatic_updates"] and self.bridge and self.bridge.peer.role=="join"
                and now-self.last_check>=60):
            self.last_check=now
            self.updates.check(f"http://{self.settings['host']}:{self.settings['port']+1}")
        if now-self.last_state>=.5:
            self.last_state=now
            message=self.message
            if self.bridge and self.bridge.peer.connected:
                try:
                    state=json.loads((self.runtime/"status.json").read_text())
                    phase=state.get("phase")
                    message={"playing":"Connected — each PC controls its own fighter",
                        "enter_fight":"Connected — click Enter multiplayer match",
                        "waiting_for_peer_fighter":"Connected — waiting for the other player to enter multiplayer match",
                        "waiting_for_guest_fighter":"Connected — preparing the guest fighter",
                        "map_mismatch":"Choose the same arena on both PCs"}.get(phase,message)
                    round_state=state.get("round")
                    if phase=="playing" and round_state:
                        if round_state["phase"]=="restart":
                            seconds=(round_state["remaining_ms"]+999)//1000
                            message=f"Round over — restarting in {seconds}s"
                        elif round_state["phase"]=="respawning":message="Starting next round — waiting for both fighters"
                        elif round_state["phase"]=="playing":message=f"Multiplayer round {round_state['id']} — your own fighter"
                except (OSError,ValueError):pass
            if self.bridge:
                try:
                    fields=(self.runtime/"match.state").read_text().strip().split("|")
                    if len(fields)==4 and fields[0]=="HSMPMATCHSTATE1":
                        if fields[1] in ("error","loading") and abs(time.time()-float(fields[3]))<5:message=fields[2]
                        elif fields[1]=="active" and not self.bridge.peer.connected:message=fields[2]
                except (OSError,ValueError):pass
            if self.updates.message not in ("Updates off","Up to date"):message+=" / "+self.updates.message
            clean=lambda v:str(v).replace("—","-").replace("|"," ").replace("\n"," ").replace("\r"," ").encode("ascii","replace").decode()[:600]
            role=self.bridge.peer.role if self.bridge else "off"
            can_restart=bool(self.bridge and self.bridge.restart_ready(now))
            values=["HSUISTATE1",message,int(self.settings["automatic_updates"]),self.settings["host"] or "-",
                    self.settings["port"],VERSION,int(self.updates.pending is not None),time.time(),role,int(can_restart)]
            atomic_write(self.runtime/"ui.state","|".join(clean(v) for v in values)+"\n")
    def close(self,game_closed=False):
        self.disconnect()
        if self.updates.busy:self.updates.thread.join(timeout=10)
        if game_closed and not self.updates.busy and self.updates.pending and (self.settings["automatic_updates"] or self.updates.apply_requested):
            self.restart=self.updates.apply()
