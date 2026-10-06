// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

// Ported from plugins/testsuite/arraytest.sma: one test per arraytestN.

#include <amxmodx>
#include <amxxbench>

new Array:g_Array;
new Array:g_Clone;

public plugin_init()
{
	register_plugin("Array Test", AMXX_VERSION_STR, "AMXX Dev Team");
}

public bench_teardown()
{
	ArrayDestroy(g_Array);
	ArrayDestroy(g_Clone);
}

stock bool:checkarray(const a[], const b[], size)
{
	while (size--)
	{
		if (a[size] != b[size])
		{
			return false;
		}
	}

	return true;
}

stock invarray(a[],size)
{
	while (size--)
	{
		a[size] = ~a[size];
	}

}

stock push_alphabet(Array:a)
{
	ArrayPushString(a, "z");
	ArrayPushString(a, "yz");
	ArrayPushString(a, "xyz");
	ArrayPushString(a, "wxyz");
	ArrayPushString(a, "vwxyz");
	ArrayPushString(a, "uvwxyz");
	ArrayPushString(a, "tuvwxyz");
	ArrayPushString(a, "stuvwxyz");
	ArrayPushString(a, "rstuvwxyz");
	ArrayPushString(a, "qrstuvwxyz");
	ArrayPushString(a, "pqrstuvwxyz");
	ArrayPushString(a, "opqrstuvwxyz");
	ArrayPushString(a, "nopqrstuvwxyz");
	ArrayPushString(a, "mnopqrstuvwxyz");
	ArrayPushString(a, "lmnopqrstuvwxyz");
	ArrayPushString(a, "klmnopqrstuvwxyz");
	ArrayPushString(a, "jklmnopqrstuvwxyz");
	ArrayPushString(a, "ijklmnopqrstuvwxyz");
	ArrayPushString(a, "hijklmnopqrstuvwxyz");
	ArrayPushString(a, "ghijklmnopqrstuvwxyz");
	ArrayPushString(a, "fghijklmnopqrstuvwxyz");
	ArrayPushString(a, "efghijklmnopqrstuvwxyz");
	ArrayPushString(a, "defghijklmnopqrstuvwxyz");
	ArrayPushString(a, "cdefghijklmnopqrstuvwxyz");
	ArrayPushString(a, "bcdefghijklmnopqrstuvwxyz");
	ArrayPushString(a, "abcdefghijklmnopqrstuvwxyz");
}

// arraytest1: 1000 iterations of 1-cell arrays
public test_cell_get_set()
{
	new Float:f;
	g_Array = ArrayCreate(1);

	ASSERT(g_Array != Invalid_Array);

	for (new i = 0; i < 1000; i++)
	{
		f = float(i);
		ArrayPushCell(g_Array,f);
	}

	new Float:r;
	for (new i = 0; i < 1000; i++)
	{
		f = float(i);
		r = Float:ArrayGetCell(g_Array, i);

		// This is normally bad for float "casting", but in this case it should be fine.
		ASSERT_EQ(_:f, _:r);

		// Reset with inversed values
		new g=_:f;
		g=~g;

		ArraySetCell(g_Array, i, g);
		r = Float:ArrayGetCell(g_Array,i);
		ASSERT_EQ(g, _:r);
	}

	ArrayDestroy(g_Array);

	bench_pass();
}

// arraytest2: 1000 iterations of 40-cell arrays
public test_array_get_set()
{
	g_Array = ArrayCreate(40);
	new buff[40];
	new buffb[40];

	for (new i = 0; i < 1000; i++)
	{
		arrayset(buff, i, sizeof(buff));

		ArrayPushArray(g_Array, buff);
	}
	for (new i = 0; i < 1000; i++)
	{
		arrayset(buff, i, sizeof(buff));
		ArrayGetArray(g_Array, i, buffb);
		ASSERT(checkarray(buff, buffb, sizeof(buff)));

		// Now overwrite the array with inversed value
		invarray(buff, sizeof(buff));

		ArraySetArray(g_Array, i, buff);
		ArrayGetArray(g_Array, i, buffb);
		ASSERT(checkarray(buff, buffb, sizeof(buff)));
	}

	ArrayDestroy(g_Array);

	bench_pass();
}

// arraytest3: 1000 iterations of strings
public test_string_get_set()
{
	// The string is 10 long, the string we're trying to pass is 20 long.
	g_Array = ArrayCreate(10);

	new buff[20] = "1234567890abcdefghi";
	new buffb[20];

	for (new i = 0; i < 1000; i++)
	{
		ArrayPushString(g_Array, buff);
	}

	for (new i = 0; i < 1000; i++)
	{
		ArrayGetString(g_Array, i, buffb, charsmax(buffb));
		ASSERT_STR_EQ(buffb, "123456789");

		ArraySetString(g_Array, i, "9876543210");
		ArrayGetString(g_Array, i, buffb, charsmax(buffb));
		ASSERT_STR_EQ(buffb, "987654321");

		buffb[0] = EOS;
		formatex(buffb, charsmax(buffb),"%a", ArrayGetStringHandle(g_Array, i));
		ASSERT_STR_EQ(buffb, "987654321");
	}

	ArrayDestroy(g_Array);

	bench_pass();
}

public sortcallback(Array:a, b, c)
{
	static stra[40];
	static strb[40];

	ArrayGetString(a, b, stra, charsmax(stra));
	ArrayGetString(a, c, strb, charsmax(strb));

	return strcmp(stra,strb);
}

// arraytest4: sorting function
public test_sort()
{
	g_Array = ArrayCreate(40);

	push_alphabet(g_Array);

	new OldSize = ArraySize(g_Array);

	ArraySort(g_Array, "sortcallback");
	ASSERT_EQ(ArraySize(g_Array), OldSize);

	new buff[40];
	ArrayGetString(g_Array, 0, buff, charsmax(buff));
	ASSERT_STR_EQ(buff, "abcdefghijklmnopqrstuvwxyz");

	ArrayGetString(g_Array, 25, buff, charsmax(buff));
	ASSERT_STR_EQ(buff, "z");

	new start = 'a';

	for (new i = 0; i < OldSize; i++)
	{
		ArrayGetString(g_Array, i, buff, charsmax(buff));
		ASSERT_EQ(buff[0], start++);
	}

	ArrayDestroy(g_Array);

	bench_pass();
}

// arraytest5: ArrayDeleteItem()
public test_delete_item()
{
	g_Array = ArrayCreate(1);
	new v;

	for (new i = 0; i < 1000; i++)
	{
		ArrayPushCell(g_Array, i);
	}

	for (new i = ArraySize(g_Array) - 1; i >= 0; i--)
	{
		if (i % 2 == 0)
		{
			ArrayDeleteItem(g_Array, i);
		}
	}

	ASSERT_EQ(ArraySize(g_Array), 500);

	for (new i = 0; i < 500; i++)
	{
		v = ArrayGetCell(g_Array, i);

		// All items should be incrementing odd numbers
		ASSERT_EQ(((i + 1) * 2) - 1, v);

		// All remaining entries should be odd
		ASSERT_EQ((v & 1), 1);
	}

	ArrayDestroy(g_Array);

	g_Array = ArrayCreate(1);

	// Repeat the same test, but check even numbers
	for (new i = 0; i < 1000; i++)
	{
		ArrayPushCell(g_Array, i);
	}

	for (new i = ArraySize(g_Array) - 1; i >= 0 ; i--)
	{
		if (i % 2 == 1)
		{
			ArrayDeleteItem(g_Array, i);
		}
	}

	ASSERT_EQ(ArraySize(g_Array), 500);

	for (new i = 0; i < 500; i++)
	{
		v = ArrayGetCell(g_Array, i);

		// All items should be incrementing even numbers
		ASSERT_EQ(((i + 1) * 2) - 2, v);

		// All remaining entries should be even
		ASSERT_EQ((v & 1), 0);
	}

	ArrayDestroy(g_Array);

	bench_pass();
}

// arraytest6: ArrayInsertCellAfter()
public test_insert_cell_after()
{
	g_Array = ArrayCreate(1);

	for (new i = 0; i < 10;i++)
	{
		ArrayPushCell(g_Array, i);
		new item = ArraySize(g_Array) - 1;

		for (new j = 0; j < 10; j++)
		{
			ArrayInsertCellAfter(g_Array, item + j, j);
		}
	}

	ASSERT_EQ(ArraySize(g_Array), 110);

	new v;
	for (new i = 0; i < 110; i++)
	{
		v = ArrayGetCell(g_Array, i);
		ASSERT_EQ(v, i / 10);

		for (new j = 0; j < 10; j++)
		{
			v = ArrayGetCell(g_Array, ++i);
			ASSERT_EQ(v, j);
		}
	}

	ArrayDestroy(g_Array);

	bench_pass();
}

// arraytest7: ArrayInsertStringAfter()
public test_insert_string_after()
{
	g_Array = ArrayCreate(4);
	new buffer[4];

	for (new i = 0; i < 10;i++)
	{
		formatex(buffer, charsmax(buffer), "%d", i);
		ArrayPushString(g_Array, buffer);
		new item = ArraySize(g_Array) - 1;

		for (new j = 0; j < 10; j++)
		{
			formatex(buffer, charsmax(buffer), "%d", j);
			ArrayInsertStringAfter(g_Array, item + j, buffer);
		}
	}

	ASSERT_EQ(ArraySize(g_Array), 110);

	for (new i = 0; i < 110; i++)
	{
		ArrayGetString(g_Array, i, buffer, charsmax(buffer));
		ASSERT_EQ(str_to_num(buffer), i / 10);

		for (new j = 0; j < 10; j++)
		{
			ArrayGetString(g_Array, ++i, buffer, charsmax(buffer));
			ASSERT_EQ(str_to_num(buffer), j);
		}
	}

	ArrayDestroy(g_Array);

	bench_pass();
}

// arraytest8: ArrayInsertCellBefore()
public test_insert_cell_before()
{
	g_Array = ArrayCreate(1);

	for (new i = 0; i < 10; i++)
	{
		new item = ArrayPushCell(g_Array, i);

		for (new j = 0; j < 10; j++)
		{
			ArrayInsertCellBefore(g_Array, item, j);
		}
	}

	ASSERT_EQ(ArraySize(g_Array), 110);

	for (new i = 0; i < 110; i++)
	{
		for (new j = 9; j >= 0; j--)
		{
			ASSERT_EQ(ArrayGetCell(g_Array, i++), j);
		}

		ASSERT_EQ(ArrayGetCell(g_Array, i), (i - 10) / 10);
	}

	ArrayDestroy(g_Array);

	bench_pass();
}

// arraytest9: ArrayInsertStringBefore()
public test_insert_string_before()
{
	new buffer[4];
	g_Array = ArrayCreate(4);

	for (new i = 0; i < 10; i++)
	{
		formatex(buffer, charsmax(buffer), "%d", i);
		new item = ArrayPushString(g_Array, buffer);

		for (new j = 0; j < 10; j++)
		{
			formatex(buffer, charsmax(buffer), "%d", j);
			ArrayInsertStringBefore(g_Array, item, buffer);
		}
	}

	ASSERT_EQ(ArraySize(g_Array), 110);

	for (new i = 0; i < 110; i++)
	{
		for (new j = 9; j >= 0; j--)
		{
			ArrayGetString(g_Array, i++, buffer, charsmax(buffer));
			ASSERT_EQ(str_to_num(buffer), j);
		}

		ArrayGetString(g_Array, i, buffer, charsmax(buffer));
		ASSERT_EQ(str_to_num(buffer), (i - 10) / 10);
	}

	ArrayDestroy(g_Array);

	bench_pass();
}

// arraytest10: ArraySwap()
public test_swap()
{
	g_Array = ArrayCreate(1);

	for (new i = 0; i < 10; i++)
	{
		ArrayPushCell(g_Array, i);
	}

	for (new i = 0; i < 5; i++)
	{
		ArraySwap(g_Array, i, (10 - (i + 1)));
	}

	new v;
	for (new i = 0; i < 5; i++)
	{
		v = ArrayGetCell(g_Array, i);

		ASSERT_EQ(v, (10 - (i + 1)));
	}

	ArrayDestroy(g_Array);

	bench_pass();
}

public Sortcallbackex_string(Array:a, const b[], const c[], d)
{
	return strcmp(b, c);
}

// arraytest11: (new) sorting function with string
public test_sort_ex_string()
{
	g_Array = ArrayCreate(40);

	push_alphabet(g_Array);

	new OldSize = ArraySize(g_Array);

	ArraySortEx(g_Array, "Sortcallbackex_string");
	ASSERT_EQ(ArraySize(g_Array), OldSize);

	new buff[40];
	ArrayGetString(g_Array, 0, buff, charsmax(buff));
	ASSERT_STR_EQ(buff, "abcdefghijklmnopqrstuvwxyz");

	ArrayGetString(g_Array, 25, buff, charsmax(buff));
	ASSERT_STR_EQ(buff, "z");

	new start = 'a';

	for (new i = 0; i < OldSize; i++)
	{
		ArrayGetString(g_Array, i, buff, charsmax(buff));
		ASSERT_EQ(buff[0], start++);
	}

	ArrayDestroy(g_Array);

	bench_pass();
}

public Sortcallbackex_int(Array:a, const b, const c, d)
{
	return b < c ? -1 : 1;
}

// arraytest12: (new) sorting function with integer
public test_sort_ex_int()
{
	g_Array = ArrayCreate(1);

	ArrayPushCell(g_Array, 8);
	ArrayPushCell(g_Array, 1);
	ArrayPushCell(g_Array, 3);
	ArrayPushCell(g_Array, 5);
	ArrayPushCell(g_Array, 7);
	ArrayPushCell(g_Array, 2);
	ArrayPushCell(g_Array, 9);
	ArrayPushCell(g_Array, 4);
	ArrayPushCell(g_Array, 10);
	ArrayPushCell(g_Array, 6);

	new OldSize = ArraySize(g_Array);

	ArraySortEx(g_Array, "Sortcallbackex_int");

	ASSERT_EQ(ArraySize(g_Array), OldSize);
	ASSERT_EQ(ArrayGetCell(g_Array, 0), 1);
	ASSERT_EQ(ArrayGetCell(g_Array, 9), 10);

	for (new i = 0; i < OldSize; i++)
	{
		ASSERT_EQ(ArrayGetCell(g_Array, i), i+1);
	}

	ArrayDestroy(g_Array);

	bench_pass();
}

// arraytest13: cloning function
public test_clone()
{
	g_Array = ArrayCreate(1);

	ArrayPushCell(g_Array, 42);
	ArrayPushCell(g_Array, 9);
	ArrayPushCell(g_Array, -1);
	ArrayPushCell(g_Array, 0);
	ArrayPushCell(g_Array, 5);
	ArrayPushCell(g_Array, 10);
	ArrayPushCell(g_Array, 15);
	ArrayPushCell(g_Array, 6.5);

	g_Clone = ArrayClone(g_Array);

	ArrayPushCell(g_Clone, 48);
	ArrayPushCell(g_Clone, 3.14);

	ASSERT(g_Array != g_Clone);
	ASSERT_EQ(ArraySize(g_Array), ArraySize(g_Clone) - 2);
	ASSERT_EQ(ArrayGetCell(g_Clone, 0), 42);
	ASSERT_EQ(ArrayGetCell(g_Clone, 2), -1);
	ASSERT_EQ(ArrayGetCell(g_Clone, 7), _:6.5);
	ASSERT_EQ(ArrayGetCell(g_Clone, 9), _:3.14);

	ArrayDestroy(g_Array);
	ArrayDestroy(g_Clone);

	bench_pass();
}

// arraytest14: resizing function
public test_resize()
{
	g_Array = ArrayCreate(16);

	ArrayPushString(g_Array, "egg");

	ArrayResize(g_Array, 50);
	ArrayPushString(g_Array, "boileregg");

	ArraySetString(g_Array, 50, "no more egg v2");

	new buffer[16];
	ArrayGetString(g_Array, 50, buffer, charsmax(buffer));

	ASSERT_EQ(ArraySize(g_Array), 50 + 1);
	ASSERT_STR_EQ(buffer, "no more egg v2");

	ArrayDestroy(g_Array);

	bench_pass();
}

// arraytest15: finding string in array
public test_find_string()
{
	g_Array = ArrayCreate(16);

	ArrayPushString(g_Array, "z");
	ArrayPushString(g_Array, "egg");
	ArrayPushString(g_Array, "boilerplate");
	ArrayPushString(g_Array, "amxmodx");
	ArrayPushString(g_Array, "something");
	ArrayPushString(g_Array, "");
	ArrayPushString(g_Array, "eggeggeggeggeggeggegg");

	new v;

	v = ArrayFindString(g_Array, "egg");
	ASSERT_EQ(v, 1);
	v = ArrayFindString(g_Array, "doh");
	ASSERT_EQ(v, -1);
	v = ArrayFindString(g_Array, "something");
	ASSERT_EQ(v, 4);
	v = ArrayFindString(g_Array, "eggeggeggeggegg");
	ASSERT_EQ(v, 6);
	v = ArrayFindString(g_Array, "");
	ASSERT_EQ(v, 5);
	v = ArrayFindString(g_Array, "zz");
	ASSERT_EQ(v, -1);

	ArrayDestroy(g_Array);

	bench_pass();
}

// arraytest16: finding value in array
public test_find_value()
{
	g_Array = ArrayCreate(1);

	ArrayPushCell(g_Array, 2);
	ArrayPushCell(g_Array, 1);
	ArrayPushCell(g_Array, 5);
	ArrayPushCell(g_Array, 3.14);
	ArrayPushCell(g_Array, -1);

	ASSERT_EQ(ArrayFindValue(g_Array, -1), 4);
	ASSERT_EQ(ArrayFindValue(g_Array, 2), 0);
	ASSERT_EQ(ArrayFindValue(g_Array, 3), -1);
	ASSERT_EQ(ArrayFindValue(g_Array, 3.14), 3);

	ArrayDestroy(g_Array);

	bench_pass();
}
