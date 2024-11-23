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
    buf: [capacity]T = undefined,
    end: capacityType = 0,
    isFull: bool = false,

    const Self = @This();

    pub fn getOldest(self: *Self) ?*T {
      if (self.end == 0) {
        if (self.isFull) return null;
        return &self.buf[capacity-1];
      }
      return &self.buf[self.end-1];
    }

    pub fn getNewest(self: *Self) ?*T {
      if (self.end == 0 and !self.isFull) return null;
      return &self.buf[self.end];
    }
    
    pub fn push(self: *Self, value: T) ?T {
      var retval: ?T = null;
      self.end += 1;
      if (self.end == capacity) self.isFull = true;
      if (self.isFull) retval = self.buf[self.end];
      self.buf[self.end] = value;

      return retval;
    }

    pub const Iterator = struct {
      list: *const Self,
      index: capacityType,
      finished: bool = false,

      pub fn next(self: *@This()) ?T {
        if (self.finished) return null;
        const retval: ?T = self.list.buf[self.index];

        if (self.index == self.list.end) {
          self.finished = true;
          return retval;
        }

        if (self.index == capacity-1) self.index = 0;
        return retval;
      }
    };

    pub fn getIteratorAfter(self: *Self, context: anytype, compareFn: fn (ctx: @TypeOf(context), a: T) std.math.Order) ?Iterator {
      var beginIndex: capacityType = undefined;
      if (self.isFull) {
        if (std.sort.binarySearch(T, self.buf[0..self.end+1], context, compareFn)) |idx| {
          beginIndex = @intCast(idx);
        } else {
          if (std.sort.binarySearch(T, self.buf[self.end+1..], context, compareFn)) |idx| {
            beginIndex = @intCast(idx + self.end + 1);
          } else {
            return null;
          }
        }
      } else {
        beginIndex = @intCast(std.sort.binarySearch(T, self.buf[0..self.end+1], context, compareFn) orelse return null);
      }

      return .{
        .list = self,
        .index = beginIndex,
      };
    }
  };
}

