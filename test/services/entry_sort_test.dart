import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hisn/data/models/vault_entry.dart';
import 'package:hisn/services/entry_sort.dart';

VaultEntry entry(
  String id, {
  String title = '',
  String url = '',
  bool favorite = false,
  DateTime? created,
  DateTime? updated,
}) => VaultEntry(
  id: id,
  title: title,
  url: url,
  favorite: favorite,
  createdAt: created ?? DateTime.utc(2020),
  updatedAt: updated ?? DateTime.utc(2020),
);

List<String> ids(List<VaultEntry> l) => [for (final e in l) e.id];

List<String> byTitle(List<VaultEntry> l) => [for (final e in l) e.title];

DateTime day(int d) => DateTime.utc(2024, 1, d);

void main() {
  test('the saved names are a contract', () {
    expect(EntrySort.values.map((v) => v.name), ['recent', 'title', 'added']);
  });

  group('title', () {
    List<VaultEntry> sorted(List<VaultEntry> l) =>
        sortEntries(l, EntrySort.title, const {});

    test('A to Z, ignoring case', () {
      final out = sorted([
        entry('1', title: 'banana'),
        entry('2', title: 'Cherry'),
        entry('3', title: 'apple'),
        entry('4', title: 'Date'),
      ]);
      expect(byTitle(out), ['apple', 'banana', 'Cherry', 'Date']);
    });

    test('same name in different case: title, then id, decide', () {
      final out = sorted([
        entry('z', title: 'apple'),
        entry('b', title: 'Apple'),
        entry('a', title: 'apple'),
      ]);
      // "Apple" < "apple" as raw text; the two "apple"s fall back to the id.
      expect(ids(out), ['b', 'a', 'z']);
    });

    test('accents do not push a name to the end', () {
      final out = sorted([
        entry('1', title: 'Zoo'),
        entry('2', title: 'Écoute'),
        entry('3', title: 'ecole'),
        entry('4', title: 'Dog'),
      ]);
      expect(byTitle(out), ['Dog', 'ecole', 'Écoute', 'Zoo']);
    });

    test(
      'an entry with no title is placed by its site, the way it is shown',
      () {
        final out = sorted([
          entry('1', title: 'Mail'),
          entry('2', url: 'https://alpha.example.test/login'),
          entry('3', title: '   ', url: 'zeta.example.test'),
        ]);
        expect(ids(out), ['2', '1', '3']);
      },
    );

    test('entries with no name at all come last, in id order', () {
      final out = sorted([
        entry('9'),
        entry('1', title: 'Zed'),
        entry('3'),
        entry('2', title: 'Alpha'),
      ]);
      expect(ids(out), ['2', '1', '3', '9']);
    });

    test(
      'Arabic: marks, tatweel and alef forms do not matter; Latin first',
      () {
        final titles = [
          'يوسف',
          'باب',
          'أحمد',
          'اَحْمَد',
          'احمد',
          'تمر',
          'Zed',
          'alpha',
          '١٠ بنك',
          '2 shop',
          'بـيت',
        ];
        final out = sorted([
          for (var i = 0; i < titles.length; i++) entry('$i', title: titles[i]),
        ]);
        expect(byTitle(out), [
          '١٠ بنك', // 10 ...
          '2 shop',
          'alpha',
          'Zed',
          // Three spellings of one name tie, then the raw text decides.
          'أحمد',
          'احمد',
          'اَحْمَد',
          'باب',
          'بـيت',
          'تمر',
          'يوسف',
        ]);
      },
    );

    test('Arabic letters keep their alphabet order', () {
      const alphabet = 'ابتثجحخدذرزسشصضطظعغفقكلمنهوي';
      final shuffled = alphabet.split('')..shuffle(Random(7));
      final out = sorted([
        for (var i = 0; i < shuffled.length; i++)
          entry('$i', title: shuffled[i]),
      ]);
      expect(byTitle(out).join(), alphabet);
    });

    test(
      'Persian yeh and kaf sort with the Arabic ones, teh marbuta with heh',
      () {
        final out = sorted([
          entry('1', title: 'مدرسه'),
          entry('2', title: 'مدرسة'),
          entry('3', title: 'کتاب'),
          entry('4', title: 'كتاب'),
          entry('5', title: 'مدرسَ'),
        ]);
        // كتاب / کتاب tie (raw text decides), then مدرس, مدرسة / مدرسه.
        expect(byTitle(out), ['كتاب', 'کتاب', 'مدرسَ', 'مدرسة', 'مدرسه']);
      },
    );

    test('full-width and ligature forms fold to plain letters', () {
      final out = sorted([
        entry('1', title: 'ｂeta'),
        entry('2', title: 'ﬁsh'),
        entry('3', title: 'alpha'),
      ]);
      expect(ids(out), ['3', '1', '2']);
    });
  });

  group('recent', () {
    List<VaultEntry> sorted(List<VaultEntry> l, Map<String, DateTime> used) =>
        sortEntries(l, EntrySort.recent, used);

    test('last used first', () {
      final out = sorted(
        [
          entry('a', title: 'A'),
          entry('b', title: 'B'),
          entry('c', title: 'C'),
        ],
        {'a': day(3), 'b': day(9), 'c': day(5)},
      );
      expect(ids(out), ['b', 'c', 'a']);
    });

    test(
      'an entry never used counts from its updatedAt, on the same timeline',
      () {
        final out = sorted(
          [
            entry('used-1h', updated: day(1)),
            entry('new-30m', updated: day(8)),
            entry('used-2h', updated: day(1)),
            entry('old-3h', updated: day(4)),
          ],
          {'used-1h': day(7), 'used-2h': day(6)},
        );
        expect(ids(out), ['new-30m', 'used-1h', 'used-2h', 'old-3h']);
      },
    );

    test('without any usage it is newest edit first', () {
      final out = sorted([
        entry('a', updated: day(1)),
        entry('b', updated: day(3)),
        entry('c', updated: day(2)),
      ], const {});
      expect(ids(out), ['b', 'c', 'a']);
    });

    test('ties: title, then id', () {
      final out = sorted(
        [
          entry('3', title: 'Beta'),
          entry('2', title: 'Alpha'),
          entry('1', title: 'Alpha'),
          entry('4', title: 'alpha'),
        ],
        {'1': day(5), '2': day(5), '3': day(5), '4': day(5)},
      );
      // "Alpha" < "alpha" as raw text; equal titles fall back to the id.
      expect(ids(out), ['1', '2', '4', '3']);
    });

    test('ids that are not in the list are ignored', () {
      final out = sorted(
        [entry('a', updated: day(1)), entry('b', updated: day(2))],
        {'gone': day(30), 'a': day(3)},
      );
      expect(ids(out), ['a', 'b']);
    });

    test('UTC and local times compare as instants', () {
      final utc = DateTime.utc(2024, 3, 1, 12);
      final local = utc.add(const Duration(minutes: 1)).toLocal();
      final out = sorted([entry('a'), entry('b')], {'a': utc, 'b': local});
      expect(ids(out), ['b', 'a']);
    });
  });

  group('added', () {
    test('newest first by createdAt, ignoring edits and use', () {
      final out = sortEntries(
        [
          entry('old', created: day(1), updated: day(30)),
          entry('new', created: day(9), updated: day(9)),
          entry('mid', created: day(5), updated: day(5)),
        ],
        EntrySort.added,
        {'old': day(31)},
      );
      expect(ids(out), ['new', 'mid', 'old']);
    });

    test('ties: title, then id', () {
      final out = sortEntries(
        [
          entry('2', title: 'B', created: day(1)),
          entry('3', title: 'A', created: day(1)),
          entry('1', title: 'B', created: day(1)),
        ],
        EntrySort.added,
        const {},
      );
      expect(ids(out), ['3', '1', '2']);
    });
  });

  group('every mode', () {
    final all = EntrySort.values;

    test('does not change its input and returns a new list', () {
      final input = [
        entry('b', title: 'B', updated: day(1)),
        entry('a', title: 'A', updated: day(2)),
      ];
      final copy = List.of(input);
      for (final mode in all) {
        final out = sortEntries(input, mode, const {});
        expect(out, isNot(same(input)));
        expect(input, copy);
      }
    });

    test('empty and single lists', () {
      for (final mode in all) {
        expect(sortEntries(const [], mode, const {}), isEmpty);
        final one = entry('x', title: 'X');
        expect(sortEntries([one], mode, const {}), [one]);
      }
    });

    test('entries equal in everything keep their input order', () {
      final a = entry('same', title: 'T');
      final b = entry('same', title: 'T');
      final c = entry('same', title: 'T');
      for (final mode in all) {
        final out = sortEntries([c, a, b], mode, const {});
        expect(out[0], same(c));
        expect(out[1], same(a));
        expect(out[2], same(b));
      }
    });

    test('the result does not depend on the input order', () {
      final rnd = Random(42);
      final entries = [
        for (var i = 0; i < 120; i++)
          entry(
            'id${i.toString().padLeft(3, '0')}',
            // Few distinct values, so there are many ties.
            title: ['Alpha', 'alpha', 'بنك', 'Bank', ''][rnd.nextInt(5)],
            created: day(1 + rnd.nextInt(4)),
            updated: day(1 + rnd.nextInt(4)),
          ),
      ];
      final used = {
        for (final e in entries)
          if (rnd.nextBool()) e.id: day(1 + rnd.nextInt(4)),
      };
      for (final mode in all) {
        final expected = ids(sortEntries(entries, mode, used));
        for (var round = 0; round < 5; round++) {
          final shuffled = List.of(entries)..shuffle(rnd);
          expect(
            ids(sortEntries(shuffled, mode, used)),
            expected,
            reason: '$mode',
          );
        }
      }
    });
  });

  group('favoritesFirst', () {
    final list = [
      entry('a', title: 'A', updated: day(1)),
      entry('b', title: 'B', favorite: true, updated: day(2)),
      entry('c', title: 'C', updated: day(3)),
      entry('d', title: 'D', favorite: true, updated: day(4)),
    ];

    test('is off unless asked for', () {
      expect(ids(sortEntries(list, EntrySort.title, const {})), [
        'a',
        'b',
        'c',
        'd',
      ]);
    });

    test('pins favourites above the rest, each group in its own order', () {
      expect(
        ids(sortEntries(list, EntrySort.title, const {}, favoritesFirst: true)),
        ['b', 'd', 'a', 'c'],
      );
      expect(
        ids(
          sortEntries(list, EntrySort.recent, {
            'a': day(9),
          }, favoritesFirst: true),
        ),
        ['d', 'b', 'a', 'c'],
      );
      expect(
        ids(sortEntries(list, EntrySort.added, const {}, favoritesFirst: true)),
        ['b', 'd', 'a', 'c'],
      );
    });
  });
}
