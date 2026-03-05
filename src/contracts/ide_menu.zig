const std = @import("std");

pub const IdeMenuDomain = enum {
    file,
    edit,
    view,
    project,
    tools,
    window,
    help,
};

pub const IdeMenuAction = enum {
    file_new_project,
    file_open_project,
    file_switch_project,
    file_disconnect,
    file_exit,

    edit_undo,
    edit_redo,

    view_toggle_chat,
    view_toggle_explorer,
    view_toggle_terminal,

    project_refresh,
    project_create,

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
        .action = .file_switch_project,
        .label = "Switch Project",
        .enabled = true,
    };

    try std.testing.expectEqual(IdeMenuDomain.file, item.domain);
    try std.testing.expectEqual(IdeMenuAction.file_switch_project, item.action);
}
