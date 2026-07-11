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

    attr_accessor :test_path
    attr_reader :command

    def kandelo_require_root!
      "/tmp/kandelo root"
    end

    def testpath
      test_path || Pathname("/tmp/formula test")
    end

    def shell_output(command)
      @command = command
      "runtime-ok\n"
    end

    def kandelo_record_node_execution!(_wasm_path, _argv); end
  end

  def test_node_execution_receipt_is_optional
    previous = ENV.delete("HOMEBREW_KANDELO_NODE_RECEIPT_PATH")

    assert_nil Harness.new.kandelo_record_node_execution!("program.wasm", [])
  ensure
    ENV["HOMEBREW_KANDELO_NODE_RECEIPT_PATH"] = previous if previous
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
end
