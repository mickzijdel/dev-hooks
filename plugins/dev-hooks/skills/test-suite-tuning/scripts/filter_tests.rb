# Run only the tests named (Class#method, one per line) in $ONLY_TESTS_FILE.
# Loaded via RUBYOPT, so no regex has to survive a shell (GNU sem re-splits arguments).
names = File.readlines(ENV.fetch("ONLY_TESTS_FILE"), chomp: true)
ONLY_TESTS = names.each_with_object({}) { |n, h| h[n] = true }.freeze
module OnlyTests
  def runnable_methods = super.select { |m| ONLY_TESTS["#{name}##{m}"] }
end
tp = TracePoint.new(:end) do |t|
  # Module#name, not t.self.name: gems redefine .name (Faker::Company.name makes up a company).
  # Not a constant lookup either: that autoloads ActiveSupport::TestCase inside this handler,
  # where Ruby does not trace, so its :end would never be seen.
  if t.self.is_a?(Module) && Module.instance_method(:name).bind_call(t.self) == "Minitest::Test"
    t.self.singleton_class.prepend(OnlyTests)
    tp.disable
  end
end
tp.enable
