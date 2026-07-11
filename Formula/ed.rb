require_relative "../Kandelo/formula_support/kandelo_formula_support"

class Ed < Formula
  include KandeloFormulaSupport

  desc "GNU line-oriented text editor for Kandelo"
  homepage "https://www.gnu.org/software/ed/ed.html"
  url "https://ftpmirror.gnu.org/gnu/ed/ed-1.22.5.tar.lz"
  mirror "https://ftp.gnu.org/gnu/ed/ed-1.22.5.tar.lz"
  sha256 "56e107ddc2f29dad6690376c15bf9751509e1ee3b8241710e44edbe5c3a158cc"
  license "GPL-3.0-or-later"

  depends_on "lzip" => :build
  depends_on "automattic/kandelo-homebrew/sed"

  skip_clean "bin/ed"

  def install
    kandelo_require_arch!("wasm32")

    instrumented = buildpath/"ed.instrumented"
    kandelo_wasm_build do |root|
      system "./configure", "--prefix=#{prefix}"
      system "make"
      system "#{root}/scripts/run-wasm-fork-instrument.sh", buildpath/"ed", "-o", instrumented
    end

    kandelo_install_bin(buildpath, "ed.instrumented", "ed")
    bin.install buildpath/"red"
    man1.install buildpath/"doc/ed.1"
    man1.install_symlink "ed.1" => "red.1"
    info.install buildpath/"doc/ed.info"
  end

  test do
    assert_match(/GNU ed 1\.22\.5$/, kandelo_run_wasm(bin/"ed", ["--version"]))
    assert_path_exists bin/"red"
    assert_match(/exec "\$\{bindir\}"ed --restricted "\$@"/, (bin/"red").read)
    assert_equal "ed.1", (man1/"red.1").readlink.to_s

    document = testpath/"document.txt"
    document.write("alpha\nbeta\ngamma\n")
    commands = <<~ED
      ,s/beta/BETA/
      2a
      inserted
      .
      !printf ed-child
      w
      q
    ED
    output = kandelo_run_wasm(
      bin/"ed", ["-", "document.txt"], env: { "KERNEL_CWD" => testpath }, stdin: commands
    )
    assert_match(/ed-child/, output)
    assert_equal "alpha\nBETA\ninserted\ngamma\n", document.read

    restricted = kandelo_run_wasm(
      bin/"ed",
      ["--restricted", "-", "document.txt"],
      env:             { "KERNEL_CWD" => testpath },
      stdin:           "!printf forbidden\nq\n",
      merge_stderr:    true,
      expected_status: 1,
    )
    refute_match(/forbidden/, restricted)
    assert_match(/Shell access restricted/, restricted)
  end
end
