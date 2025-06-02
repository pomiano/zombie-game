extends Node2D
var game_running := true

@export 
var player : Player
@export 
var PlayerScene: PackedScene

@onready var gameover_panel: Control = $UI/GameOverPanel
@onready var gameover_label: Label = $UI/GameOverPanel/GameOverLabel

@onready var players_panel: Control = $UI/PlayersPanel
@onready var players_box: VBoxContainer = $UI/PlayersPanel/VBoxContainer

@onready var sprint_bar: ProgressBar = $UI/SprintBar
@onready var sprint_label: Label = $UI/SprintLabel

@onready var time_label: Label = $UI/TimeLabel

@onready var humans_label: Label = $UI/PlayersLabel
@onready var zombies_label: Label = $UI/ZombiesLabel

var players := {}
const HUMAN = 0
const ZOMBIE = 1

func _ready():
	Global.time_left = Global.GAME_DURATION_SECONDS
	player.player_id = Global.player_id
	player.position.x = Global.x
	player.position.y = Global.y
	player.connect("collided_with_player", Callable(self, "_on_player_collided"))
	gameover_panel.hide()
	players_panel.hide()
	update_players_panel()

func send_message(message: String):
	if Global.connected:
		var data = (message + "\n").to_utf8_buffer()
		Global.udp.put_packet(data)

func send_data_to_server():
	if Global.connected and player:
		var pos_str = "P;%d;%d;%f;%f" % [player.player_id, player.current_role, player.position.x, player.position.y]
		var data = pos_str.to_utf8_buffer()
		Global.udp.put_packet(data)

func _on_player_collided(victim_id: int) -> void:
	#print("Collision detected with player:", victim_id)
	send_collision_to_server(victim_id)
	
func reset_players_ready() -> void:
	for pid in Global.players_nicknames_by_id.keys():
		Global.players_nicknames_by_id[pid]["ready"] = false
		
func update_num_players(humans:int, zombies:int) -> void:
	humans_label.text = "LUDZIE: %d" % [humans]
	zombies_label.text = "ZOMBIE: %d" % [zombies]
	

func get_data_from_server():
	var packet = Global.udp.get_packet()
	var received = packet.get_string_from_utf8()
	received = received.split(";") 
	#print("Received from server: ", received)

	var type_of_data = String(received[0]) #idk dlaczego nie mogę po prostu użyć chara
	
	var num_zombies: int = 0
	var num_humans: int = 0 
	
	if type_of_data == "P":
		var player_chunks = received[1].split("|")

		for chunk in player_chunks:
			var parts = chunk.split(",")
			if parts.size() != 4:
				continue  # zignoruj błędne dane

			var current_id = int(parts[0])
			var current_role = int(parts[1])
			var current_x = float(parts[2])
			var current_y = float(parts[3])
			
			if current_role == HUMAN:
				num_humans+=1
			else:
				num_zombies+=1
				
			if current_id == player.player_id:
				player.set_role(current_role)
				continue

			if players.has(current_id):
				var existing_player: Player = players[current_id]
				existing_player.position = Vector2(current_x, current_y)
				existing_player.set_role(current_role)
			else:
				var new_player := PlayerScene.instantiate() as Player
				new_player.player_id = current_id
				new_player.current_role = current_role
				new_player.position = Vector2(current_x, current_y)
				add_child(new_player)
				new_player.connect("collided_with_player", Callable(self, "_on_player_collided"))
				players[current_id] = new_player
				
		update_num_players(num_humans, num_zombies)
		
	elif type_of_data == "G":
		if who_won() == ZOMBIE:
			gameover_label.text = "KONIEC GRY\nZWYCIESTWO ZOMBIE"
		else:
			gameover_label.text = "KONIEC\nZWYCIESTWO GRACZY"
			
			
		for id in players:
			players[id].set_role(ZOMBIE)
			
		game_running = false
		gameover_panel.show()
		reset_players_ready()
		await get_tree().create_timer(3.0).timeout 
		
		print("GAME OVER!")
		get_tree().change_scene_to_file("res://scenes/lobby.tscn")
		
	elif(type_of_data == "D"):
		pass

func who_won():
	for id in players:
		if players[id].current_role == HUMAN:
			return HUMAN
	return ZOMBIE

func update_players_panel():
	for child in players_box.get_children():
		players_box.remove_child(child)
		child.queue_free()
	
	for id in Global.players_nicknames_by_id.keys():
		var gracz = Global.players_nicknames_by_id[id]
		var nick = gracz["nickname"]
		
		var label = Label.new()
		label.text = "ID: %d - %s" % [id, nick]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.set("theme_override_colors/font_color", Color("#ff4416"))  
		var custom_font = preload("res://assets/fonts/Creepster-Regular.ttf")
		label.set("theme_override_fonts/font", custom_font)  

		label.set("theme_override_font_sizes/font_size", 23)
		
		players_box.add_child(label)

func send_collision_to_server(target_player_id: int):
	var msg = "C;%d;%d" % [player.player_id, target_player_id]
	send_message(msg)
	
func update_timer(delta: float) -> void:
	Global.time_left -= delta
	
	if Global.time_left < 0:
		Global.time_left = 0
		
	var time = ""
	var minutes = floor(Global.time_left / 60)
	var seconds = floor(fmod(Global.time_left, 60))
	
	var time_string = "%02d:%02d" % [minutes, seconds]
	
	time_label.text = time_string
	pass
	
func _input(event):
	if event is InputEventKey and event.keycode == KEY_TAB:
		if event.pressed:
			players_panel.show()
		else:
			players_panel.hide()

func _process(delta):
	if game_running:
		var progress = player.get_sprint_progress()
		sprint_bar.value = progress * 100.0
		if progress >= 1.0:
			sprint_label.text = "Sprint gotowy"
		else:
			sprint_label.text = ""
		update_timer(delta)
		
	if Global.connected:
		while Global.udp.get_available_packet_count() > 0:
			get_data_from_server()
		if game_running:
			send_data_to_server() 
