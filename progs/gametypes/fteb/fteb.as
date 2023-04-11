Cvar ftebReverseHandicap( "fteb_reversehandicap", "1", CVAR_ARCHIVE );
Cvar ftebStatsEnable( "fteb_stats_enable", "1", CVAR_ARCHIVE );
Cvar ftebStatsMinplayers( "fteb_stats_minplayers", "4", CVAR_ARCHIVE );
Cvar ftebStatsDebug( "fteb_stats_debug", "0", CVAR_ARCHIVE );
Cvar ftebRebalanceDebug( "fteb_rebalance_debug", "0", CVAR_ARCHIVE );
Cvar ftebDefrostTime( "fteb_defrost_time", "3000", CVAR_ARCHIVE );
Cvar ftebDefrostShatterDelay( "fteb_defrost_shatter_delay", "6000", CVAR_ARCHIVE );
Cvar ftebDefrostAttackDelay( "fteb_defrost_attack_delay", "2000", CVAR_ARCHIVE );
Cvar ftebDefrostHazardScale( "fteb_defrost_hazard_scale", "2", CVAR_ARCHIVE );
Cvar ftebDefrostAttackScale( "fteb_defrost_attack_scale", "5", CVAR_ARCHIVE );
Cvar ftebDefrostDecayScale( "fteb_defrost_decay_scale", "5", CVAR_ARCHIVE );
Cvar ftebDefrostRadius( "fteb_defrost_radius", "144", CVAR_ARCHIVE );
Cvar ftebElectroboltKnockback( "fteb_electrobolt_knockback", "1", CVAR_ARCHIVE );

Cvar g_knockback_scale("g_knockback_scale", "", 0);

int minValue(int value) {
	return value > 0 ? value : 1;
}

const uint FTAG_DEFROST_TIME = minValue(ftebDefrostTime.integer);
const uint FTAG_SHATTER_DELAY = minValue(ftebDefrostShatterDelay.integer);
const uint FTAG_INVERSE_HAZARD_DEFROST_SCALE = minValue(ftebDefrostHazardScale.integer);
const uint FTAG_INVERSE_ATTACK_DEFROST_SCALE = minValue(ftebDefrostAttackScale.integer);
const uint FTAG_DEFROST_ATTACK_DELAY = minValue(ftebDefrostAttackDelay.integer);
//const uint FTAG_DEFROST_DECAY_DELAY = 500;
const uint FTAG_DEFROST_DECAY_SCALE = minValue(ftebDefrostDecayScale.integer);
const float FTAG_DEFROST_RADIUS = float(minValue(ftebDefrostRadius.integer));

uint ftaga_roundStateStartTime;
uint ftaga_roundStateEndTime;
int ftaga_countDown;
int ftaga_state;
int matchEndTime;
int playerAmount;
bool scorelimit;
String mapPool;

int prcYesIcon;
int[] defrosts(maxClients);
int[] eb_hits(maxClients);
int[] assists(maxClients);
int[][] assistTrack(maxClients);
int[] multishotTrack(maxClients);
uint[] lastShotTime(maxClients);
int[] playerSTAT_PROGRESS_SELFdelayed(maxClients);
uint[] playerLastTouch(maxClients);
bool[] spawnNextRound(maxClients);
//String[] defrostMessage(maxClients);
bool doRemoveRagdolls = false;

// Vec3 doesn't have dot product ffs
float dot(const Vec3 v1, const Vec3 v2) {
	return v1.x * v2.x + v1.y * v2.y + v1.z * v2.z;
}

// Check if player is alone versus a bigger team
bool playerIsAlone(Client @client) {
	if(match.getState() == MATCH_STATE_PLAYTIME) {
		Team @team;
		array<int> teamSize(2);
		int soloCount = 0;

		for (int i = 0; i < 2; i++) {
			@team = @G_GetTeam(i + TEAM_ALPHA);
			teamSize[i] = 0;

			for(int j = 0; @team.ent(j) != null; j++) {
				teamSize[i]++;
			}

			if (teamSize[i] == 1) soloCount++; 
		}

		if ((soloCount == 1) && (teamSize[client.team - TEAM_ALPHA] == 1)) return true;
	}

	return false;
}

void createMapPoolFile(String players, String maps) {
	if(!G_FileExists("configs/server/gametypes/" + gametype.name + "_maps_" + players + ".cfg")) {
		// the config file doesn't exist or it's empty, create it
		String response;
		response = "// '" + gametype.title + "' gametype map pool for " + players + " players\n"
			+ "// This config will be executed during each score screen\n"
			+ "\nset g_maplist \"" + maps + "\"\n"
			+ "\necho \"" + gametype.name + "_maps_" + players + ".cfg executed\"\n";
		G_WriteFile("configs/server/gametypes/" + gametype.name + "_maps_" + players + ".cfg", response);
		G_Print("Created default " + players + " player map pool file for '" + gametype.name + "'\n");
		G_CmdExecute("exec configs/server/gametypes/" + gametype.name + "_maps_" + players + ".cfg silent");
	}
}

void FTAG_giveInventory(Client @client) {
    client.inventoryClear();

    client.inventoryGiveItem(WEAP_ELECTROBOLT);
	client.inventorySetCount(AMMO_BOLTS, 99);
	client.inventorySetCount(AMMO_WEAK_BOLTS, 99);

    // give armor
    if (ftebReverseHandicap.boolean && playerIsAlone(client)) {
		client.armor = 125;
	} else client.armor = 50;

	// Spawn with less health if round ongoing
	if ((match.getState() == MATCH_STATE_PLAYTIME) && (gametype.shootingDisabled == false)) {
		client.getEnt().health = 25;
	}

    // select electrobolt
    client.selectWeapon( WEAP_ELECTROBOLT );
}

void FTAG_playerKilled(Entity @target, Entity @attacker, Entity @inflictor, String &mod) {
	if(@target.client == null) {
		return;
	}

	if(@attacker != null && @attacker.client != null) {
		if(match.getState() == MATCH_STATE_PLAYTIME) {
			// Record kills
			GT_Stats_GetPlayer( attacker.client ).stats.add("kills", 1);

			// Record assists
			if (assistTrack[target.client.playerNum].length() > 1) {
				Client @assister = G_GetClient(assistTrack[target.client.playerNum][1]);
				assists[assister.playerNum]++;
				GT_Stats_GetPlayer(assister).stats.add("assists", 1);
				assistTrack[target.client.playerNum].resize(0);
			}

			GT_updateScore(attacker.client);
		}
	}

	if((G_PointContents(target.origin) & CONTENTS_NODROP) == 0) {
		if(target.client.weapon > WEAP_GUNBLADE) {
			GENERIC_DropCurrentWeapon(target.client, true);
		}
		target.dropItem(AMMO_PACK);
	}

	// Skip kills not made during match
	if(match.getState() != MATCH_STATE_PLAYTIME) {
		return;
	}

	GT_Stats_GetPlayer( target.client ).stats.add("deaths", 1);
	GT_updateScore(target.client);

	// Forward telefrags to respawn instead
	if (mod == 64) {
		cFrozenPlayer(target.client, levelTime);
		return;
	}

	cFrozenPlayer(target.client, 0);
}

void FTAG_NewRound(Team @loser, int newState) {
	if ( newState > 3 ) {
		return;
    }
	if ( ftaga_state > newState ) {
		return;
	}

	ftaga_state = newState;

	// end round add score
	if ( ftaga_state == 1) {
		ftaga_state = 2;
		Team @winner = G_GetTeam(loser.team() == TEAM_ALPHA ? TEAM_BETA : TEAM_ALPHA);
		winner.stats.addScore(1);
		G_AnnouncerSound(null, G_SoundIndex("sounds/announcer/ctf/score_team0" + int(brandom(1, 2))), winner.team(), false, null);
		G_AnnouncerSound(null, G_SoundIndex("sounds/announcer/ctf/score_enemy0" + int(brandom(1, 2))), loser.team(), false, null);
		gametype.shootingDisabled = true;
		gametype.removeInactivePlayers = false;
		gametype.pickableItemsMask = 0;
		gametype.dropableItemsMask = 0;
		ftaga_roundStateEndTime = levelTime + 1500;

		for(int i = 0; i < maxClients; i++) {
			Client @client = @G_GetClient(i);
			if ( client.state() < CS_SPAWNED )
        		continue;

			if ( client.team == winner.team() ) {
				GT_Stats_GetPlayer( client ).stats.add("round_wins", 1);
			} else if ( client.team == loser.team() ) {
				GT_Stats_GetPlayer( client ).stats.add("round_losses", 1);
			}
		}

		return;
	} else if( ftaga_state == 2 ) {
		// short buffer period
		return;
	} else if( ftaga_state == 3 ) {
		// delay before new round
		ftaga_state = 0;
		Entity @ent;
		Team @team;
		for ( int i = TEAM_PLAYERS; i < GS_MAX_TEAMS; i++ )
		{
			@team = @G_GetTeam( i );
			// respawn all clients inside the playing teams
			for ( int j = 0; @team.ent( j ) != null; j++ )
			{
				@ent = @team.ent( j );
				ent.client.respawn( false );
			}
		}
		for(int i = 0; i < maxClients; i++) {
			Client @client = @G_GetClient(i);
			if(@client == null) {
				break;
			}
			// respawn players who connected during the previous round
			if(spawnNextRound[i]) {
				client.respawn(false);
				spawnNextRound[i] = false;
			}
		}
		G_RemoveDeadBodies();
        G_RemoveAllProjectiles();
		G_Items_RespawnByType(0, 0, 0);

		FTAG_DefrostTeam(loser.team());
		ftaga_countDown = 5; //delay before new round start
		ftaga_roundStateEndTime = levelTime + 7000;
		return;
	}
}

void FTAG_ResetDefrostCounters() {
	for(int i = 0; i < maxClients; i++) {
		if(spawnNextRound[i]) {
			spawnNextRound[i] = false;
		}

		defrosts[i] = 0;
	}
}

void GT_SpawnGametype() {
	// The map entities have just been spawned. The level is initialized for
	// playing, but nothing has yet started.
	GT_Stats_Init();
}

bool GT_Command(Client @client, const String &cmdString, const String &argsString, int argc) {
	if(cmdString == "gametype") {
		String response = "";
		Cvar fs_game("fs_game", "", 0);
		String manifest = gametype.manifest;
		response += "\n";
		response += "Gametype " + gametype.name + " : " + gametype.title + "\n";
		response += "----------------\n";
		response += "Version: " + gametype.version + "\n";
		response += "Author: " + gametype.author + "\n";
		response += "Mod: " + fs_game.string + (manifest.length() > 0 ? " (manifest: " + manifest + ")" : "") + "\n";
		response += "----------------\n";
		G_PrintMsg(client.getEnt(), response);
		return true;
	} else if ( cmdString == "cvarinfo" ) {
		GENERIC_CheatVarResponse( client, cmdString, argsString, argc );
		return true;
	} else if(cmdString == "callvotevalidate") {
		String votename = argsString.getToken(0);

		if (votename == "fteb") return true;

		client.printMessage("Unknown callvote " + votename + "\n");
		return false;
	} else if(cmdString == "callvotepassed") {
		String votename = argsString.getToken(0);

		if (votename == "fteb") {
			int callvote = argsString.getToken(1);
			return fteb_callvote(client, callvote);
		}

		return false;
	} else if ( cmdString == "fteb_stats" ) {
        Stats_Player@ player = @GT_Stats_GetPlayer( client );
        G_PrintMsg( client.getEnt(), player.stats.toString() );
		return true;
    }

	return false;
}

bool GT_UpdateBotStatus(Entity @ent) {
	// TODO: make bots defrost people
	return GENERIC_UpdateBotStatus(ent);
}

Entity @GT_SelectSpawnPoint(Entity @self) {
	// select a spawning point for a player
	// TODO: make players spawn near where they were defrosted?
	return GENERIC_SelectBestRandomSpawnPoint(self, "info_player_deathmatch");
}

String @GT_ScoreboardMessage(uint maxlen) {
	String scoreboardMessage = "";
	String entry;
	Team @team;
	Entity @ent;
	int i, t, readyIcon;

	for(t = TEAM_ALPHA; t < GS_MAX_TEAMS; t++) {
		@team = @G_GetTeam(t);
		// &t = team tab, team tag, team score (doesn't apply), team ping (doesn't apply)
		entry = "&t " + t + " " + team.stats.score + " " + team.ping + " ";

		if(scoreboardMessage.len() + entry.len() < maxlen) {
			scoreboardMessage += entry;
		}

		for(i = 0; @team.ent(i) != null; i++) {
			@ent = @team.ent(i);

			readyIcon = ent.client.isReady() ? prcYesIcon : 0;

			int playerID = (ent.isGhosting() && (match.getState() == MATCH_STATE_PLAYTIME)) ? -(ent.playerNum + 1) : ent.playerNum;

			if(gametype.isInstagib) {
				// "Name Clan Score Dfrst Ping R"
				entry = "&p " + playerID + " " + ent.client.clanName + " "
					+ ent.client.stats.score + " " + defrosts[ent.client.playerNum] + " " +
					+ ent.client.ping + " " + readyIcon + " ";
			} else {
				// "Name Clan Score Frags Assists Hits Dfrst Ping R"
				entry = "&p " + playerID + " " + ent.client.clanName + " " + ent.client.stats.score + " "
					+ ent.client.stats.frags + " " + assists[ent.client.playerNum] + " " + eb_hits[ent.client.playerNum] + " " + defrosts[ent.client.playerNum] + " "
					+ ent.client.ping + " " + readyIcon + " ";
			}

			if(scoreboardMessage.len() + entry.len() < maxlen) {
				scoreboardMessage += entry;
			}
		}
	}

	return scoreboardMessage;
}

void GT_updateScore(Client @client) {
	if(@client != null) {
		if(gametype.isInstagib) {
			client.stats.setScore(client.stats.frags + defrosts[client.playerNum]);
		} else {
			client.stats.setScore((client.stats.frags * 2) + (eb_hits[client.playerNum] * 2) + (defrosts[client.playerNum] * 2) + assists[client.playerNum]);
		}
	}
}

void GT_ScoreEvent(Client @client, const String &score_event, const String &args) {
	// Some game actions trigger score events. These are events not related to killing
	// opponents, like capturing a flag
	if ( score_event == "award" )
    {
        if(match.getState() == MATCH_STATE_PLAYTIME) {
            Stats_Player@ player = @GT_Stats_GetPlayer( client );
            String cleanAward = "award_" + args.removeColorTokens().tolower();
            player.stats.add(cleanAward, 1);
        }
    } else if(score_event == "dmg") {
		if(match.getState() == MATCH_STATE_PLAYTIME) {
			Entity @attacker = null;
			Entity @target = G_GetEntity(args.getToken(0).toInt());

    		if ( @client != null ) {
       			@attacker = @client.getEnt();
			} else {
				return; // ignore falldamage
			}

			if (@attacker == @target)
				return; // ignore self-damage

			// defrost telefragged frozen players
			if (args.getToken(1).toInt() == 100000) {
				cFrozenPlayer @frozen = @FTAG_GetFrozenForEnt(target);
				if(@frozen != null) {
					frozen.defrost(true);
				}
			}
			
			if(@target != null && @target.client != null) {
				lastShotTime[target.client.playerNum] = levelTime;
			} else {
				return; // ignore shots to frozen players
			}

        	if ( @attacker != null && @attacker.client != null ) {
            	if (gametype.isInstagib == false && attacker.weapon == WEAP_ELECTROBOLT && args.getToken(1).toInt() <= 100) {
					GT_Stats_GetPlayer( attacker.client ).stats.add("eb_hits", 1);
					eb_hits[attacker.client.playerNum]++;

					// Keep track of last two who shot the target
					int[] @targetNum = assistTrack[target.client.playerNum];
					if (targetNum.length() > 0) {
						if (targetNum[0] != attacker.client.playerNum) {
							targetNum.insertAt(0, attacker.client.playerNum);
						}
					} else {
						targetNum.insertAt(0, attacker.client.playerNum);
					}
					
					if (targetNum.length() > 1) targetNum.resize(2);

					// Track hits for multishot detection
					multishotTrack[attacker.client.playerNum]++;
				}
			}

			GT_updateScore(client);
		}
	} else if(score_event == "kill") {
		Entity @attacker = null;
		if(@client != null) {
			@attacker = @client.getEnt();
		}

		FTAG_playerKilled(G_GetEntity(args.getToken(0).toInt()), attacker, G_GetEntity(args.getToken(1).toInt()), args.getToken(3));
	} else if(score_event == "disconnect") {
		cFrozenPlayer @frozen = @FTAG_GetFrozenForPlayer(client);
		if(@frozen != null) {
			frozen.defrost(false);
		}

		/*if(playerIsFrozen[client.playerNum()]) {
		  playerFrozen[client.playerNum()].kill();
		  }*/
	} else if ( score_event == "enterGame" ) {
        if ( @client != null )
        {
            GT_Stats_GetPlayer(client).load();
        }
    } else if ( score_event == "userinfochanged" ) {
        if ( @client != null )
        {
			Stats_Player@ player = @GT_Stats_GetPlayer( client );
			if ( @player.stats == null || client.name != player.stats["name"] ) player.load();
        }
    }
}

void GT_PlayerRespawn(Entity @ent, int old_team, int new_team) {
	// a player is being respawned. This can happen from several ways, as dying, changing team,
	// being moved to ghost state, be placed in respawn queue, being spawned from spawn queue, etc
	if(old_team == TEAM_SPECTATOR) {
		spawnNextRound[ent.client.playerNum] = true;
	} else if(old_team == TEAM_ALPHA || old_team == TEAM_BETA) {
		cFrozenPlayer @frozen = @FTAG_GetFrozenForPlayer(ent.client);

		if(@frozen != null) {
			frozen.defrost(false);
		}
	}

	if(ent.isGhosting()) {
		return;
	}

	if(gametype.isInstagib) {
		ent.client.inventoryGiveItem(WEAP_INSTAGUN);
		ent.client.inventorySetCount(AMMO_INSTAS, 1);
		ent.client.inventorySetCount(AMMO_WEAK_INSTAS, 1);
	} else {
		FTAG_giveInventory(ent.client);
	}

	// auto-select best weapon in the inventory
	if(ent.client.pendingWeapon == WEAP_NONE) {
		ent.client.selectWeapon(-1);
	}

	// add a teleportation effect
	ent.respawnEffect();
}

// Thinking function. Called each frame
void GT_ThinkRules() {
	if(match.scoreLimitHit()) {
		if (matchEndTime == 0) {
			matchEndTime = levelTime;
			scorelimit = true; // Used to prevent statistic writing when map does not end naturally
		}

		if (int(levelTime) > int(matchEndTime) + 1000) match.launchState(match.getState() + 1); // Small delay before score screen fires
	}

	if (match.timeLimitHit() || match.suddenDeathFinished()) {
		match.launchState(match.getState() + 1);
	}

	GENERIC_Think();

	// print count of players alive and show class icon in the HUD

    Team @team;
    int[] alive( GS_MAX_TEAMS );

    alive[TEAM_SPECTATOR] = 0;
    alive[TEAM_PLAYERS] = 0;
    alive[TEAM_ALPHA] = 0;
    alive[TEAM_BETA] = 0;

    for ( int t = TEAM_ALPHA; t < GS_MAX_TEAMS; t++ )
    {
        @team = @G_GetTeam( t );
        for ( int i = 0; @team.ent( i ) != null; i++ )
        {
            if ( !team.ent( i ).isGhosting() )
                alive[t]++;
        }
    }

    G_ConfigString( CS_GENERAL, "" + alive[TEAM_ALPHA] );
    G_ConfigString( CS_GENERAL + 1, "" + alive[TEAM_BETA] );

	for(int i = 0; i < maxClients; i++) {
		Client @client = @G_GetClient(i);
		if(match.getState() != MATCH_STATE_PLAYTIME) {
			client.setHUDStat(STAT_MESSAGE_ALPHA, 0);
			client.setHUDStat(STAT_MESSAGE_BETA, 0);
			client.setHUDStat(STAT_IMAGE_BETA, 0);
		} else {
			client.setHUDStat(STAT_MESSAGE_ALPHA, CS_GENERAL);
			client.setHUDStat(STAT_MESSAGE_BETA, CS_GENERAL + 1);
		}
	}

	if(match.getState() >= MATCH_STATE_POSTMATCH) {
		return;
	}

	if ( ftaga_roundStateEndTime != 0 ) {
		if ( ftaga_roundStateEndTime < levelTime ) {
			FTAG_NewRound (team, 3);
            return;
        }
		if ( ftaga_countDown > 0 ) {
			// we can't use the automatic countdown announces because they are based on the
			// matchstate timelimit, and prerounds don't use it. So, fire the announces "by hand".
			int remainingSeconds = int( ( ftaga_roundStateEndTime - levelTime ) * 0.001f );
			//G_PrintMsg(null, String ( ftaga_countDown ) );
			if ( remainingSeconds < 0 )
				remainingSeconds = 0;
			if ( remainingSeconds < ftaga_countDown ) {
				ftaga_countDown = remainingSeconds;
				if ( ftaga_countDown == 4 ) {
					int soundIndex = G_SoundIndex( "sounds/announcer/countdown/ready0" + (1 + (rand() & 1)) );
					G_AnnouncerSound( null, soundIndex, GS_MAX_TEAMS, false, null );
				} else if( ftaga_countDown <= 3 ) {
					int soundIndex = G_SoundIndex( "sounds/announcer/countdown/" + ftaga_countDown + "_0" + (1 + (rand() & 1)) );
					G_AnnouncerSound( null, soundIndex, GS_MAX_TEAMS, false, null );
				}
				G_CenterPrintMsg( null, String( ftaga_countDown ) );
				if (ftaga_countDown == 0) {
					int soundIndex = G_SoundIndex( "sounds/announcer/countdown/fight0" + (1 + (rand() & 1)) );
            		G_AnnouncerSound( null, soundIndex, GS_MAX_TEAMS, false, null );
            		G_CenterPrintMsg( null, 'Fight!');
					gametype.shootingDisabled = false;
					gametype.removeInactivePlayers = true;
					gametype.pickableItemsMask = gametype.spawnableItemsMask;
					gametype.dropableItemsMask = gametype.spawnableItemsMask;
					ftaga_roundStateEndTime = 0;
					ftaga_state = 0;
				}
			}
		}
	}

	// GENERIC_Think(); why twice?

	for(int i = 0; i < maxClients; i++) {
		//defrostMessage[i] = "Defrosting:";
		Client @client = @G_GetClient(i);
		if ( client.state() < CS_SPAWNED )
        	continue;

		if(@client == null || FTAG_PlayerFrozen(@client)) {
			continue;
		}

		Entity @ent = client.getEnt();

		// Detect ammo changes to detect when player shoots to do some knockback and stats stuff to enjoy the game better.
		// Checking teams to prevent procs on spectators. Checking ghosting to prevent proc when joining mid-match.
		// Should shooting be done by detecting ET_EVENT instead?
		if ( client.inventoryCount(AMMO_BOLTS) < 99 && ( client.team == 2 || client.team == 3 )) {
			if ( gametype.isInstagib == false ) {
				// Create explosion for fake knockback
				if (ftebElectroboltKnockback.boolean) {
					Vec3 eye = ent.origin + Vec3(0, 0, ent.viewHeight);

					Vec3 dir, right, up;
					// unit vector
					ent.angles.angleVectors(dir, right, up);

					Vec3 player_look;
					player_look = eye + dir * 9001; // Max distance to apply the explosion

					Trace tr; // tr.ent: -1 = nothing; 0 = wall; 1 = player
					tr.doTrace(eye, Vec3(), Vec3(), player_look, 1, MASK_SOLID);

					Entity @boom = @G_SpawnEntity("boom");
					boom.origin = tr.get_endPos();
					boom.splashDamage(@boom, 72, 0, 67 * g_knockback_scale.value, 0, MOD_EXPLOSIVE);
					
					// destroy splash entity
					boom.freeEntity();
				}

				if ( match.getState() == MATCH_STATE_PLAYTIME && !ent.isGhosting()) {
					GT_Stats_GetPlayer( client ).stats.add("eb_shots", 1);
				}
				
				client.inventorySetCount(AMMO_BOLTS, 99);
				award_playerHit(client.getEnt(), multishotTrack[client.playerNum]);
				multishotTrack[client.playerNum] = 0;
			}
		}
		
		if(ent.health > ent.maxHealth) {
			ent.health -= (frameTime * 0.001f);
		}

		client.setHUDStat(STAT_PROGRESS_SELF, playerSTAT_PROGRESS_SELFdelayed[i]);
		if(playerLastTouch[i] < levelTime) {
			playerSTAT_PROGRESS_SELFdelayed[i] = 0;
		}

		/* check if player is looking at a frozen player and
		   show something like "Player (50%)" if they are */

		Vec3 origin = client.getEnt().origin;
		Vec3 eye = origin + Vec3(0, 0, client.getEnt().viewHeight);

		Vec3 dir, right, up;
		// unit vector
		client.getEnt().angles.angleVectors(dir, right, up);

		String msg;

		for(cFrozenPlayer @frozen = @frozenHead; @frozen != null; @frozen = @frozen.next) {
			if(client.team == frozen.client.team) {
				/* this compares the dot product of the vector from
				   player's eye and the model's center and the vector
				   from the player's eye to the model's top with the
				   dot product of the vector from the player's eye to
				   the model's center and the player's angle vector

				   it should work nicely from all angles and distances

				   TODO: it's actually stupid at close range since it
				   assumes you're looking at h1o
				 */

				Entity @model = @frozen.model;
				Vec3 mid = model.origin/* + (mins + maxs) * 0.5*/;

				if(origin.distance(mid) <= FTAG_DEFROST_RADIUS) {
					continue;
				}

				Vec3 mins, maxs;
				model.getSize(mins, maxs);

				Vec3 top = mid + Vec3(0, 0, FTAG_DEFROST_RADIUS);

				Vec3 eyemid = mid - eye;
				eyemid.normalize();
				Vec3 eyetop = top - eye;
				eyetop.normalize();

				if(dot(dir, eyemid) >= dot(eyetop, eyemid)) {
					msg += frozen.client.name + " (" + ((frozen.defrostTime * 100) / FTAG_DEFROST_TIME) + "%), ";
				}
			}
		}

		int len = msg.len();
		if(len != 0) {
			G_ConfigString(CS_GENERAL + 2 + i, msg.substr(0, len - 2));

			client.setHUDStat(STAT_MESSAGE_SELF, CS_GENERAL + 2 + i);
		} else {
			client.setHUDStat(STAT_MESSAGE_SELF, 0);
		}
		
		// Draw hurt players with red Regeneration frame
		if ( (ent.health + client.armor) < 76 && ent.team != TEAM_SPECTATOR ) {
            ent.effects |= EF_REGEN;
		} else if ( (ent.health + client.armor) > 150 && ent.team != TEAM_SPECTATOR ) { // And boosted solo player with blue Shell frame
			ent.effects |= EF_SHELL;
		}
	}

	/*for(int i = 0; i < maxClients; i++) {
	  if(defrostMessage[i].len() > 11) {
	  G_ConfigString(CS_GENERAL + 1 + i, defrostMessage[i].substr(1, 6));
	  G_GetClient(i).setHUDStat(STAT_MESSAGE_SELF, CS_GENERAL + 1 + i);
	  } else {
	  G_GetClient(i).setHUDStat(STAT_MESSAGE_SELF, 0);
	  }
	  }*/

	// if everyone on a team is frozen then start a new round
	if(match.getState() == MATCH_STATE_PLAYTIME) {
		int count;
		int size;
		for(int i = TEAM_ALPHA; i < GS_MAX_TEAMS; i++) {
			@team = @G_GetTeam(i);
			count = 0;
			size = 0;

			for(int j = 0; @team.ent(j) != null; j++) {
				size++;

				if(!team.ent(j).isGhosting()) {
					count++;
				}
			}

			if(count == 1 && size > 1) { // Only show the message when team size > 1
				for(int h = 0; @team.ent(h) != null; h++) {
					G_CenterPrintMsg( @team.ent(h), "Last unfrozen teammate!\n" );
				}
			}

			if(count == 0) {
				FTAG_NewRound(team, 1);
				break;
			}
		}
	}

	if(@frozenHead != null) {
		frozenHead.think();
	}

	if(doRemoveRagdolls) {
		G_RemoveDeadBodies();
		doRemoveRagdolls = false;
	}
}

bool GT_MatchStateFinished(int incomingMatchState) {
	// The game has detected the end of the match state, but it
	// doesn't advance it before calling this function.
	// This function must give permission to move into the next
	// state by returning true.
	if(match.getState() <= MATCH_STATE_WARMUP && incomingMatchState > MATCH_STATE_WARMUP && incomingMatchState < MATCH_STATE_POSTMATCH) {
		match.startAutorecord();
	}

	if(match.getState() == MATCH_STATE_POSTMATCH) {
		match.stopAutorecord();

		// Execute proper map pool according to the amount of players
		if (playerAmount == 0) {
			Team @team;
			
			for (int i = 0; i < 2; i++) {
				@team = @G_GetTeam(i + TEAM_ALPHA);
				for(int j = 0; @team.ent(j) != null; j++) {
					playerAmount++;
				}
			}

			switch (playerAmount) {
				case 0:
				case 1:
				case 2:
				case 3:
					mapPool = "0-3";
					break;
				case 4:
					mapPool = "4";
					break;
				case 5:
				case 6:
					mapPool = "5-6";
					break;
				default:
					mapPool = "7+";
					break;
			}

			G_CmdExecute("exec configs/server/gametypes/" + gametype.name + "_maps_" + mapPool + ".cfg silent");
		}
	}

	return true;
}

void GT_MatchStateStarted() {
	// the match state has just moved into a new state. Here is the
	// place to set up the new state rules
	switch(match.getState()) {
		case MATCH_STATE_WARMUP:
			gametype.pickableItemsMask = gametype.spawnableItemsMask;
			gametype.dropableItemsMask = gametype.spawnableItemsMask;

			GENERIC_SetUpWarmup();

			for(int team = TEAM_PLAYERS; team < GS_MAX_TEAMS; team++) {
				gametype.setTeamSpawnsystem(team, SPAWNSYSTEM_INSTANT, 0, 0, false);
			}

			break;

		case MATCH_STATE_COUNTDOWN:
			gametype.pickableItemsMask = 0;
			gametype.dropableItemsMask = 0;

			GENERIC_SetUpCountdown();

			break;

		case MATCH_STATE_PLAYTIME:
			gametype.pickableItemsMask = gametype.spawnableItemsMask;
			gametype.dropableItemsMask = gametype.spawnableItemsMask;

			GENERIC_SetUpMatch();

			FTAG_ResetDefrostCounters();

			// set spawnsystem type to not respawn the players when they die
			for(int team = TEAM_PLAYERS; team < GS_MAX_TEAMS; team++) {
				gametype.setTeamSpawnsystem(team, SPAWNSYSTEM_HOLD, 0, 0, true);
			}

			break;

		case MATCH_STATE_POSTMATCH:
			gametype.pickableItemsMask = 0;
			gametype.dropableItemsMask = 0;

			GENERIC_SetUpEndMatch();

			break;

		default:
			break;
	}
}

void GT_Shutdown() {
	// the gametype is shutting down cause of a match restart or map change
}

void GT_InitGametype() {
	// Important: This function is called before any entity is spawned, and
	// spawning entities from it is forbidden. ifyou want to make any entity
	// spawning at initialization do it in GT_SpawnGametype, which is called
	// right after the map entities spawning.
	gametype.title = "Electrobolt Freeze Tag";
	gametype.version = "0.9.5.6";
	gametype.author = "Mike^4JS";
	// Forked by Gelmo
	// decldev was here

	gametype.spawnableItemsMask = ( IT_WEAPON | IT_AMMO );
	if(gametype.isInstagib) {
		gametype.spawnableItemsMask &= ~uint(G_INSTAGIB_NEGATE_ITEMMASK);
	}
	gametype.spawnableItemsMask = 0;
    gametype.respawnableItemsMask = 0;
    gametype.dropableItemsMask = 0;
    gametype.pickableItemsMask = 0;

	gametype.isTeamBased = true;
	gametype.isRace = false;
	gametype.hasChallengersQueue = false;
	gametype.maxPlayersPerTeam = 0;

	gametype.ammoRespawn = 20;
	gametype.armorRespawn = 25;
	gametype.weaponRespawn = 15;
	gametype.healthRespawn = 25;
	gametype.powerupRespawn = 90;
	gametype.megahealthRespawn = 20;
	gametype.ultrahealthRespawn = 60;
	gametype.readyAnnouncementEnabled = false;

	gametype.scoreAnnouncementEnabled = true;
	gametype.countdownEnabled = true;
	gametype.mathAbortDisabled = false;
	gametype.shootingDisabled = false;
	gametype.infiniteAmmo = false;
	gametype.canForceModels = true;
	gametype.canShowMinimap = true;
	gametype.teamOnlyMinimap = true;
	gametype.removeInactivePlayers = true;

	gametype.mmCompatible = true;

	gametype.spawnpointRadius = 256 * 2;
	if(gametype.isInstagib) {
		gametype.spawnpointRadius *= 1;
	}

	// set spawnsystem type to instant while players join
	for(int t = TEAM_PLAYERS; t < GS_MAX_TEAMS; t++) {
		gametype.setTeamSpawnsystem(t, SPAWNSYSTEM_INSTANT, 0, 0, false);
	}

	// define the scoreboard layout
	if(gametype.isInstagib) {
		G_ConfigString(CS_SCB_PLAYERTAB_LAYOUT, "%n 112 %s 52 %i 52 %i 52 %l 48 %p 18");
		G_ConfigString(CS_SCB_PLAYERTAB_TITLES, "Name Clan Score Dfrst Ping R");
	} else {
		G_ConfigString(CS_SCB_PLAYERTAB_LAYOUT, "%n 100 %s 52 %i 36 %i 36 %i 36 %i 36 %i 36 %l 36 %r l1" );
		G_ConfigString(CS_SCB_PLAYERTAB_TITLES, "Name Clan Score Frags Assts Hits Dfrst Ping R" );
	}

	// precache images that can be used by the scoreboard
	prcYesIcon = G_ImageIndex("gfx/hud/icons/vsay/yes");

	// add commands
	G_RegisterCommand("gametype");
	G_RegisterCommand("fteb_stats");

	// add votes
	G_RegisterCallvote("fteb", "<1 or 2>", "integer", "1, SHUFFLE: Actually shuffle teams.\n\n2, REBALANCE: Balance teams by calculating a simple MMR from saved statistics.");

	// Create configs for different map pools by player amount
	// These are checked for in GT_MatchStateFinished()
	createMapPoolFile("0-3", "wda1, wda2, wda3, wda4, wda5, wdm1, wdm5, wdm9, wdm11, wdm12, wdm14, wdm15, wdm17, wdm18, wdm20");
	createMapPoolFile("4", "wdm1, wdm5, wdm9, wdm11, wdm12, wdm14, wdm15, wdm17, wdm18, wdm20");
	createMapPoolFile("5-6", "wdm1, wdm8, wdm9, wdm12, wdm14, wdm17, wdm18, wdm20");
	createMapPoolFile("7+", "wca1, wbomb1, wbomb2, wbomb3, wbomb4, wbomb5, wbomb6");

	if(!G_FileExists("configs/server/gametypes/" + gametype.name + ".cfg")) {
		String config;
		// the config file doesn't exist or it's empty, create it
		config = "// '" + gametype.title + "' gametype configuration file\n"
			+ "// This config will be executed each time the gametype is started\n"
			+ "\n// " + gametype.title + " specific settings\n"
			//+ "set g_noclass_inventory \"eb bolts\"\n"
            //+ "set g_class_strong_ammo \"1\" // EB\n"
			+ "\n// map rotation\n"
			+ "set g_maplist \"wca1\" // List of maps in automatic rotation. This is overwritten in " + gametype.name + "_maps_xx.cfg.\n"
			+ "set g_maprotation \"1\"   // 0 = same map, 1 = in order, 2 = random\n"
			+ "\n// game settings\n"
			+ "set fteb_reversehandicap \"1\" // Give more armor as solo in 1v2+\n"
			+ "set fteb_stats_enable \"1\"\n"
			+ "set fteb_stats_minplayers \"4\"\n"
			+ "set fteb_stats_debug \"0\"\n"
			+ "set fteb_rebalance_debug \"0\"\n"
			+ "set fteb_defrost_time \"3000\"\n"
			+ "set fteb_defrost_shatter_delay \"6000\"\n"
			+ "set fteb_defrost_attack_delay \"2000\"\n"
			+ "set fteb_defrost_hazard_scale \"2\"\n"
			+ "set fteb_defrost_attack_scale \"5\"\n"
			+ "set fteb_defrost_decay_scale \"5\"\n"
			+ "set fteb_defrost_radius \"144\"\n"
			+ "set fteb_electrobolt_knockback \"1\"\n\n"
			+ "set g_scorelimit \"11\"\n"
			+ "set g_timelimit \"0\"\n"
			+ "set g_warmup_enabled \"1\"\n"
			+ "set g_warmup_timelimit \"1.5\"\n"
			+ "set g_match_extendedtime \"0\"\n"
			+ "set g_allow_falldamage \"0\"\n"
			+ "set g_allow_selfdamage \"0\"\n"
			+ "set g_allow_teamdamage \"0\"\n"
			+ "set g_allow_stun \"0\"\n"
			+ "set g_teams_maxplayers \"0\"\n"
			+ "set g_teams_allow_uneven \"0\"\n"
			+ "set g_countdown_time \"5\"\n"
			+ "set g_maxtimeouts \"3\" // -1 = unlimited\n"
			+ "set g_challengers_queue \"0\"\n"
			+ "\necho \"" + gametype.name + ".cfg executed\"\n";
		G_WriteFile("configs/server/gametypes/" + gametype.name + ".cfg", config);
		G_Print("Created default config file for '" + gametype.name + "'\n");
		G_CmdExecute("exec configs/server/gametypes/" + gametype.name + ".cfg silent");
	}

	G_Print("Gametype '" + gametype.title + "' initialized\n");
}
