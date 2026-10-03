/// The 12-color profile palette (SPEC §11.3). Profile rows store an index;
/// the UI derives tints and on-colors per theme.
const List<(String name, int argb)> kProfilePalette = [
  ('Coral', 0xFFF2795D),
  ('Amber', 0xFFF2B33D),
  ('Lime', 0xFF8CC152),
  ('Mint', 0xFF3CC59A),
  ('Teal', 0xFF26A9A0),
  ('Sky', 0xFF3D9BE9),
  ('Indigo', 0xFF5B6CF2),
  ('Violet', 0xFF9B6CF0),
  ('Pink', 0xFFEE6BA8),
  ('Red', 0xFFE5484D),
  ('Brown', 0xFFA8785A),
  ('Slate', 0xFF6B7A8F),
];

int profileColor(int index) => kProfilePalette[index % kProfilePalette.length].$2;

/// Sticky-note color values; `notes.color` stores an index (the UI uses the
/// matching `kNoteColors` tokens from dearth_ui).
const List<int> kNoteColorValues = [0xFFFFF4B8, 0xFFFFD9C7, 0xFFD7F2D0, 0xFFD3E7FF, 0xFFEADCFF, 0xFFFFDDEA];

/// Profile roles (SPEC §9.1).
abstract final class ProfileRole {
  static const adult = 'adult';
  static const child = 'child';
  static const caregiver = 'caregiver';
  static const guest = 'guest';
  static const pet = 'pet';
  static const all = [adult, child, caregiver, guest, pet];
}

/// Kid stages (SPEC §10.7.1).
abstract final class KidStage {
  static const little = 'little';
  static const preschool = 'preschool';
  static const prek = 'prek';
  static const all = [little, preschool, prek];

  /// Suggested stage for an age in years.
  static String forAge(double years) => years < 3 ? little : (years < 4 ? preschool : prek);

  static String label(String? stage) => switch (stage) {
        little => 'Little (2–3)',
        preschool => 'Preschool (3–4)',
        prek => 'Pre-K (4–5)',
        _ => 'Grown-up',
      };
}
