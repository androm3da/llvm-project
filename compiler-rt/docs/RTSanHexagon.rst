.. _RTSanHexagon:

======================
RTSan on Hexagon Linux
======================

.. contents::
  :local:

Prerequisites
=============

You need a Hexagon cross-compiler toolchain like one of the
ones at https://github.com/quic/toolchain_for_hexagon/releases

The examples below assume the toolchain is installed at::

    TOOLCHAIN=/opt/clang+llvm-22.1.4-cross-hexagon-unknown-linux-musl/x86_64-linux-gnu

Adjust the path for your toolchain version.

Building RTSan for Hexagon
==========================

Configure a standalone ``compiler-rt`` build targeting
``hexagon-unknown-linux-musl``.

.. code-block:: bash

    TOOLCHAIN=/opt/clang+llvm-22.1.4-cross-hexagon-unknown-linux-musl/x86_64-linux-gnu
    SYSROOT=${TOOLCHAIN}/target/hexagon-unknown-linux-musl/usr
    LLVM_LIT=/path/to/llvm-lit          # e.g. obj_llvm/bin/llvm-lit
    LLVM_TOOLS=/path/to/llvm/tools/bin  # must contain FileCheck and not

    cmake -G Ninja \
      -DCMAKE_C_COMPILER=${TOOLCHAIN}/bin/clang \
      -DCMAKE_CXX_COMPILER=${TOOLCHAIN}/bin/clang++ \
      -DCMAKE_C_COMPILER_TARGET=hexagon-unknown-linux-musl \
      -DCMAKE_CXX_COMPILER_TARGET=hexagon-unknown-linux-musl \
      -DCMAKE_ASM_COMPILER_TARGET=hexagon-unknown-linux-musl \
      -DCMAKE_SYSTEM_NAME=Linux \
      -DCMAKE_SYSROOT=${TOOLCHAIN}/target/hexagon-unknown-linux-musl \
      -DCMAKE_AR=${TOOLCHAIN}/bin/llvm-ar \
      -DCMAKE_NM=${TOOLCHAIN}/bin/llvm-nm \
      -DCMAKE_RANLIB=${TOOLCHAIN}/bin/llvm-ranlib \
      -DLLVM_CONFIG_PATH=${TOOLCHAIN}/bin/llvm-config \
      -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=ON \
      -DLLVM_EXTERNAL_LIT=${LLVM_LIT} \
      -DLLVM_TOOLS_DIR=${LLVM_TOOLS} \
      -DHOST_ARCH=hexagon \
      "-DCOMPILER_RT_EMULATOR=${TOOLCHAIN}/bin/qemu-hexagon -L ${SYSROOT}" \
      -DCOMPILER_RT_CAN_EXECUTE_TESTS=ON \
      -DCOMPILER_RT_BUILD_BUILTINS=OFF \
      -DCOMPILER_RT_BUILD_SANITIZERS=ON \
      -DCOMPILER_RT_SANITIZERS_TO_BUILD=rtsan \
      -DCOMPILER_RT_BUILD_XRAY=OFF \
      -DCOMPILER_RT_BUILD_MEMPROF=OFF \
      -DCOMPILER_RT_BUILD_LIBFUZZER=OFF \
      -DCOMPILER_RT_BUILD_PROFILE=OFF \
      -DCOMPILER_RT_BUILD_ORC=OFF \
      -DCOMPILER_RT_BUILD_CTX_PROFILE=OFF \
      -DCOMPILER_RT_BUILD_GWP_ASAN=OFF \
      -DCOMPILER_RT_USE_BUILTINS_LIBRARY=ON \
      -DCOMPILER_RT_CXX_LIBRARY=libcxx \
      -DSANITIZER_CXX_ABI=libc++ \
      -DSANITIZER_CXX_ABI_INTREE=OFF \
      -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON \
      -DCOMPILER_RT_INCLUDE_TESTS=ON \
      -DCMAKE_BUILD_TYPE=Release \
      -B ./obj_rtsan_hexagon \
      -S ./llvm-project/compiler-rt

    ninja -C ./obj_rtsan_hexagon rtsan

The resulting library is at::

    obj_rtsan_hexagon/lib/hexagon-unknown-linux-musl/libclang_rt.rtsan.a

Clang Driver Test
=================

Verify that clang accepts ``-fsanitize=realtime`` for the Hexagon Linux
target without emitting an "unsupported option" diagnostic:

.. code-block:: bash

    clang --target=hexagon-unknown-linux-musl -fsanitize=realtime \
      compiler-rt/test/Driver/fsanitize-realtime.c -### 2>&1 \
      | grep -c "unsupported option"
    # expected output: 0

The corresponding lit test is
``clang/test/Driver/fsanitize-realtime.c`` (the ``CHECK-RTSAN-HEXAGON``
check prefix).

Running the Lit Tests
=====================

There is no dedicated ``check-rtsan`` target.  The ``check-compiler-rt``
umbrella target is also unsuitable for standalone builds because with
``COMPILER_RT_CAN_EXECUTE_TESTS=ON`` it attempts to register the
``sanitizer_common`` test suite, which depends on ``asan`` and ``msan``
targets that are not built.

Instead, invoke ``llvm-lit`` directly on the generated per-target
configuration directory:

.. code-block:: bash

    llvm-lit -v --timeout=300 \
      ./obj_rtsan_hexagon/test/rtsan/HEXAGONLinuxConfig

``llvm-lit`` must be the same major version as the toolchain (i.e. a
separately built or system-installed LLVM 22 ``llvm-lit``).  With the
cmake flags above, the generated ``lit.site.cfg.py`` in that directory
already contains the correct ``clang``, ``emulator``, and
``llvm_tools_dir`` values.

Expected results with ``--timeout=300``::

    Passed:      13
    Unsupported:  1  (darwin-only test)
    Timeout:      1  (deduplicate_errors.cpp — see Known Limitations)

The 300-second timeout is recommended because ``deduplicate_errors.cpp``
makes 220 intercepted ``usleep(1)`` calls; QEMU syscall interception
overhead makes this test very slow.  It will still time out at 300 s —
this is a pre-existing QEMU performance limitation, not an RTSan bug.

Running the Unit Tests
======================

Build and run the ``Rtsan-hexagon-NoInstTest`` unit test binary:

.. code-block:: bash

    ninja -C ./obj_rtsan_hexagon TRtsan-hexagon-NoInstTest

    QEMU_LD_PREFIX=${SYSROOT} ${QEMU} \
      ./obj_rtsan_hexagon/lib/rtsan/tests/Rtsan-hexagon-NoInstTest

Expected output::

    [==========] 10 tests from 2 test suites ran.
    [  PASSED  ] 10 tests.

Known Limitations
=================

``Rtsan-hexagon-Test`` (the GTest binary built with ``-fsanitize=realtime``)
fails to link because the Hexagon musl sysroot does not include
``libatomic``.  This test will be revisited after that's addressed.

``deduplicate_errors.cpp`` - needs investigation, likely just a timeout
and could pass with a longer timeout.
