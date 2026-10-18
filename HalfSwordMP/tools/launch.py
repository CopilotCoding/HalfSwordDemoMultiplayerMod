"""Interactive host/join launcher. Only the host needs to forward a UDP port."""
from pathlib import Path
import csv
import json
import os
import subprocess
import sys
import time

from install import ROOT, install, game_folder
from menu import Menu


def main():
    print("HalfSwordMP - in-game multiplayer menu")
    if sys.platform=="win32":
        processes=subprocess.run(["tasklist.exe","/FI","IMAGENAME eq HalfSwordUE5-Win64-Shipping.exe",
                                  "/FO","CSV","/NH"],capture_output=True,text=True,check=True,
                                 timeout=10,creationflags=subprocess.CREATE_NO_WINDOW)
        if any(row and row[0].casefold()=="halfswordue5-win64-shipping.exe" for row in csv.reader(processes.stdout.splitlines())):
            raise ValueError("Close Half Sword before starting the launcher, then try again. This avoids opening a second game copy.")
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
    lock = (runtime / "bridge.lock").open("a+b")
    if sys.platform == "win32":
        import msvcrt
        lock.seek(0)
        if not lock.read(1):
            lock.write(b"0")
            lock.flush()
        lock.seek(0)
        try:
            msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
        except OSError:
            raise ValueError("A launcher is already running for this installation") from None
    game=None
    try:
        install(game_path)
        build = json.loads((runtime / "build.json").read_text())["sha256"]
        (runtime/"ui.command").unlink(missing_ok=True)
        companion=Menu(ROOT,runtime,build)
        exe = game_path / "HalfSwordUE5/Binaries/Win64/HalfSwordUE5-Win64-Shipping.exe"
        game = subprocess.Popen([str(exe), "-windowed", "-ResX=1280", "-ResY=720"], cwd=exe.parent)
        print("Use the Multiplayer panel in the game, or press F5.")
        print("Host on the main PC; join its IP on the laptop. No room code.")
        print("Keep this launcher open while playing. Ctrl+C stops the connection.")
        while game.poll() is None:
            companion.step()
            time.sleep(0.005)
    finally:
        try:
            if companion:companion.close(game_closed=game is not None and game.poll() is not None)
        finally:lock.close()
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
