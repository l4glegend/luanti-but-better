<div align="center">
    <h1>Luanti but better by L4gLegend</h1>
    <p>A customized build of the Luanti voxel game engine.</p>
</div>

## Downloads

Get the ready-to-run packages from the [latest GitHub release](https://github.com/l4glegend/luanti-but-better/releases/latest):

- **Windows 64-bit:** [`Luanti.but.better.by.L4gLegend.exe`](https://github.com/l4glegend/luanti-but-better/releases/latest/download/Luanti.but.better.by.L4gLegend.exe) — self-extracting launcher containing the modified Luanti engine only. It does not include preinstalled games or personal profile data.
- **Linux x86_64:** [`Luanti.but.better.by.L4gLegend-x86_64.AppImage`](https://github.com/l4glegend/luanti-but-better/releases/latest/download/Luanti.but.better.by.L4gLegend-x86_64.AppImage) — portable application image.

The Windows launcher extracts the engine to the current Windows user's local application data. Games and worlds can be installed separately through Luanti.

## Source and licensing

This repository contains the source code used for these builds. Luanti is based on the [upstream Luanti project](https://github.com/luanti-org/luanti); see [LICENSE.txt](LICENSE.txt) and the relevant source-file notices for license and attribution details.

---

<div align="center">
    <img src="textures/base/pack/logo.png" width="32%">
    <h1>Luanti (formerly Minetest)</h1>
    <img src="https://github.com/luanti-org/luanti/workflows/build/badge.svg" alt="Build Status">
    <a href="https://hosted.weblate.org/engage/minetest/?utm_source=widget"><img src="https://hosted.weblate.org/widgets/minetest/-/svg-badge.svg" alt="Translation status"></a>
    <a href="https://www.gnu.org/licenses/old-licenses/lgpl-2.1.en.html"><img src="https://img.shields.io/badge/license-LGPLv2.1%2B-blue.svg" alt="License"></a>
</div>
<br>

Luanti is a free open-source voxel game engine with easy modding and game creation.

Copyright (C) 2010-2026 Perttu Ahola <celeron55@gmail.com>
and contributors (see source file comments and the version control log)

Table of Contents
------------------

1. [Further Documentation](#further-documentation)
2. [Paths](#paths)
3. [Configuration File](#configuration-file)
4. [Command-line Options](#command-line-options)
5. [Compiling](#compiling)
6. [Docker](#docker)
7. [Version Scheme](#version-scheme)


Further documentation
----------------------
- Website: https://www.luanti.org/
- Luanti Documentation: https://docs.luanti.org/
- Forum: https://forum.luanti.org/
- GitHub: https://github.com/luanti-org/luanti/
- [Developer documentation](doc/developing/)
- [doc/](doc/) directory of source distribution

Paths
-----
Locations:

* `bin`   - Compiled binaries
* `share` - Distributed read-only data
* `user`  - User-created modifiable data

Where each location is on each platform:

* Windows .zip / RUN_IN_PLACE source:
    * `bin`   = `bin`
    * `share` = `.`
    * `user`  = `.`
* Windows installed:
    * `bin`   = `C:\Program Files\Minetest\bin (Depends on the install location)`
    * `share` = `C:\Program Files\Minetest (Depends on the install location)`
    * `user`  = `%APPDATA%\Minetest` or `%MINETEST_USER_PATH%`
* Linux installed:
    * `bin`   = `/usr/bin`
    * `share` = `/usr/share/minetest`
    * `user`  = `~/.minetest` or `$MINETEST_USER_PATH`
* macOS:
    * `bin`   = `Contents/MacOS`
    * `share` = `Contents/Resources`
    * `user`  = `Contents/User` or `~/Library/Application Support/minetest` or `$MINETEST_USER_PATH`

Worlds can be found as separate folders in: `user/worlds/`

Configuration file
------------------
- Default location:
    `user/minetest.conf`
- This file is created by closing Luanti for the first time.
- A specific file can be specified on the command line:
    `--config <path-to-file>`
- A run-in-place build will look for the configuration file in
    `location_of_exe/../minetest.conf` and also `location_of_exe/../../minetest.conf`

Command-line options
--------------------
- Use `--help`

Compiling
---------

- [Compiling - common information](doc/compiling/README.md)
- [Compiling on GNU/Linux](doc/compiling/linux.md)
- [Compiling on Windows](doc/compiling/windows.md)
- [Compiling on MacOS](doc/compiling/macos.md)

Docker
------

- [Developing minetestserver with Docker](doc/developing/docker.md)
- [Running a server with Docker](doc/docker_server.md)

Version scheme
--------------
We use `major.minor.patch` since 5.0.0-dev. Prior to that we used `0.major.minor`.

- Major is incremented when the release contains breaking changes, all other
numbers are set to 0.
- Minor is incremented when the release contains new non-breaking features,
patch is set to 0.
- Patch is incremented when the release only contains bugfixes and very
minor/trivial features considered necessary.

Since 5.0.0-dev and 0.4.17-dev, the dev notation refers to the next release,
i.e.: 5.0.0-dev is the development version leading to 5.0.0.
Prior to that we used `previous_version-dev`.
