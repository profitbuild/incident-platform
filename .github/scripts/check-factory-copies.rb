# ============================================================
# The copies profitbuild/factory keeps of this repository's CI and session controls equal their originals here
# (backlog #0-268, ADR-0061).
#
#   ruby .github/scripts/check-factory-copies.rb <factory checkout> [--changed <file> --baseline <dir>]
#                                                [--shellcheck <binary>]
#
# `factory` copies this repository's CI tool pins, its actions' SHAs, three scripts, its setup-node action and
# zizmor.yml, .node-version and the owner session's denies; `factory` names no product (ADR-0060 D5), so the check
# comparing the two lives here (ADR-0061). Renovate and check-pinned-tools.sh run here alone, so a bump here leaves
# `factory` on the old value with no signal (the drift of #0-122) unless this fails. It compares, run from this
# repository's root:
#   1. pins: every <NAME>_VERSION / <NAME>_SHA256 in `factory`'s workflows and actions has the same value here, and
#      `factory` holds the pins of the tools its CI needs (REQUIRED_PINS);
#   2. actions: every `uses: <owner>/<repo>@<sha>` in `factory` is a SHA this repository uses for that action;
#   3. copies: each file of COPIES equals its original once its notice is removed (a paragraph starting
#      NOTICE_START, ending at the next bare `#` line; a copy without it is a finding), and every file of `factory`
#      that carries the notice is in COPIES (the list both ways); setup-node's action.yml and zizmor.yml equal their
#      originals once comments are removed (their comments name each repository's items); .node-version byte for byte;
#   4. denies: `factory`'s .claude/settings.json denies every deny here but those of OPTIONAL_DENIES, and nothing
#      that this repository does not deny (AC4). An optional deny names what `factory` has no use for; present there
#      it is no finding, so `factory` may add one without a false alarm.
#
# Which side leads (ADR-0061): this repository. On a pull request (--changed lists its files, --baseline is a checkout
# of main as the merge commit has it, HEAD^1), a difference fails (::error, exit 1) only when the pull request changes
# a file of COMPARED and the difference is not there already on main: so a pull request that leaves `factory` behind
# fails, the owner mirrors the change in `factory` and re-runs, and a pull request is never failed by drift it did not
# bring (Renovate's next pull request, while `factory` leads on another tool). Every other difference, and every run
# that is not a pull request, is a warning and passes: drift `factory` started would otherwise turn every pull request
# here red, and a red main stops the autopilot. At step 4.7 the reference moves from factory@main to the tag the
# product pins (.factory/adapter.json, ADR-0060 D6).
#
# It also runs check-downloads.rb, check-runtime-setup.rb and check-shell.rb on the `factory` checkout (they take the
# root as an argument; `factory` has no Ruby, ADR-0060 D2): their findings are `factory`'s own, never caused by a
# change here, so they are always warnings, prefixed `factory:`.
#
# The checkout is outside input, and what this prints goes to a public CI log (SEC-31): a symlink anywhere in it is
# refused before anything reads it, the sub-checks included (it could point at a file of the runner), a settings file that does not parse
# is reported by the parser's error class alone (its message quotes the text), and values are printed only where they
# are the subject of the finding (a pin's version, a deny's text). Fails closed: a missing checkout, one with no
# workflow, a symlink among the files it reads, or a settings file that does not parse is an error in either mode.
# What it does not see: a pin or an action in a file of `factory` other than its workflows and actions.
# Runs on the Ruby of .ruby-version (ADR-0040). Tests: test-check-factory-copies.sh.
# ============================================================
require 'digest'
require 'json'
require 'open3'
require 'set'
require_relative 'run-blocks'

# Files here whose content the comparison reads: a pull request that changes one is the side that leads.
COMPARED = %w[
  .github/workflows/ci.yml
  .github/scripts/install-pinned-tool.sh
  .github/scripts/secret-scan.sh
  .github/scripts/test-secret-scan.sh
  .github/actions/setup-node/action.yml
  .github/zizmor.yml
  .node-version
  .claude/settings.json
].freeze
COPIES = %w[
  .github/scripts/install-pinned-tool.sh
  .github/scripts/secret-scan.sh
  .github/scripts/test-secret-scan.sh
].freeze
# Copies whose comments differ on purpose: compared once comment lines and blank lines are removed.
COMMENT_COPIES = %w[.github/actions/setup-node/action.yml .github/zizmor.yml].freeze
REQUIRED_PINS = %w[ACTIONLINT SHELLCHECK ZIZMOR BETTERLEAKS].flat_map { |t| ["#{t}_VERSION", "#{t}_SHA256"] }.freeze
# Denies of this repository that `factory` may lack: they name what it does not have (repository-settings.rb, this
# repository's docker/ files). Named one by one, so a new deny here is required there until it is added to this list
# on purpose; the generic `.env` denies are required (a devcontainer of `factory` could hold one, review round 2).
OPTIONAL_DENIES = [
  'Bash(*repository-settings.rb plan*)',
  'Bash(*repository-settings.rb apply*)',
  'Read(./docker/.env)',
  'Read(./docker/secrets/**)'
].freeze
NOTICE_START = "# A copy of profitbuild/incident-platform's"

def usage!
  warn "usage: #{$PROGRAM_NAME} <factory checkout> [--changed <file> --baseline <dir>] [--shellcheck <binary>]"
  exit 2
end

args = ARGV.dup
factory = args.shift or usage!
changed_file = baseline = shellcheck = nil
until args.empty?
  case args.shift
  when '--changed' then changed_file = args.shift or usage!
  when '--baseline' then baseline = args.shift or usage!
  when '--shellcheck' then shellcheck = args.shift or usage!
  else usage!
  end
end
usage! if changed_file.nil? != baseline.nil?
FACTORY = File.expand_path(factory)

def fatal!(msg)
  puts Annotation.error("#{msg} (backlog #0-268)")
  exit 1
end

fatal!("#{FACTORY} is not a checkout of profitbuild/factory (no .github/workflows/)") unless
  File.directory?(File.join(FACTORY, '.github', 'workflows')) && !File.symlink?(File.join(FACTORY, '.github'))
# No symlink anywhere in the checkout (.git aside), before anything reads it: the sub-checks below (shellcheck on its
# tracked .sh files, check-runtime-setup.rb on the scripts its steps name) would follow one to a file of the runner.
# The glob lists a symlinked directory without entering it (Ruby 4.0). .git itself is checked, its content skipped.
fatal!("factory's .git is a symlink: refused, it could point outside the checkout") if File.symlink?(File.join(FACTORY, '.git'))
Dir.glob('**/*', File::FNM_DOTMATCH, base: FACTORY).each do |rel|
  next if rel == '.git' || rel.start_with?('.git/') || rel.end_with?('/.') || rel == '.'

  fatal!("factory's #{rel} is a symlink: refused, it could point outside the checkout") if File.symlink?(File.join(FACTORY, rel))
end

# A file of the `factory` checkout, read only if it is a regular file and no symlink, on its path or the file itself.
def factory_path!(path)
  rel = path.delete_prefix("#{FACTORY}/")
  parts = rel.split('/')
  parts.each_index do |i|
    fatal!("factory's #{rel} goes through a symlink (#{parts[0..i].join('/')}): refused, it could point outside the checkout") if
      File.symlink?(File.join(FACTORY, *parts[0..i]))
  end
  path
end

def read(root, rel)
  path = File.join(root, rel)
  factory_path!(path) if root == FACTORY
  File.file?(path) ? File.read(path) : nil
end

def ci_files(root)
  files = Dir.glob(File.join(root, '.github', 'workflows', '*.{yml,yaml}')) +
          Dir.glob(File.join(root, '.github', 'actions', '*', 'action.{yml,yaml}'))
  files.each { |f| factory_path!(f) } if root == FACTORY
  files
end

def pins(root)
  out = Hash.new { |h, k| h[k] = [] }
  ci_files(root).each do |file|
    File.foreach(file) do |line|
      out[Regexp.last_match(1)] << Regexp.last_match(2) if line =~ /^\s*([A-Z0-9_]+_(?:VERSION|SHA256)):\s*(\S+)\s*$/
    end
  end
  out
end

def actions(root)
  out = Hash.new { |h, k| h[k] = [] }
  ci_files(root).each do |file|
    File.foreach(file) do |line|
      next unless line =~ %r{^\s*-?\s*uses:\s*([\w.-]+/[\w.-]+)(?:/[^@\s]*)?@([0-9a-f]{40})\b}

      out[Regexp.last_match(1)] << Regexp.last_match(2)
    end
  end
  out
end

# A short digest of an original, in a difference's message, so a pull request that changes a file whose copy already
# differs on main brings a message main does not have (review round 2): a further change cannot hide behind old drift.
def digest(text) = "sha256 #{Digest::SHA256.hexdigest(text)[0, 12]}"

def without_notice(text)
  lines = text.lines
  start = lines.index { |l| l.start_with?(NOTICE_START) }
  return nil unless start

  stop = (start...lines.length).find { |i| lines[i].chomp == '#' }
  return nil unless stop

  (lines[0...start] + lines[(stop + 1)..]).join
end

def denies(root)
  JSON.parse(read(root, '.claude/settings.json') || '{}').dig('permissions', 'deny') || []
rescue JSON::ParserError => e
  # The parser's message quotes the text it failed on: the class alone reaches the log (SEC-31).
  fatal!("#{root == FACTORY ? "factory's" : "this repository's"} .claude/settings.json does not parse (#{e.class})")
end

# Every file of the checkout that carries the notice, so the list of copies is checked both ways.
def noticed_files
  Dir.glob('**/*', File::FNM_DOTMATCH, base: FACTORY).reject { |rel| rel.start_with?('.git/') || rel == '.git' }
     .select do |rel|
       path = File.join(FACTORY, rel)
       next false if File.symlink?(path) || !File.file?(path)

       File.open(path, 'rb') { |f| f.read(8192).to_s }.lines.first(40).any? { |l| l.start_with?(NOTICE_START) }
     end
end

# The differences between `factory` and the product tree at <product>, as messages.
def compare(product)
  found = []
  product_pins = pins(product)
  factory_pins = pins(FACTORY)
  REQUIRED_PINS.each { |name| found << "factory's CI has no #{name}" unless factory_pins.key?(name) }
  factory_pins.each do |name, values|
    values.uniq.each do |value|
      if !product_pins.key?(name)
        found << "factory pins #{name} (#{value}), which this repository does not pin"
      elsif !product_pins[name].include?(value)
        found << "factory's #{name} is #{value}, this repository's #{product_pins[name].uniq.join(', ')}"
      end
    end
  end

  product_actions = actions(product)
  actions(FACTORY).each do |action, shas|
    shas.uniq.each do |sha|
      if !product_actions.key?(action)
        found << "factory uses #{action}, which this repository does not"
      elsif !product_actions[action].include?(sha)
        found << "factory uses #{action}@#{sha}, this repository #{product_actions[action].uniq.join(', ')}"
      end
    end
  end

  COPIES.each do |rel|
    original = read(product, rel)
    copy = read(FACTORY, rel)
    if original.nil?
      found << "#{rel} is listed as copied but this repository has no such file"
    elsif copy.nil?
      found << "factory has no #{rel}"
    elsif (stripped = without_notice(copy)).nil?
      found << "factory's #{rel} has no copy notice (a paragraph starting \"#{NOTICE_START}\", ending at a bare #)"
    elsif stripped != original
      found << "factory's #{rel} differs from this repository's (#{digest(original)} here) beyond its notice"
    end
  end
  (noticed_files - COPIES - COMMENT_COPIES).each do |rel|
    found << "factory's #{rel} says it is a copy of this repository's, but check-factory-copies.rb does not list it in COPIES"
  end
  no_comments = ->(text) { text.lines.reject { |l| l.strip.start_with?('#') || l.strip.empty? }.join }
  COMMENT_COPIES.each do |rel|
    a = read(product, rel)
    b = read(FACTORY, rel)
    if a && b
      if no_comments[a] != no_comments[b]
        found << "factory's #{rel} differs from this repository's (#{digest(no_comments[a])} here) beyond its comments"
      end
    else
      found << "#{rel} is missing on one side"
    end
  end
  ours = read(product, '.node-version').to_s.strip
  theirs = read(FACTORY, '.node-version').to_s.strip
  found << "factory's .node-version is #{theirs}, this repository's #{ours}" if ours != theirs

  all = denies(product)
  actual = denies(FACTORY)
  ((all - OPTIONAL_DENIES) - actual).each { |d| found << "factory's .claude/settings.json does not deny #{d}" }
  (actual - all).each { |d| found << "factory's .claude/settings.json denies #{d}, which this repository does not" }
  found
end

touched = changed_file ? File.readlines(changed_file, chomp: true).map(&:strip) & COMPARED : []
findings = compare(File.expand_path('.'))
# Differences main already has are not this pull request's: they warn, as on every other run.
already = touched.empty? ? Set.new(findings) : Set.new(compare(File.expand_path(baseline)))
errors = findings.reject { |f| already.include?(f) }
warnings = findings.select { |f| already.include?(f) }

own = []
checks = [['check-downloads.rb', [FACTORY]], ['check-runtime-setup.rb', [FACTORY]]]
checks << ['check-shell.rb', [shellcheck, FACTORY]] if shellcheck
checks.each do |script, check_args|
  out, status = Open3.capture2e(RbConfig.ruby, File.join(__dir__, script), *check_args)
  next if status.success?

  lines = out.lines.map(&:chomp).select { |l| l.start_with?('::error') }
  lines = ["#{script} failed (exit #{status.exitstatus})"] if lines.empty?
  lines.each do |l|
    file = l[/\A::error [^:]*file=([^,:]+)/, 1]
    msg = l.sub(/\A::error[^:]*::/, '')
    own << "factory: #{script}: #{file ? "#{file}: " : ''}#{msg}"
  end
end
own << 'factory: check-shell.rb not run (no --shellcheck)' unless shellcheck

errors.each { |msg| puts Annotation.error("#{msg} (backlog #0-268)") }
warnings.each { |msg| puts Annotation.warning("#{msg} (backlog #0-268)") }
own.each { |msg| puts Annotation.warning("#{msg} (backlog #0-268)") }

if findings.empty?
  puts "factory's copies match this repository's#{own.empty? ? '' : " (#{own.length} warning(s) of factory's own checks)"}."
elsif !errors.empty?
  puts "#{errors.length} difference(s) this pull request brings (it changes #{touched.join(', ')}): change factory " \
       "to match first (this repository leads, ADR-0061), then re-run.#{warnings.empty? ? '' : " #{warnings.length} more already on main."}"
  exit 1
else
  puts "#{findings.length} difference(s), reported as warnings: #{touched.empty? ? 'this run changes none of the compared files' : 'all of them are on main already'}."
end
