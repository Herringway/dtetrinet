import dtetrinet.tetrinet;
import dtetrinet.server;

version(unittest) {
} else {
	int main(string[] args) {
		version (client) {
			return clientMain(args);
		}
		version(server) {
			return serverMain();
		}
	}
}