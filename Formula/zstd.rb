require_relative "../Kandelo/formula_support/kandelo_formula_support"

class Zstd < Formula
  include KandeloFormulaSupport

  desc "Zstandard compression library and tools for Kandelo"
  homepage "https://facebook.github.io/zstd/"
  url "https://github.com/facebook/zstd/archive/refs/tags/v1.5.7.tar.gz"
  mirror "http://fresh-center.net/linux/misc/zstd-1.5.7.tar.gz"
  sha256 "37d7284556b20954e56e1ca85b80226768902e2edabd3b649e9e72c0c9012ee3"
  license all_of: [
    { any_of: ["BSD-3-Clause", "GPL-2.0-only"] },
    "BSD-2-Clause",
    "MIT",
  ]

  skip_clean "bin/zstd", "lib/libzstd.a"

  def install
    kandelo_require_arch!("wasm32")

    kandelo_wasm_build do |root|
      make_args = [
        "CC=#{kandelo_cc(root)}",
        "AR=#{kandelo_ar(root)}",
        "RANLIB=#{kandelo_ranlib(root)}",
        "CFLAGS=-O2",
        "HAVE_THREAD=1",
        "HAVE_ZLIB=0",
        "HAVE_LZMA=0",
        "HAVE_LZ4=0",
        "ZSTD_LEGACY_SUPPORT=5",
      ]

      system "make", "-j#{ENV.make_jobs}", "-C", "lib", "libzstd.a-mt", *make_args
      system "make", "-j#{ENV.make_jobs}", "-C", "programs", "zstd-release", *make_args

      install_args = ["PREFIX=#{prefix}", *make_args]
      system "make", "-C", "lib", "install-pc", "install-static", "install-includes",
        "MT=1", *install_args
      system "make", "-C", "programs", "install", *install_args
    end

    inreplace lib/"pkgconfig/libzstd.pc", prefix, opt_prefix
  end

  test do
    assert_path_exists bin/"zstd"
    assert_equal "zstd", (bin/"zstdcat").readlink.to_s
    assert_equal "zstd", (bin/"unzstd").readlink.to_s
    assert_equal "zstd", (bin/"zstdmt").readlink.to_s
    assert_path_exists bin/"zstdgrep"
    assert_path_exists bin/"zstdless"
    assert_path_exists lib/"libzstd.a"
    assert_path_exists include/"zstd.h"
    assert_path_exists include/"zstd_errors.h"
    assert_path_exists include/"zdict.h"
    assert_path_exists man1/"zstd.1"
    assert_path_exists man1/"zstdgrep.1"
    assert_path_exists man1/"zstdless.1"
    assert_includes (lib/"pkgconfig/libzstd.pc").read, "prefix=#{opt_prefix}"

    input = ("Kandelo zstd threaded round trip\n" * 4_096).b
    compressed = kandelo_run_wasm(bin/"zstd", ["-q", "-T2", "-c"], stdin: input)
    assert_equal input,
      kandelo_run_wasm(bin/"unzstd", ["-q", "-c"], stdin: compressed, preserve_argv0: true).b
    assert_equal input,
      kandelo_run_wasm(bin/"zstdcat", [], stdin: compressed, preserve_argv0: true).b

    source = testpath/"zstd-smoke.c"
    wasm = testpath/"zstd-smoke.wasm"
    source.write <<~C
      #include <stdio.h>
      #include <string.h>
      #include <zstd.h>

      int main(void) {
        const char input[] = "kandelo libzstd api";
        char compressed[128];
        char output[128];
        ZSTD_CCtx *context = ZSTD_createCCtx();
        size_t compressed_size;
        size_t output_size;

        if (context == NULL) return 1;
        if (ZSTD_isError(ZSTD_CCtx_setParameter(context, ZSTD_c_nbWorkers, 2))) return 2;
        compressed_size = ZSTD_compress2(
          context, compressed, sizeof(compressed), input, sizeof(input)
        );
        ZSTD_freeCCtx(context);
        if (ZSTD_isError(compressed_size)) return 3;
        output_size = ZSTD_decompress(output, sizeof(output), compressed, compressed_size);
        if (ZSTD_isError(output_size)) return 4;
        if (output_size != sizeof(input) || memcmp(input, output, sizeof(input)) != 0) return 5;
        printf("libzstd %s threaded-ok\\n", ZSTD_versionString());
        return 0;
      }
    C
    kandelo_wasm_build do |root|
      system kandelo_cc(root), source, "-I#{include}", "-L#{lib}", "-lzstd", "-pthread", "-o", wasm
    end
    assert_equal "libzstd #{version} threaded-ok\n", kandelo_run_wasm(wasm, [])
  end
end
