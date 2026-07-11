require_relative "../Kandelo/formula_support/kandelo_formula_support"

class Openssl < Formula
  include KandeloFormulaSupport

  desc "TLS and cryptography library for Kandelo"
  homepage "https://www.openssl.org/"
  url "https://github.com/openssl/openssl/releases/download/openssl-3.3.2/openssl-3.3.2.tar.gz"
  sha256 "2e8a40b01979afe8be0bbfb3de5dc1c6709fedb46d6c89c10da114ab5fc3d281"
  license "Apache-2.0"

  skip_clean "lib/libssl.a"
  skip_clean "lib/libcrypto.a"

  def install
    kandelo_require_arch!("wasm32", "wasm64")
    openssl_target = (kandelo_arch == "wasm64") ? "linux-generic64" : "linux-generic32"

    kandelo_wasm_build do
      # OpenSSL records CC verbatim in libcrypto's build information. PATH
      # already resolves this name through the activated Kandelo SDK.
      ENV["CC"] = "#{kandelo_arch}posix-cc"

      system "perl", "Configure", openssl_target,
        "-DOPENSSL_NO_AFALGENG=1",
        "no-asm",
        "no-dso",
        "no-shared",
        "no-async",
        "no-engine",
        "no-afalgeng",
        "no-tests",
        "no-apps",
        "--prefix=#{prefix}",
        "--libdir=lib",
        "--openssldir=/etc/ssl"

      system "make", "build_generated", "libssl.a", "libcrypto.a"
      system "make", "install_sw"
    end
  end

  test do
    assert_path_exists lib/"libssl.a"
    assert_path_exists lib/"libcrypto.a"
    assert_path_exists include/"openssl/ssl.h"
    assert_path_exists lib/"pkgconfig/libssl.pc"
    assert_path_exists lib/"pkgconfig/libcrypto.pc"

    source = testpath/"openssl-smoke.c"
    wasm = testpath/"openssl-smoke.wasm"
    source.write <<~C
      #include <openssl/crypto.h>
      #include <openssl/evp.h>
      #include <openssl/ssl.h>
      #include <stdio.h>
      #include <string.h>

      int main(void) {
        static const unsigned char expected[] = {
          0x36, 0x37, 0xd0, 0x66, 0x5a, 0xfe, 0x8b, 0x23,
          0x3e, 0xd9, 0x20, 0xca, 0x6f, 0xa0, 0x7c, 0xda,
          0x5c, 0x35, 0xd1, 0x35, 0xd3, 0x56, 0xbb, 0x70,
          0x8a, 0xe4, 0xae, 0xe9, 0x65, 0x56, 0xfc, 0x26,
        };
        static const char expected_compiler[] = "compiler: #{kandelo_arch}posix-cc ";
        unsigned char digest[EVP_MAX_MD_SIZE];
        unsigned int digest_len = 0;
        const char *compiler = OpenSSL_version(OPENSSL_CFLAGS);
        SSL_CTX *ctx = SSL_CTX_new(TLS_client_method());

        if (ctx == NULL) return 1;
        if (EVP_Digest("kandelo", 7, digest, &digest_len, EVP_sha256(), NULL) != 1) return 2;
        if (digest_len != sizeof(expected) || memcmp(digest, expected, sizeof(expected)) != 0) return 3;
        if (strncmp(compiler, expected_compiler, sizeof(expected_compiler) - 1) != 0) return 4;

        SSL_CTX_free(ctx);
        puts("openssl-ok");
        return 0;
      }
    C

    kandelo_wasm_build do
      system kandelo_cc, source, "-I#{include}", "-L#{lib}", "-lssl", "-lcrypto", "-ldl", "-o", wasm
    end
    assert_equal "openssl-ok\n", kandelo_run_wasm(wasm, [])
  end
end
