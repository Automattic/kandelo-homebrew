require (Tap.fetch("automattic", "kandelo-homebrew").path/"Kandelo/formula_support/kandelo_formula_support").to_s

class Gettext < Formula
  include KandeloFormulaSupport

  GUEST_OPT_PREFIX = "/home/linuxbrew/.linuxbrew/opt/gettext".freeze

  desc "GNU message catalog runtime and build tools for Kandelo"
  homepage "https://www.gnu.org/software/gettext/"
  url "https://ftpmirror.gnu.org/gnu/gettext/gettext-1.0.tar.xz"
  mirror "https://ftp.gnu.org/gnu/gettext/gettext-1.0.tar.xz"
  sha256 "71132a3fb71e68245b8f2ac4e9e97137d3e5c02f415636eb508ae607bc01add7"
  license all_of: ["GPL-3.0-or-later", "LGPL-2.1-or-later"]

  depends_on "binaryen" => :build
  depends_on "pkgconf" => :build
  depends_on "wabt" => :build
  depends_on "automattic/kandelo-homebrew/libiconv"
  depends_on "automattic/kandelo-homebrew/libxml2"
  depends_on "automattic/kandelo-homebrew/ncurses"
  depends_on "automattic/kandelo-homebrew/zlib"

  skip_clean "bin"
  # Gnulib's locale-name code gates musl's nl_langinfo_l support on
  # __linux__; use its MUSL_LIBC fact without enabling Linux-only code.
  # libtextstyle's private prototype predates ncurses' standard int return.
  # WebAssembly enforces the function type at link/runtime, so align both the
  # declaration and bundled fallback with the ncurses bottle.
  patch :DATA

  def install
    kandelo_require_arch!("wasm32")
    libiconv = formula_opt_prefix("automattic/kandelo-homebrew/libiconv")
    libxml2 = formula_opt_prefix("automattic/kandelo-homebrew/libxml2")
    ncurses = formula_opt_prefix("automattic/kandelo-homebrew/ncurses")
    zlib = formula_opt_prefix("automattic/kandelo-homebrew/zlib")

    binaries = []
    kandelo_wasm_build do |root|
      stable_source = "/usr/src/gettext-#{version}"
      mapped_roots = {
        buildpath.to_s => stable_source,
        root.to_s      => "/usr/src/kandelo",
        libiconv.to_s  => "/usr/src/libiconv",
        libxml2.to_s   => "/usr/src/libxml2",
        ncurses.to_s   => "/usr/src/ncurses",
        zlib.to_s      => "/usr/src/zlib",
        "/nix/store"   => "/usr/src/toolchain",
      }
      prefix_maps = mapped_roots.flat_map do |from, to|
        [
          "-ffile-prefix-map=#{from}=#{to}",
          "-fdebug-prefix-map=#{from}=#{to}",
          "-fmacro-prefix-map=#{from}=#{to}",
        ]
      end
      ENV["CFLAGS"] = ["-O2", "-fdebug-compilation-dir=#{stable_source}", *prefix_maps].join(" ")
      ENV["CXXFLAGS"] = ENV["CFLAGS"]
      ENV["CPPFLAGS"] = "-I#{libxml2}/include/libxml2 -I#{libiconv}/include -I#{ncurses}/include/ncursesw"
      ENV["LDFLAGS"] = "-L#{libxml2}/lib -L#{libiconv}/lib -L#{ncurses}/lib -L#{zlib}/lib"
      # libxml2's static encoding objects use GNU libiconv, whose own static
      # closure includes libcharset. Keep these after libxml2 in the final
      # link rather than relying on an ambient system iconv implementation.
      ENV["LIBS"] = "-lz -liconv -lm -lcharset -ldl -pthread"
      ENV["PKG_CONFIG_LIBDIR"] = [
        libxml2/"lib/pkgconfig",
        ncurses/"lib/pkgconfig",
        zlib/"lib/pkgconfig",
      ].join(":")
      ENV.delete("PKG_CONFIG_PATH")
      ENV.delete("PKG_CONFIG_SYSROOT_DIR")

      # The same permissive link mode makes the no-library terminfo probe
      # succeed. Kandelo's ncurses bottle splits these symbols into
      # libtermcap.a -> libtinfow.a, so select that supported archive.
      ENV["gl_cv_terminfo"] = "libtermcap"
      ENV["gl_cv_terminfo_tparam"] = "no"
      ENV["gl_cv_terminfo_tparm"] = "yes"

      system kandelo_configure(root), "--prefix=#{GUEST_OPT_PREFIX}",
        "--disable-shared",
        "--enable-static",
        "--disable-java",
        "--disable-csharp",
        "--disable-libasprintf",
        "--with-included-libintl",
        "--with-included-libunistring",
        "--with-libxml2-prefix=#{libxml2}",
        "--with-libncurses-prefix=#{ncurses}",
        "--with-libtermcap-prefix=#{ncurses}",
        "--with-libiconv-prefix=#{libiconv}",
        "--without-emacs",
        "--without-git",
        "--without-cvs",
        "--without-bzip2",
        "--without-xz",
        "--disable-dependency-tracking"

      configured_flags = (buildpath/"gettext-tools/src/Makefile").read
      odie "gettext configured its bundled libxml2 instead of the tap dependency" unless
        configured_flags.match?(%r{^LIBXML = #{Regexp.escape(libxml2.to_s)}/lib/libxml2\.a\s*$}i)
      odie "gettext did not retain the tap GNU libiconv include root" unless
        configured_flags.match?(%r{^CPPFLAGS = .*\s-I#{Regexp.escape(libiconv.to_s)}/include(?:\s|$)}i)
      odie "gettext did not retain the tap GNU libiconv library root" unless
        configured_flags.match?(%r{^LDFLAGS = .*\s-L#{Regexp.escape(libiconv.to_s)}/lib(?:\s|$)}i)
      odie "gettext did not retain libxml2's ordered static link closure" unless
        configured_flags.match?(/^LIBS = -lz -liconv -lm -lcharset -ldl -pthread\s*$/i)
      terminfo_flags = (buildpath/"libtextstyle/lib/Makefile").read
      odie "gettext did not configure the tap ncurses terminfo library" unless
        terminfo_flags.match?(%r{^LIBTERMINFO = #{Regexp.escape(ncurses.to_s)}/lib/libtermcap\.a$}i)

      jobs = "-j#{ENV.make_jobs}"
      system "make", jobs, "-C", "gettext-runtime/intl"
      system "make", jobs, "-C", "gettext-runtime/gnulib-lib"
      system "make", jobs, "-C", "gettext-runtime/src", "gettext", "ngettext"
      system "make", jobs, "-C", "libtextstyle/lib"
      system "make", jobs, "-C", "gettext-tools/gnulib-lib"
      system "make", "-C", "gettext-tools/src", "textstyle.h", "textstyle/version.h", "textstyle/woe32dll.h"
      system "make", jobs, "-C", "gettext-tools/src", "msgfmt", "xgettext"

      fork_policies = {
        buildpath/"gettext-runtime/src/gettext"  => :forbidden,
        buildpath/"gettext-runtime/src/ngettext" => :forbidden,
        buildpath/"gettext-tools/src/msgfmt"     => :forbidden,
        buildpath/"gettext-tools/src/xgettext"   => :forbidden,
      }
      fork_policies.each do |artifact, fork_policy|
        kandelo_fork_instrument(artifact) if fork_policy == :required
        kandelo_validate_wasm_artifact(
          artifact,
          fork:            fork_policy,
          forbidden_paths: [libiconv, libxml2, ncurses, zlib],
        )
      end
      binaries = fork_policies.keys
    end

    bin.install binaries
    chmod 0755, bin.children

    system "make", "-C", "gettext-runtime/man", "gettext.1", "ngettext.1"
    man1.install "gettext-runtime/man/gettext.1", "gettext-runtime/man/ngettext.1",
      "gettext-tools/man/msgfmt.1", "gettext-tools/man/xgettext.1"
    its_files = (buildpath/"gettext-tools/its").children.select { |path| [".its", ".loc"].include?(path.extname) }
    (share/"gettext/its").install its_files
    (share/"gettext/styles").install (buildpath/"gettext-tools/styles").glob("*.css")
  end

  test do
    expected_versions = {
      "gettext"  => "gettext-runtime",
      "ngettext" => "gettext-runtime",
      "msgfmt"   => "gettext-tools",
      "xgettext" => "gettext-tools",
    }
    expected_versions.each do |command, component|
      assert_match(
        /#{Regexp.escape(command)} \(GNU #{Regexp.escape(component)}\) #{Regexp.escape(version.to_s)}/,
        kandelo_run_wasm(bin/command, ["--version"], preserve_argv0: true),
      )
    end

    (testpath/"messages.c").write <<~C
      #include <libintl.h>
      #include <stdio.h>

      int main(int argc, char **argv) {
        unsigned long count = argc > 1 ? 2 : 1;
        puts(gettext("Greeting"));
        printf(ngettext("%lu file", "%lu files", count), count);
        return 0;
      }
    C

    work_env = { "KERNEL_CWD" => "/work" }
    work_mount = { "/work" => testpath }
    assert_empty kandelo_run_wasm(
      bin/"xgettext",
      [
        "--language=C",
        "--keyword=gettext",
        "--keyword=ngettext:1,2",
        "--output=/work/messages.po",
        "/work/messages.c",
      ],
      env: work_env, writable_host_directories: work_mount,
    )
    extracted = (testpath/"messages.po").read
    assert_includes extracted, 'msgid "Greeting"'
    assert_includes extracted, 'msgid "%lu file"'
    assert_includes extracted, 'msgid_plural "%lu files"'

    po = <<~PO.b
      msgid ""
      msgstr ""
      "Project-Id-Version: kandelo-gettext-test 1\\n"
      "PO-Revision-Date: 2026-07-12 00:00+0000\\n"
      "Last-Translator: Kandelo Test <noreply@example.invalid>\\n"
      "Language: fr\\n"
      "Language-Team: fr\\n"
      "MIME-Version: 1.0\\n"
      "Content-Type: text/plain; charset=ISO-8859-1\\n"
      "Content-Transfer-Encoding: 8bit\\n"
      "Plural-Forms: nplurals=2; plural=(n > 1);\\n"

      msgid "Greeting"
      msgstr "cafPLACEHOLDER"

      msgid "%lu file"
      msgid_plural "%lu files"
      msgstr[0] "%lu fichier"
      msgstr[1] "%lu fichiers"
    PO
    po.sub!("cafPLACEHOLDER".b, "caf".b + [0xe9].pack("C"))
    File.binwrite(testpath/"fr.po", po)
    catalog = testpath/"locale/fr/LC_MESSAGES/kandelo.mo"
    catalog.dirname.mkpath
    assert_empty kandelo_run_wasm(
      bin/"msgfmt",
      ["--check", "--output-file=/work/locale/fr/LC_MESSAGES/kandelo.mo", "/work/fr.po"],
      env: work_env, writable_host_directories: work_mount,
    )
    assert_equal [0xde, 0x12, 0x04, 0x95].pack("C*"), catalog.binread(4)

    locale_env = work_env.merge(
      "LANGUAGE" => "fr", "LC_ALL" => "fr_FR.UTF-8", "TEXTDOMAINDIR" => "/work/locale",
    )
    translated = kandelo_run_wasm(
      bin/"gettext",
      ["--domain=kandelo", "Greeting"],
      env: locale_env, writable_host_directories: work_mount,
    )
    assert_equal "caf".b + [0xc3, 0xa9].pack("C*"), translated.b
    assert_equal "%lu fichier", kandelo_run_wasm(
      bin/"ngettext",
      ["--domain=kandelo", "%lu file", "%lu files", "1"],
      env: locale_env, writable_host_directories: work_mount,
    )
    assert_equal "%lu fichiers", kandelo_run_wasm(
      bin/"ngettext",
      ["--domain=kandelo", "%lu file", "%lu files", "2"],
      env: locale_env, writable_host_directories: work_mount,
    )

    (testpath/"window.ui").write <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <interface>
        <object class="GtkWindow" id="window">
          <property name="title" translatable="yes">Kandelo Catalog</property>
        </object>
      </interface>
    XML
    assert_empty kandelo_run_wasm(
      bin/"xgettext",
      [
        "--its=/support/glade2.its",
        "--output=/work/window.po",
        "/work/window.ui",
      ],
      env:                       work_env,
      guest_files:               { "/support/glade2.its" => share/"gettext/its/glade2.its" },
      writable_host_directories: work_mount,
    )
    assert_includes (testpath/"window.po").read, 'msgid "Kandelo Catalog"'

    styled = kandelo_run_wasm(
      bin/"xgettext",
      [
        "--language=C",
        "--color=always",
        "--style=/support/po-default.css",
        "--output=-",
        "/work/messages.c",
      ],
      env:                       work_env.merge("TERM" => "xterm-256color"),
      guest_files:               { "/support/po-default.css" => share/"gettext/styles/po-default.css" },
      writable_host_directories: work_mount,
    )
    assert_includes styled, "\e["
  end
end

__END__
diff --git a/gettext-runtime/gnulib-lib/getlocalename_l-unsafe.c b/gettext-runtime/gnulib-lib/getlocalename_l-unsafe.c
--- a/gettext-runtime/gnulib-lib/getlocalename_l-unsafe.c
+++ b/gettext-runtime/gnulib-lib/getlocalename_l-unsafe.c
@@ -37 +37 @@
-#if (__GLIBC__ >= 2 && !defined __UCLIBC__) || (defined __linux__ && HAVE_LANGINFO_H) || defined __CYGWIN__
+#if (__GLIBC__ >= 2 && !defined __UCLIBC__) || ((defined __linux__ || MUSL_LIBC) && HAVE_LANGINFO_H) || defined __CYGWIN__
@@ -483 +483 @@ getlocalename_l_unsafe (int category, locale_t locale)
-#elif defined __linux__ && HAVE_LANGINFO_H && defined NL_LOCALE_NAME
+#elif (defined __linux__ || MUSL_LIBC) && HAVE_LANGINFO_H && defined NL_LOCALE_NAME
diff --git a/gettext-runtime/intl/gnulib-lib/getlocalename_l-unsafe.c b/gettext-runtime/intl/gnulib-lib/getlocalename_l-unsafe.c
--- a/gettext-runtime/intl/gnulib-lib/getlocalename_l-unsafe.c
+++ b/gettext-runtime/intl/gnulib-lib/getlocalename_l-unsafe.c
@@ -37 +37 @@
-#if (__GLIBC__ >= 2 && !defined __UCLIBC__) || (defined __linux__ && HAVE_LANGINFO_H) || defined __CYGWIN__
+#if (__GLIBC__ >= 2 && !defined __UCLIBC__) || ((defined __linux__ || MUSL_LIBC) && HAVE_LANGINFO_H) || defined __CYGWIN__
@@ -483 +483 @@ getlocalename_l_unsafe (int category, locale_t locale)
-#elif defined __linux__ && HAVE_LANGINFO_H && defined NL_LOCALE_NAME
+#elif (defined __linux__ || MUSL_LIBC) && HAVE_LANGINFO_H && defined NL_LOCALE_NAME
diff --git a/gettext-tools/gnulib-lib/getlocalename_l-unsafe.c b/gettext-tools/gnulib-lib/getlocalename_l-unsafe.c
--- a/gettext-tools/gnulib-lib/getlocalename_l-unsafe.c
+++ b/gettext-tools/gnulib-lib/getlocalename_l-unsafe.c
@@ -37 +37 @@
-#if (__GLIBC__ >= 2 && !defined __UCLIBC__) || (defined __linux__ && HAVE_LANGINFO_H) || defined __CYGWIN__
+#if (__GLIBC__ >= 2 && !defined __UCLIBC__) || ((defined __linux__ || MUSL_LIBC) && HAVE_LANGINFO_H) || defined __CYGWIN__
@@ -483 +483 @@ getlocalename_l_unsafe (int category, locale_t locale)
-#elif defined __linux__ && HAVE_LANGINFO_H && defined NL_LOCALE_NAME
+#elif (defined __linux__ || MUSL_LIBC) && HAVE_LANGINFO_H && defined NL_LOCALE_NAME
diff --git a/libtextstyle/lib/terminfo.h b/libtextstyle/lib/terminfo.h
--- a/libtextstyle/lib/terminfo.h
+++ b/libtextstyle/lib/terminfo.h
@@ -110 +110 @@
-extern void tputs (const char *cp, int affcnt, int (*outcharfun) (int));
+extern int tputs (const char *cp, int affcnt, int (*outcharfun) (int));
diff --git a/libtextstyle/lib/tputs.c b/libtextstyle/lib/tputs.c
--- a/libtextstyle/lib/tputs.c
+++ b/libtextstyle/lib/tputs.c
@@ -24 +24 @@
-void tputs (const char *cp, int affcnt, int (*outcharfun) (int));
+int tputs (const char *cp, int affcnt, int (*outcharfun) (int));
@@ -28 +28 @@
-void
+int
@@ -38,4 +38,5 @@ tputs (const char *cp, int affcnt, int (*outcharfun) (int))
     }
   for (; *cp != '\0'; cp++)
     outcharfun (*cp);
+  return 0;
 }
