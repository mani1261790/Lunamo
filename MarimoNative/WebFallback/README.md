# Web fallback

Gate D keeps every `WKWebView` inside one output subtree. Each view uses a non-persistent
data store, a unique temporary read-access directory, a default-deny network rule, blocked
navigation, and a single height-only native message handler.

Renderer assets are copied into that temporary directory from the application bundle:

- Vega 6.4.0
- Vega-Lite 6.4.3
- Vega-Embed 7.2.0
- KaTeX 0.18.5

Their upstream licenses are stored beside the assets under `Assets/`.
