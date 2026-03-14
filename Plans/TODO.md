- add multiple feed points to the smith chart, currtently we only do the first one

## Elevation & Azimuth Radiation Pattern Display

Implementation plan based on cocoaNEC source code (ElevationView.m, AzimuthView.m, PatternView.m).

### Architecture

**Base View (PatternView equivalent)**:
- NSView-based polar plot renderer with parametric scaling
- Shared grid system (concentric circles + radial lines)
- Supports multiple patterns with color-coded overlays
- Scaling factor `rho` controls dB representation (default 1.059998 = 0.89 per 2dB, adjustable)

**Elevation View** (`ElecElevationPatternView`):
- Plots gain vs elevation angle: `angle = (90 - theta) * π/180`
  - Theta from simulation (zenith angle, 0° = top)
  - Elevation = 90° - theta (90° = horizon, 0° = zenith)
- Caption shows: frequency + azimuth angle

**Azimuth View** (`ElevationAzimuthPatternView`):
- Plots gain vs azimuth angle: `angle = phi * π/180`
  - Phi directly from simulation
- Caption shows: frequency + elevation angle

### Rendering Algorithm

**Polar Coordinate Transform**:
```
angle = (elevation ? (90 - theta) : phi) * π/180
r = ρ^(gain[i] - maxGain)
point = (r*cos(angle), r*sin(angle))
```

**Grid System**:
- **Concentric circles**: Represent dB levels
  - Major circles: -2, -4, -6, -8, -10, -13, -16, -20, -30, -40 dB (configurable array)
  - Minor circles: Between majors (variable density)
  - Radius for dB level N: `radius = rho^N`
- **Radial lines**: 10° steps (36 total), every 3rd is major line
  - Major: full length to `ρ^(-40 dB)`
  - Minor: shorter length to `ρ^(-30 dB)`

**Color Scheme**:
- Up to 16 pattern colors (user-configurable color wells)
- Reference pattern: gray, dashed line
- Previous pattern: gray, dashed line
- Current patterns: colored, solid line
- Grid: dark blue (screen), lighter blue (print)

**Gain Extraction**:
- Support polarizations: Total, Vertical, Horizontal, Left-Circular, Right-Circular, V+H, L+R
- Extract from `PatternElement` array (gain in dB for each theta/phi pair)

### Implementation Tasks

1. **Data Structure** (`SimulationResult`)
   - Already have: `RadiationPoint(theta, phi, gain)`
   - Organize by frequency/pattern element

2. **Pattern View Base Class** (SwiftUI Canvas or custom NSView)
   - Polar grid generation: circles + radial lines
   - Scaling & transformation logic
   - Font attributes for labels
   - Draw method: pattern → polar plot

3. **Elevation View**
   - Subclass/variant of pattern view
   - Apply elevation transformation
   - Show azimuth in caption

4. **Azimuth View**
   - Subclass/variant of pattern view
   - Direct phi mapping
   - Show elevation in caption

5. **Controls & Options**
   - Gain scale selector (rho: 1.05, 1.059998, 1.08 → changes circle density)
   - Polarization picker (Total, Vertical, Horizontal, Circular, Combination)
   - Color well picker for pattern colors
   - Reference/Previous pattern overlay toggle

6. **InfoPanel** (similar to Smith ChartImpl)
   - Frequency
   - Max gain in dB
   - Directivity (if available from context)
   - Current pattern metrics

7. **ResultsView Integration**
   - Add `.elevation` and `.azimuth` tabs
   - Feed `fullPatternPoints` (from `computeFullPattern`) to both views
   - Share legend/caption area

### Key Math Formula

Matplotlib-style polar to Cartesian:
- `x = r * cos(angle)`
- `y = r * sin(angle)`

where `angle` in radians, `r = ρ^(gain_dB - maxGain_dB)`

### Styling Notes

- No background fill (transparent)
- Grid circles: 0.45pt major, 0.2pt minor
- Pattern lines: 1.2pt
- Reference/previous patterns: dashed (4pt on, 2pt off)
- Text: 8-9pt system fonts, black on white or light print background
- Screen vs. print scaling differs (affects grid visibility)

### cocoaNEC Source Reference
- PatternView.m: Base class, grid creation, polar transform, color management
- ElevationView.m: Elevation angle calculation, caption format
- AzimuthView.m: Azimuth angle direct use, caption format
- PatternElement.h/m: Data structure for pattern point (theta, phi, dB values for each polarization)


