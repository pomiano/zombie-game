extends Node2D

var udp := PacketPeerUDP.new()
var connected := false
var game_running := true
enum role {HUMAN, ZOMBIE}

@export 
var player : Player

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

func get_position_and_role():
	var packet = udp.get_packet()
	var received = packet.get_string_from_utf8()
	print("Received from server: ", received)
	received = received.split(";") 
	print(received)
	
	var current_id = int(received[0])
	print(current_id)
	var current_role = int(received[1])
	print(current_role)
	var current_x = float(received[2])
	print(current_x)
	var current_y = float(received[3])
	print(current_y)
	
	var property = 0
	var current_player: Player = null
	for p in players:
		if p.player_id == current_id:
			print(p.player_id, "<->", current_id)
			current_player = p
			break
			
	#current_player.player_role = current_role #temp bo coś nie śmiga
	current_player.position.x = current_x
	current_player.position.y = current_y

func _input(event):
	if event.is_action_pressed("ui_accept"):  # "Enter"
		#send_message("hello from Godot!")
		send_position_and_role()

func _process(delta):
	if connected:
		while udp.get_available_packet_count() > 0:
			get_position_and_role()
