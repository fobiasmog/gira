# Between tests Capybara 3.40 (the latest release) resets Chrome by clearing
# cookies and local storage with one CDP call for every origin:
# Storage.clearDataForOrigin with origin "*". Chrome 158 rejects the wildcard
# ("invalid argument: * is not a valid URL"), which errors every system test
# in teardown. This clears the same storage for the app's origin, the only one
# the tests visit, so a sign-in or UI state cannot leak into the next test.
# Drop it once a Capybara release stops passing "*".
require "capybara/selenium/driver"

module ChromeStorageReset
  private
    def execute_cdp(cmd, params = {})
      if cmd == "Storage.clearDataForOrigin" && params[:origin] == "*"
        params = params.merge(origin: Capybara.app_host || Capybara.current_session.server.base_url)
      end
      super
    end
end

Capybara::Selenium::Driver::ChromeDriver.prepend(ChromeStorageReset)
