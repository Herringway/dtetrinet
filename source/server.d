module dtetrinet.server;

import dtetrinet.tetrinet;
import dtetrinet.tetris;
import dtetrinet.sockets;

__gshared int linuxmode;
__gshared int ipv6_only;

__gshared int quit;
__gshared int listen_sock;
__gshared int listen_sock6;
int[6] player_socks = [-1, -1, -1, -1, -1, -1];
TCPConnection[6] player_connections;
bool[6] players_connected;
__gshared char[6][4] player_ips;
__gshared int[6] player_lost;
__gshared int[6] player_modes;

import vibe.core.net;

/*************************************************************************/

/* Return a string containing the winlist in a format suitable for sending
 * to clients.
 */

string winlist_str() nothrow {
	import std.exception : assumeWontThrow;
	import std.format : format;
	string output;

	for (uint i = 0; i < MAXWINLIST && winlist[i].name.ptr != null; i++) {
		string str;
		if (linuxmode) {
			str = assumeWontThrow(format!" %c%s;%d;%d"(winlist[i].team ? 't' : 'p', winlist[i].name.ptr, winlist[i].points, winlist[i].games));
		} else {
			str = assumeWontThrow(format!" %c%s;%d"(winlist[i].team ? 't' : 'p', winlist[i].name.ptr, winlist[i].points));
		}
		output ~= str;
		//s += snprintf(s, buf.sizeof - (s - cast(ulong)buf.ptr), linuxmode ? " %c%s;%d;%d" : " %c%s;%d", winlist[i].team ? 't' : 'p', winlist[i].name.ptr, winlist[i].points, winlist[i].games);
	}
	return output;
}

struct WinEntry {
	string player;
	string team;
	int points;
	int games;
}

struct Settings {
	bool linuxMode;
	bool ipv6Only;
	bool averageLevels;
	bool classic;
	int initialLevel;
	int levelInc;
	int linesPerLevel;
	int[] pieceWeights;
	int specialCapacity;
	int specialCount;
	int specialLines;
	int[] specials;
	WinEntry[] winlist;
}

/*************************************************************************/
/*************************************************************************/

/* Read the configuration file. */

auto read_config() {
	import easysettings : loadSettings;
	return loadSettings!Settings("tetrinet");
}

/*************************************************************************/

/*************************************************************************/

/* Re-write the configuration file. */

void write_config() {
	import easysettings : saveSettings;
	saveSettings(Settings(), "tetrinet");
}

/*************************************************************************/
/*************************************************************************/

/* Send a message to a single player. */

void send_to(string fmt, T...)(long player, T args) {
	import std.exception : assumeWontThrow;
	import std.format : format;
	import std.conv : to;

	if (players_connected[player]) {
		sockprintf!fmt(player_connections[player], args);
	}
}

/*************************************************************************/

/* Send a message to all players. */

void send_to_all(string fmt, T...)(T args) {
	import std.exception : assumeWontThrow;
	import std.format : sformat;
	import std.conv : to;

	int i;

	for (i = 0; i < 6; i++) {
		if (players_connected[i]) {
			sockprintf!fmt(player_connections[i], args);
		}
	}
}

/*************************************************************************/

/* Send a message to all players but the given one. */

void send_to_all_but(string fmt, T...)(long player, T args) {
	import std.exception : assumeWontThrow;
	import std.format : format;
	import std.conv : to;

	int i;

	for (i = 0; i < 6; i++) {
		if (i != player && players_connected[i]) {
			sockprintf!fmt(player_connections[i], args);
		}
	}
}

/*************************************************************************/

/* Send a message to all players but those on the same team as the given
 * player.
 */

void send_to_all_but_team(string fmt, T...)(long player, T args) {
	import std.exception : assumeWontThrow;
	import std.format : format;
	import std.conv : to;

	int i;
	auto team = teams[player];

	for (i = 0; i < 6; i++) {
		if (i + 1 != player && players_connected[i] && (!team || !teams[i] || (teams[i] != team))) {
			sockprintf!fmt(player_connections[i], args);
		}
	}
}

/*************************************************************************/
/*************************************************************************/

/* Add points to a given player's [team's] winlist entry, or make a new one
 * if they rank.
 */

void add_points(int player, int points) {
	int i;

	if (!players[player]) {
		return;
	}
	for (i = 0; i < MAXWINLIST && winlist[i].name != winlist[i].name.init; i++) {
		if (!winlist[i].team && !teams[player] && (winlist[i].name == players[player])) {
			break;
		}
		if (winlist[i].team && teams[player] && (winlist[i].name == teams[player])) {
			break;
		}
	}
	if (i == MAXWINLIST) {
		for (i = 0; i < MAXWINLIST && winlist[i].points >= points; i++) {

		}
	}
	if (i == MAXWINLIST)
		return;
	if (winlist[i].name == winlist[i].name.init) {
		if (teams[player]) {
			winlist[i].name = teams[player];
			winlist[i].team = 1;
		} else {
			winlist[i].name = players[player];
			winlist[i].team = 0;
		}
	}
	winlist[i].points += points;
}

/*************************************************************************/

/* Add a game to a given player's [team's] winlist entry. */

void add_game(int player) {
	int i;

	if (!players[player])
		return;
	for (i = 0; i < MAXWINLIST && winlist[i].name != winlist[i].name.init; i++) {
		if (!winlist[i].team && !teams[player] && (winlist[i].name == players[player])) {
			break;
		}
		if (winlist[i].team && teams[player] && (winlist[i].name == teams[player])) {
			break;
		}
	}
	if (i == MAXWINLIST || winlist[i].name != winlist[i].name.init) {
		return;
	}
	winlist[i].games++;
}

/*************************************************************************/

/* Sort the winlist. */

void sort_winlist() {
	import std.algorithm : swap;
	int i, j, best, bestindex;

	for (i = 0; i < MAXWINLIST && winlist[i].name != winlist[i].name.init; i++) {
		best = winlist[i].points;
		bestindex = i;
		for (j = i + 1; j < MAXWINLIST && winlist[j].name != winlist[i].name.init; j++) {
			if (winlist[j].points > best) {
				best = winlist[j].points;
				bestindex = j;
			}
		}
		if (bestindex != i) {
			swap(winlist[i], winlist[bestindex]);
		}
	}
}

/*************************************************************************/

/* Take care of a player losing (which may end the game). */

void player_loses(long player) {
	import std.uni : icmp;
	int i, j, order, end = 1, winner = -1, second = -1, third = -1;

	if (player < 1 || player > 6 || player_socks[player] < 0) {
		return;
	}
	order = 0;
	for (i = 1; i <= 6; i++) {
		if (player_lost[i] > order) {
			order = player_lost[i];
		}
	}
	player_lost[player] = order + 1;
	for (i = 0; i < 6; i++) {
		if (player_socks[i] >= 0 && !player_lost[i]) {
			if (winner < 0) {
				winner = i;
			} else if (!teams[winner] || !teams[i] || icmp(teams[winner], teams[i]) != 0) {
				end = 0;
				break;
			}
		}
	}
	if (end) {
		send_to_all!"endgame"();
		playing_game = 0;
		/* Catch the case where no players are left (1-player game) */
		if (winner > 0) {
			send_to_all!"playerwon %d"(winner);
			add_points(winner, 3);
			order = 0;
			for (i = 1; i <= 6; i++) {
				if (player_lost[i] > order && (!teams[winner] || !teams[i] || icmp(teams[winner], teams[i]) != 0)) {
					order = player_lost[i];
					second = i;
				}
			}
			if (order) {
				add_points(second, 2);
				player_lost[second] = 0;
			}
			order = 0;
			for (i = 1; i <= 6; i++) {
				if (player_lost[i] > order && (!teams[winner] || !teams[i] || icmp(teams[winner], teams[i]) != 0) && (!teams[second] || !teams[i]
						|| icmp(teams[second], teams[i]) != 0)) {
					order = player_lost[i];
					third = i;
				}
			}
			if (order)
				add_points(third, 1);
			for (i = 0; i < 6; i++) {
				if (teams[i]) {
					for (j = 0; j < i; j++) {
						if (teams[j] && icmp(teams[i], teams[j]) == 0) {
							break;
						}
					}
					if (j < i) {
						continue;
					}
				}
				if (player_socks[i] >= 0) {
					add_game(i);
				}
			}
		}
		sort_winlist();
		write_config();
		send_to_all!"winlist %s"(winlist_str());
	}
	/* One more possibility: the only player playing left the game, which
     * means there are now no players left. */
	if (!players[0] && !players[1] && !players[2] && !players[3] && !players[4] && !players[5])
		playing_game = 0;
}

/*************************************************************************/
/*************************************************************************/
/* Parse a line from a client.  Destroys the buffer it's given as a side
 * effect.  Return 0 if the command is unknown (or bad syntax), else 1.
 */

int server_parse(long player, string buf) {
	import std.algorithm.iteration : joiner, splitter;
	import std.algorithm.searching : findSplit;
	import std.array : array;
	import std.conv : parse;
	import std.string : fromStringz;
	import std.uni : icmp;
	import std.utf : byCodeUnit;
	string s, t;
	int i, tetrifast = 0;
	auto splitOne = buf.findSplit(" ");
	string cmd = splitOne[0];
	bool parseJoin() {
		auto splitTwo = splitOne[2].findSplit(" ");
		s = splitTwo[0];
		if (!s) {
			return false;
		}
		t = splitTwo[2];
		foreach (playing; players) {
			if (playing && icmp(s, playing) == 0) {
				send_to!"noconnecting Nickname already exists on server!"(player);
				return false;
			}
		}
		players[player] = s;
		teams[player] = null;
		player_modes[player] = tetrifast;
		send_to!"%s %d"(player, tetrifast ? ")#)(!@(*3".ptr : "playernum".ptr, player);
		send_to!"winlist %s",(player, winlist_str());
		foreach (i, playing; players) {
			if (i != player && playing) {
				send_to!"playerjoin %d %s"(player, i, playing);
				send_to!"team %d %s"(player, i, teams[i] ? teams[i] : "");
			}
		}
		if (playing_game) {
			send_to!"ingame"(player);
			player_lost[player] = 1;
		}
		send_to_all_but!"playerjoin %d %s"(player, player, players[player]);
		return true;
	}
	if (cmd == "") {
		return 1;
	} else if (cmd == "tetrisstart") {
		if (!parseJoin()) {
			return 0;
		}
	} else if (cmd == "tetrifaster") {
		tetrifast = 1;
		if (!parseJoin()) {
			return 0;
		}
	} else if (cmd == "team") {
		auto splitTwo = splitOne[2].findSplit(" ");
		s = splitTwo[0];
		if (!splitOne || parse!int(s) != player) {
			return 0;
		}
		if (splitTwo) {
			teams[player] = splitTwo[2];
		} else {
			teams[player] = "";
		}
		send_to_all_but!"team %d %s"(player, player, t ? t : "");

	} else if (cmd == "pline") {
		auto splitTwo = splitOne[2].findSplit(" ");
		s = splitTwo[0];
		if (!s || parse!int(s) != player) {
			return 0;
		}
		t = splitTwo[2];
		send_to_all_but!"pline %d %s"(player, player, t);

	} else if (cmd == "plineact") {
		auto splitTwo = splitOne[2].findSplit(" ");
		s = splitTwo[0];
		if (!s || parse!int(s) != player) {
			return 0;
		}
		t = splitTwo[2];
		send_to_all_but!"plineact %d %s"(player, player, t);

	} else if (cmd == "startgame") {
		int total;
		char[101] piecebuf, specialbuf;

		for (i = 1; i < player; i++) {
			if (player_socks[i] >= 0) {
				return 1;
			}
		}
		auto splitTwo = splitOne[2].findSplit(" ");
		s = splitTwo[0];
		t = splitTwo[2];
		if (!s) {
			return 1;
		}
		i = parse!int(s);
		if ((i && playing_game) || (!i && !playing_game)) {
			return 1;
		}
		if (!i) { /* end game */
			send_to_all!"endgame"();
			playing_game = 0;
			return 1;
		}
		total = 0;
		for (i = 0; i < 7; i++) {
			if (piecefreq[i]) {
				piecebuf[total..piecefreq[i]] = cast(char)('1'+i);
				//memset(piecebuf.ptr + total, '1' + i, piecefreq[i]);
			}
			total += piecefreq[i];
		}
		piecebuf[100] = 0;
		if (total != 100) {
			send_to_all!"plineact 0 cannot start game: Piece frequencies do not total 100 percent!"();
			return 1;
		}
		total = 0;
		for (i = 0; i < 9; i++) {
			if (specialfreq[i]) {
				specialbuf[total..specialfreq[i]] = cast(char)('1'+i);
				//memset(specialbuf.ptr + total, '1' + i, specialfreq[i]);
			}
			total += specialfreq[i];
		}
		specialbuf[100] = 0;
		if (total != 100) {
			send_to_all!"plineact 0 cannot start game: Special frequencies do not total 100 percent!"();
			return 1;
		}
		playing_game = 1;
		game_paused = 0;
		for (i = 1; i <= 6; i++) {
			if (player_socks[i] < 0) {
				continue;
			}
			/* XXX First parameter is stack height */
			send_to!"%s %d %d %d %d %d %d %d %s %s %d %d"(i, player_modes[i] ? "*******".ptr : "newgame".ptr, 0, initial_level, lines_per_level, level_inc, special_lines, special_count,
				special_capacity, piecebuf.ptr, specialbuf.ptr, level_average, old_mode);
		}
		player_lost[] = 0;
		//memset(player_lost.ptr, 0, player_lost.sizeof);

	} else if (cmd == "pause") {
		if (!playing_game) {
			return 1;
		}
		auto splitTwo = splitOne[2].findSplit(" ");
		s = splitTwo[0];
		if (!s) {
			return 1;
		}
		i = parse!int(s);
		if (i) {
			i = 1; /* to make sure it's not anything else */
		}
		if ((i && game_paused) || (!i && !game_paused)) {
			return 1;
		}
		game_paused = i;
		send_to_all!"pause %d"(i);

	} else if (cmd == "playerlost") {
		auto splitTwo = splitOne[2].findSplit(" ");
		s = splitTwo[0];
		if (!s || parse!int(s) != player) {
			return 1;
		}
		player_loses(player);

	} else if (cmd == "f") { /* field */
		auto splitTwo = splitOne[2].findSplit(" ");
		s = splitTwo[0];
		if (!s || parse!int(s) != player) {
			return 1;
		}
		auto splitThree = splitTwo[2].findSplit(" ");
		s = splitThree[0];
		send_to_all_but!"f %d %s"(player, player, s);

	} else if (cmd == "lvl") {
		auto splitTwo = splitOne[2].findSplit(" ");
		s = splitTwo[0];
		if (!s || parse!int(s) != player) {
			return 1;
		}
		auto splitThree = splitTwo[2].findSplit(" ");
		s = splitThree[0];
		if (!s) {
			return 1;
		}
		levels[player] = parse!int(s);
		send_to_all_but!"lvl %d %d"(player, player, levels[player]);

	} else if (cmd == "sb") {
		int from, to;
		string type;

		auto splitTwo = splitOne[2].findSplit(" ");
		s = splitTwo[0];
		if (!s) {
			return 1;
		}
		to = parse!int(s);
		auto splitThree = splitTwo[2].findSplit(" ");
		type = splitThree[0];
		if (!type) {
			return 1;
		}
		auto splitFour = splitThree[2].findSplit(" ");
		s = splitFour[0];
		if (!s) {
			return 1;
		}
		from = parse!int(s);
		if (from != player) {
			return 1;
		}
		if (to < 0 || to > 6 || player_socks[to] < 0 || player_lost[to]) {
			return 1;
		}
		if (to == 0) {
			send_to_all_but_team!"sb %d %s %d"(player, to, type, from);
		} else {
			send_to_all_but!"sb %d %s %d"(player, to, type, from);
		}

	} else if (cmd == "gmsg") {
		if (!splitOne) {
			return 1;
		}
		s = splitOne[2];
		send_to_all!"gmsg %s"(s);

	} else { /* unrecognized command */
		return 0;

	}

	return 1;
}

int serverMain() {
	import vibe.core.net;
	import vibe.core.stream;
	import vibe.core.core;
	import vibe.stream.operations;
	import std.experimental.logger : info, trace, tracef;
	import std.algorithm : countUntil;

	/* (Try to) read the config file */
	read_config();

	runTask({
		auto listener = listenTCP(31457, (TCPConnection conn) {
			auto playerCount = players_connected[].countUntil(false);
			tracef("Player %d attempting connection", playerCount);
			if (playerCount == -1) {
				conn.write("noconnecting Too many players on server!");
				return;
			} else {
				tracef("Player %d connected", playerCount);
				players_connected[playerCount] = true;
				player_connections[playerCount] = conn;
			}
			scope(exit) {
				tracef("Player %d disconnected", playerCount);
				players_connected[playerCount] = false;
				player_connections[playerCount] = null;
			}
			while (true) {
				auto str = cast(string)conn.readLine();
				tracef("Player %s: %s", playerCount, str);
				try {
					server_parse(playerCount, str);
				} catch (Exception e) {
					info("Error: ", e);
				}
			}
		});
		write_config();
	});

	return runApplication();
}

deprecated auto assumeNogc(alias Func, T...)(T xs) @nogc {
	import std.traits;

	static auto assumeNogcPtr(T)(T f) if (isFunctionPointer!T || isDelegate!T) {
		enum attrs = functionAttributes!T | FunctionAttribute.nogc;
		return cast(SetFunctionAttributes!(T, functionLinkage!T, attrs)) f;
	}

	return assumeNogcPtr(&Func)(xs);
}
