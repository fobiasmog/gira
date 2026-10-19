namespace :announcements do
  desc "Publish an announcement: FILE=path/to/body.md (or Markdown on STDIN), WELCOME=1 for the sign-up welcome"
  task publish: :environment do
    body = ENV["FILE"] ? File.read(ENV.fetch("FILE")) : $stdin.read
    announcement = Announcement.create!(body: body.strip, welcome: ActiveModel::Type::Boolean.new.cast(ENV["WELCOME"]) || false)

    puts "Published #{announcement.welcome ? "welcome " : ""}announcement ##{announcement.id}"
  end
end
