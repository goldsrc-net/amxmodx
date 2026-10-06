// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for telemenu.sma (Teleport Menu): access, the locked first view, saving a location,
// teleporting to it (ducking included) or to where a dead admin stands, refusing dead targets,
// immunity, admin marks and paging. Puppets answer the menu with menuselect.
//
// The plugin keeps each slot's location option for the whole map and only a slot that never
// saved a location shows it locked, so the tests that need a known option bring it to "current
// location" first (Normalize), and the locked test looks for a slot that never saved one.
//

#include <amxmodx>
#include <amxmisc>
#include <fakemeta>
#include <amxxbench>

new g_P[MAX_PLAYERS + 1]
new g_PNum
new g_Tries
new Float:g_Saved[3]

public plugin_init()
{
	register_plugin("Teleport Menu Tests", AMXX_VERSION_STR, "AMXX Dev Team")

	bench_coverage_ignore("telemenu.sma", 97, 97, "the duck view height for cstrike, czero, valve, tfc and gearbox; the server runs ts")
	bench_coverage_ignore("telemenu.sma", 99, 99, "the duck view height for dod; the server runs ts")
	bench_coverage_ignore("telemenu.sma", 103, 103, "the fallback for a mod with no known duck view height; the server runs ts")
	bench_coverage_ignore("telemenu.sma", 183, 183, "colored menus, which AMX Mod X turns off for ts")
	bench_coverage_ignore("telemenu.sma", 204, 204, "colored menus, which AMX Mod X turns off for ts")
}

// ---------------------------------------------------------------------------------------------
// Helpers

// Creates count puppets named prefix1..prefixN and calls step once every one is alive.
SpawnPuppets(const prefix[], count, const step[])
{
	g_PNum = 0
	new name[32]
	for (new i = 1; i <= count; i++)
	{
		formatex(name, charsmax(name), "%s%d", prefix, i)
		new id = bench_puppet(name)
		if (!bench_check(id > 0, "puppet created"))
			return
		g_P[g_PNum++] = id
	}
	bench_wait_until("AllAlive", step, 30.0)
}

public AllAlive()
{
	new bool:ok = true
	for (new i = 0; i < g_PNum; i++)
	{
		if (is_user_connected(g_P[i]) && !is_user_alive(g_P[i]))
		{
			engclient_cmd(g_P[i], "respawn")
			ok = false
		}
	}
	return ok
}

SetFlags(id, const flags[])
{
	remove_user_flags(id)
	set_user_flags(id, read_flags(flags))
}

// The text of the newest menu sent to id, its ShowMenu parts joined.
MenuText(id, out[], len)
{
	new BenchMsg:msg = BenchMsg:0, part[256], bool:fresh = true
	out[0] = 0
	while ((msg = bench_msg_next(id, msg, "ShowMenu")) != BenchMsg:0)
	{
		if (fresh)
			out[0] = 0
		bench_msg_text(msg, part, charsmax(part))
		add(out, len, part)
		fresh = bench_msg_int(msg, 2) == 0
	}
}

MenuKeys(id)
{
	new BenchMsg:msg = bench_msg_last(id, "ShowMenu")
	return msg == BenchMsg:0 ? -1 : bench_msg_int(msg, 0)
}

bool:MenuContains(id, const text[])
{
	new body[512]
	MenuText(id, body, charsmax(body))
	return contain(body, text) != -1
}

#define ASSERT_MENU(%0,%1)      if (!MenuHas(%0, %1, true)) return
#define ASSERT_NOT_MENU(%0,%1)  if (!MenuHas(%0, %1, false)) return

bool:MenuHas(id, const text[], bool:wanted)
{
	new body[512]
	MenuText(id, body, charsmax(body))
	if ((contain(body, text) != -1) == wanted)
		return true
	replace_all(body, charsmax(body), "^n", "|")
	bench_fail("menu %s ^"%s^": ^"%s^"", wanted ? "lacks" : "has", text, body)
	return false
}

// The key (1-based, on page 1) that selects player p in a player menu.
KeyOf(p)
{
	new players[MAX_PLAYERS], num
	get_players(players, num)
	for (new i = 0; i < num; i++)
		if (players[i] == p)
			return i + 1
	return 0
}

bool:SameOrigin(a, const Float:origin[3])
{
	new Float:o[3]
	pev(a, pev_origin, o)
	return floatabs(o[0] - origin[0]) < 1.0 && floatabs(o[1] - origin[1]) < 1.0 && floatabs(o[2] - origin[2]) < 1.0
}

// Opens the menu for id and brings its location option to "current location" (0).
Normalize(id)
{
	bench_puppet_cmd(id, "amx_teleportmenu")
	if (MenuContains(id, "#. Current Location"))
	{
		// Locked (never saved): saving unlocks it at 0.
		bench_puppet_cmd(id, "menuselect 8")
		return
	}
	if (MenuContains(id, "7. Current Location"))
		return
	// 1 or 2: the toggle gives 0 or the locked -1.
	bench_puppet_cmd(id, "menuselect 7")
	if (MenuContains(id, "#. Current Location"))
		bench_puppet_cmd(id, "menuselect 8")
}

// Normalizes id, saves its origin as the location and switches to "to location" (1).
SaveLocation(id)
{
	Normalize(id)
	pev(id, pev_origin, g_Saved)
	bench_puppet_cmd(id, "menuselect 8")
	bench_puppet_cmd(id, "menuselect 7")
}

// ---------------------------------------------------------------------------------------------
// Tests

public test_no_access()
{
	SpawnPuppets("tnoacc", 1, "NoAccess_Spawned")
}

public NoAccess_Spawned()
{
	new id = g_P[0]
	SetFlags(id, "z")
	bench_puppet_cmd(id, "amx_teleportmenu")
	ASSERT_MSG(id, "", "You have no access to that command")
	ASSERT_EQ(bench_msg_count(id, "ShowMenu"), 0)
	bench_pass()
}

// A slot that never saved a location: everyone greyed, location locked, only 8 and 0 work.
// Saving unlocks "current location", which still keeps an alive admin from picking players;
// switching to "to location" enables them.
public test_alive_admin_starts_locked()
{
	g_PNum = 0
	g_Tries = 0
	TryFreshSlot()
}

TryFreshSlot()
{
	new name[32]
	formatex(name, charsmax(name), "tfresh%d", g_Tries + 1)
	new id = bench_puppet(name)
	ASSERT(id > 0)
	g_P[g_PNum++] = id
	bench_puppet_spawn(id, "Fresh_Spawned", 20.0, "respawn")
}

public Fresh_Spawned(id)
{
	SetFlags(id, "h")
	bench_puppet_cmd(id, "amx_teleportmenu")
	if (!MenuContains(id, "#. Current Location"))
	{
		// This slot saved a location in an earlier test; keep it taken and try the next.
		ASSERT(++g_Tries < 7)
		TryFreshSlot()
		return
	}
	new line[48]
	ASSERT_MENU(id, "Teleport Menu 1/1")
	formatex(line, charsmax(line), "#. tfresh%d^n", g_Tries + 1)
	ASSERT_MENU(id, line)
	ASSERT_MENU(id, "8. Save Location")
	ASSERT_MENU(id, "^n0. Exit")
	ASSERT_EQ(MenuKeys(id), MENU_KEY_0|MENU_KEY_8)

	// 7 is not enabled yet: nothing happens.
	new before = bench_msg_count(id, "ShowMenu")
	bench_puppet_cmd(id, "menuselect 7")
	ASSERT_EQ(bench_msg_count(id, "ShowMenu"), before)

	bench_puppet_cmd(id, "menuselect 8")
	ASSERT_MENU(id, "^n7. Current Location")
	ASSERT_MENU(id, line)
	ASSERT_EQ(MenuKeys(id), MENU_KEY_0|MENU_KEY_7|MENU_KEY_8)

	new Float:o[3]
	pev(id, pev_origin, o)
	bench_puppet_cmd(id, "menuselect 7")
	formatex(line, charsmax(line), "7. To location: %.0f %.0f %.0f", o[0], o[1], o[2])
	ASSERT_MENU(id, line)
	formatex(line, charsmax(line), "%d. tfresh%d *", KeyOf(id), g_Tries + 1)
	ASSERT_MENU(id, line)
	ASSERT(MenuKeys(id) & (1 << (KeyOf(id) - 1)))
	bench_pass()
}

public test_teleport_to_saved_location()
{
	SpawnPuppets("tsave", 2, "Saved_Spawned")
}

public Saved_Spawned()
{
	new admin = g_P[0], target = g_P[1]
	SetFlags(admin, "h")
	SaveLocation(admin)
	ASSERT_FALSE(SameOrigin(target, g_Saved))

	bench_puppet_cmd(admin, "menuselect %d", KeyOf(target))
	ASSERT(SameOrigin(target, g_Saved))
	ASSERT_MSG(admin, "", "ADMIN tsave1: teleport tsave2")
	ASSERT_MSG(target, "", "ADMIN tsave1: teleport tsave2")
	// The menu comes back.
	ASSERT_MENU(admin, "7. To location")
	bench_pass()
}

// A location saved while ducking puts the teleported player in the ducking state (and the ducking
// view, 16 units on ts) so it fits there (once set on the admin instead: aa67fae7 moved FL_DUCKING
// from the player to the admin).
public test_ducking_location_ducks_the_player()
{
	SpawnPuppets("tduck", 2, "Duck_Spawned")
}

public Duck_Spawned()
{
	new admin = g_P[0], target = g_P[1]
	SetFlags(admin, "h")
	Normalize(admin)
	set_pev(admin, pev_flags, pev(admin, pev_flags) | FL_DUCKING)
	pev(admin, pev_origin, g_Saved)
	bench_puppet_cmd(admin, "menuselect 8")
	set_pev(admin, pev_flags, pev(admin, pev_flags) & ~FL_DUCKING)
	set_pev(admin, pev_view_ofs, Float:{0.0, 0.0, 28.0})
	bench_puppet_cmd(admin, "menuselect 7")
	set_pev(target, pev_flags, pev(target, pev_flags) & ~FL_DUCKING)
	set_pev(target, pev_view_ofs, Float:{0.0, 0.0, 28.0})

	bench_puppet_cmd(admin, "menuselect %d", KeyOf(target))
	ASSERT(SameOrigin(target, g_Saved))
	new Float:ofs[3]
	ASSERT(pev(target, pev_flags) & FL_DUCKING)
	pev(target, pev_view_ofs, ofs)
	ASSERT(ofs[2] == 16.0)
	ASSERT_FALSE(pev(admin, pev_flags) & FL_DUCKING)
	pev(admin, pev_view_ofs, ofs)
	ASSERT(ofs[2] == 28.0)
	bench_pass()
}

// A saved location without ducking leaves the admin's view alone.
public test_saved_standing_state()
{
	SpawnPuppets("tstand", 2, "Stand_Spawned")
}

public Stand_Spawned()
{
	new admin = g_P[0], target = g_P[1]
	SetFlags(admin, "h")
	Normalize(admin)
	set_pev(admin, pev_flags, pev(admin, pev_flags) & ~FL_DUCKING)
	pev(admin, pev_origin, g_Saved)
	bench_puppet_cmd(admin, "menuselect 8")
	bench_puppet_cmd(admin, "menuselect 7")
	set_pev(admin, pev_view_ofs, Float:{0.0, 0.0, 28.0})

	bench_puppet_cmd(admin, "menuselect %d", KeyOf(target))
	ASSERT(SameOrigin(target, g_Saved))
	ASSERT_FALSE(pev(admin, pev_flags) & FL_DUCKING)
	new Float:ofs[3]
	pev(admin, pev_view_ofs, ofs)
	ASSERT(ofs[2] == 28.0)
	bench_pass()
}

// A dead admin on "current location" sends players to where the admin is.
public test_dead_admin_uses_current_location()
{
	SpawnPuppets("tdead", 2, "DeadAdmin_Spawned")
}

public DeadAdmin_Spawned()
{
	new admin = g_P[0], target = g_P[1]
	SetFlags(admin, "h")
	Normalize(admin)
	user_kill(admin, 1)
	ASSERT_FALSE(is_user_alive(admin))

	bench_puppet_cmd(admin, "amx_teleportmenu")
	ASSERT_MENU(admin, "7. Current Location")
	ASSERT(MenuKeys(admin) & (1 << (KeyOf(target) - 1)))
	new Float:here[3]
	pev(admin, pev_origin, here)
	ASSERT_FALSE(SameOrigin(target, here))

	bench_puppet_cmd(admin, "menuselect %d", KeyOf(target))
	ASSERT(SameOrigin(target, here))
	ASSERT_MSG(admin, "", "ADMIN tdead1: teleport tdead2")
	bench_pass()
}

// A player who dies after the menu was drawn is refused, and the menu is drawn again.
public test_dead_target_refused()
{
	SpawnPuppets("tdt", 2, "DeadTarget_Spawned")
}

public DeadTarget_Spawned()
{
	new admin = g_P[0], target = g_P[1]
	SetFlags(admin, "h")
	SaveLocation(admin)
	new line[32]
	formatex(line, charsmax(line), "%d. tdt2^n", KeyOf(target))
	ASSERT_MENU(admin, line)

	user_kill(target, 1)
	new Float:before[3]
	pev(target, pev_origin, before)
	bench_puppet_cmd(admin, "menuselect %d", KeyOf(target))
	ASSERT_MSG(admin, "", "That action can't be performed on dead client ^"tdt2^"")
	ASSERT(SameOrigin(target, before))
	ASSERT_MENU(admin, "#. tdt2^n")
	bench_pass()
}

// Immune players are greyed (except the admin), admins get a star.
public test_immunity_and_admin_marks()
{
	SpawnPuppets("tim", 3, "Immunity_Spawned")
}

public Immunity_Spawned()
{
	new admin = g_P[0], immune = g_P[1], other = g_P[2]
	SetFlags(admin, "ah")
	SetFlags(immune, "a")
	SetFlags(other, "c")
	SaveLocation(admin)

	new line[32]
	formatex(line, charsmax(line), "%d. tim1 *", KeyOf(admin))
	ASSERT_MENU(admin, line)
	ASSERT_MENU(admin, "#. tim2^n")
	formatex(line, charsmax(line), "%d. tim3 *", KeyOf(other))
	ASSERT_MENU(admin, line)
	new keys = MenuKeys(admin)
	ASSERT_FALSE(keys & (1 << (KeyOf(immune) - 1)))
	ASSERT(keys & (1 << (KeyOf(other) - 1)))
	bench_pass()
}

// Seven players: six on the first page, one on the second. Back and More move between them, a
// page left empty by a player leaving falls back to the first one, and 0 on the first page closes.
public test_pages()
{
	SpawnPuppets("tpg", 7, "Pages_Spawned")
}

public Pages_Spawned()
{
	new admin = g_P[0], last = g_P[6]
	SetFlags(admin, "h")
	SaveLocation(admin)
	ASSERT_MENU(admin, "Teleport Menu 1/2")
	ASSERT_MENU(admin, "^n9. More...^n0. Exit")
	ASSERT(MenuKeys(admin) & MENU_KEY_9)
	ASSERT_NOT_MENU(admin, "tpg7")

	bench_puppet_cmd(admin, "menuselect 9")
	ASSERT_MENU(admin, "Teleport Menu 2/2")
	ASSERT_MENU(admin, "1. tpg7^n")
	ASSERT_MENU(admin, "^n0. Back")
	ASSERT_FALSE(MenuKeys(admin) & MENU_KEY_9)

	bench_puppet_cmd(admin, "menuselect 10")
	ASSERT_MENU(admin, "Teleport Menu 1/2")

	bench_puppet_cmd(admin, "menuselect 9")
	ASSERT_FALSE(SameOrigin(last, g_Saved))
	bench_puppet_cmd(admin, "menuselect 1")
	ASSERT(SameOrigin(last, g_Saved))
	ASSERT_MENU(admin, "Teleport Menu 2/2")

	server_cmd("kick #%d", get_user_userid(last))
	server_exec()
	ASSERT_FALSE(is_user_connected(last))
	// Saving again redraws page 2, which is now past the last player.
	bench_puppet_cmd(admin, "menuselect 8")
	ASSERT_MENU(admin, "Teleport Menu 1/1")

	new before = bench_msg_count(admin, "ShowMenu")
	bench_puppet_cmd(admin, "menuselect 10")
	ASSERT_EQ(bench_msg_count(admin, "ShowMenu"), before)
	new oldmenu, newmenu, page
	player_menu_info(admin, oldmenu, newmenu, page)
	ASSERT_EQ(oldmenu, 0)
	bench_pass()
}
