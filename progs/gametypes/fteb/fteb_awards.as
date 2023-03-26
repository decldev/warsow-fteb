void award_playerHit(Entity @attacker, int multiplier) {
	if(@attacker == null || @attacker.client == null)
		return;

	switch (multiplier) {
		case 0:
		case 1:
			break;
		case 2:
			attacker.client.addAward(S_COLOR_GREEN + "Double!");
			break;
		case 3:
			attacker.client.addAward(S_COLOR_YELLOW + "Triple!!");
			break;
		case 4:
			attacker.client.addAward(S_COLOR_ORANGE + "QUADRUPLE!!!");
			break;
		default: 
			attacker.client.addAward(S_COLOR_RED + "HOLY SHIT");
			break;
	}
	
}