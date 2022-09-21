extends Node2D

var player_refs : Dictionary = {}

var kinematic_body = preload("res://player/player_physical_character.tscn")

func _ready() -> void:
	get_tree().get_multiplayer().peer_connected.connect(on_peer_connected)
	get_tree().get_multiplayer().peer_disconnected.connect(on_peer_disconnected)
	get_tree().get_multiplayer().connected_to_server.connect(on_connected_to_server)

func on_peer_connected(id : int) -> void:
	#only handle peer connections on server
	if !get_tree().get_multiplayer().is_server():
		return
	
	#tell all clients that a new peer has connected
	receive_peer_connected.rpc(id)
	#send newly connected client info about all clients presently on the server
	receive_players_on_server.rpc_id(id, get_tree().get_multiplayer().get_peers())

func on_peer_disconnected(id : int) -> void:
	#notify all connected clients of peer's disconnection
	receiver_peer_disconnected.rpc(id)

func on_connected_to_server() -> void:
	pass

@rpc(call_local, authority, reliable)
func receive_players_on_server(peers : PackedInt32Array) -> void:
	print("Client: Received peer IDs connected to server: ", peers)
	
	if !get_tree().get_multiplayer().is_server():
		#assume server is a player
		create_character(1)
	
	#create a puppet for every other player already on the server
	for peer in peers:
		#prevent from adding a puppet for the local client
		if peer == get_tree().get_multiplayer().get_unique_id():
			continue
		create_character(peer)

@rpc(call_local, authority, reliable)
func receive_peer_connected(id : int) -> void:
	print("Client: Peer connected with ID: ", id)
	
	#create character for newly joined player
	create_character(id)

@rpc(call_local, authority, reliable)
func receiver_peer_disconnected(id : int) -> void:
	#delete peer's character
	player_refs[id].queue_free()
	#remove reference to that player
	player_refs.erase(id)

func create_character(id : int) -> void:
	#create CharacterBody3D instance
	var body_instance : CharacterBody2D = kinematic_body.instantiate()
	body_instance.name = str(id)
	body_instance.set_multiplayer_authority(id)
	player_refs[id] = body_instance
	add_child(body_instance)
