require (Tap.fetch("automattic", "kandelo-homebrew").path/"Kandelo/formula_support/kandelo_formula_support").to_s

class Flex < Formula
  include KandeloFormulaSupport

  GUEST_OPT_PREFIX = "/home/linuxbrew/.linuxbrew/opt/flex".freeze
  GUEST_M4 = "/home/linuxbrew/.linuxbrew/opt/m4/bin/m4".freeze

  desc "Fast lexical analyzer generator and POSIX lex replacement for Kandelo"
  homepage "https://github.com/westes/flex"
  url "https://github.com/westes/flex/releases/download/v2.6.4/flex-2.6.4.tar.gz"
  sha256 "e87aae032bf07c26f85ac0ed3250998c37621d95f8bd748b31f15b33c45ee995"
  license "BSD-2-Clause"

  depends_on "binaryen" => [:build, :test]
  depends_on "wabt" => [:build, :test]
  depends_on "automattic/kandelo-homebrew/m4"

  skip_clean "bin/flex", "bin/lex"

  # Upstream only uses argv[0] to select C++ mode. Its documented --posix
  # mode is required for lex's POSIX interval-expression precedence, so make
  # the installed lex entry point select that mode inside the real program.
  patch :DATA

  def install
    kandelo_require_arch!("wasm32")
    m4 = formula_opt_prefix("automattic/kandelo-homebrew/m4")

    kandelo_wasm_build do |root|
      stable_source = "/usr/src/flex-#{version}"
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
      ENV["CC_FOR_BUILD"] = kandelo_host_cc.to_s
      ENV["M4"] = kandelo_host_tool("m4").to_s

      system kandelo_configure(root),
        "--prefix=#{GUEST_OPT_PREFIX}",
        "--disable-bootstrap",
        "--disable-dependency-tracking",
        "--disable-nls",
        "--disable-shared",
        "--enable-static"

      # Configure must execute native M4 while probing and building the shipped
      # skeleton. The installed target must execute the tap's guest M4 instead.
      inreplace "src/config.h", /^#define M4 ".*"$/, "#define M4 \"#{GUEST_M4}\""

      system "make", "-j#{ENV.make_jobs}"

      stage = buildpath/"kandelo-stage"
      system "make", "install", "DESTDIR=#{stage}"
      staged_prefix = stage/GUEST_OPT_PREFIX.delete_prefix("/")
      odie "flex did not install into the guest opt prefix" unless staged_prefix.directory?

      flex = staged_prefix/"bin/flex"
      kandelo_fork_instrument(flex)
      chmod 0755, flex
      kandelo_validate_wasm_artifact(flex, fork: :required, forbidden_paths: [m4])
      prefix.install staged_prefix.children
    end

    bin.install_symlink "flex" => "lex"
    man1.install_symlink "flex.1" => "lex.1"
  end

  test do
    assert_path_exists bin/"flex"
    assert_equal "flex", (bin/"lex").readlink.to_s
    assert_path_exists include/"FlexLexer.h"
    assert_path_exists lib/"libfl.a"
    assert_path_exists man1/"flex.1"
    assert_equal (man1/"flex.1").read, (man1/"lex.1").read
    assert_match(/^flex 2\.6\.4$/,
      kandelo_run_wasm(bin/"flex", ["--version"], preserve_argv0: true))

    scanner = testpath/"words.l"
    scanner.write <<~LEX
      %{
      #include <stdio.h>
      %}
      WORD [A-Za-z]+
      %%
      ab{3}     printf("<repeat:%s>", yytext);
      {WORD}    printf("<%s>", yytext);
      [ \\t]+   putchar(' ');
      \\n        putchar('\\n');
      .         ECHO;
      %%
      int main(int argc, char **argv) {
        int status = 0;

        for (int i = 1; i < argc; i++) {
          YY_BUFFER_STATE buffer = yy_scan_string(argv[i]);
          if (buffer == NULL) return 2;
          status = yylex();
          yy_delete_buffer(buffer);
          if (status != 0) return status;
        }
        return 0;
      }
    LEX

    m4 = formula_opt_bin("automattic/kandelo-homebrew/m4")/"m4"
    runtime_programs = { GUEST_M4 => m4 }
    runtime_files = { "/work/words.l" => scanner }
    runtime_env = { "KERNEL_CWD" => "/work" }
    generate_scanner = lambda do |program, command_name|
      argv = ["--stdout", "/work/words.l"]
      node_source = kandelo_run_wasm(
        program, argv,
        argv0:                     "#{GUEST_OPT_PREFIX}/bin/#{command_name}",
        env:                       runtime_env,
        exec_programs:             runtime_programs,
        expected_fork_descendants: 3,
        guest_files:               runtime_files
      )
      browser_source = kandelo_run_browser_wasm(
        program, argv,
        argv0:         command_name,
        env:           runtime_env,
        exec_programs: runtime_programs,
        guest_files:   runtime_files,
        timeout_ms:    180_000
      )
      assert_equal node_source, browser_source
      node_source
    end

    build_scanner = lambda do |name, source|
      c_source = testpath/"#{name}.c"
      wasm = testpath/"#{name}.wasm"
      c_source.write(source)
      kandelo_wasm_build do
        system kandelo_cc, c_source, "-I#{include}", "-L#{lib}", "-lfl", "-o", wasm
        kandelo_validate_wasm_artifact(wasm, fork: :forbidden)
      end
      wasm
    end

    flex_scanner = build_scanner.call("flex-scanner", generate_scanner.call(bin/"flex", "flex"))
    flex_inputs = ["Hello Kandelo 42\n", "ababab\n", "abbb\n"]
    flex_output = "<Hello> <Kandelo> 42\n<ababab>\n<repeat:abbb>\n"
    assert_equal flex_output, kandelo_run_wasm(flex_scanner, flex_inputs)
    assert_equal flex_output,
      kandelo_run_browser_wasm(flex_scanner, flex_inputs, argv0: "flex-scanner")

    lex_scanner = build_scanner.call("lex-scanner", generate_scanner.call(bin/"lex", "lex"))
    lex_inputs = ["POSIX lex 17\n", "ababab\n", "abbb\n"]
    # POSIX lex gives interval expressions lower precedence than
    # concatenation: ab{3} is (ab){3}, not abbb.
    lex_output = "<POSIX> <lex> 17\n<repeat:ababab>\n<abbb>\n"
    assert_equal lex_output, kandelo_run_wasm(lex_scanner, lex_inputs)
    assert_equal lex_output,
      kandelo_run_browser_wasm(lex_scanner, lex_inputs, argv0: "lex-scanner")
  end
end

__END__
diff --git a/src/main.c b/src/main.c
--- a/src/main.c
+++ b/src/main.c
@@ -997,2 +997,5 @@ void flexinit (int argc, char **argv)
-	program_name = basename (argv[0]);
-
+	program_name = basename (argv[0]);
+
+	if (program_name != NULL && strcmp (program_name, "lex") == 0)
+		posix_compat = true;
+
