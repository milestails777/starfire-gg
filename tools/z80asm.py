"""Minimal two-pass Z80 assembler for the Starfire Game Gear ROM."""

from __future__ import annotations

import re
from pathlib import Path


REGS8 = {"b": 0, "c": 1, "d": 2, "e": 3, "h": 4, "l": 5, "a": 7}
REGS16 = {"bc": 0, "de": 1, "hl": 2, "sp": 3}
REGS16_AF = {"bc": 0, "de": 1, "hl": 2, "af": 3}

CC = {"nz": 0, "z": 1, "nc": 2, "c": 3, "po": 4, "pe": 5, "p": 6, "m": 7}
JR_CC = {"nz": 0, "z": 1, "nc": 2, "c": 3}


class AsmError(Exception):
    pass


def split_operands(text: str) -> list[str]:
    ops: list[str] = []
    cur = []
    depth = 0
    in_str = False
    for ch in text:
        if ch == '"' and not in_str:
            in_str = True
            cur.append(ch)
        elif ch == '"' and in_str:
            in_str = False
            cur.append(ch)
        elif in_str:
            cur.append(ch)
        elif ch == "(":
            depth += 1
            cur.append(ch)
        elif ch == ")":
            depth -= 1
            cur.append(ch)
        elif ch == "," and depth == 0:
            ops.append("".join(cur).strip())
            cur = []
        else:
            cur.append(ch)
    if cur:
        ops.append("".join(cur).strip())
    return [op for op in ops if op]


def parse_string(token: str) -> bytes | None:
    if len(token) >= 2 and token[0] == '"' and token[-1] == '"':
        return bytes(token[1:-1], "ascii")
    return None


class Assembler:
    def __init__(self, source_path: Path) -> None:
        self.source_path = source_path
        self.lines: list[tuple[Path, int, str]] = []
        self.labels: dict[str, int] = {}
        self.equ: dict[str, int] = {}
        self.pc = 0
        self.output = bytearray(0x8000)
        self.used = 0
        self.listing: list[str] = []
        self.pass_no = 1
        self.last_global = ""

    def load(self, path: Path) -> None:
        text = path.read_text(encoding="utf-8")
        for i, raw in enumerate(text.splitlines(), 1):
            line = raw.split(";")[0].strip()
            if not line:
                continue
            if line.lower().startswith(".include"):
                inc = line.split(None, 1)[1].strip().strip('"')
                self.load((path.parent / inc).resolve())
                continue
            self.lines.append((path, i, line))

    def fail(self, path: Path, lineno: int, msg: str) -> None:
        raise AsmError(f"{path.name}:{lineno}: {msg}")

    def resolve_name(self, name: str) -> str:
        if name.startswith("."):
            if not self.last_global:
                raise AsmError(f"local label {name} with no global label")
            return f"{self.last_global}{name}"
        return name

    def eval_expr(self, expr: str, path: Path, lineno: int) -> int:
        expr = expr.strip()
        sbytes = parse_string(expr)
        if sbytes is not None:
            if len(sbytes) != 1:
                self.fail(path, lineno, "string must be one character")
            return sbytes[0]
        if len(expr) == 3 and expr[0] == "'" and expr[2] == "'":
            return ord(expr[1])

        expr = expr.replace("HIGH(", "high(").replace("LOW(", "low(")
        # Split + / - while keeping signs
        parts = re.split(r"([+-])", expr.replace(" ", ""))
        total = 0
        sign = 1
        if parts and parts[0] == "":
            parts = parts[1:]
        i = 0
        while i < len(parts):
            tok = parts[i]
            if tok in "+-":
                sign = 1 if tok == "+" else -1
                i += 1
                if i >= len(parts):
                    self.fail(path, lineno, f"bad expression {expr}")
                tok = parts[i]
            total += sign * self.eval_atom(tok, path, lineno)
            i += 1
        return total & 0xFFFF

    def eval_atom(self, tok: str, path: Path, lineno: int) -> int:
        tok = tok.strip()
        if tok.lower().startswith("high(") and tok.endswith(")"):
            return (self.eval_expr(tok[5:-1], path, lineno) >> 8) & 0xFF
        if tok.lower().startswith("low(") and tok.endswith(")"):
            return self.eval_expr(tok[4:-1], path, lineno) & 0xFF
        if tok.startswith("$"):
            return int(tok[1:], 16)
        if tok.lower().startswith("0x"):
            return int(tok, 16)
        if tok.startswith("%"):
            return int(tok[1:], 2)
        if tok.isdigit() or (tok.startswith("-") and tok[1:].isdigit()):
            return int(tok) & 0xFFFF
        name = self.resolve_name(tok.lower())
        if name in self.equ:
            return self.equ[name]
        if name in self.labels:
            return self.labels[name]
        if self.pass_no == 1:
            return 0
        self.fail(path, lineno, f"unknown symbol {tok}")
        return 0

    def emit(self, data: bytes | list[int] | int) -> None:
        if isinstance(data, int):
            data = [data]
        for b in data:
            if self.pc >= len(self.output):
                self.output.extend(b"\xff" * 0x8000)
            if self.pass_no == 2:
                self.output[self.pc] = b & 0xFF
            self.pc += 1
            self.used = max(self.used, self.pc)

    def assemble(self) -> bytes:
        self.load(self.source_path)
        for self.pass_no in (1, 2):
            self.pc = 0
            self.last_global = ""
            self.listing.clear()
            for path, lineno, line in self.lines:
                try:
                    self.assemble_line(path, lineno, line)
                except AsmError:
                    raise
                except Exception as exc:
                    self.fail(path, lineno, str(exc))
        return bytes(self.output[:0x8000])

    def assemble_line(self, path: Path, lineno: int, line: str) -> None:
        start_pc = self.pc
        lowered = line.lower()

        if lowered.startswith(".equ") or lowered.startswith("equ "):
            rest = line.split(None, 1)[1]
            name, val = rest.split(",", 1) if "," in rest else rest.split(None, 1)
            self.equ[name.strip().lower()] = self.eval_expr(val, path, lineno)
            return

        m_equ = re.match(r"^([A-Za-z_.][A-Za-z0-9_.]*)\s+(?:equ|\.equ|=)\s+(.+)$", line, re.I)
        if m_equ:
            name = self.resolve_name(m_equ.group(1).lower())
            if not m_equ.group(1).startswith("."):
                self.last_global = name
            self.equ[name] = self.eval_expr(m_equ.group(2), path, lineno)
            return

        if ":" in line.split('"')[0]:
            label, rest = line.split(":", 1)
            label = label.strip()
            if label:
                name = label.lower()
                if name.startswith("."):
                    name = self.resolve_name(name)
                else:
                    self.last_global = name
                    name = name
                if self.pass_no == 1 and name in self.labels and self.labels[name] != self.pc:
                    # allow same value
                    pass
                self.labels[name] = self.pc
            line = rest.strip()
            if not line:
                return
            lowered = line.lower()

        if lowered.startswith(".org") or lowered.startswith("org "):
            self.pc = self.eval_expr(line.split(None, 1)[1], path, lineno)
            return
        if lowered.startswith(".db") or lowered.startswith("db ") or lowered.startswith("defb"):
            self.do_db(path, lineno, line.split(None, 1)[1])
            return
        if lowered.startswith(".dw") or lowered.startswith("dw ") or lowered.startswith("defw"):
            self.do_dw(path, lineno, line.split(None, 1)[1])
            return
        if lowered.startswith(".ds") or lowered.startswith("ds ") or lowered.startswith("defs"):
            n = self.eval_expr(line.split(None, 1)[1], path, lineno)
            self.emit([0xFF] * n)
            return
        if lowered.startswith(".incbin"):
            inc = line.split(None, 1)[1].strip().strip('"')
            candidates = [
                (self.source_path.parent / inc).resolve(),
                (path.parent / inc).resolve(),
                Path(inc).resolve(),
            ]
            binpath = next((p for p in candidates if p.exists()), None)
            if binpath is None:
                self.fail(path, lineno, f"incbin not found: {inc}")
            self.emit(binpath.read_bytes())
            return

        self.emit_op(path, lineno, line)
        if self.pass_no == 2:
            dumped = " ".join(f"{self.output[a]:02X}" for a in range(start_pc, self.pc))
            self.listing.append(f"{start_pc:04X}  {dumped:<18} {line}")

    def do_db(self, path: Path, lineno: int, rest: str) -> None:
        for op in split_operands(rest):
            s = parse_string(op)
            if s is not None:
                self.emit(s)
            else:
                self.emit(self.eval_expr(op, path, lineno) & 0xFF)

    def do_dw(self, path: Path, lineno: int, rest: str) -> None:
        for op in split_operands(rest):
            v = self.eval_expr(op, path, lineno) & 0xFFFF
            self.emit([v & 0xFF, v >> 8])

    def emit_op(self, path: Path, lineno: int, line: str) -> None:
        parts = line.split(None, 1)
        mnem = parts[0].lower()
        ops = split_operands(parts[1]) if len(parts) > 1 else []
        ops_l = [op.lower() for op in ops]
        nops = len(ops)

        def imm8(i=0) -> int:
            return self.eval_expr(ops[i], path, lineno) & 0xFF

        def imm16(i=0) -> tuple[int, int]:
            v = self.eval_expr(ops[i], path, lineno) & 0xFFFF
            return v & 0xFF, v >> 8

        def rel(i=0) -> int:
            target = self.eval_expr(ops[i], path, lineno)
            off = target - (self.pc + 2)
            if self.pass_no == 2 and (off < -128 or off > 127):
                self.fail(path, lineno, f"JR out of range ({off})")
            return off & 0xFF

        def is_mem(op: str) -> bool:
            return op.startswith("(") and op.endswith(")")

        def mem_inner(op: str) -> str:
            return op[1:-1].strip()

        if mnem == "nop" and nops == 0:
            self.emit(0x00)
            return
        if mnem == "halt":
            self.emit(0x76)
            return
        if mnem == "di":
            self.emit(0xF3)
            return
        if mnem == "ei":
            self.emit(0xFB)
            return
        if mnem == "reti":
            self.emit([0xED, 0x4D])
            return
        if mnem == "retn":
            self.emit([0xED, 0x45])
            return
        if mnem == "cpl":
            self.emit(0x2F)
            return
        if mnem == "scf":
            self.emit(0x37)
            return
        if mnem == "ccf":
            self.emit(0x3F)
            return
        if mnem == "rla":
            self.emit(0x17)
            return
        if mnem == "rra":
            self.emit(0x1F)
            return
        if mnem == "rlca":
            self.emit(0x07)
            return
        if mnem == "rrca":
            self.emit(0x0F)
            return
        if mnem == "exx":
            self.emit(0xD9)
            return
        if mnem == "neg":
            self.emit([0xED, 0x44])
            return
        if mnem == "ldir":
            self.emit([0xED, 0xB0])
            return
        if mnem == "lddr":
            self.emit([0xED, 0xB8])
            return
        if mnem == "otir":
            self.emit([0xED, 0xB3])
            return
        if mnem == "outi":
            self.emit([0xED, 0xA3])
            return
        if mnem == "im":
            mode = imm8(0)
            self.emit([0xED, {0: 0x46, 1: 0x56, 2: 0x5E}[mode]])
            return
        if mnem == "daa":
            self.emit(0x27)
            return

        if mnem == "ret":
            if nops == 0:
                self.emit(0xC9)
                return
            if ops_l[0] in CC:
                self.emit(0xC0 + (CC[ops_l[0]] << 3))
                return

        if mnem == "jp":
            if nops == 1 and ops_l[0] in ("(hl)", "hl"):
                self.emit(0xE9)
                return
            if nops == 2 and ops_l[0] in CC:
                lo, hi = imm16(1)
                self.emit([0xC2 + (CC[ops_l[0]] << 3), lo, hi])
                return
            if nops == 1:
                lo, hi = imm16(0)
                self.emit([0xC3, lo, hi])
                return

        if mnem == "call":
            if nops == 2 and ops_l[0] in CC:
                lo, hi = imm16(1)
                self.emit([0xC4 + (CC[ops_l[0]] << 3), lo, hi])
                return
            lo, hi = imm16(0)
            self.emit([0xCD, lo, hi])
            return

        if mnem == "jr":
            if nops == 2 and ops_l[0] in JR_CC:
                self.emit([0x20 + (JR_CC[ops_l[0]] << 3), rel(1)])
                return
            self.emit([0x18, rel(0)])
            return

        if mnem == "djnz":
            self.emit([0x10, rel(0)])
            return

        if mnem == "rst":
            n = imm8(0)
            self.emit(0xC7 + n)
            return

        if mnem == "push" and ops_l[0] in REGS16_AF:
            self.emit(0xC5 + (REGS16_AF[ops_l[0]] << 4))
            return
        if mnem == "pop" and ops_l[0] in REGS16_AF:
            self.emit(0xC1 + (REGS16_AF[ops_l[0]] << 4))
            return

        if mnem == "ex":
            if ops_l == ["de", "hl"]:
                self.emit(0xEB)
                return
            if ops_l == ["af", "af'"]:
                self.emit(0x08)
                return
            if ops_l == ["(sp)", "hl"]:
                self.emit(0xE3)
                return

        if mnem == "out" and nops == 2 and ops_l[1] == "a" and is_mem(ops_l[0]):
            self.emit([0xD3, self.eval_expr(mem_inner(ops[0]), path, lineno) & 0xFF])
            return
        if mnem == "in" and nops == 2 and ops_l[0] == "a" and is_mem(ops_l[1]):
            self.emit([0xDB, self.eval_expr(mem_inner(ops[1]), path, lineno) & 0xFF])
            return

        if mnem in ("inc", "dec") and nops == 1:
            table_inc = {"a": 0x3C, "b": 0x04, "c": 0x0C, "d": 0x14, "e": 0x1C, "h": 0x24, "l": 0x2C, "(hl)": 0x34}
            table_dec = {"a": 0x3D, "b": 0x05, "c": 0x0D, "d": 0x15, "e": 0x1D, "h": 0x25, "l": 0x2D, "(hl)": 0x35}
            table16_inc = {"bc": 0x03, "de": 0x13, "hl": 0x23, "sp": 0x33}
            table16_dec = {"bc": 0x0B, "de": 0x1B, "hl": 0x2B, "sp": 0x3B}
            src = table_inc if mnem == "inc" else table_dec
            src16 = table16_inc if mnem == "inc" else table16_dec
            if ops_l[0] in src:
                self.emit(src[ops_l[0]])
                return
            if ops_l[0] in src16:
                self.emit(src16[ops_l[0]])
                return

        if mnem == "add":
            if nops == 2 and ops_l[0] == "hl" and ops_l[1] in REGS16:
                self.emit(0x09 + (REGS16[ops_l[1]] << 4))
                return
            if nops == 2 and ops_l[0] == "a":
                self._alu(0, ops[1], ops_l[1], path, lineno)
                return
            if nops == 1:
                self._alu(0, ops[0], ops_l[0], path, lineno)
                return
        if mnem == "adc":
            if nops == 2 and ops_l[0] == "hl":
                self.emit([0xED, 0x4A + (REGS16[ops_l[1]] << 4)])
                return
            dst = ops[1] if nops == 2 else ops[0]
            dstl = ops_l[1] if nops == 2 else ops_l[0]
            self._alu(1, dst, dstl, path, lineno)
            return
        if mnem == "sbc":
            if nops == 2 and ops_l[0] == "hl":
                self.emit([0xED, 0x42 + (REGS16[ops_l[1]] << 4)])
                return
            dst = ops[1] if nops == 2 else ops[0]
            dstl = ops_l[1] if nops == 2 else ops_l[0]
            self._alu(3, dst, dstl, path, lineno)
            return
        if mnem == "sub":
            self._alu(2, ops[-1], ops_l[-1], path, lineno)
            return
        if mnem == "and":
            self._alu(4, ops[-1], ops_l[-1], path, lineno)
            return
        if mnem == "xor":
            self._alu(5, ops[-1], ops_l[-1], path, lineno)
            return
        if mnem == "or":
            self._alu(6, ops[-1], ops_l[-1], path, lineno)
            return
        if mnem == "cp":
            self._alu(7, ops[-1], ops_l[-1], path, lineno)
            return

        if mnem in ("rlc", "rrc", "rl", "rr", "sla", "sra", "srl"):
            cb = {"rlc": 0, "rrc": 1, "rl": 2, "rr": 3, "sla": 4, "sra": 5, "srl": 7}[mnem]
            r = 6 if ops_l[0] == "(hl)" else REGS8[ops_l[0]]
            self.emit([0xCB, (cb << 3) + r])
            return
        if mnem in ("bit", "res", "set"):
            b = self.eval_expr(ops[0], path, lineno)
            r = 6 if ops_l[1] == "(hl)" else REGS8[ops_l[1]]
            base = {"bit": 0x40, "res": 0x80, "set": 0xC0}[mnem]
            self.emit([0xCB, base + (b << 3) + r])
            return

        if mnem == "ld":
            self.emit_ld(path, lineno, ops, ops_l)
            return

        self.fail(path, lineno, f"unsupported instruction: {line}")

    def _alu(self, op: int, raw: str, low: str, path: Path, lineno: int) -> None:
        if low in REGS8:
            self.emit(0x80 + (op << 3) + REGS8[low])
            return
        if low == "(hl)":
            self.emit(0x80 + (op << 3) + 6)
            return
        self.emit([0xC6 + (op << 3), self.eval_expr(raw, path, lineno) & 0xFF])

    def emit_ld(self, path: Path, lineno: int, ops: list[str], ops_l: list[str]) -> None:
        a, b = ops_l[0], ops_l[1]
        ra, rb = ops[0], ops[1]

        def is_mem(op: str) -> bool:
            return op.startswith("(") and op.endswith(")")

        def inner(op: str) -> str:
            return op[1:-1].strip().lower()

        if a in REGS8 and b in REGS8:
            self.emit(0x40 + (REGS8[a] << 3) + REGS8[b])
            return
        if a in REGS8 and b == "(hl)":
            self.emit(0x40 + (REGS8[a] << 3) + 6)
            return
        if a == "(hl)" and b in REGS8:
            self.emit(0x70 + REGS8[b])
            return
        if a == "(de)" and b == "a":
            self.emit(0x12)
            return
        if a == "(bc)" and b == "a":
            self.emit(0x02)
            return
        if a == "a" and b == "(de)":
            self.emit(0x1A)
            return
        if a == "a" and b == "(bc)":
            self.emit(0x0A)
            return
        if a == "a" and is_mem(b) and inner(b) not in ("hl", "de", "bc"):
            v = self.eval_expr(mem_expr(rb), path, lineno)
            self.emit([0x3A, v & 0xFF, v >> 8])
            return
        if a in REGS8:
            self.emit([0x06 + (REGS8[a] << 3), self.eval_expr(rb, path, lineno) & 0xFF])
            return
        if a == "(hl)":
            self.emit([0x36, self.eval_expr(rb, path, lineno) & 0xFF])
            return
        if a in REGS16 and not is_mem(b) and b not in REGS16 and b != "hl":
            v = self.eval_expr(rb, path, lineno) & 0xFFFF
            self.emit([0x01 + (REGS16[a] << 4), v & 0xFF, v >> 8])
            return
        if a == "sp" and b == "hl":
            self.emit(0xF9)
            return
        if a == "(nn)" or (is_mem(a) and inner(a) not in ("hl", "de", "bc", "ix", "iy")):
            nn = mem_expr(ra)
            v = self.eval_expr(nn, path, lineno)
            if b == "a":
                self.emit([0x32, v & 0xFF, v >> 8])
                return
            if b == "hl":
                self.emit([0x22, v & 0xFF, v >> 8])
                return
            if b in REGS16:
                self.emit([0xED, 0x43 + (REGS16[b] << 4), v & 0xFF, v >> 8])
                return
        if b.startswith("(") and a == "a" and inner(b) not in ("hl", "de", "bc"):
            v = self.eval_expr(mem_expr(rb), path, lineno)
            self.emit([0x3A, v & 0xFF, v >> 8])
            return
        if b.startswith("(") and a == "hl" and inner(b) not in ("hl", "de", "bc"):
            v = self.eval_expr(mem_expr(rb), path, lineno)
            self.emit([0x2A, v & 0xFF, v >> 8])
            return
        if b.startswith("(") and a in REGS16 and inner(b) not in ("hl", "de", "bc"):
            v = self.eval_expr(mem_expr(rb), path, lineno)
            self.emit([0xED, 0x4B + (REGS16[a] << 4), v & 0xFF, v >> 8])
            return
        self.fail(path, lineno, f"unsupported ld {ops}")


def mem_expr(op: str) -> str:
    return op.strip()[1:-1].strip()
