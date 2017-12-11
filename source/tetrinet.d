module dtetrinet.tetrinet;

import core.time;

deprecated import core.stdc.errno : errno;
deprecated import core.stdc.stdio : sprintf, snprintf;
deprecated import core.stdc.stdlib : exit;
deprecated import core.stdc.string : memset, memmove, strlen, strerror, strcpy, strchr;
deprecated import core.stdc.time : time;

import dtetrinet.defs;
import dtetrinet.version_;
import dtetrinet.io;
import dtetrinet.sockets;
import dtetrinet.tetris;

import std.array : array;
import std.string : toStringz;
import std.stdio : stderr, writefln;
import std.algorithm : map;

import vibe.core.net;

enum MAXWINLIST = 64;

enum MAXSAVEWINLIST = 32;

__gshared {
	int fancy;
	int windows_mode;
	int noslide;
	int tetrifast;
	int cast_shadow;

	int my_playernum;
	string my_nick;
	WinInfo[MAXWINLIST] winlist;
	TCPConnection server_sock;
	int dispmode;
	string[6] players;
	string[6] teams;
	int playing_game;
	int not_playing_game;
	int game_paused;

	Interface_* io;

}

enum FIELD_WIDTH = 12;
enum FIELD_HEIGHT = 22;
alias Field = char[FIELD_HEIGHT][FIELD_WIDTH];

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

void parse(string inbuf) {
	import std.algorithm : findSplit, splitter;
	import std.conv : parse;
	import std.format : format;
	import std.random : uniform;
	import std.string : fromStringz, toStringz;
	string cmd, s, t;

	auto splitOne = inbuf.findSplit(" ");
	cmd = splitOne[0];

	if (cmd == "") {
		return;
	} else if (cmd == "noconnecting") {
		if (!splitOne) {
			s = "Unknown";
		} else {
			s = splitOne[2];
		}
		/* XXX not to stderr, please! -- we need to stay running w/o server */
		stderr.writefln!"Server error: %s"(s);
		exit(1);

	} else if (cmd == "winlist") {
		int i = 0;
		auto splitTwo = splitOne[2].findSplit(" ");
		s = splitTwo[0];
		while (i < MAXWINLIST && s) {
			t = strchr(s.toStringz, ';').fromStringz;
			if (!t) {
				break;
			}
			if (s[0] == 't') {
				winlist[i].team = 1;
			} else {
				winlist[i].team = 0;
			}
			//s++;
			winlist[i].name = s;
			winlist[i].points = parse!int(t);
			if ((t = strchr(t.toStringz, ';').fromStringz) != null) {
				auto x = t[1..$];
				winlist[i].games = parse!int(x);
			}
			i++;
		}
		if (i < MAXWINLIST) {
			winlist[i].name[0] = 0;
		}
		if (dispmode == MODE_WINLIST) {
			io.setup_winlist();
		}

	} else if (cmd == (tetrifast ? ")#)(!@(*3" : "playernum")) {
		auto splitTwo = splitOne[2].findSplit(" ");
		s = splitTwo[0];
		if (splitTwo) {
			my_playernum = parse!int(s);
		}
		/* Note: players[my_playernum-1] is set in init() */
		/* But that doesn't work when joining other channel. */
		players[my_playernum] = my_nick;

	} else if (cmd == "playerjoin") {
		int player;
		//char[1024] buf;

		auto splitTwo = splitOne[2].findSplit(" ");
		if (!splitOne || !splitTwo) {
			return;
		}
		s = splitTwo[0];
		t = splitTwo[2];
		player = parse!int(s);
		if (player < 0 || player > 5) {
			return;
		}
		players[player] = t;
		if (teams[player]) {
			teams[player] = null;
		}
		auto buf = format!"*** %s is Now Playing"(t);
		io.draw_text(BUFFER_PLINE, buf);
		if (dispmode == MODE_FIELDS) {
			io.setup_fields();
		}

	} else if (cmd == "playerleave") {
		int player;

		auto splitTwo = splitOne[2].findSplit(" ");
		s = splitTwo[0];
		if (!s) {
			return;
		}
		player = parse!int(s);
		if (player < 0 || player > 5 || !players[player]) {
			return;
		}
		auto buf = format!"*** %s has Left"(players[player]);
		io.draw_text(BUFFER_PLINE, buf);
		players[player] = null;
		if (dispmode == MODE_FIELDS) {
			io.setup_fields();
		}

	} else if (cmd == "team") {
		int player;

		auto splitTwo = splitOne[2].findSplit(" ");
		s = splitTwo[0];
		if (!s) {
			return;
		}
		t = splitTwo[2];
		player = parse!int(s);
		if (player < 0 || player > 5 || !players[player]) {
			return;
		}
		if (t) {
			teams[player] = t;
		} else {
			teams[player] = null;
		}
		string buf;
		if (t) {
			buf = format!"*** %s is Now on Team %s"(players[player], t);
		} else {
			buf = format!"*** %s is Now Alone"(players[player]);
		}
		io.draw_text(BUFFER_PLINE, buf);

	} else if (cmd == "pline") {
		if (!splitOne) {
			return;
		}
		int playernum;
		string name;

		auto splitTwo = splitOne[2].findSplit(" ");
		s = splitTwo[0];
		if (!splitTwo) {
			t = "";
		} else {
			t = splitTwo[2];
		}
		playernum = parse!int(s);
		if (playernum == -1) {
			name = "Server";
		} else {
			if (playernum < 0 || playernum > 5 || !players[playernum]) {
				return;
			}
			name = players[playernum];
		}
		auto buf = format!"<%s> %s"(name, t);
		io.draw_text(BUFFER_PLINE, buf);

	} else if (cmd == "plineact") {
		if (!splitOne) {
			return;
		}
		int playernum;
		//char[1024] buf;
		string name;

		auto splitTwo = splitOne[2].findSplit(" ");
		s = splitTwo[0];
		if (!splitTwo) {
			t = "";
		} else {
			t = splitTwo[2];
		}
		playernum = parse!int(s);
		if (playernum == -1) {
			name = "Server";
		} else {
			if (playernum < 0 || playernum > 5 || !players[playernum]) {
				return;
			}
			name = players[playernum];
		}
		auto buf = format!"* %s %s"(name, t);
		io.draw_text(BUFFER_PLINE, buf);

	} else if (cmd == (tetrifast ? "*******" : "newgame")) {
		int i;
		auto split = splitOne[2].splitter(" ");
		if (split.empty) {
			return;
		}
		s = split.front;
		split.popFront;
		/* stack height */
		if (split.empty) {
			return;
		}
		s = split.front;
		split.popFront;
		initial_level = parse!int(s);
		if (split.empty) {
			return;
		}
		s = split.front;
		split.popFront;
		lines_per_level = parse!int(s);
		if (split.empty) {
			return;
		}
		s = split.front;
		split.popFront;
		level_inc = parse!int(s);
		if (split.empty) {
			return;
		}
		s = split.front;
		split.popFront;
		special_lines = parse!int(s);

		if (split.empty) {
			return;
		}
		s = split.front;
		split.popFront;
		special_count = parse!int(s);
		if (split.empty) {
			return;
		}
		s = split.front;
		split.popFront;
		special_capacity = parse!int(s);
		if (special_capacity > MAX_SPECIALS) {
			special_capacity = MAX_SPECIALS;
		}
		if (split.empty) {
			return;
		}
		s = split.front;
		split.popFront;
		memset(piecefreq.ptr, 0, piecefreq.sizeof);
		foreach (chr; s) {
			i = chr - '1';
			if (i >= 0 && i < 7) {
				piecefreq[i]++;
			}
		}
		if (split.empty) {
			return;
		}
		s = split.front;
		split.popFront;
		memset(specialfreq.ptr, 0, specialfreq.sizeof);
		foreach (chr; s) {
			i = chr - '1';
			if (i >= 0 && i < 9) {
				specialfreq[i]++;
			}
		}
		if (split.empty) {
			return;
		}
		s = split.front;
		split.popFront;
		level_average = parse!int(s);
		if (split.empty) {
			return;
		}
		s = split.front;
		old_mode = parse!int(s);
		lines = 0;
		for (i = 0; i < 6; i++) {
			levels[i] = initial_level;
		}
		memset(&fields[my_playernum], 0, Field.sizeof);
		specials[0] = -1;
		io.clear_text(BUFFER_GMSG);
		io.clear_text(BUFFER_ATTDEF);
		new_game();
		playing_game = 1;
		game_paused = 0;
		io.draw_text(BUFFER_PLINE, "*** The Game Has Started");

	} else if (cmd == "ingame") {
		/* Sent when a player connects in the middle of a game */
		int x, y;
		char[1024] buf;
		string s2;

		s2 ~= (buf.ptr + sprintf(buf.ptr, "f %d ", my_playernum))[0];
		for (y = 0; y < FIELD_HEIGHT; y++) {
			for (x = 0; x < FIELD_WIDTH; x++) {
				fields[my_playernum][y][x] = cast(char)(uniform(0, 5) + 1);
				s2 ~= cast(char)('0' + fields[my_playernum][y][x]);
			}
		}
		server_sock.write(buf[].idup);
		playing_game = 0;
		not_playing_game = 1;

	} else if (cmd == "pause") {
		auto splitTwo = splitOne[2].findSplit(" ");
		s = splitTwo[0];
		if (splitOne) {
			game_paused = parse!int(s);
		}
		if (game_paused) {
			io.draw_text(BUFFER_PLINE, "*** The Game Has Been Paused");
			io.draw_text(BUFFER_GMSG, "*** The Game Has Been Paused");
		} else {
			io.draw_text(BUFFER_PLINE, "*** The Game Has Been Unpaused");
			io.draw_text(BUFFER_GMSG, "*** The Game Has Been Unpaused");
		}

	} else if (cmd == "endgame") {
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

	} else if (cmd == "playerwon") {
		/* Syntax: playerwon # -- sent when all but one player lose */

	} else if (cmd == "playerlost") {
		/* Syntax: playerlost # -- sent after playerleave on disconnect
	 *     during a game, or when a player loses (sent by the losing
	 *     player and from the server to all other players */

	} else if (cmd == "f") { /* field */
		if (!splitOne) {
			return;
		}
		int player, x, y, tile;

		/* This looks confusing, but what it means is, ignore this message
	 * if a game isn't going on. */
		if (!playing_game && !not_playing_game) {
			return;
		}
		auto splitTwo = splitOne[2].findSplit(" ");
		if (!splitTwo) {
			return;
		}
		s = splitTwo[0];
		player = parse!int(s);
		player--;
		s = splitTwo[2];
		if (s[0] >= '0') {
			/* Set field directly */
			foreach (i, chr; s) {
				auto p_x = i/FIELD_WIDTH;
				auto p_y = i%FIELD_WIDTH;
				if (chr <= '5') {
					fields[player][p_y][p_x] = cast(char)(chr - '0');
				}
				else
					switch (chr) {
					case 'a':
						fields[player][p_y][p_x] = 6 + SPECIAL_A;
						break;
					case 'b':
						fields[player][p_y][p_x] = 6 + SPECIAL_B;
						break;
					case 'c':
						fields[player][p_y][p_x] = 6 + SPECIAL_C;
						break;
					case 'g':
						fields[player][p_y][p_x] = 6 + SPECIAL_G;
						break;
					case 'n':
						fields[player][p_y][p_x] = 6 + SPECIAL_N;
						break;
					case 'o':
						fields[player][p_y][p_x] = 6 + SPECIAL_O;
						break;
					case 'q':
						fields[player][p_y][p_x] = 6 + SPECIAL_Q;
						break;
					case 'r':
						fields[player][p_y][p_x] = 6 + SPECIAL_R;
						break;
					case 's':
						fields[player][p_y][p_x] = 6 + SPECIAL_S;
						break;
					default:
						assert(0);
				}
			}
		} else {
			/* Set specific locations on field */
			tile = 0;
			foreach (chr; s) {
				if (chr < '0') {
					tile = chr - '!';
				} else {
					x = chr - '3';
					y = chr - '3';
					fields[player][y][x] = cast(char) tile;
				}
			}
		}
		if (player == my_playernum) {
			io.draw_own_field();
		} else {
			io.draw_other_field(player + 1);
		}
	} else if (cmd == "lvl") {
		if (!splitOne) {
			return;
		}
		int player;

		auto splitTwo = splitOne[2].findSplit(" ");
		if (!splitTwo) {
			return;
		}
		s = splitTwo[0];
		player = parse!int(s);
		s = splitTwo[2];
		levels[player] = parse!int(s);

	} else if (cmd == "sb") {
		if (!splitOne) {
			return;
		}
		int from, to;
		string type;

		auto splitTwo = splitOne[2].findSplit(" ");
		if (!splitTwo) {
			return;
		}
		s = splitTwo[0];
		to = parse!int(s);
		auto splitThree = splitTwo[2].findSplit(" ");
		if (!splitThree) {
			return;
		}
		type = splitThree[0];
		auto splitFour = splitThree[2].findSplit(" ");
		s = splitFour[0];
		from = parse!int(s);
		do_special(type, from, to);

	} else if (cmd == "gmsg") {
		if (!splitOne) {
			return;
		}
		s = splitOne[2];
		io.draw_text(BUFFER_GMSG, s);

	}
}

/*************************************************************************/
/*************************************************************************/

__gshared string partyline_buffer;
__gshared size_t partyline_pos;

/*************************************************************************/

/* Add a character to the partyline buffer. */

void partyline_input(int c) {
	partyline_buffer ~= cast(char) c;
	io.draw_partyline_input(partyline_buffer, partyline_pos);
}

/*************************************************************************/

/* Delete the current character from the partyline buffer. */

void partyline_delete() {
	gmsg_buffer = gmsg_buffer[0..gmsg_pos]~gmsg_buffer[gmsg_pos..$];
	io.draw_partyline_input(partyline_buffer, partyline_pos);
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
	partyline_buffer = null;
	io.draw_partyline_input(partyline_buffer, partyline_pos);
}

/*************************************************************************/

/* Move around the input buffer.  Sign indicates direction; absolute value
 * of 1 means one character, 2 means the whole line.
 */

void partyline_move(int how) {
	if (how == -2) {
		partyline_pos = 0;
		io.draw_partyline_input(partyline_buffer, partyline_pos);
	} else if (how == -1 && partyline_pos > 0) {
		partyline_pos--;
		io.draw_partyline_input(partyline_buffer, partyline_pos);
	} else if (how == 1 && partyline_buffer[partyline_pos]) {
		partyline_pos++;
		io.draw_partyline_input(partyline_buffer, partyline_pos);
	} else if (how == 2) {
		partyline_pos = cast(int) strlen(partyline_buffer.ptr);
		io.draw_partyline_input(partyline_buffer, partyline_pos);
	}
}

/*************************************************************************/

/* Send the input line to the server. */

void partyline_enter() {
	import std.algorithm : startsWith;
	import std.format : format;
	import std.string : icmp;

	if (partyline_buffer.ptr) {
		if (partyline_buffer[].startsWith("/me ")) {
			sockprintf!"plineact %d %s"(server_sock, my_playernum, partyline_buffer.ptr + 4);
			auto str = format!"* %s %s"(players[my_playernum], partyline_buffer[4..$]);
			io.draw_text(BUFFER_PLINE, str);
		} else if (icmp(partyline_buffer, "/start") == 0) {
			sockprintf!"startgame 1 %d"(server_sock, my_playernum);
		} else if (icmp(partyline_buffer, "/end") == 0) {
			sockprintf!"startgame 0 %d"(server_sock, my_playernum);
		} else if (icmp(partyline_buffer, "/pause") == 0) {
			sockprintf!"pause 1 %d"(server_sock, my_playernum);
		} else if (icmp(partyline_buffer, "/unpause") == 0) {
			sockprintf!"pause 0 %d"(server_sock, my_playernum);
		} else if (partyline_buffer[].startsWith("/team")) {
			if (partyline_buffer.length == 5) {
				partyline_buffer ~= " "; /* make it "/team " */
			}
			sockprintf!"team %d %s"(server_sock, my_playernum, partyline_buffer.ptr + 6);
			if (partyline_buffer[6]) {
				teams[my_playernum] = partyline_buffer[6..$].idup;
				auto str = format!"*** %s is Now on Team %s"(players[my_playernum], partyline_buffer[6..$]);
				io.draw_text(BUFFER_PLINE, str);
			} else {
				teams[my_playernum] = null;
				auto str = format!"*** %s is Now Alone"(players[my_playernum]);
				io.draw_text(BUFFER_PLINE, str);
			}
		} else {
			sockprintf!"pline %d %s"(server_sock, my_playernum, partyline_buffer.ptr);
			if (partyline_buffer[0] != '/' || partyline_buffer[1] == 0 || partyline_buffer[1] == ' ') {
				/* We do not show server-side commands. */
				auto str = format!"<%s> %s"(players[my_playernum], partyline_buffer);
				io.draw_text(BUFFER_PLINE, str);
			}
		}
		partyline_pos = 0;
		partyline_buffer = partyline_buffer.init;
		io.draw_partyline_input(partyline_buffer, partyline_pos);
	}
}

/*************************************************************************/
/*************************************************************************/


string genLoginString(string nick, ubyte[4] ip, ubyte rand, string type = "tetrifaster", string ver = "1.13") @safe pure {
	import std.format : format;
	import std.range : enumerate;
	import std.utf : byCodeUnit;

	auto nickmsg = format!"%s %s %s"(type, nick, ver);
	//string iphashbuf = format! "%d"(ip[0] * 54 + ip[1] * 41 + ip[2] * 29 + ip[3] * 17);
	//ubyte[] buf = [rand];

	//foreach (i, chr; nickmsg.byCodeUnit.enumerate) {
	//	buf ~= (((buf[i] & 0xFF) + (chr & 0xFF)) % 255) ^ iphashbuf[i % iphashbuf.length];
	//}

	//return format!"%(%02X%)"(buf);
	return nickmsg;
}
///
@safe pure unittest {
	assert(genLoginString("TestUser", [209, 52, 144, 98], 128) == "80C512B4114A81DB7DC71DBEE70E4588CD1ABF13B5E42F6F96F9");
}

int clientMain(string[] args) {
	import std.string : format;
	import std.getopt : defaultGetoptPrinter, getopt;

	import vibe.stream.operations : readLine;

	void log(string path) {
		import std.experimental.logger;
		auto logger = new MultiLogger();
		auto fileLogger = new FileLogger(path);
		logger.insertLogger("console", sharedLog);
		logger.insertLogger("file", fileLogger);
		sharedLog = logger;
	}

	int i;
	string nick = null;
	string server = null;
	ubyte[4] ip;
	char[32] iphashbuf;
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
	init_shapes();
	auto help = getopt(
		args,
		"fancy", `Use "fancy" TTY graphics.`, &fancy,
		"log", "Log network traffic to file.", &log,
		"noslide", `Do not allow pieces to "slide" after being dropped with the spacebar.`, &noslide,
		"shadow", "Make the pieces cast a shadow. Can speed up gameplay considerably, but it can be considered as cheating by some people since some other tetrinet clients lack this.", &cast_shadow,
		"fast", "Connect to the server in the tetrifast mode.", &tetrifast
	);

	if ((args.length != 3) || help.helpWanted) {
		defaultGetoptPrinter(
			"Tetrinet " ~ VERSION ~ " - Text-mode tetrinet client\n"~
			"\n"~
			"Usage: "~args[0]~" [OPTION]... NICK SERVER",
			 help.options
		 );
		return 1;
	}
	nick = args[1];
	server = args[2];

	if (slide) {
		noslide = 0;
	}
	if (nick.length > 63) { /* put a reasonable limit on nick length */
		nick = nick[0..63];
	}

	try {
		server_sock = connectTCP(server, 31457);
	} catch (Exception e) {
		stderr.writefln!"Couldn't connect to server %s: %s"(server, e.msg);
		return 1;
	}
	server_sock.sockprintf!"%s"(genLoginString(nick, ip, 255, tetrifast ? "tetrifaster" : "tetrisstart", "1.13"));

	do {
		//char[1024] buf;
		//if (!sgets(buf.ptr, buf.sizeof, server_sock)) {
		//	stderr.writefln!"Server %s closed connection"(server);
		//	server_sock.close();
		//	return 1;
		//}
		parse(cast(string)server_sock.readLine());
	} while (my_playernum < 0);
	sockprintf!"team %d "(server_sock, my_playernum);

	players[my_playernum] = nick;
	dispmode = MODE_PARTYLINE;
	io.screen_setup();
	io.setup_partyline();

	for (;;) {
		Duration timeout;
		if (playing_game && !game_paused) {
			timeout = tetris_timeout();
		} else {
			timeout = -1.msecs;
		}
		i = io.wait_for_input(timeout);
		import std.experimental.logger;
		trace(i);
		if (i == -1) {
			//char[1024] buf;
			if (auto str = cast(string)server_sock.readLine()) {
				parse(str);
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

	server_sock.close();
	return 0;
}
