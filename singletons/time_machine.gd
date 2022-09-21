extends Object
class_name TimeMachine

#30 entries, half a second
var max_time_machine_entries : int = 30

#might be slight issues with interpolations near recently (less than ping) spawned/destroyed objects

#best use case is for hitreg to match to the gamestate of what the client sees (ping amount of time in the past)

#first object in array (0) is oldest value
#last object in array is newest
var time_machine_dictionary : Dictionary = {
	#time : {
#		time : int
#		property : value
#	}
}

var network_buffer : Array = []

func _init(max_entries : int = 30) -> void:
	max_time_machine_entries = max_entries

func set_property(property : StringName, value : Variant) -> void:
	get_most_recent_entry()[property] = value

func create_entry() -> void:
	var current_time : int = Time.get_ticks_msec()
	#add time machine entry for current time
	time_machine_dictionary[current_time] = {"time" : current_time}
	
	#clear old time machine entries
	#Dictionary.keys() returns keys in order of most recently added
	while time_machine_dictionary.size() > max_time_machine_entries:
		time_machine_dictionary.erase(get_timestamps()[0])

func append_to_network_buffer() -> void:
	network_buffer.append(get_most_recent_entry())

func clear_network_buffer() -> void:
	network_buffer = []

func submit_entry(time : int, entry : Dictionary) -> void:
	if !get_most_recent_entry()["time"] > time:
		entry["time"] = time
		time_machine_dictionary[time] = entry
	
	#clear old time machine entries
	#Dictionary.keys() returns keys in order of most recently added
	while time_machine_dictionary.size() > max_time_machine_entries:
		time_machine_dictionary.erase(get_timestamps()[0])

#this requires an exact match
func get_entry(time : int) -> Dictionary:
	return time_machine_dictionary[time]

func get_most_recent_entry() -> Dictionary:
	return time_machine_dictionary[get_timestamps()[-1]]

func get_timestamps() -> PackedInt64Array:
	return PackedInt64Array(time_machine_dictionary.keys())

func get_closest_timestamp_after(time : int) -> int:
	var timestamps = get_timestamps()
	
	#too new
	if time >= timestamps[-1]:
		#return most recent timestamp
		return timestamps[-1]
	#too old
	if time < timestamps[0]:
		#return oldest timestamp
		return timestamps[0]
	
	var size : int = timestamps.size() - 1
	for index in size:
		#travel from the end of the array towards the beginning
		#largest entries are at the end of the array
		if timestamps[index] >= time:
			return timestamps[index]
	
	return timestamps[-1]
func get_closest_timestamp_before(time : int) -> int:
	var timestamps = get_timestamps()
	
	#too new
	if time > timestamps[-1]:
		#return most recent timestamp
		return timestamps[-1]
	#too old
	if time <= timestamps[0]:
		#return oldest timestamp
		return timestamps[0]
	
	var size : int = timestamps.size() - 1
	for index in size:
		var key : int = size - index
		#travel from the end of the array towards the beginning
		#largest entries are at the end of the array
		if timestamps[key] < time:
			return timestamps[key]
	
	return timestamps[0]

func get_timestamps_after(time : int) -> PackedInt64Array:
	var timestamp_after : int = get_closest_timestamp_after(time)
	var timestamps : Array = get_timestamps()
	var index : int = timestamps.find(timestamp_after)
	
	return PackedInt64Array(timestamps.slice(index))
func get_timestamps_before(time : int) -> PackedInt64Array:
	var timestamp_before : int = get_closest_timestamp_before(time)
	var timestamps : Array = get_timestamps()
	var index : int = timestamps.find(timestamp_before)
	
	return PackedInt64Array(timestamps.slice(0, index))

#for use with datatypes that can't be interpolated
func get_property(property : StringName, seconds_in_past : float) -> Variant:
	#find 2 closest entries
	var time : int = Time.get_ticks_msec() - int(seconds_in_past * 1000.0)
	var timestamp : int = get_closest_timestamp_before(time)
	return time_machine_dictionary[timestamp][property]

func get_property_interpolated(property : StringName, seconds_in_past : float) -> Variant:
	#find 2 closest entries
	var time : int = Time.get_ticks_msec() - int(seconds_in_past * 1000.0)
	var timestamp_before : int = get_closest_timestamp_before(time)
	var timestamp_after : int = get_closest_timestamp_after(time)
	
	var interpolation_factor : float = remap(time, timestamp_before, timestamp_after, 0.0, 1.0)
	var before_value = time_machine_dictionary[timestamp_before][property]
	var after_value = time_machine_dictionary[timestamp_after][property]
	
	if before_value == after_value:
		return before_value
	else:
		return lerp(before_value, after_value, interpolation_factor)

