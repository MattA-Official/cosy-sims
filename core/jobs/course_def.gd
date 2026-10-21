class_name CourseDef
extends Resource
## A course people take in sessions, with an exam at the end: reading or
## woodwork for prisoners, lessons in a school, therapy in a hospital. A
## teacher works at `teacher_tag` while each student sits at a
## `student_tag` in a room of `room_type`, in blocks that hold classes.

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var icon: Texture2D
@export var room_type: StringName = &"classroom"
@export var teacher_role: StringName = &"teacher"
@export var teacher_tag: StringName = &"whiteboard"
@export var student_tag: StringName = &"class_desk"
## Sessions before the exam, and how long each runs in game minutes.
@export var sessions := 6
@export var session_minutes := 120.0
## The skill a pass raises, and by how much; empty for none.
@export var skill: StringName
@export var skill_on_pass := 30
## Pass chance added for people with a trait, by trait id.
@export var trait_bonus: Dictionary[StringName, float] = {}
## The progress source (see Progress) each session attended gives.
@export var session_source: StringName = &"course_session"
## Moodlet given on a pass, and any lasting effect, such as &"calmer".
@export var pass_moodlet: StringName = &"proud"
@export var after_pass: StringName
