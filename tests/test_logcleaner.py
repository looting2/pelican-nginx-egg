import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import time
import unittest


REPOSITORY = Path(__file__).resolve().parents[1]
STARTUP = json.loads((REPOSITORY / "egg-pelican-nginx.json").read_text())[
    "startup_commands"
]["Default"]


class LogCleanerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(dir=REPOSITORY)
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "logs").mkdir()
        (self.root / "tmp").mkdir()
        shutil.copyfile(REPOSITORY / "safe-start.sh", self.root / "safe-start.sh")
        (self.root / "start-modules.sh").write_text(
            'printf "upstream-cleaner=%s\\n" "$LOGCLEANER_STATUS"\n'
            'exit "${TEST_STARTUP_EXIT:-0}"\n'
        )

    def run_startup(self, inline=False, entrypoint=False, **settings):
        environment = {
            **os.environ,
            "LOGCLEANER_STATUS": "1",
            "MAX_SIZE_MB": "0",
            "MAX_AGE_DAYS": "30",
            "LOG_DIR": str(self.root / "logs"),
            "DRY_RUN": "false",
            "TEST_STARTUP_EXIT": "0",
            **settings,
        }
        command = ["bash", "-c", STARTUP] if inline else ["bash", "./safe-start.sh"]
        if entrypoint:
            environment["STARTUP"] = STARTUP
            command = [
                "bash", str(REPOSITORY / "entrypoint.sh"),
            ]
            environment["HOME"] = str(self.root)
        result = subprocess.run(
            command,
            cwd=self.root,
            env=environment,
            capture_output=True,
            text=True,
            timeout=10,
        )
        self.assertEqual(result.returncode, int(environment["TEST_STARTUP_EXIT"]))
        self.assertIn("upstream-cleaner=0", result.stdout)
        return result

    def test_default_startup_uses_installed_wrapper(self):
        self.assertEqual(STARTUP, "bash ./safe-start.sh")
        installer = (REPOSITORY / "scripts/install-runtime.sh").read_text()
        self.assertIn('"$source_dir/safe-start.sh"', installer)

    def test_image_entrypoint_preprocessing_preserves_startup(self):
        log = self.root / "logs" / "access.log"
        log.write_text("old data")
        self.run_startup(entrypoint=True)
        self.assertEqual(log.read_bytes(), b"")
        self.run_startup(entrypoint=True, TEST_STARTUP_EXIT="7")

    def test_runtime_files_and_open_log_survive(self):
        for inline in (False, True):
            with self.subTest(inline=inline):
                log = self.root / "logs" / "access\nspecial.log"
                with log.open("ab") as handle:
                    handle.write(b"old log data")
                    handle.flush()
                    inode = log.stat().st_ino
                    session = self.root / "tmp" / "session"
                    session.write_text("session data")
                    nested = self.root / "tmp" / "php"
                    nested.mkdir(exist_ok=True)
                    pid = nested / "php.pid"
                    pid.write_text("123")
                    sock_path = nested / "php-fpm.sock"
                    with socket.socket(socket.AF_UNIX) as sock:
                        sock.bind(str(sock_path))
                        sock.listen()
                        try:
                            self.run_startup(inline=inline)
                            self.assertTrue(sock_path.exists())
                            with socket.socket(socket.AF_UNIX) as client:
                                client.connect(str(sock_path))
                            connection, _ = sock.accept()
                            connection.close()
                        finally:
                            sock_path.unlink()
                    self.assertEqual(session.read_text(), "session data")
                    self.assertEqual(pid.read_text(), "123")
                    self.assertEqual(log.stat().st_ino, inode)
                    self.assertEqual(log.stat().st_size, 0)
                    handle.write(b"new log data")
                    handle.flush()
                    self.assertEqual(log.read_bytes(), b"new log data")

    def test_only_eligible_regular_logs_are_cleaned(self):
        old = self.root / "logs" / "old.log"
        old.write_text("old")
        timestamp = time.time() - 3 * 86400
        os.utime(old, (timestamp, timestamp))
        recent = self.root / "logs" / "recent.log"
        recent.write_text("recent")
        other = self.root / "logs" / "php.pid"
        other.write_text("123")
        outside = self.root / "secret.log"
        outside.write_text("preserve")
        (self.root / "logs" / "linked.log").symlink_to(outside)
        linked_dir = self.root / "logs" / "linked-directory"
        linked_dir.symlink_to(self.root / "tmp", target_is_directory=True)
        temporary_log = self.root / "tmp" / "temporary.log"
        temporary_log.write_text("preserve")
        os.mkfifo(self.root / "logs" / "pipe.log")
        with socket.socket(socket.AF_UNIX) as sock:
            sock.bind(str(self.root / "logs" / "socket.log"))
            self.run_startup(MAX_SIZE_MB="10", MAX_AGE_DAYS="1")
        self.assertEqual(old.read_bytes(), b"")
        self.assertEqual(recent.read_text(), "recent")
        self.assertEqual(other.read_text(), "123")
        self.assertEqual(outside.read_text(), "preserve")
        self.assertEqual(temporary_log.read_text(), "preserve")
        self.assertTrue((self.root / "logs" / "pipe.log").exists())
        self.assertTrue((self.root / "logs" / "socket.log").exists())

    def test_disabled_and_dry_run_preserve_logs(self):
        log = self.root / "logs" / "access.log"
        log.write_text("keep")
        for settings in (
            {"LOGCLEANER_STATUS": "0"},
            {"LOGCLEANER_STATUS": "false"},
            {"DRY_RUN": "true"},
            {"DRY_RUN": "1"},
        ):
            with self.subTest(settings=settings):
                self.run_startup(**settings)
                self.assertEqual(log.read_text(), "keep")

    def test_invalid_settings_and_unsafe_paths_skip_cleanup(self):
        log = self.root / "logs" / "access.log"
        log.write_text("keep")
        for settings in (
            {"MAX_SIZE_MB": "-1"},
            {"MAX_AGE_DAYS": "invalid"},
            {"LOG_DIR": str(self.root)},
            {"LOG_DIR": str(self.root / "missing")},
        ):
            with self.subTest(settings=settings):
                self.run_startup(**settings)
                self.assertEqual(log.read_text(), "keep")
        alias = self.root / "alias"
        alias.symlink_to(self.root / "logs", target_is_directory=True)
        self.run_startup(LOG_DIR=str(alias))
        self.assertEqual(log.read_text(), "keep")
        log.unlink()
        (self.root / "logs").rmdir()
        (self.root / "logs").symlink_to(self.root / "tmp", target_is_directory=True)
        temporary_log = self.root / "tmp" / "access.log"
        temporary_log.write_text("keep")
        self.run_startup()
        self.assertEqual(temporary_log.read_text(), "keep")

    def test_orchestrator_exit_status_is_preserved(self):
        self.run_startup(TEST_STARTUP_EXIT="7")


if __name__ == "__main__":
    unittest.main()
