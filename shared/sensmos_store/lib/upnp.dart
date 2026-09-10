import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:xml/xml.dart';

/// Poproszenie routera o przepuszczenie jednego portu do tego urządzenia (UPnP IGD).
///
/// Robimy to BEZ pytania i bez flagi, bo funkcja, do której trzeba przeczytać instrukcję, nie
/// istnieje. Router albo umie i przepuści, albo nie umie i nic się nie stanie — wtedy zostają
/// pozostałe trasy transferu i użytkownik niczego nie zauważy.
///
/// Ten sam przebieg co w agencie Store (`sensmos-store.py`), żeby obie strony zachowywały się
/// tak samo: rozgłoszenie SSDP → opis urządzenia → SOAP `AddPortMapping`.
class Upnp {
  static const _lease = 3600;               // dzierżawa; odnawiamy ją, zanim wygaśnie

  /// Zwraca true, jeśli któryś router przyjął mapowanie.
  static Future<bool> map(int port) async {
    for (final gw in await _discover()) {
      try {
        final ctl = await _control(gw.location);
        if (ctl == null) continue;
        final me = await _lanIp(gw.address);
        if (me == null) continue;
        String body(int lease) =>
            '<NewRemoteHost></NewRemoteHost>'
            '<NewExternalPort>$port</NewExternalPort><NewProtocol>TCP</NewProtocol>'
            '<NewInternalPort>$port</NewInternalPort>'
            '<NewInternalClient>$me</NewInternalClient><NewEnabled>1</NewEnabled>'
            '<NewPortMappingDescription>Sensmos</NewPortMappingDescription>'
            '<NewLeaseDuration>$lease</NewLeaseDuration>';
        // Sporo routerów odrzuca każdą dzierżawę poza wieczystą — znana przypadłość, nie nasz błąd.
        var st = await _soap(ctl.url, ctl.service, body(_lease));
        if (st != 200) st = await _soap(ctl.url, ctl.service, body(0));
        if (st == 200) return true;
      } catch (_) {/* następna bramka */}
    }
    return false;
  }

  static Future<List<_Gw>> _discover({Duration wait = const Duration(seconds: 3)}) async {
    final out = <_Gw>[];
    RawDatagramSocket? s;
    try {
      s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      s.broadcastEnabled = true;
      const msg = 'M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\n'
          'MAN: "ssdp:discover"\r\nMX: 2\r\n'
          'ST: urn:schemas-upnp-org:device:InternetGatewayDevice:1\r\n\r\n';
      final sock = s;
      // `onError` jest OBOWIĄZKOWE: błąd gniazda przychodzi strumieniem, a nie z `send`, więc
      // sam `try` wokół wysyłki go nie łapie i kończy jako nieobsłużony wyjątek. Poza WiFi
      // Android zabrania multicastu, czyli to jest przypadek normalny, nie brzegowy.
      final sub = sock.listen((e) {
        if (e != RawSocketEvent.read) return;
        final d = sock.receive();
        if (d == null) return;
        for (final ln in utf8.decode(d.data, allowMalformed: true).split('\n')) {
          if (ln.toLowerCase().startsWith('location:')) {
            out.add(_Gw(ln.substring(9).trim(), d.address.address));
          }
        }
      }, onError: (_) {}, cancelOnError: false);
      try {
        sock.send(utf8.encode(msg), InternetAddress('239.255.255.250'), 1900);
      } on SocketException {
        await sub.cancel();
        return out;                    // brak prawa do multicastu = nie ma tu routera do pytania
      }
      await Future.delayed(wait);
      await sub.cancel();
    } catch (_) {
      // brak uprawnień do multicastu albo sieć bez routera — nie ma czego zgłaszać
    } finally {
      s?.close();
    }
    return out;
  }

  static Future<_Ctl?> _control(String location) async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final res = await c.getUrl(Uri.parse(location)).then((q) => q.close());
      final doc = XmlDocument.parse(await res.transform(utf8.decoder).join());
      const want = {
        'urn:schemas-upnp-org:service:WANIPConnection:1',
        'urn:schemas-upnp-org:service:WANPPPConnection:1',
      };
      for (final svc in doc.findAllElements('service')) {
        final type = svc.getElement('serviceType')?.innerText.trim() ?? '';
        final url = svc.getElement('controlURL')?.innerText.trim() ?? '';
        if (want.contains(type) && url.isNotEmpty) {
          return _Ctl(Uri.parse(location).resolve(url).toString(), type);
        }
      }
      return null;
    } finally {
      c.close(force: true);
    }
  }

  static Future<int> _soap(String url, String service, String body) async {
    final env = '<?xml version="1.0"?>'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
        's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
        '<s:Body><u:AddPortMapping xmlns:u="$service">$body</u:AddPortMapping></s:Body></s:Envelope>';
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await c.postUrl(Uri.parse(url));
      req.headers.set('Content-Type', 'text/xml; charset="utf-8"');
      req.headers.set('SOAPAction', '"$service#AddPortMapping"');
      req.add(utf8.encode(env));
      final res = await req.close();
      await res.drain();
      return res.statusCode;
    } finally {
      c.close(force: true);
    }
  }

  /// Nasz adres w tej samej sieci, co router — to on ma trafić do mapowania. Bierzemy interfejs
  /// z tego samego /24; telefon z WiFi i LTE naraz ma dwa adresy i tylko jeden z nich jest ten.
  static Future<String?> _lanIp(String gateway) async {
    final pre = gateway.split('.').take(3).join('.');
    try {
      for (final ni in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
        for (final a in ni.addresses) {
          if (a.address.startsWith('$pre.')) return a.address;
        }
      }
    } catch (_) {}
    return null;
  }
}

class _Gw {
  final String location, address;
  _Gw(this.location, this.address);
}

class _Ctl {
  final String url, service;
  _Ctl(this.url, this.service);
}
