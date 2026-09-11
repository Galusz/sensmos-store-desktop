import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'store_crypto.dart';
import 'upnp.dart';

/// Dziennik pakietu. Apka podpina tu swój logger, klient na komputerze — swój; bez podpięcia
/// pakiet milczy. Dzięki temu ten sam kod działa w obu miejscach, nie znając żadnego z nich.
void Function(String poziom, String tag, String tresc)? storeLog;
void _log(String poziom, String tresc) => storeLog?.call(poziom, 'store', tresc);

/// Klient Store dla kupującego: WS /v1/store, ślepa rura jak terminal (terminal_relay.dart).
/// Uwierzytelnienie podpisem portfela nad `sensmos:store:<ts>`; sterowanie JSON-em, dane ramką
/// binarną [sid u16][bajty]. Serwer nie zna klucza — dostaje i oddaje szyfrogram.
///
/// Wysyłka idzie przez `sink.addStream`, bo tylko tak gniazdo dart:io przenosi backpressure
/// z TCP na nasz strumień: plik większy niż RAM telefonu nie zbiera się w buforze.
/// Rzucane, gdy człowiek PRZERWAŁ wysyłkę.
///
/// Osobny typ, bo przerwania nie wolno pomylić z awarią: gdy trasa bezpośrednia się wywali,
/// powtarzamy przez serwer — a wysyłki, z której ktoś świadomie zrezygnował, powtarzać nie ma po co.
class UploadCancelled implements Exception {
  const UploadCancelled();
  @override
  String toString() => 'upload cancelled';
}

class StoreRelay {
  final String owner;                                       // lower-case, tak porównuje BE
  final Future<String> Function(String message) signMessage;
  /// Publiczna połowa skrzynki właściciela. Serwer ją zapamiętuje, żeby archiwizator pomiarów
  /// mógł dokładać pliki do tego pakietu, nie mając czym odczytać czegokolwiek.
  final String boxPub;
  /// Adres backendu podaje ten, kto tworzy klienta — pakiet nie zna konfiguracji aplikacji.
  final String beUrl;
  /// Token sparowanego urzadzenia. Telefon ma portfel i podpisuje sie sam; komputer portfela nie
  /// ma i miec nie powinien, wiec wchodzi tokenem o zakresie `store.use`. Jedna klasa, dwa
  /// sposoby wejscia — bo poza logowaniem wszystko jest identyczne.
  final String? token;

  StoreRelay({required String owner, required this.signMessage, required this.boxPub,
              required this.beUrl, this.token})
      : owner = owner.toLowerCase();

  /// Klient sparowanego urzadzenia: bez portfela, bez podpisywania rekordow (robi to backend).
  StoreRelay.paired({required String owner, required this.beUrl, required String this.token})
      : owner = owner.toLowerCase(),
        boxPub = '',
        signMessage = _bezPortfela;

  static Future<String> _bezPortfela(String _) =>
      throw StateError('to urzadzenie nie ma portfela — rekordy podpisuje backend');

  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  final _waiting = <String, Completer<Map<String, dynamic>>>{};   // typ odpowiedzi → oczekujący
  IOSink? _getSink; int _getSid = -1, _getBytes = 0;
  void Function(int)? _getProgress;
  Completer<Map<String, dynamic>>? _getDone;
  final _events = StreamController<String>.broadcast();
  Stream<String> get events => _events.stream;

  /// Nasłuch dla transferów bezpośrednich. Serwer wybiera trasę, ale jeśli to sprzedawca ma
  /// zadzwonić do nas, musimy mieć gdzie odebrać. Port efemeryczny — nikt go nie konfiguruje,
  /// a BE i tak sprawdza sondą, czy da się tu dodzwonić.
  ServerSocket? _srv;
  String? _probe;                                   // baner, którego oczekuje sonda BE
  final _grants = <String, _Grant>{};
  Timer? _upnpTimer;
  /// Stały port dla transferów bezpośrednich (agent Store słucha na 9033).
  static const int directPort = 9034;
  /// Trasa ostatniego transferu — 'direct' albo 'relay'. Do pokazania w apce.
  String lastRoute = '';

  /// Ustawiane przez `przerwijWysylke()`, sprawdzane MIĘDZY porcjami bajtów. Nie przerywamy
  /// w środku porcji — chodzi o to, żeby przestać wysyłać, a nie żeby zostawić urwany kadłubek.
  bool _przerwane = false;

  /// „Zatrzymaj" przy wysyłce. Działa na obu trasach: przez serwer i wprost do sprzedawcy.
  /// Po przerwaniu mówimy o tym backendowi, żeby sprzątnął wpis i oddał miejsce w pakiecie.
  void przerwijWysylke() => _przerwane = true;

  String get _wsUrl => '${beUrl.replaceFirst('https://', 'wss://').replaceFirst('http://', 'ws://')}/v1/store';

  Future<void> connect() async {
    _ch = WebSocketChannel.connect(Uri.parse(_wsUrl));
    _sub = _ch!.stream.listen(_onMessage, onError: (e) => _fail('$e'), onDone: () => _fail('connection closed'));
    Map<String, dynamic> r;
    if (token != null) {
      r = await _ask('auth', {'type': 'auth', 'token': token});
    } else {
      final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final sig = await signMessage('sensmos:store:$ts');
      r = await _ask('auth', {'type': 'auth', 'owner': owner, 'ts': ts, 'sig': sig, 'box_pub': boxPub});
    }
    if (r['ok'] != true) throw Exception(r['error'] ?? 'auth denied');
  }

  /// addGb > 0 dokup, < 0 zmniejszenie, 0 = wykup/odczyt pakietu.
  /// gb = rozmiar przy zakładaniu pakietu (kupujący wybiera go suwakiem, nie zaczyna od 1 GB).
  Future<Map<String, dynamic>> package({int addGb = 0, int gb = 0, int copies = 0}) =>
      _ask('package', {'type': 'package', if (addGb != 0) 'add_gb': addGb, if (gb > 0) 'gb': gb,
                       if (copies > 0) 'copies': copies});
  /// Jedna STRONA jednego katalogu, nie cała zawartość konta.
  ///
  /// `folderH` null = wszystkie pliki, '' = korzeń, inaczej konkretny katalog. Odpowiedź niesie
  /// też drzewo katalogów (`folders`), żeby dało się je narysować bez pobierania czegokolwiek
  /// poza bieżącą stroną — wcześniej trzeba było ściągnąć wszystko i odszyfrować każdą nazwę.
  Future<Map<String, dynamic>> list({String? folderH, int offset = 0, int limit = 50,
                                     bool tree = true}) =>
      _ask('list', {
        'type': 'list',
        if (folderH != null) 'folder_h': folderH,
        'offset': offset, 'limit': limit, 'tree': tree,
      });

  /// Dopisanie katalogu do pliku, który już leży. Nazwy ani podpisu nie rusza — te dwa pola są
  /// wyłącznie indeksem po stronie serwera.
  Future<Map<String, dynamic>> setFolder(String id, String folderH, String folderEnc) =>
      _ask('setfolder', {'type': 'setfolder', 'object_id': id,
                         'folder_h': folderH, 'folder_enc': folderEnc});
  /// Archiwum pomiarów: bez `on` = odczyt stanu, z `on` = przestawienie.
  Future<Map<String, dynamic>> archive({bool? on}) =>
      _ask('archive', {'type': 'archive', if (on != null) 'on': on});
  Future<Map<String, dynamic>> del(String id) => _ask('del', {'type': 'del', 'object_id': id});
  Future<Map<String, dynamic>> close() => _ask('close', {'type': 'close'});

  /// Wysyłka: `put` z metadanymi, potem ramki z pliku szyfrogramu, `put_end`, czekamy na `put_state`.
  ///
  /// Metadane idą też na dysk sprzedawcy (rekord `.meta` obok bloba), więc telefon podpisuje je
  /// portfelem. Bez podpisu sprzedawca mógłby sfabrykować rekordy „trzymam pliki tego adresu"
  /// i — w chwili gdy baza BE stanie się odtwarzalna z agentów — kasować za nieistniejące dane.
  /// Kosztuje zero, bo przy wysyłce portfel i tak jest odblokowany (z jego podpisu wychodzi klucz).
  /// Skrótu adresu ani podpisu nie liczy tu nikt inny: BE odtwarza treść z własnych danych
  /// i sprawdza podpis, więc telefon nie ma jak podać cudzego właściciela.
  Future<Map<String, dynamic>> put({required File cipher, required int size, required List<String> blocks,
      required String sha256hex, required String wrappedKey, required String nameEnc,
      String folderH = '', String folderEnc = '',
      void Function(int sent)? onProgress}) async {
    const metaV = 1;
    _przerwane = false;
    final oid = StoreCrypto.newObjectId();
    final createdAt = DateTime.now().toUtc().toIso8601String();
    // Rekord podpisuje ten, kto ma czym: telefon portfelem, a za sparowane urzadzenie — backend.
    // Klucz portfela nie opuszcza telefonu, wiec innej mozliwosci nie ma i nie powinno byc.
    final sig = token != null ? '' : await signMessage(StoreCrypto.metaPayload(
        v: metaV, oid: oid, owner: StoreCrypto.ownerHash(owner), size: size, sha256hex: sha256hex,
        blocks: blocks, createdAt: createdAt, wrappedKey: wrappedKey, nameEnc: nameEnc));
    await _ensureListener();
    var r = await _ask('put', {'type': 'put', 'object_id': oid, 'size': size, 'blocks': blocks,
        'sha256': sha256hex, 'wrapped_key': wrappedKey, 'name_enc': nameEnc,
        'meta_v': metaV, 'created_at': createdAt, 'meta_sig': sig,
        // Katalog jedzie OBOK podpisanej nazwy, nie zamiast niej — inaczej podpis w `.meta`
        // przestałby się zgadzać z tym, co leży na hoście.
        'folder_h': folderH, 'folder_enc': folderEnc});
    if (r['ok'] != true) throw Exception(r['error'] ?? 'put refused');
    // Bajty bokiem, jeśli BE tak zdecydował. Nie udało się — powtarzamy żądanie z `no_direct`
    // i plik idzie przez serwer; kupujący nie ma z tego nic do wyboru i niczego nie zauważy.
    final dp = r['direct'] as Map?;
    if (dp != null) {
      _log('I', 'upload ${oid.substring(0, 8)} DIRECT — ' + _how(dp));
      final st = _expect('put_state');
      try {
        await _directSend(dp, cipher, size, onProgress);
        final s2 = await st.timeout(const Duration(minutes: 30));
        if (s2['st'] != 'ok') throw Exception(s2['msg'] ?? 'put failed');
        lastRoute = 'direct';
        _log('I', 'sent directly: $size B');
        return s2;
      } on UploadCancelled {
        await _zglosPrzerwanie(oid);
        rethrow;
      } catch (e) {
        _log('W', 'direct failed ($e) — retrying through the server');
        _events.add('direct-failed:$e');
        r = await _ask('put', {'type': 'put', 'object_id': oid, 'size': size, 'blocks': blocks,
            'sha256': sha256hex, 'wrapped_key': wrappedKey, 'name_enc': nameEnc,
            'meta_v': metaV, 'created_at': createdAt, 'meta_sig': sig, 'no_direct': true});
        if (r['ok'] != true) throw Exception(r['error'] ?? 'put refused');
      }
    }
    if (dp == null) _log('I', 'upload ${oid.substring(0, 8)} VIA SERVER — no direct route offered');
    lastRoute = 'relay';
    final sid = r['sid'] as int;
    var sent = 0;
    Stream<List<int>> frames() async* {
      await for (final part in cipher.openRead()) {
        if (_przerwane) throw const UploadCancelled();
        for (var off = 0; off < part.length; off += 256 * 1024) {
          final n = part.length - off < 256 * 1024 ? part.length - off : 256 * 1024;
          final f = Uint8List(2 + n)..buffer.asByteData().setUint16(0, sid);
          f.setRange(2, 2 + n, part, off);
          sent += n; onProgress?.call(sent);
          yield f;
        }
      }
    }
    final state = _expect('put_state');
    try {
      await _ch!.sink.addStream(frames());
    } on UploadCancelled {
      await _zglosPrzerwanie(oid);
      rethrow;
    }
    _send({'type': 'put_end', 'sid': sid});
    final st = await state.timeout(const Duration(minutes: 10));
    if (st['st'] != 'ok') throw Exception(st['msg'] ?? 'put failed');
    return st;
  }

  /// Pobranie szyfrogramu do pliku `out`. Zwraca metadane (rozmiar, klucz zapakowany, nazwa).
  Future<Map<String, dynamic>> get(String id, File out, {void Function(int got)? onProgress}) async {
    await _ensureListener();
    var r = await _ask('get', {'type': 'get', 'object_id': id});
    if (r['ok'] != true) throw Exception(r['error'] ?? 'get refused');
    final dg = r['direct'] as Map?;
    if (dg != null) {
      _log('I', 'download ${id.substring(0, 8)} DIRECT — ' + _how(dg));
      try {
        final n = await _directRecv(dg, out, onProgress);
        await _verify(out, r, id);
        lastRoute = 'direct';
        _log('I', 'downloaded directly: $n B, hashes match');
        return {...r, 'bytes': n};
      } catch (e) {
        _log('W', 'direct failed ($e) — retrying through the server');
        _events.add('direct-failed:$e');
        r = await _ask('get', {'type': 'get', 'object_id': id, 'no_direct': true});
        if (r['ok'] != true) throw Exception(r['error'] ?? 'get refused');
      }
    } else {
      _log('I', 'download ${id.substring(0, 8)} VIA SERVER — no direct route offered');
    }
    lastRoute = 'relay';
    _getSid = r['sid'] as int; _getBytes = 0; _getProgress = onProgress;
    _getSink = out.openWrite();
    _getDone = Completer();
    final end = await _getDone!.future.timeout(const Duration(minutes: 10));
    await _getSink?.close(); _getSink = null; _getSid = -1;
    if (end['error'] != null) throw Exception(end['error']);
    await _verify(out, r, id);
    _log('I', 'downloaded via server: $_getBytes B, hashes match');
    return {...r, 'bytes': _getBytes};
  }

  /// Kto do kogo dzwoni. Bez tego „bezpośrednio" w logu nie mówi, KTÓRA z dwóch dróg zadziałała,
  /// a to jedyna rzecz różniąca hosta z otwartym portem od telefonu z otwartym portem.
  String _how(Map d) => d['route'] == 'seller'
      ? 'we call the seller ${d['host']}:${d['port']}'
      : 'the seller will call us';

  /// Odebrany szyfrogram przeciw hashom, które ten telefon policzył i podpisał przy wysyłce.
  /// Ta sama funkcja licząca, co przy pakowaniu — jedna implementacja, nie druga obok.
  /// Niezgodność to nie „uszkodzony plik u mnie": to konkretny host oddał złe bajty, więc plik
  /// znika, a BE dostaje sygnał, żeby sprawdzić kopie własnym dowodem.
  Future<void> _verify(File out, Map<String, dynamic> r, String id) async {
    final want = (r['sha256'] as String?)?.toLowerCase();
    final wantBlocks = (r['blocks'] as List?)?.map((e) => '$e'.toLowerCase()).toList();
    if (want == null || want.isEmpty || wantBlocks == null || wantBlocks.isEmpty) return;
    final (got, digest) = await StoreCrypto.blockHashes(out);
    final bad = digest.toLowerCase() != want ||
        got.length != wantBlocks.length ||
        List.generate(got.length, (i) => got[i].toLowerCase() != wantBlocks[i]).any((x) => x);
    if (!bad) return;
    try { await out.delete(); } catch (_) {}
    _log('E', 'file ${id.substring(0, 8)}: hashes do NOT match the signature — the host served bad bytes');
    _send({'type': 'bad_copy', 'object_id': id});
    throw Exception('The downloaded file does not match your signature — the host served bad data. '
        'We have reported it; try again in a moment and it will come from the other copy.');
  }

  // ── transfer bezpośredni ───────────────────────────────────────────────────
  /// Nasłuch zakładamy raz na sesję i melduje go BE. Nie udało się otworzyć portu — trudno,
  /// zostają dwie pozostałe trasy; to nie jest błąd, o którym kupujący ma się dowiadywać.
  Future<void> _ensureListener() async {
    if (_srv != null) return;
    // STAŁY port, nie losowy: losowego nikt nie przekieruje ręcznie na routerze, a mapowanie
    // trzeba by robić od nowa po każdym uruchomieniu. Zajęty — bierzemy jakikolwiek, wtedy
    // zostaje samo UPnP.
    for (final p in [directPort, 0]) {
      try {
        _srv = await ServerSocket.bind(InternetAddress.anyIPv4, p, shared: false);
        break;
      } catch (_) {/* zajęty */}
    }
    if (_srv == null) { _log('W', 'listen: could not open a port — staying on the relay'); return; }
    _srv!.listen(_onInbound, onError: (_) {});
    _log('I', 'listening on port ${_srv!.port}');
    try {
      final r = await _ask('listen', {'type': 'listen', 'port': _srv!.port});
      _probe = r['probe'] as String?;
      _log('I', 'port reported to the server (${_probe == null ? "unconfirmed" : "ok"})');
    } catch (e) { _probe = null; _log('W', 'reporting the port failed: $e'); }
    // Router pytamy sami i bez flagi. Nie umie UPnP — trudno, zostają pozostałe trasy.
    unawaited(_mapPort());
    _upnpTimer ??= Timer.periodic(const Duration(minutes: 25), (_) => _mapPort());
  }

  Future<void> _mapPort() async {
    final srv = _srv;
    if (srv == null) return;
    final ok = await Upnp.map(srv.port);
    _log('I', ok
        ? 'UPnP: the router forwarded port ${srv.port}'
        : 'UPnP: no router accepted a mapping for port ${srv.port}');
    _events.add(ok ? 'upnp:ok' : 'upnp:none');
  }

  Future<void> _onInbound(Socket sock) async {
    final probe = _probe;
    if (probe == null) { sock.destroy(); return; }
    final w = _Wire(sock);
    try {
      sock.add(utf8.encode('sensmos-client $probe\n'));
      await sock.flush();
      final cmd = (await w.line()).split(' ');
      if (cmd.length != 2 || cmd[0] != 'x') { sock.destroy(); return; }
      final g = await _awaitGrant(cmd[1]);
      if (g == null) {
        _log('W', 'connection from ${sock.remoteAddress.address}: unknown transfer id');
        sock.add(utf8.encode('err unknown number\n')); await sock.flush(); sock.destroy(); return;
      }
      _log('I', 'the seller called in from ${sock.remoteAddress.address} — direct transfer');
      await g.run(w);
    } catch (e) {
      _log('W', 'incoming connection failed: $e');
      _events.add('direct-inbound-failed:$e');
    } finally {
      try { await sock.close(); } catch (_) {}
    }
  }

  /// Sprzedawca potrafi zadzwonić szybciej, niż zdążymy zapisać przydział — numer jest już wtedy
  /// prawdziwy, tylko jeszcze go u siebie nie mamy. Chwila cierpliwości zamiast odmowy.
  Future<_Grant?> _awaitGrant(String nonce) async {
    for (var i = 0; i < 50; i++) {
      final g = _grants.remove(nonce);
      if (g != null) return g;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    return null;
  }

  /// Backend sprząta wpis pliku i oddaje miejsce w pakiecie. Po IDENTYFIKATORZE, nie po numerze
  /// sesji — przy trasie bezpośredniej sesji po prostu nie ma.
  Future<void> _zglosPrzerwanie(String oid) async {
    try {
      _send({'type': 'put_abort', 'object_id': oid});
    } catch (_) {/* zerwane łącze i tak konczy sie sprzataniem po stronie BE */}
    _log('I', 'upload ${oid.substring(0, 8)} cancelled by you');
  }

  Future<void> _directSend(Map d, File cipher, int size, void Function(int)? onProgress) async {
    Future<void> body(_Wire w) async {
      w.sock.add(utf8.encode('len $size\n'));
      var sent = 0;
      await for (final part in cipher.openRead()) {
        if (_przerwane) throw const UploadCancelled();
        w.sock.add(part); sent += part.length; onProgress?.call(sent);
        await w.sock.flush();
      }
      final ack = await w.line();
      if (!ack.startsWith('ok')) throw Exception(ack.isEmpty ? 'no acknowledgement' : ack);
    }
    await _route(d, body);
  }

  Future<int> _directRecv(Map d, File out, void Function(int)? onProgress) async {
    var got = 0;
    Future<void> body(_Wire w) async {
      final head = (await w.line()).split(' ');
      if (head.length != 2 || head[0] != 'len') throw Exception(head.join(' '));
      final size = int.parse(head[1]);
      final sink = out.openWrite();
      try {
        got = await w.drainTo(sink, size, onProgress);
      } finally { await sink.close(); }
      if (got != size) throw Exception('got $got of $size bytes');
      w.sock.add(utf8.encode('ok $got\n'));
      await w.sock.flush();
    }
    await _route(d, body);
    return got;
  }

  /// Dwa kierunki, jedno ciało: albo dzwonimy my, albo czekamy, aż zadzwoni sprzedawca.
  Future<void> _route(Map d, Future<void> Function(_Wire) body) async {
    final nonce = '${d['nonce']}';
    if (d['route'] == 'seller') {
      final sock = await Socket.connect('${d['host']}', d['port'] as int,
          timeout: const Duration(seconds: 15));
      sock.setOption(SocketOption.tcpNoDelay, true);
      final w = _Wire(sock);
      try {
        await w.line();                                     // baner sprzedawcy
        sock.add(utf8.encode('x $nonce\n'));
        await sock.flush();
        await body(w);
      } finally { try { await sock.close(); } catch (_) {} }
      return;
    }
    final g = _Grant(body);
    _grants[nonce] = g;
    try {
      await g.done.future.timeout(const Duration(minutes: 30));
    } finally { _grants.remove(nonce); }
  }

  // ── plumbing ──
  Future<Map<String, dynamic>> _ask(String type, Map<String, dynamic> m) { final f = _expect(type); _send(m); return f; }
  Future<Map<String, dynamic>> _expect(String type) {
    final c = Completer<Map<String, dynamic>>(); _waiting[type] = c;
    return c.future.timeout(const Duration(seconds: 60), onTimeout: () { _waiting.remove(type); throw TimeoutException(type); });
  }
  void _send(Map<String, dynamic> m) { try { _ch?.sink.add(jsonEncode(m)); } catch (_) {} }

  void _onMessage(dynamic raw) {
    if (raw is! String) {
      final b = raw as List<int>;
      if (b.length < 2) return;
      final sid = (b[0] << 8) | b[1];
      if (sid == _getSid && _getSink != null) {
        _getSink!.add(b.sublist(2)); _getBytes += b.length - 2; _getProgress?.call(_getBytes);
      }
      return;
    }
    Map<String, dynamic> m;
    try { m = jsonDecode(raw) as Map<String, dynamic>; } catch (_) { return; }
    final t = m['type'] as String? ?? '';
    if (t == 'get_end') { _getDone?.complete(m); _getDone = null; return; }
    final c = _waiting.remove(t);
    if (c != null && !c.isCompleted) c.complete(m);
  }

  void _fail(String msg) {
    if (!_events.isClosed) _events.add('down:$msg');
    for (final c in _waiting.values) { if (!c.isCompleted) c.completeError(Exception(msg)); }
    _waiting.clear();
    if (_getDone != null && !_getDone!.isCompleted) _getDone!.complete({'error': msg});
  }

  void dispose() {
    try { _upnpTimer?.cancel(); } catch (_) {}
    try { _srv?.close(); } catch (_) {}
    try { _sub?.cancel(); } catch (_) {}
    try { _ch?.sink.close(); } catch (_) {}
    try { _getSink?.close(); } catch (_) {}
    if (!_events.isClosed) _events.close();
  }
}

/// Transfer, na który czekamy, bo to druga strona ma zadzwonić.
class _Grant {
  final Future<void> Function(_Wire) body;
  final done = Completer<void>();
  _Grant(this.body);

  Future<void> run(_Wire w) async {
    try {
      await body(w);
      if (!done.isCompleted) done.complete();
    } catch (e) {
      if (!done.isCompleted) done.completeError(e);
      rethrow;
    }
  }
}

/// Gniazdo czytane liniami i blokami. Linii używamy tylko do uścisku dłoni (baner, numer,
/// długość, potwierdzenie); dalej lecą surowe bajty, bez pakowania w ramki.
class _Wire {
  final Socket sock;
  late final StreamIterator<Uint8List> _it;
  final _buf = <int>[];
  _Wire(this.sock) { _it = StreamIterator(sock.cast<Uint8List>()); }

  Future<String> line({int limit = 512}) async {
    while (true) {
      final i = _buf.indexOf(10);
      if (i >= 0) {
        final out = utf8.decode(_buf.sublist(0, i), allowMalformed: true);
        _buf.removeRange(0, i + 1);
        return out.trim();
      }
      if (_buf.length > limit) throw Exception('line too long');
      if (!await _it.moveNext()) return utf8.decode(_buf, allowMalformed: true).trim();
      _buf.addAll(_it.current);
    }
  }

  Future<int> drainTo(IOSink out, int size, void Function(int)? progress) async {
    var got = 0;
    if (_buf.isNotEmpty) {                       // reszta, która przyszła razem z nagłówkiem
      final take = _buf.length > size ? size : _buf.length;
      out.add(Uint8List.fromList(_buf.sublist(0, take)));
      _buf.removeRange(0, take);
      got += take; progress?.call(got);
    }
    while (got < size && await _it.moveNext()) {
      var b = _it.current;
      if (got + b.length > size) b = Uint8List.sublistView(b, 0, size - got);
      out.add(b); got += b.length; progress?.call(got);
    }
    return got;
  }
}
