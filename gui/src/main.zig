const std = @import("std");
const gui = @import("gui");

const Io = std.Io;
const log = std.log.scoped(.main);

pub fn main(init: std.process.Init) !void {
    var state = gui.State{};

    try gui.setup(init, &state);
    defer gui.deinit();

    try gui.createSurface(&state);
}
