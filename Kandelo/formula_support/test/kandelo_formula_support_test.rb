# typed: strict
# frozen_string_literal: true

require "minitest/autorun"
# Standalone Ruby does not preload Homebrew's Pathname helper.
require "pathname" # rubocop:disable Lint/RedundantRequireStatement
require "tmpdir"
require_relative "../kandelo_formula_support"

# Regression coverage for Formula runtime execution evidence.
class KandeloFormulaSupportTest < Minitest::Test
  # Minimal Formula double for command-construction tests.
  class Harness
    include KandeloFormulaSupport

    attr_accessor :build_path, :nix_path, :root_path, :test_path
    attr_reader :command, :expected_status, :recorded_launcher, :system_args

    def kandelo_require_root!
      root_path || "/tmp/kandelo root"
    end

    def testpath
      test_path || Pathname("/tmp/formula test")
    end

    def buildpath
      build_path || testpath
    end

    def kandelo_nix_executable
      nix_path || super
    end

    def shell_output(command, expected_status = 0)
      @command = command
      @expected_status = expected_status
      "runtime-ok\n"
    end

    # The Formula double must intercept Kernel#system under its real name.
    # rubocop:disable Naming/PredicateMethod
    def system(*args)
      @system_args = args
      output = args.fetch(args.index("-o") + 1)
      File.binwrite(output, "instrumented")
      true
    end
    # rubocop:enable Naming/PredicateMethod

    def kandelo_record_node_execution!(_wasm_path, _argv, launcher: "kandelo_run_wasm")
      @recorded_launcher = launcher
      nil
    end
  end

  def test_node_execution_receipt_is_optional
    previous = ENV.delete("HOMEBREW_KANDELO_NODE_RECEIPT_PATH")

    assert_nil Harness.new.kandelo_record_node_execution!("program.wasm", [])
  ensure
    ENV["HOMEBREW_KANDELO_NODE_RECEIPT_PATH"] = previous if previous
  end

  def test_fork_instrumentation_replaces_the_linked_program
    Dir.mktmpdir("kandelo-formula-support") do |dir|
      harness = Harness.new
      wasm = Pathname(dir)/"program.wasm"
      wasm.binwrite("linked")

      assert_equal wasm, harness.kandelo_fork_instrument(wasm)
      assert_equal "instrumented", wasm.binread
      assert_equal "/tmp/kandelo root/scripts/run-wasm-fork-instrument.sh", harness.system_args.first
      assert_equal [wasm.to_s, "-o", "#{wasm}.fork-instrumented"], harness.system_args.drop(1)
      refute File.exist?("#{wasm}.fork-instrumented")
    end
  end

  def test_host_tool_reenters_the_dev_shell_and_preserves_the_caller_directory
    Dir.mktmpdir("kandelo-formula-support") do |dir|
      harness = Harness.new
      harness.build_path = Pathname(dir)/"build"
      harness.build_path.mkpath
      harness.nix_path = Pathname(dir)/"nix profile/bin/nix"
      harness.nix_path.dirname.mkpath
      harness.nix_path.binwrite("#!/bin/sh\n")
      File.chmod(0755, harness.nix_path)

      wrapper = harness.kandelo_host_cxx
      contents = wrapper.read

      assert wrapper.executable?
      assert_includes contents, "export PATH=#{harness.nix_path.dirname.to_s.shellescape}:"
      assert_includes contents, "caller_pwd=$PWD"
      assert_includes contents, "cd /tmp/kandelo\\ root"
      assert_includes contents,
                      'exec ./scripts/dev-shell.sh sh -c \'cd "$1"; shift; exec "$@"\' sh "$caller_pwd" c++ "$@"'
    end
  end

  def test_host_tool_executes_from_the_caller_directory
    Dir.mktmpdir("kandelo-formula-support") do |dir|
      root = Pathname(dir)/"kandelo root"
      caller = Pathname(dir)/"formula build"
      wrapper_dir = Pathname(dir)/"wrappers"
      nix = Pathname(dir)/"nix profile/bin/nix"
      [root/"scripts", caller, wrapper_dir, nix.dirname].each(&:mkpath)
      (root/"scripts/dev-shell.sh").binwrite("#!/bin/sh\nexec \"$@\"\n")
      nix.binwrite("#!/bin/sh\n")
      File.chmod(0755, root/"scripts/dev-shell.sh")
      File.chmod(0755, nix)

      harness = Harness.new
      harness.build_path = wrapper_dir
      harness.nix_path = nix
      harness.root_path = root.to_s
      wrapper = harness.kandelo_host_tool("pwd")

      output = Dir.chdir(caller) { IO.popen([wrapper.to_s], &:read) }

      assert_equal "#{caller.realpath}\n", output
    end
  end

  def test_network_execution_uses_tap_owned_runner
    harness = Harness.new
    output = harness.kandelo_run_wasm(
      "program.wasm", ["a b"], env: { "TOKEN" => "x y" }, network: true
    )

    assert_equal "runtime-ok\n", output
    assert_includes harness.command, "run-network-wasm.ts"
    assert_includes harness.command, "/tmp/kandelo\\ root"
    assert_includes harness.command, "KANDELO_FORMULA_GUEST_ENV_JSON="
    assert_includes harness.command, "KANDELO_FORMULA_ENABLE_NETWORK=1"
    assert_includes harness.command, "TOKEN"
    refute_includes harness.command, "TOKEN=x\\ y"
    assert_includes harness.command, "program.wasm a\\ b"
    refute_includes harness.command, "examples/run-example.ts"
  end

  def test_default_execution_keeps_standard_runner
    harness = Harness.new

    harness.kandelo_run_wasm("program.wasm", [])

    assert_includes harness.command, "examples/run-example.ts"
    refute_includes harness.command, "run-network-wasm.ts"
    refute_includes harness.command, "KANDELO_FORMULA_ENABLE_NETWORK="
  end

  def test_execution_accepts_explicit_guest_exec_programs
    harness = Harness.new

    harness.kandelo_run_wasm(
      "program.wasm",
      [],
      exec_programs: { "/bin/sh" => "/formula/dash" },
    )

    assert_includes harness.command, "run-network-wasm.ts"
    assert_includes harness.command, "KANDELO_FORMULA_EXEC_PROGRAMS_JSON="
    assert_includes harness.command, "/bin/sh"
    assert_includes harness.command, "/formula/dash"
  end

  def test_execution_accepts_explicit_guest_files
    harness = Harness.new

    harness.kandelo_run_wasm(
      "program.wasm",
      [],
      guest_files: { "/etc/service.conf" => "/formula/service.conf" },
    )

    assert_includes harness.command, "run-network-wasm.ts"
    assert_includes harness.command, "KANDELO_FORMULA_GUEST_FILES_JSON="
    assert_includes harness.command, "/etc/service.conf"
    assert_includes harness.command, "/formula/service.conf"
  end

  def test_preserve_argv0_stages_the_original_command_name
    Dir.mktmpdir("kandelo-formula-support") do |dir|
      harness = Harness.new
      harness.test_path = Pathname(dir)/"test"
      harness.test_path.mkpath
      command = Pathname(dir)/"gunzip"
      command.binwrite("\0asm")

      harness.kandelo_run_wasm(command, ["-c"], preserve_argv0: true)

      assert_equal "\0asm", (harness.test_path/"gunzip").binread
      assert_includes harness.command, (harness.test_path/"gunzip").to_s
      refute_includes harness.command, "gunzip.wasm"
      assert_includes harness.command, "run-network-wasm.ts"
      assert_includes harness.command, "KANDELO_FORMULA_ENABLE_NETWORK=0"
    end
  end

  def test_execution_accepts_an_expected_nonzero_status
    harness = Harness.new

    output = harness.kandelo_run_wasm("program.wasm", ["missing"], expected_status: 2)

    assert_equal "runtime-ok\n", output
    assert_equal 2, harness.expected_status
  end

  def test_pty_execution_uses_tap_owned_runner
    harness = Harness.new
    output = harness.kandelo_run_pty_wasm(
      "program.wasm", ["note.txt"],
      env:               { "KERNEL_CWD" => "/tmp/formula test" },
      inputs:            ["\u001c", "beta", "\r"],
      rerun_inputs:      ["\u0018"],
      guest_files:       { "/etc/program.conf" => "/formula/program.conf" },
      guest_directories: ["/home/linuxbrew/.linuxbrew/var/program/save"],
      writable_guest_directories: ["/home/linuxbrew/.linuxbrew/var/program"]
    )

    assert_equal "runtime-ok\n", output
    assert_includes harness.command, "run-pty-wasm.ts"
    assert_includes harness.command, "KANDELO_FORMULA_PTY_CONFIG_JSON="
    assert_includes harness.command, "note.txt"
    assert_includes harness.command, "beta"
    assert_includes harness.command, "rerunInputs"
    assert_includes harness.command, "/etc/program.conf"
    assert_includes harness.command, "/home/linuxbrew/.linuxbrew/var/program"
    assert_includes harness.command, "writableGuestDirectories"
    assert_includes harness.command, "program.wasm"
    assert_equal "kandelo_run_pty_wasm", harness.recorded_launcher
  end
end
