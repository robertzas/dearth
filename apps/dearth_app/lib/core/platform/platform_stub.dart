import 'dart:io';

/// Native: a "reload" restarts the app shell from the router's root.
void reloadApp() {}

void replaceUrl(String url) {}

/// This process's resident memory in MB, for the Hub's frame stats.
int? processRssMb() => ProcessInfo.currentRss ~/ (1024 * 1024);
