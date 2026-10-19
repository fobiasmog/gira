require "test_helper"

class Api::TeammatesControllerTest < ActionDispatch::IntegrationTest
  test "teammates are the distinct users sharing a non-archived project" do
    alice = users(:one)
    carol = users(:stranger)
    project_b = Project.create!(title: "B", short_name: "BBB", owner: alice)
    project_b.memberships.create!(user: carol)
    project_b.memberships.create!(user: users(:two)) # Bob shares two projects, listed once
    archived = Project.create!(title: "Old", short_name: "OLD", owner: alice)
    archived.memberships.create!(user: User.create!(name: "Dan", email_address: "dan@example.com", password: "a long password"))
    archived.archive!
    sign_in_as alice

    get api_teammates_path

    assert_equal [ "Stranger", "User Two" ], response.parsed_body.map { |t| t["name"] }
  end
end
