const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const vaxis_dep = b.dependency("vaxis", .{
        .target = target,
        .optimize = optimize,
    });
    const vaxis_mod = vaxis_dep.module("vaxis");

    const core_mod = b.addModule("zvrl_core", .{
        .root_source_file = b.path("src/zvrl/core/mod.zig"),
        .target = target,
        .optimize = optimize,
    });

    const command_mod = b.addModule("zvrl_command", .{
        .root_source_file = b.path("src/zvrl/command/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zvrl_core", .module = core_mod },
        },
    });

    const execution_mod = b.addModule("zvrl_execution", .{
        .root_source_file = b.path("src/zvrl/execution/mod.zig"),
        .target = target,
        .optimize = optimize,
    });

    const persistence_mod = b.addModule("zvrl_persistence", .{
        .root_source_file = b.path("src/zvrl/persistence/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zvrl_core", .module = core_mod },
        },
    });

    const app_mod = b.addModule("zvrl_app", .{
        .root_source_file = b.path("src/zvrl/app.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zvrl_core", .module = core_mod },
            .{ .name = "zvrl_command", .module = command_mod },
            .{ .name = "zvrl_execution", .module = execution_mod },
            .{ .name = "zvrl_persistence", .module = persistence_mod },
            .{ .name = "vaxis", .module = vaxis_mod },
        },
    });

    const ui_mod = b.addModule("zvrl_ui", .{
        .root_source_file = b.path("src/zvrl/ui/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zvrl_app", .module = app_mod },
            .{ .name = "vaxis", .module = vaxis_mod },
        },
    });

    _ = b.addModule("zvrl", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zvrl_core", .module = core_mod },
        },
    });

    const exe = b.addExecutable(.{
        .name = "zvrl",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zvrl_app", .module = app_mod },
                .{ .name = "zvrl_ui", .module = ui_mod },
                .{ .name = "vaxis", .module = vaxis_mod },
            },
        }),
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the zvrl application");
    run_step.dependOn(&run_cmd.step);

    const core_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/zvrl/core/mod.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const root_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zvrl_core", .module = core_mod },
            },
        }),
    });

    const app_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/zvrl/app.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zvrl_core", .module = core_mod },
                .{ .name = "zvrl_command", .module = command_mod },
                .{ .name = "zvrl_execution", .module = execution_mod },
                .{ .name = "zvrl_persistence", .module = persistence_mod },
                .{ .name = "vaxis", .module = vaxis_mod },
            },
        }),
    });

    const command_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/zvrl/command/builder.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zvrl_core", .module = core_mod },
            },
        }),
    });

    const persistence_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/zvrl/persistence/mod.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zvrl_core", .module = core_mod },
            },
        }),
    });

    const execution_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/zvrl/execution/executor.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const test_step = b.step("test", "Run all unit tests");
    test_step.dependOn(&b.addRunArtifact(core_tests).step);
    test_step.dependOn(&b.addRunArtifact(root_tests).step);
    test_step.dependOn(&b.addRunArtifact(app_tests).step);
    test_step.dependOn(&b.addRunArtifact(command_tests).step);
    test_step.dependOn(&b.addRunArtifact(persistence_tests).step);
    test_step.dependOn(&b.addRunArtifact(execution_tests).step);

    const fmt_step = b.step("fmt", "Format Zig sources");
    const fmt_cmd = b.addSystemCommand(&.{ "zig", "fmt", "src" });
    fmt_step.dependOn(&fmt_cmd.step);
}
