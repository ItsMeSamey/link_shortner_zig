const std = @import("std");
const builtin = @import("builtin");
const native_endianess = builtin.cpu.arch.endian();

const ModificationDataStruct = struct {
  /// The key (the shortened url location)
  key: []const u8,

  /// The value (the destination url)
  deathat: i64,
  dest: []const u8,

  /// The type of modification
  type: OperationType,

  const OperationType = u1;
  const Operation = enum(OperationType) {
    add = 0,
    delete = 1,
  };

  fn writeTo(self: *const @This(), writer: std.io.AnyWriter) !void {
    try writer.writeAll(&[_]u8{if (self.type == .add) '+' else '-'});
    try writer.writeAll(std.mem.toBytes(self.deathat));
    try writer.writeAll(self.key);
    try writer.writeAll(&[_]u8{'\x00'});
    try writer.writeAll(self.dest);
    try writer.writeAll(&[_]u8{'\n'});
  }
};

const ModificationDataOpaque = opaque {
  fn copyAndIncrement(ptr: *[*]u8, bytes: []const u8) void {
    @memcpy(ptr.*[0..bytes.len], bytes);
    ptr.* = ptr.*[bytes.len..];
  }

  pub fn init(allocator: std.mem.Allocator, data: ModificationDataStruct) !*@This() {
    const memory = try allocator.alignedAlloc(u8, 8, @sizeOf(i64) + @sizeOf(u16) + data.key.len + @sizeOf(u16) + data.dest.len);
    var ptr: [*]u8 = memory.ptr;

    copyAndIncrement(&ptr, std.mem.toBytes(data.deathat));
    copyAndIncrement(&ptr, &std.mem.toBytes(@as(u16, @intCast(data.key.len))));
    copyAndIncrement(&ptr, &std.mem.toBytes(@as(u16, @intCast(data.dest.len))));
    copyAndIncrement(&ptr, data.key);
    copyAndIncrement(&ptr, data.dest);

    return @ptrFromInt(@intFromPtr(ptr) | @as(usize, @intFromEnum(data.type)));
  }

  pub fn compoonents(self: *@This()) ModificationDataStruct {
    const ptr: [*]u8 = @ptrFromInt(@intFromPtr(self) & ~@as(usize, 0b1));

    const deathat: i64 = std.mem.readInt(i64, ptr[0..@sizeOf(i64)], native_endianess);
    ptr += @sizeOf(i64);
    const keyLen = std.mem.readInt(u16, ptr[@sizeOf(u16)..], native_endianess);
    ptr += @sizeOf(u16);
    const destLen = std.mem.readInt(u16, ptr[@sizeOf(u16)..], native_endianess);
    ptr += @sizeOf(u16);
    const key = ptr[0..keyLen];
    ptr += keyLen;
    const dest = ptr[0..destLen];
    ptr += destLen;

    return .{
      .key = key,
      .deathat = deathat,
      .dest = dest,
      .type = @enumFromInt(@as(ModificationDataStruct.OperationType, @intCast(@intFromPtr(self) & 1))),
    };
  }

  fn getMemory(self: *@This()) []align(8) u8 {
    const ptr: [*]u8 = @ptrFromInt(@intFromPtr(self) & ~@as(usize, 0b1));

    ptr += @sizeOf(i64);
    const keyLen = std.mem.readInt(u16, ptr[@sizeOf(u16)..], native_endianess);
    ptr += @sizeOf(u16);
    const destLen = std.mem.readInt(u16, ptr[@sizeOf(u16)..], native_endianess);
    ptr += @sizeOf(u16);

    return @alignCast(ptr[0..@sizeOf(i64) + @sizeOf(u16) + keyLen + @sizeOf(u16) + destLen]);
  }

  pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
    allocator.free(self.getMemory());
  }

  fn writeTo(self: *const @This(), writer: std.io.AnyWriter) !void {
    try self.compoonents().writeTo(writer);
  }
};

pub fn Modifications(T: type, Size: u16) type {
  return struct {
    const ListType = @import("staticCircularOverwritingList.zig").GetStaticCircularOverwritingList(Size, *ModificationDataOpaque);

    startIndex: usize = 0,
    modifications: ListType = .{},
    flushedTillIndex: usize = 0,

    pub const differenceLimit = Size;

    fn getAllocator(self: *@This()) std.mem.Allocator {
      return @field(@as(*T, @fieldParentPtr("modifications", self)), "allocator");
    }

    fn append(self: *@This(), data: ModificationDataOpaque) !void {
      const old = self.modifications.push(try ModificationDataOpaque.init(self.getAllocator(), data));
      if (old) |val| {
        val.deinit(self.getAllocator());
        self.startIndex += 1;
      }
    }

    pub fn add(self: *@This(), key: []const u8, deathat: i64, dest: []const u8) !void {
      try self.append(.{
        .key = key,
        .deathat = deathat,
        .dest = dest,
        .type = .add,
      });
    }

    pub fn delete(self: *@This(), key: []const u8, deathat: i64, dest: []const u8) !void {
      try self.append(.{
        .key = key,
        .deathat = deathat,
        .dest = dest,
        .type = .delete,
      });
    }

    pub fn flush(self: *@This(), writer: std.io.Writer) !void {
      if (self.flushedTillIndex == self.startIndex) return;
      var iterator = self.modifications.getIteratorSkip(self.flushedTillIndex - self.startIndex);
      while (iterator.next()) |mod| {
        try mod.writeTo(writer);
        self.flushedCount += 1;
      }
    }
  };
}

test {
  std.testing.refAllDeclsRecursive(@This());
}

