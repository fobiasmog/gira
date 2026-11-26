# Imports an OpenSpec change's tasks.md into a project (spec openspec-changes;
# add-openspec-changes design.md, decisions 3 to 5): sections become cards,
# items their subtasks, and the text comes back with each heading and item
# marked with its task's key and each done item checked.
#
# An import runs under the project's lock in one transaction, so it lands
# completely or not at all. Refusals raise ActiveRecord::RecordInvalid,
# naming the field and, for the text, the line; a re-import that carries no
# mark at all raises KeysMissing.
class OpenspecChange::Import
  ARTIFACTS = %w[tasks].freeze
  MAX_TEXT_LENGTH = 100_000
  MAX_CARDS = 50
  MAX_SUBTASKS = 500

  # The text carries no mark although the change has tasks: the client did
  # not save the text the last import returned.
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
      @change = @project.openspec_changes.find_or_initialize_by(name: @name.to_s)
      created = @change.new_record?
      validate_input!
      @text = OpenspecChange::TasksText.new(@artifacts["tasks"])
      validate_text!
      @marked = resolve_marks!
      raise KeysMissing, @change if !created && no_marks? && @change.tasks.kept.exists?

      save_change!
      upsert_tasks!
      archive_unmatched!
      complete_items!
      @change.update!(tasks_text: @text.render(keys: keys_by_line, checked: done_lines))
      Result.new(change: @change, created:)
    end
  end

  private
    attr_reader :change

    # Name and artifacts.
    def validate_input!
      if !@name.is_a?(String) || !OpenspecChange::NAME_FORMAT.match?(@name) || @name.length > 100
        change.errors.add(:name, :invalid)
      end

      artifacts = @artifacts.is_a?(Hash) ? @artifacts.stringify_keys : {}
      (artifacts.keys - ARTIFACTS).each { |key| change.errors.add(key.to_sym, "is not an artifact Goalner imports") }
      if !artifacts["tasks"].is_a?(String)
        change.errors.add(:tasks, :blank)
      elsif artifacts["tasks"].length > MAX_TEXT_LENGTH
        change.errors.add(:tasks, :too_long, count: MAX_TEXT_LENGTH)
      end
      @artifacts = artifacts
      refuse!
    end

    def validate_text!
      cards = @text.sections.size
      subtasks = @text.items.size
      change.errors.add(:tasks, "has #{cards} sections; a change has at most #{MAX_CARDS}") if cards > MAX_CARDS
      change.errors.add(:tasks, "has #{subtasks} items; a change has at most #{MAX_SUBTASKS}") if subtasks > MAX_SUBTASKS
      @text.items.select { |item| item.text.empty? }.each do |item|
        change.errors.add(:tasks, "line #{item.line}: the item has no title")
      end
      refuse!
    end

    # Each heading or item line with a mark => its task, or nil when the mark
    # names an archived task of the change (treated as no mark).
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
        elsif change.new_record? || task.openspec_change_id != change.id
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

    def save_change!
      milestone = change.milestone || @project.milestones.create!(title: change.name)
      milestone.recover! if milestone.deleted?
      change.update!(milestone:, imported_by: @user, imported_at: Time.current)
    end

    # Cards and subtasks in text order, so new ones are added in that order.
    def upsert_tasks!
      @tasks_by_line = {}
      @cards = {}
      @text.sections.each do |section|
        card = upsert(section.loose? ? loose_card : @marked[section.line],
          title: card_title(section), description: card_description(section), milestone: change.milestone)
        @cards[section] = card
        @tasks_by_line[section.line] = card unless section.loose?

        section.items.each do |item|
          @tasks_by_line[item.line] = upsert(@marked[item.line], title: item.title, description: item.description, parent: card)
        end
      end
    end

    def upsert(task, **attributes)
      if task
        task.update!(attributes)
        task
      else
        defaults = attributes[:parent] ? {} : { status: @project.first_status, sprint: @project.active_sprint }
        @project.tasks.create!(**defaults, **attributes, creator: @user, openspec_change: change)
      end
    end

    # The card of items before any heading has no line to carry a mark. It is
    # the change's unmarked card with the loose section's title.
    def loose_card
      marked_ids = @marked.values.compact.map(&:id)
      change.tasks.kept.roots.where(title: card_title(@text.sections.find(&:loose?))).where.not(id: marked_ids).order(:id).first
    end

    def card_title(section)
      OpenspecChange::TasksText.cut("#{change.name}: #{section.title}")
    end

    def card_description(section)
      folder = "OpenSpec change `#{change.name}`, section \"#{section.title}\": `openspec/changes/#{change.name}/`"
      [ folder, section.introduction ].reject(&:empty?).join("\n\n")
    end

    # A card goes together with its remaining subtasks, which go first.
    def archive_unmatched!
      kept = @tasks_by_line.values.map(&:id) + @cards.values.map(&:id)
      gone = change.tasks.kept.where.not(id: kept).to_a
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
