test { std.testing.refAllDeclsRecursive(@This()); }

const std = @import("std");
const linux = std.os.linux;

// The server struct
const Server = struct {
  // fd of Socket that is listening
  sock: i32,

  // init the server
  pub fn init(comptime ip: [4]u8, comptime port: u16) !Server {
    const addr: linux.sockaddr = @bitCast(linux.sockaddr.in {
      .family = linux.AF.INET,
      .addr = std.mem.nativeToBig(u32, @bitCast(ip)),
      .port = std.mem.nativeToBig(u16, port),
    });

    const sock: i32 = @intCast(linux.socket(linux.AF.INET, linux.SOCK.STREAM, 0));
    if (sock == 0) {
      std.debug.print("socket failed\n", .{});
      return error.SocketError;
    }
    errdefer _ = linux.close(sock);

    var err: usize = undefined;

    // Make the socket reusable
    err = linux.setsockopt(sock, linux.SOL.SOCKET, linux.SO.REUSEADDR, &std.mem.toBytes(@as(u32, 1)), @sizeOf(u32));
    if (err != 0) {
      std.debug.print("setsockopt failed ({x})\n", .{ err });
      return error.SocketOptionError;
    }

    err = linux.bind(sock, &addr, @sizeOf(@TypeOf(addr)));
    if (err != 0) {
      std.debug.print("socket bind failed ({x})\n", .{ err });
      return error.SocketBindError;
    }

    err = linux.listen(sock, linux.SOMAXCONN);
    if (err != 0) {
      std.debug.print("listen failed ({d})\n", .{ err });
      return error.ListenError;
    }

    return .{ .sock = sock };
  }

  // Wait for accept and return the client and request
  pub fn accept(self: *Server, buf: []u8) !struct{
    client: i32,
    request: []u8,

    pub fn close(conn: *const @This()) void {
      _ = linux.close(conn.client);
    }
  } {
    const client: i32 = @intCast(linux.accept(self.sock, null, null));
    if (client < 0) return error.AcceptError;
    errdefer _ = linux.close(client);

    const n = linux.read(client, buf.ptr, buf.len);
    if (n == 0) return error.ReadError;

    return .{ .client = client, .request = buf[0..n] };
  }

  // Deinit the server
  pub fn deinit(self: *Server) void {
    _ = linux.close(self.sock);
  }
};

// The value struct that is stored in the values array
const Value = struct {
  // The redirect destination
  dest: []const u8,
  // Time (in seconds) after which an entry must die
  deathat: u32,
};

const ReidrectionMap = struct {
  map: Map,

  const Map = std.HashMap([]const u8, Value, struct {
    pub fn hash(_: @This(), key: []const u8) u64 {
      var retval: u64 = 0;
      for (0.., key) |i, c| {
        retval = (retval << @intCast(i&7)) ^ (retval >> @intCast(64 ^ (i&63)));
        retval ^= c;
      }
      return retval;
    }
    pub fn eql(_: @This(), a: []const u8, b: []const u8) bool {
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
  }, std.hash_map.default_max_load_percentage);

  pub fn init(allocator: std.mem.Allocator) ReidrectionMap {
    return .{
      .map = Map.init(allocator),
    };
  }

  pub fn add(self: *ReidrectionMap, location: []const u8, dest: []const u8, deathat: u32) !void {
    return self.map.put(location, .{
      .dest = dest,
      .deathat = deathat,
    });
  }

  pub fn lookup(self: *ReidrectionMap, location: []const u8) ?[]const u8 {
    return if (self.map.get(location)) |v| v.dest else null;
  }

  pub fn remove(self: *ReidrectionMap, location: []const u8) void {
    _ = self.map.remove(location);
  }

  pub fn deinit(self: *ReidrectionMap) void {
    self.map.deinit();
  }
};

var server: Server = undefined;
var rmap: ReidrectionMap = undefined;

// The main function to start the server
pub fn main() !void {
  comptime if (@import("builtin").os.tag != .linux) @compileError("Only Linux is supported");

  server = try Server.init(.{ 0, 0, 0, 0 }, 8080);

  var gpa = std.heap.GeneralPurposeAllocator(.{}){};
  rmap = ReidrectionMap.init(gpa.allocator());

  while (true) {
    var buf: [2048]u8 = undefined;

    const conn = server.accept(buf[0..]) catch |e| {
      std.debug.print("accept failed with {s}\n", .{ @errorName(e) });
      continue;
    };

    defer conn.close();

    const response = getResponse(conn.request) catch |e| {
      const resp = switch (e) {
        error.Ok => "HTTP/1.1 200\r\nConnection:close\r\n\r\n",
        error.BadRequest => "HTTP/1.1 400\r\nConnection:close\r\n\r\n",
        error.Unauthorized => "HTTP/1.1 401\r\nConnection:close\r\n\r\n",
        error.NotFound => "HTTP/1.1 404\r\nConnection:close\r\n\r\n",
        else => "HTTP/1.1 500\r\nConnection:close\r\n\r\n",
      };
      _ = linux.write(conn.client, resp.ptr, resp.len);
      continue;
    };

    _ = linux.write(conn.client, "HTTP/1.1 302\r\nConnection:close\r\nLocation:", 41);
    _ = linux.write(conn.client, response.ptr, response.len);
    _ = linux.write(conn.client, "\r\n\r\n", 4);
  }
}

// Get then redirection for the request
fn getResponse(input: []u8) ![]const u8 {
  if (input.len < 14) return error.BadRequest;

  var end = 4 + (std.mem.indexOfScalar(u8, input[4..], ' ') orelse return error.BadRequest);
  if (input[end-1] == '/') end -= 1;
  const location = input[4..end];

  if (input[0] != '~' or input[1] != '~' or input[2] != '~') {
    if(location.len == 0) {
      // TODO: Login page Maybe
    }

    if (@as(u32, @bitCast(input[0..4].*)) != @as(u32, @bitCast(@as([4]u8, "GET ".*)))) return error.BadRequest;
    return rmap.lookup(location) orelse error.NotFound;
  }

  if (location.len == 0) return error.BadRequest;

  var headers = std.mem.tokenizeAny(u8, input, "\r\n");
  _ = headers.next() orelse return error.BadRequest;

  const Header = struct {
    key: KeyEnum,
    val: []const u8,

    const KeyEnum = enum {
      auth,
      dest,
      deth,
      unknown,
    };

    fn parse(header: []u8) !@This() {
      const i = std.mem.indexOfScalar(u8, header, ':') orelse return error.BadRequest;
      const key = std.mem.trim(u8, std.ascii.lowerString(header[0..i], header[0..i]), " ");
      return .{
        .key = std.meta.stringToEnum(KeyEnum, key) orelse .unknown,
        .val = std.mem.trim(u8, header[i+1 ..], " "),
      };
    }
  };

  var Headers = struct {
    auth: []const u8,
    dest: []const u8,
    deth: []const u8,
    found: u8,
  }{
    .auth = "",
    .dest = "",
    .deth = "",
    .found = 0,
  };

  while (Headers.found < 3) {
    const h = headers.next() orelse return error.BadRequest;
    const header = Header.parse(@constCast(h)) catch |e| return e;
    Headers.found += 1;
    switch (header.key) {
      .auth => if (Headers.auth.len == 0) { Headers.auth = header.val; Headers.found += 1; } else return error.BadRequest,
      .dest => if (Headers.dest.len == 0) { Headers.dest = header.val; Headers.found += 1; } else return error.BadRequest,
      .deth => if (Headers.deth.len == 0) { Headers.deth = header.val; Headers.found += 1; } else return error.BadRequest,
      else => {},
    }
  }

  if (!std.mem.eql(u8, Headers.auth, auth)) return error.Unauthorized;

  const dest = Headers.dest;
  const deathat = std.fmt.parseInt(u32, Headers.deth, 10) catch return error.BadRequest;
  try rmap.add(location, dest, deathat);

  return error.Ok;
}

const env = @import("loadKvp.zig").loadKvpComptime(@embedFile(".env"));
const auth = env.get("AUTH").?;

