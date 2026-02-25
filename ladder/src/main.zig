const std = @import("std");
const ladder = @import("ladder");
const Init = std.process.Init;
const Io = std.Io;
const Random = std.Random;
const ArrayList = std.ArrayList;

pub fn main(init: Init) !void {
    var out_buf: [1024]u8 = undefined;
    var out_writer = Io.File.stdout().writer(init.io, &out_buf);
    var stdout = &out_writer.interface;

    const seed: u64 = @intCast(Io.Timestamp.toMilliseconds(Io.Clock.now(Io.Clock.real, init.io)));
    var prng = Random.DefaultPrng.init(seed);
    const random = prng.random();

    const idx = random.intRangeLessThan(usize, 0, ladder.words.len);
    const start = ladder.words[idx];

    var words = ArrayList([4]u8).empty;
    defer words.deinit(init.gpa);

    try words.append(init.gpa, start);

    try stdout.print("Let's make a word ladder! Say `end` to exit.\n", .{});
    try stdout.flush();
}
