module flow;
import std::io;
import piece_chain;

fn int main(String[] args) {
    piece_chain::PieceChain pc = piece_chain::create("test.txt");
	io::printn("Hello, World!");
    usz bytes = piece_chain::size_bytes(pc);
    io::printf("Size: %d\n",bytes);
    piece_chain::PieceChainIterator iter = piece_chain::iter(pc, 0, bytes);
    ZString data = null;
    usz len = 0;
    while (piece_chain::iter_next(iter, &data, &len)) {
        io::printf("%s (%d)\n", data, len);
    }
    piece_chain::iter_free(iter);
    piece_chain::destroy(pc);
	return 0;
}
