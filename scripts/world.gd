extends Node2D

var udp := PacketPeerUDP.new()
var connected := false
var message_sent := false

func _ready():
	var err = udp.set_dest_address("127.0.0.1", 2137)  
	if err == OK:
		connected = true
		print("Connected to server!")
		set_process(true)
	else:
		print("Failed to connect: ", err)

func send_message(message: String):
	if connected:
		var data = (message + "\n").to_utf8_buffer()
		print("Sending: ", message)
		udp.put_packet(data)

func _input(event):
	if event.is_action_pressed("ui_accept"):  # "Enter"
		send_message("hello from Godot!")

func _process(delta):
	if connected:

		if not message_sent:
			send_message("hello from Godot!")
			message_sent = true

		while udp.get_available_packet_count() > 0:
			var packet = udp.get_packet()
			var received = packet.get_string_from_utf8()
			print("Received from server: ", received)
