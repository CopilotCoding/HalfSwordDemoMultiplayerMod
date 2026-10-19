"""Install our source mod and a pinned official UE4SS build into this game copy."""
from pathlib import Path
import hashlib
import json
import tempfile
import sys
import zipfile
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[1]
LOADER = "UE4SS_v3.0.1-1181-g83330635.zip"
LOADER_SHA256 = "b9a166a756605b21058a64cde93bcaab1a855dba3553e5c7e6ce0fa8fdfad7b9"
LOADER_URL = "https://github.com/UE4SS-RE/RE-UE4SS/releases/download/experimental/" + LOADER


def write_if_changed(path: Path, data: bytes) -> None:
    """Concurrent game starts must see a complete old or new script."""
    if path.is_file() and path.read_bytes() == data:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, prefix=path.name+".", suffix=".install", delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(data)
        temporary.replace(path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def get_loader() -> Path:
    archive = ROOT / "tools/downloads" / LOADER
    if not archive.exists():
        archive.parent.mkdir(parents=True, exist_ok=True)
        temporary = archive.with_suffix(".download")
        print("Downloading the pinned official UE4SS loader...")
        try:
            with urlopen(LOADER_URL, timeout=60) as response, temporary.open("wb") as out:
                total = 0
                while chunk := response.read(1024 * 1024):
                    total += len(chunk)
                    if total > 16 * 1024 * 1024:
                        raise ValueError("Loader download exceeds expected size")
                    out.write(chunk)
            if file_sha256(temporary) != LOADER_SHA256:
                raise ValueError("Downloaded loader checksum does not match")
            temporary.replace(archive)
        finally:
            temporary.unlink(missing_ok=True)
    if file_sha256(archive) != LOADER_SHA256:
        raise ValueError("UE4SS archive checksum does not match the pinned build")
    return archive


def game_folder(value: str | Path) -> Path:
    path = Path(str(value).strip().strip('"')).expanduser().resolve()
    if path.name == "HalfSwordUE5-Win64-Shipping.exe":
        path = path.parents[3]
    if not (path / "HalfSwordUE5/Binaries/Win64/HalfSwordUE5-Win64-Shipping.exe").is_file():
        raise ValueError(f"Half Sword Demo executable not found in {path}")
    return path


def install(game: Path) -> None:
    game = game_folder(game)
    binaries = game / "HalfSwordUE5/Binaries/Win64"
    if not (binaries / "HalfSwordUE5-Win64-Shipping.exe").is_file():
        raise ValueError(f"Game executable not found in {binaries}")
    marker = binaries / "ue4ss/.halfswordmp-managed"
    if ((binaries / "dwmapi.dll").exists() or (binaries / "ue4ss").exists()) and not marker.exists():
        raise ValueError("An unmanaged loader exists. Back it up before installing.")
    fresh = not marker.exists()
    if fresh or marker.read_text().strip() != LOADER_SHA256:
        archive=get_loader()
        with zipfile.ZipFile(archive) as z:
            for member in z.infolist():
                target = (binaries / member.filename).resolve()
                if not target.is_relative_to(binaries.resolve()):
                    raise ValueError("Unsafe archive member")
            if fresh:
                z.extractall(binaries)
            else:
                # Upgrade only our loader core and shared API; preserve mod settings.
                for member in z.infolist():
                    if (member.filename in ("dwmapi.dll", "ue4ss/UE4SS.dll")
                            or member.filename.startswith("ue4ss/Mods/shared/")):
                        z.extract(member, binaries)
        marker.write_text(LOADER_SHA256 + "\n")
    if fresh:
        settings = binaries / "ue4ss/UE4SS-settings.ini"
        text = settings.read_text()
        text = text.replace("GuiConsoleEnabled = 1", "GuiConsoleEnabled = 0")
        text = text.replace("bUseUObjectArrayCache = true", "bUseUObjectArrayCache = false")
        settings.write_text(text)
        (binaries / "ue4ss/Mods/mods.txt").write_text(
            "ConsoleEnablerMod : 1\nConsoleCommandsMod : 1\nHalfSwordMP : 1\nKeybinds : 1\n"
        )
    destination = binaries / "ue4ss/Mods/HalfSwordMP"
    source = ROOT / "mod/HalfSwordMP"
    scripts = destination / "Scripts"
    # This directory belongs to this mod. Retired adapters must not survive an
    # extraction over an older release; paths.lua is regenerated below.
    retired = {"host.lua", "camera.lua", "inputs.lua", "puppet.lua", "native_bodies.lua"}
    current = {p.name for p in (source / "Scripts").glob("*.lua") if p.name not in retired}
    if scripts.exists():
        for old in scripts.glob("*.lua"):
            if old.name not in current and old.name != "paths.lua":
                old.unlink()
    for path in source.rglob('*'):
        if path.is_file() and path.name not in retired | {'paths.lua'}:
            write_if_changed(destination/path.relative_to(source),path.read_bytes())
    runtime = ROOT / "runtime"
    runtime.mkdir(exist_ok=True)
    executable = binaries / "HalfSwordUE5-Win64-Shipping.exe"
    build_hash = file_sha256(executable)
    build=json.dumps({"sha256": build_hash, "game": str(game)}, indent=2).encode('utf-8')
    write_if_changed(runtime/'build.json',build)
    # Keep a complete, portable companion beside writable per-user runtime
    # data. Steam launches no longer depend on keeping the extracted ZIP folder.
    from bootstrap import cache_root,lua_paths
    from bundle import package_bytes,package_files
    companion=cache_root(game);companion.mkdir(parents=True,exist_ok=True)
    for name,data in package_files(package_bytes(ROOT)).items():
        write_if_changed(companion/name,data)
    (companion/'runtime').mkdir(exist_ok=True)
    write_if_changed(companion/'runtime/build.json',build)
    write_if_changed(scripts/'paths.lua',lua_paths(scripts,companion,Path(sys.executable),game).encode('utf-8'))
    print(f"Installed HalfSwordMP into {destination}")
    print(f"Runtime data: {runtime}")


if __name__ == "__main__":
    try:
        install(Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT / "Half Sword Demo")
    except (OSError, ValueError, zipfile.BadZipFile) as exc:
        sys.exit(str(exc))
