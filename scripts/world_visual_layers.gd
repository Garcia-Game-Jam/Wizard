class_name WorldVisualLayers
extends RefCounted

## Render layers for separating player visuals from maze / interactable geometry.

const WORLD := 1
const PLAYER_SELF := 2
const WORLD_LIGHT_MASK := WORLD
const SCENE_LIGHT_MASK := WORLD | PLAYER_SELF
