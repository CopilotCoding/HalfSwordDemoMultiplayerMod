# HalfSwordMP

**Experimental multiplayer for Half Sword Demo · 2 players · Version 0.10.15 · Protocol 19**

## About the mod

HalfSwordMP turns the demo's arena into a two-player fight. Choose your fighter
and equipment, host a match, and have a friend join by IP over LAN or the
Internet. Use the game's normal controls and combat, then start another round
together. No room code or preliminary single-player fight is needed.

Each PC controls its own native fighter. A native opponent represents the other
player, following their transmitted body and weapon poses. The game handles
combat contact; the mod relays injury and severing events to the injured
player's PC. The host coordinates round resets. UE4SS runs the Lua mod inside
the game, and a Python companion handles networking and updates.

Features include selected loadouts and clothing colours, native weapon contact,
wounds and dismemberment, enemy weapon pickup, shared rounds, and an F5 panel
with restart controls, measured network delay and optional host updates.

## Install

Both players need **matching Half Sword Demo installations**, the same mod
release, and **Python 3.10 or newer** available as `python`.

1. Close all Half Sword windows before installing or updating.
2. Extract the ZIP and open its `HalfSwordMP` folder.
3. Run **Start Multiplayer.cmd**. It finds the usual Steam location or asks for
   your demo folder, installs the mod, and opens the game.
4. Repeat on the other PC.

After installation, you can launch normally through **Steam**. A hidden
companion starts automatically and exits with that game window. Python must
remain installed. The companion is cached locally, so moving the extracted
folder does not break Steam startup.

To open additional windows, run **Start Multiplayer.cmd** again. Keep each
launcher open for the window it starts; each instance gets separate runtime files.

The installer adds a checksum-verified [UE4SS loader](https://github.com/UE4SS-RE/RE-UE4SS)
and scripts without modifying the original game EXE or PAK files. The ZIP
contains no game assets, saves, personal addresses or captured gameplay state.
Connection preferences stay on your PC.

## Play

1. Select your fighter and loadout in the game's main menu.
2. Open **Multiplayer / F5**. Choose **Host** on one PC; its IP field can stay blank.
3. On the other PC, enter the host's address and matching port, then choose **Join**.
4. Choose **Enter multiplayer match** on both PCs. Close F5 and fight.

| Control | Action |
| --- | --- |
| F5 | Open or close the multiplayer panel. |
| Hold G | Fill the native give-up meter; release to cancel. Available while healthy or downed. |
| E / Q | Pick up a nearby dropped weapon with a free hand. |
| Escape | Use the native pause/settings menus. |
| Restart round | Either player can request the next shared round from F5. |

Confirmed KO, death or sustained inability to recover triggers a shared restart.
A recoverable fall alone should not end the round. Giving up requires filling
the native meter. Selected gear returns after each reset; the single-player
return-to-menu death screen stays suppressed.

The restart button waits during normal respawn and allows another attempt if
setup stalls for over six seconds. To change your fighter, return to the main
menu, make your selection, then enter multiplayer again.

## Connection settings

| Situation | Address and ports |
| --- | --- |
| Same home network | Join the host PC's LAN IPv4 address. Default gameplay port: **UDP 7777**. |
| Internet play | Forward the chosen UDP port to the host PC; join its public IPv4 address. |
| Two windows on one PC | Host on **7777**; join **127.0.0.1**, port **7777**, in the other window. |
| Two hosts on one PC | Give each host a different listening port. |

The client uses a temporary local socket, so it can target the host's port
without a conflict. “Address already in use” usually means another host already
occupies that listening port.

The mod does not configure your router or firewall. CGNAT can prevent ordinary
port forwarding. Sessions have no password; the first joining peer takes the guest slot.

## Optional updates

The host shares its mod package; there is no public update server.

- **Check for update** downloads and stages the host's package.
- **Apply update & restart** requests installation after the game closes.
- **Automatic updates from the host** checks once per minute and applies a
  staged package after exit.

Updates wait for all windows using that installed game executable to close.
For Internet updates, also forward **TCP 7778**, or your gameplay port plus one.
Manual ZIP installation works too. Keep both PCs on the same release.

## Status and troubleshooting

Two-PC Internet playtests confirmed usable combat, wounds, grabbing,
dismemberment and enemy weapon pickup, with little perceived lag in those
sessions. Exact wound and sever visuals have not been proved identical.

The latest code passed **164 automated checks**. Two visible games started from
one extracted launcher kept opponent weapon meshes visible through three rounds;
each window also completed ten actual F5 key presses without crashing.

Intermittent clothing/weapon disappearance and historical crashes are not all
conclusively resolved. Long sessions still need testing. Detached limbs, ground
objects and impalement constraints do not share one identical physics simulation.
Pose delivery targets 30 Hz; network delay and slow game frames still affect play.

If joining fails, check the release, port and arena on both PCs, and ensure both
players chose **Enter multiplayer match**. If the companion is offline, close
the game and rerun **Start Multiplayer.cmd** to repair installation. For low
combat FPS, lower graphics settings; **RTT** measures network round-trip time,
which is separate from rendering performance.

Logs: `HalfSwordUE5/Binaries/Win64/ue4ss/UE4SS.log`. Launcher connection and
performance records: local `runtime/instances/` folders. To disable the mod,
close the game and set `HalfSwordMP : 0` in
`HalfSwordUE5/Binaries/Win64/ue4ss/Mods/mods.txt`.

## Development process

The first prototype let a guest control a host-side enemy. Camera, ownership
and latency problems led to the current approach: each person controls their
own fighter, and received poses drive a native opponent. Visual snapshots alone
could not provide combat, so native collision, equipment construction, injury
processing and severing were integrated next.

Development alternated between player reports, runtime inspection, automated
regression checks, visible local games and Internet playtests. Repeated rounds
exposed problems that a successful first fight missed. Later tests distinguished
real keyboard input from programmatic menu toggles, and separate game copies
from two launches of the same installation.

Below are the main issues and their fixes. Remaining uncertainty is marked
where a change has not proved every reported case resolved.

### Setup and match flow

| Issue encountered | Fix or current status |
| --- | --- |
| Installer crashed on `hashlib.file_digest`. | Replaced it with chunked SHA-256 hashing for older supported Python versions. |
| Equipment choices differed from a Steam launch. | Preserved native selection/startup and tested compatible builds; the original cause was not conclusively isolated. |
| Room codes and private settings complicated sharing. | Switched to direct IP; excluded preferences and generated paths from the ZIP. |
| Hosting with a blank IP failed. | Made the destination address join-only and reported occupied host ports explicitly. |
| The guest had the wrong camera or limited movement. | Kept each PC in control of its own native player. |
| Joining needed an existing enemy or showed a dummy. | Added native opponent creation and quarantined inactive arena actors. |
| Duel/Carnage cards interrupted match entry. | Used explicit F5 entry through native start/Duel handlers, preserving the selected fighter. |
| The client entered an empty arena after a reset. | Added current-life checks, waiting for both fighters and respawn retries; intermittent cases still need playtesting. |
| Death returned the client to single-player menus. | Suppressed result cards/exit timelines during multiplayer and coordinated shared resets. |
| Character selection automatically pulled players back into a match. | Cleared the old match and required explicit re-entry after selection. |
| Clients could not restart, or stalled resets blocked recovery. | Added acknowledged client requests, retained life IDs and a six-second retry path. |
| Additional windows were blocked; Steam needed an open launcher. | Added per-instance runtimes and automatic companion startup for Steam. |
| Two launches of one package could disrupt startup. | Removed the temporary shared path; unchanged scripts stay untouched and replacements are atomic. |
| Updates had awkward timing or failed from the Steam cache. | Staged installation until all game windows close and removed same-file cache copying. |

### Combat, equipment and appearance

| Issue encountered | Fix or current status |
| --- | --- |
| Opponents appeared in different positions. | Used common arena coordinates and measured poses instead of independent remote movement. |
| Visual proxies lacked cuts, stabs or weapon contact. | Used native fighters, collision bodies and weapon/query components. |
| Launches, phantom impacts and excessive knockback. | Removed competing remote simulation, extra capsule blocking and duplicate replay forces. Native knockback remains unchanged. |
| Fast swings separated weapons from hands. | Interpolated held weapons relative to measured hands and stopped competing remote weapon ticks. |
| Opponent weapons or modular parts were missing. | Captured native construction, mapped components and restored render flags. Later intermittent disappearance remains unconfirmed. |
| Dropped weapons disappeared from the other player's view. | Tracked released native actors and sent mesh poses; refreshed replaced component lists. Intermittent cases remain open. |
| Enemy drops could be seen but not used. | Added validated ownership transfer and native hand setup for pickup. |
| Injuries appeared only on the opponent representation. | Relayed deduplicated native injury events to the victim's owning PC. |
| Self-dismemberment did not appear. | Prepared native vertex paint and replayed confirmed sever events on the owner; playtesters confirmed usable results. |
| Dropping a weapon rebuilt worn clothing. | Separated weapon changes from armour changes, preserving garments and wounds. |
| Clothing vanished when downed or viewed at certain angles. | Applied native parent bounds and filtered camera hide parameters. Some intermittent cases remain unresolved. |
| Outfits, dyes, shield patterns or sidearms changed between rounds. | Saved all weapon slots, actual cosmetic values and material bases; restored them after native setup. |
| Respawns sometimes started naked. | Waited for configured armour and retried incomplete setup before marking fighters ready. |
| Blood effects were duplicated. | Kept native combat blood rendering and removed the extra replicated particle stream. |

### Controls, performance and stability

| Issue encountered | Fix or current status |
| --- | --- |
| Recoverable knockdowns ended rounds. | Distinguished native KO from a brief fall and required sustained incapacity confirmation. |
| Badly injured fighters stayed down without ending the round. | Remembered critical damage during recovery checks so regeneration could not cancel confirmed incapacity. |
| Resets froze mouse or keyboard input. | Used one persistent game-thread timer, retired latent UI callbacks and restored input after possession without flushing held keys. |
| The game stayed paused or in slow motion. | Restored active-match pause/time-dilation state while respecting open menus. |
| Escape stacked menus or trapped focus over settings. | Retired duplicate pause layers and restored native settings focus. Settings have automated coverage; complete visual testing remains limited. |
| Giving up was instant or changed orientation. | Used the native hold-G meter and preserved player identity. |
| Downed players could not open the give-up meter. | Added bounded input retries and a fallback opening the game's own meter. |
| Hurt hints vanished or the give-up meter doubled. | Kept one current-life HUD/meter; disabled widget ticking no longer incorrectly indicates retirement. |
| Opponent motion looked low-rate or heavily interpolated. | Raised the target to 30 Hz, reused samples and reduced redundant input/appearance work. |
| Combat contact caused stutters. | Budgeted/deduplicated injury replay, throttled discovery and reduced file/material work. Playtesters reported improvement; hardware still matters. |
| Heartbeat, hissing or weapon-slide audio persisted. | Stopped looping cues on driven/hidden actors while retaining finite impact and pain sounds. |
| The opponent's shadow trailed behind. | Enabled shadow-cache invalidation on driven meshes; the final visual result remains unconfirmed. |
| Severing or native-array access caused crashes. | Removed an unsafe by-reference read, checked delayed component lifetimes and replaced TArray callbacks with bounded indexed reads. |
| F5 crashed despite programmatic menu tests passing. | Moved key registration to startup and kept menu work on the game thread. Actual key tests passed; not every historical crash is explained. |

The central lesson was to reuse native systems while explicitly managing
ownership, object lifetimes and round transitions. Showing a remote avatar was
only the start; repeated gameplay and player feedback exposed the difficult bugs.
