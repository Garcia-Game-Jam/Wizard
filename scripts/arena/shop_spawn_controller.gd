class_name ShopSpawnController
extends Node3D

## Plays a shop encounter's "grand opening": instances shop.tscn as a child
## and rises the whole thing out of the ground, from fully buried up to true
## ground — local/world y=0, where ShopStructure's own foundation and
## entrance stairs already assume they rest (see shop_structure.gd's
## top-of-file doc comment) — over RISE_DURATION seconds, eased out so it
## settles rather than snapping to a stop. Once seated, every door bay's
## ShopDoor (named "DoorController", however many door_bay_indices the
## instance has) opens itself automatically — nobody has to press F for the
## shop's own opening.
##
## Before rising, shop_displays is re-rolled by ShopRandomizer, sized to the
## current lobby's player count (see _lobby_player_count()) rather than
## whatever placeholder pedestals shop.tscn was last saved with — assigned
## before add_child(_shop) so ShopStructure's own _ready() rebuild is the
## only rebuild, not a second one triggered by the shop_displays setter.
##
## Not netfox-rollback-tracked, unlike ArenaCover's cube restage — every
## peer starts this from the same rpc_show_telegraph call (see
## arena_scene.gd's _show_shop()), and nothing gameplay-critical depends on
## the shop's exact position mid-rise, so a plain _process-driven tween is
## enough here, matching SpawnTelegraph's gate-opening (also not
## rollback-tracked) rather than ArenaCover's elapsed-tick pattern.

const ShopScene := preload("res://scenes/arenas/shop.tscn")
const ShopRandomizerScript := preload("res://scripts/arena/shop_randomizer.gd")

const RISE_DURATION := 6.0
## Clears the tallest point (the roof apex/finial) with room to spare, so
## nothing pokes above the arena floor while the shop is still "buried".
const HEIGHT_MARGIN := 1.5

var _shop: Node3D
var _start_y := 0.0
var _elapsed := 0.0
var _rising := false
var _doors_opened := false


func _ready() -> void:
	_shop = ShopScene.instantiate()
	_shop.set(
		"shop_displays", ShopRandomizerScript.generate_displays(_lobby_player_count(), _all_spell_ids())
	)
	add_child(_shop)
	var total_height := (
		float(_shop.get("foundation_riser"))
		+ float(_shop.get("wall_height"))
		+ float(_shop.get("arch_rise"))
		+ float(_shop.get("roof_height"))
		+ HEIGHT_MARGIN
	)
	_start_y = -total_height
	position.y = _start_y
	_rising = true


## Solo play still counts as 1 — NetworkManager installs an
## OfflineMultiplayerPeer for local-only sessions, so get_lobby_peer_ids()
## already returns a single id there, but maxi() guards the empty case
## (e.g. previewed before any session starts) rather than sizing the shop to
## zero displays.
func _lobby_player_count() -> int:
	return maxi(1, NetworkManager.get_lobby_peer_ids().size())


## Every currently known spell id, for ShopRandomizer's spell display pool —
## empty if previewed outside an arena scene (no "spell_registry" group node
## to ask), same fallback shop_display_pedestal.gd's own registry lookup uses.
func _all_spell_ids() -> Array[String]:
	var registry := get_tree().get_first_node_in_group("spell_registry")
	var ids: Array[String] = []
	if registry == null:
		return ids
	for definition in registry.get_all_spells():
		ids.append(definition.id)
	return ids


func _process(delta: float) -> void:
	if not _rising:
		return
	_elapsed += delta
	var t := clampf(_elapsed / RISE_DURATION, 0.0, 1.0)
	## Cubic ease-out — fast at first, settling gently into its final rest
	## rather than arriving at full speed.
	var eased := 1.0 - pow(1.0 - t, 3.0)
	position.y = lerpf(_start_y, 0.0, eased)
	if t >= 1.0:
		_rising = false
		_open_all_doors()


func _open_all_doors() -> void:
	if _doors_opened:
		return
	_doors_opened = true
	_open_doors_under(_shop)


func _open_doors_under(node: Node) -> void:
	for child in node.get_children():
		if child.name == "DoorController" and child.has_method("open"):
			child.call("open")
		_open_doors_under(child)
