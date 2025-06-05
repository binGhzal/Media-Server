# Solving CI Pipeline Issues

## Issue Analysis

After analyzing the GitHub Actions workflow in this repository, we've identified several potential issues that might cause CI pipeline failures on GitHub while passing locally:

1. **Platform Architecture Differences**:

   - Local: macOS/Apple Silicon (arm64 architecture)
   - GitHub Actions: Ubuntu Linux (amd64 architecture)

2. **Shell Script Issues**:

   - Line ending inconsistencies (CRLF vs. LF)
   - Permissions problems (scripts need to be executable)
   - Trailing whitespace in files
   - Missing error handling with `set -e`

3. **Environment Differences**:
   - Missing dependencies in CI environment
   - Different versions of tools (shellcheck, shfmt, etc.)
   - Environment variables not set in GitHub Actions

## Solutions Implemented

To address these issues, we've created the following tools:

1. **test-ci-locally.sh**:

   - Tests GitHub Actions workflows locally using the `act` tool
   - Shows detailed output for debugging
   - Uses explicit architecture settings for Docker containers

2. **debug-ci.sh**:

   - Isolates problematic jobs for detailed analysis
   - Compares local and CI environments
   - Provides diagnostic information for fixing issues

3. **fix-ci-pipeline.sh**:

   - Automatically fixes common CI issues
   - Creates patches for fixing shell scripts
   - Tests job commands locally for validation

4. **Common CI Commands Reference**:
   - Examples of various `act` commands for different scenarios

## Recommended Workflow

1. **Identify Failing Jobs**:

   ```bash
   ./test-ci-locally.sh --list   # List all jobs
   ./test-ci-locally.sh --job <job_name> --verbose   # Test specific job
   ```

2. **Fix Common Issues**:

   ```bash
   ./fix-ci-pipeline.sh   # Select option 2
   ```

3. **Test Fix Locally**:

   ```bash
   ./test-ci-locally.sh --job <job_name>   # Verify fix
   ```

4. **Create and Apply Patch**:

   ```bash
   ./fix-ci-pipeline.sh   # Select option 3
   git apply .ci-fixes/ci-fixes.patch   # Apply fixes
   ```

5. **Commit and Push Changes**:
   ```bash
   git add .
   git commit -m "Fix CI pipeline issues"
   git push
   ```

## Common Issues and Solutions

### 1. Shell Script Permissions

**Issue**: Scripts lack executable permissions in CI environment.

**Solution**:

```bash
find ./proxmox -name "*.sh" -exec chmod +x {} \;
```

### 2. Line Ending Problems

**Issue**: CRLF line endings cause issues in Linux environments.

**Solution**:

```bash
find ./proxmox -name "*.sh" -exec perl -pi -e 's/\r\n/\n/g' {} \;
```

### 3. Trailing Whitespace

**Issue**: Trailing whitespace in files causing linting errors.

**Solution**:

```bash
find ./proxmox -name "*.sh" -exec sed -i '' 's/[[:space:]]*$//' {} \;
```

### 4. Missing Error Handling

**Issue**: Scripts continue execution after errors.

**Solution**: Add `set -e` to the top of each script after the shebang.

### 5. Docker Architecture Issues

**Issue**: Docker images pulled with incorrect architecture.

**Solution**: Use explicit architecture flag:

```bash
act -j <job_name> --container-architecture linux/amd64
```

## Additional Resources

- [Act GitHub Repository](https://github.com/nektos/act)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [ShellCheck](https://github.com/koalaman/shellcheck)
