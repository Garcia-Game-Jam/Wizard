class_name HealDisplayEntry
extends ShopDisplayEntry

## Purchasable healing — restores HP to whichever player interacts, instead
## of granting an inventory item. See ShopDisplayEntry's doc comment for how
## this fits alongside SpellDisplayEntry/ArtifactDisplayEntry.

@export_range(1.0, 1000.0, 1.0) var heal_amount: float = 50.0
