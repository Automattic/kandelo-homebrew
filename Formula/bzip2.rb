require (Tap.fetch("automattic", "kandelo-homebrew").path/"Kandelo/formula_support/kandelo_formula_support").to_s

class Bzip2 < Formula
  include KandeloFormulaSupport

  desc "Lossless block-sorting data compressor for Kandelo"
  homepage "https://sourceware.org/bzip2/"
  url "https://sourceware.org/pub/bzip2/bzip2-1.0.8.tar.gz"
  sha256 "ab5a03176ee106d3f0fa90e381da478ddae405918153cca248e682cd0c4a2269"
  license "bzip2-1.0.6"

  skip_clean "bin/bzip2", "lib/libbz2.a"
  link_overwrite "include/bzlib.h"

  def install
    kandelo_require_arch!("wasm32")
    kandelo_wasm_build do
      system "make",
        "CC=#{kandelo_cc}",
        "AR=#{kandelo_ar}",
        "RANLIB=#{kandelo_ranlib}",
        "CFLAGS=-Wall -Winline -O2 -D_FILE_OFFSET_BITS=64",
        "LDFLAGS=",
        "libbz2.a", "bzip2"
    end
    kandelo_install_bin(buildpath, "bzip2", "bzip2")
    lib.install "libbz2.a"
    include.install "bzlib.h"
  end

  test do
    assert_path_exists lib/"libbz2.a"
    assert_path_exists include/"bzlib.h"

    source = testpath/"bzip2-smoke.c"
    wasm = testpath/"bzip2-smoke.wasm"
    source.write <<~C
      #include <bzlib.h>
      #include <stdio.h>
      #include <string.h>

      int main(void) {
        const char input[] = "Kandelo libbz2 round trip";
        char compressed[128];
        char output[128];
        unsigned int compressed_length = sizeof(compressed);
        unsigned int output_length = sizeof(output);

        if (BZ2_bzBuffToBuffCompress(compressed, &compressed_length,
              (char *)input, sizeof(input), 9, 0, 30) != BZ_OK) return 1;
        if (BZ2_bzBuffToBuffDecompress(output, &output_length,
              compressed, compressed_length, 0, 0) != BZ_OK) return 2;
        if (output_length != sizeof(input) || memcmp(input, output, sizeof(input)) != 0) return 3;
        puts("libbz2-ok");
        return 0;
      }
    C
    kandelo_wasm_build do
      system kandelo_cc, source, "-I#{include}", "-L#{lib}", "-lbz2", "-o", wasm
    end
    assert_equal "libbz2-ok\n", kandelo_run_wasm(wasm, [])

    input = "Kandelo bzip2 round trip\n".b
    compressed = kandelo_run_wasm(bin/"bzip2", ["-c"], stdin: input)
    assert_equal input, kandelo_run_wasm(bin/"bzip2", ["-dc"], stdin: compressed).b
  end
end
