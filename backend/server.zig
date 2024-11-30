const std = @import("std");
const linux = std.os.linux;

// fd of Socket that is listening
sock: i32,

const Server = @This();

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

// Struct returned on accepting connection
const AcceptResponse = struct{
  client: i32,
  request: []u8,

  pub fn close(conn: *const @This()) void {
    _ = linux.close(conn.client);
  }

  pub fn responseWriter(self: *const @This()) @import("responseWriter.zig") {
    return .{ .writer = self.anyWriter() };
  }

  fn anyWriter(client_self: *const @This()) std.io.AnyWriter {
    return .{
      .context = @ptrCast(client_self),
      .writeFn = struct {
        fn write(context: *const anyopaque, data: []const u8) !usize {
          const written = linux.write(@as(@TypeOf(client_self), @ptrCast(@alignCast(context))).client, data.ptr, data.len);
          if (written == 0) return error.Closed;
          if (@as(isize, @bitCast(written)) < 0) return error.WriteError;
          std.debug.assert(written < 1 << 16);
          return written;
        }
      }.write,
    };
  }
};

// Wait for accept and return the client and request
pub fn accept(self: *Server, buf: []u8) !AcceptResponse {
  const client: i32 = @intCast(linux.accept(self.sock, null, null));
  if (client < 0) return error.AcceptError;
  errdefer _ = linux.close(client);

  const n = linux.read(client, buf.ptr, buf.len);
  if (@as(isize, @bitCast(n)) < 0) return error.ReadError;

  return .{ .client = client, .request = buf[0..n] };
}

// Deinit the server
pub fn deinit(self: *Server) void {
  _ = linux.close(self.sock);
}

