import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest


REPOSITORY = Path(__file__).resolve().parents[1]
EGG = json.loads((REPOSITORY / "egg-pelican-nginx.json").read_text())
BUNDLE = ("nginx", "php", "modules", "scripts", "safe-start.sh", "start-modules.sh", "LICENSE")


class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(dir=REPOSITORY)
        self.addCleanup(self.temporary.cleanup)
        self.workspace = Path(self.temporary.name)
        self.root = self.workspace / "server"
        self.root.mkdir()
        self.bin = self.workspace / "bin"
        self.bin.mkdir()
        self.environment = {
            **os.environ, "HOME": str(self.root),
            "SERVER_DIR": str(self.root), "AUTOUPDATE_STATUS": "0",
            "AUTOUPDATE_FORCE": "0", "LOGCLEANER_STATUS": "0",
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "GIT_ADDRESS": "", "GIT_BRANCH": "", "WORDPRESS": "0",
        }

    def run_script(self, script, *args, check=True, **env):
        return subprocess.run(
            ["bash", str(script), *map(str, args)], cwd=self.root,
            env={**self.environment, **env}, capture_output=True, text=True,
            timeout=15, check=check,
        )

    def executable(self, name, content):
        path = self.bin / name
        path.write_text("#!/bin/bash\nset -eu\n" + content)
        path.chmod(0o755)

    def install(self, source=REPOSITORY, mode="install", version="original"):
        return self.run_script(
            source / "scripts/install-runtime.sh", source, self.root, version, mode
        )

    def archive(self):
        archive = self.workspace / "runtime.tar.gz"
        with tarfile.open(archive, "w:gz") as bundle:
            for path in BUNDLE:
                bundle.add(REPOSITORY / path, arcname=f"release/{path}")
        return archive

    def mock_downloads(self, response='{"tag_name":"v1.0.0"}'):
        self.archive()
        (self.workspace / "release.json").write_text(response)
        self.executable("curl", """
printf '%s\\n' "$*" >> "$FIXTURES/requests"
output=""
url=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) output="$2"; shift 2;;
        https://*) url="$1"; shift;;
        *) shift;;
    esac
done
if [[ "${FAIL_DOWNLOAD:-0}" == 1 ]]; then exit 22; fi
case "$url" in
    */releases/latest) cp "$FIXTURES/release.json" "$output";;
    *wordpress*) cp "$FIXTURES/wordpress.tar.gz" "$output";;
    *codeload.github.com/looting2/pelican-nginx-egg/*) cp "$FIXTURES/runtime.tar.gz" "$output";;
    *) exit 99;;
esac
""")
        self.environment["FIXTURES"] = str(self.workspace)

    def test_egg_installer_and_owned_images(self):
        self.assertEqual(
            EGG["scripts"]["installation"]["script"],
            (REPOSITORY / "scripts/install.sh").read_text(),
        )
        self.assertEqual(
            set(EGG["docker_images"].values()),
            {f"ghcr.io/looting2/pelican-nginx-egg:{v}-latest" for v in ("8.2", "8.3", "8.4", "8.5")},
        )
        force = next(v for v in EGG["variables"] if v["env_variable"] == "AUTOUPDATE_FORCE")
        self.assertEqual(force["default_value"], "0")

    def test_bundle_install_and_actual_startup(self):
        self.install()
        for path in BUNDLE:
            if path != "scripts":
                self.assertTrue((self.root / path).exists(), path)
        self.executable("php-fpm8.4", 'printf "php=%s\\n" "$*"\n')
        self.executable("nginx", 'printf "nginx=%s\\n" "$*"\nexit 7\n')
        result = self.run_script(
            REPOSITORY / "entrypoint.sh", check=False,
            STARTUP=EGG["startup_commands"]["Default"],
            IMAGE_PHP_VERSION="8.4", PHP_VERSION="8.4",
            PHP_INI=str(self.root / "php/php.ini"),
            PHP_FPM_CONF=str(self.root / "php/php-fpm.conf"),
            NGINX_CONF=str(self.root / "nginx/nginx.conf"),
            NGINX_PREFIX=str(self.root),
        )
        self.assertEqual(result.returncode, 7, result.stderr)
        self.assertIn("Services successfully launched", result.stdout)
        self.assertIn("nginx=-c", result.stdout)
        self.assertTrue((self.root / "php/sessions").is_dir())

    def test_mismatched_image_version_fails_before_service_launch(self):
        self.install()
        result = self.run_script(
            self.root / "safe-start.sh", check=False,
            IMAGE_PHP_VERSION="8.4", PHP_VERSION="8.5",
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("must match image version", result.stderr)

    def test_entrypoint_preserves_multiline_and_placeholders(self):
        result = self.run_script(
            REPOSITORY / "entrypoint.sh", PHP_VERSION="8.5",
            STARTUP='printf "%s\\n" "{{PHP_VERSION}}"\nprintf "%s\\n" "second line"',
        )
        self.assertEqual(result.stdout, "8.5\nsecond line\n")

    def test_reinstall_preserves_site_and_custom_configuration(self):
        self.install()
        for path in ("www/index.php", "nginx/conf.d/default.conf", "php/php.ini", "logs/access.log", "tmp/session"):
            (self.root / path).write_text("keep")
        self.install(version="reinstalled")
        for path in ("www/index.php", "nginx/conf.d/default.conf", "php/php.ini", "logs/access.log", "tmp/session"):
            self.assertEqual((self.root / path).read_text(), "keep")
        self.assertEqual((self.root / "VERSION").read_text(), "reinstalled\n")

    def test_released_update_keeps_config_site_logs_and_runtime(self):
        self.install()
        self.mock_downloads()
        for path in ("www/index.php", "nginx/nginx.conf", "php/php.ini", "logs/access.log", "tmp/session"):
            (self.root / path).write_text("keep")
        result = self.run_script(
            self.root / "modules/autoupdate/start.sh",
            AUTOUPDATE_STATUS="1", AUTOUPDATE_FORCE="1",
        )
        self.assertIn("Updated runtime", result.stdout)
        self.assertEqual((self.root / "VERSION").read_text(), "v1.0.0\n")
        for path in ("www/index.php", "nginx/nginx.conf", "php/php.ini", "logs/access.log", "tmp/session"):
            self.assertEqual((self.root / path).read_text(), "keep")
        self.assertFalse((self.root / ".runtime-update").exists())
        requests = (self.workspace / "requests").read_text()
        self.assertIn("repos/looting2/pelican-nginx-egg/releases/latest", requests)
        self.assertIn("refs/tags/v1.0.0", requests)
        self.assertNotIn("Ym0T", requests)

    def test_update_check_only_same_version_and_failure_are_nonfatal(self):
        self.install()
        for response, env in (
            ('{"tag_name":"v1.0.0"}', {}),
            ('{"tag_name":"original"}', {"AUTOUPDATE_FORCE": "1"}),
            ('not json', {"AUTOUPDATE_FORCE": "1"}),
            ('{"tag_name":"../bad"}', {"AUTOUPDATE_FORCE": "1"}),
            ('{}', {"FAIL_DOWNLOAD": "1", "AUTOUPDATE_FORCE": "1"}),
        ):
            with self.subTest(response=response, env=env):
                self.mock_downloads(response)
                self.run_script(
                    self.root / "modules/autoupdate/start.sh",
                    AUTOUPDATE_STATUS="1", **env,
                )
                self.assertEqual((self.root / "VERSION").read_text(), "original\n")
                self.assertFalse((self.root / ".runtime-update").exists())

    def test_incomplete_bundle_does_not_replace_installed_runtime(self):
        source = self.workspace / "invalid"
        source.mkdir()
        for path in BUNDLE:
            if path == "LICENSE":
                continue
            target = source / path
            if (REPOSITORY / path).is_dir():
                shutil.copytree(REPOSITORY / path, target)
            else:
                shutil.copyfile(REPOSITORY / path, target)
        self.install()
        result = self.run_script(
            source / "scripts/install-runtime.sh", source, self.root, "bad", check=False
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.root / "VERSION").read_text(), "original\n")

    def mock_installer(self):
        self.mock_downloads()
        self.executable("apt-get", "exit 0\n")
        self.executable("git", """
if [[ "$1" == ls-remote ]]; then
    printf '0123456789012345678901234567890123456789\\tHEAD\\n'
else
    printf '%s\\n' "$*" >> "$FIXTURES/git-actions"
    exit 0
fi
""")

    def test_real_installer_creates_welcome_page_in_correct_path(self):
        self.mock_installer()
        self.run_script(REPOSITORY / "scripts/install.sh")
        self.assertIn("Pelican Nginx is ready", (self.root / "www/index.php").read_text())
        self.assertTrue((self.root / "safe-start.sh").exists())
        self.assertEqual((self.root / "VERSION").read_text(), "0123456789012345678901234567890123456789\n")
        self.assertFalse((self.root / ".runtime-install").exists())

    def test_real_installer_preserves_existing_site_even_with_git_or_wordpress(self):
        self.mock_installer()
        (self.root / "www").mkdir()
        (self.root / "www/index.php").write_text("existing")
        self.run_script(
            REPOSITORY / "scripts/install.sh",
            GIT_ADDRESS="https://example.com/site.git", WORDPRESS="1",
        )
        self.assertEqual((self.root / "www/index.php").read_text(), "existing")
        self.assertFalse((self.workspace / "git-actions").exists())

    def test_real_installer_wordpress_into_empty_site(self):
        self.mock_installer()
        wordpress = self.workspace / "index.php"
        wordpress.write_text("wordpress")
        with tarfile.open(self.workspace / "wordpress.tar.gz", "w:gz") as archive:
            archive.add(wordpress, arcname="wordpress/index.php")
        self.run_script(REPOSITORY / "scripts/install.sh", WORDPRESS="1")
        self.assertEqual((self.root / "www/index.php").read_text(), "wordpress")

    def test_legacy_cleaner_never_deletes_runtime_files(self):
        self.install()
        (self.root / "tmp/session").write_text("keep")
        self.run_script(self.root / "modules/logcleaner/start.sh", LOGCLEANER_STATUS="1")
        self.assertEqual((self.root / "tmp/session").read_text(), "keep")

    def test_git_skips_missing_checkout_and_does_not_print_tokens(self):
        self.install()
        result = self.run_script(
            self.root / "modules/git/start.sh", GIT_STATUS="1",
            GIT_DIR=str(self.root / "missing"),
        )
        self.assertIn("No repository", result.stdout)
        (self.root / "www/.git").mkdir()
        self.executable("git", 'printf "%s\\n" "$ACCESS_TOKEN"\nexit 1\n')
        result = self.run_script(
            self.root / "modules/git/start.sh", GIT_STATUS="1",
            GIT_DIR=str(self.root / "www"), USERNAME="test", ACCESS_TOKEN="fixture-value",
        )
        self.assertIn("Pull failed", result.stdout)
        self.assertNotIn("fixture-value", result.stdout + result.stderr)
        self.assertFalse((self.root / ".pelican-git").exists())

    def test_update_replaces_script_inode_without_changing_open_script(self):
        self.install()
        path = self.root / "modules/autoupdate/start.sh"
        with path.open() as running_script:
            original = running_script.read()
            inode = path.stat().st_ino
            self.install(mode="update", version="replacement")
            self.assertNotEqual(inode, path.stat().st_ino)
            running_script.seek(0)
            self.assertEqual(running_script.read(), original)

    def test_dockerfile_and_workflow_config(self):
        dockerfile = (REPOSITORY / "Dockerfile").read_text()
        workflow = (REPOSITORY / ".github/workflows/docker-image.yml").read_text()
        self.assertIn("USER container", dockerfile)
        self.assertIn('ENTRYPOINT ["/entrypoint.sh"]', dockerfile)
        self.assertIn("IMAGE_PHP_VERSION=${PHP_VERSION}", dockerfile)
        self.assertIn("openssh-client", dockerfile)
        self.assertIn("sshpass", dockerfile)
        self.assertNotIn("policy.xml", dockerfile)
        self.assertIn('php: ["8.2", "8.3", "8.4", "8.5"]', workflow)
        self.assertIn("platforms: linux/amd64,linux/arm64", workflow)
        self.assertIn("packages: write", workflow)
        self.assertIn("ghcr.io/looting2/pelican-nginx-egg:", workflow)
        # Parse each Docker RUN body with the image's shell, without executing it.
        for instruction in dockerfile.replace("\\\n", "").splitlines():
            if instruction.startswith("RUN "):
                subprocess.run(["sh", "-n", "-c", instruction[4:]], check=True)

    def test_proc_open_is_not_disabled_by_default(self):
        php_ini = (REPOSITORY / "php/php.ini").read_text()
        for line in php_ini.splitlines():
            key, separator, value = line.partition("=")
            if separator and key.strip() == "disable_functions":
                self.assertNotIn("proc_open", {name.strip() for name in value.split(",")})
        for pool in (REPOSITORY / "php/pool.d").glob("*.conf"):
            for line in pool.read_text().splitlines():
                key, separator, value = line.partition("=")
                if separator and key.strip() in (
                    "php_value[disable_functions]", "php_admin_value[disable_functions]",
                ):
                    self.assertNotIn("proc_open", {name.strip() for name in value.split(",")})


if __name__ == "__main__":
    unittest.main()
