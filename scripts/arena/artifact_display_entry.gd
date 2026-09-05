class_name ArtifactDisplayEntry
extends ShopDisplayEntry

## Placeholder shop display for artifacts — inventory items with passives
## that apply only to the player who picked them up. No artifact items exist
## yet, so interact() just grants a plain PlayerInventory entry by id, same
## as any other inventory item. See ShopDisplayEntry's doc comment for how
## this fits alongside SpellDisplayEntry/HealDisplayEntry.

@export var item_id: String = ""
