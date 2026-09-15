#!/usr/bin/env python3
"""Generates the unicode emoji catalogue Dart file.

Run from a directory holding the four sources, fetched once:

  curl -O https://unicode.org/Public/emoji/15.1/emoji-test.txt
  curl -O https://raw.githubusercontent.com/milesj/emojibase/master/packages/data/en/data.raw.json
  curl -O https://raw.githubusercontent.com/milesj/emojibase/master/packages/data/en/shortcodes/joypixels.raw.json
  curl -O https://raw.githubusercontent.com/milesj/emojibase/master/packages/data/en/shortcodes/emojibase.raw.json

Sources:
  - emoji-test.txt: Unicode's emoji-test data (15.1). Supplies the fully
    qualified RGI set, the CLDR keyboard order, and the nine groups.
  - emojibase-data.raw.json: Emojibase's full data. Supplies keywords and the
    skin variant table.
  - shortcodes-joypixels.json: the JoyPixels shortcode preset. Discord's own
    emoji names follow this family, so its first shortcode is the name the
    catalogue calls the emoji by.
  - shortcodes-emojibase.json: the Emojibase shortcode preset, kept as search
    aliases and as the name fallback for entries JoyPixels does not carry.

Emitted: a Dart part file with const tables. Kept entries are the fully
qualified emoji plus the five same-tone skin variants; the cross-tone couple
combinations are left out, as a keyboard palette does.
"""

import json

GROUP_ORDER = [
    'Smileys & Emotion',
    'People & Body',
    'Animals & Nature',
    'Food & Drink',
    'Travel & Places',
    'Activities',
    'Objects',
    'Symbols',
    'Flags',
]

GROUP_DART_NAMES = [
    'smileys',
    'people',
    'nature',
    'food',
    'travel',
    'activity',
    'objects',
    'symbols',
    'flags',
]

TONE_CPS = {'1F3FB', '1F3FC', '1F3FD', '1F3FE', '1F3FF'}
TONE_NUM = {'1F3FB': 1, '1F3FC': 2, '1F3FD': 3, '1F3FE': 4, '1F3FF': 5}


def parse_emoji_test(path):
    entries = []
    group = None
    with open(path, encoding='utf-8') as handle:
        for line in handle:
            line = line.strip()
            if line.startswith('# group:'):
                group = line.split(':', 1)[1].strip()
            elif line.startswith('# subgroup:'):
                continue
            elif line and not line.startswith('#'):
                parts = line.split(';')
                if len(parts) < 2:
                    continue
                cps = parts[0].strip().split()
                rest = parts[1]
                status = rest.split('#')[0].strip()
                comment = rest.split('#', 1)[1].strip() if '#' in rest else ''
                fields = comment.split()
                if len(fields) < 3:
                    continue
                entries.append(
                    dict(cps=cps, status=status, glyph=fields[0], group=group)
                )
    return entries


def code_lookup(table, hexcode):
    if hexcode in table:
        return table[hexcode]
    stripped = hexcode.replace('-FE0F', '')
    return table.get(stripped)


def codes_of(table, hexcode):
    value = code_lookup(table, hexcode)
    if isinstance(value, str):
        return [value]
    return list(value) if value else []


def insens(cps):
    return '-'.join(cp for cp in cps if cp != 'FE0F')


def build_catalog():
    entries = parse_emoji_test('emoji-test.txt')
    fully_qualified = [
        entry
        for entry in entries
        if entry['status'] == 'fully-qualified'
        and entry['group'] in GROUP_ORDER
    ]

    data = json.load(open('emojibase-data.raw.json'))
    data_by_hex = {}
    for entry in data:
        data_by_hex[entry['hexcode']] = entry
        for skin in entry.get('skins', []):
            data_by_hex[skin['hexcode']] = skin

    joy = json.load(open('shortcodes-joypixels.json'))
    base_codes = json.load(open('shortcodes-emojibase.json'))

    kept = []
    for entry in fully_qualified:
        tones = [TONE_NUM[cp] for cp in entry['cps'] if cp in TONE_CPS]
        if len(set(tones)) > 1:
            continue
        hexcode = '-'.join(entry['cps'])
        source = data_by_hex.get(hexcode)
        if source is None:
            source = data_by_hex.get(hexcode.replace('-FE0F', ''))
        assert source is not None, hexcode
        kept.append(
            dict(
                cps=entry['cps'],
                hexcode=hexcode,
                glyph=entry['glyph'],
                group=entry['group'],
                tone=tones[0] if tones else None,
                source=source,
            )
        )

    base_primary = {}
    for entry in kept:
        if entry['tone'] is not None:
            continue
        joy_codes = codes_of(joy, entry['hexcode'])
        other_codes = codes_of(base_codes, entry['hexcode'])
        primary = joy_codes[0] if joy_codes else other_codes[0]
        assert primary, entry['hexcode']
        base_primary[insens(entry['cps'])] = primary

    bases = []
    tones = {}
    seen = set()
    for entry in kept:
        joy_codes = codes_of(joy, entry['hexcode'])
        other_codes = codes_of(base_codes, entry['hexcode'])
        aliases = list(dict.fromkeys(joy_codes + other_codes))
        if entry['tone'] is None:
            primary = base_primary[insens(entry['cps'])]
            assert primary not in seen, primary
            seen.add(primary)
            bases.append(
                dict(
                    glyph=entry['glyph'],
                    name=primary,
                    group=GROUP_ORDER.index(entry['group']),
                    aliases=aliases,
                    tags=list(entry['source'].get('tags', [])),
                )
            )
        else:
            stripped = [cp for cp in entry['cps'] if cp not in TONE_CPS]
            base = base_primary[insens(stripped)]
            tone_name = joy_codes[0] if joy_codes else other_codes[0]
            tones.setdefault(base, {})[entry['tone']] = dict(
                glyph=entry['glyph'], name=tone_name
            )

    for base, variants in tones.items():
        assert sorted(variants) == [1, 2, 3, 4, 5], base
    all_names = [b['name'] for b in bases] + [
        variant['name'] for variants in tones.values() for variant in variants.values()
    ]
    assert len(all_names) == len(set(all_names)), 'name collision'
    return bases, tones


def dart_string(value):
    out = []
    for ch in value:
        if ch == "'":
            out.append("\\'")
        elif ch == '\\':
            out.append('\\\\')
        elif ord(ch) > 0xFFFF:
            point = ord(ch) - 0x10000
            out.append(f'\\u{0xD800 + (point >> 10):04X}')
            out.append(f'\\u{0xDC00 + (point & 0x3FF):04X}')
        elif ord(ch) > 126:
            out.append(f'\\u{ord(ch):04X}')
        else:
            out.append(ch)
    return "'" + ''.join(out) + "'"


def main():
    bases, tones = build_catalog()

    lines = []
    lines.append("part of 'unicode_emoji.dart';")
    lines.append('')
    lines.append('// GENERATED by tool/generate_unicode_emoji_data.py. Do not edit.')
    lines.append('//')
    lines.append('// Sources: Unicode emoji-test 15.1 (the set, order and groups), Emojibase')
    lines.append('// (keywords and skin variants), and the JoyPixels shortcode preset, whose')
    lines.append('// naming family is the one Discord resolves :names: against.')
    lines.append('//')

    per_group = {i: [] for i in range(9)}
    for base in bases:
        per_group[base['group']].append(base)

    for index, group in enumerate(GROUP_DART_NAMES):
        lines.append(f'const List<(String, String, String)> _k{group.title()} = [')
        for base in per_group[index]:
            search = ' '.join(dict.fromkeys(base['aliases'][1:] + base['tags']))
            lines.append(
                f"  ({dart_string(base['glyph'])}, {dart_string(base['name'])}, {dart_string(search)}),"
            )
        lines.append('];')
        lines.append('')

    lines.append('const Map<String, List<String>> _kTones = {')
    for base_name in [b['name'] for b in bases if b['name'] in tones]:
        variants = tones[base_name]
        glyphs = ', '.join(
            dart_string(variants[t]['glyph']) for t in (1, 2, 3, 4, 5)
        )
        names = ', '.join(
            dart_string(variants[t]['name']) for t in (1, 2, 3, 4, 5)
        )
        lines.append(f'  {dart_string(base_name)}: [{glyphs}, {names}],')
    lines.append('};')
    lines.append('')

    with open('unicode_emoji_data.dart', 'w', encoding='utf-8') as handle:
        handle.write('\n'.join(lines))
    print(f'bases: {len(bases)}, tone-capable: {len(tones)}')


if __name__ == '__main__':
    main()
