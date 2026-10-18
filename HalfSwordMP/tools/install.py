"""Install our source mod and a pinned official UE4SS build into this game copy."""
from pathlib import Path
import hashlib
import json
import shutil
import sys
import zipfile
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[1]
LOADER = "UE4SS_v3.0.1-1181-g83330635.zip"
LOADER_SHA256 = "b9a166a756605b21058a64cde93bcaab1a855dba3553e5c7e6ce0fa8fdfad7b9"
LOADER_URL = "https://github.com/UE4SS-RE/RE-UE4SS/releases/download/experimental/" + LOADER


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
    archive = get_loader()
    marker = binaries / "ue4ss/.halfswordmp-managed"
    if ((binaries / "dwmapi.dll").exists() or (binaries / "ue4ss").exists()) and not marker.exists():
        raise ValueError("An unmanaged loader exists. Back it up before installing.")
    fresh = not marker.exists()
    if fresh or marker.read_text().strip() != LOADER_SHA256:
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
    shutil.copytree(source, destination, dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns(*retired, "paths.lua"))
    runtime = ROOT / "runtime"
    runtime.mkdir(exist_ok=True)
    executable = binaries / "HalfSwordUE5-Win64-Shipping.exe"
    build_hash = file_sha256(executable)
    (runtime / "build.json").write_text(json.dumps({"sha256": build_hash, "game": str(game)}, indent=2))
    (destination / "Scripts/paths.lua").write_text(
        "return {runtime = " + json.dumps(runtime.as_posix()) + ", scripts = "
        + json.dumps((destination / "Scripts").as_posix()) + "}\n", encoding="utf-8"
    )
    print(f"Installed HalfSwordMP into {destination}")
    print(f"Runtime data: {runtime}")


if __name__ == "__main__":
    try:
        install(Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT / "Half Sword Demo")
    except (OSError, ValueError, zipfile.BadZipFile) as exc:
        sys.exit(str(exc))
