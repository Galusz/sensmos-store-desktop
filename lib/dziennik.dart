import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensmos_store/sensmos_store.dart';
import 'i18n.dart';

const _teal = Color(0xFF1FCFB4);
const _bg = Color(0xFF0E1116);
const _card = Color(0xFF161B22);
const _line = Color(0xFF232B36);
const _muted = Color(0xFF8B949E);
const _faint = Color(0xFF6E7681);
const _amber = Color(0xFFFFB454);
const _red = Color(0xFFFF6666);

enum Rodzaj { wyslanie, pobranie, kasowanie, blad, info }

class Wpis {
  final DateTime kiedy;
  final Rodzaj rodzaj;
  final String co;
  final int bajty;
  final String trasa; // 'direct' | 'relay' | ''
  const Wpis(this.kiedy, this.rodzaj, this.co, {this.bajty = 0, this.trasa = ''});
}

/// Co się działo z plikami — po to, żeby „ostatni transfer" w pasku stanu nie był jedyną
/// wiedzą o tym, czy coś poszło wprost do hosta, czy przez serwer, i czy w ogóle doszło.
///
/// Dziennik żyje w pamięci procesu. Nie zapisujemy go na dysk celowo: to lista nazw plików,
/// czyli dokładnie ta informacja, którą cała reszta programu trzyma zaszyfrowaną.
class Dziennik extends ChangeNotifier {
  static final Dziennik i = Dziennik._();
  Dziennik._();

  static const _max = 500;
  final List<Wpis> wpisy = [];

  void dodaj(Rodzaj r, String co, {int bajty = 0, String trasa = ''}) {
    wpisy.insert(0, Wpis(DateTime.now(), r, co, bajty: bajty, trasa: trasa));
    if (wpisy.length > _max) wpisy.removeRange(_max, wpisy.length);
    notifyListeners();
  }

  /// Podpięcie pod gadanie samego protokołu — stamtąd wiadomo, którą trasą poszły bajty.
  void podepnijProtokol() {
    storeLog = (poziom, tag, tresc) {
      if (poziom == 'err') dodaj(Rodzaj.blad, tresc);
    };
  }

  String jakoTekst() => [
        for (final w in wpisy)
          '${w.kiedy.toIso8601String()}  ${w.rodzaj.name.padRight(9)}  '
              '${w.trasa.isEmpty ? '' : '[${w.trasa}] '}${w.co}'
              '${w.bajty > 0 ? '  (${_rozmiar(w.bajty)})' : ''}',
      ].join('\n');

  static String _rozmiar(int b) {
    if (b >= 1073741824) return '${(b / 1073741824).toStringAsFixed(2)} GB';
    if (b >= 1048576) return '${(b / 1048576).toStringAsFixed(1)} MB';
    if (b >= 1024) return '${(b / 1024).toStringAsFixed(0)} kB';
    return '$b B';
  }
}

class EkranDziennika extends StatefulWidget {
  const EkranDziennika({super.key});
  @override
  State<EkranDziennika> createState() => _EkranDziennikaState();
}

class _EkranDziennikaState extends State<EkranDziennika> {
  /// null = wszystko; inaczej pokazujemy tylko ten rodzaj wpisów.
  Set<Rodzaj>? _filtr;

  @override
  void initState() { super.initState(); Dziennik.i.addListener(_odswiez); }

  @override
  void dispose() { Dziennik.i.removeListener(_odswiez); super.dispose(); }

  void _odswiez() { if (mounted) setState(() {}); }

  @override
  Widget build(BuildContext context) {
    final f = _filtr;
    final l = f == null
        ? Dziennik.i.wpisy
        : Dziennik.i.wpisy.where((w) => f.contains(w.rodzaj)).toList();
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        title: Text(t('log.title'), style: const TextStyle(fontSize: 15)),
        actions: [
          IconButton(
            tooltip: t('log.copy'),
            iconSize: 18,
            onPressed: Dziennik.i.wpisy.isEmpty ? null : () async {
              await Clipboard.setData(ClipboardData(text: Dziennik.i.jakoTekst()));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(t('log.copied')), backgroundColor: _card,
                    behavior: SnackBarBehavior.floating, width: 320));
              }
            },
            icon: const Icon(Icons.copy_all, color: _muted),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
          child: Row(children: [
            _chip(t('log.all'), null),
            const SizedBox(width: 8),
            _chip(t('log.transfers'), {Rodzaj.wyslanie, Rodzaj.pobranie}),
            const SizedBox(width: 8),
            _chip(t('log.problems'), {Rodzaj.blad}),
            const Spacer(),
            Text(t('log.kept'), style: const TextStyle(color: _faint, fontSize: 10.5)),
          ]),
        ),
        const Divider(height: 1, color: _line),
        Expanded(
          child: l.isEmpty
              ? Center(child: Text(t('log.empty'),
                  style: const TextStyle(color: _muted, fontSize: 12.5)))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: l.length,
                  itemBuilder: (_, i) => _wiersz(l[i]),
                ),
        ),
      ]),
    );
  }

  Widget _chip(String tytul, Set<Rodzaj>? co) {
    final wybrany = (_filtr == null && co == null) ||
        (co != null && _filtr != null && _filtr!.length == co.length && _filtr!.containsAll(co));
    return InkWell(
      onTap: () => setState(() => _filtr = co),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
            color: wybrany ? _teal.withValues(alpha: 0.14) : null,
            border: Border.all(color: wybrany ? _teal : _line),
            borderRadius: BorderRadius.circular(8)),
        child: Text(tytul,
            style: TextStyle(color: wybrany ? _teal : _muted, fontSize: 12)),
      ),
    );
  }

  Widget _wiersz(Wpis w) {
    final (ikona, kolor) = switch (w.rodzaj) {
      Rodzaj.wyslanie => (Icons.arrow_upward, _teal),
      Rodzaj.pobranie => (Icons.arrow_downward, _teal),
      Rodzaj.kasowanie => (Icons.delete_outline, _red),
      Rodzaj.blad => (Icons.error_outline, _amber),
      Rodzaj.info => (Icons.info_outline, _muted),
    };
    final k = w.kiedy;
    final czas = '${k.hour.toString().padLeft(2, '0')}:${k.minute.toString().padLeft(2, '0')}'
        ':${k.second.toString().padLeft(2, '0')}';
    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
          color: _card, borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _line)),
      child: Row(children: [
        SizedBox(width: 62, child: Text(czas,
            style: const TextStyle(color: _faint, fontSize: 11, fontFamily: 'monospace'))),
        Icon(ikona, size: 15, color: kolor),
        const SizedBox(width: 9),
        Expanded(child: Text(w.co, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 12))),
        if (w.bajty > 0) ...[
          const SizedBox(width: 8),
          Text(Dziennik._rozmiar(w.bajty),
              style: const TextStyle(color: _muted, fontSize: 11)),
        ],
        if (w.trasa.isNotEmpty) ...[
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
                border: Border.all(
                    color: w.trasa == 'direct' ? _teal.withValues(alpha: 0.6) : _line),
                borderRadius: BorderRadius.circular(5)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(w.trasa == 'direct' ? Icons.bolt : Icons.cloud_outlined,
                  size: 11, color: w.trasa == 'direct' ? _teal : _faint),
              const SizedBox(width: 3),
              Text(t(w.trasa == 'direct' ? 'route.direct' : 'route.server'),
                  style: TextStyle(
                      color: w.trasa == 'direct' ? _teal : _faint, fontSize: 10.5)),
            ]),
          ),
        ],
      ]),
    );
  }
}
