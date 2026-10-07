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

/**
 * Warning: To get expected result, file encoding must be UTF-8 without BOM.
 */

#define REFERENCE "𤭢hi AMXX® Hello㋡ crab?ൠ"

public plugin_init()
{
	register_plugin("UTF-8 Test", AMXX_VERSION_STR, "AMXX Dev Team");
}

enum TestType
{
	TT_Equal = 0,
	TT_LessThan,
	TT_GreaterThan,
	TT_LessThanEqual,
	TT_GreaterThanEqual,
	TT_NotEqual
};

new const TestWords[TestType][] =
{
	"==",
	"<",
	">",
	"<=",
	">=",
	"!="
};

bool:test(any:a, any:b = true, TestType:type = TT_Equal, const description[] = "")
{
	new passed = 0;

	switch (type)
	{
		case TT_Equal:              passed = a == b;
		case TT_LessThan:           passed = a < b;
		case TT_GreaterThan:        passed = a > b;
		case TT_LessThanEqual:      passed = a <= b;
		case TT_GreaterThanEqual:   passed = a >= b;
		case TT_NotEqual:           passed = a != b;
	}

	if (!passed)
	{
		bench_fail("%s (%d %s %d)", description, a, TestWords[type], b);
		return false;
	}

	return true;
}

#define TEST(%0) if (!test(%0)) return

new Array:ReferenceArray = Invalid_Array;
new Trie:ReferenceTrie = Invalid_Trie;
new DataPack:ReferencePack = Invalid_DataPack;

new bool:LocalinfoSaved;
new LocalinfoBackup[64];

public bench_teardown()
{
	if (ReferenceArray != Invalid_Array)
	{
		ArrayDestroy(ReferenceArray);
	}

	if (ReferenceTrie != Invalid_Trie)
	{
		TrieDestroy(ReferenceTrie);
	}

	if (ReferencePack != Invalid_DataPack)
	{
		DestroyDataPack(ReferencePack);
	}

	if (LocalinfoSaved)
	{
		set_localinfo("reference", LocalinfoBackup);
		LocalinfoSaved = false;
	}
}

public test_get_char_bytes()
{
	TEST(get_char_bytes(""), 1, TT_Equal, "Empty string");
	TEST(get_char_bytes("a") , 1, TT_Equal, "1 byte character");
	TEST(get_char_bytes("®") , 2, TT_Equal, "2 bytes character");
	TEST(get_char_bytes("㋡"), 3, TT_Equal, "3 bytes character");
	TEST(get_char_bytes("𤭢"), 4, TT_Equal, "4 bytes character");
	TEST(get_char_bytes("^xE1^xB9"), 3, TT_Equal, "Truncated character");

	bench_pass();
}

public test_is_char_mb()
{
	new reference[] = REFERENCE;

	/**
	 * is_char_mb() returns also number of bytes if not 0.
	 */
	TEST(is_char_mb(reference[0]), 0, TT_NotEqual, "1 byte character");  // 𤭢
	TEST(is_char_mb(reference[11]), 0, TT_NotEqual, "2 bytes character"); // ®
	TEST(is_char_mb(reference[19]), 0, TT_NotEqual, "3 bytes character"); // ㋡
	TEST(is_char_mb(reference[29]), 0, TT_NotEqual, "4 bytes character"); // ൠ
	TEST(is_char_mb('^xE1'), 3, TT_Equal, "Truncated character");

	bench_pass();
}

public test_truncated_character_formatted_output()
{
	new reference[] = REFERENCE;

	/**
	 * Truncating '𤭢' at different index. '𤭢' = 4 bytes
	 * A buffer of 4 = 3 bytes + EOS.
	 * Expected result: empty buffer.
	 */
	new buffer1[4];
	for(new i = charsmax(buffer1), length1; i >= 0; --i)
	{
		length1 = formatex(buffer1, i, "%s", reference);
		TEST(buffer1[0], EOS, .description = fmt("Truncating multi-bytes character #%d (buffer)", charsmax(buffer1) - i + 1));
		TEST(length1, 0, .description = fmt("Truncating multi-bytes character #%d (length)", charsmax(buffer1) - i + 1));
	}

	/**
	 * Truncating inside 'ൠ'.
	 * Buffer of 14: Enough to hold "㋡ crab?ൠ"
	 * Retrieve 11 characters using precision format from '㋡' to inside 'ൠ'..
	 * Expected result: 'ൠ'. should be skipped.
	 */
	new buffer3[14];
	new length3 = formatex(buffer3, charsmax(buffer3), "%.11s", reference[19]);
	TEST(strcmp(buffer3, "㋡ crab?"), 0, .description = "Truncating moar multi-bytes character (buffer)");
	TEST(length3, get_char_bytes("㋡") + strlen(" crab?"), .description = "Truncating moar multi-bytes character (length)");

	bench_pass();
}

public test_truncated_character_output()
{
	new reference[] = REFERENCE;

	LocalinfoSaved = true;
	get_localinfo("reference", LocalinfoBackup, charsmax(LocalinfoBackup));
	set_localinfo("reference", reference);

	/**
	 * Splits string at '㋡'.
	 * Buffer can hold only 16 characters.
	 * Expected result: '㋡' should not be included and returned position should be after '㋡'.
	 */
	new buffer1[16];
	new index1 = split_string(reference, "㋡", buffer1, charsmax(buffer1));
	TEST(strcmp(buffer1, "𤭢hi AMXX® H"), 0, .description = "Splitting string #1 (buffer)");
	TEST(index1, strlen("𤭢hi AMXX® Hello") + get_char_bytes("㋡"), .description = "Splitting string #1 (length)");

	/**
	 * Splits string at '𤭢'.
	 * Expected result: Empty string and returned position should be after '𤭢'.
	 */
	new buffer2[5];
	new index2 = split_string(reference, "𤭢", buffer2, charsmax(buffer2));
	TEST(buffer2[0], EOS, .description = "Splitting string #2 (buffer)");
	TEST(index2, get_char_bytes("𤭢"), .description = "Splitting string #2 (length)");

	/**
	 * Splits string at '\ൠ'.
	 * Expected result: Empty string and returned position should -1 (not found).
	 */
	new buffer3[12];
	new index3 = split_string(reference, "\ൠ", buffer3, charsmax(buffer3));
	TEST(buffer3[0], EOS, .description = "Splitting string #3 (buffer)");
	TEST(index3, -1, .description = "Splitting string #3 (length)");

	/**
	 * Truncating '𤭢' at different index. '𤭢' = 4 bytes
	 * A buffer of 4 = 3 bytes + EOS.
	 * Expected result: empty buffer.
	 */
	new buffer4[4];
	for(new i = charsmax(buffer4), length4; i >= 0; --i)
	{
		length4 = get_localinfo("reference", buffer4, i);
		TEST(buffer4[0], EOS, .description = "Truncating string (buffer)");
		TEST(length4, 0, .description = "Truncating string (length)");
	}

	bench_pass();
}

public test_truncated_character_direct_copy()
{
	new reference[] = REFERENCE;

	ReferenceArray = ArrayCreate(sizeof reference);
	ArrayPushString(ReferenceArray, reference);

	ReferenceTrie = TrieCreate();
	TrieSetString(ReferenceTrie, "reference", reference);

	ReferencePack = CreateDataPack();
	WritePackString(ReferencePack, reference);
	ResetPack(ReferencePack);

	/**
	 * Replaces '®' by '𤭢'.
	 * Expected result: '𤭢' should eat '® He" which counts 4 bytes.
	 */
	new count1 = replace_string(reference, charsmax(reference), "®", "𤭢");
	TEST(strcmp(reference, "𤭢hi AMXX𤭢ello㋡ crab?ൠ"), 0, .description = "Replacing character (buffer)");
	TEST(count1, 1, .description = "Replacing character (count)");

	/**
	 * Replaces '®' by '𤭢'.
	 * Expected result: not found.
	 */
	new count2 = replace_string(reference, charsmax(reference), "®", "𤭢");
	TEST(strcmp(reference, "𤭢hi AMXX𤭢ello㋡ crab?ൠ"), 0, .description = "Replacing inexistent character (buffer)");
	TEST(count2, 0, .description = "Replacing inexistent character (count)");

	/**
	 * Replaces 'ൠ' by '𤭢'.
	 * Expected result: 'ൠ' = 3 bytes, '𤭢' = 4 bytes. Not enough spaces to hold '𤭢', skipping it.
	 */
	new count3 = replace_string(reference, charsmax(reference), "ൠ", "𤭢");
	TEST(strcmp(reference, "𤭢hi AMXX𤭢ello㋡ crab?"), 0, .description = "Replacing character / not enough space (buffer)");
	TEST(count3, 1, .description = "Replacing character / not enough space (count)");

	/**
	 * Gets reference string with limited buffer.
	 * Expected result: '㋡' should be ignored as no spaces.
	 */
	new buffer[charsmax(reference) - 9];
	ArrayGetString(ReferenceArray, 0, buffer, charsmax(buffer));
	TEST(strcmp(buffer, "𤭢hi AMXX® Hello") == 0, .description  = "Truncating string #1");

	/**
	 * Gets reference string with limited buffer.
	 * Expected result: '㋡' should be ignored as no spaces.
	 */
	TrieGetString(ReferenceTrie, "reference", buffer, charsmax(buffer));
	TEST(strcmp(buffer, "𤭢hi AMXX® Hello") == 0, .description  = "Truncating string #2");

	/**
	 * Gets reference string with limited buffer.
	 * Expected result: '㋡' should be ignored as no room.
	 */
	new length = ReadPackString(ReferencePack, buffer, charsmax(buffer));
	TEST(strcmp(buffer, "𤭢hi AMXX® Hello") == 0 && length == strlen("𤭢hi AMXX® Hello"), .description  = "Truncating string #3");

	bench_pass();
}

public test_containi_strfind_ignorecase()
{
	new haystack[64];
	new needle[64];

	/**
	 * Empty haystack and needle.
	 */
	haystack = ""
	needle = "";
	TEST(containi(haystack, needle), -1, .description = "Empty haystack and needle (containi)");
	TEST(strfind(haystack, needle, .ignorecase = true), 0, .description = "Empty haystack and needle (strfind)");

	/**
	 * Empty haystack.
	 */
	haystack = ""
	needle = "crab";
	TEST(containi(haystack, needle), -1, .description = "Empty haystack (containi)");
	TEST(strfind(haystack, needle, .ignorecase = true), -1, .description = "Empty haystack (strfind)");

	/**
	 * Empty needle.
	 */
	haystack = "crab"
	needle = "";
	TEST(containi(haystack, needle), -1, .description = "Empty needle (containi)");
	TEST(strfind(haystack, needle, .ignorecase = true), 0, .description = "Empty needle (strfind)");

	/**
	 * Latin / Single / Both lowercase
	 */
	haystack = "a"
	needle = "a";
	TEST(containi(haystack, needle), 0, .description = "Basic latin lowercase character (containi)");
	TEST(strfind(haystack, needle, .ignorecase = true), 0, .description = "Basic latin lowercase character (strfind)");

	/**
	 * Latin / Multiple / Both lowercase
	 */
	haystack = "aaa"
	needle = "aaa";
	TEST(containi(haystack, needle), 0, .description = "Basic latin lowercase characters (containi)");
	TEST(strfind(haystack, needle, .ignorecase = true), 0, .description = "Basic latin lowercase characters (strfind)");

	/**
	 * Latin / Single / Both uppercase
	 */
	haystack = "A"
	needle = "A";
	TEST(containi(haystack, needle), 0, .description = "Basic latin uppercase character (containi)");
	TEST(strfind(haystack, needle, .ignorecase = true), 0, .description = "Basic latin uppercase character (strfind)");

	/**
	 * Latin / Multiple / Both uppercase
	 */
	haystack = "AAA"
	needle = "AAA";
	TEST(containi(haystack, needle), 0, .description = "Basic latin uppercase characters (containi)");
	TEST(strfind(haystack, needle, .ignorecase = true), 0, .description = "Basic latin uppercase characters (containi)");

	/**
	 * Latin / Single unaffected
	 */
	haystack = "@"
	needle = "@";
	TEST(containi(haystack, needle), 0, .description = "Basic latin unaffected character (containi)");
	TEST(strfind(haystack, needle, .ignorecase = true), 0, .description = "Basic latin unaffected character (strfind)");

	/**
	 * Latin / Multiple unaffected
	 */
	haystack = "@#%"
	needle = "@#%";
	TEST(containi(haystack, needle), 0, .description = "Basic latin unaffected characters (containi)");
	TEST(strfind(haystack, needle, .ignorecase = true), 0, .description = "Basic latin unaffected characters (strfind)");

	/**
	 * Latin / Single / haystack lowercase, needle uppercase
	 */
	haystack = "a"
	needle = "A";
	TEST(containi(haystack, needle), 0, .description = "Basic latin character with mixed case #1 (containi)");
	TEST(strfind(haystack, needle, .ignorecase = true), 0, .description = "Basic latin character with mixed case (strfind)");

	/**
	 * Latin / Multiple / haystack lowercase, needle uppercase
	 */
	haystack = "aaa"
	needle = "AAA";
	TEST(containi(haystack, needle), 0, .description = "Basic latin characters with mixed case (containi)");
	TEST(strfind(haystack, needle, .ignorecase = true), 0, .description = "Basic latin characters with mixed case (strfind)");

	/**
	 * Latin / Single / haystack uppercase, needle uppercase
	 */
	haystack = "A"
	needle = "a";
	TEST(containi(haystack, needle), 0, .description = "Basic latin character with mixed case #2 (containi)");
	TEST(strfind(haystack, needle, .ignorecase = true), 0, .description = "Basic latin character with mixed case #2 (strfind)");

	/**
	 * Latin / Multiple / haystack uppercase, needle uppercase
	 */
	haystack = "AAA"
	needle = "aaa";
	TEST(containi(haystack, needle), 0, .description = "Basic latin characters with mixed case #2 (containi)");
	TEST(strfind(haystack, needle, .ignorecase = true), 0, .description = "Basic latin characters with mixed case #2 (strfind)");

	/**
	 * Latin / Sentence / Single needle
	 */
	haystack = "Hello world!"
	needle = "o";
	TEST(containi(haystack, needle), 4, .description = "Basic latin sentence / Single needle (containi)");
	TEST(strfind(haystack, needle, .ignorecase = true), 4, .description = "Basic latin sentence / Single needle (strfind)");

	/**
	 * Latin / Sentence / Single needle / End of string
	 */
	haystack = "Hello world!"
	needle = "!";
	TEST(containi(haystack, needle), 11, .description = "Basic latin sentence / Single needle / End of string (containi)");
	TEST(strfind(haystack, needle, .ignorecase = true), 11, .description = "Basic latin sentence / Single needle / End of string (strfind)");

	/**
	 * Latin / Sentence / Multiple needle
	 */
	haystack = "Hello world!"
	needle = "WoRlD";
	TEST(containi(haystack, needle), 6, .description = "Basic latin sentence / Multiple needle (containi)");
	TEST(strfind(haystack, needle, .ignorecase = true), 6, .description = "Basic latin sentence / Single needle (strfind)");

	/**
	 * Latin / Sentence / Not found
	 */
	haystack = "Hello world!"
	needle = "?";
	TEST(containi(haystack, needle), -1, .description = "Basic latin sentence / Not found (containi)");
	TEST(strfind(haystack, needle, .ignorecase = true), -1, .description = "Basic latin sentence / Not found (strfind)");

	/**
	 * Multi bytes / Single / Both lowercase
	 */
	haystack = "ȓ"
	needle = "ȓ";
	TEST(containi(haystack, needle), 0, .description = "Multi bytes lowercase character (containi)");
	TEST(strfind(haystack, needle, .ignorecase = true), 0, .description = "Multi bytes lowercase character (strfind)");

	/**
	 * Multi bytes / Multiple / Both lowercase
	 */
	haystack = "ȓǯʌό"
	needle = "ȓǯʌό";
	TEST(containi(haystack, needle), 0, .description = "Multi bytes lowercase characters (containi)");
	TEST(strfind(haystack, needle, .ignorecase = true), 0, .description = "Multi bytes lowercase characters (strfind)");

	/**
	 * Multi bytes / Single / Both uppercase
	 */
	haystack = "Ȓ"
	needle = "Ȓ";
	TEST(containi(haystack, needle), 0, .description = "Multi bytes uppercase character (containi)");
	TEST(strfind(haystack, needle, .ignorecase = true), 0, .description = "Multi bytes uppercase character (strfind)");

	/**
	 * Multi bytes / Multiple / Both uppercase
	 */
	haystack = "ȒǮɅΌ"
	needle = "ȒǮɅΌ";
	TEST(containi(haystack, needle), 0, .description = "Multi bytes uppercase characters (containi)");
	TEST(strfind(haystack, needle, .ignorecase = true), 0, .description = "Multi bytes uppercase characters (strfind)");

	/**
	 * Multi bytes / Single unaffected
	 */
	haystack = "ൠ"
	needle = "ൠ";
	TEST(containi(haystack, needle), 0, .description = "Multi bytes unaffected character (containi)");
	TEST(strfind(haystack, needle, .ignorecase = true), 0, .description = "Multi bytes unaffected character (strfind)");

	/**
	 * Multi bytes / Multiple unaffected
	 */
	haystack = "ൠ㋡"
	needle = "ൠ㋡";
	TEST(containi(haystack, needle), 0, .description = "Multi bytes unaffected characters (containi)");
	TEST(strfind(haystack, needle, .ignorecase = true), 0, .description = "Multi bytes unaffected characters (containi)");

	/**
	 * Multi bytes / Sentence / Multiple needle
	 */
	haystack = "L'ÎLE ȒǮɅΌ ЦИТРУС"
	needle = "ȓǯʌό";
	TEST(containi(haystack, needle), strlen("L'ÎLE "), .description = "Multi bytes sentence (containi)");
	TEST(strfind(haystack, needle, .ignorecase = true), strlen("L'ÎLE "), .description = "Multi bytes sentence (strfind)");

	/**
	 * Multi bytes / Sentence / Single needle / End of string
	 */
	haystack = "L'ÎLE ȒǮɅΌ ЦИТРУС"
	needle = "с";
	TEST(containi(haystack, needle), strlen(haystack) - get_char_bytes("С"), .description = "Multi bytes sentence / end of string (containi)");
	TEST(strfind(haystack, needle, .ignorecase = true), strlen(haystack) - get_char_bytes("С"), .description = "Multi bytes sentence / end of string (strfind)");

	/**
	 * Multi bytes / Sentence / Not Found
	 */
	haystack = "L'ÎLE ȒǮɅΌ ЦИТРУС"
	needle = "İ";
	TEST(containi(haystack, needle), -1, .description = "Multi bytes sentence / not found (containi)");
	TEST(strfind(haystack, needle, .ignorecase = true), -1, .description = "Multi bytes sentence / not found (strfind)");

	/**
	 * Multi bytes / Words + invalid
	 */
	haystack = "^xB9hello ^xE1^xB9 ^xE1world!";
	needle = "W";
	TEST(containi(haystack, needle), strlen("^xB9hello ^xE1^xB9 ^xE1"), .description = "Multi bytes words / invalid bytes (containi)");
	TEST(strfind(haystack, needle, .ignorecase = true), strlen("^xB9hello ^xE1^xB9 ^xE1"), .description = "Multi bytes words / invalid bytes (strfind)");

	bench_pass();
}

public test_strfind_pos()
{
	new haystack[64];
	new needle[64];

	/**
	 * Multi bytes / Sentence / Negative position
	 */
	haystack = "L'ÎLE ȒǮɅΌ ЦИТРУС"
	needle = "И";
	TEST(strfind(haystack, needle, .ignorecase = true, .pos = -1), -1, .description = "Negative position");

	/**
	 * Multi bytes / Sentence / Position > length of string
	 */
	haystack = "L'ÎLE ȒǮɅΌ ЦИТРУС"
	needle = "И";
	TEST(strfind(haystack, needle, .ignorecase = true, .pos = strlen(haystack) + 42), -1, .description = "Position > length of string");

	/**
	 * Multi bytes / Sentence / Not found
	 */
	haystack = "L'ÎLE ȒǮɅΌ ЦИТРУС"
	needle = "ʌό";
	TEST(strfind(haystack, needle, .ignorecase = true, .pos = strlen("L'ÎLE ȒǮɅΌ")), -1, .description = "Valid position, needle found");

	/**
	 * Multi bytes / Sentence
	 */
	haystack = "L'ÎLE ȒǮɅΌ ЦИТРУС"
	needle = "ʌό";
	TEST(strfind(haystack, needle, .ignorecase = true, .pos = strlen("L'ÎLE ")), strlen("L'ÎLE ȒǮ"), .description = "Valid position, needle not found");

	bench_pass();
}

public test_equali_strcmp_ignorecase()
{
	new reference[32];

	/**
	 * Basic latin / Single
	 */
	reference = "a";
	TEST(equali(reference, "A"), .description = "Basic latin character (equali)");
	TEST(strcmp(reference, "A", .ignorecase = true), 0, .description = "Basic latin character (strcmp)");
	TEST(strncmp(reference, "A", strlen(reference), .ignorecase = true), 0,  .description = "Basic latin character (strncmp)");

	/**
	 * Basic latin / Multiple
	 */
	reference = "abc";
	TEST(equali(reference, "aBC"), true, .description = "Basic latin characters (equali)");
	TEST(strcmp(reference, "aBC", .ignorecase = true), 0, .description = "Basic latin characters (strcmp)");
	TEST(strncmp(reference, "aBC", strlen(reference), .ignorecase = true), 0,  .description = "Basic latin characters (strncmp)");

	/**
	 * Basic latin / Not found
	 */
	reference = "world";
	TEST(equali(reference, "!?"), false, .description = "Basic latin characters, not found (equali)");
	TEST(strcmp(reference, "!?", .ignorecase = true), 0, TT_NotEqual, .description = "Basic latin characters, not found (strcmp)");
	TEST(strncmp(reference, "!?", strlen(reference), .ignorecase = true), 0, TT_NotEqual, .description = "Basic latin characters, not found (strncmp)");

	/**
	 * Multi bytes / Single
	 */
	reference = "Ʌ";
	TEST(equali(reference, "ʌ"), true, .description = "Multi bytes character (equali)");
	TEST(strcmp(reference, "ʌ", .ignorecase = true), 0, .description = "Multi bytes character (strcmp)");
	TEST(strncmp(reference, "ʌ", strlen(reference), .ignorecase = true), 0, .description = "Multi bytes character (strncmp)");

	/**
	 * Multi bytes / Multiple
	 */
	reference = "ȒǮɅΌ";
	TEST(equali(reference, "ȓǯʌό"), true, .description = "Multi bytes characters (equali)");
	TEST(strcmp(reference, "ȓǯʌό", .ignorecase = true), 0, .description = "Multi bytes characters (strcmp)");
	TEST(strncmp(reference, "ȓǯʌό", strlen(reference), .ignorecase = true), 0, .description = "Multi bytes characters (strncmp)");

	/**
	 * Multi bytes / Not found
	 */
	reference = "ȒǮɅΌ";
	TEST(equali(reference, "ЦИТРУС"), false, .description = "Multi bytes characters, not found (equali)");
	TEST(strcmp(reference, "ЦИТРУС", .ignorecase = true), 0, TT_NotEqual, .description = "Multi bytes characters, not found (strcmp)");
	TEST(strncmp(reference, "ЦИТРУС", strlen(reference), .ignorecase = true), 0, TT_NotEqual, .description = "Multi bytes characters, not found (strncmp)");

	bench_pass();
}

public test_replace_stringex()
{
	new reference[64];

	/**
	 * Multi bytes / Smaller replacement
	 */
	reference = "L'ÎLE ȒǮɅΌ ЦИТРУС";
	TEST(replace_stringex(reference, charsmax(reference), "ʌό", "ൠ", .caseSensitive = false), strlen("L'ÎLE ȒǮൠ"), .description = "Multi bytes characters with smaller replacement (position)");
	TEST(equal(reference, "L'ÎLE ȒǮൠ ЦИТРУС"), .description = "Multi bytes characters with smaller replacement (buffer)");

	/**
	 * Multi bytes / Same replacement
	 */
	reference = "L'ÎLE ȒǮɅΌ ЦИТРУС";
	TEST(replace_stringex(reference, charsmax(reference), "l'î", "L'Î", .caseSensitive = false), strlen("L'Î"), .description = "Multi bytes characters with same replacement (position)");
	TEST(equal(reference, "L'ÎLE ȒǮɅΌ ЦИТРУС"), .description = "Multi bytes characters with smaller replacement (buffer)");

	/**
	 * Multi bytes / Larger replacement / Enough space to move old data
	 */
	reference = "L'ÎLE ȒǮɅΌ ЦИТРУС"
	TEST(replace_stringex(reference, charsmax(reference), "L", "𤭢𤭢", .caseSensitive = false), strlen("𤭢𤭢"), .description = "Multi bytes characters with larger replacement #1 (position)");
	TEST(equal(reference, "𤭢𤭢'ÎLE ȒǮɅΌ ЦИТРУС"), .description = "Multi bytes characters with larger replacement #1 (buffer)");

	/**
	 * Multi bytes / Larger replacement / Not enough space to move old data
	 */
	reference = "L'ÎLE ȒǮɅΌ ЦИТРУС"
	TEST(replace_stringex(reference, strlen(reference), "E", "𤭢", .caseSensitive = false), strlen("L'ÎL𤭢"), .description = "Multi bytes characters with larger replacement #2 (position)");
	TEST(equal(reference, "L'ÎL𤭢ǮɅΌ ЦИТРУС"), .description = "Multi bytes characters with larger replacement #2 (buffer)");

	bench_pass();
}

public test_replace_string()
{
	new reference[64];

	/**
	 * Multi bytes / Smaller replacements
	 */
	reference = "[ȒǮɅΌ ȒǮɅΌ ȒǮɅΌ]";
	TEST(replace_string(reference, charsmax(reference), "ȒǮʌό", "ൠ", .caseSensitive = false), 3, .description = "Multi bytes characters with smaller replacement (count)");
	TEST(equal(reference, "[ൠ ൠ ൠ]"), .description = "Multi bytes characters with smaller replacement (buffer)");

	/**
	 * Multi bytes / Larger replacements / Enough space to move data
	 */
	reference = "[ȒǮɅΌ ȒǮɅΌ ȒǮɅΌ]";
	TEST(replace_string(reference, charsmax(reference), "ʌ", "𤭢", .caseSensitive = false), 3, .description = "Multi bytes characters with larger replacement #1 (count)");
	TEST(equal(reference, "[ȒǮ𤭢Ό ȒǮ𤭢Ό ȒǮ𤭢Ό]"), .description = "Multi bytes characters with larger replacement #1 (buffer)");

	/**
	 * Multi bytes / Larger replacements / Not enough space to move data
	 */
	reference = "[ȒǮɅΌ ȒǮɅΌ ȒǮɅΌ]";
	TEST(replace_string(reference, strlen(reference), "ʌ", "𤭢", .caseSensitive = false), 3, .description = "Multi bytes characters with larger replacement #2 (count) #1");
	TEST(equal(reference, "[ȒǮ𤭢 ȒǮ𤭢 ȒǮ𤭢]"), .description = "Multi bytes characters with larger replacement #2 (buffer)");

	bench_pass();
}

public test_mb_ucfirst()
{
	new reference[64];

	/**
	 * Empty string.
	 */
	reference = "";
	TEST(mb_ucfirst(reference, charsmax(reference)), 0, .description = "Empty string (length)");
	TEST(reference[0], EOS, .description = "Empty string (buffer)");

	/**
	 * Basic latin / Single / Lowercase
	 */
	reference = "c";
	TEST(mb_ucfirst(reference, charsmax(reference)), 1, .description = "Basic latin character (length)");
	TEST(reference[0], 'C', .description = "Basic latin character (buffer)");

	/**
	 * Basic latin / Single / Uppercase
	 */
	reference = "R";
	TEST(mb_ucfirst(reference, charsmax(reference)), 1, .description = "Basic latin uppercase character (length)");
	TEST(reference[0], 'R', .description = "Basic latin uppercase character (buffer)");

	/**
	 * Basic latin / Single / Uunaffected
	 */
	reference = "@";
	TEST(mb_ucfirst(reference, charsmax(reference)), 1, .description = "Basic latin unaffected character (length)");
	TEST(equal(reference, "@"), .description = "Basic latin unaffected character (buffer)");

	/**
	 * Basic latin / Sentence
	 */
	reference = "hello World!";
	TEST(mb_ucfirst(reference, charsmax(reference)), 12, .description = "Basic latin sentence (length)");
	TEST(equal(reference, "Hello World!"), .description = "Basic latin sentence (buffer)");

	/**
	 * Multi Bytes / Single / Unaffected
	 */
	reference = "ൠ";
	TEST(mb_ucfirst(reference, charsmax(reference)) == get_char_bytes(reference), .description = "Multi bytes character (length)");
	TEST(equal(reference, "ൠ"), .description = "Multi bytes character (buffer)");

	/**
	 * Multi Bytes / Words
	 */
	reference = "ȓǯʌό";
	TEST(mb_ucfirst(reference, charsmax(reference)) == strlen("Ȓǯʌό"), .description = "Multi bytes characters (length)");
	TEST(equal(reference, "Ȓǯʌό"), .description = "Multi bytes characters (buffer)");

	/**
	 * Multi Bytes / Single / Not enough space
	 */
	reference = "i̇";
	TEST(mb_ucfirst(reference, 1), 1, .description = "Multi bytes character / not enough space (length)");
	TEST(reference[0] == 'I', .description = "Multi bytes character / not enough space (buffer)");

	/**
	 * Multi Bytes / Multiple / Not enough space
	 */
	reference = "i̇i̇";
	TEST(mb_ucfirst(reference, 2), 1, .description = "Multi bytes characters / not enough space (length)");
	TEST(equal(reference, "I"), .description = "Multi bytes characters / not enough space (buffer)");

	bench_pass();
}

public test_mb_strtolower_upper()
{
	new reference[64];

	/**
	 * Empty string.
	 */
	reference = "";
	TEST(mb_strtolower(reference, charsmax(reference)), 0, .description = "Empty string / return (mb_strtolower)");
	TEST(reference[0], EOS, .description = "Empty string / buffer (mb_strtolower)");
	TEST(mb_strtoupper(reference, charsmax(reference)), 0, .description = "Empty string / return (mb_strtoupper)");
	TEST(reference[0], EOS, .description = "Empty string / buffer (mb_strtoupper)");

	/**
	 * Basic latin / Single lowercase
	 */
	reference = "c";
	TEST(mb_strtolower(reference, charsmax(reference)), 1, .description = "Basic latin character / return (mb_strtolower)");
	TEST(reference[0], 'c', .description = "Basic latin character / buffer (mb_strtolower)");
	TEST(mb_strtoupper(reference, charsmax(reference)), 1, .description = "Basic latin character / return (mb_strtoupper)");
	TEST(reference[0], 'C', .description = "Basic latin character / buffer (mb_strtoupper)");

	/**
	 * Basic latin / Single uppercase
	 */
	reference = "R";
	TEST(mb_strtolower(reference, charsmax(reference)), 1, .description = "Basic latin uppercase character / return (mb_strtolower)");
	TEST(reference[0], 'r', .description = "Basic latin uppercase character / buffer (mb_strtolower)");
	TEST(mb_strtoupper(reference, charsmax(reference)), 1, .description = "Basic latin uppercase character / return (mb_strtoupper)");
	TEST(reference[0], 'R', .description = "Basic latin uppercase character / buffer (mb_strtoupper)");

	/**
	 * Basic latin / Single unaffected
	 */
	reference = "@";
	TEST(mb_strtolower(reference, charsmax(reference)), 1, .description = "Basic latin unaffected character / return (mb_strtolower)");
	TEST(equal(reference, "@"), .description = "Basic latin unaffected character / buffer (mb_strtolower)");
	TEST(mb_strtoupper(reference, charsmax(reference)), 1, .description = "Basic latin unaffected character / return (mb_strtoupper)");
	TEST(equal(reference, "@"), .description = "Basic latin unaffected character / buffer (mb_strtoupper)");

	/**
	 * Basic latin / Multiple lowercase
	 */
	reference = "ab";
	TEST(mb_strtolower(reference, charsmax(reference)), 2, .description = "Basic latin lowercase characters / return (mb_strtolower)");
	TEST(equal(reference, "ab"), .description = "Basic latin lowercase characters / buffer (mb_strtolower)");
	TEST(mb_strtoupper(reference, charsmax(reference)), 2, .description = "Basic latin lowercase characters / return (mb_strtoupper)");
	TEST(equal(reference, "AB"), .description = "Basic latin lowercase characters / buffer (mb_strtoupper)");

	/**
	 * Basic latin / Multiple uppercase
	 */
	reference = "AB";
	TEST(mb_strtolower(reference, charsmax(reference)), 2, .description = "Basic latin uppercase characters / return (mb_strtolower)");
	TEST(equal(reference, "ab"), .description = "Basic latin uppercase characters / buffer (mb_strtolower)");
	TEST(mb_strtoupper(reference, charsmax(reference)), 2, .description = "Basic latin uppercase characters / return (mb_strtoupper)");
	TEST(equal(reference, "AB"), .description = "Basic latin uppercase characters / buffer (mb_strtoupper)");

	/**
	 * Basic latin / Multiple unaffected
	 */
	reference = "(-(#)-)";
	TEST(mb_strtolower(reference, charsmax(reference)), 7, .description = "Basic latin unaffected characters / return (mb_strtolower)");
	TEST(equal(reference, "(-(#)-)"), .description = "Basic latin unaffected characters / buffer (mb_strtolower)");
	TEST(mb_strtoupper(reference, charsmax(reference)), 7, .description = "Basic latin unaffected characters / return (mb_strtoupper)");
	TEST(equal(reference, "(-(#)-)"), .description = "Basic latin unaffected characters / buffer (mb_strtoupper)");

	/**
	 * Basic latin / Sentence
	 */
	reference = "Hello World!";
	TEST(mb_strtolower(reference, charsmax(reference)), 12, .description = "Basic latin sentence / return (mb_strtolower)");
	TEST(equal(reference, "hello world!"), .description = "Basic latin sentence / buffer (mb_strtolower)");
	TEST(mb_strtoupper(reference, charsmax(reference)), 12, .description = "Basic latin sentence / return (mb_strtoupper)");
	TEST(equal(reference, "HELLO WORLD!"), .description = "Basic latin sentence / buffer (mb_strtoupper)");

	/**
	 * Multi bytes / Single unaffected
	 */
	reference = "ൠ";
	TEST(mb_strtolower(reference, charsmax(reference)) == get_char_bytes(reference), .description = "Multi bytes unaffected character / return (mb_strtolower)");
	TEST(equal(reference, "ൠ"), .description = "Multi bytes unaffected character / buffer (mb_strtolower)");
	TEST(mb_strtoupper(reference, charsmax(reference)) == get_char_bytes(reference), .description = "Multi bytes unaffected character / return (mb_strtoupper)");
	TEST(equal(reference, "ൠ"), .description = "Multi bytes unaffected character / buffer (mb_strtoupper)");

	/**
	 * Multi bytes / Words
	 */
	reference = "L'ÎLE ȒǮɅΌ ЦИТРУС";
	TEST(mb_strtolower(reference, charsmax(reference)) == strlen("l'île") + strlen("ȓǯʌό") + strlen("цитрус") + strlen(" ") * 2, .description = "Multi bytes words / buffer (mb_strtolower)");
	TEST(equal(reference, "l'île ȓǯʌό цитрус"), .description = "Multi bytes words / return (mb_strtolower)");
	TEST(mb_strtoupper(reference, charsmax(reference)) == strlen("L'ÎLE") + strlen("ȒǮɅΌ") + strlen("ЦИТРУС") + strlen(" ") * 2, .description = "Multi bytes words / buffer (mb_strtoupper)");
	TEST(equal(reference, "L'ÎLE ȒǮɅΌ ЦИТРУС"), .description = "Multi bytes words / return (mb_strtoupper)");

	/**
	 * Multi bytes / Single not enough space
	 * Note: UC: "İ" = 2 bytes, LC: "i̇" = 3 bytes
	 */
	reference = "İ";
	TEST(mb_strtolower(reference, 2), 1, .description = "Multi bytes character / not enough space / buffer (mb_strtolower)");
	TEST(reference[0] == 'i', .description = "Multi bytes character / not enough space / buffer (mb_strtolower)");

	/**
	 * Multi bytes / Multiple not enough space
	 */
	reference = "İİ";
	TEST(mb_strtolower(reference, 3), 3, .description = "Multi bytes characters / not enough space / buffer (mb_strtolower)");
	TEST(equal(reference, "i̇"), .description = "Multi bytes characters / not enough space / buffer (mb_strtolower)");

	/**
	 * Multi bytes / Single enough space
	 */
	reference = "İ";
	TEST(mb_strtolower(reference, charsmax(reference)), 3, .description = "Multi bytes character / enough space / buffer (mb_strtolower)");
	TEST(equal(reference, "i̇"), .description = "Multi bytes character / enough space / buffer (mb_strtolower)");

	/**
	 * Multi bytes / Words + invalid 1
	 */
	reference = "Hello^xE1^xB9";
	TEST(mb_strtolower(reference, charsmax(reference)), strlen(reference), .description = "Multi bytes words / invalid / return #1 (mb_strtolower)");
	TEST(equal(reference, "hello^xE1^xB9"), .description = "Multi bytes words / invalid / buffer #1 (mb_strtolower)");
	TEST(mb_strtoupper(reference, charsmax(reference)), strlen(reference), .description = "Multi bytes words / invalid / return #1 (mb_strtoupper)");
	TEST(equal(reference, "HELLO^xE1^xB9"), .description = "Multi bytes words / invalid / buffer #1 (mb_strtoupper)");

	/**
	 * Multi bytes / Words + invalid 2
	 */
	reference = "Hello^xE1^xB9World!";
	TEST(mb_strtolower(reference, charsmax(reference)), strlen(reference), .description = "Multi bytes character / enough space / return #2 (mb_strtolower)");
	TEST(equal(reference, "hello^xE1^xB9world!"), .description = "Multi bytes character / enough space / buffer #2 (mb_strtolower)");
	TEST(mb_strtoupper(reference, charsmax(reference)), strlen(reference), .description = "Multi bytes character / enough space / return #2 (mb_strtoupper)");
	TEST(equal(reference, "HELLO^xE1^xB9WORLD!"), .description = "Multi bytes character / enough space / buffer #2 (mb_strtoupper)");

	bench_pass();
}

public test_mb_strtotitle()
{
	new reference[64];

	/**
	 * Empty string without maxlen.
	 */
	reference = "";
	TEST(mb_strtotitle(reference), 0, .description = "Empty string without maxlen (length)");
	TEST(reference[0], EOS, .description = "Empty string without maxlen (buffer)");

	/**
	 * Empty string with maxlen.
	 */
	reference = "";
	TEST(mb_strtotitle(reference, charsmax(reference)), 0, .description = "Empty string with maxlen (length)");
	TEST(reference[0], EOS, .description = "Empty string with maxlen (buffer)");

	/**
	 * Basic latin / Single
	 */
	reference = "a";
	TEST(mb_strtotitle(reference), 1, .description = "Basic latin character (length)");
	TEST(reference[0], 'A', .description = "Basic latin character (buffer)");

	/**
	 * Basic latin / Single unaffected
	 */
	reference = "@";
	TEST(mb_strtotitle(reference), 1, .description = "Basic latin character unaffected (length)");
	TEST(reference[0], '@', .description = "Basic latin character unaffected (buffer)");

	/**
	 * Basic latin / Single / Maxlen to 0
	 */
	reference = "a";
	TEST(mb_strtotitle(reference, 0), 1, .description = "Basic latin character with maxlen to 0 (length)");
	TEST(reference[0], 'A', .description = "Basic latin character with maxlen to 0 (buffer)");

	/**
	 * Basic latin / Single / Maxlen to 1
	 */
	reference = "a";
	TEST(mb_strtotitle(reference, 1), 1, .description = "Basic latin character with maxlen to 1 (length)");
	TEST(reference[0], 'A', .description = "Basic latin character with maxlen to 1 (buffer)");

	/**
	 * Basic latin / Multiple lowercase
	 */
	reference = "aaa";
	TEST(mb_strtotitle(reference), 3, .description = "Basic latin lowercase characters (length)");
	TEST(equal(reference, "Aaa"), .description = "Basic latin lowercase characters (buffer)");

	/**
	 * Basic latin / Multiple uppercase
	 */
	reference = "AAA";
	TEST(mb_strtotitle(reference), 3, .description = "Basic latin uppercase characters (length)");
	TEST(equal(reference, "Aaa"), .description = "Basic latin uppercase characters (buffer)");

	/**
	 * Basic latin / Multiple unaffected
	 */
	reference = "@@@";
	TEST(mb_strtotitle(reference), 3, .description = "Basic latin characters unaffected (length)");
	TEST(equal(reference, "@@@"), .description = "Basic latin characters unaffected (buffer)");

	/**
	 * Basic latin / Multiple / With maxlen
	 */
	reference = "aaa";
	TEST(mb_strtotitle(reference, 2), 2, .description = "Basic latin characters with maxlen (length)");
	TEST(equal(reference, "Aa"), .description = "Basic latin characters with maxlen (buffer)");

	/**
	 * General / Single
	 */
	reference = "ȓ";
	TEST(mb_strtotitle(reference), 2, .description = "General character (length)");
	TEST(equal(reference, "Ȓ"), .description = "General character (buffer)");

	/**
	 * General / Single truncated / With maxlen
	 */
	reference = "ȓ";
	TEST(mb_strtotitle(reference, 1), 0, .description = "General character truncated (length)");
	TEST(equal(reference, ""), .description = "General character truncated (buffer)");

	/**
	 * General / Word
	 */
	reference = "цитрус";
	TEST(mb_strtotitle(reference), strlen("Цитрус"), .description = "General word (length)");
	TEST(equal(reference, "Цитрус"), .description = "General word (buffer)");

	/**
	 * General / Word truncated / With maxlen
	 */
	reference = "цитрус";
	TEST(mb_strtotitle(reference, 3), strlen("Ц"), .description = "General word truncated (length)");
	TEST(equal(reference, "Ц"), .description = "General word truncated (buffer)");

	/**
	 * General / Sentence / Lowercase
	 */
	reference = "l'île ȓǯʌό цитрус";
	TEST(mb_strtotitle(reference), strlen("L'Île Ȓǯʌό Цитрус"), .description = "General lowercase sentence (length)");
	TEST(equal(reference, "L'Île Ȓǯʌό Цитрус"), .description = "General lowercase sentence (buffer)");

	/**
	 * General / Sentence / Uppercase
	 */
	reference = "L'ÎLE ȒǮɅΌ ЦИТРУС";
	TEST(mb_strtotitle(reference), strlen("L'Île Ȓǯʌό Цитрус"), .description = "General uppercase sentence (length)");
	TEST(equal(reference, "L'Île Ȓǯʌό Цитрус"), .description = "General uppercase sentence (buffer)");

	bench_pass();
}

public test_is_string_category()
{
	new reference[64];
	new outputsize;

	/**
	 * Empty string
	 */
	reference = "";
	TEST(is_string_category(reference, charsmax(reference), UTF8C_ALL, outputsize), true, .description = "Empty string (return)");
	TEST(outputsize, 0, .description = "Empty string (output size)");

	/**
	 * Basic latin / Single
	 */
	reference = "a";
	TEST(is_string_category(reference, charsmax(reference), UTF8C_LETTER_LOWERCASE, outputsize), true, .description = "Basic latin character (return)");
	TEST(outputsize, 1, .description = "Basic latin character (output size)");

	/**
	 * Basic latin / Single / Mismatch
	 */
	reference = "!";
	TEST(is_string_category(reference, charsmax(reference), UTF8C_LETTER_UPPERCASE, outputsize), false, .description = "Basic latin mismatched character (return)");
	TEST(outputsize, 0, .description = "Basic latin mismatched character (output size)");

	/**
	 * Basic latin / Multiple
	 */
	reference = "123";
	TEST(is_string_category(reference, charsmax(reference), UTF8C_NUMBER_DECIMAL, outputsize), true, .description = "Basic latin characters (return)");
	TEST(outputsize, strlen(reference), .description = "Basic latin characters (output size)");

	/**
	 * Basic latin / Multiple / Mismatch at start
	 */
	reference = "(good)";
	TEST(is_string_category(reference, charsmax(reference), UTF8C_LETTER_LOWERCASE, outputsize), false, .description = "Basic latin characters / mismatched at start (return)");
	TEST(outputsize, 0, .description = "Basic latin characters / mismatched at start (output size)");

	/**
	 * Basic latin / Multiple / Mismatch before end
	 */
	reference = "    %";
	TEST(is_string_category(reference, charsmax(reference), UTF8C_SEPARATOR_SPACE, outputsize), false, .description = "Basic latin characters / mismatched before end (return)");
	TEST(outputsize, 4, .description = "Basic latin characters / mismatched before end (output size)");

	/**
	 * Multi Byte / Single
	 */
	reference = "^xC7^x85";
	TEST(is_string_category(reference, charsmax(reference), UTF8C_LETTER_TITLECASE, outputsize), true, .description = "Multi bytes single character (return)");
	TEST(outputsize, 2, .description = "Multi bytes single character (output size)");

	/**
	 * Multi Byte / Multiple
	 */
	reference = "^xD8^x87^xC2^xAC^xCF^xB6";
	TEST(is_string_category(reference, charsmax(reference), UTF8C_SYMBOL_MATH, outputsize), true, .description = "Multi bytes characters (return)");
	TEST(outputsize, 6, .description = "Multi bytes characters (output size)");

	/**
	 * Multi Byte / Multiple / Mismatch at start
	 */
	reference = "^xDE^x8A^xF0^x9B^xB0^xA2^xC2^xAA^xF0^x96^xAC^xBE";
	TEST(is_string_category(reference, charsmax(reference), UTF8C_LETTER_OTHER, outputsize), false, .description = "Multi bytes characters / mismatched at start (return)");
	TEST(outputsize, 8, .description = "Multi bytes characters / mismatched at start (output size)");

	/**
	 * Incalid code point / Single
	 */
	reference = "\xC5";
	TEST(is_string_category(reference, charsmax(reference), UTF8C_SYMBOL_OTHER, outputsize), false, .description = "Invalid code point (return)");
	TEST(outputsize, 0, .description = "Invalid code point (output size)");

	bench_pass();
}

// The cell before a destination buffer, laid out just below it in the data section.
new ZeroLengthGuard = 0xC3;
new ZeroLengthBuffer[4] = { 'x', ... };

public test_zero_length_copy_leaves_previous_cell()
{
	/**
	 * A copy with a maximum length of 0 writes an empty string. The cell before the buffer looks like
	 * the lead byte of an unfinished UTF-8 character; it must not be read as part of the copy.
	 */
	new Trie:trie = TrieCreate();
	TrieSetString(trie, "key", "value");
	TrieGetString(trie, "key", ZeroLengthBuffer, 0);
	TrieDestroy(trie);

	ASSERT_EQ(ZeroLengthGuard, 0xC3);
	ASSERT_EQ(ZeroLengthBuffer[0], 0);
	ASSERT_EQ(ZeroLengthBuffer[1], 'x');
	bench_pass();
}
