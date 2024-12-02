//! A hash map that stores redirection entries
const std = @import("std");

modificationIndex: u64 = 0,
modification: CircularOverwritingList = .{},
map: Map,

const ReidrectionMap = @This();

pub const TimestampType = i64;
pub const ModificationWithTimestamp = struct {
  index: u64,
  modification: Modification,
  
  const Modification = union(enum) {
    add: Key,
    remove: Key,
  };
};

pub const CircularOverwritingList = @import("staticCircularOverwritingList.zig").GetStaticCircularOverwritingList(1024, ModificationWithTimestamp);

pub const Map = std.HashMap(Key, void, MapContext, std.hash_map.default_max_load_percentage);

// The value struct with redirection and timeout
pub const Key = struct {
  // location string followed by the dest string
  data: [*] const u8,
  // Time (in seconds) after which an entry must die
  deathat: TimestampType,
  // Length of the location string
  keyLen: u16,
  // Length of the dest string
  valLen: u16,

  pub fn location(self: *const @This()) []const u8 {
    return self.data[0..self.keyLen];
  }
  pub fn dest(self: *const @This()) []const u8 {
    return self.data[self.keyLen..][0..self.valLen];
  }
  pub fn dataSlice(self: *const @This()) []const u8 {
    return self.data[0..@as(usize, self.keyLen) + @as(usize, self.valLen)];
  }

  pub fn init(allocator: std.mem.Allocator, loc: []const u8, dst: []const u8, deathat: TimestampType) !Key {
    const data = try allocator.alloc(u8, loc.len + dst.len);
    @memcpy(data[0..loc.len], loc);
    @memcpy(data[loc.len..], dst);
    return .{
      .data = data.ptr,
      .deathat = deathat,
      .keyLen = @intCast(loc.len),
      .valLen = @intCast(dst.len),
    };
  }
};

const MapContext = struct {
  pub fn hash(_: @This(), key: Key) u64 {
    var retval: u64 = 0;
    for (0.., key.location()) |i, c| {
      retval = (retval << @intCast(i&7)) ^ (retval >> @intCast(32 ^ (i&31)));
      retval ^= c;
    }
    return retval;
  }
  pub fn eql(_: @This(), l: Key, r: Key) bool {
    var a = l.location();
    var b = r.location();
    if (true) return std.mem.eql(u8, a, b);
    if (a.len != b.len) return false;

    if (a.len <= 16) {
      if (a.len < 4) {
        const x = (a[0] ^ b[0]) | (a[a.len - 1] ^ b[a.len - 1]) | (a[a.len / 2] ^ b[a.len / 2]);
        return x == 0;
      }
      var x: u32 = 0;
      for ([_]usize{ 0, a.len - 4, (a.len / 8) * 4, a.len - 4 - ((a.len / 8) * 4) }) |n| {
        x |= @as(u32, @bitCast(a[n..][0..4].*)) ^ @as(u32, @bitCast(b[n..][0..4].*));
      }
      return x == 0;
    }

    const Scan = if (std.simd.suggestVectorLength(u8)) |vec_size| struct {
      pub const size = vec_size;
      pub const Chunk = @Vector(size, u8);
      pub inline fn isNotEqual(chunk_a: Chunk, chunk_b: Chunk) bool {
        return @reduce(.Or, chunk_a != chunk_b);
      }
    } else struct {
      pub const size = @sizeOf(usize);
      pub const Chunk = usize;
      pub inline fn isNotEqual(chunk_a: Chunk, chunk_b: Chunk) bool {
        return chunk_a != chunk_b;
      }
    };
    inline for (1..6) |s| {
      const n = 16 << s;
      if (n <= Scan.size and a.len <= n) {
        const V = @Vector(n / 2, u8);
        var x = @as(V, a[0 .. n / 2].*) ^ @as(V, b[0 .. n / 2].*);
        x |= @as(V, a[a.len - n / 2 ..][0 .. n / 2].*) ^ @as(V, b[a.len - n / 2 ..][0 .. n / 2].*);
        const zero: V = @splat(0);
        return !@reduce(.Or, x != zero);
      }
    }
    for (0..(a.len - 1) / Scan.size) |i| {
      const a_chunk: Scan.Chunk = @bitCast(a[i * Scan.size ..][0..Scan.size].*);
      const b_chunk: Scan.Chunk = @bitCast(b[i * Scan.size ..][0..Scan.size].*);
      if (Scan.isNotEqual(a_chunk, b_chunk)) return false;
    }

    const last_a_chunk: Scan.Chunk = @bitCast(a[a.len - Scan.size ..][0..Scan.size].*);
    const last_b_chunk: Scan.Chunk = @bitCast(b[a.len - Scan.size ..][0..Scan.size].*);
    return !Scan.isNotEqual(last_a_chunk, last_b_chunk);
  }
};


pub fn init(allocator: std.mem.Allocator) ReidrectionMap {
  return .{
    .map = Map.init(allocator),
  };
}

pub fn add(self: *ReidrectionMap, location: []const u8, dest: []const u8, deathat: TimestampType) !void {
  const k = try Key.init(self.map.allocator, location, dest, deathat);
  const removed = self.modification.push(.{ .index = self.modificationIndex, .modification = .{ .add = k } });
  self.modificationIndex += 1;

  if (removed) |r| {
    switch (r.modification) {
      .remove => |v| self.map.allocator.free(v.dataSlice()),
      else => {},
    }
  }

  return self.map.put(k, {});
}

pub fn lookup(self: *ReidrectionMap, location: []const u8) ?*Key {
  return self.map.getKeyPtr(.{ .data = location.ptr, .deathat = undefined, .keyLen = @intCast(location.len), .valLen = undefined });
}

pub fn remove(self: *ReidrectionMap, location: []const u8) bool {
  if (self.map.getKeyPtr(.{ .data = location.ptr, .deathat = undefined, .keyLen = @intCast(location.len), .valLen = undefined })) |kptr| {
    const removed = self.modification.push(.{ .index = self.modificationIndex, .modification = .{ .add = kptr.* } });
    self.modificationIndex += 1;
    if (removed) |r| {
      switch (r.modification) {
        .remove => |v| self.map.allocator.free(v.dataSlice()),
        else => {},
      }
    }

    self.map.allocator.free(kptr.dataSlice());
    self.map.removeByPtr(kptr);
    return true;
  }

  return false;
}

pub fn deinit(self: *ReidrectionMap) void {
  for (self.map.keys()) |key| self.map.allocator.free(key);
  self.map.deinit();
}

