# HalfSwordMP

HalfSwordMP brings experimental two-player fights to Half Sword Demo. Select
your fighter, host a match and have a friend connect directly by IP. Each person
controls their own native fighter, with the other player's body, equipment and
injury events represented on their PC. The mod adds an in-game multiplayer
panel, shared rounds, a shared restart button and optional updates from the
host.

**Current build: 0.10.11 · Protocol: 17 · Players: 2**

[Install](#install) · [Play](#play) · [Direct IP](#direct-ip) ·
[Updates](#optional-updates) · [Development summary](#development-summary)

## Overview

Experimental direct-IP multiplayer for matching Half Sword Demo installations.
Each PC controls its own native fighter. The other player appears as a native
Willie opponent, equipped with that player's worn armor and native weapons and
whose native collision bodies follow that player's body and weapon snapshots.
There is no room code.

Both peers use the same arena coordinates. The guest's fighter is constructed at
the opposite native spawn; world geometry and blood positions are not mirrored.
The other fighter follows measured poses instead of independently replaying
controls. Native KO/death screens remain suppressed and selected gear is retained
across shared resets. Both PCs must run this version (protocol 18).

## Current build and validation

0.10.12 checks that the saved armour slots and clothing meshes are present
before marking a respawn ready. Missing armour is retried through native setup;
weapon-only changes still preserve the existing clothing and wounds. Match entry
also waits for the native preview's configured armour slots before saving it.

**Restart round is available to both players.** The client's request travels to
the host, which issues one shared reset. Requests repeat until acknowledged by a
new round, and stale requests cannot reset a later round. During respawn the
button waits six seconds, then permits another shared attempt if setup stalls.

Surrender keeps the native **hold G** meter, available while healthy or downed;
release cancels. The mod discovers the widget created by the native G handler,
including cooked ticks that bypass the event-graph hook. It does not construct a
replacement meter or complete surrender from the native hold-start flag. Old
widgets are retired at the next life. A full meter starts the shared reset after
0.25 seconds; KO/death retains the three-second countdown. Native respawn still
needs time to load the fighters and their saved gear.

Pause and surrender-widget changes are deferred out of native Blueprint hooks.
F5 preserves native settings below it and restores their focus when closed.
Escape over settings retires the extra pause layer and uses the native Back
button. Opening a menu cancels a held surrender. Opponent maintenance also
repairs hidden body render flags without rebuilding clothes or injuries.
Interpolation reuses samples from the same frame and skips unchanged native
physics targets; the pose delivery target remains 30 Hz.

Returning to the main menu now leaves the current match and clears its saved
selection. Change your fighter/gear there, then choose **Enter multiplayer match**
again. A visible main menu is never treated as an automatic re-entry request.
The native hurt hint stays visible through partial recovery while serious
injuries remain, even if regenerating health crosses its original display threshold.

The selected gear work from 0.10.10 saves actual clothing colours, shield material/pattern and
all seven native weapon slots, including sheathed sidearms. Native respawn can
reroll cosmetic values; the saved construction and appearance are restored after
setup finishes. Weapon material copying also preserves preset shield patterns
while keeping the receiver's native wound textures.

Enemy-dropped weapons can now be picked up with the normal **E/Q** controls
when nearby and that hand is free. The originating peer validates the transfer;
the receiving game uses native hand setup to create a usable weapon. A transferred
drop disappears from its previous location on both peers. Ground movement still
comes from the originating game's simulation, rather than one shared physics world.

KO/death and confirmed incapacity end the round; resting after a recoverable fall
does not. Failed recovery attempts are checked over time. Missing G press/release
edges in downed states are routed to the native handlers, preserving the game's
meter. Escape toggles one native pause menu, and Resume retires its input callbacks.
Round setup rejects previous-life opponents and retries transient renderer failures.

Validation: **144 automated checks passed**, including client requests over
real UDP, duplicate resets, a stalled respawn retry, incomplete armour, native
hold/cancel discovery, settings focus and widget lifetimes. In two visible native
game windows, both fighters cancelled partial holds; healthy host and injured,
downed client holds then completed with unchanged control yaw and shared resets.
Across repeated resets, both sampled local outfits had all six selected armour
slots and the expected clothing meshes, and both opponents returned. A client
restart command reset both games. Deliberately hidden opponent bodies recovered
on both peers, and each game completed 100 F5 open/close cycles without a crash.
Computer Use was stopped with Escape before a visual graphics-settings check
could finish. That interaction has automated coverage, but is not claimed as
verified in the running game. No numerical laptop FPS improvement is claimed.

In the preceding 0.10.10 visible native game windows,
three successive resets (KO, unrecoverable downing and downed surrender) retained
the exact sampled weapon construction, armour classes, clothing colours, shield
materials and sidearms. Each opponent's sampled clothing and hand appearance
matched its owner. Both opponents returned, with movement/look input enabled.
A one-shot renderer failure recovered without another reset. Repeated native
Escape/Resume tests left zero pause layers and restored input on both peers.
The user confirmed enemy pickup and the final appearance in play.

Unused input capture/transmission and redundant scans/material work have been
removed. This is not a measured laptop FPS or Internet latency guarantee; remaining
client lag needs testing on the second PC. Update **both PCs** for protocol 18.

### Previous release checks

0.10.9 keeps tracking each fighter's native weapons after they are dropped.
The other PC displays their individual mesh parts, materials, sizes and measured
world transforms, including while the native opponent is active. Picking a weapon
back up removes its dropped representation; a new fighter life clears old drops.
The owning game still simulates the dropped weapon. This adds visibility and pose
replication; shared pickup ownership was added in 0.10.10. Full shared ground-object
physics is not implemented.
Protocol 16 requires updating both PCs.

The 0.10.9 suite passed **125 checks**. In two visible native game windows, the
host received three visible mesh parts from the client's dropped spear and the
client received five from the host's dropped modular sword. All sampled mesh
positions matched their received poses. The user also confirmed the drop fix in
play. Native surrender was exercised and both peers returned to shared round 2
without leaving the arena; the existing give-up path needed no gameplay change.
Native knockback remains unchanged: injury replay already supplies zero impulse,
velocity and shockwave, and broader physics tuning was outside this fix.

0.10.8 makes attached worn garments share their native fighter's visibility
bounds on both peers, including each local fighter. Some copy-pose garments kept
standing/spawn bounds while the ragdoll bones moved elsewhere; those bounds could
exclude the visible pants/shoes after a fall. This change uses Unreal's native
parent-bounds flag. It preserves native material instances, wound masks, hidden
bones, clothing visibility and detached limbs rather than rebuilding garments.
Newly created garments are checked four times per second. Weapon-only changes
still keep the existing clothing and saved dyes from 0.10.7.

Incoming native injuries are queued and deduplicated. Each update processes at
most four events and stops starting further replays after a two-millisecond
budget. One native call can itself exceed that budget; wound painting stays
owned by the game. Accepted injuries are retained for later updates. Pending
severs reject destroyed query helpers or weapon components before native calls.
No contact impulses or independent combat calculations are replayed.

Unchanged damage files are no longer rewritten or parsed repeatedly. The companion
publishes round transitions immediately, quantizes countdown file updates to
100 ms, and refreshes unchanged round state twice per second. This avoids replacing
the same hot file at 30 Hz. Pose, input and network injury delivery still target
30 updates/s. No protocol layout changed (protocol 15).

Native injury/sever replay, clothing dyes, selected loadouts, host Restart round,
and incapacity reset rules from 0.10.7 are retained. A healthy fall alone does not
end the round. Critical leg injury stays recorded during that fall so native
regeneration cannot cancel the two-second incapacity confirmation.

Validation: 122 automated checks passed, including hit-burst budgeting without
losing/duplicating damage, native component lifetime checks, garment bounds,
round publication freshness, transport, resets and updates. Visible local host
and client windows were used for native damage and knockdown checks. Both peers
processed over 100 injected native damage events, including a 16-event burst;
queues emptied and no native injury replay errors were recorded. After damage
and a fall, all sampled worn garments kept valid materials, stayed visible, and
had bounds matching their body. Clothing was present in the foreground views
checked on both peers. The final additional camera-angle comparison was interrupted
by Escape, so every intermittent clothing case is not conclusively ruled out.

The repeated-hit workload averaged about 33-34 ms per frame in the candidate,
versus about 41 ms in the previous local run. These were two visible game windows
on one PC with native generated loadouts, not a controlled laptop FPS or Internet
latency measurement. Native painting/physics can still cause individual hitches.
Detached-object consistency and long-session UE4SS stability remain unverified.

**User playtest update — 18 October 2026:** The user confirms contact stutter is
gone, grabbing and wounds work, and dismemberment works on both peers well enough
for combat. Exact wound/sever matching is not confirmed. Internet play with their
brother had very little perceived lag. Native result UI is working, and manual
give-up was confirmed in the follow-up test. Impaling is difficult in the base
game too; no mod-specific impaling failure was established. Long sessions remain
untested. No numerical latency or frame-rate measurements were supplied.

The update loop uses one persistent game-thread timer. Earlier builds repeatedly
queued callbacks from an async thread; the observed UE4SS `Ref was not function`
failure stopped pose and input publishing while the game itself kept running.
The [native timer API](https://docs.ue4ss.com/dev/lua-api/global-functions/delayedactions.html)
also processes F5/F8/F9 intent without creating new cross-thread callbacks.

## Install

1. Close Half Sword and its multiplayer launcher.
2. Extract the ZIP, open `HalfSwordMP`, and run **Start Multiplayer.cmd**.
3. Use the new launcher on both PCs. It installs the current scripts into the
   selected demo and removes retired adapters. Keep the launcher running.

Python 3.10 or newer must be available as `python`. The launcher finds the
workspace game or the usual Steam installation, otherwise asks for the game
folder. Both game executables must match. The official pinned UE4SS loader is
checksum verified. Original EXE and PAK files are not modified.

The ZIP contains mod and launcher source only: no game files, saves, captured
state, saved addresses, development scripts or per-PC paths. Connection settings
remain local in `runtime/preferences.json`.

## Play

1. Select your fighter in the native main menu.
2. Press **F5**, choose **Host** on one PC; its address may stay blank.
3. On the other PC, enter the host's address and choose **Join**.
4. Choose **Enter multiplayer match** on both PCs. The mod uses native free
   combat and the native Duel start action with your selected loadout. It skips
   Tutorial at runtime, restores that setting on disconnect, and does not save
   a changed tutorial preference. No preliminary single-player fight is needed.
5. Close the panel with F5 and use the game's normal controls.

Both players have a **Restart round** button beside **Enter multiplayer match**.
The host coordinates each shared reset and retains the selected fighter/equipment.
The button is disabled during normal respawn; if that takes over six seconds it
becomes available for a retry. A client request remains pending until the host
advances the round. Both players must use protocol 18.

Confirmed unconsciousness, sustained native incapacity and death trigger a
three-second restart coordinated by the host. A completed native surrender
meter uses a 0.25-second countdown. Both PCs use the native arena reset; loading
and restoring equipment add startup time. Native result cards and KO slow motion
are suppressed while multiplayer owns `Arena_Cutting_Map`.

Hold **G** to give up using the game's native surrender action. Its give-up UI
is preserved; surrender ends the shared round. The single-player death screen's
return-to-menu action stays suppressed. Hold G until the native meter fills;
release it to cancel. This is available while healthy or downed. To collect an enemy's dropped weapon, approach
it and use E/Q with a free hand.

Each reset runs the native Duel card handler again with the selected fighter
rank/team restored. KO is latched until the coordinator resets both PCs, so native
regeneration cannot erase it between snapshots. A KO preserves native player
control identity. Death/result widgets are hidden during construction and removed
while multiplayer owns the arena. Native input is restored after possession and
when closing the panel. Returning to the main menu clears the old match.

## What is synchronized

- Controls run natively on each owner's PC. Opponents follow measured poses;
  this mode does not send an unused duplicate input stream.
- Root position, physical body-bone poses, weapon/query-helper transforms, worn
  equipment classes, mesh/material appearance, owner identity,
  vitals and native injury events target 30 updates/s. Actual capture rate is
  reported in `runtime/performance.txt`; slow game frames can reduce it.
- Modular weapons use the demo's saved weapon construction: grip, blade, guard,
  pommel, submodules, sizes, material groups, colors and coat of arms. The native
  setup function builds the weapon and hand constraints. Preset weapons retain
  their normal class setup.
- Each owner retains native control and physics for its own fighter. The remote
  fighter's native physics-asset bodies and native weapon meshes follow owner
  snapshots through Unreal's Physics Control component. Its independent AI,
  movement tick and weapon tick are stopped. Short interpolation smooths the
  received pose. Local native combat still queries the native collision meshes.
- Contacts react through local native physics. Native cut/stab query helpers
  follow their owner's captured transforms and enabled state.
- A player's native contact against the opponent produces a bounded injury
  event. The receiving owner calls native `Get Damage` once with the damage,
  cutting/stabbing flags, source component and a rebased hit point/query box.
  Its independent temporary query box cannot apply physical collision forces.
  Replayed impulse, velocity and shockwave are zero to avoid duplicate impacts.
  Current-life IDs and event sequences reject old or repeated injury. Native
  local contacts on the owner are invulnerable to avoid applying injury twice.
  There is no second scalar health subtraction. Native injury processing owns
  the resulting wounds and ongoing pain/bleeding on that instance. Confirmed
  native sever events also prepare native vertex paint and replay the sever on
  the owner. Detached limbs do not share one networked physics simulation.
- Stand-in weapons are explicitly visible to both players. Invisible collision
  helpers stay hidden. The native opponent finishes its two-second startup before
  replicated equipment is applied. Shared two-handed actors are preserved when
  clearing an absent off-hand slot. Dropped weapons are not repeatedly recreated
  in combat.
- Inactive arena opponents are excluded from weapon queries, so hidden bodies
  cannot absorb attacks. Current stand-in weapons, including fists, remain active.

Only portable cosmetic scalar/vector appearance parameters are copied onto native
materials, preserving their own wound/blood render-target textures. The worn
armor list is used rather than the pawn's spawn defaults. Short incomplete state
reads are tolerated instead of repeatedly destroying and rebuilding the opponent.

Network latency still delays remote poses. There is no rollback or latency compensation.
Exact detached-limb, constraint/impalement and wound-texture matching is not
established. Dropped weapons are visible on both peers and cross-peer pickup
ownership is implemented. Fully shared dropped-item physics is not implemented.
Physics interactions and Internet latency require
further testing across hardware and network conditions; the user has confirmed
successful Internet play with very little lag in their session. Use the same
mod version on both PCs.
Earlier forced-fall diagnostics showed native loss/countdown text. Subsequent
player testing confirms the native result UI is now working.

## Direct IP

On one home network, join the host's LAN IPv4 address. For Internet play, forward
**UDP 7777**, or your selected gameplay port, to the host PC and join its public
IPv4 address. The mod does not change router or firewall settings. CGNAT can
prevent ordinary forwarding. Direct-IP play has no password; the first peer
occupies the guest slot. Session nonces and sequence numbers reject stale state.

## Optional updates

**Check for update**, **Apply update & restart**, and optional **Automatic updates
from the host** use the chosen host's companion. There is no public update service.
The host serves updates over **TCP 7778**, or gameplay port plus one. That TCP port
also needs forwarding if Internet updates are wanted.

Downloads are staged. Applying waits until the game exits, replaces source files,
reinstalls the mod and restarts the game. Automatic updates check once per minute
and apply a staged package after exit. Manual ZIP installation also works.

## Development summary

The project began as an attempt to let a guest control an existing opponent on
the host. Connection tests worked before the experience did: the guest could
have the wrong camera, poor control, missing equipment or a visible opponent
that lacked usable combat collision.

The design moved toward a native player on each PC and a native opponent for
the remote person. Received body and weapon poses drive that opponent's native
collision components. Native injury events are sent to the victim's owner, and
the host coordinates shared round boundaries. This is mixed authority rather
than one PC simulating the entire fight.

| Problem encountered | Resulting change |
| --- | --- |
| Installer failed on older Python versions | Chunked SHA-256 hashing replaced reliance on `hashlib.file_digest`. |
| Room-code friction and duplicate hosts | Direct-IP joining, local preferences, launcher locking and occupied-port reporting. |
| Wrong cameras, fighters or missing weapons | Local native player ownership and reconstruction of the other player's selected native equipment. |
| Position disagreement, launches and phantom impacts | Common arena coordinates, pose-driven native stand-ins and injury replay without duplicate forces. |
| Mouse/keyboard freezing after resets | One persistent game-thread timer, retiring latent UI callbacks and restoring input after possession. |
| Single-player cards and menu exits interrupting matches | Multiplayer entry through the native Duel/start handler and host-coordinated shared resets. |
| Healthy falls restarting, or incapacitated players remaining in a round | Sustained KO/incapacity confirmation and remembering critical leg damage during a fall. |
| Wounds and severing missing on the owning player | Native damage replay and asynchronous native vertex-paint preparation before severing. |
| Clothes rebuilding or changing colour | Preserving garments through weapon changes and applying all three saved dye groups. |
| Clothes disappearing after movement or damage | Worn garments share native body bounds; further intermittent cases remain under investigation. |
| Contact-related hitches | Budgeted injury queues, reduced duplicate effects and less repeated file/discovery work. |
| A sever-hook host crash | Removing an unsafe by-reference UObject-array read and checking component lifetimes before delayed native calls. |

Player feedback and two-PC testing exposed failures that a successful connection
or an automated test could not establish. Local scripted checks also needed
correction: a swing with no registered native contact did not prove combat, and
a sever flag did not prove a visible cut. Later validation used repeatable
native injury workloads, actual garment bounds and foreground game-window
inspection. The final additional camera-angle check was interrupted and is not
recorded as a pass.

Full development notes and a player-facing mod write-up are available in the
separate documentation bundle. The latest changes improve identified causes;
they do not establish perfect physics synchronization, complete clothing-bug
coverage or a guaranteed client frame rate.

## Diagnostics and development

F8 writes discovery; F9 toggles a visual pose preview. Leave preview off in play.
Logs are in the game's `HalfSwordUE5/Binaries/Win64/ue4ss/UE4SS.log`. Local
`runtime/status.json`, `session-check.txt`, pose/input/damage records and performance
files help diagnose the bridge. Development helpers and runtime files are excluded
from the player ZIP. Legacy loopback helpers target retired architectures.

Run `python -m unittest discover -s tests -v` and `python tools/package.py` from the
project folder. Optional Lua tests use Lupa in `runtime/lua-check`. Native combat
validation needs rendered game instances; headless transport checks do not prove
that the demo's injury/vertex-paint pipeline works.

To disable, close the game and set `HalfSwordMP : 0` in its UE4SS `Mods/mods.txt`.

Dependencies: [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS),
[pinned official loader](https://github.com/UE4SS-RE/RE-UE4SS/releases/download/experimental/UE4SS_v3.0.1-1181-g83330635.zip).
Each player supplies their own matching demo installation.
