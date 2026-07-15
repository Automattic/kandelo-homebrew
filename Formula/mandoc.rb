require (Tap.fetch("automattic", "kandelo-homebrew").path/"Kandelo/formula_support/kandelo_formula_support").to_s
require "zlib"

class Mandoc < Formula
  include KandeloFormulaSupport

  desc "Manual page formatter and viewer for Kandelo"
  homepage "https://mandoc.bsd.lv/"
  url "https://mandoc.bsd.lv/snapshots/mandoc-1.14.6.tar.gz"
  sha256 "8bf0d570f01e70a6e124884088870cbed7537f36328d512909eb10cd53179d9c"
  license all_of: ["ISC", "BSD-2-Clause", "BSD-3-Clause"]

  depends_on "binaryen" => :build
  depends_on "wabt" => :build
  depends_on "automattic/kandelo-homebrew/less"
  depends_on "automattic/kandelo-homebrew/zlib"

  skip_clean "bin/mandoc", "bin/demandoc", "bin/soelim"

  def install
    kandelo_require_arch!("wasm32")
    zlib = formula_opt_prefix("automattic/kandelo-homebrew/zlib")
    guest_prefix = "/home/linuxbrew/.linuxbrew/opt/mandoc"
    guest_manpath = "/home/linuxbrew/.linuxbrew/share/man:/usr/local/share/man:/usr/share/man"

    kandelo_wasm_build do |root|
      stable_source = "/usr/src/mandoc-#{version}"
      prefix_maps = {
        buildpath.to_s => stable_source,
        root.to_s      => "/usr/src/kandelo",
        zlib.to_s      => "/usr/src/zlib",
        "/nix/store"   => "/usr/src/toolchain",
      }.flat_map do |from, to|
        [
          "-ffile-prefix-map=#{from}=#{to}",
          "-fdebug-prefix-map=#{from}=#{to}",
          "-fmacro-prefix-map=#{from}=#{to}",
        ]
      end
      cflags = [
        "-O2",
        "-gline-tables-only",
        "-D_GNU_SOURCE",
        "-fdebug-compilation-dir=#{stable_source}",
        *prefix_maps,
        "-I#{zlib}/include",
      ].join(" ")

      # Upstream's configure compiles and executes each feature probe. These
      # overrides were established by running the unmodified probes in Kandelo.
      # HAVE_RECVMSG records the probe result, not the broader syscall surface;
      # catman is disabled by explicit package policy below.
      target_features = {
        "HAVE_WFLAG"             => 1,
        "HAVE_ATTRIBUTE"         => 1,
        "HAVE_CMSG"              => 1,
        "HAVE_DIRENT_NAMLEN"     => 0,
        "HAVE_EFTYPE"            => 0,
        "HAVE_ENDIAN"            => 1,
        "HAVE_SYS_ENDIAN"        => 0,
        "HAVE_ERR"               => 1,
        "HAVE_FTS"               => 0,
        "HAVE_FTS_COMPARE_CONST" => 0,
        "HAVE_GETLINE"           => 1,
        "HAVE_GETSUBOPT"         => 1,
        "HAVE_ISBLANK"           => 1,
        "HAVE_LESS_T"            => 1,
        "HAVE_MKDTEMP"           => 1,
        "HAVE_MKSTEMPS"          => 1,
        "HAVE_NANOSLEEP"         => 1,
        "HAVE_NTOHL"             => 1,
        "HAVE_O_DIRECTORY"       => 1,
        "HAVE_OHASH"             => 0,
        "HAVE_PATH_MAX"          => 1,
        "HAVE_PLEDGE"            => 0,
        "HAVE_PROGNAME"          => 0,
        "HAVE_REALLOCARRAY"      => 1,
        "HAVE_RECALLOCARRAY"     => 0,
        "HAVE_RECVMSG"           => 0,
        "HAVE_REWB_BSD"          => 0,
        "HAVE_REWB_SYSV"         => 1,
        "HAVE_SANDBOX_INIT"      => 0,
        "HAVE_STRCASESTR"        => 1,
        "HAVE_STRINGLIST"        => 0,
        "HAVE_STRLCAT"           => 1,
        "HAVE_STRLCPY"           => 1,
        "HAVE_STRNDUP"           => 1,
        "HAVE_STRPTIME"          => 1,
        "HAVE_STRSEP"            => 1,
        "HAVE_STRTONUM"          => 0,
        "HAVE_VASPRINTF"         => 1,
        "HAVE_WCHAR"             => 1,
      }
      configure_local = [
        "CC=#{kandelo_arch}posix-cc",
        "AR=#{kandelo_arch}posix-ar",
        "CFLAGS=\"#{cflags}\"",
        "LDFLAGS=\"-L#{zlib}/lib\"",
        'STATIC=" "',
        "PREFIX=\"#{guest_prefix}\"",
        'BINDIR="${PREFIX}/bin"',
        'SBINDIR="${PREFIX}/sbin"',
        'MANDIR="${PREFIX}/share/man"',
        "MANPATH_BASE=\"#{guest_manpath}\"",
        "MANPATH_DEFAULT=\"#{guest_manpath}\"",
        'READ_ALLOWED_PATH="/home/linuxbrew/.linuxbrew/Cellar"',
        'BINM_PAGER="/home/linuxbrew/.linuxbrew/bin/less"',
        'LN="ln -sf"',
        "OSENUM=MANDOC_OS_OTHER",
        'UTF8_LOCALE="C.UTF-8"',
        "BUILD_CATMAN=0",
        "BUILD_CGI=0",
        "INSTALL_LIBMANDOC=0",
        *target_features.map { |name, value| "#{name}=#{value}" },
      ]
      (buildpath/"configure.local").write "#{configure_local.join("\n")}\n"

      system "./configure"
      system "make", "-j1"

      mandoc = buildpath/"mandoc"
      demandoc = buildpath/"demandoc"
      soelim = buildpath/"soelim"
      kandelo_fork_instrument(mandoc)
      kandelo_validate_wasm_artifact(mandoc, fork: :required, forbidden_paths: [zlib.to_s])
      kandelo_validate_wasm_artifact(demandoc, fork: :forbidden, forbidden_paths: [zlib.to_s])
      kandelo_validate_wasm_artifact(soelim, fork: :forbidden, forbidden_paths: [zlib.to_s])
    end

    kandelo_install_bin(buildpath, "mandoc", "mandoc")
    kandelo_install_bin(buildpath, "demandoc", "demandoc")
    kandelo_install_bin(buildpath, "soelim", "soelim")
    bin.install_symlink "mandoc" => "man"
    bin.install_symlink "mandoc" => "apropos"
    bin.install_symlink "mandoc" => "whatis"
    sbin.install_symlink "../bin/mandoc" => "makewhatis"

    man1.install "mandoc.1", "demandoc.1", "soelim.1", "man.1", "apropos.1"
    man1.install_symlink "apropos.1" => "whatis.1"
    man5.install "man.conf.5", "mandoc.db.5"
    man7.install "man.7", "mdoc.7", "roff.7", "eqn.7", "tbl.7", "mandoc_char.7"
    man8.install "makewhatis.8"
  end

  test do
    assert_equal "mandoc", (bin/"man").readlink.to_s
    assert_equal "mandoc", (bin/"apropos").readlink.to_s
    assert_equal "mandoc", (bin/"whatis").readlink.to_s
    assert_equal "../bin/mandoc", (sbin/"makewhatis").readlink.to_s
    %w[mandoc demandoc soelim man apropos whatis].each do |name|
      assert_path_exists man1/"#{name}.1"
    end
    %w[man.conf mandoc.db].each { |name| assert_path_exists man5/"#{name}.5" }
    %w[man mdoc roff eqn tbl mandoc_char].each { |name| assert_path_exists man7/"#{name}.7" }
    assert_path_exists man8/"makewhatis.8"

    guest_prefix = "/home/linuxbrew/.linuxbrew"
    assert_includes File.binread(bin/"mandoc"), "#{guest_prefix}/bin/less"

    workspace = testpath/"workspace"
    man1_dir = workspace/"man1"
    includes = workspace/"includes"
    man1_dir.mkpath
    includes.mkpath
    manual = <<~'ROFF'
      .Dd July 12, 2026
      .Dt KANDELOTEST 1
      .Os Kandelo
      .Sh NAME
      .Nm kandelotest
      .Nd Kandelo mandoc database marker
      .Sh DESCRIPTION
      Compressed input \(em rendered by the real mandoc formatter.
    ROFF
    compressed_page = man1_dir/"kandelotest.1.gz"
    Zlib::GzipWriter.open(compressed_page.to_s) do |gzip|
      gzip.mtime = 0
      gzip.write manual
    end
    (includes/"included.roff").write "included-marker\n"
    (workspace/"root.roff").write "before\n.so included.roff\nafter\n"

    mount = { "/work" => workspace }
    env = { "KERNEL_CWD" => "/work", "LC_ALL" => "C.UTF-8" }
    utf8 = kandelo_run_wasm(
      bin/"mandoc", ["-T", "utf8", "/work/man1/kandelotest.1"],
      env: env, writable_host_directories: mount
    )
    assert_includes utf8, "Kandelo mandoc database marker"
    assert_includes utf8, "\u2014"

    html = kandelo_run_wasm(
      bin/"mandoc", ["-T", "html", "/work/man1/kandelotest.1.gz"],
      env: env, writable_host_directories: mount
    )
    assert_includes html, "<!DOCTYPE html>"
    assert_includes html, "Kandelo mandoc database marker"

    assert_empty kandelo_run_wasm(
      sbin/"makewhatis", ["/work"], env: env, preserve_argv0: true,
      writable_host_directories: mount
    )
    assert_operator (workspace/"mandoc.db").size, :>, 64

    apropos = kandelo_run_wasm(
      bin/"apropos", ["-M", "/work", "Kandelo.*database"],
      env: env, preserve_argv0: true, writable_host_directories: mount
    )
    assert_includes apropos, "kandelotest(1) - Kandelo mandoc database marker"
    whatis = kandelo_run_wasm(
      bin/"whatis", ["-M", "/work", "kandelotest"],
      env: env, preserve_argv0: true, writable_host_directories: mount
    )
    assert_includes whatis, "kandelotest(1) - Kandelo mandoc database marker"
    formatted = kandelo_run_wasm(
      bin/"man", ["-M", "/work", "-c", "1", "kandelotest"],
      env: env, preserve_argv0: true, writable_host_directories: mount
    )
    assert_includes formatted, "Kandelo mandoc database marker"

    guest_less = "#{guest_prefix}/bin/less"
    paged = kandelo_run_pty_wasm(
      bin/"man", ["-M", "/work", "1", "kandelotest"],
      argv0:                     "#{guest_prefix}/opt/mandoc/bin/man",
      env:                       env.merge(
        "MANPAGER" => guest_less,
        "LESS"     => "-FXR",
        "TERM"     => "xterm-256color",
      ),
      exec_programs:             { guest_less => formula_opt_bin("automattic/kandelo-homebrew/less")/"less" },
      inputs:                    ["q"],
      writable_host_directories: mount
    )
    assert_includes paged, "Kandelo mandoc database marker"

    words = kandelo_run_wasm(
      bin/"demandoc", ["-w", "/work/man1/kandelotest.1"],
      env: env, writable_host_directories: mount
    ).lines.map(&:chomp)
    assert_includes words, "database"
    assert_includes words, "marker"
    refute_includes words, ".Nm"

    included = kandelo_run_wasm(
      bin/"soelim", ["-I", "/work/includes", "/work/root.roff"],
      env: env, writable_host_directories: mount
    )
    assert_equal "before\nincluded-marker\nafter\n", included
  end
end
