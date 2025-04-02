const std = @import("std");
const stdout = std.io.getStdOut().writer();
const stdin = std.io.getStdIn().reader();

const c = @cImport({
    @cInclude("termios.h");
    @cInclude("unistd.h");
    @cInclude("stdlib.h");
    @cInclude("sys/ioctl.h");
    @cInclude("unistd.h");
});

var orig_termios: c.termios = undefined;

pub fn enableRawMode() void {
    _ = c.tcgetattr(c.STDIN_FILENO, &orig_termios);
    _ = c.atexit(disableRawMode);

    var raw: c.termios = undefined;
    raw.c_lflag &= ~(@as(u8, c.ECHO) | @as(u8, c.ICANON));

    _ = c.tcsetattr(c.STDIN_FILENO, c.TCSAFLUSH, &raw);
}

pub fn disableRawMode() callconv(.C) void {
    _ = c.tcsetattr(c.STDIN_FILENO, c.TCSAFLUSH, &orig_termios);
}

const Colors = enum {
    ANSI_COLOR_RED,
    ANSI_COLOR_GREEN,
    ANSI_COLOR_YELLOW,
    ANSI_COLOR_BLUE,
    ANSI_COLOR_MAGENTA,
    ANSI_COLOR_CYAN,
    ANSI_COLOR_RESET,
};
const COLORS_LIST = [_][]const u8{ "\x1b[31m", "\x1b[32m", "\x1b[33m", "\x1b[34m", "\x1b[35m", "\x1b[36m", "\x1b[0m" };

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const rand = std.crypto.random;

    var dir = try std.fs.cwd().openDir("files/", std.fs.Dir.OpenDirOptions{ .iterate = true });
    defer dir.close();
    var file_list = std.ArrayList([]const u8).init(allocator);
    defer {
        for (file_list.items) |item| {
            allocator.free(item);
        }
        file_list.deinit();
    }

    var dir_iter = dir.iterate();
    while (try dir_iter.next()) |dir_content| {
        const dupe = try allocator.dupe(u8, dir_content.name);
        try file_list.append(dupe);
    }

    const rand_num = rand.uintLessThan(u64, file_list.items.len);
    const file_name = try std.fmt.allocPrint(allocator, "files/{s}", .{file_list.items[rand_num]});
    defer allocator.free(file_name);

    const buf_orignal = try std.fs.cwd().readFileAlloc(allocator, file_name, 1024 * 8);
    defer allocator.free(buf_orignal);

    var w: c.winsize = undefined;
    _ = c.ioctl(c.STDOUT_FILENO, c.TIOCGWINSZ, &w);

    var buf_list = std.ArrayList(u8).init(allocator);
    defer buf_list.deinit();

    // create a new buffer with max height given by the height of the terminal
    var buf_iter = std.mem.splitAny(u8, buf_orignal, "\n");
    var k:i32 = 0;
    while (buf_iter.next()) |line| : (k += 1) {
        try buf_list.appendSlice(line);
        try buf_list.appendSlice("\n");
        if (k > w.ws_row-3) {
            break;
        }
    }

    const buf = buf_list.items;

    try stdout.print("{s}{s}", .{ COLORS_LIST[@intFromEnum(Colors.ANSI_COLOR_CYAN)], buf });
    var newline = true;
    var i: usize = 0;

    const count = std.mem.count(u8, buf, "\n");
    for (0..count) |_| {
        // Move cursor to first line
        _ = try stdout.write("\x1b[A");
    }
    _ = try stdout.write("\r");
    enableRawMode();
    while (true) {
        if (i < buf.len and buf[i] == 13) {
            i += 1;
            continue;
        }
        if (i < buf.len and buf[i] == 10) {
            newline = true;
            try stdout.print("\n\r", .{});
            i += 1;
            continue;
        }
        if (newline) {
            if (i >= buf.len) {
                break;
            }
            if (buf[i] == 32) {
                try stdout.print("{s}{c}", .{ COLORS_LIST[@intFromEnum(Colors.ANSI_COLOR_GREEN)], buf[i] });
                i += 1;
                continue;
            }
        }
        newline = false;
        const read = try stdin.readByte();

        if (read == 3) {
            std.process.exit(0);
        } else if (read == 127 and i > 0) {
            i -= 1;
            _ = try stdout.write("\x1b[D");
            continue;
        }

        if (read == buf[i]) {
            try stdout.print("{s}{c}", .{ COLORS_LIST[@intFromEnum(Colors.ANSI_COLOR_GREEN)], buf[i] });
        } else {
            try stdout.print("{s}{c}", .{ COLORS_LIST[@intFromEnum(Colors.ANSI_COLOR_RED)], buf[i] });
        }

        i += 1;
        if (i >= buf.len) {
            break;
        }
    }
}
