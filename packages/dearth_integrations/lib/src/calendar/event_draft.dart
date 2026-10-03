import 'package:dearth_core/dearth_core.dart';
import 'package:meta/meta.dart';

/// A remote calendar event normalized for import (ICS, Google, CalDAV).
@immutable
class EventDraft {
  const EventDraft({
    required this.remoteId,
    required this.title,
    required this.allDay,
    required this.startMs,
    required this.endMs,
    this.startDate,
    this.endDate,
    this.tz,
    this.etag,
    this.location,
    this.notes,
    this.rrule,
    this.exdates = const [],
    this.recurringRemoteId,
    this.originalStartMs,
    this.status = 'confirmed',
    this.updatedMs,
  });

  final String remoteId;
  final String title;
  final bool allDay;
  final int startMs;
  final int endMs;
  final String? startDate;
  final String? endDate;
  final String? tz;
  final String? etag;
  final String? location;
  final String? notes;
  final String? rrule;
  final List<int> exdates;

  /// Set on modified/cancelled instances of a recurring series.
  final String? recurringRemoteId;
  final int? originalStartMs;
  final String status;
  final int? updatedMs;

  bool get isCancelled => status == 'cancelled';

  /// Deterministic local row id: the Hub needs no remote↔local mapping table
  /// and re-imports converge (SPEC §8.3).
  static String localId(String sourceId, String remoteId) => stableId('event', [sourceId, remoteId]);

  /// Field map for `Mutator.upsert('events', localId(...), …)`.
  /// Device-owned annotations (`profile_ids`, `icon`, `countdown`) are left
  /// untouched so they survive re-imports.
  Map<String, Object?> toFields(String sourceId) => {
        'source_id': sourceId,
        'remote_id': remoteId,
        'etag': etag,
        'title': title,
        'start_ms': startMs,
        'end_ms': endMs,
        'all_day': allDay,
        'start_date': startDate,
        'end_date': endDate,
        'tz': tz,
        'rrule': rrule,
        'exdates': exdates,
        'recurring_parent_id': recurringRemoteId == null ? null : localId(sourceId, recurringRemoteId!),
        'original_start_ms': originalStartMs,
        'location': location,
        'notes': notes,
        'status': status,
        'updated_ms': updatedMs,
        'deleted': false,
      };
}
