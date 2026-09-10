import 'package:flutter_test/flutter_test.dart';
import 'package:sensmos_pc/i18n.dart';

void main() {
  test('polski liczebnik ma trzy formy, nie dwie', () {
    L.kod = 'pl';
    expect(liczba('plural.files', 1), '1 plik');
    expect(liczba('plural.files', 2), '2 pliki');
    expect(liczba('plural.files', 4), '4 pliki');
    expect(liczba('plural.files', 5), '5 plików');
    // 12–14 to wyjątek: „12 plików", nie „12 pliki"
    expect(liczba('plural.files', 12), '12 plików');
    expect(liczba('plural.files', 22), '22 pliki');
    expect(liczba('plural.files', 25), '25 plików');
    expect(liczba('plural.files', 112), '112 plików');
  });

  test('angielski i niemiecki maja dwie formy', () {
    L.kod = 'en';
    expect(liczba('plural.files', 1), '1 file');
    expect(liczba('plural.files', 5), '5 files');
    L.kod = 'de';
    expect(liczba('plural.files', 1), '1 Datei');
    expect(liczba('plural.files', 5), '5 Dateien');
  });

  test('brakujacy klucz nie znika bez sladu', () {
    L.kod = 'pl';
    expect(t('nie.ma.takiego.klucza'), 'nie.ma.takiego.klucza');
    expect(t('st.connected'), 'Połączono');
  });

  test('pola wstawiaja sie w napis', () {
    L.kod = 'en';
    expect(t('backup.last', {'when': '5 min ago'}), 'Last: 5 min ago');
    expect(t('busy.uploadingN', {'i': 2, 'n': 9, 'f': 'a.txt'}), 'Uploading 2/9: a.txt');
  });

  test('kazdy jezyk ma komplet kluczy angielskiego', () {
    final brakujace = <String>[];
    for (final kod in L.kody) {
      if (kod == 'en') continue;
      L.kod = kod;
      for (final k in kluczeAngielskie) {
        // polskie „few" nie istnieje w innych jezykach — to jedyny dozwolony brak
        if (k.endsWith('.few')) continue;
        if (!maKlucz(kod, k)) brakujace.add('$kod: $k');
      }
    }
    L.kod = 'en';
    expect(brakujace, isEmpty, reason: brakujace.join('\n'));
  });
}
