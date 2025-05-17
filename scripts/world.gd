extends Node2D

var udp := PacketPeerUDP.new()
var connected := false
var game_running := false

@export 
var player : Player
@export 
var PlayerScene: PackedScene


var players := {}

func _ready():
	var args = OS.get_cmdline_args()
	player.player_id = 0
			
	players[player.player_id] = player
	player.connect("collided_with_player", Callable(self, "_on_player_collided"))
	var bind_result = udp.bind(0) # 0 = losowy dostępny port
	if bind_result != OK:
		print("Failed to bind UDP socket:", bind_result)
		return
	var err = udp.set_dest_address("127.0.0.1", 2137)  
	if err == OK:
		connected = true
		send_message("/join")
		print("Connected to server!")
		set_process(true)
	else:
		print("Failed to connect: ", err)
	print(players)

func send_message(message: String):
	if connected:
		var data = (message + "\n").to_utf8_buffer()
		print("Sending: ", message)
		udp.put_packet(data)

func send_data_to_server():
	if connected and player:
		var pos_str = "P;%d;%d;%f;%f" % [player.player_id, player.current_role, player.position.x, player.position.y]
		var data = pos_str.to_utf8_buffer()
		print(pos_str)
		udp.put_packet(data)

func _on_player_collided(victim_id: int) -> void:
	print("Collision detected with player:", victim_id)
	send_collision_to_server(victim_id)

func get_data_from_server():
	var packet = udp.get_packet()
	var received = packet.get_string_from_utf8()
	received = received.split(";") 
	print("Received from server: ", received)
	
	# type_of_data
	# [P] position & role -> data_type;id;role;pos_x;pos_y
	# [J] player joined -> data_type;id
	# [D] player disconnected -> data_type;id
	
	var type_of_data = String(received[0]) #idk dlaczego nie mogę po prostu użyć chara
	
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
		
	elif(type_of_data == "J"): # player joined
		var current_id = int(received[1])
		var current_role = int(received[2])
		var current_x = float(received[3])
		var current_y = float(received[4])
		
		if current_id == player.player_id or player.player_id == 0:
			player.player_id = current_id
			player.current_role = current_role
			player.position = Vector2(current_x, current_y)
			players[current_id] = player
			return
				
		if players.has(current_id):
			return 
			
		var new_player := PlayerScene.instantiate() as Player
		new_player.current_role = current_role
		new_player.player_id = current_id
		new_player.position.x = current_x
		new_player.position.y = current_y
		add_child(new_player)
		new_player.connect("collided_with_player", Callable(self, "_on_player_collided"))
		players[current_id] = new_player
	elif type_of_data == "T":  # Timer message
		var countdown = int(received[1])
		if countdown > 0:
			print("Game starts in: ", countdown)
		else:
			print("Game started!")
			game_running = true
	elif type_of_data == "G":
		game_running = false
		print("GAME OVER!")
		
	elif(type_of_data == "D"): #TODO player disconnect 
		pass

func _input(event):
	if event.is_action_pressed("ui_accept"):  # Enter
		#send_message("hello from Godot!")
		send_data_to_server()

func send_collision_to_server(target_player_id: int):
	var msg = "C;%d;%d" % [player.player_id, target_player_id]
	send_message(msg)

func _process(delta):
	if connected:
		while udp.get_available_packet_count() > 0:
			get_data_from_server()
		if game_running:
			send_data_to_server() #TODO
