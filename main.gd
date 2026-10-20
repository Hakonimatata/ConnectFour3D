extends Node
## Inngangspunkt. Starter serveren eller klienten.
##   Server:  godot --headless -- --server   (eller en «dedicated server»-eksport)
##   Klient:  alt annet


func _ready() -> void:
	if OS.has_feature("dedicated_server") or "--server" in OS.get_cmdline_user_args():
		add_child(ServerMain.new())
	else:
		add_child(ClientRoot.new())
