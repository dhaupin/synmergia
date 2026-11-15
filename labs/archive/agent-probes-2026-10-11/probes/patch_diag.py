import re
p = 'tests/tmp_diag.gd'
s = open(p).read()
s = s.replace('''	var seed_b: PackedByteArray = PackedByteArray()
	for i in range(4):
		seed_b.append(i + 1)
''', '''	var seed_b: PackedByteArray = Gen.world_seed_bytes()
''')
open(p, 'w').write(s)
print("patched")
