require (Tap.fetch("automattic", "kandelo-homebrew").path/"Kandelo/formula_support/kandelo_formula_support").to_s

class Xz < Formula
  include KandeloFormulaSupport

  desc "General-purpose data compression tools for Kandelo"
  homepage "https://tukaani.org/xz/"
  url "https://tukaani.org/xz/xz-5.6.2.tar.xz"
  mirror "http://tukaani.org/xz/xz-5.6.2.tar.xz"
  mirror "https://github.com/tukaani-project/xz/releases/download/v5.6.2/xz-5.6.2.tar.xz"
  sha256 "a9db3bb3d64e248a0fae963f8fb6ba851a26ba1822e504dc0efd18a80c626caf"
  license all_of: ["GPL-2.0-or-later", "LGPL-2.1-or-later", "0BSD"]

  skip_clean "bin", "lib/liblzma.a"

  def install
    kandelo_require_arch!("wasm32")

    # Upstream treats every Wasm target as unable to provide sigprocmask(2),
    # but Kandelo exposes the POSIX signal-mask API used by this code path.
    inreplace "src/common/mythread.h",
      "#if !(defined(_WIN32) && !defined(__CYGWIN__)) && !defined(__wasm__)",
      "#if !(defined(_WIN32) && !defined(__CYGWIN__))"

    kandelo_wasm_build do
      ENV["ac_cv_func_closedir_void"] = "no"
      ENV["ac_cv_func_malloc_0_nonnull"] = "yes"
      ENV["ac_cv_func_realloc_0_nonnull"] = "yes"
      ENV["ac_cv_func_calloc_0_nonnull"] = "yes"
      ENV["ac_cv_header_sys_capsicum_h"] = "no"
      ENV["ac_cv_func_cap_rights_limit"] = "no"
      ENV["ac_cv_sizeof_long"] = "4"
      ENV["ac_cv_sizeof_long_long"] = "8"
      ENV["ac_cv_sizeof_unsigned_long"] = "4"
      ENV["ac_cv_sizeof_int"] = "4"
      ENV["ac_cv_sizeof_size_t"] = "4"

      system kandelo_configure, *kandelo_std_configure_args,
        "--disable-nls",
        "--disable-threads",
        "--disable-shared",
        "--enable-static",
        "--disable-doc",
        "--disable-scripts",
        "--disable-lzmadec",
        "--disable-lzmainfo",
        "--enable-sandbox=no"
      system "make"
      system "make", "install"
    end

    rm lib/"liblzma.la" if (lib/"liblzma.la").exist?
  end

  test do
    assert_path_exists lib/"liblzma.a"
    assert_path_exists include/"lzma.h"
    assert_path_exists include/"lzma/base.h"
    assert_path_exists lib/"pkgconfig/liblzma.pc"

    source = testpath/"liblzma-smoke.c"
    wasm = testpath/"liblzma-smoke.wasm"
    source.write <<~C
      #include <lzma.h>
      #include <stdio.h>
      #include <string.h>

      int main(void) {
        const uint8_t input[] = "Kandelo liblzma round trip";
        uint8_t compressed[256];
        uint8_t output[128];
        size_t compressed_position = 0;
        size_t input_position = 0;
        size_t output_position = 0;
        uint64_t memory_limit = UINT64_MAX;

        if (lzma_easy_buffer_encode(6, LZMA_CHECK_CRC64, NULL,
              input, sizeof(input), compressed, &compressed_position,
              sizeof(compressed)) != LZMA_OK) return 1;
        if (lzma_stream_buffer_decode(&memory_limit, 0, NULL,
              compressed, &input_position, compressed_position,
              output, &output_position, sizeof(output)) != LZMA_OK) return 2;
        if (output_position != sizeof(input) || memcmp(input, output, sizeof(input)) != 0) return 3;
        puts("liblzma-ok");
        return 0;
      }
    C
    kandelo_wasm_build do
      system kandelo_cc, source, "-I#{include}", "-L#{lib}", "-llzma", "-o", wasm
    end
    assert_equal "liblzma-ok\n", kandelo_run_wasm(wasm, [])

    input = "Kandelo xz round trip\n".b
    compressed = kandelo_run_wasm(bin/"xz", ["-c"], stdin: input)
    assert_equal input, kandelo_run_wasm(bin/"xz", ["-dc"], stdin: compressed).b
  end
end
