// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

#include <amxmodx>
#include <amxmisc>
#include <amxxbench>

new const g_hashTypes[HashType][] =
{
	"CRC32",
	"MD5",
	"SHA1",
	"SHA256",
	"SHA3 224",
	"SHA3 256",
	"SHA3 384",
	"SHA3 512",
	"Keccak 224",
	"Keccak 256",
	"Keccak 384",
	"Keccak 512"
};

new const g_hashInput[] = "AMX Mod X";

// Hashes of g_hashInput (no terminating null), lowercase hex as the hashers write them.
new const g_hashExpected[HashType][] =
{
	"f6229305",
	"215b200dd3351965eb821b0f02c8e24e",
	"8bd771b6a1952d420abd8dac29c2c62a592178c9",
	"5c543603a2279132353af7ccd5e8315d71acd30537da2b965bb3e62854efdc39",
	"71f5d4df22e14a62371314ae4ec4400cb6f2837f876f4187b407293f",
	"5982fddb01f45cccb549e63586f0f8dae1aa4430b7a72add1d3eb2d382b876b2",
	"0fb068317f680f270e63b4013f3a5a43cdac49713818a00a3e51abb1279e624367e281f451d16fbe10418438cb8eeae4",
	"8eda31e669dccb0f64ce6379b5c94c479bfe89c367db4dd691cba5f879e0e3f6796feebbd4dd6fc784f6b936cf836df3499dc40c1951c418c51a51b1316c8e70",
	"b886c7374e1ec44bbe028d246c073ef7e3448ec51284c412ae2afec9",
	"32883e0cac5d0018492ccac41a356147d0930a285671d4259f1330c684602b11",
	"1ddec17398a0380e94c88ae6440424a664cb3d687163672bdf1647961d9e819002aa28e440e39751d06f7ec6a86a654c",
	"1fef8e6054a18b98772797b605fa1ae01d333fd5155b933f24ddd3b2d647eb1fe223e85b6594888876605ca94c9e0fe1c9999095105e8b80a9e55f75c3d737c1"
};

new g_hashFile[PLATFORM_MAX_PATH];

public plugin_init()
{
	register_plugin("Hashing Test", "1.0", "Hattrick (Claudiu HKS)");

	get_datadir(g_hashFile, charsmax(g_hashFile));
	add(g_hashFile, charsmax(g_hashFile), "/hashing_test.txt");
}

public test_hash_string()
{
	new Output[256], HashType:Type;

	for (Type = Hash_Crc32; Type < any:sizeof g_hashTypes; Type++)
	{
		hash_string(g_hashInput, Type, Output, charsmax(Output));

		if (!equal(Output, g_hashExpected[Type]))
		{
			bench_fail("%s of ^"%s^": got %s, expected %s", g_hashTypes[Type], g_hashInput, Output, g_hashExpected[Type]);
			return;
		}
	}

	bench_pass();
}

public test_hash_file()
{
	new file = fopen(g_hashFile, "wb");
	ASSERT(file);
	fputs(file, g_hashInput);
	fclose(file);

	new Output[256], HashType:Type;

	for (Type = Hash_Crc32; Type < any:sizeof g_hashTypes; Type++)
	{
		hash_file(g_hashFile, Type, Output, charsmax(Output));

		if (!equal(Output, g_hashExpected[Type]))
		{
			delete_file(g_hashFile);
			bench_fail("%s of %s: got %s, expected %s", g_hashTypes[Type], g_hashFile, Output, g_hashExpected[Type]);
			return;
		}
	}

	delete_file(g_hashFile);
	bench_pass();
}
