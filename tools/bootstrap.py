"""Generate an installed Steam bootstrap; connection settings stay out of it."""
import base64,json,os,subprocess,sys
from pathlib import Path
from contextlib import contextmanager
import time

@contextmanager
def installation_lock(root:Path):
 runtime=root/'runtime';runtime.mkdir(parents=True,exist_ok=True)
 with(runtime/'install.lock').open('a+b')as lock:
  if sys.platform=='win32':
   import msvcrt
   lock.write(b'0');lock.flush();lock.seek(0)
   while True:
    try:msvcrt.locking(lock.fileno(),msvcrt.LK_NBLCK,1);break
    except OSError:time.sleep(.1)
  try:yield
  finally:
   if sys.platform=='win32':lock.seek(0);msvcrt.locking(lock.fileno(),msvcrt.LK_UNLCK,1)

def cache_root(game:Path)->Path:
 import hashlib
 key=hashlib.sha256(str(game.resolve()).casefold().encode()).hexdigest()[:16]
 return Path(os.environ.get('LOCALAPPDATA',str(Path.home()/'.local/share')))/'HalfSwordMP'/'installs'/key

def lua_paths(scripts:Path,root:Path,python:Path,game:Path)->str:
 exe=game/'HalfSwordUE5/Binaries/Win64/HalfSwordUE5-Win64-Shipping.exe'
 pythonw=python.with_name('pythonw.exe')
 if not pythonw.is_file():pythonw=python
 psquote=lambda s:"'"+str(s).replace("'","''")+"'"
 args=subprocess.list2cmdline([str(root/'tools/companion.py'),'--root',str(root),'--game',str(game),'--token'])
 # os.execute creates cmd.exe below the game. Resolve that ancestry before
 # detaching the hidden companion, and pass the actual game PID explicitly.
 ps=("$ErrorActionPreference='Stop';$ancestor=$PID;$gamePid=0;"
     "for($i=0;$i -lt 5;$i++){$p=Get-CimInstance Win32_Process -Filter ('ProcessId='+$ancestor);"
     "if(!$p){break};if($p.Name -eq 'HalfSwordUE5-Win64-Shipping.exe'){$gamePid=$ancestor;break};$ancestor=$p.ParentProcessId};"
     "if(!$gamePid){throw 'HalfSwordMP could not identify its game process'};"
     "$arguments="+psquote(args+ ' ')+"+$env:HALFSWORDMP_BOOT_TOKEN+' --pid '+$gamePid;"
     "Start-Process -FilePath "+psquote(pythonw)+" -ArgumentList $arguments -WindowStyle Hidden")
 encoded=base64.b64encode(ps.encode('utf-16le')).decode('ascii')
 return ("local runtime=os.getenv('HALFSWORDMP_RUNTIME')\n"
         "if not runtime or runtime==''then\n"
         " local token=tostring(os.time())..'-'..tostring({}):gsub('[^%w]','')\n"
         " runtime="+json.dumps((root/'runtime/instances').as_posix())+"..'/'..token\n"
         " local command='set \"HALFSWORDMP_BOOT_TOKEN='..token..'\" & powershell.exe -NoProfile -WindowStyle Hidden -EncodedCommand "+encoded+"'\n"
         " local ok=os.execute(command)\n"
         " if not ok then print('[HalfSwordMP] Companion startup failed; run Start Multiplayer.cmd to repair installation.\\n')end\n"
         "end\nreturn {runtime=runtime,scripts="+json.dumps(scripts.as_posix())+"}\n")

def new_instance(root:Path)->Path:
 import uuid
 runtime=root/'runtime/instances'/uuid.uuid4().hex
 runtime.mkdir(parents=True,exist_ok=False)
 return runtime

def game_is_running(executable:Path)->bool:
 """Updates must wait for every window using this installed executable."""
 import ctypes
 from ctypes import wintypes
 k=ctypes.WinDLL('kernel32',use_last_error=True)
 ps=ctypes.WinDLL('psapi',use_last_error=True)
 ps.EnumProcesses.argtypes=[ctypes.POINTER(wintypes.DWORD),wintypes.DWORD,ctypes.POINTER(wintypes.DWORD)]
 k.OpenProcess.argtypes=[wintypes.DWORD,wintypes.BOOL,wintypes.DWORD];k.OpenProcess.restype=wintypes.HANDLE
 k.QueryFullProcessImageNameW.argtypes=[wintypes.HANDLE,wintypes.DWORD,wintypes.LPWSTR,ctypes.POINTER(wintypes.DWORD)]
 k.CloseHandle.argtypes=[wintypes.HANDLE]
 count=4096
 while True:
  pids=(wintypes.DWORD*count)();used=wintypes.DWORD()
  if not ps.EnumProcesses(pids,ctypes.sizeof(pids),ctypes.byref(used)):raise ctypes.WinError(ctypes.get_last_error())
  if used.value<ctypes.sizeof(pids):break
  count*=2
 expected=os.path.normcase(str(executable.resolve()))
 for pid in pids[:used.value//ctypes.sizeof(wintypes.DWORD)]:
  handle=k.OpenProcess(0x1000,False,pid)
  if not handle:continue
  try:
   path=ctypes.create_unicode_buffer(32768);size=wintypes.DWORD(len(path))
   if k.QueryFullProcessImageNameW(handle,0,path,ctypes.byref(size))and os.path.normcase(path.value)==expected:return True
  finally:k.CloseHandle(handle)
 return False

def close_companion(menu,executable:Path,game_closed:bool):
 menu.disconnect()
 if menu.updates.busy:menu.updates.thread.join(timeout=10)
 if game_closed and menu.updates.pending and (menu.settings['automatic_updates']or menu.updates.apply_requested):
  while game_is_running(executable):time.sleep(.5)
 menu.close(game_closed=game_closed)
