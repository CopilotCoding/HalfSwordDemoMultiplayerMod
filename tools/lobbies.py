"""Steam lobby lifecycle and UI data, separate from native combat."""
import ctypes as C
import secrets,time
from network import atomic_write
from party import Bridge
from steam import Steam,SteamSocket,SteamError
from version import VERSION,PROTOCOL

def hextext(value):return str(value).encode('utf-8').hex()or'-'
def unhex(value,limit=128):
 if value=='-':return ''
 if not isinstance(value,str)or len(value)>limit*8:raise ValueError('Menu field is too long.')
 try:result=bytes.fromhex(value).decode('utf-8')
 except(ValueError,UnicodeError):raise ValueError('Invalid menu text.')from None
 if len(result)>limit or any(ord(c)<32 for c in result):raise ValueError('Invalid menu text.')
 return result
def lobby_id(value):
 if not isinstance(value,str)or not value.isascii()or not value.isdigit()or not 0<int(value)<2**64:raise ValueError('Choose a Steam lobby or friend first.')
 return int(value)

class Lobbies:
 def __init__(self,menu,factory=Steam):
  self.menu=menu;self.api=factory();self.operation=False;self.generation=0
  self.channel=0;self.host=0;self.role='';self.name='';self.privacy='friends';self.invitation=''
  self.rows=[];self.friends=[];self.message='Steam ready - '+self.api.name
  self.next_poll=0;self.last_joinable=None
  launch=self.api.launch_lobby()
  if launch:self.invitation=str(launch);self.message='Steam invitation received. Enter a password if required, then Accept invite.'
 def leave(self):
  self.generation+=1;self.api.leave();self.host=0;self.role='';self.channel=0;self.last_joinable=None
  self.message='Steam ready - create a lobby, choose Friends or browse Public lobbies.'
 def start(self,privacy,name,password):
  if self.operation:raise SteamError('A Steam lobby request is still finishing. Please wait.')
  self.menu.disconnect();self.operation=True;generation=self.generation
  self.privacy=privacy;self.name=name.strip()or self.api.name+"'s match"
  self.channel=secrets.randbelow(30000)+1
  self.message='Creating Steam lobby...';self.menu.message=self.message
  def done(lobby,error):
   self.operation=False
   if generation!=self.generation:
    if lobby:self.api.leave()
    return
   if error:self.message=error;self.menu.message=error;return
   for key,value in {'halfswordmp':'1','protocol':PROTOCOL,'version':VERSION,'build':self.menu.build,'limit':self.menu.settings['max_players'],
    'name':self.name,'password':int(bool(password)),'channel':self.channel,'host':str(self.api.id)}.items():
    if not self.api.set_data(key,value):self.api.leave();self.message='Steam could not publish lobby settings. Try again.';self.menu.message=self.message;return
   self.host=self.api.id;self.role='host'
   self.connect(password)
   self.message=f'{self.privacy.title()} Steam lobby: {self.name}';self.menu.message=self.message
  try:self.api.create(privacy,done,self.menu.settings['max_players'])
  except Exception:self.operation=False;raise
 def join(self,value,password):
  target=lobby_id(value or self.invitation)
  if self.operation:raise SteamError('A Steam lobby request is still finishing. Please wait.')
  self.menu.disconnect();self.operation=True;generation=self.generation
  self.message='Joining Steam lobby...';self.menu.message=self.message
  def done(lobby,error):
   self.operation=False
   if generation!=self.generation:
    if lobby:self.api.leave()
    return
   if error:self.message=error;self.menu.message=error;return
   try:
    if self.api.metadata(lobby,'halfswordmp')!='1':raise SteamError('That lobby is not a HalfSwordMP match.')
    if self.api.metadata(lobby,'protocol')!=str(PROTOCOL):raise SteamError('Mod versions are incompatible. Install the same ZIP on both PCs.')
    if self.api.metadata(lobby,'build')!=self.menu.build:raise SteamError('The host has a different Half Sword Demo build.')
    self.channel=int(self.api.metadata(lobby,'channel'))
    if not 1<=self.channel<=30000:raise SteamError('The lobby has invalid connection settings.')
    self.host=self.api.owner(lobby)
    if self.host==self.api.id:raise SteamError('Use a second Steam account to join your own host.')
    if str(self.host)!=self.api.metadata(lobby,'host'):raise SteamError('The original host left. Choose another lobby.')
    self.role='join';self.name=self.api.metadata(lobby,'name');self.connect(password)
    self.invitation='';self.message='Connecting to '+self.name;self.menu.message=self.message
   except(ValueError,OSError)as exc:self.api.leave();self.message=str(exc);self.menu.message=self.message
  try:self.api.join(target,done)
  except Exception:self.operation=False;raise
 def connect(self,password):
  transport=SteamSocket(self.api,self.channel,self.role)
  try:self.menu.bridge=Bridge(self.role,None,self.menu.build,self.menu.runtime,password=password,
   transport=transport,target=(self.host,self.channel)if self.role=='join'else None,max_players=self.menu.settings['max_players'])
  except Exception:transport.close();self.api.leave();raise
  self.menu.connection_transport='steam'
  from steam_updates import SteamTransfer
  self.menu.steam_updates=SteamTransfer(self.menu,self.api,self.channel)
 def browse(self):
  self.message='Searching public Steam lobbies...'
  def done(rows):
   if rows is None:self.message='Steam lobby search failed. Try Refresh.'
   else:self.rows=rows;self.message=f'{len(rows)} available public Steam lobbies'
  self.api.browse(done)
 def load_friends(self):
  self.friends=self.api.friends_list();self.message='Choose a friend to invite, or join their existing lobby.'
 def tick(self):
  self.api.pump()
  for event,value in self.api.events:
   if event=='invite':self.invitation=str(value);self.message='Steam invite received. Enter a password if required, then Accept invite.'
  self.api.events.clear()
  now=time.monotonic()
  if now>=self.next_poll:
   self.next_poll=now+.5
   if self.api.lobby and self.role:
    if not self.api.logged_on()or self.api.owner()!=self.host:
     self.menu.disconnect();self.message='Steam host left or Steam went offline.';self.menu.message=self.message
    elif self.role=='host':
     joinable=not self.menu.bridge or self.menu.bridge.population<self.menu.bridge.max_players
     if joinable!=self.last_joinable:
      self.api.match('SetLobbyJoinable',C.c_bool,[C.c_uint64,C.c_bool],self.api.lobby,joinable)
      self.last_joinable=joinable
   self.publish()
 def publish(self):
  m=self.menu
  atomic_write(m.runtime/'steam.state','|'.join(map(str,['HSSTEAM1',hextext(self.message),self.api.lobby or'-',
   self.role or'-',self.invitation or'-',int(self.operation),time.time()]))+'\n')
  lines=['HSLOBBIES1']
  for row in self.rows:
   lines.append('|'.join(map(str,[row['id'],hextext(row['name']),hextext(row['host']),row['players'],int(row['locked']),int(row['compatible']),row['version']or'-',row.get('limit',4)])))
  atomic_write(m.runtime/'steam.lobbies','\n'.join(lines)+'\n')
  atomic_write(m.runtime/'steam.friends','HSFRIENDS1\n'+''.join('|'.join([r['id'],hextext(r['name']),r['lobby']or'-'])+'\n'for r in self.friends))
 def close(self):self.api.close()
