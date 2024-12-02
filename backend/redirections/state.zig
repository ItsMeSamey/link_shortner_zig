const std = @import("std");
const RedirectionMap = @import("redirectionMap.zig");

file: std.fs.File,
modificationIndex: u64,

const rmap: *RedirectionMap = &@import("../server/router.zig").rmap;

const BufferedWriterType = std.io.BufferedWriter(1 << 20, @TypeOf(std.fs));
const BufferedWriterStruct = struct {
  unbufferedConstructor: std.fs.File.Writer,
  unbuffered: std.io.AnyWriter,
  bufferedConstructor: BufferedWriterType,
  bufferedGeneric: BufferedWriterType.Writer,
  buffered: std.io.AnyWriter
};

fn getBufferedWriter(self: *@This()) BufferedWriterStruct {
  var retval: BufferedWriterStruct = undefined;
  retval.unbufferedConstructor = self.file.writer();
  retval.unbuffered = retval.unbufferedConstructor.any();
  retval.bufferedConstructor = .{ .unbuffered_writer = retval.unbuffered };
  retval.bufferedGeneric = retval.bufferedConstructor.writer();
  retval.buffered = retval.bufferedGeneric.any();
  return retval;
}

fn writeEntry(operation: u8, entry: *RedirectionMap.Key, writer: *BufferedWriterStruct) !void {
  try writer.buffered.writeAll(&[_]u8{operation});
  try writer.buffered.writeAll(&std.mem.asBytes(&entry.deathat));
  try std.fmt.format(writer.buffered, "{s}\x00{s}\n", .{entry.location(), entry.dest()});
}

pub fn saveMap(self: *@This()) !void {
  var writer = getBufferedWriter(self);
  defer writer.bufferedConstructor.flush() catch |e| {
    std.log.err("Error: flushing failed {}", .{ @errorName(e) });
    if (@errorReturnTrace()) |trace| std.debug.dumpStackTrace(trace.*) else std.log.info("No Stack Trace: {}", .{ @src() });
  };

  // Write the modification index
  try self.file.writeAll(&[_]u8{ rmap.modificationIndex });

  var iter = rmap.map.iterator();
  while (iter.next()) |entry| {
    try writeEntry(self, '+', entry.key_ptr, &writer);
  }
}

pub fn loadMap(self: *@This()) !void {
  // 1 MB buffer, we expect every line (/ entry) to be smaller than 1 mb
  var buf: [1 << 20]u8 = undefined;
  var start: u32 = 0;
  var till:  u32 = @intCast(try self.file.readAll(buf[0..]));

  if (till < 8) return error.InvalidFile;

  // The first 8 bytes are the modification index
  self.modificationIndex = @bitCast(buf[0..8]);
  start += 8;

  while (true) {
    // (1 for `+`/`-`) + (8 for deathat) + (1 for location) + (1 for \x00) + (`***://***.**`  atleast 12 for destination) + (1 for \n)
    while (till < start + (1 + 8 + 1 + 1 + 12 + 1)) {
      const op = buf[start];
      const deathat: i64 = @bitCast(buf[start+1..till][0..8]);
      var newStart = start + 9;

      var locationIterator = std.mem.splitScalar(u8, buf[newStart..till], '\x00');
      const location = locationIterator.first();
      newStart += location.len;
      if (newStart == till) break;
      newStart += 1;

      var destIterator = std.mem.splitScalar(u8, buf[newStart..till], '\n');
      const dest = destIterator.first();
      newStart += dest.len;
      if (newStart == till) break;
      newStart += 1;

      switch (op) {
        '+' => try rmap.add(location, dest, deathat),
        '-' => try rmap.remove(location),
        else => return error.InvalidOperation,
      }

      start = newStart;
    }

    if (till != buf.len) {
      if (start == till) break;
      return error.UnexpectedEndOfFile;
    }

    std.mem.copyForwards(u8, buf[0..], buf[start..till]);
    const prefixLen = buf[start..till].len;
    const n = self.file.readAll(buf[prefixLen..]);
    if (n == 0) {
      if (prefixLen != 0) return error.UnexpectedEndOfFile;
      break;
    }
    start = 0;
    till = @intCast(prefixLen + n);
  }
}

pub fn applyUpdates(self: *@This(), iter: *RedirectionMap.CircularOverwritingList.Iterator) !void {
  var writer = getBufferedWriter(self);
  defer writer.bufferedConstructor.flush() catch |e| {
    std.log.err("Error: flushing failed {}", .{ @errorName(e) });
    if (@errorReturnTrace()) |trace| std.debug.dumpStackTrace(trace.*) else std.log.info("No Stack Trace: {}", .{ @src() });
  };

  defer self.modificationIndex = iter.index;
  while (iter.next()) |entry| {
    switch (entry.modification) {
      .add =>    |*v| try writeEntry(self, '+', v, &writer),
      .remove => |*v| try writeEntry(self, '-', v, &writer),
    }
  }

  try self.file.seekTo(0);
  try self.file.writeAll(&[_]u8{ iter.index });
  try self.file.seekFromEnd(0);
}

pub fn lazyApplyUpdates(self: *@This()) !void {
  if (self.modificationIndex + rmap.modification.buf.len == rmap.modificationIndex) {
    try self.applyUpdates(rmap.modification.getBeginningIterator());
  }
}

