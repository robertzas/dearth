import 'package:meta/meta.dart';

/// Per-table replication rules shared by devices and the Hub (SPEC §8.4–8.5).
@immutable
class SyncTableSpec {
  const SyncTableSpec(
    this.name, {
    this.appendOnly = false,
    this.hubOnly = false,
    this.hubFields = const {},
    this.kidVisible = false,
    this.kidWritable = false,
  });

  /// SQL table name.
  final String name;

  /// Rows are created once and never updated (ledgers, event logs).
  final bool appendOnly;

  /// Only the Hub node may write this table (integration-owned data).
  final bool hubOnly;

  /// Fields only the Hub may write (e.g. Google `etag`, `remote_id`).
  final Set<String> hubFields;

  /// Replicated to `kid_room` devices.
  final bool kidVisible;

  /// `kid_room` devices may write this table.
  final bool kidWritable;
}

/// Columns every synced table has; never written through op fields except
/// `deleted`.
const Set<String> kSyncSystemColumns = {'id', 'sync_clock', 'sync_hlc', 'sync_seq'};

const List<SyncTableSpec> _specs = [
  SyncTableSpec('households', kidVisible: true),
  SyncTableSpec('profiles', kidVisible: true),
  SyncTableSpec('devices', kidVisible: true),
  SyncTableSpec('settings', kidVisible: true),
  SyncTableSpec('calendar_sources',
      kidVisible: true, hubFields: {'kind', 'account_id', 'remote_id', 'status', 'last_sync_ms', 'url_hash'}),
  SyncTableSpec('events', kidVisible: true, hubFields: {'remote_id', 'etag', 'updated_ms'}),
  SyncTableSpec('lists'),
  SyncTableSpec('list_items'),
  SyncTableSpec('notes', kidVisible: true),
  SyncTableSpec('recipes'),
  SyncTableSpec('meal_entries', kidVisible: true),
  SyncTableSpec('shopping_states'),
  SyncTableSpec('recipe_ratings', kidVisible: true, kidWritable: true),
  SyncTableSpec('chores', kidVisible: true),
  SyncTableSpec('chore_instances', kidVisible: true, kidWritable: true),
  SyncTableSpec('routines', kidVisible: true),
  SyncTableSpec('routine_runs', kidVisible: true, kidWritable: true),
  SyncTableSpec('rewards', kidVisible: true),
  SyncTableSpec('redemptions', kidVisible: true, kidWritable: true),
  SyncTableSpec('ledger_entries', appendOnly: true, kidVisible: true, kidWritable: true),
  SyncTableSpec('sticker_placements', kidVisible: true, kidWritable: true),
  SyncTableSpec('feeling_entries', appendOnly: true, kidWritable: true),
  SyncTableSpec('game_events', appendOnly: true, kidVisible: true, kidWritable: true),
  SyncTableSpec('artworks', kidVisible: true, kidWritable: true),
  SyncTableSpec('music_tiles', kidVisible: true),
  SyncTableSpec('photo_sources', hubFields: {'kind', 'status', 'last_sync_ms', 'item_count', 'config'}),
  SyncTableSpec('photo_items',
      kidVisible: true,
      hubFields: {
        'source_id', 'remote_id', 'taken_ms', 'width', 'height', 'caption', 'location', //
        'blob_ref', 'thumb_blob', 'color', 'added_ms',
      }),
  SyncTableSpec('photo_collections', kidVisible: true),
  SyncTableSpec('weather_reports', hubOnly: true, kidVisible: true),
  SyncTableSpec('kitchen_timers', kidVisible: true, kidWritable: true),
  SyncTableSpec('home_layouts', kidVisible: true),
];

final Map<String, SyncTableSpec> kSyncTables = {for (final s in _specs) s.name: s};

/// Whether [field] is a column devices may write on [table].
bool deviceMayWriteField(SyncTableSpec spec, String field) =>
    !spec.hubOnly && !spec.hubFields.contains(field) && !kSyncSystemColumns.contains(field);

/// Device roles (SPEC §9.2).
abstract final class DeviceRole {
  static const kitchen = 'kitchen';
  static const kidRoom = 'kid_room';
  static const entry = 'entry';
  static const personal = 'personal';
  static const custom = 'custom';
  static const all = [kitchen, kidRoom, entry, personal, custom];
}

/// Whether a device with [role] receives [table].
bool roleReceivesTable(String role, String table) {
  final spec = kSyncTables[table];
  if (spec == null) return false;
  return role == DeviceRole.kidRoom ? spec.kidVisible : true;
}
