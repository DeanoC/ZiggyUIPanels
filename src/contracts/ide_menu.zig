const std = @import("std");

pub const IdeMenuDomain = enum {
    file,
    edit,
    view,
    workspace,
    tools,
    window,
    help,
};

pub const IdeMenuAction = enum {
    file_new_workspace,
    file_open_workspace,
    file_switch_workspace,
    file_disconnect,
    file_exit,

    edit_undo,
    edit_redo,

    view_toggle_chat,
    view_toggle_explorer,
    view_toggle_terminal,

    workspace_refresh,
    workspace_create,

    tools_open_settings,

    window_new_window,

    help_docs,
    help_about,
};

pub const IdeMenuItem = struct {
    domain: IdeMenuDomain,
    action: IdeMenuAction,
    label: []const u8,
    enabled: bool = true,
};

pub const IdeMenuModel = struct {
    items: []const IdeMenuItem = &.{},
};

test "menu item metadata" {
    const item = IdeMenuItem{
        .domain = .file,
        .action = .file_switch_workspace,
        .label = "Switch Workspace",
        .enabled = true,
    };

    try std.testing.expectEqual(IdeMenuDomain.file, item.domain);
    try std.testing.expectEqual(IdeMenuAction.file_switch_workspace, item.action);
}
