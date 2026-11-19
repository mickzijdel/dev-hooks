require "minitest/autorun"
require_relative "../lib/gate"

class GateTest < Minitest::Test
  def test_adult_member_may_enter = assert(Gate.open?(30, true))
  def test_child_may_not_enter = refute(Gate.open?(10, true))
  def test_eighteen_year_old_member_may_enter = assert(Gate.open?(18, true))
  def test_unknown_age_may_not_enter = refute(Gate.open?(nil, true))
end
