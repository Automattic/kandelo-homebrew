require_relative "../Kandelo/formula_support/kandelo_formula_support"

class Bzip2 < Formula
  include KandeloFormulaSupport

  desc "Lossless block-sorting data compressor for Kandelo"
  homepage "https://sourceware.org/bzip2/"
  url "https://sourceware.org/pub/bzip2/bzip2-1.0.8.tar.gz"
  sha256 "ab5a03176ee106d3f0fa90e381da478ddae405918153cca248e682cd0c4a2269"
  license "bzip2-1.0.6"

  skip_clean "bin/bzip2"

  def install
    kandelo_require_arch!("wasm32")
    kandelo_wasm_build do
      system "make",
        "CC=#{kandelo_cc}",
        "AR=#{kandelo_ar}",
        "RANLIB=#{kandelo_ranlib}",
        "CFLAGS=-Wall -Winline -O2 -D_FILE_OFFSET_BITS=64",
        "LDFLAGS=",
        "bzip2"
    end
    kandelo_install_bin(buildpath, "bzip2", "bzip2")
  end

  test do
    input = "Kandelo bzip2 round trip\n".b
    compressed = kandelo_run_wasm(bin/"bzip2", ["-c"], stdin: input)
    assert_equal input, kandelo_run_wasm(bin/"bzip2", ["-dc"], stdin: compressed).b
  end
end
