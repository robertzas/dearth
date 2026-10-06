// Drift schema shared by every device and the Hub (SPEC §8.2).
//
// Conventions (SPEC §8.3):
// * Synced tables mix in [SyncRow] and use text UUID primary keys.
// * Every synced column is nullable or has a default, so a partial op can
//   always be applied as an insert.
// * Instants are epoch-ms integers (`*_ms`), local dates are `YYYY-MM-DD`
//   text, and structured values are JSON text.
import 'package:drift/drift.dart';

/// Columns shared by every replicated table.
mixin SyncRow on Table {
  TextColumn get id => text()();

  /// JSON map field → packed HLC of the last applied write (SPEC §8.4.2).
  TextColumn get syncClock => text().withDefault(const Constant('{}'))();

  /// Max HLC applied to the row.
  TextColumn get syncHlc => text().withDefault(const Constant(''))();

  /// Hub sequence of the last applied op.
  IntColumn get syncSeq => integer().withDefault(const Constant(0))();

  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
}

// ───────────────────────────── Household & people ───────────────────────────

@DataClassName('Household')
class Households extends Table with SyncRow {
  TextColumn get name => text().withDefault(const Constant('Our family'))();
  TextColumn get timezone => text().withDefault(const Constant('UTC'))();
  TextColumn get locale => text().withDefault(const Constant('en-US'))();
  TextColumn get units => text().withDefault(const Constant('imperial'))();
  IntColumn get weekStart => integer().withDefault(const Constant(7))();
  BoolColumn get clock24 => boolean().withDefault(const Constant(false))();
  RealColumn get lat => real().nullable()();
  RealColumn get lon => real().nullable()();
  TextColumn get locationLabel => text().nullable()();
  TextColumn get postalCode => text().nullable()();
  TextColumn get countryCode => text().withDefault(const Constant('US'))();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('Profile')
class Profiles extends Table with SyncRow {
  TextColumn get name => text().withDefault(const Constant(''))();
  TextColumn get nickname => text().nullable()();
  TextColumn get role => text().withDefault(const Constant('adult'))();
  IntColumn get color => integer().withDefault(const Constant(0))();
  TextColumn get emoji => text().nullable()();
  TextColumn get avatarBlob => text().nullable()();
  TextColumn get birthday => text().nullable()();
  TextColumn get kidStage => text().nullable()();
  TextColumn get buddy => text().nullable()();
  TextColumn get pinHash => text().nullable()();
  TextColumn get sortKey => text().withDefault(const Constant('m'))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('Device')
class Devices extends Table with SyncRow {
  TextColumn get name => text().withDefault(const Constant('Display'))();
  TextColumn get role => text().withDefault(const Constant('kitchen'))();
  TextColumn get platform => text().nullable()();
  TextColumn get model => text().nullable()();
  TextColumn get orientation => text().withDefault(const Constant('auto'))();
  RealColumn get diagonalIn => real().nullable()();
  TextColumn get viewingDistance => text().withDefault(const Constant('room'))();
  TextColumn get tierOverride => text().nullable()();
  TextColumn get ownerProfileId => text().nullable()();
  TextColumn get settings => text().withDefault(const Constant('{}'))();
  TextColumn get appVersion => text().nullable()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('Setting')
class Settings extends Table with SyncRow {
  TextColumn get scope => text().withDefault(const Constant('household'))();
  TextColumn get key => text().withDefault(const Constant(''))();
  TextColumn get value => text().withDefault(const Constant('null'))();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

// ───────────────────────────────── Calendar ─────────────────────────────────

@DataClassName('CalendarSource')
class CalendarSources extends Table with SyncRow {
  TextColumn get kind => text().withDefault(const Constant('local'))();
  TextColumn get accountId => text().nullable()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get name => text().withDefault(const Constant('Family'))();
  IntColumn get color => integer().withDefault(const Constant(0xFF5B5BD6))();
  TextColumn get defaultProfileIds => text().withDefault(const Constant('[]'))();
  BoolColumn get writable => boolean().withDefault(const Constant(true))();
  TextColumn get visibleRoles => text().withDefault(const Constant('[]'))();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  TextColumn get url => text().nullable()();
  TextColumn get status => text().nullable()();
  IntColumn get lastSyncMs => integer().nullable()();
  TextColumn get sortKey => text().withDefault(const Constant('m'))();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('Event')
@TableIndex(name: 'events_start', columns: {#startMs})
@TableIndex(name: 'events_source', columns: {#sourceId})
@TableIndex(name: 'events_parent', columns: {#recurringParentId})
class Events extends Table with SyncRow {
  TextColumn get sourceId => text().withDefault(const Constant(''))();
  TextColumn get remoteId => text().nullable()();
  TextColumn get etag => text().nullable()();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get icon => text().nullable()();
  IntColumn get startMs => integer().withDefault(const Constant(0))();
  IntColumn get endMs => integer().withDefault(const Constant(0))();
  BoolColumn get allDay => boolean().withDefault(const Constant(false))();
  TextColumn get startDate => text().nullable()();
  TextColumn get endDate => text().nullable()();
  TextColumn get tz => text().nullable()();
  TextColumn get rrule => text().nullable()();
  TextColumn get exdates => text().withDefault(const Constant('[]'))();
  TextColumn get recurringParentId => text().nullable()();
  IntColumn get originalStartMs => integer().nullable()();
  TextColumn get location => text().nullable()();
  TextColumn get notes => text().nullable()();
  BoolColumn get countdown => boolean().withDefault(const Constant(false))();
  TextColumn get reminders => text().withDefault(const Constant('[]'))();
  TextColumn get profileIds => text().withDefault(const Constant('[]'))();
  IntColumn get color => integer().nullable()();
  TextColumn get status => text().withDefault(const Constant('confirmed'))();
  IntColumn get updatedMs => integer().nullable()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

// ─────────────────────────────── Lists & notes ──────────────────────────────

@DataClassName('DList')
class Lists extends Table with SyncRow {
  TextColumn get title => text().withDefault(const Constant('List'))();
  TextColumn get kind => text().withDefault(const Constant('todo'))();
  TextColumn get visibility => text().withDefault(const Constant('family'))();
  TextColumn get ownerProfileId => text().nullable()();
  TextColumn get icon => text().nullable()();
  IntColumn get color => integer().nullable()();
  TextColumn get sortKey => text().withDefault(const Constant('m'))();
  BoolColumn get isTemplate => boolean().withDefault(const Constant(false))();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('ListItem')
@TableIndex(name: 'list_items_list', columns: {#listId})
class ListItems extends Table with SyncRow {
  TextColumn get listId => text().withDefault(const Constant(''))();
  TextColumn get itemText => text().named('text').withDefault(const Constant(''))();
  RealColumn get qty => real().nullable()();
  TextColumn get unit => text().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get category => text().nullable()();
  BoolColumn get checked => boolean().withDefault(const Constant(false))();
  IntColumn get checkedMs => integer().nullable()();
  TextColumn get sortKey => text().withDefault(const Constant('m'))();
  TextColumn get assigneeProfileId => text().nullable()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('Note')
class Notes extends Table with SyncRow {
  TextColumn get kind => text().withDefault(const Constant('sticky'))();
  TextColumn get body => text().withDefault(const Constant(''))();
  IntColumn get color => integer().withDefault(const Constant(1))();
  TextColumn get blobRef => text().nullable()();
  TextColumn get targets => text().withDefault(const Constant('[]'))();
  IntColumn get startsMs => integer().nullable()();
  IntColumn get expiresMs => integer().nullable()();
  TextColumn get authorProfileId => text().nullable()();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  TextColumn get sortKey => text().withDefault(const Constant('m'))();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

// ─────────────────────────────────── Meals ──────────────────────────────────

@DataClassName('Recipe')
class Recipes extends Table with SyncRow {
  TextColumn get source => text().withDefault(const Constant('box'))();
  TextColumn get sourceId => text().nullable()();
  TextColumn get url => text().nullable()();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get imageUrl => text().nullable()();
  TextColumn get imageBlob => text().nullable()();
  IntColumn get servings => integer().withDefault(const Constant(4))();
  IntColumn get prepMin => integer().nullable()();
  IntColumn get cookMin => integer().nullable()();
  IntColumn get totalMin => integer().nullable()();
  TextColumn get cuisine => text().nullable()();
  TextColumn get category => text().nullable()();
  TextColumn get tags => text().withDefault(const Constant('[]'))();
  TextColumn get diets => text().withDefault(const Constant('[]'))();
  TextColumn get ingredients => text().withDefault(const Constant('[]'))();
  TextColumn get steps => text().withDefault(const Constant('[]'))();
  TextColumn get nutrition => text().nullable()();
  TextColumn get attribution => text().nullable()();
  BoolColumn get saved => boolean().withDefault(const Constant(false))();
  TextColumn get notes => text().nullable()();
  IntColumn get createdMs => integer().nullable()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('MealEntry')
@TableIndex(name: 'meal_entries_date', columns: {#date})
class MealEntries extends Table with SyncRow {
  TextColumn get date => text().withDefault(const Constant(''))();
  TextColumn get slot => text().withDefault(const Constant('dinner'))();
  TextColumn get recipeId => text().nullable()();
  TextColumn get title => text().nullable()();
  IntColumn get servings => integer().nullable()();
  TextColumn get leftoversOf => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get profileIds => text().withDefault(const Constant('[]'))();
  TextColumn get sortKey => text().withDefault(const Constant('m'))();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('ShoppingState')
class ShoppingStates extends Table with SyncRow {
  TextColumn get itemKey => text().named('key').withDefault(const Constant(''))();
  BoolColumn get checked => boolean().withDefault(const Constant(false))();
  BoolColumn get haveIt => boolean().withDefault(const Constant(false))();
  TextColumn get qtyAtCheck => text().nullable()();
  IntColumn get updatedMs => integer().nullable()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('RecipeRating')
class RecipeRatings extends Table with SyncRow {
  TextColumn get recipeId => text().withDefault(const Constant(''))();
  TextColumn get profileId => text().withDefault(const Constant(''))();
  IntColumn get score => integer().withDefault(const Constant(0))();
  IntColumn get atMs => integer().nullable()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

// ─────────────────────────────── Kids & chores ──────────────────────────────

@DataClassName('Chore')
class Chores extends Table with SyncRow {
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get emoji => text().nullable()();
  TextColumn get photoBlob => text().nullable()();
  TextColumn get voiceBlob => text().nullable()();
  TextColumn get voiceLine => text().nullable()();
  TextColumn get rrule => text().withDefault(const Constant('FREQ=DAILY'))();
  TextColumn get anchorDate => text().nullable()();
  TextColumn get assignees => text().withDefault(const Constant('[]'))();
  IntColumn get stars => integer().withDefault(const Constant(1))();
  BoolColumn get sticker => boolean().withDefault(const Constant(true))();
  IntColumn get jar => integer().withDefault(const Constant(1))();
  BoolColumn get needsApproval => boolean().withDefault(const Constant(false))();
  TextColumn get timeWindow => text().named('window').withDefault(const Constant('any'))();
  BoolColumn get adult => boolean().withDefault(const Constant(false))();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  TextColumn get sortKey => text().withDefault(const Constant('m'))();
  TextColumn get notes => text().nullable()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('ChoreInstance')
@TableIndex(name: 'chore_instances_date', columns: {#date})
class ChoreInstances extends Table with SyncRow {
  TextColumn get choreId => text().withDefault(const Constant(''))();
  TextColumn get date => text().withDefault(const Constant(''))();
  TextColumn get profileId => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get completedMs => integer().nullable()();
  TextColumn get completedBy => text().nullable()();
  TextColumn get approvedBy => text().nullable()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('Routine')
class Routines extends Table with SyncRow {
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get emoji => text().nullable()();
  TextColumn get kind => text().withDefault(const Constant('custom'))();
  TextColumn get profileIds => text().withDefault(const Constant('[]'))();
  TextColumn get steps => text().withDefault(const Constant('[]'))();
  TextColumn get rrule => text().withDefault(const Constant('FREQ=DAILY'))();
  TextColumn get anchorDate => text().nullable()();
  TextColumn get startTime => text().nullable()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  TextColumn get sortKey => text().withDefault(const Constant('m'))();
  TextColumn get coverBlob => text().nullable()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('RoutineRun')
class RoutineRuns extends Table with SyncRow {
  TextColumn get routineId => text().withDefault(const Constant(''))();
  TextColumn get date => text().withDefault(const Constant(''))();
  TextColumn get profileId => text().nullable()();
  TextColumn get doneSteps => text().withDefault(const Constant('[]'))();
  TextColumn get status => text().withDefault(const Constant('in_progress'))();
  IntColumn get startedMs => integer().nullable()();
  IntColumn get completedMs => integer().nullable()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('Reward')
class Rewards extends Table with SyncRow {
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get emoji => text().nullable()();
  TextColumn get imageBlob => text().nullable()();
  TextColumn get kind => text().withDefault(const Constant('store'))();
  IntColumn get cost => integer().withDefault(const Constant(10))();
  TextColumn get currency => text().withDefault(const Constant('star'))();
  TextColumn get profileIds => text().withDefault(const Constant('[]'))();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  IntColumn get limitCount => integer().nullable()();
  TextColumn get sortKey => text().withDefault(const Constant('m'))();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('Redemption')
class Redemptions extends Table with SyncRow {
  TextColumn get rewardId => text().withDefault(const Constant(''))();
  TextColumn get profileId => text().nullable()();
  IntColumn get cost => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get requestedMs => integer().nullable()();
  TextColumn get decidedBy => text().nullable()();
  IntColumn get decidedMs => integer().nullable()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Append-only value ledger (stars, stickers, jar tokens, hearts…).
@DataClassName('LedgerEntry')
@TableIndex(name: 'ledger_profile', columns: {#profileId})
class LedgerEntries extends Table with SyncRow {
  TextColumn get profileId => text().nullable()();
  TextColumn get currency => text().withDefault(const Constant('star'))();
  IntColumn get delta => integer().withDefault(const Constant(0))();
  TextColumn get reason => text().withDefault(const Constant('manual'))();
  TextColumn get refTable => text().nullable()();
  TextColumn get refId => text().nullable()();
  IntColumn get atMs => integer().withDefault(const Constant(0))();
  TextColumn get byProfileId => text().nullable()();
  TextColumn get note => text().nullable()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('StickerPlacement')
class StickerPlacements extends Table with SyncRow {
  TextColumn get profileId => text().withDefault(const Constant(''))();
  IntColumn get page => integer().withDefault(const Constant(0))();
  TextColumn get sticker => text().withDefault(const Constant('⭐'))();
  RealColumn get x => real().withDefault(const Constant(0.5))();
  RealColumn get y => real().withDefault(const Constant(0.5))();
  RealColumn get scale => real().withDefault(const Constant(1))();
  RealColumn get rotation => real().withDefault(const Constant(0))();
  IntColumn get atMs => integer().withDefault(const Constant(0))();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('FeelingEntry')
class FeelingEntries extends Table with SyncRow {
  TextColumn get profileId => text().withDefault(const Constant(''))();
  TextColumn get feeling => text().withDefault(const Constant(''))();
  TextColumn get note => text().nullable()();
  IntColumn get atMs => integer().withDefault(const Constant(0))();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('GameEvent')
class GameEvents extends Table with SyncRow {
  TextColumn get profileId => text().nullable()();
  TextColumn get game => text().withDefault(const Constant(''))();
  IntColumn get level => integer().withDefault(const Constant(1))();
  TextColumn get result => text().withDefault(const Constant('played'))();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  IntColumn get atMs => integer().withDefault(const Constant(0))();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('Artwork')
class Artworks extends Table with SyncRow {
  TextColumn get profileId => text().nullable()();
  TextColumn get game => text().withDefault(const Constant('paint'))();
  TextColumn get blobRef => text().nullable()();
  IntColumn get atMs => integer().withDefault(const Constant(0))();
  BoolColumn get showInScreensaver => boolean().withDefault(const Constant(true))();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('MusicTile')
class MusicTiles extends Table with SyncRow {
  TextColumn get board => text().withDefault(const Constant('kids'))();
  TextColumn get source => text().withDefault(const Constant('file'))();
  TextColumn get ref => text().withDefault(const Constant(''))();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get artist => text().nullable()();
  TextColumn get artUrl => text().nullable()();
  TextColumn get artBlob => text().nullable()();
  TextColumn get emoji => text().nullable()();
  IntColumn get color => integer().nullable()();
  TextColumn get sortKey => text().withDefault(const Constant('m'))();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

// ─────────────────────────────────── Photos ─────────────────────────────────

@DataClassName('PhotoSource')
class PhotoSources extends Table with SyncRow {
  TextColumn get kind => text().withDefault(const Constant('folder'))();
  TextColumn get name => text().withDefault(const Constant('Photos'))();
  TextColumn get config => text().withDefault(const Constant('{}'))();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  TextColumn get status => text().nullable()();
  IntColumn get lastSyncMs => integer().nullable()();
  IntColumn get itemCount => integer().withDefault(const Constant(0))();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('PhotoItem')
@TableIndex(name: 'photo_items_source', columns: {#sourceId})
class PhotoItems extends Table with SyncRow {
  TextColumn get sourceId => text().withDefault(const Constant(''))();
  TextColumn get remoteId => text().nullable()();
  IntColumn get takenMs => integer().nullable()();
  IntColumn get width => integer().nullable()();
  IntColumn get height => integer().nullable()();
  TextColumn get caption => text().nullable()();
  TextColumn get location => text().nullable()();
  TextColumn get blobRef => text().nullable()();
  TextColumn get thumbBlob => text().nullable()();
  IntColumn get color => integer().nullable()();
  BoolColumn get hidden => boolean().withDefault(const Constant(false))();
  BoolColumn get favorite => boolean().withDefault(const Constant(false))();
  IntColumn get addedMs => integer().nullable()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('PhotoCollection')
class PhotoCollections extends Table with SyncRow {
  TextColumn get name => text().withDefault(const Constant('Collection'))();
  TextColumn get rules => text().withDefault(const Constant('{}'))();
  TextColumn get sortKey => text().withDefault(const Constant('m'))();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

// ──────────────────────────────── Home & misc ───────────────────────────────

/// Hub-written weather (single row `current`).
@DataClassName('WeatherReportRow')
class WeatherReports extends Table with SyncRow {
  TextColumn get data => text().withDefault(const Constant('{}'))();
  IntColumn get fetchedMs => integer().withDefault(const Constant(0))();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('KitchenTimer')
class KitchenTimers extends Table with SyncRow {
  TextColumn get label => text().withDefault(const Constant('Timer'))();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  IntColumn get startedMs => integer().nullable()();
  IntColumn get pausedRemainingMs => integer().nullable()();
  TextColumn get status => text().withDefault(const Constant('running'))();
  TextColumn get createdBy => text().nullable()();
  TextColumn get kind => text().withDefault(const Constant('kitchen'))();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('HomeLayout')
class HomeLayouts extends Table with SyncRow {
  TextColumn get widgets => text().withDefault(const Constant('[]'))();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

// ──────────────────────────── Device-local tables ───────────────────────────

/// Ops created locally and not yet acknowledged by the Hub.
@DataClassName('OutboxEntry')
class Outbox extends Table {
  IntColumn get seq => integer().autoIncrement()();
  TextColumn get opId => text()();
  TextColumn get opJson => text()();
  IntColumn get createdMs => integer()();
}

/// Small device-local key/value store (sync cursor, node id, device prefs).
@DataClassName('KvEntry')
class KvEntries extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  @override
  Set<Column<Object>> get primaryKey => {key};
}

// ────────────────────────────── Hub-only tables ─────────────────────────────

@DataClassName('OpLogEntry')
@TableIndex(name: 'op_log_row', columns: {#tbl, #rowId})
class OpLog extends Table {
  IntColumn get seq => integer().autoIncrement()();
  TextColumn get opId => text().unique()();
  TextColumn get tbl => text()();
  TextColumn get rowId => text()();
  TextColumn get opJson => text()();
  TextColumn get deviceId => text()();
  IntColumn get receivedMs => integer()();
}

@DataClassName('DeviceAuth')
class DeviceAuths extends Table {
  TextColumn get deviceId => text()();
  TextColumn get tokenHash => text()();
  TextColumn get name => text().withDefault(const Constant('Device'))();
  TextColumn get role => text().withDefault(const Constant('kitchen'))();
  BoolColumn get admin => boolean().withDefault(const Constant(false))();
  IntColumn get createdMs => integer()();
  IntColumn get revokedMs => integer().nullable()();
  IntColumn get lastSeenMs => integer().nullable()();
  @override
  Set<Column<Object>> get primaryKey => {deviceId};
}

@DataClassName('Pairing')
class Pairings extends Table {
  TextColumn get id => text()();
  TextColumn get code => text()();
  TextColumn get secretHash => text().nullable()();
  TextColumn get deviceName => text().withDefault(const Constant('Display'))();
  TextColumn get platform => text().nullable()();
  TextColumn get model => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  TextColumn get role => text().withDefault(const Constant('kitchen'))();
  BoolColumn get admin => boolean().withDefault(const Constant(false))();
  TextColumn get orientation => text().nullable()();
  TextColumn get deviceId => text().nullable()();
  IntColumn get requestedMs => integer()();
  IntColumn get expiresMs => integer()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Encrypted integration secrets (SPEC §9.5). Never synced.
@DataClassName('SecretEntry')
class Secrets extends Table {
  TextColumn get id => text()();
  TextColumn get value => text()();
  IntColumn get updatedMs => integer()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('BlobEntry')
class Blobs extends Table {
  TextColumn get sha => text()();
  TextColumn get mime => text()();
  IntColumn get bytes => integer()();
  IntColumn get width => integer().nullable()();
  IntColumn get height => integer().nullable()();
  TextColumn get origin => text().nullable()();
  IntColumn get createdMs => integer()();
  @override
  Set<Column<Object>> get primaryKey => {sha};
}

/// Every recipe the Hub has fetched from a recipe API, kept indefinitely
/// (owner request 2026-10-06; SPEC §13.6): a recipe seen once can be found
/// again offline, after a quota runs out, or when a source goes away. Never
/// synced; devices keep the recipes they save in [Recipes].
@DataClassName('CachedRecipe')
class RecipeCache extends Table {
  /// The recipe's id ("themealdb:52772").
  TextColumn get id => text()();

  /// The provider that returned it.
  TextColumn get source => text()();
  TextColumn get title => text()();

  /// The whole recipe, as `RecipeData.toJson`.
  TextColumn get data => text()();
  IntColumn get firstSeenMs => integer()();
  IntColumn get lastSeenMs => integer()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('JobState')
class JobStates extends Table {
  TextColumn get id => text()();
  IntColumn get lastRunMs => integer().nullable()();
  IntColumn get lastOkMs => integer().nullable()();
  TextColumn get lastError => text().nullable()();
  TextColumn get data => text().withDefault(const Constant('{}'))();
  @override
  Set<Column<Object>> get primaryKey => {id};
}
