"""Build a deterministic player package containing only portable source files."""
import io
from pathlib import Path, PurePosixPath
import stat
import re
import zipfile

MAX_PACKAGE = 8 * 1024 * 1024
RETIRED = {"mod/HalfSwordMP/Scripts/host.lua", "mod/HalfSwordMP/Scripts/camera.lua",
           "mod/HalfSwordMP/Scripts/inputs.lua","mod/HalfSwordMP/Scripts/puppet.lua",
           "mod/HalfSwordMP/Scripts/native_bodies.lua", "tools/steam_api64.dll"}


def allowed(path: str) -> bool:
    p=PurePosixPath(path)
    if p.is_absolute() or ".." in p.parts or "\\" in path or path!=p.as_posix():
        return False
    if path in ("README.md","Start Multiplayer.cmd","THIRD_PARTY.md"):
        return True
    if len(p.parts)==2 and p.parts[0]=="tools" and p.suffix==".py":
        return bool(re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*\.py",p.name)) and not (p.name.startswith(("loopback_","dev_")) or p.name=="game_test.py")
    return (len(p.parts)==4 and p.parts[:3]==("mod","HalfSwordMP","Scripts")
            and bool(re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*\.lua",p.name)) and p.name not in ("dev.lua","paths.lua"))


def package_bytes(root: Path) -> bytes:
    paths=[root/"README.md",root/"Start Multiplayer.cmd",root/"THIRD_PARTY.md"]
    paths+=list((root/"tools").glob("*.py"))+list((root/"mod").rglob("*.lua"))
    stream=io.BytesIO()
    with zipfile.ZipFile(stream,"w",zipfile.ZIP_DEFLATED) as z:
        for path in sorted(paths):
            relative=path.relative_to(root).as_posix()
            if not path.is_file() or not allowed(relative) or relative in RETIRED:continue
            info=zipfile.ZipInfo("HalfSwordMP/"+relative,(2026,1,1,0,0,0))
            info.compress_type=zipfile.ZIP_DEFLATED
            info.external_attr=(stat.S_IFREG|0o644)<<16
            z.writestr(info,path.read_bytes())
    return stream.getvalue()


def package_files(data: bytes) -> dict[str,bytes]:
    if len(data)>MAX_PACKAGE:raise ValueError("Update package is too large")
    result={}
    names=set()
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        total=0
        for entry in z.infolist():
            if entry.is_dir():continue
            if not entry.filename.startswith("HalfSwordMP/"):raise ValueError("Invalid update root")
            relative=entry.filename[len("HalfSwordMP/"):]
            if (not allowed(relative) or relative.casefold() in names
                    or stat.S_ISLNK(entry.external_attr>>16)):
                raise ValueError("Invalid update file: "+relative)
            total+=entry.file_size
            if total>MAX_PACKAGE:raise ValueError("Expanded update is too large")
            result[relative]=z.read(entry)
            names.add(relative.casefold())
    required={"Start Multiplayer.cmd","tools/launch.py","tools/network.py","tools/version.py",
              "tools/damage.py","tools/rounds.py","tools/frames.py","tools/snapshot.py",
              "mod/HalfSwordMP/Scripts/main.lua","mod/HalfSwordMP/Scripts/session.lua",
              "mod/HalfSwordMP/Scripts/round.lua","mod/HalfSwordMP/Scripts/damage.lua",
              "mod/HalfSwordMP/Scripts/assets.lua"}
    required.add("mod/HalfSwordMP/Scripts/match.lua")
    required.update({"tools/geometry.py","mod/HalfSwordMP/Scripts/geometry.lua",
                     "mod/HalfSwordMP/Scripts/interpolation.lua"})
    required.update({"tools/equipment.py","mod/HalfSwordMP/Scripts/equipment.lua","mod/HalfSwordMP/Scripts/weapon_parts.lua"})
    required.update({"tools/controls.py","mod/HalfSwordMP/Scripts/native_input.lua","mod/HalfSwordMP/Scripts/fighter.lua"})
    required.add('mod/HalfSwordMP/Scripts/injury.lua')
    required.add('mod/HalfSwordMP/Scripts/movement.lua')
    required.add('mod/HalfSwordMP/Scripts/dropped_weapons.lua')
    required.add('tools/dropped.py')
    required.add('mod/HalfSwordMP/Scripts/replica.lua')
    required.add('mod/HalfSwordMP/Scripts/rig_math.lua')
    required.add('mod/HalfSwordMP/Scripts/native_sever.lua')
    required.add('mod/HalfSwordMP/Scripts/clothing.lua')
    required.add('mod/HalfSwordMP/Scripts/cosmetics.lua')
    required.add('mod/HalfSwordMP/Scripts/pause.lua')
    required.update({'mod/HalfSwordMP/Scripts/held_pose.lua','mod/HalfSwordMP/Scripts/input_recovery.lua'})
    required.add('mod/HalfSwordMP/Scripts/audio_guard.lua')
    required.add('mod/HalfSwordMP/Scripts/voice.lua')
    required.update({'tools/admission.py','tools/steam.py','tools/steam_runtime.py','tools/lobbies.py','tools/steam_updates.py',
                     'THIRD_PARTY.md','mod/HalfSwordMP/Scripts/ui.lua'})
    if not required<=result.keys():raise ValueError("Incomplete update package")
    return result
