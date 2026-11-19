# Which routes the tests reach, and whether any test sees each one refused. Rails, Minitest.
#   rm -rf tmp/route_hits && RUBYOPT="-r/abs/route_hits.rb" t       record (forked workers are
#                                                                    fine, threaded ones are not)
#   bin/rails runner /abs/route_hits.rb report                      compare with the routes
# Writes one line per request to tmp/route_hits/hits-<pid>.jsonl.
# "Refused": a before_action halted the request (it rendered or redirected, so the action never
# ran), Devise/Warden threw, a 401/403/404, a NotAuthorized/AccessDenied/RecordNotFound
# exception, or a non-2xx answer from outside any controller (a routing constraint such as
# Devise's `authenticate` block). A route only ever reached successfully has no test that shows
# who may NOT use it. A 422 (invalid form) is not a refusal: it says nothing about access.
# Engine routes, mounted Rack apps and redirect() routes have no controller and are left out.
DIR = File.expand_path("tmp/route_hits")
REFUSED = /NotAuthorized|AccessDenied|Forbidden|RecordNotFound|InvalidAuthenticityToken/

if ARGV.first == "report" && defined?(Rails.application)
  require "json"
  hits = Dir[File.join(DIR, "hits-*.jsonl")].flat_map { File.readlines(_1) }.map { JSON.parse(_1) }
  abort "no hits in #{DIR}: record first" if hits.empty?
  all_routes = Rails.application.routes.routes.filter_map do |r|
    c, a = r.defaults.values_at(:controller, :action)
    next unless c && a && !c.start_with?("rails/", "active_storage/", "action_mailbox/", "turbo/")
    { action: "#{c.camelize}Controller##{a}", verb: r.verb, route: r,
      label: "#{r.verb.presence || 'ANY'} #{r.path.spec.to_s.sub('(.:format)', '')}" }
  end
  routes = all_routes.uniq { _1[:action] } # one line per action (PUT and PATCH share #update)
  # a request refused before any controller ran has no action: find the route it aimed at
  hits.each do |h|
    h["action"] ||= all_routes.find { |r| (r[:verb].blank? || r[:verb].split("|").include?(h["verb"])) && r[:route].path.match(h["path"]) }&.dig(:action)
  end
  by_action = hits.group_by { _1["action"] }
  never = routes.reject { by_action.key?(_1[:action]) }
  only_ok = routes.select { (h = by_action[_1[:action]]) && h.none? { |x| x["refused"] } }
  puts "routes: #{routes.size}, reached by a test: #{routes.size - never.size}, tests recorded: #{hits.map { _1['test'] }.uniq.size}"
  puts "\nno test reaches (#{never.size}):"
  never.each { puts "  #{_1[:label].ljust(50)} #{_1[:action]}" }
  puts "\nreached, but never refused (#{only_ok.size}): check each needs no sign-in or role"
  only_ok.each { puts "  #{_1[:label].ljust(50)} #{_1[:action]}  (#{by_action[_1[:action]].size} hits)" }
  return
end

module RouteHitsName
  def before_setup = ($__route_test = "#{self.class.name}##{name}"; super)
end

module RouteHitsIntegration
  def process(method, path, **kw)
    $__route_ctl = nil
    $__route_in_request = true
    super
  ensure
    $__route_in_request = false
    ctl = $__route_ctl
    status = response&.status
    refused = ctl ? ctl[:refused] : (status.nil? || (status >= 300 && status != 422))
    RouteHits.write(verb: method.to_s.upcase, path: path.to_s.sub(%r{\Ahttps?://[^/]+}, "").split("?").first,
                    status:, action: ctl&.dig(:action), by: ctl&.dig(:by), refused:)
  end
end

module RouteHits
  def self.write(**h)
    FileUtils.mkdir_p(DIR)
    File.open(File.join(DIR, "hits-#{Process.pid}.jsonl"), "a") { _1.puts({ test: $__route_test, **h }.to_json) }
  end
end

tp = TracePoint.new(:end) do |t|
  # Module#name, not t.self.name: gems redefine .name (Faker::Company.name makes up a company).
  # Not a constant lookup either: that autoloads ActiveSupport::TestCase inside this handler,
  # where Ruby does not trace, so its :end would never be seen.
  next unless t.self.is_a?(Module) && Module.instance_method(:name).bind_call(t.self) == "ActiveSupport::TestCase"
  tp.disable
  require "json"
  require "fileutils"
  t.self.prepend(RouteHitsName)
  ActiveSupport.on_load(:action_dispatch_integration_test) { ActionDispatch::Integration::Session.prepend(RouteHitsIntegration) }
  halted = nil
  ActiveSupport::Notifications.subscribe("halted_callback.action_controller") { |*, p| halted = p[:filter].to_s }
  ActiveSupport::Notifications.subscribe("process_action.action_controller") do |*, p|
    status = p[:status]
    refused = !!(halted || (status.nil? && !p[:exception]) || [401, 403, 404].include?(status) ||
                 p[:exception]&.first.to_s.match?(REFUSED))
    ctl = { action: "#{p[:controller]}##{p[:action]}", by: halted, refused: }
    halted = nil
    # integration requests are written by the session hook; controller tests (no router) here
    $__route_in_request ? ($__route_ctl = ctl) : RouteHits.write(status:, **ctl)
  end
end
tp.enable
