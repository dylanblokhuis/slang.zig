const std = @import("std");
const slang = @import("slang");

pub fn main() !void {
    const session = slang.spCreateSession();
    defer slang.spDestroySession(session);
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)

    const req = slang.spCreateCompileRequest(session);
    defer slang.spDestroyCompileRequest(req);

    const profile_id = slang.spFindProfile(session, "spirv_1_5");

    const index = slang.spAddCodeGenTarget(req, .SLANG_SPIRV);
    slang.spSetTargetProfile(req, index, profile_id);
    slang.spSetTargetFlags(req, index, .SLANG_TARGET_FLAG_GENERATE_SPIRV_DIRECTLY);

    const translation_index = slang.spAddTranslationUnit(req, .SLANG_SOURCE_LANGUAGE_SLANG, "".ptr);
    slang.spAddTranslationUnitSourceFile(req, translation_index, "./hello-world.slang".ptr);

    const entry_point_index = slang.spAddEntryPoint(req, translation_index, "computeMain", .SLANG_STAGE_COMPUTE);

    const res = slang.spCompile(req);
    std.debug.print("{}\n", .{res.hasSucceeded()});

    var size_out: usize = undefined;
    const ptr = slang.spGetEntryPointCode(req, entry_point_index, &size_out);
    _ = ptr; // autofix

    std.debug.print("{d}", .{size_out});

    // std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
}
