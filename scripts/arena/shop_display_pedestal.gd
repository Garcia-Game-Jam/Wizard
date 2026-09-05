@tool
class_name ShopDisplayPedestal
extends Node3D

## The interactive half of a shop display — the stone-and-gold pedestal
## mesh itself is built by ShopStructure._add_shop_display; this node is
## what it attaches on top, carrying:
##  - a small floating icon under _icon_root (a sphere tinted the spell's own
##    SpellDefinition.color for a SpellDisplayEntry, a gem tinted a
##    deterministic hash color for an ArtifactDisplayEntry, or a green "+"
##    cross for a HealDisplayEntry — this project procedurally generates its
##    own geometry rather than shipping icon art, so this follows suit
##    instead of introducing a first PNG-icon pipeline), gently bobbing (and,
##    except for the heal cross — see _process — spinning) in _process.
##    @tool so it still shows/animates while editing the level, matching the
##    rest of ShopStructure's live-preview habit;
##  - an Area3D that notices the LOCAL player walking up and registers
##    itself as Player's "nearby interactable" (see player.gd's
##    _try_interact/_resolve_interaction_prompt) so the HUD shows
##    "Buy <name> [F]" and pressing F calls interact() — inert in the
##    editor since nothing simulates physics there, only live at runtime;
##  - interact(), which branches on the entry's concrete type: teaches the
##    spell (CharacterSpellLoadout.learn_spell) for a SpellDisplayEntry,
##    grants the item (PlayerInventory.add) for an ArtifactDisplayEntry, or
##    restores HP (Character.heal) for a HealDisplayEntry. There's no economy
##    yet (see ShopEncounter's own doc comment on that) so this is a free
##    grant, not a real purchase — a display is a permanent fixture, not
##    consumed/depleted by buying.

const CollisionLayersScript := preload("res://scripts/collision_layers.gd")
const InputPromptScript := preload("res://scripts/ui/input_prompt.gd")

const ICON_HEIGHT := 0.55
const ICON_RADIUS := 0.16
const BOB_AMPLITUDE := 0.06
const BOB_SPEED := 1.6
const SPIN_SPEED := 1.1
const INTERACT_RANGE := 1.8
const ITEM_GEM_SATURATION := 0.75
const ITEM_GEM_VALUE := 0.95
const HEAL_ICON_COLOR := Color(0.25, 0.85, 0.35)
const HEAL_CROSS_ARM_LENGTH := 0.22
const HEAL_CROSS_ARM_THICKNESS := 0.07

var entry: ShopDisplayEntry
var display_name: String = ""
var icon_color: Color = Color(0.8, 0.8, 0.8)

var _icon_root: Node3D
var _time: float = 0.0


## Must be called before this node enters the tree (i.e. before add_child) —
## _ready() below reads `entry` to build the icon and resolve the display name.
func configure(display_entry: ShopDisplayEntry) -> void:
	entry = display_entry


func _ready() -> void:
	_resolve_display_info()
	_build_icon()
	_build_interaction_area()


func _process(delta: float) -> void:
	_time += delta
	if _icon_root == null:
		return
	_icon_root.position.y = ICON_HEIGHT + sin(_time * BOB_SPEED) * BOB_AMPLITUDE
	## The heal cross is built standing in a fixed vertical plane (see
	## _build_cross_icon) so it reads as a "+" rather than a gem — spinning it
	## around Y would swing that plane edge-on to the viewer, so it only
	## floats, never spins, unlike the other two display kinds' gem icon.
	if not (entry is HealDisplayEntry):
		_icon_root.rotation.y += delta * SPIN_SPEED


func _resolve_display_info() -> void:
	if entry is SpellDisplayEntry:
		var spell_entry := entry as SpellDisplayEntry
		var def := _resolve_spell_definition(spell_entry.spell_id)
		if def != null:
			display_name = def.display_name
			icon_color = def.color
		else:
			## Registry not found (e.g. previewed outside an arena scene) —
			## fall back to something visible rather than leaving the id
			## unreadable.
			display_name = spell_entry.spell_id.capitalize()
			icon_color = Color(0.55, 0.28, 0.72)
	elif entry is HealDisplayEntry:
		display_name = "Healing"
		icon_color = HEAL_ICON_COLOR
	elif entry is ArtifactDisplayEntry:
		var artifact_entry := entry as ArtifactDisplayEntry
		display_name = artifact_entry.item_id.capitalize()
		icon_color = _gem_color(artifact_entry.item_id)


func _resolve_spell_definition(spell_id: String) -> SpellDefinition:
	var registry := get_tree().get_first_node_in_group("spell_registry")
	if registry == null:
		return null
	return registry.get_spell(spell_id)


## Deterministic per-item-id hue so the same item id always gets the same
## gem color, without needing a hand-authored color per item.
static func _gem_color(seed_id: String) -> Color:
	var hashed := absf(fmod(sin(float(seed_id.hash()) * 0.0001) * 43758.5453, 1.0))
	return Color.from_hsv(hashed, ITEM_GEM_SATURATION, ITEM_GEM_VALUE)


func _build_icon() -> void:
	_icon_root = Node3D.new()
	_icon_root.name = "Icon"
	_icon_root.position = Vector3(0.0, ICON_HEIGHT, 0.0)
	add_child(_icon_root)

	if entry is HealDisplayEntry:
		_build_cross_icon()
	else:
		_build_gem_icon()

	var glow := OmniLight3D.new()
	glow.name = "IconGlow"
	glow.light_color = icon_color
	glow.light_energy = 0.5
	glow.omni_range = 2.0
	_icon_root.add_child(glow)


func _build_gem_icon() -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Gem"
	var mesh := SphereMesh.new()
	mesh.radius = ICON_RADIUS
	mesh.height = ICON_RADIUS * 2.0
	mesh.radial_segments = 12
	mesh.rings = 8
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _icon_material()
	_icon_root.add_child(mesh_instance)


## Two crossed bars instead of the gem sphere other displays use — rotated
## about Z (not Y, like a yaw spin would) so one arm stands vertical and the
## other stays horizontal, reading as an upright "+" rather than a flat
## cross lying in the horizontal plane.
func _build_cross_icon() -> void:
	for rotation_z in [0.0, PI * 0.5]:
		var bar := MeshInstance3D.new()
		bar.name = "CrossBar%d" % int(rad_to_deg(rotation_z))
		var mesh := BoxMesh.new()
		mesh.size = Vector3(
			HEAL_CROSS_ARM_LENGTH * 2.0, HEAL_CROSS_ARM_THICKNESS, HEAL_CROSS_ARM_THICKNESS
		)
		bar.mesh = mesh
		bar.material_override = _icon_material()
		bar.rotation.z = rotation_z
		_icon_root.add_child(bar)


func _icon_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = icon_color
	mat.emission_enabled = true
	mat.emission = icon_color
	mat.emission_energy_multiplier = 0.6
	mat.metallic = 0.2
	mat.roughness = 0.3
	return mat


func _build_interaction_area() -> void:
	var area := Area3D.new()
	area.name = "InteractionArea"
	area.collision_layer = 0
	area.collision_mask = CollisionLayersScript.CHARACTER
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var sphere := SphereShape3D.new()
	sphere.radius = INTERACT_RANGE
	shape.shape = sphere
	area.add_child(shape)
	add_child(area)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if not (body is Player) or not (body as Player).is_local_owner():
		return
	## Direct property, not a method call — Player exposes this as a plain
	## public var rather than register/unregister methods since player.gd
	## is already at gdlint's public-method cap.
	(body as Player).nearby_interactable = self


func _on_body_exited(body: Node3D) -> void:
	if not (body is Player):
		return
	var player := body as Player
	if player.nearby_interactable == self:
		player.nearby_interactable = null


func get_prompt_text() -> String:
	return InputPromptScript.with_action("interact", "Buy %s" % display_name)


func interact(player: Node) -> void:
	if entry is SpellDisplayEntry:
		var loadout: Node = (
			player.get_spell_loadout() if player.has_method("get_spell_loadout") else null
		)
		if loadout != null and loadout.has_method("learn_spell"):
			loadout.learn_spell((entry as SpellDisplayEntry).spell_id, "shop")
	elif entry is HealDisplayEntry:
		if player.has_method("heal"):
			player.heal((entry as HealDisplayEntry).heal_amount)
	elif entry is ArtifactDisplayEntry:
		var inventory := player.get_node_or_null("%PlayerInventory")
		if inventory != null and inventory.has_method("add"):
			inventory.add((entry as ArtifactDisplayEntry).item_id)
