require "test_helper"

# Spec openspec-changes, "Reading tasks.md" and "Goalner keys in the tasks
# text"; add-openspec-changes design.md, decisions 2, 3 and 6.
class OpenspecChange::TasksTextTest < ActiveSupport::TestCase
  def read(text) = OpenspecChange::TasksText.new(text)

  # Reading

  test "sections and items" do
    text = read(<<~MD)
      ## 1. Model

      - [x] 1.1 Add the table
      - [ ] 1.2 Add the model
    MD

    assert_equal [ "1. Model" ], text.sections.map(&:title)
    items = text.sections.first.items
    assert_equal [ "1.1 Add the table", "1.2 Add the model" ], items.map(&:title)
    assert_equal [ true, false ], items.map(&:checked?)
    assert_equal [ 3, 4 ], items.map(&:line)
    assert_equal 1, text.sections.first.line
  end

  test "an item over several lines takes the following lines, without their common indentation" do
    item = read(<<~MD).items.first
      ## 2. Accounts
      - [ ] 2.3 Add the handle:
        - word lists;
        - retries.

      - [ ] 2.4 Next
    MD

    assert_equal "2.3 Add the handle:", item.title
    assert_equal "- word lists;\n- retries.", item.description
  end

  test "a deeper task line belongs to the item before it" do
    text = read(<<~MD)
      ## 1. Prerequisites
      - [ ] 1.1 Prepare
        - [ ] 1.1.1 Check the schema
    MD

    assert_equal [ "1.1 Prepare" ], text.items.map(&:title)
    assert_equal "- [ ] 1.1.1 Check the schema", text.items.first.description
  end

  test "star bullets and capital X are items, as OpenSpec counts them" do
    items = read("## 3. Mixed\n* [X] 3.1 Done item\n- [ ] 3.2 Open item\n-[x]3.3 Tight\n").items

    assert_equal [ "3.1 Done item", "3.2 Open item", "3.3 Tight" ], items.map(&:title)
    assert_equal [ true, false, true ], items.map(&:checked?)
  end

  test "items before the first section belong to a loose Tasks section, and earlier lines are ignored" do
    text = read("# Tasks\n\nSome words.\n- [ ] Write the docs\n\n## 1. Later\n- [ ] 1.1 Item\n")

    assert_equal [ "Tasks", "1. Later" ], text.sections.map(&:title)
    assert text.sections.first.loose?
    assert_nil text.sections.first.line
    assert_equal [ "Write the docs" ], text.sections.first.items.map(&:title)
    assert_equal "", text.sections.first.introduction
  end

  test "a section without items makes no section" do
    text = read("## Notes\n\nJust a paragraph.\n\n## 1. Work\n- [ ] 1.1 Do it\n")

    assert_equal [ "1. Work" ], text.sections.map(&:title)
  end

  test "the lines between a heading and its first item are the section's introduction" do
    section = read("## 4. API\n\n  Routes first.\n  Then controllers.\n\n- [ ] 4.1 Routes\n").sections.first

    assert_equal "Routes first.\nThen controllers.", section.introduction
  end

  test "only level-2 headings start sections; deeper headings are text" do
    text = read("## 1. Work\n- [ ] 1.1 Item\n### Detail\nMore.\n# Title\n")

    assert_equal [ "1. Work" ], text.sections.map(&:title)
    assert_equal "### Detail\nMore.\n# Title", text.items.first.description
  end

  test "closing hashes of a heading are not part of its title" do
    assert_equal "1. Model", read("## 1. Model ##\n- [ ] 1.1 Item\n").sections.first.title
  end

  test "a long item is cut at a word boundary with an ellipsis, and its whole line opens the description" do
    line = "2.1 #{"word " * 70}end"
    item = read("## 2. Long\n- [ ] #{line}\n  - a detail.\n").items.first

    assert_operator line.length, :>, 255
    assert_operator item.title.length, :<=, 255
    assert item.title.end_with?("…")
    assert line.start_with?(item.title.delete_suffix("…"))
    assert_match(/word…\z/, item.title)
    assert_equal "#{line}\n\n- a detail.", item.description
  end

  test "a long title without spaces is cut hard" do
    title = OpenspecChange::TasksText.cut("x" * 300)

    assert_equal 255, title.length
    assert_equal "#{"x" * 254}…", title
  end

  test "UTF-8 text is kept as sent" do
    item = read("## 1. Модель\n- [ ] 1.1 Добавить таблицу — «быстро» 🚀\n  - подробности\n").items.first

    assert_equal "1.1 Добавить таблицу — «быстро» 🚀", item.title
    assert_equal "- подробности", item.description
  end

  test "CRLF line endings are read like LF" do
    text = read("## 1. Model\r\n- [x] 1.1 Add the table\r\n  - detail\r\n")

    assert_equal "1. Model", text.sections.first.title
    assert_equal "1.1 Add the table", text.items.first.title
    assert_equal "- detail", text.items.first.description
  end

  # Marks

  test "marks at the end of headings and items are read by their number, and are not part of titles" do
    text = read("## 1. Model <!-- goalner:TEST-20 -->\n- [ ] 1.1 Add the table <!-- goalner:QA-21 -->\n- [ ] 1.2 No mark\n")

    assert_equal 20, text.sections.first.mark
    assert_equal [ 21, nil ], text.items.map(&:mark)
    assert_equal [ "1.1 Add the table", "1.2 No mark" ], text.items.map(&:title)
    assert_equal "1. Model", text.sections.first.title
  end

  test "a malformed mark is no mark, and is not part of the title" do
    item = read("## 1. A\n- [ ] 1.1 Item <!-- goalner:lowercase-3 -->\n").items.first

    assert_nil item.mark
    assert_equal "1.1 Item", item.title
  end

  test "a mark in the middle of a line is text" do
    item = read("## 1. A\n- [ ] 1.1 See <!-- goalner:TEST-3 --> here\n").items.first

    assert_nil item.mark
    assert_equal "1.1 See <!-- goalner:TEST-3 --> here", item.title
  end

  # Rendering

  test "a text without marks comes back unchanged apart from the added marks" do
    source = "# Tasks\n\n## 1. Model\n\n- [ ] 1.1 Add the table\n  - detail\n- [x] 1.2 Add the model\n"
    text = read(source)

    rendered = text.render(keys: { 3 => "TEST-20", 5 => "TEST-21", 7 => "TEST-22" })

    assert_equal "# Tasks\n\n## 1. Model <!-- goalner:TEST-20 -->\n\n- [ ] 1.1 Add the table <!-- goalner:TEST-21 -->\n  - detail\n- [x] 1.2 Add the model <!-- goalner:TEST-22 -->\n", rendered
    assert_equal source, read(rendered).render(keys: {}).gsub(/ <!-- goalner:TEST-\d+ -->/, "")
  end

  test "a mark already in the text is replaced, so a changed short name is written anew" do
    text = read("## 1. Model <!-- goalner:TEST-20 -->  \n- [ ] 1.1 Item <!--goalner:TEST-21-->\n")

    assert_equal "## 1. Model <!-- goalner:QA-20 -->\n- [ ] 1.1 Item <!-- goalner:QA-21 -->\n",
      text.render(keys: { 1 => "QA-20", 2 => "QA-21" })
  end

  test "rendering is stable: marking a marked text again changes nothing" do
    once = read("## 1. A\n- [ ] 1.1 B\n").render(keys: { 1 => "TEST-1", 2 => "TEST-2" })

    assert_equal once, read(once).render(keys: { 1 => "TEST-1", 2 => "TEST-2" })
  end

  test "checking an item changes only its checkbox" do
    text = read("## 1. A\n  - [ ] 1.1 B\n- [x] 1.2 C\n\t* [ ] 1.3 D\n")

    assert_equal "## 1. A\n  - [x] 1.1 B\n- [x] 1.2 C\n\t* [x] 1.3 D\n", text.render(checked: [ 2, 3, 4 ])
  end

  test "CRLF endings survive marks and checkboxes" do
    text = read("## 1. A\r\n- [ ] 1.1 B\r\n  - detail\r\n")

    assert_equal "## 1. A <!-- goalner:TEST-1 -->\r\n- [x] 1.1 B <!-- goalner:TEST-2 -->\r\n  - detail\r\n",
      text.render(keys: { 1 => "TEST-1", 2 => "TEST-2" }, checked: [ 2 ])
  end

  test "UTF-8 survives rendering" do
    text = read("## 1. Модель\n- [ ] 1.1 Таблица 🚀\n")

    assert_equal "## 1. Модель <!-- goalner:TEST-1 -->\n- [ ] 1.1 Таблица 🚀 <!-- goalner:TEST-2 -->\n",
      text.render(keys: { 1 => "TEST-1", 2 => "TEST-2" })
  end

  test "this change's own tasks.md reads as twenty items in seven sections, with every mark" do
    text = read(Rails.root.join("openspec/changes/archive/2026-11-16-add-openspec-changes/tasks.md").read)

    assert_equal 7, text.sections.size
    assert_equal 20, text.items.size
    assert text.sections.all?(&:mark)
    assert text.items.all?(&:mark)
    assert text.items.all? { |item| item.title.length <= 255 }
  end
end
