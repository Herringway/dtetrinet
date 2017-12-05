CC = cc

CFLAGS = -O2 -I/usr/include/ncurses -DHAVE_IPV6 -g -Wall
OBJS = sockets.o tetrinet.o tetris.o tty.o xwin.o

### If you want to have -server tetrinet client option, comment the two lines
### above and uncomment this instead.

# CFLAGS = -O2 -I/usr/include/ncurses -DHAVE_IPV6 -g -DBUILTIN_SERVER -Wall
# OBJS = server.o sockets.o tetrinet.o tetris.o tty.o xwin.o

########

all: tetrinet tetrinet-server

install: all
	cp -p tetrinet tetrinet-server /usr/games

clean:
	rm -f tetrinet tetrinet-server *.o

spotless: clean

########

tetrinet: $(OBJS)
	$(CC) -o $@ $(OBJS) -lncurses

tetrinet-server: server.c sockets.c tetrinet.c tetris.c server.h sockets.h tetrinet.h tetris.h
	$(CC) $(CFLAGS) -o $@ -DSERVER_ONLY server.c sockets.c tetrinet.c tetris.c

.c.o:
	$(CC) $(CFLAGS) -c $<

server.o:	server.c tetrinet.h tetris.h server.h sockets.h
sockets.o:	sockets.c sockets.h tetrinet.h
tetrinet.o:	tetrinet.c tetrinet.h io.h server.h sockets.h tetris.h
tetris.o:	tetris.c tetris.h tetrinet.h io.h sockets.h
tty.o:		tty.c tetrinet.h tetris.h io.h
xwin.o:		xwin.c tetrinet.h tetris.h io.h

tetrinet.h:	io.h
