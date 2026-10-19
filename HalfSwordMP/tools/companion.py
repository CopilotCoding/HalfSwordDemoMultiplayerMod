"""Hidden companion for a modded game opened directly through Steam."""
import argparse,ctypes,json,os,re,subprocess,sys,time
from pathlib import Path
from ctypes import wintypes
from install import file_sha256,install
from menu import Menu
from bootstrap import close_companion,installation_lock

def game_handle(pid:int,game:Path):
 k=ctypes.WinDLL('kernel32',use_last_error=True)
 k.OpenProcess.argtypes=[wintypes.DWORD,wintypes.BOOL,wintypes.DWORD];k.OpenProcess.restype=wintypes.HANDLE
 handle=k.OpenProcess(0x100000|0x1000,False,pid)
 if not handle:raise OSError('The game process is unavailable')
 k.QueryFullProcessImageNameW.argtypes=[wintypes.HANDLE,wintypes.DWORD,wintypes.LPWSTR,ctypes.POINTER(wintypes.DWORD)]
 k.WaitForSingleObject.argtypes=[wintypes.HANDLE,wintypes.DWORD]
 k.CloseHandle.argtypes=[wintypes.HANDLE]
 path=ctypes.create_unicode_buffer(32768);size=wintypes.DWORD(len(path))
 expected=game/'HalfSwordUE5/Binaries/Win64/HalfSwordUE5-Win64-Shipping.exe'
 if not k.QueryFullProcessImageNameW(handle,0,path,ctypes.byref(size))or Path(path.value).resolve()!=expected.resolve():
  k.CloseHandle(handle);raise ValueError('Companion PID does not match the installed game')
 return k,handle

def main():
 p=argparse.ArgumentParser();p.add_argument('--root',type=Path,required=True);p.add_argument('--game',type=Path,required=True)
 p.add_argument('--token',required=True);p.add_argument('--pid',type=int,required=True);args=p.parse_args()
 if not re.fullmatch(r'[A-Za-z0-9-]{1,80}',args.token):raise ValueError('Invalid instance token')
 runtime=args.root/'runtime/instances'/args.token;runtime.mkdir(parents=True,exist_ok=True)
 log=(runtime/'companion.log').open('a',encoding='utf-8',buffering=1);sys.stdout=sys.stderr=log
 k,handle=game_handle(args.pid,args.game)
 lock=(runtime/'companion.lock').open('a+b')
 import msvcrt
 if lock.tell()==0:lock.write(b'0');lock.flush()
 lock.seek(0)
 try:msvcrt.locking(lock.fileno(),msvcrt.LK_NBLCK,1)
 except OSError:k.CloseHandle(handle);lock.close();return
 menu=None
 try:
  executable=args.game/'HalfSwordUE5/Binaries/Win64/HalfSwordUE5-Win64-Shipping.exe'
  build=json.loads((args.root/'runtime/build.json').read_text())['sha256']
  (runtime/'build.json').write_text(json.dumps({'sha256':build,'game':str(args.game)}))
  menu=Menu(args.root,runtime,build,preferences=args.root/'runtime/preferences.json')
  (runtime/'companion.ready').write_text(str(args.pid))
  (runtime/'companion.pid').write_text(str(os.getpid()))
  while k.WaitForSingleObject(handle,0)==258:
   menu.step();time.sleep(.005)
 finally:
  if menu:close_companion(menu,executable,game_closed=True)
  k.CloseHandle(handle);lock.close()
 if menu and menu.restart:
  with installation_lock(args.root):install(args.game)
  subprocess.Popen([str(executable)],cwd=executable.parent)

if __name__=='__main__':main()
