require (Tap.fetch("automattic", "kandelo-homebrew").path/"Kandelo/formula_support/kandelo_formula_support").to_s

class Xz < Formula
  include KandeloFormulaSupport

  desc "General-purpose data compression tools for Kandelo"
  homepage "https://tukaani.org/xz/"
  url "https://tukaani.org/xz/xz-5.6.2.tar.xz"
  mirror "http://tukaani.org/xz/xz-5.6.2.tar.xz"
  mirror "https://github.com/tukaani-project/xz/releases/download/v5.6.2/xz-5.6.2.tar.xz"
  sha256 "a9db3bb3d64e248a0fae963f8fb6ba851a26ba1822e504dc0efd18a80c626caf"
  license all_of: ["GPL-2.0-or-later", "LGPL-2.1-or-later", "0BSD"]

  skip_clean "bin/xz"
  patch :DATA

  def install
    kandelo_require_arch!("wasm32")

    kandelo_wasm_build do
      ENV["ac_cv_func_closedir_void"] = "no"
      ENV["ac_cv_func_malloc_0_nonnull"] = "yes"
      ENV["ac_cv_func_realloc_0_nonnull"] = "yes"
      ENV["ac_cv_func_calloc_0_nonnull"] = "yes"
      ENV["ac_cv_header_sys_capsicum_h"] = "no"
      ENV["ac_cv_func_cap_rights_limit"] = "no"
      ENV["ac_cv_sizeof_long"] = "4"
      ENV["ac_cv_sizeof_long_long"] = "8"
      ENV["ac_cv_sizeof_unsigned_long"] = "4"
      ENV["ac_cv_sizeof_int"] = "4"
      ENV["ac_cv_sizeof_size_t"] = "4"

      system kandelo_configure, *kandelo_std_configure_args,
        "--disable-nls",
        "--disable-threads",
        "--disable-shared",
        "--enable-static",
        "--disable-doc",
        "--disable-scripts",
        "--disable-lzmadec",
        "--disable-lzmainfo",
        "--enable-sandbox=no"
      system "make"
    end

    kandelo_install_bin(buildpath/"src/xz", "xz", "xz")
  end

  test do
    input = "Kandelo xz round trip\n".b
    compressed = kandelo_run_wasm(bin/"xz", ["-c"], stdin: input)
    assert_equal input, kandelo_run_wasm(bin/"xz", ["-dc"], stdin: compressed).b
  end
end

__END__
diff --git a/src/common/mythread.h b/src/common/mythread.h
index 1f17812..a34e02c 100644
--- a/src/common/mythread.h
+++ b/src/common/mythread.h
@@ -81,3 +81,3 @@
-#if !(defined(_WIN32) && !defined(__CYGWIN__)) && !defined(__wasm__)
+#if !(defined(_WIN32) && !defined(__CYGWIN__))
 // Use sigprocmask() to set the signal mask in single-threaded programs.
 #include <signal.h>
