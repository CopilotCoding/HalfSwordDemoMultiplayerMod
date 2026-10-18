"""Fixed game input values. Remote peers cannot name functions or send code."""
import math
from pathlib import Path
import re
import time

EPOCH = re.compile(r"^[a-f0-9]{32}$")
MAP = re.compile(r"^/Game/Maps/[A-Za-z0-9_./:-]{1,220}$")
AXES = 12
EVENTS = 16
MAX_FILE = 8192


def validate_input(value):
    if value is None:
        return True
    if not isinstance(value, dict) or set(value)-{"view"} != {"epoch", "seq", "axes", "buttons", "events", "map"}:
        return False
    if "view" in value and (not isinstance(value["view"],list) or len(value["view"])!=3
            or any(type(v) not in (float,int) or not math.isfinite(v) or abs(v)>3600 for v in value["view"])):return False
    if (not isinstance(value["epoch"], str) or not EPOCH.fullmatch(value["epoch"])
            or not isinstance(value["map"],str) or not MAP.fullmatch(value["map"])
            or type(value["seq"]) is not int or not 0 <= value["seq"] < 2**53
            or type(value["buttons"]) is not int or not 0 <= value["buttons"] < 2**17
            or not isinstance(value["axes"], list) or len(value["axes"]) != AXES
            or not isinstance(value["events"], list) or len(value["events"]) > 64):
        return False
    for i, v in enumerate(value["axes"]):
        if type(v) not in (float, int) or abs(v) > (10000 if i >= 10 else 1) or not math.isfinite(v):
            return False
    previous = -1
    for e in value["events"]:
        if (not isinstance(e, list) or len(e) != 2 or type(e[0]) is not int
                or not previous < e[0] < 2**53 or type(e[1]) is not int or not 0 <= e[1] < EVENTS):
            return False
        previous = e[0]
    return True


def input_text(value):
    if value is None:
        return "OFF\n"
    lines = [f"HSIN1|{value['epoch']}|{value['seq']}|{value['buttons']}|{value['map']}",
             "A|" + "|".join(str(n) for n in value["axes"])]
    lines.extend(f"E|{seq}|{event}" for seq, event in value["events"])
    if "view" in value:lines.append("R|"+"|".join(str(v) for v in value["view"]))
    lines.append(f"END|{value['seq']}|{len(lines)}")
    return "\n".join(lines) + "\n"


def read_input(path: Path):
    try:
        s = path.stat()
        if s.st_size > MAX_FILE or time.time() - s.st_mtime > 1:
            return None
        text = path.read_text(encoding="ascii")
        if len(text) > MAX_FILE or not text.endswith("\n"):
            return None
        lines = text.splitlines()
        h, axes, end = lines[0].split("|"), lines[1].split("|"), lines[-1].split("|")
        if (len(h) != 5 or h[0] != "HSIN1" or axes[0] != "A"
                or end != ["END", h[2], str(len(lines)-1)]):
            return None
        value = {"epoch": h[1], "seq": int(h[2]), "buttons": int(h[3]),
                 "axes": [float(n) for n in axes[1:]], "events": [], "map":h[4]}
        for line in lines[2:-1]:
            f = line.split("|")
            if len(f)==4 and f[0]=="R" and "view" not in value:
                value["view"]=[float(n) for n in f[1:]];continue
            if len(f) != 3 or f[0] != "E":
                return None
            value["events"].append([int(f[1]), int(f[2])])
        return value if validate_input(value) else None
    except (OSError, ValueError, IndexError, UnicodeError):
        return None
