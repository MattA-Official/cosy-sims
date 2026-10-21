class_name ArrivalPointDef
extends Resource
## One way into the place: a bus stop, a dock, a helipad. A placed object
## with its tag marks it, and vehicles come to it by its route (see
## Arrivals). Shared by any game: the hospital's ambulance bay and the
## airport's stands are the same.

enum Route { ROAD, WATER, AIR, CABLE, NONE }

@export var id: StringName
@export var display_name: String
## The placed object that marks it.
@export var object_tag: StringName
@export var route := Route.ROAD
## What comes: a bus, a ferry, a helicopter. Empty to use the caller's.
@export var vehicle: PackedScene
## Words for the vehicle, such as "ferry".
@export var vehicle_name := "bus"
## People and crates a trip carries.
@export var seats := 8
@export var cargo := 40
## For AIR and CABLE: game minutes from setting off to landing.
@export var travel_minutes := 0.0
## Weather ids that stop trips, such as a storm closing the dock.
@export var closed_by: Array[StringName] = []
