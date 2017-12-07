module dtetrinet.io;

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
	int function(int msec) wait_for_input;

	/**** Output routines. ****/

	/* Initialize for output. */
	void function() screen_setup;
	/* Redraw the screen. */
	void function() screen_refresh;
	/* Redraw the screen after clearing it. */
	void function() screen_redraw;

	/* Draw text into the given buffer. */
	void function(int bufnum, const char* s) draw_text;
	/* Clear the given text buffer. */
	void function(int bufnum) clear_text;

	/* Set up the fields display. */
	void function() setup_fields;
	/* Draw our own field. */
	void function() draw_own_field;
	/* Draw someone else's field. */
	void function(int player) draw_other_field;
	/* Draw the game status information. */
	void function() draw_status;
	/* Draw specials stuff */
	void function() draw_specials;
	/* Write a text string for usage of a special. */
	void function(const char* type, int from, int to) draw_attdef;
	/* Draw the game message input window. */
	void function(char* s, int pos) draw_gmsg_input;
	/* Clear the game message input window. */
	void function() clear_gmsg_input;

	/* Set up the partyline display. */
	void function() setup_partyline;
	/* Draw the partyline input string with the cursor at the given position. */
	void function(const char* s, int pos) draw_partyline_input;

	/* Set up the winlist display. */
	void function() setup_winlist;

}

__gshared extern Interface_ tty_interface, xwin_interface;
