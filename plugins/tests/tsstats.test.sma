// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for ts/tsstats.sma (TS Stats Rank Calculation): get_score ranks a player by kills minus
// deaths minus team kills. TSX calls its own copy (data/tsstats.amxx); this calls the loaded plugin.
//

#include <amxmodx>
#include <amxxbench>

public plugin_init()
{
	register_plugin("TS Stats Rank Calculation Tests", AMXX_VERSION_STR, "AMXX Dev Team")
}

Score(kills, deaths, teamkills, headshots)
{
	new stats[STATSX_MAX_STATS], body[MAX_BODYHITS]
	stats[STATSX_KILLS] = kills
	stats[STATSX_DEATHS] = deaths
	stats[STATSX_TEAMKILLS] = teamkills
	stats[STATSX_HEADSHOTS] = headshots
	stats[STATSX_SHOTS] = 100
	stats[STATSX_HITS] = 50
	stats[STATSX_DAMAGE] = 900
	body[HIT_HEAD] = 7

	if (callfunc_begin("get_score", "tsstats.amxx") != 1)
		return cellmin
	callfunc_push_array(stats, sizeof(stats))
	callfunc_push_array(body, sizeof(body))
	return callfunc_end()
}

public test_score_is_kills_minus_deaths_minus_teamkills()
{
	// Headshots, shots, hits, damage and body hits do not count.
	ASSERT_EQ(Score(10, 3, 2, 5), 5)
	bench_pass()
}

public test_score_can_be_negative()
{
	ASSERT_EQ(Score(1, 4, 1, 0), -4)
	ASSERT_EQ(Score(0, 0, 0, 0), 0)
	bench_pass()
}
