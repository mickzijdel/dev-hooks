# Hand-rolled mutation testing for one Ruby file, driven by per-test coverage.
#   ruby mutate.rb app/models/x.rb --cov tmp/pertest [--out kills.json] [--list] [--only 3,7] [--runner "bin/rails test"]
# Minitest only. Each mutant runs only the tests whose coverage touches its line (or the file,
# for class-body lines that run at load time). Default runner: `t` (the machine-wide test queue)
# when on PATH, else `bin/rails test`.
# Restores the file on exit, on INT/TERM, and from FILE.mutate-orig if a previous run was killed
# with -9 (it refuses to start while that backup exists). One run per checkout at a time.
require "prism"
require "json"
require "open3"
require "timeout"
require "fileutils"

file = ARGV[0] or abort "usage: mutate.rb FILE --cov DIR [--out JSON] [--list] [--only i,j] [--runner CMD]"
opt = ->(k) { (i = ARGV.index(k)) && ARGV[i + 1] }
cov_dir = opt.("--cov") || "tmp/pertest"
out = opt.("--out")
only = opt.("--only")&.split(",")&.map(&:to_i)
RUNNER = (opt.("--runner") || (system("command -v t >/dev/null 2>&1") ? "t" : "bin/rails test")).split
src = File.read(file)

SWAP = { "==" => "!=", "!=" => "==", ">" => "<=", "<=" => ">", "<" => ">=", ">=" => "<", "+" => "-", "-" => "+",
         "present?" => "blank?", "blank?" => "present?", "any?" => "none?", "none?" => "any?", "first" => "last",
         "exists?" => "none?", "find_by" => "find_by!" }.freeze
# off-by-one: a suite with no test at the boundary (age exactly 18) lets these survive
BOUNDARY = { ">=" => ">", ">" => ">=", "<=" => "<", "<" => "<=" }.freeze

class Gen < Prism::Visitor
  attr_reader :muts
  def initialize(src) = (@src = src; @muts = []; @in_def = 0; super())
  def add(loc, repl, desc) = @muts << { start: loc.start_offset, len: loc.length, repl:, line: loc.start_line, desc: }
  def visit_def_node(n) = (@in_def += 1; super; @in_def -= 1)
  def visit_call_node(n)
    if n.message_loc && (r = SWAP[n.name.to_s])
      add(n.message_loc, r, "#{n.name} -> #{r}")
    end
    if n.message_loc && (b = BOUNDARY[n.name.to_s])
      add(n.message_loc, b, "#{n.name} -> #{b}")
    end
    super
  end
  def visit_and_node(n) = (add(n.operator_loc, n.operator_loc.slice == "&&" ? "||" : "or", "and -> or"); super)
  def visit_or_node(n) = (add(n.operator_loc, n.operator_loc.slice == "||" ? "&&" : "and", "or -> and"); super)
  def visit_if_node(n) = (n.if_keyword_loc&.slice == "if" && add(n.if_keyword_loc, "unless", "if -> unless"); super)
  def visit_unless_node(n) = (add(n.keyword_loc, "if", "unless -> if"); super)
  def visit_true_node(n) = (add(n.location, "false", "true -> false"); super)
  def visit_false_node(n) = (add(n.location, "true", "false -> true"); super)
  def visit_class_node(n)
    # declarations (validates, scope, enum, belongs_to, callbacks) run at load: delete each one
    n.body&.body&.each do |s|
      next unless s.is_a?(Prism::CallNode) && s.receiver.nil? && !%w[private protected public include extend].include?(s.name.to_s)
      add(s.location, "nil", "delete decl `#{s.slice.lines.first.strip[0, 50]}`")
    end
    super
  end
  def visit_lambda_node(n) = (@in_def += 1; super; @in_def -= 1) # scope bodies
  def visit_statements_node(n)
    if @in_def.positive?
      n.body.each do |s|
        next unless s.is_a?(Prism::CallNode) || s.is_a?(Prism::ReturnNode)
        add(s.location, "nil", "delete `#{s.slice.lines.first.strip[0, 50]}`")
      end
    end
    super
  end
end

g = Gen.new(src)
Prism.parse(src).value.accept(g)
muts = g.muts.uniq { |m| [m[:start], m[:repl]] }.sort_by { |m| m[:start] }
if ARGV.include?("--list")
  muts.each_with_index { |m, i| puts "#{i}\tL#{m[:line]}\t#{m[:desc]}" }
  exit
end

# coverage index: line -> tests, file -> tests. The newest record per test wins, so a stale
# index from before tests were added or renamed shows up as a warning, not silent survivors.
records = {}
Dir[File.join(cov_dir, "cov-*.jsonl")].sort_by { File.mtime(_1) }.each do |f|
  File.foreach(f) do |l|
    r = JSON.parse(l)
    warn "warning: #{r["test"]} recorded twice; delete #{cov_dir} before recording again" if records.key?(r["test"])
    records[r["test"]] = r
  end
end
by_line = Hash.new { |h, k| h[k] = [] }
by_file = []
records.each_value do |r|
  lines = r["cov"][file] or next
  by_file << r
  lines.each { |n| by_line[n] << r }
end
abort "no test covers #{file}" if by_file.empty?

FILTER = File.expand_path("filter_tests.rb", __dir__)
NAMES_FILE = File.expand_path("tmp/mutate-only-tests-#{Process.pid}.txt") # relative to the app root
BACKUP = "#{file}.mutate-orig"

def descendants(pid)
  kids = Dir["/proc/[0-9]*/stat"].filter_map do |stat|
    fields = File.read(stat).split(") ").last.split
    stat[%r{\d+}].to_i if fields[1].to_i == pid
  rescue Errno::ENOENT, Errno::ESRCH
    nil
  end
  kids + kids.flat_map { descendants(_1) }
end

# `sem` (behind `t`) puts its job in a new process group, so killing the group misses it
def kill_tree(pid)
  (descendants(pid) + [pid]).each { |p| Process.kill("KILL", p) rescue nil }
end

$child = nil
def run_tests(recs, timeout)
  FileUtils.mkdir_p(File.dirname(NAMES_FILE))
  files = recs.map { |r| r["loc"].split(":").first }.uniq
  names = recs.map { |r| r["test"] }.uniq
  File.write(NAMES_FILE, names.join("\n"))
  # names go via a file, not the command line: GNU sem (behind `t`) re-splits arguments in a shell
  env = { "ONLY_TESTS_FILE" => NAMES_FILE, "RUBYOPT" => "-r#{FILTER}", "PARALLEL_WORKERS" => "1",
          "DISABLE_BOOTSNAP_COMPILE_CACHE" => "1" } # same-size mutants written in one second
  out = +""
  Open3.popen2e(env, *RUNNER, *files, pgroup: true) do |_in, io, th|
    $child = th.pid
    begin
      Timeout.timeout(timeout) { out = io.read; th.value }
    rescue Timeout::Error
      kill_tree(th.pid)
      return [:timeout, []]
    ensure
      $child = nil
    end
  end
  # Rails prints "Failure:", plain Minitest "  1) Failure:"
  failed = out.scan(/^\s*(?:\d+\) )?(?:Failure|Error):\r?\n\s*(.+?#.+?)(?: \[|:\r?$)/).flatten.uniq
  runs, failures, errors = out.scan(/(\d+) runs, \d+ assertions, (\d+) failures, (\d+) errors/).last&.map(&:to_i)
  return [:error, [out.lines.last(5).join]] if runs.nil? || runs.zero?
  return [:killed, failed.empty? ? ["(unparsed)"] : failed] if failures + errors > 0
  # fewer runs than names: a test the runner never loaded (stale index, test from a module)
  return [:partial, ["ran #{runs} of #{names.size}"]] if runs < names.size
  [:survived, []]
end

if File.exist?(BACKUP)
  abort "#{BACKUP} exists: an earlier run was killed. Check `git diff #{file}`, restore from it, delete it, rerun."
end
File.write(BACKUP, src)
restore = -> { File.write(file, src); File.delete(BACKUP) if File.exist?(BACKUP); File.delete(NAMES_FILE) if File.exist?(NAMES_FILE) }
%w[INT TERM].each do |sig|
  trap(sig) { kill_tree($child) if $child; restore.call; exit!(130) }
end

results = []
begin
  t0 = Time.now
  base, detail = run_tests(by_file, 300)
  base_secs = Time.now - t0
  abort "baseline not green for #{file}: #{base} #{detail.join}" unless base == :survived
  puts "#{muts.size} mutants, #{by_file.size} covering tests, baseline #{base_secs.round(1)}s"

  muts.each_with_index do |m, i|
    next if only && !only.include?(i)
    mutated = src.byteslice(0, m[:start]) + m[:repl] + src.byteslice(m[:start] + m[:len]..)
    _, st = Open3.capture2e("ruby", "-c", stdin_data: mutated)
    next results << m.merge(id: i, status: :invalid, killers: []) unless st.success?
    recs = by_line[m[:line]]
    recs = by_file if recs.empty? # class-body line, runs at load
    File.write(file, mutated)
    status, killers = run_tests(recs, [base_secs * 3, 30].max)
    File.write(file, src)
    results << m.merge(id: i, status:, killers:, ran: recs.size)
    puts "#{i.to_s.rjust(3)} L#{m[:line].to_s.ljust(4)} #{status.to_s.ljust(8)} #{killers.size.to_s.rjust(3)} killers  #{m[:desc]}"
  end
ensure
  restore.call
end
counts = results.group_by { |r| r[:status] }.transform_values(&:size)
puts "summary: {#{counts.map { |k, v| "#{k}: #{v}" }.join(", ")}}" # not Hash#inspect: its format changed in Ruby 3.4
if out
  # --only merges into an existing matrix by mutant id instead of replacing it
  old = only && File.exist?(out) ? JSON.parse(File.read(out), symbolize_names: true)[:results] : []
  merged = (old.reject { |r| results.any? { _1[:id] == r[:id] } } + results).sort_by { _1[:id] }
  File.write(out, JSON.pretty_generate(file:, results: merged))
end
