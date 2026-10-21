class_name MapSizeDef
extends Resource
## How big a map is: the plots you could ever own each way, the plots you
## start with in the middle, and the ground past the buyable area that
## fades into fog.

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
## Plots you can own each way, at most.
@export var plots := 8
## Plots owned at the start each way, in the middle.
@export var start_plots := 4
## Tiles of ground past the buyable area on every side.
@export var margin := 24
## Offered when starting a new prison.
@export var offered := true


## The tiles across the whole map.
func tiles(plot_size: int) -> int:
	return plots * plot_size + margin * 2


## The area you could own, in tiles.
func area(plot_size: int) -> Rect2i:
	return Rect2i(Vector2i(margin, margin), Vector2i.ONE * plots * plot_size)


## The land you start with, in tiles.
func start(plot_size: int) -> Rect2i:
	var first := (plots - start_plots) / 2
	return Rect2i(Vector2i.ONE * (margin + first * plot_size), Vector2i.ONE * start_plots * plot_size)
