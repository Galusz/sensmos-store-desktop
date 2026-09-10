import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show RootIsolateToken;
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as cg;
import 'package:flutter/services.dart' show BackgroundIsolateBinaryMessenger;
import 'package:pointycastle/export.dart' hide Digest;   // Digest bierzemy z package:crypto

/// Szyfrowanie Store — wszystko dzieje się na telefonie, serwer i sprzedawcy widzą szyfrogram.
///
/// Klucz główny (KEK) NIE jest nigdzie zapisany: wyprowadzany na żądanie z podpisu portfela nad
/// stałym komunikatem `sensmos:store:v1`. Podpis secp256k1 w web3dart jest deterministyczny
/// (RFC 6979, sprawdzone tool/sig_det.dart), więc ten sam portfel = ten sam klucz, na każdym
/// urządzeniu. Ledger podpisuje tak samo — to ten sam interfejs, inny podpisujący.
///
/// Każdy plik ma własny losowy klucz (DEK), zapakowany kluczem głównym. Portfel JEST kluczem:
/// jego zaszyfrowana kopia leży na nodzie (odzysk po PIN), osobnej ścieżki odzyskiwania nie ma.
///
/// Układ szyfrogramu:  [sól 8 B][ramka…]  ramka = AES-256-GCM(DEK, nonce = sól‖nr, aad = nr)
/// nad ≤1 MiB jawnego tekstu, czyli ≤1 MiB + 16 B tagu. Nonce z licznika: żadnej powtórki
/// w obrębie pliku, sól losowa per plik. AAD z numerem ramki blokuje przestawianie ramek.
///
/// Ramki pliku liczy NATYWNE AES systemu (cryptography_flutter: na Androidzie javax.crypto,
/// sprzętowe) — czysty Dart robił kilka MB/s i film szyfrował się minutami. Drobiazgi (klucz
/// pliku, nazwa) zostają w pointycastle: są małe i potrzebują synchronicznego API w build().
/// Ten sam algorytm i układ bajtów, więc pliki wgrane wcześniej otwierają się bez zmian.
class StoreCrypto {
  static const int chunk = 1024 * 1024;       // jawny tekst na ramkę
  static const int tag = 16, nonceLen = 12, saltLen = 8;
  static const int frame = chunk + tag;       // ramka szyfrogramu
  static const int block = 10 * 1024 * 1024;  // blok dowodowy backendu (skróty nad szyfrogramem)

  static final _rng = Random.secure();
  static Uint8List randomBytes(int n) => Uint8List.fromList(List.generate(n, (_) => _rng.nextInt(256)));

  // ── skrzynka właściciela: klucz publiczny z podpisu ──
  //
  // Wcześniej klucz był symetryczny, więc zapakować plik potrafił WYŁĄCZNIE telefon. To zamykało
  // drogę wszystkiemu, co mogłoby dokładać dane w imieniu właściciela — archiwum pomiarów
  // z jego czujników przede wszystkim. Dać ten klucz serwerowi albo nodowi nie wchodzi w grę:
  // to jeden klucz do WSZYSTKICH plików, a node stoi w cudzej piwnicy.
  //
  // Więc para kluczy zamiast jednego. Połowa publiczna jest jawna — kto ją ma, może dołożyć plik
  // do skrzynki i nie potrafi otworzyć niczego, także tego, co sam włożył. Połowa prywatna nigdzie
  // nie leży: odtwarza się z podpisu portfela, tak samo jak wcześniej klucz symetryczny. Dzięki
  // temu do CZYTANIA dalej wystarcza `signMessage` — Ledger podpisuje tak samo, to ten sam
  // interfejs, inny podpisujący.
  static final _x = cg.X25519();

  static Uint8List boxSeed(Uint8List sig) =>
      _hkdf(Uint8List.fromList(sha256.convert(sig).bytes), utf8.encode('sensmos:store:box:v1'), 32);

  static Future<cg.SimpleKeyPair> boxKeyPair(Uint8List sig) => boxFromSeed(boxSeed(sig));

  /// Skrzynka z GOTOWEGO ziarna — dla urządzenia, które dostało je przy parowaniu i portfela nie
  /// ma. Osobna nazwa, bo pomylenie ziarna z podpisem daje inny klucz i objawia się dopiero
  /// niezgodnym MAC-iem przy pierwszym odczycie, czyli daleko od miejsca pomyłki.
  static Future<cg.SimpleKeyPair> boxFromSeed(Uint8List seed) => _x.newKeyPairFromSeed(seed);

  static String pubHex(cg.SimplePublicKey p) =>
      p.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  static cg.SimplePublicKey pubFromHex(String h) => cg.SimplePublicKey(
      List.generate(h.length ~/ 2, (i) => int.parse(h.substring(2 * i, 2 * i + 2), radix: 16)),
      type: cg.KeyPairType.x25519);

  static Uint8List _hkdf(Uint8List ikm, List<int> info, int len) {
    final prk = Hmac(sha256, List.filled(32, 0)).convert(ikm).bytes;      // extract, sól zerowa
    final out = <int>[]; var t = <int>[]; var i = 1;
    while (out.length < len) {
      t = Hmac(sha256, prk).convert([...t, ...info, i++]).bytes;             // expand
      out.addAll(t);
    }
    return Uint8List.fromList(out.sublist(0, len));
  }

  // ── AES-256-GCM na małych rzeczach (klucze, nazwy) ──
  static GCMBlockCipher _gcm(bool enc, Uint8List key, Uint8List nonce, Uint8List aad) =>
      GCMBlockCipher(AESEngine())..init(enc, AEADParameters(KeyParameter(key), tag * 8, nonce, aad));

  /// base64( nonce ‖ szyfrogram ‖ tag )
  static String seal(Uint8List key, Uint8List plain, {String aad = ''}) {
    final nonce = randomBytes(nonceLen);
    final ct = _gcm(true, key, nonce, Uint8List.fromList(utf8.encode(aad))).process(plain);
    return base64Encode([...nonce, ...ct]);
  }

  static Uint8List open(Uint8List key, String sealed, {String aad = ''}) {
    final b = base64Decode(sealed);
    final nonce = Uint8List.fromList(b.sublist(0, nonceLen));
    return _gcm(false, key, nonce, Uint8List.fromList(utf8.encode(aad)))
        .process(Uint8List.fromList(b.sublist(nonceLen)));
  }

  /// Klucz pliku zapakowany do skrzynki właściciela → JSON {"x": base64(pub 32 ‖ nonce 12 ‖ szyfr+tag)}.
  ///
  /// Klucz jednorazowy do każdego pakowania, wspólny sekret z wymiany, z niego klucz opakowania.
  /// Oba klucze publiczne wchodzą do wyprowadzenia, więc opakowania nie da się przekleić do innej
  /// skrzynki. Nadawca po zapakowaniu nie ma czym odpakować — klucz jednorazowy ginie.
  static Future<String> wrapDek(Uint8List dek, cg.SimplePublicKey ownerPub) async {
    final eph = await _x.newKeyPair();
    final ephPub = await eph.extractPublicKey();
    final key = await _wrapKey(eph, ownerPub, ephPub.bytes, ownerPub.bytes);
    final nonce = randomBytes(nonceLen);
    final box = await _aes.encrypt(dek, secretKey: key, nonce: nonce);
    return jsonEncode({'x': base64Encode([...ephPub.bytes, ...nonce, ...box.cipherText, ...box.mac.bytes])});
  }

  static Future<Uint8List> unwrapDek(String wrapped, cg.SimpleKeyPair box) async {
    final b = base64Decode((jsonDecode(wrapped) as Map)['x'] as String);
    if (b.length < 32 + nonceLen + tag) throw const FormatException('wrapped key too short');
    final ephPub = cg.SimplePublicKey(b.sublist(0, 32), type: cg.KeyPairType.x25519);
    final ownerPub = await box.extractPublicKey();
    final key = await _wrapKey(box, ephPub, ephPub.bytes, ownerPub.bytes);
    final sb = cg.SecretBox(b.sublist(32 + nonceLen, b.length - tag),
        nonce: b.sublist(32, 32 + nonceLen), mac: cg.Mac(b.sublist(b.length - tag)));
    return Uint8List.fromList(await _aes.decrypt(sb, secretKey: key));
  }

  /// `label` oddziela zastosowania (klucz pliku ≠ parowanie), `extra` dokłada to, czego serwer
  /// nie zna — przy parowaniu jest to kod z ekranu komputera. Dzięki temu podmiana klucza
  /// publicznego po drodze nie wystarcza, żeby paczkę otworzyć: trzeba jeszcze znać kod.
  static Future<cg.SecretKey> _wrapKey(cg.KeyPair mine, cg.SimplePublicKey theirs,
                                       List<int> ephPub, List<int> ownerPub,
                                       {String label = 'sensmos:store:dek:v1',
                                        List<int> extra = const []}) async {
    final shared = await _x.sharedSecretKey(keyPair: mine, remotePublicKey: theirs);
    return cg.SecretKey(_hkdf(Uint8List.fromList(await shared.extractBytes()),
        [...utf8.encode(label), ...ephPub, ...ownerPub, ...extra], 32));
  }

  /// Zapieczętowanie dowolnych bajtów do klucza publicznego odbiorcy. Ta sama koperta co przy
  /// kluczu pliku — efemeryczna para, wspólny sekret, AES-GCM — więc jest jedna implementacja
  /// i jeden test zgodności, a nie dwie rozjeżdżające się przez rok.
  static Future<String> sealTo(cg.SimplePublicKey theirPub, Uint8List data,
                               {required String label, List<int> extra = const []}) async {
    final eph = await _x.newKeyPair();
    final ephPub = await eph.extractPublicKey();
    final key = await _wrapKey(eph, theirPub, ephPub.bytes, theirPub.bytes,
                               label: label, extra: extra);
    final nonce = randomBytes(nonceLen);
    final box = await _aes.encrypt(data, secretKey: key, nonce: nonce);
    return base64Encode([...ephPub.bytes, ...nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  /// Otwarcie paczki z [sealTo] — używa tego strona odbierająca (klient na komputerze).
  static Future<Uint8List> openSealed(String sealed, cg.SimpleKeyPair mine,
                                      {required String label, List<int> extra = const []}) async {
    final b = base64Decode(sealed);
    if (b.length < 32 + nonceLen + tag) throw const FormatException('sealed payload too short');
    final ephPub = cg.SimplePublicKey(b.sublist(0, 32), type: cg.KeyPairType.x25519);
    final myPub = await mine.extractPublicKey();
    final key = await _wrapKey(mine, ephPub, ephPub.bytes, myPub.bytes, label: label, extra: extra);
    final sb = cg.SecretBox(b.sublist(32 + nonceLen, b.length - tag),
        nonce: b.sublist(32, 32 + nonceLen), mac: cg.Mac(b.sublist(b.length - tag)));
    return Uint8List.fromList(await _aes.decrypt(sb, secretKey: key));
  }

  // ── katalogi ──
  //
  // Katalog NIE jest już przedrostkiem w nazwie pliku. Jedzie osobno, w dwóch postaciach:
  // odcisk do grupowania po stronie serwera i szyfrogram do pokazania człowiekowi.
  //
  // Klucz katalogów jest WSPÓLNY dla konta, a nie per plik — inaczej narysowanie drzewa
  // wymagałoby pobrania po jednym pliku z każdego katalogu tylko po to, żeby poznać jego nazwę.

  static Uint8List _folderKey(Uint8List boxSeed) =>
      _hkdf(boxSeed, utf8.encode('sensmos:store:folder:v1'), 32);

  /// Odcisk ścieżki. Serwer grupuje po nim pliki i liczy je, ale nazwy z niego nie wyprowadzi —
  /// klucz zna wyłącznie właściciel. Puste = korzeń.
  static String folderHash(Uint8List boxSeed, String path) {
    if (path.isEmpty) return '';
    final k = _hkdf(boxSeed, utf8.encode('sensmos:store:folderid:v1'), 32);
    return Hmac(sha256, k)
        .convert(utf8.encode(path))
        .bytes
        .sublist(0, 16)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static String encryptFolder(Uint8List boxSeed, String path) => path.isEmpty
      ? ''
      : seal(_folderKey(boxSeed), Uint8List.fromList(utf8.encode(path)), aad: 'folder');

  static String decryptFolder(Uint8List boxSeed, String? enc) {
    if (enc == null || enc.isEmpty) return '';
    try {
      return utf8.decode(open(_folderKey(boxSeed), enc, aad: 'folder'));
    } catch (_) {
      return '?';
    }
  }

  /// Nazwa idzie kluczem PLIKU, nie skrzynką: kto potrafi zapakować klucz pliku, musi umieć też
  /// zapisać nazwę, inaczej archiwizator wgrywałby pliki bez nazw.
  static String encryptName(Uint8List dek, String name) =>
      seal(dek, Uint8List.fromList(utf8.encode(name)), aad: 'name');
  static String decryptName(Uint8List dek, String? enc) {
    if (enc == null || enc.isEmpty) return '';
    try { return utf8.decode(open(dek, enc, aad: 'name')); } catch (_) { return '?'; }
  }

  // ── strumień pliku ──
  static int cipherSize(int plain) => plain <= 0 ? saltLen : saltLen + plain + tag * ((plain + chunk - 1) ~/ chunk);

  static Uint8List _nonce(Uint8List salt, int idx) {
    final n = Uint8List(nonceLen)..setRange(0, saltLen, salt);
    ByteData.view(n.buffer).setUint32(saltLen, idx);
    return n;
  }
  static Uint8List _aad(int idx) => Uint8List(4)..buffer.asByteData().setUint32(0, idx);

  static final _aes = cg.AesGcm.with256bits(nonceLength: nonceLen);

  /// Szyfruje plik spod `srcPath` do pliku tymczasowego. Zwraca (ścieżka szyfrogramu, skróty
  /// bloków 10 MiB hex). Dwa przebiegi: najpierw szyfr na dysk, potem skróty — bo `put` musi
  /// znać skróty ZANIM wyśle pierwszy bajt, a plik może być większy niż pamięć telefonu.
  ///
  /// Pracuje na ŚCIEŻKACH, nie na strumieniach, żeby dało się ją odpalić w `Isolate.run`.
  static Future<(String, List<String>, String)> encryptPathToTemp(String srcPath, Uint8List dek) async {
    final dir = await Directory.systemTemp.createTemp('sensmos-store-');
    final out = File('${dir.path}/enc.bin');
    final sink = out.openWrite();
    final salt = randomBytes(saltLen);
    sink.add(salt);
    final key = cg.SecretKey(dek);
    final src = await File(srcPath).open();
    var idx = 0;
    try {
      final total = await src.length();
      for (var off = 0; off < total; off += chunk) {
        final plain = await src.read(min(chunk, total - off));
        final box = await _aes.encrypt(plain, secretKey: key, nonce: _nonce(salt, idx), aad: _aad(idx));
        sink.add(box.cipherText);
        sink.add(box.mac.bytes);
        idx++;
      }
    } finally { await src.close(); }
    await sink.close();
    final (blocks, digest) = await blockHashes(out);
    return (out.path, blocks, digest);
  }

  /// Izolat Z TEGO miejsca, nie z ekranu: domknięcie utworzone w metodzie State łapie `this`
  /// (State jest nieprzesyłalny → „object is unsendable"). Natywne AES idzie kanałem do
  /// platformy, a kanał w izolacie tła trzeba najpierw zarejestrować tokenem izolatu głównego.
  static Future<(String, List<String>, String)> encryptInIsolate(String srcPath, Uint8List dek) {
    final token = RootIsolateToken.instance!;
    return Isolate.run(() { _initIsolate(token); return encryptPathToTemp(srcPath, dek); });
  }
  static Future<Uint8List> decryptInIsolate(String encPath, Uint8List dek) {
    final token = RootIsolateToken.instance!;
    return Isolate.run(() { _initIsolate(token); return decryptPath(encPath, dek); });
  }

  /// Nazwy CAŁEJ listy naraz, w izolacie tła.
  ///
  /// Sto plików to sto wymian kluczy. Na wątku interfejsu kosztuje to nie tylko zamrożony ekran:
  /// odpowiedzi HTTP czekają w tej samej kolejce zdarzeń, więc `timeout` na zapytaniu do serwera
  /// wybucha mimo natychmiastowej odpowiedzi. Dlatego cała pętla idzie obok.
  ///
  /// Wejście to pary `(wrapped_key, name_enc)`; wyjście — nazwy w tej samej kolejności, a pusty
  /// napis tam, gdzie klucz nie pasuje. Ziarno skrzynki przesyłamy zamiast pary kluczy, bo
  /// `SimpleKeyPair` nie przechodzi przez granicę izolatu.
  static Future<List<String>> namesInIsolate(
      Uint8List boxSeed, List<(String, String?)> pary) {
    final token = RootIsolateToken.instance!;
    return Isolate.run(() async {
      _initIsolate(token);
      final box = await boxFromSeed(boxSeed);
      final out = <String>[];
      for (final (wrapped, nameEnc) in pary) {
        try {
          out.add(decryptName(await unwrapDek(wrapped, box), nameEnc));
        } catch (_) {
          out.add('');
        }
      }
      return out;
    });
  }
  static void _initIsolate(RootIsolateToken token) {
    // Kanały platformy w izolacie. `FlutterCryptography.enable()` bylo tu wczesniej i zniklo:
    // wtyczka sama sie rejestruje (jej wlasna deprecjacja tak mowi), a import wiazal ten pakiet
    // z platformami mobilnymi — czego klient na Windows nie przeszedl.
    BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  }

  /// Skróty bloków 10 MiB (dowody backendu) ORAZ skrót całego szyfrogramu — jednym przebiegiem,
  /// bo drugi oznaczałby ponowne przeczytanie kilku GB z pamięci telefonu. Skrót całości idzie do
  /// rekordu `.meta` u sprzedawcy: pozwala sprawdzić plik bez składania listy bloków.
  /// Strumieniowo z `package:crypto` — `cg.Sha256().newHashSink()` zbiera CAŁY plik w RAM.
  static Future<(List<String>, String)> blockHashes(File f) async {
    final raf = await f.open();
    final out = <String>[];
    final h = cg.Sha256();
    final acc = _DigestSink();
    final whole = sha256.startChunkedConversion(acc);
    try {
      final total = await raf.length();
      for (var off = 0; off < total; off += block) {
        await raf.setPosition(off);
        final chunk = await raf.read(min(block, total - off));
        whole.add(chunk);
        final d = await h.hash(chunk);
        out.add(d.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join());
      }
    } finally { await raf.close(); }
    whole.close();
    return (out, acc.value!.toString());
  }

  /// Odszyfrowuje plik szyfrogramu do pamięci (pobieranie na telefon — limit rozmiaru pilnuje
  /// ekran). Zły tag = wyjątek, nigdy cicho zepsute dane. Też do `Isolate.run`.
  static Future<Uint8List> decryptPath(String encPath, Uint8List dek) async {
    final data = await File(encPath).readAsBytes();
    if (data.length < saltLen) throw const FormatException('too short');
    final salt = Uint8List.sublistView(data, 0, saltLen);
    final key = cg.SecretKey(dek);
    final out = BytesBuilder(copy: false);
    var off = saltLen, idx = 0;
    while (off < data.length) {
      final n = min(frame, data.length - off);
      if (n <= tag) throw const FormatException('truncated frame');
      final box = cg.SecretBox(Uint8List.sublistView(data, off, off + n - tag),
          nonce: _nonce(salt, idx), mac: cg.Mac(Uint8List.sublistView(data, off + n - tag, off + n)));
      out.add(await _aes.decrypt(box, secretKey: key, aad: _aad(idx)));
      off += n; idx++;
    }
    return out.takeBytes();
  }

  // ── rekord `.meta` u sprzedawcy ──
  //
  // Sprzedawca trzymał do tej pory sam szyfrogram pod nazwą = object_id i nie wiedział o nim NIC.
  // Wszystko inne (klucz, nazwa, skróty, właściciel) leżało wyłącznie w bazie BE, więc jej utrata
  // znaczyła utratę plików mimo żywych bajtów na cudzych dyskach. Od teraz obok każdego bloba
  // ląduje rekord z kompletem — i jedzie razem z bajtami przy replikacji, więc nie ma jak się
  // zestarzeć. Format musi być dobry za pierwszym razem: skryptu, który ktoś raz uruchomił
  // i zapomniał, nie poprawimy nigdy.

  /// Identyfikator obiektu nadaje TELEFON, nie serwer — inaczej nie dałoby się go objąć podpisem
  /// (podpis powstaje przed wysłaniem `put`, a serwer zwracał id dopiero w odpowiedzi). Kolizji
  /// pilnuje klucz główny `store_objects.id` po stronie BE.
  static String newObjectId() =>
      randomBytes(12).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Skrót adresu, nie adres: sprzedawca potwierdzi „mam pliki tego, kto poda ten adres", ale nie
  /// zbuduje sobie listy klientów ani nie sprawdzi w eksploratorze, ile kto ma GALU.
  static String ownerHash(String address) =>
      sha256.convert(utf8.encode(address.toLowerCase())).toString();

  /// Podpisywana treść rekordu. Rozdzielana `|`, nie JSON-em: kolejność kluczy w JSON-ie zależy od
  /// implementacji, a ten sam ciąg musi odtworzyć bajt w bajt Python agenta i Node backendu.
  /// Żadne z pól nie zawiera `|` (hex, base64, liczby, czas ISO).
  static String metaPayload({
    required int v, required String oid, required String owner, required int size,
    required String sha256hex, required List<String> blocks, required String createdAt,
    required String wrappedKey, required String nameEnc,
  }) => ['sensmos:store:meta:v$v', oid, owner, '$size', sha256hex,
         blocks.join(','), createdAt, wrappedKey, nameEnc].join('|');
}

/// Odbiornik jednego skrótu dla `startChunkedConversion` — żeby nie ciągnąć `package:convert`
/// tylko dla `AccumulatorSink`.
class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override void add(Digest d) => value = d;
  @override void close() {}
}
