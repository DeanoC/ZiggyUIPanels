const zui = @import("ziggy-ui");

const widgets = zui.widgets;
const Rect = zui.core.Rect;
const form_layout = zui.ui.layout.form_layout;
const interfaces = zui.ui.panel_interfaces;

// Reusable debug panel shell. The host provides the event viewport and chart
// renderers while this module owns layout and typed action emission.
pub const FocusField = enum {
    none,
    perf_benchmark_label,
    node_watch_filter,
    node_watch_replay_limit,
    debug_search_filter,
};

pub const State = struct {
    focused_field: FocusField = .none,
};

pub const PointerState = struct {
    mouse_x: f32,
    mouse_y: f32,
    mouse_released: bool,
};

pub const ThemeColors = struct {
    text_primary: [4]f32,
    text_secondary: [4]f32,
};

pub const Host = struct {
    ctx: *anyopaque,
    draw_label: *const fn (ctx: *anyopaque, x: f32, y: f32, text: []const u8, color: [4]f32) void,
    draw_text_trimmed: *const fn (ctx: *anyopaque, x: f32, y: f32, max_w: f32, text: []const u8, color: [4]f32) void,
    draw_text_input: *const fn (ctx: *anyopaque, rect: Rect, text: []const u8, focused: bool, opts: widgets.text_input.Options) bool,
    draw_button: *const fn (ctx: *anyopaque, rect: Rect, label: []const u8, opts: widgets.button.Options) bool,
    draw_text_wrapped: *const fn (ctx: *anyopaque, x: f32, y: f32, max_w: f32, text: []const u8, color: [4]f32) f32,
    draw_perf_charts: *const fn (ctx: *anyopaque, rect: Rect, layout: form_layout.Metrics, y: f32, perf_charts: []const interfaces.DebugSparklineSeriesView) f32,
    draw_event_stream: *const fn (ctx: *anyopaque, output_rect: Rect, view: interfaces.DebugEventStreamView) void,
};

pub fn draw(
    host: Host,
    rect: Rect,
    layout: form_layout.Metrics,
    colors: ThemeColors,
    model: interfaces.DebugPanelModel,
    view: interfaces.DebugPanelView,
    event_stream: interfaces.DebugEventStreamView,
    pointer: PointerState,
    state: *State,
) ?interfaces.DebugPanelAction {
    const pad = layout.inset;
    const row_height = layout.button_height;
    const line_height = layout.line_height;
    const width = rect.max[0] - rect.min[0];
    const content_width = @max(240.0, width - pad * 2.0);
    var y = rect.min[1] + pad;
    var action: ?interfaces.DebugPanelAction = null;

    host.draw_label(host.ctx, rect.min[0] + pad, y, view.title, colors.text_primary);
    y += layout.title_gap;

    host.draw_label(host.ctx, rect.min[0] + pad, y, view.stream_status, colors.text_secondary);
    y += line_height;

    host.draw_label(host.ctx, rect.min[0] + pad, y, view.snapshot_status, colors.text_secondary);
    y += line_height;

    host.draw_text_trimmed(host.ctx, rect.min[0] + pad, y, content_width, view.perf_summary, colors.text_secondary);
    y += line_height;
    host.draw_text_trimmed(host.ctx, rect.min[0] + pad, y, content_width, view.perf_history, colors.text_secondary);
    y += line_height;
    host.draw_text_trimmed(host.ctx, rect.min[0] + pad, y, content_width, view.perf_command_stats, colors.text_secondary);
    y += line_height;
    host.draw_text_trimmed(host.ctx, rect.min[0] + pad, y, content_width, view.perf_panel_stats, colors.text_secondary);
    y += line_height;

    const perf_copy_rect = Rect.fromXYWH(rect.min[0] + pad, y, @max(104.0, width * 0.14), row_height);
    if (host.draw_button(
        host.ctx,
        perf_copy_rect,
        "Copy Perf",
        .{ .variant = .secondary, .disabled = !model.has_perf_history },
    )) {
        emitAction(&action, .copy_perf);
    }

    const perf_export_rect = Rect.fromXYWH(
        perf_copy_rect.max[0] + layout.inner_inset,
        y,
        @max(112.0, width * 0.16),
        row_height,
    );
    if (host.draw_button(
        host.ctx,
        perf_export_rect,
        "Export Perf",
        .{ .variant = .secondary, .disabled = !model.has_perf_history },
    )) {
        emitAction(&action, .export_perf);
    }

    const perf_clear_rect = Rect.fromXYWH(
        perf_export_rect.max[0] + layout.inner_inset,
        y,
        @max(98.0, width * 0.13),
        row_height,
    );
    if (host.draw_button(
        host.ctx,
        perf_clear_rect,
        "Clear Perf",
        .{ .variant = .secondary, .disabled = !model.has_perf_history },
    )) {
        emitAction(&action, .clear_perf);
    }
    y += row_height + layout.row_gap * 0.35;

    host.draw_text_trimmed(host.ctx, rect.min[0] + pad, y, content_width, view.benchmark_status, colors.text_secondary);
    y += line_height;

    const benchmark_label_rect = Rect.fromXYWH(rect.min[0] + pad, y, @max(180.0, width * 0.24), row_height);
    const benchmark_label_focused = host.draw_text_input(
        host.ctx,
        benchmark_label_rect,
        view.perf_benchmark_label,
        state.focused_field == .perf_benchmark_label,
        .{ .placeholder = "benchmark label" },
    );
    if (benchmark_label_focused) state.focused_field = .perf_benchmark_label;

    const benchmark_toggle_rect = Rect.fromXYWH(
        benchmark_label_rect.max[0] + layout.inner_inset,
        y,
        @max(126.0, width * 0.16),
        row_height,
    );
    const benchmark_toggle_label = if (model.perf_benchmark_active) "Stop Bench" else "Start Bench";
    if (host.draw_button(
        host.ctx,
        benchmark_toggle_rect,
        benchmark_toggle_label,
        .{ .variant = if (model.perf_benchmark_active) .primary else .secondary },
    )) {
        emitAction(&action, .toggle_benchmark);
    }

    const benchmark_copy_rect = Rect.fromXYWH(
        benchmark_toggle_rect.max[0] + layout.inner_inset,
        y,
        @max(120.0, width * 0.14),
        row_height,
    );
    if (host.draw_button(
        host.ctx,
        benchmark_copy_rect,
        "Copy Bench",
        .{ .variant = .secondary, .disabled = !model.has_perf_benchmark_capture },
    )) {
        emitAction(&action, .copy_benchmark);
    }

    const benchmark_export_rect = Rect.fromXYWH(
        benchmark_copy_rect.max[0] + layout.inner_inset,
        y,
        @max(126.0, width * 0.15),
        row_height,
    );
    if (host.draw_button(
        host.ctx,
        benchmark_export_rect,
        "Export Bench",
        .{ .variant = .secondary, .disabled = !model.has_perf_benchmark_capture },
    )) {
        emitAction(&action, .export_benchmark);
    }

    const benchmark_clear_rect = Rect.fromXYWH(
        benchmark_export_rect.max[0] + layout.inner_inset,
        y,
        @max(112.0, width * 0.14),
        row_height,
    );
    if (host.draw_button(
        host.ctx,
        benchmark_clear_rect,
        "Clear Bench",
        .{ .variant = .secondary, .disabled = !model.has_perf_benchmark_capture and !model.perf_benchmark_active },
    )) {
        emitAction(&action, .clear_benchmark);
    }

    if (pointer.mouse_released and
        state.focused_field == .perf_benchmark_label and
        !benchmark_label_rect.contains(.{ pointer.mouse_x, pointer.mouse_y }))
    {
        state.focused_field = .none;
    }

    y += row_height + layout.row_gap * 0.45;
    y = host.draw_perf_charts(host.ctx, rect, layout, y, view.perf_charts);

    host.draw_label(host.ctx, rect.min[0] + pad, y, view.node_watch_status, colors.text_secondary);
    y += line_height;
    host.draw_text_trimmed(host.ctx, rect.min[0] + pad, y, content_width, view.scope_preview, colors.text_secondary);
    y += line_height;
    if (view.show_user_scope_notice) {
        host.draw_text_trimmed(
            host.ctx,
            rect.min[0] + pad,
            y,
            content_width,
            "User node service history is filtered to mounted nodes allowed by project observe policy.",
            colors.text_secondary,
        );
        y += line_height;
    }

    const toggle_rect = Rect.fromXYWH(rect.min[0] + pad, y, @max(220.0, width * 0.34), row_height);
    const toggle_label = if (model.stream_enabled) "Pause Debug Stream" else "Resume Debug Stream";
    if (host.draw_button(host.ctx, toggle_rect, toggle_label, .{ .variant = .primary })) {
        emitAction(&action, .toggle_stream);
    }

    const refresh_rect = Rect.fromXYWH(
        toggle_rect.max[0] + layout.inner_inset,
        y,
        @max(160.0, width * 0.24),
        row_height,
    );
    if (host.draw_button(
        host.ctx,
        refresh_rect,
        "Refresh Snapshot",
        .{ .variant = .secondary, .disabled = !model.canRefreshSnapshot() },
    )) {
        emitAction(&action, .refresh_snapshot);
    }

    y += row_height + layout.row_gap * 0.65;
    host.draw_label(host.ctx, rect.min[0] + pad, y, "Node Watch Filter (optional node_id)", colors.text_primary);
    y += line_height;

    const node_watch_filter_rect = Rect.fromXYWH(rect.min[0] + pad, y, @max(220.0, width * 0.44), row_height);
    const node_watch_filter_focused = host.draw_text_input(
        host.ctx,
        node_watch_filter_rect,
        view.node_watch_filter,
        state.focused_field == .node_watch_filter,
        .{ .placeholder = "node-2" },
    );
    if (node_watch_filter_focused) state.focused_field = .node_watch_filter;

    const node_watch_replay_rect = Rect.fromXYWH(
        node_watch_filter_rect.max[0] + layout.inner_inset,
        y,
        @max(88.0, width * 0.12),
        row_height,
    );
    const replay_focused = host.draw_text_input(
        host.ctx,
        node_watch_replay_rect,
        view.node_watch_replay_limit,
        state.focused_field == .node_watch_replay_limit,
        .{ .placeholder = "25" },
    );
    if (replay_focused) state.focused_field = .node_watch_replay_limit;

    const apply_watch_rect = Rect.fromXYWH(
        node_watch_replay_rect.max[0] + layout.inner_inset,
        y,
        @max(136.0, width * 0.20),
        row_height,
    );
    if (host.draw_button(
        host.ctx,
        apply_watch_rect,
        "Refresh Node Feed",
        .{ .variant = .secondary, .disabled = !model.canRefreshNodeFeed() },
    )) {
        emitAction(&action, .refresh_node_feed);
    }

    const stop_watch_rect = Rect.fromXYWH(
        apply_watch_rect.max[0] + layout.inner_inset,
        y,
        @max(126.0, width * 0.17),
        row_height,
    );
    if (host.draw_button(
        host.ctx,
        stop_watch_rect,
        "Pause Node Feed",
        .{ .variant = .secondary, .disabled = !model.canPauseNodeFeed() },
    )) {
        emitAction(&action, .pause_node_feed);
    }

    if (pointer.mouse_released and
        (state.focused_field == .node_watch_filter or state.focused_field == .node_watch_replay_limit) and
        !node_watch_filter_rect.contains(.{ pointer.mouse_x, pointer.mouse_y }) and
        !node_watch_replay_rect.contains(.{ pointer.mouse_x, pointer.mouse_y }))
    {
        state.focused_field = .none;
    }

    y += row_height + layout.row_gap * 0.65;
    host.draw_label(host.ctx, rect.min[0] + pad, y, "Search Debug Events", colors.text_primary);
    y += line_height;

    const debug_search_rect = Rect.fromXYWH(rect.min[0] + pad, y, @max(260.0, width * 0.46), row_height);
    const debug_search_focused = host.draw_text_input(
        host.ctx,
        debug_search_rect,
        view.debug_search_filter,
        state.focused_field == .debug_search_filter,
        .{ .placeholder = "tool_result, timeout, node_service_upsert..." },
    );
    if (debug_search_focused) state.focused_field = .debug_search_filter;

    const clear_search_rect = Rect.fromXYWH(
        debug_search_rect.max[0] + layout.inner_inset,
        y,
        @max(88.0, width * 0.12),
        row_height,
    );
    if (host.draw_button(
        host.ctx,
        clear_search_rect,
        "Clear",
        .{ .variant = .secondary, .disabled = !model.has_search_filter },
    )) {
        emitAction(&action, .clear_search);
    }
    if (pointer.mouse_released and
        state.focused_field == .debug_search_filter and
        !debug_search_rect.contains(.{ pointer.mouse_x, pointer.mouse_y }) and
        !clear_search_rect.contains(.{ pointer.mouse_x, pointer.mouse_y }))
    {
        state.focused_field = .none;
    }

    y += row_height + layout.row_gap * 0.45;
    host.draw_text_trimmed(host.ctx, rect.min[0] + pad, y, content_width, view.filter_status, colors.text_secondary);
    y += line_height;
    y += layout.row_gap * 0.25;

    if (view.jump_to_node_label) |jump_to_node_label| {
        const jump_rect = Rect.fromXYWH(rect.min[0] + pad, y, @max(220.0, width * 0.45), row_height);
        if (host.draw_button(
            host.ctx,
            jump_rect,
            jump_to_node_label,
            .{ .variant = .secondary, .disabled = !model.has_selected_node_event },
        )) {
            emitAction(&action, .jump_to_selected_node_fs);
        }
        y += row_height + layout.row_gap * 0.45;
    }

    if (model.has_selected_node_event) {
        const set_base_rect = Rect.fromXYWH(rect.min[0] + pad, y, @max(140.0, width * 0.2), row_height);
        const clear_base_rect = Rect.fromXYWH(set_base_rect.max[0] + layout.inner_inset, y, @max(126.0, width * 0.18), row_height);
        const generate_diff_rect = Rect.fromXYWH(clear_base_rect.max[0] + layout.inner_inset, y, @max(134.0, width * 0.2), row_height);
        const copy_diff_rect = Rect.fromXYWH(generate_diff_rect.max[0] + layout.inner_inset, y, @max(98.0, width * 0.14), row_height);
        const export_diff_rect = Rect.fromXYWH(copy_diff_rect.max[0] + layout.inner_inset, y, @max(102.0, width * 0.14), row_height);

        if (host.draw_button(host.ctx, set_base_rect, "Set Diff Base", .{ .variant = .secondary, .disabled = !model.has_selected_node_event })) emitAction(&action, .set_diff_base);
        if (host.draw_button(host.ctx, clear_base_rect, "Clear Base", .{ .variant = .secondary, .disabled = !model.has_diff_base_or_preview })) emitAction(&action, .clear_diff_base);
        if (host.draw_button(host.ctx, generate_diff_rect, "Generate Diff", .{ .variant = .secondary, .disabled = !model.can_generate_diff })) emitAction(&action, .generate_diff);
        if (host.draw_button(host.ctx, copy_diff_rect, "Copy Diff", .{ .variant = .secondary, .disabled = !model.can_generate_diff })) emitAction(&action, .copy_diff);
        if (host.draw_button(host.ctx, export_diff_rect, "Export Diff", .{ .variant = .primary, .disabled = !model.can_generate_diff })) emitAction(&action, .export_diff);
        y += row_height + layout.row_gap * 0.45;

        if (view.diff_base_label) |diff_base_label| {
            host.draw_text_trimmed(host.ctx, rect.min[0] + pad, y, content_width, diff_base_label, colors.text_secondary);
            y += line_height;
        }
    }

    if (view.latest_reload_diag != null or view.selected_diag != null or view.diff_preview != null) {
        host.draw_label(host.ctx, rect.min[0] + pad, y, "Manifest/Service Diff Diagnostics", colors.text_primary);
        y += line_height;

        if (view.latest_reload_diag) |diag| {
            host.draw_text_trimmed(host.ctx, rect.min[0] + pad, y, content_width, "Latest node_service_upsert delta", colors.text_secondary);
            y += line_height;
            y += host.draw_text_wrapped(host.ctx, rect.min[0] + pad, y, content_width, diag, colors.text_primary);
            y += layout.row_gap * 0.4;
        }
        if (view.selected_diag) |diag| {
            host.draw_text_trimmed(host.ctx, rect.min[0] + pad, y, content_width, "Selected event delta", colors.text_secondary);
            y += line_height;
            y += host.draw_text_wrapped(host.ctx, rect.min[0] + pad, y, content_width, diag, colors.text_primary);
            y += layout.row_gap * 0.4;
        }
        if (view.diff_preview) |diff_preview| {
            host.draw_text_trimmed(host.ctx, rect.min[0] + pad, y, content_width, "Historical event diff snapshot", colors.text_secondary);
            y += line_height;
            y += host.draw_text_wrapped(host.ctx, rect.min[0] + pad, y, content_width, diff_preview, colors.text_primary);
            y += layout.row_gap * 0.4;
        }
    }

    if (view.show_large_payload_notice) {
        host.draw_text_trimmed(
            host.ctx,
            rect.min[0] + pad,
            y,
            content_width,
            "Large payload mode: syntax coloring disabled for this event to keep UI responsive.",
            colors.text_secondary,
        );
        y += line_height;
    }

    host.draw_label(host.ctx, rect.min[0] + pad, y, "Fold nested JSON with [+]/[-].", colors.text_secondary);
    y += line_height + layout.row_gap * 0.45;

    y += row_height + layout.row_gap;
    const output_rect = Rect.fromXYWH(
        rect.min[0] + pad,
        y,
        content_width,
        @max(120.0, rect.max[1] - y - pad),
    );
    host.draw_event_stream(host.ctx, output_rect, event_stream);
    return action;
}

fn emitAction(slot: *?interfaces.DebugPanelAction, next: interfaces.DebugPanelAction) void {
    if (slot.* == null) slot.* = next;
}
