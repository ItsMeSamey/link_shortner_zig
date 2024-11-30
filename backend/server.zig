const std = @import("std");
const posix = std.posix;

// fd of Socket that is listening
sock: i32,

const Server = @This();

// init the server
pub fn init(comptime ip: [4]u8, comptime port: u16) !Server {
  const addr: posix.sockaddr = @bitCast(posix.sockaddr.in {
    .family = posix.AF.INET,
    .addr = std.mem.nativeToBig(u32, @bitCast(ip)),
    .port = std.mem.nativeToBig(u16, port),
  });

  const sock: i32 = @intCast(try posix.socket(posix.AF.INET, posix.SOCK.STREAM, 0));
  if (sock == 0) {
    std.debug.print("socket failed\n", .{});
    return error.SocketError;
  }
  errdefer _ = posix.close(sock);

  // Make the socket reusable
  try posix.setsockopt(sock, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(u32, 1)));
  try posix.bind(sock, &addr, @sizeOf(@TypeOf(addr)));
  try posix.listen(sock, posix.system.SOMAXCONN);

  return .{ .sock = sock };
}

// Struct returned on accepting connection
const AcceptResponse = struct{
  client: posix.socket_t,
  request: []u8,

  pub fn close(conn: *const @This()) void {
    _ = posix.close(conn.client);
  }

  pub fn responseWriter(self: *const @This()) @import("responseWriter.zig") {
    return .{ .writer = self.anyWriter() };
  }

  fn anyWriter(client_self: *const @This()) std.io.AnyWriter {
    return .{
      .context = @ptrCast(client_self),
      .writeFn = struct {
        fn write(context: *const anyopaque, data: []const u8) !usize {
          return posix.write(@as(@TypeOf(client_self), @ptrCast(@alignCast(context))).client, data);
        }
      }.write,
    };
  }
};

// Wait for accept and return the client and request
pub fn accept(self: *Server, buf: []u8) !AcceptResponse {
  const client = try posix.accept(self.sock, null, null, 0);
  if (client < 0) return error.AcceptError;
  errdefer _ = posix.close(client);

  const n = try posix.read(client, buf[0..]);
  return .{ .client = client, .request = buf[0..n] };
}

// Deinit the server
pub fn deinit(self: *Server) void {
  _ = posix.close(self.sock);
}

