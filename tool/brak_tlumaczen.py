# -*- coding: utf-8 -*-
"""Dwie rzeczy, ktorych `flutter test` w tej apce NIE zlapie.

Test `kazdy jezyk ma komplet kluczy angielskiego` pilnuje, zeby slowniki byly rowne.
Nie widzi natomiast:

  1. KLUCZA UZYTEGO W KODZIE, KTOREGO NIE MA W SLOWNIKU — `t()` zwraca wtedy sam klucz,
     wiec na ekranie ladnie wyswietla sie `pair2.title` zamiast napisu;
  2. POLSKIEGO WPISANEGO WPROST w widzet, z pominieciem `t()` — dla nie-Polaka to
     dokladnie to samo, co brak tlumaczenia.

Uruchomienie (przed KAZDYM wydaniem desktopu, obok `flutter test`):
    python -X utf8 tool/brak_tlumaczen.py
Kod wyjscia 1 = jest co poprawiac.
"""
import io, os, re, sys, glob

KORZEN = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB = os.path.join(KORZEN, 'lib')
OGONKI = re.compile('[ąćęłńóśźżĄĆĘŁŃÓŚŹŻ]')
UZYCIE = re.compile(r"""\bt\(\s*'([^']+)'""")
KLUCZ_W_SLOWNIKU = re.compile(r"""^\s*'([a-z][a-zA-Z0-9_.]*)'\s*:""", re.M)
# Napis w widzecie: 'coś' w Text(...) / label / title, ale NIE w wywolaniu t()
LITERAL = re.compile(r"""'([^'\\]*(?:\\.[^'\\]*)*)'""")


def klucze_slownika():
    s = io.open(os.path.join(LIB, 'i18n.dart'), encoding='utf-8').read()
    return set(KLUCZ_W_SLOWNIKU.findall(s))


def main():
    slownik = klucze_slownika()
    brakujace, twarde = [], []

    for p in glob.glob(os.path.join(LIB, '**', '*.dart'), recursive=True):
        if os.path.basename(p) == 'i18n.dart':
            continue
        for i, l in enumerate(io.open(p, encoding='utf-8').read().split('\n'), 1):
            if re.match(r'\s*//', l):
                continue
            rel = os.path.relpath(p, KORZEN)
            for k in UZYCIE.findall(l):
                if k not in slownik:
                    brakujace.append((rel, i, k))
            # polski wprost — po wycieciu tego, co siedzi w t('...')
            bez_t = re.sub(r"\bt\(\s*'[^']*'", 't(', l)
            for lit in LITERAL.findall(bez_t):
                if OGONKI.search(lit):
                    twarde.append((rel, i, lit))

    if brakujace:
        print('KLUCZE UZYTE, ALE NIEOBECNE W SLOWNIKU (na ekranie widac nazwe klucza):')
        for p, i, k in brakujace:
            print('  %s:%d  %s' % (p, i, k))
    if twarde:
        print('POLSKI WPISANY WPROST, Z POMINIECIEM t():')
        for p, i, lit in twarde:
            print('  %s:%d  %s' % (p, i, lit[:78]))
    print()
    print('brakujacych kluczy: %d | polskiego wprost: %d' % (len(brakujace), len(twarde)))
    return 1 if (brakujace or twarde) else 0


if __name__ == '__main__':
    sys.exit(main())
