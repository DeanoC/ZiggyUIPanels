const std = @import("std");

pub const ConnectionRole = enum {
    admin,
    user,
};

pub const ConnectionStatus = enum {
    disconnected,
    connecting,
    connected,
    error_state,
};

pub const ConnectionProfileModel = struct {
    id: []const u8,
    name: []const u8,
    server_url: []const u8,
    role: ConnectionRole = .admin,
    status: ConnectionStatus = .disconnected,
    metadata: ?[]const u8 = null,
};

pub const WorkspaceCardModel = struct {
    id: []const u8,
    name: []const u8,
    status: []const u8,
    vision: ?[]const u8 = null,
    token_locked: bool = false,
};

pub const LauncherViewModel = struct {
    app_title: []const u8 = "Ziggy Star Spider",
    connected: bool = false,
    connecting: bool = false,
    selected_profile_id: ?[]const u8 = null,
    selected_workspace_id: ?[]const u8 = null,
    profiles: []const ConnectionProfileModel = &.{},
    workspaces: []const WorkspaceCardModel = &.{},
    status_message: ?[]const u8 = null,
};

pub const LauncherAction = union(enum) {
    none,
    select_profile: []const u8,
    create_profile,
    connect_selected,
    disconnect_selected,
    refresh_workspaces,
    create_workspace,
    select_workspace: []const u8,
    open_workspace: OpenWorkspace,

    pub const OpenWorkspace = struct {
        profile_id: []const u8,
        workspace_id: []const u8,
    };
};

test "launcher view model default state" {
    const view = LauncherViewModel{};
    try std.testing.expectEqualStrings("Ziggy Star Spider", view.app_title);
    try std.testing.expect(view.profiles.len == 0);
    try std.testing.expect(view.workspaces.len == 0);
}
