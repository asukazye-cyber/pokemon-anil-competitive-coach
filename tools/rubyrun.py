#!/usr/bin/env python3
"""Headless Ruby runner: drives the official ruby.wasm (WASI reactor build)
through the wasmtime Python API with a large WASM stack.

Why this exists: the sandbox has no native Ruby. ruby+stdlib.wasm (from the
@ruby/3.3-wasm-wasi npm package) is a real CRuby 3.3. Running it through
node's WASI crashes with a segfault on large/complex files because the default
WASM stack is too small for Ruby's recursive parser. wasmtime exposes
Config.max_wasm_stack, which fixes that.

The wasm module is a *reactor* using the component-model canonical ABI:
  _initialize()                        -> run ctors
  cabi_realloc(old,oldsz,align,new)    -> allocator for ABI buffers
  ruby-init: (vec_ptr, vec_len)        -> ruby_init(["ruby.wasm", ...])
  rb-eval-string-protect: (ptr, len)   -> (retptr) {handle, state}
  rb-errinfo: ()                       -> handle of current exception
  rstring-ptr: (handle)                -> (retptr or multivalue) {ptr, len}
The JS-ABI imports (rb-js-abi-host::*) are stubbed; they are only reachable
through require "js", which the battle engine never uses.

Usage:
  rubyrun.py <host_dir> <ruby.wasm> file <rel_path.rb> [more.rb ...]
  rubyrun.py <host_dir> <ruby.wasm> eval "<ruby code>"
The host dir is preopened as /work. Each file is eval'd in TOPLEVEL_BINDING
inside a begin/rescue wrapper that prints a FAILED marker on exceptions.
Exit code: 0 iff all files eval'd without raising.
"""
import re
import sys

from wasmtime import Engine, Store, Module, Linker, WasiConfig, WasmtimeError, FuncType, ValType


class RubyWasm:
    def __init__(self, wasm_path: str, host_dir: str, stack_bytes: int = 2 * 1024 * 1024):
        cfg = Engine.__new__(Engine) if False else None  # placeholder; use Config
        from wasmtime import Config
        config = Config()
        config.max_wasm_stack = stack_bytes
        self.engine = Engine(config)
        self.store = Store(self.engine)
        self.module = Module.from_file(self.engine, wasm_path)

        wasi = WasiConfig()
        wasi.argv = ["ruby.wasm", "-EUTF-8", "-e_=0"]
        wasi.preopen_dir(host_dir, "/work")
        wasi.env = [("RUBYOPT", ""), ("LANG", "C.UTF-8")]
        wasi.inherit_stdout()
        wasi.inherit_stderr()
        self.store.set_wasi(wasi)

        self.linker = Linker(self.engine)
        self.linker.define_wasi()
        self._stub_js_abi()
        self.instance = self.linker.instantiate(self.store, self.module)
        self.exports = self.instance.exports(self.store)
        self.mem = self.exports["memory"]
        self.realloc = self.exports["cabi_realloc"]

        self._initialize()

        # ruby_init with a command line
        args = ["ruby.wasm", "-EUTF-8", "-e_=0"]
        argv = [a + "\0" for a in args]
        vec = self._alloc(4 * len(argv) * 2, 4)
        for i, a in enumerate(argv):
            p = self._write_str(a)
            self._set_i32(vec + i * 8, p)
            self._set_i32(vec + i * 8 + 4, len(a))
        self._exp("ruby-init: func(args: list<string>) -> ()")(self.store, vec, len(argv))

    # -- low-level helpers ----------------------------------------------------
    def _exp(self, name_prefix):
        """Find an export by prefix (exports carry long ': func(...)' names)."""
        for name in self.exports:
            if name.startswith(name_prefix):
                return self.exports[name]
        return self.exports[name_prefix]

    def _initialize(self):
        self.exports["_initialize"](self.store)

    def _alloc(self, size: int, align: int = 4) -> int:
        return self.realloc(self.store, 0, 0, align, size)

    def _write_bytes(self, data: bytes) -> int:
        ptr = self.realloc(self.store, 0, 0, 1, len(data))
        self.mem.write(self.store, data, ptr)
        return ptr

    def _write_str(self, s: str) -> int:
        return self._write_bytes(s.encode("utf-8"))

    def _set_i32(self, ptr: int, val: int):
        self.mem.write(self.store, int(val).to_bytes(4, "little", signed=True), ptr)

    def _read_i32(self, ptr: int) -> int:
        return int.from_bytes(self.mem.read(self.store, ptr, ptr + 4), "little", signed=True)

    def _read_i64(self, ptr: int) -> int:
        return int.from_bytes(self.mem.read(self.store, ptr, ptr + 8), "little", signed=True)

    # -- JS ABI stubs ----------------------------------------------------------
    def _stub_js_abi(self):
        def skip(*args):
            raise RuntimeError("JS ABI used in headless run: " + str(args))

        def drop(*a):
            return None

        def ident(x, *rest):
            return x

        def throw_prohibit(msg_ptr, msg_len):
            data = self.mem.read(self.store, msg_ptr, msg_ptr + msg_len) if hasattr(self, "mem") else b"?"
            sys.stderr.write("[rubyrun] prohibit-rewind: " + data.decode("utf-8", "replace") + "\n")
            raise RuntimeError("prohibit rewind exception")

        # We need the module's import list before instantiation; use the module
        # compiled in __init__ (self.module) — but stubs must be registered on
        # the linker BEFORE instantiate. Reorder: this method is called after
        # self.module exists. OK.
        for imp in self.module.imports:
            mod, name = imp.module, imp.name
            if mod == "wasi_snapshot_preview1":
                continue
            ty = imp.type
            nres = self._results_len(ty)
            if name == "rb_wasm_throw_prohibit_rewind_exception":
                fn = throw_prohibit
            elif mod == "canonical_abi":
                if "resource_new" in name or "resource_get" in name:
                    fn = ident if nres else (lambda *a: None)
                else:
                    fn = drop
            else:
                fn = skip
            try:
                self.linker.define_func(mod, name, ty, fn)
            except Exception:
                pass

    @staticmethod
    def _results_len(ty):
        try:
            return len(list(ty.results))
        except Exception:
            return 0

    # -- eval -------------------------------------------------------------------
    def eval_protect(self, code: str):
        """Returns (ok: bool, err_string: str|None)."""
        ptr = self._write_str(code)
        f = self._exp("rb-eval-string-protect")
        raw = f(self.store, ptr, len(code.encode("utf-8")))
        handle, state = self._unpack_tuple2(raw)
        if state == 0:
            return True, None
        err = self._errinfo_string()
        return False, err

    def _unpack_tuple2(self, raw):
        # May be [a, b] (multi-value) or an int retptr.
        if isinstance(raw, list):
            return raw[0], raw[1]
        if isinstance(raw, tuple):
            return raw[0], raw[1]
        return self._read_i32(raw), self._read_i32(raw + 4)

    def _unpack_string_ret(self, raw, cap=64 * 1024):
        if isinstance(raw, (list, tuple)):
            ptr, ln = raw[0], raw[1]
        else:
            ptr, ln = self._read_i32(raw), self._read_i32(raw + 4)
        ln = max(0, min(ln, cap))
        ptr = max(0, ptr)
        try:
            return self.mem.read(self.store, ptr, ptr + ln).decode("utf-8", "replace")
        except Exception:
            return "<bad string ptr>"

    def _errinfo_string(self):
        try:
            f = self._exp("rb-errinfo")
            h = f(self.store)
            # rstring-ptr(handle) -> string(ptr,len)
            f = self._exp("rstring-ptr")
            raw = f(self.store, h)
            return self._unpack_string_ret(raw)
        except Exception as e:
            return f"<errinfo unavailable: {e}>"


WRAPPER = '''begin
  code = File.read(%s, mode: "rb")
  code.force_encoding("UTF-8") if code.encoding == Encoding::ASCII_8BIT
  eval(code, TOPLEVEL_BINDING, %s)
rescue Exception => e
  msg = "#{e.class}: #{e.message}\\n" + (e.backtrace || [])[0, 24].map { |l| "  from #{l}" }.join("\\n")
  begin
    File.open("/work/.rubyrun_last_error.txt", "a") { |f| f.puts "=== #{$PROGRAM_NAME} #{Time.now.to_i} ===", msg }
  rescue Exception
  end
  begin
    $stdout.flush; $stderr.puts msg; $stderr.flush
  rescue Exception
  end
end'''


def main():
    host_dir, wasm_path, mode, *rest = sys.argv[1:]
    stack = int(__import__("os").environ.get("RUBYRUN_STACK", 2 * 1024 * 1024))
    vm = RubyWasm(wasm_path, host_dir, stack_bytes=stack)
    vm.eval_protect("$stdout.sync = true; $stderr.sync = true")
    failures = 0
    if mode == "file":
        import json
        for rel in rest:
            path = "/work/" + rel
            qpath = json.dumps(path)  # JSON string escaping is Ruby-compatible
            ok, err = vm.eval_protect(WRAPPER % (qpath, qpath))
            if not ok:
                failures += 1
                sys.stderr.write(f"[rubyrun] FAILED {rel}: {err}\n")
    elif mode == "eval":
        ok, err = vm.eval_protect(" ".join(rest))
        if not ok:
            failures += 1
            sys.stderr.write(f"[rubyrun] EVAL FAILED: {err}\n")
    else:
        sys.exit(f"unknown mode {mode}")
    vm.eval_protect("begin; $stdout.flush; $stderr.flush; rescue; end")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
