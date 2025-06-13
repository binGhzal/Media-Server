.PHONY: help install-hooks test lint format check format-check clean

# Default target executed when no arguments are given
help:
	@echo 'Available targets:'
	@echo '  help         - Show this help message'
	@echo '  install      - Install project dependencies and pre-commit hooks'
	@echo '  install-hooks - Install pre-commit hooks'
	@echo '  test         - Run all tests'
	@echo '  lint         - Run all linters'
	@echo '  format       - Format all files'
	@echo '  format-check - Check formatting without making changes'
	@echo '  clean        - Clean up temporary files'

# Install project dependencies and pre-commit hooks
install: install-hooks
	@echo 'Installing project dependencies...'
	# Add your installation commands here

# Install pre-commit hooks
install-hooks:
	@echo 'Installing pre-commit hooks...'
	pre-commit install --install-hooks

# Run all tests
test:
	@echo 'Running tests...'
	# Add your test commands here

# Run all linters
lint:
	@echo 'Running linters...'
	pre-commit run --all-files

# Format all files
format:
	@echo 'Formatting files...'
	pre-commit run --all-files --hook-stage manual format

# Check formatting without making changes
format-check:
	@echo 'Checking formatting...'
	pre-commit run --all-files --hook-stage manual format-check

# Clean up temporary files
clean:
	@echo 'Cleaning up...'
	find . -type f -name '*.py[co]' -delete -o -type d -name '__pycache__' -delete
	find . -type d -name '.mypy_cache' -exec rm -rf {} +
	find . -type d -name '.pytest_cache' -exec rm -rf {} +
	find . -type d -name '.ruff_cache' -exec rm -rf {} +
	find . -type d -name '.coverage' -exec rm -rf {} +
	find . -type d -name 'htmlcov' -exec rm -rf {} +
	find . -type d -name '.pytest_cache' -exec rm -rf {} +
	find . -type d -name 'dist' -exec rm -rf {} +
	find . -type d -name 'build' -exec rm -rf {} +
	find . -type d -name '*.egg-info' -exec rm -rf {} +
	find . -type f -name '*.pyc' -delete
	find . -type f -name '*.pyo' -delete
	find . -type f -name '*.pyd' -delete
	find . -type f -name '*.so' -delete
	find . -type f -name '*.c' -delete
	find . -type f -name '*.o' -delete

# Set default target
.DEFAULT_GOAL := help
