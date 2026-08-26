class_name PlayerNetInput
extends Node

## Peer-owned movement input. Property names in NET_FIELDS are the rewindable
## input contract — add a member here and it joins RollbackSynchronizer.

const NET_FIELDS: PackedStringArray = [
	"movement",
	"jump",
	"dash",
	"crouch",
	"look_yaw",
	"look_pitch",
	"charging",
	"charge_slot",
	"charge_factor",
	"wand_raised",
]

var movement: Vector2 = Vector2.ZERO
var jump: bool = false
var dash: bool = false
var crouch: bool = false
var look_yaw: float = 0.0
var look_pitch: float = 0.0
var charging: bool = false
var charge_slot: int = -1
var charge_factor: float = 0.0
var wand_raised: bool = false
## Frame-rate pulse so a dash press is not missed between 30 Hz ticks.
var _dash_queued: bool = false


static func net_input_paths() -> Array[String]:
	var paths: Array[String] = []
	for field in NET_FIELDS:
		paths.append("Input:%s" % field)
	return paths


func _ready() -> void:
	var nt := get_tree().root.get_node_or_null("NetworkTime") if is_inside_tree() else null
	if nt != null and nt.has_signal("before_tick_loop"):
		nt.before_tick_loop.connect(_on_before_tick_loop)


func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event.is_action_pressed("dash") and not event.is_echo():
		queue_dash()


func queue_dash() -> void:
	_dash_queued = true


func _on_before_tick_loop() -> void:
	if is_multiplayer_authority():
		_gather()


func _gather() -> void:
	movement = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	jump = Input.is_action_pressed("jump")
	dash = _dash_queued
	_dash_queued = false
	crouch = Input.is_action_pressed("crouch")
	charge_slot = -1
	charging = false
	charge_factor = 0.0
	for i in range(4):
		var action := "spell_slot_%d" % (i + 1)
		if Input.is_action_pressed(action):
			charging = true
			charge_slot = i
	var player := get_parent()
	if player == null:
		return
	if "net_wand_raised" in player:
		wand_raised = bool(player.get("net_wand_raised"))
	if player.has_method("is_wand_raised"):
		wand_raised = wand_raised or bool(player.call("is_wand_raised"))
	if "head" in player:
		var head: Variant = player.get("head")
		if head is Node3D:
			look_yaw = (head as Node3D).rotation.y
	if "camera_pivot" in player:
		var pivot: Variant = player.get("camera_pivot")
		if pivot is Node3D:
			look_pitch = (pivot as Node3D).rotation.x
	var wand := player.get_node_or_null("Head/CameraPivot/Wand")
	if wand != null and wand.has_method("get_cast_power_factor"):
		charge_factor = clampf(float(wand.call("get_cast_power_factor")), 0.0, 1.0)
	elif charging and "net_charge_factor" in player:
		charge_factor = float(player.get("net_charge_factor"))
