const std = @import("std");

pub fn loadKvpComptime(file: []const u8) std.StaticStringMap([]const u8) {
  @setEvalBranchQuota(10_000);
  var it = std.mem.tokenizeAny(u8, file, "\r\n");

  const pair = struct { @"0": []const u8, @"1": []const u8 };
  comptime var kvpList: []const pair = &.{};

  inline while (it.next()) |line| {
    if (line.len == 0) continue;

    const i = std.mem.indexOfScalar(u8, line, '=') orelse continue;
    const key = std.mem.trim(u8, line[0..i], " ");
    const tempVal = std.mem.trim(u8, line[i+1 ..], " ");
    var dataArr: [tempVal.len]u8 = undefined;
    const val = unescapeString(dataArr[0..], tempVal) catch |e| { @compileError(@errorName(e)); };
    if (key.len == 0 or val.len == 0) continue;
    if (val[0] == '"' or val[0] == '\'') @compileError("Values cannot be escaped i.e. cannot start or end with \" or '");
    kvpList = kvpList ++ .{ .{ .@"0" = key, .@"1" = val } };
  }
  return std.StaticStringMap([]const u8).initComptime(kvpList);
}

// Inescape function to handle escaped quotes in the value
fn unescapeString(result: []u8, val: []const u8) ![]const u8 {
  const logFn = if (!@inComptime()) std.log.warn else struct{
    fn log(fmt: []const u8, args: anytype) void {
      @compileError(std.fmt.comptimePrint(fmt, args));
    }
  }.log;

  if (val[0] != '"' and val[0] != '\'' and val[0] != '`') return val;

  // String must start and end with same kind of quotes
  if (val[0] != val[val.len - 1]) {
    logFn("Invalid string --> {s} <--, it must start and end with the same kind of quotes", .{val});
    return error.InvalidString;
  }

  switch (val[0]) {
    inline '"', '\'', '`' => |escapeChar| {
      const strippedVal = val[1..val.len - 1];
      var idx = 0;
      var resultIdx = 0;
      while (idx < strippedVal.len - 1) {
        if (strippedVal[idx] == escapeChar) {
          logFn("Invalid escape sequence {s} in --> {s} <--", .{ strippedVal[idx .. idx + 1], val });
          return error.InvalidString;
        } else if (strippedVal[idx] == '\\') {
          idx += 2;
          switch (strippedVal[idx + 1]) {
            'n' => result[resultIdx] = '\n',
            'r' => result[resultIdx] = '\r',
            't' => result[resultIdx] = '\t',
            '\\' => result[resultIdx] = '\\',
            escapeChar => result[resultIdx] = escapeChar,
            else => {
              logFn("Unexpected escape sequence {s} in --> {s} <--", .{ strippedVal[idx .. idx + 1], val });
            },
          }
        } else {
          idx += 1;
          result[resultIdx] = strippedVal[idx];
        }
        resultIdx += 1;
      }
    },
    else => unreachable,
  }
}

