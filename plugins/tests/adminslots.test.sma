// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for adminslots.sma (Slots Reservation): amx_reservation kicks a player without
// ADMIN_RESERVATION who takes a reserved slot, and amx_hideslots sets sv_visiblemaxplayers to
// the public slots, one more once they fill, and back to the default (-1) when every slot shows.
// The server runs with 8 slots. Reservation access comes from amx_default_access "b" (admin.sma
// gives it to every player not in users.ini).
//

#include <amxmodx>
#include <amxmisc>
#include <amxxbench>

new g_SavedVisible
new g_SavedDefaultAccess[32]
new g_Puppets[MAX_PLAYERS + 1]
new g_PuppetNum
new g_KickedUserId
new g_Kicked

public plugin_init()
{
	register_plugin("Slots Reservation Tests", AMXX_VERSION_STR, "AMXX Dev Team")
}

public bench_setup()
{
	g_SavedVisible = get_cvar_num("sv_visiblemaxplayers")
	get_cvar_string("amx_default_access", g_SavedDefaultAccess, charsmax(g_SavedDefaultAccess))
	g_PuppetNum = 0
	g_Kicked = 0
}

public bench_teardown()
{
	set_cvar_num("amx_hideslots", 0)
	set_cvar_num("amx_reservation", 0)
	set_cvar_num("sv_visiblemaxplayers", g_SavedVisible)
	set_cvar_string("amx_default_access", g_SavedDefaultAccess)
}

AddPuppet(const name[])
{
	new id = bench_puppet(name)
	if (id > 0)
		g_Puppets[g_PuppetNum++] = id
	return id
}

public test_server_has_eight_slots()
{
	// The rest of the file counts on this.
	ASSERT_EQ(MaxClients, 8)
	ASSERT_EQ(get_playersnum_ex(GetPlayers_IncludeConnecting), 0)
	bench_pass()
}

public test_reservation_alone_keeps_every_slot_visible()
{
	set_cvar_num("sv_visiblemaxplayers", 5)
	set_cvar_num("amx_reservation", 2)
	ASSERT_EQ(get_cvar_num("sv_visiblemaxplayers"), -1)
	bench_pass()
}

public test_hideslots_without_reservation_does_nothing()
{
	set_cvar_num("sv_visiblemaxplayers", 5)
	set_cvar_num("amx_hideslots", 1)
	ASSERT_EQ(get_cvar_num("sv_visiblemaxplayers"), -1)
	bench_pass()
}

public test_hideslots_shows_public_slots()
{
	set_cvar_num("amx_reservation", 2)
	set_cvar_num("amx_hideslots", 1)
	// No players: the six public slots show.
	ASSERT_EQ(get_cvar_num("sv_visiblemaxplayers"), 6)
	// The puppets have reservation access, so none is kicked.
	set_cvar_string("amx_default_access", "b")
	for (new i = 1; i <= 5; i++)
	{
		ASSERT(AddPuppet(fmt("slot%d", i)) > 0)
		ASSERT_EQ(get_cvar_num("sv_visiblemaxplayers"), 6)
	}
	// The public slots are full: one more shows, so a reserved player can see a way in.
	ASSERT(AddPuppet("slot6") > 0)
	ASSERT_EQ(get_cvar_num("sv_visiblemaxplayers"), 7)
	// Seven players: the eighth slot shows, which is every slot, so the default comes back.
	ASSERT(AddPuppet("slot7") > 0)
	ASSERT_EQ(get_cvar_num("sv_visiblemaxplayers"), -1)
	// A full server shows every slot too.
	ASSERT(AddPuppet("slot8") > 0)
	ASSERT_EQ(get_cvar_num("sv_visiblemaxplayers"), -1)
	// Turning hiding off also gives the default.
	set_cvar_num("sv_visiblemaxplayers", 5)
	set_cvar_num("amx_hideslots", 0)
	ASSERT_EQ(get_cvar_num("sv_visiblemaxplayers"), -1)
	bench_pass()
}

public test_reserved_slot_kicks_player_without_access()
{
	// One public slot.
	set_cvar_num("amx_reservation", 7)
	ASSERT(AddPuppet("firstin") > 0)
	new late = AddPuppet("latecomer")
	ASSERT(late > 0)
	g_Kicked = late
	g_KickedUserId = get_user_userid(late)
	bench_wait_until("kicked_gone", "check_reserved_admin", 5.0)
}

public kicked_gone()
{
	return !is_user_connected(g_Kicked) || get_user_userid(g_Kicked) != g_KickedUserId
}

public check_reserved_admin()
{
	ASSERT(is_user_connected(g_Puppets[0]))
	// A player with ADMIN_RESERVATION may take a reserved slot.
	set_cvar_string("amx_default_access", "b")
	new vip = bench_puppet("vipplayer")
	ASSERT(vip > 0)
	g_Kicked = vip
	g_KickedUserId = get_user_userid(vip)
	bench_next("vip_stays", 0.5)
}

public vip_stays()
{
	ASSERT_FALSE(kicked_gone())
	ASSERT(access(g_Kicked, ADMIN_RESERVATION))
	bench_pass()
}
