test { std.testing.refAllDeclsRecursive( *const @This()); }
const std = @import("std");
const ReidrectionMap = @import("redirectionMap.zig");

writer: std.io.AnyWriter,

pub fn writeRedirection(self: *const @This(), redirection: []const u8) !void {
  try std.fmt.format(self.writer, "HTTP/1.1 302\r\nConnection:close\r\nLocation:{s}\r\n\r\n", .{ redirection });
}

pub fn writeError(self: *const @This(), code: u16) !void {
  try std.fmt.format(self.writer, "HTTP/1.1 {d}\r\n\r\nConnection:close\r\n\r\n", .{ code });
}

pub fn writeString(self: *const @This(), data: []const u8 ) !void {
  try std.fmt.format(self.writer, "HTTP/1.1 200\r\nContent-Length:{d}\r\n\r\n{s}", .{ data.len, data });
}

pub fn writeMapIterator(self: *const @This(), iter: *ReidrectionMap.Map.Iterator, count: u32) !void {
  try std.fmt.format(self.writer, "HTTP/1.1 200\r\nTransfer-Encoding:chunked\r\n\r\n", .{});
  var done: u32 = 0;

  while (iter.next()) |val| {
    // 1 for \0 separator, 1 for the extra \n
    const len = @as(u32, val.key_ptr.keyLen) + 1 + @as(u32, val.key_ptr.valLen) + 1 ;
    try std.fmt.format(self.writer, "{x}\r\n{s}\x00{s}\n\r\n", .{len, val.key_ptr.location(), val.key_ptr.dest()});

    done += 1;
    if (done == count) break;
  }

  var buf: [12]u8 = undefined;
  const len = std.fmt.formatIntBuf(buf[0..], iter.index, 10, .lower, .{});
  try std.fmt.format(self.writer, "{x}\r\n{s}\r\n", .{len, buf[0..len]});

  try std.fmt.format(self.writer, "0\r\n\r\n", .{});
}

