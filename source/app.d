import std.stdio;
import std.array : array;
import std.string : toStringz;
import std.algorithm : map;

import dtetrinet.tetrinet;
import dtetrinet.io;
import dtetrinet.sockets;
import dtetrinet.tetris;

version (client) int main(string[] args) {
	return clientMain(args);
}

int clientMain(string[] args) {
	immutable(char)*[] argptrs = args.map!toStringz.array;

	immutable(char)** av = argptrs.ptr;
	int ac = cast(int) args.length;
	int i;

	if ((i = init(ac, av)) != 0)
		return i;

	for (;;) {
		int timeout;
		if (playing_game && !game_paused)
			timeout = tetris_timeout();
		else
			timeout = -1;
		i = io.wait_for_input(timeout);
		if (i == -1) {
			char[1024] buf;
			if (sgets(buf.ptr, cast(int) buf.sizeof, server_sock))
				parse(buf.ptr);
			else {
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
			if (i == 8 || i == 127) /* Backspace or Delete */
				partyline_backspace();
			else if (i == 4) /* Ctrl-D */
				partyline_delete();
			else if (i == 21) /* Ctrl-U */
				partyline_kill();
			else if (i == '\r' || i == '\n')
				partyline_enter();
			else if (i == K_LEFT)
				partyline_move(-1);
			else if (i == K_RIGHT)
				partyline_move(1);
			else if (i == 1) /* Ctrl-A */
				partyline_move(-2);
			else if (i == 5) /* Ctrl-E */
				partyline_move(2);
			else if (i >= 1 && i <= 0xFF)
				partyline_input(i);
		}
	}

	disconn(server_sock);
	return 0;
}
