module flow;
import std::io;
import piece_chain;
import librope;
import tree_sitter;

fn void log(void* payload, tree_sitter::LogType log_type, ZString buffer) {
    io::printf(
        "[TREE SITTER] %s :: %s\n",
        log_type == tree_sitter::LogType.PARSE ? "parser" : "lexer",
        buffer
    );
}

fn int main(String[] args) {
    piece_chain::PieceChain* pc = piece_chain::create("test.txt");
    defer pc.destroy();
    usz bytes = pc.size();
    io::printf("Size: %d\n",bytes);
    @pool() {
        piece_chain::PieceChainIterator* iter = pc.iter(0, bytes);
        ZString data = null;
        usz len = 0;
        while (iter.next(&data, &len)) {
            io::printf("%s (%d)\n", data, len);
        }
    };

    librope::Rope* rope = librope::create_with_allocators(
        &malloc,
        &realloc,
        &free
    );
    defer rope.destroy();
    librope::RopeResult result = rope.insert(
        0,
        "Lorem ipsum dolor sit amet, consectetur adipiscing elit."
        +++ " Phasellus id augue vel magna sodales feugiat."
        +++ " Vivamus posuere ac neque cursus mattis posuere."
    );
    if (result == librope::RopeResult.INVALID_UTF8) {
        io::printn("Failed to insert into rope");
        return 1;
    }
    result = rope.insert(5, " more");
    if (result == librope::RopeResult.INVALID_UTF8) {
        io::printn("Failed to insert into rope");
        return 1;
    }
    result = rope.replace_overlapping(15, " [REDACTED] ");
    if (result == librope::RopeResult.INVALID_UTF8) {
        io::printn("Failed to insert into rope");
        return 1;
    }
    rope.print();
    rope.@foreach(;librope::RopeNode* node) {
        io::printfn("Node: %s", node.data());
    };
    io::printfn("Expected: [ Got: %c", rope.get(16));
    io::printfn("Expected: r Got: %c", rope.get(8));
    @pool() {
        io::printfn("Rope data: %s", rope.create_cstr());
    };

    tree_sitter::Parser* parser = tree_sitter::parser_new();
    defer parser.delete();
    parser.set_logger((tree_sitter::Logger) {
        .payload = null,
        .log = &log,
    });
    tree_sitter::Tree* tree = null;
    tree = parser.parse_string(tree, "test stuff", 10);
    if (tree == null) {
        io::printn("Failed to parse, is there a language set?");
        return 1;
    }
    defer tree.delete();
	return 0;
}
