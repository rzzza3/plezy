import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/silo/silo_artwork.dart';

void main() {
  final origin = Uri.parse('https://silo.ruleone.xyz/api/v2/home/sections');

  group('resolveSiloArtworkUrl mirrors ArtworkUrls.kt:10-17', () {
    test('a single leading slash resolves against the response origin (ArtworkUrls.kt:11-16)', () {
      expect(resolveSiloArtworkUrl('/img/a.jpg', origin), 'https://silo.ruleone.xyz/img/a.jpg');
    });

    test('a protocol-relative value stays unchanged (ArtworkUrls.kt:11)', () {
      expect(resolveSiloArtworkUrl('//cdn/x', origin), '//cdn/x');
    });

    test('absolute and bare values stay unchanged (ArtworkUrls.kt:11)', () {
      expect(resolveSiloArtworkUrl('https://cdn.example/p.jpg', origin), 'https://cdn.example/p.jpg');
      expect(resolveSiloArtworkUrl('img/a.jpg', origin), 'img/a.jpg');
    });

    test('a signed query is kept byte for byte (ArtworkUrls.kt:9)', () {
      expect(
        resolveSiloArtworkUrl('/img/a.jpg?exp=1&sig=a%2Fb+c', origin),
        'https://silo.ruleone.xyz/img/a.jpg?exp=1&sig=a%2Fb+c',
      );
    });

    test('a non-default port is kept and a default port dropped (ArtworkUrls.kt:15)', () {
      expect(resolveSiloArtworkUrl('/p.jpg', Uri.parse('http://10.0.0.2:8090/api')), 'http://10.0.0.2:8090/p.jpg');
      expect(
        resolveSiloArtworkUrl('/p.jpg', Uri.parse('https://silo.ruleone.xyz:443/api')),
        'https://silo.ruleone.xyz/p.jpg',
      );
    });

    test('an IPv6 host is bracketed (ArtworkUrls.kt:14)', () {
      expect(resolveSiloArtworkUrl('/p.jpg', Uri.parse('http://[::1]:8090/api')), 'http://[::1]:8090/p.jpg');
    });
  });

  test('resolveSiloArtworkUrls rewrites only artwork fields, at any depth (ArtworkUrls.kt:22-37)', () {
    final resolved = resolveSiloArtworkUrls({
      'sections': [
        {
          'id': '/not-artwork',
          'items': [
            {
              'poster_url': '/p/1.jpg',
              'backdrop_url': '//cdn/b.jpg',
              'logo_url': '/l.png',
              'poster_path': '/tmdb.jpg',
              'poster_urls': ['/a.jpg', 'https://x/b.jpg', 3],
            },
          ],
        },
      ],
      'avatar_url': '/av.png',
    }, origin);

    expect(resolved, {
      'sections': [
        {
          'id': '/not-artwork',
          'items': [
            {
              'poster_url': 'https://silo.ruleone.xyz/p/1.jpg',
              'backdrop_url': '//cdn/b.jpg',
              'logo_url': 'https://silo.ruleone.xyz/l.png',
              'poster_path': '/tmdb.jpg',
              'poster_urls': ['https://silo.ruleone.xyz/a.jpg', 'https://x/b.jpg', 3],
            },
          ],
        },
      ],
      'avatar_url': 'https://silo.ruleone.xyz/av.png',
    });
  });
}
