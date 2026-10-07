#!/usr/bin/env python3
"""Rename the app in one go: user-visible name everywhere, optionally the ids.

Run from anywhere; the repository root is the parent of this tool/ directory
(override with --root). Python 3.9+, standard library only.

    python3 tool/rename_app.py --name "Hisn" --dry-run          # look first
    python3 tool/rename_app.py --name "Hisn"                    # display name
    python3 tool/rename_app.py --name "Hisn" --ids              # + technical ids
    python3 tool/rename_app.py --name "Hisn" --name-ar "حصن" --slug hisn --ids

What it changes (details, caveats and the list of strings that are kept on
purpose: docs/RENAMING.md):

  Always (display name)
    lib/brand.dart (const String appName), lib/l10n/app_*.arb appTitle and every
    string that contains the old name, the generated lib/l10n/*.dart (via
    `flutter gen-l10n`), AndroidManifest label, iOS CFBundleDisplayName and
    CFBundleName, Windows window title and Runner.rc ProductName /
    FileDescription / InternalName, README.md + docs, comments and tests that
    quote the old name, CI artifact names, the suggested backup file name.
  With --ids (technical identifiers)
    Dart package name (pubspec + every package:<old>/ import in lib/ and test/),
    class names that embed the old name (<Old>App, <Old>AutofillService, ...,
    renamed in Dart, Kotlin, Swift, C++ and the manifest together, and the
    files that carry them), Android applicationId / namespace and the Kotlin
    package directory + package lines, iOS PRODUCT_BUNDLE_IDENTIFIER, app group
    and keychain group, Windows CMake project / BINARY_NAME / CompanyName.
    --channels additionally renames the "<org>/platform" and "<org>/autofill"
    MethodChannel names, on the Dart, Kotlin, Swift and C++ side together.

What it NEVER changes: the cryptographic format strings that contain the old
slug ("vaultsnap/v1/<context>" associated data, the "vaultsnap-export" file
format tag, the "vaultsnap_bio_kek" storage key, the VSnap* KDF contexts) and
anything under supabase/. Changing those would make existing vaults, backups
and biometric wraps unreadable.

The tool is idempotent (a second run with the same arguments finds nothing to
do) and refuses to run on a dirty git working tree or on a tree whose current
name cannot be determined unambiguously, unless --force is given.
"""
from __future__ import annotations

import argparse
import difflib
import json
import os
import re
import shutil
import subprocess
import sys
import unicodedata
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Dict, List, Optional, Set, Tuple

SELF = 'tool/rename_app.py'

# Never edited and never scanned: this tool, its own documentation (both quote
# the old name as examples), and the lock file.
SKIP_FILES = {SELF, 'docs/RENAMING.md', 'pubspec.lock'}

# Directories that are never entered. supabase/ holds migrations whose file
# names and contents are history; assets/ holds fonts, images and word lists.
PRUNE_DIRS = {
    '.git', 'build', '.dart_tool', '.idea', '.gradle', '.pub-cache', '.pub',
    'Pods', 'node_modules', 'ephemeral', '.symlinks', '.vscode', '.fvm',
    'supabase', 'assets', 'coverage', '__pycache__',
}

TEXT_EXTS = {
    '.dart', '.kt', '.kts', '.java', '.swift', '.m', '.h', '.hpp', '.cc',
    '.cpp', '.rc', '.md', '.yml', '.yaml', '.xml', '.plist', '.arb', '.pro',
    '.py', '.sh', '.gradle', '.properties', '.storyboard', '.entitlements',
    '.pbxproj', '.xcscheme', '.cmake',
}
TEXT_NAMES = {'CMakeLists.txt'}

# Strings that contain the old slug but are part of a persisted or wire format.
# They are masked while renaming and reported as "kept on purpose" afterwards.
PRESERVED: List[Tuple[str, str]] = [
    ('vaultsnap/v', 'AEAD associated data "<slug>/v<N>/<context>" (every ciphertext and the iOS '
                    'autofill snapshot are bound to it)'),
    ('vaultsnap-export', 'export file "format" tag (old backups would stop importing)'),
    ('vaultsnap_bio_kek', 'secure-storage key of the biometric key wrap (renaming forces re-enrolment)'),
    ('20261005000000_vaultsnap', 'Supabase migration file name (migration history is keyed on it)'),
    ('vaultsnap_rls', 'throw-away database name of supabase/tests/run_rls_tests.sh'),
    ('@vaultsnap', 'arbitrary sample text in an OCR parser test'),
]
PRESERVED_RE = re.compile('|'.join(re.escape(p) for p, _ in PRESERVED))

DART_RESERVED = set(
    'abstract as assert async await break case catch class const continue covariant default '
    'deferred do dynamic else enum export extends extension external factory false final finally '
    'for function get hide if implements import in interface is late library mixin new null of on '
    'operator part required rethrow return set show static super switch sync this throw true try '
    'typedef var void while with yield'.split())
JAVA_RESERVED = set(
    'abstract assert boolean break byte case catch char class const continue default do double '
    'else enum extends final finally float for goto if implements import instanceof int interface '
    'long native new package private protected public return short static strictfp super switch '
    'synchronized this throw throws transient try void volatile while true false null'.split())
PACKAGE_RESERVED = {'flutter', 'flutter_test', 'flutter_localizations', 'dart', 'test', 'sky_engine',
                    'integration_test', 'flutter_driver', 'flutter_web_plugins'}

ARABIC_RE = re.compile('[؀-ۿݐ-ݿࢠ-ࣿﭐ-﷿ﹰ-﻿]')

BRAND_NAME_RE = re.compile(r"((?:const|final)\s+(?:String\s+)?appName\s*=\s*)(['\"])(.*?)\2")
BRAND_NAME_AR_RE = re.compile(r"((?:const|final)\s+(?:String\s+)?appNameAr\s*=\s*)(['\"])(.*?)\2")
ARB_TITLE_RE = re.compile(r'("appTitle"\s*:\s*")((?:[^"\\]|\\.)*)(")')
MANIFEST_LABEL_RE = re.compile(r'(<application\b[^>]*?\bandroid:label\s*=\s*")([^"]*)(")', re.S)
STRINGS_APP_NAME_RE = re.compile(r'(<string\s+name="app_name"[^>]*>)([^<]*)(</string>)')
CPP_TITLE_RE = re.compile(r'(\bCreate\(\s*L)"((?:[^"\\\n]|\\.)*)"')
CMAKE_PROJECT_RE = re.compile(r'(?m)^(project\()([A-Za-z0-9_]+)(\b)')
CMAKE_BINARY_RE = re.compile(r'(set\(BINARY_NAME\s+")([^"]*)(")')
GRADLE_NS_RE = re.compile(r'(\bnamespace\s*=\s*")([^"]*)(")')
GRADLE_ID_RE = re.compile(r'(\bapplicationId\s*=\s*")([^"]*)(")')
BACKUP_NAME_RE = re.compile(r"""(['"])[A-Za-z0-9_]+-backup\.vsnap\1""")
APP_CLASS_RE = re.compile(r'\bclass\s+([A-Z][A-Za-z0-9]*?)App\s+extends\b')
L10N_LOCALE_RE = re.compile(r'(?:^|/)app(?:_localizations)?_([a-z]{2,3})(?:_[A-Za-z0-9]+)?\.(?:arb|dart)$')


# --------------------------------------------------------------------------
# small helpers
# --------------------------------------------------------------------------

class Refused(Exception):
    """The run was refused (dirty tree, unknown state, conflicts)."""


def out(msg: str = '') -> None:
    print(msg, flush=True)


def warn(msg: str) -> None:
    print(f'warning: {msg}', file=sys.stderr, flush=True)


def is_word(ch: str) -> bool:
    return ch != '' and ch.isascii() and (ch.isalnum() or ch == '_')


def cpp_escape(s: str) -> str:
    """Wide-string-literal body that is independent of the source code page."""
    res = []
    for ch in s:
        cp = ord(ch)
        if cp < 0x80:
            res.append(ch)
        elif cp <= 0xFFFF:
            res.append('\\u%04x' % cp)
        else:
            res.append('\\U%08x' % cp)
    return ''.join(res)


def name_char_ok(ch: str) -> bool:
    return ch in ' -_.' or unicodedata.category(ch)[0] in 'LNM'


def validate_name(raw: str, what: str) -> str:
    name = unicodedata.normalize('NFC', raw)
    if not name or name != name.strip():
        raise ValueError(f'{what} must not be empty or start/end with a space')
    if len(name) > 30:
        raise ValueError(f'{what} is longer than 30 characters')
    if '  ' in name:
        raise ValueError(f'{what} must not contain two spaces in a row')
    bad = sorted({c for c in name if not name_char_ok(c)})
    if bad:
        raise ValueError(
            f'{what} contains characters that are not safe in every file type '
            f'(quotes, $, &, <, >, backslash, braces ...): {" ".join(bad)}. '
            'Allowed: letters (any script), digits, space, hyphen, underscore, dot.')
    if unicodedata.category(name[0])[0] not in 'LN':
        raise ValueError(f'{what} must start with a letter or digit')
    return name


def derive_slug(name: str) -> str:
    slug = re.sub(r'[^a-z0-9]+', '_', name.lower()).strip('_')
    return slug


def pascal_from_tokens(text: str) -> str:
    return ''.join(t[0].upper() + t[1:] for t in re.findall(r'[A-Za-z0-9]+', text))


def guarded_sub(text: str, old: str, new: str, left: str = r'(?<![A-Za-z0-9_])',
                right: str = r'(?![A-Za-z0-9_])') -> str:
    """Replace [old] by [new]; text that already says [new] is left alone, which
    keeps the replacement idempotent even when [new] contains [old]."""
    if not old or old == new:
        return text
    alts = sorted({old, new}, key=len, reverse=True)
    pat = re.compile(left + '(?:' + '|'.join(re.escape(a) for a in alts) + ')' + right)
    return pat.sub(lambda m: m.group(0) if m.group(0) == new else new, text)


def arabic_context(text: str, s: int, e: int) -> bool:
    """True if the nearest letter on either side (same line) is Arabic script."""
    i = s - 1
    while i >= 0 and text[i] not in '\r\n' and not text[i].isalnum():
        i -= 1
    if i >= 0 and ARABIC_RE.match(text[i]):
        return True
    j = e
    while j < len(text) and text[j] not in '\r\n' and not text[j].isalnum():
        j += 1
    return j < len(text) and bool(ARABIC_RE.match(text[j]))


def file_locale(rel: str) -> Optional[str]:
    m = L10N_LOCALE_RE.search(rel)
    return m.group(1) if m else None


# --------------------------------------------------------------------------
# target and current state
# --------------------------------------------------------------------------

@dataclass
class Target:
    name: str
    name_ar: str
    slug: str
    pascal: str
    app_id: str
    ids: bool
    channels: bool
    keep_data_dir: bool
    description: Optional[str]

    @property
    def org(self) -> str:
        return self.app_id.rsplit('.', 1)[0]

    @property
    def pkg_path(self) -> str:
        return self.app_id.replace('.', '/')

    @property
    def ascii_name(self) -> str:
        """Name for places that cannot carry non-ASCII text safely (Windows
        version-info strings, CI artifact names)."""
        return self.name if self.name.isascii() else self.slug

    @property
    def ci_prefix(self) -> str:
        return re.sub(r'[^A-Za-z0-9._-]+', '-', self.ascii_name).strip('-') or self.slug


@dataclass
class Current:
    # (where, value, is_arabic_locale) for every place the display name is stored
    sources: List[Tuple[str, str, bool]] = field(default_factory=list)
    slug: Optional[str] = None
    pascal: Optional[str] = None
    app_id: Optional[str] = None
    namespace: Optional[str] = None
    binary: Optional[str] = None
    brand_present: bool = False
    brand_parsed: bool = False
    problems: List[str] = field(default_factory=list)
    notes: List[str] = field(default_factory=list)

    @property
    def org(self) -> Optional[str]:
        return self.app_id.rsplit('.', 1)[0] if self.app_id else None

    @property
    def pkg_path(self) -> Optional[str]:
        return self.app_id.replace('.', '/') if self.app_id else None


def build_target(args: argparse.Namespace, root: Path) -> Target:
    name = validate_name(args.name, '--name')
    name_ar = validate_name(args.name_ar, '--name-ar') if args.name_ar else name

    if args.slug:
        slug = args.slug
    else:
        if not name.isascii():
            raise ValueError('--name is not ASCII, so --slug <ascii_id> is required (it is used for '
                             'file names, CI artifacts, the Dart package and the Windows binary)')
        slug = derive_slug(name)
    if not re.fullmatch(r'[a-z][a-z0-9_]{0,39}', slug or ''):
        raise ValueError(f'slug {slug!r} must match [a-z][a-z0-9_]* (max 40 chars, start with a letter); '
                         'pass --slug explicitly')
    if slug in DART_RESERVED or slug in PACKAGE_RESERVED:
        raise ValueError(f'slug {slug!r} is a reserved word / SDK package name; choose another --slug')
    pubspec = root / 'pubspec.yaml'
    if pubspec.exists():
        text = pubspec.read_text(encoding='utf-8')
        deps = set(re.findall(r'(?m)^\s{2}([a-z][a-z0-9_]*):', text))
        cur = re.search(r'(?m)^name:\s*(\S+)', text)
        if slug in deps and (not cur or cur.group(1) != slug):
            raise ValueError(f'slug {slug!r} is also the name of a dependency in pubspec.yaml')

    token_pascal = pascal_from_tokens(name) if name.isascii() else ''
    if token_pascal and token_pascal[0].isalpha() and token_pascal.lower() == slug.replace('_', ''):
        pascal = token_pascal
    else:
        pascal = pascal_from_tokens(slug.replace('_', ' ').replace('  ', ' '))
    if not re.fullmatch(r'[A-Z][A-Za-z0-9]*', pascal):
        raise ValueError(f'cannot derive a class-name prefix from slug {slug!r}')

    seg = slug.replace('_', '')      # iOS bundle ids may not contain underscores
    app_id = args.app_id or f'app.{seg}.{seg}'
    segs = app_id.split('.')
    if len(segs) < 2 or any(not re.fullmatch(r'[a-z][a-z0-9]*', s) for s in segs):
        raise ValueError(f'application id {app_id!r} must be dot-separated lowercase segments '
                         '([a-z][a-z0-9]*: no underscore, iOS rejects it), at least two')
    if any(s in JAVA_RESERVED for s in segs):
        raise ValueError(f'application id {app_id!r} contains a Java keyword as a segment')

    desc = args.description
    if desc is not None and ('\n' in desc or '\r' in desc):
        raise ValueError('--description must be a single line')
    return Target(name, name_ar, slug, pascal, app_id, bool(args.ids), bool(args.channels),
                  bool(args.keep_data_dir), desc)


def read_text(path: Path) -> Optional[str]:
    try:
        return path.read_bytes().decode('utf-8')
    except (OSError, UnicodeDecodeError):
        return None


def detect_current(root: Path, want_ids: bool) -> Current:
    cur = Current()

    # --- display name: lib/brand.dart and every arb appTitle -----------------
    brand = root / 'lib' / 'brand.dart'
    if brand.exists():
        cur.brand_present = True
        m = BRAND_NAME_RE.search(read_text(brand) or '')
        if m:
            cur.brand_parsed = True
            cur.sources.append(('lib/brand.dart', m.group(3), False))
        else:
            cur.notes.append("lib/brand.dart exists but has no `const String appName = '...';` - left alone")
    arb_dir = 'lib/l10n'
    l10n = read_text(root / 'l10n.yaml')
    if l10n:
        m = re.search(r'(?m)^arb-dir:\s*(\S+)', l10n)
        if m:
            arb_dir = m.group(1).strip('\'"')
    arbs = sorted((root / arb_dir).glob('*.arb')) if (root / arb_dir).is_dir() else []
    if not arbs:
        cur.problems.append(f'no .arb files in {arb_dir}/ - cannot tell what the app is called now')
    for f in arbs:
        rel = f.relative_to(root).as_posix()
        try:
            data = json.loads(f.read_text(encoding='utf-8'))
        except (OSError, ValueError) as e:
            cur.problems.append(f'{rel} is not valid JSON ({e})')
            continue
        title = data.get('appTitle')
        if not isinstance(title, str):
            cur.problems.append(f'{rel} has no "appTitle" string')
            continue
        loc = str(data.get('@@locale') or file_locale(rel) or '')
        cur.sources.append((rel, title, loc.split('_')[0] == 'ar'))

    if not want_ids:
        return cur

    # --- technical identifiers ---------------------------------------------
    pub = read_text(root / 'pubspec.yaml') or ''
    m = re.search(r'(?m)^name:\s*([A-Za-z0-9_]+)\s*(?:#.*)?$', pub)
    if m:
        cur.slug = m.group(1)
    else:
        cur.problems.append('pubspec.yaml has no `name:`')

    app = read_text(root / 'lib' / 'app.dart') or ''
    m = APP_CLASS_RE.search(app)
    if m:
        cur.pascal = m.group(1)
    else:
        cur.problems.append('lib/app.dart: no `class <Prefix>App extends ...` found (needed to rename '
                            'the <Prefix>... class names)')

    gradle = read_text(root / 'android' / 'app' / 'build.gradle.kts')
    if gradle is None:
        cur.problems.append('android/app/build.gradle.kts not found')
    else:
        ns, aid = GRADLE_NS_RE.search(gradle), GRADLE_ID_RE.search(gradle)
        if not aid:
            cur.problems.append('android/app/build.gradle.kts has no applicationId')
        else:
            cur.app_id = aid.group(2)
            cur.namespace = ns.group(2) if ns else None
            if ns and ns.group(2) != aid.group(2):
                cur.problems.append(f'namespace ({ns.group(2)}) and applicationId ({aid.group(2)}) differ')
            kdir = root / 'android/app/src/main/kotlin' / cur.pkg_path
            if not kdir.is_dir():
                cur.problems.append(f'Kotlin sources are not in android/app/src/main/kotlin/{cur.pkg_path}/')
            pbx = read_text(root / 'ios/Runner.xcodeproj/project.pbxproj')
            if pbx is not None and cur.app_id not in pbx:
                cur.notes.append(f'ios project.pbxproj does not use the Android application id {cur.app_id}; '
                                 'only the ids that are present are renamed')

    cmake = read_text(root / 'windows' / 'CMakeLists.txt')
    if cmake is not None:
        m = CMAKE_BINARY_RE.search(cmake)
        if m:
            cur.binary = m.group(2)
    return cur


# --------------------------------------------------------------------------
# the rename engine
# --------------------------------------------------------------------------

@dataclass
class Change:
    src: str
    dst: str
    old: bytes
    new: bytes

    @property
    def moved(self) -> bool:
        return self.src != self.dst

    @property
    def edited(self) -> bool:
        return self.old != self.new


class Renamer:
    def __init__(self, root: Path, cur: Current, tgt: Target):
        self.root, self.cur, self.t = root, cur, tgt
        self.final_texts: Dict[str, str] = {}
        self.skipped_binary: List[str] = []
        self.messages: List[str] = []
        self.targets = {tgt.name, tgt.name_ar} | ({tgt.pascal} if tgt.ids else set())
        old = {v for _, v, _ in cur.sources if v and v not in (tgt.name, tgt.name_ar)}
        # a source that already carries one of the targets is finished
        self.old_names: Set[str] = old
        names = set(old)
        if tgt.ids and cur.pascal and cur.pascal != tgt.pascal:
            names.add(cur.pascal)
        alts = sorted(names | self.targets, key=len, reverse=True) if names else []
        self.name_re = re.compile('|'.join(re.escape(a) for a in alts)) if names else None

    # ---- file walk -------------------------------------------------------
    def walk(self):
        for dirpath, dirnames, filenames in os.walk(self.root):
            dirnames[:] = sorted(d for d in dirnames if d not in PRUNE_DIRS)
            for fn in sorted(filenames):
                p = Path(dirpath) / fn
                if p.is_symlink():
                    continue
                yield p.relative_to(self.root).as_posix(), p

    @staticmethod
    def is_text(rel: str) -> bool:
        base = rel.rsplit('/', 1)[-1]
        return base in TEXT_NAMES or Path(base).suffix in TEXT_EXTS

    # ---- paths -----------------------------------------------------------
    def new_path(self, rel: str) -> str:
        t, c = self.t, self.cur
        if not t.ids:
            return rel
        if c.app_id and c.app_id != t.app_id:
            m = re.match(r'(android/app/src/[^/]+/(?:kotlin|java)/)(.*)', rel)
            if m and m.group(2).startswith(c.pkg_path + '/'):
                rel = m.group(1) + t.pkg_path + m.group(2)[len(c.pkg_path):]
        if c.pascal and c.pascal != t.pascal and rel.split('/')[0] in {'android', 'ios', 'windows', 'lib', 'test'}:
            d, _, base = rel.rpartition('/')
            if c.pascal in base:
                rel = (d + '/' if d else '') + base.replace(c.pascal, t.pascal)
        return rel

    # ---- per-file handlers (key based, therefore idempotent) --------------
    @staticmethod
    def _set(rx: re.Pattern, text: str, value: str, skip_if: Optional[Callable[[str], bool]] = None) -> str:
        def repl(m: re.Match) -> str:
            if skip_if and skip_if(m.group(2)):
                return m.group(0)
            return m.group(1) + value + m.group(3)
        return rx.sub(repl, text)

    def h_brand(self, text: str) -> str:
        text = BRAND_NAME_RE.sub(lambda m: m.group(1) + m.group(2) + self.t.name + m.group(2), text)
        return BRAND_NAME_AR_RE.sub(lambda m: m.group(1) + m.group(2) + self.t.name_ar + m.group(2), text)

    def h_arb(self, rel: str, text: str) -> str:
        loc = file_locale(rel)
        return self._set(ARB_TITLE_RE, text, self.t.name_ar if loc == 'ar' else self.t.name)

    def h_pubspec(self, text: str) -> str:
        if self.t.ids:
            text = re.sub(r'(?m)^(name:\s*)[A-Za-z0-9_]+(\s*(?:#.*)?)$',
                          lambda m: m.group(1) + self.t.slug + m.group(2), text, count=1)
        if self.t.description is not None:
            desc = json.dumps(self.t.description, ensure_ascii=False)
            text = re.sub(r'(?m)^description:.*$', lambda m: 'description: ' + desc, text, count=1)
        return text

    def h_manifest(self, text: str) -> str:
        return self._set(MANIFEST_LABEL_RE, text, self.t.name, skip_if=lambda v: v.startswith('@'))

    def h_strings_xml(self, rel: str, text: str) -> str:
        m = re.match(r'android/app/src/main/res/values(?:-([a-z]{2,3}))?(?:-[^/]*)?/strings\.xml$', rel)
        ar = bool(m and m.group(1) == 'ar')
        return self._set(STRINGS_APP_NAME_RE, text, self.t.name_ar if ar else self.t.name)

    def h_plist(self, text: str) -> str:
        for key in ('CFBundleDisplayName', 'CFBundleName'):
            rx = re.compile(r'(<key>%s</key>\s*<string>)([^<]*)(</string>)' % key)
            text = self._set(rx, text, self.t.name, skip_if=lambda v: v.startswith('$('))
        return text

    def h_main_cpp(self, text: str) -> str:
        return CPP_TITLE_RE.sub(lambda m: m.group(1) + '"' + cpp_escape(self.t.name) + '"', text)

    def h_rc(self, text: str) -> str:
        t = self.t

        def put(txt: str, key: str, value: str) -> str:
            rx = re.compile(r'(VALUE\s+"%s"\s*,\s*)"[^"\r\n]*"' % key)
            return rx.sub(lambda m: m.group(1) + '"' + value + '"', txt)

        if not t.keep_data_dir:
            text = put(text, 'ProductName', t.ascii_name)
        text = put(text, 'FileDescription', t.ascii_name)
        text = put(text, 'InternalName', t.slug)
        if t.ids:
            text = put(text, 'OriginalFilename', t.slug + '.exe')
            if not t.keep_data_dir:
                text = put(text, 'CompanyName', t.org)
            text = re.sub(r'(VALUE\s+"LegalCopyright"\s*,\s*"Copyright \(C\) \d{4} )(.*?)(\. All rights reserved\.")',
                          lambda m: m.group(1) + t.org + m.group(3), text)
        return text

    def h_cmake(self, text: str) -> str:
        text = CMAKE_PROJECT_RE.sub(lambda m: m.group(1) + self.t.slug + m.group(3), text, count=1)
        return self._set(CMAKE_BINARY_RE, text, self.t.slug)

    def h_gradle(self, text: str) -> str:
        text = self._set(GRADLE_NS_RE, text, self.t.app_id)
        return self._set(GRADLE_ID_RE, text, self.t.app_id)

    def h_backup_name(self, text: str) -> str:
        return BACKUP_NAME_RE.sub(lambda m: m.group(1) + self.t.slug + '-backup.vsnap' + m.group(1), text)

    def handlers(self, rel: str) -> List[Callable[[str], str]]:
        t = self.t
        hs: List[Callable[[str], str]] = []
        if rel == 'lib/brand.dart':
            hs.append(self.h_brand)
        if rel.endswith('.arb'):
            hs.append(lambda s, r=rel: self.h_arb(r, s))
        if rel == 'pubspec.yaml':
            hs.append(self.h_pubspec)
        if rel == 'android/app/src/main/AndroidManifest.xml':
            hs.append(self.h_manifest)
        if re.fullmatch(r'android/app/src/main/res/values[^/]*/strings\.xml', rel):
            hs.append(lambda s, r=rel: self.h_strings_xml(r, s))
        if rel == 'ios/Runner/Info.plist':
            hs.append(self.h_plist)
        if rel == 'windows/runner/main.cpp':
            hs.append(self.h_main_cpp)
        if rel == 'windows/runner/Runner.rc':
            hs.append(self.h_rc)
        if rel.startswith('lib/') and rel.endswith('.dart'):
            hs.append(self.h_backup_name)
        if t.ids:
            if rel == 'windows/CMakeLists.txt':
                hs.append(self.h_cmake)
            if rel == 'android/app/build.gradle.kts':
                hs.append(self.h_gradle)
        return hs

    # ---- display-name sweep ------------------------------------------------
    def display_for(self, rel: str, text: str, s: int, e: int, tok: str) -> str:
        t = self.t
        if rel.startswith('.github/workflows/'):
            return t.ci_prefix
        line = text[text.rfind('\n', 0, s) + 1:(text.find('\n', e) if text.find('\n', e) >= 0 else len(text))]
        if 'user-agent' in line.lower():
            return t.ascii_name          # HTTP header values must stay Latin-1
        ar = bool(ARABIC_RE.search(tok)) or file_locale(rel) == 'ar' or arabic_context(text, s, e)
        name = t.name_ar if ar else t.name
        if rel.endswith(('.cpp', '.cc', '.h', '.hpp')):
            return cpp_escape(name)
        if rel.endswith('.rc'):
            return name if name.isascii() else t.slug
        return name

    def sweep(self, rel: str, text: str) -> str:
        if self.name_re is None:
            return text
        masks = [m.span() for m in PRESERVED_RE.finditer(text)]
        if self.t.keep_data_dir and rel == 'windows/runner/Runner.rc':
            masks += [m.span() for m in re.finditer(r'(?m)^.*VALUE\s+"(?:ProductName|CompanyName)".*$', text)]
        parts: List[str] = []
        last = 0
        for m in self.name_re.finditer(text):
            s, e = m.span()
            tok = m.group(0)
            if tok in self.targets or any(a < e and s < b for a, b in masks):
                continue
            before = text[s - 1] if s > 0 else ''
            after = text[e] if e < len(text) else ''
            if not (is_word(before) or is_word(after)):
                new = self.display_for(rel, text, s, e, tok)
            elif self.t.ids and tok == self.cur.pascal:
                new = self.t.pascal          # part of an identifier: HisnApp, kHisnRun...
            else:
                continue
            parts.append(text[last:s])
            parts.append(new)
            last = e
        parts.append(text[last:])
        return ''.join(parts)

    # ---- id rules ----------------------------------------------------------
    def ids_rules(self, rel: str, text: str) -> str:
        t, c = self.t, self.cur
        if c.slug and c.slug != t.slug and rel.endswith('.dart'):
            text = guarded_sub(text, f'package:{c.slug}/', f'package:{t.slug}/', left='', right='')
        if rel != 'windows/runner/Runner.rc':   # handled key by key (--keep-data-dir)
            if c.app_id and c.app_id != t.app_id:
                text = guarded_sub(text, c.app_id, t.app_id)
            if c.org and c.org != t.org and len(c.org) >= 4:
                text = guarded_sub(text, c.org, t.org, right=r'(?![A-Za-z0-9_/])')
        if c.slug and c.slug != t.slug:
            text = guarded_sub(text, f'{c.slug}-clip-', f'{t.slug}-clip-', right='')
            if rel.endswith('.kt'):
                text = re.sub(r'"%s\.(\w+)"' % re.escape(c.slug), lambda m: f'"{t.slug}.{m.group(1)}"', text)
        if t.channels and c.org and c.org != t.org:
            text = guarded_sub(text, c.org + '/', t.org + '/', right=r'(?=[A-Za-z])')
        return text

    # ---- one file ----------------------------------------------------------
    def transform(self, rel: str, text: str) -> str:
        for h in self.handlers(rel):
            text = h(text)
        text = self.sweep(rel, text)
        if self.t.ids:
            text = self.ids_rules(rel, text)
        return text

    # ---- whole plan --------------------------------------------------------
    def plan(self) -> List[Change]:
        changes: List[Change] = []
        for rel, path in self.walk():
            new_rel = self.new_path(rel)
            text_file = self.is_text(rel) and rel not in SKIP_FILES
            if not text_file and new_rel == rel:
                continue
            data = path.read_bytes()
            new_data = data
            if text_file:
                try:
                    text = data.decode('utf-8')
                except UnicodeDecodeError:
                    self.skipped_binary.append(rel)
                    text = None
                if text is not None:
                    new_text = self.transform(rel, text)
                    new_data = new_text.encode('utf-8')
                    self.final_texts[new_rel] = new_text
            if new_data != data or new_rel != rel:
                changes.append(Change(rel, new_rel, data, new_data))
        # conflicts: two files landing on one path, or onto a file that stays
        seen: Dict[str, str] = {}
        moving_away = {c.src for c in changes if c.moved}
        for c in changes:
            if c.dst in seen and seen[c.dst] != c.src:
                raise Refused(f'{seen[c.dst]} and {c.src} would both become {c.dst}')
            seen[c.dst] = c.src
            if c.moved and (self.root / c.dst).exists() and c.dst not in moving_away:
                raise Refused(f'{c.src} would be moved to {c.dst}, which already exists')
        return changes

    # ---- leftover report ---------------------------------------------------
    def leftovers(self) -> Tuple[Dict[str, List[str]], List[str]]:
        """(kept on purpose: reason -> [file:line], unexpected: [file:line text])."""
        t, c = self.t, self.cur
        pats: List[str] = [re.escape(n) for n in sorted(self.old_names, key=len, reverse=True)]
        if t.ids:
            for tok in (c.slug, c.pascal):
                if tok and tok not in (t.slug, t.pascal):
                    pats.append(re.escape(tok))
            if c.app_id and c.app_id != t.app_id:
                pats.append(re.escape(c.app_id))
        if not pats:
            return {}, []
        rx = re.compile('|'.join(pats), re.I if t.ids else 0)
        kept: Dict[str, List[str]] = {}
        unexpected: List[str] = []
        preserved = [(re.compile(re.escape(p)), why) for p, why in PRESERVED]
        if t.ids and c.org and c.org != t.org and not t.channels:
            preserved.append((re.compile(re.escape(c.org + '/')),
                              f'MethodChannel name "{c.org}/..." (internal wire name; --channels renames it)'))
        for rel in sorted(self.final_texts):
            text = self.final_texts[rel]
            if rel in SKIP_FILES:
                continue
            for lineno, line in enumerate(text.splitlines(), 1):
                for m in rx.finditer(line):
                    s, e = m.span()
                    loc = f'{rel}:{lineno}'
                    reason = None
                    for prx, why in preserved:
                        if any(p.start() < e and s < p.end() for p in prx.finditer(line)):
                            reason = why
                            break
                    if reason is None and not t.ids:
                        before = line[s - 1] if s else ''
                        after = line[e] if e < len(line) else ''
                        if is_word(before) or is_word(after):
                            reason = 'code identifier that embeds the old name (renamed by --ids)'
                    if reason is None:
                        unexpected.append(f'{loc}: {line.strip()[:110]}')
                    else:
                        kept.setdefault(reason, []).append(loc)
        return kept, unexpected


# --------------------------------------------------------------------------
# apply
# --------------------------------------------------------------------------

def prune_empty_dirs(root: Path, d: Path) -> None:
    while d != root and d.is_dir() and not any(d.iterdir()):
        d.rmdir()
        d = d.parent


def apply_changes(root: Path, changes: List[Change]) -> None:
    done: List[Change] = []
    try:
        for ch in changes:
            src, dst = root / ch.src, root / ch.dst
            dst.parent.mkdir(parents=True, exist_ok=True)
            if ch.moved:
                dst.write_bytes(ch.new)
                shutil.copymode(src, dst)
                src.unlink()
            else:
                with open(dst, 'wb') as fh:      # keeps the file mode
                    fh.write(ch.new)
            done.append(ch)
    except BaseException:
        for ch in reversed(done):
            src, dst = root / ch.src, root / ch.dst
            try:
                if ch.moved:
                    src.parent.mkdir(parents=True, exist_ok=True)
                    src.write_bytes(ch.old)
                    shutil.copymode(dst, src)
                    dst.unlink()
                else:
                    dst.write_bytes(ch.old)
            except OSError as e:     # pragma: no cover - best effort
                warn(f'rollback of {ch.src} failed: {e}')
        for ch in done:              # directories created for moved files
            if ch.moved:
                prune_empty_dirs(root, (root / ch.dst).parent)
        raise
    for ch in changes:               # empty directories left behind by moves
        if ch.moved:
            prune_empty_dirs(root, (root / ch.src).parent)


def git_dirty(root: Path) -> Optional[List[str]]:
    """Porcelain lines of uncommitted work, [] if clean, None if not a git root."""
    if not (root / '.git').exists():
        return None
    try:
        res = subprocess.run(['git', '-C', str(root), 'status', '--porcelain'], capture_output=True,
                             text=True, check=True)
    except (OSError, subprocess.CalledProcessError):
        return None
    return [ln for ln in res.stdout.splitlines() if ln.strip()]


def find_flutter(explicit: Optional[str]) -> Optional[str]:
    if explicit:
        return explicit
    found = shutil.which('flutter')
    if found:
        return found
    fr = os.environ.get('FLUTTER_ROOT')
    if fr and (Path(fr) / 'bin' / 'flutter').exists():
        return str(Path(fr) / 'bin' / 'flutter')
    return None


def run_quiet(cmd: List[str], cwd: Path) -> Tuple[bool, str]:
    try:
        res = subprocess.run(cmd, cwd=str(cwd), capture_output=True, text=True, timeout=900)
    except (OSError, subprocess.TimeoutExpired) as e:
        return False, str(e)
    return res.returncode == 0, (res.stdout + res.stderr).strip()


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------

def parse_args(argv: Optional[List[str]] = None) -> argparse.Namespace:
    ap = argparse.ArgumentParser(
        description='Rename the app (user-visible name, optionally the technical ids). '
                    'See docs/RENAMING.md.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='examples:\n'
               '  tool/rename_app.py --name Hisn --dry-run\n'
               '  tool/rename_app.py --name Hisn --ids\n'
               '  tool/rename_app.py --name Hisn --name-ar "حصن" --slug hisn --ids --app-id com.example.hisn')
    ap.add_argument('--name', required=True, help='new display name, e.g. "Hisn" (letters/digits/space/-/_/. only)')
    ap.add_argument('--name-ar', help='Arabic display name for app_ar.arb (default: same as --name)')
    ap.add_argument('--slug', help='ASCII id, [a-z][a-z0-9_]* (default: derived from --name; required for '
                                   'non-ASCII names). Dart package, Windows binary, file names, CI artifacts')
    ap.add_argument('--app-id', help='application id / bundle id (default app.<slug>.<slug> without underscores); only with --ids')
    ap.add_argument('--ids', action='store_true', help='also rename the technical identifiers (see docs)')
    ap.add_argument('--channels', action='store_true', help='with --ids: also rename the MethodChannel names')
    ap.add_argument('--keep-data-dir', action='store_true',
                    help='leave Windows CompanyName/ProductName alone: path_provider derives the vault folder '
                         '%%APPDATA%%\\<CompanyName>\\<ProductName> from them')
    ap.add_argument('--description', help='also set the pubspec.yaml description')
    ap.add_argument('--dry-run', action='store_true', help='show what would change, write nothing')
    ap.add_argument('--diff', action='store_true', help='print a unified diff of every edited file')
    ap.add_argument('--force', action='store_true',
                    help='run on a dirty git tree / with an ambiguous current name')
    ap.add_argument('--strict', action='store_true', help='exit 3 if unexpected leftovers of the old name remain')
    ap.add_argument('--root', help='repository root (default: parent of this tool/ directory)')
    ap.add_argument('--flutter', help='path of the flutter executable (default: PATH / FLUTTER_ROOT)')
    ap.add_argument('--skip-gen-l10n', action='store_true', help='do not run `flutter gen-l10n`')
    ap.add_argument('--no-format', action='store_true', help='do not run `dart format` on edited Dart files')
    args = ap.parse_args(argv)
    if args.app_id and not args.ids:
        ap.error('--app-id only makes sense together with --ids')
    if args.channels and not args.ids:
        ap.error('--channels only makes sense together with --ids')
    return args


def main(argv: Optional[List[str]] = None) -> int:
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(errors='backslashreplace')
        except (AttributeError, ValueError):
            pass
    args = parse_args(argv)
    root = Path(args.root).resolve() if args.root else Path(__file__).resolve().parent.parent
    if not (root / 'pubspec.yaml').exists():
        out(f'error: {root} does not look like the app repository (no pubspec.yaml)')
        return 1

    try:
        tgt = build_target(args, root)
    except ValueError as e:
        out(f'error: {e}')
        return 1

    cur = detect_current(root, tgt.ids)
    if len({v for _, v, ar in cur.sources if not ar and v != tgt.name}) > 1:
        cur.problems.append('the Latin display name is not the same everywhere: ' +
                            ', '.join(f'{w}={v!r}' for w, v, ar in cur.sources if not ar))

    out(f'Root:     {root}')
    out(f'Current:  ' + (', '.join(f'{w}={v!r}' for w, v, _ in cur.sources) or '(unknown)'))
    if tgt.ids:
        out(f'          package={cur.slug!r} class prefix={cur.pascal!r} application id={cur.app_id!r} '
            f'windows binary={cur.binary!r}')
    out(f'New:      name={tgt.name!r}' + (f' name-ar={tgt.name_ar!r}' if tgt.name_ar != tgt.name else '') +
        f' slug={tgt.slug!r}' +
        (f' class prefix={tgt.pascal!r} application id={tgt.app_id!r}' if tgt.ids else ''))
    for n in cur.notes:
        out(f'note: {n}')
    if not cur.brand_present:
        out('note: lib/brand.dart does not exist yet (the theme work creates it with '
            "`const String appName = '...';`). Skipped. Run this tool again with the same arguments "
            'once it exists; everything else is idempotent.')

    renamer = Renamer(root, cur, tgt)
    try:
        changes = renamer.plan()
    except Refused as e:
        out(f'error: {e}')
        return 2

    if not changes:
        if cur.problems and not args.force:
            out('error: refusing to continue, the current state is unknown/inconsistent:')
            for p in cur.problems:
                out(f'  - {p}')
            out('Fix it by hand or re-run with --force.')
            return 2
        out('Nothing to do: the tree already uses this name.')
        return 0

    # -- refusals ------------------------------------------------------------
    refusals: List[str] = []
    if cur.problems:
        refusals.append('the current state is unknown/inconsistent:\n' + '\n'.join(f'  - {p}' for p in cur.problems))
    dirty = git_dirty(root)
    if dirty:
        shown = '\n'.join('    ' + ln for ln in dirty[:12])
        more = f'\n    ... and {len(dirty) - 12} more' if len(dirty) > 12 else ''
        refusals.append(f'the git working tree has {len(dirty)} uncommitted change(s) '
                        f'(commit or stash them first, so the rename is one reviewable diff):\n{shown}{more}')
    if dirty is None:
        warn('not a git checkout: cannot check for uncommitted work and there is no way to undo this '
             'rename. Use a copy or a clean checkout.')
    if refusals:
        if args.dry_run:
            for r in refusals:
                warn('a real run would be refused: ' + r)
        elif not args.force:
            out('error: refusing to continue:')
            for r in refusals:
                out(' * ' + r)
            out('Re-run with --force to override (or with --dry-run to just look).')
            return 2
        else:
            for r in refusals:
                warn('--force given, ignoring: ' + r.splitlines()[0])

    # -- show ----------------------------------------------------------------
    edited = [c for c in changes if c.edited or c.moved]
    out('')
    out(('Would change' if args.dry_run else 'Changing') + f' {len(edited)} file(s):')
    for c in edited:
        mark = 'R' if c.moved else 'M'
        out(f'  {mark} {c.src}' + (f'  ->  {c.dst}' if c.moved else '') +
            ('' if c.edited else '   (moved, content unchanged)'))
    if renamer.skipped_binary:
        warn('not valid UTF-8, left alone: ' + ', '.join(renamer.skipped_binary))
    if args.diff:
        for c in edited:
            if not c.edited:
                continue
            diff = difflib.unified_diff(
                c.old.decode('utf-8').splitlines(keepends=True), c.new.decode('utf-8').splitlines(keepends=True),
                fromfile='a/' + c.src, tofile='b/' + c.dst)
            sys.stdout.write(''.join(diff))

    kept, unexpected = renamer.leftovers()
    out('')
    if kept:
        out('Old name still present, kept on purpose:')
        for why, locs in sorted(kept.items()):
            files = sorted({loc.rsplit(':', 1)[0] for loc in locs})
            out(f'  {len(locs):3d} x {why}')
            out(f'        in {", ".join(files[:4])}' + (f' (+{len(files) - 4} more files)' if len(files) > 4 else ''))
    if unexpected:
        out('UNEXPECTED leftovers of the old name (review by hand):')
        for u in unexpected[:60]:
            out('  ' + u)
        if len(unexpected) > 60:
            out(f'  ... and {len(unexpected) - 60} more')
    if not unexpected:
        out('Leftover check: nothing unexpected left of the old name.')

    if args.dry_run:
        out('')
        out('Dry run: nothing was written.')
        return 3 if (args.strict and unexpected) else 0

    # -- write ---------------------------------------------------------------
    apply_changes(root, changes)
    out('')
    out(f'Wrote {len(edited)} file(s).')

    status = 0
    dart_files = [c.dst for c in edited if c.dst.endswith('.dart') and c.edited and
                  not re.search(r'lib/l10n/app_localizations.*\.dart$', c.dst)]
    flutter = find_flutter(args.flutter)
    if dart_files and not args.no_format:
        dart = None
        if flutter and (Path(flutter).parent / 'dart').exists():
            dart = str(Path(flutter).parent / 'dart')
        dart = dart or shutil.which('dart')
        if dart:
            ok, log = run_quiet([dart, 'format'] + dart_files, root)
            out('dart format: ' + ('ok' if ok else 'FAILED (the rename itself is complete)'))
            if not ok:
                out(log[-600:])
        else:
            out('dart format: skipped (no dart executable found; run `dart format lib test`)')
    if not args.skip_gen_l10n:
        if flutter:
            ok, log = run_quiet([flutter, 'gen-l10n'], root)
            out('flutter gen-l10n: ' + ('ok' if ok else 'FAILED'))
            if not ok:
                out(log[-1200:])
                out('The generated lib/l10n/*.dart were updated textually instead; run `flutter gen-l10n` '
                    'yourself to confirm.')
                status = 4
        else:
            out('flutter gen-l10n: skipped (flutter not found; pass --flutter or put it on PATH). '
                'The generated lib/l10n/*.dart were updated textually.')

    out('')
    out('Next: flutter pub get && flutter analyze && flutter test --exclude-tags finding')
    if tgt.ids:
        out('')
        out('Identifiers changed. Read docs/RENAMING.md before shipping: Android sees a different app '
            '(fresh install, old data stays in the old app), iOS needs new App IDs / App Group / '
            'Keychain group / provisioning, and the Windows vault folder moves.')
    elif not tgt.keep_data_dir:
        out('')
        out('Note: on Windows the vault folder is %APPDATA%\\<CompanyName>\\<ProductName> and ProductName '
            'just changed. A vault created by an earlier build will not be found until you move that folder '
            '(or re-run with --keep-data-dir). See docs/RENAMING.md.')
    return 3 if (args.strict and unexpected) else status


if __name__ == '__main__':
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
