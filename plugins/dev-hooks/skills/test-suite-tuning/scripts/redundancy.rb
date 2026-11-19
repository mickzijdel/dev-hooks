# Reads per-test coverage JSONL and reports prune CANDIDATES (never proof):
#   ruby redundancy.rb tmp/pertest [--json out.json]
require "json"
require "set"
dir = ARGV[0] || "tmp/pertest"
tests = {}
locs = {}
Dir[File.join(dir, "cov-*.jsonl")].each do |f|
  File.foreach(f) do |l|
    r = JSON.parse(l)
    set = Set.new
    r["cov"].each { |file, lines| lines.each { |n| set << "#{file}:#{n}" } }
    tests[r["test"]] = set
    locs[r["test"]] = r["loc"]
  end
end
count = Hash.new(0)
tests.each_value { |s| s.each { |k| count[k] += 1 } }
# lines hit by >=50% of tests are setup noise (layout, auth, callbacks)
noise = count.select { |_, c| c >= tests.size * 0.5 }.keys.to_set
sig = tests.transform_values { |s| s - noise }
uniq = sig.transform_values { |s| s.count { |k| count[k] == 1 } }
empty = sig.select { |_, s| s.empty? }.keys
no_unique = uniq.select { |t, u| u.zero? && !sig[t].empty? }.keys
groups = sig.reject { |_, s| s.empty? }.group_by { |_, s| s }.values.select { |g| g.size > 1 }.map { |g| g.map(&:first) }
puts "tests: #{tests.size}  tracked lines hit: #{count.size}  noise lines dropped: #{noise.size}"
puts "tests touching no tracked app line (beyond noise): #{empty.size}"
puts "tests with zero unique lines: #{no_unique.size}"
puts "identical-footprint groups: #{groups.size} (#{groups.sum(&:size)} tests)"
by_file = no_unique.group_by { |t| locs[t].split(":").first }.transform_values(&:size).sort_by { |_, v| -v }
puts "\nzero-unique tests per file (top 15):"
by_file.first(15).each { |f, n| puts "  #{n.to_s.rjust(4)}  #{f}" }
puts "\nlargest identical-footprint groups (top 8):"
groups.sort_by { |g| -g.size }.first(8).each { |g| puts "  #{g.size} tests, #{sig[g.first].size} lines: #{g.first(3).map { |t| locs[t] }.join(', ')}#{' ...' if g.size > 3}" }
if (i = ARGV.index("--json"))
  File.write(ARGV[i + 1], JSON.pretty_generate(empty: empty, no_unique: no_unique, groups: groups, locs: locs))
end
