// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for the order The Specialists 3.0 precaches its weapon events in, which reTS has to match:
// CTSGun::Precache (@0x70660) registers fire, coldcock, firelinked, empty, pump, closecombat, reload,
// knife, katana, draw, grenade. The indices are the server's, and a client keeps the ones it got on
// the map it predicts on, so a server whose order differs makes another server's client play the
// wrong events.
//
// These need the stock stack (HLDS, TS 3.0 i386): run.sh --tests plugins/tests/ts30 stock
//

#include <amxmodx>
#include <fakemeta>
#include <amxxbench>

public plugin_init()
{
	register_plugin("TS 3.0 Event Order Tests", AMXX_VERSION_STR, "AMXX Dev Team")
}

// Every one is precached at map load, so the lookup only finds its index.
EventIndex(const name[])
{
	return engfunc(EngFunc_PrecacheEvent, 1, name)
}

public test_weapon_events_precached_in_order()
{
	// CTSGun::Precache's order; fire.sc and firelinked.sc are left out of the order check because
	// test plugins precache them first.
	new const ordered[][] = { "events/coldcock.sc", "events/empty.sc", "events/pump.sc",
		"events/closecombat.sc", "events/reload.sc", "events/knife.sc", "events/katana.sc",
		"events/draw.sc", "events/grenade.sc" }
	new fire = EventIndex("events/fire.sc")
	new last = fire
	server_print("ts_event_order: events/fire.sc %d, events/firelinked.sc %d", fire,
		EventIndex("events/firelinked.sc"))
	for (new i = 0; i < sizeof ordered; i++)
	{
		new index = EventIndex(ordered[i])
		server_print("ts_event_order: %s %d", ordered[i], index)
		ASSERT(index > last)
		last = index
	}
	bench_pass()
}
