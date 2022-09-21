extends CharacterBody2D

const SPEED = 500.0

@onready var server_time_machine := TimeMachine.new()
@onready var client_input_time_machine := TimeMachine.new(60)

var network_input := Vector2.ZERO
var network_position := Vector2.ZERO
var network_velocity := Vector2.ZERO

func _ready() -> void:
	MultiplayerSingleton.network_update.connect(on_network_update)
	$"ID Label".text = str(get_multiplayer_authority())
	
	server_time_machine.create_entry()
	server_time_machine.set_property(&"position", position)
	server_time_machine.set_property(&"velocity", velocity)
	server_time_machine.set_property(&"is_on_floor", is_on_floor())
	server_time_machine.set_property(&"rollback", Vector2.ZERO)
	server_time_machine.set_property(&"ping", 0.0)

var input := Vector2.ZERO
func _process(_delta : float) -> void:
	if is_multiplayer_authority():
		input = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		
		#tell server my input
		transmit_input_update.rpc_id(1, input)
	


func _physics_process(delta : float) -> void:
	var rollback_amount : Vector2 = (network_input - input) * SPEED * PingService.get_ping(get_multiplayer_authority()) / 2.0
	if multiplayer.is_server():
		#account for input lag
#		position += rollback_amount
		input = network_input
		
		
		velocity.x = input.x * SPEED
		velocity.y = input.y * SPEED
	else:
		if !is_multiplayer_authority():
			position = server_time_machine.get_property_interpolated("position", MultiplayerSingleton.network_interpolation_duration)
			velocity = server_time_machine.get_property_interpolated("velocity", MultiplayerSingleton.network_interpolation_duration)
	
	move_and_slide()
	
	if is_multiplayer_authority():
		#save input history for client extrapolation
		client_input_time_machine.create_entry()
		client_input_time_machine.set_property("physics_delta", delta)
		client_input_time_machine.set_property("input", input)
		
		
	
	
	#only the server has authority to update player positions
	if multiplayer.is_server():
		server_time_machine.create_entry()
		server_time_machine.set_property(&"position", position)
		server_time_machine.set_property(&"velocity", velocity)
		server_time_machine.set_property(&"is_on_floor", is_on_floor())
		server_time_machine.set_property(&"rollback", rollback_amount)
		server_time_machine.set_property(&"ping", PingService.get_ping(get_multiplayer_authority()))
		server_time_machine.append_to_network_buffer()
	else:
		if is_multiplayer_authority():
			#do input extrapolation here
			extrapolate_by_input_buffer()
		#puppet
		else:
			extrapolate_by_velocity()

#this is where to transmit network updates
func on_network_update() -> void:
	if multiplayer.is_server():
		receive_server_time_machine_entry.rpc(Time.get_ticks_msec(), server_time_machine.network_buffer)
		server_time_machine.clear_network_buffer()


#can only be called by authority client
@rpc(call_local, authority, unreliable_ordered, 1)
func transmit_input_update(_input : Vector2) -> void:
	#if not server
	if !multiplayer.is_server():
		push_error("Client Error: Unauthorized network input update from peer %s" % multiplayer.get_remote_sender_id())
		return
	
	#prevent client from sending spoofed/replaced input value
	network_input = _input.limit_length()

#client receives server state
@rpc(call_remote, any_peer, unreliable_ordered, 2)
func receive_server_time_machine_entry(server_time : int, entries : Array) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		push_error("Client Error: Unauthorized network time machine update from peer %s" % multiplayer.get_remote_sender_id())
	
	#get complete server time machine with fewer RPCs
	for entry in entries:
		
		
		#adjust for cases of rollback/rollforward
	#	var rollback_amount : Vector2 = (network_input - input) * SPEED * PingService.get_ping(get_multiplayer_authority())
		var rollback : Vector2 = entry["rollback"]
		var ping : float = entry["ping"] * 500.0
		
		server_time_machine.get_closest_timestamp_after(Time.get_ticks_msec() - int(ping))
		
		#work backwards from current entry, 
		#account for rollback until we've reached the entry ping seconds before this one
		
		server_time_machine.submit_entry(server_time - PingService.server_time_offset, entry)


func movement_logic(input : Vector2, delta : float) -> Vector2:
	
	return Vector2.ZERO


#jitter in here?

#authority client extrapolation
func extrapolate_by_input_buffer() -> void:
	#get latest timestamp
	var client_time : int = server_time_machine.get_closest_timestamp_before(Time.get_ticks_msec())
	#get list of inputs every frame since last server update
	var timestamps : PackedInt64Array = client_input_time_machine.get_timestamps_after(client_time)
	
	#sum up all movements
	var last_position : Vector2 = server_time_machine.get_property_interpolated("position", MultiplayerSingleton.network_interpolation_duration)
	for timestamp in timestamps:
		
		var entry : Dictionary = client_input_time_machine.get_entry(timestamp)
		var delta : float = entry["physics_delta"]
		var history_input : Vector2 = entry["input"]
		var calculated_velocity := Vector2.ZERO
		
		calculated_velocity.x = history_input.x * SPEED
		calculated_velocity.y = history_input.y * SPEED
		
		last_position = last_position + calculated_velocity * delta
	
	#apply position
	position = last_position

#puppet extrapolation
func extrapolate_by_velocity() -> void:
	var last_entry : Dictionary = server_time_machine.get_most_recent_entry()
	
	#lerp position better? damp changes in velocity?
	position = last_entry["position"] + last_entry["velocity"] * (PingService.get_ping(multiplayer.get_unique_id()) / 2.0 + int((Time.get_ticks_msec() - last_entry["time"]) / 1000.0))
