"""Optional, bounded update transfer over the admitted Steam peer connection."""
import hashlib,json,secrets,struct,time
from bundle import MAX_PACKAGE,package_bytes
from version import VERSION,PROTOCOL

class SteamTransfer:
 def __init__(self,menu,api,channel):
  self.menu,self.api,self.channel=menu,api,channel+30000
  self.token=None;self.manifest=None;self.chunks=[];self.deadline=0;self.outgoing=None;self.next_send=0
 def request(self):
  bridge=self.menu.bridge
  if not bridge or not bridge.peer.connected or bridge.peer.role!='join':raise ValueError('Join a Steam host before checking for updates.')
  if self.token:return
  self.token=secrets.token_hex(16);self.manifest=None;self.chunks=[];self.deadline=time.monotonic()+30
  self.menu.updates.message='Checking Steam host for updates...'
  self.api.send(b'HSUM'+json.dumps({'request':self.token}).encode(),bridge.peer.address[0],self.channel,True)
 def tick(self):
  bridge=self.menu.bridge
  if not bridge or not bridge.peer.connected or not bridge.peer.address:return
  peer=bridge.peer.address[0];now=time.monotonic()
  allowed=({address[0]for address in bridge.peer_addresses()}if hasattr(bridge,'peer_addresses')else{peer})
  for data,user in self.api.receive(self.channel,8):
   if user not in allowed:continue
   peer=user
   try:
    if data.startswith(b'HSUM')and len(data)<=2048:
     value=json.loads(data[4:])
     if not isinstance(value,dict):continue
     if bridge.peer.role=='host'and set(value)=={'request'}:
      token=value['request']
      if not isinstance(token,str)or len(token)!=32:continue
      bytes.fromhex(token)
      if self.outgoing or now<self.next_send:continue
      payload=package_bytes(self.menu.root);count=(len(payload)+16383)//16384
      manifest={'token':token,'format':1,'version':VERSION,'protocol':PROTOCOL,'size':len(payload),
       'sha256':hashlib.sha256(payload).hexdigest(),'chunks':count}
      self.api.send(b'HSUM'+json.dumps(manifest).encode(),peer,self.channel,True)
      self.outgoing=(token,payload,0,peer);self.next_send=now+.1
     elif bridge.peer.role=='join'and self.token and value.get('token')==self.token:
      size=value.get('size');count=value.get('chunks')
      if(type(size)is not int or not 0<size<=MAX_PACKAGE or type(count)is not int
       or count!=(size+16383)//16384 or not isinstance(value.get('sha256'),str)or len(value['sha256'])!=64):raise ValueError('Invalid Steam update manifest.')
      if value['sha256']==self.menu.updates.current:
       self.token=None;self.menu.updates.message='Up to date'
      else:self.manifest=value;self.chunks=[]
    elif(data.startswith(b'HSUC')and bridge.peer.role=='join'and self.token and self.manifest
     and 24<len(data)<=16408 and data[4:20].hex()==self.token):
     index=struct.unpack_from('<I',data,20)[0]
     if index!=len(self.chunks)or index>=self.manifest['chunks']:raise ValueError('Steam update transfer was interrupted. Check again.')
     self.chunks.append(data[24:]);self.deadline=now+30
     self.menu.updates.message=f'Downloading Steam update: {len(self.chunks)}/{self.manifest["chunks"]}'
     if len(self.chunks)==self.manifest['chunks']:
      self.menu.updates.stage(b''.join(self.chunks),self.manifest);self.token=None;self.chunks=[];self.manifest=None
   except(ValueError,UnicodeError,TypeError,RecursionError)as exc:
    self.token=None;self.chunks=[];self.manifest=None;self.menu.updates.message='Steam update failed: '+str(exc)
  if self.outgoing and now>=self.next_send:
   token,payload,index,peer=self.outgoing
   for _ in range(2):
    chunk=payload[index*16384:(index+1)*16384]
    if not chunk:self.outgoing=None;self.next_send=now+2;break
    self.api.send(b'HSUC'+bytes.fromhex(token)+struct.pack('<I',index)+chunk,peer,self.channel,True);index+=1
   if self.outgoing:self.outgoing=(token,payload,index,peer);self.next_send=now+.1
  if self.token and now>self.deadline:
   self.token=None;self.chunks=[];self.manifest=None;self.menu.updates.message='Steam update timed out. Check again.'
