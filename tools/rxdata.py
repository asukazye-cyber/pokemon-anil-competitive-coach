#!/usr/bin/env python3
"""Minimal Ruby Marshal 4.8 reader/writer for Pokémon Essentials Scripts.rxdata.

Format (Essentials v20+):
    Marshal 4.8 stream of an Array of [Integer id, String name, String code]
    where name is an IVAR-string tagged UTF-8 and code is Zlib-deflated text.

Encoding notes (verified empirically against baseline/Scripts.rxdata):
    - fixnum in w_long position (lengths, small values):
        0x00 -> 0; 0x05..0x7f -> value-5 (small positives 1..122);
        0x01..0x04 -> n bytes LE follow (big positive); 0xfc..0xff negative.
      'i' typed fixnums use the same payload encoding after the 'i' byte.
    - strings: '"' + w_long(len) + bytes
    - IVAR: 'I' <object> + count + (symbol, value)*
    - symbols: ':' + w_long(len) + bytes (no NUL)
    - arrays: '[' + w_long(len) + elements
    - links: '@' + w_long(index); symlinks: ';'
"""
import io
import zlib


class MarshalParseError(Exception):
    pass


class Reader:
    def __init__(self, data: bytes):
        self.d = data
        self.i = 0
        self.symbols = []      # object table index 0 is symbols? No: links table
        self.objects = []      # all previously dumped objects, for '@' links
        # NOTE: Ruby's link table includes every object with an identity that
        # was emitted, including arrays/strings/ivars, but NOT fixnums/symbols.
        # Symbols get their own ':'-emission + ';' symlinks.

    def byte(self):
        if self.i >= len(self.d):
            raise MarshalParseError("EOF")
        b = self.d[self.i]
        self.i += 1
        return b

    def peek(self):
        return self.d[self.i] if self.i < len(self.d) else None

    def read(self, n):
        if self.i + n > len(self.d):
            raise MarshalParseError("EOF")
        r = self.d[self.i:self.i + n]
        self.i += n
        return r

    def long(self):
        b = self.byte()
        if b == 0:
            return 0
        if 0x01 <= b <= 0x04:
            # Payload is an unsigned little-endian magnitude; sign is carried
            # by the size byte only (0x01..0x04 positive, 0xFC..0xFF negative).
            v = int.from_bytes(self.read(b), "little", signed=False)
            return v
        if 0xfc <= b <= 0xff:
            n = 0x100 - b
            v = int.from_bytes(self.read(n), "little", signed=False)
            return -v
        if b >= 0x05:
            return b - 5
        raise MarshalParseError(f"bad fixnum byte 0x{b:02x} @ {self.i-1}")

    def parse(self):
        ver = self.read(2)
        if ver != b"\x04\x08":
            raise MarshalParseError(f"not marshal 4.8: {ver.hex()}")
        return self.value()

    def value(self):
        t = self.byte()
        tc = chr(t)
        if tc == "0":
            return None
        if tc == "T":
            return True
        if tc == "F":
            return False
        if tc == "i":
            v = self.long()
            return v
        if tc == '"':
            s = self.bytestring()
            self.objects.append(s)
            return s
        if tc == ":":
            s = self.bytestring()
            self.symbols.append(s)
            return ("sym", s)
        if tc == ";":
            n = self.long()
            return ("sym", self.symbols[n])
        if tc == "[":
            n = self.long()
            arr = []
            self.objects.append(arr)
            for _ in range(n):
                arr.append(self.value())
            return arr
        if tc == "{":
            n = self.long()
            h = {}
            self.objects.append(h)
            for _ in range(n):
                k = self.value()
                v = self.value()
                h[k] = v
            return h
        if tc == "I":
            obj = self.value()
            n = self.long()
            for _ in range(n):
                self.value()  # symbol name
                self.value()  # value (e.g. :E => true)
            return obj
        if tc == "@":
            n = self.long()
            return self.objects[n]
        raise MarshalParseError(
            f"unsupported marshal type 0x{t:02x} '{tc}' at {self.i-1}")

    def bytestring(self):
        n = self.long()
        return self.read(n)


# ---------------------------------------------------------------------------
# Writer: byte-exact for the subset we need (arrays, ivar strings, symbols,
# fixnums). Round-trip is verified against the baseline by tools/rxpack.py.
# ---------------------------------------------------------------------------

def w_long(v: int) -> bytes:
    if v == 0:
        return b"\x00"
    if 0 < v and v <= 122:
        return bytes([v + 5])
    neg = v < 0
    av = abs(v)
    n = (av.bit_length() + 7) // 8
    if neg:
        return bytes([0x100 - n]) + av.to_bytes(n, "little")
    return bytes([n]) + v.to_bytes(n, "little")


def w_fixnum(v: int) -> bytes:
    return b"i" + w_long(v)


def w_string(s: bytes, utf8_ivar: bool = True) -> bytes:
    out = b'"' + w_long(len(s)) + s
    if utf8_ivar:
        # I " str " 6 3a 06 45 54    (":E" symbol, length 1 -> 0x06, then 'T')
        out = b"I" + out + b"\x06\x3a\x06ET"
    return out


def w_symbol(s: bytes) -> bytes:
    return b":" + w_long(len(s)) + s


class Writer:
    def __init__(self):
        self.buf = bytearray()
        self.symbols = []  # bytes -> already emitted?

    def write_string(self, s: bytes, utf8=True):
        self.buf += w_string(s, utf8)

    def write_fixnum(self, v):
        self.buf += w_fixnum(v)

    def top_array(self, items):
        """items: list of (id:int, name:bytes, code:bytes-deflated).

        NOTE: Ruby Marshal arrays have NO terminator byte; each entry is
        '[', w_long(3), fixnum, ivar-string, string, with nothing after.
        The name's :E ivar symbol is emitted once as ':' and then as ';'
        symlinks, exactly like Ruby's dumper, so output is byte-stable.
        """
        self.buf += b"\x04\x08"
        self.buf += b"[" + w_long(len(items))
        symbol_emitted = False
        for (sid, name, code) in items:
            self.buf += b"[" + w_long(3)
            self.buf += w_fixnum(sid)
            # IVAR string name with :E => true (UTF-8)
            body = b'"' + w_long(len(name)) + name
            ivar_val = (b"\x3a\x06E" if not symbol_emitted else b"\x3b\x00")
            symbol_emitted = True
            self.buf += b"I" + body + b"\x06" + ivar_val + b"T"
            # plain (non-IVAR) deflated code string
            self.buf += b'"' + w_long(len(code)) + code
        return bytes(self.buf)


def read_scripts(path: str):
    """Returns list of (index, id, name:str, code:str, raw_code:bytes)."""
    data = open(path, "rb").read()
    r = Reader(data)
    arr = r.parse()
    out = []
    for i, entry in enumerate(arr):
        assert isinstance(entry, list) and len(entry) == 3, f"entry {i} malformed"
        sid, name, code = entry
        assert isinstance(sid, int)
        assert isinstance(name, bytes)
        assert isinstance(code, bytes)
        text = zlib.decompress(code)
        out.append((i, sid, name.decode("utf-8"), text.decode("utf-8"), code))
    if r.i != len(data):
        raise MarshalParseError(f"trailing bytes: {len(data) - r.i}")
    return out


def write_scripts(path: str, entries):
    """entries: list of (id:int, name:bytes, code:str_or_bytes, raw:bytes|None).

    If raw (a pre-deflated blob from a previous read) is given, it is emitted
    verbatim so unchanged entries stay byte-identical to the source file.
    """
    w = Writer()
    items = []
    for entry in entries:
        sid, name, code = entry[0], entry[1], entry[2]
        raw = entry[3] if len(entry) > 3 else None
        if raw is None:
            src = code.encode("utf-8") if isinstance(code, str) else code
            raw = zlib.compress(src, 9)
        items.append((sid, name, raw))
    blob = w.top_array(items)
    open(path, "wb").write(blob)
    return blob
