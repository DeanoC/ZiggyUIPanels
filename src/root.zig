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

// Host-parameterized panel implementations.
pub const showcase_panel = @import("panels/showcase_panel.zig");

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
