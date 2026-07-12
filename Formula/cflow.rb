require (Tap.fetch("automattic", "kandelo-homebrew").path/"Kandelo/formula_support/kandelo_formula_support").to_s

class Cflow < Formula
  include KandeloFormulaSupport

  GUEST_OPT_PREFIX = "/home/linuxbrew/.linuxbrew/opt/cflow".freeze

  desc "GNU C call graph generator for Kandelo"
  homepage "https://www.gnu.org/software/cflow/"
  url "https://ftpmirror.gnu.org/gnu/cflow/cflow-1.8.tar.xz"
  mirror "https://ftp.gnu.org/gnu/cflow/cflow-1.8.tar.xz"
  sha256 "a5830a708a587ebbf3b475b585935f89c33fc8fbd057af7d817d517aceaa7afa"
  license "GPL-3.0-or-later"

  depends_on "binaryen" => :build
  depends_on "wabt" => :build

  skip_clean "bin/cflow"

  def install
    kandelo_require_arch!("wasm32")

    kandelo_wasm_build do |root|
      stable_source = "/usr/src/cflow-#{version}"
      prefix_maps = {
        buildpath.to_s => stable_source,
        root.to_s      => "/usr/src/kandelo",
        "/nix/store"   => "/usr/src/toolchain",
      }.flat_map do |from, to|
        [
          "-ffile-prefix-map=#{from}=#{to}",
          "-fdebug-prefix-map=#{from}=#{to}",
          "-fmacro-prefix-map=#{from}=#{to}",
        ]
      end
      ENV["CFLAGS"] = ["-O2", "-gline-tables-only", *prefix_maps].join(" ")
      # The SDK site owns target facts; this gnulib runtime probe is package-specific.
      ENV["gl_cv_func_strerror_0_works"] = "yes"

      system kandelo_configure(root),
        "--prefix=#{GUEST_OPT_PREFIX}",
        "--disable-nls",
        "--disable-dependency-tracking"
      system "make", "-j#{ENV.make_jobs}"

      stage = buildpath/"kandelo-stage"
      system "make", "install", "DESTDIR=#{stage}"
      staged_prefix = stage/GUEST_OPT_PREFIX.delete_prefix("/")
      odie "cflow did not install into the guest opt prefix" unless staged_prefix.directory?
      kandelo_validate_wasm_artifact(staged_prefix/"bin/cflow", fork: :forbidden)
      prefix.install staged_prefix.children
    end
  end

  test do
    assert_match(/cflow(?:\.wasm)? \(GNU cflow\) #{Regexp.escape(version.to_s)}/,
      kandelo_run_wasm(bin/"cflow", ["--version"], env: { "CFLOWRC" => "", "CFLOW_OPTIONS" => "-q" }))
    assert_path_exists man1/"cflow.1"
    assert_path_exists info/"cflow.info"
    assert_path_exists share/"cflow/#{version}/c11.cfo"
    assert_path_exists share/"cflow/#{version}/gcc.cfo"

    (testpath/"main.c").write <<~C
      int dispatch(int value);

      static int recursive(int value) {
        return value > 1 ? recursive(value - 1) : dispatch(value);
      }

      int main(void) {
        return recursive(3);
      }
    C
    (testpath/"helpers.c").write <<~C
      static int leaf(int value) {
        return value + 1;
      }

      int dispatch(int value) {
        return value > 0 ? leaf(value) : 0;
      }
    C

    env = {
      "CFLOWRC"       => "",
      "CFLOW_OPTIONS" => "-q",
      "KERNEL_CWD"    => "/work",
    }
    guest_files = {
      "/work/main.c"    => testpath/"main.c",
      "/work/helpers.c" => testpath/"helpers.c",
    }
    graph = kandelo_run_wasm(
      bin/"cflow", ["--no-cpp", "--number", "main.c", "helpers.c"],
      env: env, guest_files: guest_files
    )
    assert_match(/main\(\).*\n\s+2\s+recursive\(\).*\(R\):/m, graph)
    assert_match(/recursive: see 2\).*\n\s+4\s+dispatch\(\).*\n\s+5\s+leaf\(\)/m, graph)

    inverted = kandelo_run_wasm(
      bin/"cflow", ["--no-cpp", "--reverse", "--brief", "main.c", "helpers.c"],
      env: env, guest_files: guest_files
    )
    assert_match(/leaf\(\).*:\n\s+dispatch\(\).*\[see 1\]/m, inverted)
    assert_match(/dispatch\(\).*:\n\s+recursive\(\).*\(R\):/m, inverted)

    xref = kandelo_run_wasm(
      bin/"cflow", ["--no-cpp", "--xref", "main.c", "helpers.c"],
      env: env, guest_files: guest_files
    )
    assert_match(/^dispatch \* helpers\.c:5 int dispatch \(int value\)$/m, xref)
    assert_match(/^dispatch   main\.c:4$/m, xref)
  end
end
