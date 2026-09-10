/// Detects Flex Street entry URLs: `flexstreet.dhanshanti.com` or `*/flexstreet`.
bool isFlexStreetEntry([Uri? uri]) {
  final u = uri ?? Uri.base;
  if (u.host.toLowerCase() == 'flexstreet.dhanshanti.com') {
    return true;
  }
  if (_pathIsFlexStreet(u.path)) {
    return true;
  }
  final fragment = u.fragment.trim();
  if (fragment.isEmpty) {
    return false;
  }
  final normalized = fragment.startsWith('/') ? fragment : '/$fragment';
  return _pathIsFlexStreet(Uri.parse(normalized).path);
}

bool _pathIsFlexStreet(String path) {
  final segments =
      path.split('/').where((segment) => segment.isNotEmpty).toList();
  if (segments.isEmpty) {
    return false;
  }
  return segments.first.toLowerCase() == 'flexstreet';
}
