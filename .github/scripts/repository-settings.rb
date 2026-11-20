# ============================================================
# The GitHub settings that guard `main`, kept in this repository (backlog #0-113, ADR-0034).
#
# Until #0-113 they lived only in GitHub's UI, invisible in any diff: one ruleset forbade deleting and
# force-pushing `main`, and nothing required a pull request, a green check or the owner's review, so the
# autopilot's machine account (Write) could push to `main` directly and `gh pr merge --auto` would merge at
# once. The settings are now files under .github/repository-settings/ (an owner-only path, CODEOWNERS):
#
#   rulesets/<name>.json   one repository ruleset each, the request body of GitHub's rulesets API
#                          (name, target, enforcement, conditions, bypass_actors, rules), every
#                          parameter written out, `bypass_actors` too when it is empty
#   environments/<name>.json  one deployment environment each (backlog #0-154, ADR-0035): who may bypass it, its
#                          deployment branch policy and the branches it allows, its protection rules, and the
#                          names of the secrets it holds (never their values: apply writes no secret)
#   repository.json        `settings`: repository settings (`delete_branch_on_merge`, `allow_auto_merge`);
#                          `admins`: the logins with the admin role, the only ones the bypass of `main` and
#                          `tag-creation` (the admin role) reaches, so a new admin would bypass them too;
#                          `writers`: the logins with Write or Maintain, whom the bypass of `branches` and
#                          `renovate` (the role Write) also reaches (backlog #0-272); `repository_secrets`: the
#                          repository-level secrets allowed (none: one of them reaches a run on any branch)
#   apps/<slug>.json       one GitHub App installed on the organization each (backlog #0-272): its `slug`, `app_id`, the
#                          `permissions` and `events` of its installation and its `repository_selection`. Every
#                          installation the organization holds has a file: an app's Contents write reaches every ref no
#                          ruleset covers, and builder-app's confinement to factory/** rests on knowing which apps hold
#                          it (Renovate was found on every repository of the organization, factory included, when
#                          these files were first written, 2026-11-20). Which repositories a `selected` installation
#                          holds is not compared: GitHub lists them only to a token of the app or a user's own token
#                          of an app, not to gh's (tried 2026-11-20); check-app (factory) proves builder-app's.
#
# and this script is the one way between them and GitHub:
#
#   check   (CI: lint-workflows, every pull request and push to main) fails when GitHub's settings and the
#           files differ, in either direction: a ruleset or a parameter changed, added or removed in the UI
#           and not in a file, or a file not applied. Also fails, before asking GitHub anything, on a
#           required check that no job of a workflow running on every pull request to main reports (a
#           renamed job would leave every pull request waiting forever) and on one without its app's
#           `integration_id` (then a status anyone with Write sets through the statuses API satisfies it), and
#           on a required check that is the name of more than one job in any workflow (a run of the other, a
#           push or a manual dispatch on the pull request's branch, reports a check of that name on the same
#           commit), and the other way, on a job of a workflow running on every pull request that no ruleset
#           requires (a red one would not stop a merge, and a required job that needs it reports "skipped",
#           which passes), and on a workflow or job whose token may write checks or statuses (its run could
#           report a required check in the name of GitHub Actions) or that declares none at all (its token is then
#           the repository default, set in the UI); and on a job that reads a secret (`secrets.<NAME>`, other than
#           GITHUB_TOKEN) outside an environment whose file names that secret, or a workflow that gives one to
#           every job (`env:` at the top, `secrets: inherit`). With --main <commit> (CI, on a pull request: main, fetched) it reads the files from that
#           commit, unless the checked-out commit changes them against its first parent (on a pull request,
#           GitHub's merge commit, whose first parent is main): so applying another pull request's change
#           does not leave every open pull request comparing GitHub with its own older copy (review of #0-113).
#   plan    prints what `apply` would change, and changes nothing.
#   apply   makes GitHub match the files: creates and updates the rulesets first and deletes the ones no
#           file names last, so `main` is never without its rules in between; then the repository
#           settings; then `check`, which must pass.
#
# What `check` cannot see with CI's token: a ruleset's `bypass_actors` (GitHub shows them only to an admin,
# so an actor added in the UI goes unnoticed in CI), the repository settings (not in the read-only
# repository response), the admins and the writers (the collaborators list needs more than read), the organization's
# app installations (an organization owner's list), and which secrets exist,
# in the repository and in each environment. `apply` creates and updates environments but never deletes one
# (its secrets would go with it), and never writes a secret: those are the owner's, in Settings. It says so in its
# summary; run by the owner (an admin token), it compares all three, and `plan`/`apply` refuse to run
# without them. `apply` never changes who is an admin: that is the owner's decision, in Settings. Arrays
# are compared as sets (their order means nothing to GitHub). A parameter GitHub adds later fails `check`
# until it is written in its file.
#
# Usage: ruby repository-settings.rb check|plan|apply [--repo <owner/name>] [--root <repository root>]
#        [--main <commit>] (check only)
# (repo: $GITHUB_REPOSITORY, else `gh repo view`). Needs gh with a token (GH_TOKEN in CI); apply needs the
# owner's (admin). Runs on the Ruby of .ruby-version (ADR-0040).
# ============================================================
require 'json'
require 'open3'
require 'psych'
require_relative 'run-blocks'

USAGE = 'usage: repository-settings.rb check|plan|apply [--repo <owner/name>] [--root <repository root>] [--main <commit>]'
RULESET_KEYS = %w[name target enforcement conditions bypass_actors rules].freeze
APP_KEYS = %w[app_id events permissions repository_selection slug].freeze
APP_ACCESS = %w[read write admin].freeze
ENVIRONMENT_KEYS = %w[name can_admins_bypass deployment_branch_policy protection_rules branch_policies secrets].freeze
# The app every required check must come from: GitHub Actions (the app that runs this repository's workflows).
GITHUB_ACTIONS_APP = 15368
# A workflow limited to some pull_request activity types must include these, or a new push reports nothing.
PR_TYPES = %w[opened synchronize reopened].freeze

$errors = 0

def fail!(msg, file: nil)
  puts Annotation.error("#{msg} (backlog #0-113)", file: file)
  $errors += 1
end

def stop!(msg)
  puts Annotation.error("#{msg} (backlog #0-113)")
  exit 1
end

mode = ARGV.shift
stop!(USAGE) unless %w[check plan apply].include?(mode)
opts = {}
until ARGV.empty?
  flag = ARGV.shift
  stop!(USAGE) unless %w[--repo --root --main].include?(flag) && ARGV.first
  opts[flag] = ARGV.shift
end
stop!('--main is for check only: plan and apply apply the working tree') if opts['--main'] && mode != 'check'
ROOT = File.expand_path(opts['--root'] || '.')
DIR = '.github/repository-settings'

# gh api <args>; the parsed JSON body, or nil for an empty one (a DELETE). A failed call ends the run: a
# check that cannot read GitHub has not checked.
def gh(*args, input: nil)
  out, err, status = Open3.capture3('gh', 'api', *args, stdin_data: input.to_s)
  stop!("gh api #{args.join(' ')} failed: #{err.lines.first.to_s.strip}") unless status.success?
  out.strip.empty? ? nil : JSON.parse(out)
rescue SystemCallError => e
  stop!("cannot run gh: #{e.message}")
rescue JSON::ParserError
  stop!("gh api #{args.join(' ')} printed no JSON: #{out.to_s.lines.first.to_s.strip}")
end

def repo_name(opts)
  return opts['--repo'] if opts['--repo']
  return ENV['GITHUB_REPOSITORY'] unless ENV['GITHUB_REPOSITORY'].to_s.empty?
  out, err, status = Open3.capture3('gh', 'repo', 'view', '--json', 'nameWithOwner', '--jq', '.nameWithOwner')
  stop!("cannot tell the repository (--repo, $GITHUB_REPOSITORY or gh repo view): #{err.lines.first.to_s.strip}") unless status.success?
  out.strip
rescue SystemCallError => e
  stop!("cannot run gh: #{e.message}")
end

def rel(path)
  path.sub(%r{\A#{Regexp.escape(ROOT)}/?}, '')
end

# --- the files ---------------------------------------------------------------------------------------

def git(*args)
  out, err, status = Open3.capture3('git', '-C', ROOT, *args)
  stop!("git #{args.join(' ')} failed: #{err.lines.first.to_s.strip}") unless status.success?
  out
rescue SystemCallError => e
  stop!("cannot run git: #{e.message}")
end

# The commit whose files are compared (main's, given by --main), or nil for the working tree: nil when the checked-out
# commit changes the files against its first parent, so a pull request that changes them is checked with its own.
def files_ref(main)
  return nil unless main
  _out, err, status = Open3.capture3('git', '-C', ROOT, 'diff', '--quiet', 'HEAD^1', 'HEAD', '--', DIR)
  return main if status.exitstatus == 0
  return nil if status.exitstatus == 1
  stop!("git diff HEAD^1 HEAD failed (--main needs the checked-out commit's parent: fetch-depth 2): #{err.lines.first.to_s.strip}")
rescue SystemCallError => e
  stop!("cannot run git: #{e.message}")
end

# The JSON files of a directory under DIR (paths from the root), from the working tree (ref nil) or from that commit.
def settings_files(ref, sub)
  dir = "#{DIR}/#{sub}"
  if ref
    # Without -r: the files directly in it, as in the working tree.
    git('ls-tree', '--name-only', ref, '--', "#{dir}/").lines.map(&:strip).select { |f| f.end_with?('.json') }.sort
  else
    Dir.glob(File.join(ROOT, dir, '*.json')).sort.map { |f| rel(f) }
  end
end

def load_json(file, ref)
  JSON.parse(ref ? git('show', "#{ref}:#{file}") : File.read(File.join(ROOT, file)))
rescue SystemCallError, JSON::ParserError => e
  fail!("#{file} cannot be read as JSON: #{e.message.lines.first.to_s.strip}", file: file)
  nil
end

def load_rulesets(ref)
  files = settings_files(ref, 'rulesets')
  stop!("no ruleset file under #{DIR}/rulesets#{ref ? " at #{ref}" : ''}: run from the repository root") if files.empty?
  specs = {}
  files.each do |file|
    spec = load_json(file, ref)
    next unless spec
    unless spec.is_a?(Hash) && (RULESET_KEYS - spec.keys).empty? && (spec.keys - RULESET_KEYS).empty?
      fail!("#{file} must have exactly the keys #{RULESET_KEYS.join(', ')} (bypass_actors too when it is " \
            'empty: no bypass is a decision, written down)', file: file)
      next
    end
    unless spec['name'].is_a?(String) && spec['rules'].is_a?(Array) && spec['bypass_actors'].is_a?(Array)
      fail!("#{file}: name must be a string, rules and bypass_actors arrays", file: file)
      next
    end
    types = spec['rules'].map { |r| r.is_a?(Hash) ? r['type'] : nil }
    if types.include?(nil) || types.uniq.size != types.size
      fail!("#{file}: every rule must be an object with a type, each type once", file: file)
      next
    end
    if specs.key?(spec['name'])
      fail!("#{file}: the ruleset name '#{spec['name']}' is also #{specs[spec['name']][:file]}", file: file)
      next
    end
    specs[spec['name']] = { file: file, spec: spec }
  end
  specs
end

# {name => {file:, spec:}} of environments/*.json; none is fine (a repository without environments).
def load_environments(ref)
  envs = {}
  settings_files(ref, 'environments').each do |file|
    spec = load_json(file, ref)
    next unless spec
    ok = spec.is_a?(Hash) && spec.keys.sort == ENVIRONMENT_KEYS.sort && spec['name'].is_a?(String) &&
         [true, false].include?(spec['can_admins_bypass']) &&
         (spec['deployment_branch_policy'].nil? || spec['deployment_branch_policy'].is_a?(Hash)) &&
         spec['protection_rules'].is_a?(Array) && spec['protection_rules'].all? { |t| t.is_a?(String) } &&
         spec['branch_policies'].is_a?(Array) &&
         spec['branch_policies'].all? { |b| b.is_a?(Hash) && b.keys.sort == %w[name type] } &&
         spec['secrets'].is_a?(Array) && spec['secrets'].all? { |n| n.is_a?(String) && !n.empty? }
    unless ok
      fail!("#{file} must have exactly the keys #{ENVIRONMENT_KEYS.join(', ')}: a name, can_admins_bypass true|false, " \
            'deployment_branch_policy an object or null, protection_rules the rule types, branch_policies ' \
            '[{"name", "type"}], secrets the names it holds', file: file)
      next
    end
    # The name goes into the API paths apply writes with the owner's token: no `/`, no `..` (security review of #0-154).
    unless spec['name'] =~ /\A[A-Za-z0-9_-][A-Za-z0-9._-]*\z/ && !spec['name'].include?('..')
      fail!("#{file}: the environment name '#{spec['name']}' must be letters, digits, '.', '_' or '-'", file: file)
      next
    end
    # apply writes no reviewers and no wait timer, so the only rule a file can name is the branch policy its own
    # custom_branch_policies gives (review of #0-154): anything else would never match GitHub.
    rules = (spec['deployment_branch_policy'] || {})['custom_branch_policies'] ? ['branch_policy'] : []
    unless spec['protection_rules'] == rules
      fail!("#{file}: protection_rules must be #{JSON.generate(rules)}: apply sets no reviewers and no wait timer, and " \
            'a branch_policy rule exactly when custom_branch_policies is true', file: file)
      next
    end
    # An environment that holds a secret is what keeps it from a branch's code (ADR-0035), so it allows main alone
    # and no admin may bypass that (security review of #0-154): the secrets check below trusts every such file.
    main_only = spec['can_admins_bypass'] == false &&
                spec['deployment_branch_policy'] == { 'protected_branches' => false, 'custom_branch_policies' => true } &&
                spec['branch_policies'] == [{ 'name' => 'main', 'type' => 'branch' }]
    if !spec['secrets'].empty? && !main_only
      fail!("#{file}: the environment '#{spec['name']}' holds secrets, so it must allow the branch main alone " \
            '(deployment_branch_policy {"protected_branches": false, "custom_branch_policies": true}, branch_policies ' \
            '[{"name": "main", "type": "branch"}]) and can_admins_bypass false (ADR-0035)', file: file)
      next
    end
    if envs.key?(spec['name'])
      fail!("#{file}: the environment name '#{spec['name']}' is also #{envs[spec['name']][:file]}", file: file)
      next
    end
    envs[spec['name']] = { file: file, spec: spec }
  end
  envs
end

# {settings: {name => boolean}, admins: [login], writers: [login], repository_secrets: [name]}.
# writers: the logins with the role Write or Maintain (not admin), the ones a ruleset's bypass for the role Write
# reaches besides the admins (`branches`, `renovate`; backlog #0-272), so a new one would bypass those too.
def load_repository(ref)
  file = "#{DIR}/repository.json"
  repo = load_json(file, ref)
  empty = { 'settings' => {}, 'admins' => [], 'writers' => [], 'repository_secrets' => [] }
  return empty unless repo
  settings = repo.is_a?(Hash) ? repo['settings'] : nil
  admins = repo.is_a?(Hash) ? repo['admins'] : nil
  writers = repo.is_a?(Hash) ? repo['writers'] : nil
  secrets = repo.is_a?(Hash) ? repo['repository_secrets'] : nil
  unless repo.is_a?(Hash) && repo.keys.sort == %w[admins repository_secrets settings writers] &&
         settings.is_a?(Hash) && !settings.empty? && settings.values.all? { |v| [true, false].include?(v) } &&
         admins.is_a?(Array) && !admins.empty? && admins.all? { |a| a.is_a?(String) && !a.empty? } &&
         writers.is_a?(Array) && writers.all? { |a| a.is_a?(String) && !a.empty? } && (writers & admins).empty? &&
         secrets.is_a?(Array) && secrets.all? { |n| n.is_a?(String) && !n.empty? }
    fail!("#{file} must be {\"settings\": {<name>: true|false, ...}, \"admins\": [<login>, ...], " \
          '"writers": [<login>, ...] (none of them an admin), "repository_secrets": [<name>, ...]}', file: file)
    return empty
  end
  repo
end

# {slug => {file:, spec:}} of apps/*.json (backlog #0-272); none is fine (an organization without apps). The file is
# named after the slug, so one app has one file.
def load_apps(ref)
  apps = {}
  settings_files(ref, 'apps').each do |file|
    spec = load_json(file, ref)
    next unless spec
    perms = spec.is_a?(Hash) ? spec['permissions'] : nil
    unless spec.is_a?(Hash) && spec.keys.sort == APP_KEYS &&
           spec['slug'].is_a?(String) && File.basename(file) == "#{spec['slug']}.json" &&
           spec['app_id'].is_a?(Integer) && spec['app_id'].positive? &&
           perms.is_a?(Hash) && !perms.empty? && perms.values.all? { |v| APP_ACCESS.include?(v) } &&
           spec['events'].is_a?(Array) && spec['events'].all? { |e| e.is_a?(String) && !e.empty? } &&
           %w[selected all].include?(spec['repository_selection'])
      fail!("#{file} must be {\"slug\": <the file's name>, \"app_id\": <id>, \"permissions\": {<name>: " \
            '"read"|"write"|"admin", ...}, "events": [<event>, ...], "repository_selection": "selected"|"all"}',
            file: file)
      next
    end
    apps[spec['slug']] = { file: file, spec: spec }
  end
  apps
end

# Every app a ruleset lets through (a bypass actor of type Integration) is an app with a file under apps/, of that
# app_id (backlog #0-272, review round 1): a wrong id in a ruleset would hand its refs to another app, and `check`
# could not see it, since GitHub holds what the file applied. From the files alone, so CI checks it too.
def check_integrations(specs, apps)
  ids = apps.values.map { |a| a[:spec]['app_id'] }
  specs.each_value do |s|
    s[:spec]['bypass_actors'].each do |actor|
      next unless actor.is_a?(Hash) && actor['actor_type'] == 'Integration'
      next if ids.include?(actor['actor_id'])

      fail!("#{s[:file]}: the bypass actor Integration #{actor['actor_id']} is the app_id of no file under #{DIR}/apps/: " \
            'an app a ruleset lets through is one the organization has installed, written down', file: s[:file])
    end
  end
end

# --- every required check is reported on every pull request, and every such job is required ------------

# [[file, document]] of every workflow, read once for every check below; one that is not YAML is reported here.
def load_workflows
  RunBlocks.workflows(ROOT).map do |path|
    begin
      doc = Psych.safe_load(File.read(path), aliases: true)
      doc.is_a?(Hash) ? [rel(path), doc] : nil
    rescue StandardError => e
      fail!("#{rel(path)} cannot be read as YAML: #{e.message.lines.first.to_s.strip}", file: rel(path))
      nil
    end
  end.compact
end

# The names of the jobs of every workflow, each with its workflow files: [jobs of the workflows that run on
# every pull request to main, jobs of every workflow whatever its trigger].
def workflow_jobs(workflows)
  jobs = Hash.new { |h, k| h[k] = [] }
  every = Hash.new { |h, k| h[k] = [] }
  workflows.each do |file, doc|
    names = (doc['jobs'] || {}).map { |key, job| job.is_a?(Hash) && job['name'] ? job['name'].to_s : key.to_s }
    names.each { |name| every[name] << file }
    # A token with checks: write or statuses: write, in a run on any branch, reports a check or a status in the
    # name of GitHub Actions, which the integration_id of a required check accepts (security review of #0-113).
    scopes = [['the workflow', doc['permissions']]] +
             (doc['jobs'] || {}).map { |key, job| ["job '#{key}'", job.is_a?(Hash) ? job['permissions'] : nil] }
    # A job with no permissions: of its own, in a workflow with none, gets the repository's default token, which
    # only the UI sets: every workflow declares its scope (backlog #0-59), and so the check above sees it.
    if doc['permissions'].nil?
      scopes.drop(1).select { |_, perms| perms.nil? }.each do |where, _|
        fail!("#{file}: #{where} has no permissions: and neither has the workflow, so its token is the " \
              "repository's default, set in the UI and seen by no check (backlog #0-59, ADR-0034)", file: file)
      end
    end
    scopes.each do |where, perms|
      next unless perms == 'write-all' || (perms.is_a?(Hash) && (perms['checks'] == 'write' || perms['statuses'] == 'write'))
      fail!("#{file}: #{where} gives its token checks or statuses write: its run could report a required " \
            "check in the name of GitHub Actions (integration_id #{GITHUB_ACTIONS_APP}) without the job behind " \
            'it (ADR-0034)', file: file)
    end
    # YAML 1.1 reads the key `on` as true.
    on = doc.key?('on') ? doc['on'] : doc[true]
    triggers = on.is_a?(Hash) ? on : Array(on).map { |t| [t, nil] }.to_h
    next unless triggers.key?('pull_request')
    filter = triggers['pull_request'] || {}
    next unless filter.is_a?(Hash)
    # A workflow that skips some pull requests (by path, by a branch filter without main, or by activity types
    # without a new push) reports nothing on them: a check it reports cannot be required.
    next if (filter.keys & %w[paths paths-ignore branches-ignore]).any?
    next if filter.key?('branches') && !Array(filter['branches']).include?('main')
    next if filter.key?('types') && !(PR_TYPES - Array(filter['types'])).empty?
    names.each { |name| jobs[name] << file }
  end
  [jobs, every]
end

def check_required_checks(specs, workflows)
  jobs, every = workflow_jobs(workflows)
  specs.each_value do |s|
    rule = s[:spec]['rules'].find { |r| r['type'] == 'required_status_checks' }
    next unless rule
    Array((rule['parameters'] || {})['required_status_checks']).each do |c|
      context = c['context']
      unless c['integration_id'] == GITHUB_ACTIONS_APP
        fail!("#{s[:file]}: required check '#{context}' must name integration_id #{GITHUB_ACTIONS_APP} " \
              "(GitHub Actions): without it a commit status of that name, which anyone with Write can set " \
              'through the statuses API, satisfies the check', file: s[:file])
      end
      found = jobs[context]
      if found.empty?
        fail!("#{s[:file]}: required check '#{context}' is the name of no job in a workflow that runs on every " \
              'pull request to main: no pull request could ever merge (a renamed job, or a path filter)',
              file: s[:file])
      elsif every[context].size > 1
        fail!("#{s[:file]}: required check '#{context}' is the name of a job in #{every[context].join(' and ')}: " \
              'a run of either (a push, a manual dispatch on the pull request\'s branch) reports a check of that ' \
              'name on the same commit, and one that passes could satisfy it', file: s[:file])
      end
    end
  end
  # And the other way (review of #0-113): every job that runs on every pull request is required. One that is not
  # only advises, and a required job that `needs:` it reports "skipped" when it fails, which a required check accepts.
  required = specs.values.flat_map do |s|
    rule = s[:spec]['rules'].find { |r| r['type'] == 'required_status_checks' }
    rule ? Array((rule['parameters'] || {})['required_status_checks']).map { |c| c['context'] } : []
  end
  (jobs.keys - required).sort.each do |name|
    jobs[name].uniq.each do |file|
      fail!("#{file}: job '#{name}' runs on every pull request to main but is no required check of a ruleset under " \
            "#{DIR}/rulesets: a red run would not stop a merge, and a required job that needs it would report " \
            'skipped and pass (ADR-0034)', file: file)
    end
  end
end

# --- every secret is read inside an environment that holds it (backlog #0-154) -------------------------------

# A repository secret reaches every run of every workflow, a manual dispatch on any branch included, where the
# branch's own scripts and build run next to it. An environment whose deployment branch policy allows main only
# refuses such a run before any step. So a job reads a secret only inside an environment whose file names it.
# The triggers whose run is main's own code when the ref is main. pull_request_target, workflow_run and the like
# also run with main's ref, so the environment's policy lets them in, but they are made to act on a branch's
# code: a job reading a secret is never in such a workflow (security review of #0-154).
SECRET_TRIGGERS = %w[push schedule workflow_dispatch].freeze

def check_workflow_secrets(envs, workflows)
  workflows.each do |file, doc|
    on = doc.key?('on') ? doc['on'] : doc[true]
    other = (on.is_a?(Hash) ? on.keys : Array(on)).map(&:to_s) - SECRET_TRIGGERS
    if other.any? && (doc['jobs'] || {}).values.any? { |job| job.is_a?(Hash) && secrets_used?(job) }
      fail!("#{file}: a job reads a secret in a workflow triggered by #{other.join(', ')}: a job that reads one runs " \
            "only on #{SECRET_TRIGGERS.join(', ')}, the triggers whose run on main is main's own code (ADR-0035)",
            file: file)
    end
    if secrets_used?(doc['env'])
      fail!("#{file}: the workflow's env: gives secrets to every job (#{secret_names(doc['env']).join(', ')}): read a secret in " \
            'the job that needs it, inside its environment (backlog #0-154)', file: file)
    end
    (doc['jobs'] || {}).each do |key, job|
      next unless job.is_a?(Hash)
      if job['secrets'] == 'inherit'
        fail!("#{file}: job '#{key}' passes secrets: inherit, every repository secret: name the ones it needs " \
              '(backlog #0-154)', file: file)
      end
      if expressions(job).any? { |x| x =~ WHOLE_SECRETS }
        fail!("#{file}: job '#{key}' reads secrets as a whole or by index (toJSON(secrets), secrets[...]): write " \
              'secrets.<NAME>, so it can be checked (backlog #0-154)', file: file)
      end
      names = secret_names(job)
      next if names.empty?
      env = job['environment'].is_a?(Hash) ? job['environment']['name'] : job['environment']
      held = envs[env.to_s] ? envs[env.to_s][:spec]['secrets'] : []
      (names - held).each do |name|
        where = env ? "the environment '#{env}', whose file under #{DIR}/environments does not name it" : 'no environment'
        fail!("#{file}: job '#{key}' reads secrets.#{name} in #{where}: a repository secret reaches a manual " \
              'dispatch on any branch, with that branch\'s code (backlog #0-154, ADR-0035)', file: file)
      end
    end
  end
end

# The `${{ }}` expressions in a piece of a workflow: only there does `secrets.` name a secret (a file named
# application-secrets.yml in a script does not).
def expressions(node)
  return [] if node.nil?
  JSON.generate(node).scan(/\$\{\{(.*?)\}\}/m).flatten
end

# The secrets context, not a property of something else (`needs.a.outputs.secrets` is an output named so), in any
# case: GitHub's expressions do not tell `Secrets.X` from `secrets.X`.
SECRET = /(?<![\w.])secrets\s*\.\s*([A-Za-z_][A-Za-z0-9_]*)/i.freeze
# The secrets context used other than as secrets.<NAME>: toJSON(secrets), secrets['X'], every secret at once.
WHOLE_SECRETS = /(?<![\w.])secrets\b(?!\s*\.\s*[A-Za-z_])/i.freeze

# The names of the secrets a piece of a workflow reads, GITHUB_TOKEN aside (the job's own token).
def secret_names(node)
  expressions(node).flat_map { |x| x.scan(SECRET).flatten }.map(&:upcase).uniq.sort - ['GITHUB_TOKEN']
end

# Whether a piece of a workflow reads a secret at all, by name or as a whole.
def secrets_used?(node)
  secret_names(node).any? || expressions(node).any? { |x| x =~ WHOLE_SECRETS }
end

# --- the comparison ----------------------------------------------------------------------------------

# Hashes with sorted keys, arrays sorted: the order of an array means nothing to GitHub here.
def canonical(value)
  case value
  when Hash then value.keys.sort.map { |k| [k, canonical(value[k])] }.to_h
  when Array then value.map { |v| canonical(v) }.sort_by { |v| JSON.generate(v) }
  else value
  end
end

# The rules as {type => parameters}, so a difference is named by its rule.
def by_type(rules)
  Array(rules).map { |r| [r['type'], r['parameters'] || {}] }.to_h
end

def diff(want, got, path, out)
  if want.is_a?(Hash) && got.is_a?(Hash)
    (want.keys | got.keys).sort.each do |k|
      if !got.key?(k)
        out << "#{path}#{k}: in the file, not on GitHub"
      elsif !want.key?(k)
        out << "#{path}#{k}: on GitHub (#{JSON.generate(got[k])}), not in the file"
      else
        diff(want[k], got[k], "#{path}#{k}.", out)
      end
    end
  elsif want != got
    out << "#{path.chomp('.')}: the file says #{JSON.generate(want)}, GitHub #{JSON.generate(got)}"
  end
end

# The differences between a ruleset's file and GitHub's copy, and whether its bypass actors were seen.
def ruleset_diff(spec, live)
  out = []
  keys = %w[target enforcement conditions]
  visible = live.key?('bypass_actors')
  keys << 'bypass_actors' if visible
  want = keys.map { |k| [k, canonical(spec[k])] }.to_h.merge('rules' => canonical(by_type(spec['rules'])))
  got = keys.map { |k| [k, canonical(live[k])] }.to_h.merge('rules' => canonical(by_type(live['rules'])))
  diff(want, got, '', out)
  [out, visible]
end

# A list GitHub answers in pages, read as one page of 100: refused when it may not be all of it, rather than
# compared cut short. key: the field that holds the list (nil: the body is the list).
def one_page(path, key = nil)
  body = gh(path)
  list = key ? (body || {})[key] : body
  stop!("gh api #{path}: no list") unless list.is_a?(Array)
  stop!("gh api #{path}: 100 entries or more, and this script reads one page") if list.size >= 100
  list
end

# GitHub's state against the files: what differs, what this token could not see, and the plan to fix it,
# in the order to apply it: every ruleset a file names is created or updated before any other is deleted, so
# `main` keeps a ruleset at every moment; then the repository settings and the environments.
def compare(repo, specs, repository)
  settings = repository['settings']
  listed = one_page("repos/#{repo}/rulesets?per_page=100")
  live = {}
  listed.each do |r|
    stop!("two rulesets on GitHub are named '#{r['name']}' (ids #{live[r['name']]['id']} and #{r['id']})") if live.key?(r['name'])
    live[r['name']] = r
  end
  # manual: what apply cannot change (an environment no file names, a secret), shown by plan and apply.
  result = { findings: [], hidden: [], actions: [], manual: [] }
  specs.each do |name, s|
    if !live.key?(name)
      result[:findings] << [s[:file], "ruleset '#{name}' is not on GitHub: apply the file (repository-settings.rb apply)"]
      result[:actions] << [:create, name, s[:spec]]
      next
    end
    out, visible = ruleset_diff(s[:spec], gh("repos/#{repo}/rulesets/#{live[name]['id']}"))
    result[:hidden] << "the bypass actors of '#{name}'" unless visible
    next if out.empty?
    out.each { |d| result[:findings] << [s[:file], "ruleset '#{name}' differs from GitHub's: #{d}"] }
    result[:actions] << [:update, name, s[:spec], live[name]['id']]
  end
  (live.keys - specs.keys).sort.each do |name|
    result[:findings] << [nil, "ruleset '#{name}' (id #{live[name]['id']}) is on GitHub but in no file under " \
                               "#{DIR}/rulesets/: changed outside a diff (write it as a file, or apply)"]
    result[:actions] << [:delete, name, nil, live[name]['id']]
  end
  current = gh("repos/#{repo}")
  result[:admin] = (current['permissions'] || {})['admin'] == true
  patch = {}
  settings.each do |key, value|
    if !current.key?(key)
      result[:hidden] << "the repository setting #{key}"
    elsif current[key] != value
      result[:findings] << ["#{DIR}/repository.json", "#{key}: the file says #{value}, GitHub #{current[key]}"]
      patch[key] = value
    end
  end
  result[:actions] << [:patch, nil, patch] unless patch.empty?
  if result[:admin]
    admins = one_page("repos/#{repo}/collaborators?permission=admin&affiliation=all&per_page=100")
    logins = admins.map { |a| a['login'] }.sort
    unless logins == repository['admins'].sort
      result[:admins] = "the admins of #{repo} are #{logins.join(', ')}; the file says " \
                        "#{repository['admins'].sort.join(', ')}: an admin bypasses the ruleset at merge (ADR-0034), " \
                        'so who is one is decided in Settings, Collaborators, then written in the file'
      result[:findings] << ["#{DIR}/repository.json", result[:admins]]
    end
    # permission=push lists everyone who may push, the admins included; the writers are the rest.
    pushers = one_page("repos/#{repo}/collaborators?permission=push&affiliation=all&per_page=100")
    writers = (pushers.map { |a| a['login'] } - logins).sort
    unless writers == repository['writers'].sort
      result[:writers] = "the collaborators of #{repo} with Write or Maintain are " \
                         "#{writers.empty? ? 'none' : writers.join(', ')}; the file says " \
                         "#{repository['writers'].empty? ? 'none' : repository['writers'].sort.join(', ')}: the role " \
                         'Write bypasses the rulesets branches and renovate (backlog #0-272), so who has it is ' \
                         'decided in Settings, Collaborators, then written in the file'
      result[:findings] << ["#{DIR}/repository.json", result[:writers]]
    end
    compare_apps(repo, repository['apps'], result)
  else
    result[:hidden] << "the repository's admins"
    result[:hidden] << "the repository's writers"
    result[:hidden] << "the organization's app installations"
  end
  compare_environments(repo, repository, result)
  result
end

# The organization's app installations against apps/*.json (backlog #0-272), with an admin token. Changed in Settings,
# GitHub Apps only: apply writes none, so each difference is also a step by hand.
def compare_apps(repo, apps, result)
  org = repo.split('/').first
  live = {}
  one_page("orgs/#{org}/installations?per_page=100", 'installations').each do |i|
    live[i['app_slug']] = i
  end
  by_hand = lambda do |file, msg|
    result[:findings] << [file, msg]
    result[:manual] << msg
  end
  (live.keys - apps.keys).sort.each do |slug|
    by_hand.call(nil, "the app '#{slug}' (app id #{live[slug]['app_id']}) is installed on #{org} but in no file " \
                      "under #{DIR}/apps/: an app's Contents write reaches every ref no ruleset covers; uninstall " \
                      'it, or write its file')
  end
  apps.each do |slug, a|
    want = a[:spec]
    got = live[slug]
    unless got
      by_hand.call(a[:file], "the app '#{slug}' is not installed on #{org}: install it as the file says, or remove the file")
      next
    end
    diffs = []
    diffs << "app_id: the file says #{want['app_id']}, GitHub #{got['app_id']}" unless got['app_id'] == want['app_id']
    unless (got['permissions'] || {}).sort == want['permissions'].sort
      diffs << "permissions: the file says #{JSON.generate(want['permissions'].sort.to_h)}, GitHub " \
               "#{JSON.generate((got['permissions'] || {}).sort.to_h)}"
    end
    unless (got['events'] || []).sort == want['events'].sort
      diffs << "events: the file says #{want['events'].sort}, GitHub #{(got['events'] || []).sort}"
    end
    unless got['repository_selection'] == want['repository_selection']
      diffs << "repository_selection: the file says #{want['repository_selection']}, GitHub #{got['repository_selection']}"
    end
    diffs.each do |d|
      by_hand.call(a[:file], "the app '#{slug}' differs from its installation on #{org}: #{d} (change it in the " \
                             "organization's Settings, GitHub Apps, then the file)")
    end
  end
end

# The environments, their branch policies and, with an admin token, the secrets they and the repository hold.
def compare_environments(repo, repository, result)
  envs = repository['environments']
  live = one_page("repos/#{repo}/environments?per_page=100", 'environments').map { |e| [e['name'], e] }.to_h
  envs.each do |name, e|
    spec = e[:spec]
    if !live.key?(name)
      result[:findings] << [e[:file], "environment '#{name}' is not on GitHub: apply the file (repository-settings.rb apply)"]
      result[:actions] << [:environment, name, spec, nil]
      next
    end
    got = live[name]
    policies = []
    if (got['deployment_branch_policy'] || {})['custom_branch_policies']
      policies = one_page("repos/#{repo}/environments/#{name}/deployment-branch-policies?per_page=100", 'branch_policies')
    end
    want = canonical('can_admins_bypass' => spec['can_admins_bypass'],
                     'deployment_branch_policy' => spec['deployment_branch_policy'],
                     'protection_rules' => spec['protection_rules'],
                     'branch_policies' => spec['branch_policies'])
    have = canonical('can_admins_bypass' => got['can_admins_bypass'],
                     'deployment_branch_policy' => got['deployment_branch_policy'],
                     'protection_rules' => Array(got['protection_rules']).map { |r| r['type'] },
                     'branch_policies' => policies.map { |b| { 'name' => b['name'], 'type' => b['type'] } })
    out = []
    diff(want, have, '', out)
    unless out.empty?
      out.each { |d| result[:findings] << [e[:file], "environment '#{name}' differs from GitHub's: #{d}"] }
      result[:actions] << [:environment, name, spec, policies]
    end
  end
  (live.keys - envs.keys).sort.each do |name|
    result[:findings] << [nil, "environment '#{name}' is on GitHub but in no file under #{DIR}/environments/: apply " \
                               'does not delete an environment (its secrets would go with it): write it as a file, ' \
                               'or delete it in Settings, Environments']
    result[:manual] << result[:findings].last[1]
  end
  unless result[:admin]
    envs.each_key { |name| result[:hidden] << "the secrets of environment '#{name}'" }
    result[:hidden] << "the repository's secrets"
    return
  end
  envs.each do |name, e|
    have = live.key?(name) ? one_page("repos/#{repo}/environments/#{name}/secrets?per_page=100", 'secrets').map { |x| x['name'] }.sort : []
    next if have == e[:spec]['secrets'].sort
    result[:findings] << [e[:file], "environment '#{name}' holds the secrets #{have.empty? ? 'none' : have.join(', ')}; " \
                                    "the file says #{e[:spec]['secrets'].sort.join(', ')}: set or remove them in " \
                                    "Settings, Environments, #{name} (apply never writes a secret)"]
    result[:manual] << result[:findings].last[1]
  end
  have = one_page("repos/#{repo}/actions/secrets?per_page=100", 'secrets').map { |x| x['name'] }.sort
  return if have == repository['repository_secrets'].sort
  result[:findings] << ["#{DIR}/repository.json",
                        "the repository holds the secrets #{have.empty? ? 'none' : have.join(', ')}; the file says " \
                        "#{repository['repository_secrets'].empty? ? 'none' : repository['repository_secrets'].sort.join(', ')}: " \
                        'a repository secret reaches a manual dispatch on any branch (backlog #0-154); move it to an ' \
                        'environment, then delete it in Settings, Secrets and variables, Actions']
  result[:manual] << result[:findings].last[1]
end

# --- the modes ----------------------------------------------------------------------------------------

# main: the --main given, ref: the commit whose files were read (nil: the working tree), for the summary.
def check(repo, specs, repository, main: nil, ref: nil)
  result = compare(repo, specs, repository)
  result[:findings].each { |file, msg| fail!(msg, file: file) }
  exit 1 if $errors > 0
  note = result[:hidden].empty? ? '' : " (not visible to this token, so not compared: #{result[:hidden].join(', ')})"
  source = if !main then ''
           elsif ref then " (main's files at #{ref}: this commit does not change them)"
           else " (this commit's files: it changes them)"
           end
  puts "Repository settings: #{specs.size} ruleset(s), #{repository['environments'].size} environment(s), " \
       "#{repository['settings'].size} setting(s), the admins, the writers, #{repository['apps'].size} app(s) and the secrets match #{DIR}/#{source} on #{repo}#{note}."
end

def describe(action)
  kind, name, body, id = action
  case kind
  when :create then "create ruleset '#{name}'"
  when :update then "update ruleset '#{name}' (id #{id})"
  when :delete then "delete ruleset '#{name}' (id #{id}): no file names it"
  when :patch then "set #{body.map { |k, v| "#{k}=#{v}" }.join(', ')}"
  when :environment then "#{id.nil? ? 'create' : 'update'} environment '#{name}' and its branch policies"
  end
end

# Creates or updates an environment (no wait timer, no reviewers: what the file does not name it does not have),
# then makes its branch policies the file's: adds the missing, deletes the others.
def apply_environment(repo, spec, live_policies)
  name = spec['name']
  gh('--method', 'PUT', "repos/#{repo}/environments/#{name}", '--input', '-',
     input: JSON.generate('wait_timer' => 0, 'reviewers' => [], 'can_admins_bypass' => spec['can_admins_bypass'],
                          'deployment_branch_policy' => spec['deployment_branch_policy']))
  return unless (spec['deployment_branch_policy'] || {})['custom_branch_policies']
  live_policies ||= []
  have = live_policies.map { |b| [b['name'], b['type']] }
  want = spec['branch_policies'].map { |b| [b['name'], b['type']] }
  (want - have).each do |n, t|
    gh('--method', 'POST', "repos/#{repo}/environments/#{name}/deployment-branch-policies", '--input', '-',
       input: JSON.generate('name' => n, 'type' => t))
  end
  live_policies.reject { |b| want.include?([b['name'], b['type']]) }.each do |b|
    gh('--method', 'DELETE', "repos/#{repo}/environments/#{name}/deployment-branch-policies/#{b['id']}")
  end
end

def plan(repo, specs, repository, apply:)
  result = compare(repo, specs, repository)
  stop!("plan and apply need a token with admin rights on #{repo} (the owner's)") unless result[:admin]
  unless result[:hidden].empty?
    stop!("this token does not see #{result[:hidden].join(', ')}: plan and apply need the owner's (admin) " \
          'token, or a bypass actor could be changed without being shown')
  end
  stop!("#{result[:admins]}; apply does not change that") if result[:admins]
  stop!("#{result[:writers]}; apply does not change that") if result[:writers]
  actions = result[:actions]
  result[:manual].each { |m| puts "by hand: #{m}" }
  if actions.empty?
    stop!('nothing apply can change; the rest is by hand (above)') unless result[:manual].empty?
    puts "Nothing to change: GitHub's settings on #{repo} match #{DIR}/."
    return
  end
  actions.each do |a|
    puts "#{apply ? 'apply' : 'would'}: #{describe(a)}"
    next unless apply
    kind, _name, body, id = a
    case kind
    when :create then gh('--method', 'POST', "repos/#{repo}/rulesets", '--input', '-', input: JSON.generate(body))
    when :update then gh('--method', 'PUT', "repos/#{repo}/rulesets/#{id}", '--input', '-', input: JSON.generate(body))
    when :delete then gh('--method', 'DELETE', "repos/#{repo}/rulesets/#{id}")
    when :patch then gh('--method', 'PATCH', "repos/#{repo}", '--input', '-', input: JSON.generate(body))
    when :environment then apply_environment(repo, body, id)
    end
  end
  check(repo, specs, repository) if apply
end

ref = files_ref(opts['--main'])
specs = load_rulesets(ref)
repository = load_repository(ref).merge('environments' => load_environments(ref), 'apps' => load_apps(ref))
workflows = load_workflows
check_required_checks(specs, workflows)
check_workflow_secrets(repository['environments'], workflows)
check_integrations(specs, repository['apps'])
exit 1 if $errors > 0
repo = repo_name(opts)
case mode
when 'check' then check(repo, specs, repository, main: opts['--main'], ref: ref)
when 'plan' then plan(repo, specs, repository, apply: false)
when 'apply' then plan(repo, specs, repository, apply: true)
end
