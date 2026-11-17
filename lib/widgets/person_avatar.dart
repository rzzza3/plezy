import 'package:flutter/material.dart';

import '../focus/card_focus_scope.dart';
import '../media/ids.dart';
import '../utils/media_image_helper.dart';
import '../utils/provider_extensions.dart';
import 'optimized_media_image.dart';

/// A person's round photo, or their initials on a tinted disc when the server
/// has no photo or it fails to load. Draws the card focus border around the
/// circle, so it can sit inside a focus wrapper that delegates its border.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({super.key, required this.name, required this.size, this.imagePath, this.serverId});

  final String name;
  final double size;

  /// Absolute URL or a server-relative path resolved through [serverId]'s
  /// client.
  final String? imagePath;
  final ServerId? serverId;

  /// Up to two initials: the first letters of the first and last words.
  static String initialsOf(String name) {
    final words = name.trim().split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();
    if (words.isEmpty) return '';
    String first(String word) => String.fromCharCode(word.runes.first).toUpperCase();
    return words.length == 1 ? first(words.single) : '${first(words.first)}${first(words.last)}';
  }

  /// A muted hue picked from the name, so a person keeps one color.
  static Color discColorFor(String name) {
    final hue = (name.hashCode & 0x7fffffff) % 360;
    return HSLColor.fromAHSL(1, hue.toDouble(), 0.32, 0.36).toColor();
  }

  Widget _initials(BuildContext context) => ColoredBox(
    color: discColorFor(name),
    child: Center(
      child: Text(
        initialsOf(name),
        maxLines: 1,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.92),
          fontSize: size * 0.3,
          fontWeight: FontWeight.w600,
          height: 1,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final path = imagePath;
    return CardFocusBorder(
      borderRadius: size / 2,
      child: SizedBox.square(
        dimension: size,
        child: ClipOval(
          child: path == null || path.isEmpty
              ? _initials(context)
              : OptimizedMediaImage(
                  client: serverId == null ? null : context.tryGetMediaClientForServer(serverId),
                  imagePath: path,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  imageType: ImageType.avatar,
                  placeholder: (context, _) => ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest),
                  errorWidget: (context, _, _) => _initials(context),
                ),
        ),
      ),
    );
  }
}
