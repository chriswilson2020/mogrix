#!/usr/bin/env python3
"""Shared ELF helpers for Mogrix IRIX N32 tooling.

These helpers are intentionally small and byte-oriented.  They support the
subset of ELF32/MIPS used by fix-anon-relocs and mrqs.
"""

from __future__ import annotations

import os
import struct
from pathlib import Path

R_MIPS_REL32 = 3
STB_LOCAL = 0
STV_PROTECTED = 3

DT_NULL = 0
DT_NEEDED = 1
DT_STRTAB = 5
DT_SYMTAB = 6
DT_RPATH = 15
DT_RUNPATH = 29
DT_MIPS_GOTSYM = 0x70000013
DT_MIPS_SYMTABNO = 0x70000011


def read_u8(data, off):
    return data[off]


def read_u16(data, off):
    return struct.unpack_from('>H', data, off)[0]


def read_u32(data, off):
    return struct.unpack_from('>I', data, off)[0]


def read_s32(data, off):
    return struct.unpack_from('>i', data, off)[0]


def write_u8(data, off, value):
    data[off] = value & 0xFF


def write_u16(data, off, value):
    struct.pack_into('>H', data, off, value & 0xFFFF)


def write_u32(data, off, value):
    struct.pack_into('>I', data, off, value & 0xFFFFFFFF)


def is_mips_n32_elf(data):
    return (
        len(data) >= 52
        and data[:4] == b'\x7fELF'
        and data[4] == 1             # ELFCLASS32
        and data[5] == 2             # ELFDATA2MSB
        and read_u16(data, 18) == 8  # EM_MIPS
    )


def get_string(data, base, offset):
    start = base + offset
    if start < 0 or start >= len(data):
        raise ValueError('string offset outside file')
    end = data.find(b'\0', start)
    if end < 0:
        raise ValueError('unterminated ELF string')
    return bytes(data[start:end]).decode('utf-8', 'replace')


def _section_headers(data):
    e_shoff = read_u32(data, 32)
    e_shentsize = read_u16(data, 46)
    e_shnum = read_u16(data, 48)
    e_shstrndx = read_u16(data, 50)
    if not e_shoff or not e_shentsize or not e_shnum:
        return [], None

    headers = []
    for i in range(e_shnum):
        off = e_shoff + i * e_shentsize
        if off + 40 > len(data):
            break
        headers.append({
            'index': i,
            'header_offset': off,
            'name_offset': read_u32(data, off),
            'type': read_u32(data, off + 4),
            'flags': read_u32(data, off + 8),
            'addr': read_u32(data, off + 12),
            'offset': read_u32(data, off + 16),
            'size': read_u32(data, off + 20),
            'link': read_u32(data, off + 24),
            'info': read_u32(data, off + 28),
            'addralign': read_u32(data, off + 32),
            'entsize': read_u32(data, off + 36),
        })

    if e_shstrndx >= len(headers):
        return headers, None
    return headers, headers[e_shstrndx]


def find_sections(data):
    headers, shstr = _section_headers(data)
    result = {}
    if shstr is None:
        return result

    for sh in headers:
        try:
            name = get_string(data, shstr['offset'], sh['name_offset'])
        except ValueError:
            continue
        sh = dict(sh)
        sh['name'] = name
        result[name] = sh

    # Historical callers use compact aliases.
    if '.dynsym' in result:
        result['dynsym'] = result['.dynsym']
    if '.dynstr' in result:
        result['dynstr'] = result['.dynstr']
    if '.rel.dyn' in result:
        result['rel'] = result['.rel.dyn']
    elif '.rel' in result:
        result['rel'] = result['.rel']
    if '.dynamic' in result:
        result['dynamic'] = result['.dynamic']
    return result


def find_dynstr(data, sections=None):
    sections = sections or find_sections(data)
    return sections.get('dynstr') or sections.get('.dynstr')


def find_dynamic_section(data):
    sections = find_sections(data)
    dynamic = sections.get('dynamic') or sections.get('.dynamic')
    if dynamic:
        return dynamic['offset'], dynamic['size']

    # Fallback to PT_DYNAMIC when section headers are unavailable.
    for ph in build_all_program_headers(data):
        if ph['type'] == 2:  # PT_DYNAMIC
            return ph['offset'], ph['filesz']
    return None, 0


def find_dynamic_tags(data):
    off, size = find_dynamic_section(data)
    tags = {}
    if off is None:
        return tags
    end = min(off + size, len(data))
    while off + 8 <= end:
        tag = read_s32(data, off)
        val = read_u32(data, off + 4)
        if tag == DT_NULL:
            break
        # Keep the first value; singleton MIPS tags are what callers use.
        tags.setdefault(tag, val)
        off += 8
    return tags


def build_all_program_headers(data):
    e_phoff = read_u32(data, 28)
    e_phentsize = read_u16(data, 42)
    e_phnum = read_u16(data, 44)
    headers = []
    if not e_phoff or not e_phentsize:
        return headers
    for i in range(e_phnum):
        off = e_phoff + i * e_phentsize
        if off + 32 > len(data):
            break
        headers.append({
            'index': i,
            'header_offset': off,
            'type': read_u32(data, off),
            'offset': read_u32(data, off + 4),
            'vaddr': read_u32(data, off + 8),
            'paddr': read_u32(data, off + 12),
            'filesz': read_u32(data, off + 16),
            'memsz': read_u32(data, off + 20),
            'flags': read_u32(data, off + 24),
            'align': read_u32(data, off + 28),
        })
    return headers


def build_load_segments(data):
    return [ph for ph in build_all_program_headers(data) if ph['type'] == 1]


def vaddr_to_foff(vaddr, load_segments):
    for seg in load_segments:
        start = seg['vaddr']
        end = start + seg['filesz']
        if start <= vaddr < end:
            return seg['offset'] + (vaddr - start)
    return None


def _dynamic_entries(data):
    off, size = find_dynamic_section(data)
    if off is None:
        return []
    entries = []
    end = min(off + size, len(data))
    while off + 8 <= end:
        tag = read_s32(data, off)
        val = read_u32(data, off + 4)
        if tag == DT_NULL:
            break
        entries.append((tag, val))
        off += 8
    return entries


def get_needed_libraries(data, sections=None, tags=None):
    sections = sections or find_sections(data)
    dynstr = find_dynstr(data, sections)
    if dynstr is None:
        return []
    result = []
    for tag, val in _dynamic_entries(data):
        if tag == DT_NEEDED:
            result.append(get_string(data, dynstr['offset'], val))
    return result


def get_rpath(data, sections=None, tags=None):
    sections = sections or find_sections(data)
    dynstr = find_dynstr(data, sections)
    if dynstr is None:
        return []
    paths = []
    for tag, val in _dynamic_entries(data):
        if tag in (DT_RPATH, DT_RUNPATH):
            paths.extend(p for p in get_string(data, dynstr['offset'], val).split(':') if p)
    return paths


def find_library_file(name, search_paths):
    candidate = Path(name)
    if candidate.is_absolute() and candidate.exists():
        return str(candidate)
    for directory in search_paths or []:
        p = Path(directory) / name
        if p.exists():
            return str(p)
    return None


def parse_library_symbols(path):
    data = Path(path).read_bytes()
    sections = find_sections(data)
    dynsym = sections.get('dynsym')
    dynstr = find_dynstr(data, sections)
    if dynsym is None or dynstr is None:
        return {}

    tags = find_dynamic_tags(data)
    count = tags.get(DT_MIPS_SYMTABNO)
    if not count:
        entsize = dynsym.get('entsize') or 16
        count = dynsym['size'] // entsize

    symbols = {}
    for idx in range(1, count):
        off = dynsym['offset'] + idx * 16
        if off + 16 > len(data):
            break
        st_name = read_u32(data, off)
        st_value = read_u32(data, off + 4)
        st_info = read_u8(data, off + 12)
        st_shndx = read_u16(data, off + 14)
        binding = st_info >> 4
        if not st_name or not st_value:
            continue
        if st_shndx == 0 or st_shndx >= 0xFF00:
            continue
        if binding == STB_LOCAL:
            continue
        try:
            name = get_string(data, dynstr['offset'], st_name)
        except ValueError:
            continue
        if name:
            symbols.setdefault(name, st_value)
    return symbols


def build_library_symbol_map(data, sections=None, tags=None, extra_lib_paths=None):
    sections = sections or find_sections(data)
    paths = []
    paths.extend(extra_lib_paths or [])
    paths.extend(get_rpath(data, sections, tags))

    env_paths = os.environ.get('IRIX_LIB_PATH', '')
    if env_paths:
        paths.extend(p for p in env_paths.split(':') if p)
    paths.extend([
        '/opt/sgug-staging/usr/sgug/lib32',
        '/opt/irix-sysroot/lib32',
        '/opt/irix-sysroot/usr/lib32',
    ])

    # De-duplicate while preserving search order.
    dedup = []
    seen = set()
    for p in paths:
        if p not in seen:
            seen.add(p)
            dedup.append(p)

    symbol_map = {}
    found = []
    missing = []
    for lib in get_needed_libraries(data, sections, tags):
        path = find_library_file(lib, dedup)
        if path is None:
            missing.append(lib)
            continue
        found.append((lib, path))
        try:
            symbols = parse_library_symbols(path)
        except (OSError, ValueError, struct.error):
            symbols = {}
        for name, value in symbols.items():
            symbol_map.setdefault(name, value)

    return symbol_map, {
        'libs_found': found,
        'libs_missing': missing,
        'total_symbols': len(symbol_map),
    }
