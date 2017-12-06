module dtetrinet.sockets;

import core.stdc.stdio;
import core.sys.posix.sys.time;
import core.sys.posix.sys.socket;
import core.sys.posix.netdb;
import core.sys.posix.unistd;
import core.stdc.string;
import core.stdc.errno;
import core.stdc.stdarg;

import dtetrinet.tetrinet;

static FILE* logfile;

enum EOF = 0xFF;
static int lastchar = EOF;

extern(C) int sgetc(int s) {
    int c;
    char ch;

    if (lastchar != EOF) {
	c = lastchar;
	lastchar = EOF;
	return c;
    }
    if (read(s, &ch, 1) != 1)
	return EOF;
    c = ch & 0xFF;
    return c;
}
/* Read a string, stopping with (and discarding) 0xFF as line terminator.
 * If connection was broken, return NULL.
 */

extern(C) char *sgets(char* buf, int len, int s)
{
    int c;
    ubyte* ptr = cast(ubyte*)buf;

    if (len == 0)
	return null;
    c = sgetc(s);
    while (--len && (*ptr++ = cast(char)c) != 0xFF && (c = sgetc(s)) >= 0) { }
    if (c < 0)
	return null;
    if (c == 0xFF)
	ptr--;
    *ptr = 0;
    if (log) {
	if (!logfile)
	    logfile = fopen(logname, "a");
	if (logfile) {
	    timeval tv;
	    gettimeofday(&tv, null);
	    fprintf(logfile, "[%d.%03d] <<< %s\n",
			cast(int) tv.tv_sec, cast(int) tv.tv_usec/1000, buf);
	    fflush(logfile);
	}
    }
    return buf;
}

/*************************************************************************/

/* Adds a 0xFF line terminator. */

extern(C) int sputs(const char *str, int s) @nogc nothrow
{
    char c = 0xFF;
    int n = 0;

    if (log) {
	if (!logfile)
	    logfile = fopen(logname, "a");
	if (logfile) {
	    timeval tv;
	    gettimeofday(&tv, null);
	    fprintf(logfile, "[%d.%03d] >>> %s\n",
			cast(int) tv.tv_sec, cast(int) tv.tv_usec/1000, str);
	}
    }
    if (*str != 0) {
	n = cast(int)write(s, str, strlen(str));
	if (n <= 0)
	    return n;
    }
    if (write(s, &c, 1) <= 0)
	return n;
    return n+1;
}

/*************************************************************************/

/* Adds a 0xFF line terminator. */

extern(C) int sockprintf(int s, const char *fmt, ...) nothrow
{
    va_list args;
    char[16384] buf;	/* Really huge, to try and avoid truncation */

    va_start(args, fmt);
    vsnprintf(buf.ptr, buf.sizeof, fmt, args);
    return sputs(buf.ptr, s);
}

/*************************************************************************/
/*************************************************************************/

extern(C) int conn(const char *host, int port, char[4] ipbuf)
{
version(HAVE_IPV6) {
    char[NI_MAXHOST] hbuf;
    addrinfo hints;
    addrinfo* res, res0;
    char[11] service;
} else {
    hostent *hp;
    sockaddr_in sa;
}
    int sock = -1;

version(HAVE_IPV6) {
    snprintf(service.ptr, service.sizeof, "%d", port);
    memset(&hints, 0, hints.sizeof);
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    if (getaddrinfo(host, service.ptr, &hints, &res0))
	return -1;
    for (res = res0; res; res = res.ai_next) {
	int errno_save;
	sock = socket(res.ai_family, res.ai_socktype, res.ai_protocol);
	if (sock < 0)
	    continue;
	getnameinfo(res.ai_addr, res.ai_addrlen, hbuf.ptr, hbuf.sizeof,
		    null, 0, 0);
	if (connect(sock, res.ai_addr, res.ai_addrlen) == 0) {
	    //if (ipbuf != [0,0,0,0]) {
		if (res.ai_family == AF_INET6) {
		    sockaddr_in6 *sin6 = cast(sockaddr_in6 *)(res.ai_addr);
		    memcpy(ipbuf.ptr, &sin6.sin6_addr + 12, 4);
		} else {
		    sockaddr_in *sin = cast(sockaddr_in *)(res.ai_addr);
		    memcpy(ipbuf.ptr, &sin.sin_addr, 4);
		}
	    //}
	    break;
	}
	errno_save = errno;
	close(sock);
	sock = -1;
	errno = errno_save;
    }
    freeaddrinfo(res0);
} else {
    memset(&sa, 0, sa.sizeof);
    hp = gethostbyname(host);
    if (!hp)
	return -1;
    memcpy(sa.sin_addr.ptr, hp.h_addr, hp.h_length);
    sa.sin_family = cast(ushort)hp.h_addrtype;
    sa.sin_port = htons(cast(ushort)port);
    if ((sock = socket(sa.sin_family, SOCK_STREAM, 0)) < 0)
	return -1;
    if (connect(sock, sa.ptr, sa.sizeof) < 0) {
	int errno_save = errno;
	close(sock);
	errno = errno_save;
	return -1;
    }
    //if (ipbuf != [0,0,0,0])
	memcpy(&ipbuf, &sa.sin_addr, 4);
}

    return sock;
}

/*************************************************************************/

extern(C) void disconn(int s)
{
    shutdown(s, 2);
    close(s);
}