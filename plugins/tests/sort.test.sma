// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

#include <amxmodx>
#include <amxxbench>

public plugin_init()
{
	register_plugin("Sort Test", "1.0", "BAILOPAN")
}

/*****************
 * INTEGER TESTS *
 *****************/
// Note that integer comparison is just int1-int2 (or a variation therein)

bool:CheckIntegers(const array[], const expected[], size, const what[])
{
	for (new i=0; i<size; i++)
	{
		if (array[i] != expected[i])
		{
			bench_fail("%s: array[%d] = %d, expected %d", what, i, array[i], expected[i])
			return false
		}
	}
	return true
}

// A random sort must keep every element: each one of expected is found once in array.
bool:CheckPermutation(const array[], const expected[], size, const what[])
{
	new bool:used[16]
	for (new i=0; i<size; i++)
	{
		new found = -1
		for (new j=0; j<size; j++)
		{
			if (!used[j] && array[j] == expected[i])
			{
				found = j
				break
			}
		}
		if (found == -1)
		{
			bench_fail("%s: element %d of the input is missing", what, i)
			return false
		}
		used[found] = true
	}
	return true
}

public test_sort_ints()
{
	new array[10] = {6, 7, 3, 2, 8, 5, 0, 1, 4, 9}
	new const ascending[10] = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9}
	new const descending[10] = {9, 8, 7, 6, 5, 4, 3, 2, 1, 0}

	SortIntegers(array, 10, Sort_Ascending)
	if (!CheckIntegers(array, ascending, 10, "ascending sort")) return

	SortIntegers(array, 10, Sort_Descending)
	if (!CheckIntegers(array, descending, 10, "descending sort")) return

	SortIntegers(array, 10, Sort_Random)
	if (!CheckPermutation(array, ascending, 10, "random sort")) return

	bench_pass()
}

/**************************
 * Float comparison tests *
 **************************/

bool:CheckFloats(const Float:array[], const Float:expected[], size, const what[])
{
	for (new i=0; i<size; i++)
	{
		if (array[i] != expected[i])
		{
			bench_fail("%s: array[%d] = %f, expected %f", what, i, array[i], expected[i])
			return false
		}
	}
	return true
}

public test_sort_floats()
{
	new Float:array[10] = {6.3, 7.6, 3.2, 2.1, 8.5, 5.2, 0.4, 1.7, 4.8, 8.2}
	new const Float:ascending[10] = {0.4, 1.7, 2.1, 3.2, 4.8, 5.2, 6.3, 7.6, 8.2, 8.5}
	new const Float:descending[10] = {8.5, 8.2, 7.6, 6.3, 5.2, 4.8, 3.2, 2.1, 1.7, 0.4}

	SortFloats(array, 10, Sort_Ascending)
	if (!CheckFloats(array, ascending, 10, "ascending sort")) return

	SortFloats(array, 10, Sort_Descending)
	if (!CheckFloats(array, descending, 10, "descending sort")) return

	SortFloats(array, 10, Sort_Random)
	if (!CheckPermutation(_:array, _:ascending, 10, "random sort")) return

	bench_pass()
}

public Custom1DSort(Float:elem1, Float:elem2)
{
	if (elem1 > elem2)
	{
		return -1;
	} else if (elem1 < elem2) {
		return 1;
	}

	return 0;
}

public test_sort_custom_1d()
{
	new Float:array[10] = {6.3, 7.6, 3.2, 2.1, 8.5, 5.2, 0.4, 1.7, 4.8, 8.2}
	new const Float:descending[10] = {8.5, 8.2, 7.6, 6.3, 5.2, 4.8, 3.2, 2.1, 1.7, 0.4}

	SortCustom1D(_:array, 10, "Custom1DSort")
	if (!CheckFloats(array, descending, 10, "custom 1D sort")) return

	bench_pass()
}

/***************************
 * String comparison tests *
 ***************************/

bool:CheckStrings(const array[][], const expected[][], size, const what[])
{
	for (new i=0; i<size; i++)
	{
		if (!equal(array[i], expected[i]))
		{
			bench_fail("%s: array[%d] = ^"%s^", expected ^"%s^"", what, i, array[i], expected[i])
			return false
		}
	}
	return true
}

bool:CheckStringPermutation(const array[][], const expected[][], size, const what[])
{
	new bool:used[16]
	for (new i=0; i<size; i++)
	{
		new found = -1
		for (new j=0; j<size; j++)
		{
			if (!used[j] && equal(array[j], expected[i]))
			{
				found = j
				break
			}
		}
		if (found == -1)
		{
			bench_fail("%s: ^"%s^" is missing", what, expected[i])
			return false
		}
		used[found] = true
	}
	return true
}

// Strings compare by character code, so upper case sorts before lower case.
new const g_SortedStrings[][] =
{
	"WHAT?!",
	"bailopan",
	"damaged soul",
	"faluco",
	"gabe newell",
	"hello",
	"johnny got his gun",
	"pm onoto",
	"sidluke",
	"sniperbeamer"
}

new const g_ReverseSortedStrings[][] =
{
	"sniperbeamer",
	"sidluke",
	"pm onoto",
	"johnny got his gun",
	"hello",
	"gabe newell",
	"faluco",
	"damaged soul",
	"bailopan",
	"WHAT?!"
}

public test_sort_strings()
{
	new array[][] =
		{
			"faluco",
			"bailopan",
			"pm onoto",
			"damaged soul",
			"sniperbeamer",
			"sidluke",
			"johnny got his gun",
			"gabe newell",
			"hello",
			"WHAT?!"
		}

	SortStrings(array, 10, Sort_Ascending)
	if (!CheckStrings(array, g_SortedStrings, 10, "ascending sort")) return

	SortStrings(array, 10, Sort_Descending)
	if (!CheckStrings(array, g_ReverseSortedStrings, 10, "descending sort")) return

	SortStrings(array, 10, Sort_Random)
	if (!CheckStringPermutation(array, g_SortedStrings, 10, "random sort")) return

	bench_pass()
}

public Custom2DSort(const elem1[], const elem2[])
{
	return strcmp(elem1, elem2)
}

public test_sort_custom_2d()
{
	new array[][] =
		{
			"faluco",
			"bailopan",
			"pm onoto",
			"damaged soul",
			"sniperbeamer",
			"sidluke",
			"johnny got his gun",
			"gabe newell",
			"hello",
			"WHAT?!"
		}

	SortCustom2D(array, 10, "Custom2DSort")
	if (!CheckStrings(array, g_SortedStrings, 10, "custom 2D sort")) return

	bench_pass()
}


/*******************
 * ADT ARRAY TESTS *
 *******************/
// Int and floats work the same as normal comparisions. Strings are direct
// comparisions with no hacky memory stuff like Pawn arrays.

bool:CheckADTArrayIntegers(Array:array, const expected[], const what[])
{
	new size = ArraySize(array);
	if (size != 10)
	{
		bench_fail("%s: size %d, expected 10", what, size);
		return false;
	}
	new values[10];
	for (new i=0; i<size;i++)
	{
		values[i] = ArrayGetCell(array, i);
	}
	return CheckIntegers(values, expected, size, what);
}

bool:CheckADTArrayPermutation(Array:array, const expected[], const what[])
{
	new size = ArraySize(array);
	if (size != 10)
	{
		bench_fail("%s: size %d, expected 10", what, size);
		return false;
	}
	new values[10];
	for (new i=0; i<size;i++)
	{
		values[i] = ArrayGetCell(array, i);
	}
	return CheckPermutation(values, expected, size, what);
}

public test_adtsort_ints()
{
	new Array:array = ArrayCreate();
	ArrayPushCell(array, 6);
	ArrayPushCell(array, 7);
	ArrayPushCell(array, 3);
	ArrayPushCell(array, 2);
	ArrayPushCell(array, 8);
	ArrayPushCell(array, 5);
	ArrayPushCell(array, 0);
	ArrayPushCell(array, 1);
	ArrayPushCell(array, 4);
	ArrayPushCell(array, 9);

	new const ascending[10] = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9}
	new const descending[10] = {9, 8, 7, 6, 5, 4, 3, 2, 1, 0}
	new bool:ok;

	SortADTArray(array, Sort_Ascending, Sort_Integer)
	ok = CheckADTArrayIntegers(array, ascending, "ascending sort");

	if (ok)
	{
		SortADTArray(array, Sort_Descending, Sort_Integer)
		ok = CheckADTArrayIntegers(array, descending, "descending sort");
	}

	if (ok)
	{
		SortADTArray(array, Sort_Random, Sort_Integer)
		ok = CheckADTArrayPermutation(array, ascending, "random sort");
	}

	ArrayDestroy(array);

	if (ok)
	{
		bench_pass();
	}
}

public test_adtsort_floats()
{
	new Array:array = ArrayCreate();
	ArrayPushCell(array, 6.0);
	ArrayPushCell(array, 7.0);
	ArrayPushCell(array, 3.0);
	ArrayPushCell(array, 2.0);
	ArrayPushCell(array, 8.0);
	ArrayPushCell(array, 5.0);
	ArrayPushCell(array, 0.0);
	ArrayPushCell(array, 1.0);
	ArrayPushCell(array, 4.0);
	ArrayPushCell(array, 9.0);

	new const Float:ascending[10] = {0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0}
	new const Float:descending[10] = {9.0, 8.0, 7.0, 6.0, 5.0, 4.0, 3.0, 2.0, 1.0, 0.0}
	new bool:ok;

	SortADTArray(array, Sort_Ascending, Sort_Float)
	ok = CheckADTArrayIntegers(array, _:ascending, "ascending sort");

	if (ok)
	{
		SortADTArray(array, Sort_Descending, Sort_Float)
		ok = CheckADTArrayIntegers(array, _:descending, "descending sort");
	}

	if (ok)
	{
		SortADTArray(array, Sort_Random, Sort_Float)
		ok = CheckADTArrayPermutation(array, _:ascending, "random sort");
	}

	ArrayDestroy(array);

	if (ok)
	{
		bench_pass();
	}
}

bool:CheckADTArrayStrings(Array:array, const expected[][], const what[], bool:permutation = false)
{
	new size = ArraySize(array);
	if (size != 10)
	{
		bench_fail("%s: size %d, expected 10", what, size);
		return false;
	}
	new values[10][64];
	for (new i=0; i<size;i++)
	{
		ArrayGetString(array, i, values[i], charsmax(values[]));
	}
	if (permutation)
	{
		return CheckStringPermutation(values, expected, size, what);
	}
	return CheckStrings(values, expected, size, what);
}

// Sort_String compares bytes, so upper case sorts before lower case.
new const g_SortedADTStrings[][] =
{
	"Hello pRED*",
	"WHAT?!",
	"bailopan",
	"damaged soul",
	"faluco",
	"gabe newell",
	"johnny got his gun",
	"pm onoto",
	"sidluke",
	"sniperbeamer"
}

new const g_ReverseSortedADTStrings[][] =
{
	"sniperbeamer",
	"sidluke",
	"pm onoto",
	"johnny got his gun",
	"gabe newell",
	"faluco",
	"damaged soul",
	"bailopan",
	"WHAT?!",
	"Hello pRED*"
}

public test_adtsort_strings()
{
	new Array:array = ArrayCreate(64);
	ArrayPushString(array, "faluco");
	ArrayPushString(array, "bailopan");
	ArrayPushString(array, "pm onoto");
	ArrayPushString(array, "damaged soul");
	ArrayPushString(array, "sniperbeamer");
	ArrayPushString(array, "sidluke");
	ArrayPushString(array, "johnny got his gun");
	ArrayPushString(array, "gabe newell");
	ArrayPushString(array, "Hello pRED*");
	ArrayPushString(array, "WHAT?!");

	new bool:ok;

	SortADTArray(array, Sort_Ascending, Sort_String)
	ok = CheckADTArrayStrings(array, g_SortedADTStrings, "ascending sort");

	if (ok)
	{
		SortADTArray(array, Sort_Descending, Sort_String)
		ok = CheckADTArrayStrings(array, g_ReverseSortedADTStrings, "descending sort");
	}

	if (ok)
	{
		SortADTArray(array, Sort_Random, Sort_String)
		ok = CheckADTArrayStrings(array, g_SortedADTStrings, "random sort", true);
	}

	ArrayDestroy(array);

	if (ok)
	{
		bench_pass();
	}
}
