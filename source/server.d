module dtetrinet.server;

import dtetrinet.tetrinet;
import dtetrinet.tetris;
import dtetrinet.sockets;

import core.sys.posix.unistd;
import core.sys.posix.signal;
import core.sys.posix.sys.socket;
import core.sys.posix.netinet.in_;
import core.sys.posix.sys.select;

import core.stdc.errno;
import core.stdc.signal;
import core.stdc.stdio;
import core.stdc.stdlib;
import core.stdc.stdarg;
import core.stdc.string;
import core.stdc.ctype;

extern (C) int strcasecmp(const char* s1, const char* s2) @nogc nothrow;

__gshared int linuxmode;
__gshared int ipv6_only;

__gshared int quit;
__gshared int listen_sock;
__gshared int listen_sock6;
__gshared int[6] player_socks = [-1, -1, -1, -1, -1, -1];
__gshared char[6][4] player_ips;
__gshared int[6] player_lost;
__gshared int[6] player_modes;

/*************************************************************************/
/*************************************************************************/

/* Convert a 2-byte hex value to an integer. */

int xtoi(const char* buf) {
	int val;

	if (buf[0] <= '9') {
		val = (buf[0] - '0') << 4;
	} else {
		val = (toupper(buf[0]) - 'A' + 10) << 4;
	}
	if (buf[1] <= '9') {
		val |= buf[1] - '0';
	} else {
		val |= toupper(buf[1]) - 'A' + 10;
	}
	return val;
}

/*************************************************************************/

/* Return a string containing the winlist in a format suitable for sending
 * to clients.
 */

string winlist_str() nothrow {
	static char[1024] buf;
	ulong s;
	int i;

	for (i = 0; i < MAXWINLIST && winlist[i].name.ptr != null; i++) {
		s += snprintf(s, buf.sizeof - (s - buf.ptr), linuxmode ? " %c%s;%d;%d" : " %c%s;%d", winlist[i].team ? 't' : 'p', winlist[i].name.ptr, winlist[i].points, winlist[i].games);
	}
	return buf[0 .. s].idup;
}

/*************************************************************************/
/*************************************************************************/

/* Read the configuration file. */

void read_config() @nogc nothrow {
	char[1024] buf;
	char* s, t;
	FILE* f;
	int i;

	s = getenv("HOME");
	if (!s) {
		s = cast(char*) "/etc".ptr;
	}
	snprintf(buf.ptr, buf.sizeof, "%s/.tetrinet", s);
	f = fopen(buf.ptr, "r");
	if (!f) {
		return;
	}
	while (fgets(buf.ptr, buf.sizeof, f)) {
		s = strtok(buf.ptr, " ");
		if (!s) {
			continue;
		} else if (strcmp(s, "linuxmode") == 0) {
			s = strtok(null, " ");
			if (s) {
				linuxmode = atoi(s);
			}
		} else if (strcmp(s, "ipv6_only") == 0) {
			s = strtok(null, " ");
			if (s) {
				ipv6_only = atoi(s);
			}
		} else if (strcmp(s, "averagelevels") == 0) {
			s = strtok(null, " ");
			if (s) {
				level_average = atoi(s);
			}
		} else if (strcmp(s, "classic") == 0) {
			s = strtok(null, " ");
			if (s) {
				old_mode = atoi(s);
			}
		} else if (strcmp(s, "initiallevel") == 0) {
			s = strtok(null, " ");
			if (s) {
				initial_level = atoi(s);
			}
		} else if (strcmp(s, "levelinc") == 0) {
			s = strtok(null, " ");
			if (s) {
				level_inc = atoi(s);
			}
		} else if (strcmp(s, "linesperlevel") == 0) {
			s = strtok(null, " ");
			if (s) {
				lines_per_level = atoi(s);
			}
		} else if (strcmp(s, "pieces") == 0) {
			i = 0;
			s = strtok(null, " ");
			while (i < 7 && s) {
				piecefreq[i++] = atoi(s);
				s = strtok(null, " ");
			}
		} else if (strcmp(s, "specialcapacity") == 0) {
			s = strtok(null, " ");
			if (s) {
				special_capacity = atoi(s);
			}
		} else if (strcmp(s, "specialcount") == 0) {
			s = strtok(null, " ");
			if (s) {
				special_count = atoi(s);
			}
		} else if (strcmp(s, "speciallines") == 0) {
			s = strtok(null, " ");
			if (s) {
				special_lines = atoi(s);
			}
		} else if (strcmp(s, "specials") == 0) {
			i = 0;
			s = strtok(null, " ");
			while (i < 9 && s) {
				specialfreq[i++] = atoi(s);
				s = strtok(null, " ");
			}
		} else if (strcmp(s, "winlist") == 0) {
			i = 0;
			s = strtok(null, " ");
			while (i < MAXWINLIST && s) {
				t = strchr(s, ';');
				if (!t)
					break;
				*t++ = 0;
				strncpy(winlist[i].name.ptr, s, winlist[i].name.sizeof - 1);
				winlist[i].name[winlist[i].name.sizeof - 1] = 0;
				s = t;
				t = strchr(s, ';');
				if (!t) {
					winlist[i].name = winlist[i].name.init;
					break;
				}
				winlist[i].team = atoi(s);
				s = t + 1;
				t = strchr(s, ';');
				if (!t) {
					winlist[i].name = winlist[i].name.init;
					break;
				}
				winlist[i].points = atoi(s);
				winlist[i].games = atoi(t + 1);
				i++;
				s = strtok(null, " ");
			}
		}
	}
	fclose(f);
}

/*************************************************************************/

/*************************************************************************/

/* Re-write the configuration file. */

void write_config() @nogc nothrow {
	char[1024] buf;
	char* s;
	FILE* f;
	int i;

	s = getenv("HOME");
	if (!s) {
		s = cast(char*) "/etc".ptr;
	}
	snprintf(buf.ptr, buf.sizeof, "%s/.tetrinet", s);
	f = fopen(buf.ptr, "w");
	if (!f) {
		return;
	}

	fprintf(f, "winlist");
	for (i = 0; i < MAXSAVEWINLIST && winlist[i].name != winlist[i].name.init; i++) {
		fprintf(f, " %s;%d;%d;%d", winlist[i].name.ptr, winlist[i].team, winlist[i].points, winlist[i].games);
	}
	fputc('\n', f);

	fprintf(f, "classic %d\n", old_mode);

	fprintf(f, "initiallevel %d\n", initial_level);
	fprintf(f, "linesperlevel %d\n", lines_per_level);
	fprintf(f, "levelinc %d\n", level_inc);
	fprintf(f, "averagelevels %d\n", level_average);

	fprintf(f, "speciallines %d\n", special_lines);
	fprintf(f, "specialcount %d\n", special_count);
	fprintf(f, "specialcapacity %d\n", special_capacity);

	fprintf(f, "pieces");
	for (i = 0; i < 7; i++) {
		fprintf(f, " %d", piecefreq[i]);
	}
	fputc('\n', f);

	fprintf(f, "specials");
	for (i = 0; i < 9; i++) {
		fprintf(f, " %d", specialfreq[i]);
	}
	fputc('\n', f);

	fprintf(f, "linuxmode %d\n", linuxmode);
	fprintf(f, "ipv6_only %d\n", ipv6_only);

	fclose(f);
}

/*************************************************************************/
/*************************************************************************/

/* Send a message to a single player. */

void send_to(T...)(int player, const char* fmt, T args) nothrow {
	import std.exception : assumeWontThrow;
	import std.format : format;
	import std.conv : to;

	if (player_socks[player - 1] >= 0) {
		sockprintf(player_socks[player - 1], "%s", assumeWontThrow(format(fmt.to!string, args)).ptr);
	}
}

/*************************************************************************/

/* Send a message to all players. */

void send_to_all(string fmt, T...)(T args) nothrow {
	import std.exception : assumeWontThrow;
	import std.format : sformat;
	import std.conv : to;

	int i;

	for (i = 0; i < 6; i++) {
		if (player_socks[i] >= 0) {
			sockprintf(player_socks[i], fmt, args);
		}
	}
}

/*************************************************************************/

/* Send a message to all players but the given one. */

void send_to_all_but(T...)(int player, const char* fmt, T args) nothrow {
	import std.exception : assumeWontThrow;
	import std.format : format;
	import std.conv : to;

	int i;

	for (i = 0; i < 6; i++) {
		if (i + 1 != player && player_socks[i] >= 0) {
			sockprintf(player_socks[i], "%s", assumeWontThrow(format(fmt.to!string, args)).ptr);
		}
	}
}

/*************************************************************************/

/* Send a message to all players but those on the same team as the given
 * player.
 */

void send_to_all_but_team(int player, const char* format, ...) nothrow {
	va_list args;
	char[1024] buf;
	int i;
	char* team = teams[player - 1];

	va_start(args, format);
	vsnprintf(buf.ptr, buf.sizeof, format, args);
	for (i = 0; i < 6; i++) {
		if (i + 1 != player && player_socks[i] >= 0 && (!team || !teams[i] || strcmp(teams[i], team) != 0)) {
			sockprintf(player_socks[i], "%s", buf.ptr);
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

	if (!players[player - 1]) {
		return;
	}
	for (i = 0; i < MAXWINLIST && winlist[i].name != winlist[i].name.init; i++) {
		if (!winlist[i].team && !teams[player - 1] && strcmp(winlist[i].name.ptr, players[player - 1]) == 0) {
			break;
		}
		if (winlist[i].team && teams[player - 1] && strcmp(winlist[i].name.ptr, teams[player - 1]) == 0) {
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
		if (teams[player - 1]) {
			strncpy(winlist[i].name.ptr, teams[player - 1], winlist[i].name.sizeof - 1);
			winlist[i].name[winlist[i].name.sizeof - 1] = 0;
			winlist[i].team = 1;
		} else {
			strncpy(winlist[i].name.ptr, players[player - 1], winlist[i].name.sizeof - 1);
			winlist[i].name[winlist[i].name.sizeof - 1] = 0;
			winlist[i].team = 0;
		}
	}
	winlist[i].points += points;
}

/*************************************************************************/

/* Add a game to a given player's [team's] winlist entry. */

void add_game(int player) {
	int i;

	if (!players[player - 1])
		return;
	for (i = 0; i < MAXWINLIST && winlist[i].name != winlist[i].name.init; i++) {
		if (!winlist[i].team && !teams[player - 1] && strcmp(winlist[i].name.ptr, players[player - 1]) == 0) {
			break;
		}
		if (winlist[i].team && teams[player - 1] && strcmp(winlist[i].name.ptr, teams[player - 1]) == 0) {
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
			WinInfo tmp;
			memcpy(&tmp, &winlist[i], WinInfo.sizeof);
			memcpy(&winlist[i], &winlist[bestindex], WinInfo.sizeof);
			memcpy(&winlist[bestindex], &tmp, WinInfo.sizeof);
		}
	}
}

/*************************************************************************/

/* Take care of a player losing (which may end the game). */

void player_loses(int player) {
	int i, j, order, end = 1, winner = -1, second = -1, third = -1;

	if (player < 1 || player > 6 || player_socks[player - 1] < 0) {
		return;
	}
	order = 0;
	for (i = 1; i <= 6; i++) {
		if (player_lost[i - 1] > order) {
			order = player_lost[i - 1];
		}
	}
	player_lost[player - 1] = order + 1;
	for (i = 1; i <= 6; i++) {
		if (player_socks[i - 1] >= 0 && !player_lost[i - 1]) {
			if (winner < 0) {
				winner = i;
			} else if (!teams[winner - 1] || !teams[i - 1] || strcasecmp(teams[winner - 1], teams[i - 1]) != 0) {
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
				if (player_lost[i - 1] > order && (!teams[winner - 1] || !teams[i - 1] || strcasecmp(teams[winner - 1], teams[i - 1]) != 0)) {
					order = player_lost[i - 1];
					second = i;
				}
			}
			if (order) {
				add_points(second, 2);
				player_lost[second - 1] = 0;
			}
			order = 0;
			for (i = 1; i <= 6; i++) {
				if (player_lost[i - 1] > order && (!teams[winner - 1] || !teams[i - 1] || strcasecmp(teams[winner - 1], teams[i - 1]) != 0) && (!teams[second - 1] || !teams[i - 1]
						|| strcasecmp(teams[second - 1], teams[i - 1]) != 0)) {
					order = player_lost[i - 1];
					third = i;
				}
			}
			if (order)
				add_points(third, 1);
			for (i = 1; i <= 6; i++) {
				if (teams[i - 1]) {
					for (j = 1; j < i; j++) {
						if (teams[j - 1] && strcasecmp(teams[i - 1], teams[j - 1]) == 0) {
							break;
						}
					}
					if (j < i) {
						continue;
					}
				}
				if (player_socks[i - 1] >= 0) {
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

int server_parse(int player, char* buf) {
	char* cmd, s, t;
	int i, tetrifast = 0;

	cmd = strtok(buf, " ");

	if (!cmd) {
		return 1;
	} else if (strcmp(cmd, "tetrisstart") == 0) {
	newplayer:
		s = strtok(null, " ");
		t = strtok(null, " ");
		if (!t) {
			return 0;
		}
		for (i = 1; i <= 6; i++) {
			if (players[i - 1] && strcasecmp(s, players[i - 1]) == 0) {
				send_to(player, "noconnecting Nickname already exists on server!");
				return 0;
			}
		}
		players[player - 1] = strdup(s);
		if (teams[player - 1]) {
			free(teams[player - 1]);
		}
		teams[player - 1] = null;
		player_modes[player - 1] = tetrifast;
		send_to(player, "%s %d".ptr, tetrifast ? ")#)(!@(*3".ptr : "playernum".ptr, player);
		send_to(player, "winlist %s", winlist_str());
		for (i = 1; i <= 6; i++) {
			if (i != player && players[i - 1]) {
				send_to(player, "playerjoin %d %s", i, players[i - 1]);
				send_to(player, "team %d %s", i, teams[i - 1] ? teams[i - 1] : "");
			}
		}
		if (playing_game) {
			send_to(player, "ingame");
			player_lost[player - 1] = 1;
		}
		send_to_all_but(player, "playerjoin %d %s", player, players[player - 1]);

	} else if (strcmp(cmd, "tetrifaster") == 0) {
		tetrifast = 1;
		goto newplayer;

	} else if (strcmp(cmd, "team") == 0) {
		s = strtok(null, " ");
		t = strtok(null, "");
		if (!s || atoi(s) != player) {
			return 0;
		}
		if (teams[player]) {
			free(teams[player]);
		}
		if (t) {
			teams[player] = strdup(t);
		} else {
			teams[player] = null;
		}
		send_to_all_but(player, "team %d %s", player, t ? t : "");

	} else if (strcmp(cmd, "pline") == 0) {
		s = strtok(null, " ");
		t = strtok(null, "");
		if (!s || atoi(s) != player) {
			return 0;
		}
		if (!t) {
			t = cast(char*) "".ptr;
		}
		send_to_all_but(player, "pline %d %s", player, t);

	} else if (strcmp(cmd, "plineact") == 0) {
		s = strtok(null, " ");
		t = strtok(null, "");
		if (!s || atoi(s) != player) {
			return 0;
		}
		if (!t) {
			t = cast(char*) "".ptr;
		}
		send_to_all_but(player, "plineact %d %s", player, t);

	} else if (strcmp(cmd, "startgame") == 0) {
		int total;
		char[101] piecebuf, specialbuf;

		for (i = 1; i < player; i++) {
			if (player_socks[i - 1] >= 0) {
				return 1;
			}
		}
		s = strtok(null, " ");
		t = strtok(null, " ");
		if (!s) {
			return 1;
		}
		i = atoi(s);
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
				memset(piecebuf.ptr + total, '1' + i, piecefreq[i]);
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
				memset(specialbuf.ptr + total, '1' + i, specialfreq[i]);
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
			if (player_socks[i - 1] < 0) {
				continue;
			}
			/* XXX First parameter is stack height */
			send_to(i, "%s %d %d %d %d %d %d %d %s %s %d %d", player_modes[i - 1] ? "*******".ptr : "newgame".ptr, 0, initial_level, lines_per_level, level_inc, special_lines, special_count,
				special_capacity, piecebuf.ptr, specialbuf.ptr, level_average, old_mode);
		}
		memset(player_lost.ptr, 0, player_lost.sizeof);

	} else if (strcmp(cmd, "pause") == 0) {
		if (!playing_game) {
			return 1;
		}
		s = strtok(null, " ");
		if (!s) {
			return 1;
		}
		i = atoi(s);
		if (i) {
			i = 1; /* to make sure it's not anything else */
		}
		if ((i && game_paused) || (!i && !game_paused)) {
			return 1;
		}
		game_paused = i;
		send_to_all!"pause %d"(i);

	} else if (strcmp(cmd, "playerlost") == 0) {
		s = strtok(null, " ");
		if (!s || atoi(s) != player) {
			return 1;
		}
		player_loses(player);

	} else if (strcmp(cmd, "f") == 0) { /* field */
		s = strtok(null, " ");
		if (!s || atoi(s) != player) {
			return 1;
		}
		s = strtok(null, "");
		if (!s) {
			s = cast(char*) "".ptr;
		}
		send_to_all_but(player, "f %d %s", player, s);

	} else if (strcmp(cmd, "lvl") == 0) {
		s = strtok(null, " ");
		if (!s || atoi(s) != player) {
			return 1;
		}
		s = strtok(null, " ");
		if (!s) {
			return 1;
		}
		levels[player] = atoi(s);
		send_to_all_but(player, "lvl %d %d", player, levels[player]);

	} else if (strcmp(cmd, "sb") == 0) {
		int from, to;
		char* type;

		s = strtok(null, " ");
		if (!s) {
			return 1;
		}
		to = atoi(s);
		type = strtok(null, " ");
		if (!type) {
			return 1;
		}
		s = strtok(null, " ");
		if (!s) {
			return 1;
		}
		from = atoi(s);
		if (from != player) {
			return 1;
		}
		if (to < 0 || to > 6 || player_socks[to - 1] < 0 || player_lost[to - 1]) {
			return 1;
		}
		if (to == 0) {
			send_to_all_but_team(player, "sb %d %s %d", to, type, from);
		} else {
			send_to_all_but(player, "sb %d %s %d", to, type, from);
		}

	} else if (strcmp(cmd, "gmsg") == 0) {
		s = strtok(null, "");
		if (!s) {
			return 1;
		}
		send_to_all!"gmsg %s"(s);

	} else { /* unrecognized command */
		return 0;

	}

	return 1;
}

/*************************************************************************/
/*************************************************************************/

void check_sockets() {
	fd_set fds;
	int i, fd, maxfd;

	FD_ZERO(&fds);
	if (listen_sock >= 0) {
		FD_SET(listen_sock, &fds);
	}
	maxfd = listen_sock;
	version (HAVE_IPV6) {
		if (listen_sock6 >= 0) {
			FD_SET(listen_sock6, &fds);
		}
		if (listen_sock6 > maxfd) {
			maxfd = listen_sock6;
		}
	}
	for (i = 0; i < 6; i++) {
		if (player_socks[i] != -1) {
			if (player_socks[i] < 0) {
				fd = (~player_socks[i]) - 1;
			} else {
				fd = player_socks[i];
			}
			FD_SET(fd, &fds);
			if (fd > maxfd) {
				maxfd = fd;
			}
		}
	}

	if (select(maxfd + 1, &fds, null, null, null) <= 0)
		return;

	if (listen_sock >= 0 && FD_ISSET(listen_sock, &fds)) {
		sockaddr_in sin;
		uint len = sin.sizeof;
		fd = accept(listen_sock, cast(sockaddr*)&sin, &len);
		if (fd >= 0) {
			for (i = 0; i < 6 && player_socks[i] != -1; i++) {

			}
			if (i == 6) {
				sockprintf(fd, "noconnecting Too many players on server!");
				close(fd);
			} else {
				player_socks[i] = ~(fd + 1);
				memcpy(player_ips[i].ptr, &sin.sin_addr, 4);
			}
		}
	}

	version (HAVE_IPV6) {
		if (listen_sock6 >= 0 && FD_ISSET(listen_sock6, &fds)) {
			sockaddr_in6 sin6;
			uint len = sin6.sizeof;
			fd = accept(listen_sock6, cast(sockaddr*)&sin6, &len);
			if (fd >= 0) {
				for (i = 0; i < 6 && player_socks[i] != -1; i++) {

				}
				if (i == 6) {
					sockprintf(fd, "noconnecting Too many players on server!");
					close(fd);
				} else {
					player_socks[i] = ~(fd + 1);
					memcpy(player_ips[i].ptr, cast(char*)(&sin6.sin6_addr) + 12, 4);
				}
			}
		}
	}

	for (i = 0; i < 6; i++) {
		char[1024] buf;

		if (player_socks[i] == -1) {
			continue;
		}
		if (player_socks[i] < 0) {
			fd = (~player_socks[i]) - 1;
		} else {
			fd = player_socks[i];
		}
		if (!FD_ISSET(fd, &fds)) {
			continue;
		}
		sgets(buf.ptr, buf.sizeof, fd);
		if (player_socks[i] < 0) {
			/* Messy decoding stuff */
			char[16] iphashbuf;
			char[1024] newbuf;
			ubyte* ip;
			int j, c, d;

			if (strlen(buf.ptr) < 2 * 13) { /* "tetrisstart " + initial byte */
				close(fd);
				player_socks[i] = -1;
				continue;
			}
			ip = cast(ubyte*) player_ips[i].ptr;
			sprintf(iphashbuf.ptr, "%d", ip[0] * 54 + ip[1] * 41 + ip[2] * 29 + ip[3] * 17);
			c = xtoi(buf.ptr);
			for (j = 2; buf[j] && buf[j + 1]; j += 2) {
				int temp;
				temp = d = xtoi(buf.ptr + j);
				d ^= iphashbuf[((j / 2) - 1) % strlen(iphashbuf.ptr)];
				d += 255 - c;
				d %= 255;
				newbuf[j / 2 - 1] = cast(char) d;
				c = temp;
			}
			newbuf[j / 2 - 1] = 0;
			if (strncmp(newbuf.ptr, "tetrisstart ", 12) != 0) {
				close(fd);
				player_socks[i] = -1;
				continue;
			}
			/* Buffers should be the same size, but let's be paranoid */
			strncpy(buf.ptr, newbuf.ptr, buf.sizeof);
			buf[buf.sizeof - 1] = 0;
			player_socks[i] = fd; /* Has now registered */
		} /* if client not registered */
		if (!server_parse(i + 1, buf.ptr)) {
			close(fd);
			player_socks[i] = -1;
			if (players[i]) {
				send_to_all!"playerleave %d"(i + 1);
				if (playing_game) {
					player_loses(i + 1);
				}
				free(players[i]);
				players[i] = null;
				if (teams[i]) {
					free(teams[i]);
					teams[i] = null;
				}
			}
		}
	} /* for each player socket */
}

/* Returns 0 on success, desired program exit code on failure */

int s_init() @nogc {
	sockaddr_in sin;
	version (HAVE_IPV6) {
		sockaddr_in6 sin6;
	}
	int i;

	/* Set up some sensible defaults */
	//winlist[0].name = null;
	old_mode = 1;
	initial_level = 1;
	lines_per_level = 2;
	level_inc = 1;
	level_average = 1;
	special_lines = 1;
	special_count = 1;
	special_capacity = 18;
	piecefreq[0] = 14;
	piecefreq[1] = 14;
	piecefreq[2] = 15;
	piecefreq[3] = 14;
	piecefreq[4] = 14;
	piecefreq[5] = 14;
	piecefreq[6] = 15;
	specialfreq[0] = 18;
	specialfreq[1] = 18;
	specialfreq[2] = 3;
	specialfreq[3] = 12;
	specialfreq[4] = 0;
	specialfreq[5] = 16;
	specialfreq[6] = 3;
	specialfreq[7] = 12;
	specialfreq[8] = 18;

	/* (Try to) read the config file */
	read_config();

	/* Catch some signals */
	signal(SIGHUP, &sigcatcher);
	signal(SIGINT, &sigcatcher);
	signal(SIGTERM, &sigcatcher);

	/* Set up a listen socket */
	if (!ipv6_only) {
		listen_sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
	}
	if (listen_sock >= 0) {
		i = 1;
		if (setsockopt(listen_sock, SOL_SOCKET, SO_REUSEADDR, &i, i.sizeof) == 0) {
			memset(&sin, 0, sin.sizeof);
			sin.sin_family = AF_INET;
			sin.sin_port = htons(31457);
			if (bind(listen_sock, cast(sockaddr*)&sin, sin.sizeof) == 0) {
				if (listen(listen_sock, 5) == 0) {
					goto ipv4_success;
				}
			}
		}
		i = errno;
		close(listen_sock);
		errno = i;
		listen_sock = -1;
	}
ipv4_success:

	version (HAVE_IPV6) {
		/* Set up an IPv6 listen socket if possible */
		listen_sock6 = socket(AF_INET6, SOCK_STREAM, IPPROTO_TCP);
		if (listen_sock6 >= 0) {
			i = 1;
			if (setsockopt(listen_sock6, SOL_SOCKET, SO_REUSEADDR, &i, i.sizeof) == 0) {
				memset(&sin6, 0, sin6.sizeof);
				sin6.sin6_family = AF_INET6;
				sin6.sin6_port = htons(31457);
				if (bind(listen_sock6, cast(sockaddr*)&sin6, sin6.sizeof) == 0) {
					if (listen(listen_sock6, 5) == 0) {
						goto ipv6_success;
					}
				}
			}
			i = errno;
			close(listen_sock6);
			errno = i;
			listen_sock6 = -1;
		}
	ipv6_success:
	} else {
		if (ipv6_only) {
			fprintf(stderr, "ipv6_only specified but IPv6 support not available\n");
			return 1;
		}
	}

	version (HAVE_IPV6) {
		bool cond = (listen_sock < 0) && (listen_sock6 < 0);
	} else {
		bool cond = listen_sock < 0;
	}
	if (cond) {
		return 1;
	}

	return 0;
}

int serverMain() {
	int i;

	if ((i = s_init()) != 0) {
		return i;
	}
	while (!quit) {
		check_sockets();
	}
	write_config();
	if (listen_sock >= 0) {
		close(listen_sock);
	}
	version (HAVE_IPV6) {
		if (listen_sock6 >= 0) {
			close(listen_sock6);
		}
	}
	for (i = 0; i < 6; i++) {
		close(player_socks[i]);
	}
	return 0;
}

void assumeNogc(alias Func, T...)(T xs) @nogc {
	import std.traits;

	static auto assumeNogcPtr(T)(T f) if (isFunctionPointer!T || isDelegate!T) {
		enum attrs = functionAttributes!T | FunctionAttribute.nogc;
		return cast(SetFunctionAttributes!(T, functionLinkage!T, attrs)) f;
	}

	assumeNogcPtr(&Func)(xs);
}

extern (C) void sigcatcher(int sig) nothrow @nogc @system {
	if (sig == SIGHUP) {
		assumeNogc!read_config();
		signal(SIGHUP, &sigcatcher);
		assumeNogc!(send_to_all!("winlist %s", char*))(winlist_str());
	} else if (sig == SIGTERM || sig == SIGINT) {
		quit = 1;
		signal(sig, SIG_IGN);
	}
}
