/// Dearth provider adapters (SPEC §13). Pure Dart; used by the Hub (also
/// when it runs inside the app, in Solo mode).
library;

export 'src/calendar/event_draft.dart';
export 'src/calendar/google_calendar.dart';
export 'src/calendar/ics.dart';
export 'src/calendar/oauth.dart';
export 'src/demo/demo_seed.dart';
export 'src/http/fetcher.dart';
export 'src/lists/google_tasks.dart';
export 'src/music/music.dart';
export 'src/photos/photos.dart';
export 'src/recipes/aggregate.dart';
export 'src/recipes/catalog.dart';
export 'src/recipes/quota.dart';
export 'src/recipes/racion.dart';
export 'src/recipes/recipe_provider.dart';
export 'src/recipes/recipeapi.dart';
export 'src/recipes/spoonacular.dart';
export 'src/recipes/tasty.dart';
export 'src/recipes/themealdb.dart';
export 'src/recipes/url_import.dart';
export 'src/recipes/wikibooks.dart';
export 'src/weather/weather_providers.dart';
export 'src/weather/weather_service.dart';
