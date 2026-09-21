# 🚀 CosmoScope — Interactive AR/VR Mobile Solar System Exploration & Simulation Engine

> **Project Title:** CosmoScope  
> **Engine & Renderer:** Godot Engine 4.7 (Mobile Vulkan Renderer)  
> **Language:** GDScript  
> **Target Platform:** Android (Mobile AR / Mobile DIY Stereoscopic VR) & Windows Desktop Preview

---

## 📌 Project Overview

**CosmoScope** is an immersive mobile AR/VR educational application designed to accurately convey the **true scale, relative sizes, spatial layout, orbital mechanics, internal compositions, and astronomical phenomena** of the Solar System.

Traditional 2D textbook diagrams suffer from severe spatial distortion:
- If planet sizes are drawn to scale, distances become invisible.
- If distances are drawn to scale, planets become smaller than single pixels.

CosmoScope resolves this by providing **dual visualization paradigms**:
1. **📱 AR Mode (Relative Size):** Tabletop projection allowing users to walk around planets, scale them, and inspect details in real physical space.
2. **👓 VR Mode (Scale & Spatial Depth):** Center-of-system stereoscopic immersion, giving the user a 1:1 sense of distance, planetary motion, and depth.
3. **6 Specialized Interactive Simulation Modules:** Guided Tour, Property Comparison, Physics/Gravity Simulator, Eclipse Simulator, Astronomy Quiz, and Custom Orbit Sandbox.

---

## 🚀 Key Features & 8 Interactive Modes

### 1. 👓 DIY Stereoscopic Mobile VR Mode (`VRRig.gd` & `VRScene.tscn`)
- **Headset-Free VR:** Designed for mobile phones in Google Cardboard holders (no OpenXR required).
- **Stereoscopic Dual Viewports:** Two `SubViewport` containers with cameras separated by $0.064\text{m}$ ($64\text{mm}$ Interpupillary Distance) for authentic 3D binocular parallax.
- **Lens Distortion Shader:** Renders through [lens_distortion.gdshader](file:///c:/Users/Nikshith%20Gurram/arvr_project/CosmoScope/shaders/lens_distortion.gdshader) to counter physical optical lens distortion:
  $$r' = r(1 + k_1 r^2 + k_2 r^4)$$
- **Gyroscope Head Tracking:** Real-time sensor integration via `Input.get_gyroscope()` with mouse look desktop fallback.
- **Gaze-and-Dwell Selection:** Look at a planet for $1.5\text{s}$ to trigger a smooth camera focus flight state machine.

### 2. 🌍 Mobile Augmented Reality Mode (`ARController.gd` & `ARScene.tscn`)
- **ARCore Integration:** Queries `XRServer` for mobile AR plane detection.
- **Touch Gestures:** Multi-touch pinch-to-scale ($0.1\times$ to $3.0\times$), drag-to-rotate, tap-to-select.
- **Desktop Grid Overlay:** Synthesizes a 3D grid table plane ([ARGridOverlay.gd](file:///c:/Users/Nikshith%20Gurram/arvr_project/CosmoScope/scripts/ARGridOverlay.gd)) for PC testing without AR hardware.

### 3. 🎙️ Guided Voiceover & Interactive Tour (`TourController.gd` & `TourScene.tscn`)
- **Cinematic Camera Path:** Cubic `Tween` camera trajectories smoothly flying between planets.
- **Rich Educational Cards:** On-screen telemetry, fast facts, axial tilt highlights, and audio narration controls.

### 4. 🔬 Side-by-Side Property & Cutaway Compare (`CompareController.gd` & `CompareScene.tscn`)
- **Relative Scale Visualizer:** Normalizes the visual scale of any two selected bodies (e.g. Earth vs Jupiter) side-by-side.
- **Internal Cross-Section Shader:** Uses [cutaway.gdshader](file:///c:/Users/Nikshith%20Gurram/arvr_project/CosmoScope/shaders/cutaway.gdshader) to slice 3D models and reveal core, mantle, and crust layers with pulsating core boundary highlights.
- **Telemetry Data Matrix:** Compares mass, diameter, gravity ($g$), rotation period, surface temp, and atmosphere composition.

### 5. ⚖️ Gravity & Weight Jump Simulator (`GravitySimulatorController.gd` & `GravitySimulatorScene.tscn`)
- **Newtonian Kinematic Physics:** Calculates relative surface gravity $g_{body} = g_{earth} \times \text{gravity\_g}$.
- **Kinematic Calculations:**
  - Apparent weight: $W_{body} = m_{earth} \times g_{body}$
  - Jump takeoff velocity: $v_0 = \sqrt{2 \cdot g_{earth} \cdot h_{earth}}$
  - Jump height: $h_{body} = \frac{v_0^2}{2 \cdot g_{body}}$
  - Hang time: $t_{hang} = \frac{2 \cdot v_0}{g_{body}}$
- **Live 3D Parabolic Trajectory:** Renders dynamic trajectory arcs using Godot's `ImmediateMesh`.

### 6. 🌒 Eclipse Simulator (`EclipseSimulatorController.gd` & `EclipseSimulatorScene.tscn`)
- **Solar & Lunar Eclipses:** 3D positioning of Sun, Earth, and Moon.
- **Frustum Shadow Geometry:** Visualizes **Umbra** (total shadow cone) and **Penumbra** (partial shadow cone).
- **Orbital Inclination Toggle:** Toggles $0^\circ$ alignment vs normal $5.14^\circ$ Moon tilt to explain eclipse frequency.

### 7. 🧠 Interactive Astronomy Quiz (`QuizController.gd` & `QuizScene.tscn`)
- **Gamified Learning System:** Multiple-choice quiz testing planetary extremes, tilt angles, mass concentration, and moons.
- **Live 3D Planet Preview:** Swaps `material_override` on a 3D viewport mesh synchronously per question.

### 8. 🛠️ Orbit Sandbox & Custom System Creator (`SandboxController.gd` & `SandboxScene.tscn`)
- **Custom System Builder:** Spawn custom planets, adjust mass, radius, distance, speed, and eccentricity.

---

## 🛠️ Project Architecture & File Layout

```
CosmoScope/
├── scenes/                         # Godot 3D & UI Scene Files (.tscn)
│   ├── Main.tscn                   # Entry point & scene transition manager
│   ├── Menu.tscn                   # Main navigation menu
│   ├── VRScene.tscn                # Stereoscopic DIY VR scene
│   ├── ARScene.tscn                # ARCore & Desktop Grid scene
│   ├── TourScene.tscn              # Guided Tour scene
│   ├── CompareScene.tscn           # Property Compare & Cutaway scene
│   ├── GravitySimulatorScene.tscn # Gravity & Jump Physics scene
│   ├── EclipseSimulatorScene.tscn # Eclipse Shadow Cone scene
│   ├── QuizScene.tscn              # Astronomy Quiz scene
│   └── SandboxScene.tscn           # Custom Orbit Sandbox scene
├── scripts/                        # Core Logic (GDScript)
│   ├── Main.gd                     # Scene switcher with CanvasLayer fade
│   ├── SolarSystem.gd              # Dynamic 3D planet spawner & orbit engine
│   ├── VRRig.gd                    # Dual viewport VR, gyro tracking, gaze dwell
│   ├── ARController.gd             # AR plane tracking & touch gesture handler
│   ├── ARGridOverlay.gd            # Desktop 3D table plane fallback overlay
│   ├── CompareController.gd        # Scale comparison & cutaway material logic
│   ├── GravitySimulatorController.gd # Newtonian kinematic physics simulator
│   ├── EclipseSimulatorController.gd # Umbra/Penumbra frustum geometry manager
│   ├── QuizController.gd           # Quiz state machine & material swapper
│   ├── TourController.gd           # Cinematic camera Tweens & narrative HUD
│   └── SandboxController.gd        # Interactive solar system sandbox
├── shaders/                        # Custom GLSL Shaders
│   ├── planet.gdshader             # Textures, axial tilt, specular reflections
│   ├── sun.gdshader                # Simplex noise solar surface turbulence
│   ├── corona.gdshader             # Atmospheric solar corona glow
│   ├── atmosphere.gdshader         # Fresnel limb scattering (Rayleigh)
│   ├── ring.gdshader               # Concentric planetary ring system
│   ├── cutaway.gdshader            # Core / mantle / crust cross-section
│   └── lens_distortion.gdshader    # Barrel lens distortion for VR
├── data/
│   └── planets.gd                  # Centralized astronomical data table
└── project.godot                   # Engine settings & mobile renderer config
```

---

## 📐 Key Shaders & Mathematical Formulations

| Shader / System | Formula / Implementation |
| :--- | :--- |
| **Parametric Orbits** | $\vec{P}_{orbit}(t) = [r \cos(\omega t), 0, r \sin(\omega t)]^T$ |
| **Kinematic Jump Arc** | $y(t) = v_0 t - \frac{1}{2} g_{body} t^2$ |
| **Rayleigh Atmosphere** | $\text{Rim} = (1.0 - \max(0.0, \vec{N} \cdot \vec{V}))^{\text{power}} \cdot \text{AtmoColor}$ |
| **Cutaway Cross-Section** | Radial layer slicing: $d = \|\vec{P}_{local}\| \rightarrow \text{Core}(d < r_c), \text{Mantle}(r_c \le d < r_m), \text{Crust}(d \ge r_m)$ |
| **VR Barrel Distortion** | $r' = r (1 + k_1 r^2 + k_2 r^4)$ |

---

## 🚀 How to Run & Build

### **System Requirements:**
- **Godot Engine:** Version 4.7+ (Mobile Vulkan Renderer).
- **Language:** GDScript.
- **Target OS:** Android (ARCore / Cardboard) & Windows Desktop (Preview Mode).

### **Running in Godot Editor:**
1. Open Godot 4.7 and select `Import`, pointing to `project.godot`.
2. Press `F5` to run the project.
3. Use mouse drag and scroll wheel on desktop to preview AR and VR modes.

### **Headless Integrity Check:**
```bash
godot --headless --path . --quit
```

---

## 🎓 Viva Examination & Project Defense
For complete viva examination preparation, detailed architectural breakdown, code flow, and high-yield Q&A defense answers, refer to the included guide:
📄 **[viva_prep_guide.md](file:///C:/Users/Nikshith%20Gurram/.gemini/antigravity-ide/brain/67f41140-a61a-4972-a94c-849bbc9ceaa6/viva_prep_guide.md)**
