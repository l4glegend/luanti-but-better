# ChestDupe (CSM) — Luanti fork client mod

Input-list dupe for Mineclonia servers (hidden `input` listring workaround,
mcl_chests upstream issue). Continuous dupe like the built-in ChestDupe cheat:
small chests and double chests (v3 scope: only vectors that also work
on foreign/origin servers) — each container class
is double-checked by a passive per-server probe and skipped when the server
cannot support it (foreign servers without the `dupe_workaround` server mod
fall back to small chests, which dupe everywhere).

## Install (supported client fork)

1. Copy the `chest_dupe/` folder into the fork's `clientmods/` directory.
2. Add `load_mod_chest_dupe = true` to `clientmods/mods.conf`
   (or enable it in the "Installed Client Mods" dialog).
3. Restart the client.

Conflict-safe: if the built-in Cheat-menu version (`F8 -> Misc -> ChestDupe`)
is loaded, the CSM keeps itself disabled to avoid double globalsteps.

## Controls

- `0` toggles the whole module on/off.
- Hold-Mode (default on): dupes run only while the **middle mouse button** is held.
- `.chesttake [x y z]` — pull everything from a synced container into your inventory.
- `.chestscan [radius]` — list node names around you (identify unknown container variants).
- `.chestlog` — print the last diagnostic lines (works without `io`).
- `.chestdbg` — one-shot state dump (wield cache, target, settings).

## Requirements / limits

- **Fork-only**: needs `InventoryAction`-apply and client input APIs
  (standard Luanti CSMs cannot send inventory moves).
- Small chests duplicate on **any** Mineclonia server; double chests work on
  unpatched servers (probe decides). Barrels/shulkers/furnaces were REMOVED in
  v3 scope: they needed the `dupe_workaround` server mod and thus never worked
  on foreign servers.
  (own server: install `dupe_workaround` + the 2-line mcl_chests patch).
- "Log" switch (F8 panel / settings) toggles chat cycle lines AND the in-memory
  diag buffer; `.chestlog` dumps it even when file io is unavailable.
- On clients that do expose `io`, the diag file lands in the Minetest user
  directory (`core.get_user_path()`) — no absolute build-machine paths are
  hardcoded.
