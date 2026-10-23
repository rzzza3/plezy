import 'package:flutter/foundation.dart';
import '../media/media_item.dart';
import '../media/play_queue.dart';
import '../mixins/disposable_change_notifier_mixin.dart';

/// Outcome of resolving one direction in the active playback queue.
enum QueueNavigationStatus {
  /// The adjacent queue item was found.
  found,

  /// The active queue was loaded successfully and has no item in this direction.
  boundary,

  /// No active queue or matching current item was available.
  unavailable,

  /// The queue could not be walked.
  failed,
}

@immutable
class QueueNavigationResult {
  const QueueNavigationResult._(this.status, this.item);

  const QueueNavigationResult.found(MediaItem item) : this._(QueueNavigationStatus.found, item);

  const QueueNavigationResult.boundary() : this._(QueueNavigationStatus.boundary, null);

  const QueueNavigationResult.unavailable() : this._(QueueNavigationStatus.unavailable, null);

  const QueueNavigationResult.failed() : this._(QueueNavigationStatus.failed, null);

  final QueueNavigationStatus status;
  final MediaItem? item;
}

/// Result of trying to locate the current queue index.
class _IndexLookupResult {
  final int? index;

  const _IndexLookupResult({this.index});
}

/// Manages the client-side playback queue (playlists, collections, shuffles
/// and sequential shows). This provider is session-only and does not persist across app restarts.
class PlaybackStateProvider with ChangeNotifier, DisposableChangeNotifierMixin {
  // Play queue state
  int? _playQueueId;
  int _playQueueTotalCount = 0;
  bool _playQueueShuffled = false;
  int? _currentPlayQueueItemID;

  // The queue's items, fully resident.
  List<MediaItem> _loadedItems = [];

  /// Synthetic per-item queue IDs, parallel to [_loadedItems] —
  /// `_syntheticIds[i]` is the queue ID for `_loadedItems[i]`.
  List<int> _syntheticIds = const [];

  String? _contextKey; // The show/season/playlist ratingKey for this session
  bool _isQueueMode = false;

  /// Returns the queue id for [item] within the current queue: the
  /// synthetic index assigned in [setPlaybackFromLocalQueue]. Returns null
  /// when [item] isn't in the queue.
  int? playQueueItemIdFor(MediaItem item) {
    if (!_isQueueMode) return null;
    final idx = _loadedItems.indexOf(item);
    if (idx < 0 || idx >= _syntheticIds.length) return null;
    return _syntheticIds[idx];
  }

  bool get isShuffleActive => _playQueueShuffled;

  /// Whether playlist/collection mode is currently active
  bool get isPlaylistActive => _isQueueMode;

  /// Whether any queue-based playback is active
  bool get isQueueActive => _playQueueId != null && _isQueueMode;

  /// Whether [item] belongs to the currently active queue. Membership uses
  /// the exact stored object because duplicate media entries in playlists
  /// must remain distinguishable.
  /// Gates the player's "preserve vs. wipe launcher-set queue" decision in
  /// [VideoPlayerScreen.initState] and [EpisodeNavigationService]'s `_ensureLocalEpisodeQueue`, so a
  /// playlist, collection, or shuffled show queue survives entry into the
  /// player instead of being replaced with a sequential show queue.
  bool isItemInActiveQueue(MediaItem item) => isQueueActive && playQueueItemIdFor(item) != null;

  /// The context key (show/season/playlist ratingKey) for the current session
  String? get shuffleContextKey => _contextKey;

  int? get playQueueId => _playQueueId;

  /// The queue items
  List<MediaItem> get loadedItems => List.unmodifiable(_loadedItems);

  int? get currentPlayQueueItemID => _currentPlayQueueItemID;

  /// The queue item the cursor currently points at, or null when no queue
  /// is active.
  MediaItem? get currentQueueItem => _currentPlayQueueItemID == null ? null : _findLoadedItem(_currentPlayQueueItemID!);

  /// Update the queue cursor after playback of [metadata] starts.
  ///
  /// Items outside the active queue are rejected.
  void setCurrentItem(MediaItem metadata) {
    if (!_isQueueMode) return;
    final id = playQueueItemIdFor(metadata);
    if (id == null || id == _currentPlayQueueItemID) return;
    _currentPlayQueueItemID = id;
    safeNotifyListeners();
  }

  /// Initialize playback from a [LocalPlayQueue]. Synthetic per-item queue
  /// IDs are recorded in [_syntheticIds] (parallel to [_loadedItems]) for
  /// the Queue sheet, content strip and current item highlight. Items
  /// themselves are stored unmutated.
  ///
  /// `playQueueId` is set to a sentinel so [isQueueActive] returns true.
  void setPlaybackFromLocalQueue(LocalPlayQueue queue, {String? contextKey}) {
    _playQueueId = -1; // sentinel for "client-side queue"
    _playQueueTotalCount = queue.items.length;
    _playQueueShuffled = queue.shuffled;
    _loadedItems = List.of(queue.items);
    _syntheticIds = [for (var i = 0; i < queue.items.length; i++) i];
    _currentPlayQueueItemID = queue.currentIndex;
    _contextKey = contextKey;
    _isQueueMode = true;
    safeNotifyListeners();
  }

  _IndexLookupResult _getCurrentIndex(String currentItemKey) {
    if (!_isQueueMode || _loadedItems.isEmpty || _currentPlayQueueItemID == null) {
      return const _IndexLookupResult();
    }

    int findCurrent() {
      final cursorIndex = _findLoadedIndex(_currentPlayQueueItemID!);
      if (cursorIndex != -1 && _matchesItemKey(_loadedItems[cursorIndex], currentItemKey)) {
        return cursorIndex;
      }

      var matchedIndex = -1;
      for (var i = 0; i < _loadedItems.length; i++) {
        if (!_matchesItemKey(_loadedItems[i], currentItemKey)) continue;
        if (matchedIndex != -1) return -1;
        matchedIndex = i;
      }
      return matchedIndex;
    }

    final currentIndex = findCurrent();
    return currentIndex == -1 ? const _IndexLookupResult() : _IndexLookupResult(index: currentIndex);
  }

  bool _matchesItemKey(MediaItem item, String currentItemKey) =>
      item.id == currentItemKey || item.globalKey == currentItemKey;

  /// Returns the index of the item with [playQueueItemId] in [_loadedItems],
  /// or -1 if absent.
  int _findLoadedIndex(int playQueueItemId) {
    for (var i = 0; i < _loadedItems.length && i < _syntheticIds.length; i++) {
      if (_syntheticIds[i] == playQueueItemId) return i;
    }
    return -1;
  }

  MediaItem? _findLoadedItem(int playQueueItemId) {
    final index = _findLoadedIndex(playQueueItemId);
    return index == -1 ? null : _loadedItems[index];
  }

  /// Gets the next item in the playback queue.
  ///
  /// Returns a typed result so a lookup failure cannot be mistaken for the
  /// confirmed end of the queue. Entries backed by the same file as the one
  /// playing are skipped: each episode of a multi-episode file
  /// (`S02E24-E25.mkv`) is its own queue item, and advancing to the sibling
  /// would replay the file from the start (#1500). [playedPartId] pins the
  /// comparison to the file of the part actually playing when known;
  /// otherwise any file overlap with the current item counts.
  Future<QueueNavigationResult> getNextEpisode(String currentItemKey, {String? playedPartId}) async {
    if (!_isQueueMode) return const QueueNavigationResult.unavailable();

    final indexResult = _getCurrentIndex(currentItemKey);
    if (indexResult.index == null) return const QueueNavigationResult.unavailable();

    final current = _loadedItems[indexResult.index!];
    var anchor = current;
    // Bounded so a pathological all-same-file queue cannot spin.
    for (var steps = 0; steps <= _playQueueTotalCount; steps++) {
      final result = _itemAtOffset(anchor, 1);
      final candidate = result.item;
      if (result.status != QueueNavigationStatus.found || candidate == null) {
        return result;
      }
      if (!current.sharesFileWith(candidate, playedPartId: playedPartId)) {
        return result;
      }
      anchor = candidate;
    }
    return const QueueNavigationResult.failed();
  }

  /// Gets the previous item in the playback queue.
  /// Returns null if at the beginning of the queue or current item is not in queue.
  ///
  /// Mirrors [getNextEpisode]'s multi-episode-file handling (#1500): entries
  /// backed by the file that's playing are skipped, and the result is
  /// collapsed to the first episode of its same-file group so a
  /// multi-episode file is entered at the episode that fronts it.
  Future<QueueNavigationResult> getPreviousEpisode(String currentItemKey, {String? playedPartId}) async {
    if (!_isQueueMode) return const QueueNavigationResult.unavailable();

    final indexResult = _getCurrentIndex(currentItemKey);
    if (indexResult.index == null) return const QueueNavigationResult.unavailable();

    final current = _loadedItems[indexResult.index!];
    MediaItem candidate = current;
    for (var steps = 0; steps <= _playQueueTotalCount; steps++) {
      final result = _itemAtOffset(candidate, -1);
      final before = result.item;
      if (result.status != QueueNavigationStatus.found || before == null) {
        return result;
      }
      candidate = before;
      if (!current.sharesFileWith(candidate, playedPartId: playedPartId)) break;
    }

    // Collapse to the first episode of the candidate's same-file group.
    for (var steps = 0; steps <= _playQueueTotalCount; steps++) {
      final result = _itemAtOffset(candidate, -1);
      final before = result.item;
      if (result.status == QueueNavigationStatus.failed) return result;
      if (result.status != QueueNavigationStatus.found || before == null || !candidate.sharesFileWith(before)) {
        return QueueNavigationResult.found(candidate);
      }
      candidate = before;
    }
    return QueueNavigationResult.found(candidate);
  }

  /// The queue item [delta] steps from [anchor]. The queue is fully
  /// resident, so its edge is the queue boundary.
  QueueNavigationResult _itemAtOffset(MediaItem anchor, int delta) {
    final anchorId = playQueueItemIdFor(anchor);
    if (anchorId == null) return const QueueNavigationResult.unavailable();
    final anchorIndex = _findLoadedIndex(anchorId);
    if (anchorIndex == -1) return const QueueNavigationResult.unavailable();
    final target = anchorIndex + delta;
    return target >= 0 && target < _loadedItems.length
        ? QueueNavigationResult.found(_loadedItems[target])
        : const QueueNavigationResult.boundary();
  }

  /// Queue items backed by the same physical file as [current] — the other
  /// episodes of a multi-episode file (#1500), which should share its
  /// watched state.
  /// [current] may be a different object instance than the queue's copy;
  /// exclusion is by item id.
  List<MediaItem> sameFileSiblings(MediaItem current, {String? playedPartId}) {
    if (!_isQueueMode) return const [];
    final seenIds = <String>{current.id};
    return [
      for (final item in _loadedItems)
        if (seenIds.add(item.id) && current.sharesFileWith(item, playedPartId: playedPartId)) item,
    ];
  }

  /// Clears the playback queue and exits queue mode
  void clearShuffle() {
    _playQueueId = null;
    _playQueueTotalCount = 0;
    _playQueueShuffled = false;
    _currentPlayQueueItemID = null;
    _loadedItems = [];
    _syntheticIds = const [];
    _contextKey = null;
    _isQueueMode = false;
    safeNotifyListeners();
  }
}
