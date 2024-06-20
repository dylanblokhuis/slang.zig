const std = @import("std");
const log = std.log.scoped(.slang);

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

    const download_url = b.option([]const u8, "slang-override-download", "Force a specific release by providing a zip download URL from https://github.com/shader-slang/slang/releases/");

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
            .download_url = download_url,
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
}

pub const Options = struct {
    release_version: []const u8 = "160229789",
    download_url: ?[]const u8 = null,
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
        const allocator = download_step.b.allocator;

        const cache_dir_path = try std.fs.path.join(allocator, &.{ download_step.b.cache_root.path.?, "slang-release" });
        try std.fs.cwd().makePath(cache_dir_path);
        var cache_dir = try std.fs.openDirAbsolute(cache_dir_path, .{});
        defer cache_dir.close();
        errdefer {
            log.err("Cleaning up...", .{});
            std.fs.deleteTreeAbsolute(cache_dir_path) catch |err| {
                log.err("Failed to cleanup cache dir: {}", .{err});
            };
        }

        const target = download_step.target.rootModuleTarget();
        const cache_file_name = download_step.b.fmt("{s}-{s}-{s}", .{
            download_step.options.release_version,
            @tagName(target.os.tag),
            @tagName(target.cpu.arch),
        });

        const linkable_path = cache_dir.readFileAlloc(allocator, cache_file_name, std.math.maxInt(usize)) catch blk: {
            const path_with_binaries = try downloadFromBinary(
                download_step.b,
                download_step.target,
                download_step.options,
                prog_node.start("Downloading release and extracting", 2),
                cache_dir,
            );

            try cache_dir.writeFile(.{
                .sub_path = cache_file_name,
                .data = path_with_binaries,
            });

            break :blk path_with_binaries;
        };

        std.debug.assert(linkable_path.len > 0);

        download_step.target.addLibraryPath(.{
            .cwd_relative = linkable_path,
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

pub fn downloadFromBinary(b: *std.Build, step: *std.Build.Step.Compile, options: Options, node: std.Progress.Node, cache_dir: std.fs.Dir) ![]const u8 {
    // This function could be called in parallel. We're manipulating the FS here
    // and so need to prevent that.
    download_mutex.lock();
    defer download_mutex.unlock();

    const target = step.rootModuleTarget();
    var client: std.http.Client = .{
        .allocator = b.allocator,
    };
    try std.http.Client.initDefaultProxies(&client, b.allocator);

    const archive_extension = ".zip";
    const slang_os_arch_combo: []const u8 = switch (target.os.tag) {
        .windows => switch (target.cpu.arch) {
            .x86_64 => "win64",
            .x86 => "win32",
            .aarch64 => "win-arm64",
            else => return error.UnsupportedTarget,
        },
        .macos => switch (target.cpu.arch) {
            .x86_64 => "macos-x64",
            .aarch64 => "macos-aarch64",
            else => return error.UnsupportedTarget,
        },
        .linux => switch (target.cpu.arch) {
            .x86_64 => "linux-x86_64",
            .aarch64 => "linux-aarch64",
            else => return error.UnsupportedTarget,
        },
        else => return error.UnsupportedTarget,
    };

    const download_url, const archive_name = if (options.download_url != null) blk: {
        break :blk .{
            options.download_url.?,
            b.fmt("slang-{s}-{s}{s}", .{
                options.release_version,
                slang_os_arch_combo,
                archive_extension,
            }),
        };
    } else blk: {
        var body = std.ArrayList(u8).init(b.allocator);
        var server_header_buffer: [16 * 1024]u8 = undefined;

        const url = b.fmt("https://api.github.com/repos/shader-slang/slang/releases/{s}", .{options.release_version});
        const req = try client.fetch(.{
            .server_header_buffer = &server_header_buffer,
            .method = .GET,
            .location = .{ .url = url },
            .response_storage = .{
                .dynamic = &body,
            },
        });
        if (req.status != .ok) {
            var iter = std.http.HeaderIterator.init(&server_header_buffer);
            while (iter.next()) |header| {
                if (std.mem.eql(u8, header.name, "X-RateLimit-Remaining") and std.mem.eql(u8, header.value, "0")) {
                    log.err("Github API rate limit exceeded, wait 30 minutes", .{});
                    return error.GithubApiRateLimitExceeded;
                }
            }

            log.err("Failed to fetch slang releases: {}", .{req.status});
            return error.FailedToFetchGithubReleases;
        }

        const release = std.json.parseFromSliceLeaky(GithubReleaseItem, b.allocator, body.items, .{
            .ignore_unknown_fields = true,
        }) catch |err| {
            log.err("Failed to parse slang release JSON: {}", .{err});
            return error.FailedToParseGithubReleaseJson;
        };
        std.debug.assert(release.name[0] == 'v');

        const tar_name = b.fmt("slang-{s}-{s}{s}", .{
            release.name[1..],
            slang_os_arch_combo,
            archive_extension,
        });

        for (release.assets) |asset| {
            if (std.mem.endsWith(u8, asset.name, tar_name)) {
                break :blk .{ asset.browser_download_url, asset.name };
            }
        }

        log.err("Failed to find slang release for: {s}", .{tar_name});
        return error.FailedToFindSlangRelease;
    };

    std.debug.assert(b.cache_root.path != null);

    // download zip release file
    {
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
            log.err("Failed to download slang release: {}", .{response.status});
            return error.FailedToDownloadSlangRelease;
        }

        const target_file = try cache_dir.createFile(archive_name, .{});
        defer target_file.close();

        try target_file.writeAll(body.items);
        node.completeOne();
    }

    // unzip the just downloaded zip file to a directory
    var file = try cache_dir.openFile(archive_name, .{ .mode = .read_only });
    defer file.close();
    defer cache_dir.deleteFile(archive_name) catch unreachable;

    const extract_dir_name = try std.mem.replaceOwned(u8, b.allocator, archive_name, archive_extension, "");
    try cache_dir.makePath(extract_dir_name);

    var extract_dir = try cache_dir.openDir(extract_dir_name, .{
        .iterate = true,
    });
    defer extract_dir.close();

    try std.zip.extract(extract_dir, file.seekableStream(), .{});

    // we try and find a folder called "release" in the extracted files
    // in the slang releases this is where the binaries are stored
    var iter = try extract_dir.walk(b.allocator);
    defer iter.deinit();

    var maybe_release_dir_path: ?[]const u8 = null;
    while (try iter.next()) |entry| {
        if (entry.kind == .directory and std.mem.eql(u8, entry.basename, "release")) {
            maybe_release_dir_path = try entry.dir.realpathAlloc(b.allocator, entry.basename);
            break;
        }
    }

    if (maybe_release_dir_path) |path| {
        node.completeOne();
        return path;
    }

    return error.FailedToFindSlangReleaseDir;
}
