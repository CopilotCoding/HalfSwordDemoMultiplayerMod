"""Interactive host/join launcher. Only the host needs to forward a UDP port."""
from pathlib import Path
import json
import os
import subprocess
import sys
import time

from install import ROOT, install, game_folder
from menu import Menu
from bootstrap import new_instance,installation_lock,close_companion


def main():
    print("HalfSwordMP - in-game multiplayer menu")
    runtime = ROOT / "runtime"
    game_path = ROOT / "Half Sword Demo"
    if not game_path.is_dir():
        saved_build = runtime / "build.json"
        if saved_build.exists():
            game_path = Path(json.loads(saved_build.read_text()).get("game", str(game_path)))
        steam_path=Path(os.environ.get("ProgramFiles(x86)",r"C:\Program Files (x86)"))/"Steam/steamapps/common/Half Sword Demo"
        if not game_path.is_dir() and (steam_path/"HalfSwordUE5/Binaries/Win64/HalfSwordUE5-Win64-Shipping.exe").is_file():
            game_path=steam_path
            print(f"Found Half Sword Demo: {game_path}")
        if not game_path.is_dir():
            game_path = game_folder(input("Path to your Half Sword Demo folder: "))
    runtime.mkdir(exist_ok=True)
    companion = None
    game=None
    try:
        with installation_lock(ROOT):install(game_path)
        build = json.loads((runtime / "build.json").read_text())["sha256"]
        instance=new_instance(ROOT)
        (instance/'build.json').write_text(json.dumps({'sha256':build,'game':str(game_path)}))
        companion=Menu(ROOT,instance,build,preferences=runtime/'preferences.json',steam_autostart=True)
        exe = game_path / "HalfSwordUE5/Binaries/Win64/HalfSwordUE5-Win64-Shipping.exe"
        environment=os.environ.copy();environment['HALFSWORDMP_RUNTIME']=instance.as_posix()
        game = subprocess.Popen([str(exe), "-windowed", "-ResX=1280", "-ResY=720"], cwd=exe.parent,env=environment)
        print("Use the Multiplayer panel in the game, or press F5.")
        print("Host on the main PC; join its IP on the laptop. No room code.")
        print("Keep this launcher open while playing. Ctrl+C stops the connection.")
        while game.poll() is None:
            companion.step()
            time.sleep(0.005)
    finally:
        if companion:close_companion(companion,exe,game_closed=game is not None and game.poll() is not None)
    if companion.restart:
        os.execv(sys.executable,[sys.executable,str(Path(__file__).resolve())])


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("Connection stopped.")
    except (OSError, ValueError) as exc:
        print(f"Cannot start: {exc}")
        input("Press Enter to close.")
        sys.exit(1)
