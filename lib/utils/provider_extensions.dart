import 'package:flutter/material.dart';
import '../media/ids.dart';
import 'package:provider/provider.dart';
import '../media/media_item.dart';
import '../media/media_library.dart';
import '../media/media_server_client.dart';
import '../i18n/strings.g.dart';
import '../providers/multi_server_provider.dart';

extension ProviderExtensions on BuildContext {
  // These return [MediaServerClient] so callers that consume only the
  // [MediaServerClient] surface don't need to type-check the result.

  MediaServerClient? _resolveMediaClient(ServerId? serverId) {
    final provider = Provider.of<MultiServerProvider>(this, listen: false);
    return _resolvePrioritized(serverId, provider.onlineServerIds, provider.getClientForServer);
  }

  MediaServerClient? tryGetMediaClientForServer(ServerId? serverId) {
    if (serverId == null) return null;
    final provider = Provider.of<MultiServerProvider?>(this, listen: false);
    return provider?.getClientForServer(serverId);
  }

  /// Get a [MediaServerClient] for the given serverId. Throws when the
  /// server isn't registered or is offline.
  MediaServerClient getMediaClientForServer(ServerId serverId) {
    final provider = Provider.of<MultiServerProvider>(this, listen: false);
    final c = provider.getClientForServer(serverId);
    if (c == null) throw Exception(t.errors.noClientAvailable);
    return c;
  }

  MediaServerClient getMediaClientForLibrary(MediaLibrary library) {
    final serverId = serverIdOrNull(library.serverId);
    if (serverId == null) throw Exception(t.errors.noClientAvailable);
    return getMediaClientForServer(serverId);
  }

  /// Get a [MediaServerClient] for a [MediaItem], or null in offline mode /
  /// when the server isn't online.
  MediaServerClient? getMediaClientForItemOrNull(MediaItem item, {bool isOffline = false}) {
    if (isOffline) return null;
    return tryGetMediaClientForServer(serverIdOrNull(item.serverId));
  }

  /// Get a [MediaServerClient] for [serverId], falling back to the first
  /// online server when not found. Throws if no client is available.
  MediaServerClient getMediaClientWithFallback(ServerId? serverId) {
    final c = _resolveMediaClient(serverId);
    if (c == null) throw Exception(t.errors.noClientAvailable);
    return c;
  }

  /// Like [getMediaClientWithFallback] but returns null instead of throwing
  /// when no client is registered. Use this for non-critical surfaces (image
  /// loaders, list cards) that can render a fallback when the client isn't
  /// available — throwing during `build` would crash the widget instead.
  MediaServerClient? tryGetMediaClientWithFallback(ServerId? serverId) {
    final provider = Provider.of<MultiServerProvider?>(this, listen: false);
    if (provider == null) return null;
    return _resolvePrioritized(serverId, provider.onlineServerIds, provider.getClientForServer);
  }
}

/// Try [preferred] first, then fall back through [fallbacks] in order. Returns
/// the first non-null result from [resolve], or `null` if every candidate
/// resolves to null.
T? _resolvePrioritized<T>(String? preferred, Iterable<String> fallbacks, T? Function(ServerId) resolve) {
  if (preferred != null) {
    final c = resolve(ServerId(preferred));
    if (c != null) return c;
  }
  for (final id in fallbacks) {
    final c = resolve(ServerId(id));
    if (c != null) return c;
  }
  return null;
}
