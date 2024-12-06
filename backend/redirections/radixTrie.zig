//! An efficient radix trie implementation

const std = @import("std");
const builtin = @import("builtin");

// ##############################################
// # - implementation of some slice functions - #
// ##############################################

const eqlBytes_allowed = switch (builtin.zig_backend) {
  .stage2_spirv64, .stage2_riscv64 => false,
  else => true,
};
fn eql(comptime T: type, a: []const T, b: []const T) bool {
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

fn indexOfDiff(comptime T: type, a: []const T, b: []const T) ?usize {
  const shortest = @min(a.len, b.len);
  var index: usize = 0;
  while (index < shortest): (index += 1) if (a[index] != b[index]) return index;
  return if (a.len == b.len) null else shortest;
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
fn isUrlValid(url: []const u8) bool {
  for (url) |val| {
    if (!isCharacterAllowed(val)) return false;
  }
  return url.len != 0;
}

/// The value that is returned when the index is invalid
const InvalidIndex = 0xff;

/// An array of all the allowed characters soted in ascending order w.r.t their ascii values
const CharacterToIndexMap = blk: {
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
const IndexToCharacterMap: [CharacterEnd - CharacterStart]u8 = blk: {
  var retval = [1]u8{InvalidIndex} ** (CharacterEnd - CharacterStart);
  for (CharacterToIndexMap, 0..) |char, index| { retval[char - CharacterStart] = @intCast(index); }
  break :blk retval;
};

/// Returns true if the index provided is valid otherwise returns false
fn isValidIndex(index: u8) bool {
  return index < CharacterToIndexMap.len;
}

/// Convert index to ascii character
/// Assert that the index is valid.
/// To check index validity, use isValidIndex.
fn characterFromIndex(index: u8) u8 {
  std.debug.assert(isValidIndex(index));
  return CharacterToIndexMap[index];
}

/// Returns index from a character or return `InvalidIndex` if the character is invalid
fn indexFromCharacter(char: u8) u8 {
  std.debug.assert(isCharacterAllowed(char));
  return IndexToCharacterMap[char - CharacterStart];
}

test "indexFromCharacter and characterFromIndex" {
  for (0..0xff + 1) |i| {
    const char: u8 = @intCast(i);
    if (!isCharacterAllowed(char)) continue;
    const index = indexFromCharacter(char);

    try std.testing.expectEqual(char, characterFromIndex(index));
  }
}

// ############################################
// # - a convoluted but efficient node impl - #
// ############################################

const UnpackedNodeValues = struct {
  next: ?*Node.NextType align(@sizeOf(usize)),
  value: ?Node.Value align(@sizeOf(usize)),
  str: ?[]const u8 align(@sizeOf(usize)),
};

const Node = opaque {
  pub const Value = struct {
    deathat: i64,
    str: []const u8,
  };

  const NextType = [TotalCharacterCount]?*Node;
  const NextTypeNull = [_]?*Node{null} ** TotalCharacterCount;
  const NextTypeSize = @sizeOf(NextType);

  const mask: usize = 0b111;

  fn newUnfilledSized(allocator: std.mem.Allocator, next: bool, strlen: usize, valstrlen: usize) !*@This() {
    var maskValue: usize = 0;
    var size: usize = 0;

    if (next) {
      maskValue |= 0b100;
      size += NextTypeSize;
    }
    if (valstrlen != 0) {
      maskValue |= 0b010;
      size += @sizeOf(i64) + @sizeOf(u16) + valstrlen;
    }
    if (strlen != 0) {
      maskValue |= 0b001;
      size += @sizeOf(u16) + strlen;
    }

    const memory = try allocator.alignedAlloc(u8, 8, size);
    return @ptrFromInt(@intFromPtr(memory.ptr) | maskValue);
  }

  fn copyAndIncrement(ptr: *[*]u8, bytes: []const u8) void {
    @memcpy(ptr.*[0..bytes.len], bytes);
    ptr.* = ptr.*[bytes.len..];
  }

  fn new(allocator: std.mem.Allocator, constValue: UnpackedNodeValues) !*@This() {
    var value = constValue;
    if (value.str) |str| { if (str.len == 0) value.str = null; }

    const retval = try newUnfilledSized(
      allocator,
      value.next != null,
      if(value.str) |str| str.len else 0,
      if (value.value) |val| val.str.len else 0
    );

    var ptr: [*]u8 = @ptrFromInt(@intFromPtr(retval) & ~mask);

    if (value.next) |nxt| {
      copyAndIncrement(&ptr, std.mem.asBytes(nxt));
    }
    if (value.value) |val| {
      copyAndIncrement(&ptr, &std.mem.toBytes(val.deathat));
      copyAndIncrement(&ptr, &std.mem.toBytes(@as(u16, @intCast(val.str.len))));
    }
    if (value.str) |str| {
      copyAndIncrement(&ptr, &std.mem.toBytes(@as(u16, @intCast(str.len))));
      copyAndIncrement(&ptr, str);
    }
    if (value.value) |val| {
      copyAndIncrement(&ptr, val.str);
    }

    return retval;
  }

  fn getNext(self: *@This()) ?*NextType {
    var ptr = @intFromPtr(self);
    const existence = ptr & mask;
    ptr &= ~mask;

    if (existence & 0b100 == 0) { return null; }
    return @ptrFromInt(ptr);
  }

  fn getNextAndStr(self: *@This()) UnpackedNodeValues {
    var ptr = @intFromPtr(self);
    const existence = ptr & mask;
    ptr &= ~mask;

    var next: ?*NextType = undefined;
    if (existence & 0b100 != 0) {
      next = @ptrFromInt(ptr);
      ptr += NextTypeSize;
    } else {
      next = null;
    }

    if (existence & 0b010 != 0) {
      ptr += @sizeOf(i64) + @sizeOf(u16);
    }

    var str: ?[]u8 = undefined;
    if (existence & 0b001 != 0) {
      str = @as([*]u8, @ptrFromInt(ptr + @sizeOf(u16)))[0.. @as(*u16, @ptrFromInt(ptr)).*];
      ptr += @sizeOf(u16) + str.?.len;
    } else {
      str = null;
    }

    return .{
      .next = next,
      .value = null,
      .str = str,
    };
  }

  fn getComponents(self: *@This()) UnpackedNodeValues {
    var ptr = @intFromPtr(self);
    const existence = ptr & mask;
    ptr &= ~mask;

    var next: ?*NextType = undefined;
    if (existence & 0b100 != 0) {
      next = @ptrFromInt(ptr);
      ptr += NextTypeSize;
    } else {
      next = null;
    }

    var value: ?Value = undefined;
    var valuestrlen: u16 = undefined;
    if (existence & 0b010 != 0) {
      value = .{
        .deathat = @as(*i64, @ptrFromInt(ptr)).*,
        .str = undefined,
      };
      ptr += @sizeOf(i64);
      valuestrlen = @as(*u16, @ptrFromInt(ptr)).*;
      ptr += @sizeOf(u16);
    } else {
      value = null;
      valuestrlen = 0;
    }

    var str: ?[]u8 = undefined;
    if (existence & 0b001 != 0) {
      str = @as([*]u8, @ptrFromInt(ptr + @sizeOf(u16)))[0.. @as(*u16, @ptrFromInt(ptr)).*];
      ptr += @sizeOf(u16) + str.?.len;
    } else {
      str = null;
    }

    if (value != null) {
      value.?.str = @as([*]u8, @ptrFromInt(ptr))[0..valuestrlen];
    }

    return .{
      .next = next,
      .value = value,
      .str = str,
    };
  }

  fn getNodeMemory(self: *@This()) []align(@sizeOf(usize)) u8 {
    var ptr = @intFromPtr(self);
    const existence = ptr & mask;
    ptr &= ~mask;

    const memory: [*]align(@sizeOf(usize)) u8 = @ptrFromInt(ptr);
    var size: usize = 0;
    if (existence & 0b100 != 0) {
      size += NextTypeSize;
      ptr += NextTypeSize;
    }

    if (existence & 0b010 != 0) {
      size += @sizeOf(i64) + @sizeOf(u16) + @as(*u16, @ptrFromInt(ptr + @sizeOf(i64))).*;
      ptr += @sizeOf(i64) + @sizeOf(u16);
    }

    if (existence & 0b001 != 0) {
      size += @sizeOf(u16) + @as(*u16, @ptrFromInt(ptr)).*;
    }

    return memory[0..size];
  }

  fn freeNode(self: *@This(), allocator: std.mem.Allocator) void {
    allocator.free(self.getNodeMemory());
  }
};

test Node {
  const allocator = std.testing.allocator;
  const example = "https://example.com";
  const val = "randomValue";

  @setEvalBranchQuota(10_000);
  inline for (0..1) |i| {
    const string = example ++ [1]u8{'!'} ** i;
    const valstr = [1]u8{i} ++ val ++ [1]u8{i} ** i;
    const next = [1]?*Node{@ptrFromInt(i)} ** TotalCharacterCount;

    const mutstr = try allocator.dupe(u8, string);
    defer allocator.free(mutstr);
    const mutvalstr = try allocator.dupe(u8, valstr);
    defer allocator.free(mutvalstr);
    const mutnext: *Node.NextType = (try allocator.alloc(?*Node, TotalCharacterCount))[0..TotalCharacterCount];
    defer allocator.free(mutnext);
    @memcpy(mutnext, &next);

    const node = try Node.new(allocator, .{
      .next = mutnext,
      .value = .{
        .deathat = @as(i64, @intCast(i)),
        .str = mutstr,
      },
      .str = mutvalstr,
    });
    defer node.freeNode(allocator);

    const gottenNext = node.getNext();
    const gottenNextAndStr = node.getNextAndStr();
    const gottenComponents = node.getComponents();

    try std.testing.expectEqual(next, gottenNext.?.*);
    try std.testing.expectEqual(next, gottenNextAndStr.next.?.*);
    try std.testing.expectEqual(next, gottenComponents.next.?.*);

    try std.testing.expectEqualStrings(valstr, gottenNextAndStr.str.?);
    try std.testing.expectEqualStrings(valstr, gottenComponents.str.?);

    try std.testing.expectEqualStrings(string, gottenComponents.value.?.str);
  }
}

// ########################################
// # - implementation of the radix trie - #
// ########################################

pub const RadixTrie = struct {
  head: Node.NextType = Node.NextTypeNull,
  allocator: std.mem.Allocator,

  /// A helper function for add
  fn getHeadIndexDiff(self: *@This(), constKey: []const u8) struct {
    node: *?*Node,
    diff: usize,
    remaining: []const u8,
  } {
    var key = constKey;
    var next = &self.head;

    while (true) {
      const idx = indexFromCharacter(key[0]);
      key = key[1..];
      // -> Case 1
      const node: *Node = next[idx] orelse return .{
        .node = &next[idx],
        .diff = undefined,
        .remaining = key,
      };

      const val = node.getNextAndStr();
      if (val.str) |str| {
        const minLen = @min(str.len, key.len);
        if (indexOfDiff(u8, str[0..minLen], key[0..minLen])) |diff| {
          // -> Case 2
          return .{
            .node = &next[idx],
            .diff = diff,
            .remaining = key[diff..],
          };
        } else if (key.len < str.len) {
          // -> Case 3
          return .{
            .node = &next[idx],
            .diff = key.len,
            .remaining = key[key.len..],
          };
        }
        key = key[minLen..];
      }

      // -> Case 4
      if (key.len == 0 or val.next == null) return .{
        .node = &next[idx],
        .diff = 0,
        .remaining = key,
      };

      next = val.next.?;
    }
  }

  /// Add a new key-value pair to the trie
  pub fn add(self: *@This(), key: []const u8, dest: []const u8, deathat: i64) !void {
    if (!isUrlValid(key)) return error.InvalidKey;
    var diff = self.getHeadIndexDiff(key);

    // -> Case 1
    if (diff.node.* == null) {
      diff.node.* = try Node.new(self.allocator, .{
        .next = null,
        .value = .{ .str = dest, .deathat = deathat },
        .str = diff.remaining,
      });
      return;
    }

    var components = diff.node.*.?.getComponents();

    // -> Case 4 (1 nodes to be added, 1 to be removed)
    if (diff.diff == 0) { // Value only node
      if (diff.remaining.len == 0) { // Replace old value
        components.value = .{ .str = dest, .deathat = deathat };
        const newNode = try Node.new(self.allocator, components);
        diff.node.*.?.freeNode(self.allocator);
        diff.node.* = newNode;
      } else { // Add new value and make the node non-terminal
        const idx = indexFromCharacter(diff.remaining[0]);
        diff.remaining = diff.remaining[1..];
        var nextArr: Node.NextType = Node.NextTypeNull;
        nextArr[idx] = try Node.new(self.allocator, .{
          .next = components.next,
          .value = .{ .str = dest, .deathat = deathat },
          .str = diff.remaining,
        });
        errdefer nextArr[idx].?.freeNode(self.allocator);

        components.next = &nextArr;
        const newNode = try Node.new(self.allocator, components);
        diff.node.*.?.freeNode(self.allocator);
        diff.node.* = newNode;
      }
      return;
    }

    // -> Case 3 (3 nodes to be added, 1 to be removed)
    if (diff.remaining.len == 0) {
      var nextArr: Node.NextType = Node.NextTypeNull;
      const idx = indexFromCharacter(components.str.?[diff.diff]);
      nextArr[idx] = try Node.new(self.allocator, .{
        .next = components.next,
        .value = components.value,
        .str = components.str.?[diff.diff+1..],
      });
      errdefer nextArr[idx].?.freeNode(self.allocator);

      const nodeBefore = try Node.new(self.allocator, .{
        .next = &nextArr,
        .value = .{ .str = dest, .deathat = deathat },
        .str = null,
      });

      diff.node.*.?.freeNode(self.allocator);
      diff.node.* = nodeBefore;
      return;
    }

    // -> Case 2 (3 nodes to be added, 1 to be removed)
    var nextArr: Node.NextType = Node.NextTypeNull;
    const oldValIdx = indexFromCharacter(components.str.?[diff.diff]);
    nextArr[oldValIdx] = try Node.new(self.allocator, .{
      .next = components.next,
      .value = components.value,
      .str = components.str.?[diff.diff+1..],
    });
    errdefer nextArr[oldValIdx].?.freeNode(self.allocator);

    const newValIdx = indexFromCharacter(diff.remaining[0]);
    nextArr[newValIdx] = try Node.new(self.allocator, .{
      .next = null,
      .value = .{ .str = dest, .deathat = deathat },
      .str = diff.remaining[1..],
    });
    errdefer nextArr[newValIdx].?.freeNode(self.allocator);

    const newNode = try Node.new(self.allocator, .{
      .next = &nextArr,
      .value = null,
      .str = components.str.?[0..diff.diff],
    });

    diff.node.*.?.freeNode(self.allocator);
    diff.node.* = newNode;
  }

  /// Get the value associated with a key if it exists
  pub fn get(self: *@This(), constKey: []const u8) ?Node.Value {
    if (!isUrlValid(constKey)) return null;

    var key = constKey;
    var next = &self.head;
    while (true) {
      const node = next[indexFromCharacter(key[0])] orelse return null;
      key = key[1..];
      const val = node.getComponents();
      if (val.str) |str| {
        if (str.len > key.len and !std.mem.eql(u8, str, key[0..str.len])) return null;
        key = key[str.len..];
      }
      if (key.len == 0) return val.value;
      next = val.next orelse return null;
    }
  }

  fn merge(self: *@This(), prev: UnpackedNodeValues, childIndex: u8, child: UnpackedNodeValues) !*Node {
    std.debug.assert(prev.next == null);
    std.debug.assert(prev.value == null);

    const strlen = (if (prev.str) |str| str.len else 0) + (if (child.str) |str| str.len else 0) + 1;
    const mergedNode = try Node.newUnfilledSized(
      self.allocator,
      child.next != null,
      strlen,
      if (child.value) |childVal| childVal.str.len else 0,
    );
    var mergedPtr: [*]u8 = @ptrFromInt(@intFromPtr(mergedNode) & ~Node.mask);
    if (child.next) |childNext| {
      Node.copyAndIncrement(&mergedPtr, std.mem.asBytes(childNext));
    }
    if (child.value) |childValue| {
      Node.copyAndIncrement(&mergedPtr, &std.mem.toBytes(childValue.deathat));
      Node.copyAndIncrement(&mergedPtr, &std.mem.toBytes(@as(u16, @intCast(childValue.str.len))));
    }
    Node.copyAndIncrement(&mergedPtr, &std.mem.toBytes(@as(u16, @intCast(strlen))));
    if (prev.str) |str| {
      Node.copyAndIncrement(&mergedPtr, str);
    }
    Node.copyAndIncrement(&mergedPtr, &[_]u8{characterFromIndex(childIndex)});
    if (child.str) |childStr| {
      Node.copyAndIncrement(&mergedPtr, childStr);
    }
    if (child.value) |childValue| {
      Node.copyAndIncrement(&mergedPtr, childValue.str);
    }

    return mergedNode;
  }

  pub fn delete(self: *@This(), constKey: []const u8) !void {
    if (!isUrlValid(constKey)) return error.InvalidKey;
    var key = constKey;
    var parentPtr: ?**Node = null;
    var next = &self.head;
    while (true) {
      const idx = indexFromCharacter(key[0]);
      const node = next[idx] orelse return error.KeyNotFound;
      key = key[1..];
      const val = node.getComponents();
      if (val.str) |str| {
        if (str.len > key.len and !std.mem.eql(u8, str, key[0..str.len])) return error.KeyNotFound;
        key = key[str.len..];
      }

      if (key.len == 0) { // Remove the node
        var childrenCount: u8 = 0;
        if (val.next) |valNext| {
          for (valNext) |child| childrenCount += if (child != null) 1 else 0;
        }

        if (childrenCount == 0) { // Remove
          node.freeNode(self.allocator);
          next[idx] = null;
        } else if (childrenCount == 1) { // Merge
          const childIndex = blk: {
            for (val.next.?, 0..) |child, i| if (child != null) break :blk i;
            unreachable;
          };
          const childComponents = val.next.?[childIndex].?.getComponents();
          const merged = try self.merge(.{ .next = null, .value = null, .str = val.str }, @intCast(childIndex), childComponents);
          val.next.?[childIndex].?.freeNode(self.allocator);
          node.freeNode(self.allocator);
          next[idx] = merged;
        } else { return; } // Node with multiple children cant be merged
        if (parentPtr == null) return; // The node is in the head, so cant do nothing

        var siblingsCount: u8 = 0;
        for (next) |valSibling| siblingsCount += if (valSibling != null) 1 else 0;
        if (siblingsCount > 1) return;  // Cant do anything for nodes with multiple siblings

        var parentComponents = parentPtr.?.*.getComponents();
        if (parentComponents.value == null and siblingsCount == 0) { // This should never happen unless OOM (from which we somehow recovered)
          parentPtr.?.*.freeNode(self.allocator);
          @as(*?*Node, @ptrCast(parentPtr.?)).* = null;
          return;
        }
        parentComponents.next = null;

        if (siblingsCount == 0) {
          const newNode = try Node.new(self.allocator, parentComponents);
          parentPtr.?.*.freeNode(self.allocator);
          parentPtr.?.* = newNode;
        } else if (siblingsCount == 1 and parentComponents.value == null) { // Merge parent and sibling
          const siblingIndex = blk: {
            for (parentComponents.next.?, 0..) |sibling, i| if (sibling != null) break :blk i;
            unreachable;
          };
          const merged = try self.merge(parentComponents, @intCast(siblingIndex), parentComponents.next.?[siblingIndex].?.getComponents());
          parentPtr.?.*.freeNode(self.allocator);
          parentPtr.?.* = merged;
        }
        return;
      } // <- Remove the node

      parentPtr = &next[idx].?;
      next = val.next orelse return error.KeyNotFound;
    }
  }

  /// Free a node recursively
  fn freeRecursiveNoConsequence(self: *@This(), nullableHead: ?*Node) void {
    const head = nullableHead orelse return;
    defer head.freeNode(self.allocator);
    const next = head.getNext() orelse return;
    for (next) |node| self.freeRecursiveNoConsequence(node);
  }

  fn freeRecursive(self: *@This(), head: *?*Node) void {
    freeRecursiveNoConsequence(self, head.*);
    head.* = null;
  }

  pub fn deinit(self: *@This()) void {
    for (0..TotalCharacterCount) |idx| self.freeRecursive(&self.head[idx]);
  }
};

test RadixTrie {
  const allocator = std.testing.allocator;
  var trie = RadixTrie{ .allocator = allocator };
  defer trie.deinit();

  // -> Test add
  const AddArgsType = struct {
    key: []const u8,
    deathat: i64,
    dest: []const u8,
  };

  var arena = std.heap.ArenaAllocator.init(allocator);
  const arenaAllocator = arena.allocator();
  defer arena.deinit();
  var addArgsList = std.ArrayList(AddArgsType).init(arenaAllocator);

  try addArgsList.append(.{
    .key = "foo",
    .deathat = -1,
    .dest = "https://example.com/10",
  });
  try addArgsList.append(.{
    .key = "bar",
    .deathat = -2,
    .dest = "https://example.com/20",
  });
  for (0..1000) |i| {
    try addArgsList.append(.{
      .key = try std.fmt.allocPrint(arenaAllocator, "{d}", .{i}),
      .deathat = @intCast(i),
      .dest = try std.fmt.allocPrint(arenaAllocator, "https://example.com/{d}", .{i}),
    });
  }
  try addArgsList.append(.{
    .key = "foo",
    .deathat = -1,
    .dest = "https://example.com/10",
  });
  try addArgsList.append(.{
    .key = "bar",
    .deathat = -2,
    .dest = "https://example.com/20",
  });

  std.debug.print("testing add\n", .{});
  const addArgs = try addArgsList.toOwnedSlice();
  for (addArgs, 0..) |args, idx| {
    try trie.add(args.key, args.dest, args.deathat);
    for (addArgs[0..idx]) |a| {
      const val = trie.get(a.key).?;
      try std.testing.expectEqual(a.deathat, val.deathat);
      try std.testing.expectEqualStrings(a.dest, val.str);
    }
  }

  std.debug.print("testing remove\n", .{});
  const removeArgs = addArgs[2..];
  for (removeArgs, 0..) |args, idx| {
    try trie.delete(args.key);
    for (removeArgs[idx+1..]) |a| {
      const val = trie.get(a.key).?;
      try std.testing.expectEqual(a.deathat, val.deathat);
      try std.testing.expectEqualStrings(a.dest, val.str);
    }
  }
}

test {
  std.testing.refAllDeclsRecursive(@This());
}

