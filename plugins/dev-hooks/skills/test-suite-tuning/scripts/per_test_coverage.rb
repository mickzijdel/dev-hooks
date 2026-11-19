# Per-test line coverage for Minitest, stdlib only. Load before the app:
#   RUBYOPT="-r/abs/path/per_test_coverage.rb" PER_TEST_COV_DIR=tmp/pertest bin/rails test
# Writes one JSON line per test to $PER_TEST_COV_DIR/cov-<pid>.jsonl (safe with forked workers;
# threaded workers mix their tests' lines). Delete that directory before recording again.
# Switch SimpleCov off for this run: a second Coverage.start raises.
require "coverage" # nothing else here: gems required before Bundler.setup clash with the bundle

Coverage.start(lines: true) unless Coverage.running?

module PerTestCoverage
  ROOT = Dir.pwd + "/"
  DIR = ENV.fetch("PER_TEST_COV_DIR", "tmp/pertest")
  TRACK = Regexp.new(ENV.fetch("PER_TEST_COV_TRACK", "\\A(app|lib)/"))

  def self.snapshot
    out = {}
    Coverage.peek_result.each do |path, data|
      next unless path.start_with?(ROOT)
      rel = path.delete_prefix(ROOT)
      next unless rel.match?(TRACK)
      out[rel] = data.is_a?(Hash) ? data[:lines] : data
    end
    out
  end

  def self.diff(before, after)
    hit = {}
    after.each do |file, lines|
      prev = before[file]
      touched = []
      lines.each_with_index do |n, i|
        next if n.nil? || n.zero?
        touched << i + 1 if prev.nil? || n > (prev[i] || 0)
      end
      hit[file] = touched unless touched.empty?
    end
    hit
  end

  def self.eager_load_once
    return if @loaded
    @loaded = true
    Rails.application.eager_load! if defined?(Rails) && Rails.respond_to?(:application) && Rails.application
  end

  def self.write(record)
    require "json"
    require "fileutils"
    @io ||= begin
      FileUtils.mkdir_p(DIR)
      File.open(File.join(DIR, "cov-#{Process.pid}.jsonl"), "a")
    end
    @pid ||= Process.pid
    if @pid != Process.pid # forked worker: own file
      @pid = Process.pid
      @io = File.open(File.join(DIR, "cov-#{Process.pid}.jsonl"), "a")
    end
    @io.puts(JSON.generate(record))
    @io.flush
  end

  module Hook
    def before_setup
      super
      PerTestCoverage.eager_load_once
      @__ptc_before = PerTestCoverage.snapshot
    end

    def after_teardown
      if @__ptc_before
        # the class's file, not the method's: a test from an included module or a base class
        # must still be run through the file that defines this class
        file, line = method(name).source_location
        class_file = Object.const_source_location(self.class.name)&.first
        line = 0 if class_file && class_file != file
        PerTestCoverage.write(
          test: "#{self.class.name}##{name}",
          loc: "#{(class_file || file).to_s.delete_prefix(PerTestCoverage::ROOT)}:#{line}",
          failed: !passed?,
          cov: PerTestCoverage.diff(@__ptc_before, PerTestCoverage.snapshot)
        )
      end
      super
    end
  end
end

tp = TracePoint.new(:end) do |t|
  # Module#name, not t.self.name: gems redefine .name (Faker::Company.name makes up a company).
  # Not a constant lookup either: that autoloads ActiveSupport::TestCase inside this handler,
  # where Ruby does not trace, so its :end would never be seen.
  if t.self.is_a?(Module) && Module.instance_method(:name).bind_call(t.self) == "Minitest::Test"
    t.self.prepend(PerTestCoverage::Hook)
    tp.disable
  end
end
tp.enable
