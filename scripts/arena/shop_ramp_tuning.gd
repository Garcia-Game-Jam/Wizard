class_name ShopRampTuning
extends Resource

## Tuning knobs for ShopEntranceStairsBuilder's invisible ramp collision —
## split out into their own Resource instead of five more @export vars on
## ShopStructure (which already sat close to gdlint's per-file line cap),
## the same reason ShopDisplayEntry exists as its own file. The Inspector
## emits a Resource's own "changed" signal after committing any edit to an
## @export property here — ShopStructure listens for that and calls
## _rebuild(), so dragging a slider below updates the shop live, same as
## every other @export on ShopStructure itself. Editing a property from
## code instead doesn't emit that signal on its own — call emit_changed()
## afterward if a script needs the same live-update behavior.

## How far sideways the ramp drifts from dead center (at the landing) to
## its own side (at the ground) — matches
## ShopEntranceStairsBuilder.FLIGHT_LATERAL_SPREAD by default, keeping the
## ramp aligned with the visible flight's own straight-line drift; move it
## away from that to make the ramp visibly diverge from the steps under it.
@export_range(0.0, 5.0, 0.05, "suffix:m") var tilt: float = 2.0
## The ramp's own slope — keep under CharacterBody3D.floor_max_angle's
## default 45° so it still reads as walkable floor.
@export_range(5.0, 44.0, 0.5, "suffix:°") var angle_deg: float = 38.0
## How wide the ramp collision is.
@export_range(0.2, 6.0, 0.05, "suffix:m") var width: float = 2.3
## How far the ramp's low end is buried past true ground instead of
## leaving an exposed edge for a walking player to catch on.
@export_range(0.0, 6.0, 0.05, "suffix:m") var ground_overshoot: float = 2.0
## Rotation around the ramp's own length axis (its slope/tilt direction),
## on top of the "as level as possible" orientation _build_ramp starts
## from — see that function's own doc comment for why a ramp that's both
## sloped and tilted sideways needs this to sit flush against its mirrored
## twin instead of visibly twisting relative to it.
@export_range(-45.0, 45.0, 0.5, "suffix:°") var roll_deg: float = 0.0
## Shortens the ramp from its landing-side (top) end, pulling that end back
## down along the ramp's own slope by this much instead of letting it
## reach all the way to the landing's outer edge — the mirror image of
## ground_overshoot, which instead extends the low end further than it
## needs to go.
@export_range(0.0, 4.0, 0.05, "suffix:m") var top_trim: float = 0.0
## Slices off whatever part of the ramp pokes up above the shop's own
## floor height, with a flat cut parallel to that floor (the top of the
## raised foundation, not the slope) — a rotated, width-widened box's top
## corners can rise above the landing height even when its centerline sits
## exactly at it (see _build_ramp's own doc comment). 0 cuts flush with the
## floor exactly; raise it to trim further down instead.
@export_range(0.0, 3.0, 0.05, "suffix:m") var top_cut_margin: float = 0.0
