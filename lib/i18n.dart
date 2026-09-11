import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Język interfejsu. Domyślnie bierzemy ten z systemu — człowiek, który ma polskie Windows,
/// nie powinien musieć niczego przestawiać. Wybór ręczny ma pierwszeństwo i przeżywa restart.
class L {
  static const kody = ['en', 'pl', 'de', 'pt'];
  static const nazwy = {'en': 'English', 'pl': 'Polski', 'de': 'Deutsch', 'pt': 'Português'};

  static String kod = 'en';

  /// Zmiana języka przerysowuje całą apkę — bez restartu, bo restart po zmianie języka
  /// to zawsze wygląda na awarię.
  static final ValueNotifier<String> zmiana = ValueNotifier('en');

  static Future<void> wczytaj() async {
    final p = await SharedPreferences.getInstance();
    final zapisany = p.getString('sensmos_jezyk');
    kod = (zapisany != null && kody.contains(zapisany)) ? zapisany : _zSystemu();
    zmiana.value = kod;
  }

  static String _zSystemu() {
    final l = Platform.localeName.toLowerCase().split(RegExp('[_-]')).first;
    return kody.contains(l) ? l : 'en';
  }

  static Future<void> ustaw(String k) async {
    if (!kody.contains(k)) return;
    kod = k;
    zmiana.value = k;
    final p = await SharedPreferences.getInstance();
    await p.setString('sensmos_jezyk', k);
  }
}

/// Napis w bieżącym języku. Brakujący klucz spada na angielski, a nie na pustkę — lepiej
/// pokazać zdanie w innym języku niż puste miejsce w oknie.
String t(String klucz, [Map<String, Object>? pola]) {
  var s = _slowniki[L.kod]?[klucz] ?? _slowniki['en']![klucz] ?? klucz;
  if (pola != null) {
    pola.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
  }
  return s;
}

/// Liczebnik. Polski ma trzy formy (1 plik / 2 pliki / 5 plików) i bez tego każde zdanie
/// z liczbą brzmi jak tłumaczenie maszynowe.
String liczba(String rzecz, int n) {
  final forma = L.kod == 'pl'
      ? (n == 1
          ? 'one'
          : (n % 10 >= 2 && n % 10 <= 4 && !(n % 100 >= 12 && n % 100 <= 14) ? 'few' : 'other'))
      : (n == 1 ? 'one' : 'other');
  final s = _slowniki[L.kod]?['$rzecz.$forma'] ??
      _slowniki['en']!['$rzecz.${n == 1 ? 'one' : 'other'}'] ??
      '$n';
  return s.replaceAll('{n}', '$n');
}

/// Do testu kompletnosci: angielski jest zrodlem prawdy, reszta ma miec te same klucze.
Iterable<String> get kluczeAngielskie => _slowniki['en']!.keys;
bool maKlucz(String kod, String klucz) => _slowniki[kod]?.containsKey(klucz) ?? false;

const _slowniki = <String, Map<String, String>>{
  // ── angielski: źródło prawdy, reszta jest tłumaczeniem TEGO ────────────────
  'en': {
    'plural.files.one': '{n} file',
    'plural.files.other': '{n} files',
    'plural.dup.one': '{n} duplicate',
    'plural.dup.other': '{n} duplicates',

    'pair.hint': 'On your phone: Settings → Paired devices → Pair,\nthen type this code.',
    'pair.waiting': 'Waiting for the phone…',
    'pair.newCode': 'New code',
    'pair.privacy': 'The code never reaches our server — only its hash. What the phone hands '
        'over is sealed to this computer, and we have nothing to open it with.',
    'pair.refused': 'the server refused the pairing',
    'pair.expired': 'the code expired',
    'pair.timeout': 'nobody paired within the time limit',

    'pair2.title': 'Pair another computer',
    'pair2.hint': 'Start Sensmos Store on the other computer. It shows a code — type it here. '
        'You will not need the phone.',
    'pair2.code': 'Code from the other computer',
    'pair2.check': 'Check the code',
    'pair2.asks': '„{name}” is asking for access to the account',
    'pair2.pickHint': 'Tick what that computer may do. You can take it back at any time from the '
        'phone, under Settings → Paired devices.',
    'pair2.readFiles': 'May read files',
    'pair2.readFilesHint': 'Without this it can upload files and see the list, but will not open '
        'a single name — not even its own upload after a restart.',
    'pair2.noSeed': 'This computer cannot pass on the right to read, because it does not have it '
        'either. Pair the other computer from the phone.',
    'pair2.noChain': 'A computer paired from here cannot pair further ones. That takes the phone.',
    'pair2.pair': 'Pair',
    'pair2.searching': 'Looking…',
    'pair2.pairing': 'Pairing…',
    'pair2.done': 'Paired. The other computer should open your files in a moment.',
    'pair2.noToken': 'the server would not issue a token',
    'pair2.noHandover': 'the token could not be handed over',
    'pair2.noBox': 'this computer has no account key',
    'pair2.close': 'Close',
    'log.foldersFilled': 'folders filled in: {n}',
    'menu.pairPc': 'Pair another computer',

    'menu.account': 'Account',
    'menu.language': 'Language',
    'menu.hide': 'Hide to tray',
    'menu.closeToTray': 'Close button hides to tray',
    'dlg.unpairTitle': 'Unpair this computer?',
    'dlg.unpairBody': 'This computer forgets its key and goes back to the pairing code. Your '
        'files are not touched. The access token stays on the phone\u2019s device list until you '
        'remove it there.',
    'dlg.unpairYes': 'Unpair',
    'menu.unpair': 'Unpair this computer',

    'sec.folders': 'Folders',
    'sec.backup': 'Backup',
    'sec.news': 'News',
    'folders.all': 'All files',

    'pkg.title': '{n} GB package',
    'pkg.used': '{size} used · {files}',
    'pkg.daily': '{galu} GALU/day · {n} copies',
    'pkg.balance': 'You have {galu} GALU · about {days} days at this rate',
    'pkg.grow': 'Add 1 GB',
    'pkg.shrink': 'Give back 1 GB',
    'pkg.resized': 'The package is now {n} GB',
    'busy.resizing': 'Changing the size…',
    'pkg.writeOnly': 'Write-only: this computer has no reading key, so names stay hidden.',

    'backup.add': 'Watch another folder',
    'backup.addFirst': 'Watch a folder',
    'backup.target': 'goes to {f}',
    'backup.targetRoot': 'goes straight in',
    'backup.rename': 'Rename target folder',
    'backup.stop': 'Stop watching',
    'dlg.watchTitle': 'Back up “{f}”',
    'dlg.parent': 'Put it inside a folder',
    'dlg.parentName': 'Folder name',
    'dlg.stopTitle': 'Stop watching this folder?',
    'dlg.stopBody': 'Only the watching stops. Everything already in Store stays exactly where it is.',
    'dlg.stopYes': 'Stop watching',
    'dlg.renameTitle': 'Target folder',
    'dlg.renameBody': 'New files go here from now on. Everything already uploaded stays in its old folder and is NOT sent again \u2014 moving it would mean paying for the same bytes twice.',
    'dlg.save': 'Save',
    'media.play': 'Play',
    'media.fetching': 'Fetching {size}…',
    'media.failed': 'Could not play this file: {e}',
    'media.big': 'Play ({size})',
    'menu.log': 'Transfers and log',
    'log.title': 'Transfers and log',
    'log.copy': 'Copy everything',
    'log.copied': 'Copied to the clipboard',
    'log.all': 'Everything',
    'log.transfers': 'Transfers',
    'log.problems': 'Problems',
    'log.kept': 'this session only',
    'log.empty': 'Nothing has happened yet.',
    'log.resume': 'link dropped on {f} \u2014 carrying on where it stopped',
    'log.upload': 'sent {f}',
    'log.download': 'fetched {f}',
    'log.delete': 'deleted {f}',
    'log.failed': '{f} \u2014 {e}',
    'stuck.title': '{files} never finished uploading',
    'stuck.body': 'Not a single byte reached any seller, so the network has nothing to rebuild '
        'from. These entries still take up your package.',
    'stuck.retry': 'Send again',
    'stuck.forget': 'Remove',
    'stuck.gone': 'The original is no longer at {p}',
    'stuck.done': 'Sent again: {files}',
    'det.notUploaded': 'This upload never finished \u2014 nothing was stored anywhere.',
    'folders.more': 'show {n} more',
    'folders.less': 'show fewer',
    'nopkg.title': 'This account has no space in Store yet',
    'nopkg.body': 'Store keeps encrypted copies of your files on other people\u2019s nodes. The key '
        'stays in your wallet \u2014 nobody, us included, sees the names or the contents. You pay in '
        'GALU, per day, for as long as you keep the space.',
    'nopkg.size': 'How much space?',
    'nopkg.cost': '{galu} GALU/day \u00b7 {n} copies of every file',
    'nopkg.balance': 'You have {galu} GALU \u2014 about {days} days at that rate',
    'nopkg.buy': 'Buy {n} GB',
    'nopkg.recheck': 'Check again',
    'nopkg.none': 'Nobody is selling space right now. Try again in a while.',
    'nopkg.funds': 'Not enough GALU: {need} needed, you have {have}.',
    'nopkg.bought': 'Done \u2014 {n} GB is yours. Drop files anywhere in this window.',
    'nopkg.card': 'No package',
    'nopkg.cardBody': 'Buy space to start putting files here.',
    'nopkg.max': 'at most {n} GB right now',
    'copies.label': 'Number of copies',
    'copies.rec': '{n} · recommended',
    'copies.why': 'A host that goes quiet only drops out of the package after three days, and '
        'only then is the copy rebuilt elsewhere. With two copies the file hangs on a single '
        'disk for that time; with three, on two.',
    'copies.now': '{n} copies of every file',
    'copies.rebuild': 'Rebuilding: {a} of {b} copies in place',
    'copies.done': 'Now {n} copies of every file',
    'busy.copies': 'Changing the number of copies…',
    'arrears.title': 'Uploads are paused \u2014 unpaid days: {n}',
    'arrears.body': 'The daily fee did not go through. Top up GALU; uploads resume after one paid '
        'day. Your files stay exactly where they are.',
    'act.delFolder': 'Delete folder',
    'act.forgetFolder': 'Forget this empty folder',
    'dlg.delFolderTitle': 'Delete “{f}” and {files}?',
    'dup.askTitle': 'Compare {files} byte by byte?',
    'dup.askBody': 'Same name and same size only means they might match. To be sure, the files '
        'have to be read and hashed here \u2014 the server cannot help: every upload gets its own '
        'random key, so two identical files look different to it. This will fetch {size}.',
    'dup.go': 'Compare',
    'dup.checking': 'Comparing\u2026',
    'dup.checkingN': 'Reading {i}/{n}: {f}',
    'dup.needRead': 'This computer has no reading key, so it cannot compare contents.',
    'tb.deleteAll': 'Delete everything',
    'dlg.delAllTitle': 'Delete all {files} ({size})?',
    'dlg.delAllBody': 'Every file and every folder goes, at every seller. The package stays '
        'bought, so you keep the space and the daily charge \u2014 only the contents are gone. '
        'This cannot be undone.',
    'backup.intro': 'Watch a folder and keep it backed up here — encrypted, one way.',
    'backup.choose': 'Choose folder',
    'backup.never': 'Never run',
    'backup.last': 'Last: {when}',
    'backup.now': 'Back up now',
    'backup.changeFolder': 'Change folder',
    'backup.auto': 'Automatically, every {n} min',
    'backup.scanning': 'Scanning…',
    'busy.stop': 'Stop',
    'busy.stopping': 'Stopping…',
    'backup.stopped': 'Stopped · {a} sent',
    'backup.gone': 'Folder is gone',
    'backup.checking': 'Checking {i}/{n}: {f}',
    'backup.sending': 'Sending {i}/{n}: {f}',
    'backup.upToDate': 'Up to date — {n} unchanged',
    'backup.sent': 'Sent {a}, unchanged {b}',
    'backup.failed': 'Failed: {e}',

    'tb.up': 'Up one level',
    'tb.search': 'Search  (Ctrl+F)',
    'tb.selected': '{n} selected',
    'tb.duplicates': 'Find duplicates',
    'tb.newFolder': 'New folder',
    'tb.restoreAll': 'Restore everything to a folder',
    'tb.restoreShort': 'Restore everything',
    'tb.refresh': 'Refresh  (F5)',
    'tb.addFiles': 'Add files',
    'tb.addFilesKey': 'Add files  (Ctrl+U)',
    'tb.more': 'More',

    'act.download': 'Download',
    'act.downloadN': 'Download ({n})',
    'act.verify': 'Verify',
    'act.delete': 'Delete',
    'act.copyId': 'Copy identifier',
    'act.goToFolder': 'Go to folder',

    'sort.title': 'Sort',
    'sort.name': 'Name',
    'sort.size': 'Size',
    'sort.date': 'Date',

    'chip.needCopy': '{n} need a second copy',

    'col.name': 'Name',
    'col.size': 'Size',
    'col.copies': 'Copies',
    'col.added': 'Added',

    'row.empty': 'empty',

    'empty.noMatch': 'Nothing matches “{q}”.',
    'empty.allCopies': 'Every file here already has its copies.',
    'empty.folder': 'This folder is empty.',
    'empty.none': 'Nothing here yet — drop files anywhere in this window.',
    'empty.showAll': 'Show all files',
    'err.account': 'Could not reach the account',
    'err.tryAgain': 'Try again',

    'det.nameUnreadable': 'Name not readable',
    'det.previewNoCopy': 'No confirmed copy to read from yet — the network is still placing it.',
    'det.previewErr': 'Could not read this file: {e}',
    'det.notImage': 'Not an image after all',
    'det.identifier': 'Identifier',
    'det.folder': 'Folder',
    'det.noCopyYet': 'No confirmed copy yet. It is being placed — check again in a few minutes.',
    'det.oneCopy': 'Only one confirmed copy. The network rebuilds the second one by itself.',

    'dlg.deleteTitle': 'Delete {files}?',
    'dlg.deleteBody': 'The copies are removed from every seller. This cannot be undone.',
    'dlg.cancel': 'Cancel',
    'dlg.newFolder': 'New folder',
    'dlg.folderHint': 'photos/2026',
    'dlg.folderHelp': 'Folders live inside the encrypted file name — the server never sees them.',
    'dlg.go': 'Go',

    'busy.uploading': 'Uploading…',
    'busy.uploadingN': 'Uploading {i}/{n}: {f}',
    'busy.downloading': 'Downloading…',
    'busy.downloadingN': 'Downloading {i}/{n}: {f}',
    'busy.deleting': 'Deleting…',
    'busy.refreshing': 'Refreshing…',
    'busy.restoring': 'Restoring…',
    'busy.restoringN': 'Restoring {i}/{n}: {f}',
    'busy.verifying': 'Verifying…',
    'busy.verifyingN': 'Verifying {i}/{n}: {f}',

    'route.direct': 'direct',
    'route.server': 'via server',

    'toast.uploaded': 'Uploaded {files} · {route}',
    'toast.saved': 'Saved {files} to {dir}',
    'toast.deleted': 'Deleted {files}',
    'toast.folderReady': 'Folder “{f}” is ready — drop files here or use Add files',
    'toast.restored': 'Restored {files} to {dir}',
    'toast.restoreFail': 'Restored {ok}, failed {bad}: {list}',
    'toast.verifyOk': 'All {files} check out — bytes and signatures match',
    'toast.verifyBad': '{ok} fine, {bad} FAILED: {list}',
    'toast.noDup': 'No duplicates found',
    'toast.dupSel': '{dup} selected ({size}) — the newest of each is left alone',
    'toast.idCopied': 'Identifier copied',

    'drop.here': 'Drop to encrypt and upload',
    'drop.into': 'Drop into “{f}”',

    'st.connected': 'Connected',
    'st.offline': 'Offline',
    'st.lastDirect': 'last transfer: direct to the host',
    'st.lastServer': 'last transfer: through the server',
    'st.counts': '{shown} shown · {total} total',

    'time.now': 'just now',
    'time.min': '{n} min ago',
    'time.h': '{n} h ago',
    'time.d': '{n} d ago',

    'tray.show': 'Open Sensmos Store',
    'tray.quit': 'Quit',
    'tray.hidden': 'Sensmos Store keeps running in the tray — your backup stays on schedule.',
  },

  // ── polski ─────────────────────────────────────────────────────────────────
  'pl': {
    'plural.files.one': '{n} plik',
    'plural.files.few': '{n} pliki',
    'plural.files.other': '{n} plików',
    'plural.dup.one': '{n} duplikat',
    'plural.dup.few': '{n} duplikaty',
    'plural.dup.other': '{n} duplikatów',

    'pair.hint': 'W telefonie: Ustawienia → Sparowane urządzenia → Paruj,\npotem przepisz ten kod.',
    'pair.waiting': 'Czekam na telefon…',
    'pair.newCode': 'Nowy kod',
    'pair.privacy': 'Kod nigdy nie trafia na nasz serwer — tylko jego skrót. To, co przekazuje '
        'telefon, jest zapieczętowane dla tego komputera i nie mamy czym tego otworzyć.',
    'pair.refused': 'serwer odmówił parowania',
    'pair.expired': 'kod wygasł',
    'pair.timeout': 'nikt nie sparował się w wyznaczonym czasie',

    'pair2.title': 'Sparuj kolejny komputer',
    'pair2.hint': 'Uruchom Sensmos Store na tamtym komputerze. Pokaże kod — przepisz go tutaj. '
        'Telefon nie będzie potrzebny.',
    'pair2.code': 'Kod z tamtego komputera',
    'pair2.check': 'Sprawdź kod',
    'pair2.asks': '„{name}” prosi o dostęp do konta',
    'pair2.pickHint': 'Zaznacz, co temu komputerowi wolno. Możesz to odebrać w każdej chwili '
        'z telefonu, w Ustawieniach → Sparowane urządzenia.',
    'pair2.readFiles': 'Może czytać pliki',
    'pair2.readFilesHint': 'Bez tego wyśle pliki i zobaczy listę, ale nie otworzy ani jednej '
        'nazwy — nawet własnej wysyłki po restarcie.',
    'pair2.noSeed': 'Ten komputer nie ma czego przekazać: sam nie może czytać plików. '
        'Tamten sparuj z telefonu.',
    'pair2.noChain': 'Komputer sparowany stąd nie sparuje kolejnych. Do tego trzeba telefonu.',
    'pair2.pair': 'Sparuj',
    'pair2.searching': 'Szukam…',
    'pair2.pairing': 'Paruję…',
    'pair2.done': 'Sparowano. Tamten komputer powinien za chwilę otworzyć Twoje pliki.',
    'pair2.noToken': 'serwer nie wydał tokenu',
    'pair2.noHandover': 'nie udało się przekazać tokenu',
    'pair2.noBox': 'ten komputer nie ma klucza konta',
    'pair2.close': 'Zamknij',
    'log.foldersFilled': 'uzupełnione katalogi: {n}',
    'menu.pairPc': 'Sparuj kolejny komputer',

    'menu.account': 'Konto',
    'menu.language': 'Język',
    'menu.hide': 'Schowaj do zasobnika',
    'menu.closeToTray': 'Zamknięcie chowa do zasobnika',
    'dlg.unpairTitle': 'Od\u0142\u0105czy\u0107 ten komputer?',
    'dlg.unpairBody': 'Ten komputer zapomina sw\u00f3j klucz i wraca do ekranu z kodem. Pliki '
        'zostaj\u0105 nietkni\u0119te. Token dost\u0119pu wisi na li\u015bcie urz\u0105dze\u0144 w telefonie, dop\u00f3ki '
        'nie zdejmiesz go tam.',
    'dlg.unpairYes': 'Od\u0142\u0105cz',
    'menu.unpair': 'Odłącz ten komputer',

    'sec.folders': 'Foldery',
    'sec.backup': 'Kopia zapasowa',
    'sec.news': 'Aktualności',
    'folders.all': 'Wszystkie pliki',

    'pkg.title': 'Pakiet {n} GB',
    'pkg.used': 'zajęte {size} · {files}',
    'pkg.daily': '{galu} GALU/dzień · kopie: {n}',
    'pkg.balance': 'Masz {galu} GALU · mniej więcej na {days} dni',
    'pkg.grow': 'Dokup 1 GB',
    'pkg.shrink': 'Oddaj 1 GB',
    'pkg.resized': 'Pakiet ma teraz {n} GB',
    'busy.resizing': 'Zmieniam rozmiar…',
    'pkg.writeOnly': 'Tylko zapis: ten komputer nie ma klucza do odczytu, więc nazwy pozostają ukryte.',

    'backup.add': 'Pilnuj kolejnego folderu',
    'backup.addFirst': 'Pilnuj folderu',
    'backup.target': 'trafia do {f}',
    'backup.targetRoot': 'trafia prosto do Store',
    'backup.rename': 'Zmie\u0144 folder docelowy',
    'backup.stop': 'Przesta\u0144 pilnowa\u0107',
    'dlg.watchTitle': 'Kopia folderu \u201e{f}\u201d',
    'dlg.parent': 'W\u0142\u00f3\u017c do folderu',
    'dlg.parentName': 'Nazwa folderu',
    'dlg.stopTitle': 'Przesta\u0107 pilnowa\u0107 tego folderu?',
    'dlg.stopBody': 'Ko\u0144czy si\u0119 tylko pilnowanie. Wszystko, co ju\u017c jest w Store, zostaje dok\u0142adnie tam, gdzie by\u0142o.',
    'dlg.stopYes': 'Przesta\u0144 pilnowa\u0107',
    'dlg.renameTitle': 'Folder docelowy',
    'dlg.renameBody': 'Od teraz nowe pliki id\u0105 tutaj. To, co ju\u017c wys\u0142ane, zostaje w starym folderze i NIE p\u00f3jdzie drugi raz \u2014 przeniesienie znaczy\u0142oby zap\u0142acenie za te same bajty dwa razy.',
    'dlg.save': 'Zapisz',
    'media.play': 'Odtw\u00f3rz',
    'media.fetching': 'Pobieram {size}\u2026',
    'media.failed': 'Nie uda\u0142o si\u0119 odtworzy\u0107: {e}',
    'media.big': 'Odtw\u00f3rz ({size})',
    'menu.log': 'Transfery i dziennik',
    'log.title': 'Transfery i dziennik',
    'log.copy': 'Skopiuj ca\u0142o\u015b\u0107',
    'log.copied': 'Skopiowano do schowka',
    'log.all': 'Wszystko',
    'log.transfers': 'Transfery',
    'log.problems': 'Problemy',
    'log.kept': 'tylko ta sesja',
    'log.empty': 'Jeszcze nic si\u0119 nie wydarzy\u0142o.',
    'log.resume': 'zerwane \u0142\u0105cze przy {f} \u2014 wracam tam, gdzie stan\u0119\u0142o',
    'log.upload': 'wys\u0142ano {f}',
    'log.download': 'pobrano {f}',
    'log.delete': 'usuni\u0119to {f}',
    'log.failed': '{f} \u2014 {e}',
    'stuck.title': 'nie doko\u0144czono wysy\u0142ki: {files}',
    'stuck.body': 'Do \u017cadnego sprzedawcy nie dotar\u0142 ani jeden bajt, wi\u0119c sie\u0107 nie ma z czego '
        'odbudowa\u0107 kopii. Te wpisy nadal zajmuj\u0105 miejsce w pakiecie.',
    'stuck.retry': 'Wy\u015blij ponownie',
    'stuck.forget': 'Usu\u0144',
    'stuck.gone': 'Orygina\u0142u nie ma ju\u017c w {p}',
    'stuck.done': 'Wys\u0142ano ponownie: {files}',
    'det.notUploaded': 'Ta wysy\u0142ka nie zosta\u0142a doko\u0144czona \u2014 nigdzie nic nie le\u017cy.',
    'folders.more': 'jeszcze {n}',
    'folders.less': 'poka\u017c mniej',
    'nopkg.title': 'To konto nie ma jeszcze miejsca w Store',
    'nopkg.body': 'Store trzyma zaszyfrowane kopie Twoich plik\u00f3w na nodach innych ludzi. Klucz '
        'zostaje w Twoim portfelu \u2014 nikt, my te\u017c nie, nie widzi nazw ani tre\u015bci. P\u0142acisz w GALU, '
        'za dob\u0119, tak d\u0142ugo, jak trzymasz to miejsce.',
    'nopkg.size': 'Ile miejsca?',
    'nopkg.cost': '{galu} GALU/dob\u0119 \u00b7 {n} kopie ka\u017cdego pliku',
    'nopkg.balance': 'Masz {galu} GALU \u2014 mniej wi\u0119cej na {days} dni',
    'nopkg.buy': 'Wykup {n} GB',
    'nopkg.recheck': 'Sprawd\u017a ponownie',
    'nopkg.none': 'Nikt teraz nie sprzedaje miejsca. Spr\u00f3buj za jaki\u015b czas.',
    'nopkg.funds': 'Za ma\u0142o GALU: potrzeba {need}, masz {have}.',
    'nopkg.bought': 'Gotowe \u2014 {n} GB jest Twoje. Upu\u015b\u0107 pliki w dowolnym miejscu tego okna.',
    'nopkg.card': 'Brak pakietu',
    'nopkg.cardBody': 'Wykup miejsce, \u017ceby zacz\u0105\u0107 tu trzyma\u0107 pliki.',
    'nopkg.max': 'teraz najwy\u017cej {n} GB',
    'copies.label': 'Ile kopii',
    'copies.rec': '{n} · zalecane',
    'copies.why': 'Host, który zamilknie, wypada z pakietu dopiero po trzech dobach i dopiero '
        'wtedy kopia odbudowuje się gdzie indziej. Przy dwóch kopiach plik wisi przez ten czas '
        'na jednym dysku, przy trzech — na dwóch.',
    'copies.now': '{n} kopie każdego pliku',
    'copies.rebuild': 'Odbudowa: {a} z {b} kopii na miejscu',
    'copies.done': 'Teraz {n} kopie każdego pliku',
    'busy.copies': 'Zmieniam liczbę kopii…',
    'arrears.title': 'Wysy\u0142ki wstrzymane \u2014 nieop\u0142acone doby: {n}',
    'arrears.body': 'Op\u0142ata za dob\u0119 nie przesz\u0142a. Dop\u0142a\u0107 GALU \u2014 wysy\u0142ki wracaj\u0105 po jednej '
        'op\u0142aconej dobie. Pliki zostaj\u0105 dok\u0142adnie tam, gdzie by\u0142y.',
    'act.delFolder': 'Usu\u0144 folder',
    'act.forgetFolder': 'Zapomnij ten pusty folder',
    'dlg.delFolderTitle': 'Usun\u0105\u0107 \u201e{f}\u201d i {files}?',
    'dup.askTitle': 'Por\u00f3wna\u0107 {files} bajt po bajcie?',
    'dup.askBody': 'Ta sama nazwa i ten sam rozmiar znacz\u0105 tylko tyle, \u017ce MOG\u0104 by\u0107 takie same. '
        '\u017deby mie\u0107 pewno\u015b\u0107, trzeba je tutaj odczyta\u0107 i policzy\u0107 sum\u0119 \u2014 serwer nie pomo\u017ce: ka\u017cda '
        'wysy\u0142ka ma w\u0142asny losowy klucz, wi\u0119c dwa identyczne pliki wygl\u0105daj\u0105 dla niego r\u00f3\u017cnie. '
        'Pobierze to {size}.',
    'dup.go': 'Por\u00f3wnaj',
    'dup.checking': 'Por\u00f3wnuj\u0119\u2026',
    'dup.checkingN': 'Czytam {i}/{n}: {f}',
    'dup.needRead': 'Ten komputer nie ma klucza do odczytu, wi\u0119c nie por\u00f3wna tre\u015bci.',
    'tb.deleteAll': 'Usu\u0144 wszystko',
    'dlg.delAllTitle': 'Usun\u0105\u0107 wszystkie {files} ({size})?',
    'dlg.delAllBody': 'Znikaj\u0105 wszystkie pliki i wszystkie foldery, u ka\u017cdego sprzedawcy. '
        'Pakiet zostaje wykupiony \u2014 miejsce i op\u0142ata za dob\u0119 dalej s\u0105 Twoje, ginie tylko '
        'zawarto\u015b\u0107. Tego nie da si\u0119 cofn\u0105\u0107.',
    'backup.intro': 'Pilnuj folderu i trzymaj tu jego kopię — zaszyfrowaną, w jedną stronę.',
    'backup.choose': 'Wybierz folder',
    'backup.never': 'Jeszcze nie uruchamiana',
    'backup.last': 'Ostatnio: {when}',
    'backup.now': 'Zrób kopię teraz',
    'backup.changeFolder': 'Zmień folder',
    'backup.auto': 'Automatycznie, co {n} min',
    'backup.scanning': 'Przeglądam…',
    'busy.stop': 'Zatrzymaj',
    'busy.stopping': 'Zatrzymuję…',
    'backup.stopped': 'Zatrzymane · wysłano {a}',
    'backup.gone': 'Folder zniknął',
    'backup.checking': 'Sprawdzam {i}/{n}: {f}',
    'backup.sending': 'Wysyłam {i}/{n}: {f}',
    'backup.upToDate': 'Aktualne — bez zmian: {n}',
    'backup.sent': 'Wysłano {a}, bez zmian {b}',
    'backup.failed': 'Nie udało się: {e}',

    'tb.up': 'Poziom wyżej',
    'tb.search': 'Szukaj  (Ctrl+F)',
    'tb.selected': 'zaznaczone: {n}',
    'tb.duplicates': 'Znajdź duplikaty',
    'tb.newFolder': 'Nowy folder',
    'tb.restoreAll': 'Odtwórz wszystko do folderu',
    'tb.restoreShort': 'Odtwórz wszystko',
    'tb.refresh': 'Odśwież  (F5)',
    'tb.addFiles': 'Dodaj pliki',
    'tb.addFilesKey': 'Dodaj pliki  (Ctrl+U)',
    'tb.more': 'Więcej',

    'act.download': 'Pobierz',
    'act.downloadN': 'Pobierz ({n})',
    'act.verify': 'Sprawdź',
    'act.delete': 'Usuń',
    'act.copyId': 'Kopiuj identyfikator',
    'act.goToFolder': 'Przejdź do folderu',

    'sort.title': 'Sortowanie',
    'sort.name': 'Nazwa',
    'sort.size': 'Rozmiar',
    'sort.date': 'Data',

    'chip.needCopy': 'czeka na drugą kopię: {n}',

    'col.name': 'Nazwa',
    'col.size': 'Rozmiar',
    'col.copies': 'Kopie',
    'col.added': 'Dodano',

    'row.empty': 'pusty',

    'empty.noMatch': 'Nic nie pasuje do „{q}”.',
    'empty.allCopies': 'Każdy plik tutaj ma już swoje kopie.',
    'empty.folder': 'Ten folder jest pusty.',
    'empty.none': 'Jeszcze nic tu nie ma — upuść pliki w dowolnym miejscu tego okna.',
    'empty.showAll': 'Pokaż wszystkie pliki',
    'err.account': 'Nie udało się połączyć z kontem',
    'err.tryAgain': 'Spróbuj ponownie',

    'det.nameUnreadable': 'Nazwa nieczytelna',
    'det.previewNoCopy': 'Nie ma jeszcze potwierdzonej kopii do odczytu — sieć wciąż ją rozmieszcza.',
    'det.previewErr': 'Nie udało się odczytać tego pliku: {e}',
    'det.notImage': 'Jednak nie obrazek',
    'det.identifier': 'Identyfikator',
    'det.folder': 'Folder',
    'det.noCopyYet': 'Brak potwierdzonej kopii. Trwa rozmieszczanie — sprawdź za kilka minut.',
    'det.oneCopy': 'Tylko jedna potwierdzona kopia. Sieć sama odbuduje drugą.',

    'dlg.deleteTitle': 'Usunąć {files}?',
    'dlg.deleteBody': 'Kopie znikają u każdego sprzedawcy. Tego nie da się cofnąć.',
    'dlg.cancel': 'Anuluj',
    'dlg.newFolder': 'Nowy folder',
    'dlg.folderHint': 'zdjecia/2026',
    'dlg.folderHelp': 'Foldery żyją wewnątrz zaszyfrowanej nazwy pliku — serwer ich nie widzi.',
    'dlg.go': 'Przejdź',

    'busy.uploading': 'Wysyłam…',
    'busy.uploadingN': 'Wysyłam {i}/{n}: {f}',
    'busy.downloading': 'Pobieram…',
    'busy.downloadingN': 'Pobieram {i}/{n}: {f}',
    'busy.deleting': 'Usuwam…',
    'busy.refreshing': 'Odświeżam…',
    'busy.restoring': 'Odtwarzam…',
    'busy.restoringN': 'Odtwarzam {i}/{n}: {f}',
    'busy.verifying': 'Sprawdzam…',
    'busy.verifyingN': 'Sprawdzam {i}/{n}: {f}',

    'route.direct': 'bezpośrednio',
    'route.server': 'przez serwer',

    'toast.uploaded': 'Wysłano {files} · {route}',
    'toast.saved': 'Zapisano {files} do {dir}',
    'toast.deleted': 'Usunięto {files}',
    'toast.folderReady': 'Folder „{f}” jest gotowy — upuść tu pliki albo użyj „Dodaj pliki”',
    'toast.restored': 'Odtworzono {files} do {dir}',
    'toast.restoreFail': 'Odtworzono {ok}, nie udało się {bad}: {list}',
    'toast.verifyOk': 'Wszystko się zgadza — {files}, bajty i podpisy',
    'toast.verifyBad': '{ok} w porządku, {bad} BŁĄD: {list}',
    'toast.noDup': 'Nie znaleziono duplikatów',
    'toast.dupSel': 'Zaznaczono {dup} ({size}) — najnowszy z każdej pary zostaje',
    'toast.idCopied': 'Skopiowano identyfikator',

    'drop.here': 'Upuść, żeby zaszyfrować i wysłać',
    'drop.into': 'Upuść do „{f}”',

    'st.connected': 'Połączono',
    'st.offline': 'Offline',
    'st.lastDirect': 'ostatni transfer: bezpośrednio do hosta',
    'st.lastServer': 'ostatni transfer: przez serwer',
    'st.counts': 'widocznych {shown} · razem {total}',

    'time.now': 'przed chwilą',
    'time.min': '{n} min temu',
    'time.h': '{n} godz. temu',
    'time.d': '{n} dni temu',

    'tray.show': 'Otwórz Sensmos Store',
    'tray.quit': 'Zakończ',
    'tray.hidden': 'Sensmos Store działa dalej w zasobniku — kopia zapasowa robi się o czasie.',
  },

  // ── niemiecki ──────────────────────────────────────────────────────────────
  'de': {
    'plural.files.one': '{n} Datei',
    'plural.files.other': '{n} Dateien',
    'plural.dup.one': '{n} Duplikat',
    'plural.dup.other': '{n} Duplikate',

    'pair.hint': 'Auf dem Telefon: Einstellungen → Gekoppelte Geräte → Koppeln,\ndann diesen Code eintippen.',
    'pair.waiting': 'Warte auf das Telefon…',
    'pair.newCode': 'Neuer Code',
    'pair.privacy': 'Der Code erreicht unseren Server nie — nur sein Hash. Was das Telefon '
        'übergibt, ist für diesen Computer versiegelt, und wir haben nichts, um es zu öffnen.',
    'pair.refused': 'der Server hat die Kopplung abgelehnt',
    'pair.expired': 'der Code ist abgelaufen',
    'pair.timeout': 'niemand hat sich rechtzeitig gekoppelt',

    'pair2.title': 'Weiteren Computer koppeln',
    'pair2.hint': 'Starten Sie Sensmos Store auf dem anderen Computer. Er zeigt einen Code — '
        'tippen Sie ihn hier ein. Das Telefon brauchen Sie dafür nicht.',
    'pair2.code': 'Code vom anderen Computer',
    'pair2.check': 'Code prüfen',
    'pair2.asks': '„{name}” bittet um Zugang zum Konto',
    'pair2.pickHint': 'Wählen Sie, was dieser Computer darf. Sie können es jederzeit am Telefon '
        'zurücknehmen, unter Einstellungen → Gekoppelte Geräte.',
    'pair2.readFiles': 'Darf Dateien lesen',
    'pair2.readFilesHint': 'Ohne dies lädt er Dateien hoch und sieht die Liste, öffnet aber '
        'keinen einzigen Namen — nicht einmal den eigenen Upload nach einem Neustart.',
    'pair2.noSeed': 'Dieser Computer kann das Leserecht nicht weitergeben, weil er es selbst '
        'nicht hat. Koppeln Sie den anderen Computer vom Telefon aus.',
    'pair2.noChain': 'Ein von hier gekoppelter Computer koppelt keine weiteren. Dafür braucht es '
        'das Telefon.',
    'pair2.pair': 'Koppeln',
    'pair2.searching': 'Suche…',
    'pair2.pairing': 'Kopple…',
    'pair2.done': 'Gekoppelt. Der andere Computer sollte Ihre Dateien gleich öffnen.',
    'pair2.noToken': 'der Server hat kein Token ausgestellt',
    'pair2.noHandover': 'das Token konnte nicht übergeben werden',
    'pair2.noBox': 'dieser Computer hat keinen Kontoschlüssel',
    'pair2.close': 'Schließen',
    'log.foldersFilled': 'Ordner ergänzt: {n}',
    'menu.pairPc': 'Weiteren Computer koppeln',

    'menu.account': 'Konto',
    'menu.language': 'Sprache',
    'menu.hide': 'In den Infobereich',
    'menu.closeToTray': 'Schließen legt in den Infobereich',
    'dlg.unpairTitle': 'Diesen Computer entkoppeln?',
    'dlg.unpairBody': 'Dieser Computer vergisst seinen Schl\u00fcssel und kehrt zum Kopplungscode '
        'zur\u00fcck. Ihre Dateien bleiben unber\u00fchrt. Das Zugriffstoken bleibt in der '
        'Ger\u00e4teliste des Telefons, bis Sie es dort entfernen.',
    'dlg.unpairYes': 'Entkoppeln',
    'menu.unpair': 'Diesen Computer entkoppeln',

    'sec.folders': 'Ordner',
    'sec.backup': 'Sicherung',
    'sec.news': 'Neuigkeiten',
    'folders.all': 'Alle Dateien',

    'pkg.title': 'Paket {n} GB',
    'pkg.used': '{size} belegt · {files}',
    'pkg.daily': '{galu} GALU/Tag · {n} Kopien',
    'pkg.balance': 'Sie haben {galu} GALU · etwa {days} Tage zu diesem Satz',
    'pkg.grow': '1 GB dazukaufen',
    'pkg.shrink': '1 GB zurückgeben',
    'pkg.resized': 'Das Paket hat jetzt {n} GB',
    'busy.resizing': 'Größe wird geändert…',
    'pkg.writeOnly': 'Nur Schreiben: Dieser Computer hat keinen Leseschlüssel, Namen bleiben verborgen.',

    'backup.add': 'Weiteren Ordner beobachten',
    'backup.addFirst': 'Ordner beobachten',
    'backup.target': 'geht nach {f}',
    'backup.targetRoot': 'geht direkt hinein',
    'backup.rename': 'Zielordner umbenennen',
    'backup.stop': 'Nicht mehr beobachten',
    'dlg.watchTitle': '\u201e{f}\u201c sichern',
    'dlg.parent': 'In einen Ordner legen',
    'dlg.parentName': 'Ordnername',
    'dlg.stopTitle': 'Diesen Ordner nicht mehr beobachten?',
    'dlg.stopBody': 'Nur das Beobachten endet. Alles, was bereits im Store liegt, bleibt genau dort.',
    'dlg.stopYes': 'Nicht mehr beobachten',
    'dlg.renameTitle': 'Zielordner',
    'dlg.renameBody': 'Neue Dateien landen ab jetzt hier. Bereits Hochgeladenes bleibt in seinem alten Ordner und wird NICHT erneut gesendet \u2014 ein Umzug hie\u00dfe, dieselben Bytes doppelt zu bezahlen.',
    'dlg.save': 'Speichern',
    'media.play': 'Abspielen',
    'media.fetching': 'Hole {size}\u2026',
    'media.failed': 'Konnte nicht abgespielt werden: {e}',
    'media.big': 'Abspielen ({size})',
    'menu.log': '\u00dcbertragungen und Protokoll',
    'log.title': '\u00dcbertragungen und Protokoll',
    'log.copy': 'Alles kopieren',
    'log.copied': 'In die Zwischenablage kopiert',
    'log.all': 'Alles',
    'log.transfers': '\u00dcbertragungen',
    'log.problems': 'Probleme',
    'log.kept': 'nur diese Sitzung',
    'log.empty': 'Bisher ist nichts passiert.',
    'log.resume': 'Verbindung bei {f} abgerissen \u2014 es geht weiter, wo es aufh\u00f6rte',
    'log.upload': '{f} gesendet',
    'log.download': '{f} geholt',
    'log.delete': '{f} gel\u00f6scht',
    'log.failed': '{f} \u2014 {e}',
    'stuck.title': 'Unvollst\u00e4ndig gesendet: {files}',
    'stuck.body': 'Kein einziges Byte hat einen Anbieter erreicht, das Netz kann also nichts '
        'wiederherstellen. Diese Eintr\u00e4ge belegen weiterhin Ihr Paket.',
    'stuck.retry': 'Erneut senden',
    'stuck.forget': 'Entfernen',
    'stuck.gone': 'Das Original liegt nicht mehr unter {p}',
    'stuck.done': 'Erneut gesendet: {files}',
    'det.notUploaded': 'Diese \u00dcbertragung wurde nie beendet \u2014 nirgends liegt etwas.',
    'folders.more': '{n} weitere zeigen',
    'folders.less': 'weniger zeigen',
    'nopkg.title': 'Dieses Konto hat noch keinen Platz im Store',
    'nopkg.body': 'Store h\u00e4lt verschl\u00fcsselte Kopien Ihrer Dateien auf den Nodes anderer Leute. '
        'Der Schl\u00fcssel bleibt in Ihrer Wallet \u2014 niemand, wir eingeschlossen, sieht Namen oder '
        'Inhalte. Bezahlt wird in GALU, pro Tag, solange Sie den Platz behalten.',
    'nopkg.size': 'Wie viel Platz?',
    'nopkg.cost': '{galu} GALU/Tag \u00b7 {n} Kopien jeder Datei',
    'nopkg.balance': 'Sie haben {galu} GALU \u2014 etwa {days} Tage zu diesem Satz',
    'nopkg.buy': '{n} GB kaufen',
    'nopkg.recheck': 'Erneut pr\u00fcfen',
    'nopkg.none': 'Gerade verkauft niemand Platz. Versuchen Sie es sp\u00e4ter.',
    'nopkg.funds': 'Zu wenig GALU: {need} n\u00f6tig, Sie haben {have}.',
    'nopkg.bought': 'Fertig \u2014 {n} GB geh\u00f6ren Ihnen. Dateien irgendwo in dieses Fenster ziehen.',
    'nopkg.card': 'Kein Paket',
    'nopkg.cardBody': 'Kaufen Sie Platz, um hier Dateien abzulegen.',
    'nopkg.max': 'derzeit h\u00f6chstens {n} GB',
    'copies.label': 'Wie viele Kopien',
    'copies.rec': '{n} · empfohlen',
    'copies.why': 'Ein Host, der verstummt, fällt erst nach drei Tagen aus dem Paket, und erst '
        'dann wird die Kopie anderswo neu aufgebaut. Bei zwei Kopien hängt die Datei diese Zeit '
        'an einer einzigen Platte, bei drei an zweien.',
    'copies.now': '{n} Kopien jeder Datei',
    'copies.rebuild': 'Wiederaufbau: {a} von {b} Kopien vorhanden',
    'copies.done': 'Jetzt {n} Kopien jeder Datei',
    'busy.copies': 'Zahl der Kopien wird geändert…',
    'arrears.title': 'Uploads pausiert \u2014 unbezahlte Tage: {n}',
    'arrears.body': 'Die Tagesgeb\u00fchr ging nicht durch. Laden Sie GALU auf \u2014 Uploads laufen nach '
        'einem bezahlten Tag weiter. Ihre Dateien bleiben genau dort, wo sie sind.',
    'act.delFolder': 'Ordner l\u00f6schen',
    'act.forgetFolder': 'Diesen leeren Ordner vergessen',
    'dlg.delFolderTitle': '\u201e{f}\u201c und {files} l\u00f6schen?',
    'dup.askTitle': '{files} Byte f\u00fcr Byte vergleichen?',
    'dup.askBody': 'Gleicher Name und gleiche Gr\u00f6\u00dfe hei\u00dft nur, dass sie \u00fcbereinstimmen K\u00d6NNTEN. '
        'F\u00fcr Gewissheit m\u00fcssen die Dateien hier gelesen und gehasht werden \u2014 der Server hilft '
        'nicht: jeder Upload bekommt einen eigenen Zufallsschl\u00fcssel, zwei identische Dateien '
        'sehen f\u00fcr ihn also verschieden aus. Das holt {size}.',
    'dup.go': 'Vergleichen',
    'dup.checking': 'Vergleiche\u2026',
    'dup.checkingN': 'Lese {i}/{n}: {f}',
    'dup.needRead': 'Dieser Computer hat keinen Leseschl\u00fcssel und kann Inhalte nicht vergleichen.',
    'tb.deleteAll': 'Alles l\u00f6schen',
    'dlg.delAllTitle': 'Alle {files} ({size}) l\u00f6schen?',
    'dlg.delAllBody': 'Jede Datei und jeder Ordner verschwinden, bei jedem Anbieter. Das Paket '
        'bleibt gekauft \u2014 Platz und Tagesgeb\u00fchr bleiben, nur der Inhalt ist weg. Das l\u00e4sst sich '
        'nicht r\u00fcckg\u00e4ngig machen.',
    'backup.intro': 'Einen Ordner beobachten und hier gesichert halten — verschlüsselt, in eine Richtung.',
    'backup.choose': 'Ordner wählen',
    'backup.never': 'Noch nie gelaufen',
    'backup.last': 'Zuletzt: {when}',
    'backup.now': 'Jetzt sichern',
    'backup.changeFolder': 'Ordner ändern',
    'backup.auto': 'Automatisch, alle {n} Min.',
    'backup.scanning': 'Durchsuche…',
    'busy.stop': 'Stopp',
    'busy.stopping': 'Wird gestoppt…',
    'backup.stopped': 'Gestoppt · {a} gesendet',
    'backup.gone': 'Ordner ist verschwunden',
    'backup.checking': 'Prüfe {i}/{n}: {f}',
    'backup.sending': 'Sende {i}/{n}: {f}',
    'backup.upToDate': 'Aktuell — unverändert: {n}',
    'backup.sent': 'Gesendet {a}, unverändert {b}',
    'backup.failed': 'Fehlgeschlagen: {e}',

    'tb.up': 'Eine Ebene höher',
    'tb.search': 'Suchen  (Strg+F)',
    'tb.selected': '{n} ausgewählt',
    'tb.duplicates': 'Duplikate finden',
    'tb.newFolder': 'Neuer Ordner',
    'tb.restoreAll': 'Alles in einen Ordner wiederherstellen',
    'tb.restoreShort': 'Alles wiederherstellen',
    'tb.refresh': 'Aktualisieren  (F5)',
    'tb.addFiles': 'Dateien hinzufügen',
    'tb.addFilesKey': 'Dateien hinzufügen  (Strg+U)',
    'tb.more': 'Mehr',

    'act.download': 'Herunterladen',
    'act.downloadN': 'Herunterladen ({n})',
    'act.verify': 'Prüfen',
    'act.delete': 'Löschen',
    'act.copyId': 'Kennung kopieren',
    'act.goToFolder': 'Zum Ordner',

    'sort.title': 'Sortieren',
    'sort.name': 'Name',
    'sort.size': 'Größe',
    'sort.date': 'Datum',

    'chip.needCopy': '{n} brauchen eine zweite Kopie',

    'col.name': 'Name',
    'col.size': 'Größe',
    'col.copies': 'Kopien',
    'col.added': 'Hinzugefügt',

    'row.empty': 'leer',

    'empty.noMatch': 'Nichts passt zu „{q}“.',
    'empty.allCopies': 'Jede Datei hier hat bereits ihre Kopien.',
    'empty.folder': 'Dieser Ordner ist leer.',
    'empty.none': 'Noch nichts hier — Dateien irgendwo in dieses Fenster ziehen.',
    'empty.showAll': 'Alle Dateien zeigen',
    'err.account': 'Konto nicht erreichbar',
    'err.tryAgain': 'Erneut versuchen',

    'det.nameUnreadable': 'Name nicht lesbar',
    'det.previewNoCopy': 'Noch keine bestätigte Kopie zum Lesen — das Netz verteilt sie gerade.',
    'det.previewErr': 'Diese Datei konnte nicht gelesen werden: {e}',
    'det.notImage': 'Doch kein Bild',
    'det.identifier': 'Kennung',
    'det.folder': 'Ordner',
    'det.noCopyYet': 'Noch keine bestätigte Kopie. Sie wird gerade verteilt — in ein paar Minuten erneut prüfen.',
    'det.oneCopy': 'Nur eine bestätigte Kopie. Das Netz baut die zweite von selbst wieder auf.',

    'dlg.deleteTitle': '{files} löschen?',
    'dlg.deleteBody': 'Die Kopien werden bei jedem Anbieter entfernt. Das lässt sich nicht rückgängig machen.',
    'dlg.cancel': 'Abbrechen',
    'dlg.newFolder': 'Neuer Ordner',
    'dlg.folderHint': 'fotos/2026',
    'dlg.folderHelp': 'Ordner leben im verschlüsselten Dateinamen — der Server sieht sie nie.',
    'dlg.go': 'Los',

    'busy.uploading': 'Sende…',
    'busy.uploadingN': 'Sende {i}/{n}: {f}',
    'busy.downloading': 'Lade herunter…',
    'busy.downloadingN': 'Lade herunter {i}/{n}: {f}',
    'busy.deleting': 'Lösche…',
    'busy.refreshing': 'Aktualisiere…',
    'busy.restoring': 'Stelle wieder her…',
    'busy.restoringN': 'Stelle wieder her {i}/{n}: {f}',
    'busy.verifying': 'Prüfe…',
    'busy.verifyingN': 'Prüfe {i}/{n}: {f}',

    'route.direct': 'direkt',
    'route.server': 'über den Server',

    'toast.uploaded': '{files} gesendet · {route}',
    'toast.saved': '{files} nach {dir} gespeichert',
    'toast.deleted': '{files} gelöscht',
    'toast.folderReady': 'Ordner „{f}“ ist bereit — Dateien hierher ziehen oder „Dateien hinzufügen“',
    'toast.restored': '{files} nach {dir} wiederhergestellt',
    'toast.restoreFail': '{ok} wiederhergestellt, {bad} fehlgeschlagen: {list}',
    'toast.verifyOk': 'Alles stimmt — {files}, Bytes und Signaturen',
    'toast.verifyBad': '{ok} in Ordnung, {bad} FEHLER: {list}',
    'toast.noDup': 'Keine Duplikate gefunden',
    'toast.dupSel': '{dup} ausgewählt ({size}) — das neueste bleibt jeweils unberührt',
    'toast.idCopied': 'Kennung kopiert',

    'drop.here': 'Loslassen zum Verschlüsseln und Senden',
    'drop.into': 'In „{f}“ ablegen',

    'st.connected': 'Verbunden',
    'st.offline': 'Offline',
    'st.lastDirect': 'letzte Übertragung: direkt zum Host',
    'st.lastServer': 'letzte Übertragung: über den Server',
    'st.counts': '{shown} sichtbar · {total} gesamt',

    'time.now': 'gerade eben',
    'time.min': 'vor {n} Min.',
    'time.h': 'vor {n} Std.',
    'time.d': 'vor {n} T.',

    'tray.show': 'Sensmos Store öffnen',
    'tray.quit': 'Beenden',
    'tray.hidden': 'Sensmos Store läuft im Infobereich weiter — die Sicherung bleibt im Takt.',
  },

  // ── portugalski ────────────────────────────────────────────────────────────
  'pt': {
    'plural.files.one': '{n} ficheiro',
    'plural.files.other': '{n} ficheiros',
    'plural.dup.one': '{n} duplicado',
    'plural.dup.other': '{n} duplicados',

    'pair.hint': 'No telemóvel: Definições → Dispositivos emparelhados → Emparelhar,\ndepois escreva este código.',
    'pair.waiting': 'À espera do telemóvel…',
    'pair.newCode': 'Novo código',
    'pair.privacy': 'O código nunca chega ao nosso servidor — apenas o seu hash. O que o telemóvel '
        'entrega está selado para este computador e não temos nada com que o abrir.',
    'pair.refused': 'o servidor recusou o emparelhamento',
    'pair.expired': 'o código expirou',
    'pair.timeout': 'ninguém emparelhou dentro do tempo',

    'pair2.title': 'Emparelhar outro computador',
    'pair2.hint': 'Abra o Sensmos Store no outro computador. Ele mostra um código — escreva-o '
        'aqui. Não vai precisar do telemóvel.',
    'pair2.code': 'Código do outro computador',
    'pair2.check': 'Verificar o código',
    'pair2.asks': '„{name}” pede acesso à conta',
    'pair2.pickHint': 'Escolha o que esse computador pode fazer. Pode retirá-lo a qualquer '
        'momento no telemóvel, em Definições → Dispositivos emparelhados.',
    'pair2.readFiles': 'Pode ler ficheiros',
    'pair2.readFilesHint': 'Sem isto envia ficheiros e vê a lista, mas não abre um único nome — '
        'nem sequer o seu próprio envio depois de reiniciar.',
    'pair2.noSeed': 'Este computador não tem como passar o direito de leitura, porque também não '
        'o tem. Emparelhe o outro computador a partir do telemóvel.',
    'pair2.noChain': 'Um computador emparelhado a partir daqui não emparelha mais nenhum. Para '
        'isso é preciso o telemóvel.',
    'pair2.pair': 'Emparelhar',
    'pair2.searching': 'A procurar…',
    'pair2.pairing': 'A emparelhar…',
    'pair2.done': 'Emparelhado. O outro computador deve abrir os seus ficheiros dentro de momentos.',
    'pair2.noToken': 'o servidor não emitiu um token',
    'pair2.noHandover': 'não foi possível entregar o token',
    'pair2.noBox': 'este computador não tem a chave da conta',
    'pair2.close': 'Fechar',
    'log.foldersFilled': 'pastas preenchidas: {n}',
    'menu.pairPc': 'Emparelhar outro computador',

    'menu.account': 'Conta',
    'menu.language': 'Idioma',
    'menu.hide': 'Ocultar na área de notificação',
    'menu.closeToTray': 'Fechar oculta na área de notificação',
    'dlg.unpairTitle': 'Desemparelhar este computador?',
    'dlg.unpairBody': 'Este computador esquece a sua chave e volta ao ecr\u00e3 do c\u00f3digo. Os seus '
        'ficheiros ficam intactos. O token de acesso permanece na lista de dispositivos do '
        'telem\u00f3vel at\u00e9 que o remova a\u00ed.',
    'dlg.unpairYes': 'Desemparelhar',
    'menu.unpair': 'Desemparelhar este computador',

    'sec.folders': 'Pastas',
    'sec.backup': 'Cópia de segurança',
    'sec.news': 'Novidades',
    'folders.all': 'Todos os ficheiros',

    'pkg.title': 'Pacote de {n} GB',
    'pkg.used': '{size} usados · {files}',
    'pkg.daily': '{galu} GALU/dia · {n} cópias',
    'pkg.balance': 'Tem {galu} GALU · cerca de {days} dias a este ritmo',
    'pkg.grow': 'Comprar mais 1 GB',
    'pkg.shrink': 'Devolver 1 GB',
    'pkg.resized': 'O pacote tem agora {n} GB',
    'busy.resizing': 'A alterar o tamanho…',
    'pkg.writeOnly': 'Só escrita: este computador não tem chave de leitura, os nomes ficam ocultos.',

    'backup.add': 'Vigiar outra pasta',
    'backup.addFirst': 'Vigiar uma pasta',
    'backup.target': 'vai para {f}',
    'backup.targetRoot': 'vai diretamente para o Store',
    'backup.rename': 'Mudar a pasta de destino',
    'backup.stop': 'Deixar de vigiar',
    'dlg.watchTitle': 'C\u00f3pia de \u201c{f}\u201d',
    'dlg.parent': 'Colocar dentro de uma pasta',
    'dlg.parentName': 'Nome da pasta',
    'dlg.stopTitle': 'Deixar de vigiar esta pasta?',
    'dlg.stopBody': 'S\u00f3 a vigil\u00e2ncia termina. Tudo o que j\u00e1 est\u00e1 no Store fica exatamente onde est\u00e1.',
    'dlg.stopYes': 'Deixar de vigiar',
    'dlg.renameTitle': 'Pasta de destino',
    'dlg.renameBody': 'Os novos ficheiros passam a ir para aqui. O que j\u00e1 foi enviado fica na pasta antiga e N\u00c3O \u00e9 enviado de novo \u2014 mov\u00ea-lo seria pagar duas vezes pelos mesmos bytes.',
    'dlg.save': 'Guardar',
    'media.play': 'Reproduzir',
    'media.fetching': 'A obter {size}\u2026',
    'media.failed': 'N\u00e3o foi poss\u00edvel reproduzir: {e}',
    'media.big': 'Reproduzir ({size})',
    'menu.log': 'Transfer\u00eancias e registo',
    'log.title': 'Transfer\u00eancias e registo',
    'log.copy': 'Copiar tudo',
    'log.copied': 'Copiado para a \u00e1rea de transfer\u00eancia',
    'log.all': 'Tudo',
    'log.transfers': 'Transfer\u00eancias',
    'log.problems': 'Problemas',
    'log.kept': 'apenas esta sess\u00e3o',
    'log.empty': 'Ainda n\u00e3o aconteceu nada.',
    'log.resume': 'liga\u00e7\u00e3o caiu em {f} \u2014 continuo de onde parou',
    'log.upload': '{f} enviado',
    'log.download': '{f} obtido',
    'log.delete': '{f} eliminado',
    'log.failed': '{f} \u2014 {e}',
    'stuck.title': 'envio nunca conclu\u00eddo: {files}',
    'stuck.body': 'Nem um byte chegou a qualquer vendedor, por isso a rede n\u00e3o tem de onde '
        'reconstruir. Estes registos continuam a ocupar o seu pacote.',
    'stuck.retry': 'Enviar de novo',
    'stuck.forget': 'Remover',
    'stuck.gone': 'O original j\u00e1 n\u00e3o est\u00e1 em {p}',
    'stuck.done': 'Enviados de novo: {files}',
    'det.notUploaded': 'Este envio nunca terminou \u2014 n\u00e3o ficou nada em lado nenhum.',
    'folders.more': 'mostrar mais {n}',
    'folders.less': 'mostrar menos',
    'nopkg.title': 'Esta conta ainda n\u00e3o tem espa\u00e7o no Store',
    'nopkg.body': 'O Store guarda c\u00f3pias cifradas dos seus ficheiros nos nodes de outras pessoas. '
        'A chave fica na sua carteira \u2014 ningu\u00e9m, nem n\u00f3s, v\u00ea os nomes ou o conte\u00fado. Paga em '
        'GALU, por dia, enquanto mantiver o espa\u00e7o.',
    'nopkg.size': 'Quanto espa\u00e7o?',
    'nopkg.cost': '{galu} GALU/dia \u00b7 {n} c\u00f3pias de cada ficheiro',
    'nopkg.balance': 'Tem {galu} GALU \u2014 cerca de {days} dias a este ritmo',
    'nopkg.buy': 'Comprar {n} GB',
    'nopkg.recheck': 'Verificar de novo',
    'nopkg.none': 'Ningu\u00e9m est\u00e1 a vender espa\u00e7o agora. Tente daqui a pouco.',
    'nopkg.funds': 'GALU insuficiente: precisa de {need}, tem {have}.',
    'nopkg.bought': 'Pronto \u2014 {n} GB s\u00e3o seus. Largue ficheiros em qualquer ponto desta janela.',
    'nopkg.card': 'Sem pacote',
    'nopkg.cardBody': 'Compre espa\u00e7o para come\u00e7ar a guardar ficheiros aqui.',
    'nopkg.max': 'no m\u00e1ximo {n} GB neste momento',
    'copies.label': 'Quantas cópias',
    'copies.rec': '{n} · recomendado',
    'copies.why': 'Um anfitrião que se cala só sai do pacote ao fim de três dias, e só então a '
        'cópia é reconstruída noutro lado. Com duas cópias o ficheiro fica esse tempo num '
        'único disco; com três, em dois.',
    'copies.now': '{n} cópias de cada ficheiro',
    'copies.rebuild': 'A reconstruir: {a} de {b} cópias no lugar',
    'copies.done': 'Agora {n} cópias de cada ficheiro',
    'busy.copies': 'A alterar o número de cópias…',
    'arrears.title': 'Envios em pausa \u2014 dias por pagar: {n}',
    'arrears.body': 'A taxa di\u00e1ria n\u00e3o passou. Carregue GALU \u2014 os envios recome\u00e7am ap\u00f3s um dia '
        'pago. Os seus ficheiros ficam exatamente onde est\u00e3o.',
    'act.delFolder': 'Eliminar pasta',
    'act.forgetFolder': 'Esquecer esta pasta vazia',
    'dlg.delFolderTitle': 'Eliminar \u201c{f}\u201d e {files}?',
    'dup.askTitle': 'Comparar {files} byte a byte?',
    'dup.askBody': 'O mesmo nome e o mesmo tamanho s\u00f3 querem dizer que PODEM ser iguais. Para ter '
        'a certeza, os ficheiros t\u00eam de ser lidos e somados aqui \u2014 o servidor n\u00e3o ajuda: cada '
        'envio recebe a sua pr\u00f3pria chave aleat\u00f3ria, por isso dois ficheiros id\u00eanticos parecem-lhe '
        'diferentes. Isto vai obter {size}.',
    'dup.go': 'Comparar',
    'dup.checking': 'A comparar\u2026',
    'dup.checkingN': 'A ler {i}/{n}: {f}',
    'dup.needRead': 'Este computador n\u00e3o tem chave de leitura, por isso n\u00e3o compara conte\u00fados.',
    'tb.deleteAll': 'Eliminar tudo',
    'dlg.delAllTitle': 'Eliminar todos os {files} ({size})?',
    'dlg.delAllBody': 'Desaparecem todos os ficheiros e todas as pastas, em todos os vendedores. '
        'O pacote continua comprado \u2014 o espa\u00e7o e a taxa di\u00e1ria mant\u00eam-se, s\u00f3 o conte\u00fado se '
        'perde. Isto n\u00e3o pode ser desfeito.',
    'backup.intro': 'Vigie uma pasta e mantenha aqui a cópia — cifrada, num só sentido.',
    'backup.choose': 'Escolher pasta',
    'backup.never': 'Nunca executada',
    'backup.last': 'Última: {when}',
    'backup.now': 'Copiar agora',
    'backup.changeFolder': 'Mudar de pasta',
    'backup.auto': 'Automaticamente, a cada {n} min',
    'backup.scanning': 'A percorrer…',
    'busy.stop': 'Parar',
    'busy.stopping': 'A parar…',
    'backup.stopped': 'Parado · {a} enviados',
    'backup.gone': 'A pasta desapareceu',
    'backup.checking': 'A verificar {i}/{n}: {f}',
    'backup.sending': 'A enviar {i}/{n}: {f}',
    'backup.upToDate': 'Atualizado — sem alterações: {n}',
    'backup.sent': 'Enviados {a}, sem alterações {b}',
    'backup.failed': 'Falhou: {e}',

    'tb.up': 'Um nível acima',
    'tb.search': 'Procurar  (Ctrl+F)',
    'tb.selected': '{n} selecionados',
    'tb.duplicates': 'Encontrar duplicados',
    'tb.newFolder': 'Nova pasta',
    'tb.restoreAll': 'Restaurar tudo para uma pasta',
    'tb.restoreShort': 'Restaurar tudo',
    'tb.refresh': 'Atualizar  (F5)',
    'tb.addFiles': 'Adicionar ficheiros',
    'tb.addFilesKey': 'Adicionar ficheiros  (Ctrl+U)',
    'tb.more': 'Mais',

    'act.download': 'Transferir',
    'act.downloadN': 'Transferir ({n})',
    'act.verify': 'Verificar',
    'act.delete': 'Eliminar',
    'act.copyId': 'Copiar identificador',
    'act.goToFolder': 'Ir para a pasta',

    'sort.title': 'Ordenar',
    'sort.name': 'Nome',
    'sort.size': 'Tamanho',
    'sort.date': 'Data',

    'chip.needCopy': '{n} precisam de uma segunda cópia',

    'col.name': 'Nome',
    'col.size': 'Tamanho',
    'col.copies': 'Cópias',
    'col.added': 'Adicionado',

    'row.empty': 'vazia',

    'empty.noMatch': 'Nada corresponde a “{q}”.',
    'empty.allCopies': 'Todos os ficheiros aqui já têm as suas cópias.',
    'empty.folder': 'Esta pasta está vazia.',
    'empty.none': 'Ainda não há nada — largue ficheiros em qualquer ponto desta janela.',
    'empty.showAll': 'Mostrar todos os ficheiros',
    'err.account': 'Não foi possível contactar a conta',
    'err.tryAgain': 'Tentar de novo',

    'det.nameUnreadable': 'Nome ilegível',
    'det.previewNoCopy': 'Ainda não há cópia confirmada para ler — a rede está a colocá-la.',
    'det.previewErr': 'Não foi possível ler este ficheiro: {e}',
    'det.notImage': 'afinal não é uma imagem',
    'det.identifier': 'Identificador',
    'det.folder': 'Pasta',
    'det.noCopyYet': 'Ainda sem cópia confirmada. Está a ser colocada — verifique daqui a alguns minutos.',
    'det.oneCopy': 'Apenas uma cópia confirmada. A rede reconstrói a segunda sozinha.',

    'dlg.deleteTitle': 'Eliminar {files}?',
    'dlg.deleteBody': 'As cópias são removidas de todos os vendedores. Isto não pode ser desfeito.',
    'dlg.cancel': 'Cancelar',
    'dlg.newFolder': 'Nova pasta',
    'dlg.folderHint': 'fotos/2026',
    'dlg.folderHelp': 'As pastas vivem dentro do nome cifrado do ficheiro — o servidor nunca as vê.',
    'dlg.go': 'Ir',

    'busy.uploading': 'A enviar…',
    'busy.uploadingN': 'A enviar {i}/{n}: {f}',
    'busy.downloading': 'A transferir…',
    'busy.downloadingN': 'A transferir {i}/{n}: {f}',
    'busy.deleting': 'A eliminar…',
    'busy.refreshing': 'A atualizar…',
    'busy.restoring': 'A restaurar…',
    'busy.restoringN': 'A restaurar {i}/{n}: {f}',
    'busy.verifying': 'A verificar…',
    'busy.verifyingN': 'A verificar {i}/{n}: {f}',

    'route.direct': 'direto',
    'route.server': 'pelo servidor',

    'toast.uploaded': 'Enviados {files} · {route}',
    'toast.saved': 'Guardados {files} em {dir}',
    'toast.deleted': 'Eliminados {files}',
    'toast.folderReady': 'A pasta “{f}” está pronta — largue ficheiros aqui ou use “Adicionar ficheiros”',
    'toast.restored': 'Restaurados {files} para {dir}',
    'toast.restoreFail': 'Restaurados {ok}, falharam {bad}: {list}',
    'toast.verifyOk': 'Está tudo certo — {files}, bytes e assinaturas',
    'toast.verifyBad': '{ok} bem, {bad} FALHARAM: {list}',
    'toast.noDup': 'Nenhum duplicado encontrado',
    'toast.dupSel': '{dup} selecionados ({size}) — o mais recente de cada fica intacto',
    'toast.idCopied': 'Identificador copiado',

    'drop.here': 'Largue para cifrar e enviar',
    'drop.into': 'Largue em “{f}”',

    'st.connected': 'Ligado',
    'st.offline': 'Offline',
    'st.lastDirect': 'última transferência: direta para o anfitrião',
    'st.lastServer': 'última transferência: pelo servidor',
    'st.counts': '{shown} visíveis · {total} no total',

    'time.now': 'agora mesmo',
    'time.min': 'há {n} min',
    'time.h': 'há {n} h',
    'time.d': 'há {n} d',

    'tray.show': 'Abrir o Sensmos Store',
    'tray.quit': 'Sair',
    'tray.hidden': 'O Sensmos Store continua na área de notificação — a cópia mantém o horário.',
  },
};
