# Real AR (ARCore) setup — `godot_arcore` plugin

Goal: replace the camera "magic-window" with **true plane-tracking AR** (planets
pinned to a real surface as you walk around). This needs the
[`godot_arcore`](https://github.com/GodotVR/godot_arcore) **GDExtension** plugin
(Godot 4.2+), which must be **built natively on your machine** — it can't be
downloaded prebuilt. Claude writes the in-engine integration once the plugin loads.

> ⚠️ Honest risk: the plugin targets Godot 4.2+; building `godot-cpp` against
> **4.7** may hit API mismatches. Budget a few hours and expect some debugging.

## 0. Prerequisites (install once)

- **Android Studio** (already installed) → gives the Android SDK.
- **Android NDK + CMake**: Android Studio → *SDK Manager → SDK Tools* → tick
  **NDK (Side by side)** and **CMake** → Apply. Note the NDK path.
- **JDK 17** — use Android Studio's bundled JBR: `C:\Program Files\Android\Android Studio\jbr`
  (the plugin's Gradle wants 17, **not** 21).
- **Python 3 + SCons**: `pip install scons` (SCons builds `godot-cpp`).
- **Git**.
- Environment: set `ANDROID_HOME` to the SDK path and `ANDROID_NDK_ROOT` to the NDK path.

## 1. Build the plugin

```bash
git clone https://github.com/GodotVR/godot_arcore.git
cd godot_arcore
git submodule update --init            # pulls godot-cpp

cd godot-cpp
# If build errors mention missing/changed API, check out the godot-cpp branch
# matching your engine (e.g. `git checkout 4.7` or the closest 4.x) and retry.
scons platform=android target=template_debug -j4
scons platform=android target=template_release -j4
cd ..

gradlew.bat assemble                   # Windows (use ./gradlew on macOS/Linux)
```

The built addon lands in `plugin/demo/addons/`.

## 2. Verify with the plugin's own demo FIRST

Before touching CosmoScope, open **`plugin/demo`** in Godot 4.7 and export/deploy
it to your phone. If the demo shows the **camera + detected planes**, the plugin
works on 4.7. If the demo fails, the plugin isn't 4.7-ready and we stop here
(fall back to the camera overlay or Unity). **This is the go/no-go checkpoint.**

## 3. Add it to CosmoScope

1. Copy `plugin/demo/addons/<arcore-addon>` → this project's `addons/`.
2. **Project → Install Android Build Template** (needed for GDExtension native libs).
3. Android export preset → tick **Use Gradle Build** and confirm the CAMERA
   permission is on; set **Java SDK Path** to the Android Studio JBR (JDK 17).
4. Restart Godot so the `.gdextension` is picked up (no load errors in Output).

## 4. Then Claude writes the integration

Once the addon loads cleanly, tell Claude. Claude will replace `ARController.gd`
with a real AR scene: `XROrigin3D` + `XRCamera3D`, initialise the ARCore
`XRInterface`, subscribe to plane detection, show a reticle on detected planes,
and **tap-to-place** the (shared) `SolarSystem` anchored to the real world, plus
tap-a-planet for info. Content reuses `scripts/SolarSystem.gd`.

## Likely failure points (and fixes)

- **godot-cpp API mismatch vs 4.7** → check out the matching `godot-cpp` branch.
- **NDK version** SCons can't find → set `ANDROID_NDK_ROOT`, or install the NDK
  version the plugin expects.
- **Gradle fails** → wrong JDK; point it at JDK 17 (Android Studio JBR).
- **Export missing the plugin** → "Use Gradle Build" not enabled.
