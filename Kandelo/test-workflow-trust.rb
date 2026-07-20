#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"

candidate_root = ARGV.shift
abort "usage: test-workflow-trust.rb [candidate-root]" unless ARGV.empty?

ROOT = candidate_root ? File.expand_path(candidate_root) : File.expand_path("..", __dir__)
WORKFLOW_ROOT = File.join(ROOT, ".github/workflows")
CONTRACT_PATH = File.join(WORKFLOW_ROOT, "contract-checks.yml")
BASE_CONTRACT_PATH = File.join(WORKFLOW_ROOT, "base-contract-checks.yml")
EXPECTED_WORKFLOW_FILES = %w[
  base-contract-checks.yml
  contract-checks.yml
].freeze
RETIRED_EXECUTION_EVENTS = %w[
  repository_dispatch
  workflow_call
  workflow_dispatch
].freeze
CHECKOUT_ACTION = "actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0"
RUBY_ACTION = "ruby/setup-ruby@d45b1a4e94b71acab930e56e79c6aa188764e7f9"

def check(condition, message)
  raise message unless condition
end

def load_workflow(path)
  workflow = YAML.safe_load(File.read(path), aliases: false)
  check(workflow.is_a?(Hash), "#{File.basename(path)} is not a workflow mapping")
  workflow
end

def workflow_events(workflow)
  events = workflow.key?("on") ? workflow["on"] : workflow[true]
  check(events.is_a?(Hash), "workflow on: value is not a mapping")
  events
end

def normalized_keys(mapping, label)
  check(mapping.is_a?(Hash), "#{label} is not a mapping")
  keys = mapping.keys.map { |key| key == true ? "on" : key.to_s }
  check(keys.uniq.length == keys.length, "#{label} has ambiguous keys")
  keys
end

def values_for_key(node, wanted, values = [])
  case node
  when Hash
    node.each do |key, value|
      values << value if key.to_s == wanted
      values_for_key(value, wanted, values)
    end
  when Array
    node.each { |value| values_for_key(value, wanted, values) }
  end
  values
end

def exact_permissions?(actual, expected)
  actual.is_a?(Hash) && actual.transform_keys(&:to_s) == expected
end

def expression(source)
  "$" + "{{ #{source} }}"
end

def deep_copy(value)
  Marshal.load(Marshal.dump(value))
end

def expect_rejection(label)
  rejected = false
  begin
    yield
  rescue KeyError, RuntimeError
    rejected = true
  end
  check(rejected, "self-test accepted #{label}")
end

BASE_MATERIALIZE_RUN = <<~'BASH'
  set -euo pipefail
  [[ "$HEAD_REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || {
    echo "::error::invalid pull-request head repository"; exit 2;
  }
  [[ "$HEAD_SHA" =~ ^[0-9a-f]{40}$ ]] || {
    echo "::error::invalid pull-request head SHA"; exit 2;
  }

  candidate_root="$RUNNER_TEMP/tap-contract-candidate"
  rm -rf "$candidate_root"
  tree_json="$RUNNER_TEMP/tap-contract-tree.json"
  gh api --method GET \
    -H "Accept: application/vnd.github+json" \
    "repos/${HEAD_REPOSITORY}/git/trees/${HEAD_SHA}?recursive=1" \
    >"$tree_json"
  jq -e '
    .truncated == false and
    ([.tree[] |
      select(.path | startswith(".github/workflows/")) |
      select(.type != "tree") |
      {path, mode, type}] | sort_by(.path)) == [
        {path: ".github/workflows/base-contract-checks.yml", mode: "100644", type: "blob"},
        {path: ".github/workflows/contract-checks.yml", mode: "100644", type: "blob"}
      ] and
    ([.tree[] |
      select(.path == "Kandelo/test-workflow-trust.rb") |
      {path, mode, type}]) == [
        {path: "Kandelo/test-workflow-trust.rb", mode: "100644", type: "blob"}
      ] and
    ([.tree[] |
      select(.path == "Kandelo/test-workflow-trust.sh") |
      {path, mode, type}]) == [
        {path: "Kandelo/test-workflow-trust.sh", mode: "100755", type: "blob"}
      ]
  ' "$tree_json" >/dev/null || {
    echo "::error::candidate workflow or trust-root file set changed"; exit 2;
  }
  paths=(
    .github/workflows/base-contract-checks.yml
    .github/workflows/contract-checks.yml
    Kandelo/test-workflow-trust.rb
    Kandelo/test-workflow-trust.sh
  )
  for path in "${paths[@]}"; do
    destination="$candidate_root/$path"
    mkdir -p "$(dirname "$destination")"
    gh api --method GET \
      -H "Accept: application/vnd.github.raw+json" \
      "repos/${HEAD_REPOSITORY}/contents/${path}?ref=${HEAD_SHA}" \
      >"$destination"
  done

  for path in "${paths[@]}"; do
    cmp -s "$GITHUB_WORKSPACE/$path" "$candidate_root/$path" || {
      echo "::error::base-owned trust contract changed: $path"; exit 2;
    }
  done
  printf 'KANDELO_TAP_CONTRACT_CANDIDATE=%s\n' "$candidate_root" >>"$GITHUB_ENV"
BASH

def check_workflow_file_set
  actual = Dir.children(WORKFLOW_ROOT).sort
  check(actual == EXPECTED_WORKFLOW_FILES,
        "workflow file set changed: expected #{EXPECTED_WORKFLOW_FILES.inspect}, got #{actual.inspect}")
end

def check_no_publication_authority(workflow, label)
  events = normalized_keys(workflow_events(workflow), "#{label} events")
  retired_events = events & RETIRED_EXECUTION_EVENTS
  check(retired_events.empty?,
        "#{label} exposes retired execution events: #{retired_events.join(', ')}")

  jobs = workflow["jobs"]
  check(jobs.is_a?(Hash), "#{label} jobs are not a mapping")
  jobs.each do |job_name, job|
    check(job.is_a?(Hash), "#{label} job #{job_name} is not a mapping")
    check(!job.key?("uses"),
          "#{label} job #{job_name} delegates authority to a reusable workflow")
  end

  check(values_for_key(workflow, "packages").empty?,
        "#{label} grants GitHub Packages authority")
  check(values_for_key(workflow, "secrets").empty?,
        "#{label} passes repository secrets")
end

def check_contract_workflow(workflow)
  label = "retired tap contract-check workflow"
  check_no_publication_authority(workflow, label)
  check(normalized_keys(workflow, label).sort == %w[jobs name on permissions],
        "#{label} has unexpected top-level configuration")
  check(workflow["name"] == "Retired tap contract checks", "#{label} name changed")

  watched_paths = [
    ".github/workflows/**",
    "Kandelo/test-workflow-trust.sh",
    "Kandelo/test-workflow-trust.rb",
  ]
  check(workflow_events(workflow) == {
    "pull_request" => {},
    "push" => { "branches" => ["main"], "paths" => watched_paths },
  }, "#{label} triggers changed")
  check(exact_permissions?(workflow["permissions"], { "contents" => "read" }),
        "#{label} permissions are not exact")

  jobs = workflow["jobs"]
  check(jobs.keys == ["retired-tap-trust"], "#{label} has an unexpected job set")
  expected_steps = [
    { "uses" => CHECKOUT_ACTION },
    {
      "uses" => RUBY_ACTION,
      "with" => { "ruby-version" => "3.4" },
    },
    {
      "name" => "Validate retired tap trust boundaries",
      "run" => "bash Kandelo/test-workflow-trust.sh",
    },
  ]
  check(jobs.fetch("retired-tap-trust") == {
    "runs-on" => "ubuntu-latest",
    "steps" => expected_steps,
  }, "#{label} job execution contract changed")
  check(values_for_key(workflow, "uses") == [CHECKOUT_ACTION, RUBY_ACTION],
        "#{label} action set or pins changed")
end

def check_base_contract_workflow(workflow)
  label = "base-controlled retired tap check"
  check_no_publication_authority(workflow, label)
  check(normalized_keys(workflow, label).sort == %w[jobs name on permissions],
        "#{label} has unexpected top-level configuration")
  check(workflow["name"] == "Base-controlled retired tap checks", "#{label} name changed")
  check(workflow_events(workflow) == {
    "pull_request_target" => { "branches" => ["main"] },
  }, "#{label} triggers changed")
  check(exact_permissions?(workflow["permissions"], { "contents" => "read" }),
        "#{label} permissions are not exact")

  jobs = workflow["jobs"]
  check(jobs.keys == ["retired-tap-trust-base"], "#{label} has an unexpected job set")
  expected_steps = [
    {
      "uses" => CHECKOUT_ACTION,
      "with" => {
        "ref" => expression("github.event.pull_request.base.sha"),
        "persist-credentials" => false,
      },
    },
    {
      "uses" => RUBY_ACTION,
      "with" => { "ruby-version" => "3.4" },
    },
    {
      "name" => "Materialize candidate trust shell as inert data",
      "shell" => "bash",
      "env" => {
        "GH_TOKEN" => expression("github.token"),
        "HEAD_REPOSITORY" => expression("github.event.pull_request.head.repo.full_name"),
        "HEAD_SHA" => expression("github.event.pull_request.head.sha"),
      },
      "run" => BASE_MATERIALIZE_RUN,
    },
    {
      "name" => "Validate candidate with the base-owned parser",
      "shell" => "bash",
      "run" => 'ruby Kandelo/test-workflow-trust.rb "$KANDELO_TAP_CONTRACT_CANDIDATE"',
    },
  ]
  check(jobs.fetch("retired-tap-trust-base") == {
    "runs-on" => "ubuntu-latest",
    "steps" => expected_steps,
  }, "#{label} job execution contract changed")
  check(values_for_key(workflow, "uses") == [CHECKOUT_ACTION, RUBY_ACTION],
        "#{label} action set or pins changed")
end

def self_test(contract, base_contract)
  expect_rejection("repository_dispatch authority") do
    mutated = deep_copy(contract)
    workflow_events(mutated)["repository_dispatch"] = { "types" => ["publish"] }
    check_no_publication_authority(mutated, "mutated contract")
  end
  expect_rejection("workflow_call authority") do
    mutated = deep_copy(contract)
    workflow_events(mutated)["workflow_call"] = {}
    check_no_publication_authority(mutated, "mutated contract")
  end
  expect_rejection("manual dispatch authority") do
    mutated = deep_copy(contract)
    workflow_events(mutated)["workflow_dispatch"] = {}
    check_no_publication_authority(mutated, "mutated contract")
  end
  expect_rejection("a reusable publication caller") do
    mutated = deep_copy(contract)
    mutated.fetch("jobs")["publish"] = {
      "uses" => "owner/repo/.github/workflows/publish.yml@main",
      "permissions" => { "contents" => "write", "packages" => "write" },
    }
    check_no_publication_authority(mutated, "mutated contract")
  end
  expect_rejection("path-filtered pull-request checks") do
    mutated = deep_copy(contract)
    workflow_events(mutated)["pull_request"] = { "paths" => [".github/workflows/**"] }
    check_contract_workflow(mutated)
  end
  expect_rejection("a write-capable contract check") do
    mutated = deep_copy(contract)
    mutated["permissions"] = { "contents" => "write" }
    check_contract_workflow(mutated)
  end
  expect_rejection("an unpinned setup action") do
    mutated = deep_copy(contract)
    mutated.dig("jobs", "retired-tap-trust", "steps", 1)["uses"] = "ruby/setup-ruby@v1"
    check_contract_workflow(mutated)
  end
  expect_rejection("a disabled contract command") do
    mutated = deep_copy(contract)
    mutated.dig("jobs", "retired-tap-trust", "steps", 2)["run"] = "true"
    check_contract_workflow(mutated)
  end
  expect_rejection("a secret-bearing contract check") do
    mutated = deep_copy(contract)
    mutated.dig("jobs", "retired-tap-trust")["secrets"] = "inherit"
    check_contract_workflow(mutated)
  end
  expect_rejection("a write-capable base-controlled check") do
    mutated = deep_copy(base_contract)
    mutated["permissions"] = { "contents" => "write" }
    check_base_contract_workflow(mutated)
  end
  expect_rejection("checking out pull-request code in the base-controlled check") do
    mutated = deep_copy(base_contract)
    mutated.dig("jobs", "retired-tap-trust-base", "steps", 0, "with")["ref"] =
      expression("github.event.pull_request.head.sha")
    check_base_contract_workflow(mutated)
  end
  expect_rejection("executing the candidate trust parser") do
    mutated = deep_copy(base_contract)
    mutated.dig("jobs", "retired-tap-trust-base", "steps", 3)["run"] =
      'ruby "$KANDELO_TAP_CONTRACT_CANDIDATE/Kandelo/test-workflow-trust.rb"'
    check_base_contract_workflow(mutated)
  end
  expect_rejection("a path-filtered base-controlled check") do
    mutated = deep_copy(base_contract)
    workflow_events(mutated)["pull_request_target"] = {
      "paths" => [".github/workflows/**"],
    }
    check_base_contract_workflow(mutated)
  end
  expect_rejection("a base-controlled check for an unprotected target branch") do
    mutated = deep_copy(base_contract)
    workflow_events(mutated).fetch("pull_request_target")["branches"] = ["release"]
    check_base_contract_workflow(mutated)
  end
end

begin
  check_workflow_file_set
  contract = load_workflow(CONTRACT_PATH)
  base_contract = load_workflow(BASE_CONTRACT_PATH)

  self_test(contract, base_contract)
  check_contract_workflow(contract)
  check_base_contract_workflow(base_contract)
  puts "test-workflow-trust.rb: ok"
rescue KeyError, Psych::Exception, RuntimeError => e
  warn "test-workflow-trust.rb: #{e.message}"
  exit 1
end
