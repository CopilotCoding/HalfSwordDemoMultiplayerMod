"""Package the mod and launcher, excluding the game and runtime data."""
from install import ROOT
from bundle import package_bytes,package_files
from version import VERSION
import hashlib

dist = ROOT / "dist"
dist.mkdir(exist_ok=True)
output = dist / "HalfSwordMP.zip"
payload=package_bytes(ROOT)
package_files(payload)
versioned=f"HalfSwordMP-{VERSION}.zip"
for name in (output.name,"HalfSwordMP-direct-IP.zip","HalfSwordMP-prototype.zip",versioned):
    (dist/name).write_bytes(payload)
(dist/f"HalfSwordMP-{VERSION}.sha256").write_text(hashlib.sha256(payload).hexdigest()+"  "+versioned+"\n",encoding="ascii")
print(output)
print(f"{output.stat().st_size:,} bytes; game and private runtime files excluded")
