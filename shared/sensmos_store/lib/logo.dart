import 'package:flutter/material.dart';

/// Kanoniczne logo SENSMOS — znak kropkowy + wordmark „Sensmos".
///
/// Współrzędne, promienie i przezroczystości przepisane CO DO LICZBY z nagłówka `public/index.html`
/// (siatka 5×5 w polu 24×24, dwie grupy: przygaszone tło i pełne kropki, kolor #1FCFB4).
/// Rysowane malarzem, nie obrazkiem: skaluje się bez rozmycia, nie wymaga pliku w zasobach ani
/// biblioteki do SVG, a przy okazji nie da się go „prawie odtworzyć" na oko.
///
/// Wordmark jest MIXED-CASE — „Sensmos", nigdy „SENSMOS". Wielkie litery były w apce od początku
/// i rozjeżdżały się ze stroną; to jest poprawka, nie zmiana gustu.
class SensmosLogo extends StatelessWidget {
  /// Kanoniczny kolor znaku. Zapisany TUTAJ, bo to jedyne miejsce, w ktorym ma prawo zyc —
  /// aplikacje podaja swoj kolor tekstu, ale znaku nie przemalowuja.
  static const teal = Color(0xFF1FCFB4);

  final double size;        // bok znaku kropkowego
  final double? fontSize;   // null = bez wordmarku, sam znak
  final Color textColor;    // kolor wordmarku — jedyne, co rozni sie miedzy motywami
  const SensmosLogo({super.key, this.size = 44, this.fontSize = 34,
                     this.textColor = const Color(0xFFE6EDF3)});

  @override
  Widget build(BuildContext context) {
    final mark = SizedBox(
      width: size, height: size,
      child: CustomPaint(painter: _DotMatrix()),
    );
    if (fontSize == null) return mark;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      mark,
      SizedBox(width: size * 0.30),
      Text('Sensmos', style: TextStyle(
        color: textColor, fontSize: fontSize, fontWeight: FontWeight.w600,
        fontFamily: 'monospace', letterSpacing: -0.5, height: 1.0,
      )),
    ]);
  }
}

class _DotMatrix extends CustomPainter {
  // [x, y, r, opacity] w układzie 24×24 — pierwsza grupa przygaszona, druga pełna.
  static const _dim = <List<double>>[
    [2.5, 2.5, 1.46, .38], [21.5, 2.5, 1.53, .53], [12, 7.25, 1.5, .45],
    [16.75, 7.25, 1.5, .46], [21.5, 7.25, 1.51, .48], [2.5, 12, 1.5, .45],
    [21.5, 12, 1.52, .5], [2.5, 16.75, 1.52, .5], [7.25, 16.75, 1.48, .42],
    [12, 16.75, 1.49, .44], [2.5, 21.5, 1.55, .57], [21.5, 21.5, 1.49, .45],
  ];
  static const _full = <List<double>>[
    [7.25, 2.5, 1.64], [12, 2.5, 1.68], [16.75, 2.5, 1.67], [2.5, 7.25, 1.57],
    [7.25, 7.25, 1.7], [7.25, 12, 1.68], [12, 12, 1.71], [16.75, 12, 1.68],
    [16.75, 16.75, 1.68], [21.5, 16.75, 1.6], [7.25, 21.5, 1.68], [12, 21.5, 1.68],
    [16.75, 21.5, 1.66],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 24.0;
    final p = Paint()..isAntiAlias = true;
    for (final d in _dim) {
      p.color = SensmosLogo.teal.withValues(alpha: d[3]);
      canvas.drawCircle(Offset(d[0] * k, d[1] * k), d[2] * k, p);
    }
    p.color = SensmosLogo.teal;
    for (final d in _full) {
      canvas.drawCircle(Offset(d[0] * k, d[1] * k), d[2] * k, p);
    }
  }

  @override
  bool shouldRepaint(covariant _DotMatrix oldDelegate) => false;
}
