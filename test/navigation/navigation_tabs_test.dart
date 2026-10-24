import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/navigation/navigation_tabs.dart';

void main() {
  group('NavigationTab.resolveDefaultTab', () {
    test('offline prefers Downloads when available', () {
      expect(NavigationTab.resolveDefaultTab(isOffline: true, preferredStartup: null), NavigationTabId.downloads);
    });

    test('offline ignores an online-only preferred section', () {
      expect(
        NavigationTab.resolveDefaultTab(isOffline: true, preferredStartup: NavigationTabId.search),
        NavigationTabId.downloads,
      );
    });

    test('online honours the preferred section when it is visible', () {
      expect(
        NavigationTab.resolveDefaultTab(isOffline: false, preferredStartup: NavigationTabId.search),
        NavigationTabId.search,
      );
      expect(
        NavigationTab.resolveDefaultTab(isOffline: false, preferredStartup: NavigationTabId.libraries),
        NavigationTabId.libraries,
      );
    });

    test('online defaults to Home when no preference is set', () {
      expect(NavigationTab.resolveDefaultTab(isOffline: false, preferredStartup: null), NavigationTabId.discover);
    });

    test('online falls back to Home when preferred Explore is unavailable', () {
      expect(
        NavigationTab.resolveDefaultTab(isOffline: false, preferredStartup: NavigationTabId.explore),
        NavigationTabId.discover,
      );
      expect(
        NavigationTab.resolveDefaultTab(isOffline: false, hasExplore: true, preferredStartup: NavigationTabId.explore),
        NavigationTabId.explore,
      );
    });
  });

  group('NavigationTab.getVisibleTabs', () {
    test('hides Explore until a catalog source is connected', () {
      final without = NavigationTab.getVisibleTabs(isOffline: false);
      expect(without.map((tab) => tab.id), isNot(contains(NavigationTabId.explore)));

      final with_ = NavigationTab.getVisibleTabs(isOffline: false, hasExplore: true);
      final ids = with_.map((tab) => tab.id).toList();
      expect(ids, contains(NavigationTabId.explore));
      // Explore sits after Libraries, directly before Search.
      expect(ids.indexOf(NavigationTabId.explore), ids.indexOf(NavigationTabId.libraries) + 1);
      expect(ids.indexOf(NavigationTabId.explore), ids.indexOf(NavigationTabId.search) - 1);
    });

    test('Explore is online-only', () {
      final offline = NavigationTab.getVisibleTabs(isOffline: true, hasExplore: true);
      expect(offline.map((tab) => tab.id), isNot(contains(NavigationTabId.explore)));
    });

    test('there is no live TV tab', () {
      expect(NavigationTabId.values.map((id) => id.name), isNot(contains('liveTv')));
    });
  });
}
