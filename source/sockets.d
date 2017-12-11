module dtetrinet.sockets;

import dtetrinet.tetrinet;

import std.experimental.logger;

import vibe.core.net;


void sockprintf(string fmt, T...)(TCPConnection s, T args) {
	import std.format : format;
	auto str = format!fmt(args);
	trace(str);
	s.write(str);
	s.write("\r\n");
}