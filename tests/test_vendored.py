import os
from pathlib import Path
import re
import shutil
import socket
import ssl
import subprocess
import tempfile
import time
import unittest
import urllib.error
import urllib.request


REPOSITORY = Path(__file__).resolve().parents[1]
CRON = REPOSITORY / "modules/cron/cron-engine.sh"
CONFIGS = ("default.conf", "default-ssl.conf.example")
EXTENSIONS = ("bak", "config", "sql", "fla", "psd", "ini", "log", "sh", "inc", "swp", "dist")


class CronTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(dir=REPOSITORY)
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.log = self.root / "cron.log"

    def shell(self, body, *args, now="00 06 15 06 1"):
        return subprocess.run(
            ["bash", "-c", 'source "$1"; shift\n'
             'date() { if [[ "$1" == "+%S" ]]; then echo 00; '
             'else printf "%s\\n" "$TEST_TIME"; fi; }\n' + body,
             "test", str(CRON), *map(str, args)],
            env={**os.environ, "CRON_LOG_FILE": str(self.log), "TEST_TIME": now},
            cwd=self.root, capture_output=True, text=True, timeout=5,
        )

    def test_field_wildcards_numbers_steps_ranges_and_lists(self):
        cases = (
            ("*", 0, 0, 59, 0), ("08", 8, 0, 59, 0),
            ("08", 9, 0, 59, 1), ("*/6", 18, 0, 23, 0),
            ("*/6", 19, 0, 23, 1), ("10-20", 15, 0, 59, 0),
            ("10-20", 21, 0, 59, 1), ("1-23/2", 7, 0, 23, 0),
            ("1-23/2", 8, 0, 23, 1), ("0,15,30,45", 30, 0, 59, 0),
            ("0,15,30,45", 31, 0, 59, 1),
            ("0-10/5,20-30/2", 24, 0, 59, 0),
            ("5/10", 55, 0, 59, 0), ("5/10", 50, 0, 59, 1),
            ("*/2", 3, 1, 31, 0), ("*/2", 2, 1, 31, 1),
            ("0", 0, 0, 7, 0), ("7", 0, 0, 7, 0),
            ("5-7", 0, 0, 7, 0), ("1-7/2", 0, 0, 7, 0),
            ("1-7/2", 2, 0, 7, 1),
        )
        for field, value, minimum, maximum, expected in cases:
            with self.subTest(field=field, value=value):
                result = self.shell('match_field "$@"', field, value, minimum, maximum)
                self.assertEqual(result.returncode, expected, result.stderr)

    def test_invalid_fields_are_rejected_without_arithmetic_expansion(self):
        for field in (
            "", "60", "-1", "*/0", "*/00", "*/100", "20-10", "0-60",
            "1,,2", ",1", "1,", "MON", "@daily", "1/2/3", "1-*/2",
            "1\n2", "1 2", "99999999999999999999999999999",
            'a[$(touch injected)]', '$(touch injected)', "0,garbage",
        ):
            with self.subTest(field=field):
                result = self.shell('match_field "$@"', field, 0, 0, 59)
                self.assertEqual(result.returncode, 2, result.stderr)
        for field, minimum, maximum in (("24", 0, 23), ("0", 1, 31), ("13", 1, 12), ("8", 0, 7)):
            self.assertEqual(self.shell('match_field "$@"', field, 1, minimum, maximum).returncode, 2)
        self.assertFalse((self.root / "injected").exists())

    def test_schedules_and_standard_day_matching(self):
        cases = (
            (("0", "*/6", "*", "*", "*"), "00 06 15 06 1", True),
            (("0", "*/6", "*", "*", "*"), "00 07 15 06 1", False),
            (("0", "*/6", "*", "*", "*"), "01 06 15 06 1", False),
            (("0", "*/6", "*", "7", "*"), "00 06 15 06 1", False),
            (("*", "*", "15", "*", "2"), "00 06 15 06 1", True),
            (("*", "*", "16", "*", "1"), "00 06 15 06 1", True),
            (("*", "*", "16", "*", "2"), "00 06 15 06 1", False),
            (("*", "*", "*", "*", "2"), "00 06 15 06 1", False),
            (("*", "*", "16", "*", "*"), "00 06 15 06 1", False),
            (("*", "*", "*/2", "*", "2"), "00 06 15 06 1", False),
            (("*", "*", "*/2", "*", "1"), "00 06 15 06 1", True),
            (("*", "*", "*", "*", "7"), "00 00 01 01 0", True),
            (("08", "09", "01", "01", "*"), "08 09 01 01 0", True),
        )
        for fields, now, expected in cases:
            with self.subTest(fields=fields, now=now):
                marker = self.root / "executed"
                marker.unlink(missing_ok=True)
                result = self.shell('execute_if_match "$@"', *fields, "touch executed", now=now)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(marker.exists(), expected)

    def test_invalid_schedule_is_logged_even_when_an_earlier_field_misses(self):
        result = self.shell('execute_if_match "$@"', "1", "*", "*", "*",
                            'a[$(touch injected)]', "touch executed")
        self.assertEqual(result.returncode, 2)
        self.assertIn("ERROR: Invalid cron field:", self.log.read_text())
        self.assertFalse((self.root / "injected").exists())
        self.assertFalse((self.root / "executed").exists())

    def test_main_parses_tabs_leading_spaces_and_final_unterminated_line(self):
        crontab = self.root / "crontab"
        crontab.write_text(
            "  # ignored\n\t\ninvalid\n"
            "  0\t*/6\t*\t*\t* printf '%s' 'hello  world' > result"
        )
        result = self.shell(
            'CRON_CONFIG_FILE="$1"\nsleep() { exit 0; }\nmain', crontab,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / "result").read_text(), "hello  world")
        self.assertIn("ERROR: Invalid cron line:", self.log.read_text())


class NginxTests(unittest.TestCase):
    def test_sensitive_suffix_and_existing_deny_rules(self):
        for name in CONFIGS:
            config = (REPOSITORY / "nginx/conf.d" / name).read_text()
            rules = re.findall(r"location ~ (\S+) \{\s*deny all;", config)
            with self.subTest(config=name):
                for extension in EXTENSIONS:
                    for path in (f"/config.php.{extension}", f"/nested/file.{extension}", f"/.{extension}"):
                        self.assertTrue(any(re.search(rule, path) for rule in rules), path)
                for path in ("/.git/config", "/.htaccess", "/.env", "/.svn/entries",
                             "/composer.json", "/composer.lock", "/package.json",
                             "/package-lock.json", "/.user.ini"):
                    self.assertTrue(any(re.search(rule, path) for rule in rules), path)
                for path in ("/index.html", "/image.png", "/backup.bak.txt", "/config.ini.css"):
                    self.assertFalse(any(re.search(rule, path) for rule in rules), path)

    def test_ssl_has_only_one_copy_of_server_directives(self):
        config = (REPOSITORY / "nginx/conf.d/default-ssl.conf.example").read_text()
        for directive in ("client_max_body_size", "client_body_timeout", "sendfile"):
            self.assertEqual(len(re.findall(rf"^\s*{directive}\s", config, re.MULTILINE)), 1)

    @unittest.skipUnless(shutil.which("nginx") and shutil.which("openssl"),
                         "Nginx and OpenSSL required for live configuration tests")
    def test_actual_http_and_ssl_configurations_deny_sensitive_files(self):
        with tempfile.TemporaryDirectory(dir=REPOSITORY) as directory:
            root = Path(directory)
            (root / "www").mkdir()
            (root / "www/index.html").write_text("public")
            for extension in EXTENSIONS:
                (root / f"www/config.php.{extension}").write_text("private")
            (root / "www/backup.bak.txt").write_text("public")
            subprocess.run(
                ["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                 "-keyout", str(root / "key.pem"), "-out", str(root / "cert.pem"),
                 "-days", "1", "-subj", "/CN=localhost"],
                check=True, capture_output=True, timeout=15,
            )
            for name in CONFIGS:
                with self.subTest(config=name):
                    with socket.socket() as reservation:
                        reservation.bind(("127.0.0.1", 0))
                        port = reservation.getsockname()[1]
                    secure = "ssl" in name
                    server = (REPOSITORY / "nginx/conf.d" / name).read_text()
                    server = server.replace("listen 80;", f"listen 127.0.0.1:{port};")
                    server = server.replace("<port>", f"127.0.0.1:{port}").replace("<domain>", "localhost")
                    server = server.replace("/home/container/www", str(root / "www"))
                    server = server.replace(
                        "/home/container/letsencrypt/config/live/localhost/fullchain.pem", str(root / "cert.pem")
                    ).replace(
                        "/home/container/letsencrypt/config/live/localhost/privkey.pem", str(root / "key.pem")
                    )
                    server = server.replace("include fastcgi_params;",
                                            f"include {REPOSITORY / 'nginx/fastcgi_params'};")
                    config = root / "nginx.conf"
                    config.write_text(
                        f"daemon off;\nmaster_process off;\nerror_log stderr;\npid {root}/nginx.pid;\n"
                        "events {}\nhttp {\naccess_log off;\n"
                        f"client_body_temp_path {root}/body;\nfastcgi_temp_path {root}/fastcgi;\n"
                        f"proxy_temp_path {root}/proxy;\nuwsgi_temp_path {root}/uwsgi;\n"
                        f"scgi_temp_path {root}/scgi;\n{server}\n}}\n"
                    )
                    command = [shutil.which("nginx"), "-p", str(root) + "/", "-c", str(config)]
                    checked = subprocess.run(command + ["-t"], capture_output=True, text=True, timeout=5)
                    self.assertEqual(checked.returncode, 0, checked.stderr)
                    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                    try:
                        deadline = time.monotonic() + 5
                        while True:
                            try:
                                with socket.create_connection(("127.0.0.1", port), timeout=0.1):
                                    break
                            except OSError:
                                if process.poll() is not None or time.monotonic() >= deadline:
                                    self.fail("Nginx failed to start")
                                time.sleep(0.05)
                        scheme = "https" if secure else "http"
                        opener = urllib.request.build_opener(
                            urllib.request.ProxyHandler({}),
                            urllib.request.HTTPSHandler(context=ssl._create_unverified_context()),
                        )
                        for path, expected in (
                            *((f"config.php.{extension}", 403) for extension in EXTENSIONS),
                            ("index.html", 200), ("backup.bak.txt", 200),
                        ):
                            try:
                                with opener.open(f"{scheme}://127.0.0.1:{port}/{path}", timeout=3) as response:
                                    status = response.status
                            except urllib.error.HTTPError as error:
                                status = error.code
                                error.close()
                            self.assertEqual(status, expected, path)
                    finally:
                        process.terminate()
                        process.communicate(timeout=5)


if __name__ == "__main__":
    unittest.main()
