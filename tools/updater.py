"""Optional host-to-client updates. Downloads stage; changes apply after game exit."""
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import shutil
import threading
import time
from urllib.request import build_opener, ProxyHandler, HTTPRedirectHandler

from bundle import MAX_PACKAGE,RETIRED,package_bytes,package_files
from version import VERSION,PROTOCOL


class UpdateServer:
    def __init__(self,root:Path,port:int,bind="0.0.0.0"):
        payload=package_bytes(root)
        manifest=json.dumps({"format":1,"version":VERSION,"protocol":PROTOCOL,
                             "size":len(payload),"sha256":hashlib.sha256(payload).hexdigest()}).encode()
        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                if self.path=="/manifest.json":body,kind=manifest,"application/json"
                elif self.path=="/package.zip":body,kind=payload,"application/zip"
                else:self.send_error(404);return
                self.send_response(200);self.send_header("Content-Type",kind)
                self.send_header("Content-Length",str(len(body)));self.end_headers();self.wfile.write(body)
            def log_message(self,*args):pass
        self.server=ThreadingHTTPServer((bind,port),Handler)
        self.thread=threading.Thread(target=self.server.serve_forever,daemon=True)
        self.thread.start()
    def close(self):
        self.server.shutdown();self.server.server_close();self.thread.join(timeout=2)


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self,*args,**kwargs):return None


class Updates:
    def __init__(self,root:Path,runtime:Path):
        self.root,self.runtime=root,runtime
        self.current=hashlib.sha256(package_bytes(root)).hexdigest()
        self.message="Updates off"
        self.pending=None
        self.pending_hash=None
        self.thread=None
        self.apply_requested=False
    @property
    def busy(self):return self.thread is not None and self.thread.is_alive()
    def stage(self,data,manifest):
        if(len(data)>MAX_PACKAGE or len(data)!=manifest.get('size')
                or hashlib.sha256(data).hexdigest()!=manifest.get('sha256')):
            raise ValueError('Update checksum mismatch')
        package_files(data)
        destination=self.runtime/'updates/pending.zip';destination.parent.mkdir(parents=True,exist_ok=True)
        destination.write_bytes(data);self.pending=destination;self.pending_hash=manifest['sha256']
        self.message='Update ready - applies after the game closes'
    def check(self,base:str):
        if self.busy:return
        self.message="Checking for updates..."
        def work():
            try:
                opener=build_opener(ProxyHandler({}),NoRedirect())
                with opener.open(base+"/manifest.json",timeout=4) as response:
                    raw=response.read(16385)
                if len(raw)>16384:raise ValueError("Invalid update manifest")
                m=json.loads(raw)
                if (not isinstance(m,dict) or m.get("format")!=1 or not isinstance(m.get("version"),str)
                        or type(m.get("size")) is not int or not 0<m["size"]<=MAX_PACKAGE
                        or not isinstance(m.get("sha256"),str) or len(m["sha256"])!=64):
                    raise ValueError("Invalid update manifest")
                if m["sha256"]==self.current:self.message="Up to date";return
                with opener.open(base+"/package.zip",timeout=8) as response:data=response.read(MAX_PACKAGE+1)
                if len(data)!=m["size"] or hashlib.sha256(data).hexdigest()!=m["sha256"]:
                    raise ValueError("Update checksum mismatch")
                package_files(data)
                destination=self.runtime/"updates/pending.zip"
                destination.parent.mkdir(parents=True,exist_ok=True)
                destination.write_bytes(data)
                self.pending=destination
                self.pending_hash=m["sha256"]
                self.message="Update ready — applies after the game closes"
            except Exception as exc:self.message="Update check failed: "+str(exc)
        self.thread=threading.Thread(target=work,daemon=True);self.thread.start()
    def apply(self):
        if self.pending is None:return False
        payload=self.pending.read_bytes()
        if hashlib.sha256(payload).hexdigest()!=self.pending_hash:
            raise ValueError("Staged update checksum mismatch; check for updates again")
        files=package_files(payload)
        old_files=package_files(package_bytes(self.root))
        backup=self.runtime/"updates/backup"
        replaced=[]
        try:
            for name in sorted(old_files.keys() | files.keys() | {n for n in RETIRED if (self.root/n).is_file()}):
                target=self.root/name
                if not target.resolve().is_relative_to(self.root.resolve()):raise ValueError("Invalid update target")
                original=backup/name
                existed=target.exists()
                if existed:
                    original.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(target,original)
                replaced.append((target,original,existed))
                if name not in files:
                    target.unlink(missing_ok=True)
                    continue
                target.parent.mkdir(parents=True,exist_ok=True)
                temporary=target.with_suffix(target.suffix+".update")
                try:
                    temporary.write_bytes(files[name]);temporary.replace(target)
                finally:temporary.unlink(missing_ok=True)
        except Exception:
            for target,original,existed in reversed(replaced):
                if existed:shutil.copyfile(original,target)
                else:target.unlink(missing_ok=True)
            raise
        self.pending=None
        self.pending_hash=None
        self.current=hashlib.sha256(package_bytes(self.root)).hexdigest()
        self.message="Update installed"
        return True
