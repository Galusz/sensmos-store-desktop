import 'dart:io';
import 'dart:typed_data';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'i18n.dart';

const _teal = Color(0xFF1FCFB4);
const _card = Color(0xFF161B22);
const _line = Color(0xFF232B36);
const _muted = Color(0xFF8B949E);
const _faint = Color(0xFF6E7681);

/// To, co autor pliku zapisał w środku: tytuł, wykonawca, album, rok i okładka.
///
/// Czytamy je z ODSZYFROWANEJ kopii, która i tak musi zjechać, żeby cokolwiek zagrać —
/// więc okładka nie kosztuje ani jednego dodatkowego bajtu. Serwer tych danych nie widzi
/// i zobaczyć nie może: leżą wewnątrz szyfrogramu, dokładnie tak samo jak nazwa pliku.
class Tagi {
  final String? tytul, wykonawca, album;
  final int? rok;
  final Uint8List? okladka;
  const Tagi({this.tytul, this.wykonawca, this.album, this.rok, this.okladka});

  bool get pusty =>
      tytul == null && wykonawca == null && album == null && okladka == null;
}

String? _czysty(String? s) {
  final x = s?.trim();
  return (x == null || x.isEmpty) ? null : x;
}

/// Brak tagów to normalny stan pliku, a nie awaria — dlatego każdy błąd kończy się `null`,
/// a nie wyjątkiem lecącym przez pół programu.
Tagi? czytajTagi(File f) {
  try {
    final m = readMetadata(f, getImage: true);
    Picture? obraz;
    if (m.pictures.isNotEmpty) {
      obraz = m.pictures.firstWhere(
        (p) => p.pictureType == PictureType.coverFront,
        orElse: () => m.pictures.first,
      );
    }
    final rok = m.year?.year;
    return Tagi(
      tytul: _czysty(m.title),
      wykonawca: _czysty(m.artist),
      album: _czysty(m.album),
      rok: (rok != null && rok > 1900 && rok < 2200) ? rok : null,
      okladka: obraz?.bytes,
    );
  } catch (_) {
    return null;
  }
}

/// Okładka obok opisu. Gdy okładki nie ma, zostaje sama nuta — pole nie zapada się do zera,
/// więc panel nie skacze przy przełączaniu utworów.
class KartaTagow extends StatelessWidget {
  final Tagi tagi;
  const KartaTagow({super.key, required this.tagi});

  @override
  Widget build(BuildContext context) {
    final o = tagi.okladka;
    final podpisy = <String>[
      if (tagi.wykonawca != null) tagi.wykonawca!,
      if (tagi.album != null) tagi.album!,
    ];
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
          color: _card, borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _line)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: SizedBox(
            width: 76, height: 76,
            child: o == null
                ? Container(color: const Color(0xFF0E1116),
                    child: const Icon(Icons.music_note, size: 24, color: _faint))
                : Image.memory(o, fit: BoxFit.cover, gaplessPlayback: true,
                    errorBuilder: (_, _, _) => Container(
                        color: const Color(0xFF0E1116),
                        child: const Icon(Icons.music_note, size: 24, color: _faint))),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (tagi.tytul != null)
            Text(tagi.tytul!, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 12,
                    fontWeight: FontWeight.w600, height: 1.25)),
          for (final p in podpisy) ...[
            const SizedBox(height: 2),
            Text(p, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _muted, fontSize: 11)),
          ],
          if (tagi.rok != null) ...[
            const SizedBox(height: 2),
            Text('${tagi.rok}', style: const TextStyle(color: _faint, fontSize: 10.5)),
          ],
        ])),
      ]),
    );
  }
}

/// Rozszerzenia, dla których podgląd znaczy „posłuchaj / obejrzyj", a nie „zobacz obrazek".
const dzwiek = {'mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg', 'opus', 'wma'};
const wideo = {'mp4', 'mkv', 'webm', 'mov', 'avi', 'm4v', 'mpg', 'mpeg', 'wmv'};

/// Odtwarzacz jednego pliku, który leży już na dysku.
///
/// Plik MUSI być odszyfrowany do pliku tymczasowego — odtwarzacz czyta strumieniem z dysku,
/// a nie z pamięci, więc godzinny film nie musi się mieścić w RAM-ie w całości.
class Odtwarzacz extends StatefulWidget {
  final File plik;
  final bool zObrazem;
  const Odtwarzacz({super.key, required this.plik, required this.zObrazem});

  @override
  State<Odtwarzacz> createState() => _OdtwarzaczState();
}

class _OdtwarzaczState extends State<Odtwarzacz> {
  late final Player _p = Player();
  VideoController? _v;

  @override
  void initState() {
    super.initState();
    if (widget.zObrazem) _v = VideoController(_p);
    _p.open(Media(widget.plik.path));
  }

  @override
  void dispose() { _p.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (widget.zObrazem && _v != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: AspectRatio(aspectRatio: 16 / 9, child: Video(controller: _v!, controls: AdaptiveVideoControls)),
      );
    }
    return _PasekDzwieku(player: _p);
  }
}

/// Dźwięk nie potrzebuje obrazu, tylko przycisku, suwaka i czasu. Cała reszta to ozdoby,
/// które w wąskiej kolumnie i tak by się nie zmieściły.
class _PasekDzwieku extends StatefulWidget {
  final Player player;
  const _PasekDzwieku({required this.player});
  @override
  State<_PasekDzwieku> createState() => _PasekDzwiekuState();
}

class _PasekDzwiekuState extends State<_PasekDzwieku> {
  Duration _teraz = Duration.zero, _calosc = Duration.zero;
  bool _gra = false;
  final _sub = <dynamic>[];

  @override
  void initState() {
    super.initState();
    final s = widget.player.stream;
    _sub
      ..add(s.position.listen((d) { if (mounted) setState(() => _teraz = d); }))
      ..add(s.duration.listen((d) { if (mounted) setState(() => _calosc = d); }))
      ..add(s.playing.listen((v) { if (mounted) setState(() => _gra = v); }));
  }

  @override
  void dispose() {
    for (final x in _sub) { x.cancel(); }
    super.dispose();
  }

  static String _czas(Duration d) {
    final m = d.inMinutes, s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final max = _calosc.inMilliseconds.toDouble();
    return Column(children: [
      Row(children: [
        IconButton(
          iconSize: 26, padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
          onPressed: () => _gra ? widget.player.pause() : widget.player.play(),
          icon: Icon(_gra ? Icons.pause_circle_filled : Icons.play_circle_fill, color: _teal),
        ),
        Expanded(child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
          ),
          child: Slider(
            value: max <= 0 ? 0 : _teraz.inMilliseconds.clamp(0, max.toInt()).toDouble(),
            max: max <= 0 ? 1 : max,
            activeColor: _teal, inactiveColor: _faint,
            onChanged: max <= 0 ? null
                : (v) => widget.player.seek(Duration(milliseconds: v.round())),
          ),
        )),
      ]),
      Padding(
        padding: const EdgeInsets.only(left: 4, right: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(_czas(_teraz), style: const TextStyle(color: _muted, fontSize: 10.5)),
          Text(_czas(_calosc), style: const TextStyle(color: _faint, fontSize: 10.5)),
        ]),
      ),
    ]);
  }
}

/// Przycisk „odtwórz" pokazywany, zanim bajty zjadą z sieci. Mówi, ile trzeba ściągnąć,
/// bo dla filmu to nie jest drobiazg — plik jest zaszyfrowany, więc nie da się go puścić
/// strumieniem, dopóki nie leży u nas w całości.
class PrzyciskOdtwarzania extends StatelessWidget {
  final String rozmiar;
  final double? postep;
  final VoidCallback? onTap;
  const PrzyciskOdtwarzania({super.key, required this.rozmiar, this.postep, this.onTap});

  @override
  Widget build(BuildContext context) {
    if (postep != null) {
      return Column(children: [
        Text(t('media.fetching', {'size': rozmiar}),
            style: const TextStyle(color: _muted, fontSize: 11)),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
              value: postep! > 0 ? postep : null, minHeight: 4,
              backgroundColor: const Color(0xFF0E1116), color: _teal),
        ),
      ]);
    }
    return SizedBox(width: double.infinity, child: OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.play_arrow, size: 16),
      style: OutlinedButton.styleFrom(foregroundColor: _teal),
      label: Text(t('media.big', {'size': rozmiar}), style: const TextStyle(fontSize: 12)),
    ));
  }
}
