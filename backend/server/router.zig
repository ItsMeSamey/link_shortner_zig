//! A kind of router if you can call it that
const std = @import("std");
const ReidrectionMap = @import("../redirections/redirectionMap.zig");
const ResponseWriter = @import("responseWriter.zig");
const parseHeaders = @import("headerParser.zig").parseHeaders;

const auth = @import("../env/env.zig").auth;
const allowedMethods = "GET,POST,OPTIONS,~~~0,~~~1,~~~2,~~~3";
const allowedHeaders = "auth,dest,death";
const corsResponse = "HTTP/1.1 200\r\nAccess-Control-Allow-Origin:*\r\nAccess-Control-Allow-Methods:" ++ allowedMethods ++ "\r\nAccess-Control-Allow-Headers:" ++ allowedHeaders ++ "\r\nConnection:close\r\n\r\n";

// The global redirections map
var rmap: ReidrectionMap = undefined;
pub fn initRmap(allocator: std.mem.Allocator) void {
  rmap = ReidrectionMap.init(allocator);
}

// Get then redirection for the request
pub fn sendResponse(input: []u8, responseWriter: ResponseWriter) !void {
  if (input.len <= 14) return responseWriter.writeError(400);
  if (input[0] == '~' and input[1] == '~' and input[2] == '~') return adminRequest(input, responseWriter);

  var location = input[2+(std.mem.indexOfScalar(u8, input[0..12], ' ') orelse return responseWriter.writeError(400)) ..];
  location.len = std.mem.indexOfScalar(u8, location, ' ') orelse return responseWriter.writeError(400);

  // The requests has no sub-path
  if(location.len == 0) return zeroLengthNormalRequest(input, responseWriter);

  if (@as(u32, @bitCast(input[0..4].*)) != @as(u32, @bitCast(@as([4]u8, "GET ".*)))) {
    if (@as(u32, @bitCast(input[0..4].*)) == @as(u32, @bitCast(@as([4]u8, "OPTI".*)))) {
      return responseWriter.writer.writeAll(corsResponse);
    } else {
      return responseWriter.writeError(404);
    }
  }
  return responseWriter.writeRedirection(
    (rmap.lookup(location) orelse return responseWriter.writeError(404)).dest()
  );
}

fn zeroLengthNormalRequest(input: []u8, responseWriter: ResponseWriter) !void {
  switch (@as(u32, @bitCast(input[0..4].*))) {
    @as(u32, @bitCast(@as([4]u8, "OPTI".*))) => {
      return responseWriter.writer.writeAll(corsResponse);
    },
    @as(u32, @bitCast(@as([4]u8, "GET ".*))) => {
      // Server the admin panel page
      return responseWriter.writeString(@embedFile("../dist/index.html"));
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

  // First line is the request `[METHOD] [PATH] HTTP/1.1`
  const first = headersIterator.next() orelse return responseWriter.writeError(400);

  // Extract the path from first line
  var location = first[2+(std.mem.indexOfScalar(u8, first[0..12], ' ') orelse return responseWriter.writeError(400)) ..];
  location.len = std.mem.indexOfScalar(u8, location, ' ') orelse return responseWriter.writeError(400);
  if (location.len > 0 and location[location.len - 1] == '/') location.len -= 1;

  if (location.len != 0) {
    switch (first[3]) {
      '0' => {
        // Add / Set an entry to the Map

        const Headers = parseHeaders(enum{auth, dest, death}, &headersIterator) catch return responseWriter.writeError(400);
        if (!std.mem.eql(u8, Headers.auth, auth)) return responseWriter.writeError(401);

        const death = std.fmt.parseInt(ReidrectionMap.TimestampType, Headers.death, 10) catch return responseWriter.writeError(400);
        rmap.add(location, Headers.dest, death) catch return responseWriter.writeError(500);

        return responseWriter.writeError(200);
      },
      '1' => {
        // Delete an entry from the Map
        // This will always succeed network errors notwithstanding
        const Headers = parseHeaders(enum{auth}, &headersIterator) catch return responseWriter.writeError(400);
        if (!std.mem.eql(u8, Headers.auth, auth)) return responseWriter.writeError(401);

        if (rmap.remove(location)) return responseWriter.writeError(200);
        // Entry didnt even exist but okk!
        return responseWriter.writeError(202);
      },
      '2' => {
        // Get Entries from the Map
        // Expect location to be in the format of `[from].[len]`
        // eg `0.10` will return the first 10 entries`
        // The response will end in a number, that number should be provided as from to get the next entries
        // (that number is random for all intents and purposes), therefore to get nth entry, you need to get all the entries before too
        // The response will be of the following format
        // `[Location]\0[Redirection]\n...[Location]\0[Redirection]\n[NextKey]`

        // Veriy auth header
        const Headers = parseHeaders(enum{auth}, &headersIterator) catch return responseWriter.writeError(400);
        if (!std.mem.eql(u8, Headers.auth, auth)) return responseWriter.writeError(401);

        var mapIterator = rmap.map.iterator();
        var locationSplitIterator = std.mem.splitScalar(u8, location, '.');

        const fromStr = locationSplitIterator.next() orelse return responseWriter.writeError(400);
        const from = std.fmt.parseInt(u32, fromStr, 10) catch return responseWriter.writeError(400);

        const lenStr = locationSplitIterator.next() orelse return responseWriter.writeError(400);
        const len = std.fmt.parseInt(u32, lenStr, 10) catch return responseWriter.writeError(400);

        if (from >= rmap.map.capacity()) return responseWriter.writeError(404);
        mapIterator.index = from;

        return responseWriter.writeMapIterator(&mapIterator, len);
      },
      '3' => {
        // getModificarionsSince

        // Veriy auth header
        const Headers = parseHeaders(enum{auth}, &headersIterator) catch return responseWriter.writeError(400);
        if (!std.mem.eql(u8, Headers.auth, auth)) return responseWriter.writeError(401);

        const sortCtx = struct {
          target: ReidrectionMap.TimestampType,
          fn compareFn(ctx: @This(), a: ReidrectionMap.ModificationWithTimestamp) std.math.Order {
            return std.math.order(a.index, ctx.target);
          }
        };

        var iterator = rmap.modification.getIteratorAfter(sortCtx{
          .target = std.fmt.parseInt(ReidrectionMap.TimestampType, location, 10) catch return responseWriter.writeError(400)
        }, sortCtx.compareFn);

        return responseWriter.writeMapModificationIterator(&iterator);
      },
      else => {},
    }
    return responseWriter.writeError(404);
  }

  // Veriy auth header
  const Headers = parseHeaders(enum{auth}, &headersIterator) catch return responseWriter.writeError(400);
  if (!std.mem.eql(u8, Headers.auth, auth)) return responseWriter.writeError(401);

  switch (first[3]) {
    '0' => {
      // Return the number of entries in the Map
      // A simple number is returned as body

      var buf: [10]u8 = undefined;
      const len = std.fmt.formatIntBuf(buf[0..], @as(u32, rmap.map.count()), 10, .lower, .{});
      try responseWriter.writeString(buf[0..len]);
    },
    '1' => {
      // getOldestModificationIndex

      try std.fmt.format(responseWriter.writer, "{x}", .{ if (rmap.modification.getOldest()) |e| e.index else 0 });
    },
    '2' => {
      // getLatestModificationIndex

      try std.fmt.format(responseWriter.writer, "{x}", .{ rmap.modificationIndex });
    },
    '3' => {
      // getAllModifications

      var iterator = rmap.modification.getBeginningIterator();
      return responseWriter.writeMapModificationIterator(&iterator);
    },
    else => {},
  }
  return responseWriter.writeError(404);
}

