require (Tap.fetch("automattic", "kandelo-homebrew").path/"Kandelo/formula_support/kandelo_formula_support").to_s

class Cxref < Formula
  include KandeloFormulaSupport

  GUEST_OPT_PREFIX = "/home/linuxbrew/.linuxbrew/opt/cxref".freeze

  desc "Generate C source cross-references and documentation for Kandelo"
  homepage "https://www.gedanken.org.uk/software/cxref/"
  url "https://www.gedanken.org.uk/software/cxref/download/cxref-1.6e.tgz"
  sha256 "21492210f9e1030e4e697f0d84f31ac57a0844e64c8fb28432001c44663242f2"
  license "GPL-2.0-or-later"

  depends_on "binaryen" => :build
  depends_on "bison" => :build
  depends_on "flex" => :build
  depends_on "wabt" => :build

  skip_clean "bin/cxref", "bin/cxref-cpp"

  def install
    kandelo_require_arch!("wasm32")

    kandelo_wasm_build do |root|
      stable_source = "/usr/src/cxref-#{version}"
      mapped_roots = {
        buildpath.to_s               => stable_source,
        root.to_s                    => "/usr/src/kandelo",
        Pathname(root).realpath.to_s => "/usr/src/kandelo",
        "/nix/store"                 => "/usr/src/toolchain",
      }
      prefix_maps = mapped_roots.uniq.flat_map do |from, to|
        [
          "-ffile-prefix-map=#{from}=#{to}",
          "-fdebug-prefix-map=#{from}=#{to}",
          "-fmacro-prefix-map=#{from}=#{to}",
        ]
      end
      cflags = [
        "-O2", "-gline-tables-only", "-fdebug-compilation-dir=#{stable_source}", *prefix_maps
      ]
      ENV["CFLAGS"] = cflags.join(" ")

      # The historical configure test treats Clang's GCC-compatible predefined
      # macros as proof that the compiler is GCC and selects unsupported flags.
      ENV["ac_cv_c_compiler_gnu"] = "no"

      # Both the preprocessor's data lookup and cxref's exec target must name
      # the stable guest opt link, never the build-host Cellar or staging path.
      system kandelo_configure(root),
        "--prefix=#{GUEST_OPT_PREFIX}",
        "--with-cxref-cpp",
        "--disable-doc"

      # Upstream's generator refuses every non-GCC compiler and exits without
      # creating the required file. Emit its documented format from Kandelo's
      # target Clang macros. Do not copy the build-only SDK sysroot search
      # paths: cxref-cpp rejects missing default directories, while guest
      # headers are selected through cxref's normal -I interface.
      cpp_defines = buildpath/"cpp/cxref-cpp.defines"
      system "sh", "-c",
        "#{kandelo_cc(root).shellescape} -dM -E - < /dev/null | LC_ALL=C sort > #{cpp_defines.to_s.shellescape}"
      File.binwrite(
        cpp_defines,
        "// cxref-cpp runtime configuration file\n" + File.binread(cpp_defines),
      )

      system "make", "-j#{ENV.make_jobs}", "-C", "cpp", "cxref-cpp"
      # The historical yacc targets race each other under parallel make.
      system "make", "-C", "src", "cxref"

      cpp_command = [
        "#{GUEST_OPT_PREFIX}/bin/cxref-cpp",
        "-cxref-cpp-defines", "#{GUEST_OPT_PREFIX}/share/cxref/cxref-cpp.defines",
        "-lang-c", "-C", "-dD", "-dI"
      ].join(" ")
      system kandelo_cc(root), "-c", *cflags,
        "-Isrc", %Q(-DCXREF_CPP="#{cpp_command}"),
        "src/cxref.c", "-o", "src/cxref.o"
      (buildpath/"src/cxref").delete
      system "make", "-C", "src", "cxref"

      kandelo_fork_instrument(buildpath/"src/cxref")
      kandelo_validate_wasm_artifact(buildpath/"src/cxref", fork: :required)
      kandelo_validate_wasm_artifact(buildpath/"cpp/cxref-cpp", fork: :forbidden)
    end

    kandelo_install_bin(buildpath/"src", "cxref", "cxref")
    kandelo_install_bin(buildpath/"cpp", "cxref-cpp", "cxref-cpp")
    (share/"cxref").install buildpath/"cpp/cxref-cpp.defines"
    man1.install buildpath/"doc/README.man" => "cxref.1"
    man1.install buildpath/"cpp/cxref-cpp.man" => "cxref-cpp.1"
  end

  test do
    assert_path_exists bin/"cxref-cpp"
    assert_path_exists share/"cxref/cxref-cpp.defines"
    assert_path_exists man1/"cxref.1"
    assert_path_exists man1/"cxref-cpp.1"

    source = testpath/"sample.c"
    source.write <<~C
      /** A formula runtime fixture. **/
      #define SCALE 3

      /*+ Multiply the input by the fixture scale. +*/
      int scaled_answer(int input) {
        return input * SCALE;
      }
    C
    args = ["../work/sample.c", "-R/", "-raw", "-xref-all"]
    exec_programs = { "#{GUEST_OPT_PREFIX}/bin/cxref-cpp" => bin/"cxref-cpp" }
    guest_files = {
      "#{GUEST_OPT_PREFIX}/share/cxref/cxref-cpp.defines" => share/"cxref/cxref-cpp.defines",
    }
    guest_files["/work/sample.c"] = source

    node_output = kandelo_run_wasm(
      bin/"cxref", args,
      env:                               { "KERNEL_CWD" => "/root" },
      exec_programs:                     exec_programs,
      guest_files:                       guest_files,
      expected_fork_descendant_statuses: [0]
    )
    assert_match(%r{FILE : 'work/sample\.c'}, node_output)
    assert_match(/DEFINES : 'SCALE' = 3/, node_output)
    assert_match(/FUNCTION : scaled_answer \[Global\]/, node_output)

    browser_output = kandelo_run_browser_wasm(
      bin/"cxref", args,
      argv0:         "cxref",
      exec_programs: exec_programs,
      guest_files:   guest_files,
      timeout_ms:    120_000
    )
    assert_match(%r{FILE : 'work/sample\.c'}, browser_output)
    assert_match(/DEFINES : 'SCALE' = 3/, browser_output)
    assert_match(/FUNCTION : scaled_answer \[Global\]/, browser_output)
  end
end
