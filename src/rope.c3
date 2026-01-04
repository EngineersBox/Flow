module librope;

const usz NODE_STR_SIZE = 136;
const usz BIAS = 25;
const usz MAX_HEIGHT = 60;

struct RopeSkipNode @cname("rope_skip_node") {
    usz skip_size;
    RopeNode* node;
}

struct RopeNode @cname("rope_node") {
    char[NODE_STR_SIZE] str;
    ushort num_bytes;
    char height;
    RopeSkipNode[*] nexts;
}

alias RopeAlloc = fn void*(usz bytes);
alias RopeRealloc = fn void*(void* ptr, usz new_size);
alias RopeFree = fn void(void* ptr);

struct Rope @cname("rope") {
    usz num_chars;
    usz num_bytes;
    RopeAlloc alloc;
    RopeRealloc realloc;
    RopeFree free;
    RopeNode head;
}

enum RopeResult: const CInt @cname("ROPE_RESULT") {
    OK = 0,
    INVALID_UTF8 = 1
}

extern fn Rope* create() @cname("rope_new");
extern fn Rope* create_with_allocators(RopeAlloc alloc, RopeRealloc realloc, RopeFree free) @cname("rope_new2");
extern fn Rope* create_with_utf8(ZString str) @cname("rope_new_with_utf8");

<* @param [&in] self *>
extern fn Rope* Rope.copy(Rope* self) @cname("rope_copy");
extern fn void Rope.destroy(Rope* self) @cname("rope_free");

<* @param [&in] self *>
extern fn usz Rope.char_count(Rope* self) @cname("rope_char_count");

<* @param [&in] self *>
extern fn usz Rope.byte_count(Rope* self) @cname("rope_byte_count");

<* @param [&out] dest *>
extern fn usz Rope.write_cstr(Rope* self, ZString dest) @cname("rope_write_cstr");
extern fn ZString Rope.create_cstr(Rope* self) @cname("rope_create_cstr");

<* @param [&in] str *>
extern fn RopeResult Rope.insert(Rope* self, usz pos, ZString str) @cname("rope_insert");
extern fn void Rope.remove(Rope* self, usz pos, usz num) @cname("rope_del");

<* @param [&in] str *>
macro RopeResult Rope.replace(Rope* self, usz pos, usz num, ZString str) {
    self.remove(pos, num);
    return self.insert(pos, str);
}

<* @param [&in] str *>
macro RopeResult Rope.replace_overlapping(Rope* self, usz pos, ZString str) {
    return self.replace(pos, str.len(), str);
}

<* @param [&in] self *>
fn char Rope.get(Rope* self, usz char_pos) {
    assert(char_pos <= self.num_chars);
    RopeNode* node = &self.head;
    int height = self.head.height - 1;
    usz offset = char_pos;
    usz skip;
    while (true) {
        skip = node.nexts[height].skip_size;
        if (offset > skip) {
            // Right
            assert(node == &self.head || node.num_bytes > 0);
            offset -= skip;
            node = node.nexts[height].node;
            continue;
        }
        // Down
        if (height == 0) {
            break;
        }
        height--;
    }
    assert(offset <= NODE_STR_SIZE);
    return node.str[offset];
}

<* @require $defined(self.head) *>
macro Rope.@foreach(Rope* self; @body(node)) {
    for (RopeNode* iter = &self.head; iter != null; iter = iter.nexts[0].node) {
        @body(iter);
    }
}

macro ZString RopeNode.data(RopeNode* self) {
    return (ZString) &self.str;
}

macro usz RopeNode.num_chars(RopeNode* self) {
    return self.nexts[0].skip_size;
}

extern fn void Rope.check(Rope* self) @cname("_rope_check");
extern fn void Rope.print(Rope* self) @cname("_rope_print");
