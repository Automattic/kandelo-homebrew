# typed: strict
# frozen_string_literal: true

require "minitest/autorun"
require_relative "../kandelo_formula_support"

# Regression coverage for Formula runtime execution evidence.
class KandeloFormulaSupportTest < Minitest::Test
  class Harness
    include KandeloFormulaSupport
  end

  def test_node_execution_receipt_is_optional
    previous = ENV.delete("HOMEBREW_KANDELO_NODE_RECEIPT_PATH")

    assert_nil Harness.new.kandelo_record_node_execution!("program.wasm", [])
  ensure
    ENV["HOMEBREW_KANDELO_NODE_RECEIPT_PATH"] = previous if previous
  end
end
