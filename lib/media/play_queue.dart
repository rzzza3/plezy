import 'media_item.dart';

/// Client-only play queue. Every queue is built client-side; there is no
/// server queue model.
class LocalPlayQueue {
  final List<MediaItem> items;
  final int? currentIndex;
  final bool shuffled;

  const LocalPlayQueue({required this.items, this.currentIndex, this.shuffled = false});
}
