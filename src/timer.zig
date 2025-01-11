const std = @import("std");

var timer: ?std.time.Timer = null;

pub fn nanotime() u64 {
    if (timer == null) {
        timer = std.time.Timer.start() catch unreachable;
    }
    return timer.?.read();
}
