# CosmoScope — Implementation Strategy

A living plan for building the app. Update as decisions change.

## 1. Goal & scope

**One use case:** convey the true *scale and spatial layout* of the Solar System, which flat diagrams fail at.

- **AR mode** → *relative size* (planets placed on a real surface, tap for facts).
- **VR mode** → *scale & distance* (stand at the center, planets orbit around you).

**In scope (MVP):** Sun + 8 planets as textured spheres, simple circular orbits, a mode-select menu, one interaction per mode.
**Out of scope:** moons, asteroid belt, accurate physics, networking, multiplayer, sound design beyond ambient.

## 2. Key decisions

| Decision | Choice | Notes |
|----------|--------|-------|
| Engine | Godot 4.7 | Already set up |
| Renderer | Mobile (Vulkan) | Never Forward+; Compatibility is the only fallback |
| **Language** | **GDScript** | Confirmed. `[dotnet]` config removed from `project.godot` |
| VR method | DIY stereoscopic | Dual `Camera3D` + distortion shader + gyro; not OpenXR (no headset) |
| AR method | ARCore plugin | Minimal: plane detection + tap-to-place; marker-based AR as fallback |
| Target | **Android** | Confirmed. ARCore; builds from Windows |

## 3. Architecture

Planned project layout:

```
res://
  scenes/
    Main.tscn            # entry point → loads MenuScene
    Menu.tscn            # mode-select UI (AR / VR)
    VRScene.tscn         # stereoscopic solar system
    ARScene.tscn         # AR solar system
  scripts/
    SolarSystem.gd       # builds planets + drives orbits (shared by both modes)
    VRCamera.gd          # gyro head-tracking + gaze ray
    ARController.gd       # plane detection + tap-to-place
    GazeSelector.gd      # look-and-dwell selection
  shaders/
    lens_distortion.gdshader
  data/
    planets.gd / planets.json   # name, radius, distance, texture, facts
  assets/
    textures/            # planet textures (NASA, public domain)
```

**Shared core:** `SolarSystem.gd` builds the planet nodes and animates orbits from `planets` data. Both `VRScene` and `ARScene` instance it, so content stays defined once. AR and VR differ only in *camera + interaction*, not content.

## 4. Roadmap (phased, each phase is demoable)

### Phase 0 — Foundations
- [x] Confirm GDScript vs C# → **GDScript**
- [ ] Folder structure + `.gitattributes` for Godot binary/text
- [ ] `planets` data table (radius/distance scaled for readability, not true-to-life)
- [ ] `SolarSystem.gd`: spawn spheres + orbit animation (test in a plain 3D scene first)

### Phase 1 — VR mode (do first: lowest risk, no plugins)
- [ ] Dual-camera split-screen viewport setup
- [ ] `lens_distortion.gdshader` for the Cardboard lenses
- [ ] Gyro head-tracking (`VRCamera.gd`)
- [ ] Gaze + dwell selection showing a planet info card
- **Done when:** you can look around the solar system in a Cardboard holder and select a planet.

### Phase 2 — Mode-select menu
- [ ] `Menu.tscn` with AR / VR buttons, landscape layout
- [ ] Scene switching from `Main.tscn`

### Phase 3 — AR mode (highest risk)
- [ ] Integrate ARCore/ARKit plugin; verify it builds to device
- [ ] Plane detection + reticle
- [ ] Tap-to-place the solar system, scale/rotate gesture
- [ ] Tap-a-planet info card
- **Fallback:** marker-based AR if plane tracking is unreliable.

### Phase 4 — Polish & evaluation
- [ ] Info-card content for all planets
- [ ] Visual polish (skybox, sun glow), performance pass on device
- [ ] Small usability test (AR vs VR for size/distance estimation) for the report

## 5. Risks

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Mobile AR plugin won't build | Medium | Do VR first; marker-based AR fallback; keep AR scope tiny |
| Android export setup friction | Medium | Set up export templates + SDK early, test a "hello cube" on device before real work |
| Gyro drift / uncomfortable VR | Medium | Recenter option; cap framerate; keep motion minimal |
| Performance on mid-range phone | Low | Mobile renderer, low-poly spheres, texture size limits |

## 6. First actions

1. ~~Confirm language~~ → **GDScript**
2. ~~Confirm target device~~ → **Android**
3. Verify a trivial build runs on the physical device **before** building features.
