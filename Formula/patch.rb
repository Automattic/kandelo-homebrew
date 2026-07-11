require_relative "../Kandelo/formula_support/kandelo_formula_support"

class Patch < Formula
  include KandeloFormulaSupport

  desc "GNU utility for applying differences to files in Kandelo"
  homepage "https://savannah.gnu.org/projects/patch/"
  url "https://ftpmirror.gnu.org/gnu/patch/patch-2.8.tar.xz"
  mirror "https://ftp.gnu.org/gnu/patch/patch-2.8.tar.xz"
  sha256 "f87cee69eec2b4fcbf60a396b030ad6aa3415f192aa5f7ee84cad5e11f7f5ae3"
  license "GPL-3.0-or-later"

  skip_clean "bin/patch"

  def install
    kandelo_require_arch!("wasm32")

    instrumented = buildpath/"src/patch.instrumented"
    kandelo_wasm_build do |root|
      # The SDK site owns target facts; this gnulib runtime probe is package-specific.
      ENV["gl_cv_func_strerror_0_works"] = "yes"

      system kandelo_configure, *kandelo_std_configure_args,
        "--disable-nls",
        "--disable-xattr",
        "--disable-dependency-tracking"
      system "make", "-j#{ENV.make_jobs}"
      system "#{root}/scripts/run-wasm-fork-instrument.sh", buildpath/"src/patch", "-o", instrumented
    end

    kandelo_install_bin(buildpath/"src", "patch.instrumented", "patch")
    man1.install buildpath/"src/patch.1"
  end

  test do
    assert_match(/patch(?:\.wasm)? 2\.8$/, kandelo_run_wasm(bin/"patch", ["--version"]))

    workspace = testpath/"workspace"
    project = workspace/"project"
    project.mkpath
    (project/"notes.txt").write("alpha\nbeta\ngamma\n")
    (project/"remove.txt").write("remove me\n")
    env = { "KERNEL_CWD" => workspace }
    diff = <<~DIFF
      --- a/project/notes.txt
      +++ b/project/notes.txt
      @@ -1,3 +1,4 @@
       alpha
      -beta
      +beta revised
       gamma
      +delta
      --- /dev/null
      +++ b/project/new.txt
      @@ -0,0 +1,2 @@
      +created
      +file
      --- a/project/remove.txt
      +++ /dev/null
      @@ -1 +0,0 @@
      -remove me
    DIFF

    kandelo_run_wasm(bin/"patch", ["--batch", "-p1"], env: env, stdin: diff)
    assert_equal "alpha\nbeta revised\ngamma\ndelta\n", (project/"notes.txt").read
    assert_equal "created\nfile\n", (project/"new.txt").read
    refute_path_exists project/"remove.txt"

    kandelo_run_wasm(bin/"patch", ["--batch", "--dry-run", "-R", "-p1"], env: env, stdin: diff)
    assert_equal "alpha\nbeta revised\ngamma\ndelta\n", (project/"notes.txt").read
    assert_path_exists project/"new.txt"

    kandelo_run_wasm(bin/"patch", ["--batch", "-R", "-p1"], env: env, stdin: diff)
    assert_equal "alpha\nbeta\ngamma\n", (project/"notes.txt").read
    refute_path_exists project/"new.txt"
    assert_equal "remove me\n", (project/"remove.txt").read

    rejected = <<~DIFF
      --- a/project/notes.txt
      +++ b/project/notes.txt
      @@ -1,3 +1,3 @@
      -missing
      +replacement
       beta
       gamma
    DIFF
    failure = kandelo_run_wasm(
      bin/"patch",
      ["--batch", "--reject-file=failed.rej", "-p1"],
      env:             env,
      stdin:           rejected,
      merge_stderr:    true,
      expected_status: 1,
    )
    assert_match(/1 out of 1 hunk FAILED/, failure)
    assert_match(/missing/, (workspace/"failed.rej").read)
    assert_equal "alpha\nbeta\ngamma\n", (project/"notes.txt").read
  end
end
