const std = @import("std");
const zui = @import("ziggy-ui");

const draw_context = zui.ui.draw_context;
const ui_command_inbox = zui.ui.ui_command_inbox;
const interfaces = zui.ui.panel_interfaces;
const workspace = zui.ui.workspace;

// Thin wrapper that keeps SpiderApp on the ZiggyUIPanels boundary while
// reusing the generic chat implementation from ziggy-ui.
pub fn draw(
    comptime Message: type,
    comptime Session: type,
    allocator: std.mem.Allocator,
    panel_state: *workspace.ChatPanel,
    agent_id: []const u8,
    session_key: ?[]const u8,
    messages: []const Message,
    stream_text: ?[]const u8,
    inbox: ?*const ui_command_inbox.UiCommandInbox,
    agent_icon: []const u8,
    agent_name: []const u8,
    sessions: []const Session,
    pending_approvals_count: usize,
    rect_override: ?draw_context.Rect,
) interfaces.ChatPanelAction {
    const Panel = zui.ChatPanel(Message, Session);
    const action = Panel.draw(
        allocator,
        panel_state,
        agent_id,
        session_key,
        messages,
        stream_text,
        inbox,
        agent_icon,
        agent_name,
        sessions,
        pending_approvals_count,
        rect_override,
        null,
    );
    return toPanelAction(action);
}

fn toPanelAction(action: zui.ChatPanelAction) interfaces.ChatPanelAction {
    return .{
        .send_message = action.send_message,
        .select_session = action.select_session,
        .select_session_id = action.select_session_id,
        .new_chat_session_key = action.new_chat_session_key,
        .open_activity_panel = action.open_activity_panel,
        .open_approvals_panel = action.open_approvals_panel,
    };
}
