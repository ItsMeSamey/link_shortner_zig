const std = @import("std");

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

/// The terminal Value Entry
const Value = packed struct {
  deathat: i64,

  /// Done this way so we need only one allocation
  pub fn new(allocator: std.mem.Allocator, dest: []const u8, deathat: i64) !*Value {
    if (dest.len > std.math.maxInt(u16)) return error.DestinationTooLong;
    // length  takes 2 bytes (u16)
    const memory: []u8 = try allocator.alignedAlloc(u8, @alignOf(Value), @sizeOf(Value) + 2 + dest.len);

    const retval: *Value = @alignCast(@ptrCast(memory[0..@sizeOf(Value)]));
    retval.deathat = deathat;

    const destLength: *u16 = @alignCast(@ptrCast(memory[@sizeOf(Value)..].ptr));
    destLength.* = @intCast(dest.len);

    const destSlice = memory[@sizeOf(Value)+2..][0..dest.len];
    @memcpy(destSlice, dest);

    return retval;
  }

  fn getDestLength(self: *const Value) u16 {
    const memory: [*]const u8 = @ptrCast(self);
    return @bitCast(memory[@sizeOf(Value)..][0..2].*);
  }

  /// Get the Destination string slice
  pub fn getDest(self: *const Value) []const u8 {
    const memory: [*]const u8 = @ptrCast(self);
    return memory[@sizeOf(Value)+2..][0..self.getDestLength()];
  }

  /// Free this value
  pub fn free(self: *Value, allocator: std.mem.Allocator) void {
    // Because the allocator.free cannot free crooked(length is not a multiple of aligenment) aligend allocated memory (afaik)
    const memory: [*]u8 = @ptrCast(self);
    const byteLen: usize = @sizeOf(Value)+2+self.getDestLength();
    allocator.rawFree(memory[0..byteLen], std.math.log2(@alignOf(Value)), @returnAddress());
  }
};

test Value {
  std.testing.refAllDecls(Value);
  const allocator = std.testing.allocator;

  const example = "https://example.com";
  inline for (0..255) |i| {
    const string = example ++ [1]u8{'!'} ** i;
    const v = try Value.new(allocator, string, 100);
    defer v.free(allocator);
    try std.testing.expectEqualStrings(string, v.getDest());
    try std.testing.expectEqual(100, v.deathat);
    try std.testing.expectEqual(v.getDestLength(), string.len);
  }
}


const Entry = struct {
  value: ?*Value,
  nodes: [TotalCharacterCount]?*Entry,

  pub const NullVal = Entry {
    .value = null,
    .nodes = [1]?*Entry{null} ** TotalCharacterCount,
  };

  fn createNodes(allocator: std.mem.Allocator, value: ?*Value) !*Entry {
    const retval = try allocator.create(Entry);
    retval.* = .{
      .value = value,
      .nodes = NullVal.nodes,
    };
    return retval;
  }

  /// Free all the entries and values that are children of this entry (value of this entry is also free'd)
  /// Does not free the entry itself tho
  pub fn freeRecursively(self: *Entry, allocator: std.mem.Allocator) void {
    for (self.nodes) |node| {
      if (node) |n| {
        n.freeRecursively(allocator);
        allocator.destroy(n);
      }
    }
    if (self.value) |val| val.free(allocator);
  }
};

test Entry {
  std.testing.refAllDeclsRecursive(Entry);
}

pub const Trie = struct {
  head: Entry = Entry.NullVal,
  allocator: std.mem.Allocator,

  pub fn getEntry(self: *Trie, location: []const u8) ?*Value {
    if (!isUrlValid(location)) return null;
    var entry = &self.head;

    for (location) |char| {
      if (entry.nodes[indexFromCharacter(char)]) |next| {
        entry = next;
      } else {
        return null;
      }
    }
    return entry.value;
  }

  pub fn add(self: *Trie, location: []const u8, dest: []const u8, deathat: u32) !void {
    if (!isUrlValid(location)) return error.InvalidUrl;

    var entry = &self.head;
    for (location) |char| {
      const idx = indexFromCharacter(char);
      if (entry.nodes[idx] == null) {
        entry.nodes[idx] = try Entry.createNodes(self.allocator, null);
      }
      entry = entry.nodes[idx].?;
    }

    if (entry.value) |value| value.free(self.allocator);
    entry.value = try Value.new(self.allocator, dest, deathat);
  }

  pub fn remove(self: *Trie, location: []const u8) !void {
    if (!isUrlValid(location)) return error.InvalidUrl;

    var toDelete = &self.head;
    var toDeleteIndex: u8 = InvalidIndex;
    var current = &self.head;
    for (location) |char| {
      const idx = indexFromCharacter(char);
      for (0..TotalCharacterCount) |i| {
        if (current.nodes[i]) |_| {
          if (i == idx) continue;
          toDelete = current;
          toDeleteIndex = idx;
          break;
        }
      }
      current = current.nodes[idx] orelse return error.NotFound;
    }

    if (current.value) |value| {
      value.free(self.allocator);
      current.value = null;
    }

    var hasChildren = false;
    for (0..TotalCharacterCount) |i| {
      if (current.nodes[i] != null) {
        hasChildren = true;
        break;
      }
    }

    if (!hasChildren) {
      toDelete.nodes[toDeleteIndex].?.freeRecursively(self.allocator);
      self.allocator.destroy(toDelete.nodes[toDeleteIndex].?);
      toDelete.nodes[toDeleteIndex] = null;
    }
  }

  pub fn deinit(self: *Trie) void {
    self.head.freeRecursively(self.allocator);
  }
};

test Trie {
  std.testing.refAllDecls(Trie);
  const allocator = std.testing.allocator;
  var trie = Trie{ .allocator = allocator };
  defer trie.deinit();

  try trie.add("hello1", "hello", 1024);
  try trie.add("hello2", "world", 1024);
  try trie.add("hello3", "world", 1024);
  try std.testing.expectEqualStrings("hello", trie.getEntry("hello1").?.getDest());
  try std.testing.expectEqualStrings("world", trie.getEntry("hello2").?.getDest());
  try std.testing.expectEqualStrings("world", trie.getEntry("hello3").?.getDest());
  try trie.remove("hello1");

  try trie.add("hello1", "world", 1024);
  try trie.add("hello2", "hello", 1024);
  try trie.add("hello3", "hello", 1024);
  try std.testing.expectEqualStrings("world", trie.getEntry("hello1").?.getDest());
  try std.testing.expectEqualStrings("hello", trie.getEntry("hello2").?.getDest());
  try std.testing.expectEqualStrings("hello", trie.getEntry("hello3").?.getDest());
  try trie.remove("hello2");

  try trie.add("hello1", "1", 1024);
  try trie.add("hello2", "2", 1024);
  try trie.add("hello3", "3", 1024);
  try std.testing.expectEqualStrings("1", trie.getEntry("hello1").?.getDest());
  try std.testing.expectEqualStrings("2", trie.getEntry("hello2").?.getDest());
  try std.testing.expectEqualStrings("3", trie.getEntry("hello3").?.getDest());
  try trie.remove("hello3");

  try trie.add("hello1a", "hello", 1024);
  try trie.add("hello2a", "world", 1024);
  try trie.add("hello3a", "world", 1024);
  try trie.add("hello1bs", "hello", 1024);
  try trie.add("hello2cs", "world", 1024);
  try trie.add("hello3da", "world", 1024);
}

