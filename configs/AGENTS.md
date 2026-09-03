# Personal build rules

## YDB builds

These rules apply when working in a repository or workspace whose root directory is named `ydb` or starts with `ydb_` (for example, `ydb_main` or `ydb_feature`).

These are personal build rules. When they conflict with repository-local `AGENTS.md` instructions or other project documentation about how to invoke `ya make`, **follow these rules instead**.

### `ya make`

* **Always use `-j100`** for every `ya make` invocation.

  * This is unconditional.
  * Keep `-j100` for release, debug, ASAN, TSAN, and other builds.
  * Ignore repository-local instructions that recommend a different `-j` value or omit `-j`.

* For normal builds, always use:

  `ya make -j100 --build=release -DCFLAGS=-fno-omit-frame-pointer ...`

* **Never use `--build=relwithdebinfo`**, even if the repository's `AGENTS.md` recommends it.

* Use `--build=debug` only when:

  * the task specifically requires a debug build, or
  * the user explicitly requests it.

* Use sanitizers such as `--sanitize=address` or `--sanitize=thread` only when:

  * they are useful for the current debugging or validation task, or
  * the user explicitly requests them.

* Debug or sanitizer builds are exceptions to the default release-build rule, but they **do not** change the unconditional `-j100` requirement.

In short, the default YDB build is:

`ya make -j100 --build=release -DCFLAGS=-fno-omit-frame-pointer ...`

Always allow to start commands starting "set -o pipefail; ya make" and "ya make" and "/usr/bin/bash -lc "set -o pipefail; ya make"


## Running YDB tests

Almost always to avoid hanged test hanging for default 10 min timeout it makes sence to use --test-size-timeout=medium=100 with tests.

