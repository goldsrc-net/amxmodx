// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
// Copyright (C) 2004 Lukasz Wlasinski.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// TSX Module
//

#ifndef CMISC_H
#define CMISC_H

#include "amxxmodule.h"
#include "CRank.h"

#define TSMAX_CUSTOMWPNS		5
#define TSMAX_WEAPONS			40 + TSMAX_CUSTOMWPNS

// The Specialists 3.0 weapon ids run 0 (kung fu) to 37; TSX adds the thrown knife. The stats keep
// every weapon's totals in slot 0, so kung fu's own stats go in a slot of their own.
#define TSWEAPON_KUNGFU			0
#define TSWEAPON_TKNIFE			38
#define TSWEAPON_KUNGFU_STATS	39


#if defined(_WIN32)
#define TSKNIFE_OFFSET			31 // owner offset in knife entity
#else
#define TSKNIFE_OFFSET			35
#endif

#define TS_SPEED_ENTITIES		32 // CBasePlayer's slowed entities

#define TSPWUP_SLOWMO			1
#define TSPWUP_INFAMMO			2
#define TSPWUP_KUNGFU			4
#define TSPWUP_SLOWPAUSE		8
#define TSPWUP_DFIRERATE		16
#define TSPWUP_SJUMP			256

#define TSITEM_KUNGFU			1<<0
#define TSITEM_SUPERJUMP		1<<1

#define TSKF_STUNTKILL			1<<0
#define TSKF_SLIDINGKILL		1<<1
#define TSKF_DOUBLEKILL			1<<2
#define TSKF_ISSPEC				1<<3 // is specialist
#define TSKF_KILLEDSPEC			1<<4 // killed specialist

// *****************************************************
// class CPlayer
// *****************************************************

struct CPlayer {

	edict_t* pEdict;
	char ip[32];
	int index;
	int teamId;
	int aiming;
	int current;

	int space;
	int money;
	int PwUp;
	int PwUpValue;
	int items; // "stale" przedmioty , super jump i kung fu bonus

	//
	int killingSpree;
	int is_specialist;
	int killFlags;
	int lastFrag; // oblicz ostatni frag, sprawdza czy poprawna jest detekcja broni i bonusow 
	float lastKill;  // kiedy ostatni , dla double kill
	//
	int frags; // suma dla kontroli ostatniego fraga, to - v.frags = lastfrag

	bool ingame;
	float clearStats;

	int checkstate;
	int state;
	int oldstate;

	// ts_set_speed: this player's time scale and how far around him it reaches, until speedEnd;
	// speedBy is the player whose ts_set_speed scales this one now.
	bool speedActive;
	float speedEnd;
	float speedValue;
	float speedAura;
	int speedBy;
	// The grenades, thrown knives and dropped guns his ts_set_speed scales now (entity index and
	// serial number), at most as many as the game's own slow motion keeps per player.
	struct SpeedEntity {
		int index;
		int serial;
	} speedEntities[TS_SPEED_ENTITIES];
	int speedEntityCount;
	
	struct PlayerWeapon : public Stats {
		char*		name;
		int			ammo;
		int			clip;
		int			mode; // burst , full auto ..
		int			attach; // scope ,laser
	};

	PlayerWeapon	weapons[TSMAX_WEAPONS];
	PlayerWeapon	attackers[33];
	PlayerWeapon	victims[33];
	Stats			weaponsRnd[TSMAX_WEAPONS]; // DEC-Weapon (Round) stats
	Stats			life;

	RankSystem::RankStats*	rank;

	void Init(  int pi, edict_t* pe );
	void Connect( const char* ip );
	void PutInServer();
	void Disconnect();
	void saveKill(CPlayer* pVictim, int weapon, int hs, int tk);
	void saveHit(CPlayer* pVictim, int weapon, int damage, int aiming);
	void saveShot(int weapon);
	void restartStats(bool all = true);

	inline bool IsBot(){
		const char* auth= (*g_engfuncs.pfnGetPlayerAuthId)(pEdict);
		return ( auth && !strcmp( auth , "BOT" ) );
	}
	inline bool IsAlive(){
		return ((pEdict->v.deadflag==DEAD_NO)&&(pEdict->v.health>0));
	}
};

#endif // CMISC_H

