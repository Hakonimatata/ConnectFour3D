class_name QrCode
extends RefCounted
## QR-kode (runde 18) til lenken på storskjermen, så telefonene kan skanne seg inn i turneringen.
## Bare det som trengs: byte-modus (UTF-8), feilretting M (tåler at rundt 15 % er ødelagt), versjon
## 1–10 (opptil 213 byte), og masken med lavest straff, slik standarden (ISO/IEC 18004) beskriver.
## Samme oppbygning som Nayukis referanseimplementasjon.
## encode() gir modulene rad for rad (1 = mørk), uten den lyse kanten rundt. Tegn minst 4 moduler
## lyst rundt koden (se QrView).

const TOTAL := [26, 44, 70, 100, 134, 172, 196, 242, 292, 346]    ## kodeord per versjon (1–10)
const ECC_PER_BLOCK := [10, 16, 26, 18, 24, 16, 18, 22, 22, 26]   ## feilrettingsord per blokk, nivå M
const BLOCKS := [1, 1, 1, 2, 2, 4, 4, 4, 5, 5]
const ALIGN := [[], [6, 18], [6, 22], [6, 26], [6, 30], [6, 34], [6, 22, 38], [6, 24, 42], [6, 26, 46], [6, 28, 50]]


## Modulene (size × size, rad for rad), eller tom hvis teksten er for lang.
static func encode(text: String) -> PackedByteArray:
	var data := text.to_utf8_buffer()
	var version := 0
	for v in range(1, 11):
		if 4 + (8 if v < 10 else 16) + data.size() * 8 <= _data_codewords(v) * 8:
			version = v
			break
	if version == 0:
		return PackedByteArray()
	var g := _Grid.new(17 + 4 * version)
	_draw_functions(g, version)
	_draw_codewords(g, _add_ecc(_data_bytes(data, version), version))
	var best := 0
	var best_score := 1 << 30
	for mask in 8:
		_apply_mask(g, mask)
		_draw_format(g, mask)
		var score := _penalty(g)
		if score < best_score:
			best = mask
			best_score = score
		_apply_mask(g, mask)   # maskering er sin egen invers
	_apply_mask(g, best)
	_draw_format(g, best)
	return g.m


static func size_of(modules: PackedByteArray) -> int:
	return roundi(sqrt(modules.size()))


## Feilrettingsordene (Reed–Solomon) for data, n stykker.
static func rs_ecc(data: PackedByteArray, n: int) -> PackedByteArray:
	return _rs_remainder(data, _rs_divisor(n))


## Formatinformasjonen (nivå M og masken) med BCH-kode, 15 biter.
static func format_bits(mask: int) -> int:
	var data := mask   # nivå M = 00
	var rem := data
	for i in 10:
		rem = (rem << 1) ^ ((rem >> 9) * 0x537)
	return ((data << 10) | rem) ^ 0x5412


## Versjonsinformasjonen (versjon 7 og høyere), 18 biter.
static func version_bits(v: int) -> int:
	var rem := v
	for i in 12:
		rem = (rem << 1) ^ ((rem >> 11) * 0x1F25)
	return (v << 12) | rem


class _Grid:
	var size := 0
	var m := PackedByteArray()   ## 1 = mørk
	var f := PackedByteArray()   ## 1 = funksjonsmodul (søkemønstre, tidslinjer, format), ikke data

	func _init(n: int) -> void:
		size = n
		m.resize(n * n)
		m.fill(0)
		f.resize(n * n)
		f.fill(0)

	func fn(x: int, y: int, dark: bool) -> void:
		m[y * size + x] = 1 if dark else 0
		f[y * size + x] = 1


static func _data_codewords(v: int) -> int:
	return TOTAL[v - 1] - ECC_PER_BLOCK[v - 1] * BLOCKS[v - 1]


## Modus (byte), lengden, dataene, avslutning og fyll (0xEC, 0x11) til alle dataordene er brukt.
static func _data_bytes(data: PackedByteArray, v: int) -> PackedByteArray:
	var bits: Array[int] = []
	_push(bits, 0b0100, 4)
	_push(bits, data.size(), 8 if v < 10 else 16)
	for b in data:
		_push(bits, b, 8)
	var cap := _data_codewords(v) * 8
	_push(bits, 0, mini(4, cap - bits.size()))
	_push(bits, 0, (8 - bits.size() % 8) % 8)
	var out := PackedByteArray()
	for i in range(0, bits.size(), 8):
		var byte := 0
		for j in 8:
			byte = (byte << 1) | bits[i + j]
		out.append(byte)
	var pad := 0xEC
	while out.size() < _data_codewords(v):
		out.append(pad)
		pad = 0x11 if pad == 0xEC else 0xEC
	return out


static func _push(bits: Array[int], value: int, count: int) -> void:
	for i in range(count - 1, -1, -1):
		bits.append((value >> i) & 1)


## Deler dataene i blokker, legger feilretting på hver, og fletter dem sammen.
static func _add_ecc(data: PackedByteArray, v: int) -> PackedByteArray:
	var blocks: int = BLOCKS[v - 1]
	var ecc_len: int = ECC_PER_BLOCK[v - 1]
	var raw: int = TOTAL[v - 1]
	var short := blocks - raw % blocks
	var short_len := raw / blocks
	var div := _rs_divisor(ecc_len)
	var all: Array[PackedByteArray] = []
	var k := 0
	for i in blocks:
		var n := short_len - ecc_len + (0 if i < short else 1)
		var block := data.slice(k, k + n)
		k += n
		var ecc := _rs_remainder(block, div)
		if i < short:
			block.append(0)   # plassholder, så alle blokkene er like lange (hoppes over under)
		block.append_array(ecc)
		all.append(block)
	var out := PackedByteArray()
	for i in all[0].size():
		for j in blocks:
			if i != short_len - ecc_len or j >= short:
				out.append(all[j][i])
	return out


static func _rs_divisor(degree: int) -> PackedByteArray:
	var r := PackedByteArray()
	r.resize(degree)
	r.fill(0)
	r[degree - 1] = 1
	var root := 1
	for i in degree:
		for j in degree:
			r[j] = _gf_mul(r[j], root)
			if j + 1 < degree:
				r[j] = r[j] ^ r[j + 1]
		root = _gf_mul(root, 0x02)
	return r


static func _rs_remainder(data: PackedByteArray, div: PackedByteArray) -> PackedByteArray:
	var r := PackedByteArray()
	r.resize(div.size())
	r.fill(0)
	for b in data:
		var factor := b ^ r[0]
		r.remove_at(0)
		r.append(0)
		for i in div.size():
			r[i] = r[i] ^ _gf_mul(div[i], factor)
	return r


## Multiplikasjon i GF(256) med polynomet x⁸ + x⁴ + x³ + x² + 1.
static func _gf_mul(x: int, y: int) -> int:
	var z := 0
	for i in range(7, -1, -1):
		z = (z << 1) ^ ((z >> 7) * 0x11D)
		z ^= ((y >> i) & 1) * x
	return z


## Tidslinjene, de tre søkemønstrene, justeringsmønstrene, plassen til formatet og versjonen.
static func _draw_functions(g: _Grid, v: int) -> void:
	var n := g.size
	for i in n:
		g.fn(6, i, i % 2 == 0)
		g.fn(i, 6, i % 2 == 0)
	for c in [Vector2i(3, 3), Vector2i(n - 4, 3), Vector2i(3, n - 4)]:
		for dy in range(-4, 5):
			for dx in range(-4, 5):
				var x: int = c.x + dx
				var y: int = c.y + dy
				if x >= 0 and x < n and y >= 0 and y < n:
					var d := maxi(absi(dx), absi(dy))
					g.fn(x, y, d != 2 and d != 4)
	var pos: Array = ALIGN[v - 1]
	for i in pos.size():
		for j in pos.size():
			if (i == 0 and j == 0) or (i == 0 and j == pos.size() - 1) or (i == pos.size() - 1 and j == 0):
				continue   # der søkemønstrene står
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					g.fn(int(pos[i]) + dx, int(pos[j]) + dy, maxi(absi(dx), absi(dy)) != 1)
	_draw_format(g, 0)   # reserverer plassen; den valgte masken tegnes til slutt
	if v >= 7:
		var bits := version_bits(v)
		for i in 18:
			var dark := ((bits >> i) & 1) == 1
			g.fn(n - 11 + i % 3, i / 3, dark)
			g.fn(i / 3, n - 11 + i % 3, dark)


static func _draw_format(g: _Grid, mask: int) -> void:
	var bits := format_bits(mask)
	var n := g.size
	var bit := func(i: int) -> bool: return ((bits >> i) & 1) == 1
	for i in 6:
		g.fn(8, i, bit.call(i))
	g.fn(8, 7, bit.call(6))
	g.fn(8, 8, bit.call(7))
	g.fn(7, 8, bit.call(8))
	for i in range(9, 15):
		g.fn(14 - i, 8, bit.call(i))
	for i in 8:
		g.fn(n - 1 - i, 8, bit.call(i))
	for i in range(8, 15):
		g.fn(8, n - 15 + i, bit.call(i))
	g.fn(8, n - 8, true)   # den mørke modulen


## Dataene i sikksakk, to kolonner om gangen fra nederst til høyre, utenom funksjonsmodulene.
static func _draw_codewords(g: _Grid, data: PackedByteArray) -> void:
	var n := g.size
	var i := 0
	var right := n - 1
	while right >= 1:
		if right == 6:
			right = 5   # hopp over den loddrette tidslinjen
		for vert in n:
			for j in 2:
				var x := right - j
				var upward := ((right + 1) & 2) == 0
				var y := n - 1 - vert if upward else vert
				if g.f[y * n + x] == 0 and i < data.size() * 8:
					g.m[y * n + x] = (data[i >> 3] >> (7 - (i & 7))) & 1
					i += 1
		right -= 2


static func _apply_mask(g: _Grid, mask: int) -> void:
	var n := g.size
	for y in n:
		for x in n:
			var k := y * n + x
			if g.f[k] == 1:
				continue
			var flip := false
			match mask:
				0: flip = (x + y) % 2 == 0
				1: flip = y % 2 == 0
				2: flip = x % 3 == 0
				3: flip = (x + y) % 3 == 0
				4: flip = (x / 3 + y / 2) % 2 == 0
				5: flip = x * y % 2 + x * y % 3 == 0
				6: flip = (x * y % 2 + x * y % 3) % 2 == 0
				7: flip = ((x + y) % 2 + x * y % 3) % 2 == 0
			if flip:
				g.m[k] = g.m[k] ^ 1


## Straffen for en maske (lavest er lettest å lese): lange like strekk, 2×2-felt, mønstre som ligner
## søkemønstrene, og skjev balanse mellom lyst og mørkt.
static func _penalty(g: _Grid) -> int:
	var n := g.size
	var score := 0
	for horizontal in [true, false]:
		for a in n:
			var line := PackedByteArray()
			var run := 0
			var last := -1
			for b in n:
				var v := g.m[a * n + b] if horizontal else g.m[b * n + a]
				line.append(v)
				if v == last:
					run += 1
					score += 3 if run == 5 else (1 if run > 5 else 0)
				else:
					last = v
					run = 1
			for b in n - 6:
				if line[b] == 1 and line[b + 1] == 0 and line[b + 2] == 1 and line[b + 3] == 1 and line[b + 4] == 1 \
						and line[b + 5] == 0 and line[b + 6] == 1:
					if _light(line, b - 4, b) or _light(line, b + 7, b + 11):
						score += 40
	for y in n - 1:
		for x in n - 1:
			var c := g.m[y * n + x]
			if c == g.m[y * n + x + 1] and c == g.m[(y + 1) * n + x] and c == g.m[(y + 1) * n + x + 1]:
				score += 3
	var dark := 0
	for v in g.m:
		dark += v
	var total := n * n
	return score + maxi(0, (absi(dark * 20 - total * 10) + total - 1) / total - 1) * 10


## Er alle modulene fra..til (ikke med) lyse? Utenfor koden regnes som lyst.
static func _light(line: PackedByteArray, from: int, to: int) -> bool:
	for i in range(maxi(0, from), mini(line.size(), to)):
		if line[i] == 1:
			return false
	return true
