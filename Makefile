.PHONY: coverage

# Generate an lcov coverage report and open it in the browser.
# Scoped to src/ and test/lib/mocks/ (excludes test runner files).
coverage:
	forge coverage --no-match-coverage "(\.t\.sol|Test\.sol)$$" --report lcov
	genhtml lcov.info --branch-coverage -o coverage --dark-mode --ignore-errors inconsistent,corrupt
	open coverage/index.html
