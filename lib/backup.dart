import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sensmos_store/sensmos_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'i18n.dart';
import 'session.dart';

/// Kopia zapasowa pilnowanych katalogów — JEDNOKIERUNKOWA i to jest decyzja, nie skrót.
///
/// Nowy albo zmieniony plik idzie w górę. Skasowanie u siebie **nie kasuje** kopii w Store, a
/// zmiana nazwy tworzy nowy wpis zamiast ruszać stary. Prawdziwa synchronizacja dwukierunkowa
/// znaczyłaby propagowanie kasowania — a błąd w takim kodzie usuwa komuś prawdziwe pliki, których
/// my nawet nie zobaczymy, bo wszystko jest zaszyfrowane. Tego ryzyka nie warto brać.
///
/// Co zmieniło się od ostatniego razu, poznajemy po sumie kontrolnej JAWNEJ treści. Rozmiar i data
/// same w sobie kłamią (edytor potrafi zapisać plik bez zmiany rozmiaru), więc służą wyłącznie do
/// pominięcia liczenia sumy tam, gdzie na pewno nic się nie stało.

/// Jeden pilnowany katalog. Każdy ma WŁASNY folder docelowy — inaczej wszystko lądowałoby
/// w jednym „backup" i po tygodniu nikt by nie wiedział, co skąd przyszło.
class Pilnowany {
  String dir;
  String prefix;
  Map<String, dynamic> index;
  DateTime? lastRun;

  bool running = false;
  String status = '';

  Pilnowany({required this.dir, required this.prefix, Map<String, dynamic>? index, this.lastRun})
      : index = index ?? {};

  /// Nazwa samego katalogu, bez ścieżki — domyślna propozycja folderu docelowego.
  String get nazwa {
    final cz = dir.split(RegExp(r'[\\/]')).where((x) => x.isNotEmpty).toList();
    return cz.isEmpty ? dir : cz.last;
  }

  Map<String, dynamic> toJson() =>
      {'dir': dir, 'prefix': prefix, 'index': index, 'last': lastRun?.toIso8601String()};

  static Pilnowany fromJson(Map m) => Pilnowany(
        dir: '${m['dir']}',
        prefix: '${m['prefix'] ?? ''}',
        index: (m['index'] as Map?)?.cast<String, dynamic>() ?? {},
        lastRun: DateTime.tryParse('${m['last']}'),
      );
}

class Backup extends ChangeNotifier {
  static const _slot = 'sensmos_backup';

  final List<Pilnowany> lista = [];
  bool auto = false;
  int everyMin = 30;
  Timer? _timer;

  bool get running => lista.any((w) => w.running);

  /// Status tego, co akurat pracuje — a jak nic nie pracuje, ostatnie zdanie z listy.
  String get status {
    for (final w in lista) {
      if (w.running) return w.status;
    }
    for (final w in lista.reversed) {
      if (w.status.isNotEmpty) return w.status;
    }
    return '';
  }

  DateTime? get lastRun {
    DateTime? n;
    for (final w in lista) {
      final l = w.lastRun;
      if (l != null && (n == null || l.isAfter(n))) n = l;
    }
    return n;
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_slot);
    lista.clear();
    if (raw != null) {
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        auto = m['auto'] == true;
        everyMin = (m['every'] as num?)?.toInt() ?? 30;
        if (m['lista'] is List) {
          for (final e in (m['lista'] as List)) {
            lista.add(Pilnowany.fromJson(e as Map));
          }
        } else if (m['dir'] is String) {
          // Zapis z czasów jednego katalogu. Przepisujemy raz i od tej pory istnieje już tylko
          // lista — starego kształtu nie zapisujemy nigdy więcej.
          lista.add(Pilnowany(
            dir: m['dir'] as String,
            prefix: '${m['prefix'] ?? 'backup'}',
            index: (m['index'] as Map?)?.cast<String, dynamic>() ?? {},
            lastRun: DateTime.tryParse('${m['last']}'),
          ));
          await save();
        }
      } catch (_) {/* zepsuty zapis = zaczynamy od zera, to tylko pamięć podręczna */}
    }
    notifyListeners();
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_slot, jsonEncode({
      'auto': auto,
      'every': everyMin,
      'lista': [for (final w in lista) w.toJson()],
    }));
  }

  Future<void> dodaj(String dir, String prefix) async {
    if (lista.any((w) => w.dir == dir)) return;
    lista.add(Pilnowany(dir: dir, prefix: prefix));
    await save();
    notifyListeners();
  }

  Future<void> usun(Pilnowany w) async {
    lista.remove(w);
    await save();
    notifyListeners();
  }

  /// Zmiana folderu docelowego dotyczy TYLKO nowych plików.
  ///
  /// Indeksu NIE czyścimy — czyszczenie kazało wysłać cały pilnowany katalog drugi raz, bo
  /// pominięcie pliku wymagało, żeby leżał pod nowym przedrostkiem, a tam jeszcze nic nie było.
  /// To, co już zabezpieczone, zostaje tam, gdzie jest; przenosin nie ma i nie udajemy, że są.
  Future<void> przemianuj(Pilnowany w, String prefix) async {
    if (w.prefix == prefix) return;
    w.prefix = prefix;
    await save();
    notifyListeners();
  }

  void schedule(Session s) {
    _timer?.cancel();
    if (!auto || lista.isEmpty) return;
    _timer = Timer.periodic(Duration(minutes: everyMin), (_) { if (!running) run(s); });
  }

  /// Żądanie zatrzymania. Sprawdzane przed każdym plikiem, więc pętla staje natychmiast,
  /// a plik, który właśnie leci, przerywa sama sesja.
  ///
  /// Potrzebne, bo wskazanie nie tego katalogu było dotąd nieodwracalne: pętla listowała
  /// wszystko i szła do końca, a jedynym wyjściem było ubicie programu.
  bool _stop = false;
  bool get zatrzymywane => _stop;

  void przerwij(Session s) {
    if (!running) return;
    _stop = true;
    s.przerwij();                 // przerwij TAKŻE plik, który właśnie jest w locie
    notifyListeners();
  }

  /// Bez argumentu — wszystkie pilnowane katalogi po kolei. Z argumentem — tylko ten jeden.
  Future<void> run(Session s, [Pilnowany? tylko]) async {
    _stop = false;
    final robota = tylko != null ? [tylko] : List<Pilnowany>.from(lista);
    for (final w in robota) {
      if (_stop) break;
      await _jeden(s, w);
    }
    _stop = false;
    await s.refresh();
  }

  Future<void> _jeden(Session s, Pilnowany w) async {
    if (w.running) return;
    w.running = true;
    w.status = t('backup.scanning');
    notifyListeners();
    // Licznik ZA try, nie w srodku: przy przerwaniu obsluga musi podac PRAWDZIWA liczbe
    // wyslanych, a nie zero.
    var wyslane = 0, pominiete = 0;
    try {
      final d = Directory(w.dir);
      if (!await d.exists()) { w.status = t('backup.gone'); return; }

      // Co JUŻ leży w pakiecie — żeby po przeinstalowaniu programu nie wysłać wszystkiego drugi raz.
      final wStore = {for (final f in s.files) f.name ?? ''};

      final pliki = <File>[];
      await for (final e in d.list(recursive: true, followLinks: false)) {
        if (e is File) pliki.add(e);
      }
      for (var i = 0; i < pliki.length; i++) {
        // Sprawdzamy PRZED każdym plikiem, a nie raz na przebieg: przy pomylonym katalogu
        // różnica między jednym plikiem a całym dyskiem to właśnie ta linijka.
        if (_stop) { w.status = t('backup.stopped', {'a': wyslane}); await save(); return; }
        final f = pliki[i];
        final rel =
            f.path.substring(w.dir.length).replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), '');
        final st = await f.stat();
        final znany = w.index[rel] as Map?;
        final tenSam = znany != null &&
            (znany['size'] as num?)?.toInt() == st.size &&
            znany['mtime'] == st.modified.toIso8601String();
        final docelowa = w.prefix.isEmpty ? rel : '${w.prefix}/$rel';
        // Pod jaką nazwą ten plik już poszedł. Liczy się TO, a nie dzisiejszy przedrostek —
        // inaczej zmiana nazwy folderu wysyłałaby cały katalog jeszcze raz.
        final juzJako = (znany?['cel'] as String?) ?? docelowa;

        if (tenSam && wStore.contains(juzJako)) { pominiete++; continue; }

        w.status = t('backup.checking', {'i': i + 1, 'n': pliki.length, 'f': rel});
        notifyListeners();
        final sha = await _sha(f);
        if (znany != null && znany['sha'] == sha && wStore.contains(juzJako)) {
          w.index[rel] = {'sha': sha, 'size': st.size,
                          'mtime': st.modified.toIso8601String(), 'cel': juzJako};
          pominiete++;
          continue;
        }

        w.status = t('backup.sending', {'i': i + 1, 'n': pliki.length, 'f': rel});
        notifyListeners();
        final podkatalog = rel.contains('/') ? rel.substring(0, rel.lastIndexOf('/')) : '';
        final folder = [w.prefix, podkatalog].where((x) => x.isNotEmpty).join('/');
        await s.upload(f, folder: folder);
        w.index[rel] = {'sha': sha, 'size': st.size,
                        'mtime': st.modified.toIso8601String(), 'cel': docelowa};
        wyslane++;
        await save();
      }
      w.lastRun = DateTime.now();
      w.status = wyslane == 0
          ? t('backup.upToDate', {'n': liczba('plural.files', pominiete)})
          : t('backup.sent', {'a': wyslane, 'b': pominiete});
      await save();
    } on UploadCancelled {
      // Zatrzymanie to nie awaria. Wpis o niedokończonym pliku sprząta backend, a indeks
      // jest zapisywany po każdym pliku, więc następny przebieg zacznie tam, gdzie stanął.
      w.status = t('backup.stopped', {'a': wyslane});
    } catch (e) {
      w.status = t('backup.failed', {'e': '$e'});
    } finally {
      w.running = false;
      notifyListeners();
    }
  }

  /// Suma jawnej tresci, liczona strumieniem — plik moze byc wiekszy niz pamiec.
  static Future<String> _sha(File f) async {
    final ujscie = _Ujscie();
    final s = sha256.startChunkedConversion(ujscie);
    await for (final chunk in f.openRead()) { s.add(chunk); }
    s.close();
    return ujscie.wynik.toString();
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }
}

/// Kubelek na wynik sumy liczonej strumieniem — `crypto` oddaje ja wlasnie tak.
class _Ujscie implements Sink<Digest> {
  late Digest wynik;
  @override
  void add(Digest d) => wynik = d;
  @override
  void close() {}
}
