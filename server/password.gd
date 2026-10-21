class_name Password
extends RefCounted
## Passord lagres aldri i klartekst, bare som tilfeldig salt + PBKDF2-HMAC-SHA256.
## Mange runder gjør det tregt å gjette passord selv om noen får tak i users.json.

const ALGO := "pbkdf2-sha256"
const ITERATIONS := 60_000
const MIN_LENGTH := 8

static var _crypto := Crypto.new()


## Lager en lagringsklar hash: { algo, iterations, salt, hash } (base64).
static func make(password: String, iterations := ITERATIONS) -> Dictionary:
	var salt := _crypto.generate_random_bytes(16)
	var dk := pbkdf2(password.to_utf8_buffer(), salt, iterations)
	return { "algo": ALGO, "iterations": iterations, "salt": Marshalls.raw_to_base64(salt),
		"hash": Marshalls.raw_to_base64(dk) }


static func verify(password: String, record: Variant) -> bool:
	if not record is Dictionary or record.get("algo") != ALGO:
		return false
	var iterations := int(record.get("iterations", 0))
	if iterations < 1:
		return false
	var salt := Marshalls.base64_to_raw(str(record.get("salt", "")))
	var expected := Marshalls.base64_to_raw(str(record.get("hash", "")))
	var actual := pbkdf2(password.to_utf8_buffer(), salt, iterations)
	return _equal(actual, expected)


## PBKDF2-HMAC-SHA256 med én blokk (32 byte). Testet mot standard testvektorer.
static func pbkdf2(password: PackedByteArray, salt: PackedByteArray, iterations: int) -> PackedByteArray:
	var block := salt.duplicate()
	block.append_array(PackedByteArray([0, 0, 0, 1]))
	var u := _crypto.hmac_digest(HashingContext.HASH_SHA256, password, block)
	# XOR av alle rundene, regnet som fire 64-bits tall for fart.
	var t := [u.decode_s64(0), u.decode_s64(8), u.decode_s64(16), u.decode_s64(24)]
	for i in iterations - 1:
		u = _crypto.hmac_digest(HashingContext.HASH_SHA256, password, u)
		t[0] ^= u.decode_s64(0)
		t[1] ^= u.decode_s64(8)
		t[2] ^= u.decode_s64(16)
		t[3] ^= u.decode_s64(24)
	var out := PackedByteArray()
	out.resize(32)
	for k in 4:
		out.encode_s64(k * 8, t[k])
	return out


## Sammenligning som tar like lang tid uansett hvor bytene er ulike.
static func _equal(a: PackedByteArray, b: PackedByteArray) -> bool:
	if a.size() != b.size():
		return false
	var diff := 0
	for i in a.size():
		diff |= a[i] ^ b[i]
	return diff == 0
