"""Installer integration tests using small, disposable Git repositories."""

import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import tomllib
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "bin/setup-ydb-agent-rules"
loader = importlib.machinery.SourceFileLoader("ydb_rules", str(SCRIPT))
spec = importlib.util.spec_from_loader(loader.name, loader)
rules = importlib.util.module_from_spec(spec)
loader.exec_module(rules)


class InstallerTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="ydb rules tests ")
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name) / "Users/test engineer"
        self.home.mkdir(parents=True)
        self.env = dict(os.environ, HOME=str(self.home))
        self.source = self.home / "repos/my-env-private/ai/AGENTS.ydb.md"
        self.source.parent.mkdir(parents=True)
        self.source.write_text("---\nalwaysApply: true\n---\nPersonal YDB instructions\n")
        skill = self.home / ".agents/skills/ydb-build-test/SKILL.md"
        skill.parent.mkdir(parents=True)
        skill.write_text("YDB build policy\n")
        installer = self.home / "repos/my-env/bin/setup-ydb-agent-rules"
        installer.parent.mkdir(parents=True)
        installer.symlink_to(SCRIPT)
        self.root = self.home / "repos/ydb"
        self.root.mkdir(parents=True)
        self.git("init", "-q")
        self.git("config", "user.name", "Test")
        self.git("config", "user.email", "test@example.invalid")
        self.git("remote", "add", "origin", "git@github.com:test/ydb.git")
        (self.root / "ya").write_text("fixture\n")
        (self.root / "ydb").mkdir()
        (self.root / "ydb/ya.make").write_text("fixture\n")
        (self.root / "AGENTS.md").write_text("Conflicting root policy\n")
        (self.root / "CLAUDE.md").write_text("@./AGENTS.md\n")
        self.git("add", ".")
        self.git("commit", "-qm", "fixture")

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.root), *args], text=True).strip()

    def run_installer(self, *args, code=0):
        result = subprocess.run([str(SCRIPT), *map(str, args)], env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        return result

    def put(self, relative, text):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def test_dry_run_check_and_idempotence(self):
        self.run_installer("--repo", self.root, "--dry-run")
        self.assertFalse((self.root / "AGENTS.override.md").exists())
        self.run_installer("--repo", self.root, "--check", code=1)
        self.run_installer("--repo", self.root)
        before = {name: (self.root / name).lstat().st_mtime_ns for name in rules.FILES}
        self.run_installer("--repo", self.root, "--check")
        self.run_installer("--repo", self.root)
        self.assertEqual(before, {name: (self.root / name).lstat().st_mtime_ns for name in rules.FILES})
        self.assertEqual(self.git("status", "--porcelain"), "")
        self.assertEqual((self.root / "AGENTS.override.md").resolve(), self.source.resolve())
        self.assertFalse((self.root / "CLAUDE.local.md").is_symlink())

    def test_merges_existing_settings_and_actions(self):
        self.put(".claude/settings.local.json", json.dumps({"permissions": {"allow": ["Read"]}, "claudeMdExcludes": ["/other/file"]}))
        self.put(".cursor/worktrees.json", json.dumps({"setup-worktree": ["echo existing"], "other": 7}))
        self.put(".cursorignore", "secret.txt\n")
        self.put(".codex/environments/environment.toml", 'version = 1\nname = "Existing"\n[setup]\nscript = "echo existing"\n[setup.linux]\nscript = "echo linux"\n[[actions]]\nname = "Run"\ncommand = "echo run"\nicon = "run"\n')
        self.run_installer("--repo", self.root)
        settings = json.loads((self.root / ".claude/settings.local.json").read_text())
        self.assertEqual(settings["permissions"], {"allow": ["Read"]})
        self.assertIn("/other/file", settings["claudeMdExcludes"])
        self.assertEqual(len(settings["claudeMdExcludes"]), 3)
        cursor = json.loads((self.root / ".cursor/worktrees.json").read_text())
        self.assertEqual(cursor["setup-worktree-unix"], rules.CURSOR_SCRIPT)
        self.assertIn("sh -c 'echo existing'", (self.root / ".cursor" / rules.CURSOR_SCRIPT).read_text())
        self.assertEqual(cursor["other"], 7)
        data = tomllib.loads((self.root / ".codex/environments/environment.toml").read_text())
        self.assertEqual(data["name"], "Existing")
        self.assertTrue(data["setup"]["script"].endswith("echo existing"))
        self.assertTrue(data["setup"]["linux"]["script"].endswith("echo linux"))
        self.assertEqual(data["actions"][0]["command"], "echo run")
        self.assertTrue((self.root / ".cursorignore").read_text().startswith("secret.txt\n"))
        self.run_installer("--repo", self.root, "--check")

    def test_cursor_script_path_remains_worktree_relative(self):
        self.put(".cursor/worktrees.json", '{"setup-worktree-unix": "existing setup.sh"}')
        self.run_installer("--repo", self.root)
        script = (self.root / ".cursor" / rules.CURSOR_SCRIPT).read_text()
        self.assertIn("/'existing setup.sh'", script)
        self.assertNotIn(str(self.root), script)

    def test_refuses_tracked_config_before_writing(self):
        self.put(".cursorignore", "tracked\n")
        self.git("add", ".cursorignore")
        self.run_installer("--repo", self.root, code=2)
        self.assertFalse((self.root / "AGENTS.override.md").exists())

    def test_refuses_unfamiliar_instructions_and_symlinked_parents(self):
        shim = self.put("CLAUDE.local.md", "My personal instructions\n")
        self.run_installer("--repo", self.root, code=2)
        self.assertEqual(shim.read_text(), "My personal instructions\n")
        shim.unlink()
        outside = self.home / "outside"
        outside.mkdir()
        (self.root / ".cursor").symlink_to(outside, target_is_directory=True)
        self.run_installer("--repo", self.root, code=2)
        self.assertEqual(list(outside.iterdir()), [])

    def test_refuses_invalid_json_and_malformed_blocks(self):
        settings = self.put(".claude/settings.local.json", "[1,2]")
        self.run_installer("--repo", self.root, code=2)
        self.assertFalse((self.root / "AGENTS.override.md").exists())
        settings.write_text("{}")
        self.put(".cursorignore", rules.BEGIN + "\n")
        self.run_installer("--repo", self.root, code=2)

    def test_shared_exclusions_and_arbitrary_worktree_name(self):
        worktree = self.home / ".cursor/worktrees/ydb/random name"
        worktree.parent.mkdir(parents=True)
        self.git("worktree", "add", "--detach", str(worktree))
        self.run_installer("--all")
        self.assertTrue((worktree / "AGENTS.override.md").is_symlink())
        self.assertEqual(subprocess.check_output(["git", "-C", str(worktree), "status", "--porcelain"], text=True), "")
        exclude = (self.root / ".git/info/exclude").read_text()
        self.assertEqual(exclude.count(rules.BEGIN), 1)
        self.run_installer("--all", "--check")

    def test_global_migration_removes_only_known_symlinks(self):
        global_file = self.home / "AGENTS.md"
        global_file.symlink_to(self.source.parent / "AGENTS.md")
        codex_file = self.home / ".codex/AGENTS.md"
        codex_file.parent.mkdir()
        codex_file.write_text("Unrelated global preferences\n")
        self.run_installer("--all", "--migrate-global", code=2)
        self.assertTrue(global_file.is_symlink())
        self.assertFalse((self.root / "AGENTS.override.md").exists())
        codex_file.unlink()
        codex_file.symlink_to(self.source)
        self.run_installer("--all", "--migrate-global", "--dry-run")
        self.assertTrue(global_file.is_symlink())
        self.run_installer("--all", "--migrate-global")
        self.assertFalse(global_file.is_symlink())
        self.assertFalse(codex_file.is_symlink())

    def test_rejects_side_project_and_preserves_working_changes(self):
        self.git("remote", "set-url", "origin", "git@github.com:test/side-project.git")
        self.run_installer("--repo", self.root, code=2)
        self.git("remote", "set-url", "origin", "git@github.com:test/ydb.git")
        (self.root / "ya").write_text("User modification\n")
        self.run_installer("--repo", self.root)
        self.assertEqual(self.git("status", "--porcelain"), "M ya")

    def test_linux_style_home(self):
        linux_home = Path(self.temp.name) / "home/engineer"
        linux_home.parent.mkdir(parents=True)
        self.home.rename(linux_home)
        self.home = linux_home
        self.root = linux_home / "repos/ydb"
        self.env["HOME"] = str(linux_home)
        self.run_installer("--all")
        self.run_installer("--all", "--check")

    def test_helper_creates_and_configures_worktree(self):
        self.git("branch", "-M", "main")
        main = self.home / "repos/ydb_main"
        self.git("worktree", "add", "--detach", str(main))
        helper = SCRIPT.parent / "git-worktree-ydb.sh"
        result = subprocess.run(["bash", str(helper), "helper-test", "main"], env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        worktree = self.home / "repos/ydb_worktrees/helper-test"
        self.run_installer("--repo", worktree, "--check")
        self.assertIn("To enter it", result.stdout)

    def test_native_setup_commands_bootstrap_fresh_worktrees(self):
        self.run_installer("--repo", self.root)
        cursor = json.loads((self.root / ".cursor/worktrees.json").read_text())
        codex = tomllib.loads((self.root / ".codex/environments/environment.toml").read_text())
        cursor_command = "bash " + shlex.quote(str(self.root / ".cursor" / cursor["setup-worktree-unix"]))
        for name, command in [("cursor", cursor_command), ("codex", codex["setup"]["script"])]:
            with self.subTest(agent=name):
                worktree = self.home / ("native " + name)
                self.git("worktree", "add", "--detach", str(worktree))
                self.assertFalse((worktree / "AGENTS.override.md").exists())
                result = subprocess.run(["bash", "-c", command], cwd=worktree, env=self.env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.run_installer("--repo", worktree, "--check")

    def test_repository_negation_overrides_info_exclude(self):
        ignore = self.put(".gitignore", "*\n!*/\n!*.*\n.cursor/\n.cursorignore\n.claude/\n")
        self.git("add", "-f", ".gitignore")
        self.git("commit", "-qm", "YDB ignore precedence fixture")
        before = ignore.read_bytes()
        result = self.run_installer("--repo", self.root)
        self.assertIn("remain visible to Git", result.stderr)
        self.assertEqual(ignore.read_bytes(), before)
        self.assertIn("?? AGENTS.override.md", self.git("status", "--porcelain"))
        self.assertEqual(self.git("diff", "--name-only"), "")
        self.run_installer("--repo", self.root, "--check")

    def test_preserved_cursor_script_runs_in_new_worktree(self):
        self.put(".cursor/worktrees.json", '{"setup-worktree-unix": "existing setup.sh"}')
        self.put(".cursor/existing setup.sh", 'printf "%s" "$1" > existing-setup-result\n')
        self.run_installer("--repo", self.root)
        worktree = self.home / "new cursor worktree"
        self.git("worktree", "add", "--detach", str(worktree))
        script = self.root / ".cursor" / rules.CURSOR_SCRIPT
        result = subprocess.run(["bash", str(script)], cwd=worktree, env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(Path((worktree / "existing-setup-result").read_text()).resolve(), worktree.resolve())
        self.run_installer("--repo", worktree, "--check")

    def test_preserves_edited_managed_script(self):
        self.run_installer("--repo", self.root)
        path = self.root / ".cursor" / rules.CURSOR_SCRIPT
        path.write_text(path.read_text() + "echo user edit\n")
        before = path.read_bytes()
        self.run_installer("--repo", self.root, code=2)
        self.assertEqual(path.read_bytes(), before)

    def test_managed_environment_without_external_toml_parser(self):
        data = {"version": 1, "name": "YDB", "setup": {"script": 'echo "x = y"\necho \\path', "linux": {"script": "echo linux"}}, "actions": [{"name": "Run", "command": "echo run", "icon": "run"}]}
        with patch.dict("sys.modules", {"tomllib": None, "tomli": None}):
            self.assertEqual(rules.load_environment(rules.toml_text(data)), data)
            with self.assertRaisesRegex(ValueError, "Python 3.11"):
                rules.load_environment('[setup]\nscript = "echo existing"\n')
            with self.assertRaisesRegex(ValueError, "Python 3.11"):
                rules.load_environment(rules.toml_text(data) + "# user formatting\n")


if __name__ == "__main__":
    unittest.main()
