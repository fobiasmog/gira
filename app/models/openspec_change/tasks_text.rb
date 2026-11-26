# The text of an OpenSpec tasks.md, read into sections and items (spec
# openspec-changes, "Reading tasks.md"; add-openspec-changes design.md,
# decisions 2, 3 and 6), and written back with Goalner marks and checkboxes.
#
# Items are the lines OpenSpec itself counts as tasks, so Goalner's progress
# and `openspec archive` agree. Nothing else in the Markdown is interpreted.
class OpenspecChange::TasksText
  # OpenSpec's own task pattern (utils/task-progress.js in @fission-ai/openspec).
  TASK_LINE = /\A\s*[-*]\s*\[([\sxX])\]\s*(.*)/
  HEADING = /\A {0,3}##[ \t]+(.*)\z/
  # A mark names a task by its key; only the number after the hyphen counts,
  # so a project's short name may change.
  MARK = /<!--\s*goalner:[A-Z][A-Z0-9]*-(\d+)\s*-->[ \t]*\z/
  # Any goalner mark at the end of a line, with the whitespace before it.
  TRAILING_MARK = /[ \t]*(?:<!--\s*goalner:[^>]*-->[ \t]*)?\z/
  CHECKBOX = /\A(\s*[-*]\s*\[)\s\]/
  TITLE_LIMIT = 255
  ELLIPSIS = "…"
  LOOSE_SECTION_TITLE = "Tasks"

  # Cuts a title longer than the limit at the last space that leaves room
  # for the ellipsis, or hard when there is no space.
  def self.cut(title)
    return title if title.length <= TITLE_LIMIT

    head = title[0, TITLE_LIMIT - ELLIPSIS.length]
    space = head.rindex(/\s/)
    head = head[0, space] if space&.positive?
    "#{head.rstrip}#{ELLIPSIS}"
  end

  # Joins lines with their blank first and last lines dropped and their
  # common indentation removed (leading tabs count as four spaces).
  def self.dedent(lines)
    lines = lines.map { |line| line.sub(/\A[ \t]+/) { |space| space.gsub("\t", "    ") } }
    lines = lines.drop_while(&:blank?).reverse.drop_while(&:blank?).reverse
    indent = lines.reject(&:blank?).map { |line| line[/\A */].length }.min || 0
    lines.map { |line| line[indent..] || "" }.join("\n")
  end

  class Item
    attr_reader :text, :line, :mark, :description_lines

    def initialize(text:, line:, mark:, checked:)
      @text, @line, @mark, @checked = text, line, mark, checked
      @description_lines = []
    end

    def checked? = @checked

    def title = OpenspecChange::TasksText.cut(text)

    # The whole line opens the description when the title had to be cut.
    def description
      rest = OpenspecChange::TasksText.dedent(description_lines)
      return rest if text.length <= TITLE_LIMIT

      [ text, rest ].reject(&:empty?).join("\n\n")
    end
  end

  class Section
    attr_reader :title, :line, :mark, :intro_lines, :items

    # line and mark are nil for the section of items before any heading.
    def initialize(title:, line: nil, mark: nil)
      @title, @line, @mark = title, line, mark
      @intro_lines = []
      @items = []
    end

    def loose? = line.nil?

    def introduction = OpenspecChange::TasksText.dedent(intro_lines)
  end

  attr_reader :sections

  def initialize(text)
    @lines = text.to_s.split("\n", -1)
    @sections = parse.select { |section| section.items.any? }
  end

  def items = sections.flat_map(&:items)

  # The text with each line in `keys` (line number => task key) ending in
  # its mark, and the checkbox of each item line in `checked` checked. Every
  # other byte stays as it was, line endings included.
  def render(keys: {}, checked: [])
    @lines.each_with_index.map do |raw, index|
      number = index + 1
      next raw unless keys.key?(number) || checked.include?(number)

      ending = raw.end_with?("\r") ? "\r" : ""
      line = raw.chomp("\r")
      line = line.sub(CHECKBOX, '\1x]') if checked.include?(number)
      line = "#{line.sub(TRAILING_MARK, "")} <!-- goalner:#{keys[number]} -->" if keys.key?(number)
      line + ending
    end.join("\n")
  end

  private
    def parse
      sections = []
      section = item = indent = nil

      @lines.each_with_index do |raw, index|
        line = raw.chomp("\r")

        if (heading = line[HEADING, 1])
          section = Section.new(title: heading_title(heading), line: index + 1, mark: mark_in(line))
          sections << section
          item = indent = nil
        elsif (task = line.match(TASK_LINE)) && (indent.nil? || indent_of(line) <= indent)
          section ||= Section.new(title: LOOSE_SECTION_TITLE).tap { |loose| sections << loose }
          indent ||= indent_of(line)
          item = Item.new(text: without_mark(task[2]).strip, line: index + 1, mark: mark_in(line), checked: task[1].match?(/[xX]/))
          section.items << item
        elsif item
          item.description_lines << line
        elsif section
          section.intro_lines << line
        end
      end

      sections
    end

    def heading_title(text)
      without_mark(text).sub(/[ \t]+#+[ \t]*\z/, "").strip
    end

    def without_mark(text) = text.sub(TRAILING_MARK, "")

    def mark_in(line) = line[MARK, 1]&.to_i

    def indent_of(line) = line[/\A[ \t]*/].gsub("\t", "    ").length
end
