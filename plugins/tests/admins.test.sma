// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Port of plugins/testsuite/admins_test.sma. The admin cache is global: admins a configured plugin
// loaded are set aside before the test and pushed back after it.
//

#include <amxmodx>
#include <amxxbench>

#define MAX_SAVED_ADMINS 64

new __testnumber;

enum TestType
{
	TT_Equal = 0,
	TT_LessThan,
	TT_GreaterThan,
	TT_LessThanEqual,
	TT_GreaterThanEqual,
	TT_NotEqual
};

new TestWords[6][] = {
 "==",
 "<",
 ">",
 "<=",
 ">=",
 "!="
};

new SavedAuth[MAX_SAVED_ADMINS][44];
new SavedPassword[MAX_SAVED_ADMINS][32];
new SavedAccess[MAX_SAVED_ADMINS];
new SavedFlags[MAX_SAVED_ADMINS];
new SavedNum;

stock bool:test(A,B=0,TestType:Type=TT_Equal)
{
	++__testnumber;

	new passed=0;

	switch (Type)
	{
		case TT_Equal: if (A==B) passed=1;
		case TT_LessThan: if (A<B) passed=1;
		case TT_GreaterThan: if (A>B) passed=1;
		case TT_LessThanEqual: if (A<=B) passed=1;
		case TT_GreaterThanEqual: if (A>=B) passed=1;
		case TT_NotEqual: if (A!=B) passed=1;
	}

	if (!passed)
	{
		bench_fail("Failed test #%d (%d %s %d)",__testnumber,A,TestWords[_:Type],B);
		return false;
	}
	return true;
}


public bench_setup()
{
	SavedNum = 0;
	new num = admins_num();
	for (new i = 0; i < num && SavedNum < MAX_SAVED_ADMINS; i++)
	{
		admins_lookup(i,AdminProp_Auth,SavedAuth[SavedNum],charsmax(SavedAuth[]));
		admins_lookup(i,AdminProp_Password,SavedPassword[SavedNum],charsmax(SavedPassword[]));
		SavedAccess[SavedNum]=admins_lookup(i,AdminProp_Access);
		SavedFlags[SavedNum]=admins_lookup(i,AdminProp_Flags);
		SavedNum++;
	}
	bench_check(SavedNum == num, "configured admins fit in MAX_SAVED_ADMINS");
	admins_flush();
}

public bench_teardown()
{
	admins_flush();
	for (new i = 0; i < SavedNum; i++)
	{
		admins_push(SavedAuth[i],SavedPassword[i],SavedAccess[i],SavedFlags[i]);
	}
}

public test_admins()
{

	new AuthData[44];
	new Password[32];
	new Access;
	new Flags;
	new id;

	__testnumber=0;


	if (!test(admins_num(),0)) return;

	admins_push("STEAM_0:1:23456","",read_flags("abcdefghijklmnopqrstu"),read_flags("ce"));

	if (!test(admins_num(),1)) return;

	admins_push("ABCDEFGHIJKLMNOP","abcdefghijklmnop",read_flags("z"),read_flags("a"));

	if (!test(admins_num(),2)) return;

	admins_push("ZYXWVUTSRQPONMLKJIHGFEDCBA","plop",read_flags("a"),read_flags("b"));

	if (!test(admins_num(),3)) return;

	id=0;

	admins_lookup(id,AdminProp_Auth,AuthData,sizeof(AuthData)-1);
	admins_lookup(id,AdminProp_Password,Password,sizeof(Password)-1);
	Access=admins_lookup(id,AdminProp_Access);
	Flags=admins_lookup(id,AdminProp_Flags);

	if (!test(strcmp(AuthData,"STEAM_0:1:23456"),0)) return;
	if (!test(strcmp(Password,""),0)) return;
	if (!test(Access,read_flags("abcdefghijklmnopqrstu"))) return;
	if (!test(Flags,read_flags("ce"))) return;

	id++;

	admins_lookup(id,AdminProp_Auth,AuthData,sizeof(AuthData)-1);
	admins_lookup(id,AdminProp_Password,Password,sizeof(Password)-1);
	Access=admins_lookup(id,AdminProp_Access);
	Flags=admins_lookup(id,AdminProp_Flags);

	if (!test(strcmp(AuthData,"ABCDEFGHIJKLMNOP"),0)) return;
	if (!test(strcmp(Password,"abcdefghijklmnop"),0)) return;
	if (!test(Access,read_flags("z"))) return;
	if (!test(Flags,read_flags("a"))) return;

	id++;

	admins_lookup(id,AdminProp_Auth,AuthData,sizeof(AuthData)-1);
	admins_lookup(id,AdminProp_Password,Password,sizeof(Password)-1);
	Access=admins_lookup(id,AdminProp_Access);
	Flags=admins_lookup(id,AdminProp_Flags);

	if (!test(strcmp(AuthData,"ZYXWVUTSRQPONMLKJIHGFEDCBA"),0)) return;
	if (!test(strcmp(Password,"plop"),0)) return;
	if (!test(Access,read_flags("a"))) return;
	if (!test(Flags,read_flags("b"))) return;

	admins_flush();

	if (!test(admins_num(),0)) return;

	bench_pass();
}
