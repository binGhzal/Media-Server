# Debugging CI Pipeline Issues

This guide explains how to use the provided scripts to diagnose and fix issues with GitHub Actions CI pipelines that are failing on GitHub but passing locally.

## Available Tools

1. **test-ci-locally.sh** - Run GitHub Actions workflows locally using the `act` tool
2. **debug-ci.sh** - Additional debugging features to diagnose specific job issues

## Common CI Issues and Solutions

### Environment Differences

GitHub Actions runners use Ubuntu Linux environments. If your local environment is different (macOS, Windows), this can cause issues.

**Solution:**

- Run tests in a Docker container that mimics the GitHub Actions environment
- Use the `--container-architecture linux/amd64` flag with `act` on Apple Silicon

### Missing Dependencies

CI jobs might fail because GitHub's runner lacks packages or tools that are installed on your local machine.

**Solution:**

- Explicitly install all required dependencies in your workflow file
- Use the `setup-*` actions to configure common tools

### Permissions Issues

File permissions don't always translate correctly between systems, especially shell scripts.

**Solution:**

- Always include `chmod +x` commands for executable scripts in your workflow
- Ensure consistent line endings (LF, not CRLF)

### Secrets and Environment Variables

GitHub Actions workflows may use secrets or environment variables that aren't available locally.

**Solution:**

- Create a `.env` or `.secrets` file for local testing
- Pass variables with `act -s SECRET=value` or `act -e ENV=value`

## Using the Scripts

### Testing a Specific Job

To run a specific job locally:

```bash
./test-ci-locally.sh --job shellcheck
```

### Listing Available Jobs

To see all jobs defined in your workflow:

```bash
./test-ci-locally.sh --list
```

### Detailed Debugging

For more detailed debugging of a problematic job:

```bash
./debug-ci.sh --job test
```

### Comparing Environments

To compare your local environment with the CI environment:

```bash
./debug-ci.sh --compare
```

### Finding Recent GitHub Failures

To check recent workflow failures on GitHub (requires GitHub CLI):

```bash
./debug-ci.sh --find-failures
```

## Tips for CI Pipeline Success

1. **Run the full pipeline locally** before pushing: `./test-ci-locally.sh --all`
2. **Get detailed logs** for failing jobs: `act -j job_name -W workflow.yml -v`
3. **Ensure consistent shell environments** by specifying the shell in your workflow
4. **Set up proper error handling** with `set -e` in your bash scripts
5. **Test in separate steps** to identify where failures occur
6. **Use matrix jobs** when testing across different environments

## Additional Resources

- [Act Documentation](https://github.com/nektos/act#readme)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
