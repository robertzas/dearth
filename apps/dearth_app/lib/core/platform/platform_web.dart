import 'package:web/web.dart' as web;

void reloadApp() => web.window.location.reload();

/// Replaces the page URL without reloading (drops one-shot flags like `reset`).
void replaceUrl(String url) => web.window.history.replaceState(null, '', url);

/// Browsers don't say.
int? processRssMb() => null;
