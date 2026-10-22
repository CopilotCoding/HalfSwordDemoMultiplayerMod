"""Small Steamworks flat-API binding. All calls run on the companion thread.

Uses Valve's signed Windows redistributable, never another application's App ID.
Manual dispatch avoids native callbacks into Python during game/loader teardown.
"""
import ctypes as C
import os
from pathlib import Path
import socket
import struct
import time
from collections import deque

APP_ID=2642680  # Half Sword Demo
P=C.c_void_p;I=C.c_int;U=C.c_uint32;Q=C.c_uint64;B=C.c_bool;S=C.c_char_p

class Identity(C.Structure):
 _pack_=1
 _fields_=[('kind',I),('size',I),('data',C.c_byte*128)]

class Callback(C.Structure):
 _fields_=[('user',I),('callback',I),('data',P),('size',I)]

class Message(C.Structure):
 _fields_=[('data',P),('size',I),('connection',U),('identity',Identity),
  ('connection_user',C.c_int64),('received',C.c_int64),('number',C.c_int64),
  ('free_data',P),('release',P),('channel',I),('flags',I),('user',C.c_int64),('lane',C.c_uint16)]

class SteamError(ValueError):pass

class Steam:
 def __init__(self,dll_path=None):
  if os.name!='nt' or C.sizeof(P)!=8:raise SteamError('Steam mode requires 64-bit Windows Python and the Steam client.')
  from steam_runtime import find_runtime
  path=Path(dll_path)if dll_path is not None else find_runtime()
  os.environ['SteamAppId']=str(APP_ID);os.environ['SteamGameId']=str(APP_ID)
  self.dll=C.CDLL(str(path.resolve()));self.functions={};self.pending={};self.events=[];self.closed=False
  self.lobby=0;self.accept=None;self.failures=deque(maxlen=8)
  try:
   error=C.create_string_buffer(1024)
   if hasattr(self.dll,'SteamInternal_SteamAPI_Init'):
    ok=self.fn('SteamInternal_SteamAPI_Init',I,S,P)(b'SteamMatchMaking009\0SteamNetworkingMessages002\0\0',error)==0
   elif hasattr(self.dll,'SteamAPI_InitFlat'):
    ok=self.fn('SteamAPI_InitFlat',I,P)(error)==0
   else:
    ok=self.fn('SteamAPI_Init',B)()
   if not ok:raise SteamError('Steam unavailable: '+(error.value.decode('utf-8','replace')[:400]or'Launch Half Sword Demo through Steam and sign in.'))
   self.initialized=True
   self.mm=self.interface('SteamAPI_SteamMatchmaking_v009')
   self.net=self.interface('SteamAPI_SteamNetworkingMessages_SteamAPI_v002')
   self.friends=self.interface('SteamAPI_SteamFriends_v017')
   self.utils=self.interface('SteamAPI_SteamUtils_v010')
   self.user=self.interface('SteamAPI_SteamUser_v023')
   self.apps=self.interface('SteamAPI_SteamApps_v008')
   if self.fn('SteamAPI_ISteamUtils_GetAppID',U,P)(self.utils)!=APP_ID:raise SteamError('Steam started under the wrong application. Launch Half Sword Demo through Steam.')
   if not self.logged_on():raise SteamError('Sign in to Steam and go online before using Steam multiplayer.')
   self.id=self.fn('SteamAPI_ISteamUser_GetSteamID',Q,P)(self.user)
   self.name=self.persona(self.id)
   self.pipe=self.fn('SteamAPI_GetHSteamPipe',I)()
   self.fn('SteamAPI_ManualDispatch_Init',None)()
   # Ask for relay availability early, without making a public session.
   n=self.interface('SteamAPI_SteamNetworkingUtils_SteamAPI_v004')
   self.fn('SteamAPI_ISteamNetworkingUtils_InitRelayNetworkAccess',None,P)(n)
  except Exception:
   self.close();raise
 def fn(self,name,result,*args):
  if name not in self.functions:
   try:f=getattr(self.dll,name)
   except AttributeError:raise SteamError('Installed Steam runtime is incompatible: '+name)from None
   f.restype=result;f.argtypes=list(args);self.functions[name]=f
  return self.functions[name]
 def interface(self,name):
  value=self.fn(name,P)()
  if not value:raise SteamError('Steam interface unavailable: '+name)
  return value
 def logged_on(self):return self.fn('SteamAPI_ISteamUser_BLoggedOn',B,P)(self.user)
 def persona(self,user):
  raw=self.fn('SteamAPI_ISteamFriends_GetFriendPersonaName',S,P,Q)(self.friends,user)
  return (raw or b'Player').decode('utf-8','replace')[:64]
 def identity(self,user):
  value=Identity();self.fn('SteamAPI_SteamNetworkingIdentity_SetSteamID64',None,P,Q)(C.byref(value),int(user));return value
 def identity_id(self,value):return self.fn('SteamAPI_SteamNetworkingIdentity_GetSteamID64',Q,P)(C.byref(value))
 def match(self,name,result,args,*values):return self.fn('SteamAPI_ISteamMatchmaking_'+name,result,P,*args)(self.mm,*values)
 def call(self,handle,kind,callback):
  if not handle:raise SteamError('Steam could not start this request.')
  self.pending[handle]=(kind,time.monotonic()+25,callback)
 def pump(self):
  if self.closed:return
  self.fn('SteamAPI_ManualDispatch_RunFrame',None,I)(self.pipe)
  msg=Callback()
  for _ in range(256):
   if not self.fn('SteamAPI_ManualDispatch_GetNextCallback',B,I,P)(self.pipe,C.byref(msg)):break
   try:
    raw=C.string_at(msg.data,msg.size)if 0<=msg.size<=4096 else b''
    if msg.callback==703 and len(raw)>=16:
     handle,kind,size=struct.unpack_from('<Qii',raw)
     task=self.pending.pop(handle,None)
     if task:
      expected,_,callback=task;failed=B();buf=C.create_string_buffer(max(1,min(size,4096)))
      ok=(kind==expected and 0<=size<=4096 and self.fn('SteamAPI_ManualDispatch_GetAPICallResult',B,I,Q,P,I,I,P)
       (self.pipe,handle,buf,size,kind,C.byref(failed)))
      callback(bytes(buf.raw[:size])if ok and not failed.value else None)
    elif msg.callback==333 and len(raw)>=16:
     self.events.append(('invite',struct.unpack_from('<Q',raw)[0]))
    elif msg.callback==1251 and len(raw)>=C.sizeof(Identity):
     identity=Identity.from_buffer_copy(raw[:C.sizeof(Identity)]);user=self.identity_id(identity)
     if self.accept and self.accept(user):self.fn('SteamAPI_ISteamNetworkingMessages_AcceptSessionWithUser',B,P,P)(self.net,C.byref(identity))
    elif msg.callback==1252:self.failures.append('Steam P2P connection failed; reconnect or try Direct IP.')
   finally:self.fn('SteamAPI_ManualDispatch_FreeLastCallback',None,I)(self.pipe)
  for handle,(_,deadline,callback)in list(self.pending.items()):
   if time.monotonic()>deadline:self.pending.pop(handle);callback(None)
 def metadata(self,lobby,key):
  raw=self.match('GetLobbyData',S,[Q,S],lobby,key.encode());return(raw or b'').decode('utf-8','replace')[:240]
 def set_data(self,key,value):return self.match('SetLobbyData',B,[Q,S,S],self.lobby,key.encode(),str(value).encode('utf-8'))
 def owner(self,lobby=None):return self.match('GetLobbyOwner',Q,[Q],lobby or self.lobby)
 def members(self):
  if not self.lobby:return set()
  count=self.match('GetNumLobbyMembers',I,[Q],self.lobby)
  return {self.match('GetLobbyMemberByIndex',Q,[Q,I],self.lobby,i)for i in range(min(count,32))}
 def leave(self):
  if self.lobby:self.match('LeaveLobby',None,[Q],self.lobby)
  self.lobby=0;self.accept=None
  if hasattr(self,'friends'):
   self.fn('SteamAPI_ISteamFriends_ClearRichPresence',None,P)(self.friends)
 def presence(self):
  self.fn('SteamAPI_ISteamFriends_SetRichPresence',B,P,S,S)(self.friends,b'connect',f'+connect_lobby {self.lobby}'.encode())
 def create(self,privacy,callback,max_players=4):
  types={'invite':0,'friends':1,'public':2}
  if privacy not in types:raise SteamError('Choose friends, invite-only or public.')
  def done(raw):
   if not raw or len(raw)<16 or struct.unpack_from('<i',raw)[0]!=1:
    callback(None,'Steam could not create a lobby'+(' (result '+str(struct.unpack_from('<i',raw)[0])+')'if raw else' (request timed out)'));return
   self.lobby=struct.unpack_from('<Q',raw,8)[0];self.presence();callback(self.lobby,None)
  from party import player_limit
  self.call(self.match('CreateLobby',Q,[I,I],types[privacy],player_limit(max_players)),513,done)
 def join(self,lobby,callback):
  def done(raw):
   if not raw or len(raw)<20 or struct.unpack_from('<I',raw,16)[0]!=1:
    callback(None,'Lobby is full, private, unavailable or the invitation expired.');return
   self.lobby=struct.unpack_from('<Q',raw)[0];self.presence();callback(self.lobby,None)
  self.call(self.match('JoinLobby',Q,[Q],int(lobby)),504,done)
 def browse(self,callback):
  from version import PROTOCOL
  self.match('AddRequestLobbyListStringFilter',None,[S,S,I],b'halfswordmp',b'1',0)
  self.match('AddRequestLobbyListDistanceFilter',None,[I],3)
  self.match('AddRequestLobbyListResultCountFilter',None,[I],50)
  def done(raw):
   if not raw or len(raw)<4:callback(None);return
   callback([self.row(self.match('GetLobbyByIndex',Q,[I],i))for i in range(min(struct.unpack_from('<I',raw)[0],50))])
  self.call(self.match('RequestLobbyList',Q,[]),510,done)
 def row(self,lobby):
  from version import PROTOCOL
  host=self.owner(lobby)
  return {'id':str(lobby),'name':self.metadata(lobby,'name')or'HalfSwordMP',
   'host':self.persona(host),'players':self.match('GetNumLobbyMembers',I,[Q],lobby),
   'limit':self.match('GetLobbyMemberLimit',I,[Q],lobby),
   'locked':self.metadata(lobby,'password')=='1','compatible':self.metadata(lobby,'protocol')==str(PROTOCOL),
   'version':self.metadata(lobby,'version')}
 def friends_list(self):
  count=self.fn('SteamAPI_ISteamFriends_GetFriendCount',I,P,I)(self.friends,4);result=[]
  for i in range(min(count,200)):
   user=self.fn('SteamAPI_ISteamFriends_GetFriendByIndex',Q,P,I,I)(self.friends,i,4)
   info=C.create_string_buffer(24)
   played=self.fn('SteamAPI_ISteamFriends_GetFriendGamePlayed',B,P,Q,P)(self.friends,user,info)
   game,_,_,_,lobby=struct.unpack('<QIHHQ',info.raw)
   lobby=lobby if played and game&0xffffff==APP_ID else 0
   result.append({'id':str(user),'name':self.persona(user),'lobby':str(lobby)if lobby else''})
  return sorted(result,key=lambda x:(not bool(x['lobby']),x['name'].casefold()))
 def invite(self,user):
  if not self.lobby:raise SteamError('Create or join a lobby before inviting a friend.')
  if not self.match('InviteUserToLobby',B,[Q,Q],self.lobby,int(user)):raise SteamError('Steam could not send the invitation.')
 def launch_lobby(self):
  import re
  buf=C.create_string_buffer(2048)
  self.fn('SteamAPI_ISteamApps_GetLaunchCommandLine',I,P,P,I)(self.apps,buf,len(buf))
  m=re.search(rb'(?:^|\s)\+connect_lobby\s+([0-9]{15,20})(?:\s|$)',buf.value)
  return int(m[1])if m else 0
 def send(self,data,user,channel,reliable=False):
  identity=self.identity(user)
  # Flush interactive snapshots promptly; allow a failed native session to
  # restart when the shared peer protocol retries its handshake.
  flags=(8 if reliable else 1)|32  # Reliable / UnreliableNoNagle + AutoRestartBrokenSession
  result=self.fn('SteamAPI_ISteamNetworkingMessages_SendMessageToUser',I,P,P,P,U,I,I)(self.net,C.byref(identity),data,len(data),flags,channel)
  if result!=1:raise OSError('Steam send failed (result '+str(result)+').')
 def receive(self,channel,limit=32):
  pointers=(P*limit)();count=self.fn('SteamAPI_ISteamNetworkingMessages_ReceiveMessagesOnChannel',I,P,I,P,I)(self.net,channel,pointers,limit)
  result=[]
  for pointer in pointers[:max(0,min(limit,count))]:
   try:
    msg=C.cast(pointer,C.POINTER(Message)).contents
    if 0<msg.size<=65536:result.append((C.string_at(msg.data,msg.size),self.identity_id(msg.identity)))
   finally:self.fn('SteamAPI_SteamNetworkingMessage_t_Release',None,P)(pointer)
  return result
 def close_session(self,user):
  identity=self.identity(user);self.fn('SteamAPI_ISteamNetworkingMessages_CloseSessionWithUser',B,P,P)(self.net,C.byref(identity))
 def close(self):
  if self.closed:return
  self.closed=True
  try:
   if getattr(self,'initialized',False):
    if hasattr(self,'mm'):self.leave()
    self.fn('SteamAPI_Shutdown',None)()
  finally:
   import _ctypes
   _ctypes.FreeLibrary(self.dll._handle);self.dll._handle=0

class SteamSocket:
 """Socket-shaped adapter so the tested match protocol is shared with UDP."""
 def __init__(self,steam,channel,role):
  self.steam,self.channel,self.role=steam,channel,role;self.queue=deque();self.peers=set();self.next_members=0;self.closed=False
  self.refresh();steam.accept=lambda user:user in self.peers and user!=steam.id
 def refresh(self):
  if time.monotonic()>=self.next_members:
   self.peers=self.steam.members()-{self.steam.id};self.next_members=time.monotonic()+.25
 def setblocking(self,value):pass
 def sendto(self,data,address):
  self.refresh();user,channel=address
  if self.closed or channel!=self.channel or user not in self.peers:raise OSError('Peer left the Steam lobby.')
  self.steam.send(data,user,channel)
 def recvfrom(self,size):
  self.refresh()
  if not self.queue:self.queue.extend(self.steam.receive(self.channel))
  while self.queue:
   data,user=self.queue.popleft()
   if user in self.peers:return data[:size],(user,self.channel)
  raise BlockingIOError()
 def close(self):
  if self.closed:return
  self.closed=True
  for user in self.peers:self.steam.close_session(user)
  self.queue.clear();self.steam.accept=None
