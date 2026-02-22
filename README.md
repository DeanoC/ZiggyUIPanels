# ZiggyUIPanels

Contract and boundary package for Ziggy panel-level UI extraction.

## What This Package Contains

- `AttachmentOpen`: shared attachment-open payload used by panel pipelines.
- `DrawResult`: shared per-panel render result surface.
- `showcase_panel.ShowcasePanel(Host)`: host-parameterized concrete showcase
  panel implementation extracted from `ziggy-ui`.

This package keeps extraction incremental:
- Contracts stay centralized here.
- Concrete panel implementations move here as host-parameterized modules so
  `ziggy-ui` remains the base UI toolkit while app-level panel behavior lives
  outside it.

## Build

- `zig build`
- `zig build test`

## License

MIT
