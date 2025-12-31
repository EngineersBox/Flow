module flow;
import std::io;
import piece_chain;
import tree_sitter;

fn void log(void* payload, tree_sitter::LogType log_type, ZString buffer) {
    io::printf("[LOG]: %s\n", buffer);
}

fn int main(String[] args) {
    piece_chain::PieceChain* pc = piece_chain::create("test.txt");
	io::printn("Hello, World!");
    usz bytes = pc.size();
    io::printf("Size: %d\n",bytes);
    piece_chain::PieceChainIterator* iter = pc.iter(0, bytes);
    ZString data = null;
    usz len = 0;
    while (iter.next(&data, &len)) {
        io::printf("%s (%d)\n", data, len);
    }
    iter.free();
    pc.destroy();
    tree_sitter::Parser* parser = tree_sitter::parser_new();
    parser.set_logger((tree_sitter::Logger) {
        .payload = null,
        .log = &log,
    });
    tree_sitter::Tree* tree = null;
    tree = parser.parse_string(tree, "test stuff", 10);
    if (tree == null) {
        io::printn("Failed to parse");
    }
    parser.delete();
	return 0;
}
