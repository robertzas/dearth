import 'package:material_ui/material_ui.dart';

/// A top-level destination (SPEC §11.2). Roles can hide any of them.
class Destination {
  const Destination({
    required this.id,
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.path,
    this.phoneLabel,
  });

  final String id;
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final String path;
  final String? phoneLabel;
}

/// Shell branches, in navigation order. Index = StatefulShellRoute branch.
const List<Destination> kDestinations = [
  Destination(id: 'home', label: 'Home', phoneLabel: 'Today', icon: Icons.home_outlined, activeIcon: Icons.home_rounded, path: '/'),
  Destination(id: 'calendar', label: 'Calendar', icon: Icons.calendar_month_outlined, activeIcon: Icons.calendar_month_rounded, path: '/calendar'),
  Destination(id: 'meals', label: 'Meals', icon: Icons.restaurant_menu_outlined, activeIcon: Icons.restaurant_menu_rounded, path: '/meals'),
  Destination(id: 'lists', label: 'Lists', icon: Icons.checklist_rounded, activeIcon: Icons.fact_check_rounded, path: '/lists'),
  Destination(id: 'kids', label: 'Kids', icon: Icons.child_care_outlined, activeIcon: Icons.child_care_rounded, path: '/kids'),
  Destination(id: 'toybox', label: 'Toys', icon: Icons.toys_outlined, activeIcon: Icons.toys_rounded, path: '/toybox'),
  Destination(id: 'weather', label: 'Weather', icon: Icons.wb_sunny_outlined, activeIcon: Icons.wb_sunny_rounded, path: '/weather'),
  Destination(id: 'photos', label: 'Photos', icon: Icons.photo_library_outlined, activeIcon: Icons.photo_library_rounded, path: '/photos'),
  Destination(id: 'settings', label: 'Settings', icon: Icons.settings_outlined, activeIcon: Icons.settings_rounded, path: '/settings'),
];

int destinationIndex(String id) => kDestinations.indexWhere((d) => d.id == id);
