"""Local companion for the in-game multiplayer panel."""
import json
import errno
from pathlib import Path
import re
import socket
import time

from network import atomic_write
from party import Bridge,DEFAULT_PLAYERS,player_limit
from updater import Updates,UpdateServer
from version import VERSION

HOST=re.compile(r"^[A-Za-z0-9_.-]{1,240}$")


def lan_ipv4():
    try:
        with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as route:
            route.connect(("192.0.2.1",9));return route.getsockname()[0]
    except OSError:return "this PC's LAN IP"


class Menu:
    def __init__(self,root:Path,runtime:Path,build:str,preferences:Path|None=None,steam_autostart=False):
        self.root,self.runtime,self.build=root,runtime,build
        runtime.mkdir(parents=True,exist_ok=True)
        self.bridge=None;self.server=None
        self.steam=None;self.steam_updates=None;self.connection_transport='direct';self.tab='direct'
        self.updates=Updates(root,runtime)
        self.last_poll=self.last_state=self.last_check=-1e9
        self.last_command=""
        self.message="Offline — choose Host or Join"
        self.restart=False
        self.settings={"automatic_updates":False,"host":"","port":7777,"max_players":DEFAULT_PLAYERS}
        self.preferences=preferences or runtime/'preferences.json'
        try:
            saved=json.loads(self.preferences.read_text())
            self.settings["automatic_updates"]=saved.get("automatic_updates") is True
            if isinstance(saved.get("host"),str) and HOST.fullmatch(saved["host"]):self.settings["host"]=saved["host"]
            if type(saved.get("port")) is int and 1<=saved["port"]<=65534:self.settings["port"]=saved["port"]
            if type(saved.get('max_players'))is int and 2<=saved['max_players']<=16:self.settings['max_players']=saved['max_players']
        except (OSError,ValueError):pass
        atomic_write(runtime/"role.cfg","OFF\n")
        atomic_write(runtime/"match.request","OFF\n")
        if steam_autostart:
            try:self.steam_command('steam_open','friends','','','')
            except (ValueError,OSError):pass  # Direct mode remains available offline.
    def save(self):atomic_write(self.preferences,json.dumps(self.settings,indent=2))
    def disconnect(self):
        self.steam_updates=None
        if self.bridge:self.bridge.close();self.bridge=None
        if self.server:self.server.close();self.server=None
        if self.steam:self.steam.leave()
        self.message="Offline — choose Host or Join"
        atomic_write(self.runtime/"match.request","OFF\n")
    def command(self,line:str):
        p=line.strip().split("|")
        if not((len(p)==6 and p[0]=='HSUI1')or(len(p)==11 and p[0]=='HSUI2')or(len(p)==12 and p[0]=='HSUI3'))or p[1]==self.last_command:return
        action=p[2]
        password='';name='';privacy='friends';target=''
        if p[0]in('HSUI2','HSUI3'):
            from lobbies import unhex
            if p[6]not in('direct','steam'):raise ValueError('Unknown connection tab.')
            self.tab=p[6];privacy=p[7];target=''if p[10]=='-'else p[10]
            if action in('host','join','steam_host','steam_join'):password=unhex(p[9],128)
            if action=='steam_host':name=unhex(p[8],64)
            if p[0]=='HSUI3'and action in('host','steam_host'):
                try:self.settings['max_players']=player_limit(int(p[11]))
                except ValueError:raise ValueError('Choose a host limit from 2 to 16 players.')from None
                self.save()
        if action.startswith('steam_'):
            self.last_command=p[1]
            self.steam_command(action,privacy,name,password,target);return
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
            try:self.bridge=Bridge(action,None,self.build,self.runtime,port,host or None,password=password,max_players=self.settings['max_players'])
            except OSError as exc:
                if action=="host" and (exc.errno in (errno.EADDRINUSE,10048) or getattr(exc,"winerror",None)==10048):
                    raise ValueError(f"Port {port} is already in use. Join that host, or choose a different port for a second host.") from None
                raise
            if action=="host":
                try:self.server=UpdateServer(self.root,port+1)
                except OSError as exc:self.updates.message="Update sharing unavailable: "+str(exc)
                self.message=f"Hosting at {lan_ipv4()}:{port} — waiting for guest"
            else:self.message=f"Connecting to {host}:{port}"
            self.connection_transport='direct'
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
                raise ValueError("At least two fighters must enter the multiplayer match before restarting")
            self.message="Starting the next multiplayer round"
        elif action=="auto_updates":
            self.settings["automatic_updates"]=p[5]=="1";self.save()
        elif action=="check_updates":
            if self.bridge and self.connection_transport=='steam':
                if not self.bridge.peer.connected:raise ValueError('Connect to the Steam host before checking for updates.')
                self.steam_updates.request();return
            if not host:host=self.settings["host"]
            if not host:raise ValueError("Enter the host address to check for updates")
            self.updates.check(f"http://{host}:{port+1}")
        elif action=="apply_update":
            if self.updates.pending:
                self.updates.apply_requested=True
                self.message="Quit the game to apply the update and restart"
            else:self.message="Check for an update first"
        else:raise ValueError("Unknown multiplayer action")
    def steam_command(self,action,privacy,name,password,target):
        from lobbies import Lobbies,lobby_id,hextext
        if self.steam is None:
            try:self.steam=Lobbies(self)
            except Exception as exc:
                atomic_write(self.runtime/'steam.state',f'HSSTEAM1|{hextext(str(exc))}|-|-|-|0|{time.time()}\n')
                raise
        if action=='steam_open':self.steam.publish()
        elif action=='steam_host':self.steam.start(privacy,name,password)
        elif action=='steam_join':self.steam.join(target,password)
        elif action=='steam_refresh':self.steam.browse()
        elif action=='steam_friends':self.steam.load_friends()
        elif action=='steam_invite':
            self.steam.api.invite(lobby_id(target));self.steam.message='Steam invitation sent.'
        else:raise ValueError('Unknown Steam action.')
    def step(self):
        now=time.monotonic()
        if self.steam:
            try:self.steam.tick()
            except (ValueError,OSError)as exc:self.message=str(exc)
        if self.bridge:self.bridge.step()
        if self.steam_updates:
            try:self.steam_updates.tick()
            except (ValueError,OSError)as exc:self.updates.message='Steam update failed: '+str(exc)
        if self.bridge and isinstance(self.bridge.peer.error_message,str)and self.bridge.peer.error_message:
            error=self.bridge.peer.error_message
            if self.connection_transport=='steam':self.disconnect()
            self.message=error
        if now-self.last_poll>=.05:
            self.last_poll=now
            path=self.runtime/"ui.command"
            try:
                line=path.read_text(encoding="ascii")
                if len(line)>4096:raise ValueError("Invalid menu command")
                if line.endswith("\n"):
                    self.command(line)
                    path.unlink(missing_ok=True)
            except FileNotFoundError:pass
            except (ValueError,OSError) as exc:self.message=str(exc)
        if (self.settings["automatic_updates"] and self.bridge and self.bridge.peer.role=="join"
                and now-self.last_check>=60):
            self.last_check=now
            if self.connection_transport=='steam':
                if self.bridge.peer.connected:self.steam_updates.request()
            else:self.updates.check(f"http://{self.settings['host']}:{self.settings['port']+1}")
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
                    rtt=state.get('rtt_ms')
                    if type(rtt)in(int,float):message+=f' / RTT {rtt:.0f} ms'
                    if type(state.get('players'))is int:message+=f" / {state['players']}/{state['max_players']} players"
                    if state.get('slot')in state.get('eliminated',[]):message+=' / Out this round - waiting for the winner'
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
                    self.settings["port"],VERSION,int(self.updates.pending is not None),time.time(),role,int(can_restart),self.settings['max_players']]
            atomic_write(self.runtime/"ui.state","|".join(clean(v) for v in values)+"\n")
    def close(self,game_closed=False):
        self.disconnect()
        if self.steam:self.steam.close();self.steam=None
        if self.updates.busy:self.updates.thread.join(timeout=10)
        if game_closed and not self.updates.busy and self.updates.pending and (self.settings["automatic_updates"] or self.updates.apply_requested):
            self.restart=self.updates.apply()
