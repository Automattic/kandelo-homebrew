require_relative "../Kandelo/formula_support/kandelo_formula_support"

class Libcxx < Formula
  include KandeloFormulaSupport

  desc "LLVM C++ standard library and ABI runtime for Kandelo"
  homepage "https://libcxx.llvm.org/"
  url "https://github.com/llvm/llvm-project/releases/download/llvmorg-21.1.7/llvm-project-21.1.7.src.tar.xz"
  sha256 "e5b65fd79c95c343bb584127114cb2d252306c1ada1e057899b6aacdd445899e"
  license "Apache-2.0" => { with: "LLVM-exception" }

  depends_on "cmake" => :build

  skip_clean "lib/libc++.a"
  skip_clean "lib/libc++abi.a"
  skip_clean "lib/libc++experimental.a"

  # The register-save assembly files emit no code for Wasm, but include
  # assembly.h before their Wasm guard and use this directive afterward.
  patch :DATA

  def install
    kandelo_require_arch!("wasm32", "wasm64")
    pointer_size = (kandelo_arch == "wasm64") ? 8 : 4

    kandelo_wasm_build do |root|
      cflags = "-O2 -DNDEBUG -fexceptions"

      # Kandelo executables allow unresolved kernel imports, so CMake's
      # check_library_exists cannot distinguish a missing target symbol from a
      # real one. In particular, it reports __cxa_thread_atexit_impl even
      # though Kandelo's libc does not export it. Seed the audited target facts
      # instead of inheriting host or linker-policy false positives.
      system "cmake", "-S", "runtimes", "-B", "build",
        "-DCMAKE_INSTALL_PREFIX=#{prefix}",
        "-DCMAKE_INSTALL_LIBDIR=lib",
        "-DCMAKE_BUILD_TYPE=Release",
        "-DCMAKE_SYSTEM_NAME=Generic",
        "-DCMAKE_SYSTEM_PROCESSOR=#{kandelo_arch}",
        "-DCMAKE_C_COMPILER=#{kandelo_cc(root)}",
        "-DCMAKE_CXX_COMPILER=#{kandelo_tool("c++", root)}",
        "-DCMAKE_AR=#{kandelo_ar(root)}",
        "-DCMAKE_RANLIB=#{kandelo_ranlib(root)}",
        "-DCMAKE_NM=#{kandelo_tool("nm", root)}",
        "-DCMAKE_C_FLAGS=#{cflags}",
        "-DCMAKE_CXX_FLAGS=#{cflags}",
        "-DCMAKE_SIZEOF_VOID_P=#{pointer_size}",
        "-DLLVM_ENABLE_RUNTIMES=libcxx;libcxxabi;libunwind",
        "-DLIBCXX_ENABLE_SHARED=OFF",
        "-DLIBCXX_ENABLE_STATIC=ON",
        "-DLIBCXX_ENABLE_EXCEPTIONS=ON",
        "-DLIBCXX_ENABLE_RTTI=ON",
        "-DLIBCXX_HAS_MUSL_LIBC=ON",
        "-DLIBCXX_HAS_PTHREAD_API=ON",
        "-DLIBCXX_CXX_ABI=libcxxabi",
        "-DLIBCXX_INCLUDE_BENCHMARKS=OFF",
        "-DLIBCXX_INCLUDE_TESTS=OFF",
        "-DLIBCXX_ENABLE_FILESYSTEM=ON",
        "-DLIBCXX_ENABLE_MONOTONIC_CLOCK=ON",
        "-DLIBCXX_ENABLE_RANDOM_DEVICE=ON",
        "-DLIBCXX_ENABLE_LOCALIZATION=ON",
        "-DLIBCXX_ENABLE_WIDE_CHARACTERS=ON",
        "-DLIBCXX_ENABLE_NEW_DELETE_DEFINITIONS=ON",
        "-DLIBCXXABI_ENABLE_SHARED=OFF",
        "-DLIBCXXABI_ENABLE_STATIC=ON",
        "-DLIBCXXABI_ENABLE_EXCEPTIONS=ON",
        "-DLIBCXXABI_USE_LLVM_UNWINDER=ON",
        "-DLIBCXXABI_ENABLE_STATIC_UNWINDER=ON",
        "-DLIBCXXABI_STATICALLY_LINK_UNWINDER_IN_STATIC_LIBRARY=ON",
        "-DLIBCXXABI_ENABLE_THREADS=ON",
        "-DLIBCXXABI_HAS_PTHREAD_API=ON",
        "-DLIBCXXABI_INCLUDE_TESTS=OFF",
        "-DLIBUNWIND_ENABLE_SHARED=OFF",
        "-DLIBUNWIND_ENABLE_STATIC=ON",
        "-DLIBUNWIND_ENABLE_THREADS=ON",
        "-DLIBUNWIND_USE_COMPILER_RT=OFF",
        "-DLIBUNWIND_INCLUDE_TESTS=OFF",
        "-DLIBUNWIND_HIDE_SYMBOLS=ON",
        "-DLIBUNWIND_INSTALL_HEADERS=ON",
        "-DLIBCXX_HAS_GCC_LIB=OFF",
        "-DLIBCXX_HAS_GCC_S_LIB=OFF",
        "-DLIBCXX_HAS_PTHREAD_LIB=ON",
        "-DLIBCXX_HAS_RT_LIB=ON",
        "-DLIBCXX_HAS_ATOMIC_LIB=OFF",
        "-DLIBCXXABI_HAS_C_LIB=ON",
        "-DLIBCXXABI_HAS_GCC_LIB=OFF",
        "-DLIBCXXABI_HAS_GCC_S_LIB=OFF",
        "-DLIBCXXABI_HAS_DL_LIB=ON",
        "-DLIBCXXABI_HAS_PTHREAD_LIB=ON",
        "-DLIBCXXABI_HAS_CXA_THREAD_ATEXIT_IMPL=OFF",
        "-DLIBUNWIND_HAS_C_LIB=ON",
        "-DLIBUNWIND_HAS_GCC_LIB=OFF",
        "-DLIBUNWIND_HAS_GCC_S_LIB=OFF",
        "-DLIBUNWIND_HAS_DL_LIB=ON",
        "-DLIBUNWIND_HAS_PTHREAD_LIB=ON",
        "-DLIBUNWIND_HAS_ROOT_LIB=OFF",
        "-DLIBUNWIND_HAS_BSD_LIB=OFF"

      target_libraries = %w[
        LIBCXX_HAS_GCC_LIB=OFF
        LIBCXX_HAS_GCC_S_LIB=OFF
        LIBCXX_HAS_PTHREAD_LIB=ON
        LIBCXX_HAS_RT_LIB=ON
        LIBCXX_HAS_ATOMIC_LIB=OFF
        LIBCXXABI_HAS_C_LIB=ON
        LIBCXXABI_HAS_GCC_LIB=OFF
        LIBCXXABI_HAS_GCC_S_LIB=OFF
        LIBCXXABI_HAS_DL_LIB=ON
        LIBCXXABI_HAS_PTHREAD_LIB=ON
        LIBCXXABI_HAS_CXA_THREAD_ATEXIT_IMPL=OFF
        LIBUNWIND_HAS_C_LIB=ON
        LIBUNWIND_HAS_GCC_LIB=OFF
        LIBUNWIND_HAS_GCC_S_LIB=OFF
        LIBUNWIND_HAS_DL_LIB=ON
        LIBUNWIND_HAS_PTHREAD_LIB=ON
        LIBUNWIND_HAS_ROOT_LIB=OFF
        LIBUNWIND_HAS_BSD_LIB=OFF
      ]
      cache = (buildpath/"build/CMakeCache.txt").read
      target_libraries.each do |fact|
        variable, expected = fact.split("=", 2)
        entry = cache.each_line.find { |line| line.start_with?("#{variable}:") }
        value = entry ? entry.split("=", 2).last.strip : nil
        next if value == expected

        odie "CMake target-library fact drifted: #{variable}=#{value.inspect}"
      end

      system "cmake", "--build", "build", "--parallel"
      system "cmake", "--install", "build"
    end

    # libc++abi contains the static unwinder; consumers intentionally need only
    # -lc++ -lc++abi, matching Kandelo's existing libcxx package contract.
    rm lib/"libunwind.a"
  end

  test do
    assert_path_exists lib/"libc++.a"
    assert_path_exists lib/"libc++abi.a"
    assert_path_exists lib/"libc++experimental.a"
    assert_path_exists include/"c++/v1/vector"
    assert_path_exists include/"libunwind.h"
    assert_path_exists include/"unwind.h"
    refute_path_exists lib/"libunwind.a"

    source = testpath/"libcxx-smoke.cpp"
    wasm = testpath/"libcxx-smoke.wasm"
    source.write <<~CPP
      #include <exception>
      #include <chrono>
      #include <cstdio>
      #include <filesystem>
      #include <fstream>
      #include <locale>
      #include <random>
      #include <stdexcept>
      #include <string>
      #include <thread>
      #include <vector>

      struct base { virtual ~base() = default; };
      struct derived : base {};

      int main() {
        derived value;
        base* polymorphic = &value;
        const std::filesystem::path path("/tmp/libcxx-ok.txt");
        const std::locale locale("C.UTF-8");
        std::string result;

        if (dynamic_cast<derived*>(polymorphic) == nullptr) return 1;
        {
          std::ofstream output(path);
          if (!output) return 2;
          output << "libcxx-ok";
        }
        if (!std::filesystem::is_regular_file(path)) return 3;
        if (std::filesystem::file_size(path) != 9) return 4;
        if (!std::filesystem::remove(path)) return 5;
        if (!std::use_facet<std::ctype<wchar_t>>(locale).is(std::ctype_base::alpha, L'K')) return 6;

        const auto before = std::chrono::steady_clock::now();
        const auto after = std::chrono::steady_clock::now();
        if (after < before) return 7;

        std::random_device random;
        volatile unsigned int sample = random();
        (void)sample;

        std::thread worker([&result] {
          std::vector<int> values;
          try {
            (void)values.at(0);
          } catch (const std::out_of_range&) {
            result = "libcxx-ok";
          }
        });
        worker.join();
        if (result != "libcxx-ok") return 8;
        std::puts(result.c_str());
        return 0;
      }
    CPP

    kandelo_wasm_build do |root|
      system kandelo_tool("c++", root), source,
        "-fwasm-exceptions", "--kandelo-thread-slots=1",
        "-nostdinc++", "-isystem", include/"c++/v1",
        "-L#{lib}", "-lc++", "-lc++abi", "-o", wasm
    end
    assert_equal "libcxx-ok\n", kandelo_run_wasm(wasm, [])
  end
end

__END__
diff --git a/libunwind/src/assembly.h b/libunwind/src/assembly.h
index 91ee30cd19ce..5c0c45e28179 100644
--- a/libunwind/src/assembly.h
+++ b/libunwind/src/assembly.h
@@ -222 +222,4 @@
-#elif defined(_AIX)
+#elif defined(__wasm__)
+#define NO_EXEC_STACK_DIRECTIVE
+
+#elif defined(_AIX)
