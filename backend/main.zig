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


    fn writer(client_self: *const @This()) std.io.AnyWriter {
      return .{
        .context = @ptrCast(client_self),
        .writeFn = struct {
          fn write(context: *const anyopaque, data: []const u8) !usize {
            return linux.write(@as(@TypeOf(client_self), @ptrCast(@alignCast(context))).client, data.ptr, data.len);
          }
        }.write,
      };
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

// The value struct with redirection and timeout
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

const env = @import("loadKvp.zig").loadKvpComptime(@embedFile(".env"));
const auth = env.get("AUTH").?;

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

    getResponse(conn.request).send(conn.writer()) catch |e| {
      std.debug.print("error: {s}\n", .{ @errorName(e) });
    };
  }
}

const Response = union(enum) {
  redirection: []const u8,
  @"error": u16,
  html: []const u8,

  fn send(self: *const @This(), writer: std.io.AnyWriter) !void {
    switch (self.*) {
      .redirection => |redirection| try std.fmt.format(writer, "HTTP/1.1 302\r\nConnection:close\r\nLocation:{s}\r\n\r\n", .{ redirection }),
      .html => |html| try std.fmt.format(writer, "HTTP/1.1 200\r\nContent-Length:{d}\r\n\r\n{s}", .{ html.len, html }),
      .@"error" => |code| try std.fmt.format(writer, "HTTP/1.1 {d}\r\nConnection:close\r\n\r\n", .{ code }),
    }
  }
};


fn HeadersStructFromFieldNames(comptime headerNames: []const []const u8) type {
  comptime var fields: [headerNames.len]std.builtin.Type.StructField = undefined;
  inline for (0.., headerNames) |i, name| {
    comptime var newName: [name.len]u8 = undefined;
    std.ascii.lowerString(name, newName[0..]);

    fields[i] = .{
      .name = headerNames[i],
      .type = []const u8,
      .default_value = "",
      .is_comptime = false,
      .alignment = 0,
    };
  }

  return @Type(std.builtin.Type{
    .@"struct" = .{
      .layout = .auto,
      .fields = fields,
      .decls = &[_]std.builtin.Type.Declaration{},
      .is_tuple = false,
    }
  });
}

fn parseHeaders(comptime headerNames: []const []const u8, iterator: std.mem.TokenIterator(u8, .any)) !HeadersStructFromFieldNames(headerNames) {
  const HeaderType = HeadersStructFromFieldNames(headerNames);
  const HeaderEnum = std.meta.FieldEnum(HeaderType);
  var headers: HeaderType = undefined;

  var count = 0;
  while (count < headerNames.len) {
    const header = iterator.next() orelse return error.MissingHeaders!headers;

    const i = std.mem.indexOfScalar(u8, header, ':') orelse return error.BadRequest;

    // This is faster than direct inline for loop as stringToEnum uses a hash_map
    const keyString = std.mem.trim(u8, std.ascii.lowerString(header[0..i], header[0..i]), " ");
    const key = std.meta.stringToEnum(HeaderEnum, keyString) orelse continue;

    count += 1;
    const val = std.mem.trim(u8, header[i+1 ..], " ");

    inline for (@typeInfo(HeaderEnum).Enum.fields) |field| {
      if (@call(std.builtin.CallModifier.compile_time, std.mem.eql, .{ u8, field.name, @tagName(key) })) {
        @field(headers, field.name) = val;
        break;
      }
    }
  }
  return headers;
}

// Get then redirection for the request
fn getResponse(input: []u8) Response {
  if (input.len < 14) return .{ .@"error" = 400 };

  // All the normal requests
  if (input[0] != '~' or input[1] != '~' or input[2] != '~') {
    var end = 4 + (std.mem.indexOfScalar(u8, input[4..], ' ') orelse return .{ .@"error" = 400 });
    if (input[end-1] == '/') end -= 1;
    const location = input[4..end];

    if(location.len == 0) {
    }

    if (@as(u32, @bitCast(input[0..4].*)) != @as(u32, @bitCast(@as([4]u8, "GET ".*)))) return  .{ .@"error" = 400 };
    return .{ .redirection = rmap.lookup(location) orelse return .{ .@"error" = 404 } };
  }

  // Special Admin requests
  var headersIterator = std.mem.tokenizeAny(u8, input, "\r\n");
  const first = headersIterator.next() orelse return .{ .@"error" = 400 };

  if (first[4] == ' ') {
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
      const h = headersIterator.next() orelse return .{ .@"error" = 400 };
      const header = Header.parse(@constCast(h)) catch return .{ .@"error" = 400 };
      Headers.found += 1;
      switch (header.key) {
        .auth => if (Headers.auth.len == 0) { Headers.auth = header.val; Headers.found += 1; } else return .{ .@"error" = 400 },
        .dest => if (Headers.dest.len == 0) { Headers.dest = header.val; Headers.found += 1; } else return .{ .@"error" = 400 },
        .deth => if (Headers.deth.len == 0) { Headers.deth = header.val; Headers.found += 1; } else return .{ .@"error" = 400 },
        else => {},
      }
    }

    if (!std.mem.eql(u8, Headers.auth, auth)) return .{ .@"error" = 401 };

    // const dest = Headers.dest;
    // const deathat = std.fmt.parseInt(u32, Headers.deth, 10) catch return .{ .@"error" = 400 };
    // rmap.add(location, dest, deathat) catch return .{ .@"error" = 500 };

  }

  return .{ .@"error" = 200 };
}

