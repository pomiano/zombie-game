extends CharacterBody2D
class_name Player

@onready
var sprite = $Sprite2D
@onready
var camera = $Camera2D
@onready
var collision_box = $CollisionShape2D

signal collided_with_player(victim_id: int)

const HUMAN = 0
const ZOMBIE = 1

@export
var current_role: int = HUMAN
@export
var playable: bool = false
@export
var player_id : int

const VELOCITY = 80
var current_velocity = VELOCITY
var sprint_multilier = 1.5
var sprint_cooldown = 5.0
var sprint_duration = 5.0
var sprint_timer = 0.0
var is_sprinting = false
var can_sprint = true

func set_role(r):
	current_role = r
	set_sprite()

func set_sprite() -> void:
	if current_role == HUMAN:
		sprite.region_rect = Rect2(Vector2(0,0),Vector2(16,16))
	elif current_role == ZOMBIE:
		sprite.region_rect = Rect2(Vector2(32,16),Vector2(16,16))

func _ready() -> void:
	if playable:
		camera.enabled = true
	set_sprite()

func _process(delta: float) -> void:
	# movement and inputs
	if playable:
		handle_sprint(delta)
		velocity.x = Input.get_axis("ui_left", "ui_right")
		velocity.y = Input.get_axis("ui_up", "ui_down")
		velocity = velocity.normalized() * current_velocity
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
			if collider_instance.current_role == ZOMBIE:
				current_role = ZOMBIE
			# infect other player or nothing happens
			elif collider_instance.current_role == HUMAN:
				if current_role == ZOMBIE:
					collider_instance.current_role = ZOMBIE
			set_sprite()
			collider_instance.set_sprite()
			emit_signal("collided_with_player", collider_instance.player_id)

func handle_sprint(delta: float) -> void:
	# ui_accept --> spacebar 
	if Input.is_action_pressed("ui_accept") and can_sprint:
		is_sprinting = true
		can_sprint = false
		current_velocity = VELOCITY * sprint_multilier
		sprint_timer = sprint_duration
		
	if is_sprinting:
		sprint_timer -= delta
		if sprint_timer <= 0:
			is_sprinting = false
			current_velocity = VELOCITY
			sprint_timer = sprint_cooldown 
			
	if not is_sprinting and not can_sprint:
		sprint_timer -= delta
		if sprint_timer <= 0:
			can_sprint = true
	
func get_sprint_progress() -> float:
	if is_sprinting:
		return sprint_timer / sprint_duration
	elif not can_sprint:
		return 1.0 - (sprint_timer / sprint_cooldown)
	else:
		return 1.0  #pełne naładowanie
