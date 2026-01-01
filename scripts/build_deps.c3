import std::io;
import std::os::process;
import std::collections::list;

alias ListStr = List {String};

enum LogLevel: int (String name) {
    TRACE = "TRACE",
    DEBUG = "DEBUG",
    INFO = "INFO",
    WARN = "WARN",
    ERROR = "ERROR"
}

fn void log(LogLevel level, String func, String msg, args...) {
    io::printfn("[%s] %s :: %s", level, func, string::tformat(msg, ...));
}

fn void? exec_cmd(String[] cmds, String location = "") {
    ListStr cmd_list;
    defer cmd_list.free();
    cmd_list.init(mem);
    if (location != "") {
        cmd_list.push_all({"cd", location, "&&"});
    }
    cmd_list.push_all(cmds);
    String formatted_cmd = std::core::string::join(mem, cmd_list.array_view(), " ");
    defer formatted_cmd.free(mem);
    process::SubProcess proc = process::create(
        {
            "/bin/sh",
            "-c",
            formatted_cmd
        },
        {
            .inherit_stdio = true,
            .inherit_environment = true,
        }
    )!;
    proc.join()!;
}

fn build_piece_chain() {
    log(LogLevel.INFO, "build_piece_chain", "Building external/PieceChain");
    log(LogLevel.INFO, "build_piece_chain", "Initialising cmake");
    exec_cmd(
        {"cmake", "."},
        "external/PieceChain"
    )!!;
    log(LogLevel.INFO, "build_piece_chain", "Building static library");
    exec_cmd(
        {"make"},
        "external/PieceChain"
    )!!;
    log(LogLevel.INFO, "build_piece_chain", "Installing libraries and headers into project");
    exec_cmd(
        {
            "mkdir", "-p", "'../../lib/piece_chain'", "&&",
            "mkdir", "-p", "'../../include/PieceChain'" "&&",
            "cp", "libPieceChain.a", "../../lib/piece_chain/.", "&&",
            "cp", "include/PieceChain/PieceChain.h", "../../include/PieceChain/."
        },
        "external/PieceChain"
    )!!;
    
}

fn int main(String[] args) {
    exec_cmd(
        {"ls", "-la"},
        "/Users/jackkilrain/projects/c3/flow/external/librope"
    )!!;
    return 0;
}
