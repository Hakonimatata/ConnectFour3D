extends TestCase
## Tester QR-koden (core/qr_code.gd) mot kjente verdier fra standarden, og at koden er bygd riktig opp.


## Reed–Solomon: eksempelet «HELLO WORLD» (versjon 1-M) fra standarden og thonky.com.
func test_error_correction_matches_the_known_example() -> void:
	var data := PackedByteArray([32, 91, 11, 120, 209, 114, 220, 77, 67, 64, 236, 17, 236, 17, 236, 17])
	check_eq(Array(QrCode.rs_ecc(data, 10)), [196, 35, 39, 119, 235, 215, 231, 226, 93, 23])


## Formatinformasjonen for nivå M og alle maskene, og versjonsinformasjonen for versjon 7 (fra tabellene
## i standarden).
func test_format_and_version_bits() -> void:
	var table := ["101010000010010", "101000100100101", "101111001111100", "101101101001011",
		"100010111111001", "100000011001110", "100111110010111", "100101010100000"]
	for mask in 8:
		check_eq(QrCode.format_bits(mask), table[mask].bin_to_int(), "maske %d:" % mask)
	check_eq(QrCode.version_bits(7), "000111110010010100".bin_to_int())


## En lenke blir en kode med riktig størrelse, søkemønstre, tidslinjer, mørk modul og to like kopier av
## formatinformasjonen (som sier nivå M og en gyldig maske).
func test_link_becomes_a_well_formed_code() -> void:
	for text in ["https://fourinspace.com/?t=KX4P2", "https://192-168-1-23.local-ip.sh:8000/?t=ABCDE&vis=1&x=" + "a".repeat(60)]:
		var m := QrCode.encode(text)
		var n := QrCode.size_of(m)
		check(n >= 21 and (n - 17) % 4 == 0, "gyldig størrelse: %d" % n)
		var at := func(x: int, y: int) -> int: return m[y * n + x]
		for c in [Vector2i(0, 0), Vector2i(n - 7, 0), Vector2i(0, n - 7)]:
			check_eq(at.call(c.x, c.y), 1, "søkemønsterets hjørne")
			check_eq(at.call(c.x + 1, c.y + 1), 0, "lys ring")
			check_eq(at.call(c.x + 3, c.y + 3), 1, "mørk midte")
		for i in range(8, n - 8):
			check_eq(at.call(i, 6), 1 - i % 2, "tidslinje")
			check_eq(at.call(6, i), 1 - i % 2, "tidslinje")
		check_eq(at.call(8, n - 8), 1, "den mørke modulen")
		var first := 0
		var second := 0
		var spots := [[8, 0], [8, 1], [8, 2], [8, 3], [8, 4], [8, 5], [8, 7], [8, 8], [7, 8], [5, 8], [4, 8], [3, 8], [2, 8],
			[1, 8], [0, 8]]
		for i in 15:
			first |= at.call(spots[i][0], spots[i][1]) << i
			var x: int = n - 1 - i if i < 8 else 8
			var y: int = 8 if i < 8 else n - 15 + i
			second |= at.call(x, y) << i
		check_eq(first, second, "to like kopier av formatet")
		var mask := ((first ^ 0x5412) >> 10) & 7
		check_eq(((first ^ 0x5412) >> 13) & 3, 0, "nivå M")
		check_eq(first, QrCode.format_bits(mask), "gyldig BCH-kode")
	check(QrCode.encode("x".repeat(300)).is_empty(), "for lang tekst gir ingen kode")
