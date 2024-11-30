const std = @import("std");
const ReidrectionMap = @import("../redirections/redirectionMap.zig");

const Self = @This();
const Header = struct {
  k: []const u8,
  v: []const u8,
};

const FormatString = "HTTP/1.1 {d}\r\nAccess-Control-Allow-Origin:*\r\n";

writer: std.io.AnyWriter,

const ChunkedWriterType = GetChunkWriter(1 << 14, std.io.AnyWriter);
pub fn GetChunkWriter(comptime bufLen: usize, comptime WriterType: type) type {
  return struct {
    unbuffered: WriterType,
    buf: [bufLen]u8 = undefined,
    end: usize = 0,

    pub const Error = WriterType.Error;
    const Writer = std.io.Writer(*@This(), Error, write);

    fn flush(self: *@This()) !void {
      try std.fmt.format(self.unbuffered, "{x}\r\n{s}\r\n", .{ self.end, self.buf[0..self.end] });
      self.end = 0;
    }
    pub fn finish(self: *@This()) !void {
      try self.flush();
      try std.fmt.format(self.unbuffered, "0\r\n\r\n", .{});
    }

    pub fn writer(self: *@This()) Writer {
      return .{ .context = self };
    }

    pub fn write(self: *@This(), bytes: []const u8) Error!usize {
      if (self.end + bytes.len > bufLen) {
        try std.fmt.format(self.unbuffered, "{x}\r\n{s}{s}\r\n", .{ self.end + bytes.len, self.buf[0..self.end], bytes });
        self.end = 0;
      } else {
        @memcpy(self.buf[self.end..][0..bytes.len], bytes);
        self.end += bytes.len;
      }
      return bytes.len;
    }

    pub fn init(unbuffered: WriterType) !@This() {
      try std.fmt.format(unbuffered, FormatString ++ "Transfer-Encoding:chunked\r\n\r\n", .{ 200 });
      return .{ .unbuffered = unbuffered };
    }
  };
}

pub fn writeRedirection(self: *const Self, redirection: []const u8) !void {
  try std.fmt.format(self.writer, FormatString ++ "Connection:close\r\nLocation:{s}\r\n\r\n", .{ 302, redirection });
}

pub fn writeError(self: *const Self, comptime code: u16) !void {
  const trace = @errorReturnTrace();
  if (trace) |t| {
    try t.format("Error {}", .{}, std.io.getStdOut());
  }
  try std.fmt.format(self.writer, FormatString ++ "Connection:close\r\n\r\n", .{ code });
}

pub fn writeString(self: *const Self, data: []const u8 ) !void {
  try std.fmt.format(self.writer, FormatString ++ "Content-Length:{d}\r\n\r\n{s}", .{200, data.len, data});
}

pub fn writeMapIterator(self: *const Self, iter: *ReidrectionMap.Map.Iterator, count: u32) !void {
  var chunkWriter = try ChunkedWriterType.init(self.writer);
  var genericChunkWriter = chunkWriter.writer();
  const anyChunkWriter = genericChunkWriter.any();

  var done: u32 = 0;
  while (iter.next()) |val| {
    try std.fmt.format(anyChunkWriter, "{d}\x00{s}\x00{s}\n", .{val.key_ptr.deathat, val.key_ptr.location(), val.key_ptr.dest()});
    done += 1;
    if (done == count) break;
  }

  try std.fmt.format(anyChunkWriter, "{x}", .{ iter.index });
  try chunkWriter.finish();
}

pub fn writeMapModificationIterator(self: *const @This(), iter: *ReidrectionMap.CircularOverwritingList.Iterator) !void {
  var chunkWriter = try ChunkedWriterType.init(self.writer);
  var genericChunkWriter = chunkWriter.writer();
  const anyChunkWriter = genericChunkWriter.any();

  while (iter.next()) |val| {
    switch (val.modification) {
      .add =>    |v| {try std.fmt.format(anyChunkWriter, "+{d}\x00{d}\x00{s}\x00{s}\n", .{val.index, v.deathat, v.location(), v.dest()});},
      .remove => |v| {try std.fmt.format(anyChunkWriter, "-{d}\x00{d}\x00{s}\x00{s}\n", .{val.index, v.deathat, v.location(), v.dest()});},
    }
  }

  try std.fmt.format(anyChunkWriter, "{x}", .{ ReidrectionMap.modificationIndex });
  try chunkWriter.finish();
}

