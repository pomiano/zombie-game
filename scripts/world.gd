extends Node2D

var udp := PacketPeerUDP.new()
var connected := false
var game_running := true
enum role {HUMAN, ZOMBIE}

@export 
var player : Player
@export 
var PlayerScene: PackedScene


var players = []

func _ready():
	var err = udp.set_dest_address("127.0.0.1", 2137)  
	if err == OK:
		connected = true
		print("Connected to server!")
		set_process(true)
	else:
		print("Failed to connect: ", err)
	
	var dzieci = get_children()
	for dziecko in dzieci:
		if dziecko is Player:
			players.append(dziecko)
	print(players)

func send_message(message: String):
	if connected:
		var data = (message + "\n").to_utf8_buffer()
		print("Sending: ", message)
		udp.put_packet(data)

func send_position_and_role():
	if connected and player:
		var pos_str = "%d;%d;%f;%f" % [player.player_id, player.current_role, player.position.x, player.position.y]
		var data = pos_str.to_utf8_buffer()
		print(pos_str)
		udp.put_packet(data)

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
	
	if(type_of_data == 'P'):
		var current_id = int(received[1])
		var current_role = int(received[2])
		var current_x = float(received[3])
		var current_y = float(received[4])
		
		var current_player: Player = null
		# set position for all the players except yours
		for p in players:
			if p.player_id == current_id:
				current_player = p
				if current_id != player.player_id:
					current_player.position.x = current_x
					current_player.position.y = current_y
				break
		
		current_player.set_role(current_role) 
		
	elif(type_of_data == "J"): # player joined
		var current_id = int(received[1])
		
		var new_player := PlayerScene.instantiate() as Player
		new_player.current_role = 0
		new_player.player_id = current_id
		new_player.position.x = randi_range(30,190)
		new_player.position.y = randi_range(30,150)
		add_child(new_player)
		players.append(new_player)
	
	elif(type_of_data == "D"): #player disconnect TODO
		pass

func _input(event):
	if event.is_action_pressed("ui_accept"):  # "Enter"
		#send_message("hello from Godot!")
		send_position_and_role()

func _process(delta):
	if connected:
		while udp.get_available_packet_count() > 0:
			get_data_from_server()
