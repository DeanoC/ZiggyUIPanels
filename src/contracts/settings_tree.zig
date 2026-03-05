const std = @import("std");

pub const SettingsTreeNode = struct {
    id: []const u8,
    label: []const u8,
    expanded: bool = true,
    children: []const SettingsTreeNode = &.{},
};

pub const SettingsTreeModel = struct {
    root_nodes: []const SettingsTreeNode = &.{},
    selected_id: ?[]const u8 = null,
    filter: ?[]const u8 = null,
};

pub const SettingsTreeAction = union(enum) {
    none,
    select: []const u8,
    toggle_expanded: []const u8,
    set_filter: []const u8,
    clear_filter,
};

pub fn hasNode(model: SettingsTreeModel, node_id: []const u8) bool {
    for (model.root_nodes) |node| {
        if (nodeMatches(node, node_id)) return true;
    }
    return false;
}

fn nodeMatches(node: SettingsTreeNode, node_id: []const u8) bool {
    if (std.mem.eql(u8, node.id, node_id)) return true;
    for (node.children) |child| {
        if (nodeMatches(child, node_id)) return true;
    }
    return false;
}

test "settings tree lookup supports nested nodes" {
    const nested = [_]SettingsTreeNode{.{ .id = "tokens", .label = "Tokens" }};
    const roots = [_]SettingsTreeNode{.{
        .id = "connection",
        .label = "Connection",
        .children = nested[0..],
    }};

    const model = SettingsTreeModel{
        .root_nodes = roots[0..],
    };

    try std.testing.expect(hasNode(model, "tokens"));
    try std.testing.expect(!hasNode(model, "missing"));
}
