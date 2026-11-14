class_name DialogStyle
extends RefCounted

# Shared touch-friendly look for the built-in AcceptDialog /
# ConfirmationDialog windows. ModalBlur.attach() calls apply() on every
# modal, so each dialog gets it without per-scene wiring. Button size
# lives in the theme (AcceptDialog/constants/buttons_min_*): the dialog
# re-applies those on every theme change, overriding per-button sizes.

const MIN_WIDTH := 560

static func apply(dialog: AcceptDialog) -> void:
	# Size to the content instead of a fixed tall box: a one-line
	# question used to leave a large empty band above the buttons.
	# reset_size() on every open, since a Window never shrinks on its own.
	dialog.min_size = Vector2i(maxi(dialog.min_size.x, MIN_WIDTH), 0)
	dialog.about_to_popup.connect(dialog.reset_size)

# For questions whose "yes" is destructive (quit, resign, discard,
# delete): focus the safe answer when the dialog opens, so a stray
# Enter / d-pad confirm doesn't do the irreversible thing.
static func prefer_cancel(dialog: ConfirmationDialog) -> void:
	dialog.about_to_popup.connect(func() -> void:
		dialog.get_cancel_button().grab_focus.call_deferred())
