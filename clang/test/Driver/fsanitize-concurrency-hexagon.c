// RUN: %clang --target=hexagon-unknown-linux-musl -fsanitize=concurrency %s -### 2>&1 | FileCheck %s --check-prefix=STATIC
// RUN: %clang --target=hexagon-unknown-linux-musl -fsanitize=concurrency -shared-libsan %s -### 2>&1 | FileCheck %s --check-prefix=SHARED
// RUN: not %clang --target=hexagon-unknown-linux-android -fsanitize=concurrency %s -### 2>&1 | FileCheck %s --check-prefix=ANDROID
// RUN: not %clang --target=hexagon-unknown-none-elf -fsanitize=concurrency %s -### 2>&1 | FileCheck %s --check-prefix=BAREMETAL

// STATIC-NOT: error:
// STATIC: "-fsanitize=concurrency"
// STATIC: "--whole-archive" "{{.*}}libclang_rt.csan{{.*}}.a" "--no-whole-archive"
// STATIC-NOT: csan_offload

// SHARED-NOT: error:
// SHARED: "-fsanitize=concurrency"
// SHARED: libclang_rt.csan{{.*}}.so
// SHARED-NOT: csan_offload

// ANDROID: unsupported option '-fsanitize=concurrency'
// BAREMETAL: unsupported option '-fsanitize=concurrency'
