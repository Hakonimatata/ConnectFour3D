class_name WebTextField
extends Node
## Chatfeltet på mobil i nettleseren (runde 18): et ekte HTML-tekstfelt ligger over LineEdit-en, så
## tastaturet, markering, autokorrektur, lim inn og emojier virker som på vanlige nettsider. Med Godots
## eget skjermtastatur på nett kunne man noen ganger ikke skrive, ikke markere tekst, og tastaturet
## lukket seg etter hver melding.
## - HTML-feltet er usynlig til man trykker på det (LineEdit-en under vises som vanlig). Trykket treffer
##   HTML-feltet direkte, så telefonen åpner tastaturet (iPhone gjør det bare for et ekte trykk).
## - Mens man skriver, vises HTML-feltet, og teksten i LineEdit-en skjules. Teksten holdes lik i begge.
## - Enter på tastaturet og «Send» sender uten at feltet mister fokus, så tastaturet blir stående. Et
##   usynlig HTML-felt over «Send» tar trykket (et trykk på spillflaten ville lukket tastaturet).
## - Plassen følger LineEdit-en (rulling, tastaturet som skyver UI-et), og klippes av rullelister rundt.
## iPhone (samme grep som Flutter bruker på nett):
## - Ligger et felt med fokus der tastaturet kommer, ruller Safari hele siden opp, og alt hopper. Derfor
##   flyttes feltet ut av skjermen før det får fokus (i trykket), og settes tilbake når UI-et har lagt seg
##   over tastaturet. Med fokus legges det aldri under tastaturet (da heller rett over, med bakgrunn).
## - Drar man i markøren eller markeringen, mister feltet fokus et øyeblikk og får det tilbake. Bare et
##   fokustap uten mål som varer (150 ms), betyr at man er ferdig å skrive. Går fokuset til noe annet
##   (spillflaten, når man trykker på en knapp), er man ferdig med en gang.
## - Mens man skriver, skjules ikke feltet om noe legger seg over (et banner): det ville lukket tastaturet.
## - Endrer den synlige delen av siden seg (tastaturet), får ClientRoot vite det med en gang (viewport_changed).
## Bare på berøringsskjerm i nettleseren. Ellers gjør attach ingenting, og LineEdit-en brukes som før.

## Feltet man skriver i nå (null = ingen). ClientRoot bruker det for å holde feltet over tastaturet.
static var editing: LineEdit
## Tastaturet eller den synlige delen av siden har endret seg (ClientRoot nullstiller det).
static var viewport_changed := false
static var _enabled := -1                  ## -1 = ikke sjekket ennå
static var _callback: JavaScriptObject     ## må leve så lenge siden er oppe
static var _fields := {}                   ## id -> WebTextField
static var _next_id := 1

var edit: LineEdit
var send: Button
var _id := 0
var _placed := ""        ## siste plassering sendt til nettleseren (ingen kall når ingenting er endret)
var _text := ""          ## teksten slik HTML-feltet har den
var _placeholder := ""
var _covered := false    ## noe annet ligger over feltet (sjekkes noen ganger i sekundet, se _is_covered)
var _cover_check := 0.0

const JS := """
(function(){
if (window.c4Text) return;
var canvas = document.getElementById('canvas');
var css = document.createElement('style');
css.textContent = '.c4t{position:absolute;inset:0;width:100%;height:100%;box-sizing:border-box;margin:0;border:0;'
	+ 'outline:none;background:transparent;opacity:0;font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;'
	+ '-webkit-user-select:text;user-select:text;touch-action:manipulation;-webkit-appearance:none;appearance:none}'
	+ '.c4t:focus{opacity:1}';
document.head.appendChild(css);
var fields = {};
var api = { cb: null };
var OFF = 'translate(-9999px,-9999px)';
function call(f, kind) { if (api.cb) api.cb(f ? f.id : 0, kind, f ? f.input.value : ''); }
function focused(f) { return document.activeElement === f.input; }
// Den delen av siden som synes (over tastaturet), i sidekoordinater
function visible() {
	var vv = window.visualViewport;
	return vv ? { top: vv.pageTop, h: vv.height } : { top: window.scrollY, h: window.innerHeight };
}
// Spillet skal aldri være rullet. Bare et felt med fokus kan ha en grunn til det (Godots eget også).
function unscroll() {
	var a = document.activeElement;
	if ((!a || a === document.body || a === canvas) && (window.scrollX || window.scrollY)) window.scrollTo(0, 0);
}
function place(f) {
	var p = f.p, st = f.form.style, bs = f.btn.style;
	if (!p || !p.shown || p.cw <= 0 || p.ch <= 0 || !canvas || !canvas.width) { st.display = 'none'; bs.display = 'none'; return; }
	var r = canvas.getBoundingClientRect();
	var s = r.width / canvas.width, ox = r.left + window.scrollX, oy = r.top + window.scrollY;
	var x = ox + p.x * s, y = oy + p.y * s, w = p.w * s, h = p.h * s;
	var on = focused(f), v = visible();
	st.display = 'block';
	st.left = x + 'px'; st.width = w + 'px'; st.height = h + 'px';
	f.input.style.fontSize = Math.max(16, p.fs * s) + 'px';   // under 16 px zoomer iPhone inn på feltet
	f.input.style.padding = '0 ' + (p.pad * s) + 'px';
	if (on && f.park) {
		// Tastaturet er på vei opp: feltet holdes utenfor skjermen til UI-et har lagt seg over det
		var up = f.park.up || v.h < f.park.h - 80;
		var inside = y >= v.top - 1 && y + h <= v.top + v.h + 1;
		if (!(up && inside) && Date.now() - f.park.t < 1000) {
			st.top = y + 'px'; st.transform = OFF; bs.display = 'none';
			return;
		}
		f.park = null;
	}
	st.transform = '';
	// Med fokus aldri under tastaturet: rakk ikke UI-et å flytte seg, legges feltet rett over det
	var top = on ? Math.max(v.top, Math.min(y, v.top + v.h - h)) : y;
	var moved = Math.abs(top - y) > 1;
	st.top = top + 'px';
	st.background = moved ? f.bg : 'transparent';
	if (moved) {
		st.clipPath = 'none';
	} else {
		var t = Math.max(0, p.cy - p.y) * s, l = Math.max(0, p.cx - p.x) * s;
		var b = Math.max(0, p.y + p.h - p.cy - p.ch) * s, rr = Math.max(0, p.x + p.w - p.cx - p.cw) * s;
		st.clipPath = 'inset(' + t + 'px ' + rr + 'px ' + b + 'px ' + l + 'px)';
	}
	if (on && !moved && p.sw > 0) {
		bs.display = 'block';
		bs.left = (ox + p.sx * s) + 'px'; bs.top = (oy + p.sy * s) + 'px';
		bs.width = (p.sw * s) + 'px'; bs.height = (p.sh * s) + 'px';
	} else {
		bs.display = 'none';
	}
}
function placeAll() { for (var k in fields) place(fields[k]); }
function changed() { placeAll(); call(null, 'viewport'); }
window.addEventListener('resize', changed);
window.addEventListener('scroll', function() { unscroll(); changed(); });
if (window.visualViewport) {
	window.visualViewport.addEventListener('resize', changed);
	window.visualViewport.addEventListener('scroll', changed);
}
api.add = function(id, o) {
	var form = document.createElement('form');
	form.setAttribute('autocomplete', 'off');
	form.style.cssText = 'position:absolute;margin:0;padding:0;z-index:10;display:none;border-radius:8px';
	var input = document.createElement('input');
	input.type = 'text';
	input.className = 'c4t';
	input.setAttribute('enterkeyhint', 'send');
	input.setAttribute('autocomplete', 'off');
	input.setAttribute('autocorrect', 'on');
	input.spellcheck = true;
	input.maxLength = o.max > 0 ? o.max : 524288;
	input.placeholder = o.placeholder;
	input.style.color = o.color;
	input.style.caretColor = o.caret;
	form.appendChild(input);
	var btn = document.createElement('div');
	btn.style.cssText = 'position:absolute;z-index:11;display:none;-webkit-tap-highlight-color:transparent';
	document.body.appendChild(form);
	document.body.appendChild(btn);
	var f = { id: id, form: form, input: input, btn: btn, p: null, bg: o.bg, park: null, tap: null, blur: 0 };
	fields[id] = f;
	form.addEventListener('submit', function(e) { e.preventDefault(); call(f, 'submit'); });
	input.addEventListener('input', function() { call(f, 'input'); });
	input.addEventListener('focus', function() { clearTimeout(f.blur); place(f); call(f, 'focus'); });
	function ended() {
		if (focused(f)) return;
		f.park = null;
		place(f);
		call(f, 'blur');
		unscroll();
	}
	input.addEventListener('blur', function(e) {
		f.btn.style.display = 'none';
		clearTimeout(f.blur);
		// Gikk fokuset til noe annet (spillflaten, et trykk på en knapp), er man ferdig med en gang.
		// Uten mål tar iPhone det bare et øyeblikk når man drar i markøren eller markeringen.
		if (e.relatedTarget) ended(); else f.blur = setTimeout(ended, 150);
	});
	// Trykk på feltet uten fokus: flytt det ut av skjermen og gi det fokus her, i trykket (tastaturet
	// kommer bare for et ekte trykk). Ellers ruller iPhone siden opp for å vise feltet over tastaturet.
	input.addEventListener('touchstart', function(e) {
		f.tap = !focused(f) && e.touches.length === 1 ? { x: e.touches[0].clientX, y: e.touches[0].clientY } : null;
	}, { passive: true });
	input.addEventListener('touchmove', function(e) {
		var t = e.touches[0];
		if (f.tap && t && Math.abs(t.clientX - f.tap.x) + Math.abs(t.clientY - f.tap.y) > 12) f.tap = null;
	}, { passive: true });
	input.addEventListener('touchend', function(e) {
		var tap = f.tap;
		f.tap = null;
		if (!tap || focused(f)) return;
		e.preventDefault();
		var v = visible();
		f.park = { t: Date.now(), h: v.h, up: v.h < window.innerHeight - 100 };
		form.style.transform = OFF;
		input.focus();
		var n = input.value.length;
		try { input.setSelectionRange(n, n); } catch (err) {}
		setTimeout(function() { place(f); }, 1050);
	}, { passive: false });
	input.addEventListener('keydown', function(e) {
		e.stopPropagation();   // tastene er til feltet, ikke til spillet
		if (e.key === 'Escape') input.blur();
	});
	input.addEventListener('keyup', function(e) { e.stopPropagation(); });
	// «Send»: feltet beholder fokus (tastaturet blir stående)
	btn.addEventListener('touchstart', function(e) { e.preventDefault(); }, { passive: false });
	btn.addEventListener('mousedown', function(e) { e.preventDefault(); });
	btn.addEventListener('touchend', function(e) { e.preventDefault(); call(f, 'submit'); }, { passive: false });
	btn.addEventListener('click', function() { call(f, 'submit'); });
};
api.remove = function(id) {
	var f = fields[id];
	if (!f) return;
	f.form.remove(); f.btn.remove();
	delete fields[id];
};
api.place = function(id, p) { var f = fields[id]; if (f) { f.p = p; place(f); } };
api.blur = function(id) {
	var f = fields[id];
	if (!f) return;
	f.park = null;
	if (focused(f)) f.input.blur();
};
api.value = function(id, v) { var f = fields[id]; if (f && f.input.value !== v) f.input.value = v; };
api.placeholder = function(id, v) { var f = fields[id]; if (f) f.input.placeholder = v; };
window.c4Text = api;
})();
"""


## Legger et HTML-felt over edit (og et usynlig over send-knappen). Gir null utenfor mobil-nettleser.
static func attach(p_edit: LineEdit, p_send: Button = null) -> WebTextField:
	if not enabled():
		return null
	var f := WebTextField.new()
	f.edit = p_edit
	f.send = p_send
	p_edit.add_child(f)
	return f


static func enabled() -> bool:
	if _enabled < 0:
		_enabled = 1 if OS.has_feature("web") and bool(JavaScriptBridge.eval(
			"(navigator.maxTouchPoints || 0) > 0 || 'ontouchstart' in window", true)) else 0
	return _enabled == 1


static func is_editing(e: LineEdit) -> bool:
	return editing != null and editing == e


## Avslutter skrivingen i e, så tastaturet lukkes (f.eks. når chatten lukkes).
static func stop(e: LineEdit) -> void:
	if editing == e:
		editing = null
	for f: WebTextField in _fields.values():
		if f.edit == e:
			JavaScriptBridge.eval("c4Text.blur(%d)" % f._id, true)
			f._set_editing(false)


func _ready() -> void:
	if _callback == null:
		JavaScriptBridge.eval(JS, true)
		var api := JavaScriptBridge.get_interface("c4Text")
		if api == null:   # noe gikk galt i nettleseren: bruk Godots eget felt som før
			_enabled = 0
			queue_free()
			return
		_callback = JavaScriptBridge.create_callback(_on_js)
		api.cb = _callback
	_id = _next_id
	_next_id += 1
	_fields[_id] = self
	_placeholder = tr(edit.placeholder_text)
	_text = edit.text
	JavaScriptBridge.eval("c4Text.add(%d, %s); c4Text.value(%d, %s)" % [_id, JSON.stringify({
		"placeholder": _placeholder, "max": edit.max_length,
		"color": "#" + edit.get_theme_color("font_color").to_html(false),
		"caret": "#" + UI.ACCENT_HOVER.to_html(false),
		"bg": "#" + _background(edit).to_html(false),   # når feltet må legges rett over tastaturet
	}), _id, JSON.stringify(_text)], true)


static func _background(e: LineEdit) -> Color:
	var normal := e.get_theme_stylebox("normal")
	return (normal as StyleBoxFlat).bg_color if normal is StyleBoxFlat else UI.BG_BOTTOM


func _exit_tree() -> void:
	if _id == 0:
		return
	JavaScriptBridge.eval("c4Text.remove(%d)" % _id, true)
	_fields.erase(_id)
	if editing == edit:
		editing = null


func _process(delta: float) -> void:
	if _id == 0:
		return
	_cover_check -= delta
	if _cover_check <= 0.0:
		_cover_check = 0.15
		# Mens man skriver, blir feltet liggende (å skjule det ville lukket tastaturet)
		_covered = editing != edit and edit.is_visible_in_tree() and _is_covered(edit)
	var shown := edit.is_visible_in_tree() and edit.editable and not _covered
	var p := { "shown": shown }
	if shown:
		var scale := maxf(edit.get_window().content_scale_factor, 0.01)
		var r := _screen_rect(edit)
		var clip := _clip_rect(edit, r)
		p.merge({ "x": r.position.x, "y": r.position.y, "w": r.size.x, "h": r.size.y,
			"cx": clip.position.x, "cy": clip.position.y, "cw": clip.size.x, "ch": clip.size.y,
			"fs": edit.get_theme_font_size("font_size") * scale,
			"pad": edit.get_theme_stylebox("normal").get_margin(SIDE_LEFT) * scale })
		var s := _screen_rect(send) if send != null and send.is_visible_in_tree() and not send.disabled else Rect2()
		p.merge({ "sx": s.position.x, "sy": s.position.y, "sw": s.size.x, "sh": s.size.y })
	var placed := JSON.stringify(p)
	if placed != _placed:
		_placed = placed
		JavaScriptBridge.eval("c4Text.place(%d, %s)" % [_id, placed], true)
	if edit.text != _text:   # endret i Godot (f.eks. tømt etter sending)
		_text = edit.text
		JavaScriptBridge.eval("c4Text.value(%d, %s)" % [_id, JSON.stringify(_text)], true)
	var placeholder := tr(edit.placeholder_text)
	if placeholder != _placeholder:   # f.eks. byttet kanal i chatten
		_placeholder = placeholder
		JavaScriptBridge.eval("c4Text.placeholder(%d, %s)" % [_id, JSON.stringify(placeholder)], true)


## Fra nettleseren: [id, hva, teksten]. Kjøres midt i nettleserens hendelse (trykket, tastetrykket).
static func _on_js(args: Array) -> void:
	if args.size() < 3:
		return
	if str(args[1]) == "viewport":   # tastaturet kom eller gikk, eller siden ble rullet
		viewport_changed = true
		return
	var f: WebTextField = _fields.get(int(args[0]))
	if f == null or not is_instance_valid(f.edit):
		return
	var text := str(args[2])
	if f.edit.max_length > 0:
		text = text.substr(0, f.edit.max_length)
	f._text = text
	if f.edit.text != text:
		f.edit.text = text
	match str(args[1]):
		"focus":
			if f.edit.has_focus():
				f.edit.release_focus()   # Godots eget skjermtastatur skal ikke slåss med HTML-feltet
			f._set_editing(true)
		"blur": f._set_editing(false)
		"submit": f.edit.text_submitted.emit(text)


## Mens HTML-feltet vises: LineEdit-en ser ut som et felt med fokus, men uten egen tekst under.
func _set_editing(on: bool) -> void:
	if on:
		editing = edit
		for c in ["font_color", "font_placeholder_color", "caret_color"]:
			edit.add_theme_color_override(c, Color.TRANSPARENT)
		edit.add_theme_stylebox_override("normal", edit.get_theme_stylebox("focus"))
	else:
		if editing == edit:
			editing = null
		for c in ["font_color", "font_placeholder_color", "caret_color"]:
			edit.remove_theme_color_override(c)
		edit.remove_theme_stylebox_override("normal")


## Rektangelet i vinduspiksler (det nettleserens lerret har).
static func _screen_rect(c: Control) -> Rect2:
	return c.get_viewport().get_final_transform() * c.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, c.size)


## Ligger noe annet over feltet (f.eks. resultatet etter et parti over chatten, eller et banner)? Da skal
## ikke HTML-feltet ta trykkene. Samme valg som Godot gjør for et trykk: øverst først, uten de usynlige
## og dem som slipper musen gjennom.
static func _is_covered(c: Control) -> bool:
	var r := c.get_global_rect()
	var mid := r.get_center()
	for point in [mid, Vector2(r.position.x + 6.0, mid.y), Vector2(r.end.x - 6.0, mid.y)]:
		var top := _pick(c.get_tree().root, point)
		if top != null and top != c:
			return true
	return false


## Kontrollen et trykk på point ville truffet (de siste barna tegnes øverst).
static func _pick(n: Node, point: Vector2) -> Control:
	if (n is CanvasItem and not (n as CanvasItem).visible) or (n is CanvasLayer and not (n as CanvasLayer).visible):
		return null
	var c := n as Control
	if c != null and c.clip_contents and not c.get_global_rect().has_point(point):
		return null
	for i in range(n.get_child_count() - 1, -1, -1):
		var hit := _pick(n.get_child(i), point)
		if hit != null:
			return hit
	if c != null and c.mouse_filter != Control.MOUSE_FILTER_IGNORE and c.get_global_rect().has_point(point):
		return c
	return null


## Delen av r som synes: klippet av rullelister og andre som klipper innholdet.
static func _clip_rect(c: Control, r: Rect2) -> Rect2:
	var n := c.get_parent()
	while n != null:
		if n is Control and (n as Control).clip_contents:
			r = r.intersection(_screen_rect(n as Control))
		n = n.get_parent()
	return r
