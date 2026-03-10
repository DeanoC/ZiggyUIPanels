const std = @import("std");
const zui = @import("ziggy-ui");

const widgets = zui.widgets;
const Rect = zui.core.Rect;
const form_layout = zui.ui.layout.form_layout;
const interfaces = zui.ui.panel_interfaces;
const ui_theme_runtime = zui.ui.theme_engine.runtime;
const zcolors = zui.theme.colors;

// Reusable filesystem explorer shell. The host owns filesystem data,
// sorting/filtering policy, and side effects; this module owns layout,
// local paging/click behavior, and typed action emission.
pub const FocusField = enum {
    none,
    contract_payload,
};

pub const State = struct {
    focused_field: FocusField = .none,
    entry_page: usize = 0,
    last_clicked_entry_index: ?usize = null,
    last_click_ms: i64 = 0,
    preview_split_ratio: f32 = 0.28,
    preview_split_dragging: bool = false,
    type_column_width: f32 = 96.0,
    modified_column_width: f32 = 122.0,
    size_column_width: f32 = 72.0,
    column_resize: ColumnResizeHandle = .none,
};

pub const ColumnResizeHandle = enum {
    none,
    type,
    modified,
    size,
};

pub const PointerState = struct {
    mouse_x: f32,
    mouse_y: f32,
    mouse_down: bool,
    mouse_clicked: bool,
    mouse_released: bool,
};

pub const ThemeColors = struct {
    text_primary: [4]f32,
    text_secondary: [4]f32,
    primary: [4]f32,
    border: [4]f32,
    surface: [4]f32,
    error_text: [4]f32,
};

pub const Host = struct {
    ctx: *anyopaque,
    draw_label: *const fn (ctx: *anyopaque, x: f32, y: f32, text: []const u8, color: [4]f32) void,
    draw_text_trimmed: *const fn (ctx: *anyopaque, x: f32, y: f32, max_w: f32, text: []const u8, color: [4]f32) void,
    draw_text_input: *const fn (ctx: *anyopaque, rect: Rect, text: []const u8, focused: bool, opts: widgets.text_input.Options) bool,
    draw_button: *const fn (ctx: *anyopaque, rect: Rect, label: []const u8, opts: widgets.button.Options) bool,
    draw_surface_panel: *const fn (ctx: *anyopaque, rect: Rect) void,
    draw_text_wrapped: *const fn (ctx: *anyopaque, x: f32, y: f32, max_w: f32, text: []const u8, color: [4]f32) f32,
    draw_filled_rect: *const fn (ctx: *anyopaque, rect: Rect, color: [4]f32) void,
    draw_rect: *const fn (ctx: *anyopaque, rect: Rect, color: [4]f32) void,
};

const toolbar_gap_factor: f32 = 0.55;
const list_min_height: f32 = 220.0;
const preview_min_height: f32 = 110.0;
const preview_default_ratio: f32 = 0.28;
const preview_min_ratio: f32 = 0.18;
const preview_max_ratio: f32 = 0.62;
const splitter_hit_height: f32 = 14.0;
const column_resize_hit_width: f32 = 10.0;
const min_name_column_width: f32 = 96.0;
const min_type_column_width: f32 = 72.0;
const min_modified_column_width: f32 = 96.0;
const min_size_column_width: f32 = 56.0;
const double_click_ms: i64 = 350;

pub fn draw(
    host: Host,
    rect: Rect,
    layout: form_layout.Metrics,
    model: interfaces.FilesystemPanelModel,
    view: interfaces.FilesystemPanelView,
    colors: ThemeColors,
    pointer: PointerState,
    state: *State,
) ?interfaces.FilesystemPanelAction {
    const pad = layout.inset;
    const row_h = @max(28.0, layout.button_height * 0.72);
    const content_width = @max(260.0, rect.width() - pad * 2.0);
    var y = rect.min[1] + pad;
    var action: ?interfaces.FilesystemPanelAction = null;

    host.draw_label(host.ctx, rect.min[0] + pad, y, "Explorer", colors.text_primary);
    y += layout.title_gap;

    var path_buf: [768]u8 = undefined;
    const path_line = std.fmt.bufPrint(&path_buf, "Path: {s}", .{view.path_label}) catch view.path_label;
    host.draw_text_trimmed(host.ctx, rect.min[0] + pad, y, content_width, path_line, colors.text_secondary);
    y += layout.line_height + layout.row_gap * 0.65;

    y = drawHeaderToolbar(host, rect, y, pad, row_h, content_width, layout, model, view, colors, &action);

    if (model.busy) {
        host.draw_text_trimmed(host.ctx, rect.min[0] + pad, y, content_width, "Loading...", colors.text_secondary);
        y += layout.line_height;
    }
    if (view.error_text) |err_text| {
        host.draw_text_trimmed(host.ctx, rect.min[0] + pad, y, content_width, err_text, colors.error_text);
        y += layout.line_height;
    }

    y += layout.row_gap * 0.35;
    y = drawSortAndFilterToolbar(host, rect, y, pad, row_h, content_width, layout, model, colors, &action);

    const explorer_rect = Rect.fromXYWH(rect.min[0] + pad, y, content_width, @max(list_min_height, rect.max[1] - y - pad));
    drawExplorerBody(host, explorer_rect, layout, model, view, colors, pointer, state, &action);

    return action;
}

fn drawHeaderToolbar(
    host: Host,
    rect: Rect,
    start_y: f32,
    pad: f32,
    row_h: f32,
    content_width: f32,
    layout: form_layout.Metrics,
    model: interfaces.FilesystemPanelModel,
    view: interfaces.FilesystemPanelView,
    colors: ThemeColors,
    action: *?interfaces.FilesystemPanelAction,
) f32 {
    const button_gap = pad * toolbar_gap_factor;
    const base_w: f32 = @max(82.0, (content_width - button_gap * 4.0) / 5.0);
    var y = start_y;

    const refresh_rect = Rect.fromXYWH(rect.min[0] + pad, y, base_w, row_h);
    const up_rect = Rect.fromXYWH(refresh_rect.max[0] + button_gap, y, base_w, row_h);
    const root_rect = Rect.fromXYWH(up_rect.max[0] + button_gap, y, base_w * 1.05, row_h);
    const open_rect = Rect.fromXYWH(root_rect.max[0] + button_gap, y, base_w, row_h);
    if (host.draw_button(host.ctx, refresh_rect, "Refresh", .{ .variant = .ghost, .disabled = model.controlsDisabled() })) emitAction(action, .refresh);
    if (host.draw_button(host.ctx, up_rect, "Up", .{ .variant = .secondary, .disabled = model.controlsDisabled() })) emitAction(action, .navigate_up);
    if (host.draw_button(host.ctx, root_rect, "Root", .{ .variant = .secondary, .disabled = model.controlsDisabled() })) emitAction(action, .use_workspace_root);
    if (host.draw_button(host.ctx, open_rect, "Open", .{ .variant = .primary, .disabled = !model.canOpenSelectedEntry() })) emitAction(action, .open_selected_entry);

    y += row_h + layout.row_gap * 0.55;

    var counts_buf: [96]u8 = undefined;
    const counts_text = std.fmt.bufPrint(&counts_buf, "Showing {d} of {d} entries", .{ view.visible_entry_count, view.total_entry_count }) catch "Entries";
    host.draw_text_trimmed(host.ctx, rect.min[0] + pad, y, content_width * 0.58, counts_text, colors.text_secondary);

    const preview_button_w: f32 = @max(96.0, base_w * 0.95);
    const preview_rect = Rect.fromXYWH(rect.max[0] - pad - preview_button_w, y - layout.row_gap * 0.15, preview_button_w, row_h);
    if (host.draw_button(host.ctx, preview_rect, "Preview", .{ .variant = .ghost, .disabled = !model.canOpenSelectedEntry() })) {
        emitAction(action, .refresh_preview);
    }

    return y + layout.line_height + layout.row_gap * 0.65;
}

fn drawSortAndFilterToolbar(
    host: Host,
    rect: Rect,
    start_y: f32,
    pad: f32,
    row_h: f32,
    content_width: f32,
    layout: form_layout.Metrics,
    model: interfaces.FilesystemPanelModel,
    colors: ThemeColors,
    action: *?interfaces.FilesystemPanelAction,
) f32 {
    const gap = pad * 0.55;
    var y = start_y;

    host.draw_text_trimmed(host.ctx, rect.min[0] + pad, y, content_width, "Filters", colors.text_secondary);
    y += layout.line_height + layout.row_gap * 0.28;

    const chip_w: f32 = @max(64.0, (content_width - gap * 4.0) / 5.0);
    var x = rect.min[0] + pad;
    inline for ([_]struct {
        label: []const u8,
        active: bool,
        action_tag: enum { hidden, directories, files, noise },
    }{
        .{ .label = "Hidden", .active = model.hide_hidden, .action_tag = .hidden },
        .{ .label = "Dirs", .active = model.hide_directories, .action_tag = .directories },
        .{ .label = "Files", .active = model.hide_files, .action_tag = .files },
        .{ .label = "Noise", .active = model.hide_runtime_noise, .action_tag = .noise },
    }) |spec| {
        const chip_rect = Rect.fromXYWH(x, y, chip_w, row_h);
        if (host.draw_button(host.ctx, chip_rect, spec.label, .{ .variant = if (spec.active) .primary else .ghost, .disabled = model.controlsDisabled() })) {
            switch (spec.action_tag) {
                .hidden => emitAction(action, .toggle_hide_hidden),
                .directories => emitAction(action, .toggle_hide_directories),
                .files => emitAction(action, .toggle_hide_files),
                .noise => emitAction(action, .toggle_hide_runtime_noise),
            }
        }
        x = chip_rect.max[0] + gap;
    }

    const reset_rect = Rect.fromXYWH(x, y, chip_w, row_h);
    if (host.draw_button(host.ctx, reset_rect, "Reset", .{ .variant = .ghost, .disabled = model.controlsDisabled() or !model.hasActiveFilters() })) {
        emitAction(action, .reset_explorer_view);
    }

    return y + row_h + layout.row_gap;
}

fn drawExplorerBody(
    host: Host,
    rect: Rect,
    layout: form_layout.Metrics,
    model: interfaces.FilesystemPanelModel,
    view: interfaces.FilesystemPanelView,
    colors: ThemeColors,
    pointer: PointerState,
    state: *State,
    action: *?interfaces.FilesystemPanelAction,
) void {
    const split_gap = layout.inset * 0.6;
    if (!pointer.mouse_down) state.preview_split_dragging = false;

    const usable_h = @max(list_min_height + preview_min_height + split_gap, rect.height());
    const min_preview_h = @max(preview_min_height, usable_h * preview_min_ratio);
    const max_preview_h = @max(min_preview_h, usable_h * preview_max_ratio);
    var preview_h = std.math.clamp(usable_h * clampPreviewRatio(state.preview_split_ratio), min_preview_h, max_preview_h);
    var list_h = @max(list_min_height, usable_h - preview_h - split_gap);
    preview_h = @max(min_preview_h, usable_h - list_h - split_gap);

    const splitter_y = rect.min[1] + list_h;
    const splitter_rect = Rect.fromXYWH(rect.min[0], splitter_y - splitter_hit_height * 0.5, rect.width(), splitter_hit_height);
    if (pointer.mouse_clicked and splitter_rect.contains(.{ pointer.mouse_x, pointer.mouse_y })) {
        state.preview_split_dragging = true;
    }
    if (state.preview_split_dragging and pointer.mouse_down) {
        const raw_preview_h = rect.max[1] - pointer.mouse_y;
        preview_h = std.math.clamp(raw_preview_h, min_preview_h, max_preview_h);
        list_h = @max(list_min_height, usable_h - preview_h - split_gap);
        preview_h = @max(min_preview_h, usable_h - list_h - split_gap);
        state.preview_split_ratio = preview_h / usable_h;
    } else {
        state.preview_split_ratio = preview_h / usable_h;
    }

    const list_rect = Rect.fromXYWH(rect.min[0], rect.min[1], rect.width(), list_h);
    const preview_rect = Rect.fromXYWH(rect.min[0], list_rect.max[1] + split_gap, rect.width(), usable_h - list_h - split_gap);

    drawEntryList(host, list_rect, layout, model, view, colors, pointer, state, action);
    drawPreviewSplitter(host, Rect.fromXYWH(rect.min[0], list_rect.max[1], rect.width(), split_gap), colors, splitter_rect.contains(.{ pointer.mouse_x, pointer.mouse_y }) or state.preview_split_dragging);
    drawPreviewPane(host, preview_rect, layout, view, colors);
}

fn drawEntryList(
    host: Host,
    rect: Rect,
    layout: form_layout.Metrics,
    model: interfaces.FilesystemPanelModel,
    view: interfaces.FilesystemPanelView,
    colors: ThemeColors,
    pointer: PointerState,
    state: *State,
    action: *?interfaces.FilesystemPanelAction,
) void {
    const inner = @max(8.0, layout.inner_inset * 0.8);
    const row_gap = @max(2.0, layout.row_gap * 0.28);
    const pager_h = @max(24.0, layout.button_height * 0.68);
    const pager_gap = layout.row_gap * 0.4;
    const list_header_h = layout.line_height + inner * 0.7;
    const row_h = @max(layout.line_height + inner * 1.2, 30.0);

    host.draw_surface_panel(host.ctx, rect);
    host.draw_text_trimmed(host.ctx, rect.min[0] + inner, rect.min[1] + inner * 0.7, rect.width() - inner * 2.0, "Files", colors.text_primary);

    var subtitle_buf: [96]u8 = undefined;
    const subtitle = if (view.total_entry_count == 0)
        "Empty directory"
    else if (view.visible_entry_count == view.total_entry_count)
        std.fmt.bufPrint(&subtitle_buf, "{d} visible entries", .{view.visible_entry_count}) catch "Entries"
    else
        std.fmt.bufPrint(&subtitle_buf, "{d} visible / {d} total", .{ view.visible_entry_count, view.total_entry_count }) catch "Entries";
    host.draw_text_trimmed(host.ctx, rect.min[0] + inner + 58.0, rect.min[1] + inner * 0.7, rect.width() - inner * 2.0 - 58.0, subtitle, colors.text_secondary);

    const body_top = rect.min[1] + layout.line_height + inner * 1.35;
    const body_h = @max(0.0, rect.height() - (body_top - rect.min[1]) - inner);
    const rows_without_pager = @max(1, @as(usize, @intFromFloat(@floor((body_h + row_gap) / (row_h + row_gap)))));
    const needs_pager = view.entries.len > rows_without_pager;
    const rows_per_page = if (needs_pager)
        @max(1, @as(usize, @intFromFloat(@floor((@max(0.0, body_h - pager_h - pager_gap) + row_gap) / (row_h + row_gap)))))
    else
        rows_without_pager;
    const page_count = @max(1, std.math.divCeil(usize, view.entries.len, rows_per_page) catch 1);
    if (state.entry_page >= page_count) state.entry_page = page_count - 1;

    var list_y = body_top;
    if (needs_pager) {
        const button_w: f32 = @max(54.0, @min(72.0, rect.width() * 0.14));
        const prev_rect = Rect.fromXYWH(rect.min[0] + inner, list_y, button_w, pager_h);
        const next_rect = Rect.fromXYWH(rect.max[0] - inner - button_w, list_y, button_w, pager_h);
        if (host.draw_button(host.ctx, prev_rect, "Prev", .{ .variant = .ghost, .disabled = state.entry_page == 0 })) state.entry_page -= 1;
        if (host.draw_button(host.ctx, next_rect, "Next", .{ .variant = .ghost, .disabled = state.entry_page + 1 >= page_count })) state.entry_page += 1;

        var page_buf: [80]u8 = undefined;
        const start_ordinal = state.entry_page * rows_per_page + 1;
        const end_ordinal = @min(view.entries.len, (state.entry_page + 1) * rows_per_page);
        const page_text = std.fmt.bufPrint(&page_buf, "Rows {d}-{d} of {d}", .{ start_ordinal, end_ordinal, view.entries.len }) catch "Rows";
        host.draw_text_trimmed(host.ctx, prev_rect.max[0] + inner, list_y + @max(0.0, (pager_h - layout.line_height) * 0.5), @max(0.0, next_rect.min[0] - prev_rect.max[0] - inner * 2.0), page_text, colors.text_secondary);
        list_y += pager_h + pager_gap;
    }

    const column_header_rect = Rect.fromXYWH(rect.min[0] + inner, list_y, rect.width() - inner * 2.0, list_header_h);
    const was_resizing = state.column_resize != .none;
    const pointer_on_resize_handle = headerPointerOnResizeHandle(column_header_rect, inner, pointer, state);
    handleColumnResize(column_header_rect, inner, pointer, state);
    const cols = entryColumns(column_header_rect, inner, state);
    drawEntryHeaderRow(host, column_header_rect, cols, layout, model, colors, pointer, state, action, was_resizing or state.column_resize != .none or pointer_on_resize_handle);
    list_y += list_header_h + row_gap;

    if (view.entries.len == 0) {
        const empty_text = if (model.hasActiveFilters())
            "No entries match the active explorer filters"
        else
            "This directory has no visible entries yet";
        _ = host.draw_text_wrapped(host.ctx, rect.min[0] + inner, list_y + inner * 0.4, rect.width() - inner * 2.0, empty_text, colors.text_secondary);
        return;
    }

    const start_idx = @min(view.entries.len, state.entry_page * rows_per_page);
    const end_idx = @min(view.entries.len, start_idx + rows_per_page);
    var idx: usize = start_idx;
    while (idx < end_idx) : (idx += 1) {
        const entry = view.entries[idx];
        const row_rect = Rect.fromXYWH(rect.min[0] + inner, list_y, rect.width() - inner * 2.0, row_h);
        const hovered = rowRectHovered(row_rect, pointer);
        drawEntryRow(host, row_rect, cols, layout, entry, colors, hovered);
        if (pointer.mouse_released and !model.busy and row_rect.contains(.{ pointer.mouse_x, pointer.mouse_y })) {
            const now = std.time.milliTimestamp();
            if (state.last_clicked_entry_index != null and state.last_clicked_entry_index.? == entry.index and now - state.last_click_ms <= double_click_ms) {
                emitAction(action, .{ .open_entry_index = entry.index });
            } else {
                emitAction(action, .{ .select_entry_index = entry.index });
            }
            state.last_clicked_entry_index = entry.index;
            state.last_click_ms = now;
        }
        list_y += row_h + row_gap;
    }
}

fn drawEntryRow(
    host: Host,
    rect: Rect,
    cols: EntryColumns,
    layout: form_layout.Metrics,
    entry: interfaces.FilesystemEntryView,
    colors: ThemeColors,
    hovered: bool,
) void {
    const fill = listRowFill(colors, entry.selected, hovered);
    const border = listRowBorder(colors, entry.selected, hovered);

    host.draw_filled_rect(host.ctx, rect, fill);
    host.draw_rect(host.ctx, rect, border);

    const text_y = rect.min[1] + @max(0.0, (rect.height() - layout.line_height) * 0.5);
    const selected_text = listRowTextColor(colors, entry.selected);
    const name_color = if (entry.selected)
        selected_text
    else if (entry.kind == .directory)
        zcolors.blend(colors.text_primary, colors.primary, 0.18)
    else
        colors.text_primary;
    host.draw_text_trimmed(host.ctx, cols.name_x, text_y, cols.name_w, entry.name, name_color);

    const type_text = if (entry.hidden and entry.kind == .directory)
        "Folder hidden"
    else if (entry.hidden and entry.kind != .directory)
        "hidden"
    else
        entry.type_label;
    host.draw_text_trimmed(host.ctx, cols.type_x, text_y, cols.type_w, type_text, colors.text_secondary);
    if (entry.modified_label) |value| host.draw_text_trimmed(host.ctx, cols.modified_x, text_y, cols.modified_w, value, colors.text_secondary);
    if (entry.size_label) |value| host.draw_text_trimmed(host.ctx, cols.size_x, text_y, cols.size_w, value, colors.text_secondary);
}

fn listRowFill(colors: ThemeColors, selected: bool, hovered: bool) [4]f32 {
    const row = ui_theme_runtime.getStyleSheet().list_row;
    if (selected and hovered) return row.selected_hover_fill orelse row.selected_fill orelse zcolors.withAlpha(colors.primary, 0.2);
    if (selected) return row.selected_fill orelse zcolors.withAlpha(colors.primary, 0.15);
    if (hovered) return row.hover_fill orelse zcolors.withAlpha(colors.primary, 0.05);
    return zcolors.withAlpha(colors.surface, 0.0);
}

fn listRowBorder(colors: ThemeColors, selected: bool, hovered: bool) [4]f32 {
    const row = ui_theme_runtime.getStyleSheet().list_row;
    if (selected) return row.selected_border orelse zcolors.blend(colors.border, colors.primary, 0.35);
    if (hovered) return row.hover_border orelse zcolors.blend(colors.border, colors.primary, 0.14);
    return zcolors.withAlpha(colors.border, 0.55);
}

fn listRowTextColor(colors: ThemeColors, selected: bool) [4]f32 {
    if (!selected) return colors.text_primary;
    return ui_theme_runtime.getStyleSheet().list_row.selected_text orelse colors.text_primary;
}

fn drawEntryHeaderRow(
    host: Host,
    rect: Rect,
    cols: EntryColumns,
    layout: form_layout.Metrics,
    model: interfaces.FilesystemPanelModel,
    colors: ThemeColors,
    pointer: PointerState,
    state: *State,
    action: *?interfaces.FilesystemPanelAction,
    suppress_sort_click: bool,
) void {
    const text_y = rect.min[1] + @max(0.0, (rect.height() - layout.line_height) * 0.5);
    const color = zcolors.withAlpha(colors.text_secondary, 0.95);
    drawSortableHeaderCell(host, cols.name_rect, text_y, columnLabel("Name", model.sort_key == .name, model.sort_direction), color);
    drawSortableHeaderCell(host, cols.type_rect, text_y, columnLabel("Type", model.sort_key == .type, model.sort_direction), color);
    drawSortableHeaderCell(host, cols.modified_rect, text_y, columnLabel("Modified", model.sort_key == .modified, model.sort_direction), color);
    drawSortableHeaderCell(host, cols.size_rect, text_y, columnLabel("Size", model.sort_key == .size, model.sort_direction), color);

    if (pointer.mouse_released and !suppress_sort_click and state.column_resize == .none) {
        if (cols.name_rect.contains(.{ pointer.mouse_x, pointer.mouse_y })) {
            emitSortAction(action, model, .name);
        } else if (cols.type_rect.contains(.{ pointer.mouse_x, pointer.mouse_y })) {
            emitSortAction(action, model, .type);
        } else if (cols.modified_rect.contains(.{ pointer.mouse_x, pointer.mouse_y })) {
            emitSortAction(action, model, .modified);
        } else if (cols.size_rect.contains(.{ pointer.mouse_x, pointer.mouse_y })) {
            emitSortAction(action, model, .size);
        }
    }

    drawColumnHandles(host, cols, colors, pointer, state);
    host.draw_rect(host.ctx, Rect.fromXYWH(rect.min[0], rect.max[1], rect.width(), 1.0), zcolors.withAlpha(colors.border, 0.55));
}

const EntryColumns = struct {
    name_x: f32,
    name_w: f32,
    type_x: f32,
    type_w: f32,
    modified_x: f32,
    modified_w: f32,
    size_x: f32,
    size_w: f32,
    name_rect: Rect,
    type_rect: Rect,
    modified_rect: Rect,
    size_rect: Rect,
    type_handle_x: f32,
    modified_handle_x: f32,
    size_handle_x: f32,
};

fn entryColumns(rect: Rect, inner: f32, state: *const State) EntryColumns {
    const bounds = normalizedColumnWidths(rect.width(), inner, state.type_column_width, state.modified_column_width, state.size_column_width);
    const size_w = bounds.size_w;
    const modified_w = bounds.modified_w;
    const type_w = bounds.type_w;
    const name_x = rect.min[0] + inner;
    const size_x = rect.max[0] - inner - size_w;
    const modified_x = size_x - inner - modified_w;
    const type_x = modified_x - inner - type_w;
    const name_w = @max(56.0, type_x - name_x - inner);
    return .{
        .name_x = name_x,
        .name_w = name_w,
        .type_x = type_x,
        .type_w = type_w,
        .modified_x = modified_x,
        .modified_w = modified_w,
        .size_x = size_x,
        .size_w = size_w,
        .name_rect = Rect.fromXYWH(name_x, rect.min[1], name_w, rect.height()),
        .type_rect = Rect.fromXYWH(type_x, rect.min[1], type_w, rect.height()),
        .modified_rect = Rect.fromXYWH(modified_x, rect.min[1], modified_w, rect.height()),
        .size_rect = Rect.fromXYWH(size_x, rect.min[1], size_w, rect.height()),
        .type_handle_x = type_x - inner * 0.5,
        .modified_handle_x = modified_x - inner * 0.5,
        .size_handle_x = size_x - inner * 0.5,
    };
}

const NormalizedColumnWidths = struct {
    type_w: f32,
    modified_w: f32,
    size_w: f32,
};

fn normalizedColumnWidths(total_w: f32, inner: f32, type_w: f32, modified_w: f32, size_w: f32) NormalizedColumnWidths {
    const usable_w = @max(0.0, total_w - inner * 2.0);
    const max_side_total = @max(min_type_column_width + min_modified_column_width + min_size_column_width, usable_w - min_name_column_width - inner * 3.0);

    var resolved_type = @max(min_type_column_width, type_w);
    var resolved_modified = @max(min_modified_column_width, modified_w);
    var resolved_size = @max(min_size_column_width, size_w);
    const side_total = resolved_type + resolved_modified + resolved_size;
    if (side_total > max_side_total) {
        var overflow = side_total - max_side_total;

        const modified_reducible = @max(0.0, resolved_modified - min_modified_column_width);
        const reduce_modified = @min(overflow, modified_reducible);
        resolved_modified -= reduce_modified;
        overflow -= reduce_modified;

        const type_reducible = @max(0.0, resolved_type - min_type_column_width);
        const reduce_type = @min(overflow, type_reducible);
        resolved_type -= reduce_type;
        overflow -= reduce_type;

        const size_reducible = @max(0.0, resolved_size - min_size_column_width);
        const reduce_size = @min(overflow, size_reducible);
        resolved_size -= reduce_size;
    }

    return .{
        .type_w = resolved_type,
        .modified_w = resolved_modified,
        .size_w = resolved_size,
    };
}

fn handleColumnResize(rect: Rect, inner: f32, pointer: PointerState, state: *State) void {
    const cols = entryColumns(rect, inner, state);
    if (!pointer.mouse_down) state.column_resize = .none;

    if (pointer.mouse_clicked) {
        if (nearHandle(pointer.mouse_x, cols.type_handle_x) and pointer.mouse_y >= rect.min[1] and pointer.mouse_y <= rect.max[1]) {
            state.column_resize = .type;
        } else if (nearHandle(pointer.mouse_x, cols.modified_handle_x) and pointer.mouse_y >= rect.min[1] and pointer.mouse_y <= rect.max[1]) {
            state.column_resize = .modified;
        } else if (nearHandle(pointer.mouse_x, cols.size_handle_x) and pointer.mouse_y >= rect.min[1] and pointer.mouse_y <= rect.max[1]) {
            state.column_resize = .size;
        }
    }

    if (state.column_resize == .none or !pointer.mouse_down) return;

    const bounds = normalizedColumnWidths(rect.width(), inner, state.type_column_width, state.modified_column_width, state.size_column_width);
    const usable_w = @max(0.0, rect.width() - inner * 2.0);
    const gaps_total = inner * 3.0;
    const name_w = @max(min_name_column_width, usable_w - gaps_total - bounds.type_w - bounds.modified_w - bounds.size_w);

    switch (state.column_resize) {
        .type => {
            const min_name_w = min_name_column_width;
            const max_name_w = @max(min_name_w, usable_w - gaps_total - min_type_column_width - bounds.modified_w - bounds.size_w);
            const next_name_w = std.math.clamp(pointer.mouse_x - (rect.min[0] + inner), min_name_w, max_name_w);
            state.type_column_width = @max(min_type_column_width, usable_w - gaps_total - next_name_w - bounds.modified_w - bounds.size_w);
        },
        .modified => {
            const min_type_w = min_type_column_width;
            const max_type_w = @max(min_type_w, usable_w - gaps_total - name_w - min_modified_column_width - bounds.size_w);
            const type_start_x = rect.min[0] + inner + name_w + inner;
            const next_type_w = std.math.clamp(pointer.mouse_x - type_start_x, min_type_w, max_type_w);
            state.type_column_width = next_type_w;
            state.modified_column_width = @max(min_modified_column_width, usable_w - gaps_total - name_w - next_type_w - bounds.size_w);
        },
        .size => {
            const min_modified_w = min_modified_column_width;
            const max_modified_w = @max(min_modified_w, usable_w - gaps_total - name_w - bounds.type_w - min_size_column_width);
            const modified_start_x = rect.min[0] + inner + name_w + inner + bounds.type_w + inner;
            const next_modified_w = std.math.clamp(pointer.mouse_x - modified_start_x, min_modified_w, max_modified_w);
            state.modified_column_width = next_modified_w;
            state.size_column_width = @max(min_size_column_width, usable_w - gaps_total - name_w - bounds.type_w - next_modified_w);
        },
        .none => {},
    }
}

fn headerPointerOnResizeHandle(rect: Rect, inner: f32, pointer: PointerState, state: *const State) bool {
    const cols = entryColumns(rect, inner, state);
    if (pointer.mouse_y < rect.min[1] or pointer.mouse_y > rect.max[1]) return false;
    return nearHandle(pointer.mouse_x, cols.type_handle_x) or nearHandle(pointer.mouse_x, cols.modified_handle_x) or nearHandle(pointer.mouse_x, cols.size_handle_x);
}

fn nearHandle(mouse_x: f32, handle_x: f32) bool {
    return @abs(mouse_x - handle_x) <= column_resize_hit_width * 0.5;
}

fn drawSortableHeaderCell(host: Host, rect: Rect, text_y: f32, label: []const u8, color: [4]f32) void {
    host.draw_text_trimmed(host.ctx, rect.min[0], text_y, rect.width(), label, color);
}

fn emitSortAction(slot: *?interfaces.FilesystemPanelAction, model: interfaces.FilesystemPanelModel, key: interfaces.FilesystemSortKey) void {
    if (model.sort_key == key) {
        emitAction(slot, .toggle_sort_direction);
    } else {
        emitAction(slot, .{ .set_sort_key = key });
    }
}

fn columnLabel(base: []const u8, active: bool, direction: interfaces.FilesystemSortDirection) []const u8 {
    if (!active) return base;
    return switch (direction) {
        .ascending => switch (base[0]) {
            else => switch (base.len) {
                else => if (std.mem.eql(u8, base, "Name")) "Name ^" else if (std.mem.eql(u8, base, "Type")) "Type ^" else if (std.mem.eql(u8, base, "Modified")) "Modified ^" else "Size ^",
            },
        },
        .descending => if (std.mem.eql(u8, base, "Name")) "Name v" else if (std.mem.eql(u8, base, "Type")) "Type v" else if (std.mem.eql(u8, base, "Modified")) "Modified v" else "Size v",
    };
}

fn drawColumnHandles(host: Host, cols: EntryColumns, colors: ThemeColors, pointer: PointerState, state: *State) void {
    const handles = [_]struct {
        x: f32,
        active: bool,
    }{
        .{ .x = cols.type_handle_x, .active = state.column_resize == .type or nearHandle(pointer.mouse_x, cols.type_handle_x) },
        .{ .x = cols.modified_handle_x, .active = state.column_resize == .modified or nearHandle(pointer.mouse_x, cols.modified_handle_x) },
        .{ .x = cols.size_handle_x, .active = state.column_resize == .size or nearHandle(pointer.mouse_x, cols.size_handle_x) },
    };

    for (handles) |handle| {
        const handle_rect = Rect.fromXYWH(handle.x, cols.name_rect.min[1], 1.0, cols.name_rect.height());
        host.draw_rect(host.ctx, handle_rect, if (handle.active) zcolors.withAlpha(colors.primary, 0.65) else zcolors.withAlpha(colors.border, 0.35));
    }
}

fn drawPreviewPane(
    host: Host,
    rect: Rect,
    layout: form_layout.Metrics,
    view: interfaces.FilesystemPanelView,
    colors: ThemeColors,
) void {
    const inner = layout.inner_inset;
    const content_w = rect.width() - inner * 2.0;
    host.draw_surface_panel(host.ctx, rect);
    host.draw_rect(host.ctx, rect, zcolors.withAlpha(colors.border, 0.45));

    var y = rect.min[1] + inner;
    const title_text = switch (view.preview_mode) {
        .empty => "No selection",
        else => if (view.preview_title.len > 0) view.preview_title else "Preview",
    };
    host.draw_text_trimmed(host.ctx, rect.min[0] + inner, y, content_w, title_text, colors.text_primary);
    y += layout.line_height + layout.row_gap * 0.3;

    var meta_buf: [320]u8 = undefined;
    const preview_meta = buildPreviewMeta(&meta_buf, view);
    if (preview_meta.len > 0) {
        host.draw_text_trimmed(host.ctx, rect.min[0] + inner, y, content_w, preview_meta, colors.text_secondary);
        y += layout.line_height + layout.row_gap * 0.3;
    }

    const status_text: ?[]const u8 = switch (view.preview_mode) {
        .loading => view.preview_status orelse "Loading preview...",
        .unsupported => view.preview_status orelse "Preview unavailable for this selection",
        .empty => view.preview_status orelse "Select a file or directory to inspect it here",
        .json, .text => if (view.preview_status) |value|
            if (std.mem.eql(u8, value, "JSON preview") or std.mem.eql(u8, value, "Text preview")) null else value
        else
            null,
    };
    if (status_text) |value| {
        host.draw_text_trimmed(host.ctx, rect.min[0] + inner, y, content_w, value, colors.primary);
        y += layout.line_height + layout.row_gap * 0.35;
    }

    switch (view.preview_mode) {
        .text, .json => if (view.preview_text) |text| {
            _ = host.draw_text_wrapped(host.ctx, rect.min[0] + inner, y, content_w, text, colors.text_primary);
        },
        .unsupported, .empty, .loading => if (view.preview_text) |text| {
            _ = host.draw_text_wrapped(host.ctx, rect.min[0] + inner, y, content_w, text, colors.text_secondary);
        },
    }
}

fn drawPreviewSplitter(host: Host, rect: Rect, colors: ThemeColors, active: bool) void {
    const line_y = rect.min[1] + rect.height() * 0.5;
    const line_rect = Rect.fromXYWH(rect.min[0], line_y, rect.width(), 1.0);
    host.draw_rect(host.ctx, line_rect, if (active) zcolors.withAlpha(colors.primary, 0.8) else zcolors.withAlpha(colors.border, 0.55));

    const handle_w = @min(54.0, rect.width() * 0.12);
    const handle_rect = Rect.fromXYWH(rect.min[0] + (rect.width() - handle_w) * 0.5, line_y - 2.0, handle_w, 4.0);
    host.draw_filled_rect(host.ctx, handle_rect, if (active) zcolors.withAlpha(colors.primary, 0.3) else zcolors.withAlpha(colors.border, 0.35));
}

fn clampPreviewRatio(value: f32) f32 {
    if (value <= 0.0) return preview_default_ratio;
    return std.math.clamp(value, preview_min_ratio, preview_max_ratio);
}

fn buildPreviewMeta(buf: []u8, view: interfaces.FilesystemPanelView) []const u8 {
    var stream = std.io.fixedBufferStream(buf);
    const writer = stream.writer();
    var first = true;
    appendMetaPart(writer, &first, kindLabel(view.preview_kind)) catch return "";
    if (view.preview_type_label.len > 0) appendMetaPart(writer, &first, view.preview_type_label) catch return stream.getWritten();
    if (view.preview_size_label) |value| appendMetaPart(writer, &first, value) catch return stream.getWritten();
    if (view.preview_modified_label) |value| appendMetaPart(writer, &first, value) catch return stream.getWritten();
    return stream.getWritten();
}

fn appendMetaPart(writer: anytype, first: *bool, value: []const u8) !void {
    if (value.len == 0) return;
    if (!first.*) try writer.writeAll(" | ");
    try writer.writeAll(value);
    first.* = false;
}

fn kindLabel(kind: interfaces.FilesystemEntryKind) []const u8 {
    return switch (kind) {
        .directory => "directory",
        .file => "file",
        .unknown => "unknown",
    };
}

fn rowRectHovered(rect: Rect, pointer: PointerState) bool {
    return rect.contains(.{ pointer.mouse_x, pointer.mouse_y });
}

fn emitAction(slot: *?interfaces.FilesystemPanelAction, next: interfaces.FilesystemPanelAction) void {
    if (slot.* == null) slot.* = next;
}
