"""Port of game/tests/lint/test_lint_syntax.gd checks to Python.
Run: python3 check_syntax.py [files...]
"""
import re, sys, os


def read_bytes(p):
    with open(p, 'rb') as f:
        return f.read()


def read_text(p):
    return read_bytes(p).decode('utf-8', errors='replace')


def strip_strings_and_comments(line, in_triple, tq='"""'):
    out = ''
    i = 0
    n = len(line)
    while i < n:
        if in_triple:
            end = line.find(tq, i)
            if end < 0:
                return [out, True]
            i = end + 3
            in_triple = False
            continue
        if i < n and line[i] == '#':
            break
        if i + 2 < n and line[i:i+3] == tq:
            in_triple = True
            i += 3
            continue
        if i < n and line[i] == '"':
            i += 1
            while i < n and line[i] != '"':
                if line[i] == '\\' and i + 1 < n:
                    i += 2
                    continue
                i += 1
            if i < n:
                i += 1
            continue
        if i < n and line[i] == "'":
            i += 1
            while i < n and line[i] != "'":
                if line[i] == '\\' and i + 1 < n:
                    i += 2
                    continue
                i += 1
            if i < n:
                i += 1
            continue
        out += line[i]
        i += 1
    return [out, in_triple]


def _match(o):
    return {'(': ')', '[': ']', '{': '}'}[o]


def _open(c):
    return {')': '(', ']': '[', '}': '{'}[c]


def scan_brackets(text):
    issues = []
    lines = text.split('\n')
    in_triple = False
    stack = []
    for li, line in enumerate(lines):
        cleaned, in_triple = strip_strings_and_comments(line, in_triple)
        for c in cleaned:
            if c in '([{':
                stack.append({'c': _match(c), 'line': li + 1})
            elif c in ')]}':
                if not stack:
                    issues.append((li + 1, "stray '%s'" % c))
                elif stack[-1]['c'] != c:
                    issues.append((li + 1, "mismatch '%s'" % c))
                else:
                    stack.pop()
    for e in stack:
        issues.append((e['line'], "unclosed '%s'" % _open(e['c'])))
    return issues


def first_decl(text):
    for line in text.split('\n'):
        code = line.split('#')[0].lstrip()
        if not code:
            continue
        m = re.match(r'(extends|class_name|enum|const|var|func|signal)\b', code)
        if m:
            return m.group(1)
    return ''


def check(path):
    b = read_bytes(path)
    t = read_text(path)
    probs = []
    if b'\r\n' in b:
        probs.append('CRLF')
    if b[:3] == b'\xef\xbb\xbf':
        probs.append('BOM')
    if b'\r' in b.replace(b'\r\n', b''):
        probs.append('orphan-CR')
    iss = scan_brackets(t)
    if iss:
        probs.append('unbalanced:%s' % iss[:4])
    fd = first_decl(t)
    if fd == 'class_name':
        probs.append('class_name-before-extends')
    for i, line in enumerate(t.split('\n'), 1):
        if line[:1] == '\t' and line.lstrip('\t')[:1] == ' ':
            probs.append('mixed-tab-space L%d' % i)
            break
    for i, line in enumerate(t.split('\n'), 1):
        code = line.split('#')[0]
        for ch in code:
            if ord(ch) > 127:
                probs.append('non-ASCII L%d:%r' % (i, ch))
                break
    return probs


def main():
    files = sys.argv[1:] or []
    if not files:
        for dp, dn, fn in os.walk('game'):
            if '/tests' in dp:
                continue
            for f in fn:
                if f.endswith('.gd'):
                    files.append(os.path.join(dp, f))
    bad = 0
    for p in sorted(files):
        probs = check(p)
        if probs:
            bad += 1
            print('%s: %s' % (p, '; '.join(probs)))
    print('\n%d files with issues' % bad)
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())