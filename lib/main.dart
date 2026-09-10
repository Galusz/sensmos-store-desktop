import 'dart:async';
import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sensmos_store/sensmos_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'backup.dart';
import 'dziennik.dart';
import 'i18n.dart';
import 'media.dart';
import 'news.dart';
import 'pairing.dart';
import 'session.dart';
import 'tray.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  Dziennik.i.podepnijProtokol();
  await windowManager.ensureInitialized();
  await L.wczytaj();
  // Okno wraca tam, gdzie je zostawiono. Apka, ktora za kazdym razem otwiera sie w domyslnym
  // prostokacie, kaze ustawiac sie od nowa przy kazdym uruchomieniu.
  final zapamietany = await Zasobnik.zapamietanyRozmiar();
  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: zapamietany ?? const Size(1180, 720),
      minimumSize: const Size(780, 480),
      title: 'Store',
      backgroundColor: bg,
    ),
    () async { await windowManager.show(); await windowManager.focus(); },
  );
  runApp(const SensmosPc());
}

const teal = Color(0xFF1FCFB4);
const bg = Color(0xFF0E1116);
const card = Color(0xFF161B22);
const line = Color(0xFF232B36);
const muted = Color(0xFF8B949E);
const faint = Color(0xFF6E7681);
const amber = Color(0xFFFFB454);
const red = Color(0xFFFF6666);

class SensmosPc extends StatelessWidget {
  const SensmosPc({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
    valueListenable: L.zmiana,
    builder: (_, _, _) => MaterialApp(
        title: 'Sensmos',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: bg,
          appBarTheme: const AppBarTheme(backgroundColor: bg, elevation: 0),
          colorScheme: ThemeData.dark().colorScheme.copyWith(primary: teal, surface: card),
          tooltipTheme: const TooltipThemeData(
            decoration: BoxDecoration(color: card),
            textStyle: TextStyle(color: Colors.white, fontSize: 11),
          ),
        ),
        home: const _Gate(),
      ),
  );
}

class _Gate extends StatefulWidget {
  const _Gate();
  @override
  State<_Gate> createState() => _GateState();
}

class _GateState extends State<_Gate> {
  Map<String, dynamic>? _pairing;
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final p = await Pairing.load();
    if (mounted) setState(() { _pairing = p; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_pairing == null) return PairScreen(onPaired: _load);
    return Home(
      key: ValueKey(_pairing!['token']),
      pairing: _pairing!,
      onUnpair: () async { await Pairing.forget(); await _load(); },
    );
  }
}

// ── parowanie ────────────────────────────────────────────────────────────────

class PairScreen extends StatefulWidget {
  final VoidCallback onPaired;
  const PairScreen({super.key, required this.onPaired});
  @override
  State<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends State<PairScreen> {
  Pairing? _p;
  String? _error;
  bool _waiting = false;

  @override
  void initState() { super.initState(); _start(); }

  Future<void> _start() async {
    setState(() { _error = null; _waiting = true; });
    final p = await Pairing.start();
    if (!mounted) return;
    setState(() => _p = p);
    try {
      final data = await p.waitForPhone(deviceName: Platform.localHostname);
      await Pairing.save(data);
      if (mounted) widget.onPaired();
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _waiting = false; });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const SensmosLogo(size: 44, fontSize: 30),
                const SizedBox(height: 10),
                Text(t('pair.hint'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: muted, fontSize: 13, height: 1.4)),
                const SizedBox(height: 28),
                if (_p != null) ...[
                  SelectableText(_p!.pretty,
                      style: const TextStyle(color: Colors.white, fontSize: 32,
                          fontFamily: 'monospace', letterSpacing: 4, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 20),
                  // QR niesie DOKŁADNIE ten sam kod — nie drugi kanał, tylko wygodniejsze
                  // przepisanie tych samych znaków.
                  Container(padding: const EdgeInsets.all(10), color: Colors.white,
                      child: QrImageView(data: _p!.code, size: 150)),
                ],
                const SizedBox(height: 24),
                if (_waiting)
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: teal)),
                    const SizedBox(width: 10),
                    Text(t('pair.waiting'),
                        style: const TextStyle(color: muted, fontSize: 13)),
                  ]),
                if (_error != null) ...[
                  Text(_error!, textAlign: TextAlign.center,
                      style: const TextStyle(color: amber, fontSize: 13)),
                  const SizedBox(height: 14),
                  OutlinedButton(onPressed: _start,
                      style: OutlinedButton.styleFrom(foregroundColor: teal),
                      child: Text(t('pair.newCode'))),
                ],
                const SizedBox(height: 30),
                Text(t('pair.privacy'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: faint, fontSize: 11, height: 1.4)),
              ]),
            ),
          ),
        ),
      );
}

/// Parowanie KOLEJNEGO komputera — bez sięgania po telefon.
///
/// Pól jest więcej niż dwa, więc pełny ekran, nie okienko. I te same pola, co na ekranie parowania
/// w telefonie: kod, kto prosi i o co, przełącznik odczytu plików — bo to ta sama czynność i nie
/// ma powodu, żeby wyglądała inaczej po tej stronie.
class EkranParowaniaPC extends StatefulWidget {
  final Map<String, dynamic> moje;
  const EkranParowaniaPC({super.key, required this.moje});
  @override
  State<EkranParowaniaPC> createState() => _EkranParowaniaPCState();
}

class _EkranParowaniaPCState extends State<EkranParowaniaPC> {
  final _kod = TextEditingController();
  Map<String, dynamic>? _kto;            // {name, pub, want} spod tego kodu
  Map<String, String> _opisy = {};       // klucz zakresu → opis, z serwera
  final _wybrane = <String>{};
  bool _prosilOParowanie = false;        // poprosił o `token.issue`, a tego oddać nie możemy
  bool _czytaPliki = false;
  String? _busy, _blad;
  bool _gotowe = false;

  /// Ziarna skrzynki nie mamy, gdy właściciel wpuścił nas bez prawa odczytu — wtedy nie ma czego
  /// przekazać dalej i przełącznik musi być martwy, a nie tylko bezskuteczny.
  bool get _mamOdczyt {
    final z = widget.moje['box_seed'];
    return z is String && z.isNotEmpty;
  }

  String get _be => '${widget.moje['be'] ?? Pairing.be}';

  @override
  void initState() {
    super.initState();
    DalszeParowanie.opisy(_be).then((m) { if (mounted) setState(() => _opisy = m); });
  }

  @override
  void dispose() { _kod.dispose(); super.dispose(); }

  Future<void> _sprawdz() async {
    setState(() { _busy = t('pair2.searching'); _blad = null; });
    try {
      final f = await DalszeParowanie.ktoCzeka(_be, _kod.text);
      final moje = ((widget.moje['scopes'] as List?) ?? const []).map((e) => '$e').toSet();
      final chce = ((f['want'] as List?) ?? const []).map((e) => '$e').toSet();
      if (!mounted) return;
      setState(() {
        _kto = f;
        _busy = null;
        _prosilOParowanie = chce.contains('token.issue');
        // Zaznaczamy to, o co poprosił, przycięte do tego, co sami mamy. Prawa parowania dalej
        // na liście nie ma, bo backend i tak by je odciął — a pole, które nic nie robi, jest
        // obietnicą bez pokrycia.
        _wybrane
          ..clear()
          ..addAll(chce.intersection(moje)..remove('token.issue'));
      });
    } catch (e) {
      if (mounted) setState(() { _busy = null; _blad = '$e'; _kto = null; });
    }
  }

  Future<void> _sparuj() async {
    setState(() { _busy = t('pair2.pairing'); _blad = null; });
    try {
      await DalszeParowanie.sparuj(
        moje: widget.moje,
        kod: _kod.text,
        zakresy: _wybrane.toList(),
        czytaPliki: _czytaPliki && _mamOdczyt,
        nazwa: '${_kto?['name'] ?? 'computer'}',
      );
      if (mounted) setState(() { _busy = null; _gotowe = true; });
    } catch (e) {
      if (mounted) setState(() { _busy = null; _blad = '$e'; });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: bg,
          title: Text(t('pair2.title'), style: const TextStyle(fontSize: 15)),
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (_gotowe) ...[
                  const Icon(Icons.check_circle_outline, color: teal, size: 42),
                  const SizedBox(height: 14),
                  Text(t('pair2.done'), textAlign: TextAlign.center,
                      style: const TextStyle(color: muted, fontSize: 13, height: 1.4)),
                  const SizedBox(height: 22),
                  FilledButton(
                      onPressed: () => Navigator.pop(context),
                      style: FilledButton.styleFrom(backgroundColor: teal),
                      child: Text(t('pair2.close'))),
                ] else ...[
                  Text(t('pair2.hint'),
                      style: const TextStyle(color: muted, fontSize: 12.5, height: 1.4)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _kod,
                    autofocus: true,
                    textCapitalization: TextCapitalization.characters,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) { if (_busy == null && _kod.text.isNotEmpty) _sprawdz(); },
                    style: const TextStyle(color: Colors.white, letterSpacing: 3,
                        fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      labelText: t('pair2.code'),
                      labelStyle: const TextStyle(color: muted),
                      enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: line)),
                      focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: teal)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: _busy == null && _kod.text.isNotEmpty ? _sprawdz : null,
                    style: OutlinedButton.styleFrom(foregroundColor: teal),
                    child: Text(t('pair2.check')),
                  ),
                  if (_kto != null) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          color: card, borderRadius: BorderRadius.circular(10)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t('pair2.asks', {'name': '${_kto!['name']}'}),
                            style: const TextStyle(color: Colors.white, fontSize: 13,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(t('pair2.pickHint'),
                            style: const TextStyle(color: muted, fontSize: 11.5, height: 1.35)),
                        const SizedBox(height: 6),
                        for (final k in _wybrane.toList())
                          CheckboxListTile(
                            value: _wybrane.contains(k),
                            onChanged: (v) => setState(() =>
                                v == true ? _wybrane.add(k) : _wybrane.remove(k)),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            activeColor: teal,
                            title: Text(_opisy[k] ?? k,
                                style: const TextStyle(color: Colors.white, fontSize: 12.5)),
                          ),
                        CheckboxListTile(
                          value: _czytaPliki && _mamOdczyt,
                          onChanged:
                              _mamOdczyt ? (v) => setState(() => _czytaPliki = v == true) : null,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          activeColor: teal,
                          title: Text(t('pair2.readFiles'),
                              style: TextStyle(
                                  color: _mamOdczyt ? Colors.white : faint, fontSize: 12.5)),
                          subtitle: Text(
                              _mamOdczyt ? t('pair2.readFilesHint') : t('pair2.noSeed'),
                              style: TextStyle(color: _mamOdczyt ? muted : amber,
                                  fontSize: 11, height: 1.35)),
                        ),
                        // Tamten komputer poprosił także o prawo parowania kolejnych. Nie damy mu
                        // go — i lepiej powiedzieć to wprost, niż zostawić po sobie ciszę.
                        if (_prosilOParowanie) ...[
                          const SizedBox(height: 6),
                          Text(t('pair2.noChain'),
                              style: const TextStyle(color: faint, fontSize: 11, height: 1.35)),
                        ],
                      ]),
                    ),
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: _busy == null && _wybrane.isNotEmpty ? _sparuj : null,
                      style: FilledButton.styleFrom(backgroundColor: teal),
                      child: Text(t('pair2.pair')),
                    ),
                  ],
                  if (_busy != null) ...[
                    const SizedBox(height: 16),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const SizedBox(width: 15, height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2, color: teal)),
                      const SizedBox(width: 10),
                      Text(_busy!, style: const TextStyle(color: muted, fontSize: 12.5)),
                    ]),
                  ],
                  if (_blad != null) ...[
                    const SizedBox(height: 14),
                    Text(_blad!, style: const TextStyle(color: amber, fontSize: 12.5)),
                  ],
                  const SizedBox(height: 24),
                  Text(t('pair.privacy'),
                      style: const TextStyle(color: faint, fontSize: 11, height: 1.4)),
                ],
              ]),
            ),
          ),
        ),
      );
}

// ── główny widok ─────────────────────────────────────────────────────────────

enum SortBy { name, size, date }

class Home extends StatefulWidget {
  final Map<String, dynamic> pairing;
  final VoidCallback onUnpair;
  const Home({super.key, required this.pairing, required this.onUnpair});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  late final Session _s = Session(widget.pairing);
  final _backup = Backup();
  final _search = TextEditingController();
  final _searchFocus = FocusNode();

  final _sel = <String>{};
  String _folder = '';                 // '' = korzeń
  SortBy _sort = SortBy.date;
  bool _asc = false;
  bool _dropping = false;
  String? _busy;
  double? _progress;
  Timer? _tick;
  /// Ostatnio klikniety wiersz — punkt zaczepienia dla zaznaczania zakresem (Shift).
  String? _kotwica;
  /// Katalogi zalozone przez czlowieka, ktore nie maja jeszcze ani jednego pliku. Zyja wylacznie
  /// tutaj, bo na serwerze nie ma czego zapisac — nazwa katalogu istnieje tylko wewnatrz nazwy
  /// pliku, a tej jeszcze nie ma.
  final _puste = <String>{};
  /// Pokazuj tylko pliki, ktorym brakuje kopii — szybkie „czy wszystko jest bezpieczne".
  bool _tylkoUwaga = false;
  /// Plik, ktory wlasnie gra (albo sie sciaga, zeby zagrac). Jeden na raz — dwa naraz to
  /// halas, a nie podglad.
  String? _graId;
  double? _graPostep;
  File? _graPlik;
  /// Tytul, wykonawca i okladka wyjete z pobranego pliku. Wczesniej nie mamy ich skad wziac —
  /// siedza w srodku szyfrogramu.
  Tagi? _tagi;
  /// Ile gigabajtow ma miec pakiet przy wykupie. Poza ekranem zakupu nie znaczy nic.
  int _gbDoKupienia = 1;
  /// Wybor liczby kopii na ekranie zakupu. null = jeszcze nietkniety, bierz zalecana.
  int? _kopieDoKupienia;

  @override
  void initState() {
    super.initState();
    _s.addListener(_onChange);
    _backup.addListener(_onChange);
    _s.connect();
    _backup.load().then((_) => _backup.schedule(_s));
    // Kopia zapasowa chodzi z zegara TEJ apki, wiec zamkniecie okna zabiloby ja razem z oknem.
    // Krzyzyk chowa do zasobnika, a przy pierwszym razie mowi o tym wprost.
    Zasobnik.i
      ..onKopia = () { if (!_backup.running && _busy == null) _backup.run(_s); }
      ..pytanie = _pytanieOZasobnik
      ..start();
    SharedPreferences.getInstance().then((p) {
      final l = p.getStringList('sensmos_puste_foldery') ?? const [];
      if (mounted) setState(() => _puste.addAll(l));
    });
    // Kopie dochodza w tle (tik dublowania po stronie serwera), wiec liczba kopii zmienia sie
    // bez naszego udzialu. Bez odswiezania czlowiek patrzy na „0 kopii" i mysli, ze cos padlo.
    _tick = Timer.periodic(const Duration(seconds: 60), (_) {
      if (_busy == null && !_backup.running && _s.connected) _s.refresh().catchError((_) {});
    });
  }

  void _onChange() { if (mounted) setState(() {}); }

  /// Zadawane raz na instalacje, przy pierwszym zamknieciu okna. „Nie" nie jest kara — od tej
  /// pory krzyzyk po prostu konczy apke, a wlaczyc chowanie mozna z menu konta.
  Future<bool> _pytanieOZasobnik() async {
    if (!mounted) return true;
    final v = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: card,
      title: const Text('Sensmos Store', style: TextStyle(fontSize: 15)),
      content: Text(t('tray.hidden'), style: const TextStyle(color: muted, fontSize: 12.5)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('tray.quit'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: teal),
            child: Text(t('menu.hide'), style: const TextStyle(color: Colors.black))),
      ],
    ));
    return v ?? true;
  }

  @override
  void dispose() {
    _s.removeListener(_onChange);
    _backup.removeListener(_onChange);
    _tick?.cancel();
    _search.dispose(); _searchFocus.dispose();
    _s.dispose(); _backup.dispose();
    super.dispose();
  }

  // ── dane widoku ────────────────────────────────────────────────────────────

  /// Wszystkie katalogi: te wynikajace z nazw plikow ORAZ te zalozone recznie, jeszcze puste.
  List<String> get _folders {
    final set = <String>{};
    for (final f in _s.files) {
      final d = f.folder;
      if (d.isEmpty) continue;
      // każdy poziom osobno, żeby drzewo miało gałęzie pośrednie
      final parts = d.split('/');
      for (var i = 1; i <= parts.length; i++) { set.add(parts.take(i).join('/')); }
    }
    // Pusty katalog przestaje byc „nasza notatka" w chwili, gdy pojawia sie w nim pliki.
    _puste.removeWhere(set.contains);
    for (final d in _puste) {
      final parts = d.split('/');
      for (var i = 1; i <= parts.length; i++) { set.add(parts.take(i).join('/')); }
    }
    final l = set.toList()..sort();
    return l;
  }

  /// Katalogi lezace BEZPOSREDNIO w biezacym — to one ida na gore listy.
  List<String> get _podkatalogi {
    final tu = <String>{};
    for (final d in _folders) {
      if (_folder.isEmpty) {
        if (!d.contains('/')) tu.add(d);
      } else if (d.startsWith('$_folder/')) {
        final reszta = d.substring(_folder.length + 1);
        tu.add('$_folder/${reszta.split('/').first}');
      }
    }
    final l = tu.toList()..sort();
    return l;
  }

  int _ilePlikow(String folder) =>
      _s.files.where((f) => f.folder == folder || f.folder.startsWith('$folder/')).length;

  /// Ile plikow czeka na druga kopie. Zero = nie ma czego filtrowac.
  int get _ileUwaga => _s.files.where((f) => f.copies < 2).length;

  List<StoreFile> get _visible {
    final q = _search.text.trim().toLowerCase();
    // Gdy nie ma juz czego pokazywac, filtr sam sie zdejmuje — inaczej zostawalby wlaczony bez
    // widocznego przelacznika i lista bylaby pusta bez podania powodu.
    final uwaga = _tylkoUwaga && _ileUwaga > 0;
    var l = _s.files.where((f) {
      // Wyszukiwarka i filtr „brakuje kopii" przeszukuja CALOSC — czlowiek szuka pliku albo
      // pyta „czy wszystko jest bezpieczne", a nie „co jest w tym katalogu". Licznik na chipie
      // tez liczy po calym koncie, wiec ograniczenie do katalogu dawalo pusta liste przy „1".
      if (q.isEmpty && !uwaga && f.folder != _folder) return false;
      if (uwaga && f.copies >= 2) return false;
      if (q.isEmpty) return true;
      return (f.name ?? f.id).toLowerCase().contains(q);
    }).toList();
    int cmp(StoreFile a, StoreFile b) {
      switch (_sort) {
        case SortBy.name: return a.baseName.toLowerCase().compareTo(b.baseName.toLowerCase());
        case SortBy.size: return a.sizeB.compareTo(b.sizeB);
        case SortBy.date:
          return (a.createdAt ?? DateTime(2000)).compareTo(b.createdAt ?? DateTime(2000));
      }
    }
    l.sort((a, b) => _asc ? cmp(a, b) : cmp(b, a));
    return l;
  }

  // ── akcje ──────────────────────────────────────────────────────────────────

  Future<void> _run(String label, Future<void> Function() body) async {
    setState(() { _busy = label; _progress = null; });
    try {
      await body();
    } catch (e) {
      if (mounted) _toast('$e', bad: true);
    }
    if (mounted) setState(() { _busy = null; _progress = null; });
  }

  void _toast(String msg, {bool bad = false}) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: bad ? red : card,
            behavior: SnackBarBehavior.floating, width: 460),
      );

  Future<void> _pickAndUpload() async {
    final picked = await FilePicker.platform.pickFiles(allowMultiple: true);
    final paths = picked?.files.where((f) => f.path != null && f.size > 0)
        .map((f) => f.path!).toList() ?? [];
    if (paths.isNotEmpty) await _uploadPaths(paths);
  }

  Future<void> _uploadPaths(List<String> paths) => _run(t('busy.uploading'), () async {
        // Katalog upuszczony razem z plikami wchodzi w całości — struktura ląduje w nazwach.
        final pliki = <(File, String)>[];
        for (final p in paths) {
          final t = FileSystemEntity.typeSync(p);
          if (t == FileSystemEntityType.directory) {
            final base = p.split(Platform.pathSeparator).last;
            await for (final e in Directory(p).list(recursive: true, followLinks: false)) {
              if (e is! File) continue;
              final rel = e.path.substring(p.length)
                  .replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), '');
              final sub = rel.contains('/') ? rel.substring(0, rel.lastIndexOf('/')) : '';
              pliki.add((e, [_folder, base, sub].where((x) => x.isNotEmpty).join('/')));
            }
          } else if (t == FileSystemEntityType.file) {
            pliki.add((File(p), _folder));
          }
        }
        for (var i = 0; i < pliki.length; i++) {
          final (f, folder) = pliki[i];
          setState(() => _busy = t('busy.uploadingN', {
                'i': i + 1, 'n': pliki.length,
                'f': f.path.split(Platform.pathSeparator).last,
              }));
          await _s.upload(f, folder: folder,
              onProgress: (v) { if (mounted) setState(() => _progress = v); });
        }
        await _s.refresh();
        _toast(t('toast.uploaded', {
          'files': liczba('plural.files', pliki.length),
          'route': t(_s.lastRoute == 'direct' ? 'route.direct' : 'route.server'),
        }));
      });

  Future<void> _downloadSel() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null) return;
    final wanted = _s.files.where((f) => _sel.contains(f.id)).toList();
    await _run(t('busy.downloading'), () async {
      for (var i = 0; i < wanted.length; i++) {
        setState(() => _busy = t('busy.downloadingN',
            {'i': i + 1, 'n': wanted.length, 'f': wanted[i].baseName}));
        await _s.download(wanted[i], dir,
            onProgress: (v) { if (mounted) setState(() => _progress = v); });
      }
      _toast(t('toast.saved',
          {'files': liczba('plural.files', wanted.length), 'dir': dir}));
    });
  }

  Future<void> _deleteSel() async {
    final n = _sel.length;
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: card,
      title: Text(t('dlg.deleteTitle', {'files': liczba('plural.files', n)})),
      content: Text(t('dlg.deleteBody'), style: const TextStyle(color: muted)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('dlg.cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: red), child: Text(t('act.delete'))),
      ]));
    if (ok != true) return;
    await _run(t('busy.deleting'), () async {
      for (final f in _s.files.where((f) => _sel.contains(f.id)).toList()) {
        await _s.remove(f);
      }
      _sel.clear();
      await _s.refresh();
      _toast(t('toast.deleted', {'files': liczba('plural.files', n)}));
    });
  }

  /// „Nowy folder" nie tworzy niczego na serwerze i nie ma czego tworzyc: katalog to przedrostek
  /// w ZASZYFROWANEJ nazwie, wiec istnieje dokladnie tak dlugo, jak lezy w nim plik. Przechodzimy
  /// wiec do niego i nastepna wysylka go „zaklada".
  Future<void> _newFolder() async {
    final c = TextEditingController();
    final n = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: card,
      title: Text(t('dlg.newFolder'), style: const TextStyle(fontSize: 15)),
      content: TextField(
        controller: c, autofocus: true,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: t('dlg.folderHint'),
          helperText: t('dlg.folderHelp'),
          helperStyle: const TextStyle(fontSize: 10.5, color: faint),
        ),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('dlg.cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text),
            style: FilledButton.styleFrom(backgroundColor: teal),
            child: Text(t('dlg.go'), style: const TextStyle(color: Colors.black))),
      ],
    ));
    final czysty = (n ?? '').trim().replaceAll(RegExp(r'^/+|/+$'), '');
    if (czysty.isEmpty || !mounted) return;
    setState(() { _puste.add(czysty); _folder = czysty; _sel.clear(); });
    final p = await SharedPreferences.getInstance();
    await p.setStringList('sensmos_puste_foldery', _puste.toList());
    if (mounted) _toast(t('toast.folderReady', {'f': czysty}));
  }

  /// Odtworzenie WSZYSTKIEGO do wskazanego katalogu. To jest wlasciwy test kopii zapasowej:
  /// backup, ktorego nikt nigdy nie odtworzyl, jest tylko rachunkiem za miejsce.
  Future<void> _restoreAll() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null) return;
    final wszystkie = _s.files;
    await _run(t('busy.restoring'), () async {
      var ok = 0;
      final zle = <String>[];
      for (var i = 0; i < wszystkie.length; i++) {
        setState(() => _busy = t('busy.restoringN',
            {'i': i + 1, 'n': wszystkie.length, 'f': wszystkie[i].baseName}));
        try {
          await _s.download(wszystkie[i], dir,
              onProgress: (v) { if (mounted) setState(() => _progress = v); });
          ok++;
        } catch (e) {
          zle.add(wszystkie[i].baseName);
        }
      }
      _toast(
          zle.isEmpty
              ? t('toast.restored', {'files': liczba('plural.files', ok), 'dir': dir})
              : t('toast.restoreFail',
                  {'ok': ok, 'bad': zle.length, 'list': zle.take(3).join(', ')}),
          bad: zle.isNotEmpty);
    });
  }

  /// Sprawdzenie zaznaczonych BEZ zapisywania: pobieramy, liczymy hashe, kasujemy. Sprawdza
  /// naraz trzy rzeczy — ze sprzedawca oddaje bajty, ze sie zgadzaja z podpisem i ze klucz otwiera.
  Future<void> _verifySel() async {
    final wanted = _s.files.where((f) => _sel.contains(f.id)).toList();
    final tmp = await Directory.systemTemp.createTemp('sensmos-verify-');
    await _run(t('busy.verifying'), () async {
      var ok = 0;
      final zle = <String>[];
      for (var i = 0; i < wanted.length; i++) {
        setState(() => _busy = t('busy.verifyingN',
            {'i': i + 1, 'n': wanted.length, 'f': wanted[i].baseName}));
        try {
          final f = await _s.download(wanted[i], tmp.path,
              onProgress: (v) { if (mounted) setState(() => _progress = v); });
          await f.delete();
          ok++;
        } catch (e) {
          zle.add(wanted[i].baseName);
        }
      }
      try { await tmp.delete(recursive: true); } catch (_) {}
      _toast(
          zle.isEmpty
              ? t('toast.verifyOk', {'files': liczba('plural.files', ok)})
              : t('toast.verifyBad',
                  {'ok': ok, 'bad': zle.length, 'list': zle.take(3).join(', ')}),
          bad: zle.isNotEmpty);
    });
  }

  // ── budowa ─  // ── budowa ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyA, control: true): () =>
            setState(() => _sel..clear()..addAll(_visible.map((f) => f.id))),
        const SingleActivator(LogicalKeyboardKey.escape): () => setState(_sel.clear),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): _searchFocus.requestFocus,
        const SingleActivator(LogicalKeyboardKey.f5): () => _run(t('busy.refreshing'), _s.refresh),
        const SingleActivator(LogicalKeyboardKey.keyU, control: true): _pickAndUpload,
        const SingleActivator(LogicalKeyboardKey.delete): () { if (_sel.isNotEmpty) _deleteSel(); },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Column(children: [
            Expanded(child: Row(children: [
              _sidebar(),
              const VerticalDivider(width: 1, color: line),
              Expanded(child: _main()),
            ])),
            _statusBar(),
          ]),
        ),
      ),
    );
  }

  // ── lewa kolumna ───────────────────────────────────────────────────────────

  Widget _sidebar() => Container(
        width: 268,
        color: const Color(0xFF11161D),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(children: [
              const SensmosLogo(size: 26, fontSize: null),
              const SizedBox(width: 10),
              const Text('Sensmos',
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600,
                      fontFamily: 'monospace')),
              const Spacer(),
              PopupMenuButton<String>(
                iconSize: 18,
                tooltip: t('menu.account'),
                color: card,
                onSelected: _menuKonta,
                itemBuilder: (_) => [
                  for (final k in L.kody)
                    PopupMenuItem(value: 'lang:$k', height: 34, child: Row(children: [
                      Icon(k == L.kod ? Icons.check : Icons.language,
                          size: 14, color: k == L.kod ? teal : faint),
                      const SizedBox(width: 8),
                      Text(L.nazwy[k]!, style: const TextStyle(fontSize: 12.5)),
                    ])),
                  const PopupMenuDivider(height: 6),
                  PopupMenuItem(value: 'log', height: 34, child: Row(children: [
                    const Icon(Icons.receipt_long_outlined, size: 15, color: muted),
                    const SizedBox(width: 8),
                    Text(t('menu.log'), style: const TextStyle(fontSize: 12.5)),
                  ])),
                  PopupMenuItem(value: 'hide', height: 34, child: Row(children: [
                    const Icon(Icons.keyboard_arrow_down, size: 15, color: muted),
                    const SizedBox(width: 8),
                    Text(t('menu.hide'), style: const TextStyle(fontSize: 12.5)),
                  ])),
                  PopupMenuItem(value: 'tray', height: 34, child: Row(children: [
                    Icon(Zasobnik.i.chowaj ? Icons.check_box_outlined
                                           : Icons.check_box_outline_blank,
                        size: 15, color: Zasobnik.i.chowaj ? teal : faint),
                    const SizedBox(width: 8),
                    Flexible(child: Text(t('menu.closeToTray'),
                        style: const TextStyle(fontSize: 12.5))),
                  ])),
                  // Wpuszczenie kolejnego komputera pokazujemy WYŁĄCZNIE wtedy, gdy ten ma na to
                  // pozwolenie z telefonu. Pozycja, która kończy się odmową serwera, jest gorsza
                  // niż jej brak.
                  if (DalszeParowanie.wolno(widget.pairing)) ...[
                    const PopupMenuDivider(height: 6),
                    PopupMenuItem(value: 'pairPc', height: 34, child: Row(children: [
                      const Icon(Icons.devices_other_outlined, size: 15, color: muted),
                      const SizedBox(width: 8),
                      Flexible(child: Text(t('menu.pairPc'),
                          style: const TextStyle(fontSize: 12.5))),
                    ])),
                  ],
                  const PopupMenuDivider(height: 6),
                  PopupMenuItem(value: 'unpair', height: 34, child: Row(children: [
                    const Icon(Icons.link_off, size: 15, color: red),
                    const SizedBox(width: 8),
                    Text(t('menu.unpair'),
                        style: const TextStyle(fontSize: 12.5, color: red)),
                  ])),
                ],
              ),
            ]),
          ),
          const Divider(height: 1, color: line),
          Expanded(child: ListView(padding: const EdgeInsets.all(12), children: [
            _packageCard(),
            // Foldery i kopia zapasowa bez wykupionego miejsca to puste obietnice — nie ma
            // dokad kopiowac.
            if (_s.hasPackage != false) ...[
              const SizedBox(height: 12),
              _sectionTitle(t('sec.folders')),
              _folderTile(t('folders.all'), '', Icons.folder_open),
              _drzewo(),
              const SizedBox(height: 14),
              _sectionTitle(t('sec.backup'), obok: SizedBox(
              width: 22, height: 18,
              child: IconButton(
                tooltip: t('backup.add'),
                iconSize: 15, padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 22, minHeight: 18),
                onPressed: _dodajPilnowany,
                icon: const Icon(Icons.add, color: teal),
              ),
            )),
              _backupCard(),
            ],
            // Naglowek „Aktualnosci" nalezy do samych aktualnosci — gdy ich nie ma, nie zostaje
            // po nich pusty tytul.
            News(owner: '${widget.pairing['owner']}', naglowek: _sectionTitle(t('sec.news'))),
          ])),
        ]),
      );

  /// Menu konta. Odparowanie pyta, bo jest jedyna rzecza w tej apce, ktorej nie da sie cofnac
  /// jednym klikiem — powrot wymaga telefonu i nowego kodu.
  Future<void> _menuKonta(String v) async {
    if (v.startsWith('lang:')) { await L.ustaw(v.substring(5)); if (mounted) setState(() {}); return; }
    if (v == 'log') {
      if (mounted) {
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const EkranDziennika()));
      }
      return;
    }
    if (v == 'pairPc') {
      if (mounted) {
        await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => EkranParowaniaPC(moje: widget.pairing)));
      }
      return;
    }
    if (v == 'hide') { await Zasobnik.i.schowaj(); return; }
    if (v == 'tray') {
      await Zasobnik.i.ustawChowanie(!Zasobnik.i.chowaj);
      if (mounted) setState(() {});
      return;
    }
    if (v != 'unpair' || !mounted) return;
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: card,
      title: Text(t('dlg.unpairTitle'), style: const TextStyle(fontSize: 15)),
      content: Text(t('dlg.unpairBody'),
          style: const TextStyle(color: muted, fontSize: 12.5, height: 1.4)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('dlg.cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: red),
            child: Text(t('dlg.unpairYes'))),
      ],
    ));
    if (ok == true) widget.onUnpair();
  }

  Widget _sectionTitle(String tytul, {Widget? obok}) => Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 2),
        child: Row(children: [
          Expanded(child: Text(tytul.toUpperCase(),
              style: const TextStyle(color: faint, fontSize: 10, letterSpacing: 1.2,
                  fontWeight: FontWeight.w600))),
          ?obok,
        ]),
      );

  Widget _packageCard() {
    if (_s.hasPackage == false) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(10),
            border: Border.all(color: amber.withValues(alpha: 0.4))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.sd_storage_outlined, size: 15, color: amber),
            const SizedBox(width: 6),
            Expanded(child: Text(t('nopkg.card'), overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: amber, fontSize: 12.5,
                    fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 5),
          Text(t('nopkg.cardBody'),
              style: const TextStyle(color: muted, fontSize: 11, height: 1.3)),
        ]),
      );
    }
    final gb = (_s.limitB / 1073741824);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(10),
          border: Border.all(color: line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.sd_storage_outlined, size: 15, color: teal),
          const SizedBox(width: 6),
          Expanded(child: Text(t('pkg.title', {'n': gb.toStringAsFixed(0)}),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 12.5,
                  fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: _s.usedRatio.clamp(0, 1),
            minHeight: 6,
            backgroundColor: const Color(0xFF0E1116),
            color: _s.usedRatio > 0.9 ? amber : teal,
          ),
        ),
        const SizedBox(height: 6),
        Text(t('pkg.used',
                {'size': _fmt(_s.usedB), 'files': liczba('plural.files', _s.files.length)}),
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: muted, fontSize: 11)),
        Text(t('pkg.daily', {'galu': _s.daily.toStringAsFixed(2), 'n': _s.sellers}),
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: faint, fontSize: 11)),
        // Ile kopii pakiet MA MIEC — klikalne, bo to jedno pytanie, wiec wolno je zadac
        // w okienku. Gdy sprzedawca zamilknie, pod spodem wychodzi, ze trwa odbudowa;
        // udawanie kompletu byloby tu najgorsza z mozliwych uprzejmosci.
        if (_s.kopiiPakietu > 0) InkWell(
          onTap: _busy == null ? _zmienKopie : null,
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(children: [
              Expanded(child: Text(t('copies.now', {'n': _s.kopiiPakietu}),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: faint, fontSize: 11))),
              const Icon(Icons.tune, size: 12, color: faint),
            ]),
          ),
        ),
        if (_s.kopiiTeraz > 0 && _s.kopiiTeraz < _s.kopiiPakietu)
          Text(t('copies.rebuild', {'a': _s.kopiiTeraz, 'b': _s.kopiiPakietu}),
              style: const TextStyle(color: amber, fontSize: 10.5, height: 1.3)),
        if (!_s.canRead) ...[
          const SizedBox(height: 8),
          Text(t('pkg.writeOnly'),
              style: const TextStyle(color: amber, fontSize: 10.5, height: 1.3)),
        ],
      ]),
    );
  }

  /// Drzewo katalogow. Przy kilkudziesieciu folderach lista wypychalaby kopie zapasowa
  /// i aktualnosci poza ekran, wiec domyslnie pokazujemy pierwsze kilkanascie.
  ///
  /// Nadmiar chowa sie pod „jeszcze N", a NIE pod wlasnym paskiem przewijania. Obszar
  /// przewijania w obszarze przewijania lapie kolko myszy i po dojechaniu do konca nie oddaje
  /// go kolumnie — czyli do tego, co lezy nizej, nie da sie dojechac. Kolumna ma miec jeden
  /// scroll i tyle.
  static const _maxKatalogow = 11;
  bool _wszystkieFoldery = false;

  Widget _drzewo() {
    final f = _folders;
    final ukryte = f.length - _maxKatalogow;
    final pierwsze = f.take(_maxKatalogow).toList();
    final widoczne = (_wszystkieFoldery || ukryte <= 0)
        ? f
        : [
            ...pierwsze,
            // katalog, w ktorym stoisz, nie moze zniknac tylko dlatego, ze jest daleko w alfabecie
            if (_folder.isNotEmpty && !pierwsze.contains(_folder)) _folder,
          ];
    return Column(children: [
      for (final x in widoczne)
        _folderTile(x.split('/').last, x, Icons.folder, depth: x.split('/').length),
      if (ukryte > 0)
        InkWell(
          onTap: () => setState(() => _wszystkieFoldery = !_wszystkieFoldery),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 5, 6, 3),
            child: Row(children: [
              Icon(_wszystkieFoldery ? Icons.expand_less : Icons.expand_more,
                  size: 15, color: teal),
              const SizedBox(width: 6),
              Text(
                  _wszystkieFoldery
                      ? t('folders.less')
                      : t('folders.more', {'n': ukryte}),
                  style: const TextStyle(color: teal, fontSize: 11)),
            ]),
          ),
        ),
    ]);
  }

  Widget _folderTile(String label, String path, IconData icon, {int depth = 0}) {
    final wybrany = _folder == path;
    final ile = path.isEmpty ? _s.files.length : _ilePlikow(path);
    return InkWell(
      onTap: () => setState(() { _folder = path; _sel.clear(); }),
      child: Container(
        padding: EdgeInsets.only(left: 6.0 + depth * 12, right: 6, top: 5, bottom: 5),
        decoration: BoxDecoration(
            color: wybrany ? teal.withValues(alpha: 0.12) : null,
            borderRadius: BorderRadius.circular(6)),
        child: Row(children: [
          Icon(icon, size: 14, color: wybrany ? teal : muted),
          const SizedBox(width: 7),
          Expanded(child: Text(label, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: wybrany ? Colors.white : muted, fontSize: 12))),
          Text('$ile', style: const TextStyle(color: faint, fontSize: 10.5)),
        ]),
      ),
    );
  }

  Widget _backupCard() {
    if (_backup.lista.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(10),
            border: Border.all(color: line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t('backup.intro'),
              style: const TextStyle(color: muted, fontSize: 11, height: 1.35)),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: OutlinedButton.icon(
              onPressed: _dodajPilnowany,
              icon: const Icon(Icons.create_new_folder_outlined, size: 15),
              style: OutlinedButton.styleFrom(foregroundColor: teal,
                  padding: const EdgeInsets.symmetric(vertical: 8)),
              label: Text(t('backup.addFirst'), style: const TextStyle(fontSize: 12)))),
        ]),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final w in _backup.lista) _pilnowanyKafel(w),
      Row(children: [
        SizedBox(width: 26, child: Checkbox(
          value: _backup.auto, activeColor: teal,
          visualDensity: VisualDensity.compact,
          onChanged: (v) async {
            _backup.auto = v == true;
            await _backup.save();
            _backup.schedule(_s);
            setState(() {});
          },
        )),
        const SizedBox(width: 2),
        Expanded(child: Text(t('backup.auto', {'n': _backup.everyMin}),
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: muted, fontSize: 11))),
      ]),
    ]);
  }

  /// Jeden pilnowany katalog: skad, dokad, kiedy ostatnio i co z nim zrobic.
  Widget _pilnowanyKafel(Pilnowany w) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(10, 8, 6, 10),
        decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(10),
            border: Border.all(color: line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.folder_outlined, size: 14, color: muted),
            const SizedBox(width: 6),
            Expanded(child: Text(w.nazwa, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 12,
                    fontWeight: FontWeight.w600))),
            SizedBox(width: 26, height: 26, child: PopupMenuButton<String>(
              iconSize: 15, color: card, padding: EdgeInsets.zero,
              tooltip: '',
              onSelected: (v) => _menuPilnowanego(w, v),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'now', height: 34,
                    child: Text(t('backup.now'), style: const TextStyle(fontSize: 12.5))),
                PopupMenuItem(value: 'rename', height: 34,
                    child: Text(t('backup.rename'), style: const TextStyle(fontSize: 12.5))),
                PopupMenuItem(value: 'stop', height: 34,
                    child: Text(t('backup.stop'),
                        style: const TextStyle(fontSize: 12.5, color: red))),
              ],
            )),
          ]),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(w.dir, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: faint, fontSize: 10)),
          ),
          const SizedBox(height: 5),
          Row(children: [
            const Icon(Icons.subdirectory_arrow_right, size: 12, color: teal),
            const SizedBox(width: 4),
            Expanded(child: Text(
                w.prefix.isEmpty ? t('backup.targetRoot') : t('backup.target', {'f': w.prefix}),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: muted, fontSize: 10.5))),
          ]),
          const SizedBox(height: 6),
          Text(
              w.running ? w.status
                  : w.lastRun == null ? t('backup.never')
                  : t('backup.last', {'when': _kiedy(w.lastRun!)}),
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: w.running ? teal : faint, fontSize: 10.5, height: 1.25)),
          if (!w.running) ...[
            const SizedBox(height: 6),
            SizedBox(width: double.infinity, height: 26, child: OutlinedButton(
              onPressed: _busy != null || _backup.running ? null : () => _backup.run(_s, w),
              style: OutlinedButton.styleFrom(
                  foregroundColor: teal, padding: EdgeInsets.zero),
              child: Text(t('backup.now'), style: const TextStyle(fontSize: 11)),
            )),
          ],
        ]),
      );

  Future<void> _menuPilnowanego(Pilnowany w, String v) async {
    if (v == 'now') { await _backup.run(_s, w); return; }
    if (v == 'rename') {
      final n = await _spytajONazwe(t('dlg.renameTitle'), t('dlg.renameBody'), w.prefix);
      if (n != null) await _backup.przemianuj(w, n);
      return;
    }
    if (v != 'stop' || !mounted) return;
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: card,
      title: Text(t('dlg.stopTitle'), style: const TextStyle(fontSize: 15)),
      content: Text(t('dlg.stopBody'),
          style: const TextStyle(color: muted, fontSize: 12.5, height: 1.4)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('dlg.cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: red),
            child: Text(t('dlg.stopYes'))),
      ],
    ));
    if (ok == true) { await _backup.usun(w); _backup.schedule(_s); }
  }

  /// Dodanie katalogu do pilnowania. Nazwa folderu docelowego jest OSOBNYM pytaniem, bo
  /// wrzucanie wszystkiego do jednego „backup" po tygodniu przestaje cokolwiek znaczyc.
  Future<void> _dodajPilnowany() async {
    final d = await FilePicker.platform.getDirectoryPath();
    if (d == null || !mounted) return;
    final domyslna = d.split(RegExp(r'[\\/]')).where((x) => x.isNotEmpty).last;
    var wFolderze = true;
    final c = TextEditingController(text: domyslna);
    final wynik = await showDialog<String>(context: context, builder: (ctx) => StatefulBuilder(
      builder: (_, ustaw) => AlertDialog(
        backgroundColor: card,
        title: Text(t('dlg.watchTitle', {'f': domyslna}), style: const TextStyle(fontSize: 15)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            SizedBox(width: 30, child: Checkbox(
              value: wFolderze, activeColor: teal,
              visualDensity: VisualDensity.compact,
              onChanged: (v) => ustaw(() => wFolderze = v == true),
            )),
            Expanded(child: Text(t('dlg.parent'),
                style: const TextStyle(color: muted, fontSize: 12.5))),
          ]),
          TextField(
            controller: c, enabled: wFolderze, autofocus: true,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              labelText: t('dlg.parentName'),
              helperText: t('dlg.folderHelp'),
              helperMaxLines: 2,
              helperStyle: const TextStyle(fontSize: 10.5, color: faint),
            ),
            onSubmitted: (v) => Navigator.pop(ctx, wFolderze ? v : ''),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('dlg.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, wFolderze ? c.text : ''),
              style: FilledButton.styleFrom(backgroundColor: teal),
              child: Text(t('dlg.save'), style: const TextStyle(color: Colors.black))),
        ],
      ),
    ));
    if (wynik == null) return;
    await _backup.dodaj(d, wynik.trim().replaceAll(RegExp(r'^/+|/+$'), ''));
    _backup.schedule(_s);
    if (mounted) setState(() {});
  }

  Future<String?> _spytajONazwe(String tytul, String pomoc, String teraz) async {
    final c = TextEditingController(text: teraz);
    final v = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: card,
      title: Text(tytul, style: const TextStyle(fontSize: 15)),
      content: TextField(
        controller: c, autofocus: true,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          helperText: pomoc, helperMaxLines: 3,
          helperStyle: const TextStyle(fontSize: 10.5, color: faint),
        ),
        onSubmitted: (x) => Navigator.pop(ctx, x),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('dlg.cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text),
            style: FilledButton.styleFrom(backgroundColor: teal),
            child: Text(t('dlg.save'), style: const TextStyle(color: Colors.black))),
      ],
    ));
    return v?.trim().replaceAll(RegExp(r'^/+|/+$'), '');
  }

  // ── prawa część ─  // ── prawa część ────────────────────────────────────────────────────────────

  Widget _main() {
    // Konto bez wykupionego miejsca NIE MOZE wygladac jak pusty, dzialajacy Store. Wczesniej
    // widzialo pusta liste i „Pakiet 1 GB", a prawda wychodzila dopiero przy pierwszej wysylce,
    // po angielsku i w formie wyjatku.
    if (_s.hasPackage == false) return _ekranZakupu();
    return _listaPlikow();
  }

  Widget _listaPlikow() => DropTarget(
        onDragEntered: (_) => setState(() => _dropping = true),
        onDragExited: (_) => setState(() => _dropping = false),
        onDragDone: (d) {
          setState(() => _dropping = false);
          final paths = d.files.map((f) => f.path).where((p) => p.isNotEmpty).toList();
          if (paths.isNotEmpty) _uploadPaths(paths);
        },
        child: Stack(children: [
          Column(children: [
            _toolbar(),
            const Divider(height: 1, color: line),
            if (_busy != null) _progressBar(),
            if (_s.unpaidDays > 0) _bannerZaleglosc(),
            if (_s.niedokonczone.isNotEmpty) _bannerNiedokonczone(),
            Expanded(child: Row(children: [
              Expanded(child: Column(children: [
                if (_visible.isNotEmpty) _header(),
                Expanded(child: _table()),
              ])),
              // Panel szczegolow ma sens dopiero wtedy, gdy zostaje miejsce na tabele.
              if (_sel.length == 1 && MediaQuery.of(context).size.width > 900) ...[
                const VerticalDivider(width: 1, color: line),
                _details(_s.files.firstWhere((f) => f.id == _sel.first)),
              ],
            ])),
          ]),
          if (_dropping)
            Positioned.fill(child: IgnorePointer(child: Container(
              color: teal.withValues(alpha: 0.10),
              child: Center(child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                decoration: BoxDecoration(
                    color: card, borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: teal, width: 2)),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.file_download_outlined, color: teal, size: 30),
                  const SizedBox(height: 8),
                  Text(_folder.isEmpty ? t('drop.here') : t('drop.into', {'f': _folder}),
                      style: const TextStyle(color: Colors.white, fontSize: 13)),
                ]),
              )),
            ))),
        ]),
      );

  /// Konto bez pakietu: powod, oferta i przycisk. Wykup idzie stad, a nie „w telefonie" —
  /// odsylanie czlowieka do innego urzadzenia po to, zeby wydal pieniadze, jest wymyslone.
  Widget _ekranZakupu() {
    final kopii = (_kopieDoKupienia ?? _s.zalecaneKopii).clamp(_s.minKopii, _s.maxKopii);
    // Sufit zalezy od liczby kopii — kazda musi trafic do innego wlasciciela, wiec przy trzech
    // ogranicza nas trzeci najlepszy sprzedawca, a nie drugi.
    final max = _s.maxGbDlaKopii[kopii] ?? _s.maxGb;
    final gb = max < 1 ? 1 : _gbDoKupienia.clamp(1, max);
    final dziennie = _s.zaGbZaKopie * kopii * gb;
    final dni = dziennie > 0 ? (_s.dostepneGalu / dziennie).floor() : 0;
    return Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SensmosLogo(size: 38, fontSize: null),
          const SizedBox(height: 16),
          Text(t('nopkg.title'), textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Text(t('nopkg.body'), textAlign: TextAlign.center,
              style: const TextStyle(color: muted, fontSize: 12.5, height: 1.45)),
          const SizedBox(height: 22),
          if (max < 1) ...[
            Text(t('nopkg.none'), textAlign: TextAlign.center,
                style: const TextStyle(color: amber, fontSize: 12.5)),
            const SizedBox(height: 16),
          ] else ...[
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: line)),
              child: Column(children: [
                Row(children: [
                  Text(t('nopkg.size'),
                      style: const TextStyle(color: muted, fontSize: 12)),
                  const Spacer(),
                  Text(t('nopkg.max', {'n': max}),
                      style: const TextStyle(color: faint, fontSize: 11)),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  IconButton(
                    iconSize: 22,
                    onPressed: gb > 1 ? () => setState(() => _gbDoKupienia = gb - 1) : null,
                    icon: const Icon(Icons.remove_circle_outline, color: teal),
                  ),
                  Expanded(child: Text('$gb GB', textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 26,
                          fontWeight: FontWeight.w600))),
                  IconButton(
                    iconSize: 22,
                    onPressed: gb < max ? () => setState(() => _gbDoKupienia = gb + 1) : null,
                    icon: const Icon(Icons.add_circle_outline, color: teal),
                  ),
                ]),
                if (max > 1)
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(trackHeight: 3),
                    child: Slider(
                      value: gb.toDouble(), min: 1, max: max.toDouble(),
                      divisions: max - 1, activeColor: teal, inactiveColor: line,
                      onChanged: (v) => setState(() => _gbDoKupienia = v.round()),
                    ),
                  ),
                const Divider(height: 18, color: line),
                _wyborKopii(kopii, (n) => setState(() => _kopieDoKupienia = n)),
                const SizedBox(height: 10),
                Text(t('nopkg.cost',
                        {'galu': dziennie.toStringAsFixed(2), 'n': kopii}),
                    style: const TextStyle(color: Colors.white, fontSize: 12.5)),
                const SizedBox(height: 4),
                Text(
                    t('nopkg.balance', {
                      'galu': _s.dostepneGalu.toStringAsFixed(2),
                      'days': dni,
                    }),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: dni < 7 ? amber : muted, fontSize: 11.5, height: 1.35)),
              ]),
            ),
            const SizedBox(height: 14),
            SizedBox(width: double.infinity, child: FilledButton(
              onPressed: _busy == null ? () => _kup(gb, kopii) : null,
              style: FilledButton.styleFrom(backgroundColor: teal,
                  padding: const EdgeInsets.symmetric(vertical: 13)),
              child: Text(t('nopkg.buy', {'n': gb}),
                  style: const TextStyle(color: Colors.black, fontSize: 13,
                      fontWeight: FontWeight.w600)),
            )),
            const SizedBox(height: 6),
          ],
          TextButton.icon(
            onPressed: _busy == null
                ? () => _run(t('busy.refreshing'), _s.odswiezStan) : null,
            icon: const Icon(Icons.refresh, size: 15, color: muted),
            label: Text(t('nopkg.recheck'),
                style: const TextStyle(color: muted, fontSize: 12)),
          ),
        ]),
      ),
    ));
  }

  /// Zmiana liczby kopii wykupionego pakietu. Jedno pytanie, wiec okienko — te same widelki
  /// i to samo wyjasnienie, co przy zakupie.
  Future<void> _zmienKopie() async {
    var wybrane = _s.kopiiPakietu.clamp(_s.minKopii, _s.maxKopii);
    final n = await showDialog<int>(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, ustaw) => AlertDialog(
        backgroundColor: card,
        title: Text(t('copies.label'), style: const TextStyle(fontSize: 15)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: _wyborKopii(wybrane, (v) => ustaw(() => wybrane = v)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('dlg.cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, wybrane),
              style: FilledButton.styleFrom(backgroundColor: teal),
              child: Text(t('dlg.go'))),
        ],
      ),
    ));
    if (n == null || n == _s.kopiiPakietu || !mounted) return;
    await _run(t('busy.copies'), () async {
      final r = await _s.ustawKopie(n);
      if (r['ok'] == true) { _toast(t('copies.done', {'n': n})); return; }
      _toast('${r['error']}', bad: true);
    });
  }

  /// Wybor liczby kopii. Zalecana jest OPISANA, nie tylko podswietlona — czlowiek ma wiedziec
  /// dlaczego, zanim zaplaci o polowe wiecej.
  Widget _wyborKopii(int wybrane, void Function(int) wybierz) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t('copies.label'), style: const TextStyle(color: muted, fontSize: 12)),
        const SizedBox(height: 6),
        Row(children: [
          for (var n = _s.minKopii; n <= _s.maxKopii; n++) Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              selected: wybrane == n,
              onSelected: _busy == null ? (_) => wybierz(n) : null,
              backgroundColor: bg,
              selectedColor: teal.withValues(alpha: 0.18),
              side: BorderSide(color: wybrane == n ? teal : line),
              showCheckmark: false,
              label: Text(n == _s.zalecaneKopii ? t('copies.rec', {'n': n}) : '$n',
                  style: TextStyle(color: wybrane == n ? teal : muted, fontSize: 11.5)),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Text(t('copies.why'),
            style: const TextStyle(color: faint, fontSize: 10.5, height: 1.35)),
      ]);

  Future<void> _kup(int gb, int kopii) => _run(t('busy.refreshing'), () async {
        final r = await _s.kup(gb, kopii);
        if (r['ok'] == true) { _toast(t('nopkg.bought', {'n': gb})); return; }
        // Brak pokrycia to jedyna odmowa, ktora czlowiek moze sam naprawic — wiec podajemy
        // dokladne liczby od serwera, a nie samo „nie udalo sie".
        if (r['funds'] == true) {
          _toast(
              t('nopkg.funds', {
                'need': (num.tryParse('${r['need']}') ?? 0).toStringAsFixed(1),
                'have': (num.tryParse('${r['have']}') ?? 0).toStringAsFixed(1),
              }),
              bad: true);
          return;
        }
        _toast('${r['error']}', bad: true);
      });

  /// Zaleglosc wstrzymuje WYSYLKI, ale nie rusza plikow. Bez tego rozroznienia komunikat
  /// o nieoplaconej dobie czyta sie jak „stracisz dane".
  Widget _bannerZaleglosc() => Container(
        margin: const EdgeInsets.fromLTRB(14, 8, 18, 0),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: amber.withValues(alpha: 0.07),
            border: Border.all(color: amber.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          const Icon(Icons.pause_circle_outline, size: 18, color: amber),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('arrears.title', {'n': _s.unpaidDays}),
                style: const TextStyle(color: amber, fontSize: 12.5,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(t('arrears.body'),
                style: const TextStyle(color: muted, fontSize: 11, height: 1.3)),
          ])),
        ]),
      );

  /// Wysylka, ktora sie urwala, zostawia wpis pliku bez ani jednego bajtu u sprzedawcow.
  /// Siec tego nie naprawi — nie ma z czego kopiowac — wiec musi to zobaczyc czlowiek.
  Widget _bannerNiedokonczone() => Container(
        margin: const EdgeInsets.fromLTRB(14, 8, 18, 0),
        padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
        decoration: BoxDecoration(
            color: amber.withValues(alpha: 0.07),
            border: Border.all(color: amber.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          const Icon(Icons.report_gmailerrorred_outlined, size: 18, color: amber),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('stuck.title', {'files': liczba('plural.files', _s.niedokonczone.length)}),
                style: const TextStyle(color: amber, fontSize: 12.5,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(t('stuck.body'),
                style: const TextStyle(color: muted, fontSize: 11, height: 1.3)),
          ])),
          const SizedBox(width: 10),
          TextButton.icon(
              onPressed: _busy == null ? _ponowNiedokonczone : null,
              icon: const Icon(Icons.refresh, size: 15, color: teal),
              label: Text(t('stuck.retry'),
                  style: const TextStyle(color: teal, fontSize: 12))),
          TextButton(
              onPressed: _busy == null ? _skasujNiedokonczone : null,
              child: Text(t('stuck.forget'),
                  style: const TextStyle(color: muted, fontSize: 12))),
        ]),
      );

  /// Gdzie na dysku lezy oryginal. Najpewniej wie o tym dziennik wysylek, ale plik, ktory
  /// przyszedl z pilnowanego katalogu, ma sciezke DAJACA SIE WYLICZYC — folder w Store to
  /// dokladnie ten sam uklad, co na dysku, tylko z innym korzeniem.
  File? _zrodloLokalne(StoreFile f) {
    final n = f.name;
    if (n == null) return null;
    final zDziennika = _s.wLocie[n];
    if (zDziennika != null) return File(zDziennika);
    for (final w in _backup.lista) {
      final pre = w.prefix.isEmpty ? '' : '${w.prefix}/';
      if (pre.isNotEmpty && !n.startsWith(pre)) continue;
      final rel = n.substring(pre.length).replaceAll('/', Platform.pathSeparator);
      final p = File('${w.dir}${Platform.pathSeparator}$rel');
      if (p.existsSync()) return p;
    }
    return null;
  }

  /// Ponowienie z ORYGINALU na dysku. Duch po przerwanej wysylce ginie, zeby nie zostawic
  /// dwoch wpisow o tej samej nazwie.
  Future<void> _ponowNiedokonczone() => _run(t('busy.uploading'), () async {
        final zgubione = _s.niedokonczone;
        var ok = 0;
        final brak = <String>[];
        for (var i = 0; i < zgubione.length; i++) {
          final f = zgubione[i];
          final nazwa = f.name ?? f.id;
          final zrodlo = _zrodloLokalne(f);
          if (zrodlo == null) { brak.add(nazwa); continue; }
          setState(() => _busy =
              t('busy.uploadingN', {'i': i + 1, 'n': zgubione.length, 'f': nazwa}));
          await _s.remove(f);
          final folder = nazwa.contains('/')
              ? nazwa.substring(0, nazwa.lastIndexOf('/')) : '';
          await _s.upload(zrodlo, folder: folder,
              onProgress: (v) { if (mounted) setState(() => _progress = v); });
          ok++;
        }
        _sel.clear();
        await _s.refresh();
        _toast(
            brak.isEmpty
                ? t('stuck.done', {'files': liczba('plural.files', ok)})
                : t('stuck.gone', {'p': brak.first}),
            bad: brak.isNotEmpty);
      });

  Future<void> _skasujNiedokonczone() => _run(t('busy.deleting'), () async {
        for (final f in _s.niedokonczone) {
          await _s.remove(f);
        }
        _sel.clear();
        await _s.refresh();
      });

  Widget _toolbar() => LayoutBuilder(builder: (_, c) {
    // Przy waskim oknie napisy znikaja, zostaja same ikony. Wczesniej pasek wychodzil poza obszar
    // i Flutter rysowal pasiaki — czyli wygladalo to na zepsute, choc dzialalo.
    final waski = c.maxWidth < 1000;
    final bardzoWaski = c.maxWidth < 760;
    return Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 18, 10),
        child: Row(children: [
          if (_folder.isNotEmpty) ...[
            IconButton(
              tooltip: t('tb.up'), iconSize: 17,
              onPressed: () => setState(() {
                _folder = _folder.contains('/') ? _folder.substring(0, _folder.lastIndexOf('/')) : '';
                _sel.clear();
              }),
              icon: const Icon(Icons.arrow_upward, color: muted),
            ),
            Text(_folder, style: const TextStyle(color: Colors.white, fontSize: 13)),
            const SizedBox(width: 12),
          ],
          // Pole szukania bierze CALE wolne miejsce, zamiast dzielic je ze Spacerem. Luzny
          // Flexible obok Spacera zostawial na koncu wiersza nierozdana reszte — stad dziura
          // miedzy „Add files" a prawa krawedzia okna.
          Expanded(child: Row(children: [
            Flexible(child: SizedBox(
            width: waski ? 170 : 240,
            height: 32,
            child: TextField(
              controller: _search, focusNode: _searchFocus,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 12.5),
              decoration: InputDecoration(
                isDense: true,
                hintText: t('tb.search'),
                hintStyle: const TextStyle(color: faint, fontSize: 12),
                prefixIcon: const Icon(Icons.search, size: 16, color: muted),
                suffixIcon: _search.text.isEmpty ? null : IconButton(
                  iconSize: 14, icon: const Icon(Icons.close, color: muted),
                  onPressed: () => setState(_search.clear),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: line),
                    borderRadius: BorderRadius.circular(8)),
                focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: teal),
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          )),
            const SizedBox(width: 10),
            if (!bardzoWaski) _sortButton(),
            // Ostrzezenie nie chowa sie NIGDY. Brak chipa czyta sie jako „wszystko dobrze",
            // wiec w waskim oknie zostaje sama tarcza z liczba.
            const SizedBox(width: 8),
            _uwagaChip(zwarty: waski),
          ])),
          if (_sel.isNotEmpty) ...[
            if (!waski) Text(t('tb.selected', {'n': _sel.length}),
                style: const TextStyle(color: muted, fontSize: 12)),
            const SizedBox(width: 6),
            if (_s.canRead) ...[
              _akcja(Icons.download, t('act.downloadN', {'n': _sel.length}), teal,
                  _busy == null ? _downloadSel : null, waski),
              _akcja(Icons.verified_outlined, t('act.verify'), muted,
                  _busy == null ? _verifySel : null, waski),
            ],
            _akcja(Icons.delete_outline, t('act.delete'), red,
                _busy == null ? _deleteSel : null, waski),
            const SizedBox(width: 6),
          ],
          if (!bardzoWaski) ...[
            IconButton(tooltip: t('tb.duplicates'), iconSize: 18,
                onPressed: _busy == null ? _duplikaty : null,
                icon: const Icon(Icons.content_copy_outlined, color: muted)),
            IconButton(tooltip: t('tb.newFolder'), iconSize: 18,
                onPressed: _busy == null ? _newFolder : null,
                icon: const Icon(Icons.create_new_folder_outlined, color: muted)),
            if (_s.canRead)
              IconButton(tooltip: t('tb.restoreAll'), iconSize: 18,
                  onPressed: _busy == null ? _restoreAll : null,
                  icon: const Icon(Icons.settings_backup_restore, color: muted)),
            IconButton(tooltip: t('tb.deleteAll'), iconSize: 18,
                onPressed: _busy == null || _s.files.isEmpty ? _usunWszystko : null,
                icon: const Icon(Icons.delete_sweep_outlined, color: muted)),
          ] else
            // W naprawde waskim oknie rzadsze akcje chowaja sie pod jednym przyciskiem, zamiast
            // znikac bez sladu.
            PopupMenuButton<String>(
              tooltip: t('tb.more'), iconSize: 18, color: card,
              onSelected: (v) {
                if (v == 'dup') _duplikaty();
                if (v == 'new') _newFolder();
                if (v == 'restore') _restoreAll();
                if (v == 'delall') _usunWszystko();
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'dup', child: Text(t('tb.duplicates'))),
                PopupMenuItem(value: 'new', child: Text(t('tb.newFolder'))),
                if (_s.canRead)
                  PopupMenuItem(value: 'restore', child: Text(t('tb.restoreShort'))),
                const PopupMenuDivider(height: 6),
                PopupMenuItem(value: 'delall', child: Text(t('tb.deleteAll'),
                    style: const TextStyle(color: red))),
              ],
            ),
          IconButton(tooltip: t('tb.refresh'), iconSize: 18,
              onPressed: _busy == null ? () => _run(t('busy.refreshing'), _s.refresh) : null,
              icon: const Icon(Icons.refresh, color: muted)),
          const SizedBox(width: 4),
          if (bardzoWaski)
            IconButton(
              tooltip: t('tb.addFilesKey'), iconSize: 20,
              onPressed: _busy == null ? _pickAndUpload : null,
              icon: const Icon(Icons.upload_file, color: teal),
            )
          else
            FilledButton.icon(
              onPressed: _busy == null ? _pickAndUpload : null,
              style: FilledButton.styleFrom(backgroundColor: teal,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
              icon: const Icon(Icons.upload_file, size: 16, color: Colors.black),
              label: Text(t('tb.addFiles'),
                  style: const TextStyle(color: Colors.black, fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
            ),
        ]));
  });

  /// Akcja na zaznaczeniu: z napisem, gdy jest miejsce, sama ikona z podpowiedzia, gdy go brakuje.
  Widget _akcja(IconData ikona, String tytul, Color kolor, VoidCallback? akcja, bool waski) =>
      waski
          ? IconButton(tooltip: tytul, iconSize: 18, onPressed: akcja,
              icon: Icon(ikona, color: kolor))
          : TextButton.icon(onPressed: akcja,
              icon: Icon(ikona, size: 16, color: kolor),
              label: Text(tytul, style: TextStyle(color: kolor, fontSize: 12.5)));

  /// Te same nazwy o tym samym rozmiarze — czyli najpewniej ten sam plik wyslany kilka razy.
  /// Nie kasujemy niczego sami: pokazujemy, ile miejsca zajmuja nadmiarowe kopie, i pozwalamy
  /// zaznaczyc wszystkie oprocz najnowszej.
  /// Duplikaty rozstrzyga SUMA Z TRESCI, nie nazwa.
  ///
  /// Nazwa i rozmiar to poszlaka — dwa rozne pliki o tej samej nazwie i dlugosci sa czyms
  /// zwyczajnym, a zaznaczenie ich do skasowania byloby po prostu niebezpieczne. Poszlaka wiec
  /// tylko zaweza kandydatow; rozstrzygamy po pobraniu i policzeniu sumy u siebie. Serwer w tym
  /// nie pomoze: jego `sha256` dotyczy szyfrogramu, a kazda wysylka ma wlasny losowy klucz.
  Future<void> _duplikaty() async {
    final grupy = <String, List<StoreFile>>{};
    for (final f in _s.files) {
      if (f.name == null) continue;
      grupy.putIfAbsent('${f.baseName}|${f.sizeB}', () => []).add(f);
    }
    final kandydaci = [for (final g in grupy.values.where((g) => g.length > 1)) ...g];
    if (kandydaci.isEmpty) { _toast(t('toast.noDup')); return; }
    if (!_s.canRead) { _toast(t('dup.needRead'), bad: true); return; }
    if (!mounted) return;

    final doPobrania = kandydaci.fold<int>(0, (a, f) => a + f.sizeB);
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: card,
      title: Text(
          t('dup.askTitle', {'files': liczba('plural.files', kandydaci.length)}),
          style: const TextStyle(fontSize: 15)),
      content: Text(t('dup.askBody', {'size': _fmt(doPobrania)}),
          style: const TextStyle(color: muted, fontSize: 12.5, height: 1.4)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('dlg.cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: teal),
            child: Text(t('dup.go'), style: const TextStyle(color: Colors.black))),
      ],
    ));
    if (ok != true) return;

    await _run(t('dup.checking'), () async {
      final wgSumy = <String, List<StoreFile>>{};
      for (var i = 0; i < kandydaci.length; i++) {
        setState(() => _busy = t('dup.checkingN',
            {'i': i + 1, 'n': kandydaci.length, 'f': kandydaci[i].baseName}));
        final suma = await _s.sumaJawna(kandydaci[i],
            onProgress: (v) { if (mounted) setState(() => _progress = v); });
        wgSumy.putIfAbsent(suma, () => []).add(kandydaci[i]);
      }
      final nadmiar = <StoreFile>[];
      var bajty = 0;
      for (final g in wgSumy.values.where((g) => g.length > 1)) {
        g.sort((a, b) =>
            (b.createdAt ?? DateTime(2000)).compareTo(a.createdAt ?? DateTime(2000)));
        for (final f in g.skip(1)) { nadmiar.add(f); bajty += f.sizeB; }
      }
      if (nadmiar.isEmpty) { _toast(t('toast.noDup')); return; }
      setState(() { _sel..clear()..addAll(nadmiar.map((f) => f.id)); _tylkoUwaga = false; });
      _toast(t('toast.dupSel',
          {'dup': liczba('plural.dup', nadmiar.length), 'size': _fmt(bajty)}));
    });
  }

  /// Ile plikow nie ma jeszcze dwoch potwierdzonych kopii. Zero to stan docelowy, wiec chip
  /// pojawia sie tylko wtedy, gdy jest co pokazac.
  Widget _uwagaChip({bool zwarty = false}) {
    final ile = _ileUwaga;
    if (ile == 0) { _tylkoUwaga = false; return const SizedBox.shrink(); }
    return InkWell(
      onTap: () => setState(() {
        _tylkoUwaga = !_tylkoUwaga;
        // Wejscie w filtr wraca do korzenia, zeby sciezka u gory zgadzala sie z tym, co widac.
        if (_tylkoUwaga) _folder = '';
        _sel.clear();
      }),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
            color: _tylkoUwaga ? amber.withValues(alpha: 0.14) : null,
            border: Border.all(color: amber.withValues(alpha: 0.55)),
            borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          const Icon(Icons.shield_outlined, size: 14, color: amber),
          const SizedBox(width: 5),
          Text(zwarty ? '$ile' : t('chip.needCopy', {'n': ile}),
              style: const TextStyle(color: amber, fontSize: 12)),
        ]),
      ),
    );
  }

  Widget _sortButton() => PopupMenuButton<SortBy>(
        tooltip: t('sort.title'),
        onSelected: (v) => setState(() { _asc = _sort == v ? !_asc : false; _sort = v; }),
        itemBuilder: (_) => [
          for (final s in SortBy.values)
            PopupMenuItem(value: s, child: Row(children: [
              if (_sort == s) Icon(_asc ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 13, color: teal) else const SizedBox(width: 13),
              const SizedBox(width: 8),
              Text(_nazwaSort(s)),
            ])),
        ],
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
              border: Border.all(color: line), borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            const Icon(Icons.swap_vert, size: 15, color: muted),
            const SizedBox(width: 5),
            Text(_nazwaSort(_sort),
                style: const TextStyle(color: muted, fontSize: 12)),
          ]),
        ),
      );

  static String _nazwaSort(SortBy s) => t(switch (s) {
        SortBy.name => 'sort.name',
        SortBy.size => 'sort.size',
        SortBy.date => 'sort.date',
      });

  Widget _progressBar() => Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
        child: Column(children: [
          Row(children: [
            const SizedBox(width: 13, height: 13,
                child: CircularProgressIndicator(strokeWidth: 2, color: teal)),
            const SizedBox(width: 9),
            Expanded(child: Text(_busy!,
                style: const TextStyle(color: muted, fontSize: 11.5),
                overflow: TextOverflow.ellipsis)),
            if (_progress != null) ...[
              const SizedBox(width: 6),
              Text('${(_progress! * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(color: faint, fontSize: 11)),
            ],
          ]),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(value: _progress, minHeight: 4,
                backgroundColor: card, color: teal),
          ),
        ]),
      );

  /// Naglowek: zaznacz wszystko + sortowanie kliknieciem w kolumne. Strzalka pokazuje kierunek,
  /// bo „posortowane" bez kierunku to polowa informacji.
  Widget _header() {
    final l = _visible;
    final wszystkie = l.isNotEmpty && l.every((f) => _sel.contains(f.id));
    Widget kol(String tytul, SortBy by, double szer, {bool prawo = false}) => InkWell(
          onTap: () => setState(() { _asc = _sort == by ? !_asc : false; _sort = by; }),
          child: SizedBox(
            width: szer,
            child: Row(
              mainAxisAlignment: prawo ? MainAxisAlignment.end : MainAxisAlignment.start,
              children: [
                Text(tytul, style: TextStyle(
                    color: _sort == by ? teal : faint, fontSize: 10.5,
                    fontWeight: FontWeight.w600, letterSpacing: 0.6)),
                if (_sort == by) Icon(_asc ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                    size: 15, color: teal),
              ],
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: line))),
      child: Row(children: [
        SizedBox(width: 26, child: Checkbox(
          value: wszystkie, activeColor: teal, visualDensity: VisualDensity.compact,
          tristate: false,
          onChanged: (v) => setState(() {
            if (v == true) { _sel.addAll(l.map((f) => f.id)); }
            else { for (final f in l) { _sel.remove(f.id); } }
          }),
        )),
        const SizedBox(width: 25),
        Expanded(child: kol(t('col.name').toUpperCase(), SortBy.name, double.infinity)),
        kol(t('col.size').toUpperCase(), SortBy.size, 84, prawo: true),
        SizedBox(width: 62, child: Text(t('col.copies').toUpperCase(),
            textAlign: TextAlign.right,
            style: const TextStyle(color: faint, fontSize: 10.5, fontWeight: FontWeight.w600,
                letterSpacing: 0.6))),
        kol(t('col.added').toUpperCase(), SortBy.date, 108, prawo: true),
      ]),
    );
  }

  /// Szczegoly jednego pliku. Pokazujemy takze to, czego nie wiemy — „nazwa nieczytelna" jest
  /// informacja, a nie brakiem.
  Widget _details(StoreFile f) => Container(
        width: 260,
        color: const Color(0xFF11161D),
        padding: const EdgeInsets.all(14),
        child: ListView(children: [
          Row(children: [
            _icon(f),
            const SizedBox(width: 8),
            Expanded(child: Text(f.name == null ? t('det.nameUnreadable') : f.baseName,
                style: TextStyle(color: f.name == null ? muted : Colors.white,
                    fontSize: 13, fontWeight: FontWeight.w600))),
          ]),
          if (_mediaMozliwe(f)) ...[
            const SizedBox(height: 12),
            _media(f),
          ],
          if (_podgladMozliwy(f)) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: FutureBuilder(
                future: _s.preview(f),
                builder: (_, snap) {
                  if (snap.hasError) {
                    // Najczestszy powod to brak potwierdzonej kopii — nie ma skad wziac bajtow.
                    // To stan przejsciowy, wiec mowimy o nim jak o stanie, a nie jak o awarii.
                    final brakKopii = f.copies == 0 ||
                        '${snap.error}'.toLowerCase().contains('no online copy');
                    return Text(
                        brakKopii
                            ? t('det.previewNoCopy')
                            : t('det.previewErr', {'e': '${snap.error}'}),
                        style: const TextStyle(color: amber, fontSize: 11, height: 1.35));
                  }
                  if (!snap.hasData) {
                    return const SizedBox(height: 90,
                        child: Center(child: SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: teal))));
                  }
                  return Image.memory(snap.data!, fit: BoxFit.cover,
                      errorBuilder: (_, e, st) => Text(t('det.notImage'),
                          style: const TextStyle(color: faint, fontSize: 11)));
                },
              ),
            ),
          ],
          const SizedBox(height: 14),
          _pole(t('det.folder'), f.folder.isEmpty ? '—' : f.folder),
          _pole(t('col.size'), _fmt(f.sizeB)),
          _pole(t('col.copies'), '${f.copies}'),
          _pole(t('col.added'), f.createdAt == null ? '—'
              : '${f.createdAt!.day}.${f.createdAt!.month.toString().padLeft(2, '0')}.'
                '${f.createdAt!.year} ${f.createdAt!.hour.toString().padLeft(2, '0')}:'
                '${f.createdAt!.minute.toString().padLeft(2, '0')}'),
          const SizedBox(height: 6),
          Text(t('det.identifier').toUpperCase(),
              style: const TextStyle(color: faint, fontSize: 9.5,
                  letterSpacing: 1, fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          SelectableText(f.id,
              style: const TextStyle(color: muted, fontSize: 10.5, fontFamily: 'monospace')),
          const SizedBox(height: 14),
          if (_s.niedokonczony(f))
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: red.withValues(alpha: 0.5))),
              child: Text(t('det.notUploaded'),
                  style: const TextStyle(color: red, fontSize: 10.5, height: 1.35)),
            )
          else if (f.copies < 2)
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: amber.withValues(alpha: 0.4))),
              child: Text(t(f.copies == 0 ? 'det.noCopyYet' : 'det.oneCopy'),
                  style: const TextStyle(color: amber, fontSize: 10.5, height: 1.35)),
            ),
          const SizedBox(height: 12),
          if (_s.canRead)
            SizedBox(width: double.infinity, child: OutlinedButton.icon(
                onPressed: _busy == null ? _downloadSel : null,
                icon: const Icon(Icons.download, size: 15),
                style: OutlinedButton.styleFrom(foregroundColor: teal),
                label: Text(t('act.download'), style: const TextStyle(fontSize: 12)))),
          const SizedBox(height: 6),
          SizedBox(width: double.infinity, child: OutlinedButton.icon(
              onPressed: _busy == null ? _deleteSel : null,
              icon: const Icon(Icons.delete_outline, size: 15),
              style: OutlinedButton.styleFrom(foregroundColor: red),
              label: Text(t('act.delete'), style: const TextStyle(fontSize: 12)))),
        ]),
      );

  /// Podglad ma sens tylko wtedy, gdy mamy czym odszyfrowac, plik jest obrazkiem i nie jest tak
  /// duzy, zeby jego pobranie bylo niespodzianka dla lacza.
  /// Muzyki i filmu nie da sie puscic strumieniem — plik jest zaszyfrowany, wiec musi
  /// najpierw zjechac w calosci. Dlatego mowimy z gory, ile to jest.
  bool _mediaMozliwe(StoreFile f) =>
      _s.canRead && f.copies > 0 && (dzwiek.contains(f.ext) || wideo.contains(f.ext));

  Widget _media(StoreFile f) {
    final plik = _graPlik;
    if (_graId == f.id && plik != null) {
      final tagi = _tagi;
      return Column(children: [
        if (tagi != null && !tagi.pusty) ...[
          KartaTagow(tagi: tagi),
          const SizedBox(height: 8),
        ],
        Odtwarzacz(key: ValueKey(f.id), plik: plik, zObrazem: wideo.contains(f.ext)),
      ]);
    }
    return PrzyciskOdtwarzania(
      rozmiar: _fmt(f.sizeB),
      postep: _graId == f.id ? _graPostep : null,
      onTap: _busy != null ? null : () async {
        setState(() { _graId = f.id; _graPostep = 0; _graPlik = null; _tagi = null; });
        try {
          final p = await _s.doPliku(f,
              onProgress: (v) { if (mounted) setState(() => _graPostep = v); });
          final tagi = dzwiek.contains(f.ext) ? czytajTagi(p) : null;
          if (mounted) setState(() { _graPlik = p; _graPostep = null; _tagi = tagi; });
        } catch (e) {
          if (!mounted) return;
          setState(() { _graId = null; _graPostep = null; });
          _toast(t('media.failed', {'e': '$e'}), bad: true);
        }
      },
    );
  }

  bool _podgladMozliwy(StoreFile f) =>
      _s.canRead &&
      const {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'}.contains(f.ext) &&
      f.sizeB < 8 * 1024 * 1024;

  Widget _pole(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k.toUpperCase(), style: const TextStyle(color: faint, fontSize: 9.5,
              letterSpacing: 1, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(v, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ]),
      );

  Widget _table() {
    if (!_s.connected && _s.error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_s.error != null) {
      return Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off, color: amber, size: 28),
          const SizedBox(height: 10),
          Text(t('err.account'),
              style: const TextStyle(color: Colors.white, fontSize: 14)),
          const SizedBox(height: 6),
          Text(_s.error!, textAlign: TextAlign.center,
              style: const TextStyle(color: muted, fontSize: 11.5)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: () => _s.connect(),
              style: OutlinedButton.styleFrom(foregroundColor: teal),
              child: Text(t('err.tryAgain'))),
        ]),
      ));
    }
    final l = _visible;
    // Wiersze katalogow liczymy PRZED sprawdzeniem pustki. Folder, ktory ma tylko podkatalogi
    // (np. `bac` z calym `bac/Muzyka` w srodku), nie ma ani jednego pliku BEZPOSREDNIO w sobie —
    // a przy starej kolejnosci konczylo sie to napisem „ten folder jest pusty" i ślepym zaulkiem:
    // 92 pliki w liczniku, zero na ekranie i zadnego sposobu, zeby sie do nich dostac.
    final kat = _search.text.trim().isEmpty && !(_tylkoUwaga && _ileUwaga > 0)
        ? _podkatalogi
        : const <String>[];
    if (l.isEmpty && kat.isEmpty) {
      // Pusto z POWODU, nie „po prostu pusto": filtr, wyszukiwarka i katalog to trzy rozne
      // przyczyny i kazda ma inne wyjscie. Bez tego czlowiek widzi „0 z 13" i nie wie, co kliknac.
      final filtr = _tylkoUwaga && _ileUwaga > 0;
      final szuka = _search.text.trim().isNotEmpty;
      final wFolderze = _folder.isNotEmpty;
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(szuka ? Icons.search_off : filtr ? Icons.filter_alt_off_outlined
                                              : Icons.inbox_outlined,
            color: faint, size: 30),
        const SizedBox(height: 10),
        Text(
            szuka ? t('empty.noMatch', {'q': _search.text})
                : filtr ? t('empty.allCopies')
                : wFolderze ? t('empty.folder')
                : t('empty.none'),
            style: const TextStyle(color: muted, fontSize: 12.5)),
        if (szuka || filtr || wFolderze) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => setState(() {
              _search.clear();
              _tylkoUwaga = false;
              _folder = '';
              _sel.clear();
            }),
            icon: const Icon(Icons.clear_all, size: 15),
            style: OutlinedButton.styleFrom(foregroundColor: teal),
            label: Text(t('empty.showAll'), style: const TextStyle(fontSize: 12)),
          ),
        ],
      ]));
    }
    // Filtr „brakuje kopii" pokazuje pliki z CALEGO konta, wiec wiersze katalogow nie maja tu
    // czego szukac — mowilyby o czyms zupelnie innym niz reszta listy.
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      itemCount: kat.length + l.length,
      itemBuilder: (_, i) => i < kat.length
          ? _wierszKatalogu(kat[i])
          : _row(l[i - kat.length], i - kat.length, l),
    );
  }

  /// Katalog w liscie plikow — pierwszy w kolejnosci, tak jak wszedzie indziej. Klikniety
  /// wchodzi do srodka; pusty mowi wprost, ze jeszcze nic w nim nie ma.
  Widget _wierszKatalogu(String sciezka) {
    final nazwa = sciezka.contains('/') ? sciezka.substring(sciezka.lastIndexOf('/') + 1) : sciezka;
    final ile = _ilePlikow(sciezka);
    return InkWell(
      onTap: () => setState(() { _folder = sciezka; _sel.clear(); }),
      onSecondaryTapUp: (d) => _menuKatalogu(sciezka, d.globalPosition),
      child: Container(
        margin: const EdgeInsets.only(bottom: 3),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        decoration: BoxDecoration(
            color: card, borderRadius: BorderRadius.circular(8),
            border: Border.all(color: line)),
        child: Row(children: [
          const SizedBox(width: 26),
          Icon(ile == 0 ? Icons.folder_outlined : Icons.folder,
              size: 17, color: ile == 0 ? faint : teal),
          const SizedBox(width: 9),
          Expanded(child: Text(nazwa, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 12.5,
                  fontWeight: FontWeight.w500))),
          Text(ile == 0 ? t('row.empty') : liczba('plural.files', ile),
              style: TextStyle(color: ile == 0 ? faint : muted, fontSize: 11.5)),
          // Menu przy KAZDYM folderze, nie tylko przy pustym: prawy przycisk myszy to za malo,
          // zeby ktokolwiek domyslil sie, jak sprzatnac folder, ktory powstal przez pomylke.
          const SizedBox(width: 6),
          SizedBox(width: 24, height: 24, child: IconButton(
            tooltip: ile == 0 ? t('act.forgetFolder') : t('act.delFolder'),
            iconSize: 15, padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            onPressed: () => _usunFolder(sciezka),
            icon: Icon(ile == 0 ? Icons.close : Icons.delete_outline,
                color: ile == 0 ? faint : muted),
          )),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right, size: 16, color: faint),
        ]),
      ),
    );
  }

  Future<void> _menuKatalogu(String sciezka, Offset gdzie) async {
    final v = await showMenu<String>(
      context: context, color: card,
      position: RelativeRect.fromLTRB(gdzie.dx, gdzie.dy, gdzie.dx, gdzie.dy),
      items: [
        PopupMenuItem(value: 'del', height: 36, child: Row(children: [
          const Icon(Icons.delete_outline, size: 15, color: red),
          const SizedBox(width: 8),
          Text(_ilePlikow(sciezka) == 0 ? t('act.forgetFolder') : t('act.delFolder'),
              style: const TextStyle(fontSize: 12.5, color: red)),
        ])),
      ],
    );
    if (v == 'del') await _usunFolder(sciezka);
  }

  /// Oproznienie calego pakietu. Osobno od zamkniecia pakietu: tam znika takze wykupione
  /// miejsce i oplata, tu tylko zawartosc.
  Future<void> _usunWszystko() async {
    final ile = _s.files.length;
    if (ile == 0) return;
    final bajty = _s.files.fold<int>(0, (a, f) => a + f.sizeB);
    if (!mounted) return;
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: card,
      title: Text(
          t('dlg.delAllTitle',
              {'files': liczba('plural.files', ile), 'size': _fmt(bajty)}),
          style: const TextStyle(fontSize: 15)),
      content: Text(t('dlg.delAllBody'),
          style: const TextStyle(color: muted, fontSize: 12.5, height: 1.4)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('dlg.cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: red),
            child: Text(t('act.delete'))),
      ],
    ));
    if (ok != true) return;
    await _run(t('busy.deleting'), () async {
      final wszystkie = List<StoreFile>.from(_s.files);
      for (var i = 0; i < wszystkie.length; i++) {
        setState(() => _busy = t('busy.deleting'));
        setState(() => _progress = (i + 1) / wszystkie.length);
        await _s.remove(wszystkie[i]);
      }
      // Foldery zyja w nazwach plikow, wiec razem z plikami znika tez cale drzewo. Zostaja
      // tylko nasze lokalne notatki o pustych katalogach — te kasujemy tutaj.
      _puste.clear();
      final p = await SharedPreferences.getInstance();
      await p.setStringList('sensmos_puste_foldery', const []);
      _folder = '';
      _sel.clear();
      await _s.refresh();
      _toast(t('toast.deleted', {'files': liczba('plural.files', ile)}));
    });
  }

  /// Pusty folder tylko zapominamy — na serwerze i tak go nie ma. Folder z plikami ginie razem
  /// z zawartoscia, ale dopiero po pytaniu, w ktorym stoi, ile plikow zniknie.
  Future<void> _usunFolder(String sciezka) async {
    final ile = _ilePlikow(sciezka);
    if (ile == 0) {
      setState(() {
        _puste.remove(sciezka);
        if (_folder == sciezka) _folder = '';
      });
      final p = await SharedPreferences.getInstance();
      await p.setStringList('sensmos_puste_foldery', _puste.toList());
      return;
    }
    if (!mounted) return;
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: card,
      title: Text(
          t('dlg.delFolderTitle',
              {'f': sciezka, 'files': liczba('plural.files', ile)}),
          style: const TextStyle(fontSize: 15)),
      content: Text(t('dlg.deleteBody'), style: const TextStyle(color: muted)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('dlg.cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: red),
            child: Text(t('act.delete'))),
      ],
    ));
    if (ok != true) return;
    await _run(t('busy.deleting'), () async {
      for (final f in _s.files
          .where((x) => x.folder == sciezka || x.folder.startsWith('$sciezka/'))
          .toList()) {
        await _s.remove(f);
      }
      _puste.remove(sciezka);
      if (_folder == sciezka || _folder.startsWith('$sciezka/')) _folder = '';
      _sel.clear();
      await _s.refresh();
    });
  }

  /// Klik w wiersz. Bez klawiszy = „pokaz mi ten plik", czyli zaznaczenie zastepuje poprzednie.
  void _klik(StoreFile f, int i, List<StoreFile> widoczne) {
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    setState(() {
      if (shift && _kotwica != null) {
        final od = widoczne.indexWhere((x) => x.id == _kotwica);
        if (od >= 0) {
          final a = od < i ? od : i, b = od < i ? i : od;
          _sel.addAll(widoczne.sublist(a, b + 1).map((x) => x.id));
          return;
        }
      }
      if (ctrl) {
        _sel.contains(f.id) ? _sel.remove(f.id) : _sel.add(f.id);
      } else {
        // Jeden klik = jeden plik. Ponowny klik w juz wybrany zdejmuje zaznaczenie, zeby dalo sie
        // wrocic do pustego stanu bez siegania po Esc.
        final tylkoTen = _sel.length == 1 && _sel.contains(f.id);
        _sel.clear();
        if (!tylkoTen) _sel.add(f.id);
      }
      _kotwica = f.id;
      // Inny plik = koniec grania. Odtwarzacz pod spodem nie ma prawa dalej lecieć.
      _graId = null; _graPostep = null; _graPlik = null; _tagi = null;
    });
  }

  Widget _row(StoreFile f, int i, List<StoreFile> widoczne) {
    final zazn = _sel.contains(f.id);
    final znana = f.name != null;
    final zgubiony = _s.niedokonczony(f);
    return InkWell(
      onTap: () => _klik(f, i, widoczne),
      onSecondaryTapUp: (d) => _menu(f, d.globalPosition),
      child: Container(
        margin: const EdgeInsets.only(bottom: 3),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
            color: zazn ? teal.withValues(alpha: 0.10) : card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: zazn ? teal.withValues(alpha: 0.5) : line)),
        child: Row(children: [
          // Kwadracik jest OD dokladania — nie kasuje reszty zaznaczenia, w odroznieniu od kliku
          // w wiersz. Dzieki temu jedno i drugie da sie robic bez klawiatury.
          SizedBox(width: 26, child: Checkbox(
            value: zazn, activeColor: teal, visualDensity: VisualDensity.compact,
            onChanged: (v) => setState(() {
              v == true ? _sel.add(f.id) : _sel.remove(f.id);
              _kotwica = f.id;
            }),
          )),
          _icon(f),
          const SizedBox(width: 9),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(znana ? f.baseName : f.id.substring(0, 12),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5,
                    color: znana ? Colors.white : muted,
                    fontFamily: znana ? null : 'monospace')),
            if (f.folder.isNotEmpty && (_folder.isEmpty || _search.text.isNotEmpty))
              Text(f.folder, style: const TextStyle(color: faint, fontSize: 10.5)),
          ])),
          SizedBox(width: 84, child: Text(_fmt(f.sizeB), textAlign: TextAlign.right,
              style: const TextStyle(color: muted, fontSize: 11.5))),
          SizedBox(width: 62, child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            Icon(zgubiony ? Icons.error_outline : Icons.copy_all_outlined, size: 12,
                color: zgubiony ? red : f.copies >= 2 ? teal : amber),
            const SizedBox(width: 3),
            Text(zgubiony ? '!' : '${f.copies}', style: TextStyle(
                color: zgubiony ? red : f.copies >= 2 ? muted : amber, fontSize: 11.5)),
          ])),
          SizedBox(width: 108, child: Text(
              f.createdAt == null ? '' : _kiedy(f.createdAt!),
              textAlign: TextAlign.right,
              style: const TextStyle(color: faint, fontSize: 11))),
        ]),
      ),
    );
  }

  /// Prawy przycisk: to, czego czlowiek szuka odruchowo. Zaznacza plik, jesli nie byl zaznaczony,
  /// zeby akcja dotyczyla tego, w co klikniete.
  Future<void> _menu(StoreFile f, Offset gdzie) async {
    if (!_sel.contains(f.id)) setState(() { _sel..clear()..add(f.id); });
    final v = await showMenu<String>(
      context: context,
      color: card,
      position: RelativeRect.fromLTRB(gdzie.dx, gdzie.dy, gdzie.dx, gdzie.dy),
      items: [
        if (_s.canRead)
          PopupMenuItem(value: 'get', height: 36, child: Row(children: [
            const Icon(Icons.download, size: 15, color: teal), const SizedBox(width: 8),
            Text(t('act.download'), style: const TextStyle(fontSize: 12.5))])),
        PopupMenuItem(value: 'id', height: 36, child: Row(children: [
          const Icon(Icons.tag, size: 15, color: muted), const SizedBox(width: 8),
          Text(t('act.copyId'), style: const TextStyle(fontSize: 12.5))])),
        if (f.folder.isNotEmpty)
          PopupMenuItem(value: 'folder', height: 36, child: Row(children: [
            const Icon(Icons.folder_open, size: 15, color: muted), const SizedBox(width: 8),
            Text(t('act.goToFolder'), style: const TextStyle(fontSize: 12.5))])),
        const PopupMenuDivider(height: 6),
        PopupMenuItem(value: 'del', height: 36, child: Row(children: [
          const Icon(Icons.delete_outline, size: 15, color: red), const SizedBox(width: 8),
          Text(t('act.delete'), style: const TextStyle(fontSize: 12.5, color: red))])),
      ],
    );
    if (!mounted) return;
    switch (v) {
      case 'get': await _downloadSel();
      case 'del': await _deleteSel();
      case 'id':
        await Clipboard.setData(ClipboardData(text: f.id));
        _toast(t('toast.idCopied'));
      case 'folder': setState(() { _folder = f.folder; _sel.clear(); });
    }
  }

  Widget _icon(StoreFile f) {
    const map = {
      'jpg': Icons.image_outlined, 'jpeg': Icons.image_outlined, 'png': Icons.image_outlined,
      'gif': Icons.image_outlined, 'webp': Icons.image_outlined, 'bmp': Icons.image_outlined,
      'pdf': Icons.picture_as_pdf_outlined,
      'zip': Icons.folder_zip_outlined, '7z': Icons.folder_zip_outlined,
      'rar': Icons.folder_zip_outlined, 'gz': Icons.folder_zip_outlined,
      'tar': Icons.folder_zip_outlined,
      'mp4': Icons.movie_outlined, 'mkv': Icons.movie_outlined, 'avi': Icons.movie_outlined,
      'mp3': Icons.audiotrack_outlined, 'wav': Icons.audiotrack_outlined,
      'flac': Icons.audiotrack_outlined,
      'txt': Icons.description_outlined, 'md': Icons.description_outlined,
      'doc': Icons.description_outlined, 'docx': Icons.description_outlined,
      'xls': Icons.table_chart_outlined, 'xlsx': Icons.table_chart_outlined,
      'csv': Icons.table_chart_outlined,
      'dart': Icons.code, 'js': Icons.code, 'py': Icons.code, 'json': Icons.code,
      'sql': Icons.code, 'html': Icons.code, 'css': Icons.code, 'yaml': Icons.code,
    };
    return Icon(map[f.ext] ?? Icons.insert_drive_file_outlined, size: 16,
        color: f.name == null ? faint : muted);
  }

  Widget _statusBar() => Container(
        height: 26,
        decoration: const BoxDecoration(
            color: Color(0xFF11161D), border: Border(top: BorderSide(color: line))),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(
              shape: BoxShape.circle, color: _s.connected ? teal : red)),
          const SizedBox(width: 7),
          Text(t(_s.connected ? 'st.connected' : 'st.offline'),
              style: const TextStyle(color: muted, fontSize: 11)),
          const SizedBox(width: 14),
          if (_s.lastRoute.isNotEmpty) ...[
            Icon(_s.lastRoute == 'direct' ? Icons.bolt : Icons.cloud_outlined,
                size: 12, color: _s.lastRoute == 'direct' ? teal : faint),
            const SizedBox(width: 4),
            Flexible(child: Text(
                t(_s.lastRoute == 'direct' ? 'st.lastDirect' : 'st.lastServer'),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: faint, fontSize: 11))),
          ],
          const Spacer(),
          Text(t('st.counts', {'shown': _visible.length, 'total': _s.files.length}),
              style: const TextStyle(color: faint, fontSize: 11)),
        ]),
      );

  // ── drobiazgi ──────────────────────────────────────────────────────────────

  static String _fmt(int b) {
    if (b >= 1073741824) return '${(b / 1073741824).toStringAsFixed(2)} GB';
    if (b >= 1048576) return '${(b / 1048576).toStringAsFixed(1)} MB';
    if (b >= 1024) return '${(b / 1024).toStringAsFixed(0)} kB';
    return '$b B';
  }

  static String _kiedy(DateTime d) {
    final r = DateTime.now().difference(d);
    if (r.inMinutes < 1) return t('time.now');
    if (r.inMinutes < 60) return t('time.min', {'n': r.inMinutes});
    if (r.inHours < 24) return t('time.h', {'n': r.inHours});
    if (r.inDays < 7) return t('time.d', {'n': r.inDays});
    return '${d.day}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }
}
