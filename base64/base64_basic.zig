const std = @import("std");
const stdout = std.fs.File.stdout();
const print = std.debug.print;

const Base64 = struct {
    table: *const [64]u8,

    pub fn init() Base64 {
        return Base64{
            .table = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/",
        };
    }

    fn charAt(self: Base64, index: u8) u8 {
        return self.table[index];
    }

    fn charIndex(self: Base64, char: u8) u8 {
        if (char == '=')
            return 64; // Padding character

        var i: u8 = 0;
        var index: u8 = 0;

        while (i < 64) : (i += 1) {
            if (self.charAt(i) == char)
                break;
            index += 1;
        }

        return index;
    }
};

pub fn main() !void {
    const base64 = Base64.init();

    const char: u8 = 'T';
    const index = base64.charIndex(char);
    print("Character: {}, Index: {}\n", .{ char, index });

    const idx: u8 = 19;
    const character = base64.charAt(idx);
    print("Index: {}, Character: {}\n", .{ idx, character });
}
