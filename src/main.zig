const std = @import("std");
const slang = @import("slang");

pub fn main() !void {
    const session = slang.spCreateSession();
    defer slang.spDestroySession(session);
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
}
