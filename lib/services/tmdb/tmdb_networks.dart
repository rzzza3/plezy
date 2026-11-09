/// Where a network sits in the Edit Library page's grid.
enum TmdbNetworkGroup { streaming, usChannels, ukChannels }

/// A network the Library tab's Networks row can show.
class TmdbNetworkBrand {
  /// TMDB network id: the network's series (`with_networks`) and its logo.
  final int id;
  final String name;

  /// TMDB watch providers carrying the network's films, `|`-separated, read
  /// from [watchRegion]'s lists. Null for channels, which match series only.
  /// Titles show only when they are in the library, so the region never
  /// limits what can be watched.
  final String? watchProviders;
  final String watchRegion;

  /// Apple TV's logo carries the Apple mark, which apps can't display, so its
  /// name is set as text.
  final bool usesWordmark;

  final TmdbNetworkGroup group;

  const TmdbNetworkBrand(
    this.id,
    this.name, {
    this.watchProviders,
    this.watchRegion = 'US',
    this.usesWordmark = false,
    this.group = TmdbNetworkGroup.streaming,
  });
}

/// The networks the Library tab's Networks row can show, grouped by
/// [TmdbNetworkGroup] in that order, after Silo's
/// `NetworksRepository.catalogue`.
///
/// TMDB has no endpoint listing networks (only `/3/network/{id}`, and there
/// are thousands), so the choice is this fixed list of major streamers and
/// channels. Names here label the settings list and stand in until
/// [TmdbClient.network] brings TMDB's own name and logo.
class TmdbNetworks {
  TmdbNetworks._();

  static const List<TmdbNetworkBrand> all = [
    TmdbNetworkBrand(213, 'Netflix', watchProviders: '8'),
    TmdbNetworkBrand(1024, 'Prime Video', watchProviders: '9'),
    TmdbNetworkBrand(49, 'HBO', watchProviders: '1899'),
    TmdbNetworkBrand(4330, 'Paramount+', watchProviders: '2303|2616'),
    TmdbNetworkBrand(3186, 'HBO Max', watchProviders: '1899'),
    TmdbNetworkBrand(2739, 'Disney+', watchProviders: '337'),
    TmdbNetworkBrand(2552, 'Apple TV', watchProviders: '350', usesWordmark: true),
    TmdbNetworkBrand(453, 'Hulu', watchProviders: '15'),
    TmdbNetworkBrand(3353, 'Peacock', watchProviders: '386|387'),
    TmdbNetworkBrand(4661, 'AMC+', watchProviders: '526'),
    TmdbNetworkBrand(4353, 'discovery+', watchProviders: '524', watchRegion: 'GB'),
    TmdbNetworkBrand(1112, 'Crunchyroll', watchProviders: '283'),
    TmdbNetworkBrand(2697, 'Acorn TV', watchProviders: '87'),
    TmdbNetworkBrand(318, 'STARZ', watchProviders: '43'),
    TmdbNetworkBrand(67, 'Showtime', group: TmdbNetworkGroup.usChannels),
    TmdbNetworkBrand(2, 'ABC', group: TmdbNetworkGroup.usChannels),
    TmdbNetworkBrand(6, 'NBC', group: TmdbNetworkGroup.usChannels),
    TmdbNetworkBrand(16, 'CBS', group: TmdbNetworkGroup.usChannels),
    TmdbNetworkBrand(19, 'FOX', group: TmdbNetworkGroup.usChannels),
    TmdbNetworkBrand(71, 'The CW', group: TmdbNetworkGroup.usChannels),
    TmdbNetworkBrand(174, 'AMC', group: TmdbNetworkGroup.usChannels),
    TmdbNetworkBrand(88, 'FX', group: TmdbNetworkGroup.usChannels),
    TmdbNetworkBrand(41, 'TNT', group: TmdbNetworkGroup.usChannels),
    TmdbNetworkBrand(30, 'USA Network', group: TmdbNetworkGroup.usChannels),
    TmdbNetworkBrand(77, 'Syfy', group: TmdbNetworkGroup.usChannels),
    TmdbNetworkBrand(47, 'Comedy Central', group: TmdbNetworkGroup.usChannels),
    TmdbNetworkBrand(80, 'Adult Swim', group: TmdbNetworkGroup.usChannels),
    TmdbNetworkBrand(56, 'Cartoon Network', group: TmdbNetworkGroup.usChannels),
    TmdbNetworkBrand(13, 'Nickelodeon', group: TmdbNetworkGroup.usChannels),
    TmdbNetworkBrand(54, 'Disney Channel', group: TmdbNetworkGroup.usChannels),
    TmdbNetworkBrand(33, 'MTV', group: TmdbNetworkGroup.usChannels),
    TmdbNetworkBrand(64, 'Discovery', group: TmdbNetworkGroup.usChannels),
    TmdbNetworkBrand(43, 'National Geographic', group: TmdbNetworkGroup.usChannels),
    TmdbNetworkBrand(65, 'History', group: TmdbNetworkGroup.usChannels),
    TmdbNetworkBrand(4, 'BBC One', group: TmdbNetworkGroup.ukChannels),
    TmdbNetworkBrand(332, 'BBC Two', group: TmdbNetworkGroup.ukChannels),
    TmdbNetworkBrand(3, 'BBC Three', group: TmdbNetworkGroup.ukChannels),
    TmdbNetworkBrand(9, 'ITV1', group: TmdbNetworkGroup.ukChannels),
    TmdbNetworkBrand(26, 'Channel 4', group: TmdbNetworkGroup.ukChannels),
    TmdbNetworkBrand(1063, 'Sky Atlantic', group: TmdbNetworkGroup.ukChannels),
  ];

  /// Shown until the user picks their own: Netflix, Prime Video, HBO,
  /// Paramount+.
  static const List<String> defaultIds = ['213', '1024', '49', '4330'];
}
