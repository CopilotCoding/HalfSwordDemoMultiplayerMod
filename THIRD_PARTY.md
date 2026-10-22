# Third-party runtime

The mod ZIP contains no Steam DLL. At startup, the companion looks for a
compatible Valve-signed `steam_api64.dll` in local Steam libraries. If absent,
it automatically downloads the runtime from Valve's official Source SDK
repository and verifies the pinned SHA-256 before using it. SteamVR, browser
sign-in and manual downloads are not required. Local cache files never enter
mod packages or host updates.

Official fallback source:
https://github.com/ValveSoftware/source-sdk-2013/blob/0759e2e8e179d5352d81d0d4aaded72c1704b7a9/game/bin/x64/steam_api64.dll

Downloaded runtime SHA-256:
`a44e5537939ae4eebc69000589aa9b2437a667813a1657cc779198bae9b815a9`

The Steamworks runtime is proprietary Valve software, copyright Valve
Corporation, and is not covered by any license applied to this mod's source.
Downloading it does not change its license.
Steamworks terms: https://partner.steamgames.com/documentation/sdk_access_agreement/
Steamworks documentation: https://partner.steamgames.com/doc/sdk

Steam is a trademark of Valve Corporation. HalfSwordMP is an unofficial mod,
not endorsed by Valve or the Half Sword developers. Each player supplies the
Half Sword Demo and a signed-in Steam account for Steam mode.
