# Ext-Fork (Luanti 5.17.0)

Erweiterungen fuer den Luanti-Client: natives Settings-Panel, Cheat-Optionen,
Freecam, X-Ray-Keybind und ein UI-Utils-Panel.

## Bedienung

| Aktion | Wie |
|---|---|
| Ext-Panel (6 Zeilen) | `.menu` im Chat |
| UI-Utils-Panel | Taste **L** (umbindbar über `keymap_toggle_uiutils`) |
| Freecam | Taste **F4** (`keymap_toggle_freecam`) |
| X-Ray | Taste **F7** (`keymap_toggle_xray`) |
| Item im Inventar droppen | die Drop-Taste (umbindbar über `keymap_drop`) |
| Komplettes Inventar/Truhe droppen | `.dropinv` / `.dropchest` oder die Buttons über offenen Inventaren |

Die drei neuen Tasten (F4, F7, L) stehen im Rebind-Dialog der
Einstellungen (`keymap_toggle_freecam`, `keymap_toggle_xray`,
`keymap_toggle_uiutils`).

## Ext-Panel (`.menu`)

- **XRay** — Blöcke aus `xray.nodes` werden nicht gerendert (Standard:
  `default:stone,mcl_core:stone,mcl_deepslate:deepslate`). Subpage
  „Nodelist" zum Editieren der Liste.
- **Fullbright** — die Szene wird gleichmäßig hell (Himmel, Entitäten,
  Wield und Flüssigkeiten eingeschlossen).
- **No-Night** — Tag/Nacht wird auf volles Tageslicht gepinnt.
- **ChestDupe** — Dupe-Cheat; Subpage mit Mode (Auto / Crosshair only),
  Hold-Mode, Auto-Collect und Log.
- **FreeCam** — die Kamera fliegt frei, der Körper bleibt stehen
  (kein Server-Rollback). Die eigene Figur bleibt an der echten Position
  markiert.
- **Drop buttons** — blendet die „Drop all"-Buttons über offenen
  Inventaren ein/aus.

## UI-Utils-Panel (Taste L)

Wie in einer erweiterten Client-Implementierung: *Close without Packet* (Formspec ohne Close-Paket
schließen), *Desync*, *Send Packets*, *Delay*, *Leave & Send*,
*Disconnect*, *Save* sowie ein Chat-Eingabefeld. Das Panel erscheint,
während ein Inventar-/Formspec-Fenster offen ist.

## CSM-Autonomie

Der Server darf die Clientmods des Clients nicht abschalten: die
`csm_restriction_flags` werden vom Client ignoriert (`CSM_RF_NONE`).
Ohne das blockiert ein Server `.menu` und alle Cheat-CSMs.

## Clientmods

- `ext_menu` — die `.menu`-Brücke plus die Chatbefehle `.xray`,
  `.fullbright`, `.nonight`, `.chestdupe`, `.freecam`.
- `chest_dupe` — der Dupe-Cheat (clientseitig).

Die Clientmods werden über `clientmods/mods.conf` geladen; außerdem muss
`enable_client_modding = true` in `minetest.conf` gesetzt sein.

## Verifikation (headless, ohne Fenster)

```bash
bash tools/verify-extpanel.sh --run    # Ext-Panel: Layout, Klicks, Hit-Tests
bash tools/verify-ui-panel.sh          # UI-Utils-Panel, Ext-Bruecke, Drop-API
bash tools/verify-chestdupe.sh         # Dupe end-to-end (serverseitig gemessen)
```

Alle Prüfungen laufen mit `SDL_VIDEODRIVER=offscreen` und geleertem `DISPLAY`.
