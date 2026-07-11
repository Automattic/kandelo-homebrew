require_relative "../Kandelo/formula_support/kandelo_formula_support"

class Wget < Formula
  include KandeloFormulaSupport

  desc "GNU network file retriever for Kandelo"
  homepage "https://www.gnu.org/software/wget/"
  url "https://ftpmirror.gnu.org/gnu/wget/wget-1.25.0.tar.gz"
  mirror "https://ftp.gnu.org/gnu/wget/wget-1.25.0.tar.gz"
  sha256 "766e48423e79359ea31e41db9e5c289675947a7fcf2efdcedb726ac9d0da3784"
  license "GPL-3.0-or-later"

  depends_on "automattic/kandelo-homebrew/openssl"
  depends_on "automattic/kandelo-homebrew/zlib"

  skip_clean "bin/wget"

  def install
    kandelo_require_arch!("wasm32")
    openssl = formula_opt_prefix("automattic/kandelo-homebrew/openssl")
    zlib = formula_opt_prefix("automattic/kandelo-homebrew/zlib")

    instrumented = buildpath/"src/wget.instrumented"
    kandelo_wasm_build do |root|
      ENV["CPPFLAGS"] = "-I#{openssl}/include -I#{zlib}/include"
      ENV["LDFLAGS"] = "-L#{openssl}/lib -L#{zlib}/lib"
      ENV["OPENSSL_CFLAGS"] = "-I#{openssl}/include"
      ENV["OPENSSL_LIBS"] = "-L#{openssl}/lib -lssl -lcrypto -ldl"
      ENV["ZLIB_CFLAGS"] = "-I#{zlib}/include"
      ENV["ZLIB_LIBS"] = "-L#{zlib}/lib -lz"

      # The SDK site owns target facts; this gnulib runtime probe is package-specific.
      ENV["gl_cv_func_strerror_0_works"] = "yes"

      system kandelo_configure, *kandelo_std_configure_args,
        "--disable-nls",
        "--disable-iri",
        "--disable-pcre",
        "--disable-pcre2",
        "--disable-xattr",
        "--without-libpsl",
        "--without-metalink",
        "--without-libuuid",
        "--with-ssl=openssl"
      system "make", "-j#{ENV.make_jobs}"
      system "#{root}/scripts/run-wasm-fork-instrument.sh", buildpath/"src/wget", "-o", instrumented
    end

    kandelo_install_bin(buildpath/"src", "wget.instrumented", "wget")
  end

  test do
    version_output = kandelo_run_wasm(bin/"wget", ["--version"])
    assert_match(/^GNU Wget 1\.25\.0 /, version_output)
    assert_match(%r{(?:\A|\s)\+ssl/openssl(?:\s|\z)}, version_output)

    page = kandelo_run_wasm(
      bin/"wget",
      [
        "--quiet",
        "--no-hsts",
        "--timeout=20",
        "--tries=1",
        "--output-document=-",
        "https://example.com/",
      ],
      network: true,
    )
    assert_match(%r{<title>Example Domain</title>}, page)

    failure = kandelo_run_wasm(
      bin/"wget",
      [
        "--no-hsts",
        "--timeout=2",
        "--tries=1",
        "--output-document=-",
        "http://127.0.0.1:1/",
      ],
      merge_stderr:    true,
      network:         true,
      expected_status: 4,
    )
    assert_match(/Connection refused/, failure)
  end
end
