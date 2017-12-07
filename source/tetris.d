module dtetrinet.tetris;

import dtetrinet.tetrinet;
import dtetrinet.sockets;

import core.time;

import core.stdc.string;
import core.stdc.stdio;

deprecated import core.sys.posix.sys.time;

deprecated import core.sys.posix.stdlib;

extern (C) int strncasecmp(const char* s1, const char* s2, size_t n);

enum SPECIAL_A = 0;
enum SPECIAL_C = 1;
enum SPECIAL_N = 2;
enum SPECIAL_R = 3;
enum SPECIAL_S = 4;
enum SPECIAL_B = 5;
enum SPECIAL_G = 6;
enum SPECIAL_Q = 7;
enum SPECIAL_O = 8;

struct PieceData {
	int hot_x, hot_y; /* Hotspot coordinates */
	int top, left; /* Top-left coordinates relative to hotspot */
	int bottom, right; /* Bottom-right coordinates relative to hotspot */
	char[4][4] shape; /* Shape data for the piece */
}

enum MAX_SPECIALS = 64;

__gshared {
	int current_piece, current_rotation;
	int piece_waiting;
	PieceData[4][7] piecedata;
	Duration timeout;
	int last_special;
	int[7] piecefreq;
	int[9] specialfreq;
	int old_mode;
	int initial_level, lines_per_level, level_inc, level_average;
	int special_lines, special_count, special_capacity;
	Field[6] fields;
	int[6] levels;
	int lines;
	byte[MAX_SPECIALS] specials;
	int next_piece;
	int current_x, current_y;
}

/*************************************************************************/

/* The array of piece shapes.  It is organized as:
 *	- 7 pieces
 *	  - 4 rows
 *	    - 4 rotations (ordered clockwise)
 *	      - 4 points
 * A . is an empty point, a # is a full one.  An X (upper-case) represents
 * the "hot-spot" of the piece; this is where the coordinates are fastened
 * to, and is used to determine the piece's new position after rotation.
 * If the location for an X empty, use a lowercase letter instead.
 *
 * This is all parsed by init_shapes, which should be called at startup.
 */

static immutable char[4][4][4][7] shapes = [
    [ [ "##X#", "..X.", "##X#", "..X." ],
      [ "....", "..#.", "....", "..#." ],
      [ "....", "..#.", "....", "..#." ],
      [ "....", "..#.", "....", "..#." ] ],

    [ [ "....", "....", "....", "...." ],
      [ ".X#.", ".X#.", ".X#.", ".X#." ],
      [ ".##.", ".##.", ".##.", ".##." ],
      [ "....", "....", "....", "...." ] ],

    [ [ "....", ".#..", "#...", ".##." ],
      [ "#X#.", ".X..", "#X#.", ".X.." ],
      [ "..#.", "##..", "....", ".#.." ],
      [ "....", "....", "....", "...." ] ],

    [ [ "....", "##..", "..#.", ".#.." ],
      [ "#X#.", ".X..", "#X#.", ".X.." ],
      [ "#...", ".#..", "....", ".##." ],
      [ "....", "....", "....", "...." ] ],

    [ [ "....", ".#..", "....", ".#.." ],
      [ "#X..", "#X..", "#X..", "#X.." ],
      [ ".##.", "#...", ".##.", "#..." ],
      [ "....", "....", "....", "...." ] ],

    [ [ "....", "#...", "....", "#..." ],
      [ ".X#.", "#X..", ".X#.", "#X.." ],
      [ "##..", ".#..", "##..", ".#.." ],
      [ "....", "....", "....", "...." ] ],

    [ [ "....", ".#..", ".#..", ".#.." ],
      [ "#X#.", "#X..", "#X#.", ".X#." ],
      [ ".#..", ".#..", "....", ".#.." ],
      [ "....", "....", "....", "...." ] ]
];

/*************************************************************************/

/* Parse the shapes array and fill in the piece data. */

void init_shapes() {
	int i, x, y, r;

	for (i = 0; i < 7; i++) {
		for (r = 0; r < 4; r++) {
			piecedata[i][r].hot_x = -1;
			piecedata[i][r].hot_y = -1;
			piecedata[i][r].top = 3;
			piecedata[i][r].left = 3;
			piecedata[i][r].bottom = 0;
			piecedata[i][r].right = 0;
			for (y = 0; y < 4; y++) {
				for (x = 0; x < 4; x++) {
					switch (shapes[i][y][r][x]) {
						case '.':
							piecedata[i][r].shape[y][x] = 0;
							break;
						case '#':
							piecedata[i][r].shape[y][x] = 1;
							if (piecedata[i][r].top > y)
								piecedata[i][r].top = y;
							if (piecedata[i][r].left > x)
								piecedata[i][r].left = x;
							if (piecedata[i][r].bottom < y)
								piecedata[i][r].bottom = y;
							if (piecedata[i][r].right < x)
								piecedata[i][r].right = x;
							break;
						case 'x':
							piecedata[i][r].shape[y][x] = 0;
							piecedata[i][r].hot_x = x;
							piecedata[i][r].hot_y = y;
							break;
						case 'X':
							piecedata[i][r].shape[y][x] = 1;
							if (piecedata[i][r].top > y)
								piecedata[i][r].top = y;
							if (piecedata[i][r].left > x)
								piecedata[i][r].left = x;
							if (piecedata[i][r].bottom < y)
								piecedata[i][r].bottom = y;
							if (piecedata[i][r].right < x)
								piecedata[i][r].right = x;
							piecedata[i][r].hot_x = x;
							piecedata[i][r].hot_y = y;
							break;
						default:
							fprintf(stderr, "Piece %d rotation %d: " ~ "weird character `%c' at (%d,%d)\n", i, r, shapes[i][y][r][x], x, y);
							exit(1);
					}
				}
			}
			if (piecedata[i][r].hot_x < 0 || piecedata[i][r].hot_y < 0) {
				fprintf(stderr, "Piece %d rotation %d missing hot spot!\n", i, r);
				exit(1);
			}
		}
	}
}

/*************************************************************************/

/* Retrieve the shape for the given piece and rotation.  Return -1 if piece
 * or rotation is invalid, else 0.
 */

int get_shape(int piece, int rotation, char[4][4] buf) {
	int x, y;
	char* shape;

	if (piece < 0 || piece > 6 || rotation < 0 || rotation > 3)
		return -1;
	shape = cast(char*) piecedata[piece][rotation].shape;
	for (y = 0; y < 4; y++) {
		for (x = 0; x < 4; x++) {
			buf[y][x] = *shape++ ? cast(char)(piece % 5 + 1) : 0;
		}
	}
	return 0;
}

/*************************************************************************/
/*************************************************************************/

/* Return the number of milliseconds of delay between piece drops for the
 * current level.
 */

int level_delay() {
	int level = levels[my_playernum - 1];
	int delay = 1000;

	while (--level)
		delay = (delay * 69 + 35) / 70; /* multiply by 69/70 and round */
	return delay;
}

/*************************************************************************/

/* Return whether the piece in the position given by the x, y, and rot
 * variables (interpreted the same way as current_*) would overlap any
 * other blocks in the field.  A value of -1 means use the current_* value.
 */

int piece_overlaps(int x, int y, int rot) {
	Field* f = &fields[my_playernum - 1];
	PieceData* pd;
	int i, j, ok;

	if (x < 0)
		x = current_x;
	if (y < 0)
		y = current_y;
	if (rot < 0)
		rot = current_rotation;
	pd = &piecedata[current_piece][rot];
	x -= pd.hot_x;
	y -= pd.hot_y;
	ok = 1;
	for (j = 0; ok && j < 4; j++) {
		if (y + j < 0)
			continue;
		for (i = 0; ok && i < 4; i++) {
			if (pd.shape[j][i] && (y + j >= FIELD_HEIGHT || x + i < 0 || x + i >= FIELD_WIDTH || (*f)[y + j][x + i]))
				ok = 0;
		}
	}
	return !ok;
}

/*************************************************************************/

/* Draw the piece in its current position on the board.  If draw == 0, then
 * erase the piece rather than drawing it.
 */

void draw_piece(int draw) {
	Field* f = &fields[my_playernum - 1];
	char c = draw ? cast(char)(current_piece % 5 + 1) : 0;
	int x = current_x - piecedata[current_piece][current_rotation].hot_x;
	int y = current_y - piecedata[current_piece][current_rotation].hot_y;
	char* shape = cast(char*) piecedata[current_piece][current_rotation].shape;
	int i, j;

	for (j = 0; j < 4; j++) {
		if (y + j < 0) {
			shape += 4;
			continue;
		}
		for (i = 0; i < 4; i++) {
			if (*shape++)
				(*f)[y + j][x + i] = c;
		}
	}
}

/*************************************************************************/

/* Clear any full lines on the field; return the number of lines cleared. */

int clear_lines(int add_specials) {
	Field* f = &fields[my_playernum - 1];
	int x, y, count = 0, i, j, k;
	int[9] new_specials;

	for (y = 0; y < FIELD_HEIGHT; y++) {
		int full = 1;
		for (x = 0; x < FIELD_WIDTH; x++) {
			if ((*f)[y][x] == 0) {
				full = 0;
				break;
			}
		}
		if (full)
			count++;
	}

	memset(new_specials.ptr, 0, new_specials.sizeof);
	for (y = 0; y < FIELD_HEIGHT; y++) {
		int full = 1;
		for (x = 0; x < FIELD_WIDTH; x++) {
			if ((*f)[y][x] == 0) {
				full = 0;
				break;
			}
		}
		if (full) {
			for (x = 0; x < FIELD_WIDTH; x++) {
				if ((*f)[y][x] > 5)
					new_specials[(*f)[y][x] - 6]++;
			}
			if (y > 0)
				memmove((*f)[1].ptr, (*f)[0].ptr, FIELD_WIDTH * y);
			memset((*f)[0].ptr, 0, FIELD_WIDTH);
		}
	}

	if (add_specials) {
		int pos = 0;
		while (pos < special_capacity && specials[pos] >= 0)
			pos++;
		for (i = 0; i < count && pos < special_capacity; i++) {
			for (j = 0; j < 9 && pos < special_capacity; j++) {
				for (k = 0; k < new_specials[j] && pos < special_capacity; k++) {
					if (windows_mode && rand() % 2) {
						memmove(specials.ptr + 1, specials.ptr, pos);
						specials[0] = cast(byte) j;
						pos++;
					} else
						specials[pos++] = cast(byte) j;
				}
			}
		}
		if (pos < special_capacity)
			specials[pos] = -1;
		io.draw_specials();
	}

	return count;
}

/*************************************************************************/

/* Place the given number of specials on the field.  If there aren't enough
 * blocks to replace, replace all of the blocks and drop the rest of the
 * specials.
 */

void place_specials(int num) {
	Field* f = &fields[my_playernum - 1];
	int nblocks = 0, left;
	int x, y, tries;

	for (y = 0; y < FIELD_HEIGHT; y++) {
		for (x = 0; x < FIELD_WIDTH; x++) {
			if ((*f)[y][x])
				nblocks++;
		}
	}
	if (num > nblocks)
		num = nblocks;
	left = num;
	tries = 10;
	while (left > 0 && tries > 0) {
		for (y = 0; left > 0 && y < FIELD_HEIGHT; y++) {
			for (x = 0; left > 0 && x < FIELD_WIDTH; x++) {
				if ((*f)[y][x] > 5 || (*f)[y][x] == 0)
					continue;
				if (rand() % nblocks < num) {
					int which = 0, n = rand() % 100;
					while (n >= specialfreq[which]) {
						n -= specialfreq[which];
						which++;
					}
					(*f)[y][x] = cast(char)(6 + which);
					left--;
				}
			}
		}
		tries--;
	}
}

/*************************************************************************/

/* Send the new field, either as differences from the given old field or
 * (if more efficient) as a complete field.  If oldfield is NULL, always
 * send the complete field.
 */

void send_field(Field* oldfield) {
	Field* f = &fields[my_playernum - 1];
	int i, x, y, diff = 0;
	char[512] buf;
	char* s;

	if (oldfield) {
		for (y = 0; y < FIELD_HEIGHT; y++) {
			for (x = 0; x < FIELD_WIDTH; x++) {
				if ((*f)[y][x] != (*oldfield)[y][x])
					diff++;
			}
		}
	} else {
		diff = FIELD_WIDTH * FIELD_HEIGHT;
	}
	if (diff < (FIELD_WIDTH * FIELD_HEIGHT) / 2) {
		s = buf.ptr + sprintf(buf.ptr, "f %d ", my_playernum);
		for (i = 0; i < 15; i++) {
			int seen = 0; /* Have we seen a difference of this block? */
			for (y = 0; y < FIELD_HEIGHT; y++) {
				for (x = 0; x < FIELD_WIDTH; x++) {
					if ((*f)[y][x] == i && (*f)[y][x] != (*oldfield)[y][x]) {
						if (!seen) {
							*s++ = cast(char)(i + '!');
							seen = 1;
						}
						*s++ = cast(char)(x + '3');
						*s++ = cast(char)(y + '3');
					}
				} /* for x */
			} /* for y */
		} /* for i (each tile type) */
	} /* difference check */
	/* -4 below is to adjust for "f %d " */
	if (diff >= (FIELD_WIDTH * FIELD_HEIGHT) / 2 || strlen(buf.ptr) - 4 > FIELD_WIDTH * FIELD_HEIGHT) {
		static immutable string specials = "acnrsbgqo";
		s = buf.ptr + sprintf(buf.ptr, "f %d ", my_playernum);
		for (y = 0; y < FIELD_HEIGHT; y++) {
			for (x = 0; x < FIELD_WIDTH; x++) {
				if ((*f)[y][x] > 5)
					*s++ = specials[(*f)[y][x] - 6];
				else
					*s++ = cast(char)((*f)[y][x] + '0');
			}
		}
	}
	*s = 0;
	sputs(buf.ptr, server_sock);
}

/*************************************************************************/
/*************************************************************************/

/* Generate a new piece and set up the timer. */

void new_piece() {
	int n;
	PieceData* pd;

	current_piece = next_piece;
	n = rand() % 100;
	next_piece = 0;
	while (n >= piecefreq[next_piece] && next_piece < 6) {
		n -= piecefreq[next_piece];
		next_piece++;
	}
	current_rotation = 0;
	pd = &piecedata[current_piece][current_rotation];
	current_x = 6;
	current_y = pd.hot_y - pd.top;
	if (piece_overlaps(-1, -1, -1)) {
		current_x--;
		if (piece_overlaps(-1, -1, -1)) {
			current_x += 2;
			if (piece_overlaps(-1, -1, -1)) {
				Field* f = &fields[my_playernum - 1];
				int x, y;
				for (y = 0; y < FIELD_HEIGHT; y++) {
					for (x = 0; x < FIELD_WIDTH; x++)
						(*f)[y][x] = cast(char)(rand() % 5 + 1);
				}
				send_field(null);
				sockprintf(server_sock, "playerlost %d", my_playernum);
				playing_game = 0;
				not_playing_game = 1;
			}
		}
	}
	draw_piece(1);
	io.draw_status();
	io.draw_own_field();

	// add delay msecs?
	gettimeofday(&timeout, null);
	timeout += level_delay() * 1.msec;
	timeout.tv_sec += timeout.tv_usec / 1000000;
	timeout.tv_usec %= 1000000;
	piece_waiting = 0;
}

/*************************************************************************/

/* Step the current piece down one space.  If it's already as far as it can
 * go, solidify it, check for completed lines, send the new field state,
 * and start a new piece.
 */

void step_down() {
	Field* f = &fields[my_playernum - 1];
	PieceData* pd = &piecedata[current_piece][current_rotation];
	int y = current_y - pd.hot_y;
	int ynew;

	draw_piece(0);
	ynew = current_y + 1;
	if (y + 1 + pd.bottom < FIELD_HEIGHT && !piece_overlaps(-1, ynew, -1)) {
		current_y++;
		draw_piece(1);
		io.draw_own_field();
		gettimeofday(&timeout, null);
		timeout.tv_usec += level_delay() * 1000;
		timeout.tv_sec += timeout.tv_usec / 1000000;
		timeout.tv_usec %= 1000000;
	} else {
		int completed, level, nspecials;
		Field oldfield;
		char[16] buf;

		memcpy(&oldfield, f, oldfield.sizeof);
		draw_piece(1);
		if (last_special > lines) /* i.e. from a previous game */
			last_special = 0;
		completed = clear_lines(1);
		lines += completed;
		if (old_mode && completed > 1) {
			if (completed < 4)
				completed--;
			sockprintf(server_sock, "sb 0 cs%d %d", completed, my_playernum);
			sprintf(buf.ptr, "cs%d", completed);
			io.draw_attdef(buf.ptr, my_playernum, 0);
		}
		level = initial_level + (lines / lines_per_level) * level_inc;
		if (level > 100)
			level = 100;
		levels[my_playernum] = level;
		if (completed > 0) {
			sockprintf(server_sock, "lvl %d %d", my_playernum, level);
			io.draw_status();
		}
		nspecials = (lines - last_special) / special_lines;
		last_special += nspecials * special_lines;
		nspecials *= special_count;
		place_specials(nspecials);
		io.draw_own_field();
		send_field(&oldfield);
		piece_waiting = 1;
		gettimeofday(&timeout, null);
		timeout.tv_usec += tetrifast ? 0 : 600000;
		timeout.tv_sec += timeout.tv_usec / 1000000;
		timeout.tv_usec %= 1000000;
	}
}

/*************************************************************************/

/* Do something for a special block. */

void do_special(const char* type, int from, int to) {
	Field* f = &fields[my_playernum - 1];
	Field oldfield;
	int x, y;

	io.draw_attdef(type, from, to);

	if (!playing_game)
		return;
	if (to != 0 && to != my_playernum && !(from == my_playernum && *type == 's'))
		return;

	if (!piece_waiting)
		draw_piece(0);

	memcpy(&oldfield, f, Field.sizeof);

	if (strncmp(type, "cs", 2) == 0) {
		int nlines = atoi(type + 2);

		/* Don't add lines from a team member */
		if (!teams[my_playernum - 1] || !teams[from - 1] || strcmp(teams[my_playernum - 1], teams[from - 1]) != 0) {
			while (nlines--) {
				memmove((*f)[0].ptr, (*f)[1].ptr, FIELD_WIDTH * (FIELD_HEIGHT - 1));
				for (x = 0; x < FIELD_WIDTH; x++)
					f[21][x] = cast(char)(1 + rand() % 5);
				f[FIELD_HEIGHT - 1][rand() % FIELD_WIDTH] = 0;
			}
		}

	} else if (*type == 'a') {
		memmove((*f)[0].ptr, f[1].ptr, FIELD_WIDTH * (FIELD_HEIGHT - 1));
		for (x = 0; x < FIELD_WIDTH; x++)
			f[21][x] = cast(char)(1 + rand() % 5);
		f[FIELD_HEIGHT - 1][rand() % FIELD_WIDTH] = 0;
		f[FIELD_HEIGHT - 1][rand() % FIELD_WIDTH] = 0;
		f[FIELD_HEIGHT - 1][rand() % FIELD_WIDTH] = 0;

	} else if (*type == 'b') {
		for (y = 0; y < FIELD_HEIGHT; y++) {
			for (x = 0; x < FIELD_WIDTH; x++) {
				if ((*f)[y][x] > 5)
					(*f)[y][x] = cast(char)(rand() % 5 + 1);
			}
		}

	} else if (*type == 'c') {
		memmove((*f)[1].ptr, (*f)[0].ptr, FIELD_WIDTH * (FIELD_HEIGHT - 1));
		memset((*f)[0].ptr, 0, FIELD_WIDTH);

	} else if (*type == 'g') {
		for (x = 0; x < FIELD_WIDTH; x++) {
			y = FIELD_HEIGHT - 1;
			while (y > 0) {
				if ((*f)[y][x] == 0) {
					int y2, allclear = 1;
					for (y2 = y - 1; allclear && y2 >= 0; y2--) {
						if ((*f)[y2][x])
							allclear = 0;
					}
					if (allclear)
						break;
					for (y2 = y - 1; y2 >= 0; y2--)
						(*f)[y2 + 1][x] = (*f)[y2][x];
					(*f)[0][x] = 0;
				} else
					y--;
			}
		}
		clear_lines(0);

	} else if (*type == 'n') {
		memset(f.ptr, 0, FIELD_WIDTH * FIELD_HEIGHT);

	} else if (*type == 'o') {
		int tries, x2, y2, xnew, ynew;

		for (y = 0; y < FIELD_HEIGHT; y++) {
			for (x = 0; x < FIELD_WIDTH; x++) {
				if ((*f)[y][x] != 6 + SPECIAL_O)
					continue;
				(*f)[y][x] = 0;
				for (y2 = y - 1; y2 <= y + 1; y2++) {
					if (y2 < 0 || y2 >= FIELD_HEIGHT)
						continue;
					for (x2 = x - 1; x2 <= x + 1; x2++) {
						if (x2 < 0 || x2 >= FIELD_WIDTH)
							continue;
						if (!windows_mode && !(*f)[y2][x2])
							continue;
						tries = 10;
						while (tries--) {
							xnew = random() % FIELD_WIDTH;
							ynew = FIELD_HEIGHT - 1 - random() % 16;
							if (windows_mode || !(*f)[ynew][xnew]) {
								(*f)[ynew][xnew] = (*f)[y2][x2];
								break;
							}
						}
						(*f)[y2][x2] = 0;
					}
				}
			}
		}
		clear_lines(0);

	} else if (*type == 'q') {
		for (y = 0; y < FIELD_HEIGHT; y++) {
			int r = rand() % 3 - 1;
			if (r < 0) {
				int save = (*f)[y][0];
				memmove((*f)[y].ptr, (*f)[y].ptr + 1, FIELD_WIDTH - 1);
				if (windows_mode)
					(*f)[y][FIELD_WIDTH - 1] = 0;
				else
					(*f)[y][FIELD_WIDTH - 1] = cast(char) save;
			} else if (r > 0) {
				int save = (*f)[y][FIELD_WIDTH - 1];
				memmove((*f)[y].ptr + 1, (*f)[y].ptr, FIELD_WIDTH - 1);
				if (windows_mode)
					(*f)[y][0] = 0;
				else
					(*f)[y][0] = cast(char) save;
			}
		}

	} else if (*type == 'r') {
		int i;

		for (i = 0; i < 10; i++) {
			x = rand() % FIELD_WIDTH;
			y = rand() % FIELD_HEIGHT;
			if ((*f)[y][x] != 0) {
				(*f)[y][x] = 0;
				break;
			}
		}

	} else if (*type == 's') {
		Field temp;

		memcpy(temp.ptr, fields[from - 1].ptr, Field.sizeof);
		memcpy(fields[from - 1].ptr, fields[to - 1].ptr, Field.sizeof);
		memcpy(fields[to - 1].ptr, temp.ptr, Field.sizeof);
		if (from == my_playernum || to == my_playernum)
			memset(fields[my_playernum - 1].ptr, 0, 6 * FIELD_WIDTH);
		if (from != my_playernum)
			io.draw_other_field(from);
		if (to != my_playernum)
			io.draw_other_field(to);

	}

	send_field(&oldfield);

	if (!piece_waiting) {
		while (piece_overlaps(-1, -1, -1))
			current_y--;
		draw_piece(1);
	}
	io.draw_own_field();
}

/*************************************************************************/
/*************************************************************************/

/* Deal with the in-game message input buffer. */

__gshared char[512] gmsg_buffer;
__gshared int gmsg_pos;

/*************************************************************************/

void gmsg_input(int c) {
	if (gmsg_pos < gmsg_buffer.sizeof - 1) {
		memmove(gmsg_buffer.ptr + gmsg_pos + 1, gmsg_buffer.ptr + gmsg_pos, strlen(gmsg_buffer.ptr + gmsg_pos) + 1);
		gmsg_buffer[gmsg_pos++] = cast(char) c;
		io.draw_gmsg_input(gmsg_buffer.ptr, gmsg_pos);
	}
}

/*************************************************************************/

void gmsg_delete() {
	if (gmsg_buffer[gmsg_pos]) {
		memmove(gmsg_buffer.ptr + gmsg_pos, gmsg_buffer.ptr + gmsg_pos + 1, strlen(gmsg_buffer.ptr + gmsg_pos) - 1 + 1);
		io.draw_gmsg_input(gmsg_buffer.ptr, gmsg_pos);
	}
}

/*************************************************************************/

void gmsg_backspace() {
	if (gmsg_pos > 0) {
		gmsg_pos--;
		gmsg_delete();
	}
}

/*************************************************************************/

void gmsg_kill() {
	gmsg_pos = 0;
	gmsg_buffer = null;
	io.draw_gmsg_input(gmsg_buffer.ptr, gmsg_pos);
}

/*************************************************************************/

void gmsg_move(int how) {
	if (how == -2) {
		gmsg_pos = 0;
		io.draw_gmsg_input(gmsg_buffer.ptr, gmsg_pos);
	} else if (how == -1 && gmsg_pos > 0) {
		gmsg_pos--;
		io.draw_gmsg_input(gmsg_buffer.ptr, gmsg_pos);
	} else if (how == 1 && gmsg_buffer[gmsg_pos]) {
		gmsg_pos++;
		io.draw_gmsg_input(gmsg_buffer.ptr, gmsg_pos);
	} else if (how == 2) {
		gmsg_pos = cast(int) strlen(gmsg_buffer.ptr);
		io.draw_gmsg_input(gmsg_buffer.ptr, gmsg_pos);
	}
}

/*************************************************************************/

void gmsg_enter() {
	if (gmsg_buffer.ptr) {
		if (strncasecmp(gmsg_buffer.ptr, "/me ", 4) == 0)
			sockprintf(server_sock, "gmsg * %s %s", players[my_playernum - 1], gmsg_buffer.ptr + 4);
		else
			sockprintf(server_sock, "gmsg <%s> %s", players[my_playernum - 1], gmsg_buffer.ptr);
		gmsg_pos = 0;
		gmsg_buffer = null;
		io.clear_gmsg_input();
	}
}

/*************************************************************************/
/*************************************************************************/

/* Set up for a new game. */

void new_game() {
	int n;

	gettimeofday(&timeout, null);
	timeout.tv_usec += 1200000;
	timeout.tv_sec += timeout.tv_usec / 1000000;
	timeout.tv_usec %= 1000000;
	piece_waiting = 1;
	n = rand() % 100;
	next_piece = 0;
	while (n >= piecefreq[next_piece] && next_piece < 6) {
		n -= piecefreq[next_piece];
		next_piece++;
	}
}

/*************************************************************************/

/* Return the number of milliseconds until we want to do something. */

int tetris_timeout() {
	timeval tv;
	int t;

	gettimeofday(&tv, null);
	t = cast(int)((timeout.tv_sec - tv.tv_sec) * 1000 + (timeout.tv_usec - tv.tv_usec) / 1000);
	return t < 0 ? 0 : t;
}

/*************************************************************************/

/* Do something when we hit a timeout. */

void tetris_timeout_action() {
	if (piece_waiting)
		new_piece();
	else
		step_down();
}

/*************************************************************************/

/* Do something with a character of input. */

static immutable string special_chars = "acnrsbgqo";

void tetris_input(int c) {
	PieceData* pd = &piecedata[current_piece][current_rotation];
	int x = current_x - pd.hot_x;
	int y = current_y - pd.hot_y;
	int rnew, ynew;
	static int gmsg_active = 0;

	if (gmsg_active) {
		if (c == 8 || c == 127) /* Backspace or Delete */
			gmsg_backspace();
		else if (c == 4) /* Ctrl-D */
			gmsg_delete();
		else if (c == 21) /* Ctrl-U */
			gmsg_kill();
		else if (c == K_LEFT)
			gmsg_move(-1);
		else if (c == K_RIGHT)
			gmsg_move(1);
		else if (c == 1) /* Ctrl-A */
			gmsg_move(-2);
		else if (c == 5) /* Ctrl-E */
			gmsg_move(2);
		else if (c == '\r' || c == '\n') {
			gmsg_enter();
			gmsg_active = 0;
		} else if (c == 27) { /* Escape */
			io.clear_gmsg_input();
			gmsg_active = 0;
		} else if (c >= 1 && c <= 0xFF)
			gmsg_input(c);
		return;
	}

	if (c != 't' && (!playing_game || game_paused))
		return;

	switch (c) {
		case K_UP: /* Rotate clockwise */
			case 'x':
			if (piece_waiting)
				break;
			rnew = (current_rotation + 1) % 4;
			pd = &piecedata[current_piece][current_rotation];
			x = current_x - pd.hot_x;
			y = current_y - pd.hot_y;
			if (x + pd.left < 0 || x + pd.right >= FIELD_WIDTH || y + pd.bottom >= FIELD_HEIGHT)
				break;
			draw_piece(0);
			if (!piece_overlaps(-1, -1, rnew)) {
				current_rotation = rnew;
				draw_piece(1);
				io.draw_own_field();
			} else {
				draw_piece(1);
			}
			break;

		case 'z': /* Rotate counterclockwise */
			if (piece_waiting)
				break;
			rnew = (current_rotation + 3) % 4;
			pd = &piecedata[current_piece][current_rotation];
			x = current_x - pd.hot_x;
			y = current_y - pd.hot_y;
			if (x + pd.left < 0 || x + pd.right >= FIELD_WIDTH || y + pd.bottom >= FIELD_HEIGHT)
				break;
			draw_piece(0);
			if (!piece_overlaps(-1, -1, rnew)) {
				current_rotation = rnew;
				draw_piece(1);
				io.draw_own_field();
			} else {
				draw_piece(1);
			}
			break;

		case K_LEFT: /* Move left */
			if (piece_waiting)
				break;
			if (x + pd.left > 0) {
				draw_piece(0);
				if (!piece_overlaps(current_x - 1, -1, -1)) {
					current_x--;
					draw_piece(1);
					io.draw_own_field();
				} else {
					draw_piece(1);
				}
			}
			break;

		case K_RIGHT: /* Move right */
			if (piece_waiting)
				break;
			if (x + pd.right < FIELD_WIDTH - 1) {
				draw_piece(0);
				if (!piece_overlaps(current_x + 1, -1, -1)) {
					current_x++;
					draw_piece(1);
					io.draw_own_field();
				} else {
					draw_piece(1);
				}
			}
			break;

		case K_DOWN: /* Down one space */
			if (piece_waiting)
				break;
			step_down();
			break;

		case ' ': /* Down until the piece hits something */
			if (piece_waiting)
				break;
			draw_piece(0);
			ynew = current_y + 1;
			while (y + pd.bottom < FIELD_HEIGHT && !piece_overlaps(-1, ynew, -1)) {
				ynew++;
				y++;
			}
			ynew--;
			if (ynew != current_y) {
				current_y = ynew - 1;
				if (noslide)
					current_y++; /* Don't allow sliding */
				step_down();
			} else {
				draw_piece(1);
			}
			break;

		case 'd':
			if (specials[0] == -1)
				break;
			if (special_capacity > 1)
				memmove(specials.ptr, specials.ptr + 1, special_capacity - 1);
			specials[special_capacity - 1] = -1;
			io.draw_specials();
			break;

		case '1':
			case '2':
			case '3':
			case '4':
			case '5':
			case '6': {
				char[2] buf;

				c -= '0';
				if (!players[c - 1])
					break;
				if (specials[0] == -1)
					break;
				sockprintf(server_sock, "sb %d %c %d", c, special_chars[cast(int) specials[0]], my_playernum);
				buf[0] = special_chars[cast(int) specials[0]];
				buf[1] = 0;
				do_special(buf.ptr, my_playernum, c);
				if (special_capacity > 1)
					memmove(specials.ptr, specials.ptr + 1, special_capacity - 1);
				specials[special_capacity - 1] = -1;
				io.draw_specials();
				break;
			}

		case 't':
			gmsg_active = 1;
			io.draw_gmsg_input(gmsg_buffer.ptr, gmsg_pos);
			break;
		default:
			assert(0);
	}
}
