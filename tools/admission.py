"""Password admission and session authentication for either transport."""
import hashlib,hmac,json

def password(value):
 if not isinstance(value,str)or len(value)>128 or any(ord(c)<32 for c in value):
  raise ValueError('Use a password of at most 128 characters without control characters.')
 return value

def base_key(value,salt):
 return hashlib.pbkdf2_hmac('sha256',password(value).encode('utf-8'),bytes.fromhex(salt),200000)

def session_key(base,client,host,build):
 return hmac.digest(base,('HalfSwordMP admission 1|'+client+'|'+host+'|'+build).encode(),'sha256')

def proof(key):return hmac.digest(key,b'HalfSwordMP host proof','sha256').hex()

def seal(message,key):
 if key is None:return message
 body=json.dumps(message,separators=(',',':'),sort_keys=True,allow_nan=False).encode()
 return dict(message,auth=hmac.digest(key,body,'sha256').hex())

def verify(message,key):
 if key is None:return 'auth'not in message
 claimed=message.get('auth')
 if not isinstance(claimed,str)or len(claimed)!=64:return False
 unsigned={k:v for k,v in message.items()if k!='auth'}
 try:return hmac.compare_digest(claimed,seal(unsigned,key)['auth'])
 except(ValueError,TypeError,RecursionError):return False
