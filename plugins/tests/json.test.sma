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
#include <json>
#include <amxxbench>

//For encoding
new buffer[500];

// What the encoded root array serializes to. Parson writes numbers with "%1.17g", so the reals
// show the float values (-5.31 and -31.1 as Float) widened to double, and escapes '/' as "\/".
new const g_ExpectedEncoded[] = "[{^"string^":^"https:\/\/alliedmods.net^",^"number^":45,^"real^":-5.309999942779541,^"null.null^":null,^"bool^":{^"true^":true}},-31.100000381469727,-42,false,null]";
new const g_ExpectedEncodedPretty[] = "[^n    {^n        ^"string^": ^"https:\/\/alliedmods.net^",^n        ^"number^": 45,^n        ^"real^": -5.309999942779541,^n        ^"null.null^": null,^n        ^"bool^": {^n            ^"true^": true^n        }^n    },^n    -31.100000381469727,^n    -42,^n    false,^n    null^n]";

new g_DataDir[PLATFORM_MAX_PATH];

public plugin_init()
{
	register_plugin("JSON Test", "1.0", "Ni3znajomy");

	get_datadir(g_DataDir, charsmax(g_DataDir));
}

DataPath(const name[], path[], maxlen)
{
	formatex(path, maxlen, "%s/%s", g_DataDir, name);
}

// Builds the root array the way json_test_encode does: with the init funcs or with the set and
// append funcs. Returns Invalid_JSON if the root array has a parent.
JSON:EncodeRootArray(bool:init)
{
	// Create root array
	new JSON:root_array = json_init_array();
	// Init & setup object
	new JSON:object = json_init_object();
	if (!init)
	{
		json_object_set_string(object, "string", "https://alliedmods.net");
		json_object_set_number(object, "number", 45);
		json_object_set_real(object, "real", -5.31);
		json_object_set_null(object, "null.null");
		json_object_set_bool(object, "bool.true", true, true);
	}
	else
	{
		ObjectSetKey(object, "string", json_init_string("https://alliedmods.net"));
		ObjectSetKey(object, "number", json_init_number(45));
		ObjectSetKey(object, "real", json_init_real(-5.31));
		ObjectSetKey(object, "null.null", json_init_null());
		ObjectSetKey(object, "bool.true", json_init_bool(true), true);
	}

	// Add object to root array
	ArrayAppendValue(root_array, object);

	new JSON:parent = json_get_parent(root_array);
	if (parent != Invalid_JSON)
	{
		bench_fail("Root array has parent!");
		json_free(parent);
		json_free(root_array);
		return Invalid_JSON;
	}

	// Append some values to root array
	if (!init)
	{
		json_array_append_real(root_array, -31.1);
		json_array_append_number(root_array, -42);
		json_array_append_bool(root_array, false);
		json_array_append_null(root_array);
	}
	else
	{
		ArrayAppendValue(root_array, json_init_real(-31.1));
		ArrayAppendValue(root_array, json_init_number(-42));
		ArrayAppendValue(root_array, json_init_bool(false));
		ArrayAppendValue(root_array, json_init_null());
	}

	return root_array;
}

// What the other commands start from: json_test_encode 0 0 run first.
bool:EncodeToBuffer()
{
	new JSON:root_array = EncodeRootArray(false);
	if (root_array == Invalid_JSON)
		return false;

	json_serial_to_string(root_array, buffer, charsmax(buffer));
	json_free(root_array);
	return true;
}

public test_json_encode()
{
	new file_path[PLATFORM_MAX_PATH], string_path[PLATFORM_MAX_PATH];
	DataPath("json_encode_test_to_file.txt", file_path, charsmax(file_path));
	DataPath("json_encode_test_to_string.txt", string_path, charsmax(string_path));

	for (new init = 0; init <= 1; init++)
	{
		for (new pretty = 0; pretty <= 1; pretty++)
		{
			if (!EncodeOnce(bool:init, bool:pretty, file_path, string_path))
			{
				delete_file(file_path);
				delete_file(string_path);
				return;
			}
		}
	}

	delete_file(file_path);
	delete_file(string_path);
	bench_pass();
}

bool:EncodeOnce(bool:init, bool:pretty, const file_path[], const string_path[])
{
	new JSON:root_array = EncodeRootArray(init);
	if (root_array == Invalid_JSON)
		return false;

	// Serialiaze to file and to buffer
	new bool:to_file = json_serial_to_file(root_array, file_path, pretty);
	json_serial_to_string(root_array, buffer, charsmax(buffer), pretty);

	// Put buffer's content to file
	new file = fopen(string_path, "wt");
	if (!file)
	{
		json_free(root_array);
		bench_fail("Couldn't create file");
		return false;
	}

	fputs(file, buffer);
	fclose(file);

	new const expected_length = strlen(pretty ? g_ExpectedEncodedPretty : g_ExpectedEncoded);
	new size = json_serial_size(root_array, pretty);
	new JSON:from_file = json_parse(file_path, true);
	new bool:file_matches = from_file != Invalid_JSON && json_equals(from_file, root_array);
	json_free(from_file);
	json_free(root_array);

	if (!to_file)
	{
		bench_fail("json_serial_to_file failed (init %d, pretty %d)", init, pretty);
		return false;
	}
	if (!equal(buffer, pretty ? g_ExpectedEncodedPretty : g_ExpectedEncoded))
	{
		bench_fail("encoded (init %d, pretty %d): %s", init, pretty, buffer);
		return false;
	}
	if (size != expected_length)
	{
		bench_fail("Encoding done (%d bytes), expected %d (init %d, pretty %d)", size, expected_length, init, pretty);
		return false;
	}
	if (!file_matches)
	{
		bench_fail("json_encode_test_to_file.txt does not parse back to the root array (init %d, pretty %d)", init, pretty);
		return false;
	}
	if (file_size(file_path) != expected_length || file_size(string_path) != expected_length)
	{
		bench_fail("file sizes %d and %d, expected %d (init %d, pretty %d)", file_size(file_path), file_size(string_path), expected_length, init, pretty);
		return false;
	}
	return true;
}

public test_json_decode()
{
	if (!EncodeToBuffer())
		return;

	new file_path[PLATFORM_MAX_PATH];
	DataPath("json_encode_test_to_file.txt", file_path, charsmax(file_path));

	new JSON:encoded = json_parse(buffer);
	new bool:written = json_serial_to_file(encoded, file_path);
	json_free(encoded);
	if (!bench_check(written, "json_serial_to_file"))
	{
		delete_file(file_path);
		return;
	}

	new JSON:root_array = json_parse(buffer);
	new JSON:for_compare = json_parse(file_path, true);
	delete_file(file_path);

	// Check if they are the same
	if (root_array == Invalid_JSON || for_compare == Invalid_JSON
		|| !json_equals(root_array, for_compare) || !json_is_array(root_array))
	{
		if (root_array != Invalid_JSON)
			json_free(root_array);

		if (for_compare != Invalid_JSON)
			json_free(for_compare);

		bench_fail("Root value is not array!");
		return;
	}

	// We don't need this anymore
	json_free(for_compare);

	new bool:ok = DecodeArray(root_array);

	json_free(root_array);

	if (ok)
		bench_pass();
}

//Creating inversed root array
public test_json_replace()
{
	if (!EncodeToBuffer())
		return;

	new JSON:root_array_orig = json_parse(buffer);
	new JSON:root_array_copy = json_deep_copy(root_array_orig);
	new JSON:object_orig = json_array_get_value(root_array_orig, 0);

	//Replace null with object
	new JSON:object = json_array_get_value(root_array_copy, 0);
	new bool:replaced_value = json_array_replace_value(root_array_copy, 4, object);
	json_free(object);

	//Replace object with null
	new bool:replaced_null = json_array_replace_null(root_array_copy, 0);

	//Replace bool with real and vice versa
	new Float:realnum = json_array_get_real(root_array_copy, 1);
	new bool:boolval = json_array_get_bool(root_array_copy, 3);
	new bool:replaced_real = json_array_replace_real(root_array_copy, 3, realnum);
	new bool:replaced_bool = json_array_replace_bool(root_array_copy, 1, boolval);

	//Replace number with random
	new number = random(42);
	new bool:replaced_number = json_array_replace_number(root_array_copy, 2, number);

	new path[PLATFORM_MAX_PATH];
	DataPath("json_replace_test.txt", path, charsmax(path));
	new bool:written = json_serial_to_file(root_array_copy, path, true);
	delete_file(path);

	new JSON:moved = json_array_get_value(root_array_copy, 4);
	new bool:object_moved = json_is_object(moved) && json_equals(moved, object_orig);
	json_free(moved);
	json_free(object_orig);
	json_free(root_array_orig);

	new count = json_array_get_count(root_array_copy);
	new JSON:first = json_array_get_value(root_array_copy, 0);
	new bool:first_null = json_is_null(first);
	json_free(first);
	new JSON:second = json_array_get_value(root_array_copy, 1);
	new bool:second_false = json_is_false(second);
	json_free(second);
	new got_number = json_array_get_number(root_array_copy, 2);
	new Float:got_real = json_array_get_real(root_array_copy, 3);

	json_free(root_array_copy);

	ASSERT_TRUE(replaced_value);
	ASSERT_TRUE(replaced_null);
	ASSERT_TRUE(replaced_real);
	ASSERT_TRUE(replaced_bool);
	ASSERT_TRUE(replaced_number);
	ASSERT_TRUE(written);
	ASSERT_EQ(count, 5);
	if (!bench_check(first_null, "index 0 is null")) return;
	if (!bench_check(second_false, "index 1 is the bool false")) return;
	ASSERT_EQ(got_number, number);
	ASSERT(got_real == -31.1);
	if (!bench_check(object_moved, "index 4 is the object")) return;
	bench_pass();
}

bool:ValidateOnce(bool:success)
{
	//Create schema
	new JSON:schema = json_init_object();

	if (success)
		json_object_set_string(schema, "string", "");
	else
		json_object_set_real(schema, "string", 0.0);

	json_object_set_number(schema, "number", 0);
	json_object_set_null(schema, "real");   //Null validate all types

	new JSON:root_array = json_parse(buffer);   //Get root array
	new JSON:object = json_array_get_value(root_array, 0);  //Get object from it

	new bool:result = json_validate(schema, object);	//Validate object with our schema

	json_free(object);
	json_free(schema);
	json_free(root_array);

	return result;
}

public test_json_validate()
{
	if (!EncodeToBuffer())
		return;

	if (!bench_check(ValidateOnce(true) == true, "Validate with a matching schema")) return;
	if (!bench_check(ValidateOnce(false) == false, "Validate with a mismatching schema")) return;
	bench_pass();
}

bool:HasKey(const keyname[], bool:dotnot, type)
{
	//Get root array
	new JSON:root_array = json_parse(buffer);
	new JSON:object = json_array_get_value(root_array, 0);  //Get object
	new JSONType:jtype = JSONError;

	//Get type
	switch(type)
	{
		case 'n': jtype = JSONNull;
		case 's': jtype = JSONString;
		case 'r': jtype = JSONNumber;
		case 'o': jtype = JSONObject;
		case 'a': jtype = JSONArray;
		case 'b': jtype = JSONBoolean;
	}

	new bool:found = json_object_has_value(object, keyname, jtype, dotnot);

	json_free(object);
	json_free(root_array);

	return found;
}

bool:CheckHasKey(const keyname[], bool:dotnot, type, bool:expected)
{
	new bool:found = HasKey(keyname, dotnot, type);
	if (found != expected)
	{
		bench_fail("Key %s (type: %c)%s!%s Found!", keyname, type ? type : '-', (dotnot) ? " using dotnot" : "", (found) ? "" : " Not");
		return false;
	}
	return true;
}

public test_json_has_key()
{
	if (!EncodeToBuffer())
		return;

	// key name, dot notation, type ('n', 's', 'r', 'o', 'a', 'b' or 0 for any), found
	if (!CheckHasKey("string", false, 0, true)) return;
	if (!CheckHasKey("string", false, 's', true)) return;
	if (!CheckHasKey("string", false, 'r', false)) return;
	if (!CheckHasKey("number", false, 'r', true)) return;
	if (!CheckHasKey("real", false, 'r', true)) return;
	if (!CheckHasKey("null.null", false, 0, true)) return;
	if (!CheckHasKey("null.null", false, 'n', true)) return;
	if (!CheckHasKey("null.null", true, 0, false)) return;
	if (!CheckHasKey("bool", false, 'o', true)) return;
	if (!CheckHasKey("bool", false, 'a', false)) return;
	if (!CheckHasKey("bool.true", false, 0, false)) return;
	if (!CheckHasKey("bool.true", true, 0, true)) return;
	if (!CheckHasKey("bool.true", true, 'b', true)) return;
	if (!CheckHasKey("bool.true", true, 's', false)) return;
	if (!CheckHasKey("true", true, 0, false)) return;
	if (!CheckHasKey("missing", false, 0, false)) return;
	bench_pass();
}

// json_test_remove o <key name|clear> <dotnot>. Returns whether removing succeeded and, in
// object_count, how many values the object has left.
bool:RemoveFromObject(const keyname[], bool:dotnot, &object_count)
{
	//Get root array
	new JSON:root_array = json_parse(buffer);
	new bool:success;

	new JSON:object = json_array_get_value(root_array, 0);

	if (equal(keyname, "clear"))
		success = json_object_clear(object);
	else
		success = json_object_remove(object, keyname, dotnot);

	object_count = json_object_get_count(object);
	json_free(object);

	//Dump result
	new path[PLATFORM_MAX_PATH];
	DataPath("json_remove_test.txt", path, charsmax(path));
	new bool:written = json_serial_to_file(root_array, path, true); //Use pretty format for better view
	delete_file(path);

	json_free(root_array);

	if (!written)
	{
		object_count = -1;
	}

	return success;
}

// json_test_remove a <index|-1> . Returns whether removing succeeded and, in array_count, how
// many values the root array has left.
bool:RemoveFromArray(index, &array_count)
{
	//Get root array
	new JSON:root_array = json_parse(buffer);
	new bool:success;

	if (index == -1)
		success = json_array_clear(root_array);
	else
		success = json_array_remove(root_array, index);

	array_count = json_array_get_count(root_array);

	//Dump result
	new path[PLATFORM_MAX_PATH];
	DataPath("json_remove_test.txt", path, charsmax(path));
	new bool:written = json_serial_to_file(root_array, path, true); //Use pretty format for better view
	delete_file(path);

	json_free(root_array);

	if (!written)
	{
		array_count = -1;
	}

	return success;
}

bool:CheckRemoveFromObject(const keyname[], bool:dotnot, bool:expected, expected_count)
{
	new count;
	new bool:success = RemoveFromObject(keyname, dotnot, count);
	if (success != expected || count != expected_count)
	{
		bench_fail("Removing %s%s %s! (%d values left, expected %s with %d left)", keyname, (dotnot) ? " using dotnot" : "", (success) ? "succeed" : "failed", count, (expected) ? "succeed" : "failed", expected_count);
		return false;
	}
	return true;
}

public test_json_remove_from_object()
{
	if (!EncodeToBuffer())
		return;

	if (!CheckRemoveFromObject("string", false, true, 4)) return;
	if (!CheckRemoveFromObject("missing", false, false, 5)) return;
	if (!CheckRemoveFromObject("bool.true", false, false, 5)) return;
	if (!CheckRemoveFromObject("bool.true", true, true, 5)) return;
	if (!CheckRemoveFromObject("null.null", false, true, 4)) return;
	if (!CheckRemoveFromObject("null.null", true, false, 5)) return;
	if (!CheckRemoveFromObject("clear", false, true, 0)) return;
	bench_pass();
}

bool:CheckRemoveFromArray(index, bool:expected, expected_count)
{
	new count;
	new bool:success = RemoveFromArray(index, count);
	if (success != expected || count != expected_count)
	{
		bench_fail("Removing index %d %s! (%d values left, expected %s with %d left)", index, (success) ? "succeed" : "failed", count, (expected) ? "succeed" : "failed", expected_count);
		return false;
	}
	return true;
}

public test_json_remove_from_array()
{
	if (!EncodeToBuffer())
		return;

	if (!CheckRemoveFromArray(0, true, 4)) return;
	if (!CheckRemoveFromArray(4, true, 4)) return;
	if (!CheckRemoveFromArray(5, false, 5)) return;
	if (!CheckRemoveFromArray(-1, true, 0)) return;
	bench_pass();
}

ObjectSetKey(JSON:object, const key[], JSON:node, bool:dot_not = false)
{
	json_object_set_value(object, key, node, dot_not);
	json_free(node);
}

ArrayAppendValue(JSON:array, JSON:node)
{
	json_array_append_value(array, node);
	json_free(node);
}

// What json_test_decode prints for the root array: index, type and the value read through the
// value's handle and through the array.
new const JSONType:g_ArrayTypes[] = { JSONObject, JSONNumber, JSONNumber, JSONBoolean, JSONNull };
new const g_ArrayNumbers[] = { 0, -31, -42, 0, 0 };
new const Float:g_ArrayReals[] = { 0.0, -31.1, -42.0, 0.0, 0.0 };

bool:DecodeArray(&JSON:array)
{
	new count = json_array_get_count(array);
	if (count != sizeof g_ArrayTypes)
	{
		bench_fail("Array has %d elements, expected %d", count, sizeof g_ArrayTypes);
		return false;
	}

	//for storing string data
	new tempbuf[2][100];
	new JSON:array_value, JSON:parent_value;
	for (new i = 0; i < json_array_get_count(array); i++)
	{
		array_value = json_array_get_value(array, i);
		parent_value = json_get_parent(array_value);

		if (parent_value == Invalid_JSON || !json_equals(parent_value, array))
		{
			json_free(parent_value);
			json_free(array_value);

			bench_fail("[Array] Parent value differs!");
			return false;
		}

		json_free(parent_value);

		new JSONType:type = json_get_type(array_value);
		if (type != g_ArrayTypes[i])
		{
			json_free(array_value);
			bench_fail("Array Index %d has type %d, expected %d", i, type, g_ArrayTypes[i]);
			return false;
		}

		new bool:ok = true;
		switch (type)
		{
			case JSONString:
			{
				json_get_string(array_value, tempbuf[0], charsmax(tempbuf[]));
				json_array_get_string(array, i, tempbuf[1], charsmax(tempbuf[]));

				ok = bool:equal(tempbuf[0], tempbuf[1]);
				if (!ok)
					bench_fail("Array Index %d (String) value: %s | index: %s", i, tempbuf[0], tempbuf[1]);
			}
			case JSONNumber:
			{
				new num1 = json_get_number(array_value), num2 = json_array_get_number(array, i);
				new Float:num3 = json_get_real(array_value), Float:num4 = json_array_get_real(array, i);

				ok = num1 == g_ArrayNumbers[i] && num2 == g_ArrayNumbers[i] && num3 == g_ArrayReals[i] && num4 == g_ArrayReals[i];
				if (!ok)
					bench_fail("Array Index %d (Number/Real) value: %d/%f | index: %d/%f, expected %d/%f", i, num1, num3, num2, num4, g_ArrayNumbers[i], g_ArrayReals[i]);
			}
			case JSONObject:
			{
				new iCount = json_object_get_count(array_value);
				ok = iCount == 5;
				if (!ok)
					bench_fail("Array Index %d (Object) %d elements, expected 5", i, iCount);
				else
					ok = DecodeObject(array_value);
			}
			case JSONArray:
			{
				ok = DecodeArray(array_value);
			}
			case JSONBoolean:
			{
				new bool:val1 = json_get_bool(array_value), bool:val2 = json_array_get_bool(array, i);
				ok = val1 == false && val2 == false;
				if (!ok)
					bench_fail("Array Index %d (Bool) value %d | index %d, expected 0", i, val1, val2);
			}
		}

		json_free(array_value);

		if (!ok)
			return false;
	}
	return true;
}

// What json_test_decode prints for the object at index 0.
new const g_ObjectKeys[][] = { "string", "number", "real", "null.null", "bool" };
new const JSONType:g_ObjectTypes[] = { JSONString, JSONNumber, JSONNumber, JSONNull, JSONObject };
new const g_ObjectNumbers[] = { 0, 45, -5, 0, 0 };
new const Float:g_ObjectReals[] = { 0.0, 45.0, -5.31, 0.0, 0.0 };

bool:DecodeObject(&JSON:object)
{
	//for storing string data
	new tempbuf[2][100];
	new key[30];
	new JSON:obj_value, JSON:parent_value;
	for (new i = 0; i < json_object_get_count(object); i++)
	{
		json_object_get_name(object, i, key, charsmax(key));
		if (!equal(key, g_ObjectKeys[i]))
		{
			bench_fail("Object Key %d is ^"%s^", expected ^"%s^"", i, key, g_ObjectKeys[i]);
			return false;
		}

		obj_value = json_object_get_value_at(object, i);
		parent_value = json_get_parent(obj_value);

		if (parent_value == Invalid_JSON || !json_equals(parent_value, object))
		{
			json_free(parent_value);
			json_free(obj_value);

			bench_fail("[Object] Parent value differs!");
			return false;
		}

		json_free(parent_value);

		new JSONType:type = json_get_type(obj_value);
		if (type != g_ObjectTypes[i])
		{
			json_free(obj_value);
			bench_fail("Object Key ^"%s^" has type %d, expected %d", key, type, g_ObjectTypes[i]);
			return false;
		}

		new bool:ok = true;
		switch (type)
		{
			case JSONString:
			{
				json_get_string(obj_value, tempbuf[0], charsmax(tempbuf[]));
				json_object_get_string(object, key, tempbuf[1], charsmax(tempbuf[]));

				ok = equal(tempbuf[0], "https://alliedmods.net") && equal(tempbuf[1], "https://alliedmods.net");
				if (!ok)
					bench_fail("Object Key ^"%s^" (String) value: %s | key: %s", key, tempbuf[0], tempbuf[1]);
			}
			case JSONNumber:
			{
				new num1 = json_get_number(obj_value), num2 = json_object_get_number(object, key);
				new Float:num3 = json_get_real(obj_value), Float:num4 = json_object_get_real(object, key);

				ok = num1 == g_ObjectNumbers[i] && num2 == g_ObjectNumbers[i] && num3 == g_ObjectReals[i] && num4 == g_ObjectReals[i];
				if (!ok)
					bench_fail("Object Key ^"%s^" (Number/Real) value: %d/%f | key: %d/%f, expected %d/%f", key, num1, num3, num2, num4, g_ObjectNumbers[i], g_ObjectReals[i]);
			}
			case JSONObject:
			{
				new iCount = json_object_get_count(obj_value);
				ok = iCount == 1;
				if (!ok)
					bench_fail("Object Key ^"%s^" (Object) %d elements, expected 1", key, iCount);

				//Let's get its value by dot notation
				else if (equal(key, "bool"))
				{
					//dotnot
					new bool:val1 = json_object_get_bool(object, "bool.true", true);
					new bool:val2 = json_object_get_bool(obj_value, "true");
					json_object_get_name(obj_value, 0, key, charsmax(key));

					ok = equal(key, "true") && val1 == true && val2 == true;
					if (!ok)
						bench_fail("Object Key ^"%s^" (Bool) dot %d | nodot: %d, expected ^"true^" 1 1", key, val1, val2);
				}
				else
					ok = DecodeObject(obj_value);
			}
			case JSONArray:
			{
				ok = DecodeArray(obj_value);
			}
			case JSONBoolean:
			{
				new bool:val1 = json_get_bool(obj_value), bool:val2 = json_object_get_bool(object, key);
				ok = val1 == val2;
				if (!ok)
					bench_fail("Object Key ^"%s^" (Bool) value %d | index %d", key, val1, val2);
			}
		}

		json_free(obj_value);

		if (!ok)
			return false;
	}
	return true;
}
