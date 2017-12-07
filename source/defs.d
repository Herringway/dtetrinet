module dtetrinet.defs;

enum TetrinetCommand {
	playerNumber,
	playerJoin,
	playerLeave,
	team,
	winList,
	partyLine,
	partyLineAction,
	gMsg,
	inGame,
	levelUpdate,
	specialUsed,
	playerLost,
	playerWon,
	pause,
	endGame,
	noConnecting
}

enum TetrinetCommandStrings {
	playerNumber = "playernum",
	playerJoin = "playerjoin",
	playerLeave = "playerleave",
	team = "team",
	winList = "winlist",
	partyLine = "pline",
	partyLineAction = "plineact",
	gMsg = "gmsg",
	inGame = "ingame",
	levelUpdate = "lvl",
	specialUsed = "sb",
	playerLost = "playerlost",
	playerWon = "playerwon",
	pause = "pause",
	endGame = "endgame",
	noConnecting = "noconnecting"
}

enum TetrifastCommandStrings {
	playerNumber = ")#)(!@(*3",
	playerJoin = TetrinetCommandStrings.playerJoin,
	playerLeave = TetrinetCommandStrings.playerLeave,
	team = TetrinetCommandStrings.team,
	winList = TetrinetCommandStrings.winList,
	partyLine = TetrinetCommandStrings.partyLine,
	partyLineAction = TetrinetCommandStrings.partyLineAction,
	gMsg = TetrinetCommandStrings.gMsg,
	inGame = TetrinetCommandStrings.inGame,
	levelUpdate = TetrinetCommandStrings.levelUpdate,
	specialUsed = TetrinetCommandStrings.specialUsed,
	playerLost = TetrinetCommandStrings.playerLost,
	playerWon = TetrinetCommandStrings.playerWon,
	pause = TetrinetCommandStrings.pause,
	endGame = TetrinetCommandStrings.endGame,
	noConnecting = TetrinetCommandStrings.noConnecting
}

enum TetrinetClient {
	tetrinet,
	tetrifast
}
