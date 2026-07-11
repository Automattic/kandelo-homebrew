require_relative "../Kandelo/formula_support/kandelo_formula_support"

class Lsof < Formula
  include KandeloFormulaSupport

  desc "Utility to list open files inside Kandelo"
  homepage "https://github.com/lsof-org/lsof"
  url "https://github.com/lsof-org/lsof/archive/refs/tags/4.99.7.tar.gz"
  sha256 "bac1b0acbc50aede42fc97dffaa0b0475e97973e36a6351de5f349c6155afc68"
  license "lsof"

  skip_clean "bin/lsof"

  def install
    kandelo_require_arch!("wasm32")

    kandelo_wasm_build do |root|
      # Kandelo intentionally does not expose Linux AF_PACKET or AF_NETLINK
      # UAPI. Upstream only uses these headers for optional, guarded names.
      inreplace "lib/dialects/linux/dlsof.h" do |s|
        s.gsub! <<~OLD, <<~NEW
          #    include <linux/if_ether.h>
          #    include <linux/netlink.h>
        OLD
          #    if defined(__has_include)
          #        if __has_include(<linux/if_ether.h>)
          #            include <linux/if_ether.h>
          #        endif
          #        if __has_include(<linux/netlink.h>)
          #            include <linux/netlink.h>
          #        endif
          #    else
          #        include <linux/if_ether.h>
          #        include <linux/netlink.h>
          #    endif
        NEW
      end

      include_dir = "#{ENV.fetch("WASM_POSIX_SYSROOT")}/include"
      ENV["LSOF_CC"] = kandelo_cc(root)
      ENV["LINUX_CONF_CC"] = kandelo_cc(root)
      ENV["LSOF_CCV"] = ENV.cc
      ENV["LSOF_INCLUDE"] = include_dir
      ENV["LINUX_INCL"] = include_dir
      ENV["LINUX_VERSION_CODE"] = "393216" # Linux 6.0 procfs compatibility level.
      ENV["LINUX_CLIB"] = "-U__GLIBC__"
      ENV["LSOF_AR"] = "#{kandelo_ar(root)} cr"
      ENV["LSOF_RANLIB"] = kandelo_ranlib(root)
      ENV["LSOF_MAKE"] = "make"

      system "./Configure", "-n", "linux"
      system "make", "-j#{ENV.make_jobs}"
      kandelo_fork_instrument(buildpath/"lsof")
    end

    kandelo_install_bin(buildpath, "lsof", "lsof")
    man8.install "Lsof.8" => "lsof.8"
  end

  test do
    version_output = kandelo_run_wasm(bin/"lsof", ["-v"], merge_stderr: true)
    assert_match(/revision: 4\.99\.7$/, version_output)

    workdir = testpath/"working-directory"
    workdir.mkpath
    fields = kandelo_run_wasm(
      bin/"lsof",
      ["-nP", "-a", "-p", "100", "-d", "cwd,0-2", "-Fpcfnt"],
      env: { "KERNEL_CWD" => workdir },
    )
    assert_match(/^p100$/, fields)
    assert_match(/^clsof\.wasm$/, fields)
    assert_match(/^fcwd\ntDIR\nn#{Regexp.escape(workdir.to_s)}$/, fields)
    assert_match(%r{^f0\nn/dev/stdin$}, fields)
    assert_match(%r{^f1\nn/dev/stdout$}, fields)
    assert_match(%r{^f2\nn/dev/stderr$}, fields)
  end
end
