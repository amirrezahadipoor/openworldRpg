extends Node
## The one owner of `get_tree().paused` (audit C6).
##
## Before this, six screens each wrote the flag directly: opening the inventory
## paused the game, closing it unpaused — even if the pause menu was still open
## underneath. The settings and travel screens worked around it with a private
## `_was_paused` copy, which only helped the one case their author thought of
## (open the settings *from* the pause menu) and did nothing for the dialogue box
## finishing while a shop was open, or the death screen appearing under the pause
## menu.
##
## The state is a set of holds rather than a boolean. Anything that needs the
## world to stand still — a menu, a conversation, the death screen, the ending —
## holds it while it is up and releases it when it is done, and the tree is paused
## exactly while at least one hold is outstanding. Holds are keyed by the object
## that wants them, so a hold can never be left behind by a freed screen: a node
## that dies without releasing (scene change, quit to title, a mid-conversation
## load) is no longer valid, and pruning drops it on the next query.

var _holds: Dictionary = {}   # Object -> tag (String), for messages and tests


func _ready() -> void:
	# The manager itself must keep running while the tree is paused, or nothing
	# would ever be able to release a hold.
	process_mode = Node.PROCESS_MODE_ALWAYS


func hold(holder: Object, tag: String = "ui") -> void:
	if holder == null:
		return
	_holds[holder] = tag
	_apply()


func release(holder: Object) -> void:
	if holder == null:
		_purge()
		_apply()
		return
	_holds.erase(holder)
	_apply()


func release_all() -> void:
	## Leaving the run entirely (load a save, quit to title): nothing that held the
	## world still exists, and the next scene must start live.
	_holds.clear()
	_apply()


func is_paused() -> bool:
	_purge()
	return not _holds.is_empty()


func holders() -> Array:
	## The tags currently holding the world still, in no particular order.
	_purge()
	return _holds.values()


func holder_count() -> int:
	_purge()
	return _holds.size()


func _purge() -> void:
	for k in _holds.keys():
		if not is_instance_valid(k):
			_holds.erase(k)


func _apply() -> void:
	var tree := get_tree()
	if tree != null:
		tree.paused = is_paused()
