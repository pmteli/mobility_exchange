module EquipmentMedia
  # Conservative pilot rules: absent equipment labels are never sufficient to reject.
  class EquipmentClassifier
    EQUIPMENT = ['wheelchair', 'manual wheelchair', 'walker', 'walking frame', 'rollator', 'walking stick', 'walking cane', 'cane', 'crutch', 'crutches', 'shower chair', 'bath chair', 'commode', 'commode chair'].freeze
    UNRELATED = ['dog', 'cat', 'pizza', 'hamburger', 'cake', 'sandwich', 'car', 'motorcycle', 'airplane'].freeze
    def self.classify(labels)
      candidates = labels.select { |l| ([l[:name]] + Array(l[:aliases])).any? { |name| EQUIPMENT.include?(name.to_s.downcase) } }
      return 'recognized' if candidates.any? { |l| l[:confidence].to_f >= 80 }
      return 'uncertain' if candidates.any? # A possible aid wins over unrelated background objects.
      dominant = labels.any? do |l|
        UNRELATED.include?(l[:name].to_s.downcase) && l[:confidence].to_f >= 95 &&
          Array(l[:instances]).any? { |i| i[:confidence].to_f >= 95 && i[:area].to_f >= 0.5 }
      end
      dominant ? 'unrelated' : 'uncertain'
    end
  end
end
