class_name AvatarData
extends RefCounted
## Profilbilder: et lite, kvadratisk JPEG-bilde lagret som base64-tekst.
## Brukes av klienten (lage og vise) og serveren (sjekke før det sendes videre).

const SIZE := 112                 ## Bredde og høyde i piksler
const MAX_B64 := 24_000           ## Maks lengde på base64-teksten (~18 KB bilde)
const MAX_SOURCE_PIXELS := 4096   ## Større kildebilder avvises (bruk nettleserens forminsking)

static var _textures: Dictionary = {}   ## hash -> ImageTexture (cache)


## Lager profilbilde-tekst fra en bildefil (PNG, JPEG eller WebP).
## Beskjærer til kvadrat fra midten og skalerer ned. Gir "" hvis bildet ikke kan leses.
static func from_bytes(bytes: PackedByteArray) -> String:
	var img := _load(bytes)
	if img == null:
		return ""
	if img.get_width() > MAX_SOURCE_PIXELS or img.get_height() > MAX_SOURCE_PIXELS:
		return ""
	var side := mini(img.get_width(), img.get_height())
	img = img.get_region(Rect2i((img.get_width() - side) / 2, (img.get_height() - side) / 2, side, side))
	img.convert(Image.FORMAT_RGB8)
	img.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS if side > SIZE else Image.INTERPOLATE_BILINEAR)
	var b64 := Marshalls.raw_to_base64(img.save_jpg_to_buffer(0.85))
	return b64 if b64.length() <= MAX_B64 else ""


## Er teksten et gyldig, lite profilbilde? (Serveren bruker denne før den deler bildet.)
static func is_valid(b64: Variant) -> bool:
	if not b64 is String or b64 == "" or (b64 as String).length() > MAX_B64:
		return false
	var img := _load(Marshalls.base64_to_raw(b64))
	return img != null and img.get_width() <= 256 and img.get_height() <= 256


## Tekstur til visning, eller null. Bildene caches så de ikke dekodes hver gang.
static func to_texture(b64: String) -> Texture2D:
	if b64 == "":
		return null
	var key := b64.hash()
	if not _textures.has(key):
		var img := _load(Marshalls.base64_to_raw(b64))
		_textures[key] = ImageTexture.create_from_image(img) if img != null else null
	return _textures[key]


static func _load(bytes: PackedByteArray) -> Image:
	if bytes.size() < 12:
		return null
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if bytes[0] == 0x89 and bytes[1] == 0x50:                 # PNG
		err = img.load_png_from_buffer(bytes)
	elif bytes[0] == 0xFF and bytes[1] == 0xD8:               # JPEG
		err = img.load_jpg_from_buffer(bytes)
	elif bytes.slice(0, 4).get_string_from_ascii() == "RIFF" and bytes.slice(8, 12).get_string_from_ascii() == "WEBP":
		err = img.load_webp_from_buffer(bytes)
	if err != OK or img.is_empty():
		return null
	return img
