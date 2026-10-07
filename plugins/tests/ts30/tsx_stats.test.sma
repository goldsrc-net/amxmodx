// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for TSX's stats on the original The Specialists 3.0 game library: the shots a gun fires,
// and the ranks TSX saves to tsstats.dat on a map change.
//
// These need the stock stack (HLDS, TS 3.0 i386): run.sh --tests plugins/tests/ts30 stock
//

#include <amxmodx>
#include <fakemeta>
#include <tsx>
#include <tsfun>
#include <tsstats>
#include <amxxbench>

#define GLOCK18		1

enum
{
	SHOTS,
	RANK_FILE
}

new g_Mode
new g_Victim
new g_Shooter
new g_Name[32]
new g_Before[STATSX_MAX_STATS]
new g_Shots

public plugin_init()
{
	register_plugin("TSX Stats Tests", AMXX_VERSION_STR, "AMXX Dev Team")
}

// The weapon in the last WeaponInfo the game sent the player, or -1.
LastWeaponInfo(id)
{
	new BenchMsg:msg = bench_msg_last(id, "WeaponInfo")
	if (msg == BenchMsg:0)
		return -1
	return bench_msg_int(msg, 0)
}

// --- a shooter with a Glock and a victim with 1 health in front of him -----------------------

StartShooting(mode, const shooter[])
{
	g_Mode = mode
	copy(g_Name, charsmax(g_Name), shooter)
	new victim = bench_puppet("target")
	ASSERT(victim > 0)
	bench_puppet_spawn(victim, "target_spawned", 20.0, "respawn")
}

public target_spawned(victim)
{
	g_Victim = victim
	new id = bench_puppet(g_Name)
	ASSERT(id > 0)
	new name[32]
	get_user_name(id, name, charsmax(name))
	ASSERT_STR_EQ(name, g_Name)
	g_Shooter = id
	bench_puppet_spawn(id, "shooter_spawned", 20.0, "respawn")
}

public shooter_spawned(shooter)
{
	// His rank as it stands, from earlier runs.
	new body[MAX_BODYHITS]
	ASSERT(get_user_stats(shooter, g_Before, body) > 0)
	ts_giveweapon(shooter, GLOCK18, 1, 0)
	bench_wait_until("holds_glock", "shooter_armed", 3.0, shooter)
}

public bool:holds_glock(id)
{
	return LastWeaponInfo(id) == GLOCK18
}

public shooter_armed(shooter)
{
	new Float:target[3]
	ASSERT(bench_puppet_face(shooter, g_Victim, 150.0))
	pev(g_Victim, pev_origin, target)
	bench_puppet_look_at(shooter, target)
	set_pev(g_Victim, pev_health, 1.0)
	bench_next("shooter_fire", 0.5, shooter)
}

public shooter_fire(shooter)
{
	bench_puppet_input(shooter, IN_ATTACK)
	bench_wait_until("target_dead", "shooter_done", 5.0, shooter)
}

public bool:target_dead(shooter)
{
	return !is_user_alive(g_Victim)
}

public shooter_done(shooter)
{
	bench_puppet_input(shooter, 0)
	if (g_Mode == SHOTS)
		ShotsCounted(shooter)
	else
		bench_change_map("ts_lobby", "rank_saved")
}

// --- shots -----------------------------------------------------------------------------------
// The Specialists 3.0 never sends ClipInfo; each shot shows in the clip of the WeaponInfo it sends.

public test_gun_shots_and_hits_are_counted()
{
	StartShooting(SHOTS, "gunner")
}

ShotsCounted(shooter)
{
	new stats[STATSX_MAX_STATS], body[MAX_BODYHITS]

	// The Glock's own stats, and every weapon's.
	ASSERT_EQ(get_user_wstats(shooter, GLOCK18, stats, body), 1)
	ASSERT(stats[STATSX_SHOTS] >= 1)
	ASSERT_EQ(stats[STATSX_HITS], 1)
	ASSERT_EQ(stats[STATSX_KILLS], 1)
	g_Shots = stats[STATSX_SHOTS]
	ASSERT_EQ(get_user_wstats(shooter, 0, stats, body), 1)
	ASSERT_EQ(stats[STATSX_SHOTS], g_Shots)
	ASSERT_EQ(stats[STATSX_HITS], 1)

	// This life's, which go into his rank when he leaves.
	ASSERT_EQ(get_user_rstats(shooter, stats, body), 1)
	ASSERT_EQ(stats[STATSX_SHOTS], g_Shots)
	ASSERT_EQ(stats[STATSX_HITS], 1)
	server_cmd("kick #%d", get_user_userid(shooter))
	bench_wait_until("shooter_gone", "shooter_left", 2.0)
}

public bool:shooter_gone()
{
	return !is_user_connected(g_Shooter)
}

public shooter_left()
{
	// He comes back under the same name, and get_user_stats shows his rank with that life in it.
	new id = bench_puppet(g_Name)
	ASSERT(id > 0)
	new name[32]
	get_user_name(id, name, charsmax(name))
	ASSERT_STR_EQ(name, g_Name)
	bench_wait_until("back_in_game", "shooter_back", 2.0, id)
}

public bool:back_in_game(id)
{
	return is_user_connected(id) != 0
}

public shooter_back(id)
{
	new stats[STATSX_MAX_STATS], body[MAX_BODYHITS]
	ASSERT(get_user_stats(id, stats, body) > 0)
	ASSERT_EQ(stats[STATSX_SHOTS] - g_Before[STATSX_SHOTS], g_Shots)
	ASSERT_EQ(stats[STATSX_HITS] - g_Before[STATSX_HITS], 1)
	ASSERT_EQ(stats[STATSX_KILLS] - g_Before[STATSX_KILLS], 1)
	bench_pass()
}

// --- tsstats.dat ------------------------------------------------------------------------------
// TSX keeps the ranks in memory and writes them to tsstats.dat on every map change; it reads the
// file when it loads, at server start. Each total must sit in the file where the loader reads it:
// tks, damage, deaths, kills, shots, hits, headshots, then the body hits.

public test_map_change_saves_the_ranks_where_tsx_reads_them()
{
	StartShooting(RANK_FILE, "ranked")
}

ReadShort(file)
{
	new value
	if (fread(file, value, BLOCK_SHORT) <= 0)
		return -1
	return value & 0xFFFF
}

public rank_saved()
{
	new path[256]
	get_localinfo("tsstats", path, charsmax(path))
	if (!path[0])
		copy(path, charsmax(path), "addons/amxmodx/data/tsstats.dat")
	new file = fopen(path, "rb")
	ASSERT(bench_check(file != 0, path))

	new version = ReadShort(file)

	// Record i is rank i + 1, which get_stats(i) reads from memory.
	new const fields[] = { STATSX_TEAMKILLS, STATSX_DAMAGE, STATSX_DEATHS, STATSX_KILLS, STATSX_SHOTS,
		STATSX_HITS, STATSX_HEADSHOTS }
	new records, len, ranked = -1
	while ((len = ReadShort(file)) > 0)
	{
		new name[64], unique[64], saved[STATSX_MAX_STATS], body[MAX_BODYHITS]
		ASSERT(len <= charsmax(name))
		fread_blocks(file, name, len, BLOCK_CHAR)
		len = ReadShort(file)
		ASSERT(len > 0 && len <= charsmax(unique))
		fread_blocks(file, unique, len, BLOCK_CHAR)
		for (new f = 0; f < sizeof fields; f++)
			fread(file, saved[fields[f]], BLOCK_INT)
		fread_blocks(file, body, MAX_BODYHITS, BLOCK_INT)

		new stats[STATSX_MAX_STATS], rbody[MAX_BODYHITS], rname[64]
		get_stats(records, stats, rbody, rname, charsmax(rname))
		ASSERT_STR_EQ(name, rname)
		for (new f = 0; f < sizeof fields; f++)
			ASSERT_EQ(saved[fields[f]], stats[fields[f]])
		if (equal(name, "ranked"))
			ranked = records
		records++
	}
	fclose(file)
	ASSERT_EQ(records, get_statsnum())
	// Version 6 marks this order; the loader reads a version 5 file in the order it was written.
	ASSERT_EQ(version, 6)

	// The shooter is there with his kill, and his totals differ, so a field out of place shows.
	new stats[STATSX_MAX_STATS], body[MAX_BODYHITS], rname[64]
	ASSERT(ranked >= 0)
	get_stats(ranked, stats, body, rname, charsmax(rname))
	ASSERT(stats[STATSX_KILLS] >= 1)
	ASSERT(stats[STATSX_DAMAGE] > stats[STATSX_KILLS])
	bench_pass()
}
