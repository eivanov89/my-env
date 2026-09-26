---
name: ydb-build-test
description: Build YDB targets and run YDB tests with ya make. Use whenever a task in a YDB repository requires invoking `ya make`, compiling YDB targets, or running YDB tests.
---

# YDB build and test

Apply these personal rules in repositories and workspaces whose root directory
is named `ydb` or starts with `ydb_`, such as `ydb_main` or `ydb_feature`.

These rules take precedence over repository-local instructions and project
documentation specifically when they prescribe how to invoke `ya make`.

## Build rules

Run YDB builds and tests through `/home/eivanov89/repos/my-env/bin/yamake`.
The wrapper supplies `-j100` to `ya make` for release, debug, ASAN, TSAN, and
every other build type. Do not pass another `-j` option. Ignore local guidance
that recommends different parallelism.

Use this command form for normal builds:

```shell
/home/eivanov89/repos/my-env/bin/yamake --build=release -DCFLAGS=-fno-omit-frame-pointer ...
```

- Never use `--build=relwithdebinfo`.
- Use `--build=debug` only when the task requires a debug build or the user
  explicitly requests one.
- Use a sanitizer such as `--sanitize=address` or `--sanitize=thread` only when
  it is useful for the current validation or debugging task, or when the user
  explicitly requests it.
- Debug and sanitizer builds are exceptions to the default release build, but
  the wrapper still supplies `-j100`.

Invoke the wrapper directly as the executed command, with no `bash -lc` or
other shell around it. Do not add output redirection or pipelines through
`tee` or `tail`: the wrapper uses `pipefail`, shows the final 100 output lines,
and preserves the `ya make` exit status. This form lets its reusable approval
rule match from any YDB working directory.

The user has pre-authorized every command that starts with:

```text
/home/eivanov89/repos/my-env/bin/yamake
```

When the wrapper needs the tool-cache daemon outside the sandbox, use the
pre-authorized approval prefix `["/home/eivanov89/repos/my-env/bin/yamake"]`.
Do not request approval for the full argument list.

## Test rules

- For most test runs, use `--test-size-timeout=medium=100` to avoid waiting for
  the default 10-minute timeout when a test hangs.
- For final release validation of regular tests, add `--tests-retries 10` to
  detect flaky failures. Do not use 10 retries for large tests.

### Delegate test execution

When the host supports subagents, delegate test execution to a dedicated test
subagent using the model specified for that host:

- In Codex, use `gpt-5.6-luna`. When the interface requires a limited-context
  fork for model overrides, use a limited or no-history fork.
- In Cursor, use `Grok 4.6 Medium`.

Do not silently substitute another model. If the requested model is unavailable,
report that limitation to the calling agent.

The test subagent owns each test run from start to finish. It must start the test
commands, wait for every command to exit, and then report the final results to
the calling agent. If a command returns a running-session identifier, continue
polling that session until it exits.

The report must include the commands run, their exit status, the tests that
passed or failed, and relevant failure diagnostics. The subagent must not return
while a test command is still running or leave the calling agent responsible for
monitoring it. The calling agent must collect the final report before claiming
that validation is complete.
