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
                          'want': const ['store.use']}));
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
