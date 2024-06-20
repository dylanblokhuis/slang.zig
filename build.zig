const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const download_url = b.option([]const u8, "force-slang-release", "Force a specific release by providing a zip download URL from https://github.com/shader-slang/slang/releases/");
    _ = download_url; // autofix

    const mod = b.addModule("slang", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod.linkSystemLibrary("slang", .{});

    const exe = b.addExecutable(.{
        .name = "slang.zig",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    var download_step = DownloadBinaryStep.init(
        b,
        exe,
        Options{
            .download_url = "https://github.com/shader-slang/slang/releases/download/v2024.1.22/slang-2024.1.22-macos-x64.zip",
        },
    );
    exe.step.dependOn(&download_step.step);
    exe.root_module.addImport("slang", mod);

    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // // Creates a step for unit testing. This only builds the test executable
    // // but does not run it.
    // const lib_unit_tests = b.addTest(.{
    //     .root_source_file = b.path("src/root.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });

    // const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    // const exe_unit_tests = b.addTest(.{
    //     .root_source_file = b.path("src/main.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });

    // const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // // Similar to creating the run step earlier, this exposes a `test` step to
    // // the `zig build --help` menu, providing a way for the user to request
    // // running the unit tests.
    // const test_step = b.step("test", "Run unit tests");
    // test_step.dependOn(&run_lib_unit_tests.step);
    // test_step.dependOn(&run_exe_unit_tests.step);
}

pub const Options = struct {
    download_url: ?[]const u8,
};
pub const DownloadBinaryStep = struct {
    target: *std.Build.Step.Compile,
    options: Options,
    step: std.Build.Step,
    b: *std.Build,

    pub fn init(b: *std.Build, target: *std.Build.Step.Compile, options: Options) *DownloadBinaryStep {
        const download_step = b.allocator.create(DownloadBinaryStep) catch unreachable;
        download_step.* = .{
            .target = target,
            .options = options,
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = "download",
                .owner = b,
                .makeFn = &make,
            }),
            .b = b,
        };
        return download_step;
    }

    fn make(step: *std.Build.Step, prog_node: std.Progress.Node) anyerror!void {
        const download_step: *DownloadBinaryStep = @fieldParentPtr("step", step);
        const path_with_binaries = try downloadFromBinary(
            download_step.b,
            download_step.target,
            download_step.options,
            prog_node.start("Downloading release and extracting", 2),
        );
        download_step.target.addLibraryPath(.{
            .cwd_relative = path_with_binaries,
        });
    }
};

const GithubReleaseItem = struct {
    id: u64,
    name: []const u8,
    draft: bool,
    prerelease: bool,
    created_at: []const u8,
    published_at: []const u8,
    assets: []GithubReleaseAsset,
};

const GithubReleaseAsset = struct {
    id: u64,
    url: []const u8,
    name: []const u8,
    content_type: []const u8,
    state: []const u8,
    size: u64,
    created_at: []const u8,
    updated_at: []const u8,
    browser_download_url: []const u8,
};

var download_mutex = std.Thread.Mutex{};

pub fn downloadFromBinary(b: *std.Build, step: *std.Build.Step.Compile, options: Options, node: std.Progress.Node) ![]const u8 {
    // This function could be called in parallel. We're manipulating the FS here
    // and so need to prevent that.
    download_mutex.lock();
    defer download_mutex.unlock();

    const target = step.rootModuleTarget();
    var client: std.http.Client = .{
        .allocator = b.allocator,
    };
    try std.http.Client.initDefaultProxies(&client, b.allocator);

    const download_url = if (options.download_url != null) options.download_url.? else blk: {
        var body = std.ArrayList(u8).init(b.allocator);
        var server_header_buffer: [16 * 1024]u8 = undefined;
        const req = try client.fetch(.{
            .server_header_buffer = &server_header_buffer,
            .method = .GET,
            .location = .{ .url = "https://api.github.com/repos/shader-slang/slang/releases/latest" },
            .response_storage = .{
                .dynamic = &body,
            },
        });
        if (req.status != .ok) {
            var iter = std.http.HeaderIterator.init(&server_header_buffer);
            while (iter.next()) |header| {
                if (std.mem.eql(u8, header.name, "X-RateLimit-Remaining") and std.mem.eql(u8, header.value, "0")) {
                    std.log.err("Github API rate limit exceeded, wait 30 minutes\n", .{});
                    return error.GithubApiRateLimitExceeded;
                }
            }

            std.log.err("Failed to fetch slang releases: {}\n", .{req.status});
            return error.FailedToFetchGithubReleases;
        }

        const release = std.json.parseFromSliceLeaky(GithubReleaseItem, b.allocator, body.items, .{
            .ignore_unknown_fields = true,
        }) catch |err| {
            std.log.err("Failed to parse slang release JSON: {}\n", .{err});
            return error.FailedToParseGithubReleaseJson;
        };
        std.debug.assert(release.name[0] == 'v');

        for (release.assets) |asset| {
            const tar_name = b.fmt("slang-{s}-{s}-{s}.zip", .{
                release.name[1..],
                @tagName(target.os.tag),
                // slang is naming the triplet different for macos smh..
                if (target.os.tag == .macos and target.cpu.arch == .x86_64) "x64" else @tagName(target.cpu.arch),
            });
            if (std.mem.endsWith(u8, asset.name, tar_name)) {
                std.log.info("found asset: {s}\n", .{asset.name});
                break :blk asset.browser_download_url;
            }
        }

        return error.FailedToFindSlangRelease;
    };

    std.debug.assert(b.cache_root.path != null);

    const cache_dir = try std.fs.path.join(b.allocator, &.{ b.cache_root.path.?, "slang-release" });
    try std.fs.cwd().makePath(cache_dir);

    // download zip release file
    const zip_file_path = blk: {
        const zip_path = try std.fs.path.join(b.allocator, &.{ cache_dir, "slang.zip" });
        var body = std.ArrayList(u8).init(b.allocator);
        const response = try client.fetch(.{
            .method = .GET,
            .location = .{ .url = download_url },
            .response_storage = .{
                .dynamic = &body,
            },
            .max_append_size = 50 * 1024 * 1024,
        });
        if (response.status != .ok) {
            std.log.err("Failed to download slang release: {}\n", .{response.status});
            return error.FailedToDownloadSlangRelease;
        }

        const target_file = try std.fs.cwd().createFile(zip_path, .{});
        defer target_file.close();
        try target_file.writeAll(body.items);
        node.completeOne();

        break :blk zip_path;
    };

    // unzip the just downloaded zip file to a directory
    const extracted_dir_path = blk: {
        var file = try std.fs.openFileAbsolute(zip_file_path, .{ .mode = .read_only });
        defer file.close();

        const extract_dir_path = try std.fs.path.join(b.allocator, &.{ cache_dir, "slang" });
        try std.fs.cwd().makePath(extract_dir_path);

        var extract_dir = try std.fs.openDirAbsolute(extract_dir_path, .{});
        defer extract_dir.close();

        try std.zip.extract(extract_dir, file.seekableStream(), .{});
        node.completeOne();
        break :blk extract_dir_path;
    };

    const dir_with_binaries = blk: {
        const dir = try std.fs.cwd().openDir(extracted_dir_path, .{
            .iterate = true,
        });

        var iter = try dir.walk(b.allocator);
        defer iter.deinit();

        var release_dir_path: ?[]const u8 = null;
        while (try iter.next()) |entry| {
            if (entry.kind == .directory and std.mem.eql(u8, entry.basename, "release")) {
                release_dir_path = try std.fs.path.join(b.allocator, &.{ extracted_dir_path, entry.path });
                break;
            }
        }

        if (release_dir_path == null) {
            return error.FailedToFindSlangReleaseDir;
        }

        break :blk release_dir_path.?;
    };

    return dir_with_binaries;
}
