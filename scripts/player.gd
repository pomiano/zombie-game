extends CharacterBody2D

@onready
var sprite = $Sprite2D

enum {HUMAN, ZOMBIE}
const VELOCITY = 100
var current_role = ZOMBIE

func set_sprite() -> void:
	if current_role == HUMAN:
		sprite.region_rect = Rect2(Vector2(0,0),Vector2(16,16))
	elif current_role == ZOMBIE:
		sprite.region_rect = Rect2(Vector2(32,16),Vector2(16,16))

func _ready() -> void:
	set_sprite()

func _process(delta: float) -> void:
	# movement and inputs
	velocity.x = Input.get_axis("ui_left", "ui_right")
	velocity.y = Input.get_axis("ui_up", "ui_down")
	velocity = velocity.normalized() * VELOCITY
	move_and_slide()
	
	# flip player horizontally
	if velocity.x < 0:
		sprite.flip_h = true
	else: 
		sprite.flip_h = false
