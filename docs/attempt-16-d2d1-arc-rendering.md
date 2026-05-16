# Attempt 16 — UI shapes render correctly (Direct2D arc fix)

Lightroom's UI had a class of rendering defects: toolbar buttons drawn as
pointed hexagons instead of pills, the rating circle as a jagged polygon,
icon badges as diamonds instead of dots, rounded panels with cut corners.
"Buttons and things don't fully display properly." One root cause, one
fix.

## Investigation

Ruled out, by experiment, everything that *wasn't* the cause:

- patched vs stock `winex11.so` — toolbar renders pixel-identical
- GPU acceleration on vs off — identical
- scaling — confirmed 1:1 (desktop = window = monitor, DPI 96)
- DPI 96 → 192 + 2× virtual desktop — no change

Then traced Lightroom's Direct2D calls (`WINEDEBUG=+d2d`). Lightroom draws
its entire UI through Wine's `d2d1`:

- `FillGeometry` ×1620, `FillEllipse` ×310, `FillRectangle` ×308
- **`ID2D1GeometrySink::AddArc` ×214**

Every `AddArc` logged `fixme:d2d:d2d_geometry_sink_AddArc ... stub!`.

## Root cause

`d2d_geometry_sink_AddArc` in `dlls/d2d1/geometry.c` was an unimplemented
stub:

```c
FIXME("iface %p, arc %p stub!\n", iface, arc);
...
d2d_figure_add_vertex(&geometry->u.path.figures[...], arc->point);
```

It discarded the arc entirely and inserted a single straight line to the
arc's endpoint. Lightroom builds every rounded UI shape — pill buttons,
the rating circle, rounded panels, circular badges — as a path geometry
whose curves are arc segments. With `AddArc` a no-op, each arc collapsed
to one straight chord:

- a pill button's two semicircular ends → two points → a pointed hexagon
- a circle outline (4 arc quadrants) → 4 chords → a diamond/polygon
- a rounded-rectangle corner → a diagonal cut

## The fix

`installers/wine-patches/wine-d2d1-addarc.patch` implements `AddArc`. It
converts the D2D arc (SVG-style endpoint parameterisation) to centre form
(SVG 1.1 implementation notes F.6.5), splits the sweep into ≤30° pieces,
approximates each with a quadratic Bézier (control point on the angle
bisector at `1/cos(half-angle)`), and feeds them through the sink's
existing `AddQuadraticBeziers` path. Handles ellipse radii, x-axis
rotation, both sweep directions and the large-arc flag; degenerate cases
(zero radius, coincident endpoints) fall back to a straight line.

## Result — verified

| Element | Before | After |
|---------|--------|-------|
| "Copy Edit Settings" / gear buttons | pointed hexagons | proper rounded rectangles |
| Flag-filter button group | pointed end | proper rounded pill end |
| Rating circle | ~12-sided polygon | round |
| "Assisted Culling" badge | diamond | round dot |
| Search box / rounded panels | cut corners | proper rounded corners |

The patched `d2d1.dll` ships in `wine-patches/`; `run-lightroom.sh`
installs it idempotently (stock kept as `d2d1.dll.orig`). It carries all
three d2d1 fixes — the attempt-4 `ColorManagement` effect, the attempt-6
non-delay imports, and this `AddArc` implementation.

This is a genuine upstream Wine bug — `AddArc` is a stub in current Wine.
The patch is self-contained and a candidate for submission to WineHQ.
