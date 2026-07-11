require (Tap.fetch("automattic", "kandelo-homebrew").path/"Kandelo/formula_support/kandelo_formula_support").to_s

class Xz < Formula
  include KandeloFormulaSupport

  desc "General-purpose data compression tools for Kandelo"
  homepage "https://tukaani.org/xz/"
  url "https://tukaani.org/xz/xz-5.6.2.tar.xz"
  mirror "https://github.com/tukaani-project/xz/releases/download/v5.6.2/xz-5.6.2.tar.xz"
  mirror "https://downloads.sourceforge.net/project/lzmautils/xz-5.6.2.tar.xz"
  mirror "http://downloads.sourceforge.net/project/lzmautils/xz-5.6.2.tar.xz"
  sha256 "a9db3bb3d64e248a0fae963f8fb6ba851a26ba1822e504dc0efd18a80c626caf"
  license all_of: ["GPL-2.0-or-later", "LGPL-2.1-or-later", "0BSD"]
  revision 1

  depends_on "pkgconf" => :test

  skip_clean "bin", "lib/liblzma.a"

  def install
    kandelo_require_arch!("wasm32")

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
        "--enable-threads=posix",
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
    inreplace lib/"pkgconfig/liblzma.pc" do |s|
      s.gsub!(/^prefix=.*/, "prefix=#{opt_prefix}")
      s.gsub!(/^exec_prefix=.*/, "exec_prefix=${prefix}")
      s.gsub!(/^libdir=.*/, "libdir=${exec_prefix}/lib")
      s.gsub!(/^includedir=.*/, "includedir=${prefix}/include")
    end
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
        static uint8_t input[262144];
        static uint8_t compressed[524288];
        static uint8_t output[sizeof(input)];
        lzma_stream stream = LZMA_STREAM_INIT;
        lzma_mt options = { 0 };
        size_t compressed_position = 0;
        size_t input_position = 0;
        size_t output_position = 0;
        uint64_t memory_limit = UINT64_MAX;
        lzma_ret result;

        for (size_t i = 0; i < sizeof(input); ++i) input[i] = (uint8_t)(i * 31U + i / 257U);
        options.threads = 2;
        options.block_size = 65536;
        options.preset = 6;
        options.check = LZMA_CHECK_CRC64;
        if (lzma_stream_encoder_mt(&stream, &options) != LZMA_OK) return 1;
        stream.next_in = input;
        stream.avail_in = sizeof(input);
        stream.next_out = compressed;
        stream.avail_out = sizeof(compressed);
        do {
          result = lzma_code(&stream, LZMA_FINISH);
        } while (result == LZMA_OK);
        if (result != LZMA_STREAM_END) return 2;
        compressed_position = sizeof(compressed) - stream.avail_out;
        lzma_end(&stream);
        if (lzma_stream_buffer_decode(&memory_limit, 0, NULL,
              compressed, &input_position, compressed_position,
              output, &output_position, sizeof(output)) != LZMA_OK) return 3;
        if (output_position != sizeof(input) || memcmp(input, output, sizeof(input)) != 0) return 4;
        puts("liblzma-mt-ok");
        return 0;
      }
    C
    kandelo_wasm_build do
      ENV["PKG_CONFIG_LIBDIR"] = (lib/"pkgconfig").to_s
      ENV.delete("PKG_CONFIG_PATH")
      ENV.delete("PKG_CONFIG_SYSROOT_DIR")
      pkgconf = formula_opt_bin("pkgconf")/"pkg-config"
      assert_equal opt_prefix.to_s,
        Utils.safe_popen_read(pkgconf, "--variable=prefix", "liblzma").strip
      flags = Utils.safe_popen_read(pkgconf, "--static", "--cflags", "--libs", "liblzma").split
      assert_includes flags, "-llzma"
      system kandelo_cc, source, *flags, "-o", wasm
    end
    assert_equal "liblzma-mt-ok\n", kandelo_run_wasm(wasm, [])

    %w[lzcat lzma unlzma unxz xzcat].each do |name|
      assert_equal "xz", (bin/name).readlink.to_s
    end
    assert_path_exists bin/"xzdec"

    input = "Kandelo xz round trip\n".b
    compressed = kandelo_run_wasm(bin/"xz", ["-c"], stdin: input)
    assert_equal input, kandelo_run_wasm(bin/"xz", ["-dc"], stdin: compressed).b
    assert_equal input, kandelo_run_wasm(bin/"xzdec", [], stdin: compressed).b
  end
end
