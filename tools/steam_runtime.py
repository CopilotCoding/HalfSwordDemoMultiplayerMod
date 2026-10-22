"""Find a local Valve runtime, or fetch a pinned copy from Valve's repository."""
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import tempfile
import time
from urllib.request import urlopen

# An already verified Valve-signed build is also accepted when Windows cannot
# check certificates offline. Other builds require a current Valve signature.
KNOWN_SHA256 = 'dcfaa13aa419a0641917205957dbe15aa472e7cf09a28cf8d3cf429598e67799'
DOWNLOAD_URL = ('https://raw.githubusercontent.com/ValveSoftware/source-sdk-2013/'
                '0759e2e8e179d5352d81d0d4aaded72c1704b7a9/game/bin/x64/steam_api64.dll')
DOWNLOAD_SHA256 = 'a44e5537939ae4eebc69000589aa9b2437a667813a1657cc779198bae9b815a9'
TRUSTED_HASHES = {KNOWN_SHA256, DOWNLOAD_SHA256}
INIT_EXPORTS = {'SteamInternal_SteamAPI_Init', 'SteamAPI_InitFlat', 'SteamAPI_Init'}
REQUIRED_EXPORTS = frozenset('''
SteamAPI_GetHSteamPipe SteamAPI_Shutdown
SteamAPI_SteamApps_v008 SteamAPI_SteamFriends_v017
SteamAPI_SteamMatchmaking_v009 SteamAPI_SteamUser_v023
SteamAPI_SteamUtils_v010 SteamAPI_SteamNetworkingMessages_SteamAPI_v002
SteamAPI_SteamNetworkingUtils_SteamAPI_v004
SteamAPI_ManualDispatch_Init SteamAPI_ManualDispatch_RunFrame
SteamAPI_ManualDispatch_GetNextCallback SteamAPI_ManualDispatch_FreeLastCallback
SteamAPI_ManualDispatch_GetAPICallResult
SteamAPI_ISteamApps_GetLaunchCommandLine
SteamAPI_ISteamFriends_ClearRichPresence SteamAPI_ISteamFriends_GetFriendByIndex
SteamAPI_ISteamFriends_GetFriendCount SteamAPI_ISteamFriends_GetFriendGamePlayed
SteamAPI_ISteamFriends_GetFriendPersonaName SteamAPI_ISteamFriends_SetRichPresence
SteamAPI_ISteamMatchmaking_AddRequestLobbyListDistanceFilter
SteamAPI_ISteamMatchmaking_AddRequestLobbyListResultCountFilter
SteamAPI_ISteamMatchmaking_AddRequestLobbyListStringFilter
SteamAPI_ISteamMatchmaking_CreateLobby SteamAPI_ISteamMatchmaking_GetLobbyByIndex
SteamAPI_ISteamMatchmaking_GetLobbyData SteamAPI_ISteamMatchmaking_GetLobbyMemberByIndex
SteamAPI_ISteamMatchmaking_GetLobbyOwner SteamAPI_ISteamMatchmaking_GetNumLobbyMembers
SteamAPI_ISteamMatchmaking_InviteUserToLobby SteamAPI_ISteamMatchmaking_JoinLobby
SteamAPI_ISteamMatchmaking_LeaveLobby SteamAPI_ISteamMatchmaking_RequestLobbyList
SteamAPI_ISteamMatchmaking_SetLobbyData SteamAPI_ISteamMatchmaking_SetLobbyJoinable
SteamAPI_SteamNetworkingIdentity_GetSteamID64 SteamAPI_SteamNetworkingIdentity_SetSteamID64
SteamAPI_SteamNetworkingMessage_t_Release
SteamAPI_ISteamNetworkingMessages_AcceptSessionWithUser
SteamAPI_ISteamNetworkingMessages_CloseSessionWithUser
SteamAPI_ISteamNetworkingMessages_ReceiveMessagesOnChannel
SteamAPI_ISteamNetworkingMessages_SendMessageToUser
SteamAPI_ISteamNetworkingUtils_InitRelayNetworkAccess
SteamAPI_ISteamUser_BLoggedOn SteamAPI_ISteamUser_GetSteamID SteamAPI_ISteamUtils_GetAppID
'''.split())


def compatible(data):
    """Inspect PE exports without loading untrusted code into Python."""
    try:
        if not 1024 <= len(data) <= 8 * 1024 * 1024 or data[:2] != b'MZ':return False
        pe = struct.unpack_from('<I', data, 60)[0]
        if data[pe:pe+4] != b'PE\0\0':return False
        machine, sections = struct.unpack_from('<HH', data, pe+4)
        optional_size = struct.unpack_from('<H', data, pe+20)[0]
        optional = pe+24
        if machine != 0x8664 or struct.unpack_from('<H', data, optional)[0] != 0x20b:return False
        if not 1 <= sections <= 96 or optional_size < 120:return False
        table = optional+optional_size
        def offset(rva):
            for i in range(sections):
                size, va, raw_size, raw = struct.unpack_from('<IIII', data, table+i*40+8)
                if va <= rva < va+max(size, raw_size):
                    result = raw+rva-va
                    if rva-va < raw_size and 0 <= result < len(data):return result
            raise ValueError('Invalid RVA')
        exports = offset(struct.unpack_from('<I', data, optional+112)[0])
        count = struct.unpack_from('<I', data, exports+24)[0]
        if not 1 <= count <= 100000:return False
        names = offset(struct.unpack_from('<I', data, exports+32)[0])
        found = set()
        for i in range(count):
            name = offset(struct.unpack_from('<I', data, names+i*4)[0])
            end = data.find(b'\0', name, min(len(data), name+256))
            if end < 0:return False
            found.add(data[name:end].decode('ascii'))
        return REQUIRED_EXPORTS <= found and bool(INIT_EXPORTS & found)
    except (ValueError, struct.error, UnicodeError, IndexError):return False


def valve_signed(path):
    # The path is passed as data, not interpolated into PowerShell code.
    environment = os.environ.copy();environment['HSMP_SIGNATURE_PATH'] = str(path.resolve())
    command = "$s=Get-AuthenticodeSignature -LiteralPath $env:HSMP_SIGNATURE_PATH; [bool]($s.Status -eq 'Valid' -and $s.SignerCertificate.Subject -match '(^|,\\s*)O=Valve (Corp\\.|Corporation)(,|$)')"
    executable = Path(os.environ.get('SystemRoot', r'C:\Windows'))/'System32/WindowsPowerShell/v1.0/powershell.exe'
    # A launcher started from PowerShell 7 can inherit incompatible module paths.
    environment['PSModulePath'] = str(executable.parent/'Modules')
    try:
        result = subprocess.run([str(executable), '-NoProfile', '-NonInteractive', '-Command', command],
                                env=environment, capture_output=True, text=True, timeout=12,
                                creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        return result.returncode == 0 and result.stdout.strip() == 'True'
    except (OSError, subprocess.SubprocessError):return False


def steam_roots():
    roots = []
    if os.name == 'nt':
        import winreg
        for hive, key, value in ((winreg.HKEY_CURRENT_USER, r'Software\Valve\Steam', 'SteamPath'),
                                 (winreg.HKEY_LOCAL_MACHINE, r'SOFTWARE\WOW6432Node\Valve\Steam', 'InstallPath'),
                                 (winreg.HKEY_LOCAL_MACHINE, r'SOFTWARE\Valve\Steam', 'InstallPath')):
            try:
                with winreg.OpenKey(hive, key) as handle:roots.append(Path(winreg.QueryValueEx(handle, value)[0]))
            except OSError:pass
    for variable in ('ProgramFiles(x86)', 'ProgramFiles'):
        if os.environ.get(variable):roots.append(Path(os.environ[variable])/'Steam')
    return list(dict.fromkeys(roots))


def libraries(roots):
    result = list(roots)
    for root in roots:
        try:text = (root/'steamapps/libraryfolders.vdf').read_text(encoding='utf-8')
        except (OSError, UnicodeError):continue
        # Modern "path" fields and old numeric path entries; never execute VDF.
        for value in re.findall(r'"(?:path|[0-9]+)"\s*"((?:\\.|[^"\\])*)"', text):
            value = value.replace('\\\\', '\\').replace('\\"', '"')
            path = Path(value)
            if path.is_absolute():result.append(path)
    return list(dict.fromkeys(result))


def candidates(root, roots=None):
    roots = steam_roots() if roots is None else list(roots)
    games = []
    try:
        game = json.loads((root/'runtime/build.json').read_text()).get('game')
        if game:games.append(Path(game))
    except (OSError, ValueError, TypeError):pass
    common = [library/'steamapps/common' for library in libraries(roots)]
    # Prioritize the selected game. The rest are ordinary installed games/tools;
    # no SteamVR dependency and no hard-coded requirement for a particular game.
    bases = games+common+roots
    seen = set()
    deadline = time.monotonic()+12
    for base in bases:
        for directory, folders, files in os.walk(base, followlinks=False):
            if time.monotonic() > deadline:return
            folders[:] = sorted(n for n in folders if n.casefold() not in
                {'content', 'steamapps', 'workshop', 'shadercache', 'downloading', '.git', 'ue4ss', 'node_modules'})
            # The common directory is entered directly above, not via Steam's root.
            for name in files:
                if name.casefold() != 'steam_api64.dll':continue
                path = Path(directory)/name
                key = str(path.resolve()).casefold()
                if key not in seen:seen.add(key);yield path


def cache_runtime(cached, data):
    cached.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=cached.parent, suffix='.dll', delete=False) as stream:
            temporary = Path(stream.name);stream.write(data)
        digest = hashlib.sha256(data).hexdigest()
        if digest not in TRUSTED_HASHES and not valve_signed(temporary):
            raise ValueError('Copied Steam runtime has no valid Valve signature.')
        try:temporary.replace(cached)
        except PermissionError:
            # A simultaneous launch may already have cached/loaded it.
            if cached.read_bytes() != data:raise
        return cached
    finally:
        if temporary is not None:temporary.unlink(missing_ok=True)


def download_runtime(cached):
    print('Downloading Steam runtime from Valve\'s official Source SDK repository...', flush=True)
    with urlopen(DOWNLOAD_URL, timeout=25) as response:
        data = response.read(8*1024*1024+1)
    if hashlib.sha256(data).hexdigest() != DOWNLOAD_SHA256 or not compatible(data):
        raise ValueError('Downloaded Steam runtime checksum/API mismatch.')
    return cache_runtime(cached, data)


def find_runtime(root=None, *, roots=None):
    root = Path(root) if root is not None else Path(__file__).resolve().parents[1]
    cached = root/'runtime/steam/steam_api64.dll'
    seen = set()
    if cached.is_file():
        try:
            data = cached.read_bytes();digest = hashlib.sha256(data).hexdigest()
            if compatible(data) and (digest in TRUSTED_HASHES or valve_signed(cached)):return cached
            seen.add(digest)
        except OSError:pass
    for path in candidates(root, roots):
        try:
            if not 1024 <= path.stat().st_size <= 8*1024*1024:continue
            data = path.read_bytes();digest = hashlib.sha256(data).hexdigest()
            if digest in seen:continue
            seen.add(digest)
            if not compatible(data) or not (digest in TRUSTED_HASHES or valve_signed(path)):continue
            return cache_runtime(cached, data)
        except OSError:continue
    try:return download_runtime(cached)
    except (OSError, ValueError) as exc:
        raise ValueError('Steam runtime setup failed: '+str(exc)+
                         ' Reopen multiplayer with Internet access to retry. Direct IP remains available.')from None
