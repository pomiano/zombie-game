extends Node

@onready var player_list = $VBoxContainer/PlayerList
@onready var ready_button = $VBoxContainer/ReadyButton
@onready var back_button = $VBoxContainer/BackButton
@onready var countdown_label = $VBoxContainer/CountdownLabel
var connected := true  # już połączony, po przejściu z connect.gd
var is_ready := false

func _ready():
	ready_button.connect("pressed", Callable(self, "_on_ready_button_pressed"))
	back_button.pressed.connect(_back_pressed)
	update_player_list()
	
func update_player_list():
	# wyczyść listę
	for child in player_list.get_children():
		child.queue_free()
		
	for p_id in Global.players_nicknames_by_id.keys():
		var player_data = Global.players_nicknames_by_id[p_id]
		var p_nick = player_data["nickname"]
		var ready = player_data["ready"]
		var ready_status = "✅" if ready else "❌"
		
		var label = Label.new()
		label.text = "%s (ID: %s) %s" % [p_nick, str(p_id), ready_status]
		label.set("theme_override_colors/font_color", Color("#ff4416"))  

		# Załaduj czcionkę (jeśli jeszcze nie)
		var custom_font = preload("res://assets/fonts/Creepster-Regular.ttf")
		label.set("theme_override_fonts/font", custom_font)  

		label.set("theme_override_font_sizes/font_size", 23)
		
		player_list.add_child(label)

func _on_ready_button_pressed():
	if not is_ready:
		is_ready = true
		ready_button.disabled = true
		ready_button.text = "Czekam na innych..."
		send_message("/ready;" + str(Global.player_id))

func send_message(message: String):
	if connected:
		var data = (message + "\n").to_utf8_buffer()
		Global.udp.put_packet(data)

func _process(delta):
	while Global.udp.get_available_packet_count() > 0:
		var packet = Global.udp.get_packet()
		var received = packet.get_string_from_utf8().split(";")
		if received.size() < 1:
			continue
		var type_of_data = received[0]
		
		if type_of_data == "L":  # update listy graczy w lobby
			var players_info = received.slice(1, received.size())
			Global.players_nicknames_by_id.clear()
			
			for i in range(0, players_info.size(), 3):
				if i + 2 < players_info.size():
					var pid = int(players_info[i])
					var nick = players_info[i + 1]
					var ready = players_info[i + 2] == "1"
			
					Global.players_nicknames_by_id[pid] = {
						"nickname": nick,
						"ready": ready
					}
			update_player_list()
			
		elif type_of_data == "T":  # timer startu gry
			var countdown = int(received[1])
			if countdown > 0:
				print("Start gry za: ", countdown)
				countdown_label.text = "Start gry za: %d s" % countdown
			else:
				print("Gra startuje!")
				countdown_label.text = "Gra startuje!"
				get_tree().change_scene_to_file("res://scenes/world.tscn")
		elif type_of_data == "E":
			var error_msg = received.size() > 1 if received[1] else "Nieznany błąd"
			# np. powrót do menu
			Global.connection_error = error_msg
			Global.was_connecting = true
			get_tree().change_scene_to_file("res://scenes/mainmenu.tscn")

func _back_pressed():
	send_message("/left;" + str(Global.player_id))
	get_tree().change_scene_to_file("res://scenes/mainMenu.tscn")
	
