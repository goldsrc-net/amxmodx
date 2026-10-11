// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for a weapon's draw on The Specialists 3.0, which reTS has to match: DefaultDeploy (@0x90178)
// sets the idle 3 s on (0.75 s for the Contender, @0x9033d), so the draw animation stays the
// weaponanim until then, and plays weapons/draw.wav on CHAN_VOICE, attenuation 1.25, volume 0.92 to 1,
// pitch 98 to 101 (@0x903be).
//
// These need the stock stack (HLDS, TS 3.0 i386): run.sh --tests plugins/tests/ts30 stock
//

#include <amxmodx>
#include <fakemeta>
#include <tsfun>
#include <amxxbench>

// The Specialists 3.0 weapon ids.
#define GLOCK18		1
#define CONTENDER	36

new g_P
new g_Weapon
new Float:g_Hold
new g_Draw
new g_Sounds
new g_BadSound

public plugin_init()
{
	register_plugin("TS 3.0 Draw Tests", AMXX_VERSION_STR, "AMXX Dev Team")
	register_forward(FM_EmitSound, "on_sound")
}

public bench_setup()
{
	g_P = 0
	g_Sounds = 0
	g_BadSound = 0
}

// The draw sound from the puppet: CHAN_VOICE, attenuation 1.25, pitch 98 to 101.
public on_sound(id, channel, const sample[], Float:volume, Float:attn, flags, pitch)
{
	if (!g_P || id != g_P || !equal(sample, "weapons/draw.wav"))
		return FMRES_IGNORED
	g_Sounds++
	server_print("ts_draw: draw.wav channel %d volume %f attn %f flags %d pitch %d", channel, volume,
		attn, flags, pitch)
	if (channel != CHAN_VOICE || attn != 1.25 || flags != 0 || pitch < 98 || pitch > 101
		|| volume < 0.92 || volume > 1.0)
		g_BadSound++
	return FMRES_IGNORED
}

// Spawns the puppet, gives him the weapon and calls the checks: the draw is still the weaponanim
// hold - 0.25 s after the give, and the idle has replaced it at hold + 0.5 s.
Drawn(const name[], weapon, Float:hold)
{
	g_Weapon = weapon
	g_Hold = hold
	g_P = bench_puppet(name)
	ASSERT(g_P > 0)
	bench_puppet_spawn(g_P, "drawn_spawned", 20.0, "respawn")
}

public drawn_spawned(id)
{
	// past the spawn's own kung fu deploy
	bench_next("drawn_give", 1.0, id)
}

public drawn_give(id)
{
	g_Sounds = 0
	g_BadSound = 0
	ts_giveweapon(id, g_Weapon, 30, 0)
	g_Draw = pev(id, pev_weaponanim)
	server_print("ts_draw: weapon %d draw %d", g_Weapon, g_Draw)
	bench_next("drawn_before", g_Hold - 0.25, id)
}

public drawn_before(id)
{
	new anim = pev(id, pev_weaponanim)
	server_print("ts_draw: weapon %d at %.2f s weaponanim %d", g_Weapon, g_Hold - 0.25, anim)
	ASSERT_EQ(anim, g_Draw)
	bench_next("drawn_after", 0.75, id)
}

public drawn_after(id)
{
	new anim = pev(id, pev_weaponanim)
	server_print("ts_draw: weapon %d at %.2f s weaponanim %d", g_Weapon, g_Hold + 0.5, anim)
	ASSERT(anim != g_Draw)
	ASSERT_EQ(g_Sounds, 1)
	ASSERT_EQ(g_BadSound, 0)
	bench_pass()
}

// A Glock 18 keeps its draw for 3 s, then idles; one draw sound.
public test_draw_holds_three_seconds()
{
	Drawn("drawglock", GLOCK18, 3.0)
}

// The Contender idles after 0.75 s.
public test_contender_draw_holds_three_quarters()
{
	Drawn("drawcontender", CONTENDER, 0.75)
}
