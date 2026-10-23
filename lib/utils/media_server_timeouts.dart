/// Centralized HTTP timeout constants for both backends. The same
/// [MediaServerHttpClient] wrapper is used by the media-server clients —
/// timeouts are kept here so the budgets per phase are visible at a
/// glance.
class MediaServerTimeouts {
  /// Reaching the server: DNS, TCP and TLS. Enforced by the transport, so it
  /// never cuts into the server's think time.
  static const connect = Duration(seconds: 10);

  /// Waiting on a server that was reached for its response headers — the
  /// server's think time. Covers a slow-but-working query (a search
  /// that takes 11–15 s, #2581) while a server that accepted the connection
  /// and never answers still fails well before [receive].
  static const response = Duration(seconds: 30);

  /// Waiting on the response body once the headers arrived.
  static const receive = Duration(seconds: 120);

  /// Per-server deadline for one leg of a global search
  /// (`DataAggregationService.searchAcrossServers`): a server's titles, and
  /// separately its people. Every server's results are shown together, so a
  /// server that accepted the connection and stopped answering would
  /// otherwise hold back all of them for the full [response] budget. Same
  /// budget as [libraryLookup], which searches the same libraries.
  static const searchServerDeadline = Duration(seconds: 20);

  /// Per-server deadline for one server's library list
  /// (`DataAggregationService.getMediaLibrariesFromAllServers`). A server
  /// that misses it counts as failed and is retried on the next pass instead
  /// of holding back the libraries, and the home hubs built from them, of
  /// every other server. Same budget as [homeHubDeadline].
  static const libraryListServerDeadline = Duration(seconds: 15);

  /// How long the startup splash waits for the initial bind when the OS
  /// reports no network. The bind still runs — `none` leaves loopback and
  /// LAN-without-WAN servers reachable (#2505) — but an airplane-mode launch
  /// must not sit through [perServerConnect]. Past the cap the offline shell
  /// opens and the bind keeps going, so a server that connects later still
  /// brings the app online.
  static const noNetworkStartupBind = Duration(seconds: 2);
}
