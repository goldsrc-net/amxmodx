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

#include "amxxmodule.h"
#include "tsx.h"

// Where a weapon's stats go: slot 0 holds every weapon's, so kung fu has its own.
static inline int StatsSlot(int weapon)
{
	return weapon == TSWEAPON_KUNGFU ? TSWEAPON_KUNGFU_STATS : weapon;
}

// The game's stunt bits in pev->iuser4 that TSGetPointsForFrag (0x79140) reads: a dive (0x10), a
// cartwheel (0x400, 0x800) or a wall jump (0x10000) is a stunt, a slide (0x20) with friction under 1
// is a slide. Either counts only while the killer moves faster than 80 units a second.
#define TS_STUNT_BITS	0x10c10
#define TS_SLIDE_BIT	0x20

static int StuntFlags(edict_t *pKiller)
{
	if ( pKiller->v.velocity.Length() <= 80.0f )
		return 0;
	if ( pKiller->v.iuser4 & TS_STUNT_BITS )
		return TSKF_STUNTKILL;
	if ( (pKiller->v.iuser4 & TS_SLIDE_BIT) && pKiller->v.friction < 1.0f )
		return TSKF_SLIDINGKILL;
	return 0;
}


void Client_ResetHUD_End(void* mValue)
{
	if ( mPlayer->IsAlive() ){ // ostatni przed spawn'em 
		mPlayer->clearStats = gpGlobals->time + 0.25f; // teraz czysc statystyki 
		mPlayer->deathKiller = 0;
	}
	else { // dalej "dead" nie czysc statystyk!
		mPlayer->items = 0;
		mPlayer->is_specialist = 0;
		mPlayer->killingSpree = 0;
		mPlayer->killFlags = 0;
		mPlayer->frags = (int)mPlayer->pEdict->v.frags;
		/* 
		fix dla user_kill() z addfrag 
		oraz self kills
		*/
	}
}

void Client_ScoreInfo(void* mValue)
{
	static int iId;
	switch(mState++){
	case 0:
		iId = *(int*)mValue;
		break;
	case 4:
		if ( iId && (iId < 33) ){
			GET_PLAYER_POINTER_I(iId)->teamId = *(int*)mValue;
		}
		break;
	}
}

void Client_WeaponInfo(void* mValue)
{
	static int wpn;
	switch(mState++){
	case 0:
		wpn =  *(int*)mValue; // 0 is kung fu
		mPlayer->current = wpn;
		break;
	case 1:
		mPlayer->weapons[wpn].clip = *(int*)mValue;
		break;
	case 2:
		mPlayer->weapons[wpn].ammo = *(int*)mValue;
		break;
	case 3:
		mPlayer->weapons[wpn].mode = *(int*)mValue;
		break;
	case 4:
		mPlayer->weapons[wpn].attach = *(int*)mValue;
		break;
	}
}

void Client_ClipInfo(void* mValue)
{
	int iValue = *(int*)mValue;
	if ( iValue < mPlayer->weapons[mPlayer->current].clip ) {
		mPlayer->saveShot(StatsSlot(mPlayer->current));
	}
	mPlayer->weapons[mPlayer->current].clip = iValue;
}

void Client_TSHealth_End(void* mValue){
	edict_t *enemy = mPlayer->pEdict->v.dmg_inflictor;
	int damage = (int)mPlayer->pEdict->v.dmg_take;

	if ( !damage || !enemy )
		return;

	int aim = 0;
	int weapon = 0;
	mPlayer->pEdict->v.dmg_take = 0.0; 

	CPlayer* pAttacker = NULL;
	if ( enemy->v.flags & (FL_CLIENT | FL_FAKECLIENT) ){
		pAttacker = GET_PLAYER_POINTER(enemy);
		weapon = pAttacker->current;
		aim = pAttacker->aiming;
		pAttacker->saveHit( mPlayer , StatsSlot(weapon) , damage, aim );
	}
	else {
		char szCName[16];
		strcpy( szCName,STRING(enemy->v.classname) );

		if ( szCName[0] == 'g' ) { 
			if ( enemy->v.owner && enemy->v.owner->v.flags & (FL_CLIENT | FL_FAKECLIENT) ){ 
				pAttacker = GET_PLAYER_POINTER(enemy->v.owner);
				weapon = 24; // grenade
				if ( pAttacker != mPlayer )
					pAttacker->saveHit( mPlayer , weapon , damage, 0 );
			}
		}
		else if ( szCName[0] == 'k' ) {
			edict_t *pOwner = *( (edict_t **)enemy->pvPrivateData + gKnifeOffset );

			if ( FNullEnt( (edict_t*)pOwner) )
				return;

			pAttacker = GET_PLAYER_POINTER( pOwner );
			
			weapon = TSWEAPON_TKNIFE; // throwing knife
			aim = pAttacker ? pAttacker->aiming : 0;
			if (pAttacker)
				pAttacker->saveHit( mPlayer , weapon , damage, aim );
		}
	}
	bool world = !pAttacker; // weapon 0 is kung fu, but not here
	if ( !pAttacker ) pAttacker = mPlayer;

	int TA = 0;
	if ( mPlayer->teamId || is_theonemode  ){
		if ( (mPlayer->teamId == pAttacker->teamId ) && (mPlayer != pAttacker) )
			TA = 1;
	}

	if ( weaponData[weapon].melee ) 
		pAttacker->saveShot(world ? weapon : StatsSlot(weapon));
	
	MF_ExecuteForward(g_damage_info,
		(cell)pAttacker->index,
		(cell)mPlayer->index,
		(cell)damage,
		(cell)weapon,
		(cell)aim,
		(cell)TA
		);

	if ( mPlayer->IsAlive() )
		return;

	// death

    if ( (int)pAttacker->pEdict->v.frags - pAttacker->frags == 0 ) // nie bylo fraga ? jest tak dla bledu z granatem ..
		pAttacker = mPlayer;

	int killFlags = 0;

	// The game named kung fu in its DeathMsg when the kill was close combat, and the killer's
	// stunt was read there, when the game scored it.
	bool deathMsg = mPlayer->deathKiller == pAttacker->index;
	mPlayer->deathKiller = 0;

	if ( !TA && mPlayer!=pAttacker ) {
		int stuntKill = 0;

		if ( weapon == 24 ) // dla granata nie liczy sie sflags
			; // nic nie rob..
		else {
			stuntKill = deathMsg ? mPlayer->deathStunt : StuntFlags(pAttacker->pEdict);
			if ( deathMsg && mPlayer->deathKungFu )
				weapon = TSWEAPON_KUNGFU;
		}

		int doubleKill = 0;
		
		if ( gpGlobals->time - pAttacker->lastKill < 1.0 )
			doubleKill = 1;
		
		killFlags |= stuntKill;
		
		pAttacker->lastKill = gpGlobals->time;
	
		pAttacker->killingSpree++;

		if ( pAttacker->killingSpree == 10 )
			pAttacker->is_specialist = 1;
	
		// A stunt or a slide is a point more, but not in close combat, which kung fu always is.
		pAttacker->lastFrag = weaponData[weapon].bonus + ( (stuntKill && weapon != TSWEAPON_KUNGFU) ? 1 : 0 );

		if ( doubleKill ){
			pAttacker->lastFrag *= 2;
			killFlags |= TSKF_DOUBLEKILL;
		}

		if ( pAttacker->is_specialist ){
			pAttacker->lastFrag *= 2;
			killFlags |= TSKF_ISSPEC;
		}

		if ( mPlayer->is_specialist ){
			pAttacker->lastFrag += 5; 
			killFlags |= TSKF_KILLEDSPEC;
		}

		pAttacker->frags += pAttacker->lastFrag; 
			if ( pAttacker->frags != pAttacker->pEdict->v.frags ){
				if ( !deathMsg ) // moze to kung fu z bronia ?
					weapon = TSWEAPON_KUNGFU;
				pAttacker->lastFrag += (int)pAttacker->pEdict->v.frags - pAttacker->frags;
				pAttacker->frags = (int)pAttacker->pEdict->v.frags;
			}
	}

	pAttacker->killFlags = killFlags;
	pAttacker->saveKill(mPlayer,world ? weapon : StatsSlot(weapon),( aim == 1 ) ? 1:0 ,TA);
	MF_ExecuteForward(g_death_info,
		(cell)pAttacker->index,
		(cell)mPlayer->index,
		(cell)weapon,
		(cell)aim,
		(cell)TA);
}

void Client_TSState(void* mValue)
{
	mPlayer->oldstate = mPlayer->state;
	mPlayer->checkstate = 1;
	mPlayer->state =  *(int*)mValue;
}

void Client_WStatus(void* mValue)
{
	switch(mState++){
	case 1:
		if ( !*(int*)mValue ){
			mPlayer->current = TSWEAPON_KUNGFU; // fix dla wytraconej broni
		}
		break;
	}
}

void Client_TSCash(void* mValue)
{
	mPlayer->money = *(int*)mValue;
}

void Client_TSSpace(void* mValue)
{
	mPlayer->space = *(int*)mValue;
}

void Client_PwUp(void* mValue)
{
	static int iPwType;
	switch(mState++){
	case 0:
		iPwType = *(int*)mValue;
		switch(iPwType){
		case TSPWUP_KUNGFU :
			mPlayer->items |= TSITEM_KUNGFU;
			break;
		case TSPWUP_SJUMP:
			mPlayer->items |= TSITEM_SUPERJUMP;
			break;
		default: mPlayer->PwUp = iPwType;
		}
		break;
	case 1:
		if ( iPwType != TSPWUP_KUNGFU && iPwType != TSPWUP_SJUMP )
			mPlayer->PwUpValue = *(int*)mValue;
		break;
	}
}

// What killed whom, the way the game tells everyone: the killer, the victim and a weapon name, which is
// "Kung Fu" for close combat (PlayerKilled, 0x798f0), with any weapon in hand.
void Client_DeathMsg(void* mValue)
{
	static int iKiller;
	static int iVictim;
	switch(mState++){
	case 0:
		iKiller = *(int*)mValue;
		break;
	case 1:
		iVictim = *(int*)mValue;
		break;
	case 2:
		if ( iVictim >= 1 && iVictim <= gpGlobals->maxClients ){
			CPlayer* pVictim = GET_PLAYER_POINTER_I(iVictim);
			pVictim->deathKiller = iKiller;
			pVictim->deathKungFu = strcmp( (char*)mValue, "Kung Fu" ) == 0;
			pVictim->deathStunt = ( iKiller >= 1 && iKiller <= gpGlobals->maxClients ) ? StuntFlags( INDEXENT(iKiller) ) : 0;
		}
		break;
	}
}
