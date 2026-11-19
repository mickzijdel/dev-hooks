# Share of test time per ActiveSupport event, a stdlib stand-in for TestProf EventProf/TagProf.
#   RUBYOPT=-r/abs/event_share.rb MAX_WORKERS=1 t              (through the test queue)
#   RUBYOPT=-r/abs/event_share.rb PARALLEL_WORKERS=1 bin/rails test
# Serial only: forked workers record in processes this report never sees.
EVENTS = %w[sql.active_record render_template.action_view render_partial.action_view
            process_action.action_controller perform.active_job deliver.action_mailer].freeze
$__ev = Hash.new(0.0); $__ev_n = Hash.new(0)
$__tests = 0
module EventShareCount
  def before_setup = ($__tests += 1; super)
end
tp = TracePoint.new(:end) do |t|
  # Module#name, not t.self.name: gems redefine .name (Faker::Company.name makes up a company).
  # Not a constant lookup either: that autoloads ActiveSupport::TestCase inside this handler,
  # where Ruby does not trace, so its :end would never be seen.
  next unless t.self.is_a?(Module) && Module.instance_method(:name).bind_call(t.self) == "ActiveSupport::TestCase"
  tp.disable
  t.self.prepend(EventShareCount)
  ActiveSupport::Notifications.monotonic_subscribe(/\A(#{EVENTS.map { Regexp.escape(_1) }.join('|')})\z/) do |name, s, f, _id, payload|
    next if name == "sql.active_record" && payload[:name] == "SCHEMA"
    $__ev[name] += f - s; $__ev_n[name] += 1
  end
  $__t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  pid0 = Process.pid
  at_exit do
    next unless Process.pid == pid0 # forked workers inherit this hook
    next warn("\n[event_share] no tests ran in this process (forked workers ran them). Rerun serially.") if $__tests.zero?
    total = Process.clock_gettime(Process::CLOCK_MONOTONIC) - $__t0
    warn "\n[event_share] #{$__tests} tests, wall in process: #{total.round(1)}s (events nest: controller time includes its SQL and renders)"
    $__ev.sort_by { -_2 }.each { |k, v| warn format("  %-34s %7.1fs %5.1f%%  n=%d", k, v, 100 * v / total, $__ev_n[k]) }
  end
end
tp.enable
