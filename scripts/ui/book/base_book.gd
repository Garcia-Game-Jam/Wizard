class_name BaseBook
extends Control

## Physical book overlay: closed cover opens to a two-page spread.
## Children supply ordered pre-baked page scenes via page_scenes().
## Optional cover_scene() replaces the default ClosedCover.

signal closed()
signal page_changed(page_index: int)
signal spread_changed(spread_index: int)

## First half (front peel to spine). Second half is shorter so the backside barely flashes.
const FLIP_OUT_SEC := 0.09
const FLIP_IN_SEC := 0.05
const COVER_OPEN_SEC := 0.28
## Matches default_cover.tscn / page leaf authored size.
const PAGE_SIZE := Vector2(320, 440)
const BlankLeafScene := preload("res://scenes/ui/book/page_leaf.tscn")
const PageTurnLeafScript := preload("res://scripts/ui/book/page_turn_leaf.gd")

@export var cover_scene: PackedScene

var _spread_index := 0
var _open := false
var _turning := false
var _opening_cover := false
var _turn_delta := 0
var _turn_tween: Tween
var _cover_tween: Tween
var _left_instance: Control
var _right_instance: Control
var _flip_leaf: Control

@onready var _cover_slot: Control = $Center/BookRoot/CoverSlot
@onready var _default_cover: Control = $Center/BookRoot/CoverSlot/ClosedCover
@onready var _open_book: Control = $Center/BookRoot/OpenBook
@onready var _left_frame: Control = $Center/BookRoot/OpenBook/BookBody/Inner/Spread/LeftPage
@onready var _right_frame: Control = $Center/BookRoot/OpenBook/BookBody/Inner/Spread/RightPage
@onready var _left_slot: Control = (
	$Center/BookRoot/OpenBook/BookBody/Inner/Spread/LeftPage/PageHost
)
@onready var _right_slot: Control = (
	$Center/BookRoot/OpenBook/BookBody/Inner/Spread/RightPage/PageHost
)
@onready var _flip_layer: Control = $Center/BookRoot/OpenBook/BookBody/Inner/FlipLayer
@onready var _prev_button: Button = $Center/BookRoot/OpenBook/PrevButton
@onready var _next_button: Button = $Center/BookRoot/OpenBook/NextButton


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_install_cover()
	_prev_button.pressed.connect(prev_page)
	_next_button.pressed.connect(next_page)
	_show_cover_state()
	set_process_input(false)


func is_open() -> bool:
	return _open


func open_book() -> void:
	_kill_tweens()
	_clear_flip_leaf()
	_open = true
	_turning = false
	_opening_cover = false
	_spread_index = clampi(_initial_spread_index(), 0, maxi(spread_count() - 1, 0))
	visible = true
	set_process_input(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _should_skip_cover_anim():
		_finish_cover_open()
		return
	_show_cover_state()
	_opening_cover = true
	_cover_tween = create_tween()
	_cover_tween.tween_interval(COVER_OPEN_SEC)
	_cover_tween.tween_callback(_finish_cover_open)


func close_book() -> void:
	if not _open:
		return
	_kill_tweens()
	_clear_flip_leaf()
	_open = false
	_turning = false
	_opening_cover = false
	_clear_spread()
	_show_cover_state()
	visible = false
	set_process_input(false)
	closed.emit()


## Override: ordered pre-baked page scenes for this book.
func page_scenes() -> Array[PackedScene]:
	return []


## Override or set export: custom closed cover, or null to keep the base default.
func get_cover_scene() -> PackedScene:
	return cover_scene


## Override: spread to show when the book opens.
func _initial_spread_index() -> int:
	return 0


func page_count() -> int:
	return page_scenes().size()


func spread_count() -> int:
	var pages := page_count()
	if pages <= 0:
		return 0
	return int(ceili(float(pages) / 2.0))


func prev_page() -> void:
	_shift_spread(-1)


func next_page() -> void:
	_shift_spread(1)


## Left-page index of the current spread (0-based content page).
func get_page_index() -> int:
	return _spread_index * 2


func get_spread_index() -> int:
	return _spread_index


func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel"):
		close_book()
		get_viewport().set_input_as_handled()
		return
	if _opening_cover:
		return
	if event.is_action_pressed("book_page_prev"):
		prev_page()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("book_page_next"):
		next_page()
		get_viewport().set_input_as_handled()


func _install_cover() -> void:
	var custom := get_cover_scene()
	if custom == null:
		return
	if _default_cover != null:
		_default_cover.queue_free()
		_default_cover = null
	var cover := custom.instantiate() as Control
	if cover == null:
		return
	cover.name = "ClosedCover"
	_cover_slot.add_child(cover)
	_default_cover = cover


func _finish_cover_open() -> void:
	_opening_cover = false
	_cover_slot.visible = false
	_open_book.visible = true
	_show_spread(_spread_index)


func _show_cover_state() -> void:
	_cover_slot.visible = true
	_open_book.visible = false


func _should_skip_cover_anim() -> bool:
	if COVER_OPEN_SEC <= 0.0:
		return true
	if OS.has_feature("headless"):
		return true
	if DisplayServer.get_name() == "headless":
		return true
	if OS.get_environment("FRIEND_SLOP_TEST") == "1":
		return true
	return false


func _shift_spread(delta: int) -> void:
	if _turning or _opening_cover:
		return
	if page_count() < 2:
		return
	var spreads := maxi(spread_count(), 1)
	var to_index := clampi(_spread_index + delta, 0, spreads - 1)
	if to_index == _spread_index:
		return
	_turn_delta = delta
	_spread_index = to_index
	_play_leaf_turn(delta)


## Q: left leaf peels around the spine and lands on the right.
## E: right leaf peels the other way and lands on the left (Soja-style curl).
func _play_leaf_turn(delta: int) -> void:
	_turning = true
	var source_page := _left_instance if delta < 0 else _right_instance
	var source_frame := _left_frame if delta < 0 else _right_frame
	if source_page == null or source_frame == null:
		_show_spread(_spread_index)
		_turning = false
		return

	_clear_flip_leaf()
	_flip_leaf = _make_flip_leaf(source_page, source_frame, delta)
	source_page.visible = false
	## Snapshot needs one rendered frame before the curl texture is valid.
	await get_tree().process_frame
	if not _turning or _flip_leaf == null or not is_instance_valid(_flip_leaf):
		return

	_turn_tween = create_tween()
	_turn_tween.set_parallel(false)
	_turn_tween.tween_property(
		_flip_leaf, "progress", 0.5, FLIP_OUT_SEC
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_turn_tween.tween_callback(_on_leaf_mid_flip)
	_turn_tween.tween_property(
		_flip_leaf, "progress", 1.0, FLIP_IN_SEC
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_turn_tween.tween_callback(_on_leaf_turn_finished)


func _on_leaf_mid_flip() -> void:
	## Reveal the destination spread under the turning leaf.
	_show_spread(_spread_index)
	if _flip_leaf == null or not is_instance_valid(_flip_leaf):
		return
	## Keep the landing page hidden until the curl settles over it.
	if _turn_delta < 0:
		if _right_instance != null:
			_right_instance.visible = false
	elif _left_instance != null:
		_left_instance.visible = false


func _on_leaf_turn_finished() -> void:
	_clear_flip_leaf()
	if _left_instance != null:
		_left_instance.visible = true
	if _right_instance != null:
		_right_instance.visible = true
	_turning = false


func _make_flip_leaf(page: Control, frame: Control, delta: int) -> Control:
	var leaf: Control = PageTurnLeafScript.new()
	leaf.name = "PageTurnLeaf"
	leaf.z_index = 20
	_flip_layer.add_child(leaf)
	leaf.visible = true
	## E (delta>0): right→left. Q (delta<0): left→right.
	var turn_dir := 1.0 if delta > 0 else -1.0
	if leaf.has_method("setup_from_page"):
		leaf.call("setup_from_page", page, turn_dir)
	if "progress" in leaf:
		leaf.set("progress", 0.0)
	_place_flip_over_frame(frame, leaf)
	return leaf


func _place_flip_over_frame(frame: Control, leaf: Control = null) -> void:
	var target := leaf if leaf != null else _flip_leaf
	if target == null or frame == null or _flip_layer == null:
		return
	## Align in FlipLayer local space to the page frame.
	target.global_position = frame.global_position
	target.size = PAGE_SIZE


func _clear_flip_leaf() -> void:
	if _flip_leaf != null and is_instance_valid(_flip_leaf):
		_flip_layer.remove_child(_flip_leaf)
		_flip_leaf.free()
	_flip_leaf = null


func _kill_tweens() -> void:
	if _turn_tween != null and _turn_tween.is_valid():
		_turn_tween.kill()
	_turn_tween = null
	if _cover_tween != null and _cover_tween.is_valid():
		_cover_tween.kill()
	_cover_tween = null


func _show_spread(spread_index: int) -> void:
	_clear_spread()
	var scenes := page_scenes()
	var left_i := spread_index * 2
	var right_i := left_i + 1
	if left_i >= 0 and left_i < scenes.size() and scenes[left_i] != null:
		_left_instance = _instance_page(scenes[left_i], _left_slot, left_i)
	else:
		_left_instance = _instance_page(BlankLeafScene, _left_slot, left_i)
	if right_i >= 0 and right_i < scenes.size() and scenes[right_i] != null:
		_right_instance = _instance_page(scenes[right_i], _right_slot, right_i)
	else:
		_right_instance = _instance_page(BlankLeafScene, _right_slot, right_i)
	_update_nav()
	page_changed.emit(get_page_index())
	spread_changed.emit(_spread_index)
	_on_spread_shown(spread_index, _left_instance, _right_instance)


## Hook for subclasses after a spread's page scenes are instanced.
func _on_spread_shown(
	_spread_index_shown: int, _left: Control, _right: Control
) -> void:
	pass


func _instance_page(scene: PackedScene, slot: Control, page_index: int) -> Control:
	var page := scene.instantiate() as Control
	if page == null:
		return null
	page.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	page.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	page.custom_minimum_size = PAGE_SIZE
	slot.add_child(page)
	var number := page.get_node_or_null("Margin/VBox/PageNumber") as Label
	if number != null and page_index >= 0:
		number.text = str(page_index + 1)
	return page


func _clear_spread() -> void:
	for child in _left_slot.get_children():
		_left_slot.remove_child(child)
		child.free()
	for child in _right_slot.get_children():
		_right_slot.remove_child(child)
		child.free()
	_left_instance = null
	_right_instance = null


func _update_nav() -> void:
	var spreads := spread_count()
	_prev_button.disabled = spreads < 2 or _spread_index <= 0
	_next_button.disabled = spreads < 2 or _spread_index >= spreads - 1
