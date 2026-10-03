import 'package:dearth_integrations/dearth_integrations.dart';

import '../auth.dart';
import '../blobs.dart';
import '../config.dart';
import '../connections.dart';
import '../integrations.dart';
import '../jobs/google_job.dart';
import '../jobs/scheduler.dart';
import '../kernel.dart';
import '../recipes_service.dart';
import '../storage.dart';

/// Everything a route handler may need.
class HubContext {
  HubContext({
    required this.config,
    required this.kernel,
    required this.auth,
    required this.connections,
    required this.blobs,
    required this.integrations,
    required this.recipes,
    required this.scheduler,
    required this.jobs,
    required this.google,
    required this.fetcher,
    required this.vault,
  }) : startedMs = DateTime.now().millisecondsSinceEpoch;

  final HubConfig config;
  final HubKernel kernel;
  final HubAuth auth;
  final ConnectionHub connections;
  final BlobStore blobs;
  final Integrations integrations;
  final RecipeService recipes;
  final Scheduler scheduler;
  final JobStore jobs;
  final GoogleCalendarJob google;
  final Fetcher fetcher;
  final SecretVault vault;
  final int startedMs;

  /// Pending OAuth flows by state (expire after 15 minutes).
  final Map<String, Map<String, Object?>> oauthStates = {};
}
