const std = @import("std");

/// Contract type for opening an attachment in panel-driven UIs.
pub const AttachmentOpen = struct {
    name: []u8,
    kind: []u8,
    url: []u8,
    body: ?[]u8 = null,
    status: ?[]u8 = null,
    truncated: bool = false,

    pub fn deinit(self: *AttachmentOpen, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.kind);
        allocator.free(self.url);
        if (self.body) |body| allocator.free(body);
        if (self.status) |status| allocator.free(status);
        self.* = undefined;
    }
};

/// Contract result for a single panel render dispatch pass.
pub const DrawResult = struct {
    session_key: ?[]const u8 = null,
    agent_id: ?[]const u8 = null,
};

pub const launcher = @import("contracts/launcher.zig");
pub const ide_menu = @import("contracts/ide_menu.zig");
pub const settings_tree = @import("contracts/settings_tree.zig");

// Host-parameterized reusable panel implementations.
pub const showcase_panel = @import("panels/showcase_panel.zig");
pub const launcher_settings_panel = @import("panels/launcher_settings_panel.zig");
pub const chat_workspace_panel = @import("panels/chat_workspace_panel.zig");
pub const filesystem_panel = @import("panels/filesystem_panel.zig");
pub const filesystem_tools_panel = @import("panels/filesystem_tools_panel.zig");
pub const project_panel = @import("panels/project_panel.zig");
pub const debug_panel = @import("panels/debug_panel.zig");
pub const debug_event_stream = @import("panels/debug_event_stream.zig");
pub const terminal_panel = @import("panels/terminal_panel.zig");
pub const terminal_output_panel = @import("panels/terminal_output_panel.zig");

pub const version = "0.1.0";

test "attachment deinit frees optional buffers" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var value = AttachmentOpen{
        .name = try allocator.dupe(u8, "example.txt"),
        .kind = try allocator.dupe(u8, "text"),
        .url = try allocator.dupe(u8, "file:///tmp/example.txt"),
        .body = try allocator.dupe(u8, "hello"),
        .status = try allocator.dupe(u8, "ready"),
        .truncated = false,
    };

    value.deinit(allocator);
}
