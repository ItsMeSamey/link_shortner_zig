test { std.testing.refAllDeclsRecursive(@This()); }

const std = @import("std");
const linux = std.os.linux;
const TagType = @TypeOf(.enum_literal);

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
const Key = struct {
  // location string followed by the dest string
  data: [*] const u8,
  // Time (in seconds) after which an entry must die
  deathat: u32,
  // Length of the location string
  keyLen: u16,
  // Length of the dest string
  valLen: u16,

  pub fn location(self: *const @This()) []const u8 {
    return self.data[0..self.keyLen];
  }
  pub fn dest(self: *const @This()) []const u8 {
    return self.data[self.keyLen..][0..self.valLen];
  }

  pub fn init(allocator: std.mem.Allocator, loc: []const u8, dst: []const u8, deathat: u32) !Key {
    const data = try allocator.alloc(u8, loc.len + dst.len);
    @memcpy(data[0..loc.len], loc);
    @memcpy(data[loc.len..], dst);
    return .{
      .data = data.ptr,
      .deathat = deathat,
      .keyLen = @intCast(loc.len),
      .valLen = @intCast(dst.len),
    };
  }
};

const ReidrectionMap = struct {
  map: Map,

  const MapContext = struct {
    pub fn hash(_: @This(), key: Key) u64 {
      var retval: u64 = 0;
      for (0.., key.location()) |i, c| {
        retval = (retval << @intCast(i&7)) ^ (retval >> @intCast(32 ^ (i&31)));
        retval ^= c;
      }
      return retval;
    }
    pub fn eql(_: @This(), l: Key, r: Key) bool {
      var a = l.location();
      var b = r.location();
      if (true) return std.mem.eql(u8, a, b);
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

    test "eql" {
      try std.testing.expect(eql(MapContext{}, "a", "a"));
      try std.testing.expect(eql(MapContext{}, "b", "b"));
      try std.testing.expect(eql(MapContext{}, "aa", "aa"));
      try std.testing.expect(!eql(MapContext{}, "a", "ab"));
      try std.testing.expect(!eql(MapContext{}, "ab", "a"));
      try std.testing.expect(!eql(MapContext{}, "aab", "baa"));
      try std.testing.expect(eql(MapContext{}, "/ab", "/ab"));
    }
  };
  const Map = std.HashMap(Key, void, MapContext, std.hash_map.default_max_load_percentage);

  pub fn init(allocator: std.mem.Allocator) ReidrectionMap {
    return .{
      .map = Map.init(allocator),
    };
  }

  pub fn add(self: *ReidrectionMap, location: []const u8, dest: []const u8, deathat: u32) !void {
    return self.map.put(try Key.init(self.map.allocator, location, dest, deathat), {});
  }

  pub fn lookup(self: *ReidrectionMap, location: []const u8) ?*Key {
    return self.map.getKeyPtr(.{ .data = location.ptr, .deathat = undefined, .keyLen = @intCast(location.len), .valLen = undefined, });
  }

  pub fn remove(self: *ReidrectionMap, location: []const u8) void {
    if (self.map.getKeyPtr(location)) |kptr| {
      self.map.allocator.free(kptr);
      self.map.removeByPtr(kptr);
    }
  }

  pub fn deinit(self: *ReidrectionMap) void {
    for (self.map.keys()) |key| self.map.allocator.free(key);
    self.map.deinit();
  }
};

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

fn HeadersStructFromFieldNames(comptime HeaderEnum: type) type {
  const enumFields = @typeInfo(HeaderEnum).@"enum".fields;
  comptime var fields: [enumFields.len]std.builtin.Type.StructField = undefined;

  comptime {
    for (enumFields, 0..) |field, i| {
      std.debug.assert(field.value == i);
      if (field.value > enumFields.len-1) {
        @compileError("Field " ++ field.name ++ " is out of bounds");
      }
    }
  }

  inline for (0.., enumFields) |i, field| {
    comptime var newName: [field.name.len:0]u8 = undefined;
    for (field.name, 0..) |char, idx| newName[idx] = std.ascii.toLower(char);
    
    fields[i] = .{
      .name = &newName,
      .type = []const u8,
      .default_value = null,
      .is_comptime = false,
      .alignment = 0,
    };
  }

  const structInfo: std.builtin.Type.Struct = .{
    .layout = .auto,
    .backing_integer = null,
    .fields = &fields,
    .decls = &[_]std.builtin.Type.Declaration{},
    .is_tuple = false,
  };
  return @Type(.{ .@"struct" = structInfo });
}

// iterator MUST be over a mutable slice, or the result is undefined
fn parseHeaders(comptime HeaderEnum: type, iterator: *std.mem.TokenIterator(u8, .any)) !HeadersStructFromFieldNames(HeaderEnum) {
  const HeaderType = HeadersStructFromFieldNames(HeaderEnum);
  const enumFields = @typeInfo(HeaderEnum).@"enum".fields;
  var headers: HeaderType = undefined;

  // Init to 0 length strings
  inline for (enumFields) |field| @field(headers, field.name) = "";

  var count: usize = 0;
  while (count < @typeInfo(HeaderEnum).@"enum".fields.len) {
    const headerString = iterator.next() orelse return error.MissingHeaders;

    const i = std.mem.indexOfScalar(u8, headerString, ':') orelse return error.BadRequest;

    // This is faster than direct inline for loop as stringToEnum uses a hash_map
    const keyString = std.mem.trim(u8, std.ascii.lowerString(@constCast(headerString[0..i]), headerString[0..i]), " ");
    const key = std.meta.stringToEnum(HeaderEnum, keyString) orelse continue;

    const val = std.mem.trim(u8, headerString[i+1 ..], " ");

    switch (@intFromEnum(key)) {
      inline 0...enumFields.len-1 => |fieldValue| {
        if (@field(headers, enumFields[fieldValue].name).len == 0) {
          @field(headers, enumFields[fieldValue].name) = val;
          count += 1;
        } else {
          return error.DuplicateHeader;
        }
      },
      else => unreachable,
    }
  }
  return headers;
}


// Get then redirection for the request
fn getResponse(input: []u8) Response {
  if (input.len <= 14) return .{ .@"error" = 400 };

  // All the normal requests
  if (input[0] != '~' or input[1] != '~' or input[2] != '~') {
    var location = input[5..];
    location.len = std.mem.indexOfScalar(u8, input[5..], ' ') orelse return .{ .@"error" = 400 };
    if (location.len > 0 and location[location.len - 1] == '/') location.len -= 1;

    // The requests has no sub-path
    if(location.len == 0) {
      if (@as(u32, @bitCast(input[0..4].*)) == @as(u32, @bitCast(@as([4]u8, "GET ".*)))) {
        // GET request
      } else if (@as(u32, @bitCast(input[0..4].*)) == @as(u32, @bitCast(@as([4]u8, "POST".*)))) {
        //Verify auth header
        var headersIterator = std.mem.tokenizeAny(u8, input, "\r\n");
        _ = headersIterator.next() orelse return .{ .@"error" = 400 };
        const Headers = parseHeaders(enum{auth}, &headersIterator) catch return .{ .@"error" = 400 };
        if (!std.mem.eql(u8, Headers.auth, auth)) return .{ .@"error" = 401 };
        return .{ .@"error" = 200 };
      }

      // Unsupported request
      return .{ .@"error" = 404 };
    }

    if (@as(u32, @bitCast(input[0..4].*)) != @as(u32, @bitCast(@as([4]u8, "GET ".*)))) return  .{ .@"error" = 404 };
    return .{ .redirection = (rmap.lookup(location) orelse return .{ .@"error" = 404 }).dest() };
  }

  // Special Admin requests
  var headersIterator = std.mem.tokenizeAny(u8, input, "\r\n");
  const first = headersIterator.next() orelse return .{ .@"error" = 400 };
  var location = first[std.mem.indexOfScalar(u8, first, ' ') orelse return .{ .@"error" = 400 } ..];
  location.len = std.mem.indexOfScalar(u8, location, ' ') orelse return .{ .@"error" = 400 };
  if (location.len > 0 and location[location.len - 1] == '/') location.len -= 1;

  if (first[3] == ' ' and location.len > 0) {
    const Headers = parseHeaders(enum{auth, dest, death}, &headersIterator) catch return .{ .@"error" = 400 };
    if (!std.mem.eql(u8, Headers.auth, auth)) return .{ .@"error" = 401 };

    const death = std.fmt.parseInt(u32, Headers.death, 10) catch return .{ .@"error" = 400 };
    rmap.add(location, Headers.dest, death) catch return .{ .@"error" = 500 };
  } else if (first[3] == ' ' and location.len == 0) {

  }

  return .{ .@"error" = 200 };
}


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

