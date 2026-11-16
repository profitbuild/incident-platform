# ============================================================
# Every hook entry of the factory blocks the call when its hook fails (backlog #0-162 PR 2, ADR-0039).
#
# Claude Code runs a call after a hook that exits other than 0 or 2, one that cannot start (missing, not
# executable) and one that times out: a non-blocking error. The scripts already turn every failure they can see
# into exit 2 (#0-162 PR 1, the fail-closed table of .claude/hooks/test-hooks.sh); a hook that never starts sees
# nothing, and only Claude Code's `"onFailure": "block"` on the entry stops the call then (v2.1.295 or later; an
# older version ignores the field without a word, spike of 2026-10-25, so preflight.sh refuses one). This checks,
# in .claude/settings.json, .claude/settings.autopilot.json and the frontmatter of every agent, skill and command
# under .claude/ (subdirectories too: Claude Code scans .claude/agents/ recursively), for every entry of every event:
#   1. it is a `command` hook with `onFailure: "block"`, not run in the background (`async`/`asyncRewake`, which
#      the field does not apply to, per the hooks reference);
#   2. its command is `"$CLAUDE_PROJECT_DIR"/.claude/hooks/<name>.sh [arguments without shell syntax]`, an
#      executable file there,
#      with a row in test-hooks.sh's FAILS_CLOSED table (that table proves the hook exits 2 when it fails; the
#      test fails a hook of the directory without a row, this one a hook that is wired but not in the table);
#   3. neither settings file sets `disableAllHooks`;
#   4. every guard an agent's frontmatter runs has its session-level twin in both settings files (backlog #0-164,
#      ADR-0041): the same hook, on the same matcher, with the same arguments after `--agent <names>`, whose names
#      are exactly the agents whose frontmatter runs it, so every hook a frontmatter uses as a guard must accept
#      `--agent` (frontmatter hooks are documented for agents of the Agent
#      tool, not for the agents a Workflow spawns; a twin keyed on agent_type covers those). A frontmatter hook
#      takes no `--agent`; a twin naming an agent whose frontmatter has no such guard is stale;
#   5. every session-level guard of REQUIRED below is wired in its settings file, on a matcher that covers its
#      tools (#0-164 AC4): a deleted entry, or one moved to another matcher, would pass the rules above.
#   6. every agent whose `tools:` holds Bash runs a Bash guard in its frontmatter (readonly-bash.sh or
#      factory-ops-bash.sh) on a matcher that covers Bash, and every agent holding Edit, Write, MultiEdit or
#      NotebookEdit runs write-scope.sh on a matcher that covers each of them; an agent whose `tools:` names
#      no tool (absent, empty) holds them all, and `Bash(git:*)` is Bash. No two definitions share a `name:`.
#      The only exceptions are the agents of UNGUARDED below, each with its reason, and an exception that names
#      no agent, or an agent that has its guards after all, is stale (backlog #0-186): rule 4 compares an
#      agent's guard with its twin, so an agent with neither passed it (the defect-seeder, from #0-170 to #0-172).
# The YAML and JSON are parsed, not matched as text: a field one indent off, or in flow style, is what Claude
# Code reads, so it is what this reads. A file that does not parse, a frontmatter that does not close, a hooks
# block of another shape and a key repeated in one map fail the check. Of a repeated key Ruby keeps the last
# value, and which one Claude Code's parser keeps (or whether it refuses the file) is not documented: `onFailure`
# written twice could pass here and not hold there, so no file may repeat a key (review round 2).
#
# What it does not see: whether a guard's arguments are the right scope for its agent (a reviewer's to judge), and
# a hook a session gets from elsewhere (the user's own settings, a plugin).
# Usage: ruby check-hook-entries.rb [<repository root>] (Factory guards, after test-hook-entries.sh).
# Runs on the Ruby of .ruby-version (ADR-0040).
# ============================================================
require 'json'
require 'shellwords'
require 'yaml'

# Every file is read as UTF-8, whatever the locale: without one (a bare container) Ruby reads US-ASCII and a
# non-ASCII character in test-hooks.sh would end the check in an exception, not a finding.

ROOT = File.expand_path(ARGV[0] || '.')
HOOKS_DIR = File.join(ROOT, '.claude', 'hooks')
# The arguments take no shell syntax (`;`, `|`, `&`, `$`, backticks, parentheses, redirections, double quotes, a
# newline): `guard-tests.sh || true` is a hook that never fails, and `x.sh; other` runs a second command. A `*`
# only inside single quotes: unquoted, the shell expands it against the session's directory when the hook runs,
# so `write-scope.sh .ai/*` would hand the hook a list of files rather than its scope (review round 2).
ARG = %r{(?:[A-Za-z0-9_./=,-]|'[A-Za-z0-9_./*= -]*')+}.freeze
COMMAND = %r{\A"\$CLAUDE_PROJECT_DIR"/\.claude/hooks/([A-Za-z0-9_-]+\.sh)(?: #{ARG})*\z}.freeze

# The session-level guards each settings file must run (#0-164 AC4), and isolation-probe.sh, which guards nothing but
# records the fact the isolation check reads (#0-252): file => [[hook and its arguments, the tools its matcher must
# cover]]. The one list of them; the settings files are what it checks. webfetch-allowlist.sh is
# not here: check-web-access.sh holds its wiring, both files and both modes (one list per control, FAC-A01).
REQUIRED = {
  'settings.json' => [
    ['guard-migrations.sh', %w[Edit Write MultiEdit]]
  ],
  'settings.autopilot.json' => [
    ['guard-tests.sh', %w[Bash]],
    ['guard-protected-bash.sh', %w[Bash]],
    ['guard-git-push.sh', %w[Bash]],
    ['guard-factory-scripts.sh', %w[Bash]],
    ['isolation-probe.sh', %w[Bash]],
    ['guard-write-in-repo.sh', %w[Edit Write MultiEdit NotebookEdit]],
    ['guard-migrations.sh', %w[Edit Write MultiEdit NotebookEdit]]
  ]
}.freeze
# Rule 6 (backlog #0-186): the guards that bound an agent's Bash and its file tools, and the agents that run without
# them, each with the reason. These are the autopilot's own stages: "Autopilot only" by their definitions, they run in a
# session of settings.autopilot.json, whose denies and session-wide guards (REQUIRED, rule 5) bound them instead of a
# scope of their own; in the owner's interactive session they would run unbounded (README "Infrastructure
# Hardening", known gaps).
BASH_GUARDS = %w[readonly-bash.sh factory-ops-bash.sh].freeze
WRITE_GUARDS = %w[write-scope.sh].freeze
WRITE_TOOLS = %w[Edit Write MultiEdit NotebookEdit].freeze
UNGUARDED = {
  'implementer' => 'writes the item\'s code and tests anywhere but the protected paths; settings.autopilot.json\'s denies, ' \
                   'guard-write-in-repo.sh, guard-protected-bash.sh, guard-tests.sh and guard-migrations.sh bound it',
  'implementer-light' => 'the implementer on a lighter model, bounded the same way',
  'shipper' => 'pushes the run\'s branch and opens its pull request; bounded like the implementer, and guard-git-push.sh ' \
               '(the run\'s own branch only)'
}.freeze
# Every agent definition read, for rule 6: {name:, where:, tools: [names] or nil (no `tools:`, every tool)}.
@agents = []

# Every hook entry read, for rules 4 and 5: {owner: 'settings.json' | 'agent:<name>' | nil, where:, event:,
# tools: [matcher's tools], hook:, args: [words]}.
@entries = []

@failures = 0
def fail!(msg)
  puts "::error::#{msg}"
  @failures += 1
end

# The keys repeated in any map of a YAML node tree, as their path (e.g. hooks.PreToolUse[0].hooks[0].onFailure). JSON
# is read the same way, as YAML: what JSON.parse does with a repeated key is the json gem's choice, and it changed
# (2.1 and 2.6 call an object_class's []= for each key, the runner's gem did not, so PR #517's first CI run passed a
# repeated key; 3.x refuses it with its own message); Psych's tree is the same for every version.
def repeated_yaml_keys(node, path = '', found = [])
  case node
  when Psych::Nodes::Mapping
    seen = {}
    node.children.each_slice(2) do |key, value|
      name = key.is_a?(Psych::Nodes::Scalar) ? key.value : key.to_ruby.inspect
      found << (path.empty? ? name : "#{path}.#{name}") if seen[name]
      seen[name] = true
      repeated_yaml_keys(value, path.empty? ? name : "#{path}.#{name}", found)
    end
  when Psych::Nodes::Sequence
    node.children.each_with_index { |child, i| repeated_yaml_keys(child, "#{path}[#{i}]", found) }
  else
    node.children.to_a.each { |child| repeated_yaml_keys(child, path, found) } if node.respond_to?(:children)
  end
  found
end

# The hooks the fail-closed table of test-hooks.sh has a row for: the name before the first `|` of each row.
def fails_closed_rows
  file = File.join(HOOKS_DIR, 'test-hooks.sh')
  lines = File.readlines(file, encoding: 'UTF-8')
  start = lines.index { |l| l =~ /\AFAILS_CLOSED=\(\s*\z/ }
  return nil unless start

  rows = []
  lines[(start + 1)..-1].each do |l|
    break if l =~ /\A\)\s*\z/

    rows << Regexp.last_match(1) if l =~ /\A\s*"([^|"]+)\|/
  end
  rows
rescue SystemCallError => e
  fail!("cannot read #{file}: #{e.message}")
  nil
end

# Checks one `hooks` block (settings or frontmatter) of <where>.
def check_hooks(where, hooks, rows, owner = nil)
  unless hooks.is_a?(Hash)
    fail!("#{where}: `hooks` is not a map of events")
    return 0
  end
  count = 0
  hooks.each do |event, groups|
    unless groups.is_a?(Array)
      fail!("#{where}: hooks.#{event} is not a list")
      next
    end
    groups.each_with_index do |group, gi|
      entries = group.is_a?(Hash) ? group['hooks'] : nil
      unless entries.is_a?(Array)
        fail!("#{where}: hooks.#{event}[#{gi}] has no list of hooks")
        next
      end
      entries.each_with_index do |entry, ei|
        count += 1
        at = "#{where}: hooks.#{event}[#{gi}].hooks[#{ei}]"
        unless entry.is_a?(Hash)
          fail!("#{at} is not a hook entry")
          next
        end
        fail!("#{at} is a #{entry['type'].inspect} hook: only command hooks, which onFailure applies to") unless entry['type'] == 'command'
        unless entry['onFailure'] == 'block'
          fail!("#{at} has no \"onFailure\": \"block\" (#{entry['onFailure'].inspect}): a hook that cannot start or times out would let the call through")
        end
        %w[async asyncRewake].each do |k|
          fail!("#{at} sets #{k}: onFailure does not apply to a hook in the background, so the call never waits for it") if entry.key?(k)
        end
        cmd = entry['command'].to_s
        m = COMMAND.match(cmd)
        unless m
          fail!("#{at}: #{cmd.inspect} is not \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/<name>.sh with plain arguments")
          next
        end
        name = m[1]
        path = File.join(HOOKS_DIR, name)
        if !File.file?(path) then fail!("#{at}: .claude/hooks/#{name} does not exist")
        elsif !File.executable?(path) then fail!("#{at}: .claude/hooks/#{name} is not executable")
        end
        fail!("#{at}: #{name} has no row in FAILS_CLOSED (test-hooks.sh), so nothing shows it fails closed") if rows && !rows.include?(name)
        @entries << { owner: owner, where: at, event: event, tools: group['matcher'].to_s.split('|').sort, hook: name,
                      args: Shellwords.split(cmd.sub(/\A\S+/, '')) }
      end
    end
  end
  count
end

rows = fails_closed_rows
fail!('.claude/hooks/test-hooks.sh has no FAILS_CLOSED table') if rows.nil? || rows.empty?
total = 0

%w[settings.json settings.autopilot.json].each do |name|
  where = ".claude/#{name}"
  begin
    text = File.read(File.join(ROOT, where), encoding: 'UTF-8')
    # Repeated keys first: json 3 refuses them itself, with its own message, older versions keep one in silence.
    repeated = repeated_yaml_keys(Psych.parse(text))
    unless repeated.empty?
      fail!("#{where} repeats the key(s) #{repeated.join(', ')}")
      next
    end
    settings = JSON.parse(text)
  rescue SystemCallError, JSON::ParserError, Psych::Exception => e
    fail!("cannot read #{where}: #{e.message.lines.first.to_s.strip}")
    next
  end
  unless settings.is_a?(Hash)
    fail!("#{where} is not a JSON object")
    next
  end
  fail!("#{where} sets disableAllHooks: every hook, and every guard with it, would be off") if settings.key?('disableAllHooks')
  total += check_hooks(where, settings['hooks'], rows, name) if settings.key?('hooks')
end

# Checks the frontmatter of one Markdown definition. An agent must have one; a skill or a command without one has
# no hooks, but one that opens a frontmatter must close it and be YAML, or Claude Code and this would read it apart.
def check_markdown(file, rows, required, agent = false)
  where = file.sub("#{ROOT}/", '')
  lines = File.readlines(file, encoding: 'UTF-8')
  opened = lines.first.to_s =~ /\A---\s*\z/
  return 0 if !opened && !required

  close = lines.each_index.find { |i| i > 0 && lines[i] =~ /\A---\s*\z/ }
  unless opened && close
    fail!("#{where}: no frontmatter between two --- lines")
    return 0
  end
  text = lines[1...close].join
  begin
    repeated = repeated_yaml_keys(Psych.parse(text))
    unless repeated.empty?
      fail!("#{where}: the frontmatter repeats the key(s) #{repeated.join(', ')}")
      return 0
    end
    front = YAML.safe_load(text)
  rescue Psych::Exception => e
    fail!("#{where}: the frontmatter is not YAML (#{e.message})")
    return 0
  end
  unless front.is_a?(Hash)
    fail!("#{where}: the frontmatter is not a map")
    return 0
  end
  owner = agent ? "agent:#{front['name'] || File.basename(file, '.md')}" : nil
  if agent
    # A tool is named by what precedes a specifier (`Bash(git:*)` is Bash, review round 1 of #0-186), and `tools:`
    # that names none (absent, empty, blank) is read as every tool: whatever Claude Code makes of it, the check then
    # asks for every guard rather than none.
    tools = front['tools']
    tools = tools.scan(/(?:[^,(]|\([^)]*\))+/) if tools.is_a?(String)   # commas inside a specifier split nothing
    tools = tools.is_a?(Array) ? tools.map { |t| t.to_s.sub(/\(.*\z/m, '').strip }.reject(&:empty?) : []
    @agents << { name: owner.sub('agent:', ''), where: where, tools: tools.empty? ? nil : tools }
  end
  front.key?('hooks') ? check_hooks(where, front['hooks'], rows, owner) : 0
rescue SystemCallError => e
  fail!("cannot read #{where}: #{e.message}")
  0
end

# Every place a definition can declare hooks: agents, skills and commands, in subdirectories too (review round 1).
claude = File.join(ROOT, '.claude')
agents = Dir.glob(File.join(claude, 'agents', '**', '*.md')).sort
fail!('.claude/agents has no agent definition') if agents.empty?
agents.each { |file| total += check_markdown(file, rows, true, true) }
(Dir.glob(File.join(claude, 'skills', '**', 'SKILL.md')) + Dir.glob(File.join(claude, 'commands', '**', '*.md'))).sort.each do |file|
  total += check_markdown(file, rows, false)
end

# 4. Session-level twins of the agents' guards.
SETTINGS = %w[settings.json settings.autopilot.json].freeze
guards = Hash.new { |h, k| h[k] = [] }   # [event, tools, hook, args] => agent names
@entries.each do |e|
  next unless e[:owner].to_s.start_with?('agent:')

  agent = e[:owner].sub('agent:', '')
  if e[:args].first == '--agent'
    fail!("#{e[:where]}: a frontmatter hook guards its own agent, it takes no --agent")
    next
  end
  guards[[e[:event], e[:tools], e[:hook], e[:args]]] << agent
end
twins = 0
SETTINGS.each do |file|
  seen = []
  @entries.select { |e| e[:owner] == file && e[:args].first == '--agent' }.each do |e|
    names = e[:args][1].to_s.split(',')
    key = [e[:event], e[:tools], e[:hook], e[:args][2..-1] || []]
    seen << key
    want = guards.key?(key) ? guards[key].sort.uniq : []
    if want.empty?
      fail!("#{e[:where]}: no agent's frontmatter runs #{e[:hook]} #{key[3].join(' ')} on #{e[:tools].join('|')}: a stale twin")
    elsif names.sort != want
      fail!("#{e[:where]}: --agent #{names.join(',')} is not the agents whose frontmatter runs it (#{want.join(',')})")
    end
    twins += 1
  end
  guards.each do |key, agents|
    next if seen.include?(key)

    fail!(".claude/#{file}: no session-level twin of #{key[2]} #{key[3].join(' ')} on #{key[1].join('|')} " \
          "(#{agents.sort.uniq.join(',')}'s frontmatter guard; a Workflow's agents are not promised it, #0-164)")
  end
end

# 5. The required session-level guards.
REQUIRED.each do |file, wants|
  wants.each do |command, tools|
    hook, *args = command.split(' ')
    found = @entries.any? do |e|
      e[:owner] == file && e[:event] == 'PreToolUse' && e[:hook] == hook && e[:args] == args && (tools - e[:tools]).empty?
    end
    next if found

    fail!(".claude/#{file} does not run #{command} on #{tools.join('|')} before every such call (#0-164 AC4): a deleted " \
          'or moved guard would pass every other rule')
  end
end

# 6. Every agent with Bash or a file tool has its guard, or is one of UNGUARDED (backlog #0-186).
guarded = 0
@agents.each do |a|
  tools = a[:tools] || (['Bash'] + WRITE_TOOLS)
  mine = @entries.select { |e| e[:owner] == "agent:#{a[:name]}" && e[:event] == 'PreToolUse' }
  writes = tools & WRITE_TOOLS
  missing = []
  if tools.include?('Bash') && mine.none? { |e| BASH_GUARDS.include?(e[:hook]) && e[:tools].include?('Bash') }
    missing << "Bash guard (#{BASH_GUARDS.join(' or ')}) on a matcher with Bash"
  end
  if !writes.empty? && mine.none? { |e| WRITE_GUARDS.include?(e[:hook]) && (writes - e[:tools]).empty? }
    missing << "#{WRITE_GUARDS.join(' or ')} on a matcher with #{writes.join(', ')}"
  end
  what = a[:tools] ? "holds #{(tools & (['Bash'] + WRITE_TOOLS)).join(', ')}" : 'declares no tools: (so holds every tool)'
  if UNGUARDED.key?(a[:name])
    fail!("#{a[:where]}: has its guards, so its entry in UNGUARDED (check-hook-entries.rb) is stale") if missing.empty?
  elsif missing.empty?
    guarded += 1 unless (tools & (['Bash'] + WRITE_TOOLS)).empty?
  else
    fail!("#{a[:where]}: #{what} but its frontmatter has no #{missing.join(', and no ')}: add the guard, or name the " \
          'agent in UNGUARDED with the reason it runs without one (backlog #0-186)')
  end
end
# One name, one definition: rule 4's twins (agent_type) and UNGUARDED are keyed on it, so a second file reusing
# `shipper` would pass as excepted (review round 1 of #0-186).
@agents.group_by { |a| a[:name] }.each do |name, defs|
  next if defs.size == 1

  fail!("#{defs.map { |d| d[:where] }.join(' and ')} are both the agent #{name}: one name, one definition")
end
UNGUARDED.each_key do |name|
  next if @agents.any? { |a| a[:name] == name }

  fail!("UNGUARDED (check-hook-entries.rb) names #{name}, which is no agent of .claude/agents/: a stale exception")
end

if @failures > 0
  puts "#{@failures} hook entry problem(s)"
  exit 1
end
puts "Hook entries: all #{total} block when their hook fails, each a hook of the fail-closed table; " \
     "#{twins} session-level twin(s) match the agents' guards, the #{REQUIRED.values.flatten(1).size} required guards are wired, " \
     "and #{guarded} agent(s) with Bash or a file tool run their guards (#{UNGUARDED.size} autopilot stage(s) excepted)."
