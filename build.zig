const std = @import("std");
const builtin = @import("builtin");
const slash = std.fs.path.sep;

// return true if binName is found in the PATH
fn existsBin(binName: []const u8) bool {
  const path = std.posix.getenvZ("PATH") orelse return false;
  var pathBuf: [std.posix.system.PATH_MAX]u8 = undefined;
  var iter = std.mem.tokenizeScalar(u8, path, ':');

  while (iter.next()) |pathFrgment| {
    if (pathFrgment.len == 0) continue;
    var from: usize = 0;

    if (pathBuf.len < pathFrgment.len + 1 + binName.len + 1) return false;

    @memcpy(pathBuf[from..][0..pathFrgment.len], pathFrgment);
    from += pathFrgment.len;
    if (pathFrgment[pathFrgment.len - 1] != slash) {
      pathBuf[from] = slash;
      from += 1;
    }
    @memcpy(pathBuf[from..][0..binName.len], binName);
    from += binName.len;
    pathBuf[from] = 0;

    std.posix.accessZ(@as([*:0]const u8, @ptrCast(&pathBuf)), std.posix.X_OK) catch continue;
    return true;
  }

  return false;
}

pub fn build(b: *std.Build) void {
  const target = b.standardTargetOptions(.{});
  const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSafe });

  // install dependencies step
  const installDepsNpm = b.addSystemCommand(&.{ "npm", "install" });
  installDepsNpm.setCwd(.{ .src_path = .{ .owner = b, .sub_path = "frontend" } });
  b.step("install_deps_npm", "Install npm dependencies").dependOn(&installDepsNpm.step);

  const installDepsBun = b.addSystemCommand(&.{ "bun", "install" });
  installDepsBun.setCwd(.{ .src_path = .{ .owner = b, .sub_path = "frontend" } });
  b.step("install_deps_bun", "Install bun dependencies").dependOn(&installDepsBun.step);

  const installDepsAuto = b.step("install_deps", "Install dependencies, automatiaclly detect if bun or npm is in path (bun is preferred)");
  const buildFrontend = b.step("build_frontend", "Build the frontend using npm and vite");

  // Select the proper package manager
  if (existsBin("bun")) {
    installDepsAuto.dependOn(&installDepsBun.step);

    const vite = b.addSystemCommand(&.{ "bunx", "vite", "build" });
    vite.setCwd(.{ .src_path = .{ .owner = b, .sub_path = "frontend" } });
    buildFrontend.dependOn(&vite.step);
  } else if (existsBin("npm")) {
    installDepsAuto.dependOn(&installDepsNpm.step);

    const vite = b.addSystemCommand(&.{ "npx", "vite", "build" });
    vite.setCwd(.{ .src_path = .{ .owner = b, .sub_path = "frontend" } });
    buildFrontend.dependOn(&vite.step);
  } else {
    const failStep = b.addFail("No package manager found in PATH, please install bun or npm");

    installDepsAuto.dependOn(&failStep.step);
    buildFrontend.dependOn(&failStep.step);
  }

  // build backend Step
  const exe = b.addExecutable(.{
    .name = "backend",
    .root_source_file = b.path("backend/main.zig"),
    .target = target,
    .optimize = optimize,
  });
  exe.step.dependOn(buildFrontend);
  b.installArtifact(exe);
  b.step("build", "Build the frontend and install the backend").dependOn(&exe.step);

  // run step
  const run_cmd = b.addRunArtifact(exe);
  run_cmd.step.dependOn(b.getInstallStep());
  const run_step = b.step("run", "Run the application");
  run_step.dependOn(&run_cmd.step);

  // test step
  const exe_unit_tests = b.addTest(.{
    .root_source_file = b.path("backend/main.zig"),
    .target = target,
    .optimize = optimize,
  });
  const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
  const test_step = b.step("test", "Run unit tests");
  test_step.dependOn(&run_exe_unit_tests.step);
}

