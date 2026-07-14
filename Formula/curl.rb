require (Tap.fetch("automattic", "kandelo-homebrew").path/"Kandelo/formula_support/kandelo_formula_support").to_s

class Curl < Formula
  include KandeloFormulaSupport

  desc "Command-line multiprotocol file transfer tool for Kandelo"
  homepage "https://curl.se/"
  url "https://curl.se/download/curl-8.11.1.tar.xz"
  sha256 "c7ca7db48b0909743eaef34250da02c19bc61d4f1dcedd6603f109409536ab56"
  license "curl"

  depends_on "binaryen" => :build
  depends_on "pkgconf" => :build
  depends_on "wabt" => :build
  depends_on "automattic/kandelo-homebrew/libcurl"
  depends_on "automattic/kandelo-homebrew/openssl"
  depends_on "automattic/kandelo-homebrew/zlib"

  skip_clean "bin/curl"

  def install
    kandelo_require_arch!("wasm32", "wasm64")
    libcurl = formula_opt_prefix("automattic/kandelo-homebrew/libcurl")
    openssl = formula_opt_prefix("automattic/kandelo-homebrew/openssl")
    zlib = formula_opt_prefix("automattic/kandelo-homebrew/zlib")

    kandelo_wasm_build do
      ENV["CPPFLAGS"] = "-I#{libcurl}/include -I#{openssl}/include -I#{zlib}/include"
      ENV["LDFLAGS"] = "-L#{libcurl}/lib -L#{openssl}/lib -L#{zlib}/lib"
      ENV["LIBS"] = "-ldl -pthread"
      ENV["OPENSSL_CFLAGS"] = "-I#{openssl}/include"
      ENV["OPENSSL_LIBS"] = "-L#{openssl}/lib -lssl -lcrypto -ldl -pthread"
      ENV["PKG_CONFIG_LIBDIR"] = [
        libcurl/"lib/pkgconfig",
        openssl/"lib/pkgconfig",
        zlib/"lib/pkgconfig",
      ].join(":")
      ENV.delete("PKG_CONFIG_PATH")
      ENV.delete("PKG_CONFIG_SYSROOT_DIR")

      # Match libcurl's cross-probe results while generating the private
      # configuration headers used by curl's command-line sources.
      ENV["ac_cv_lib_z_gzread"] = "yes"
      ENV["ac_cv_func_SSL_set0_wbio"] = "yes"

      system kandelo_configure, *kandelo_std_configure_args,
        "--disable-shared",
        "--enable-static",
        "--with-openssl=#{openssl}",
        "--with-zlib=#{zlib}",
        "--with-ca-bundle=/etc/ssl/certs/ca-certificates.crt",
        "--without-ca-path",
        "--enable-threaded-resolver",
        "--enable-unix-sockets",
        "--without-brotli",
        "--without-zstd",
        "--without-nghttp2",
        "--without-libidn2",
        "--without-libssh2",
        "--without-librtmp",
        "--without-libpsl",
        "--without-libgsasl",
        "--disable-ldap",
        "--disable-ldaps",
        "--disable-manual",
        "--disable-docs"

      pkgconf = formula_opt_bin("pkgconf")/"pkg-config"
      libcurl_version = Utils.safe_popen_read(pkgconf, "--modversion", "libcurl").strip
      odie "curl #{version} requires libcurl #{version}, found #{libcurl_version}" if libcurl_version != version.to_s
      link_flags = Utils.safe_popen_read(pkgconf, "--static", "--libs", "libcurl").split

      # Upstream's curl target hardcodes its sibling libcurl.la. Build only the
      # CLI and replace that dependency with the installed tap libcurl contract.
      system "make", "-C", "src", "curl", "curl_DEPENDENCIES=", "curl_LDADD=#{link_flags.join(" ")}"

      dependency_paths = [libcurl, openssl, zlib].flat_map do |dependency|
        [dependency, dependency.realpath]
      end.uniq
      kandelo_validate_wasm_artifact(
        buildpath/"src/curl",
        fork:            :forbidden,
        forbidden_paths: dependency_paths,
      )
    end

    kandelo_install_bin(buildpath/"src", "curl", "curl")
  end

  test do
    root = kandelo_require_root!
    version_output = kandelo_run_wasm(bin/"curl", ["--version"])
    assert_match(%r{^curl 8\.11\.1 .* libcurl/8\.11\.1 }, version_output)
    assert_match(%r{ OpenSSL/[0-9]}, version_output)
    assert_match(%r{ zlib/[0-9]}, version_output)
    assert_match(/^Protocols: .*\bfile\b.*\bhttp\b.*\bhttps\b/, version_output)
    assert_match(/^Features: .*\bAsynchDNS\b/, version_output)
    assert_match(/^Features: .*\bSSL\b/, version_output)
    assert_match(/^Features: .*\bUnixSockets\b/, version_output)
    assert_match(/^Features: .*\blibz\b/, version_output)
    assert_match(/^Features: .*\bthreadsafe\b/, version_output)

    write_out = "curl-ok %" + "{http_code} %" + "{ssl_verify_result}\\n"
    ca_bundle = Pathname(root)/"images/rootfs/etc/ssl/cert.pem"
    assert_path_exists ca_bundle
    guest_ca_bundle = "/etc/ssl/certs/ca-certificates.crt"
    output = kandelo_run_wasm(
      bin/"curl",
      [
        "--disable",
        "--fail",
        "--silent",
        "--show-error",
        "--compressed",
        "--http1.1",
        "--tlsv1.2",
        "--tls-max", "1.2",
        "--max-time", "20",
        "--output", "/dev/null",
        "--write-out", write_out,
        "https://example.com/"
      ],
      network:     true,
      guest_files: { guest_ca_bundle => ca_bundle },
    )
    assert_equal "curl-ok 200 0\n", output

    browser_write_out = "curl-browser-ok %" + "{http_code} %" + "{ssl_verify_result}\\n"
    browser_output = kandelo_run_browser_wasm(
      bin/"curl",
      [
        "--disable",
        "--fail",
        "--silent",
        "--show-error",
        "--http1.1",
        "--tlsv1.2",
        "--tls-max", "1.2",
        "--max-time", "30",
        "--output", "/dev/null",
        "--write-out", browser_write_out,
        "https://nghttp2.org/httpbin/status/204"
      ],
    )
    assert_equal "curl-browser-ok 204 0\n", browser_output
  end
end
