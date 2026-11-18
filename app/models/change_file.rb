# An OpenSpec file of a change as its last import sent it (spec
# openspec-changes, "Files of a change"; add-change-conversation design.md,
# decision 5): proposal.md, design.md or the spec.md of a delta spec.
# tasks.md is not one of them: its text is Change#tasks_text.
class ChangeFile < ApplicationRecord
  PROPOSAL = "proposal.md"
  DESIGN = "design.md"
  TASKS = "tasks.md"
  MAX_LENGTH = 100_000
  # The folders under a change's specs/: groups of lowercase letters and
  # digits joined by single hyphens, separated by single slashes.
  CAPABILITY_FORMAT = %r{\A[a-z0-9]+(?:-[a-z0-9]+)*(?:/[a-z0-9]+(?:-[a-z0-9]+)*)*\z}
  SPEC_PATH_FORMAT = %r{\Aspecs/(.+)/spec\.md\z}

  belongs_to :change

  # proposal.md, design.md, then the spec files by path, byte by byte.
  scope :in_order, -> {
    order(Arel.sql("CASE change_files.path WHEN 'proposal.md' THEN 0 WHEN 'design.md' THEN 1 ELSE 2 END"), Arel.sql('change_files.path COLLATE "C"'))
  }

  validates :path, uniqueness: { scope: :change_id }
  validate :path_is_an_openspec_file
  validates :text, length: { maximum: MAX_LENGTH }
  validate { errors.add(:text, :blank) if text.nil? }

  def self.valid_capability?(capability)
    capability.is_a?(String) && CAPABILITY_FORMAT.match?(capability)
  end

  def self.spec_path(capability) = "specs/#{capability}/spec.md"

  def self.valid_path?(path)
    return false unless path.is_a?(String)

    [ PROPOSAL, DESIGN ].include?(path) || valid_capability?(path[SPEC_PATH_FORMAT, 1])
  end

  private
    def path_is_an_openspec_file
      errors.add(:path, :invalid) unless self.class.valid_path?(path)
    end
end
