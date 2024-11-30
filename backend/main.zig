const std = @import("std");
const Server = @import("server/server.zig");
const Router = @import("server/router.zig");

var server: Server = undefined;

fn init(allocator: std.mem.Allocator) !void {
  Router.initRmap(allocator);

  server = try Server.init(.{ 0, 0, 0, 0 }, 8080);
  std.log.info("Server started at 0.0.0.0:8080", .{});
}

// The main function to start the server
pub fn main() !void {
  var gpa = std.heap.GeneralPurposeAllocator(.{}){};
  try init(gpa.allocator());

  while (true) {
    var buf: [2048]u8 = undefined;

    const conn = server.accept(buf[0..]) catch |e| {
      std.debug.print("accept failed with {s}\n", .{ @errorName(e) });
      continue;
    };
    defer conn.close();

    Router.sendResponse(conn.request, conn.responseWriter()) catch |e| {
      std.debug.print("error: {s}\n", .{ @errorName(e) });
    };
  }
}

