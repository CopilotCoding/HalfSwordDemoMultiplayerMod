# HalfSwordMP

**Experimental multiplayer for Half Sword Demo · 4 players by default · Version 0.12.1 · Protocol 23**

## About the mod

HalfSwordMP turns the demo's arena into a multiplayer free-for-all. Choose your fighter
and equipment, host a Steam lobby or a Direct IP match, and have friends join.
Use the game's normal controls and combat, then start another round
together. No room code or preliminary single-player fight is needed.

Each PC controls its own native fighter. Native opponents represent the other
players, following their transmitted body and weapon poses. The game handles
combat contact; the mod relays injury and severing events to the injured
player's PC. The host coordinates round resets. UE4SS runs the Lua mod inside
the game, and a Python companion handles networking and updates.

Features include selected loadouts and clothing colours, native weapon contact,
wounds and dismemberment, enemy weapon pickup, shared character voice sounds, and an F5 panel
with Steam friends/invites, public Steam lobbies, optional passwords, restart
controls, measured network delay and optional host updates.

Free Mode character tiers, including Master and Baron, are available without the
progression lock. Master is second from the top; click it again for another
native loadout. The top Baron button uses his fixed boss loadout; this unlock does not add new Baron variants. Gauntlet
progression is unchanged.

## Install

All players need **matching Half Sword Demo installations**, the same mod
release, and **Python 3.10 or newer** available as `python`.
Steam mode additionally needs **64-bit Python** and Steam signed in and online.
The launcher automatically finds a compatible Steam runtime locally or downloads
a checksum-verified copy from Valve's official repository. SteamVR and manual
SDK downloads are not required. The Steam DLL is cached locally and is not in
this ZIP or host update packages. First-time setup may need Internet access.

1. Close all Half Sword windows before installing or updating.
2. Extract the ZIP and open its `HalfSwordMP` folder.
3. Run **Start Multiplayer.cmd**. It finds the usual Steam location or asks for
   your demo folder, installs the mod, and opens the game.
4. Repeat on each PC.

**Upgrading:** install this ZIP on every PC, including those using 0.12.0,
to fix guest spawn placement. Protocol 23 requires matching 0.12.x releases.
Earlier protocol versions cannot connect.

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

## Play through Steam

1. Select your fighter and loadout in the normal game menu.
2. Open **Multiplayer / F5 → Steam**. Enter a lobby name if wanted.
3. Click the visibility button to choose **Friends only**, **Invite only** or
   **Public**. Set the host player limit (default **4**, range **2–16**) and an
   optional password, then click **Create lobby**.
4. Choose **Friends**, then click a friend to send a Steam invitation. The guest
   accepts the invitation and uses **Accept invite** in F5 if prompted. Enter the
   password first if the host set one. Without an active lobby, the Friends list
   lets you join friends who have a lobby.
5. Alternatively, choose **Public lobbies / Refresh** and click a listed match.
6. Choose **Enter multiplayer match** on each PC and close F5.

Steam handles P2P/relay connections without manual port forwarding. Lobbies hold
four players by default, with a host-selected limit of 2–16. Invite-only and
friends-only lobbies stay out of the public list;
the list shows only this mod's Steam lobbies. Hosts remain responsible for the
match; leaving ends the session rather than migrating gameplay to another host.

## Play through Direct IP

1. Select your fighter and loadout in the game's main menu.
2. Open **Multiplayer / F5 → Direct IP / Port Forward**. Set an optional password
   and a host player limit (default **4**, range **2–16**), then choose **Host**
   on one PC; its IP field can stay blank.
3. On each other PC, enter the host's address, matching port and password, then **Join**.
4. Choose **Enter multiplayer match** on each PC. Close F5 and fight.

Direct IP does not require Steam networking and never advertises a public listing.
Passwords are not saved in preferences or published in lobby metadata. A password
is optional, not a required room code. Both transports verify it before admitting
the guest and authenticate the resulting gameplay session.

| Control | Action |
| --- | --- |
| F5 | Open or close the multiplayer panel. |
| Hold G | Fill the native give-up meter; release to cancel. Available while healthy or downed. |
| E / Q | Pick up a nearby dropped weapon with a free hand. |
| Escape | Use the native pause/settings menus. |
| Restart round | Any player can request the next shared round from F5. |

Confirmed KO, death, giving up or sustained inability to recover eliminates that
fighter for the round. The round resets after three seconds once one fighter
remains. A recoverable fall alone should not eliminate anyone. Giving up requires
filling the native meter. Selected gear returns after each reset; the
single-player return-to-menu death screen stays suppressed.

Matches can start with two players; they do not wait for every available slot.
The first two players use opposite native duel entrances, regardless of the
lobby capacity. Extra players use the other sides at the same native spawn
distance and face inward. A new fighter entering an active match triggers a
shared fresh round. The host
coordinates all participants and waits for their new fighters before resuming.
Choose the player limit before hosting. Larger matches need more CPU and bandwidth;
the 16-player cap is an allowed setting, not a performance guarantee.

The restart button waits during normal respawn and allows another attempt if
setup stalls for over six seconds. To change your fighter, return to the main
menu, make your selection, then enter multiplayer again.

## Direct IP connection settings

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
port forwarding. Use Steam mode if ordinary forwarding is unavailable.

## Optional updates

The host shares its mod package; there is no public update server.

- **Check for update** downloads and stages the host's package.
- **Apply update & restart** requests installation after the game closes.
- **Automatic updates from the host** checks once per minute and applies a
  staged package after exit.

Updates wait for all windows using that installed game executable to close.
Direct IP Internet updates also need **TCP 7778**, or your gameplay port plus one.
Steam updates travel over the admitted Steam connection and need no extra port;
join the host before checking. Incompatible protocol releases require manual ZIP
installation before joining.
Manual ZIP installation works too. Keep both PCs on the same release.

## Status and troubleshooting

Two-PC Internet playtests confirmed usable combat, wounds, grabbing,
dismemberment and enemy weapon pickup, with little perceived lag in those
sessions. Exact wound and sever visuals have not been proved identical.

**223 automated checks passed.** Real Steam tests created and closed all three
lobby types, verified public visibility and exercised native message loopback.
Two visible local game copies played a password-protected Direct IP session and
completed host/client round restarts. Two-account Steam invitations, remote P2P/
relay combat and Internet update transfer still need a real two-PC playtest.
Use separate Steam accounts for that test; two windows on one account can use
the Direct IP loopback setup above instead.

Version 0.11.1 also passed a fresh automatic runtime download with local library
search disabled, Valve signature verification and real Steam initialization.

Intermittent clothing/weapon disappearance and historical crashes are not all
conclusively resolved. Long sessions still need testing. Detached limbs, ground
objects and impalement constraints do not share one identical physics simulation.
Pose delivery targets 30 Hz; network delay and slow game frames still affect play.
Brief native hand/weapon offsets can remain during extreme swings. Voice cues
use each game's native audio, so randomized samples need not be identical.

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
| Room codes and private settings complicated sharing. | Kept passwords optional, added Steam invitations alongside Direct IP, and excluded preferences/generated paths from the ZIP. |
| Connecting required IP sharing and router setup. | Added Steam P2P/relay transport, friends/invite-only/public lobbies and a Steam-only browser. Real lobby visibility passed; two-account play remains untested. |
| Matches were limited to two players. | Added host limits (default four, range 2–16), authenticated state relay and one native opponent adapter per remote player. Four local game windows connected successfully. |
| A duel-style reset ended a larger match on the first defeat. | Track current-life eliminations and reset once one fighter remains; wait for fresh lives on every participant. |
| Missing poses or disconnected players could strand a reset. | Retain known life IDs for recovery, expire sustained missing fighters and prune disconnected participants. |
| Locked high-tier selections and repeated Baron equipment were confusing. | Enable native Free Mode buttons without changing progression. Repeated Master clicks produced varied kits; Baron remains the fixed native boss. |
| A session admitted anyone who reached the host first. | Added host-verified password admission and session authentication for both transports. Wrong passwords cannot take the gameplay slot. |
| Updates assumed every host had an IP/HTTP address. | Added bounded reliable Steam update transfer after peer admission, retaining staged installation on exit. |
| Hosting with a blank IP failed. | Made the destination address join-only and reported occupied host ports explicitly. |
| The guest had the wrong camera or limited movement. | Kept each PC in control of its own native player. |
| Joining needed an existing enemy or showed a dummy. | Added native opponent creation and quarantined inactive arena actors. |
| Duel/Carnage cards interrupted match entry. | Used explicit F5 entry through native start/Duel handlers, preserving the selected fighter. |
| The client entered an empty arena after a reset. | Added current-life checks, waiting for all fighters and respawn retries; intermittent cases still need playtesting. |
| Death returned the client to single-player menus. | Suppressed result cards/exit timelines during multiplayer and coordinated shared resets. |
| Character selection automatically pulled players back into a match. | Cleared the old match and required explicit re-entry after selection. |
| Clients could not restart, or stalled resets blocked recovery. | Added acknowledged client requests, retained life IDs and a six-second retry path. |
| Additional windows were blocked; Steam needed an open launcher. | Added per-instance runtimes and automatic companion startup for Steam. |
| Two launches of one package could disrupt startup. | Removed the temporary shared path; unchanged scripts stay untouched and replacements are atomic. |
| Updates had awkward timing or failed from the Steam cache. | Staged installation until all game windows close and removed same-file cache copying. |

### Combat, equipment and appearance

| Issue encountered | Fix or current status |
| --- | --- |
| Guests spawned outside the arena or faced sideways after the four-player update. | Use the current native Duel spawn transform and arena origin, preserve native height/rotation, and keep slot two opposite the host at every capacity. Additional slots use the same native distance. |
| Opponents appeared in different positions. | Used common arena coordinates and measured poses instead of independent remote movement. |
| Visual proxies lacked cuts, stabs or weapon contact. | Used native fighters, collision bodies and weapon/query components. |
| Launches, phantom impacts and excessive knockback. | Removed competing remote simulation, extra capsule blocking and duplicate replay forces. Native knockback remains unchanged. |
| Fast swings separated weapons from hands. | Interpolated relative to measured hands, stopped competing ticks, gave held meshes precedence over stowed duplicates, and refreshed equipment mappings together. Brief native physics offsets remain possible. |
| E weapon transitions made a fighter vanish or desync. | Filter invalid temporary mesh transforms before transmission, refresh replaced component mappings, and preserve the fighter during native hand-setup retries. Paired sheath/draw and enemy-pickup checks passed. |
| Old cleanup references could affect recycled native objects. | Check cached actor/component identities before hiding or restoring them. Three paired reset cycles with weapon changes and forced garbage collection passed. |
| Opponent weapons or modular parts were missing. | Captured native construction, mapped components and restored render flags. Later intermittent disappearance remains unconfirmed. |
| Dropped weapons disappeared from the other player's view. | Track released actors with refreshed mesh lists, exclude temporary fists, and retire acknowledged transfers without exhausting the life inventory. |
| Enemy drops could be seen but not used. | Added validated ownership transfer and native hand setup for pickup. |
| Injuries appeared only on the opponent representation. | Relayed deduplicated native injury events to the victim's owning PC. |
| Self-dismemberment did not appear and severed fighters looked choppy. | Corrected a native paint TMap mistakenly read as an array. Owner-side cuts now complete; replay errors no longer repeatedly destroy the remote avatar. Paired arm-cut tests and a player retest passed. |
| Dropping a weapon rebuilt worn clothing. | Separated weapon changes from armour changes, preserving garments and wounds. |
| Clothing vanished when downed or viewed at certain angles. | Applied native parent bounds and filtered camera hide parameters. Some intermittent cases remain unresolved. |
| Outfits, dyes, shield patterns or sidearms changed between rounds. | Saved all weapon slots, actual cosmetic values and material bases; restored them after native setup. |
| Respawns sometimes started naked. | Waited for configured armour and retried incomplete setup before marking fighters ready. |
| Blood effects were duplicated. | Kept native combat blood rendering and removed the extra replicated particle stream. |

### Controls, performance and stability

| Issue encountered | Fix or current status |
| --- | --- |
| A native opponent died while its owner stayed alive and the fighter glitched indefinitely. | Restored current-life confirmed-death reporting to the shared coordinator; headless states count as death and input recovery cannot revive that life. |
| Recoverable knockdowns ended rounds. | Distinguished native KO from a brief fall and required sustained incapacity confirmation. |
| Badly injured fighters stayed down without ending the round. | Remembered critical damage during recovery checks so regeneration could not cancel confirmed incapacity. |
| Resets froze mouse or keyboard input. | Used one persistent game-thread timer, retired latent UI callbacks and restored input after possession without flushing held keys. |
| The game stayed paused or in slow motion. | Restored active-match pause/time-dilation state while respecting open menus. |
| Escape stacked menus or trapped focus over settings. | Retired duplicate pause layers and restored native settings focus. Settings have automated coverage; complete visual testing remains limited. |
| Giving up was instant or changed orientation. | Used the native hold-G meter and preserved player identity. |
| Downed players could not open or finish the give-up meter. | Preserve held G while suppressing death UI, recover failed native input, and complete the hold despite meter removal/replacement. Releasing G or opening a menu cancels it. |
| Hurt hints vanished or the give-up meter doubled. | Kept one current-life HUD/meter; disabled widget ticking no longer incorrectly indicates retirement. |
| Opponent motion looked low-rate or heavily interpolated. | Raised the target to 30 Hz, reused samples and reduced redundant input/appearance work. |
| Combat contact caused stutters. | Budgeted/deduplicated injury replay, throttled discovery and reduced file/material work. Playtesters reported improvement; hardware still matters. |
| Heartbeat, hissing or weapon-slide audio persisted. | Stopped unmanaged loops on driven/hidden actors; replicated exterior voice loops follow the owner's volume and stop state. |
| A fighter made voice sounds that the other player could not hear. | Replicated native pain, breathing and throat audio state with playback revisions; stop stale playback and exclude private heartbeat/music audio. Both directions passed native checks. |
| The opponent's shadow trailed behind. | Enabled shadow-cache invalidation on driven meshes; the final visual result remains unconfirmed. |
| Severing or native-array access caused crashes. | Removed an unsafe by-reference read, checked delayed component lifetimes and replaced TArray callbacks with bounded indexed reads. |
| F5 crashed despite programmatic menu tests passing. | Moved key registration to startup and kept menu work on the game thread. Actual key tests passed; not every historical crash is explained. |

The central lesson was to reuse native systems while explicitly managing
ownership, object lifetimes and round transitions. Showing a remote avatar was
only the start; repeated gameplay and player feedback exposed the difficult bugs.
