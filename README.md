# md4w distribution

This branch contains an installable package. Pin its commit in your dependency
manifest. The default module loads ReleaseSmall. Use `await init("fast")` to
load the stripped ReleaseFast file explicitly.

Both Wasm binaries are built from `c0dfec2b56e487dfe125c16e2abf14a8ba32fd1a`.
Use Zig 0.11.0 and LLVM objcopy 18:

```sh
git clone --recurse-submodules https://github.com/SethBurkart123/md4w.git source
cd source
git checkout c0dfec2b56e487dfe125c16e2abf14a8ba32fd1a
git submodule update --init --recursive
zig build -j2
llvm-objcopy-18 --strip-all js/md4w-fast.wasm
```

The session binding, type declarations and Wasm use the same [source commit](https://github.com/SethBurkart123/md4w/tree/c0dfec2b56e487dfe125c16e2abf14a8ba32fd1a).

```js
import { init, createSession } from "md4w";
await init();
const session = createSession({ streaming: true });
try {
  const update = session.append("First paragraph.\n\nSecond");
  const finalUpdate = session.finish();
} finally {
  session.close();
}
```

With Vite, import the asset URL and pass the fetch response to `init`:

```js
import { init, createSession } from "md4w";
import wasmUrl from "md4w/js/md4w-small.wasm?url";
await init(fetch(wasmUrl));
```
