#!/usr/bin/env bash
# ============================================================
# Tests .github/scripts/repository-settings.rb (backlog #0-113), offline: gh is a stub on PATH that serves
# GitHub's rulesets and repository settings from a directory of the case (live/), and applies the writes
# `apply` sends to it, so a case can check what GitHub would hold afterwards. One temporary directory per
# case, holding a workflow, two rulesets and the repository settings, which the case then breaks. Every
# case names the message it must give, so a case cannot pass on another rule's refusal.
#
# Run by the lint-workflows job in .github/workflows/ci.yml, before the check; locally:
#   .github/scripts/test-repository-settings.sh
# ============================================================
# The cases write workflows as literal text: `${{ }}` in single quotes is meant (backlog #0-154).
# shellcheck disable=SC2016
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT=$HERE/repository-settings.rb
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
failures=0
n=0
dir=""

# gh stub: `api [--method M] [--input -] <path>` against $GH_STUB_LIVE (rulesets/<id>.json, repo.json, admins.json,
# writers.json: the collaborators with Write, whom permission=push lists after the admins); every
# call is logged as "<METHOD> <path>" in its calls file. GH_STUB_HIDE=bypass,repo hides what only an admin
# sees (setting: one repository setting, from an admin's token too); environments are
# live/environments/<name>.env.json, .policies.json and .secrets.json, the repository's secrets live/repo-secrets.json; GH_STUB_FAIL=<text> fails a call whose path contains it; GH_STUB_NOT_LIST=1 answers the list with an object.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env ruby
require 'json'
live = ENV.fetch('GH_STUB_LIVE')
hide = ENV['GH_STUB_HIDE'].to_s.split(',')
args = ARGV.dup
abort("gh stub: unexpected #{args.join(' ')}") unless args.shift == 'api'
method = 'GET'
input = nil
path = nil
until args.empty?
  a = args.shift
  case a
  when '--method' then method = args.shift
  when '--input' then args.shift; input = JSON.parse($stdin.read)
  else path = a
  end
end
File.open(File.join(live, 'calls'), 'a') { |f| f.puts("#{method} #{path}") }
fail_on = ENV['GH_STUB_FAIL'].to_s
abort('HTTP 502: Bad Gateway') if !fail_on.empty? && path.include?(fail_on)
dir = File.join(live, 'rulesets')
file = ->(id) { File.join(dir, "#{id}.json") }
ids = Dir.glob(File.join(dir, '*.json')).map { |f| File.basename(f, '.json').to_i }.sort
case [method, path]
when ['GET', 'repos/o/r/rulesets?per_page=100']
  (puts '{}'; exit) if ENV['GH_STUB_NOT_LIST']
  puts JSON.generate(ids.map { |id| r = JSON.parse(File.read(file[id])); { 'id' => id, 'name' => r['name'], 'target' => r['target'] } })
when ['GET', 'repos/o/r/collaborators?permission=admin&affiliation=all&per_page=100']
  puts File.read(File.join(live, 'admins.json'))
when ['GET', 'repos/o/r/collaborators?permission=push&affiliation=all&per_page=100']
  # GitHub's push list holds everyone who may push: the admins too.
  puts JSON.generate(JSON.parse(File.read(File.join(live, 'admins.json'))) + JSON.parse(File.read(File.join(live, 'writers.json'))))
when ['GET', 'repos/o/r']
  repo = JSON.parse(File.read(File.join(live, 'repo.json')))
  repo = repo.reject { |k, _| k == 'delete_branch_on_merge' } if hide.include?('setting')
  puts JSON.generate(hide.include?('repo') ? { 'full_name' => 'o/r', 'permissions' => { 'admin' => false } } : repo)
when ['GET', 'repos/o/r/environments?per_page=100']
  envs = Dir.glob(File.join(live, 'environments', '*.env.json')).sort.map { |f| JSON.parse(File.read(f)) }
  puts JSON.generate('total_count' => envs.size, 'environments' => envs)
when ['GET', 'repos/o/r/actions/secrets?per_page=100']
  names = JSON.parse(File.read(File.join(live, 'repo-secrets.json')))
  puts JSON.generate('total_count' => names.size, 'secrets' => names.map { |n| { 'name' => n } })
when ['POST', 'repos/o/r/rulesets']
  id = (ids.max || 99) + 1
  File.write(file[id], JSON.generate(input.merge('id' => id)))
  puts JSON.generate(input.merge('id' => id))
when ['PATCH', 'repos/o/r']
  repo = JSON.parse(File.read(File.join(live, 'repo.json'))).merge(input)
  File.write(File.join(live, 'repo.json'), JSON.generate(repo))
  puts JSON.generate(repo)
else
  env = path[%r{\Arepos/o/r/environments/([^/?]+)}, 1]
  if env
    base = File.join(live, 'environments', env)
    case [method, path.sub(%r{\Arepos/o/r/environments/[^/?]+}, '')]
    when ['GET', '/deployment-branch-policies?per_page=100']
      p = File.exist?("#{base}.policies.json") ? JSON.parse(File.read("#{base}.policies.json")) : []
      puts JSON.generate('total_count' => p.size, 'branch_policies' => p)
    when ['GET', '/secrets?per_page=100']
      names = File.exist?("#{base}.secrets.json") ? JSON.parse(File.read("#{base}.secrets.json")) : []
      puts JSON.generate('total_count' => names.size, 'secrets' => names.map { |n| { 'name' => n } })
    when ['PUT', '']
      rules = (input['deployment_branch_policy'] || {})['custom_branch_policies'] ? [{ 'id' => 1, 'type' => 'branch_policy' }] : []
      e = { 'name' => env, 'can_admins_bypass' => input['can_admins_bypass'], 'protection_rules' => rules,
            'deployment_branch_policy' => input['deployment_branch_policy'] }
      Dir.mkdir(File.join(live, 'environments')) rescue nil
      File.write("#{base}.env.json", JSON.generate(e))
      puts JSON.generate(e)
    when ['POST', '/deployment-branch-policies']
      p = File.exist?("#{base}.policies.json") ? JSON.parse(File.read("#{base}.policies.json")) : []
      p << input.merge('id' => (p.map { |b| b['id'] }.max || 0) + 1)
      File.write("#{base}.policies.json", JSON.generate(p))
      puts JSON.generate(p.last)
    else
      pid = path[%r{/deployment-branch-policies/(\d+)\z}, 1]
      abort("gh stub: unexpected #{method} #{path}") unless method == 'DELETE' && pid
      p = JSON.parse(File.read("#{base}.policies.json")).reject { |b| b['id'] == pid.to_i }
      File.write("#{base}.policies.json", JSON.generate(p))
    end
    exit
  end
  id = path[%r{\Arepos/o/r/rulesets/(\d+)\z}, 1]
  abort("gh stub: unexpected #{method} #{path}") unless id
  abort('HTTP 404: Not Found') unless File.exist?(file[id])
  case method
  when 'GET'
    r = JSON.parse(File.read(file[id]))
    r.delete('bypass_actors') if hide.include?('bypass')
    puts JSON.generate(r)
  when 'PUT'
    File.write(file[id], JSON.generate(input.merge('id' => id.to_i)))
    puts JSON.generate(input)
  when 'DELETE'
    File.delete(file[id])
  end
end
STUB
chmod +x "$WORK/bin/gh"
export PATH="$WORK/bin:$PATH"

# put <file> <line...>: writes the lines into the case's file.
put() {
    local file=$1; shift
    mkdir -p "$(dirname "$dir/$file")"
    printf '%s\n' "$@" > "$dir/$file"
}

# rb <ruby>: runs Ruby in the case's directory (to write or change JSON).
rb() { (cd "$dir" && ruby -rjson -e "$1"); }

# The case's layout: a workflow with two jobs on every pull request, ruleset `checks` requiring both and
# `review` with an admin bypass, the repository settings; and GitHub holding the same (live/), with the
# fields GitHub adds and its arrays in another order.
layout() {
    put .github/workflows/ci.yml 'name: CI' 'on:' '  pull_request:' '    branches: [ main ]' 'permissions: read-all' 'jobs:' \
        '  build:' '    name: Build' '    runs-on: ubuntu-latest' '    steps:' '      - run: echo build' \
        '  lint:' '    runs-on: ubuntu-latest' '    steps:' '      - run: echo lint application-secrets.yml' \
        '        env:' '          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}'
    put .github/workflows/release.yml 'name: Release' 'on: push' 'permissions: read-all' 'jobs:' \
        '  publish:' '    runs-on: ubuntu-latest' '    environment:' '      name: scans' '      deployment: false' \
        '    steps:' '      - run: echo publish' '        env:' '          TOKEN: ${{ secrets.TOKEN }}'
    rb '
      cond = { "ref_name" => { "include" => ["refs/heads/main"], "exclude" => [] } }
      checks = { "name" => "checks", "target" => "branch", "enforcement" => "active", "conditions" => cond,
                 "bypass_actors" => [],
                 "rules" => [{ "type" => "deletion" },
                             { "type" => "required_status_checks", "parameters" => {
                                 "strict_required_status_checks_policy" => false,
                                 "required_status_checks" => [{ "context" => "Build", "integration_id" => 15368 },
                                                              { "context" => "lint", "integration_id" => 15368 }] } }] }
      review = { "name" => "review", "target" => "branch", "enforcement" => "active", "conditions" => cond,
                 "bypass_actors" => [{ "actor_id" => 5, "actor_type" => "RepositoryRole", "bypass_mode" => "pull_request" }],
                 "rules" => [{ "type" => "pull_request", "parameters" => {
                                 "required_approving_review_count" => 0, "require_code_owner_review" => true,
                                 "allowed_merge_methods" => ["merge", "squash"] } }] }
      Dir.mkdir(".github/repository-settings") rescue nil
      Dir.mkdir(".github/repository-settings/rulesets") rescue nil
      Dir.mkdir("live") rescue nil
      Dir.mkdir("live/rulesets") rescue nil
      File.write(".github/repository-settings/rulesets/checks.json", JSON.pretty_generate(checks))
      File.write(".github/repository-settings/rulesets/review.json", JSON.pretty_generate(review))
      File.write(".github/repository-settings/repository.json",
                 JSON.generate("settings" => { "delete_branch_on_merge" => true }, "admins" => ["owner"],
                               "writers" => ["bot"], "repository_secrets" => []))
      Dir.mkdir(".github/repository-settings/environments") rescue nil
      env = { "name" => "scans", "can_admins_bypass" => false,
              "deployment_branch_policy" => { "protected_branches" => false, "custom_branch_policies" => true },
              "protection_rules" => ["branch_policy"], "branch_policies" => [{ "name" => "main", "type" => "branch" }],
              "secrets" => ["TOKEN"] }
      File.write(".github/repository-settings/environments/scans.json", JSON.pretty_generate(env))
      Dir.mkdir("live/environments") rescue nil
      File.write("live/environments/scans.env.json", JSON.generate("id" => 5, "name" => "scans", "can_admins_bypass" => false,
        "protection_rules" => [{ "id" => 9, "node_id" => "x", "type" => "branch_policy" }],
        "deployment_branch_policy" => { "protected_branches" => false, "custom_branch_policies" => true }))
      File.write("live/environments/scans.policies.json", JSON.generate([{ "id" => 3, "node_id" => "y", "name" => "main", "type" => "branch" }]))
      File.write("live/environments/scans.secrets.json", JSON.generate(["TOKEN"]))
      File.write("live/repo-secrets.json", JSON.generate([]))
      extra = { "source_type" => "Repository", "source" => "o/r", "node_id" => "RRS_x",
                "current_user_can_bypass" => "never", "_links" => {}, "created_at" => "2026-10-18T00:00:00Z" }
      [[11, checks], [12, review]].each do |id, r|
        r = Marshal.load(Marshal.dump(r)).merge(extra).merge("id" => id)
        r["rules"].reverse!
        r["rules"].each { |x| (x["parameters"] || {}).each_value { |v| v.reverse! if v.is_a?(Array) } }
        File.write("live/rulesets/#{id}.json", JSON.generate(r))
      end
      File.write("live/repo.json", JSON.generate("full_name" => "o/r", "permissions" => { "admin" => true },
                                                "delete_branch_on_merge" => true, "allow_auto_merge" => false))
      File.write("live/admins.json", JSON.generate([{ "login" => "owner" }]))
      File.write("live/writers.json", JSON.generate([{ "login" => "bot" }]))
    '
}

# live <id> <ruby on r>: changes GitHub's copy of ruleset <id>.
live() { rb "f = \"live/rulesets/$1.json\"; r = JSON.parse(File.read(f)); $2; File.write(f, JSON.generate(r))"; }
# spec <name> <ruby on r>: changes the file of ruleset <name>.
spec() { rb "f = \".github/repository-settings/rulesets/$1.json\"; r = JSON.parse(File.read(f)); $2; File.write(f, JSON.generate(r))"; }
# The parameters of a ruleset's required_status_checks and pull_request rule, as Ruby on r (for live and spec).
P_CHECKS='r["rules"].find { |x| x["type"] == "required_status_checks" }["parameters"]'
P_REVIEW='r["rules"].find { |x| x["type"] == "pull_request" }["parameters"]'

# [MSG=<regex>] [CALLS=<regex the calls must match>] [NOCALLS=<regex they must not>] [MODE=check|plan|apply]
# [ARGS=<more arguments, split on spaces>]
# (the output and the calls are matched as one line, each of their lines ended by ';')
# case_ <expect: pass|fail> <name> <setup command...>
case_() {
    local expect=$1 name=$2; shift 2
    dir="$WORK/case$((n += 1))"
    mkdir -p "$dir"
    layout
    "$@"
    : > "$dir/live/calls"
    local out rc
    set +e
    local extra=()
    read -ra extra <<<"${ARGS:-}"
    out=$(cd "$dir" && GH_STUB_LIVE="$dir/live" ruby "$SCRIPT" "${MODE:-check}" --repo o/r ${extra[@]+"${extra[@]}"} 2>&1)
    rc=$?
    set -e
    # Output and calls on one line each, lines ended by ';', so a pattern can span lines.
    local calls ok=1
    out=$(tr '\n' ';' <<<"$out"); out=${out%;}
    calls=$(tr '\n' ';' < "$dir/live/calls")
    if [ "$expect" = pass ]; then
        [ "$rc" -eq 0 ] && grep -qE -- "${MSG:-match \.github/repository-settings/}" <<<"$out" || ok=0
    else
        [ "$rc" -eq 1 ] && grep -qE "backlog #0-113" <<<"$out" && grep -qE -- "$MSG" <<<"$out" || ok=0
    fi
    if [ -n "${CALLS:-}" ] && ! grep -qE "$CALLS" <<<"$calls"; then ok=0; fi
    if [ -n "${NOCALLS:-}" ] && grep -qE "$NOCALLS" <<<"$calls"; then ok=0; fi
    if [ "$ok" = 1 ]; then
        echo "  ok: $expect - $name"
    else
        echo "::error::expected $expect - $name (exit $rc): $out"$'\n'"calls: $calls"
        failures=$((failures + 1))
    fi
}

as_is() { :; }
hidden() { export GH_STUB_HIDE=bypass,repo; }
setting_hidden() { export GH_STUB_HIDE=setting; }
gh_fails() { export GH_STUB_FAIL=rulesets/12; }
check_dropped() { live 11 "${P_CHECKS}[\"required_status_checks\"].pop"; }
no_code_owners() { live 12 "${P_REVIEW}[\"require_code_owner_review\"] = false"; }
evaluate() { live 11 'r["enforcement"] = "evaluate"'; }
bot_bypass() { live 11 'r["bypass_actors"] << { "actor_id" => 4, "actor_type" => "RepositoryRole", "bypass_mode" => "always" }'; }
github_param() { live 12 "${P_REVIEW}[\"required_reviewers\"] = []"; }
ui_ruleset() { live 11 'r["name"] = "Protect main"'; rb 'File.write("live/rulesets/13.json", File.read("live/rulesets/11.json").sub("Protect main", "checks").sub("\"id\":11", "\"id\":13"))'; }
not_applied() { rm "$dir/live/rulesets/12.json"; }
auto_delete_off() { rb 'r = JSON.parse(File.read("live/repo.json")); r["delete_branch_on_merge"] = false; File.write("live/repo.json", JSON.generate(r))'; }
renamed_job() { sed -i.bak 's/name: Build/name: Build and test/' "$dir/.github/workflows/ci.yml"; }
push_only() { spec checks "${P_CHECKS}[\"required_status_checks\"] << { \"context\" => \"publish\", \"integration_id\" => 15368 }"; }
path_filter() { sed -i.bak 's/    branches: \[ main \]/    paths: [ "src\/**" ]/' "$dir/.github/workflows/ci.yml"; }
other_branch() { sed -i.bak 's/    branches: \[ main \]/    branches: [ release ]/' "$dir/.github/workflows/ci.yml"; }
checks_write() { put .github/workflows/report.yml 'name: Report' 'on: push' 'permissions:' '  checks: write' 'jobs:' '  r:' '    runs-on: ubuntu-latest' '    steps:' '      - run: echo'; }
statuses_job() { put .github/workflows/report.yml 'name: Report' 'on: push' 'jobs:' '  r:' '    runs-on: ubuntu-latest' '    permissions: { statuses: write }' '    steps:' '      - run: echo'; }
write_all() { put .github/workflows/report.yml 'name: Report' 'on: push' 'permissions: write-all' 'jobs:' '  r:' '    runs-on: ubuntu-latest' '    steps:' '      - run: echo'; }
no_permissions() { put .github/workflows/release.yml 'name: Release' 'on: push' 'jobs:' '  publish:' '    runs-on: ubuntu-latest' '    steps:' '      - run: echo publish'; }
job_permissions() { put .github/workflows/release.yml 'name: Release' 'on: push' 'jobs:' '  publish:' '    runs-on: ubuntu-latest' '    permissions: { contents: read }' '    steps:' '      - run: echo publish'; }
# Environments (backlog #0-154). lenv <ruby on e>: changes GitHub's copy of the environment scans.
lenv() { rb "f = \"live/environments/scans.env.json\"; e = JSON.parse(File.read(f)); $1; File.write(f, JSON.generate(e))"; }
env_missing() { rm "$dir/live/environments/scans.env.json" "$dir/live/environments/scans.policies.json"; }
admins_bypass_env() { lenv 'e["can_admins_bypass"] = true'; }
reviewers_env() { lenv 'e["protection_rules"] << { "id" => 10, "type" => "required_reviewers" }'; }
extra_policy() { rb 'f = "live/environments/scans.policies.json"; p = JSON.parse(File.read(f)); p << { "id" => 4, "name" => "feat/*", "type" => "branch" }; File.write(f, JSON.generate(p))'; }
other_env() { rb 'File.write("live/environments/github-pages.env.json", JSON.generate("name" => "github-pages", "can_admins_bypass" => true, "protection_rules" => [], "deployment_branch_policy" => nil))'; }
env_secret_missing() { rb 'File.write("live/environments/scans.secrets.json", JSON.generate([]))'; }
repo_secret() { rb 'File.write("live/repo-secrets.json", JSON.generate(["OLD_TOKEN"]))'; }
bad_env_file() { put .github/repository-settings/environments/scans.json '{ "name": "scans", "secrets": ["TOKEN"] }'; }
# Workflows reading secrets.
secret_no_env() { put .github/workflows/release.yml 'name: Release' 'on: push' 'permissions: read-all' 'jobs:' '  publish:' \
    '    runs-on: ubuntu-latest' '    steps:' '      - run: echo "$T"' '        env:' '          T: ${{ secrets.TOKEN }}'; }
secret_not_held() { put .github/workflows/release.yml 'name: Release' 'on: push' 'permissions: read-all' 'jobs:' '  publish:' \
    '    runs-on: ubuntu-latest' '    environment: scans' '    steps:' '      - run: echo "$T"' '        env:' '          T: ${{ secrets.OTHER }}'; }
secret_top_env() { put .github/workflows/release.yml 'name: Release' 'on: push' 'permissions: read-all' 'env:' '  T: ${{ secrets.TOKEN }}' \
    'jobs:' '  publish:' '    runs-on: ubuntu-latest' '    environment: scans' '    steps:' '      - run: echo'; }
secret_inherit() { put .github/workflows/release.yml 'name: Release' 'on: push' 'permissions: read-all' 'jobs:' '  publish:' \
    '    uses: ./.github/workflows/other.yml' '    secrets: inherit'; }
secret_whole() { put .github/workflows/release.yml 'name: Release' 'on: push' 'permissions: read-all' 'jobs:' '  publish:' \
    '    runs-on: ubuntu-latest' '    steps:' '      - run: echo "$T"' '        env:' '          T: ${{ toJSON(secrets) }}'; }
output_secrets() { put .github/workflows/release.yml 'name: Release' 'on: push' 'permissions: read-all' 'jobs:' '  a:' \
    '    runs-on: ubuntu-latest' '    outputs: { secrets: x }' '    steps:' '      - run: echo' '  publish:' '    needs: a' \
    '    runs-on: ubuntu-latest' '    steps:' '      - run: echo "$T"' '        env:' '          T: ${{ needs.a.outputs.secrets.token }}'; }
any_branch_env() { spec_env 'e["deployment_branch_policy"] = nil; e["branch_policies"] = []; e["protection_rules"] = []'; }
bypassable_env() { spec_env 'e["can_admins_bypass"] = true'; }
feature_branch_env() { spec_env 'e["branch_policies"] << { "name" => "feat/*", "type" => "branch" }'; }
secret_case() { put .github/workflows/release.yml 'name: Release' 'on: push' 'permissions: read-all' 'jobs:' '  publish:' \
    '    runs-on: ubuntu-latest' '    steps:' '      - run: echo "$T"' '        env:' '          T: ${{ Secrets.TOKEN }}'; }
env_twice() { rb 'File.write(".github/repository-settings/environments/copy.json", File.read(".github/repository-settings/environments/scans.json"))'; }
env_no_policies() { lenv 'e["deployment_branch_policy"] = nil; e["protection_rules"] = []'; rm "$dir/live/environments/scans.policies.json"; }
many_policies() { rb 'f = "live/environments/scans.policies.json"; File.write(f, JSON.generate((1..100).map { |i| { "id" => i, "name" => "b#{i}", "type" => "branch" } }))'; }
many_repo_secrets() { rb 'File.write("live/repo-secrets.json", JSON.generate((1..100).map { |i| "S#{i}" }))'; }
secret_on_pr_target() { put .github/workflows/release.yml 'name: Release' 'on: pull_request_target' 'permissions: read-all' 'jobs:' \
    '  publish:' '    runs-on: ubuntu-latest' '    environment: scans' '    steps:' '      - run: echo "$T"' '        env:' \
    '          T: ${{ secrets.TOKEN }}'; }
secret_on_workflow_run() { put .github/workflows/release.yml 'name: Release' 'on:' '  workflow_run:' '    workflows: [ CI ]' \
    'permissions: read-all' 'jobs:' '  publish:' '    runs-on: ubuntu-latest' '    environment: scans' '    steps:' \
    '      - run: echo "$T"' '        env:' '          T: ${{ secrets.TOKEN }}'; }
bad_env_name() { spec_env 'e["name"] = "a/b"'; }
bad_env_rules() { spec_env 'e["protection_rules"] << "required_reviewers"'; }
# spec_env <ruby on e>: changes the file of the environment scans.
spec_env() { rb "f = \".github/repository-settings/environments/scans.json\"; e = JSON.parse(File.read(f)); $1; File.write(f, JSON.generate(e))"; }
secret_index() { put .github/workflows/release.yml 'name: Release' 'on: push' 'permissions: read-all' 'jobs:' '  publish:' \
    '    runs-on: ubuntu-latest' '    environment: scans' '    steps:' '      - run: echo "$T"' '        env:' "          T: \${{ secrets['TOKEN'] }}"; }
unrequired_job() { printf '%s\n' '  e2e:' '    name: End to end' '    runs-on: ubuntu-latest' '    steps:' '      - run: echo e2e' >> "$dir/.github/workflows/ci.yml"; }
some_types() { sed -i.bak 's/    branches: \[ main \]/    types: [ opened, labeled ]/' "$dir/.github/workflows/ci.yml"; }
all_types() { sed -i.bak 's/    branches: \[ main \]/    types: [ opened, synchronize, reopened, labeled ]/' "$dir/.github/workflows/ci.yml"; }
push_twin() { put .github/workflows/release.yml 'name: Release' 'on: push' 'permissions: read-all' 'jobs:' '  lint:' '    runs-on: ubuntu-latest' '    steps:' '      - run: echo'; }
other_admin() { rb 'File.write("live/admins.json", JSON.generate([{ "login" => "owner" }, { "login" => "someone" }]))'; }
other_admin_before() { before; other_admin; }
extra_key() { put .github/repository-settings/repository.json '{ "settings": { "delete_branch_on_merge": true }, "admins": ["owner"], "writers": [], "repository_secrets": [], "teams": [] }'; }
# The writers (backlog #0-272): who the bypass of the role Write reaches besides the admins.
other_writer() { rb 'File.write("live/writers.json", JSON.generate([{ "login" => "bot" }, { "login" => "someone" }]))'; }
other_writer_before() { before; other_writer; }
no_writer() { rb 'File.write("live/writers.json", JSON.generate([]))'; }
# A Maintain collaborator passes `branches` through the role Write's bypass too, so permission=push (which lists it) makes
# it a writer: the script takes every non-admin login of that list, whatever its role_name.
maintain_writer() { rb 'File.write("live/writers.json", JSON.generate([{ "login" => "bot", "role_name" => "maintain" }]))'; }
admin_writer() { rb 'f = ".github/repository-settings/repository.json"; r = JSON.parse(File.read(f)); r["writers"] << "owner"; File.write(f, JSON.generate(r))'; }
no_writers_key() { rb 'f = ".github/repository-settings/repository.json"; r = JSON.parse(File.read(f)); r.delete("writers"); File.write(f, JSON.generate(r))'; }
# A tag ruleset whose bypass holds an app (an Integration) and a role, in another order than the file's: target and
# bypass actors are compared as `renovate`'s are (backlog #0-272).
tag_ruleset() {
    rb '
      t = { "name" => "tags", "target" => "tag", "enforcement" => "active",
            "conditions" => { "ref_name" => { "include" => ["~ALL"], "exclude" => [] } },
            "bypass_actors" => [{ "actor_id" => 2740, "actor_type" => "Integration", "bypass_mode" => "always" },
                                { "actor_id" => 4, "actor_type" => "RepositoryRole", "bypass_mode" => "always" }],
            "rules" => [{ "type" => "deletion" }, { "type" => "update", "parameters" => { "update_allows_fetch_and_merge" => false } }] }
      File.write(".github/repository-settings/rulesets/tags.json", JSON.pretty_generate(t))
      live = t.merge("id" => 13, "source_type" => "Repository", "source" => "o/r")
      live["bypass_actors"] = live["bypass_actors"].reverse
      File.write("live/rulesets/13.json", JSON.generate(live))
    '
}
tag_app_dropped() { tag_ruleset; live 13 'r["bypass_actors"].reject! { |a| a["actor_type"] == "Integration" }'; }
tag_target_branch() { tag_ruleset; live 13 'r["target"] = "branch"'; }
bad_repository() { put .github/repository-settings/repository.json '{ "delete_branch_on_merge": true }'; }
# --main: main is the first commit (the layout), the pull request a second one. commit <message> commits the case.
commit() { git -C "$dir" add -A .; git -C "$dir" -c user.name=t -c user.email=t@example.org commit -qm "$1"; }
main_first() { git -C "$dir" init -q; commit main; }
# The pull request changes something else; the working tree then makes the checks strict, which GitHub's are not,
# so only main's files (HEAD^1) match.
pr_other() { main_first; echo pr > "$dir/README.md"; commit pr; spec checks "${P_CHECKS}[\"strict_required_status_checks_policy\"] = true"; }
# The pull request itself makes them strict: it is checked with its own files, which GitHub does not hold yet.
pr_settings() { main_first; spec checks "${P_CHECKS}[\"strict_required_status_checks_policy\"] = true"; commit pr; }
one_commit() { main_first; }
dup_rule() { spec checks 'r["rules"] << { "type" => "deletion" }'; }
untyped_rule() { spec checks 'r["rules"] << { "parameters" => {} }'; }
many_rulesets() { rb '(13..112).each { |i| File.write("live/rulesets/#{i}.json", JSON.generate("id" => i, "name" => "r#{i}", "rules" => [])) }'; }
same_live_name() { rb 'File.write("live/rulesets/13.json", File.read("live/rulesets/11.json").sub("\"id\":11", "\"id\":13"))'; }
not_a_list() { export GH_STUB_NOT_LIST=1; }
two_jobs() { put .github/workflows/other.yml 'name: Other' 'on: pull_request' 'permissions: read-all' 'jobs:' '  lint:' '    runs-on: ubuntu-latest' '    steps:' '      - run: echo'; }
no_app() { spec checks "${P_CHECKS}[\"required_status_checks\"][0].delete(\"integration_id\")"; }
no_bypass_key() { spec checks 'r.delete("bypass_actors")'; }
same_name() { rb 'File.write(".github/repository-settings/rulesets/copy.json", File.read(".github/repository-settings/rulesets/checks.json"))'; }
not_json() { put .github/repository-settings/rulesets/broken.json '{ "name": '; }
no_rulesets() { rm -rf "$dir/.github/repository-settings"; }
# For plan and apply: GitHub as #0-113 found it, one ruleset made in the UI, auto-delete off.
before() {
    rm "$dir/live/rulesets/"*.json
    rb 'File.write("live/rulesets/7.json", JSON.generate("id" => 7, "name" => "Protect main", "target" => "branch",
          "enforcement" => "active", "bypass_actors" => [], "conditions" => {}, "rules" => [{ "type" => "deletion" }]))'
    auto_delete_off
}
before_hidden() { before; hidden; }

echo "repository-settings: check, what passes"
MSG="2 ruleset\(s\), 1 environment\(s\), 1 setting\(s\), the admins, the writers and the secrets match \.github/repository-settings/ on o/r\.$" \
    case_ pass "GitHub holds the files (its own fields ignored, arrays in another order)" as_is
MSG="not visible to this token, so not compared: the bypass actors of 'checks', the bypass actors of 'review', the repository setting delete_branch_on_merge, the repository's admins, the repository's writers, the secrets of environment 'scans', the repository's secrets" \
    case_ pass "a token that is not an admin's: bypass actors and settings named as not compared" hidden
unset GH_STUB_HIDE
MSG="not visible to this token, so not compared: the repository setting delete_branch_on_merge\)" \
    case_ pass "an admin's token that does not see a setting names it" setting_hidden
unset GH_STUB_HIDE
MSG="match \.github/repository-settings/ on o/r\.$" case_ pass "a pull_request workflow whose types include every new push" all_types
case_ pass "a workflow without permissions whose every job has its own" job_permissions
MSG="match \.github/repository-settings/ \(main's files at HEAD\^1: this commit does not change them\) on o/r\.$" \
    ARGS="--main HEAD^1" case_ pass "--main, a pull request that does not change the files: main's" pr_other

echo "repository-settings: check, what fails"
MSG="ruleset 'checks' differs from GitHub's: rules\.required_status_checks\.required_status_checks: the file says" \
    case_ fail "a required check removed in the UI" check_dropped
MSG="review\.json::ruleset 'review' differs from GitHub's: rules\.pull_request\.require_code_owner_review: the file says true, GitHub false" \
    case_ fail "code owner review turned off in the UI" no_code_owners
MSG="enforcement: the file says \"active\", GitHub \"evaluate\"" case_ fail "a ruleset set to evaluate only" evaluate
MSG="bypass_actors: the file says \[\], GitHub \[\{" case_ fail "a bypass actor added in the UI (admin token)" bot_bypass
MSG="rules\.pull_request\.required_reviewers: on GitHub \(\[\]\), not in the file" case_ fail "a parameter only GitHub has" github_param
MSG="ruleset 'Protect main' \(id 11\) is on GitHub but in no file" case_ fail "a ruleset made in the UI" ui_ruleset
MSG="review\.json::ruleset 'review' is not on GitHub: apply the file" case_ fail "a file never applied" not_applied
MSG="repository\.json::delete_branch_on_merge: the file says true, GitHub false" case_ fail "a repository setting changed in the UI" auto_delete_off
MSG="gh api repos/o/r/rulesets/12 failed: HTTP 502" case_ fail "GitHub cannot be read" gh_fails
unset GH_STUB_FAIL
MSG="required check 'Build' is the name of no job in a workflow that runs on every pull request" \
    NOCALLS=. case_ fail "a required check whose job was renamed (before asking GitHub)" renamed_job
MSG="required check 'publish' is the name of no job" case_ fail "a required check of a push-only workflow" push_only
MSG="required check 'Build' is the name of no job" case_ fail "a required check of a workflow with a path filter" path_filter
MSG="required check 'Build' is the name of no job" case_ fail "a required check of a workflow for another branch" other_branch
MSG="required check 'Build' is the name of no job" case_ fail "a required check of a workflow limited to some activity types" some_types
MSG="file=\.github/workflows/ci\.yml::\.github/workflows/ci\.yml: job 'End to end' runs on every pull request to main but is no required check" \
    NOCALLS=. case_ fail "a job of every pull request that no ruleset requires" unrequired_job
MSG="report\.yml: the workflow gives its token checks or statuses write" NOCALLS=. case_ fail "a workflow whose token may write checks" checks_write
MSG="release\.yml: job 'publish' has no permissions: and neither has the workflow" NOCALLS=. case_ fail "a workflow and job without permissions" no_permissions
MSG="report\.yml: job 'r' gives its token checks or statuses write" case_ fail "a job whose token may write statuses" statuses_job
MSG="report\.yml: the workflow gives its token checks or statuses write" case_ fail "a workflow with write-all" write_all
MSG="required check 'lint' is the name of a job in \.github/workflows/ci\.yml and \.github/workflows/release\.yml: a run of either" \
    case_ fail "a required check that is also the name of a job in a push workflow" push_twin
MSG="repository\.json::the admins of o/r are owner, someone; the file says owner" case_ fail "an admin the file does not name" other_admin
MSG="repository\.json must be \{\"settings\"" case_ fail "repository.json in another form" bad_repository
MSG="repository\.json must be \{\"settings\"" case_ fail "repository.json with a key it does not know" extra_key
MSG="repository\.json::the collaborators of o/r with Write or Maintain are bot, someone; the file says bot: the role Write bypasses" \
    case_ fail "a writer the file does not name (backlog #0-272)" other_writer
MSG="repository\.json::the collaborators of o/r with Write or Maintain are none; the file says bot" case_ fail "a writer the file names, gone on GitHub" no_writer
MSG="2 ruleset\(s\).*the admins, the writers and the secrets match \.github/repository-settings/ on o/r\.$" \
    case_ pass "a writer with the role Maintain is a writer" maintain_writer
MSG="repository\.json must be \{\"settings\".*\(none of them an admin\)" case_ fail "an admin listed as a writer" admin_writer
MSG="repository\.json must be \{\"settings\"" case_ fail "repository.json without writers" no_writers_key
MSG="3 ruleset\(s\).*match \.github/repository-settings/ on o/r\.$" case_ pass "a tag ruleset with an app and a role as bypass, in another order" tag_ruleset
MSG="tags\.json::ruleset 'tags' differs from GitHub's: bypass_actors: the file says" case_ fail "the app's bypass removed in the UI" tag_app_dropped
MSG="tags\.json::ruleset 'tags' differs from GitHub's: target: the file says \"tag\", GitHub \"branch\"" case_ fail "a tag ruleset turned into a branch ruleset" tag_target_branch
MSG="ruleset 'checks' differs from GitHub's: rules\.required_status_checks\.strict_required_status_checks_policy" case_ fail "without --main, the working tree's files" pr_other
MSG="ruleset 'checks' differs from GitHub's: rules\.required_status_checks\.strict_required_status_checks_policy" ARGS="--main HEAD^1" \
    case_ fail "--main, a pull request that changes the files: its own" pr_settings
MSG="git diff HEAD\^1 HEAD failed \(--main needs the checked-out commit's parent" ARGS="--main HEAD" \
    case_ fail "--main without the commit's parent (a shallow checkout)" one_commit
MSG="git ls-tree --name-only nope -- \.github/repository-settings/rulesets/ failed" ARGS="--main nope" case_ fail "--main naming no commit" pr_other
MSG="--main is for check only" MODE=plan ARGS="--main HEAD" case_ fail "--main with plan" as_is
MSG="checks\.json: every rule must be an object with a type, each type once" case_ fail "a rule type twice" dup_rule
MSG="checks\.json: every rule must be an object with a type, each type once" case_ fail "a rule without a type" untyped_rule
MSG="gh api repos/o/r/rulesets\?per_page=100: 100 entries or more" case_ fail "a hundred rulesets on GitHub" many_rulesets
MSG="two rulesets on GitHub are named 'checks' \(ids 11 and 13\)" case_ fail "two rulesets on GitHub with one name" same_live_name
MSG="gh api repos/o/r/rulesets\?per_page=100: no list" case_ fail "GitHub's list is not a list" not_a_list
unset GH_STUB_NOT_LIST
MSG="required check 'lint' is the name of a job in \.github/workflows/ci\.yml and \.github/workflows/other\.yml" \
    case_ fail "a required check two workflows report" two_jobs
MSG="required check 'Build' must name integration_id 15368" case_ fail "a required check from any app" no_app
MSG="checks\.json must have exactly the keys name, target, enforcement, conditions, bypass_actors, rules" \
    case_ fail "a ruleset file without bypass_actors" no_bypass_key
MSG="the ruleset name 'checks' is also" case_ fail "two files with one name" same_name
MSG="broken\.json cannot be read as JSON" case_ fail "a file that is not JSON" not_json
MSG="no ruleset file under \.github/repository-settings/rulesets" case_ fail "no ruleset files (not run from the root)" no_rulesets
MSG="environment 'scans' is not on GitHub: apply the file" case_ fail "an environment never applied" env_missing
MSG="environment 'scans' differs from GitHub's: can_admins_bypass: the file says false, GitHub true" case_ fail "an environment admins may bypass" admins_bypass_env
MSG="environment 'scans' differs from GitHub's: protection_rules: the file says \[\"branch_policy\"\], GitHub" case_ fail "required reviewers added in the UI" reviewers_env
MSG="environment 'scans' differs from GitHub's: branch_policies: the file says" case_ fail "a branch policy added in the UI" extra_policy
MSG="apply: update environment 'scans'.*1 environment\(s\)" MODE=apply \
    CALLS=';PUT repos/o/r/environments/scans;POST repos/o/r/environments/scans/deployment-branch-policies;' \
    case_ pass "apply gives an environment without branch policies its own" env_no_policies
MSG="environment 'github-pages' is on GitHub but in no file under \.github/repository-settings/environments/: apply does not delete" \
    case_ fail "an environment made in the UI" other_env
MSG="environment 'scans' holds the secrets none; the file says TOKEN: set or remove them" case_ fail "an environment without its secret" env_secret_missing
MSG="the repository holds the secrets OLD_TOKEN; the file says none: a repository secret reaches a manual dispatch" \
    case_ fail "a repository secret" repo_secret
MSG="scans\.json must have exactly the keys name, can_admins_bypass" case_ fail "an environment file in another form" bad_env_file
MSG="release\.yml: job 'publish' reads secrets\.TOKEN in no environment: a repository secret reaches" NOCALLS=. \
    case_ fail "a job reading a secret outside an environment" secret_no_env
MSG="release\.yml: job 'publish' reads secrets\.OTHER in the environment 'scans', whose file under" \
    case_ fail "a job reading a secret its environment does not hold" secret_not_held
MSG="release\.yml: the workflow's env: gives secrets to every job \(TOKEN\)" case_ fail "a secret in the workflow's env" secret_top_env
MSG="release\.yml: job 'publish' passes secrets: inherit" case_ fail "secrets: inherit" secret_inherit
MSG="release\.yml: job 'publish' reads secrets as a whole or by index" case_ fail "a secret read by index" secret_index
MSG="release\.yml: job 'publish' reads secrets as a whole or by index" case_ fail "every secret at once, toJSON(secrets)" secret_whole
case_ pass "an output named secrets is no secret" output_secrets
MSG="scans\.json: the environment 'scans' holds secrets, so it must allow the branch main alone" case_ fail "an environment with secrets open to every branch" any_branch_env
MSG="scans\.json: the environment 'scans' holds secrets, so it must allow the branch main alone" case_ fail "an environment with secrets an admin may bypass" bypassable_env
MSG="scans\.json: the environment 'scans' holds secrets, so it must allow the branch main alone" case_ fail "an environment with secrets open to another branch" feature_branch_env
MSG="release\.yml: job 'publish' reads secrets\.TOKEN in no environment" case_ fail "a secret named in another case, Secrets.TOKEN" secret_case
MSG="the environment name 'scans' is also" case_ fail "two environment files with one name" env_twice
MSG="deployment-branch-policies\?per_page=100: 100 entries or more" case_ fail "a hundred branch policies" many_policies
MSG="actions/secrets\?per_page=100: 100 entries or more" case_ fail "a hundred repository secrets" many_repo_secrets
MSG="release\.yml: a job reads a secret in a workflow triggered by pull_request_target" NOCALLS=. \
    case_ fail "a secret read on pull_request_target" secret_on_pr_target
MSG="release\.yml: a job reads a secret in a workflow triggered by workflow_run" case_ fail "a secret read on workflow_run" secret_on_workflow_run
MSG="scans\.json: the environment name 'a/b' must be letters" case_ fail "an environment name that would change an API path" bad_env_name
MSG="scans\.json: protection_rules must be \[\"branch_policy\"\]: apply sets no reviewers" case_ fail "a protection rule apply cannot write" bad_env_rules

echo "repository-settings: plan and apply"
MSG="^would: create ruleset 'checks';would: create ruleset 'review';would: delete ruleset 'Protect main' \(id 7\): no file names it;would: set delete_branch_on_merge=true$" \
    MODE=plan NOCALLS='(^|;)(POST|PUT|PATCH|DELETE) ' case_ pass "plan lists the changes, creates before deletes, and writes nothing" before
MSG="Nothing to change" MODE=apply NOCALLS='(^|;)(POST|PUT|PATCH|DELETE) ' case_ pass "apply when GitHub holds the files writes nothing" as_is
MSG="apply: update ruleset 'review' \(id 12\).*2 ruleset\(s\), 1 environment\(s\), 1 setting\(s\), the admins, the writers and the secrets match" MODE=apply CALLS='PUT repos/o/r/rulesets/12' \
    case_ pass "apply updates a ruleset changed in the UI, in place" no_code_owners
MSG="apply: delete ruleset 'Protect main'.*match \.github/repository-settings/ on o/r\.$" MODE=apply \
    CALLS=';POST repos/o/r/rulesets;POST repos/o/r/rulesets;DELETE repos/o/r/rulesets/7;PATCH repos/o/r;GET ' \
    case_ pass "apply creates, then deletes, then sets, then checks" before
MSG="plan and apply need a token with admin rights on o/r" MODE=apply \
    NOCALLS='(^|;)(POST|PUT|PATCH|DELETE) ' case_ fail "apply without an admin token changes nothing" before_hidden
unset GH_STUB_HIDE
MSG="this token does not see the repository setting delete_branch_on_merge: plan and apply need" MODE=plan \
    NOCALLS='(^|;)(POST|PUT|PATCH|DELETE) ' case_ fail "plan with a setting the admin's token does not see" setting_hidden
unset GH_STUB_HIDE
MSG="apply: create environment 'scans' and its branch policies.*1 environment\(s\)" MODE=apply \
    CALLS=';PUT repos/o/r/environments/scans;POST repos/o/r/environments/scans/deployment-branch-policies;' \
    case_ pass "apply creates an environment and its branch policy" env_missing
MSG="apply: update environment 'scans'.*1 environment\(s\)" MODE=apply \
    CALLS=';PUT repos/o/r/environments/scans;DELETE repos/o/r/environments/scans/deployment-branch-policies/4;' \
    case_ pass "apply removes a branch policy added in the UI" extra_policy
MSG="by hand: environment 'github-pages' is on GitHub but in no file.*nothing apply can change" MODE=apply NOCALLS='DELETE repos/o/r/environments' \
    case_ fail "apply deletes no environment" other_env
MSG="the admins of o/r are owner, someone; the file says owner: .*; apply does not change that" MODE=apply \
    NOCALLS='(^|;)(POST|PUT|PATCH|DELETE) ' case_ fail "apply with an admin the file does not name changes nothing" other_admin_before
MSG="Write or Maintain are bot, someone; the file says bot: .*; apply does not change that" MODE=apply \
    NOCALLS='(^|;)(POST|PUT|PATCH|DELETE) ' case_ fail "apply with a writer the file does not name changes nothing" other_writer_before

if [ "$failures" -gt 0 ]; then
    echo "::error::$failures of $n cases failed (backlog #0-113)"
    exit 1
fi
echo "All $n cases passed."
