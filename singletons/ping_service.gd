extends Node

#global
var ping_update_frequency : int = 5

#client
var ping : float = 0.0:
	get:
		return ping_dictionary[multiplayer.get_unique_id()]
var ping_dictionary : Dictionary = {}


var server_time_offset : int = 0:
	set(x):
		server_time_offset_history.append(x)
		if server_time_offset_history.size() > server_time_offset_history_max_length:
			#remove oldest entry
			server_time_offset_history.remove_at(0)

		var sum : int = 0
		for i in server_time_offset_history:
			sum += i
		server_time_offset = int(float(sum) / server_time_offset_history.size())
var server_time_offset_history_max_length : int = 20
var server_time_offset_history := PackedInt64Array()
#server
#list of all player's stats
var player_stats : Dictionary = {}

class player_ping_statistics:
	const ping_history_max_length = 20

	#average ping in seconds
	var ping : float = 0.0
	var ping_history := PackedFloat64Array()
	var mark_for_recompute : bool = false

	func new() -> RefCounted:
		return self

	#adds a new ping to the history and handles recomputing
	func register_ping(_ping : float) -> void:
		ping_history.append(_ping)

		if ping_history.size() > ping_history_max_length:
			#remove oldest ping value
			ping_history.remove_at(0)

		mark_for_recompute = true

	func recompute_average_ping() -> void:
		var sum : float = 0.0
		for value in ping_history:
			sum += value

		ping = sum / ping_history.size()
		mark_for_recompute = false

func _ready() -> void:
	get_tree().get_multiplayer().peer_connected.connect(on_peer_connected)
	get_tree().get_multiplayer().peer_disconnected.connect(on_peer_disconnected)
	get_tree().get_multiplayer().connected_to_server.connect(on_connected_to_server)


	var timer := Timer.new()
	timer.wait_time = 1.0 / ping_update_frequency
	timer.timeout.connect(update_ping)
	add_child(timer)
	timer.start.call_deferred()

func update_ping() -> void:
	if !multiplayer.has_multiplayer_peer() or !multiplayer.is_server():
		return

	#ping everyone
	_ping.rpc(Time.get_ticks_msec())

func _physics_process(_delta : float) -> void:
	if !multiplayer.has_multiplayer_peer():
		return

	#server side
	if multiplayer.is_server():
		#keep new player network stats in a dictionary to lower overhead from RPCs
		var recomputed_stats : Dictionary = {}
		for player_id in player_stats.keys():
			#recalculate average ping
			var current_player_stat : RefCounted = player_stats[player_id]
			if current_player_stat.mark_for_recompute:
				current_player_stat.recompute_average_ping()

				#save to dictionary
				recomputed_stats[player_id] = current_player_stat.ping

		#send updated pings, and current server time
		receive_updated_pings.rpc(recomputed_stats, Time.get_ticks_msec())




#server sends ping to client
@rpc(call_remote, any_peer, unreliable_ordered)
func _ping(_server_time : int) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	#return time to server
	_pong.rpc_id(1, _server_time + int(get_physics_process_delta_time() * 1000.0))

#client returns pong to server
@rpc(call_local, any_peer, unreliable_ordered)
func _pong(returned_time : int) -> void:
	#this is the one-way latency
	var elapsed_time : float = float(Time.get_ticks_msec() - returned_time) / 1000.0
	#add to player's network stats entry
	player_stats[multiplayer.get_remote_sender_id()].register_ping(elapsed_time)

@rpc(call_local, any_peer, unreliable_ordered)
func receive_updated_pings(_ping_dictionary : Dictionary, server_time : int) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return

	for id in _ping_dictionary:
		set_ping(id, _ping_dictionary[id])

	server_time_offset = Time.get_ticks_msec() - server_time
	


#utility funcs
func get_ping(id : int) -> float:
	return ping_dictionary[id]

func set_ping(id : int, new_ping : float) -> void:
	ping_dictionary[id] = new_ping



#create initial values for new peers
func on_connected_to_server() -> void:
	ping_dictionary[multiplayer.get_unique_id()] = 0.0
func on_peer_connected(id : int) -> void:
	ping_dictionary[id] = 0.0

	#if on server, create entry for new player
	if multiplayer.is_server():
		player_stats[id] = player_ping_statistics.new()

func on_peer_disconnected(id : int) -> void:
	ping_dictionary.erase(id)

	#if on server, remove entry
	if multiplayer.is_server():
		player_stats.erase(id)
