module piece_chain;

typedef PieceChain = void*;
typedef PieceChainIterator = void*;

struct Error @cname("PieceChainError_t") {
    ZString message;
    int err;
}

enum SaveMode : const CInt {
    AUTO = 0,
    ATOMIC = 1,
    INPLACE = 2,
}

<* @param [&out] data *>
alias Visitor = fn bool(PieceChain chain, usz offset, ZString data, usz len, void* user);

<* @param [&in] path *>
extern fn PieceChain create(char* path) @cname("piece_chain_open");
extern fn void destroy(PieceChain chain) @cname("piece_chain_destroy");

extern fn usz size_bytes(PieceChain chain) @cname("piece_chain_size");
extern fn bool is_dirty(PieceChain chain) @cname("piece_chain_dirty");
extern fn Error last_error(PieceChain chain) @cname("piece_chain_last_error");
<* @param [&in] path *>
extern fn bool save(PieceChain chain, ZString path, SaveMode mode) @cname("piece_chain_save");

<* @param [&in] data *>
extern fn bool insert(PieceChain chain, usz offset, ZString data, usz len) @cname("piece_chain_insert");
extern fn bool delete(PieceChain chain, usz offset, usz len) @cname("piece_chain_delete");
<* @param [&in] data *>
extern fn bool replace(PieceChain chain, usz offset, ZString data, usz len) @cname("piece_chain_replace");

extern fn bool commit(PieceChain chain) @cname("piece_chain_commit");
<* @param [&out] pos *>
extern fn bool undo(PieceChain chain, usz* pos) @cname("piece_chain_undo");
<* @param [&out] pos *>
extern fn bool redo(PieceChain chain, usz* pos) @cname("piece_chain_redo");

<* @param [&out] out *>
extern fn bool read_byte(PieceChain chain, usz offset, ZString out) @cname("piece_chain_read_byte");
extern fn bool visit(PieceChain chain, usz start, usz len, Visitor visitor, void* user) @cname("piece_chain_visit");

extern fn PieceChainIterator iter(PieceChain chain, usz start, usz len) @cname("piece_chain_iter");
extern fn PieceChainIterator iter_clone(PieceChainIterator iterator) @cname("piece_chain_iter_clone");
<*
 @param [&out] data
 @param [&out] len
*>
extern fn bool iter_next(PieceChainIterator chain_iter, ZString* data, usz* len) @cname("piece_chain_iter_next");
extern fn void iter_free(PieceChainIterator chain_iter) @cname("piece_chain_iter_free");
