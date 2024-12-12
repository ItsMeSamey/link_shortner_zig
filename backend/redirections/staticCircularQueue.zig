//! a circular queue like data structure, but we overwrite the oldest entry instead of expanding
const std = @import("std");

pub fn GetStaticCircularOverwritingList(comptime usizeCapacity: usize, comptime T: type) type {
  const capacityType = switch (std.math.log2_int_ceil(usize, usizeCapacity)) {
    0 => @compileError("Capacity must be atleast 2"),
    1...7 => u8,
    8...15 => u16,
    16...31 => u32,
    32...63 => u64,
    else => @compileError(std.fmt.comptimePrint("Invalid capacity, {d} is too large", .{usizeCapacity})),
  };

  const capacity: capacityType = @intCast(usizeCapacity);

  return struct {
    _buf: [capacity]T = undefined,
    // One after the last inserted entry, but is never out of bounds due to wraparound
    _end: capacityType = 0,
    _full: bool = false,

    const Self = @This();

    pub fn count(self: *Self) usize {
      return if (!self.isFull()) self._end else capacity;
    }

    pub fn isFull(self: *Self) bool {
      return self._full;
    }

    pub fn isEmpty(self: *Self) bool {
      return !self._full and self._end == 0;
    }

    pub fn getOldest(self: *Self) ?*T {
      if (self.isEmpty()) return null;
      return &self._buf[if (!self.isFull()) 0 else self._end];
    }

    pub fn getLatest(self: *Self) ?*T {
      if (self.isEmpty()) return null;
      return &self._buf[(if (self._end == 0) capacity else self._end) - 1];
    }

    pub fn push(self: *Self, value: T) ?T {
      const retval = if (self.isFull()) self._buf[self._end] else null;
      self._buf[self._end] = value;
      self._end += 1;
      if (self._end == capacity) {
        self._full = true;
        self._end = 0;
      }
      return retval;
    }

    pub const Iterator = struct {
      list: *const Self,
      index: capacityType,
      finished: bool = false,

      pub fn next(self: *@This()) ?*T {
        if (self.finished) return null;

        const retval = &self.list._buf[self.index];

        self.index += 1;
        if (self.index == capacity) self.index = 0;
        if (self.index == self.list._end) self.finished = true;

        return retval;
      }
    };

    pub fn nilIterator() Iterator {
      return .{ .list = undefined, .index = undefined, .finished = true };
    }

    pub fn getBeginningIterator(self: *Self) Iterator {
      if (self.isEmpty()) return self.nilIterator();
      return .{ .list = self, .index = if (self.isFull()) self._end else 0 };
    }

    pub fn getIteratorAfter(self: *Self, skipCount: usize) Iterator {
      if (self.isEmpty() or skipCount >= capacity or (!self.isFull() and skipCount >= self._end)) return self.nilIterator();
      if (!self.isFull()) return .{ .list = self, .index = skipCount };
      const index = skipCount + self._end;
      return .{
        .list = self,
        .index = if (index >= capacity) index - capacity else index,
      };
    }
  };
}

test {
  const StaticCircularOverwritingList = GetStaticCircularOverwritingList(8, u8);
  var list = StaticCircularOverwritingList{};

  try std.testing.expectEqual(true, list.isEmpty());
  try std.testing.expectEqual(false, list.isFull());

  try std.testing.expectEqual(null, list.getOldest());
  try std.testing.expectEqual(null, list.getLatest());

  try std.testing.expectEqual(null, list.push(0));
  try std.testing.expectEqual(null, list.push(1));
  try std.testing.expectEqual(null, list.push(2));
  try std.testing.expectEqual(null, list.push(3));

  try std.testing.expectEqual(false, list.isEmpty());
  try std.testing.expectEqual(false, list.isFull());

  try std.testing.expectEqual(0, list.getOldest().?.*);
  try std.testing.expectEqual(3, list.getLatest().?.*);

  try std.testing.expectEqual(null, list.push(4));
  try std.testing.expectEqual(null, list.push(5));
  try std.testing.expectEqual(null, list.push(6));
  try std.testing.expectEqual(null, list.push(7));

  try std.testing.expectEqual(false, list.isEmpty());
  try std.testing.expectEqual(true, list.isFull());

  try std.testing.expectEqual(0, list.getOldest().?.*);
  try std.testing.expectEqual(7, list.getLatest().?.*);

  try std.testing.expectEqual(0, list.push(8));
  try std.testing.expectEqual(1, list.push(9));
  try std.testing.expectEqual(2, list.push(10));
  try std.testing.expectEqual(3, list.push(11));

  try std.testing.expectEqual(false, list.isEmpty());
  try std.testing.expectEqual(true, list.isFull());

  try std.testing.expectEqual(4 , list.getOldest().?.*);
  try std.testing.expectEqual(11, list.getLatest().?.*);
}

test {
  std.testing.refAllDeclsRecursive(@This());
}

