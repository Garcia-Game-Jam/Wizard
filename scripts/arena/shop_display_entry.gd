class_name ShopDisplayEntry
extends Resource

## Base type for one pedestal in a ShopStructure's shop_displays array — which
## bay it sits in, shared by all three concrete kinds:
##  - SpellDisplayEntry: teaches a spell, icon tinted by that spell's own
##    SpellDefinition.color (looked up live via the "spell_registry" group).
##  - ArtifactDisplayEntry: placeholder — no artifact items exist yet, but
##    grants a plain PlayerInventory entry, icon tinted by a deterministic
##    hash of the item id.
##  - HealDisplayEntry: restores HP instead of granting an item, green "+"
##    icon instead of a gem.
## ShopDisplayPedestal (the interactive half — floating icon, "press F to
## buy" prompt) branches on the concrete subclass for display name, icon
## color/shape, and what interact() actually does; this Resource is just the
## per-pedestal config, same split as the Encounter/CombatEncounter/
## ShopEncounter hierarchy in encounter.gd.

@export var bay_index: int = 0
