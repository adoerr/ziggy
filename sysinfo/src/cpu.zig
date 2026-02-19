const std = @import("std");
const mem = std.mem;
const fmt = std.fmt;
const Io = std.Io;
const Dir = Io.Dir;
const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;

pub const CPUError = error{
    InvalidFormat,
};

pub const Sample = struct {
    idle: u64,
    total: u64,
};

pub const Snapshot = struct {
    total: Sample,
    cores: []Sample,
};

/// Parse a single CPU line from `/proc/stat` and return a `Sample`
pub inline fn parseLine(line: []const u8) CPUError!Sample {
    // remove everything up to the first numerical value
    _, const after = mem.cutScalar(u8, line, ' ') orelse return CPUError.InvalidFormat;
    const values = mem.trimStart(u8, after, " ");

    var it = mem.tokenizeScalar(u8, values, ' ');

    var fields: [8]u64 = .{ 0, 0, 0, 0, 0, 0, 0, 0 };
    var idx: usize = 0;

    while (it.next()) |tok| {
        if (idx >= 8) break;
        fields[idx] = fmt.parseInt(u64, tok, 10) catch return CPUError.InvalidFormat;
        idx += 1;
    }

    // we want at least `user`, `nice`, `system` and `idle` times
    if (idx < 4) return CPUError.InvalidFormat;

    const sum_idle = fields[3] + fields[4]; //`idle` and `iowait`
    const sum_bussy = fields[0] + fields[1] + fields[2] + fields[5] + fields[6] + fields[7];

    return .{ .idle = sum_idle, .total = sum_bussy };
}

// `/proc/stat` is usually small
const STAT_BUFFER_SIZE: usize = 16 * 1024;

// max expected cores
const MAX_CORES: usize = 256;

/// Read a CPU usage counter snapshot for `proc/stat`
pub fn readSnapshot(io: Io, alloc: Allocator) !Snapshot {
    var file = try Dir.openFileAbsolute(io, "/proc/stat", .{});
    defer file.close(io);

    var buf: [STAT_BUFFER_SIZE]u8 = undefined;
    var reader = file.reader(io, &buf);
    const nbytes = try reader.interface.readSliceShort(&buf);

    // pre-alloc a list of cores
    var cores: ArrayList(Sample) = .empty;
    try cores.ensureTotalCapacity(alloc, MAX_CORES);
    errdefer cores.deinit(alloc);

    var total: Sample = undefined;
    // do we have a total (`cpu`) line
    var has_total = false;

    // parse total (`cpu`) and idividual core (`cpux`) lines in one go
    var lines = mem.splitScalar(u8, buf[0..nbytes], '\n');
    while (lines.next()) |raw| {
        if (raw.len < 4) continue;

        // we are only care about cpu counters
        if (raw[0] != 'c' or raw[1] != 'p' or raw[2] != 'u') break;

        if (raw[3] == ' ') {
            total = try parseLine(raw);
            has_total = true;
        } else {
            // per core line (`cpu0`, `cpu1`, etc)
            cores.appendAssumeCapacity(try parseLine(raw));
        }
    }

    if (!has_total) return CPUError.InvalidFormat;

    return .{
        .total = total,
        .cores = cores.toOwnedSlice(alloc) catch cores.items,
    };
}

pub inline fn computeUsage(a: Sample, b: Sample) f64 {
    // handle counter wrap-around or CPU hotpluging
    if (b.total <= a.total or b.idle <= a.idle) return 0.0;

    const total = b.total - a.total;
    const idle = b.idle - a.idle;

    if (idle > total) return 0.0;

    const total_f: f64 = @floatFromInt(total);
    const idle_f: f64 = @floatFromInt(idle);

    return (total_f - idle_f) / total_f * 100.0;
}

const testing = std.testing;
const Threaded = std.Io.Threaded;

test "parseLine" {
    // valid cpu line
    const line = "cpu  218940 1325 115910 98319183 16321 0 3538 0 0 0";
    const sample = try parseLine(line);
    try testing.expectEqual(@as(u64, 98335504), sample.idle);
    try testing.expectEqual(@as(u64, 339713), sample.total);

    // value core line (cpu10)
    const line2 = "cpu10 1989 3 1458 4353320 112 0 7 0 0 0";
    const sample2 = try parseLine(line2);
    try testing.expectEqual(@as(u64, 4353432), sample2.idle);
    try testing.expectEqual(@as(u64, 3457), sample2.total);

    // missing field (less than 4)
    const line3 = "btime 1771145266";
    try testing.expectError(CPUError.InvalidFormat, parseLine(line3));

    // bad format (non numerical)
    const line4 = "cpu9 3555 13 3030 alpha 284 0 6 0 0 0";
    try testing.expectError(CPUError.InvalidFormat, parseLine(line4));
}

test "readSnapshot smoke test" {
    const alloc = testing.allocator;
    var threaded: Threaded = .init_single_threaded;
    const io = threaded.io();

    const snapshot = try readSnapshot(io, alloc);
    defer alloc.free(snapshot.cores);

    try testing.expect(snapshot.total.total > 0);
    try testing.expect(snapshot.total.idle > 0);
}
