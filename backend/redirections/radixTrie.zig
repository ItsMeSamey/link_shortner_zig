//! An efficient radix trie implementation

const std = @import("std");
const builtin = @import("builtin");


// ##########################
// # - eql implementation - #
// ##########################

const eqlBytes_allowed = switch (builtin.zig_backend) {
  .stage2_spirv64, .stage2_riscv64 => false,
  else => true,
};
pub fn eql(comptime T: type, a: []const T, b: []const T) bool {
  if (@sizeOf(T) == 0) return true;
  if (!@inComptime() and std.meta.hasUniqueRepresentation(T) and eqlBytes_allowed) return eqlBytes(std.mem.sliceAsBytes(a), std.mem.sliceAsBytes(b));

  if (a.len != b.len) return false;
  for (a, b) |a_elem, b_elem| {
    if (a_elem != b_elem) return false;
  }
  return true;
}
fn eqlBytes(a: []const u8, b: []const u8) bool {
  comptime std.debug.assert(eqlBytes_allowed);

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

  const Scan = if (std.simd.suggestVectorLength(u8)) |vec_size|
    struct {
      pub const size = vec_size;
      pub const Chunk = @Vector(size, u8);
      pub inline fn isNotEqual(chunk_a: Chunk, chunk_b: Chunk) bool {
        return @reduce(.Or, chunk_a != chunk_b);
      }
    }
  else
    struct {
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

// ###################################
// # - character index translation - #
// ###################################

/// Total number of characters allowed in url.
const TotalCharacterCount = 85; // = CharacterToIndexMap.len = total number of allowed characters

test TotalCharacterCount {
  try std.testing.expectEqual(TotalCharacterCount, CharacterToIndexMap.len);
}

// -> Convert characters to and from reduced index form

/// tells if a character is allowed to be in a url
fn isCharacterAllowed(char: u8) bool {
  return switch (char) {
    '!', '$'...'&', '('...'[', ']', '_', 'a'...'z', '~' => true,
    else => false,
  };
}

/// Return true if the url is valid, otherwise returns false
pub fn isUrlValid(url: []const u8) bool {
  for (url) |val| {
    if (!isCharacterAllowed(val)) return false;
  }
  return true;
}

/// The value that is returned when the index is invalid
pub const InvalidIndex = 0xff;

/// An array of all the allowed characters soted in ascending order w.r.t their ascii values
pub const CharacterToIndexMap = blk: {
  var allC: []const u8 = &.{};
  for (0..255) |i| {
    const char: u8 = @intCast(i);
    if (isCharacterAllowed(char)) {
      allC = allC ++ &[_]u8{char};
    }
  }
  const len = allC.len;
  break :blk allC[0..len].*;
};

const CharacterStart = CharacterToIndexMap[0];
const CharacterEnd = CharacterToIndexMap[CharacterToIndexMap.len-1] + 1;

/// Map from indexed to Characters.
/// NOTE: IndexToCharacterMap[0] coresponsed to the first valid character not the character `\x00`
pub const IndexToCharacterMap: [CharacterEnd - CharacterStart]u8 = blk: {
  var retval = [1]u8{InvalidIndex} ** (CharacterEnd - CharacterStart);
  for (CharacterToIndexMap, 0..) |char, index| { retval[char - CharacterStart] = @intCast(index); }
  break :blk retval;
};

/// Returns true if the index provided is valid otherwise returns false
pub fn isValidIndex(index: u8) bool {
  return index < CharacterToIndexMap.len;
}

/// Convert index to ascii character
/// Assert that the index is valid.
/// To check index validity, use isValidIndex.
pub fn characterFromIndex(index: u8) u8 {
  std.debug.assert(isValidIndex(index));
  return CharacterToIndexMap[index];
}

/// Returns index from a character or return `InvalidIndex` if the character is invalid
pub fn indexFromCharacter(char: u8) u8 {
  if (char >= CharacterEnd or char < CharacterStart) return InvalidIndex;
  return IndexToCharacterMap[char - CharacterStart];
}

test "indexFromCharacter and characterFromIndex" {
  for (0..0xff + 1) |i| {
    const char: u8 = @intCast(i);
    const index = indexFromCharacter(char);
    if (index == InvalidIndex) continue;

    try std.testing.expectEqual(char, characterFromIndex(index));
  }
}

// ##################################################
// # - implementation of entry and value struct's - #
// ##################################################

/// set the post string and `strlen` of a struct, so we have to make only one allocation
/// Asserts that the string is of valid length
fn initPostStringStruct(comptime T: type, allocator: std.mem.Allocator, str: []const u8) !*T {
  const memory = try allocator.alignedAlloc(u8, @alignOf(T), @sizeOf(T) + str.len);
  const retval: *T = @alignCast(@ptrCast(memory[0..@sizeOf(T)]));
  @field(retval, "strlen") = @intCast(str.len);
  @memcpy(getPostString(retval), str);
  return retval;
}

/// get the post string of a struct
fn getPostString(ptr: anytype) []u8 {
  return @as([*]u8, @ptrCast(ptr))[@sizeOf(@typeInfo(@TypeOf(ptr)).pointer.child)..][0..@field(ptr, "strlen")];
}

fn freePostStringStruct(ptr: anytype, allocator: std.mem.Allocator) void {
  // Because the allocator.free cannot free crooked(length is not a multiple of aligenment) aligend allocated memory (afaik)
  const memory: [*]u8 = @ptrCast(ptr);
  const byteLen: usize = @sizeOf(@typeInfo(@TypeOf(ptr)).pointer.child) + @field(ptr, "strlen");
  allocator.rawFree(memory[0..byteLen], std.math.log2(@alignOf(Value)), @returnAddress());
}

/// The terminal Value Entry
const Value = packed struct {
  deathat: i64,
  strlen: u16,

  pub fn new(allocator: std.mem.Allocator, dest: []const u8, deathat: i64) !*Value {
    const retval = try initPostStringStruct(Value, allocator, dest);
    retval.deathat = deathat;
    return retval;
  }

  pub fn getString(self: *@This()) []u8 {
    return getPostString(self);
  }

  pub fn free(self: *Value, allocator: std.mem.Allocator) void {
    freePostStringStruct(self, allocator);
  }
};

const NodeEnum = enum {
  single_no_value,
  single_and_value,
  string_no_value,
  string_and_value,
};

const UnitedNode = union {
  opaqueptr: ?*anyopaque,
  single_no_value: ?*SingleNoValue,
  single_and_value: ?*SingleAndValue,
  string_no_value: ?*StringNoValue,
  string_and_value: ?*StringAndValue,
};

const TaggedUnitedNode = struct {
  array: *NodeArray,
  idx: u8,

  fn exists(self: *@This()) bool {
    return self.array.nodePointers[self.idx] != null;
  }

  fn getNodes(self: *@This()) *NodeArray {
    const node = self.array.nodePointers[self.idx];
    switch (self.array.nodeEnums[self.idx]) {
      .single_no_value  => return node.single_no_value.?.getNodes(),
      .single_and_value => return node.single_and_value.?.getNodes(),
      .string_no_value  => return node.string_no_value.?.getNodes(),
      .string_and_value => return node.string_and_value.?.getNodes(),
    }
  }

  fn freeSelf(self: *@This(), allocator: std.mem.Allocator) void {
    switch (self.array.nodeEnums[self.idx]) {
      .single_no_value  => allocator.destroy(self.node.single_no_value),
      .single_and_value => allocator.destroy(self.node.single_and_value),
      .string_no_value  => freePostStringStruct(self.node.string_no_value, allocator),
      .string_and_value => freePostStringStruct(self.node.string_and_value, allocator),
    }
  }

  fn freeChildren(self: *@This(), allocator: std.mem.Allocator) void {
    const nodes = self.getNodes();
    for (0..TotalCharacterCount) |i| {
      if (nodes.get(i)) |node| node.freeChildren(allocator);
    }
    self.freeSelf(allocator);
  }

  fn freeSelfAndChildren(self: *@This(), allocator: std.mem.Allocator) void {
    self.freeChildren(allocator);
    self.freeSelf(allocator);
  }

  fn getChildrenCount(self: *@This()) u8 {
    var count: u8 = 0;
    const nodes = self.getNodes();
    for (nodes.nodePointers) |node| {
      if (node.opaqueptr != null) count += 1;
    }
    return count;
  }
};

const NodeArray = struct {
  nodePointers: [TotalCharacterCount]*UnitedNode,
  nodeEnums: [TotalCharacterCount]NodeEnum,

  fn getUnsafe(self: *NodeArray, index: u8) TaggedUnitedNode {
    return .{
      .array = self,
      .idx = index,
    };
  }

  fn get(self: *NodeArray, index: u8) ?TaggedUnitedNode {
    const retval = self.getUnsafe(index);
    return if (retval.exists()) retval else null;
  }

  fn set(self: *NodeArray, index: u8, node: UnitedNode, tag: NodeEnum) void {
    self.nodePointers[index] = node;
    self.nodeEnums[index] = tag;
  }
};

const SingleNoValue = struct {
  nodes: NodeArray,

  fn getNodes(self: *SingleNoValue) *NodeArray {
    return &self.nodes;
  }
};

const SingleAndValue = struct {
  value: Value,
  underlying: SingleNoValue,

  fn getNodes(self: *@This()) *NodeArray {
    return self.underlying.getNodes();
  }
};

const StringNoValue = struct {
  underlying: SingleNoValue,
  strlen: u16,

  fn getNodes(self: *@This()) *NodeArray {
    return self.underlying.getNodes();
  }

  fn getString(self: *@This()) []u8 {
    return getPostString(self);
  }

  fn new(allocator: std.mem.Allocator, string: []const u8) !*@This() {
    const retval = try initPostStringStruct(@This(), allocator, string);
    retval.underlying.nodes.nodePointers = [1]?*UnitedNode{null} ** TotalCharacterCount;
    return retval;
  }
};

const StringAndValue = struct {
  underlying: SingleAndValue,
  strlen: u16,

  fn getNodes(self: *@This()) *NodeArray {
    return self.underlying.getNodes();
  }

  fn getString(self: *@This()) []u8 {
    return getPostString(self);
  }

  fn new(allocator: std.mem.Allocator, string: []const u8, value: ?*Value) !*@This() {
    const retval = try initPostStringStruct(@This(), allocator, string);
    retval.underlying.nodes.nodePointers = [1]?*UnitedNode{null} ** TotalCharacterCount;
    retval.underlying.value = value;
    return retval;
  }
};

test Value {
  const allocator = std.testing.allocator;

  const example = "https://example.com";
  inline for (0..255) |i| {
    const string = example ++ [1]u8{'!'} ** i;
    const v = try Value.new(allocator, string, @intCast(i));
    defer v.free(allocator);
    try std.testing.expectEqualStrings(string, v.getString());
    try std.testing.expectEqual(@as(i64, @intCast(i)), v.deathat);
  }
}

// ########################################
// # - implementation of the radix trie - #
// ########################################

const RadixTrie = struct {
  head: NodeArray,
  allocator: std.mem.Allocator,


  fn getFirstNonMatching(node: TaggedUnitedNode, key: []const u8) !TaggedUnitedNode {
    while (key.len > 0) {
      const idx = indexFromCharacter(key[0]);
      if (node.getNodes().nodePointers[idx] == null) {
        return node;
      }
      if (node.getChildrenCount() == 0) {
        return node;
      }
      node = node.getNodes().nodePointers[idx].?;
    }
    return node;
  }

  // fn addNodes(self: *@This(), node: TaggedUnitedNode, key: []const u8) !TaggedUnitedNode {
  //   while (key.len > 0) {
  //     const idx = indexFromCharacter(key[0]);
  //     const children = node.getNodes();
  //     const next = children.get(idx);
  //     if (!next.exists()) return next;
  //     if (children.nodePointers[idx] == null) {
  //       children.set(idx, try Strin);
  //     }
  //     if (node.getChildrenCount() == 0) {
  //     }
  //     if (key)
  //
  //     key = key[1..];
  //   }
  // }
};

test {
  std.testing.refAllDeclsRecursive(@This());
}

