import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_part.dart';
import 'package:plezy/media/media_version.dart';
import 'package:plezy/media/play_queue.dart';
import 'package:plezy/providers/playback_state_provider.dart';
import '../test_helpers/media_items.dart';

MediaItem _item(String id) =>
    testMediaItem(id: id, backend: MediaBackend.silo, kind: MediaKind.episode, title: 'Episode $id');

/// Episode queue entry carrying file identity. Episodes of a multi-episode
/// file (`S02E24-E25.mkv`) get *distinct* part ids (`part-<id>` here,
/// mirroring real servers) but share [file].
MediaItem _itemWithFile(String id, String file) => testMediaItem(
  id: id,
  backend: MediaBackend.silo,
  kind: MediaKind.episode,
  title: 'Episode $id',
  mediaVersions: [
    MediaVersion(
      id: 'v-$id',
      parts: [MediaPart(id: 'part-$id', file: file)],
    ),
  ],
);

PlaybackStateProvider _providerWith(List<MediaItem> items, {int? currentIndex, String? contextKey}) {
  final p = PlaybackStateProvider();
  p.setPlaybackFromLocalQueue(
    LocalPlayQueue(items: items, currentIndex: currentIndex),
    contextKey: contextKey,
  );
  return p;
}

void main() {
  group('PlaybackStateProvider', () {
    test('starts in idle state with no queue', () {
      final p = PlaybackStateProvider();
      expect(p.isQueueActive, isFalse);
      expect(p.isPlaylistActive, isFalse);
      expect(p.isShuffleActive, isFalse);
      expect(p.playQueueId, isNull);
      expect(p.currentPlayQueueItemID, isNull);
      expect(p.shuffleContextKey, isNull);
      expect(p.loadedItems, isEmpty);
      p.dispose();
    });

    test('setPlaybackFromLocalQueue populates state and notifies', () {
      final p = PlaybackStateProvider();
      addTearDown(p.dispose);
      var notified = 0;
      p.addListener(() => notified++);

      final items = [_item('100'), _item('101'), _item('102')];
      p.setPlaybackFromLocalQueue(
        LocalPlayQueue(items: items, currentIndex: 1, shuffled: true),
        contextKey: 'show-key',
      );

      expect(p.playQueueId, isNotNull);
      expect(p.currentPlayQueueItemID, 1);
      expect(p.currentQueueItem, same(items[1]));
      expect(p.isShuffleActive, isTrue);
      expect(p.isPlaylistActive, isTrue);
      expect(p.isQueueActive, isTrue);
      expect(p.shuffleContextKey, 'show-key');
      expect(p.loadedItems, items);
      expect(notified, 1);
    });

    test('clearShuffle resets all state and notifies', () {
      final p = _providerWith([_item('a'), _item('b')], currentIndex: 0, contextKey: 'context-1');
      addTearDown(p.dispose);
      expect(p.isQueueActive, isTrue);

      var notified = 0;
      p.addListener(() => notified++);

      p.clearShuffle();
      expect(p.isQueueActive, isFalse);
      expect(p.isPlaylistActive, isFalse);
      expect(p.isShuffleActive, isFalse);
      expect(p.playQueueId, isNull);
      expect(p.currentPlayQueueItemID, isNull);
      expect(p.shuffleContextKey, isNull);
      expect(p.loadedItems, isEmpty);
      expect(notified, 1);
    });

    test('setCurrentItem updates the cursor only for queue members', () {
      final p = PlaybackStateProvider();
      addTearDown(p.dispose);
      final a = _item('a');
      final b = _item('b');

      var notified = 0;
      p.addListener(() => notified++);
      p.setCurrentItem(a);
      expect(p.currentPlayQueueItemID, isNull);
      expect(notified, 0);

      p.setPlaybackFromLocalQueue(LocalPlayQueue(items: [a, b], currentIndex: 0));
      final preNotify = notified;

      // A loaded member is accepted.
      p.setCurrentItem(b);
      expect(p.currentPlayQueueItemID, 1);
      expect(p.currentQueueItem, same(b));
      expect(notified, preNotify + 1);

      // An item outside this queue cannot poison the cursor.
      p.setCurrentItem(_item('outsider'));
      expect(p.currentPlayQueueItemID, 1);
      expect(notified, preNotify + 1);
    });

    test('getNextEpisode returns the next item when current is mid-queue', () async {
      final items = [_item('a'), _item('b'), _item('c')];
      final p = _providerWith(items, currentIndex: 1);
      addTearDown(p.dispose);

      final next = await p.getNextEpisode('b');
      expect(next.status, QueueNavigationStatus.found);
      expect(next.item, same(items[2]));
      expect(p.playQueueItemIdFor(next.item!), 2);

      // currentPlayQueueItemID is NOT updated by getNextEpisode (setCurrentItem does that).
      expect(p.currentPlayQueueItemID, 1);
    });

    test('getNextEpisode reports the queue boundary at the end', () async {
      final p = _providerWith([_item('a'), _item('b')], currentIndex: 1);
      addTearDown(p.dispose);

      final next = await p.getNextEpisode('b');
      expect(next.status, QueueNavigationStatus.boundary);
      expect(next.item, isNull);
    });

    test('getNextEpisode anchors on the supplied media key instead of a stale cursor', () async {
      final p = _providerWith([_item('a'), _item('b'), _item('c')], currentIndex: 0);
      addTearDown(p.dispose);

      final next = await p.getNextEpisode('b');

      expect(next.status, QueueNavigationStatus.found);
      expect(next.item!.id, 'c');
      expect(p.currentPlayQueueItemID, 0, reason: 'read-only lookup must not move the playback cursor');
    });

    test('getNextEpisode reports unavailable with no active queue', () async {
      final p = PlaybackStateProvider();
      final next = await p.getNextEpisode('any-key');
      expect(next.status, QueueNavigationStatus.unavailable);
      expect(next.item, isNull);
      p.dispose();
    });

    test('getNextEpisode reports unavailable for an item outside the queue', () async {
      final p = _providerWith([_item('a'), _item('b')], currentIndex: 0);
      addTearDown(p.dispose);

      final next = await p.getNextEpisode('outsider');
      expect(next.status, QueueNavigationStatus.unavailable);
      expect(next.item, isNull);
    });

    test('getNextEpisode walks a shuffled queue in its stored order', () async {
      final items = [_item('c'), _item('a'), _item('b')];
      final p = PlaybackStateProvider();
      addTearDown(p.dispose);
      p.setPlaybackFromLocalQueue(LocalPlayQueue(items: items, currentIndex: 0, shuffled: true));

      expect((await p.getNextEpisode('c')).item!.id, 'a');
      expect((await p.getNextEpisode('a')).item!.id, 'b');
      expect((await p.getNextEpisode('b')).status, QueueNavigationStatus.boundary);
      expect((await p.getPreviousEpisode('a')).item!.id, 'c');
    });

    test('getPreviousEpisode returns the previous item when current is mid-queue', () async {
      final items = [_item('a'), _item('b'), _item('c')];
      final p = _providerWith(items, currentIndex: 1);
      addTearDown(p.dispose);

      final previous = await p.getPreviousEpisode('b');
      expect(previous.status, QueueNavigationStatus.found);
      expect(previous.item, same(items[0]));
      expect(p.playQueueItemIdFor(previous.item!), 0);
    });

    test('getPreviousEpisode at index 0 reports the boundary', () async {
      final p = _providerWith([_item('a'), _item('b')], currentIndex: 0);
      addTearDown(p.dispose);

      final previous = await p.getPreviousEpisode('a');
      expect(previous.status, QueueNavigationStatus.boundary);
      expect(previous.item, isNull);
    });

    test('getPreviousEpisode without queue mode reports unavailable', () async {
      final p = PlaybackStateProvider();
      final previous = await p.getPreviousEpisode('any-key');
      expect(previous.status, QueueNavigationStatus.unavailable);
      expect(previous.item, isNull);
      p.dispose();
    });

    test('loadedItems getter is unmodifiable', () {
      final p = _providerWith([_item('a')], currentIndex: 0);
      addTearDown(p.dispose);
      expect(() => p.loadedItems.add(_item('mutated')), throwsUnsupportedError);
    });

    test('safeNotifyListeners after dispose is a no-op', () {
      final p = PlaybackStateProvider();
      p.dispose();
      // clearShuffle and setPlaybackFromLocalQueue both notify; must not throw.
      p.clearShuffle();
      p.setPlaybackFromLocalQueue(LocalPlayQueue(items: [_item('a')], currentIndex: 0));
    });

    test('playQueueItemIdFor returns synthetic ids for Silo local queue items', () {
      // Anchor: VideoPlayerScreen.initState and `_ensurePlayQueue` both gate
      // on `isItemInActiveQueue(meta)` (which delegates to `playQueueItemIdFor`)
      // so a Silo playlist queue survives entry into the player. If this
      // returns null for queue members, the player wipes the launcher-set
      // queue and prev/next walks the show instead of the playlist.
      final p = PlaybackStateProvider();
      addTearDown(p.dispose);

      final ep1 = testMediaItem(id: 'ep1', backend: MediaBackend.silo, kind: MediaKind.episode);
      final ep2 = testMediaItem(id: 'ep2', backend: MediaBackend.silo, kind: MediaKind.episode);
      final outsider = testMediaItem(id: 'ep-other', backend: MediaBackend.silo, kind: MediaKind.episode);

      p.setPlaybackFromLocalQueue(LocalPlayQueue(items: [ep1, ep2], currentIndex: 0), contextKey: 'playlist-X');

      expect(p.playQueueItemIdFor(ep1), 0);
      expect(p.playQueueItemIdFor(ep2), 1);
      expect(p.playQueueItemIdFor(outsider), isNull);
      expect(p.isItemInActiveQueue(ep1), isTrue);
      expect(p.isItemInActiveQueue(outsider), isFalse);
    });

    test('isItemInActiveQueue keeps playlist/collection queues alive', () {
      // `_ensurePlayQueue` gates its "preserve vs. clobber" decision on
      // `isItemInActiveQueue`. A playlist queue's contextKey is the playlist
      // id (not the show), so a context-key-only check would wipe it.
      // Queue membership is the right signal — see gh #978.
      final inQueue = _item('ep-in-playlist');
      // A non-queue item (e.g. tapped from media detail).
      final outsider = _item('ep-different-show');
      final p = _providerWith(
        [inQueue, _item('ep-other-in-playlist')],
        currentIndex: 0,
        // contextKey is the playlist id, deliberately != grandparentId of any item
        contextKey: 'playlist-Z',
      );
      addTearDown(p.dispose);

      expect(p.isItemInActiveQueue(inQueue), isTrue);
      expect(p.isItemInActiveQueue(outsider), isFalse);
    });

    test('isItemInActiveQueue is false when no queue is active', () {
      final p = PlaybackStateProvider();
      addTearDown(p.dispose);

      final ep = _item('ep1');
      expect(p.isQueueActive, isFalse);
      expect(p.isItemInActiveQueue(ep), isFalse);
    });
  });

  group('multi-episode files (#1500)', () {
    // Each episode of a multi-episode file (S02E24-E25.mkv) is its own queue
    // entry with a distinct id AND a distinct part id, but the same
    // Part.file. e24/e25 share a file; e23 and e26 don't.
    const fileA = '/tv/S02E24-E25.mkv';
    PlaybackStateProvider queueWithMultiEpisodeFile({int currentIndex = 1}) => _providerWith([
      _itemWithFile('e23', '/tv/S02E23.mkv'),
      _itemWithFile('e24', fileA),
      _itemWithFile('e25', fileA),
      _itemWithFile('e26', '/tv/S02E26-E27.mkv'),
    ], currentIndex: currentIndex);

    test('getNextEpisode skips the same-file sibling using playedPartId', () async {
      final p = queueWithMultiEpisodeFile();
      addTearDown(p.dispose);

      final next = await p.getNextEpisode('e24', playedPartId: 'part-e24');
      expect(next.status, QueueNavigationStatus.found);
      expect(next.item!.id, 'e26');
    });

    test('getNextEpisode skips the same-file sibling via file intersection without playedPartId', () async {
      final p = queueWithMultiEpisodeFile();
      addTearDown(p.dispose);

      final next = await p.getNextEpisode('e24');
      expect(next.status, QueueNavigationStatus.found);
      expect(next.item!.id, 'e26');
    });

    test('getNextEpisode skips multiple siblings of a triple-episode file', () async {
      final p = _providerWith([
        _itemWithFile('e1', fileA),
        _itemWithFile('e2', fileA),
        _itemWithFile('e3', fileA),
        _itemWithFile('e4', '/tv/S02E26-E27.mkv'),
      ], currentIndex: 0);
      addTearDown(p.dispose);

      final next = await p.getNextEpisode('e1', playedPartId: 'part-e1');
      expect(next.status, QueueNavigationStatus.found);
      expect(next.item!.id, 'e4');
    });

    test('getNextEpisode reports the boundary when only same-file siblings remain', () async {
      final p = _providerWith([_itemWithFile('e24', fileA), _itemWithFile('e25', fileA)], currentIndex: 0);
      addTearDown(p.dispose);

      expect((await p.getNextEpisode('e24', playedPartId: 'part-e24')).status, QueueNavigationStatus.boundary);
    });

    test('items without file data keep positional behavior even with playedPartId', () async {
      final p = _providerWith([_item('a'), _item('b')], currentIndex: 0);
      addTearDown(p.dispose);

      final next = await p.getNextEpisode('a', playedPartId: 'part-a');
      expect(next.status, QueueNavigationStatus.found);
      expect(next.item!.id, 'b');
    });

    test('getPreviousEpisode collapses to the first episode of the same-file group', () async {
      final p = queueWithMultiEpisodeFile(currentIndex: 3);
      addTearDown(p.dispose);

      // From e26, previous is the e24-e25 file, entered at e24 (not e25).
      final previous = await p.getPreviousEpisode('e26', playedPartId: 'part-e26');
      expect(previous.status, QueueNavigationStatus.found);
      expect(previous.item!.id, 'e24');
    });

    test('getPreviousEpisode skips same-file siblings of the playing item', () async {
      final p = queueWithMultiEpisodeFile(currentIndex: 2);
      addTearDown(p.dispose);

      // Playing the file as e25: previous must not land inside the same file.
      final previous = await p.getPreviousEpisode('e25', playedPartId: 'part-e25');
      expect(previous.status, QueueNavigationStatus.found);
      expect(previous.item!.id, 'e23');
    });

    test('sameFileSiblings returns the other episodes of the playing file', () {
      final p = queueWithMultiEpisodeFile();
      addTearDown(p.dispose);

      final current = p.loadedItems[1]; // e24
      final siblings = p.sameFileSiblings(current, playedPartId: 'part-e24');
      expect(siblings.map((s) => s.id), ['e25']);

      // Distinct-file episode has no siblings.
      expect(p.sameFileSiblings(p.loadedItems.first, playedPartId: 'part-e23'), isEmpty);
    });

    test('sameFileSiblings is empty without an active queue', () {
      final p = PlaybackStateProvider();
      addTearDown(p.dispose);
      expect(p.sameFileSiblings(_itemWithFile('e24', fileA), playedPartId: 'part-e24'), isEmpty);
    });
  });
}
