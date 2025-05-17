extends CharacterBody2D
class_name Player

@onready
var sprite = $Sprite2D
@onready
var camera = $Camera2D
@onready
var collision_box = $CollisionShape2D

signal collided_with_player(victim_id: int)

enum role {HUMAN, ZOMBIE}
@export
var current_role: role = role.HUMAN
@export
var playable: bool = false
@export
var player_id : int

const VELOCITY = 64

func set_role(r):
	current_role = r
	set_sprite()

func set_sprite() -> void:
	if current_role == role.HUMAN:
		sprite.region_rect = Rect2(Vector2(0,0),Vector2(16,16))
	elif current_role == role.ZOMBIE:
		sprite.region_rect = Rect2(Vector2(32,16),Vector2(16,16))

func _ready() -> void:
	if playable:
		camera.enabled = true
	set_sprite()

func _process(delta: float) -> void:
	# movement and inputs
	if playable:
		velocity.x = Input.get_axis("ui_left", "ui_right")
		velocity.y = Input.get_axis("ui_up", "ui_down")
		velocity = velocity.normalized() * VELOCITY
		move_and_slide()
	
	# flip player horizontally
	if velocity.x < 0:
		sprite.flip_h = true
	elif velocity.x > 0: 
		sprite.flip_h = false
		
	# collisions
	if get_last_slide_collision():
		var collider = get_last_slide_collision().get_collider()
		if collider.get_class() == "CharacterBody2D":
			print("Collision with other Player")
			var collider_instance : Player = instance_from_id(collider.get_instance_id())
			# get infected
			if collider_instance.current_role == role.ZOMBIE:
				current_role = role.ZOMBIE
			# infect other player or nothing happens
			elif collider_instance.current_role == role.HUMAN:
				if current_role == role.ZOMBIE:
					collider_instance.current_role = role.ZOMBIE
			set_sprite()
			collider_instance.set_sprite()
			emit_signal("collided_with_player", collider_instance.player_id)
