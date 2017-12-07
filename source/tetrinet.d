module dtetrinet.tetrinet;

import core.stdc.errno;
import core.stdc.stdio;
import core.stdc.stdlib;
import core.stdc.string;
import core.stdc.time;

import dtetrinet.version_;
import dtetrinet.io;
import dtetrinet.sockets;
import dtetrinet.tetris;

import std.stdio;
import std.array : array;
import std.string : toStringz;
import std.algorithm : map;


extern (C) int strcasecmp(const char* s1, const char* s2) @nogc nothrow;

enum MAXWINLIST = 64;

enum MAXSAVEWINLIST = 32;

__gshared {
	int fancy;
	int windows_mode;
	int noslide;
	int tetrifast;
	int cast_shadow;

	int my_playernum;
	char* my_nick;
	WinInfo[MAXWINLIST] winlist;
	int server_sock;
	int dispmode;
	char*[6] players;
	char*[6] teams;
	int playing_game;
	int not_playing_game;
	int game_paused;

	Interface_* io;

}

enum FIELD_WIDTH = 12;
enum FIELD_HEIGHT = 22;
alias Field = char[FIELD_HEIGHT][FIELD_WIDTH];

int log; /* Log network traffic to file? */
char* logname; /* Log filename */

struct WinInfo {
	char[32] name;
	int team; /* 0 = individual player, 1 = team */
	int points;
	int games; /* Number of games played */
}

/* Overall display modes */

enum MODE_FIELDS = 0;
enum MODE_PARTYLINE = 1;
enum MODE_WINLIST = 2;
enum MODE_SETTINGS = 3;
enum MODE_CLIENT = 4; /* Client settings */
enum MODE_SERVER = 5; /* Server settings */

/*************************************************************************/

/* Key definitions for input.  We use K_* to avoid conflict with ncurses */

enum K_UP = 0x100;
enum K_DOWN = 0x101;
enum K_LEFT = 0x102;
enum K_RIGHT = 0x103;
enum K_F1 = 0x104;
enum K_F2 = 0x105;
enum K_F3 = 0x106;
enum K_F4 = 0x107;
enum K_F5 = 0x108;
enum K_F6 = 0x109;
enum K_F7 = 0x10A;
enum K_F8 = 0x10B;
enum K_F9 = 0x10C;
enum K_F10 = 0x10D;
enum K_F11 = 0x10E;
enum K_F12 = 0x10F;

/*************************************************************************/

/* Parse a line from the server.  Destroys the buffer it's given as a side
 * effect.
 */

void parse(char* inbuf) {
	char* cmd, s, t;

	cmd = strtok(inbuf, " ");

	if (!cmd) {
		return;

	} else if (strcmp(cmd, "noconnecting") == 0) {
		s = strtok(null, "");
		if (!s) {
			s = cast(char*) "Unknown".ptr;
		}
		/* XXX not to stderr, please! -- we need to stay running w/o server */
		fprintf(stderr, "Server error: %s\n", s);
		exit(1);

	} else if (strcmp(cmd, "winlist") == 0) {
		int i = 0;
		s = strtok(null, " ");
		while (i < MAXWINLIST && s) {
			t = strchr(s, ';');
			if (!t) {
				break;
			}
			*t++ = 0;
			if (*s == 't') {
				winlist[i].team = 1;
			} else {
				winlist[i].team = 0;
			}
			s++;
			strncpy(winlist[i].name.ptr, s, winlist[i].name.sizeof - 1);
			winlist[i].name[winlist[i].name.sizeof - 1] = 0;
			winlist[i].points = atoi(t);
			if ((t = strchr(t, ';')) != null) {
				winlist[i].games = atoi(t + 1);
			}
			i++;
		}
		if (i < MAXWINLIST) {
			winlist[i].name[0] = 0;
		}
		if (dispmode == MODE_WINLIST) {
			io.setup_winlist();
		}

	} else if (strcmp(cmd, tetrifast ? ")#)(!@(*3" : "playernum") == 0) {
		s = strtok(null, " ");
		if (s) {
			my_playernum = atoi(s);
		}
		/* Note: players[my_playernum-1] is set in init() */
		/* But that doesn't work when joining other channel. */
		players[my_playernum - 1] = strdup(my_nick);

	} else if (strcmp(cmd, "playerjoin") == 0) {
		int player;
		char[1024] buf;

		s = strtok(null, " ");
		t = strtok(null, "");
		if (!s || !t) {
			return;
		}
		player = atoi(s) - 1;
		if (player < 0 || player > 5) {
			return;
		}
		players[player] = strdup(t);
		if (teams[player]) {
			free(teams[player]);
			teams[player] = null;
		}
		snprintf(buf.ptr, buf.sizeof, "*** %s is Now Playing", t);
		io.draw_text(BUFFER_PLINE, buf.ptr);
		if (dispmode == MODE_FIELDS) {
			io.setup_fields();
		}

	} else if (strcmp(cmd, "playerleave") == 0) {
		int player;
		char[1024] buf;

		s = strtok(null, " ");
		if (!s) {
			return;
		}
		player = atoi(s) - 1;
		if (player < 0 || player > 5 || !players[player]) {
			return;
		}
		snprintf(buf.ptr, buf.sizeof, "*** %s has Left", players[player]);
		io.draw_text(BUFFER_PLINE, buf.ptr);
		free(players[player]);
		players[player] = null;
		if (dispmode == MODE_FIELDS) {
			io.setup_fields();
		}

	} else if (strcmp(cmd, "team") == 0) {
		int player;
		char[1024] buf;

		s = strtok(null, " ");
		t = strtok(null, "");
		if (!s) {
			return;
		}
		player = atoi(s) - 1;
		if (player < 0 || player > 5 || !players[player]) {
			return;
		}
		if (teams[player]) {
			free(teams[player]);
		}
		if (t) {
			teams[player] = strdup(t);
		} else {
			teams[player] = null;
		}
		if (t) {
			snprintf(buf.ptr, buf.sizeof, "*** %s is Now on Team %s", players[player], t);
		} else {
			snprintf(buf.ptr, buf.sizeof, "*** %s is Now Alone", players[player]);
		}
		io.draw_text(BUFFER_PLINE, buf.ptr);

	} else if (strcmp(cmd, "pline") == 0) {
		int playernum;
		char[1024] buf;
		char* name;

		s = strtok(null, " ");
		t = strtok(null, "");
		if (!s) {
			return;
		}
		if (!t) {
			t = cast(char*) "".ptr;
		}
		playernum = atoi(s) - 1;
		if (playernum == -1) {
			name = cast(char*) "Server".ptr;
		} else {
			if (playernum < 0 || playernum > 5 || !players[playernum]) {
				return;
			}
			name = players[playernum];
		}
		snprintf(buf.ptr, buf.sizeof, "<%s> %s", name, t);
		io.draw_text(BUFFER_PLINE, buf.ptr);

	} else if (strcmp(cmd, "plineact") == 0) {
		int playernum;
		char[1024] buf;
		char* name;

		s = strtok(null, " ");
		t = strtok(null, "");
		if (!s) {
			return;
		}
		if (!t) {
			t = cast(char*) "".ptr;
		}
		playernum = atoi(s) - 1;
		if (playernum == -1) {
			name = cast(char*) "Server".ptr;
		} else {
			if (playernum < 0 || playernum > 5 || !players[playernum]) {
				return;
			}
			name = players[playernum];
		}
		snprintf(buf.ptr, buf.sizeof, "* %s %s", name, t);
		io.draw_text(BUFFER_PLINE, buf.ptr);

	} else if (strcmp(cmd, tetrifast ? "*******" : "newgame") == 0) {
		int i;
		s = strtok(null, " ");
		if (s) {
		}
		/* stack height */
		s = strtok(null, " ");
		if (s) {
			initial_level = atoi(s);
		}
		s = strtok(null, " ");
		if (s) {
			lines_per_level = atoi(s);
		}
		s = strtok(null, " ");
		if (s) {
			level_inc = atoi(s);
		}
		s = strtok(null, " ");
		if (s) {
			special_lines = atoi(s);
		}
		s = strtok(null, " ");
		if (s) {
			special_count = atoi(s);
		}
		s = strtok(null, " ");
		if (s) {
			special_capacity = atoi(s);
			if (special_capacity > MAX_SPECIALS) {
				special_capacity = MAX_SPECIALS;
			}
		}
		s = strtok(null, " ");
		if (s) {
			memset(piecefreq.ptr, 0, piecefreq.sizeof);
			while (*s) {
				i = *s - '1';
				if (i >= 0 && i < 7) {
					piecefreq[i]++;
				}
				s++;
			}
		}
		s = strtok(null, " ");
		if (s) {
			memset(specialfreq.ptr, 0, specialfreq.sizeof);
			while (*s) {
				i = *s - '1';
				if (i >= 0 && i < 9) {
					specialfreq[i]++;
				}
				s++;
			}
		}
		s = strtok(null, " ");
		if (s) {
			level_average = atoi(s);
		}
		s = strtok(null, " ");
		if (s) {
			old_mode = atoi(s);
		}
		lines = 0;
		for (i = 0; i < 6; i++) {
			levels[i] = initial_level;
		}
		memset(&fields[my_playernum - 1], 0, Field.sizeof);
		specials[0] = -1;
		io.clear_text(BUFFER_GMSG);
		io.clear_text(BUFFER_ATTDEF);
		new_game();
		playing_game = 1;
		game_paused = 0;
		io.draw_text(BUFFER_PLINE, "*** The Game Has Started");

	} else if (strcmp(cmd, "ingame") == 0) {
		/* Sent when a player connects in the middle of a game */
		int x, y;
		char[1024] buf;
		char* s2;

		s2 = buf.ptr + sprintf(buf.ptr, "f %d ", my_playernum);
		for (y = 0; y < FIELD_HEIGHT; y++) {
			for (x = 0; x < FIELD_WIDTH; x++) {
				fields[my_playernum - 1][y][x] = cast(char)(rand() % 5 + 1);
				*s2++ = cast(char)('0' + fields[my_playernum - 1][y][x]);
			}
		}
		*s2 = 0;
		sputs(buf.ptr, server_sock);
		playing_game = 0;
		not_playing_game = 1;

	} else if (strcmp(cmd, "pause") == 0) {
		s = strtok(null, " ");
		if (s) {
			game_paused = atoi(s);
		}
		if (game_paused) {
			io.draw_text(BUFFER_PLINE, "*** The Game Has Been Paused");
			io.draw_text(BUFFER_GMSG, "*** The Game Has Been Paused");
		} else {
			io.draw_text(BUFFER_PLINE, "*** The Game Has Been Unpaused");
			io.draw_text(BUFFER_GMSG, "*** The Game Has Been Unpaused");
		}

	} else if (strcmp(cmd, "endgame") == 0) {
		playing_game = 0;
		not_playing_game = 0;
		memset(fields.ptr, 0, fields.sizeof);
		specials[0] = -1;
		io.clear_text(BUFFER_ATTDEF);
		io.draw_text(BUFFER_PLINE, "*** The Game Has Ended");
		if (dispmode == MODE_FIELDS) {
			int i;
			io.draw_own_field();
			for (i = 1; i <= 6; i++) {
				if (i != my_playernum) {
					io.draw_other_field(i);
				}
			}
		}

	} else if (strcmp(cmd, "playerwon") == 0) {
		/* Syntax: playerwon # -- sent when all but one player lose */

	} else if (strcmp(cmd, "playerlost") == 0) {
		/* Syntax: playerlost # -- sent after playerleave on disconnect
	 *     during a game, or when a player loses (sent by the losing
	 *     player and from the server to all other players */

	} else if (strcmp(cmd, "f") == 0) { /* field */
		int player, x, y, tile;

		/* This looks confusing, but what it means is, ignore this message
	 * if a game isn't going on. */
		if (!playing_game && !not_playing_game) {
			return;
		}
		s = strtok(null, " ");
		if (!s) {
			return;
		}
		player = atoi(s);
		player--;
		s = strtok(null, "");
		if (!s) {
			return;
		}
		if (*s >= '0') {
			/* Set field directly */
			char* ptr = cast(char*) fields[player];
			while (*s) {
				if (*s <= '5') {
					*ptr++ = cast(char)((*s++) - '0');
				}
				else
					switch (*s++) {
					case 'a':
						*ptr++ = 6 + SPECIAL_A;
						break;
					case 'b':
						*ptr++ = 6 + SPECIAL_B;
						break;
					case 'c':
						*ptr++ = 6 + SPECIAL_C;
						break;
					case 'g':
						*ptr++ = 6 + SPECIAL_G;
						break;
					case 'n':
						*ptr++ = 6 + SPECIAL_N;
						break;
					case 'o':
						*ptr++ = 6 + SPECIAL_O;
						break;
					case 'q':
						*ptr++ = 6 + SPECIAL_Q;
						break;
					case 'r':
						*ptr++ = 6 + SPECIAL_R;
						break;
					case 's':
						*ptr++ = 6 + SPECIAL_S;
						break;
					default:
						assert(0);
				}
			}
		} else {
			/* Set specific locations on field */
			tile = 0;
			while (*s) {
				if (*s < '0') {
					tile = *s - '!';
				} else {
					x = *s - '3';
					y = (*++s) - '3';
					fields[player][y][x] = cast(char) tile;
				}
				s++;
			}
		}
		if (player == my_playernum - 1) {
			io.draw_own_field();
		} else {
			io.draw_other_field(player + 1);
		}
	} else if (strcmp(cmd, "lvl") == 0) {
		int player;

		s = strtok(null, " ");
		if (!s) {
			return;
		}
		player = atoi(s) - 1;
		s = strtok(null, "");
		if (!s) {
			return;
		}
		levels[player] = atoi(s);

	} else if (strcmp(cmd, "sb") == 0) {
		int from, to;
		char* type;

		s = strtok(null, " ");
		if (!s) {
			return;
		}
		to = atoi(s);
		type = strtok(null, " ");
		if (!type) {
			return;
		}
		s = strtok(null, " ");
		if (!s) {
			return;
		}
		from = atoi(s);
		do_special(type, from, to);

	} else if (strcmp(cmd, "gmsg") == 0) {
		s = strtok(null, "");
		if (!s) {
			return;
		}
		io.draw_text(BUFFER_GMSG, s);

	}
}

/*************************************************************************/
/*************************************************************************/

__gshared char[512] partyline_buffer;
__gshared int partyline_pos;

/*************************************************************************/

/* Add a character to the partyline buffer. */

void partyline_input(int c) {
	if (partyline_pos < partyline_buffer.sizeof - 1) {
		memmove(partyline_buffer.ptr + partyline_pos + 1, partyline_buffer.ptr + partyline_pos, strlen(partyline_buffer.ptr + partyline_pos) + 1);
		partyline_buffer[partyline_pos++] = cast(char) c;
		io.draw_partyline_input(partyline_buffer.ptr, partyline_pos);
	}
}

/*************************************************************************/

/* Delete the current character from the partyline buffer. */

void partyline_delete() {
	if (partyline_buffer[partyline_pos]) {
		memmove(partyline_buffer.ptr + partyline_pos, partyline_buffer.ptr + partyline_pos + 1, strlen(partyline_buffer.ptr + partyline_pos) - 1 + 1);
		io.draw_partyline_input(partyline_buffer.ptr, partyline_pos);
	}
}

/*************************************************************************/

/* Backspace a character from the partyline buffer. */

void partyline_backspace() {
	if (partyline_pos > 0) {
		partyline_pos--;
		partyline_delete();
	}
}

/*************************************************************************/

/* Kill the entire partyline input buffer. */

void partyline_kill() {
	partyline_pos = 0;
	partyline_buffer = partyline_buffer.init;
	io.draw_partyline_input(partyline_buffer.ptr, partyline_pos);
}

/*************************************************************************/

/* Move around the input buffer.  Sign indicates direction; absolute value
 * of 1 means one character, 2 means the whole line.
 */

void partyline_move(int how) {
	if (how == -2) {
		partyline_pos = 0;
		io.draw_partyline_input(partyline_buffer.ptr, partyline_pos);
	} else if (how == -1 && partyline_pos > 0) {
		partyline_pos--;
		io.draw_partyline_input(partyline_buffer.ptr, partyline_pos);
	} else if (how == 1 && partyline_buffer[partyline_pos]) {
		partyline_pos++;
		io.draw_partyline_input(partyline_buffer.ptr, partyline_pos);
	} else if (how == 2) {
		partyline_pos = cast(int) strlen(partyline_buffer.ptr);
		io.draw_partyline_input(partyline_buffer.ptr, partyline_pos);
	}
}

/*************************************************************************/

/* Send the input line to the server. */

void partyline_enter() {
	char[1024] buf;

	if (partyline_buffer.ptr) {
		if (strncasecmp(partyline_buffer.ptr, "/me ", 4) == 0) {
			sockprintf(server_sock, "plineact %d %s", my_playernum, partyline_buffer.ptr + 4);
			snprintf(buf.ptr, buf.sizeof, "* %s %s", players[my_playernum - 1], partyline_buffer.ptr + 4);
			io.draw_text(BUFFER_PLINE, buf.ptr);
		} else if (strcasecmp(partyline_buffer.ptr, "/start") == 0) {
			sockprintf(server_sock, "startgame 1 %d", my_playernum);
		} else if (strcasecmp(partyline_buffer.ptr, "/end") == 0) {
			sockprintf(server_sock, "startgame 0 %d", my_playernum);
		} else if (strcasecmp(partyline_buffer.ptr, "/pause") == 0) {
			sockprintf(server_sock, "pause 1 %d", my_playernum);
		} else if (strcasecmp(partyline_buffer.ptr, "/unpause") == 0) {
			sockprintf(server_sock, "pause 0 %d", my_playernum);
		} else if (strncasecmp(partyline_buffer.ptr, "/team", 5) == 0) {
			if (strlen(partyline_buffer.ptr) == 5) {
				strcpy(partyline_buffer.ptr + 5, " "); /* make it "/team " */
			}
			sockprintf(server_sock, "team %d %s", my_playernum, partyline_buffer.ptr + 6);
			if (partyline_buffer[6]) {
				if (teams[my_playernum - 1]) {
					free(teams[my_playernum - 1]);
				}
				teams[my_playernum - 1] = strdup(partyline_buffer.ptr + 6);
				snprintf(buf.ptr, buf.sizeof, "*** %s is Now on Team %s", players[my_playernum - 1], partyline_buffer.ptr + 6);
				io.draw_text(BUFFER_PLINE, buf.ptr);
			} else {
				if (teams[my_playernum - 1]) {
					free(teams[my_playernum - 1]);
				}
				teams[my_playernum - 1] = null;
				snprintf(buf.ptr, buf.sizeof, "*** %s is Now Alone", players[my_playernum - 1]);
				io.draw_text(BUFFER_PLINE, buf.ptr);
			}
		} else {
			sockprintf(server_sock, "pline %d %s", my_playernum, partyline_buffer.ptr);
			if (partyline_buffer[0] != '/' || partyline_buffer[1] == 0 || partyline_buffer[1] == ' ') {
				/* We do not show server-side commands. */
				snprintf(buf.ptr, buf.sizeof, "<%s> %s", players[my_playernum - 1], partyline_buffer.ptr);
				io.draw_text(BUFFER_PLINE, buf.ptr);
			}
		}
		partyline_pos = 0;
		partyline_buffer = partyline_buffer.init;
		io.draw_partyline_input(partyline_buffer.ptr, partyline_pos);
	}
}

/*************************************************************************/
/*************************************************************************/

void help() {
	import std.stdio;

	stderr.writeln(
		"Tetrinet " ~ VERSION ~ " - Text-mode tetrinet client\n"~
		"\n"~
		"Usage: tetrinet [OPTION]... NICK SERVER\n"~
		"\n"~
		"Options (see README for details):\n"~
		"  -fancy       Use \"fancy\" TTY graphics.\n"~
		"  -fast        Connect to the server in the tetrifast mode.\n"~
		"  -log <file>  Log network traffic to the given file.\n"~
		"  -noshadow    Do not make the pieces cast shadow.\n"~
		"  -noslide     Do not allow pieces to \"slide\" after being dropped\n"~
		"               with the spacebar.\n"~
		"  -server      Start the server instead of the client.\n"~
		"  -shadow      Make the pieces cast shadow. Can speed up gameplay\n"~
		"               considerably, but it can be considered as cheating by\n"~
		"               some people since some other tetrinet clients lack this.\n"~
		"  -slide       Opposite of -noslide; allows pieces to \"slide\" after\n"~
		"               being dropped.  If both -slide and -noslide are given,\n"~
		"               -slide takes precedence.\n"~
		"  -windows     Behave as much like the Windows version of Tetrinet as\n"~
		"               possible. Implies -noslide and -noshadow.\n"
	);
}

int init(int ac, char** av) {
	int i;
	char* nick = null;
	char* server = null;
	char[1024] buf;
	char[1024] nickmsg;
	ubyte[4] ip;
	char[32] iphashbuf;
	int len;
	int slide = 0; /* Do we definitely want to slide? (-slide) */

	version (xwin) {
		/* If there's a DISPLAY variable set in the environment, default to
		 * Xwindows I/O, else default to terminal I/O. */
		if (getenv("DISPLAY")) {
			io = &xwin_interface;
		} else {
			io = &tty_interface;
		}
	} else {
		io = &tty_interface; /* because Xwin isn't done yet */
	}
	srand(cast(uint) time(null));
	init_shapes();

	for (i = 1; i < ac; i++) {
		if (*av[i] == '-') {
			if (strcmp(av[i], "-fancy") == 0) {
				fancy = 1;
			} else if (strcmp(av[i], "-log") == 0) {
				log = 1;
				i++;
				if (i >= ac) {
					fprintf(stderr, "Option -log requires an argument\n");
					return 1;
				}
				logname = av[i];
			} else if (strcmp(av[i], "-noslide") == 0) {
				noslide = 1;
			} else if (strcmp(av[i], "-noshadow") == 0) {
				cast_shadow = 0;
			} else if (strcmp(av[i], "-shadow") == 0) {
				cast_shadow = 1;
			} else if (strcmp(av[i], "-slide") == 0) {
				slide = 1;
			} else if (strcmp(av[i], "-windows") == 0) {
				windows_mode = 1;
				noslide = 1;
				cast_shadow = 0;
			} else if (strcmp(av[i], "-fast") == 0) {
				tetrifast = 1;
			} else {
				fprintf(stderr, "Unknown option %s\n", av[i]);
				help();
				return 1;
			}
		} else if (!nick) {
			my_nick = nick = av[i];
		} else if (!server) {
			server = av[i];
		} else {
			help();
			return 1;
		}
	}
	if (slide) {
		noslide = 0;
	}
	if (!server) {
		help();
		return 1;
	}
	if (strlen(nick) > 63) { /* put a reasonable limit on nick length */
		nick[63] = 0;
	}

	if ((server_sock = conn(server, 31457, cast(char[4]) ip)) < 0) {
		fprintf(stderr, "Couldn't connect to server %s: %s\n", server, strerror(errno));
		return 1;
	}
	sprintf(nickmsg.ptr, "tetri%s %s 1.13", tetrifast ? "faster".ptr : "sstart".ptr, nick);
	sprintf(iphashbuf.ptr, "%d", ip[0] * 54 + ip[1] * 41 + ip[2] * 29 + ip[3] * 17);
	/* buf[0] does not need to be initialized for this algorithm */
	len = cast(int) strlen(nickmsg.ptr);
	for (i = 0; i < len; i++) {
		buf[i + 1] = (((buf[i] & 0xFF) + (nickmsg[i] & 0xFF)) % 255) ^ iphashbuf[i % strlen(iphashbuf.ptr)];
	}
	len++;
	for (i = 0; i < len; i++) {
		sprintf(nickmsg.ptr + i * 2, "%02X", buf[i] & 0xFF);
	}
	sputs(nickmsg.ptr, server_sock);

	do {
		if (!sgets(buf.ptr, buf.sizeof, server_sock)) {
			fprintf(stderr, "Server %s closed connection\n", server);
			disconn(server_sock);
			return 1;
		}
		parse(buf.ptr);
	}
	while (my_playernum < 0);
	sockprintf(server_sock, "team %d ", my_playernum);

	players[my_playernum - 1] = strdup(nick);
	dispmode = MODE_PARTYLINE;
	io.screen_setup();
	io.setup_partyline();

	return 0;
}

int clientMain(string[] args) {
	immutable(char)*[] argptrs = args.map!toStringz.array;

	immutable(char)** av = argptrs.ptr;
	int ac = cast(int) args.length;
	int i;

	if ((i = init(ac, av)) != 0) {
		return i;
	}

	for (;;) {
		int timeout;
		if (playing_game && !game_paused) {
			timeout = tetris_timeout();
		} else {
			timeout = -1;
		}
		i = io.wait_for_input(timeout);
		if (i == -1) {
			char[1024] buf;
			if (sgets(buf.ptr, cast(int) buf.sizeof, server_sock)) {
				parse(buf.ptr);
			} else {
				io.draw_text(BUFFER_PLINE, "*** Disconnected from Server");
				break;
			}
		} else if (i == -2) {
			tetris_timeout_action();
		} else if (i == 12) { /* Ctrl-L */
			io.screen_redraw();
		} else if (i == K_F10) {
			break; /* out of main loop */
		} else if (i == K_F1) {
			if (dispmode != MODE_FIELDS) {
				dispmode = MODE_FIELDS;
				io.setup_fields();
			}
		} else if (i == K_F2) {
			if (dispmode != MODE_PARTYLINE) {
				dispmode = MODE_PARTYLINE;
				io.setup_partyline();
			}
		} else if (i == K_F3) {
			if (dispmode != MODE_WINLIST) {
				dispmode = MODE_WINLIST;
				io.setup_winlist();
			}
		} else if (dispmode == MODE_FIELDS) {
			tetris_input(i);
		} else if (dispmode == MODE_PARTYLINE) {
			if (i == 8 || i == 127) /* Backspace or Delete */ {
				partyline_backspace();
			} else if (i == 4) /* Ctrl-D */ {
				partyline_delete();
			} else if (i == 21) /* Ctrl-U */ {
				partyline_kill();
			} else if (i == '\r' || i == '\n') {
				partyline_enter();
			} else if (i == K_LEFT) {
				partyline_move(-1);
			} else if (i == K_RIGHT) {
				partyline_move(1);
			} else if (i == 1) /* Ctrl-A */ {
				partyline_move(-2);
			} else if (i == 5) /* Ctrl-E */ {
				partyline_move(2);
			} else if (i >= 1 && i <= 0xFF) {
				partyline_input(i);
			}
		}
	}

	disconn(server_sock);
	return 0;
}
