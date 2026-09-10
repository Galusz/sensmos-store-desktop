import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as cg;
import 'package:http/http.dart' as http;
import 'package:sensmos_store/sensmos_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'i18n.dart';

/// Parowanie z kontem — strona komputera.
///
/// Losujemy kod i efemeryczną parę kluczy, pokazujemy kod człowiekowi i czekamy. Telefon
/// odczytuje z serwera nasz klucz publiczny, wydaje token i odkłada go ZAPIECZĘTOWANY. Serwer
/// widzi tylko skrót kodu i nie ma czym paczki otworzyć.
class Pairing {
  static const be = 'https://sensmos.com';
  static const _label = 'sensmos:pair:v1';

  /// Bez znaków, które ludzie mylą przy przepisywaniu: zero i O, jedynka oraz I i L.
  static const alphabet = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  static const _len = 12;

  final String code;
  final cg.SimpleKeyPair _eph;
  Pairing._(this.code, this._eph);

  static Future<Pairing> start() async {
    final r = Random.secure();
    final code = List.generate(_len, (_) => alphabet[r.nextInt(alphabet.length)]).join();
    return Pairing._(code, await cg.X25519().newKeyPair());
  }

  /// Kod pokazywany człowiekowi — w grupach po cztery, żeby dało się go przepisać bez pomyłki.
  String get pretty {
    final g = <String>[];
    for (var i = 0; i < code.length; i += 4) {
      g.add(code.substring(i, i + 4 > code.length ? code.length : i + 4));
    }
    return g.join('-');
  }

  String get rendezvous =>
      sha256.convert(utf8.encode('sensmos:pair:$code')).toString().substring(0, 32);

  /// Zgłasza się serwerowi i czeka, aż telefon odłoży paczkę. Zwraca odczytaną zawartość.
  Future<Map<String, dynamic>> waitForPhone({
    required String deviceName,
    Duration timeout = const Duration(minutes: 3),
  }) async {
    final pub = await _eph.extractPublicKey();
    final offer = await http.post(Uri.parse('$be/v1/pair/offer'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'rendezvous': rendezvous, 'name': deviceName,
                          'pub': StoreCrypto.pubHex(pub),
                          // Prosimy DOKLADNIE o to, czego ten program uzywa. Telefon pokaze
                          // wylacznie te pozycje — nie ma jak zaznaczyc tuneli „na wszelki
                          // wypadek", bo nikt o nie nie poprosil.
                          //
                          // `token.issue` to prawo wpuszczenia na konto KOLEJNEGO komputera bez
                          // siegania po telefon. Prosimy, nie bierzemy: na telefonie sa to dwie
                          // osobne pozycje i mozna dac same pliki. Bez tego zakresu ekran
                          // „Sparuj kolejny komputer" po prostu sie nie pokazuje.
                          'want': const ['store.use', 'token.issue']}));
    final o = jsonDecode(offer.body) as Map<String, dynamic>;
    if (o['ok'] != true) throw Exception(o['error'] ?? t('pair.refused'));

    final koniec = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(koniec)) {
      await Future.delayed(const Duration(seconds: 2));
      final r = await http.get(Uri.parse('$be/v1/pair/claim/$rendezvous'));
      final m = jsonDecode(r.body) as Map<String, dynamic>;
      if (m['waiting'] == true) continue;
      if (m['ok'] != true) throw Exception(m['error'] ?? t('pair.expired'));
      final jawne = await StoreCrypto.openSealed(m['blob'] as String, _eph,
          label: _label, extra: utf8.encode(code));
      return jsonDecode(utf8.decode(jawne)) as Map<String, dynamic>;
    }
    throw Exception(t('pair.timeout'));
  }

  // ── to, co zostaje po sparowaniu ───────────────────────────────────────────
  static const _slot = 'sensmos_pairing';

  static Future<void> save(Map<String, dynamic> p) async =>
      (await SharedPreferences.getInstance()).setString(_slot, jsonEncode(p));

  static Future<Map<String, dynamic>?> load() async {
    final s = (await SharedPreferences.getInstance()).getString(_slot);
    if (s == null) return null;
    try { return jsonDecode(s) as Map<String, dynamic>; } catch (_) { return null; }
  }

  static Future<void> forget() async =>
      (await SharedPreferences.getInstance()).remove(_slot);
}

/// Parowanie KOLEJNEGO komputera — strona tego, który już siedzi na koncie.
///
/// Robi dokładnie to samo, co telefon: sprawdza, kto czeka pod kodem, wydaje token i odkłada go
/// zapieczętowanego kluczem publicznym tamtego komputera. Różnica jest jedna — portfela tu nie ma,
/// więc żądanie wydania tokenu uwierzytelnia nasz własny token.
///
/// Backend przepuszcza to wyłącznie z zakresem `token.issue`, przycina potomka do tego, co sami
/// mamy, i ODBIERA mu prawo parowania dalej. Łańcuch ma więc zawsze jedno ogniwo: telefon →
/// komputer. Odwołanie naszego tokenu z telefonu kasuje kaskadą wszystko, co tędy wydaliśmy.
class DalszeParowanie {
  /// Postać kanoniczna kodu — spacje, myślniki i wielkość liter nie mogą decydować o tym,
  /// czy parowanie się uda.
  static String normalizuj(String kod) =>
      kod.toUpperCase().split('').where(Pairing.alphabet.contains).join();

  static String _rv(String kod) => sha256
      .convert(utf8.encode('sensmos:pair:${normalizuj(kod)}'))
      .toString()
      .substring(0, 32);

  /// Czy ten komputer w ogóle może parować kolejne.
  static bool wolno(Map<String, dynamic> moje) =>
      ((moje['scopes'] as List?) ?? const []).map((e) => '$e').contains('token.issue');

  /// Opisy uprawnień bierzemy z serwera, żeby ekran nie trzymał własnej kopii listy
  /// i nie rozjechał się z tym, co backend naprawdę honoruje.
  static Future<Map<String, String>> opisy(String be) async {
    try {
      final r = await http.get(Uri.parse('$be/v1/nodes/owner-token/scopes'))
          .timeout(const Duration(seconds: 10));
      final m = (jsonDecode(r.body) as Map<String, dynamic>)['scopes'] as Map<String, dynamic>;
      return m.map((k, v) => MapEntry(k, '$v'));
    } catch (_) {
      return const {};   // bez opisów da się żyć, przy zaznaczaniu liczy się klucz
    }
  }

  /// Kto czeka pod tym kodem: `{name, pub, want}`.
  static Future<Map<String, dynamic>> ktoCzeka(String be, String kod) async {
    final r = await http.get(Uri.parse('$be/v1/pair/${_rv(kod)}'))
        .timeout(const Duration(seconds: 12));
    final m = jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode != 200 || m['ok'] != true) {
      throw Exception(m['error'] ?? t('pair.expired'));
    }
    return m;
  }

  /// Wydaje token potomny i odkłada paczkę dla tamtego komputera.
  ///
  /// `czytaPliki` dokłada ziarno skrzynki, czyli prawo ODCZYTU. Przekazać je możemy tylko wtedy,
  /// gdy sami je mamy — komputer wpuszczony bez prawa odczytu nie ma czego oddać.
  static Future<void> sparuj({
    required Map<String, dynamic> moje,
    required String kod,
    required List<String> zakresy,
    required bool czytaPliki,
    required String nazwa,
  }) async {
    final be = '${moje['be'] ?? Pairing.be}';
    final info = await ktoCzeka(be, kod);

    final res = await http.post(
      Uri.parse('$be/v1/nodes/owner-token'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'owner_token': moje['token'], 'label': nazwa,
                        'scopes': [...zakresy]..sort()}),
    ).timeout(const Duration(seconds: 15));
    final tok = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200 || tok['token'] == null) {
      throw Exception(tok['error'] ?? t('pair2.noToken'));
    }

    // Publiczna połowa skrzynki jedzie ZAWSZE — bez niej tamten komputer nie ma czym zaszyfrować
    // wysyłki, nawet jeśli nie wolno mu niczego odczytać. Pisać można kluczem publicznym, czytać
    // dopiero prywatnym; to jest cały sens przełącznika „może czytać pliki".
    final ziarno = moje['box_seed'];
    var pub = '${moje['box_pub'] ?? ''}';
    if (pub.isEmpty && ziarno is String && ziarno.isNotEmpty) {
      final kp = await StoreCrypto.boxFromSeed(Box._bytes(ziarno));
      pub = StoreCrypto.pubHex(await kp.extractPublicKey());
    }
    if (pub.isEmpty) throw Exception(t('pair2.noBox'));

    final paczka = <String, dynamic>{
      'be': be,
      'owner': moje['owner'],
      'token': tok['token'],
      'scopes': tok['scopes'] ?? zakresy,
      'box_pub': pub,
    };
    if (czytaPliki && ziarno is String && ziarno.isNotEmpty) paczka['box_seed'] = ziarno;

    final sealed = await StoreCrypto.sealTo(
      StoreCrypto.pubFromHex(info['pub'] as String),
      Uint8List.fromList(utf8.encode(jsonEncode(paczka))),
      label: Pairing._label,
      extra: utf8.encode(normalizuj(kod)),
    );

    final put = await http.post(Uri.parse('$be/v1/pair/seal'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'rendezvous': _rv(kod), 'blob': sealed}))
        .timeout(const Duration(seconds: 15));
    final done = jsonDecode(put.body) as Map<String, dynamic>;
    if (put.statusCode != 200 || done['ok'] != true) {
      throw Exception(done['error'] ?? t('pair2.noHandover'));
    }
  }
}

/// Skrzynka właściciela po stronie komputera.
///
/// Bez `box_seed` mamy wyłącznie publiczną połowę: da się WYSŁAĆ plik (klucz pliku pakujemy do
/// skrzynki właściciela), ale nie da się odczytać ani jednej nazwy — nawet własnej wysyłki po
/// restarcie. To nie brak, tylko sens przełącznika „może czytać pliki".
class Box {
  final cg.SimplePublicKey pub;
  final cg.SimpleKeyPair? priv;
  /// To samo ziarno, z ktorego powstal klucz — potrzebne do odcisku i nazwy katalogu, ktore sa
  /// wspolne dla konta, a nie zwiazane z zadnym pojedynczym plikiem.
  final Uint8List? seed;
  Box(this.pub, this.priv, [this.seed]);
  bool get canRead => priv != null;

  static Future<Box> from(Map<String, dynamic> pairing) async {
    final seed = pairing['box_seed'] as String?;
    if (seed != null && seed.isNotEmpty) {
      // ZIARNO, nie podpis: `boxKeyPair` policzylby ziarno jeszcze raz i klucz by sie nie zgadzal.
      final bajty = _bytes(seed);
      final kp = await StoreCrypto.boxFromSeed(bajty);
      return Box(await kp.extractPublicKey(), kp, bajty);
    }
    return Box(StoreCrypto.pubFromHex(pairing['box_pub'] as String), null);
  }

  static Uint8List _bytes(String h) => Uint8List.fromList(
      List.generate(h.length ~/ 2, (i) => int.parse(h.substring(2 * i, 2 * i + 2), radix: 16)));
}
