# -*- coding: utf-8 -*-
"""Nintendo DS BIOS decompression: LZ10, LZ11, RLE and the difference filter.

Every BIOS-compressed blob starts with a 4-byte header::

    byte 0   : type   (high nibble = algorithm, low nibble = variant)
    byte 1-3 : uncompressed size, 24-bit little-endian

A 24-bit size of 0 means an extended 32-bit size follows at bytes 4..7 and the
payload starts at byte 8.

    0x10        LZ77 / LZ10
    0x11        LZ77 / LZ11 (extended lengths)
    0x20/24/28  Huffman (NOT implemented - no asset in these ROMs needs it)
    0x30        run-length
    0x80/0x81   difference filter (8-bit / 16-bit)

See docs/research/nds-formats.md section 3.

Two traps this module exists to avoid:

* LZ back-references deliberately overlap the output written so far, so the copy
  MUST be byte-at-a-time. A slice copy silently corrupts runs.
* Sniffing compression on the first byte alone has a ~5% false-positive rate
  across these ROMs. Use :func:`maybe_decompress`, which validates the decoded
  length before accepting the result.
"""

import struct

__all__ = [
    'CompressionError', 'read_comp_header', 'decompress_lz10', 'decompress_lz11',
    'decompress_rle', 'decompress_diff', 'decompress', 'maybe_decompress',
    'looks_compressed',
]

# Largest plausible decompressed asset; guards against a bogus header claiming
# a gigabyte and making us allocate forever.
MAX_DECOMPRESSED = 16 * 1024 * 1024


class CompressionError(ValueError):
    """Raised when a blob claims to be compressed but does not decode."""


def read_comp_header(data):
    """-> (type_byte, decompressed_size, payload_offset)."""
    if len(data) < 4:
        raise CompressionError('blob too short for a BIOS compression header')
    t = data[0]
    size = data[1] | (data[2] << 8) | (data[3] << 16)
    p = 4
    if size == 0:                       # extended 32-bit length
        if len(data) < 8:
            raise CompressionError('blob too short for an extended size field')
        size = struct.unpack_from('<I', data, 4)[0]
        p = 8
    return t, size, p


def decompress_lz10(data):
    """LZ10 (type 0x10). Raises CompressionError on a malformed stream."""
    t, size, p = read_comp_header(data)
    if t != 0x10:
        raise CompressionError('not LZ10: type byte 0x%02X' % t)
    if size > MAX_DECOMPRESSED:
        raise CompressionError('implausible decompressed size %d' % size)
    out = bytearray()
    n = len(data)
    try:
        while len(out) < size:
            flags = data[p]
            p += 1
            for bit in range(8):
                if len(out) >= size:
                    break
                if flags & (0x80 >> bit):
                    b0, b1 = data[p], data[p + 1]
                    p += 2
                    ln = (b0 >> 4) + 3
                    disp = (((b0 & 0x0F) << 8) | b1) + 1
                    start = len(out) - disp
                    if start < 0:
                        raise CompressionError('LZ10 displacement before start of output')
                    for i in range(ln):
                        out.append(out[start + i])   # byte-at-a-time: runs overlap
                else:
                    out.append(data[p])
                    p += 1
    except IndexError:
        raise CompressionError('LZ10 stream truncated at %d/%d bytes (input %d)'
                               % (len(out), size, n))
    return bytes(out[:size])


def decompress_lz11(data):
    """LZ11 (type 0x11). Raises CompressionError on a malformed stream."""
    t, size, p = read_comp_header(data)
    if t != 0x11:
        raise CompressionError('not LZ11: type byte 0x%02X' % t)
    if size > MAX_DECOMPRESSED:
        raise CompressionError('implausible decompressed size %d' % size)
    out = bytearray()
    n = len(data)
    try:
        while len(out) < size:
            flags = data[p]
            p += 1
            for bit in range(8):
                if len(out) >= size:
                    break
                if not (flags & (0x80 >> bit)):
                    out.append(data[p])
                    p += 1
                    continue
                b0 = data[p]
                ind = b0 >> 4
                if ind == 0:                                  # 3-byte form
                    b1, b2 = data[p + 1], data[p + 2]
                    p += 3
                    ln = (((b0 & 0x0F) << 4) | (b1 >> 4)) + 0x11
                    disp = (((b1 & 0x0F) << 8) | b2) + 1
                elif ind == 1:                                # 4-byte form
                    b1, b2, b3 = data[p + 1], data[p + 2], data[p + 3]
                    p += 4
                    ln = (((b0 & 0x0F) << 12) | (b1 << 4) | (b2 >> 4)) + 0x111
                    disp = (((b2 & 0x0F) << 8) | b3) + 1
                else:                                         # 2-byte form
                    b1 = data[p + 1]
                    p += 2
                    ln = ind + 1
                    disp = (((b0 & 0x0F) << 8) | b1) + 1
                start = len(out) - disp
                if start < 0:
                    raise CompressionError('LZ11 displacement before start of output')
                for i in range(ln):
                    out.append(out[start + i])
    except IndexError:
        raise CompressionError('LZ11 stream truncated at %d/%d bytes (input %d)'
                               % (len(out), size, n))
    return bytes(out[:size])


def decompress_rle(data):
    """BIOS run-length (type 0x30).

    UNVERIFIED against a genuine asset: a scan of Platinum, White 2 and
    HeartGold found no sub-file that both begins 0x3* and decodes to a
    recognisable Nitro resource. Kept for completeness; do not build a pipeline
    on it without first finding a real case.
    """
    t, size, p = read_comp_header(data)
    if t & 0xF0 != 0x30:
        raise CompressionError('not RLE: type byte 0x%02X' % t)
    out = bytearray()
    try:
        while len(out) < size:
            flag = data[p]
            p += 1
            if flag & 0x80:
                ln = (flag & 0x7F) + 3
                out += bytes([data[p]]) * ln
                p += 1
            else:
                ln = (flag & 0x7F) + 1
                chunk = data[p:p + ln]
                if len(chunk) < ln:
                    raise IndexError
                out += chunk
                p += ln
    except IndexError:
        raise CompressionError('RLE stream truncated at %d/%d bytes' % (len(out), size))
    return bytes(out[:size])


def decompress_diff(data):
    """Difference filter (0x80 = 8-bit, 0x81 = 16-bit).

    Not a compressor: each output element is the running sum of the deltas.
    """
    t, size, p = read_comp_header(data)
    if t & 0xF0 != 0x80:
        raise CompressionError('not a difference filter: type byte 0x%02X' % t)
    out = bytearray()
    try:
        if t & 0x0F == 0:
            cur = 0
            while len(out) < size:
                cur = (cur + data[p]) & 0xFF
                p += 1
                out.append(cur)
        else:
            cur = 0
            while len(out) < size:
                cur = (cur + struct.unpack_from('<H', data, p)[0]) & 0xFFFF
                p += 2
                out += struct.pack('<H', cur)
    except (IndexError, struct.error):
        raise CompressionError('diff stream truncated at %d/%d bytes' % (len(out), size))
    return bytes(out[:size])


def decompress(data):
    """Dispatch on the BIOS header byte. Raises if the type is compressed but bad.

    Returns the input unchanged when the type byte is not a known compression
    type. Use this when you KNOW the blob is compressed; use
    :func:`maybe_decompress` when you are guessing.
    """
    if not data:
        return data
    t = data[0]
    if t == 0x10:
        return decompress_lz10(data)
    if t == 0x11:
        return decompress_lz11(data)
    if t & 0xF0 == 0x30:
        return decompress_rle(data)
    if t & 0xF0 == 0x80:
        return decompress_diff(data)
    return data


def looks_compressed(data):
    """Cheap first-byte test. ~5% false-positive rate - validate before trusting."""
    return len(data) >= 4 and data[0] in (0x10, 0x11)


def maybe_decompress(data):
    """Decompress LZ10/LZ11 if the blob really is compressed, else return it as-is.

    Validates the decoded length against the declared length, which is what
    rejects the ~5% of sub-files whose leading byte merely coincides with a
    compression type.
    """
    if not looks_compressed(data):
        return bytes(data)
    size = data[1] | (data[2] << 8) | (data[3] << 16)
    if size == 0 or size > MAX_DECOMPRESSED:
        return bytes(data)
    try:
        out = decompress_lz10(data) if data[0] == 0x10 else decompress_lz11(data)
    except CompressionError:
        return bytes(data)
    if len(out) != size:
        return bytes(data)
    return out
