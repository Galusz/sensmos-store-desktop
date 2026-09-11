import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sensmos_store/sensmos_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dziennik.dart';
import 'i18n.dart';
import 'pairing.dart';

/// Stan konta po stronie komputera: połączenie, skrzynka, lista plików i pakiet.
///
/// Trzymany osobno od widoku, bo korzysta z niego i tabela, i backup w tle, i pasek stanu —
/// a trzy kopie tej samej listy rozjeżdżają się przy pierwszym błędzie.
class Session extends ChangeNotifier {
  final Map<String, dynamic> pairing;
  Session(this.pairing);

  StoreRelay? relay;
  Box? box;
  List<StoreFile> files = [];
  int usedB = 0, limitB = 0;
  double daily = 0;
  int sellers = 0;
  String? error;
  bool connected = false;
  /// Trasa ostatniego transferu — 'direct' albo 'relay'. Widać ją w pasku stanu.
  String lastRoute = '';

  /// Czy konto ma w ogóle wykupione miejsce. `null` = jeszcze nie wiemy — i wtedy NIE wolno
  /// niczego twierdzić, bo „brak pakietu" i „nie zdążyliśmy zapytać" wyglądają tak samo.
  bool? hasPackage;
  int unpaidDays = 0;
  int sellersOnline = 0;

  /// Oferta: ile największy pakiet da się dziś kupić, po ile i w ilu kopiach.
  int maxGb = 0;
  int kopie = 0;
  double dziennieZaGb = 0;
  double dostepneGalu = 0;

  /// Widełki wyboru liczby kopii — z serwera, żeby nie rozjechały się z tym, co on wpuszcza.
  int minKopii = 2, maxKopii = 4, zalecaneKopii = 3;
  /// Ile GB da się kupić PRZY DANEJ liczbie kopii. Każda kopia musi trafić do innego właściciela,
  /// więc im więcej kopii, tym słabszy jest ostatni potrzebny sprzedawca — i tym niższy sufit.
  Map<int, int> maxGbDlaKopii = const {};
  /// Cena za gigabajt za JEDNĄ kopię na dobę.
  double zaGbZaKopie = 0.1;
  /// Ile kopii ma trzymać wykupiony pakiet i ile ich w tej chwili naprawdę stoi. Różnią się,
  /// gdy sprzedawca zamilkł i trwa odbudowa.
  int kopiiPakietu = 0, kopiiTeraz = 0;

  String get owner => '${pairing['owner']}';
  String get _be => (pairing['be'] as String?) ?? Pairing.be;

  /// Stan konta i oferta — zwykłym HTTP, bo to te same liczby, które widzi telefon, i nie ma
  /// powodu dublować ich w protokole plików.
  Future<void> odswiezStan() async {
    Future<Map<String, dynamic>?> pobierz(String sciezka) async {
      try {
        final r = await http.get(Uri.parse('$_be$sciezka')).timeout(const Duration(seconds: 12));
        if (r.statusCode != 200) return null;
        return jsonDecode(r.body) as Map<String, dynamic>;
      } catch (_) {
        return null;
      }
    }

    final p = await pobierz('/v1/store/package/$owner');
    if (p != null) {
      hasPackage = p['has_package'] == true;
      unpaidDays = (num.tryParse('${p['unpaid_days']}') ?? 0).toInt();
      sellersOnline = (num.tryParse('${p['sellers_online']}') ?? 0).toInt();
      kopiiPakietu = (num.tryParse('${p['copies']}') ?? 0).toInt();
      kopiiTeraz = (num.tryParse('${p['copies_now']}') ?? 0).toInt();
    }
    final c = await pobierz('/v1/store/capacity');
    if (c != null) {
      maxGb = (num.tryParse('${c['max_gb']}') ?? 0).toInt();
      kopie = (num.tryParse('${c['copies']}') ?? 0).toInt();
      final zaPakiet = (num.tryParse('${c['daily_galu']}') ?? 0).toDouble();
      final gbPakietu = (num.tryParse('${c['package_gb']}') ?? 1).toDouble();
      dziennieZaGb = gbPakietu > 0 ? zaPakiet / gbPakietu : 0;
      minKopii = (num.tryParse('${c['min_copies']}') ?? 0).toInt().clamp(1, 4);
      maxKopii = (num.tryParse('${c['max_copies']}') ?? 0).toInt().clamp(minKopii, 4);
      zalecaneKopii = (num.tryParse('${c['default_copies']}') ?? 0).toInt().clamp(minKopii, maxKopii);
      zaGbZaKopie = double.tryParse('${c['price_gb_copy']}') ?? 0.1;
      final tab = c['max_gb_by_copies'];
      if (tab is Map) {
        maxGbDlaKopii = {
          for (final e in tab.entries)
            if (int.tryParse('${e.key}') != null)
              int.parse('${e.key}'): (num.tryParse('${e.value}') ?? 0).toInt(),
        };
      }
    }
    final w = await pobierz('/v1/wallet/$owner');
    if (w != null) dostepneGalu = double.tryParse('${w['available']}') ?? 0;
    notifyListeners();
  }

  /// Wykup miejsca. Ta sama wiadomość, którą wysyła telefon — sparowany komputer jest dla
  /// serwera zwykłym kupującym, więc nie ma tu osobnej ścieżki ani osobnego uprawnienia.
  Future<Map<String, dynamic>> kup(int gb, int kopii) async {
    final r = await relay!.package(gb: gb, copies: kopii);
    if (r['ok'] == true) { await odswiezStan(); await refresh(); }
    return r;
  }

  /// Powiększenie albo zmniejszenie pakietu o pełne gigabajty. Ta sama wiadomość, którą wysyła
  /// telefon — backend umiał to od dawna, brakowało wyłącznie przycisków po tej stronie.
  Future<Map<String, dynamic>> zmienRozmiar(int oGb) async {
    final r = await relay!.package(addGb: oGb);
    if (r['ok'] == true) { await odswiezStan(); await refresh(); }
    return r;
  }

  /// Zmiana liczby kopii wykupionego pakietu. W górę serwer dobiera sprzedawcę od razu i sam
  /// odmawia, gdy nie ma z kogo — wtedy oddajemy jego powód, bo tylko on wie, czego zabrakło.
  Future<Map<String, dynamic>> ustawKopie(int kopii) async {
    final r = await relay!.package(copies: kopii);
    if (r['ok'] == true) { await odswiezStan(); await refresh(); }
    return r;
  }

  /// „Zatrzymaj" w trakcie wysyłki. Przerywa bieżący plik i mówi o tym backendowi, żeby
  /// sprzątnął wpis i oddał miejsce w pakiecie. Tego, co już doszło, nie cofa.
  void przerwij() => relay?.przerwijWysylke();

  bool get canRead => box?.canRead ?? false;
  double get usedRatio => limitB > 0 ? usedB / limitB : 0;

  /// Wysyłki, które ZACZĘŁY się, ale nie potwierdziły: nazwa docelowa → ścieżka na dysku.
  /// Trzymamy to na dysku, bo najgorszy przypadek to ubicie programu w połowie wysyłki —
  /// wtedy wpis pliku już jest, bajtów nie ma i nikt się o tym nie dowie.
  final Map<String, String> wLocie = {};
  static const _slotWLocie = 'sensmos_wysylki_w_locie';

  Future<void> _wczytajWLocie() async {
    final p = await SharedPreferences.getInstance();
    try {
      final m = jsonDecode(p.getString(_slotWLocie) ?? '{}') as Map;
      wLocie.addAll(m.map((k, v) => MapEntry('$k', '$v')));
    } catch (_) {/* zepsuty zapis = pusto, to tylko notatka */}
  }

  Future<void> _zapiszWLocie() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_slotWLocie, jsonEncode(wLocie));
  }

  Future<void> zapomnijWLocie(String nazwa) async {
    wLocie.remove(nazwa);
    await _zapiszWLocie();
    notifyListeners();
  }

  /// Po tylu minutach bez ani jednej potwierdzonej kopii nie ma już na co czekać. Rozmieszczanie
  /// idzie sekundami — kwadrans to nie „jeszcze trwa", tylko „nic nie wyszło".
  static const _martwePo = Duration(minutes: 15);

  /// Plik, który widać na liście, ale nie doszedł do nikogo — ani jeden bajt. Sieć tego nie
  /// naprawi, bo odbudowa kopiuje z żywej kopii, a tu nie ma z czego.
  bool niedokonczony(StoreFile f) {
    if (f.copies > 0) return false;
    if (wLocie.containsKey(f.name ?? '')) return true;
    final k = f.createdAt;
    return k != null && DateTime.now().difference(k) > _martwePo;
  }

  List<StoreFile> get niedokonczone => files.where(niedokonczony).toList();

  Future<void> connect() async {
    try {
      await _wczytajWLocie();
      box = await Box.from(pairing);
      await _polacz();
      connected = true;
      error = null;
      await refresh();
      await odswiezStan();
      await _uzupelnijKatalogi();
    } catch (e) {
      connected = false;
      error = '$e';
      notifyListeners();
    }
  }

  /// Jedyne miejsce, w którym powstaje połączenie ze sklepem. Używa go i pierwsze zalogowanie,
  /// i powrót po zerwanym łączu — dwa różne sposoby łączenia rozjechałyby się przy pierwszej
  /// zmianie parowania.
  Future<void> _polacz() async {
    relay = StoreRelay.paired(
      owner: pairing['owner'] as String,
      beUrl: (pairing['be'] as String?) ?? Pairing.be,
      token: pairing['token'] as String,
    );
    await relay!.connect();
  }

  Future<void> refresh() async {
    final l = await relay!.list();
    final raw = ((l['items'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final out = <StoreFile>[];
    for (final it in raw) {
      String? name;
      if (canRead) {
        try {
          final dek = await StoreCrypto.unwrapDek(it['wrapped_key'] as String, box!.priv!);
          final n = StoreCrypto.decryptName(dek, it['name_enc'] as String?);
          if (n.isNotEmpty && n != '?') name = n;
        } catch (_) {/* nie nasz klucz albo uszkodzony rekord — pokażemy identyfikator */}
      }
      out.add(StoreFile(
        id: '${it['id']}',
        name: name,
        sizeB: (num.tryParse('${it['size_b']}') ?? 0).toInt(),
        copies: (num.tryParse('${it['copies']}') ?? 0).toInt(),
        createdAt: DateTime.tryParse('${it['created_at']}')?.toLocal(),
        wrappedKey: '${it['wrapped_key']}',
        folderH: '${it['folder_h'] ?? ''}',
      ));
    }
    files = out;
    usedB = (num.tryParse('${l['used_b']}') ?? 0).toInt();
    limitB = (num.tryParse('${l['limit_b']}') ?? 0).toInt();
    daily = (num.tryParse('${l['daily']}') ?? 0).toDouble();
    sellers = ((l['sellers'] as List?) ?? const []).length;
    error = null;
    notifyListeners();
  }

  /// Pliki, ktore powstaly przed katalogami-polami, nie maja czym sie grupowac po stronie
  /// serwera. Nazwa nadal niesie pelna sciezke, wiec odcisk da sie policzyc u nas i dopisac —
  /// jednym przebiegiem, raz. Podpisu ani nazwy to nie dotyka.
  Future<void> _uzupelnijKatalogi() async {
    final ziarno = box?.seed;
    if (ziarno == null) return;
    var ile = 0;
    for (final f in files) {
      if (f.folderH.isNotEmpty || f.name == null) continue;
      final d = f.folder;
      try {
        await relay!.setFolder(f.id, StoreCrypto.folderHash(ziarno, d),
            StoreCrypto.encryptFolder(ziarno, d));
        ile++;
      } catch (_) { return; }
    }
    if (ile > 0) {
      Dziennik.i.dodaj(Rodzaj.info, t('log.foldersFilled', {'n': ile}));
      await refresh();
    }
  }

  /// Wysyłka. `folder` trafia do NAZWY jako przedrostek — serwer nazwy nie widzi, więc katalogi
  /// są wyłącznie umową między klientami. Zero zmian w protokole i u sprzedawców.
  Future<void> upload(File f, {String folder = '', void Function(double)? onProgress}) async {
    final nazwa = folder.isEmpty ? _base(f.path) : '$folder/${_base(f.path)}';
    final dek = StoreCrypto.randomBytes(32);
    final (encPath, blocks, digest) = await StoreCrypto.encryptInIsolate(f.path, dek);
    final enc = File(encPath);
    wLocie[nazwa] = f.path;
    await _zapiszWLocie();
    try {
      final size = await enc.length();
      final ziarno = box?.seed;
      // Wysyłka urwana nie przez człowieka dostaje jeszcze dwie szanse. Bajty, które doszły,
      // leżą u sprzedawcy, a ten sam szyfrogram mamy jeszcze pod ręką — wracamy więc do TEJ
      // SAMEJ wysyłki zamiast zaczynać nowej. Dalej to już nie jest chwilowe zerwanie łącza.
      String? wznow;
      for (var proba = 0; ; proba++) {
        try {
          await relay!.put(
            cipher: enc, size: size, blocks: blocks, sha256hex: digest,
            wrappedKey: await StoreCrypto.wrapDek(dek, box!.pub),
            nameEnc: StoreCrypto.encryptName(dek, nazwa),
            // Odcisk katalogu idzie OBOK podpisanej nazwy — po nim serwer grupuje i stronicuje.
            folderH: ziarno == null ? '' : StoreCrypto.folderHash(ziarno, folder),
            folderEnc: ziarno == null ? '' : StoreCrypto.encryptFolder(ziarno, folder),
            resumeOid: wznow,
            onProgress: (s) => onProgress?.call(size > 0 ? s / size : 0),
          );
          break;
        } on UploadInterrupted catch (e) {
          if (proba >= 2) rethrow;
          wznow = e.objectId;
          Dziennik.i.dodaj(Rodzaj.blad, t('log.resume', {'f': nazwa}));
          try { await _polacz(); } catch (_) { rethrow; }
        }
      }
      lastRoute = relay!.lastRoute;
      wLocie.remove(nazwa);
      await _zapiszWLocie();
      Dziennik.i.dodaj(Rodzaj.wyslanie, t('log.upload', {'f': nazwa}),
          bajty: size, trasa: lastRoute);
    } catch (e) {
      Dziennik.i.dodaj(Rodzaj.blad, t('log.failed', {'f': nazwa, 'e': '$e'}));
      rethrow;
    } finally {
      try { await enc.parent.delete(recursive: true); } catch (_) {}
    }
  }

  /// Pobranie do wskazanego katalogu; struktura folderów z nazwy jest odtwarzana na dysku.
  Future<File> download(StoreFile f, String dir, {void Function(double)? onProgress}) async {
    final tmp = await Directory.systemTemp.createTemp('sensmos-');
    final enc = File('${tmp.path}${Platform.pathSeparator}dl.bin');
    try {
      await relay!.get(f.id, enc,
          onProgress: (g) => onProgress?.call(f.sizeB > 0 ? g / f.sizeB : 0));
      lastRoute = relay!.lastRoute;
      final dek = await StoreCrypto.unwrapDek(f.wrappedKey, box!.priv!);
      final plain = await StoreCrypto.decryptInIsolate(enc.path, dek);
      final rel = (f.name ?? f.id).split('/');
      final cel = Directory([dir, ...rel.take(rel.length - 1)].join(Platform.pathSeparator));
      if (!await cel.exists()) await cel.create(recursive: true);
      final out = File('${cel.path}${Platform.pathSeparator}${rel.last}');
      await out.writeAsBytes(plain);
      Dziennik.i.dodaj(Rodzaj.pobranie, t('log.download', {'f': f.name ?? f.id}),
          bajty: f.sizeB, trasa: lastRoute);
      return out;
    } finally {
      try { await tmp.delete(recursive: true); } catch (_) {}
    }
  }

  Future<void> remove(StoreFile f) async {
    await relay!.del(f.id);
    await zapomnijWLocie(f.name ?? '');
    Dziennik.i.dodaj(Rodzaj.kasowanie, t('log.delete', {'f': f.name ?? f.id}), bajty: f.sizeB);
  }

  /// Media do PLIKU na dysku, nie do pamięci: odtwarzacz czyta strumieniem, więc godzinny film
  /// nie musi zmieścić się w RAM-ie. Trzymamy ostatnio otwarty, żeby przewinięcie w tył nie
  /// oznaczało ponownego pobrania z sieci.
  Directory? _mediaKatalog;
  String? _mediaId;
  File? _mediaPlik;

  Future<File> doPliku(StoreFile f, {void Function(double)? onProgress}) async {
    final gotowy = _mediaPlik;
    if (_mediaId == f.id && gotowy != null && await gotowy.exists()) return gotowy;
    await _sprzatnijMedia();
    final tmp = await Directory.systemTemp.createTemp('sensmos-media-');
    _mediaKatalog = tmp;
    final enc = File('${tmp.path}${Platform.pathSeparator}enc.bin');
    try {
      await relay!.get(f.id, enc,
          onProgress: (g) => onProgress?.call(f.sizeB > 0 ? g / f.sizeB : 0));
      lastRoute = relay!.lastRoute;
      final dek = await StoreCrypto.unwrapDek(f.wrappedKey, box!.priv!);
      final plain = await StoreCrypto.decryptInIsolate(enc.path, dek);
      final out = File('${tmp.path}${Platform.pathSeparator}${f.baseName}');
      await out.writeAsBytes(plain);
      _mediaId = f.id;
      _mediaPlik = out;
      Dziennik.i.dodaj(Rodzaj.pobranie, t('log.download', {'f': f.name ?? f.id}),
          bajty: f.sizeB, trasa: lastRoute);
      return out;
    } finally {
      try { await enc.delete(); } catch (_) {}
    }
  }

  /// Suma z JAWNEJ tresci — jedyna rzecz, ktora naprawde mowi „to ten sam plik".
  ///
  /// Serwerowy `sha256` dotyczy szyfrogramu, a kazda wysylka ma wlasny losowy klucz, wiec dwa
  /// identyczne pliki maja tam rozne sumy. To nie brak, tylko wlasnosc: serwer nie ma jak
  /// stwierdzic, kto trzyma to samo co kto inny.
  Future<String> sumaJawna(StoreFile f, {void Function(double)? onProgress}) async {
    final tmp = await Directory.systemTemp.createTemp('sensmos-dup-');
    final enc = File('${tmp.path}${Platform.pathSeparator}d.bin');
    try {
      await relay!.get(f.id, enc,
          onProgress: (g) => onProgress?.call(f.sizeB > 0 ? g / f.sizeB : 0));
      lastRoute = relay!.lastRoute;
      final dek = await StoreCrypto.unwrapDek(f.wrappedKey, box!.priv!);
      final plain = await StoreCrypto.decryptInIsolate(enc.path, dek);
      return sha256.convert(plain).toString();
    } finally {
      try { await tmp.delete(recursive: true); } catch (_) {}
    }
  }

  Future<void> _sprzatnijMedia() async {
    final k = _mediaKatalog;
    _mediaKatalog = null; _mediaId = null; _mediaPlik = null;
    if (k != null) { try { await k.delete(recursive: true); } catch (_) {} }
  }

  /// Jawna tresc pliku w pamieci — do podgladu. Trzymamy kilka ostatnich, bo kazde wejscie w plik
  /// oznacza pobranie go z sieci i odszyfrowanie; bez tego przewijanie listy kosztowaloby transfer.
  final _podglad = <String, Uint8List>{};
  static const _maxPodgladow = 6;

  Future<Uint8List> preview(StoreFile f) async {
    final gotowe = _podglad[f.id];
    if (gotowe != null) return gotowe;
    final tmp = await Directory.systemTemp.createTemp('sensmos-prev-');
    final enc = File('${tmp.path}${Platform.pathSeparator}p.bin');
    try {
      await relay!.get(f.id, enc);
      final dek = await StoreCrypto.unwrapDek(f.wrappedKey, box!.priv!);
      final plain = await StoreCrypto.decryptInIsolate(enc.path, dek);
      if (_podglad.length >= _maxPodgladow) _podglad.remove(_podglad.keys.first);
      _podglad[f.id] = plain;
      return plain;
    } finally {
      try { await tmp.delete(recursive: true); } catch (_) {}
    }
  }

  static String _base(String p) => p.split(Platform.pathSeparator).last.split('/').last;

  @override
  void dispose() { _sprzatnijMedia(); relay?.dispose(); super.dispose(); }
}

/// Jeden plik w pakiecie. `name` puste = nie mamy prawa czytania albo rekord jest sprzed nazw.
class StoreFile {
  final String id;
  final String? name;
  final int sizeB, copies;
  final DateTime? createdAt;
  final String wrappedKey;
  /// Odcisk katalogu po stronie serwera. Pusty = plik sprzed katalogow-pol albo korzen.
  final String folderH;
  const StoreFile({required this.id, this.name, required this.sizeB, required this.copies,
                   this.createdAt, required this.wrappedKey, this.folderH = ''});

  /// Katalog wyprowadzony z nazwy — `zdjęcia/2026/x.jpg` → `zdjęcia/2026`.
  String get folder {
    final n = name;
    if (n == null || !n.contains('/')) return '';
    return n.substring(0, n.lastIndexOf('/'));
  }

  String get baseName {
    final n = name;
    if (n == null) return id;
    return n.contains('/') ? n.substring(n.lastIndexOf('/') + 1) : n;
  }

  String get ext {
    final b = baseName;
    final i = b.lastIndexOf('.');
    return i > 0 && i < b.length - 1 ? b.substring(i + 1).toLowerCase() : '';
  }
}
