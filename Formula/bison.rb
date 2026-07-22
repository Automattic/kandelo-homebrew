require (Tap.fetch("automattic", "kandelo-homebrew").path/"Kandelo/formula_support/kandelo_formula_support").to_s

class Bison < Formula
  include KandeloFormulaSupport

  GUEST_OPT_PREFIX = "/home/linuxbrew/.linuxbrew/opt/bison".freeze
  GUEST_BISON = "#{GUEST_OPT_PREFIX}/bin/bison".freeze
  GUEST_YACC = "#{GUEST_OPT_PREFIX}/bin/yacc".freeze
  GUEST_M4 = "/home/linuxbrew/.linuxbrew/opt/m4/bin/m4".freeze

  desc "GNU parser generator and yacc replacement for Kandelo"
  homepage "https://www.gnu.org/software/bison/"
  url "https://ftpmirror.gnu.org/gnu/bison/bison-3.8.2.tar.xz"
  mirror "https://ftp.gnu.org/gnu/bison/bison-3.8.2.tar.xz"
  sha256 "9bba0214ccf7f1079c5d59210045227bcf619519840ebfa80cd3849cff5a5bf2"
  license "GPL-3.0-or-later"

  depends_on "binaryen" => :build
  depends_on "wabt" => :build
  depends_on "automattic/kandelo-homebrew/dash" => :test
  depends_on "automattic/kandelo-homebrew/m4"

  skip_clean "bin/bison"

  def install
    kandelo_require_arch!("wasm32")
    m4 = formula_opt_prefix("automattic/kandelo-homebrew/m4")

    kandelo_wasm_build do |root|
      stable_source = "/usr/src/bison-#{version}"
      # The release tarball's generated scanners retain the maintainer's
      # absolute source path in #line directives.
      %w[src/scan-code.c src/scan-gram.c src/scan-skel.c].each do |scanner|
        inreplace scanner, "/Users/akim/src/gnu/bison", stable_source
      end
      prefix_maps = {
        buildpath.to_s => stable_source,
        root.to_s      => "/usr/src/kandelo",
        m4.to_s        => "/usr/src/m4",
        "/nix/store"   => "/usr/src/toolchain",
      }.flat_map do |from, to|
        [
          "-ffile-prefix-map=#{from}=#{to}",
          "-fdebug-prefix-map=#{from}=#{to}",
          "-fmacro-prefix-map=#{from}=#{to}",
        ]
      end
      ENV["CFLAGS"] = ["-O2", "-gline-tables-only", *prefix_maps].join(" ")
      ENV["M4"] = kandelo_host_tool("m4")
      ENV["LEX"] = kandelo_host_tool("flex").to_s

      system kandelo_configure(root),
        "--prefix=#{GUEST_OPT_PREFIX}",
        "--disable-nls",
        "--disable-rpath",
        "--disable-dependency-tracking",
        "--without-libiconv-prefix",
        "--without-libintl-prefix",
        "--without-libtextstyle-prefix"

      # Configure must execute the native build-machine m4 while probing it,
      # but the installed target program must spawn the tap's guest m4.
      inreplace "lib/config.h", /^#define M4 ".*"$/, "#define M4 \"#{GUEST_M4}\""

      system "make", "-j#{ENV.make_jobs}"

      stage = buildpath/"kandelo-stage"
      system "make", "install", "DESTDIR=#{stage}"
      staged_prefix = stage/GUEST_OPT_PREFIX.delete_prefix("/")
      odie "bison did not install into the guest opt prefix" unless staged_prefix.directory?

      bison = staged_prefix/"bin/bison"
      chmod 0755, bison
      kandelo_validate_wasm_artifact(bison, fork: :forbidden, forbidden_paths: [m4])
      prefix.install staged_prefix.children
    end
  end

  test do
    assert_match(/^bison \(GNU Bison\) 3\.8\.2$/, kandelo_run_wasm(bin/"bison", ["--version"]))
    assert_path_exists bin/"yacc"
    assert_predicate bin/"yacc", :executable?
    yacc_script = (bin/"yacc").read
    assert_equal "#! /bin/sh\n", yacc_script.lines.first
    assert_includes yacc_script, "prefix=#{GUEST_OPT_PREFIX}"
    assert_includes yacc_script, "exec_prefix=${prefix}"
    assert_includes yacc_script, 'bindir=`relocate "${exec_prefix}/bin"`'
    assert_includes yacc_script, 'exec "$bindir/bison" -y "$@"'

    grammar = testpath/"answer.y"
    grammar.write <<~YACC
      %{
      #include <stdio.h>
      static int emitted;
      int yylex(void);
      void yyerror(const char *message);
      %}
      %token ANSWER
      %%
      input: ANSWER { puts("parser=42"); };
      %%
      int yylex(void) {
        if (emitted) return 0;
        emitted = 1;
        return ANSWER;
      }
      void yyerror(const char *message) { fprintf(stderr, "%s\\n", message); }
      int main(void) { return yyparse(); }
    YACC

    runtime_mounts = {
      "/work"                           => testpath,
      "#{GUEST_OPT_PREFIX}/share/bison" => pkgshare,
    }
    runtime_programs = {
      GUEST_BISON => bin/"bison",
      GUEST_M4    => formula_opt_bin("automattic/kandelo-homebrew/m4")/"m4",
    }
    runtime_env = { "KERNEL_CWD" => "/work" }
    assert_empty kandelo_run_wasm(
      bin/"bison",
      ["--defines=/work/answer.h", "--output=/work/answer.c", "/work/answer.y"],
      env:                       runtime_env,
      exec_programs:             runtime_programs,
      writable_host_directories: runtime_mounts,
    )
    assert_path_exists testpath/"answer.c"
    assert_path_exists testpath/"answer.h"

    kandelo_wasm_build do
      system kandelo_cc, testpath/"answer.c", "-o", testpath/"answer.wasm"
    end
    assert_equal "parser=42\n", kandelo_run_wasm(testpath/"answer.wasm", [])

    dash = formula_opt_bin("automattic/kandelo-homebrew/dash")/"dash"
    assert_empty kandelo_run_wasm(
      dash,
      [GUEST_YACC, "-d", "/work/answer.y"],
      env:                       runtime_env,
      exec_programs:             runtime_programs,
      guest_files:               { GUEST_YACC => bin/"yacc" },
      writable_host_directories: runtime_mounts,
    )
    assert_path_exists testpath/"y.tab.c"
    assert_path_exists testpath/"y.tab.h"

    kandelo_wasm_build do
      system kandelo_cc, testpath/"y.tab.c", "-o", testpath/"yacc-answer.wasm"
    end
    assert_equal "parser=42\n", kandelo_run_wasm(testpath/"yacc-answer.wasm", [])
  end
end
