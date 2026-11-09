import 'settings_service.dart';

/// The rails of the Library tab below its hero, which the user can reorder
/// and hide on the Edit Library page. Declared in the default order.
///
/// Stored by [Enum.name] in [SettingsService.libraryRowOrder] and
/// [SettingsService.libraryRowsHidden], so renaming a value loses its place.
enum LibraryRow {
  continueWatching,
  calendar,
  seasonal,
  runtime,
  forYou,
  networks,
  genres;

  static final Map<String, LibraryRow> _byName = {for (final row in values) row.name: row};

  static final List<String> defaultOrder = List.unmodifiable([for (final row in values) row.name]);

  static LibraryRow? fromName(String name) => _byName[name];

  /// Every row in [stored]'s order, without unknown names or repeats. A row
  /// the stored order lacks (one added in a later version) goes at the end.
  static List<LibraryRow> orderOf(List<String> stored) {
    final order = <LibraryRow>{for (final name in stored) ?fromName(name)};
    return [...order, ...values.where((row) => !order.contains(row))];
  }

  /// Every row, in the saved order.
  static List<LibraryRow> savedOrder() => orderOf(SettingsService.instance.read(SettingsService.libraryRowOrder));

  /// The rows the user hid.
  static Set<LibraryRow> savedHidden() => {
    for (final name in SettingsService.instance.read(SettingsService.libraryRowsHidden)) ?fromName(name),
  };

  /// The rows the Library shows, in order.
  static List<LibraryRow> shown() {
    final hidden = savedHidden();
    return [
      for (final row in savedOrder())
        if (!hidden.contains(row)) row,
    ];
  }
}
