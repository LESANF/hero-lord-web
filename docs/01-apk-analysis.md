# 01 · What is in the APK

Target: `hero-lord-remaster-20261014-r24.apk` (431,641,426 bytes)
SHA-256: `668e20f47de3698d378c4a03b21bf0a08668641cb2452c6cadba230e97dbe33c`

The by-extension counts and sizes below come from `python3 -I tools/inventory.py <apk>`;
the per-file facts (magic bytes, `.import` metadata, `project.binary` keys, PCK header)
from the one-liners quoted next to them.
Manifest facts come from REA `inspect_android_package` (JADX headless 0.7.1),
evidence id `ev_9c75a85080d89eadf46896ab5cd14154bc3c6aaaed77e0334103dbb079e4ffa2`.

## Observed

### Manifest

| field | value |
|---|---|
| package | `local.herolore.remaster` |
| versionName / versionCode | `0.2-play` / 25 |
| minSdk / targetSdk | 24 / 35 |
| permissions | INTERNET, ACCESS_NETWORK_STATE, VIBRATE |
| main activity | `com.godot.game.GodotApp` (stock Godot Android wrapper) |
| `org.godotengine.editor.version` | `4.6.stable` |
| `org.godotengine.library.version` | `4.6.0.stable` |
| `org.godotengine.rendering.method` | `gl_compatibility` |
| Godot plugins | `GodotPlayGameServices` (com.jacobibanez, Play Games Services v2) |

### Native code

```
lib/{arm64-v8a,armeabi-v7a,x86_64}/libgodot_android.so   ~70 MB each
lib/*/libc++_shared.so
classes.dex                                               6.3 MB
```

`libgodot_android.so` carries the string `Godot Engine v4.6.stable.official`.
There is no other `.so` and no `*.gdextension` file anywhere in `assets/`.
The DEX is the Godot Android wrapper plus the Play Games plugin and AndroidX.

**Conclusion: no game code is native. The whole game is GDScript and data.**

### The Godot project (loose under `assets/`)

| count | size | what |
|---:|---:|---|
| 47,146 | 63 MB | `assets/modern_pixel/**/*.dot` — PNG files with a `.dot` extension (byte 0 is `\x89PNG`), loaded at runtime by script, bypassing the importer |
| 6,862 | 16 MB | `.godot/imported/*.ctex` — imported textures. Every texture's `.import` stub carries `metadata={"vram_texture": false}` (lossless, no per-GPU `.s3tc`/`.etc2` variants; `find . -name '*.etc2.ctex'` is empty) |
| 6,975 | | `*.import` remap stubs pointing at `.godot/imported/` |
| 536 | 19 MB | `.json` game data: `assets/game/maps` (210), `assets/world/events` (210), `assets/world/maps` (81), catalogs |
| 108 | 80 MB | `.sample` imported WAV audio |
| 74 | 0.9 MB | `*.gdc` compiled GDScript (header `GDSC`, version 101, zstd body) |
| 75 | | `*.remap` stubs: `scripts/*.gd.remap → *.gdc`, and `scenes/main.tscn.remap → .godot/exported/…/main.scn` (the only link from `main_scene` to the exported scene) |
| 39 | 16 MB | `.cut` cutscene frames |
| 8 | | `.gdshader` |
| 5 | | `.fontdata` (Galmuri 9/11, Noto Sans KR, Geist Mono; OFL per `fonts/fonts.json`) |
| 2 | 25 MB | `.ogv` title-screen loops |
| 1 | | `.godot/exported/.../main.scn` — the **only** scene; UI is built in code |
| 1 | | `project.binary` — compiled project settings (binary `ECFG`, stores only non-default values) |
| 1 | 0.4 MB | `.godot/uid_cache.bin` — resolves `uid://` references such as the autoload |
| 1 | | `.godot/global_script_class_cache.cfg` — `class_name` registry (Play Games addon classes) |
| 2 | 1.2 MB | raw `.png`: `assets/icon/boot-splash.png`, `icon-192.png`, referenced directly by project settings |
| 1 | 6 MB | `assets.sparsepck` — PCK v3 header, flags `REL_FILEBASE|SPARSE_BUNDLE`: an index over the loose files, not a data container |

Android-only leftovers: `_cl_` (command line: `--xr-mode off --fullscreen --edge_to_edge --background_color #f7f3ea`), `dexopt/baseline.prof*`.

### Project settings (strings in `project.binary`)

- `application/run/main_scene = res://scenes/main.tscn`
- `application/config/features = ["4.6", "GL Compatibility"]`
- `application/config/custom_user_dir_name = HeroLordRemaster`
- `autoload/GodotPlayGameServices = uid://mvjiglywn6qe`
- `rendering/renderer/rendering_method = gl_compatibility` (also `.mobile`)
- `rendering/textures/vram_compression/import_etc2_astc` set
- `input_devices/pointing/emulate_mouse_from_touch = false` (stored; engine default is true). The engine default for the other direction, `emulate_touch_from_mouse`, is also false, so a mouse-only browser produces no `InputEventScreenTouch` unless the web build turns it on.
- `debug/file_logging/enable_file_logging = true` (on web that writes into IDBFS)
- `gui/theme/default_font_multichannel_signed_distance_field` set

`assets/world/catalog.json` identifies the source material as
`"edition": "KTF PD002678 v01.00.08", "localOnly": true`: a remaster of a
KTF-era Korean feature-phone title, assets re-packed as `.dot` PNGs.

## Inferred

- Because the renderer is already **GL Compatibility** and every texture is
  lossless, the exported resources work under the Godot **Web** export template
  (WebGL 2) with no re-import and no editor project reconstruction. Project
  *settings* still need web-specific overrides (touch emulation, the Android-only
  Play Games autoload); that is an `override.cfg`/autoload shim, not a rebuild.
- `.gdc` binary tokens are version-locked: the web runtime must be exactly
  **Godot 4.6.x**.
- The PCK we build only needs the files that the sparse index lists; the
  Android-only leftovers are dropped.

## Unknown (to resolve in later PRs)

1. How the game behaves when the `GodotPlayGameServices` Android singleton is
   absent (web). Needs the decompiled `godot_play_game_services.gd` and
   `cloud_saves*.gd`.
2. Which UI paths are touch-only. Desktop browsers deliver mouse events and,
   per the settings above, nothing converts them to touches. Needs the
   decompiled input handlers.
3. Memory: the project files total ~230 MB (the APK is 431 MB only because of three 70 MB copies of the engine). Godot web loads the main pack fully into memory.
