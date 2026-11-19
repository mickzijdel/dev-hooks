class Gate
  def self.open?(age, member)
    return false unless age
    age >= 18 && member
  end
end
