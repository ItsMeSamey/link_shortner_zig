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

// This will e used in the Entry struct
pub fn PackedStaticBitSet(comptime count: u16) type {
  return packed struct {
    holder: IntType = 0,

    pub const IntType = std.meta.Int(.unsigned, count);

    pub fn zeroOut(self: *@This()) void {
      self.holder = 0;
    }

    pub fn get(self: *const @This(), index: u16) bool {
      return (self.holder & (@as(IntType, 1) << @intCast(index))) != 0;
    }

    pub fn set(self: *@This(), index: u16, value: bool) void {
      if (value) {
        self.holder |= (@as(IntType, 1) << @intCast(index));
      } else {
        self.holder &= ~(@as(IntType, 1) << @intCast(index));
      }
    }
  };
}

test PackedStaticBitSet {
  var set = PackedStaticBitSet(TotalCharacterCount){};
  for (0..TotalCharacterCount) |i| {
    try std.testing.expectEqual(false, set.get(@intCast(i)));
    set.set(@intCast(i), true);
    try std.testing.expectEqual(true, set.get(@intCast(i)));
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

const EntryTag = enum(u1) {
  TerminalEntry = 0,
  Entry = 1,

  pub fn getType(self: *const @This()) type {
    return switch (self.*) {
      .Entry => Entry,
      .TerminalEntry => TerminalEntry,
    };
  }
};

const Entry = packed struct {
  next: ?*[TotalCharacterCount]Entry = null,
  fragments: PackedStaticBitSet(TotalCharacterCount) = .{},
  padding: u2 = undefined,
  tag: EntryTag = .Entry,

  pub fn toTerminalEntry(self: *Entry) *TerminalEntry { return @ptrCast(self); }
  pub fn blanked(self: *Entry) *Entry {
    self.next = null;
    self.fragments.zeroOut();
    self.tag = .Entry;
    return self;
  }

  pub fn createNext(allocator: std.mem.Allocator) !*[TotalCharacterCount]Entry {
    const retval = try allocator.create([TotalCharacterCount]Entry);
    inline for (0..TotalCharacterCount) |i| {
      _ = (&(retval.*[i])).blanked();
    }
    return retval;
  }
};

const TerminalEntry = packed struct {
  value: ?*Value = null,
  rest: packed union {
    char: u88,
    tag: packed struct {
      padding: u77 = 0,
      tag: EntryTag = .TerminalEntry,
    },
  },

  pub fn new(allocator: std.mem.Allocator) !*TerminalEntry {
    var retval = try allocator.create(TerminalEntry);
    retval.value = null;
    retval.rest.char = 0;
    retval.rest.tag.tag = .TerminalEntry;
    return retval;
  }

  pub fn setRestChars(self: *TerminalEntry, rest: []const u8) void {
    std.debug.assert(rest.len <= 11);
    const bytes = @as([*]u8, @ptrCast(&self.rest.char));
    @memcpy(bytes, rest);

    if (self.len == 11) {
      bytes[10] <<= 1;
      self.rest.tag.tag = .TerminalEntry;
    }
  }
};

test "Value and Entry type properties" {
  try std.testing.expectEqual(@alignOf(Entry), @alignOf(TerminalEntry));

  try std.testing.expectEqual(@bitSizeOf(Entry), 64 + 88);
  try std.testing.expectEqual(@bitSizeOf(TerminalEntry), 64 + 88);
}

pub const Trie = struct {
  head: Entry = .{},
  allocator: std.mem.Allocator,

  pub fn getEntry(self: *Trie, location: []const u8) ?*Value {
    var head: *Entry = &self.head;
    for (0..location.len) |i| {
      switch (head.tag) {
        .value => {
          if (head.next == null) return null;
          const idx = indexFromCharacter(location[i]);
          if (!head.fragments.get(idx)) return null;
          head = (&head.next.?)[idx];
        },
        .terminal => {
          const th = head.toTerminalEntry();
          const restLocation = location[i..];
          if (restLocation.len > 11) return null;
          var restUint: u88 = 0;
          const restChars = @as([*]u8, @ptrCast(&restUint))[0..restLocation.len];
          @memcpy(restChars, restLocation);
          if (restLocation.len == 11) {
            restChars[10] <<= 1;
            restChars[10] |= @intFromEnum(EntryTag.TerminalEntry);
          }

          return if (restChars != th.characters) null else th.value;
        },
      }
    }
  }

  fn mustAddNodesForLocation(self: *Trie, location: []const u8, entry: *Entry) !*Entry {
    for (location) |char| {
      const idx = indexFromCharacter(char);
      std.debug.assert(entry.next == null);
      entry.next = try Entry.createNext(self.allocator);
      entry.fragments.set(idx, true);
      entry = &entry.next.?[idx];
    }
  }

  fn freeChain(self: *Trie, entry: *Entry) void {
    switch (entry.tag) {
      .Entry => {

      },
      .TerminalEntry => {
        self.fre
      }
    }
    for (0..TotalCharacterCount) |i| {
      if 
    }
  }

  fn addNodes(self: *Trie, location: []const u8, entry: *Entry, val: *Value) !void {
    if (entry.tag == .TerminalEntry) {
      const te = entry.toTerminalEntry();
      const otherVal = te.rest.value;
      const otherLocationFull = std.mem.asBytes(&te.rest.char);

      const len = std.mem.indexOfScalar(u8, otherLocationFull, 0) orelse 11;
      const otherLocation = otherLocationFull[0..len];

      const diff = std.mem.indexOfDiff(u8, location, otherLocation) orelse {
        otherVal.free(self.allocator);
        entry.value = val;
        return;
      };

      entry.next = null;
      entry.tag = .Entry;
      try mustAddNodesForLocation(self, location[0..diff], entry) catch {

      }

    }

    while (location.len >= 12) {
      const idx = indexFromCharacter(location[0]);
      entry.next = try Entry.createNext(self.allocator);
      entry = &(entry.next.*[idx]);
      location = location[1..];
    }

    entry.tag = .TerminalEntry;
    const te = entry.toTerminalEntry();
    te.setRestChars(location);
    te.value = val;
  }

  fn addEntry(self: *Trie, location: []const u8, head: *Entry, val: *Value) !void {
    for (0..location.len) |i| {
      if (head.next == null) return addNodes(location[i..], head, val);
      const idx = indexFromCharacter(location[i]);
      if (!head.fragments.get(idx) or head.next.?[idx].tag == .TerminalEntry) {
        head.fragments.set(idx, true);
        return self.addNode(location[i+1..], &head.next.?[idx], val);
      }
      head = &head.next.?[idx];
    }
  }

  pub fn add(self: *Trie, location: []const u8, dest: []const u8, deathat: u32) !void {
    const value = try Value.new(self.allocator, dest, deathat);
    errdefer value.free(self.allocator);

    try self.addEntryValue(location, &self.head, value);
  }
};

