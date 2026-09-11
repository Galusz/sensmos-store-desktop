// Wysylka nie moze zagluszać sterowania.
//
// Gniazdo do serwera jest jedno: ida nim i komendy, i bajty plikow. Dopoki caly plik szedl
// jednym `addStream`, Dart odrzucal kazda komende wyslana w trakcie („StreamSink is bound to
// a stream"), a `catch (_) {}` w kliencie to ukrywal — wiec „odswiez" w trakcie wysylki
// konczylo sie minuta ciszy i `TimeoutException: list`. Ten test pilnuje, zeby nie wrocilo.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sensmos_store/sensmos_store.dart';

/// Backend na tyle prawdziwy, na ile trzeba: przyjmuje auth, wysylke i liste.
class _Backend {
  late HttpServer serwer;
  WebSocket? gniazdo;
  final ramki = <int>[];
  final komendy = <String>[];
  Completer<void>? _putPrzyjety;

  int get port => serwer.port;

  Future<void> start() async {
    serwer = await HttpServer.bind('127.0.0.1', 0);
    serwer.listen((req) async {
      final ws = await WebSocketTransformer.upgrade(req);
      gniazdo = ws;
      ws.listen((d) {
        if (d is! String) { ramki.add((d as List<int>).length); return; }
        final m = jsonDecode(d) as Map<String, dynamic>;
        final t = '${m['type']}';
        komendy.add(t);
        switch (t) {
          case 'auth':
            ws.add(jsonEncode({'type': 'auth', 'ok': true, 'device_id': 'de' * 16}));
            break;
          case 'listen':
            ws.add(jsonEncode({'type': 'listen', 'ok': false}));
            break;
          case 'put':
            ws.add(jsonEncode({'type': 'put', 'ok': true, 'sid': 1, 'object_id': m['object_id']}));
            _putPrzyjety?.complete();
            break;
          case 'put_end':
            ws.add(jsonEncode({'type': 'put_state', 'sid': 1, 'st': 'ok', 'copies': 2}));
            break;
          case 'list':
            ws.add(jsonEncode({'type': 'list', 'items': [], 'used_b': 0, 'limit_b': 0,
                               'daily': 0, 'sellers': []}));
            break;
        }
      });
    });
  }

  Future<void> czekajNaPut() { _putPrzyjety = Completer<void>(); return _putPrzyjety!.future; }
  Future<void> stop() async { await gniazdo?.close(); await serwer.close(force: true); }
}

void main() {
  test('komenda wyslana w trakcie wysylki dociera i wraca', () async {
    final be = _Backend();
    await be.start();

    final katalog = await Directory.systemTemp.createTemp('sensmos-test-');
    final plik = File('${katalog.path}${Platform.pathSeparator}duzy.bin');
    await plik.writeAsBytes(List<int>.filled(6 * 1024 * 1024, 7));   // 6 odcinkow po 1 MiB

    final relay = StoreRelay.paired(
      owner: '0x${'a' * 40}', beUrl: 'http://127.0.0.1:${be.port}', token: 'smt_test');
    await relay.connect();

    // wysylka startuje i leci w tle
    final wysylka = relay.put(
      cipher: plik, size: await plik.length(),
      blocks: ['0' * 64], sha256hex: '0' * 64,
      wrappedKey: 'x', nameEnc: 'y');

    await be.czekajNaPut();                       // serwer przyjal `put`, lecą bajty
    final lista = await relay.list().timeout(const Duration(seconds: 10));

    expect(lista['type'], 'list', reason: 'lista musi wrocic W TRAKCIE wysylki');
    expect(be.komendy.contains('list'), isTrue, reason: 'komenda musi dojsc do serwera');

    await wysylka.timeout(const Duration(seconds: 30));
    // kazda ramka niesie 2 bajty naglowka [sid], wiec dane to reszta
    final dane = be.ramki.fold<int>(0, (a, b) => a + b) - 2 * be.ramki.length;
    expect(dane, 6 * 1024 * 1024,
        reason: 'wszystkie bajty pliku musza dojsc mimo komend w trakcie');

    relay.dispose();
    await be.stop();
    await katalog.delete(recursive: true);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('po zerwaniu lacza komenda wraca bledem od razu, nie po minucie', () async {
    final be = _Backend();
    await be.start();
    final relay = StoreRelay.paired(
      owner: '0x${'b' * 40}', beUrl: 'http://127.0.0.1:${be.port}', token: 'smt_test');
    await relay.connect();
    expect(relay.zywe, isTrue);

    final zerwane = relay.events.firstWhere((e) => e.startsWith('down:'));
    await be.stop();                              // serwer znika spod nog
    await zerwane.timeout(const Duration(seconds: 10));

    expect(relay.zywe, isFalse, reason: 'klient ma WIEDZIEC, ze lacza nie ma');
    final zegar = Stopwatch()..start();
    await expectLater(relay.list(), throwsA(isA<Object>()));
    zegar.stop();
    expect(zegar.elapsed.inSeconds, lessThan(5),
        reason: 'blad ma wrocic od razu, a nie po 60 s ciszy');

    relay.dispose();
  }, timeout: const Timeout(Duration(seconds: 60)));
}
