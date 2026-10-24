import 'media_filter.dart';

/// Combined filter listing result. A server may return categories with no values
/// pre-loaded; Silo pre-populates [cachedValues] so the FiltersBottomSheet
/// avoids a second round-trip per category.
class LibraryFilterResult {
  final List<MediaFilter> filters;
  final Map<String, List<MediaFilterValue>> cachedValues;

  const LibraryFilterResult({required this.filters, required this.cachedValues});

  static const empty = LibraryFilterResult(filters: [], cachedValues: {});
}
