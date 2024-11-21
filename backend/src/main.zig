const std = @import("std");
const linux = std.os.linux;

// The main function to start the server
pub fn main() void {
  var addr: linux.sockaddr = @bitCast(linux.sockaddr.in {
    .family = linux.AF.INET,
    .port = std.mem.nativeToBig(u16, 8080),
    .addr = std.mem.nativeToBig(u32, @bitCast([_]u8{ 0, 0, 0, 0 })),
  });

  const sock: i32 = @intCast(linux.socket(linux.AF.INET, linux.SOCK.STREAM, 0));
  if (sock == 0) return std.debug.print("socket creation failed\n", .{});
  defer _ = linux.close(sock);

  var err: usize = undefined;

  err = linux.setsockopt(sock, linux.SOL.SOCKET, linux.SO.REUSEADDR, &std.mem.toBytes(@as(u32, 1)), @sizeOf(u32));
  if (err != 0) return std.debug.print("setsockopt failed ({x})\n", .{ err });

  err = linux.bind(sock, &addr, @sizeOf(@TypeOf(addr)));
  if (err != 0) return std.debug.print("socket bind failed ({x})\n", .{ err });

  err = linux.listen(sock, linux.SOMAXCONN);
  if (err != 0) return std.debug.print("listen failed ({d})\n", .{ err });

  while (true) {
    const client: i32 = @intCast(linux.accept(sock, null, null));
    if (client < 0) {
      std.debug.print("accept failed with {x}\n", .{ client });
      continue;
    }
    defer _ = linux.close(client);

    var buf: [2048]u8 = undefined;

    const n = linux.read(client, &buf, buf.len);
    if (n == 0) {
      std.debug.print("read failed with {x}\n", .{ n });
      continue;
    }

    const response = getResponse(buf[0..n]) catch |e| {
      const resp = switch (e) {
        error.Ok => "HTTP/1.1 200\r\n\r\n",
        else => "HTTP/1.1 400\r\n\r\n"
      };
      _ = linux.write(client, resp, resp.len);
      continue;
    };

    _ = linux.write(client, "HTTP/1.1 302\r\nContent-Length:0\r\nLocation:", 41);
    _ = linux.write(client, response.ptr, response.len);
    _ = linux.write(client, "\r\n\r\n", 4);
  }

  std.time.sleep(1000_000_000_0);
}

var trie: std.ArrayList(ValueEntry) = undefined;
var values: std.ArrayList(Value) = undefined;

fn init() void {
  const allocator = std.testing.allocator;

  trie = std.ArrayList(ValueEntry).init(allocator);
  values = std.ArrayList(Value).init(allocator);
}

// Get then redirection for the request
fn getResponse(input: []const u8) ![]const u8 {
  if (input.len < 14) return error.BadRequest;

  var end = 4 + (std.mem.indexOfScalar(u8, input[4..], ' ') orelse return error.BadRequest);
  if (input[end-1] == '/') end -= 1;

  const location = input[4..end];
  if (input[0] == '~') {
    // TODO: implement Add to trie
    return error.Ok;
  }
  if (end == 4) return error.BadRequest;

  if(location.len == 0) {
    // TODO: Login page Maybe
  }

  if (@as(u32, @bitCast(input[0..4].*)) != @as(u32, @bitCast(@as([4]u8, "GET ".*)))) return error.BadRequest;

  // TODO: implement lookup
  return "https://ziglang.org";
}

// Identify weather the entry is a value (one that can have children) or a terminal entry
const EntryTag = enum(u1) {
  value,
  terminal,
};

// The terminal entry struct
const TerminalEntry = packed struct {
  // Offset of the value in the values array
  valueOffset: u32,
  // Kinda like short string optimization
  string: GetSizedArraylikeStruct(u7, 18),
  // Padding to make size same as ValueEntry
  padding: u1 = undefined,
  // Entry type tag
  tag: EntryTag = .terminal,
};

// The value entry struct
const ValueEntry = packed struct {
  // Offset of the value in the values array
  valueOffset: u32,
  // Offset from here (this entry) to the next entry
  nextOffset: u32,
  // which children exist
  fragments: GetSizedArraylikeStruct(u1, UrlTableSize) = GetSizedArraylikeStruct(u1, UrlTableSize).zeroValue(),
  // Number of bits set in fragments
  bitcount: u7 = 0,
  // Entry type tag
  tag: EntryTag = .value,
};

// A packed struct cant contain an array, so this is a workaround
fn GetSizedArraylikeStruct(comptime T: type, comptime size: usize) type {
  comptime std.debug.assert(@sizeOf(T) != 0);
  return packed struct {
    underlying: std.meta.Int(.unsigned, @sizeOf(T) * size),

    pub fn get(self: *const @This(), index: usize) T {
      std.debug.assert(index < size);
      return std.mem.readPackedIntNative(T, std.mem.asBytes(&self.underlying), @sizeOf(T) * index);
    }

    pub fn set(self: *@This(), index: usize, value: T) void {
      std.debug.assert(index < size);
      return std.mem.writePackedIntNative(T, std.mem.asBytes(&self.underlying), @sizeOf(T) * index, value);
    }

    pub fn zeroValue() @This() {
      return .{ .underlying = 0 };
    }
  };
}

// The value struct that is stored in the values array
const Value = struct {
  // The redirect destination
  dest: []const u8,
  // Time after which an entry must die (in seconds)
  deathat: u32,
};

// Total number of allowed characters in the url table
pub const UrlTableSize: u8 = 88; // = '[' - '!' + 'z' - 'a' + 5

// Converts a character to an index in the url table
pub fn charToIndex(in: u8) u8 {
  return switch (in) {
    '!'...'[' => in - '!',
    ']' => '[' - '!' + 1,
    '_' => '[' - '!' + 2,
    'a'...'z' => '[' - '!' + 3 + in - 'a',
    '~' => '[' - '!' + 'z' - 'a' + 4,
    else => return 255
  };
}

// Converts an index in the url table back to character
pub fn indexToChar(in: u8) u8 {
  return switch (in) {
    0...'['-'!' => in + '!',
    '['-'!'+1 => ']',
    '['-'!'+2 => '_',
    '['-'!'+3...'['-'!'+'z'-'a'+3 => in + '[' - '!' + 3 + 'a' - 'z',
    '['-'!'+'z'-'a'+4 => '~',
    else => return 255
  };
}

test "toIndex, fromIndex" {
  for (0..127) |char| {
    const idx = charToIndex(@intCast(char));
    if (idx == 255) continue;

    try std.testing.expect(idx < UrlTableSize);
    try std.testing.expect(indexToChar(idx) == char);
  }
}

test {
  std.testing.refAllDeclsRecursive(@This());
}

