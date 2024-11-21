const std = @import("std");
const linux = std.os.linux;

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

const EntryTag = enum(u1) {
  value,
  terminal,
};

const TerminalEntry = packed struct {
  valueOffset: u32,
  string: [18]u7,
  padding: u1,
  tag: EntryTag,
};

const ValueEntry = packed struct {
  valueOffset: u32,
  nextOffset: u32,
  fragments: [UrlTableSize]u1,
  bitcount: u7,
  tag: EntryTag,

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

var globalTrie: std.ArrayList(ValueEntry) = undefined;

test "toIndex, fromIndex" {
  std.debug.print("{d}\n", .{ ValueEntry.UrlTableSize });
  for (0..127) |char| {
    const idx = ValueEntry.CharToIndex(@intCast(char));
    if (idx == 255) continue;

    std.testing.expect(idx < ValueEntry.UrlTableSize);
    std.testing.expect(ValueEntry.IndexToChar(idx) == char);
  }
}

test {
  std.testing.refAllDeclsRecursive(@This());
}

