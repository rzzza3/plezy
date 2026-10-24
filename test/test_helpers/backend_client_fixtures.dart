import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/models/plex/plex_config.dart';
import 'package:plezy/services/plex_client.dart';
import 'package:plezy/utils/active_client_scope.dart';

PlexConfig testPlexConfig({
  String baseUrl = 'https://plex.example.com',
  String? token = 'token',
  String clientIdentifier = 'test-client',
  String product = 'Plezy Test',
  String version = '1.0.0',
  String platform = 'Flutter Test',
  String? device,
  String? deviceName,
  String? machineIdentifier,
  String? languageCode,
}) {
  return PlexConfig(
    baseUrl: baseUrl,
    token: token,
    clientIdentifier: clientIdentifier,
    product: product,
    version: version,
    platform: platform,
    device: device,
    deviceName: deviceName,
    machineIdentifier: machineIdentifier,
    languageCode: languageCode,
  );
}

PlexClient testPlexClient({
  PlexConfig? config,
  String baseUrl = 'https://plex.example.com',
  String? token = 'token',
  ServerId? serverId,
  PlexProfileScopeId? profileScopeId,
  String? serverName = 'Server',
  http.Client? httpClient,
  Future<http.Response> Function(http.Request request)? handler,
  List<String>? prioritizedEndpoints,
  http.Client Function()? endpointProbeHttpClientFactory,
  void Function()? onAllEndpointsExhausted,
  List<PlexEpgProvider> epgProviders = const [],
  String? homeHubKey,
  String? promotedHubKey,
  String? continueWatchingHubKey,
}) {
  assert(httpClient == null || handler == null, 'Provide either httpClient or handler, not both');
  final resolvedServerId = serverId ?? ServerId('server-1');
  return PlexClient.forTesting(
    config: config ?? testPlexConfig(baseUrl: baseUrl, token: token),
    serverId: resolvedServerId,
    profileScopeId: profileScopeId ?? buildPlexProfileScopeId(serverId: resolvedServerId, profileId: 'test-profile'),
    serverName: serverName,
    httpClient: httpClient ?? MockClient(handler ?? _defaultResponse),
    prioritizedEndpoints: prioritizedEndpoints,
    endpointProbeHttpClientFactory: endpointProbeHttpClientFactory,
    onAllEndpointsExhausted: onAllEndpointsExhausted,
    epgProviders: epgProviders,
    homeHubKey: homeHubKey,
    promotedHubKey: promotedHubKey,
    continueWatchingHubKey: continueWatchingHubKey,
  );
}

Future<http.Response> _defaultResponse(http.Request request) async {
  return http.Response('{}', 200, headers: const {'content-type': 'application/json'});
}
