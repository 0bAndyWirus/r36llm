#!/usr/bin/env python3
"""Select a reproducible Latin-prose-compatible output vocabulary from a GGUF.

Run from the repository root: python scripts/vocab/generate.py
The default input is Ternary-Bonsai-2-2B-PTQ1_0.gguf. Only GGUF metadata is
read; the model weights are neither loaded nor modified. The output list uses
original token IDs, one per line, in ascending order. The JSON report records
counts and examples. Use scripts/vocab/corpus.txt with the native tokenizer to
measure corpus coverage; this heuristic does not tokenize that corpus.

The model uses GPT-2 byte-to-Unicode BPE, not literal Unicode token strings.
Decode its byte alphabet before classification. Preserve every non-normal
GGUF token (including control/user-defined/unused), explicit special token ID,
byte fallback token and every single-byte piece, even when it is not prose.
Normal multi-byte pieces are kept if their complete characters are Latin
letters, combining accents, digits, common punctuation or whitespace. UTF-8
fragments at token boundaries are accepted only when they could complete an
allowed character; this necessarily admits some fragments also usable by
other scripts. Code-only symbols and common code operators in multi-byte
pieces are excluded. This is a character heuristic, not a language detector:
other Latin-script languages, code made only of prose characters, and all
single-byte output remain possible. Conversely, normal prose with uncommon
symbols or code-like punctuation can be excluded. Native tokenization may
choose excluded merged pieces even if byte-level representation is possible.
"""

import argparse
import collections
import hashlib
import json
import re
import struct
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MODEL = ROOT / 'models/Ternary-Bonsai-2-2B-PTQ1_0.gguf'
DEFAULT_LIST = ROOT / 'card/r36llm/output-keep-en-fr.txt'
DEFAULT_REPORT = ROOT / 'out/vocab/selection.json'

# GPT-2's bijection maps visible Latin-1 bytes to themselves, then maps all
# remaining bytes to successive code points starting at U+0100.
def byte_decoder():
    visible = list(range(33, 127)) + list(range(161, 173)) + list(range(174, 256))
    chars = visible + list(range(256, 256 + 256 - len(visible)))
    byte_values = visible + [b for b in range(256) if b not in visible]
    return {chr(c): b for c, b in zip(chars, byte_values)}

DECODER = byte_decoder()
PUNCTUATION = set(' .,;:!?\'"-–—…()/%&+*$€£\n\r\t\u00a0«»“”‘’·')
CODE_SYMBOLS = set('_{}[]`\\|<>=~^@#')
# Double asterisks also mark ordinary prose emphasis, so keep them.
CODE_PATTERNS = re.compile(r'(?://|/\*|\*/|&&|\+\+|->|::)')


def allowed_character(ch):
    cat = unicodedata.category(ch)
    return (ch in PUNCTUATION or cat == 'Nd' and ord(ch) < 128 or
            cat.startswith('L') and 'LATIN' in unicodedata.name(ch, '') or
            0x300 <= ord(ch) <= 0x36f and cat.startswith('M'))


# Only a partial sequence at a token edge can be completed by adjacent tokens.
# Include suffixes as well as prefixes: a token may start with continuation
# bytes after a previous token's leading bytes.
PARTIAL_PREFIXES = set()
PARTIAL_SUFFIXES = set()
for point in range(0x80, 0x110000):
    char = chr(point)
    if allowed_character(char):
        encoded = char.encode('utf-8')
        for i in range(1, len(encoded)):
            PARTIAL_PREFIXES.add(encoded[:i])
            PARTIAL_SUFFIXES.add(encoded[i:])


def read_exact(f, count):
    data = f.read(count)
    if len(data) != count:
        raise ValueError('Truncated GGUF metadata')
    return data


def number(f, fmt):
    return struct.unpack('<' + fmt, read_exact(f, struct.calcsize(fmt)))[0]


def string(f):
    return read_exact(f, number(f, 'Q')).decode('utf-8')


SCALARS = {0: 'B', 1: 'b', 2: 'H', 3: 'h', 4: 'I', 5: 'i',
           6: 'f', 7: '?', 10: 'Q', 11: 'q', 12: 'd'}


def value(f, kind, keep):
    if kind == 8:
        length = number(f, 'Q')
        if keep:
            return read_exact(f, length).decode('utf-8')
        f.seek(length, 1)
        return None
    if kind == 9:
        subtype, count = number(f, 'I'), number(f, 'Q')
        if not keep and subtype in SCALARS:
            f.seek(struct.calcsize(SCALARS[subtype]) * count, 1)
            return None
        if keep:
            return [value(f, subtype, True) for _ in range(count)]
        for _ in range(count):
            value(f, subtype, False)
        return None
    if kind not in SCALARS:
        raise ValueError(f'Unsupported GGUF metadata type {kind}')
    if keep:
        return number(f, SCALARS[kind])
    f.seek(struct.calcsize(SCALARS[kind]), 1)
    return None


def metadata(path):
    with path.open('rb') as f:
        if read_exact(f, 4) != b'GGUF':
            raise ValueError('Expected a little-endian GGUF file')
        version = number(f, 'I')
        if version not in (2, 3):
            raise ValueError(f'Unsupported GGUF version {version}')
        number(f, 'Q')  # tensor count
        count = number(f, 'Q')
        result = {}
        for _ in range(count):
            key = string(f)
            kind = number(f, 'I')
            keep = (key in ('tokenizer.ggml.model', 'tokenizer.ggml.pre',
                            'tokenizer.ggml.tokens', 'tokenizer.ggml.token_type') or
                    key.startswith('tokenizer.ggml.') and key.endswith('_token_id'))
            data = value(f, kind, keep)
            if keep:
                result[key] = data
        return result


def classify(piece):
    try:
        raw = bytes(DECODER[ch] for ch in piece)
    except KeyError as exc:
        raise ValueError(f'Token not in GPT-2 byte alphabet: {piece!r}') from exc
    if len(raw) == 1:
        return 'single_byte'
    # Enumerating at most 4 x 4 boundary lengths avoids discarding valid
    # split UTF-8 while never ignoring invalid bytes in the interior.
    had_text = False
    code = False
    for start in range(min(3, len(raw)) + 1):
        if start and raw[:start] not in PARTIAL_SUFFIXES:
            continue
        for end in range(min(3, len(raw) - start) + 1):
            if end and raw[len(raw)-end:] not in PARTIAL_PREFIXES:
                continue
            middle = raw[start:len(raw)-end if end else len(raw)]
            try:
                text = middle.decode('utf-8')
            except UnicodeDecodeError:
                continue
            had_text = True
            if any(ch in CODE_SYMBOLS for ch in text) or CODE_PATTERNS.search(text):
                code = True
                continue
            if all(allowed_character(ch) for ch in text):
                return 'prose_or_utf8_fragment'
    return 'code_syntax' if code else ('non_latin_or_symbol' if had_text else 'invalid_or_other_utf8_fragment')


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--model', type=Path, default=DEFAULT_MODEL)
    parser.add_argument('--output', type=Path, default=DEFAULT_LIST)
    parser.add_argument('--report', type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()
    meta = metadata(args.model)
    if meta.get('tokenizer.ggml.model') != 'gpt2':
        raise ValueError('Only GPT-2 byte-encoded BPE tokenizers are supported')
    tokens = meta['tokenizer.ggml.tokens']
    types = meta['tokenizer.ggml.token_type']
    if len(tokens) != len(types):
        raise ValueError('Token and token-type counts differ')
    special_ids = {v for k, v in meta.items() if k.endswith('_token_id')}
    if any(not isinstance(i, int) or i < 0 or i >= len(tokens) for i in special_ids):
        raise ValueError('Special token ID outside vocabulary')
    counts = collections.Counter()
    examples = collections.defaultdict(list)
    kept = []
    digest = hashlib.sha256()
    for i, (token, token_type) in enumerate(zip(tokens, types)):
        encoded = token.encode('utf-8')
        digest.update(struct.pack('<QI', len(encoded), token_type))
        digest.update(encoded)
        if token_type != 1 or i in special_ids or re.fullmatch(r'<0x[0-9A-Fa-f]{2}>', token):
            category = 'special_control_or_byte_fallback'
        else:
            category = classify(token)
        counts[category] += 1
        if len(examples[category]) < 12:
            example = {'id': i, 'piece': token}
            if category != 'special_control_or_byte_fallback':
                raw = bytes(DECODER[ch] for ch in token)
                example['decoded_bytes_hex'] = raw.hex()
                example['decoded_utf8_preview'] = raw.decode('utf-8', errors='replace')
            examples[category].append(example)
        if category in ('special_control_or_byte_fallback', 'single_byte', 'prose_or_utf8_fragment'):
            kept.append(i)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(''.join(f'{i}\n' for i in kept), encoding='utf-8', newline='\n')
    report = {
        'model': args.model.name,
        'tokenizer_model': meta['tokenizer.ggml.model'],
        'tokenizer_pre': meta.get('tokenizer.ggml.pre'),
        'tokenizer_tokens_and_types_sha256': digest.hexdigest(),
        'vocabulary_size': len(tokens), 'kept': len(kept), 'dropped': len(tokens) - len(kept),
        'category_counts': dict(sorted(counts.items())),
        'category_examples_encoded_pieces': dict(sorted(examples.items())),
        'special_token_ids': sorted(special_ids),
        'limitations': 'Latin-compatible character filtering is not English/French language identification. Single bytes and special tokens remain unrestricted; boundary fragments may also compose other scripts. Native tokenizer coverage is not measured here.',
    }
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
    print(f"Kept {len(kept)} of {len(tokens)} tokens; wrote {args.output} and {args.report}")


if __name__ == '__main__':
    main()
