//! An optimized header parser
const std = @import("std");

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
pub fn parseHeaders(comptime HeaderEnum: type, iterator: *std.mem.TokenIterator(u8, .any)) !HeadersStructFromFieldNames(HeaderEnum) {
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

    if (enumFields.len-1 == std.math.maxInt(@TypeOf(@intFromEnum(key)))) {
      switch (@intFromEnum(key)) {
        inline 0...enumFields.len-1 => |fieldValue| {
          if (@field(headers, enumFields[fieldValue].name).len == 0) {
            @field(headers, enumFields[fieldValue].name) = val;
            count += 1;
          } else {
            return error.DuplicateHeader;
          }
        },
      }
    } else {
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
  }
  return headers;
}

