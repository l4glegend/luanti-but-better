# Luanti but better by L4gLegend

A customized build of the Luanti 5.17.0 voxel game engine, with a native
client-side feature panel and additional client utilities.

## Features

- **Extension panel:** open it with `.menu` in chat to control the added
  client-side features.
- **Visual options:** X-Ray with an editable node list, Fullbright, and a
  daylight mode.
- **Freecam:** move the camera independently while your character stays at its
  original position.
- **Inventory helpers:** optional drop-all controls and a server-dependent
  ChestDupe client module.
- **UI utilities:** an additional panel with utilities for open formspecs.
- **Configurable keys:** the added Freecam, X-Ray, and UI-utilities shortcuts
  can be changed in Luanti's settings.

These are client-side modifications. Feature availability can vary between
servers, and some servers may prohibit their use; follow the rules of the
server you join.

## Downloads

Ready-to-run builds are available from the
[latest GitHub release](https://github.com/l4glegend/luanti-but-better/releases/latest):

- **Windows 64-bit:** [Luanti.but.better.by.L4gLegend.exe](https://github.com/l4glegend/luanti-but-better/releases/latest/download/Luanti.but.better.by.L4gLegend.exe) — a self-extracting launcher containing the modified engine.
- **Linux x86_64:** [Luanti.but.better.by.L4gLegend-x86_64.AppImage](https://github.com/l4glegend/luanti-but-better/releases/latest/download/Luanti.but.better.by.L4gLegend-x86_64.AppImage) — a portable application image.

The Windows launcher extracts the engine for the current Windows user. Neither
package includes games, worlds, or personal profile data. Install games
separately through Luanti's in-app content browser.

## Source and licensing

This repository contains the source used for these builds. The engine is based
on the [upstream Luanti project](https://github.com/luanti-org/luanti). See
[LICENSE.txt](LICENSE.txt), [COPYING.LESSER](COPYING.LESSER), and the notices
in individual source files for licensing and attribution.

For instructions on building the source, see the platform-specific guides in
[doc/compiling](doc/compiling/).
