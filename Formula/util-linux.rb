require (Tap.fetch("automattic", "kandelo-homebrew").path/"Kandelo/formula_support/kandelo_formula_support").to_s

class UtilLinux < Formula
  include KandeloFormulaSupport

  desc "Calendar, priority, and IPC utilities for Kandelo"
  homepage "https://github.com/util-linux/util-linux"
  url "https://mirrors.edge.kernel.org/pub/linux/utils/util-linux/v2.42/util-linux-2.42.2.tar.xz"
  mirror "https://www.kernel.org/pub/linux/utils/util-linux/v2.42/util-linux-2.42.2.tar.xz"
  sha256 "03a05d3adf9602ef128f2da05b84b3205ce60c351e5737c0370f74000679ce8a"
  license all_of: [
    "BSD-3-Clause",
    "BSD-4-Clause-UC",
    "GPL-2.0-only",
    "GPL-2.0-or-later",
    "GPL-3.0-or-later",
    "LGPL-2.1-or-later",
    :public_domain,
  ]

  depends_on "binaryen" => [:build, :test]
  depends_on "wabt" => [:build, :test]

  skip_clean "bin/cal", "bin/ipcrm", "bin/renice"

  def install
    kandelo_require_arch!("wasm32")

    kandelo_wasm_build do |root|
      stable_source = "/usr/src/util-linux-#{version}"
      ENV["CFLAGS"] = [
        "-O2", "-gline-tables-only", "-fdebug-compilation-dir=#{stable_source}",
        "-ffile-prefix-map=#{buildpath}=#{stable_source}",
        "-fdebug-prefix-map=#{buildpath}=#{stable_source}",
        "-fmacro-prefix-map=#{buildpath}=#{stable_source}",
        "-ffile-prefix-map=#{root}=/usr/src/kandelo",
        "-fdebug-prefix-map=#{root}=/usr/src/kandelo",
        "-fmacro-prefix-map=#{root}=/usr/src/kandelo"
      ].join(" ")
      ENV["LC_ALL"] = "C"
      ENV["TZ"] = "UTC"
      ENV["SOURCE_DATE_EPOCH"] = "0"
      ENV["ZERO_AR_DATE"] = "1"
      ENV.delete("PKG_CONFIG_PATH")
      ENV.delete("PKG_CONFIG_LIBDIR")

      # Kandelo executables permit unresolved kernel imports, so link-based
      # Autoconf probes can report absent libc APIs as present. These selected
      # sources either need util-linux's fallback or have no target declaration.
      %w[
        getexecname getsgnam getttynam ntp_gettime rpmatch scandirat
        setprogname strnchr __secure_getenv
      ].each { |function| ENV["ac_cv_func_#{function}"] = "no" }
      ENV["ac_cv_func_secure_getenv"] = "yes"

      system kandelo_configure, *kandelo_std_configure_args,
        "--enable-cal",
        "--enable-ipcrm",
        "--disable-logger",
        "--disable-ipcs",
        "--disable-nls",
        "--disable-asciidoc",
        "--disable-poman",
        "--disable-bash-completion",
        "--disable-libuuid",
        "--disable-liblastlog2",
        "--disable-libblkid",
        "--disable-libmount",
        "--disable-libsmartcols",
        "--disable-libfdisk",
        "--without-systemd",
        "--without-udev",
        "--without-ncursesw",
        "--without-tinfo",
        "--without-readline",
        "--without-cap-ng",
        "--without-libz",
        "--without-libmagic",
        "--without-user",
        "--without-econf",
        "--without-python",
        "--disable-makeinstall-chown",
        "--disable-makeinstall-setuid",
        "--disable-makeinstall-tty-setgid"
      system "make", "-j#{ENV.make_jobs}", "cal", "ipcrm", "renice"

      %w[cal ipcrm renice].each do |program|
        kandelo_validate_wasm_artifact(buildpath/program, fork: :forbidden)
        kandelo_install_bin(buildpath, program, program)
      end
    end

    man1.install "misc-utils/cal.1", "sys-utils/ipcrm.1", "sys-utils/renice.1"
  end

  def caveats
    <<~EOS
      ipcs is not included. Its upstream implementation requires Linux IPC
      enumeration through /proc/sysvipc or IPC_INFO, which Kandelo does not yet
      expose.

      logger is not included. Kandelo's AF_UNIX and loopback UDP receivers are
      currently process-local, so a standalone logger process cannot deliver
      to a Kandelo syslog daemon truthfully.
    EOS
  end

  test do
    %w[cal ipcrm renice].each do |program|
      assert_path_exists bin/program
      assert_path_exists man1/"#{program}.1"
      version_output = kandelo_run_wasm(bin/program, ["--version"])
      assert_match(/from util-linux #{Regexp.escape(version.to_s)}$/, version_output)
      browser_version = kandelo_run_browser_wasm(bin/program, ["--version"])
      assert_match(/from util-linux #{Regexp.escape(version.to_s)}$/, browser_version)
    end

    calendar_args = ["--color=never", "--monday", "2", "2024"]
    calendar = kandelo_run_wasm(bin/"cal", calendar_args)
    assert_match(/^Mo Tu We Th Fr Sa Su$/, calendar)
    assert_match(/^26 27 28 29\s+$/, calendar)
    assert_equal calendar, kandelo_run_browser_wasm(bin/"cal", calendar_args)

    renice_args = ["--priority", "7", "-p", "0"]
    priority = "0 (process ID) old priority 0, new priority 7\n"
    assert_equal priority, kandelo_run_wasm(bin/"renice", renice_args)
    assert_equal priority, kandelo_run_browser_wasm(bin/"renice", renice_args)

    priority_source = testpath/"priority-state.c"
    priority_fixture = testpath/"priority-state.wasm"
    priority_source.write <<~C
      #include <errno.h>
      #include <stdio.h>
      #include <sys/resource.h>

      int main(void) {
        errno = 0;
        int before = getpriority(PRIO_PROCESS, 0);
        if (errno != 0) return 1;
        if (setpriority(PRIO_PROCESS, 0, 7) != 0) return 2;
        errno = 0;
        int after = getpriority(PRIO_PROCESS, 0);
        if (errno != 0 || after != 7) return 3;
        printf("priority-state:%d->%d\\n", before, after);
        return 0;
      }
    C

    denied_source = testpath/"renice-denied.c"
    denied_fixture = testpath/"renice-denied.wasm"
    denied_source.write <<~C
      #include <unistd.h>

      int main(void) {
        if (setuid(1000) != 0) return 125;
        execl("/usr/bin/renice", "renice", "--priority", "-1", "-p", "0", (char *) NULL);
        return 126;
      }
    C

    kandelo_wasm_build do
      system kandelo_cc, "-O2", priority_source, "-o", priority_fixture
      system kandelo_cc, "-O2", denied_source, "-o", denied_fixture
      kandelo_validate_wasm_artifact(priority_fixture, fork: :forbidden)
      kandelo_validate_wasm_artifact(denied_fixture, fork: :forbidden)
    end
    state = "priority-state:0->7\n"
    assert_equal state, kandelo_run_wasm(priority_fixture, [])
    assert_equal state, kandelo_run_browser_wasm(priority_fixture, [])
    denied = kandelo_run_wasm(
      denied_fixture, [],
      exec_programs:   { "/usr/bin/renice" => bin/"renice" },
      expected_status: 1,
      merge_stderr:    true
    )
    assert_match(/failed to set priority for 0 \(process ID\): Operation not permitted/, denied)

    source = testpath/"ipcrm-smoke.c"
    fixture = testpath/"ipcrm-smoke.wasm"
    source.write <<~C
      #include <errno.h>
      #include <stdio.h>
      #include <stdlib.h>
      #include <sys/msg.h>
      #include <sys/sem.h>
      #include <sys/shm.h>
      #include <sys/wait.h>
      #include <unistd.h>

      union semun {
        int val;
        struct semid_ds *buf;
        unsigned short *array;
      };

      int main(void) {
        struct msqid_ds message_status;
        struct shmid_ds shared_status;
        struct semid_ds semaphore_status;
        union semun semaphore_arg = { .buf = &semaphore_status };
        char message_text[32];
        char shared_text[32];
        char semaphore_text[32];
        int queue = msgget(IPC_PRIVATE, IPC_CREAT | 0600);
        if (queue < 0) return 1;
        int shared = shmget(IPC_PRIVATE, 4096, IPC_CREAT | 0600);
        if (shared < 0) return 2;
        int semaphore = semget(IPC_PRIVATE, 1, IPC_CREAT | 0600);
        if (semaphore < 0) return 3;

        pid_t child = fork();
        if (child < 0) return 4;
        if (child == 0) {
          snprintf(message_text, sizeof(message_text), "%d", queue);
          snprintf(shared_text, sizeof(shared_text), "%d", shared);
          snprintf(semaphore_text, sizeof(semaphore_text), "%d", semaphore);
          execl(
            "/usr/bin/ipcrm", "ipcrm",
            "-q", message_text, "-m", shared_text, "-s", semaphore_text,
            (char *) NULL
          );
          _exit(126);
        }

        int child_status = 0;
        if (waitpid(child, &child_status, 0) != child ||
            !WIFEXITED(child_status) || WEXITSTATUS(child_status) != 0) return 5;

        errno = 0;
        if (msgctl(queue, IPC_STAT, &message_status) != -1 || errno != EINVAL) return 6;
        errno = 0;
        if (shmctl(shared, IPC_STAT, &shared_status) != -1 || errno != EINVAL) return 7;
        errno = 0;
        if (semctl(semaphore, 0, IPC_STAT, semaphore_arg) != -1 || errno != EINVAL) return 8;
        puts("ipcrm-removed-msg-shm-sem");
        return 0;
      }
    C
    kandelo_wasm_build do
      system kandelo_cc, "-O2", source, "-o", fixture
      kandelo_fork_instrument(fixture)
      kandelo_validate_wasm_artifact(fixture, fork: :required)
    end
    assert_equal "ipcrm-removed-msg-shm-sem\n",
      kandelo_run_wasm(
        fixture, [],
        exec_programs:             { "/usr/bin/ipcrm" => bin/"ipcrm" },
        expected_fork_descendants: 1
      )

    %w[cal ipcrm renice].each do |program|
      contents = File.binread(bin/program)
      refute_includes contents, prefix.to_s
      refute_includes contents, "/private/tmp/"
      refute_includes contents, "/Users/"
      refute_includes contents, "/nix/store/"
    end
  end
end
