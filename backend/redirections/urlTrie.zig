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


const Entry = union(enum) {
  nodes: Nodes,
  terminal: TerminalEntry,

  pub const Nodes = struct {
    value: ?*Value,
    nodes: [TotalCharacterCount]?*Entry,

    pub const NullVal = Nodes {
      .value = null,
      .nodes = [1]?*Entry{null} ** TotalCharacterCount,
    };
  };
  pub const TerminalEntry = struct {
    value: ?*Value,
    strLen: u16,
    str: [@sizeOf(Nodes) - @sizeOf(usize) - @sizeOf(u16)]u8,

    pub const NullVal = TerminalEntry {
      .value = null,
      .strLen = 0,
      .str = [1]u8{0} ** (@sizeOf(Nodes) - @sizeOf(usize) - @sizeOf(u16)),
    };

    pub fn setStr(self: *TerminalEntry, str: []const u8) void {
      self.strLen = @intCast(str.len);
      @memcpy(self.str[0..str.len], str);
    }
  };

  fn createNodes(allocator: std.mem.Allocator, value: ?*Value) !*Entry {
    const retval = try allocator.create(Entry);
    retval.* = .{
      .nodes = .{
        .value = value,
        .nodes = Nodes.NullVal.nodes,
      }
    };
    return retval;
  }

  fn createTerminal(allocator: std.mem.Allocator, value: ?*Value, str: []const u8) !*Entry {
    const retval = try allocator.create(Entry);
    retval.* = .{
      .terminal = .{
        .value = value,
        .strLen = undefined,
        .str = undefined,
      },
    };
    retval.terminal.setStr(str);
    return retval;
  }

  /// Asserts that the url is valid
  /// Returns the entry that is nonMatching (and is .nodes) or the entry that points to the value
  pub fn getNonMatching(noalias self: *Entry, noalias location : *[]const u8) *Entry {
    std.debug.assert(isUrlValid(location.*));
    var entry = self;

    for (location.*, 0..) |char, i| {
      switch (entry.*) {
        .nodes => {
          const nodes = &entry.nodes.nodes;
          if (nodes[indexFromCharacter(char)]) |next| {
            entry = next;
            continue;
          }
        },
        .terminal => {},
      }
      location.* = location.*[i..];
      return entry;
    }
    location.* = location.*[location.len..]; // 0 length slice
    return entry;
  }

  /// Asserts that the url is valid
  /// Adds nodes and returns the last one for all characters in location.
  /// NOTE: Returned entry may or may not be terminal entry and may or may not have a value already set
  pub fn addNodes(self: *Entry, location: []const u8, allocator: std.mem.Allocator) !*Entry {
    std.debug.assert(isUrlValid(location));
    var entry = self;

    var i: usize = 0;
    while (i < location.len) : (i += 1) {
      switch (entry.*) {
        .nodes => {
          const nodes = &entry.nodes.nodes;
          const idx = indexFromCharacter(location[i]);
          if (nodes[idx]) |val| {
            entry = val;
          } else {
            nodes[idx] = try createNodes(allocator, null);
          }
        },
        .terminal => {
          const terminal = &entry.terminal;
          const diff = std.mem.indexOfDiff(u8, terminal.str[0..terminal.strLen], location[i..]) orelse return entry;
          var oldNode: TerminalEntry = entry.terminal;
          entry.nodes.nodes = [1]?*Entry{null} ** TotalCharacterCount;
          errdefer {
            entry.freeRecursively(allocator);
            entry.terminal = oldNode;
          }
          const newEntry = try entry.addNodes(location[i..][0..diff], allocator);

          entry = newEntry;
          if (oldNode.strLen == diff) {
            entry.nodes.value = oldNode.value;
            const retval = try createTerminal(allocator, null, location[diff..]);
            entry.nodes.nodes[indexFromCharacter(location[diff])] = retval;
            return retval;
          }

          const idxOld = characterFromIndex(oldNode.str[diff]);
          oldNode.setStr(oldNode.str[diff..oldNode.strLen]);
          entry.nodes.nodes[idxOld] = try createTerminal(allocator, oldNode.value, oldNode.str[diff+1..]);
          if (location.len == diff) return entry;

          const idxNew = characterFromIndex(location[diff]);
          const retNode = try createTerminal(allocator, null, location[diff+1..]);
          entry.nodes.nodes[idxNew] = retNode;
          return retNode;
        },
      }
    }

    return entry;
  }

  /// Free all the entries and values that are children of this entry (value of this entry is also free'd)
  /// Does not free the entry itself tho
  pub fn freeRecursively(self: *Entry, allocator: std.mem.Allocator) void {
    var value: ?*Value = undefined;
    switch (self.*) {
      .nodes => {
        for (self.nodes.nodes) |node| {
          if (node) |n| {
            n.freeRecursively(allocator);
            allocator.destroy(n);
          }
        }
        value = self.nodes.value;
      },
      .terminal => {
        value = self.terminal.value;
      },
    }
    if (value) |val| val.free(allocator);
  }

  /// Searches for an entry and gives the Entry that is isolated (has only one children all the way to termination)
  /// Asserts that the location exists and that the url is valid
  pub fn getIsolatedEntry(self: *Entry, location: []const u8) *Entry {
    std.debug.assert(isUrlValid(location));

    var retval = self;
    for (location) |char| {
      switch (retval.*) {
        .nodes => {
          const nodes = &retval.nodes.nodes;
          if (nodes[indexFromCharacter(char)]) |next| {
            retval = next;
          } else return retval;
        },
        .terminal => return retval,
      }
    }
    return retval;
  }
};

test Entry {
  std.testing.refAllDeclsRecursive(Entry);

  try std.testing.expectEqual(@sizeOf(Entry.Nodes), @sizeOf(Entry.TerminalEntry));
  try std.testing.expectEqual(@bitSizeOf(Entry.Nodes), @bitSizeOf(Entry.TerminalEntry));
}

pub const Trie = struct {
  head: Entry = .{ .nodes = Entry.Nodes.NullVal },
  allocator: std.mem.Allocator,

  pub fn getEntry(self: *Trie, constLocation: []const u8) ?*Value {
    var location = constLocation;
    const entry = self.head.getNonMatching(&location);

    const retval = switch (entry.*) {
      .nodes => entry.nodes.value,
      .terminal => entry.terminal.value
    };
    if (location.len == 0) return retval;
    if (entry.* != .terminal) return null;

    if (!std.mem.eql(u8, entry.terminal.str[0..entry.terminal.strLen], location)) return null;

    return retval;
  }

  pub fn add(self: *Trie, location: []const u8, dest: []const u8, deathat: u32) !void {
    const val = try Value.new(self.allocator, dest, deathat);
    errdefer val.free(self.allocator);
    const entry = try self.head.addNodes(location, self.allocator);
    switch (entry.*) {
      .nodes => {
        if (entry.nodes.value) |value| value.free(self.allocator);
        entry.nodes.value = val;
      },
      .terminal => {
        if (entry.terminal.value) |value| value.free(self.allocator);
        entry.terminal.value = val;
      },
    }
  }

  pub fn remove(self: *Trie, location: []const u8) void {
    _ = self;
    _ = location;
    return;
  }

  pub fn deinit(self: *Trie) void {
    self.head.freeRecursively(self.allocator);
  }

  const Iterator = struct {
  };
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
  trie.remove("hello1");

  try trie.add("hello1", "world", 1024);
  try trie.add("hello2", "hello", 1024);
  try trie.add("hello3", "hello", 1024);
  try std.testing.expectEqualStrings("world", trie.getEntry("hello1").?.getDest());
  try std.testing.expectEqualStrings("hello", trie.getEntry("hello2").?.getDest());
  try std.testing.expectEqualStrings("hello", trie.getEntry("hello3").?.getDest());
  trie.remove("hello2");

  try trie.add("hello1", "1", 1024);
  try trie.add("hello2", "2", 1024);
  try trie.add("hello3", "3", 1024);
  try std.testing.expectEqualStrings("1", trie.getEntry("hello1").?.getDest());
  try std.testing.expectEqualStrings("2", trie.getEntry("hello2").?.getDest());
  try std.testing.expectEqualStrings("3", trie.getEntry("hello3").?.getDest());
  trie.remove("hello3");

  try trie.add("hello1a", "hello", 1024);
  try trie.add("hello2a", "world", 1024);
  try trie.add("hello3a", "world", 1024);
  try trie.add("hello1bs", "hello", 1024);
  try trie.add("hello2cs", "world", 1024);
  try trie.add("hello3da", "world", 1024);
}

