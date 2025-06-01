extends Node

var nick: String = ""
var ip: String = "127.0.0.1"
var port:= 2137
var connection_error:String =""
var was_connecting := false
var udp := PacketPeerUDP.new()
var player_id: int = -1
var x: int = 0
var y: int = 0
var players_nicknames_by_id = {}
var connected := false

const GAME_DURATION_SECONDS = 180
var time_left = GAME_DURATION_SECONDS
