@tool
class_name PlayerMenu
extends PanelContainer

## Centered Tab menu: Inventory, Spells, and Guide. (The spellbook is its own
## book overlay now — see scripts/ui/book/spell/spell_book.gd, hotkey B.)

enum Tab {
	INVENTORY,
	SPELLS,
	GUIDE,
}

const GuideContentScript := preload("res://scripts/ui/guide_content.gd")
const PlayerInventoryScript := preload("res://scripts/inventory/player_inventory.gd")
const InventorySlotButtonScript := preload("res://scripts/ui/inventory_slot_button.gd")
const SpellHotbarScript := preload("res://scripts/spells/spell_hotbar.gd")
const SpellSlotButtonScript := preload("res://scripts/ui/spell_slot_button.gd")

@export var editor_tab: Tab = Tab.GUIDE:
	set(value):
		editor_tab = value
		if Engine.is_editor_hint() and is_node_ready():
			_show_tab(value)

var _inventory: Node
var _spell_hotbar: Node
var _tab: Tab = Tab.GUIDE
var _objective_lines: PackedStringArray = PackedStringArray()
var _inv_buttons: Array[Button] = []
var _spell_buttons: Array[Button] = []

@onready var _title_label: Label = $MarginContainer/VBox/Header/TitleLabel
@onready var _subtitle_label: Label = $MarginContainer/VBox/Header/SubtitleLabel
@onready var _tab_bar: TabBar = $MarginContainer/VBox/TabBar
@onready var _inventory_page: VBoxContainer = $MarginContainer/VBox/InventoryPage
@onready var _inventory_grid: GridContainer = $MarginContainer/VBox/InventoryPage/InventoryGrid
@onready var _inventory_hint: Label = $MarginContainer/VBox/InventoryPage/InventoryHint
@onready var _spells_page: VBoxContainer = $MarginContainer/VBox/SpellsPage
@onready var _spells_grid: GridContainer = $MarginContainer/VBox/SpellsPage/SpellsGrid
@onready var _spells_hint: Label = $MarginContainer/VBox/SpellsPage/SpellsHint
@onready var _guide_page: VBoxContainer = $MarginContainer/VBox/GuidePage
@onready var _hints_label: Label = $MarginContainer/VBox/GuidePage/HintsLabel
@onready var _objective_label: Label = $MarginContainer/VBox/GuidePage/ObjectiveLabel


func _ready() -> void:
	if not _tab_bar.tab_changed.is_connected(_on_tab_changed):
		_tab_bar.tab_changed.connect(_on_tab_changed)
	if Engine.is_editor_hint():
		_show_tab(editor_tab)
		return
	_bind_inventory_slots()
	_bind_spell_slots()
	visible = false
	_show_tab(Tab.GUIDE)


func configure_inventory(inventory: Node) -> void:
	if (
		_inventory != null
		and _inventory.has_signal("inventory_changed")
		and _inventory.inventory_changed.is_connected(_refresh_inventory)
	):
		_inventory.inventory_changed.disconnect(_refresh_inventory)
	_inventory = inventory
	if _inventory != null and _inventory.has_signal("inventory_changed"):
		_inventory.inventory_changed.connect(_refresh_inventory)
	_refresh_inventory()


func configure_spell_hotbar(hotbar: Node) -> void:
	if (
		_spell_hotbar != null
		and _spell_hotbar.has_signal("slots_changed")
		and _spell_hotbar.slots_changed.is_connected(_refresh_spells)
	):
		_spell_hotbar.slots_changed.disconnect(_refresh_spells)
	_spell_hotbar = hotbar
	if _spell_hotbar != null and _spell_hotbar.has_signal("slots_changed"):
		_spell_hotbar.slots_changed.connect(_refresh_spells)
	_refresh_spells()


func get_tab() -> Tab:
	return _tab


func reset_to_main() -> void:
	_show_tab(Tab.GUIDE)


func open_inventory() -> void:
	_show_tab(Tab.INVENTORY)


func refresh(objective_lines: PackedStringArray) -> void:
	_objective_lines = objective_lines
	if _tab == Tab.GUIDE:
		_apply_main_view(_objective_lines)
	elif _tab == Tab.INVENTORY:
		_refresh_inventory()
	elif _tab == Tab.SPELLS:
		_refresh_spells()


func _show_tab(tab: Tab) -> void:
	_tab = tab
	if _tab_bar.current_tab != int(tab):
		_tab_bar.set_block_signals(true)
		_tab_bar.current_tab = int(tab)
		_tab_bar.set_block_signals(false)
	match tab:
		Tab.INVENTORY:
			_title_label.text = "Inventory"
			_subtitle_label.text = "Drag items between slots. Press [Tab] to hide"
			if not Engine.is_editor_hint():
				_refresh_inventory()
		Tab.SPELLS:
			_title_label.text = "Spells"
			_subtitle_label.text = "Drag to swap slots. Press [Tab] to hide"
			if not Engine.is_editor_hint():
				_refresh_spells()
		Tab.GUIDE:
			_title_label.text = "Guide"
			_subtitle_label.text = "Press [Tab] to hide"
			_apply_main_view(_objective_lines)
	_update_content_visibility()


func _update_content_visibility() -> void:
	_inventory_page.visible = _tab == Tab.INVENTORY
	_spells_page.visible = _tab == Tab.SPELLS
	_guide_page.visible = _tab == Tab.GUIDE


func _on_tab_changed(tab: int) -> void:
	_show_tab(tab as Tab)


func _apply_main_view(objective_lines: PackedStringArray) -> void:
	var view := GuideContentScript.build_view(objective_lines)
	_hints_label.text = str(view.get("hints", ""))
	_objective_label.text = str(view.get("objectives", ""))


func _bind_inventory_slots() -> void:
	_inv_buttons.clear()
	var i := 0
	for child in _inventory_grid.get_children():
		var button := child as Button
		if button == null:
			continue
		if button.has_method("setup"):
			button.call("setup", _inventory, i)
		_inv_buttons.append(button)
		i += 1
	while i < PlayerInventoryScript.SLOT_COUNT:
		var button: Button = InventorySlotButtonScript.new()
		_inventory_grid.add_child(button)
		if button.has_method("setup"):
			button.call("setup", _inventory, i)
		_inv_buttons.append(button)
		i += 1
	if _inventory_hint != null:
		_inventory_hint.text = "Drag items between slots. Slots 1–4 are the hotbar (keys 1–4)."


func _refresh_inventory() -> void:
	for button in _inv_buttons:
		if button.has_method("setup"):
			button.call("setup", _inventory, int(button.get("slot_index")))
		elif button.has_method("refresh"):
			button.set("inventory", _inventory)
			button.call("refresh")


func _bind_spell_slots() -> void:
	_spell_buttons.clear()
	var i := 0
	for child in _spells_grid.get_children():
		var button := child as Button
		if button == null:
			continue
		if button.has_method("setup"):
			button.call("setup", _spell_hotbar, i)
		_spell_buttons.append(button)
		i += 1
	while i < SpellHotbarScript.SLOT_COUNT:
		var button: Button = SpellSlotButtonScript.new()
		_spells_grid.add_child(button)
		if button.has_method("setup"):
			button.call("setup", _spell_hotbar, i)
		_spell_buttons.append(button)
		i += 1
	if _spells_hint != null:
		_spells_hint.text = (
			"Drag spells to swap slots. After a voice confirm, press LMB / RMB / Q / E to assign."
		)


func _refresh_spells() -> void:
	for button in _spell_buttons:
		if button.has_method("setup"):
			button.call("setup", _spell_hotbar, int(button.get("slot_index")))
		elif button.has_method("refresh"):
			button.set("hotbar", _spell_hotbar)
			button.call("refresh")
