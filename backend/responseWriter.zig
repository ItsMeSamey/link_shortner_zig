test { std.testing.refAllDeclsRecursive( *const @This()); }
const std = @import("std");
const ReidrectionMap = @import("redirectionMap.zig");


writer: std.io.AnyWriter,

pub fn BufferedWriter(comptime buffer_size: usize, comptime WriterType: type) type {
  return struct {
    unbuffered_writer: WriterType,
    buf: [buffer_size]u8 = undefined,
    end: usize = 0,

    pub const Writer = std.io.Writer(*Self, Error, write);
    pub const Error = WriterType.Error;

    const Self = @This();

    pub fn flush(self: *Self) !void {
      try std.fmt.format(self.unbuffered_writer, "{x}\r\n{s}\r\n", .{ self.end, self.buf[0..self.end] });
      self.end = 0;
    }

    pub fn genericWriter(self: *Self) Writer {
      return .{ .context = self };
    }

    pub fn write(self: *Self, bytes: []const u8) Error!usize {
      if (self.end + bytes.len > self.buf.len) {
        try self.flush();
        if (bytes.len > self.buf.len)
          return self.unbuffered_writer.write(bytes);
      }

      const new_end = self.end + bytes.len;
      @memcpy(self.buf[self.end..new_end], bytes);
      self.end = new_end;
      return bytes.len;
    }

    pub fn init(unbuffered_writer: WriterType) !Self {
      try std.fmt.format(unbuffered_writer, "HTTP/1.1 200\r\nAccess-Control-Allow-Origin:*\r\nTransfer-Encoding:chunked\r\n\r\n", .{});
      return .{ .unbuffered_writer = unbuffered_writer };
    }

    pub fn deinit(self: *Self) !void {
      try self.flush();
      try std.fmt.format(self.unbuffered_writer, "0\r\n\r\n", .{});
    }
  };
}

pub fn writeRedirection(self: *const @This(), redirection: []const u8) !void {
  try std.fmt.format(self.writer, "HTTP/1.1 302\r\nAccess-Control-Allow-Origin:*\r\nConnection:close\r\nLocation:{s}\r\n\r\n", .{ redirection });
}

pub fn writeError(self: *const @This(), code: u16) !void {
  try std.fmt.format(self.writer, "HTTP/1.1 {d}\r\nAccess-Control-Allow-Origin:*\r\nConnection:close\r\n\r\n", .{ code });
}

pub fn writeString(self: *const @This(), data: []const u8 ) !void {
  try std.fmt.format(self.writer, "HTTP/1.1 200\r\nAccess-Control-Allow-Origin:*\r\nContent-Length:{d}\r\n\r\n{s}", .{ data.len, data });
}

pub fn writeMapIterator(self: *const @This(), iter: *ReidrectionMap.Map.Iterator, count: u32) !void {
  var bufferedWriter = try BufferedWriter(1 << 14, @TypeOf(self.writer)).init(self.writer);
  const anyBufferedWriter = bufferedWriter.genericWriter().any();
  var done: u32 = 0;

  while (iter.next()) |val| {
    try std.fmt.format(anyBufferedWriter, "{d}\x00{s}\x00{s}\n", .{val.key_ptr.location(), val.key_ptr.dest()});

    done += 1;
    if (done == count) break;
  }

  try bufferedWriter.deinit();
}

pub fn writeMapModificationIterator(self: *const @This(), iter: *@import("redirectionMap.zig").CircularOverwritingList.Iterator) !void {
  var bufferedWriter = try BufferedWriter(1 << 14, @TypeOf(self.writer)).init(self.writer);
  const anyBufferedWriter = bufferedWriter.genericWriter().any();

  while (iter.next()) |val| {
    switch (val.modification) {
      .add =>    |v| {try std.fmt.format(anyBufferedWriter, "+{d}\x00{d}\x00{s}\x00{s}\n", .{val.timestamp, v.deathat, v.location(), v.dest()});},
      .remove => |v| {try std.fmt.format(anyBufferedWriter, "-{d}\x00{d}\x00{s}\x00{s}\n", .{val.timestamp, v.deathat, v.location(), v.dest()});},
    }
  }

  try bufferedWriter.deinit();
}

