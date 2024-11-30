test { std.testing.refAllDeclsRecursive( *const @This()); }
const std = @import("std");
const ReidrectionMap = @import("redirectionMap.zig");

const Self = @This();
const Header = struct {
  k: []const u8,
  v: []const u8,
};

writer: std.io.AnyWriter,

const FormatString = "HTTP/1.1 {d}\r\nAccess-Control-Allow-Origin:*\r\n";

fn writeChunk(self: *const Self, chunk: []const u8) !void {
  return std.fmt.format(self.writer, "{x}\r\n{s}\r\n", .{ chunk.len, chunk });
}

pub fn ChunkWriter(comptime bufLen: usize, comptime WriterType: type) type {
  return struct {
    unbuffered: WriterType,
    buf: [bufLen]u8 = undefined,
    end: usize = 0,

    pub const Error = WriterType.Error;
    pub const Writer = std.io.Writer(*@This(), Error, write);

    fn flush(self: *@This()) !void {
      try std.fmt.format(self.unbuffered, "{x}\r\n{s}\r\n", .{ self.end, self.buf[0..self.end] });
      self.end = 0;
    }

    fn writer(self: *@This()) Writer {
      return .{ .context = self };
    }

    pub fn any(self: *@This()) std.io.AnyWriter {
      return self.writer().any();
    }

    fn write(self: *@This(), bytes: []const u8) Error!usize {
      if (self.end + bytes.len > self.buf.len) {
        try self.flush();
        if (bytes.len > self.buf.len)
          return self.unbuffered.write(bytes);
      }

      const nEnd = self.end + bytes.len;
      @memcpy(self.buf[self.end..nEnd], bytes);
      self.end = nEnd;
      return bytes.len;
    }

    pub fn init(unbuffered: WriterType) !@This() {
      try std.fmt.format(unbuffered, FormatString ++ "Transfer-Encoding:chunked\r\n\r\n", .{ 200 });
      return .{ .unbuffered = unbuffered };
    }

    pub fn finish(self: *@This()) !void {
      try self.flush();
      try std.fmt.format(self.unbuffered, "0\r\n\r\n", .{});
    }
  };
}

pub fn writeRedirection(self: *const Self, redirection: []const u8) !void {
  try std.fmt.format(self.writer, FormatString ++ "Connection:close\r\nLocation:{s}\r\n\r\n", .{ 302, redirection });
}

pub fn writeError(self: *const Self, comptime code: u16) !void {
  try std.fmt.format(self.writer, FormatString ++ "Connection:close\r\n\r\n", .{ code });
}

pub fn writeString(self: *const Self, data: []const u8 ) !void {
  try std.fmt.format(self.writer, FormatString ++ "Content-Length:{d}\r\n\r\n{s}", .{200, data.len, data});
}

pub fn writeMapIterator(self: *const Self, iter: *ReidrectionMap.Map.Iterator, count: u32) !void {
  var chunkWriter = try ChunkWriter(1 << 14, @TypeOf(self.writer)).init(self.writer);
  const anyChunkWriter = chunkWriter.any();
  var done: u32 = 0;

  while (iter.next()) |val| {
    try std.fmt.format(anyChunkWriter, "{d}\x00{s}\x00{s}\n", .{val.key_ptr.deathat, val.key_ptr.location(), val.key_ptr.dest()});

    done += 1;
    if (done == count) break;
  }

  try chunkWriter.finish();
}

pub fn writeMapModificationIterator(self: *const @This(), iter: *@import("redirectionMap.zig").CircularOverwritingList.Iterator) !void {
  var chunkWriter = try ChunkWriter(1 << 14, @TypeOf(self.writer)).init(self.writer);
  const anyChunkWriter = chunkWriter.any();

  while (iter.next()) |val| {
    switch (val.modification) {
      .add =>    |v| {try std.fmt.format(anyChunkWriter, "+{d}\x00{d}\x00{s}\x00{s}\n", .{val.index, v.deathat, v.location(), v.dest()});},
      .remove => |v| {try std.fmt.format(anyChunkWriter, "-{d}\x00{d}\x00{s}\x00{s}\n", .{val.index, v.deathat, v.location(), v.dest()});},
    }
  }

  try chunkWriter.finish();
}

