import 'dart:io';

import 'package:finance_tracker/utils/auth_landing_style.dart';
import 'package:flutter_test/flutter_test.dart';

String _htmlEscape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

void _expectPhrase(String html, String phrase, {required String file}) {
  expect(
    html.contains(phrase) || html.contains(_htmlEscape(phrase)),
    isTrue,
    reason: '$file is missing landing copy: $phrase',
  );
}

void _expectHead(
  String html, {
  required String file,
  required String canonical,
  required String title,
  required String description,
  required String ogImage,
}) {
  expect(html, contains('<html lang="en">'), reason: file);
  expect(html, contains('<title>$title</title>'), reason: file);
  expect(html, contains('name="description" content="$description"'),
      reason: file);
  expect(html, contains('name="robots" content="index,follow"'), reason: file);
  expect(html, contains('rel="canonical" href="$canonical"'), reason: file);
  expect(html, contains('property="og:type" content="website"'), reason: file);
  expect(html, contains('property="og:url" content="$canonical"'), reason: file);
  expect(html, contains('property="og:title" content="$title"'), reason: file);
  expect(
    html,
    contains('property="og:description" content="$description"'),
    reason: file,
  );
  expect(html, contains('property="og:image" content="$ogImage"'), reason: file);
  expect(
    html,
    contains('name="twitter:card" content="summary_large_image"'),
    reason: file,
  );
  expect(html, contains('"@type": "WebApplication"'), reason: file);
  expect(html, contains('"isAccessibleForFree": true'), reason: file);
  expect(html, contains('id="seo-landing"'), reason: file);
  expect(html, contains('<noscript>'), reason: file);
  expect(html, contains('flutter-first-frame'), reason: file);
  expect(html, contains("classList.add('flutter-ready')"), reason: file);
  expect(html, isNot(contains("getElementById('seo-landing')")), reason: file);
  expect(html, contains('src="flutter_bootstrap.js"'), reason: file);
}

void _expectLandingCopy(
  String html,
  AuthLandingStyle style, {
  required String file,
}) {
  _expectPhrase(html, style.heroTitle, file: file);
  _expectPhrase(html, style.heroTagline, file: file);
  final byline = style.heroByline;
  if (byline != null) {
    _expectPhrase(html, byline, file: file);
  }
  for (final line in style.heroLines) {
    _expectPhrase(html, line, file: file);
  }
  _expectPhrase(html, style.featuresTitle, file: file);
  _expectPhrase(html, style.featuresSubtitle, file: file);
  for (final feature in style.features) {
    _expectPhrase(html, feature.$2, file: file);
    _expectPhrase(html, feature.$3, file: file);
  }
  _expectPhrase(html, style.midTitle, file: file);
  _expectPhrase(html, style.midSubtitle, file: file);
  for (final card in style.midCards) {
    _expectPhrase(html, card.$2, file: file);
    _expectPhrase(html, card.$3, file: file);
    _expectPhrase(html, card.$4, file: file);
  }
  _expectPhrase(html, style.howTitle, file: file);
  _expectPhrase(html, style.howSubtitle, file: file);
  for (final step in style.howSteps) {
    _expectPhrase(html, step.$2, file: file);
    _expectPhrase(html, step.$3, file: file);
  }
  _expectPhrase(html, style.privacyTitle, file: file);
  _expectPhrase(html, style.privacyBody, file: file);
  _expectPhrase(html, style.privacyExtra, file: file);
  _expectPhrase(html, style.privacyCta, file: file);
}

void main() {
  late String dhanHtml;
  late String flexHtml;
  late String robots;
  late String sitemap;

  setUpAll(() {
    dhanHtml = File('web/index.html').readAsStringSync();
    flexHtml = File('web/flexstreet/index.html').readAsStringSync();
    robots = File('web/robots.txt').readAsStringSync();
    sitemap = File('web/sitemap.xml').readAsStringSync();
  });

  test('Dhan Shanti index.html is a crawlable landing document', () {
    _expectHead(
      dhanHtml,
      file: 'web/index.html',
      canonical: 'https://www.dhanshanti.com/',
      title: 'Dhan Shanti — Rules on. Noise off.',
      description:
          'Dhan Shanti. Rules on. Noise off. Live portfolio, Flex Street challenge, Horizon plan.',
      ogImage: 'https://www.dhanshanti.com/og-dhan-shanti.png',
    );
    expect(dhanHtml, contains('"@type": "Organization"'));
    expect(dhanHtml, contains('href="/flexstreet"'));
    expect(dhanHtml, contains('name="theme-color" content="#0F5C56"'));
    _expectLandingCopy(
      dhanHtml,
      AuthLandingStyle.dhanShantiStyle,
      file: 'web/index.html',
    );
    expect(File('web/og-dhan-shanti.png').existsSync(), isTrue);
  });

  test('FlexStreet index.html is a distinct crawlable landing document', () {
    _expectHead(
      flexHtml,
      file: 'web/flexstreet/index.html',
      canonical: 'https://www.dhanshanti.com/flexstreet',
      title: 'FlexStreet — An investment challenge',
      description:
          'FlexStreet by DhanShanti. An investment challenge. Virtual money, real stocks. Same starting cash. Leaderboard decides the Alpha.',
      ogImage: 'https://www.dhanshanti.com/og-flex-street.png',
    );
    expect(flexHtml, contains('<base href="/">'));
    expect(flexHtml, contains('flexstreet.dhanshanti.com'));
    expect(flexHtml, contains('name="theme-color" content="#170B48"'));
    _expectLandingCopy(
      flexHtml,
      AuthLandingStyle.flexStreetStyle,
      file: 'web/flexstreet/index.html',
    );
    expect(File('web/og-flex-street.png').existsSync(), isTrue);
  });

  test('robots.txt and sitemap.xml advertise both brand URLs', () {
    expect(robots, contains('Allow: /'));
    expect(robots, contains('Disallow: /api/'));
    expect(robots, contains('Sitemap: https://www.dhanshanti.com/sitemap.xml'));
    expect(sitemap, contains('https://www.dhanshanti.com/</loc>'));
    expect(sitemap, contains('https://www.dhanshanti.com/flexstreet</loc>'));
    expect(sitemap, contains('https://flexstreet.dhanshanti.com/</loc>'));
  });
}
