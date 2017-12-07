import dtetrinet.tetrinet;
import dtetrinet.server;

int main(string[] args) {
	version (client) {
		return clientMain(args);
	}
	version(server) {
		return serverMain();
	}
}