import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'pairing.dart';

/// Aktualności — te same, które widzisz w telefonie. Ten sam endpoint, ten sam adres portfela,
/// więc wpisy celowane (kraj, wersja, konkretne portfele) trafiają tu identycznie.
class News extends StatefulWidget {
  final String owner;
  /// Naglowek sekcji. Trzymamy go TUTAJ, bo tytul bez tresci to smiec na ekranie.
  final Widget naglowek;
  const News({super.key, required this.owner, required this.naglowek});
  @override
  State<News> createState() => _NewsState();
}

class _NewsState extends State<News> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final r = await http
          .get(Uri.parse('${Pairing.be}/v1/news?owner=${widget.owner}'))
          .timeout(const Duration(seconds: 12));
      final j = jsonDecode(r.body);
      final list = (j is List ? j : (j as Map)['items'] as List?) ?? const [];
      if (mounted) {
        setState(() { _items = list.cast<Map<String, dynamic>>(); _loading = false; });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Podczas wczytywania rowniez nic nie pokazujemy: krecacy sie kolek pod pustym tytulem
    // obiecuje tresc, ktorej najczesciej nie ma.
    if (_loading || _items.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 14),
      widget.naglowek,
      for (final n in _items.take(4)) _card(n),
    ]);
  }

  Widget _card(Map<String, dynamic> n) {
    final data = DateTime.tryParse('${n['published_at']}')?.toLocal();
    final link = '${n['link_url'] ?? ''}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: const Color(0xFF161B22), borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF232B36))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${n['title'] ?? ''}',
            style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
        if ('${n['body'] ?? ''}'.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text('${n['body']}',
              style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11.5, height: 1.35)),
        ],
        if (link.isNotEmpty) ...[
          const SizedBox(height: 6),
          InkWell(
            onTap: () => launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication),
            child: Text('${n['link_label'] ?? link}',
                style: const TextStyle(color: Color(0xFF1FCFB4), fontSize: 11.5)),
          ),
        ],
        if (data != null) ...[
          const SizedBox(height: 4),
          Text('${data.day}.${data.month.toString().padLeft(2, '0')}.${data.year}',
              style: const TextStyle(color: Color(0xFF6E7681), fontSize: 10)),
        ],
      ]),
    );
  }
}
