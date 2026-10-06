// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

// Ported from plugins/testsuite/trietest.sma (trietest): one test per named section, the
// "Iterator" section split along its blocks.

#include <amxmodx>
#include <amxxbench>

new Trie:g_Trie;
new Snapshot:g_Snapshot;
new TrieIter:g_Iter;
new TrieIter:g_Iter1;
new TrieIter:g_Iter2;

new data[5] = { 93, 1, 2, 3, 4 };

public plugin_init()
{
	register_plugin("Trie Test", AMXX_VERSION_STR, "AMXX Dev Team");
}

public bench_teardown()
{
	TrieIterDestroy(g_Iter);
	TrieIterDestroy(g_Iter1);
	TrieIterDestroy(g_Iter2);
	TrieSnapshotDestroy(g_Snapshot);
	TrieDestroy(g_Trie);
}

// The "String tests" fill: K<i>K = V<i>V for i in 0..99.
stock fill_strings(Trie:t)
{
	new key[32];
	for (new i = 0; i < 100; i++)
	{
		static val[32];
		formatex(key, charsmax(key), "K%dK", i);
		formatex(val, charsmax(val), "V%dV", i);
		TrieSetString(t, key, val);
	}
}

public test_cell_values()
{
	g_Trie = TrieCreate();

	new key[32];
	for (new i = 0; i < 100; i++)
	{
		formatex(key, charsmax(key), "K%dK", i);
		ASSERT(TrieSetCell(g_Trie, key, i));
	}

	for (new i = 0; i < 100; i++)
	{
		formatex(key, charsmax(key), "K%dK", i);
		new val;
		ASSERT(TrieGetCell(g_Trie, key, val));
		ASSERT_EQ(val, i);
	}

	// Setting K42K without replace should fail.
	new value;
	if (!bench_check(!TrieSetCell(g_Trie, "K42K", 999, false), "set trie K42K should fail")) return;
	if (!bench_check(TrieGetCell(g_Trie, "K42K", value) && value == 42, "value at K42K not correct")) return;
	if (!bench_check(bool:TrieSetCell(g_Trie, "K42K", 999), "set trie K42K = 999 should succeed")) return;
	if (!bench_check(TrieGetCell(g_Trie, "K42K", value) && value == 999, "value at K42K not correct")) return;

	// Check size is 100.
	ASSERT_EQ(TrieGetSize(g_Trie), 100);

	if (!bench_check(!TrieGetCell(g_Trie, "cat", value), "trie should not have a cat.")) return;

	// Check that "K42K" is not a string or array.
	new array[32];
	new string[32];
	if (!bench_check(!(TrieGetArray(g_Trie, "K42K", array, sizeof(array)) ||
		TrieGetString(g_Trie, "K42K", string, charsmax(string))),
		"entry K42K should not be an array or string")) return;

	TrieClear(g_Trie);

	ASSERT_EQ(TrieGetSize(g_Trie), 0);

	TrieDestroy(g_Trie);

	bench_pass();
}

// Makes sure that the trie handle system recycles old handles
public test_recycle_handles()
{
	g_Trie = TrieCreate();
	new Trie:oldhandle = g_Trie;

	TrieDestroy(g_Trie);

	g_Trie = TrieCreate();
	if (!bench_check(g_Trie == oldhandle, "Recycle handles")) return;

	TrieDestroy(g_Trie);

	bench_pass();
}

public test_string_values()
{
	g_Trie = TrieCreate();

	fill_strings(g_Trie);

	new key[32];
	for (new i = 0; i < 100; i++)
	{
		formatex(key, charsmax(key), "K%dK", i);
		static val[32];
		static exp[32];
		formatex(exp, charsmax(exp), "V%dV", i);
		new size;

		ASSERT(TrieGetString(g_Trie, key, val, charsmax(val), size));
		ASSERT_STR_EQ(val, exp);
		ASSERT_EQ(size, strlen(exp));
	}

	new value;
	new array[32];
	new string[32];
	if (!bench_check(!(TrieGetCell(g_Trie, "K42K", value) ||
		TrieGetArray(g_Trie, "K42K", array, sizeof(array))),
		"entry K42K should not be an array or string")) return;

	if (!bench_check(!TrieGetString(g_Trie, "cat", string, charsmax(string)), "trie should not have a cat.")) return;

	TrieDestroy(g_Trie);

	bench_pass();
}

public test_array_values()
{
	g_Trie = TrieCreate();

	fill_strings(g_Trie);

	new value;
	new array[32];
	new string[32];

	if (!bench_check(bool:TrieSetArray(g_Trie, "K42K", data, sizeof data), "K42K should be a string.")) return;
	if (!bench_check(TrieGetArray(g_Trie, "K42K", array, sizeof(array)), "K42K should be V42V.")) return;
	for (new i = 0; i < sizeof data; i++)
	{
		ASSERT_EQ(array[i], data[i]);
	}
	if (!bench_check(!(TrieGetCell(g_Trie, "K42K", value) ||
		TrieGetString(g_Trie, "K42K", string, charsmax(string))),
		"entry K42K should not be an array or string")) return;
	if (!bench_check(bool:TrieSetArray(g_Trie, "K42K", data, 1), "couldn't set K42K to 1-entry array")) return;
	if (!bench_check(TrieGetArray(g_Trie, "K42K", array, sizeof(array), value), "couldn't fetch 1-entry array")) return;
	ASSERT_EQ(value, 1);

	TrieDestroy(g_Trie);

	bench_pass();
}

public test_exists_delete()
{
	g_Trie = TrieCreate();

	fill_strings(g_Trie);
	TrieSetArray(g_Trie, "K42K", data, 1);

	new value;
	new array[32];
	new string[32];

	// Remove "K42K".
	if (!bench_check(TrieDeleteKey(g_Trie, "K42K"), "K42K should have been removed")) return;
	if (!bench_check(!TrieDeleteKey(g_Trie, "K42K"), "K42K should not exist")) return;
	if (!bench_check(!(TrieGetCell(g_Trie, "K42K", value) ||
		TrieGetArray(g_Trie, "K42K", array, sizeof(array)) ||
		TrieGetString(g_Trie, "K42K", string, charsmax(string))),
		"map should not have a K42K")) return;

	TrieDestroy(g_Trie);

	g_Trie = TrieCreate();

	new key[32];
	for (new i = 0; i < 1000; i++)
	{
		formatex(key, charsmax(key), "!%d!", i);
		TrieSetString(g_Trie, key, key);
	}
	for (new i = 0; i < 1000; i++)
	{
		formatex(key, charsmax(key), "!%d!", i);

		ASSERT(TrieKeyExists(g_Trie, key));
		ASSERT(TrieDeleteKey(g_Trie, key));
	}

	TrieDestroy(g_Trie);

	bench_pass();
}

public test_snapshot()
{
	g_Trie = TrieCreate();

	TrieClear(g_Trie);

	ASSERT_EQ(TrieGetSize(g_Trie), 0);

	TrieSetString(g_Trie, "adventure", "time!");
	TrieSetString(g_Trie, "butterflies", "bees");
	TrieSetString(g_Trie, "egg", "egg");

	g_Snapshot = TrieSnapshotCreate(g_Trie);
	{
		ASSERT_EQ(TrieSnapshotLength(g_Snapshot), 3);

		new bool:found[3], len = TrieSnapshotLength(g_Snapshot);
		new buffer[32];
		for (new i = 0; i < len; i++)
		{
			new size = TrieSnapshotKeyBufferSize(g_Snapshot, i); // Just to use it, otherwise you should use charsmax(buffer).
			TrieSnapshotGetKey(g_Snapshot, i, buffer, size);

			if (strcmp(buffer, "adventure") == 0)			found[0] = true;
			else if (strcmp(buffer, "butterflies") == 0)	found[1] = true;
			else if (strcmp(buffer, "egg") == 0)			found[2] = true;
			else { bench_fail("unexpected key: %s", buffer); return; }
		}

		if (!bench_check(found[0] && found[1] && found[2], "did not find all keys")) return;
	}

	TrieSnapshotDestroy(g_Snapshot);
	TrieDestroy(g_Trie);

	bench_pass();
}

public test_iterator_reads_pairs()
{
	g_Trie = TrieCreate();

	TrieSetString(g_Trie, "full", "throttle");
	TrieSetString(g_Trie, "brutal", "legend");
	TrieSetString(g_Trie, "broken", "age");

	g_Iter = TrieIterCreate(g_Trie);
	{
		ASSERT_EQ(TrieIterGetSize(g_Iter), 3);

		if (!bench_check(!TrieIterEnded(g_Iter), "Trie iterator should have a next key/value pair at this point")) return;

		new key[32], value[32], bool:valid[4], klen, vlen;
		if (!bench_check(TrieIterGetKey(g_Iter, key, charsmax(key)) != 0,
			"Trie iterator should not be empty at this point (no key retrieval)")) return;

		while (!TrieIterEnded(g_Iter))
		{
			klen = TrieIterGetKey(g_Iter, key, charsmax(key));
			TrieIterGetString(g_Iter, value, charsmax(value), vlen);

			if (strcmp(key, "full") == 0 && strcmp(value, "throttle") == 0)
				valid[0] = true;
			else if (strcmp(key, "brutal") == 0 && strcmp(value, "legend") == 0)
				valid[1] = true;
			else if (strcmp(key, "broken") == 0 && strcmp(value, "age") == 0)
				valid[2] = true;

			ASSERT_EQ(strlen(key), klen);
			ASSERT_EQ(strlen(value), vlen);

			TrieIterNext(g_Iter);
		}

		if (!bench_check(valid[0] && valid[1] && valid[2], "Did not find all value pairs (1)")) return;

		TrieIterDestroy(g_Iter);

		if (!bench_check(!g_Iter, "Iterator handle should be null after being destroyed")) return;
	}

	TrieDestroy(g_Trie);

	bench_pass();
}

public test_iterator_allows_overwrite()
{
	g_Trie = TrieCreate();

	TrieSetString(g_Trie, "full", "throttle");
	TrieSetString(g_Trie, "brutal", "legend");
	TrieSetString(g_Trie, "broken", "age");

	new key[32], value[32], array[32], bool:valid[4];

	g_Iter = TrieIterCreate(g_Trie);
	{
		TrieSetString(g_Trie, "full", "speed");
		TrieSetString(g_Trie, "brutal", "uppercut");
		TrieSetString(g_Trie, "broken", "sword");

		for (; !TrieIterEnded(g_Iter); TrieIterNext(g_Iter))
		{
			if (!bench_check(!(TrieIterGetCell(g_Iter, value[0]) || TrieIterGetArray(g_Iter, array, sizeof(array))),
				"Entries should not be an array or string")) return;

			TrieIterGetKey(g_Iter, key, charsmax(key));
			TrieIterGetString(g_Iter, value, charsmax(value));

			if (strcmp(key, "full") == 0)
				TrieSetString(g_Trie, "full", "speed");
			else if (strcmp(key, "brutal") == 0)
				TrieSetString(g_Trie, "brutal", "uppercut");
			else if (strcmp(key, "broken") == 0)
				TrieSetString(g_Trie, "broken", "sword");
		}

		if (TrieGetString(g_Trie, "full", value, charsmax(value)) && strcmp(value, "speed") == 0)
			valid[0] = true;
		if (TrieGetString(g_Trie, "brutal", value, charsmax(value)) && strcmp(value, "uppercut") == 0)
			valid[1] = true;
		if (TrieGetString(g_Trie, "broken", value, charsmax(value)) && strcmp(value, "sword") == 0)
			valid[2] = true;

		if (!bench_check(valid[0] && valid[1] && valid[2],
			"Did not set the new values (overwriting value is allowed)")) return;
	}
	TrieIterDestroy(g_Iter);

	if (!bench_check(!TrieIterDestroy(g_Iter), "Iter should be null")) return;

	TrieDestroy(g_Trie);

	bench_pass();
}

public test_iterator_outlives_trie()
{
	g_Trie = TrieCreate();

	TrieSetString(g_Trie, "full", "speed");

	g_Iter = TrieIterCreate(g_Trie);
	{
		TrieDestroy(g_Trie);
	}

	if (!bench_check(bool:TrieIterDestroy(g_Iter), "Iter should be valid")) return;

	bench_pass();
}

public test_iterator_cell_and_array()
{
	new key[32], array[32];

	g_Trie = TrieCreate();
	TrieSetCell(g_Trie, "key_1", cellmin);
	TrieSetArray(g_Trie, "key_2", data, sizeof data);

	g_Iter = TrieIterCreate(g_Trie);

	if (!bench_check(!TrieIterEnded(g_Iter), "Iter should not be ended")) return;

	for (; !TrieIterEnded(g_Iter); TrieIterNext(g_Iter))
	{
		TrieIterGetKey(g_Iter, key, charsmax(key));

		if (strcmp(key, "key_1") == 0)
		{
			new val;
			if (!bench_check(TrieIterGetCell(g_Iter, val) && val == cellmin, "Failed to retrieve value")) return;
		}
		else if (strcmp(key, "key_2") == 0)
		{
			if (!bench_check(TrieIterGetArray(g_Iter, array, sizeof(array)), "Failed to retrieve array")) return;

			for (new i = 0; i < sizeof data; i++)
			{
				ASSERT_EQ(array[i], data[i]);
			}
		}
	}

	TrieIterDestroy(g_Iter);
	TrieDestroy(g_Trie);

	bench_pass();
}

public test_nested_iterators()
{
	g_Trie = TrieCreate();
	TrieSetCell(g_Trie, "key_1", cellmin);

	// Upstream keeps the previous block's iterator open across the clear and destroys it last.
	g_Iter = TrieIterCreate(g_Trie);

	TrieClear(g_Trie);
	TrieSetCell(g_Trie, "1", 1);
	TrieSetCell(g_Trie, "2", 2);
	TrieSetCell(g_Trie, "3", 3);

	new totalSum = 0;
	new element1, element2;

	g_Iter1 = TrieIterCreate(g_Trie)
	for (; !TrieIterEnded(g_Iter1); TrieIterNext(g_Iter1))
	{
		g_Iter2 = TrieIterCreate(g_Trie);
		for(; !TrieIterEnded(g_Iter2); TrieIterNext(g_Iter2))
		{
			TrieIterGetCell(g_Iter1, element1);
			TrieIterGetCell(g_Iter2, element2);

			totalSum += element1 * element2;
		}
		TrieIterDestroy(g_Iter2);
	}
	TrieIterDestroy(g_Iter1);

	ASSERT_EQ(totalSum, 36);

	TrieIterDestroy(g_Iter);
	TrieDestroy(g_Trie);

	bench_pass();
}
