# hero-lord-web

Run **Hero Lord Remaster** (shipped as a Godot 4.6 Android APK) in the browser.

The APK contains no native game code: `libgodot_android.so` is the stock
Godot 4.6 runtime and the game itself is GDScript + assets packed loose under
`assets/`. So the port is not a rewrite. It is:

```
APK ──unzip──▶ exported Godot project ──pack──▶ game.pck ──+ official Godot 4.6 web template──▶ WASM in the browser
```

Everything here is reproducible from the APK and is done in the open, PR by PR.
See `docs/` for the reverse-engineering notes with evidence.

## Status

Work in progress. Follow the pull requests.

## Legal

Tooling and docs in this repository are MIT licensed. The game content inside
the APK (art, audio, scripts) belongs to the game's author and is not covered by
that license. The build pipeline consumes the APK as an input and does not
redistribute its content from this repository's git history.
