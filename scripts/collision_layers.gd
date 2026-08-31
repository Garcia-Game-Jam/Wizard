class_name CollisionLayers
extends RefCounted

## Physics layers: characters on 1, pit geometry on 2.

const CHARACTER := 1
const WORLD := 2
const CHARACTER_AND_WORLD := CHARACTER | WORLD
const GHOST_MASK := WORLD
