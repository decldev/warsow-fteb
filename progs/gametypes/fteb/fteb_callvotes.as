bool ftebCallvoteDebug = false;

bool fteb_callvote(Client @client, int callvote) {
	switch (callvote) {
		case 1:
			if (match.getState() != MATCH_STATE_WARMUP) {
				G_PrintMsg(client.getEnt(), "Teams can only be shuffled during warmup");
				return false;
			}

			fteb_shuffle();
			return true;
		case 2:
			if (match.getState() != MATCH_STATE_WARMUP) {
				G_PrintMsg(client.getEnt(), "Teams can only be rebalanced during warmup");
				return false;
			}

			fteb_rebalance();
			return true;
	}

    return false;
}

void fteb_shuffle() {
	int numPlayers;
	array<int> alpha, newAlpha, beta, newBeta, allPlayers;
	Client @client;

	for ( int i = 0; i < maxClients; i++ ) {
		@client = @G_GetClient(i);

		if (int(client.team) == 2) alpha.insertLast(client.playerNum);
		if (int(client.team) == 3) beta.insertLast(client.playerNum);
	}

	alpha.sortAsc();
	beta.sortAsc();
	newAlpha = alpha;
	newBeta = beta;

	// Shuffle until teams are not the same as before
	while (alpha == newAlpha || beta == newBeta || alpha == newBeta || beta == newAlpha) {
		allPlayers = alpha;
		for (uint i = 0; i < beta.length(); i++) allPlayers.insertAt(allPlayers.length(), beta[i]);
		numPlayers = allPlayers.length();
		newAlpha.resize(0);
		newBeta.resize(0);

		// Fisher-Yates
		for (int i = numPlayers - 1; i > 0; i--) {
			int newPos = rand() % (i + 1);
			int tempPos = allPlayers[i];
			allPlayers[i] = allPlayers[newPos];
			allPlayers[newPos] = tempPos;
		}

		// Split the teams
		for (int i = 0; i < numPlayers; i++) {
			if (i < numPlayers / 2) {
				newAlpha.insertLast(allPlayers[i]);
				continue;
			}

			newBeta.insertLast(allPlayers[i]);
		}

		newAlpha.sortAsc();
		newBeta.sortAsc();
	}

	// Put players in new teams
	for (uint i = 0; i < newAlpha.length(); i++) {
		@client = @G_GetClient(newAlpha[i]);
		client.team = TEAM_ALPHA;
		client.respawn(false);
	}

	for (uint i = 0; i < newBeta.length(); i++) {
		@client = @G_GetClient(newBeta[i]);
		client.team = TEAM_BETA;
		client.respawn(false);
	}

	G_PrintMsg(null, S_COLOR_CYAN + "Teams shuffled!\n");
}

float parseKey(array<array<String @>> tokens, String key) {
	int index;
	String value;

	for (int i = 0; i < int(tokens.length()); i++) {
		index = tokens[i][0] == ("\"" + key + "\"") ? i : -1;
		
		if (index > -1) {
			value = tokens[index][1];
			value = value.replace("\"", "");

			return float(value);
		}
	}

	return 0;
}

void fteb_rebalance() {
	int alphaMMR = 0, betaMMR = 0, bestAlphaMMR = 0, bestBetaMMR = 0, currentDiff = 99999, bestDiff = 99999; //, numPlayers = 0;
	int[] playerStats(maxClients, 0), alpha, newAlpha, beta, newBeta, numPlayers;
	Client @client;

	int iterationCount = 0;
	int permutationCount = 0;

	// Parse player statistic strings
	for (int i = 0; i < maxClients; i++) {
		@client = @G_GetClient(i);

		if (client.team == TEAM_ALPHA || client.team == TEAM_BETA) {
			float totalWins, totalLosses, totalMatches, totalRoundWins, totalRoundLosses, totalRounds, totalKills, totalDeaths, totalAssists, totalDefrosts;
			float averageKDAD, averageWL;
			array<String @> tokenKeys;
			array<array<String @>> tokens;

			Stats_Player@ player = @GT_Stats_GetPlayer(client);
			String clientStats = player.stats.toString();

			// Default new players to static 50 MMR
			if (clientStats == "") {
				playerStats[client.playerNum] = 50;
				continue;
			}

			tokenKeys = StringUtils::Split(clientStats, "\n");

			for (uint j = 0; j < tokenKeys.length(); j++) {
				tokens.insertLast(StringUtils::Split(tokenKeys[j], " "));
			}

			totalKills = parseKey(tokens, "kills");
			totalDeaths = parseKey(tokens, "deaths");
			totalAssists = parseKey(tokens, "assists");
			totalWins = parseKey(tokens, "match_wins");
			totalLosses = parseKey(tokens, "match_losses");
			totalMatches = totalWins + totalLosses;
			totalRoundWins = parseKey(tokens, "round_wins");
			totalRoundLosses = parseKey(tokens, "round_losses");
			totalRounds = totalRoundWins + totalRoundLosses;
			totalDefrosts = parseKey(tokens, "defrosts");

			averageKDAD = (totalKills + totalAssists + (totalDefrosts * 1.5f)) / (totalDeaths > 0 ? totalDeaths : 1);
			averageWL = (totalWins / (totalMatches > 0 ? totalMatches : 1) + totalRoundWins / (totalRounds > 0 ? totalRounds : 1)) / 2.0f;

			// Poorly calculate player MMR
			playerStats[client.playerNum] = int((averageKDAD * averageWL) * 1000.0f);

			// Default new and/or weak players to 100
			if (playerStats[client.playerNum] < 100 || totalRounds < 50) {
				playerStats[client.playerNum] = 100;
			}

			if (ftebCallvoteDebug) G_PrintMsg(null, "# " + client.name + " MMR: " + playerStats[client.playerNum] + " (KDAD: " + averageKDAD + " - WL: " + averageWL + ")\n");
			numPlayers.insertLast(client.playerNum);
		}
	}

	// Brute force the shit out of possible team combinations
	// Heavy in large player amounts like 20+
	for (int64 i = 0; i < (1 << numPlayers.length()); i++) {
		alpha.resize(0);
		beta.resize(0);
		alphaMMR = 0;
		betaMMR = 0;

		for (uint j = 0; j < numPlayers.length(); j++) {
			if ((i & (1 << j)) != 0) {
				alpha.insertLast(numPlayers[j]);
			} else {
				beta.insertLast(numPlayers[j]);
			}

			iterationCount++;
		}

		permutationCount++;

		// Skip uneven sized teams
		if (abs(alpha.length() - beta.length()) > 1) continue;

		// Calculate difference in total MMR between the teams
		for (uint k = 0; k < alpha.length(); k++) alphaMMR += playerStats[alpha[k]];
		for (uint k = 0; k < beta.length(); k++) betaMMR += playerStats[beta[k]];

		currentDiff = abs(alphaMMR - betaMMR);
		if (currentDiff < bestDiff) {
			bestDiff = currentDiff;
			newAlpha = alpha;
			newBeta = beta;
			bestAlphaMMR = alphaMMR;
			bestBetaMMR = betaMMR;

			if (ftebCallvoteDebug) G_PrintMsg(null, "# New best difference: " + bestDiff + "\n");
		}
	}

	// Put players in new teams
	for (uint i = 0; i < newAlpha.length(); i++) {
		@client = @G_GetClient(newAlpha[i]);
		client.team = TEAM_ALPHA;
		client.respawn(false);
	}

	for (uint i = 0; i < newBeta.length(); i++) {
		@client = @G_GetClient(newBeta[i]);
		client.team = TEAM_BETA;
		client.respawn(false);
	}

	if (ftebCallvoteDebug) G_PrintMsg(null, "Ran " + iterationCount + " iterations and " + permutationCount + " permutations\n");
	G_PrintMsg(null, S_COLOR_CYAN + "Teams rebalanced: " + S_COLOR_YELLOW + bestAlphaMMR + S_COLOR_CYAN + " VS " + S_COLOR_YELLOW + bestBetaMMR + "\n");
}