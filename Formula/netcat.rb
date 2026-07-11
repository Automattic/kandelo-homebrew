require_relative "../Kandelo/formula_support/kandelo_formula_support"

class Netcat < Formula
  include KandeloFormulaSupport

  desc "GNU TCP and UDP networking utility for Kandelo"
  homepage "https://netcat.sourceforge.net/"
  url "https://downloads.sourceforge.net/project/netcat/netcat/0.7.1/netcat-0.7.1.tar.gz"
  sha256 "30719c9a4ffbcf15676b8f528233ccc54ee6cba96cb4590975f5fd60c68a066f"
  license "GPL-2.0-or-later"

  depends_on "binaryen" => :build
  depends_on "wabt" => :build

  skip_clean "bin/netcat"

  patch :DATA

  def install
    kandelo_require_arch!("wasm32")

    kandelo_wasm_build do |root|
      ENV["CFLAGS"] = "-O2 -gline-tables-only -fdebug-compilation-dir=."
      ENV["ac_cv_func_malloc_0_nonnull"] = "yes"
      ENV["ac_cv_func_realloc_0_nonnull"] = "yes"
      ENV["ac_cv_func_gethostbyname"] = "yes"
      ENV["ac_cv_func_getservbyname"] = "yes"
      ENV["ac_cv_func_getaddrinfo"] = "yes"
      ENV["ac_cv_func_inet_pton"] = "yes"
      ENV["ac_cv_func_select"] = "yes"
      ENV["ac_cv_header_resolv_h"] = "no"
      ENV["ac_cv_lib_resolv_main"] = "no"
      ENV["gl_cv_func_gettimeofday_clobber"] = "no"

      configure_args = kandelo_std_configure_args
      # Upstream's 2004 config.sub predates arm64 Darwin. This identifies the
      # build machine only; the SDK wrapper supplies the Wasm target triplet.
      configure_args << "--build=arm-apple-darwin" if OS.mac? && Hardware::CPU.arm?
      system kandelo_configure, *configure_args,
        "--disable-nls",
        "--without-included-gettext"
      system "make", "-j#{ENV.make_jobs}"

      instrumented = buildpath/"src/netcat.instrumented"
      system "#{root}/scripts/run-wasm-fork-instrument.sh", buildpath/"src/netcat", "-o", instrumented
      artifact_guards = "#{root}/scripts/wasm-artifact-guards.sh"
      system "bash", "-c", <<~SH
        set -euo pipefail
        . #{artifact_guards.shellescape}
        expected_abi=$(wasm_current_abi_version #{root.to_s.shellescape})
        artifact_abi=$(wasm_extract_abi_version #{instrumented.to_s.shellescape})
        if [ -z "$expected_abi" ] || [ "$artifact_abi" != "$expected_abi" ]; then
          echo "ERROR: Netcat ABI $artifact_abi does not match Kandelo ABI $expected_abi" >&2
          exit 1
        fi
        wasm_require_no_legacy_asyncify #{instrumented.to_s.shellescape}
        if ! wasm_has_complete_fork_instrumentation #{instrumented.to_s.shellescape}; then
          echo "ERROR: Netcat has incomplete fork instrumentation" >&2
          exit 1
        fi
      SH
    end

    kandelo_install_bin(buildpath/"src", "netcat.instrumented", "netcat")
    bin.install_symlink "netcat" => "nc"
    man1.install "doc/netcat.1"
  end

  test do
    version_output = kandelo_run_wasm(bin/"netcat", ["--version"])
    assert_match(/netcat \(The GNU Netcat\) 0\.7\.1/, version_output)

    help_output = kandelo_run_wasm(bin/"nc", ["--help"], preserve_argv0: true)
    assert_includes help_output, "-l, --listen"
    assert_includes help_output, "-u, --udp"
    assert_includes help_output, "-c, --close"

    pair_output = kandelo_run_virtual_network_pairs(
      bin/"netcat",
      [
        {
          name:                 "tcp",
          transport:            "tcp",
          serverArgs:           %w[nc -n -l -p 25125 -w 3],
          clientArgs:           %w[nc -n -c 10.88.0.2 25125],
          serverStdin:          "",
          clientStdin:          "from-tcp\n",
          expectedServerStdout: "from-tcp\n",
        },
        {
          name:                 "udp",
          transport:            "udp",
          serverArgs:           %w[nc -n -c -u -l -p 25126 -w 3],
          clientArgs:           %w[nc -n -u -c 10.88.0.2 25126],
          serverStdin:          "",
          clientStdin:          "from-udp\n",
          expectedServerStdout: "from-udp\n",
        },
      ],
    )
    assert_includes pair_output, '"tcp"'
    assert_includes pair_output, '"udp"'

    binary = File.binread(bin/"netcat")
    refute_includes binary, prefix.to_s
    refute_match %r{/Users/[^/]+/}, binary
  end
end

__END__
diff --git a/src/netcat.c b/src/netcat.c
index 8fd6b51..3c19d64 100644
--- a/src/netcat.c
+++ b/src/netcat.c
@@ -494,2 +494,5 @@ int main(int argc, char *argv[])
     if (netcat_mode == NETCAT_LISTEN) {
+      /* A completed listen loop is successful; upstream leaves glob_ret at
+         its EXIT_FAILURE initializer. */
+      glob_ret = EXIT_SUCCESS;
       if (opt_exec) {
diff --git a/src/core.c b/src/core.c
index 7e6f3dd..158720a 100644
--- a/src/core.c
+++ b/src/core.c
@@ -81,7 +81,11 @@ static int core_udp_listen(nc_sock_t *ncsock)
 static int core_udp_listen(nc_sock_t *ncsock)
 {
   int ret, *sockbuf, sock, sock_max, timeout = ncsock->timeout;
-  bool need_udphelper = TRUE;
+  /* GNU netcat's fallback enumerates interfaces with SIOCGIFCONF and binds
+     one socket per address. Kandelo exposes ordinary INADDR_ANY UDP bind,
+     but not that non-POSIX interface-enumeration ioctl. Select upstream's
+     single-socket path. */
+  bool need_udphelper = FALSE;
 #ifdef USE_PKTINFO
   int sockopt = 1;
 #endif
diff --git a/src/netcat.h b/src/netcat.h
index 88a2974..3ee95f0 100644
--- a/src/netcat.h
+++ b/src/netcat.h
@@ -94 +94,5 @@
-#  define USE_PKTINFO
+/* Kandelo's current POSIX socket layer exposes the constants via libc headers,
+   but does not implement IP_PKTINFO ancillary data. Keep GNU netcat on its
+   portable UDP path until the kernel supports the sockopt and recvmsg control
+   messages. */
+/* #  define USE_PKTINFO */
