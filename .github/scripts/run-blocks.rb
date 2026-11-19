# ============================================================
# The `run:` blocks of the workflows and of the composite actions, each with the line its text starts on
# (backlog #0-149). Read by check-shell.rb (shellcheck of the composite actions' steps, which actionlint does
# not lint), check-downloads.rb (no download outside install-pinned-tool.sh, ADR-0033), check-runtime-setup.rb
# (its helpers only: it walks each job's steps in order, backlog #0-166) and check-rule-claims.rb (its helpers only:
# it reads each job's name, `if:` and `continue-on-error` with its steps, backlog #0-184).
#
# The YAML is read as a node tree (Psych.parse), not as data (safe_load): only the nodes know their line.
# Psych counts lines from 0 and puts a block scalar (`run: |`, `run: >`) on the line of its indicator; its
# text starts on the next one. A folded block (`>`) joins its lines, so only its first line maps back.
# Also how the checkers print a finding (Annotation, below). Runs on the Ruby of .ruby-version (ADR-0040).
# ============================================================
require 'psych'

module RunBlocks
  # file: path from the root; line: the 1-based line in that file of the text's first line; column: what to
  # add to a column of the text to get the file's (nil for a folded block); shell: the step's `shell:` (nil
  # when it has none); kind: :workflow or :action; step: the step's name or id, for a message.
  Block = Struct.new(:file, :line, :column, :folded, :shell, :text, :kind, :step)

  # The value node of `key` in a mapping node, or nil.
  def self.get(node, key)
    return nil unless node.is_a?(Psych::Nodes::Mapping)
    node.children.each_slice(2) { |k, v| return v if k.is_a?(Psych::Nodes::Scalar) && k.value == key }
    nil
  end

  def self.scalar(node)
    node.is_a?(Psych::Nodes::Scalar) ? node.value : nil
  end

  def self.seq(node)
    node.is_a?(Psych::Nodes::Sequence) ? node.children : []
  end

  def self.workflows(root)
    Dir.glob(File.join(root, '.github/workflows/*.{yml,yaml}')).sort
  end

  def self.actions(root)
    Dir.glob(File.join(root, '.github/actions/*/action.{yml,yaml}')).sort
  end

  # Every run block of the given files (absolute paths), and the files that could not be read as YAML,
  # as [blocks, errors]; an error is [file, message]. Nothing is skipped silently: a caller fails on errors.
  def self.of(root, files)
    blocks = []
    errors = []
    files.each do |path|
      file = path.sub(%r{\A#{Regexp.escape(root)}/?}, '')
      begin
        raw = File.read(path)
        doc = Psych.parse(raw)
      rescue StandardError => e
        errors << [file, "#{file} cannot be read as YAML: #{e.message.lines.first.to_s.strip}"]
        next
      end
      top = doc && doc.root
      unless top.is_a?(Psych::Nodes::Mapping)
        errors << [file, "#{file} is not a YAML mapping"]
        next
      end
      lines = raw.lines
      steps_of(file, top).each do |kind, step, default_shell|
        node = get(step, 'run')
        next unless node.is_a?(Psych::Nodes::Scalar)
        blocks << block(file, lines, node, kind, step, scalar(get(step, 'shell')) || default_shell)
      end
    end
    [blocks, errors]
  end

  # [kind, step node, default shell] for each step: a workflow's jobs, or a composite action's runs.
  def self.steps_of(file, top)
    if file.start_with?('.github/actions/')
      runs = get(top, 'runs')
      return [] unless scalar(get(runs, 'using')) == 'composite'
      seq(get(runs, 'steps')).map { |s| [:action, s, nil] }
    else
      wf_shell = scalar(get(get(get(top, 'defaults'), 'run'), 'shell'))
      jobs = get(top, 'jobs')
      return [] unless jobs.is_a?(Psych::Nodes::Mapping)
      jobs.children.each_slice(2).flat_map do |_, job|
        shell = scalar(get(get(get(job, 'defaults'), 'run'), 'shell')) || wf_shell
        seq(get(job, 'steps')).map { |s| [:workflow, s, shell] }
      end
    end
  end

  def self.block(file, lines, node, kind, step, shell)
    name = scalar(get(step, 'name')) || scalar(get(step, 'id')) || 'unnamed step'
    style = node.style
    if [Psych::Nodes::Scalar::LITERAL, Psych::Nodes::Scalar::FOLDED].include?(style)
      line = node.start_line + 2
      first = node.value.lines.first.to_s
      raw = lines[line - 1].to_s
      # The block's indentation in the file, less what the text itself keeps (an indentation indicator).
      column = raw[/\A */].length - first[/\A */].length
      folded = style == Psych::Nodes::Scalar::FOLDED
      Block.new(file, line, folded ? nil : column, folded, shell, node.value, kind, name)
    else
      # A plain or quoted scalar on one line: its text starts at the node's column (a quote moves it by one).
      column = node.start_column + (style == Psych::Nodes::Scalar::PLAIN ? 0 : 1)
      Block.new(file, node.start_line + 1, column, false, shell, node.value, kind, name)
    end
  end
end

# A finding as a GitHub `::error` workflow command, escaped as @actions/core escapes it: in the message %, CR and
# LF, in a property (file=) also `:` and `,`. A step name or a path carries text from the repository, and
# unescaped a newline in it would end the command and start another line (review of #0-149).
module Annotation
  def self.data(text)
    text.to_s.gsub('%', '%25').gsub("\r", '%0D').gsub("\n", '%0A')
  end

  def self.property(text)
    data(text).gsub(':', '%3A').gsub(',', '%2C')
  end

  def self.error(msg, file: nil, line: nil, col: nil)
    props = []
    props << "file=#{property(file)}" if file
    props << "line=#{line}" if line
    props << "col=#{col}" if col
    "::error#{props.empty? ? '' : ' ' + props.join(',')}::#{data(msg)}"
  end

  # The same, as a `::warning` (check-factory-copies.rb, backlog #0-268: a finding that does not fail the run).
  def self.warning(msg, file: nil, line: nil, col: nil)
    error(msg, file: file, line: line, col: col).sub(/\A::error/, '::warning')
  end
end
