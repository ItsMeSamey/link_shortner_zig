test { std.testing.refAllDeclsRecursive(@This()); }

const std = @import("std");
const linux = std.os.linux;
const TagType = @TypeOf(.enum_literal);
const Server = @import("server.zig");
const ReidrectionMap = @import("redirectionMap.zig");
const ResponseWriter = @import("responseWriter.zig");
const parseHeaders = @import("headerParser.zig").parseHeaders;

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

    sendResponse(conn.request, conn.responseWriter()) catch |e| {
      std.debug.print("error: {s}\n", .{ @errorName(e) });
    };
  }
}

// Get then redirection for the request
fn sendResponse(input: []u8, responseWriter: ResponseWriter) !void {
  if (input.len <= 14) return responseWriter.writeError(400);

  if (input[0] == '~' and input[1] == '~' and input[2] == '~') return adminRequest(input, responseWriter);

  var location = input[5..];
  location.len = std.mem.indexOfScalar(u8, input[5..], ' ') orelse return responseWriter.writeError(400);
  if (location.len > 0 and location[location.len - 1] == '/') location.len -= 1;

  // The requests has no sub-path
  if(location.len == 0) return zeroLengthNormalRequest(input, responseWriter);

  if (@as(u32, @bitCast(input[0..4].*)) != @as(u32, @bitCast(@as([4]u8, "GET ".*)))) return responseWriter.writeError(404);
  return responseWriter.writeRedirection(
    (rmap.lookup(location) orelse return responseWriter.writeError(404)).dest()
  );
}

fn zeroLengthNormalRequest(input: []u8, responseWriter: ResponseWriter) !void {
  switch (@as(u32, @bitCast(input[0..4].*))) {
    @as(u32, @bitCast(@as([4]u8, "OPTI".*))) => {
      // TODO: Send cors response
      return responseWriter.writer.writeAll("HTTP/1.1 200\r\nAccess-Control-Allow-Origin:*\r\nAccess-Control-Allow-Methods:GET,POST,OPTIONS\r\nAccess-Control-Allow-Headers:Authorization\r\n\r\n");
    },
    @as(u32, @bitCast(@as([4]u8, "GET ".*))) => {
      // Server the admin panel page
      return responseWriter.writeString(@embedFile("./dist/index.html"));
    },
    @as(u32, @bitCast(@as([4]u8, "POST".*))) => {
      //Verify auth header, return 200 if correct
      var headersIterator = std.mem.tokenizeAny(u8, input, "\r\n");
      _ = headersIterator.next() orelse return responseWriter.writeError(400);
      const Headers = parseHeaders(enum{auth}, &headersIterator) catch return responseWriter.writeError(400);
      if (!std.mem.eql(u8, Headers.auth, auth)) return responseWriter.writeError(401);
      return responseWriter.writeError(200);
    },
    // Unsupported request
    else => return responseWriter.writeError(404),
  }
}

fn adminRequest(input: []u8, responseWriter: ResponseWriter) !void {
  var headersIterator = std.mem.tokenizeAny(u8, input, "\r\n");
  const first = headersIterator.next() orelse return responseWriter.writeError(400);
  var location = first[std.mem.indexOfScalar(u8, first, ' ') orelse return responseWriter.writeError(400) ..];
  location.len = std.mem.indexOfScalar(u8, location, ' ') orelse return responseWriter.writeError(400);
  if (location.len > 0 and location[location.len - 1] == '/') location.len -= 1;

  if (location.len == 0) {
    // Return the number of entries in the Map
    var buf: [12]u8 = undefined;
    const len = std.fmt.formatIntBuf(buf[0..], rmap.map.capacity(), 10, .lower, .{});
    try responseWriter.writeString(buf[0..len]);
  } else if (first[3] == ' ') {
    const Headers = parseHeaders(enum{auth, dest, death}, &headersIterator) catch return responseWriter.writeError(400);
    if (!std.mem.eql(u8, Headers.auth, auth)) return responseWriter.writeError(401);

    const death = std.fmt.parseInt(u32, Headers.death, 10) catch return responseWriter.writeError(400);
    rmap.add(location, Headers.dest, death) catch return responseWriter.writeError(500);

    return responseWriter.writeError(200);
  } else if (first[3] == 'v') {
    const Headers = parseHeaders(enum{auth}, &headersIterator) catch return responseWriter.writeError(400);
    if (!std.mem.eql(u8, Headers.auth, auth)) return responseWriter.writeError(401);

    var mapIterator = rmap.map.iterator();
    var locationSplitIterator = std.mem.splitScalar(u8, location, ' ');

    const fromStr = locationSplitIterator.next() orelse return responseWriter.writeError(400);
    const from = std.fmt.parseInt(u32, fromStr, 10) catch return responseWriter.writeError(400);

    const lenStr = locationSplitIterator.next() orelse return responseWriter.writeError(400);
    const len = std.fmt.parseInt(u32, lenStr, 10) catch return responseWriter.writeError(400);

    if (from >= rmap.map.capacity()) return responseWriter.writeError(404);
    mapIterator.index = from;

    return responseWriter.writeMapIterator(&mapIterator, len);
  }

  return responseWriter.writeError(404);
}

