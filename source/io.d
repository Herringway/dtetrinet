module dtetrinet.io;

public import dtetrinet.tty : tty_interface;

import core.time;

/* Tetrinet for Linux, by Andrew Church <achurch@achurch.org>
 * This program is public domain.
 *
 * Input/output interface declaration and constant definitions.
 */

/* Text buffers: */
enum BUFFER_PLINE = 0;
enum BUFFER_GMSG = 1;
enum BUFFER_ATTDEF = 2;

struct Interface_ {

	/**** Input routine. ****/

	/* Wait for input and return either an ASCII code, a K_* value, -1 if
     * server input is waiting, or -2 if we time out. */
	int function(Duration) wait_for_input;

	/**** Output routines. ****/

	/* Initialize for output. */
	void function() screen_setup;
	/* Redraw the screen. */
	void function() screen_refresh;
	/* Redraw the screen after clearing it. */
	void function() screen_redraw;

	/* Draw text into the given buffer. */
	void function(int, const string) draw_text;
	/* Clear the given text buffer. */
	void function(int) clear_text;

	/* Set up the fields display. */
	void function() setup_fields;
	/* Draw our own field. */
	void function() draw_own_field;
	/* Draw someone else's field. */
	void function(int) draw_other_field;
	/* Draw the game status information. */
	void function() draw_status;
	/* Draw specials stuff */
	void function() draw_specials;
	/* Write a text string for usage of a special. */
	void function(const string, int, int) draw_attdef;
	/* Draw the game message input window. */
	void function(string, size_t) draw_gmsg_input;
	/* Clear the game message input window. */
	void function() clear_gmsg_input;

	/* Set up the partyline display. */
	void function() setup_partyline;
	/* Draw the partyline input string with the cursor at the given position. */
	void function(const string, size_t) draw_partyline_input;

	/* Set up the winlist display. */
	void function() setup_winlist;

}