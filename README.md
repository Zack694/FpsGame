# SCP: Lockdown

A first-person SCP survival horror shooter for **Android** (built with **Godot 4.7**, targets **Android 16 / API 36**, arm64).

A containment breach has hit Site-19. Survive **SCP-173**, **SCP-096**, **SCP-049** and its **SCP-049-2** instances, find the four **Alpha Warhead code fragments** hidden around the facility, and enter the 4-digit code at the Control Room terminal to nuke everything.

## Gameplay
- **SCP-173**: only moves when you are not looking at it (or while you blink). Touch = neck snap.
- **SCP-096**: harmless until you see its face, then it screams and charges through doors.
- **SCP-049**: slow hunter, kills on touch, flinches from bullets, revives dead 049-2.
- **SCP-049-2**: killable with the revolver (headshots deal ~2.6x damage).
- Revolver (6 rounds), ammo boxes, flashlight batteries and medkits are scattered around the map.
- Blink meter, stamina, flashlight battery, health, map overlay, 3 difficulties.
- 30-second detonation sequence after entering the code; the Control Room seals itself.

## Controls
| Touch | Keyboard / Mouse | Gamepad |
|---|---|---|
| Left side: floating joystick (push to the edge to sprint) | WASD | Left stick |
| Right side: drag to look (the FIRE button also drags) | Mouse | Right stick |
| FIRE / RELOAD / USE / LIGHT / BLINK / CROUCH / RUN | LMB / R / E / F / Space / Ctrl / Shift | RB / X / A / Y / LB / B / L3 |
| MAP, II (pause) | M, Esc | Back, Start |

Settings: look sensitivity, invert Y, joystick/button size and opacity, left-handed layout, aim assist, quality preset, render scale, FOV, brightness, flashlight shadows, glow, FPS limit and FPS counter, audio volumes, head bob.

## Building
CI (`.github/workflows/android.yml`) downloads Godot 4.7.2 and the Android export templates, imports the project and exports a signed release APK. The APK is uploaded as the **SCP-Lockdown-apk** workflow artifact.

Signing: set the repository secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD` and `ANDROID_KEYSTORE_ALIAS` to use your own key. Without them, CI signs with the bundled `android/build.keystore` (fine for sideloading, not for the Play Store).

To build locally: open the folder in Godot 4.7, install the Android export templates, then choose Project > Export > Android.

### Asset pipeline (`tools/`)
- `mapgen.py`: generates and validates the facility layout into `scripts/map_data.gd`.
- `glbtool.py`: post-processes assimp-converted SCP:CB `.b3d`/`.x` models. It embeds textures, splits animation clips and fixes the root transform. A patched assimp B3D importer was used so that every animation key chunk is merged.
- `tools/dev/`: headless test scenes (gameplay checks and screenshots). These are excluded from export.

## Credits / License
- SCP-173, SCP-096, SCP-049 and SCP-049-2 models, props, textures, doors, sound effects and music: **SCP - Containment Breach** by Regalis (Undertow Games) and contributors, [github.com/Regalis11/scpcb](https://github.com/Regalis11/scpcb), licensed under **CC BY-SA 3.0**. The original author list is in `assets/SCPCB_Credits.txt`.
- The SCP Foundation universe ([scp-wiki.wikidot.com](https://scp-wiki.wikidot.com)) is licensed under CC BY-SA 3.0.
- Engine: [Godot Engine](https://godotengine.org) (MIT).

This game includes CC BY-SA 3.0 material, so its assets are distributed under **CC BY-SA 3.0**.
