extends Node

@onready var nick_input: LineEdit = $VBoxContainer/NickInput
@onready var ip_input: LineEdit = $VBoxContainer/IPInput
@onready var error_label: Label = $VBoxContainer/ErrorLabel
@onready var join_button: Button = $VBoxContainer/JoinButton
@onready var controls_button: Button = $VBoxContainer/HBoxContainer/ControlsButton
@onready var quit_button: Button = $VBoxContainer/HBoxContainer/QuitButton

@onready var connecting_panel: Control = $ConnectingPanel
@onready var connecting_label: Label = $ConnectingPanel/ConnectingLabel

@onready var controls_panel: Control = $ControlsPanel
@onready var backMenuButton: Button = $ControlsPanel/ControlsBox/BackMenuButton
const CONNECTION_TIMEOUT := 5.0
var connected := false

func _ready():
	join_button.pressed.connect(_on_join_pressed)
	controls_button.pressed.connect(_on_controls_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	backMenuButton.pressed.connect(_on_menu_pressed)
	connecting_panel.hide()  # Upewnij się że panel jest ukryty na starcie
	controls_panel.hide()

func _on_join_pressed():
	var nick = nick_input.text.strip_edges()
	var ip = ip_input.text.strip_edges()
	
	error_label.text = ""
	
	# Walidacja danych
	if nick.length() < 3:
		error_label.text = "Nick musi mieć co najmniej 3 znaki!"
		return
		
	if ip.is_empty():
		error_label.text = "Podaj adres IP serwera!"
		return
		
	# Aktualizacja UI przed rozpoczęciem operacji sieciowych
	update_ui_for_connection_attempt()
	
	# Próba połączenia
	var err = Global.udp.set_dest_address(ip, Global.port)
	if err != OK:
		show_error("Błąd połączenia: %s" % error_string(err))
		return
		
	connected = true
	Global.nick = nick
	send_message("/join;"+Global.nick)
	
	# Obsługa odpowiedzi serwera
	var joined_successfully := await wait_for_connection_or_timeout(CONNECTION_TIMEOUT)
	
	if joined_successfully:
		handle_successful_connection()
	else:
		handle_connection_failure()

func update_ui_for_connection_attempt():
	join_button.disabled = true
	connecting_panel.show()
	connecting_label.text = "Łączenie z serwerem"
	
	# Wymuś natychmiastową aktualizację UI
	await get_tree().process_frame

func handle_successful_connection():
	print("Połączono z serwerem!")
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")

func handle_connection_failure():
	show_error("Nie udało się połączyć z serwerem")
	connecting_panel.hide()
	join_button.disabled = false
	connected = false

func send_message(message: String):
	if connected:
		var data = (message + "\n").to_utf8_buffer()
		Global.udp.put_packet(data)

func wait_for_connection_or_timeout(timeout_sec: float) -> bool:
	var elapsed_time := 0.0
	var dots := 0
	
	while elapsed_time < timeout_sec:
		# animacja kropek
		connecting_label.text = "Łączenie z serwerem" + ".".repeat(dots)
		dots = (dots + 1) % 4
		
		# Sprawdź odpowiedź serwera
		print("test")
		if Global.udp.get_available_packet_count() > 0:
			var packet = Global.udp.get_packet().get_string_from_utf8().strip_edges()
			print("przed J")
			if packet.begins_with("J;"):
				Global.connected = true
				var parts = packet.split(";")
				print("Odebrany pakiet:", packet, "Części:", parts)
				if parts.size() >= 4:
					Global.player_id = parts[1].to_int()
					Global.x = parts[2].to_int()
					Global.y = parts[3].to_int()
					Global.players_nicknames_by_id.clear()

					for i in range(4, parts.size(), 3):
						if i + 1 < parts.size():
							var p_id = parts[i].to_int()
							var p_nick = parts[i + 1]
							var ready = parts[i + 2] == "1"
							Global.players_nicknames_by_id[p_id] = {
								"nickname": p_nick,
								"ready": ready
							}

			print("Połączono z serwerem. Otrzymano player_id:", Global.player_id)
			print("Lista graczy:", Global.players_nicknames_by_id)
			return true
		
		await get_tree().create_timer(0.5).timeout
		elapsed_time += 0.5
	
	return false
	


func show_error(message: String):
	error_label.text = message
	connecting_panel.hide()
	join_button.disabled = false

func _on_controls_pressed():
	controls_panel.show()


func _on_quit_pressed():
	get_tree().quit()
	
func _on_menu_pressed():
	controls_panel.hide()
