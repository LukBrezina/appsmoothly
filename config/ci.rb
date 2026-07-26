# Run using bin/ci

CI.run do
  step "Setup", "bin/setup --skip-server"

  step "Style: Ruby", "bin/rubocop"

  step "Security: Gem audit", "bin/bundler-audit"
  step "Security: Importmap vulnerability audit", "bin/importmap audit"
  step "Security: Brakeman code analysis", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"
  step "Tests: Rails", "bin/rails test"
  step "Tests: Seeds", "env RAILS_ENV=test bin/rails db:seed:replant"

  # Optional: Run system tests
  # step "Tests: System", "bin/rails test:system"

  # There is no hosted CI: this file IS the build. .githooks/pre-push runs it
  # before every push, and `gh signoff` puts the same green commit status on
  # GitHub that a rented runner would have (gh extension install
  # basecamp/gh-signoff).
  #
  # A status can only be attached to a commit GitHub already has, and the usual
  # run of this file is the one *before* a push — so sign off only once the
  # commit is on a remote branch, and say so plainly the rest of the time.
  # bin/ship does the two halves in the right order.
  if success?
    step "Signoff: All systems go. Ready for merge and deploy.",
         "if git branch -r --contains HEAD 2>/dev/null | grep -q .; then gh signoff; " \
         "else echo 'Green. Not pushed yet — bin/ship pushes, then signs off.'; fi"
  else
    failure "Signoff: CI failed. Do not merge or deploy.", "Fix the issues and try again."
  end
end
