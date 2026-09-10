import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'i18n.dart';

/// Ikona w zasobniku i to, co robi krzyżyk.
///
/// Kopia zapasowa chodzi z zegara wewnątrz tej apki — zamknięcie okna zabija ją razem z oknem.
/// Dlatego krzyżyk domyślnie chowa, a nie kończy: człowiek, który zamknął okno „bo skończył",
/// nadal ma robioną kopię. Żeby to nie było zaskoczeniem, przy pierwszym schowaniu pytamy raz
/// i zapamiętujemy odpowiedź.
class Zasobnik with TrayListener, WindowListener {
  static final Zasobnik i = Zasobnik._();
  Zasobnik._();

  /// Co robi krzyżyk. Zmienialne z menu konta.
  bool chowaj = true;

  /// Czy wyjaśnienie już padło — pytamy dokładnie raz w życiu instalacji.
  bool _wyjasnione = false;

  /// Wpięte przez główny ekran: kopia teraz oraz pytanie zadawane przy pierwszym schowaniu
  /// (true = chowaj, false = zakończ).
  VoidCallback? onKopia;
  Future<bool> Function()? pytanie;

  bool _gotowy = false;

  Future<void> start() async {
    if (_gotowy) return;
    _gotowy = true;
    final p = await SharedPreferences.getInstance();
    chowaj = p.getBool('sensmos_chowaj_do_zasobnika') ?? true;
    _wyjasnione = p.getBool('sensmos_zasobnik_wyjasniony') ?? false;

    trayManager.addListener(this);
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);
    await trayManager.setIcon('assets/tray.ico');
    await trayManager.setToolTip('Sensmos Store');
    await odswiezMenu();
    L.zmiana.addListener(odswiezMenu);
  }

  Future<void> odswiezMenu() async {
    if (!_gotowy) return;
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: 'pokaz', label: t('tray.show')),
      MenuItem(key: 'kopia', label: t('backup.now')),
      MenuItem.separator(),
      MenuItem(key: 'koniec', label: t('tray.quit')),
    ]));
  }

  Future<void> ustawChowanie(bool v) async {
    chowaj = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool('sensmos_chowaj_do_zasobnika', v);
  }

  Future<void> pokaz() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> schowaj() async {
    await _zapamietajOkno();
    await windowManager.hide();
  }

  Future<void> zakoncz() async {
    await _zapamietajOkno();
    await trayManager.destroy();
    await windowManager.destroy();
  }

  /// Rozmiar okna przeżywa restart — apka, która za każdym razem wraca do domyślnego
  /// prostokąta, każe człowiekowi układać ją od nowa przy każdym uruchomieniu.
  Future<void> _zapamietajOkno() async {
    try {
      final r = await windowManager.getBounds();
      final p = await SharedPreferences.getInstance();
      await p.setDouble('sensmos_okno_w', r.width);
      await p.setDouble('sensmos_okno_h', r.height);
    } catch (_) {}
  }

  static Future<Size?> zapamietanyRozmiar() async {
    final p = await SharedPreferences.getInstance();
    final w = p.getDouble('sensmos_okno_w'), h = p.getDouble('sensmos_okno_h');
    if (w == null || h == null || w < 700 || h < 460) return null;
    return Size(w, h);
  }

  // ── zasobnik ───────────────────────────────────────────────────────────────

  @override
  void onTrayIconMouseDown() => pokaz();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'pokaz':
        pokaz();
      case 'kopia':
        onKopia?.call();
        pokaz();
      case 'koniec':
        zakoncz();
    }
  }

  // ── okno ───────────────────────────────────────────────────────────────────

  @override
  void onWindowClose() async {
    if (!chowaj) { await zakoncz(); return; }
    if (!_wyjasnione) {
      final chowac = await (pytanie?.call() ?? Future.value(true));
      _wyjasnione = true;
      final p = await SharedPreferences.getInstance();
      await p.setBool('sensmos_zasobnik_wyjasniony', true);
      if (!chowac) { await ustawChowanie(false); await zakoncz(); return; }
    }
    await schowaj();
  }
}
