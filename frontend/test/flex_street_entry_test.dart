import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/utils/flex_street_entry.dart';

void main() {
  group('isFlexStreetEntry', () {
    test('matches exact flexstreet subdomain', () {
      expect(
        isFlexStreetEntry(Uri.parse('https://flexstreet.dhanshanti.com/')),
        isTrue,
      );
      expect(
        isFlexStreetEntry(Uri.parse('https://FlexStreet.DhanShanti.com')),
        isTrue,
      );
    });

    test('matches /flexstreet path on www, apex, and localhost', () {
      expect(
        isFlexStreetEntry(
          Uri.parse('https://www.dhanshanti.com/flexstreet'),
        ),
        isTrue,
      );
      expect(
        isFlexStreetEntry(Uri.parse('https://dhanshanti.com/flexstreet')),
        isTrue,
      );
      expect(
        isFlexStreetEntry(Uri.parse('http://localhost:3000/flexstreet')),
        isTrue,
      );
    });

    test('matches trailing slash and nested paths under /flexstreet', () {
      expect(
        isFlexStreetEntry(
          Uri.parse('https://www.dhanshanti.com/flexstreet/'),
        ),
        isTrue,
      );
      expect(
        isFlexStreetEntry(
          Uri.parse('https://www.dhanshanti.com/flexstreet/join'),
        ),
        isTrue,
      );
    });

    test('matches case-insensitive path', () {
      expect(
        isFlexStreetEntry(
          Uri.parse('https://www.dhanshanti.com/FlexStreet'),
        ),
        isTrue,
      );
    });

    test('matches hash fragment /flexstreet', () {
      expect(
        isFlexStreetEntry(
          Uri.parse('https://www.dhanshanti.com/#/flexstreet'),
        ),
        isTrue,
      );
      expect(
        isFlexStreetEntry(
          Uri.parse('https://www.dhanshanti.com/#flexstreet'),
        ),
        isTrue,
      );
    });

    test('matches invite query on a Flex Street URL', () {
      expect(
        isFlexStreetEntry(
          Uri.parse(
            'https://www.dhanshanti.com/flexstreet?learner_invite=ABC',
          ),
        ),
        isTrue,
      );
      expect(
        isFlexStreetEntry(
          Uri.parse(
            'https://flexstreet.dhanshanti.com/?learner_invite=ABC',
          ),
        ),
        isTrue,
      );
    });

    test('does not match the main site or similar hosts/paths', () {
      expect(
        isFlexStreetEntry(Uri.parse('https://www.dhanshanti.com/')),
        isFalse,
      );
      expect(
        isFlexStreetEntry(Uri.parse('https://dhanshanti.com/')),
        isFalse,
      );
      expect(
        isFlexStreetEntry(
          Uri.parse('https://www.flexstreet.dhanshanti.com/'),
        ),
        isFalse,
      );
      expect(
        isFlexStreetEntry(
          Uri.parse('https://flexstreet.dhanshanti.com.evil.example/'),
        ),
        isFalse,
      );
      expect(
        isFlexStreetEntry(
          Uri.parse('https://www.dhanshanti.com/flexstreets'),
        ),
        isFalse,
      );
      expect(
        isFlexStreetEntry(
          Uri.parse('https://www.dhanshanti.com/app/flexstreet'),
        ),
        isFalse,
      );
      expect(
        isFlexStreetEntry(Uri.parse('http://localhost:3000/')),
        isFalse,
      );
    });
  });
}
