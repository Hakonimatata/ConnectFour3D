class_name AvatarPicker
extends Node
## Lar brukeren velge et bilde fra enheten.
## Web: nettleserens filvelger (på mobil også galleri/kamera). Bildet beskjæres og
##      forminskes i nettleseren før det sendes inn i spillet, så store mobilbilder går fort.
## PC:  operativsystemets egen filvelger.

signal picked(bytes: PackedByteArray)

var _js_callback: JavaScriptObject   # må holdes i live mens nettleseren venter


func pick() -> void:
	if OS.has_feature("web"):
		_pick_web()
	else:
		_pick_desktop()


func _pick_web() -> void:
	_js_callback = JavaScriptBridge.create_callback(_on_web_result)
	var window := JavaScriptBridge.get_interface("window")
	window.godotAvatarPicked = _js_callback
	JavaScriptBridge.eval("""
	(function () {
		var input = document.createElement('input');
		input.type = 'file';
		input.accept = 'image/*';
		input.onchange = function () {
			var file = input.files && input.files[0];
			if (!file) return;
			var img = new Image();
			img.onload = function () {
				var side = Math.min(img.width, img.height);
				var canvas = document.createElement('canvas');
				canvas.width = canvas.height = %d;
				canvas.getContext('2d').drawImage(img, (img.width - side) / 2, (img.height - side) / 2,
					side, side, 0, 0, %d, %d);
				window.godotAvatarPicked(canvas.toDataURL('image/jpeg', 0.85));
				URL.revokeObjectURL(img.src);
			};
			img.src = URL.createObjectURL(file);
		};
		input.click();
	})();
	""" % [AvatarData.SIZE, AvatarData.SIZE, AvatarData.SIZE], true)


func _on_web_result(args: Array) -> void:
	var data_url := str(args[0]) if not args.is_empty() else ""
	var comma := data_url.find(",")
	if comma < 0:
		return
	picked.emit(Marshalls.base64_to_raw(data_url.substr(comma + 1)))


func _pick_desktop() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.use_native_dialog = true
	dialog.title = tr("Velg profilbilde")
	dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; " + tr("Bilder")])
	dialog.file_selected.connect(func(path: String) -> void:
		picked.emit(FileAccess.get_file_as_bytes(path))
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_ratio(0.6)
