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
    const val = std.mem.trim(u8, line[i+1 ..], " ");
    if (key.len == 0 or val.len == 0) continue;
    if (val[0] == '"' or val[0] == '\'') @compileError("Values cannot be escaped i.e. cannot start or end with \" or '");
    kvpList = kvpList ++ .{ .{ .@"0" = key, .@"1" = val } };
  }
  return std.StaticStringMap([]const u8).initComptime(kvpList);
}

