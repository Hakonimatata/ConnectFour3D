extends TestCase
## Tester for profilbilder (net/avatar_data.gd).


func _png(w: int, h: int) -> PackedByteArray:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.6, 0.9))
	img.fill_rect(Rect2i(w / 2 - 5, 0, 10, h), Color.RED)   # rød stripe midt på
	return img.save_png_to_buffer()


func test_from_bytes_makes_small_square_jpeg() -> void:
	var b64 := AvatarData.from_bytes(_png(300, 200))
	check(b64 != "", "skal lage et bilde")
	check(b64.length() < AvatarData.MAX_B64, "skal være lite")
	var img := Image.new()
	check_eq(img.load_jpg_from_buffer(Marshalls.base64_to_raw(b64)), OK)
	check_eq(img.get_size(), Vector2i(AvatarData.SIZE, AvatarData.SIZE))
	# Beskåret fra midten: den røde stripen skal fortsatt være i midten.
	var mid := img.get_pixel(AvatarData.SIZE / 2, AvatarData.SIZE / 2)
	check(mid.r > 0.6 and mid.b < 0.4, "midten skal være rød, var %s" % str(mid))
	check(AvatarData.is_valid(b64))
	check(AvatarData.to_texture(b64) != null)


func test_rejects_garbage() -> void:
	check_eq(AvatarData.from_bytes("hei".to_utf8_buffer()), "")
	check_eq(AvatarData.from_bytes(PackedByteArray()), "")
	check(not AvatarData.is_valid(""))
	check(not AvatarData.is_valid(5))
	check(not AvatarData.is_valid("A".repeat(AvatarData.MAX_B64 + 4)))
	check(not AvatarData.is_valid(Marshalls.raw_to_base64("ikke et bilde i det hele tatt".to_utf8_buffer())))
