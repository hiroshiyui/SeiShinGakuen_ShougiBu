class_name BackGuard
extends RefCounted

# Android's back gesture closes an open OptionButton list *and* still
# delivers NOTIFICATION_WM_GO_BACK_REQUEST to the screen, which then
# ran its own back action (the main menu popped the 終了 dialog).
# Screens call watch() on their OptionButtons in _ready and ask
# swallows_back() at the top of their back handler.

const _META := &"backguard_closed_frame"
const _GRACE_FRAMES := 2

static func watch(option: OptionButton) -> void:
	var popup := option.get_popup()
	popup.popup_hide.connect(func() -> void:
		popup.set_meta(_META, Engine.get_process_frames()))

# True when the back press belongs to a list: it is still open (close
# it) or it closed in the last couple of frames from this same press.
static func swallows_back(options: Array) -> bool:
	var now: int = Engine.get_process_frames()
	for o in options:
		var popup: PopupMenu = (o as OptionButton).get_popup()
		if popup.visible:
			popup.hide()
			return true
		if now - int(popup.get_meta(_META, -100)) <= _GRACE_FRAMES:
			return true
	return false
