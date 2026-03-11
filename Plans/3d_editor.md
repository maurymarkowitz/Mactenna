# Plan: 3D Geometry Editor — Interactive Editing System

## TL;DR

Expand GeometryView from a read-only viewer into a full interactive geometry editor. Users will drag handles to modify wire/arc/helix endpoints, with axis-constrained movement by default, modifier keys for free rotation/axis-lock, live dimensioning overlays, and snap-to-point inference when dragging near key points on other geometry. The design follows a hybrid SketchUp-inference + Blender-axis-constraint model adapted to NEC antenna geometry semantics.

---

## Design Principles

1. **Shape-aware constraints**: Default drag behaviour respects the geometry type. A GW wire stays on its existing axis unless the user explicitly overrides. An arc stays on its plane. This is domain-specific — antenna wires usually need to grow/shrink along their axis, not rotate arbitrarily.
2. **Modifier keys for override**: Hold a key to switch from constrained to free movement, or to lock to a world axis.
3. **Inference snapping**: When a dragged endpoint approaches a key point on another object (vertex, midpoint), display a visual indicator on the target and snap to it.
4. **Live dimensioning**: Show length/angle/distance overlays during any drag.
5. **Undo everything**: Every drag-commit writes through the existing snapshot-based undo system.

---

## Interaction Model

### Default Behaviour (no modifiers)

| Card Type | Drag Handle | Default Constraint |
|-----------|-------------|-------------------|
| **GW** (Wire) | Start/End endpoint | **Axial** — move along wire's existing direction vector only (lengthen/shorten) |
| **GW** (Wire) | Midpoint | **Free translate** — move entire wire (both endpoints shift equally) |
| **GA** (Arc) | Start/End | **Radial** — change arc angle while preserving radius and plane |
| **GA** (Arc) | Midpoint | **Free translate** — move arc center |
| **GH** (Helix) | Start/End | **Axial** — change helix length along its axis |
| **SP/SM** (Patch) | Corner | **Planar** — move within patch plane |

### Modifier Keys

| Modifier | Effect | Visual Indicator |
|----------|--------|-----------------|
| **None** | Shape-specific constraint (axial for wires) | Dashed constraint line along wire axis |
| **⌥ Option** | Free 3D movement (unconstrained) | No constraint guide |
| **X / Y / Z key** (held during drag) | Lock to world axis | Bright axis-colored guide line |
| **⇧ Shift + X/Y/Z** | Lock to world plane (exclude axis) | Translucent axis-colored plane |
| **⌘ Cmd** (held during drag start) | Rotation mode — rotate wire around its midpoint | Circular rotation guide ring |
| **⇧ Shift** (alone, during drag) | Precision mode — 10× slower mouse-to-world mapping | "PRECISION" label in HUD |

### Keyboard Shortcuts (non-drag)

| Key | Action |
|-----|--------|
| **Escape** | Cancel in-progress drag; revert to pre-drag state ✅ |
| **Enter / Return** | Confirm drag (same as mouse-up) |
| **Delete / Backspace** | Delete selected card (with undo) |
| **Tab** | Cycle selection to next geometry card |
| **Shift+Tab** | Cycle selection to previous geometry card |

---

## Snap / Inference System (SketchUp-inspired)

### Snap Targets

When dragging a handle, continuously test proximity to:
1. **Endpoints** of other wires (start, end)
2. **Midpoints** of other wires
3. **Origin** (0, 0, 0)
4. **Axis intersections** with other geometry
5. **Colinear projections** — if the dragged endpoint is close to the line extending another wire

### Visual Feedback

- **Snap indicator on target**: A pulsing/glowing sphere appears on the snap target point of the *other* object. Color: **cyan** for vertex snap, **magenta** for midpoint snap, **orange** for axis projection.
- **Snap indicator on dragged handle**: Handle color brightens when snapped.
- **Guide lines**: Dashed lines connecting the snapped handle to the snap target when within threshold.
- **Tooltip/label**: Small text label at snap point ("Endpoint", "Midpoint", "Origin", "On X Axis").
- **Snap threshold**: Configurable in Preferences (default: visual radius × 3 in screen space, ~15px).

### Snap Confirmation

When the user releases the mouse while snapped, the coordinate is set to the *exact* snap target value (no floating-point drift). This ensures wire endpoints that should be coincident truly are.

---

## Live Dimensioning System

### During Drag

| Measurement | When Shown | Format |
|-------------|-----------|--------|
| **Wire length** | Always when dragging GW endpoint | "L: 0.500 m" near midpoint |
| **Delta from start** | Always during any drag | "Δ: 0.123 m" near cursor |
| **Coordinates** | Always | "(X: 1.23, Y: 0.00, Z: 4.56)" near dragged handle |
| **Angle** | When in rotation mode (⌘) | "θ: 45.0°" with arc indicator |
| **Distance to snap target** | When near a snap target | "→ 0.012 m" with connecting line |

### Implementation

- **SCNText nodes** positioned in screen-space (billboarded to camera) near the relevant handle.
- **Update every frame** during drag (via `SCNSceneRendererDelegate.renderer(_:updateAtTime:)`).
- **Units**: Match the deck's coordinate system (metres by default; future: wavelengths toggle).
- **Numeric input**: _not required_ — users may enter values via the table instead.

---

## Rendering Optimization: Batched Geometry

### Current Problem
Each NEC sub-segment is a separate `SCNNode` with its own `SCNCylinder`. For a model with thousands of segments, this creates thousands of draw calls.

### Solution: Single Batched Geometry Element
Build all wire cylinders into a single `SCNGeometry` with one vertex buffer and one `SCNGeometryElement`:

1. **Per-cylinder mesh generation**: For each segment, generate a unit cylinder's vertices (e.g., 12 sides × 2 caps = 26 vertices), transform them to the segment's position/orientation/radius, and append to a shared vertex array.
2. **Per-vertex color attribute**: Instead of per-material color, encode `card_\(index)` identity as a vertex color or custom shader attribute. Selected segments get yellow; others get gray.
3. **Single draw call**: One `SCNGeometrySource` (positions + normals + colors) and one `SCNGeometryElement` (triangle indices).
4. **Selection update**: On selection change, rebuild only the color buffer (not the full geometry). Or use a `SCNProgram` (custom shader) with a uniform for the selected card index.

### Hit Testing with Batched Geometry
- `SCNHitTestResult` returns the face index. Map face index back to segment index via `faceIndex / facesPerCylinder`.
- Alternatively, keep invisible per-segment hit-test proxy nodes (no geometry, just bounding boxes) at `categoryBitMask = 2`.

### Handles Remain Separate Nodes
Handles are interactive objects that need individual transforms during drag — keep them as separate `SCNNode`s.

---

## Architecture

### New Types

- **`DragState`** — enum tracking the current interaction:
  ```
  case idle
  case dragging(handle: HandleID, startWorldPos: SIMD3<Float>,
                currentWorldPos: SIMD3<Float>, constraint: DragConstraint,
                preEditSnapshot: String)
  ```
- **`HandleID`** — identifies which handle: `.start(cardIndex)`, `.mid(cardIndex)`, `.end(cardIndex)`
- **`DragConstraint`** — enum: `.axial(direction: SIMD3<Float>)`, `.worldAxis(Axis)`, `.worldPlane(Axis)`, `.free`, `.rotation(center: SIMD3<Float>, axis: SIMD3<Float>)`
- **`SnapResult`** — struct: `targetPoint: SIMD3<Float>`, `targetType: SnapType`, `targetCardIndex: Int?`, `distance: Float`
- **`DimensionOverlay`** — manages SCNText nodes for live measurements

### Modified Types

- **`GeometrySegment`** — added `radius` field (F7); wire thickness honours explicit radii without further scaling (slider only affects computed sizes) ✅
- **Handle size** — handles are now derived from the same base radius but are multiplied by 1.5 and clamped so they remain visible ✅
- **`GeometryView`** — add `@Binding` for deck mutation callbacks, or pass `NECDeck` directly
- **`Coordinator`** — becomes the primary interaction controller: mouse tracking, constraint computation, snap detection, dimension updates, undo commits

### Data Flow for Edits

```
User drags handle
  → Coordinator tracks mouse delta
  → Project delta onto active constraint (axis/plane/free)
  → Test for snaps against all other geometry endpoints
  → Update handle node position (visual feedback)
  → Update dimension overlay text
  → On mouse-up: compute new F1-F7 values for the card
  → Call NECDeck.setFloatField() for each changed field
  → Register undo with pre-drag snapshot
  → Trigger geometry rebuild (auto-recalc if enabled)
```

### Coordinate Conversion: 3D → Card Fields

| Card | Fields | From 3D |
|------|--------|---------|
| **GW** | F1-F3 = X1,Y1,Z1; F4-F6 = X2,Y2,Z2; F7 = radius | Handle positions map directly to F1-F6 |
| **GA** | F1 = arc radius; F2 = start angle; F3 = end angle; F4 = wire radius | Compute from 3D arc geometry |
| **GH** | F1 = spacing; F2 = length; F3-F6 = radii; F7 = wire radius | Compute from helix parameters |
| **SP** | F1-F3 = corner1; F4-F6 = corner2 | Handle positions map to corners |

GW is the simplest and most common — implement it first and use it as the template for others.

---

## Steps

### Phase A: Batched Rendering (prerequisite)
1. Create cylinder mesh generator: function that produces vertex/normal/index arrays for one cylinder given endpoints and radius
2. Build combined `SCNGeometry` from all segments in `makeScene()`
3. Add per-vertex color attribute; encode card index in vertex data
4. Implement face-index → card-index mapping for hit testing
5. Selection update: rebuild color buffer only (or use shader uniform)
6. Verify visual parity with current per-node rendering
7. **Files**: GeometryView.swift

- Initial camera framing now uses the original simple rule `max(geoRadius * 3, 5)`.
      More elaborate adjustments proved too aggressive; the earlier math was
      preferable despite its occasional closeness.

### Phase B: Drag Infrastructure (*depends on A*)
1. Replace `NSClickGestureRecognizer` with combined click + drag handling via `mouseDown`/`mouseDragged`/`mouseUp` overrides on `ZoomableSCNView`
2. Add `DragState` to Coordinator
3. On mouse-down on a handle node: begin drag, capture `preEditSnapshot`
4. On mouse-drag: project screen delta to 3D constraint, update handle position
5. On mouse-up: commit edit (compute new field values, call setters, register undo). Use the node’s final world position rather than requiring the mouse hit the geometry, so drags ending off‑object still apply ✅
6. Ensure deck edits trigger table view reload — subscribe to editGeneration or post notification
6. On Escape during drag: revert handle position, discard ✅
7. **Files**: GeometryView.swift

### Phase C: Constraint System (*depends on B*)
1. Implemented `DragConstraint` enum and projection math for axial, world axis/plane, free and rotation cases ✅
   - New `Axis` type and constraint computation live in `Coordinator`.
   - Projections applied in `mouseDragged(at:in:)` with proper 3‑D math.
2. Default constraint selection now honours card type + handle (GW start/end axial, mid free) ✅
3. Modifier keys are monitored via keyDown/keyUp and `NSEvent.modifierFlags`; Option gives free, Command enters rotation, Shift enables precision and plane locking ✅
4. Added worldMidpointFor helper; fixed ambiguous operator issue when computing midpoints ✅
4. Letter keys X/Y/Z lock to world axes (hold Shift for plane) via key event tracking ✅
5. **Guide visualization** partially done: axial/world-axis/plane guides now appear as lines/planes; rotation ring remains to implement ✏️
6. **Files**: GeometryView.swift (Coordinator expanded)

### Phase D: Snap / Inference System (*depends on B, parallel with C*)
1. Build spatial index of all geometry endpoints/midpoints at drag start ✅
2. During drag: test proximity of dragged position against targets; override position when within threshold ✅
3. Threshold currently fixed (≈0.02 m); future improvement: convert to screen-space 🛠
4. Show snap indicator spheres at target location (cyan deep for endpoint, magenta for midpoint) ✅
5. On mouse-up while snapped: use exact snap coordinate (already inherent) ✅
6. **Files**: GeometryView.swift

### Phase E: Live Dimensioning (*depends on B, parallel with C and D*)
1. Added live drag overlay in `GeometryView.Coordinator` using billboarded `SCNText` ✅
2. Overlay now updates continuously during drag events (`mouseDragged`) ✅
   • switched to screen-space SpriteKit overlay via `overlaySKScene` for
     guaranteed visibility; coordinates obtained via `projectPoint`.  scene
     children are now fully cleared on update to avoid artifacts.
3. Overlay shows delta distance, world coordinates, GW wire length and rotation angle; snap state label included ✅
4. Numeric input is not needed; users can edit values in the table instead. ✔️
5. Camera transform is persisted in a `@Binding` from ResultsView and tracked via `SCNSceneRendererDelegate`; eliminates snapping on rebuilds ✅
6. **Files**: GeometryView.swift, ResultsView.swift

### Phase F: GW Write-Back (*depends on B*)
1. When drag completes on a GW handle: read new start/end positions from handle nodes
2. Reverse the container transform to get world coordinates
3. Map to F1-F6 fields on the card
4. Call `deck.setFloatField(row:field:value:)` for each changed field
5. Register undo with pre-drag snapshot
6. Trigger `autoRecalcIfAppropriate()` if enabled; when writing multiple fields disable auto-recalc temporarily to avoid early run ✅
7. **Files**: GeometryView.swift, NECDeck.swift

### Phase G: Other Card Types (*depends on F*)
1. GA (Arc): map 3D arc manipulation to radius/angle fields
2. GH (Helix): map 3D helix manipulation to spacing/length/radius fields
3. SP/SM (Patches): map corner drags to coordinate fields
4. GC (Taper): handle radius variation along wire
5. Each card type gets its own constraint defaults and handle layout

---

## Relevant Files

- **Mactenna/Views/GeometryView.swift** — Primary file for all phases; currently ~400 lines, will grow significantly
- **Mactenna/Views/PatternView.swift** — updated `GeometrySegment` struct to include radius; samples adjusted
- **Mactenna/Models/NECDeck.swift** — `geometrySegments()` populates segments; `setFloatField()` for write-back; undo via `text()` snapshots
- **Mactenna/Models/NECCardType.swift** — Field label metadata per card type (used for dimension labels)
- **Mactenna/Bridge/MactennaOpenNEC.h** — C geometry query helpers; may need new helpers for patch geometry
- **Mactenna/Preferences.swift** — Add snap threshold, dimension display preferences

---

## Verification

1. **Batched rendering**: Load a deck with 1000+ segments; verify frame rate improvement vs current per-node approach; visually identical output
2. **Drag GW endpoint**: Drag end of a wire along its axis; confirm length updates in table; undo/redo works; camera doesn't reset
3. **Axis lock**: Hold X key during drag; confirm movement constrained to world X; guide line visible
4. **Snap**: Drag wire end near another wire's end; confirm cyan snap indicator appears on target; release snaps to exact coordinate; verify coordinates match in table
5. **Dimensioning**: During any drag, confirm length/delta/coordinates are visible and update in real-time; type a number and confirm it sets exact value
6. **Rotation**: Hold ⌘ and drag wire endpoint; confirm rotation around midpoint; angle displayed
7. **Undo**: Every completed drag is undoable with ⌘Z; cancelled drags (Escape) leave no undo entry
8. **Multi-type**: Test with GA (arc), GH (helix), SP (patch) cards — each should have appropriate constraints

---

## Decisions

- **Hybrid SketchUp + Blender model**: Default is shape-aware constraint (like parametric CAD), modifier keys switch to Blender-style world-axis locks. This serves antenna engineers who mostly adjust wire lengths (axial) but occasionally need precise axis-aligned placement.
- **Snap is always on**: Like SketchUp's inference engine, snap detection runs continuously during drag. No toggle needed. Snap threshold is screen-space based (camera-aware).
- **Batched rendering first**: Performance is a prerequisite for interactive editing — doing this before drag implementation avoids rework.
- **GW first**: Wire is the most common NEC geometry type (~90% of real decks). Other types follow the same pattern.
- **Undo via snapshots**: Reuse existing text-snapshot undo rather than per-field incremental undo. Simple and proven correct.
- **SceneKit, not RealityKit**: Current codebase uses SceneKit; switching frameworks mid-project adds risk with no clear benefit for this use case.

---

## Further Considerations

1. **Multi-selection editing**: Should the user be able to select and drag multiple wires at once (e.g., Shift+click to add to selection)? Recommendation: defer to a later phase — single-selection editing is the MVP.
2. **Grid display**: Should a ground-plane grid be shown for spatial reference? Recommendation: yes, add a toggleable XY grid at Z=0 (common ground plane for antennas). Low priority; can be added independently.
3. **Touch/trackpad gestures (iPad)**: The modifier-key model doesn't translate to iPad. For iOS, consider a toolbar with constraint-mode buttons (Axial / Free / X / Y / Z / Rotate) instead. Defer until Phase 6 (iOS).
