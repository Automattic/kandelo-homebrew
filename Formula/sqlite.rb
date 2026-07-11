require (Tap.fetch("automattic", "kandelo-homebrew").path/"Kandelo/formula_support/kandelo_formula_support").to_s

class Sqlite < Formula
  include KandeloFormulaSupport

  desc "Embeddable SQL database engine for Kandelo"
  homepage "https://www.sqlite.org/"
  url "https://www.sqlite.org/2025/sqlite-amalgamation-3490100.zip"
  version "3.49.1"
  sha256 "6cebd1d8403fc58c30e93939b246f3e6e58d0765a5cd50546f16c00fd805d2c3"
  license "blessing"

  skip_clean "lib/libsqlite3.a"

  def install
    sqlite_cflags = %w[
      -O2
      -DSQLITE_OMIT_LOAD_EXTENSION
      -DSQLITE_THREADSAFE=1
      -DSQLITE_DEFAULT_SYNCHRONOUS=0
      -DSQLITE_ENABLE_SETLK_TIMEOUT=2
      -DHAVE_PREAD=1
      -DHAVE_PWRITE=1
      -DSQLITE_ENABLE_FTS5
      -DSQLITE_ENABLE_JSON1
      -DSQLITE_ENABLE_MATH_FUNCTIONS
    ]

    kandelo_wasm_build do
      system kandelo_cc, *sqlite_cflags, "-c", "sqlite3.c", "-o", "sqlite3.o"
      system kandelo_ar, "rcs", "libsqlite3.a", "sqlite3.o"
    end

    include.install "sqlite3.h", "sqlite3ext.h"
    lib.install "libsqlite3.a"
    (lib/"pkgconfig").mkpath
    (lib/"pkgconfig/sqlite3.pc").write <<~EOS
      prefix=#{prefix}
      libdir=${prefix}/lib
      includedir=${prefix}/include

      Name: SQLite
      Description: SQL database engine
      Version: #{version}
      Libs: -L${libdir} -lsqlite3
      Cflags: -I${includedir}
    EOS
  end

  test do
    source = testpath/"sqlite-smoke.c"
    wasm = testpath/"sqlite-smoke.wasm"
    source.write <<~C
      #include <stdio.h>
      #include <string.h>
      #include <sqlite3.h>

      int main(void) {
        sqlite3 *db = NULL;
        sqlite3_stmt *stmt = NULL;
        const char *value = NULL;

        if (sqlite3_open(":memory:", &db) != SQLITE_OK) return 1;
        if (sqlite3_exec(db, "CREATE TABLE t(v TEXT); INSERT INTO t VALUES('kandelo');",
                         NULL, NULL, NULL) != SQLITE_OK) return 2;
        if (sqlite3_prepare_v2(db, "SELECT v FROM t", -1, &stmt, NULL) != SQLITE_OK) return 3;
        if (sqlite3_step(stmt) != SQLITE_ROW) return 4;
        value = (const char *)sqlite3_column_text(stmt, 0);
        if (value == NULL || strcmp(value, "kandelo") != 0) return 5;

        sqlite3_finalize(stmt);
        sqlite3_close(db);
        puts("sqlite-ok");
        return 0;
      }
    C

    kandelo_wasm_build do
      system kandelo_cc, source, "-I#{include}", "-L#{lib}", "-lsqlite3", "-lm", "-o", wasm
    end
    assert_equal "sqlite-ok\n", kandelo_run_wasm(wasm, [])
  end
end
