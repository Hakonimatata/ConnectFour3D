extends Node
## Inngangspunkt. Starter serveren eller klienten.
##   Server:  godot --headless -- --server   (eller en «dedicated server»-eksport)
##   Klient:  alt annet


func _ready() -> void:
	if OS.has_feature("dedicated_server") or "--server" in OS.get_cmdline_user_args():
		Engine.max_fps = 60   # ellers går hovedløkken så fort den kan og bruker en hel CPU-kjerne
		var server := ServerMain.new()
		server.standalone = true
		add_child(server)
	else:
		add_child(ClientRoot.new())
