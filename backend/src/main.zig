const std = @import("std");

const Entry = packed struct {
  nextOffset: u32,
  fragments: [UrlTableSize]u1,
  bitcount: u7,
  hasValue: u1,
  valueOffset: u32,

  pub const UrlTableSize: u8 = 88; // = '[' - '!' + 'z' - 'a' + 5

  pub fn CharToIndex(in: u8) u8 {
    return switch (in) {
      '!'...'[' => in - '!',
      ']' => '[' - '!' + 1,
      '_' => '[' - '!' + 2,
      'a'...'z' => '[' - '!' + 3 + in - 'a',
      '~' => '[' - '!' + 'z' - 'a' + 4,
      else => return 255
    };
  }

  pub fn IndexToChar(in: u8) u8 {
    return switch (in) {
      0...'['-'!' => in + '!',
      '['-'!'+1 => ']',
      '['-'!'+2 => '_',
      '['-'!'+3...'['-'!'+'z'-'a'+3 => in + '[' - '!' + 3 + 'a' - 'z',
      '['-'!'+'z'-'a'+4 => '~',
      else => return 255
    };
  }
};

test "toIndex, fromIndex" {
  std.debug.print("{d}\n", .{ Entry.UrlTableSize });
  for (0..127) |char| {
    const idx = Entry.CharToIndex(@intCast(char));
    if (idx == 255) continue;

    std.testing.expect(idx < Entry.UrlTableSize);
    std.testing.expect(Entry.IndexToChar(idx) == char);
  }
}

const Trie = std.ArrayList(Entry);


fn getResponse(input: []const u8) ![]const u8 {
  const BadRequest = "HTTP/1.1 400\r\n\r\n";
  const Ok = "HTTP/1.1 200\r\n\r\n";

  if (input.len < 14) return BadRequest;
  if (input[0] == '~') {
    return Ok;
  }

  if (@as(u32, @bitCast(input)) != @as(u32, @bitCast("GET "))) return BadRequest;
  const location = input[4..input.len-9];
  _ = location;
  // lookup(location);



  return "HTTP/1.1 302\r\nLocation: " ++ "https://ziglang.org/" ++ "\r\n\r\n";
}


