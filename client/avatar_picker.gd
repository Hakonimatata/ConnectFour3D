class_name AvatarPicker
extends Node
## Lar brukeren velge et bilde fra enheten.
## Web: nettleserens filvelger (på mobil også galleri/kamera). Bildet beskjæres og
##      forminskes i nettleseren før det sendes inn i spillet, så store mobilbilder går fort.
## PC:  operativsystemets egen filvelger.
##
## iPhone (Safari og Chrome, som begge bruker WebKit) åpner bare filvelgeren midt i selve trykket.
## Godot behandler trykket først i neste bilde, og da er det for sent. Derfor kalles arm() når
## fingeren treffer knappen (button_down), og nettleseren åpner velgeren når fingeren slippes
## (touchend/mouseup). Flyttet fingeren seg (scrolling), åpnes den ikke. pick() (pressed) er reserven
## for nettlesere som tillater det litt etter trykket (Android, PC).

signal picked(bytes: PackedByteArray)

const WEB_JS := """
(function () {
	if (window.godotAvatar) return;
	var a = window.godotAvatar = { armed: 0, opened: 0, x: 0, y: 0, input: null };
	a.open = function () {
		a.armed = 0;
		a.opened = Date.now();
		if (a.input) a.input.remove();
		var input = a.input = document.createElement('input');
		input.type = 'file';
		input.accept = 'image/*';
		// Utenfor skjermen, men i dokumentet (iOS sender ellers ikke alltid «change»)
		input.style.cssText = 'position:fixed;left:-1000px;top:0;opacity:0;';
		document.body.appendChild(input);
		input.onchange = function () {
			var file = input.files && input.files[0];
			input.remove();
			a.input = null;
			if (!file) return;
			var img = new Image();
			img.onload = function () {
				var side = Math.min(img.width, img.height);
				var canvas = document.createElement('canvas');
				canvas.width = canvas.height = %d;
				canvas.getContext('2d').drawImage(img, (img.width - side) / 2, (img.height - side) / 2,
					side, side, 0, 0, %d, %d);
				if (window.godotAvatarPicked) window.godotAvatarPicked(canvas.toDataURL('image/jpeg', 0.85));
				URL.revokeObjectURL(img.src);
			};
			img.src = URL.createObjectURL(file);
		};
		input.click();
	};
	function down(x, y) { a.x = x; a.y = y; }
	function up(x, y) {
		if (!a.armed || Date.now() - a.armed > 3000) return;
		if (Math.abs(x - a.x) > 20 || Math.abs(y - a.y) > 20) { a.armed = 0; return; }   // scrollet, ikke trykk
		a.open();
	}
	document.addEventListener('touchstart', function (e) { var t = e.changedTouches[0]; down(t.clientX, t.clientY); }, true);
	document.addEventListener('touchend', function (e) { var t = e.changedTouches[0]; up(t.clientX, t.clientY); }, true);
	document.addEventListener('mousedown', function (e) { down(e.clientX, e.clientY); }, true);
	document.addEventListener('mouseup', function (e) { up(e.clientX, e.clientY); }, true);
})();
"""

var _js_callback: JavaScriptObject   # må holdes i live mens nettleseren venter


func _ready() -> void:
	if OS.has_feature("web"):
		_setup_web()   # lytterne må være på plass før første trykk


## Kalles når fingeren/musen treffer knappen. På web åpnes velgeren når den slippes.
func arm() -> void:
	if OS.has_feature("web"):
		_setup_web()
		JavaScriptBridge.eval("window.godotAvatar.armed = Date.now();", true)


func pick() -> void:
	if OS.has_feature("web"):
		_setup_web()
		# Åpnet allerede da fingeren ble sluppet (arm)? Ellers prøv nå (virker på Android og PC).
		JavaScriptBridge.eval("if (Date.now() - window.godotAvatar.opened > 1500) window.godotAvatar.open();", true)
	else:
		_pick_desktop()


func _setup_web() -> void:
	if _js_callback == null:
		_js_callback = JavaScriptBridge.create_callback(_on_web_result)
		JavaScriptBridge.get_interface("window").godotAvatarPicked = _js_callback
		JavaScriptBridge.eval(WEB_JS % [AvatarData.SIZE, AvatarData.SIZE, AvatarData.SIZE], true)


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
