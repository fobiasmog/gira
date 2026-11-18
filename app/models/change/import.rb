# Imports an OpenSpec change's tasks.md into the project's open change of
# that name, creating the change when there is none (spec openspec-changes;
# add-openspec-changes design.md, decisions 3 to 5; replace-sprints-with-changes
# design.md, decision 4). Sections become cards, items their subtasks, all in
# the change, and the text comes back with each heading and item marked with
# its task's key and each done item checked.
#
# The import owns the tasks it created or matched by a mark (in_tasks_md):
# only those are archived when their marks are gone. Tasks added to the
# change by hand are left alone until a mark names them, which adopts them.
#
# The proposal, the design and the delta specs, when sent, become the
# change's files, replacing those of the last import; the import is recorded
# in the change's history, and a change in Idea or Exploring moves to
# Proposed (add-change-conversation design.md, decisions 4 to 6).
#
# An import runs under the project's lock in one transaction, so it lands
# completely or not at all. Refusals raise ActiveRecord::RecordInvalid,
# naming the field and, for the text, the line; a re-import that carries no
# mark at all raises KeysMissing.
class Change::Import
  ARTIFACTS = %w[tasks proposal design specs].freeze
  # Artifacts stored as a file each, with the path they are stored at.
  DOCUMENTS = { "proposal" => ChangeFile::PROPOSAL, "design" => ChangeFile::DESIGN }.freeze
  MAX_TEXT_LENGTH = 100_000
  MAX_SECTIONS = 50
  MAX_ITEMS = 500
  MAX_SPECS = 50
  # Phases an import moves on to Proposed.
  BEFORE_PROPOSED = %w[idea exploring].freeze

  # The text carries no mark although tasks.md cards of the change are kept:
  # the client did not save the text the last import returned.
  class KeysMissing < StandardError
    attr_reader :change

    def initialize(change)
      @change = change
      super("keys missing")
    end
  end

  Result = Data.define(:change, :created)

  def initialize(project:, user:, name:, artifacts:)
    @project, @user, @name, @artifacts = project, user, name, artifacts
  end

  def run!
    @project.with_lock do
      @change = @project.project_changes.kept.find_or_initialize_by(name: @name.to_s)
      created = @change.new_record?
      validate_input!
      @text = Change::TasksText.new(@artifacts["tasks"])
      validate_text!
      @marked = resolve_marks!
      raise KeysMissing, @change if !created && no_marks? && owned_tasks.exists?

      save_change!
      upsert_tasks!
      archive_unmatched!
      complete_items!
      @change.update!(tasks_text: @text.render(keys: keys_by_line, checked: done_lines))
      store_files!
      record!
      Result.new(change: @change, created:)
    end
  end

  private
    attr_reader :change

    # Name and artifacts.
    def validate_input!
      change.errors.add(:name, :invalid) unless Change.valid_name?(@name)

      artifacts = @artifacts.is_a?(Hash) ? @artifacts.stringify_keys : {}
      (artifacts.keys - ARTIFACTS).each { |key| change.errors.add(key.to_sym, "is not an artifact Goalner imports") }
      if !artifacts["tasks"].is_a?(String)
        change.errors.add(:tasks, :blank)
      elsif artifacts["tasks"].length > MAX_TEXT_LENGTH
        change.errors.add(:tasks, :too_long, count: MAX_TEXT_LENGTH)
      end
      DOCUMENTS.each_key { |key| validate_document(key, artifacts[key]) }
      validate_specs(artifacts["specs"])
      @artifacts = artifacts
      refuse!
    end

    # A proposal or a design: a text, or null for none.
    def validate_document(key, text)
      if !text.nil? && !text.is_a?(String)
        change.errors.add(key.to_sym, "must be a text")
      elsif text && text.length > MAX_TEXT_LENGTH
        # A message, not :too_long, which would read the attribute from Change.
        change.errors.add(key.to_sym, I18n.t("errors.messages.too_long", count: MAX_TEXT_LENGTH))
      end
    end

    # An object of capability path => text of its spec.md, or null for none.
    # Each refused key is named.
    def validate_specs(specs)
      return if specs.nil?
      return change.errors.add(:specs, "must be an object whose keys are capability paths") unless specs.is_a?(Hash)

      change.errors.add(:specs, "has #{specs.size} specs; an import carries at most #{MAX_SPECS}") if specs.size > MAX_SPECS
      specs.each do |capability, text|
        if !ChangeFile.valid_capability?(capability)
          change.errors.add(:specs, "#{capability}: is not a capability path; use lowercase letters and digits joined by single hyphens, separated by single slashes, such as identity/user-auth")
        elsif !text.is_a?(String)
          change.errors.add(:specs, "#{capability}: must be a text")
        elsif text.length > MAX_TEXT_LENGTH
          change.errors.add(:specs, "#{capability}: is too long (maximum is #{MAX_TEXT_LENGTH} characters)")
        end
      end
    end

    def validate_text!
      sections = @text.sections.size
      items = @text.items.size
      change.errors.add(:tasks, "has #{sections} sections; a change has at most #{MAX_SECTIONS}") if sections > MAX_SECTIONS
      change.errors.add(:tasks, "has #{items} items; a change has at most #{MAX_ITEMS}") if items > MAX_ITEMS
      @text.items.select { |item| item.text.empty? }.each do |item|
        change.errors.add(:tasks, "line #{item.line}: the item has no title")
      end
      refuse!
    end

    # Each heading or item line with a mark => its task, or nil when the mark
    # names an archived task of the change (treated as no mark). Any task of
    # the change may be named, including one added by hand.
    def resolve_marks!
      lines = @text.sections.reject(&:loose?).filter_map { |section| [ section, true ] if section.mark } +
        @text.items.filter_map { |item| [ item, false ] if item.mark }
      tasks = @project.tasks.where(number: lines.map { |line, _| line.mark }).index_by(&:number)
      seen = {}

      lines.sort_by { |line, _| line.line }.each_with_object({}) do |(line, heading), marked|
        task = tasks[line.mark]
        error = if seen[line.mark]
          "line #{line.line}: the mark of #{task&.key || line.mark} is already on line #{seen[line.mark]}"
        elsif task.nil?
          "line #{line.line}: the mark names no task of this project"
        elsif change.new_record? || task.change_id != change.id
          "line #{line.line}: the mark names #{task.key}, which does not belong to this change"
        elsif heading && !task.root?
          "line #{line.line}: the heading's mark names #{task.key}, a subtask"
        elsif !heading && task.root?
          "line #{line.line}: the item's mark names #{task.key}, a card"
        end
        seen[line.mark] ||= line.line
        error ? change.errors.add(:tasks, error) : (marked[line.line] = (task unless task.archived?))
      end.tap { refuse! }
    end

    def no_marks?
      @text.sections.none?(&:mark) && @text.items.none?(&:mark)
    end

    # The tasks this import owns from earlier imports.
    def owned_tasks
      change.tasks.kept.where(in_tasks_md: true)
    end

    # A change the import creates starts in Proposed.
    def save_change!
      change.phase = "proposed" if change.new_record?
      change.update!(imported_by: @user, imported_at: Time.current)
    end

    # path => text of each file sent, in the order of ChangeFile.in_order.
    def files_sent
      @files_sent ||= begin
        documents = DOCUMENTS.filter_map { |key, path| [ path, @artifacts[key] ] unless @artifacts[key].nil? }
        specs = (@artifacts["specs"] || {}).map { |capability, text| [ ChangeFile.spec_path(capability), text ] }.sort_by(&:first)
        (documents + specs).to_h
      end
    end

    # The files of a change are those of its last import.
    def store_files!
      change.files.where.not(path: files_sent.keys).delete_all
      stored = change.files.where(path: files_sent.keys).index_by(&:path)
      files_sent.each { |path, text| (stored[path] || change.files.build(path:)).update!(text:) }
    end

    # The import first, then the move it causes.
    def record!
      change.events.create!(kind: "import", actor: @user, paths: [ *files_sent.keys, ChangeFile::TASKS ])
      change.move_to!("proposed", by: @user) if BEFORE_PROPOSED.include?(change.phase)
    end

    # Cards and subtasks in text order, so new ones are added in that order.
    def upsert_tasks!
      @tasks_by_line = {}
      @cards = {}
      @text.sections.each do |section|
        card = upsert(section.loose? ? loose_card : @marked[section.line],
          title: card_title(section), description: card_description(section))
        @cards[section] = card
        @tasks_by_line[section.line] = card unless section.loose?

        section.items.each do |item|
          @tasks_by_line[item.line] = upsert(@marked[item.line], title: item.title, description: item.description, parent: card)
        end
      end
    end

    # A matched task, adopted when it was added by hand, or a new one in the
    # change; a new card starts in the first column.
    def upsert(task, **attributes)
      if task
        task.update!(**attributes, in_tasks_md: true)
        task
      else
        defaults = attributes[:parent] ? {} : { status: @project.first_status }
        @project.tasks.create!(**defaults, **attributes, creator: @user, change:, in_tasks_md: true)
      end
    end

    # The card of items before any heading has no line to carry a mark. It is
    # the change's unmarked tasks.md card with the loose section's title.
    def loose_card
      marked_ids = @marked.values.compact.map(&:id)
      owned_tasks.roots.where(title: card_title(@text.sections.find(&:loose?))).where.not(id: marked_ids).order(:id).first
    end

    def card_title(section)
      Change::TasksText.cut("#{change.name}: #{section.title}")
    end

    def card_description(section)
      folder = "OpenSpec change `#{change.name}`, section \"#{section.title}\": `openspec/changes/#{change.name}/`"
      [ folder, section.introduction ].reject(&:empty?).join("\n\n")
    end

    # tasks.md tasks whose marks are gone. A card goes together with its
    # remaining subtasks, added by hand or not, which go first.
    def archive_unmatched!
      kept = @tasks_by_line.values.map(&:id) + @cards.values.map(&:id)
      gone = owned_tasks.where.not(id: kept).to_a
      gone += Task.kept.where(parent_id: gone.select(&:root?).map(&:id)).where.not(id: kept + gone.map(&:id)).to_a
      gone.sort_by { |task| task.root? ? 1 : 0 }.each(&:archive!)
    end

    # Forward only: checked items are completed, nothing is reopened, and a
    # card whose items are all done moves to the done column.
    def complete_items!
      done = @project.done_status
      @text.sections.each do |section|
        section.items.each do |item|
          subtask = @tasks_by_line[item.line]
          subtask.update!(status: done) if item.checked? && !subtask.done?
        end

        card = @cards[section]
        if !card.done? && section.items.all? { |item| @tasks_by_line[item.line].done? }
          card.update!(status: done)
        end
      end
    end

    def keys_by_line
      @tasks_by_line.except(nil).transform_values(&:key)
    end

    def done_lines
      @text.items.filter_map { |item| item.line if @tasks_by_line[item.line].done? }
    end

    def refuse!
      raise ActiveRecord::RecordInvalid, change if change.errors.any?
    end
end
