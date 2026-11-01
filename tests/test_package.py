import hashlib
import importlib.util
import pathlib
import tempfile
import unittest
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("package_mod", ROOT / "scripts/package.py")
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)


class ReleasePackage(unittest.TestCase):
    def test_archive_contains_only_the_mod_and_notices(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = package.build(tmp)
            with zipfile.ZipFile(path) as archive:
                expected = {f"{package.INSTALL_PATH}/{name}" for name in (*package.FILES, "LICENSE")}
                self.assertEqual(set(archive.namelist()), expected)
                self.assertIsNone(archive.testzip())
                for name in package.FILES:
                    self.assertEqual(archive.read(f"{package.INSTALL_PATH}/{name}"),
                                     (package.MOD / name).read_bytes())
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            self.assertEqual((path.parent / "SHA256SUMS.txt").read_text().strip(),
                             f"{digest}  {path.name}")

    def test_identical_sources_create_identical_archives(self):
        with tempfile.TemporaryDirectory() as first, tempfile.TemporaryDirectory() as second:
            self.assertEqual(package.build(first).read_bytes(), package.build(second).read_bytes())


if __name__ == "__main__":
    unittest.main()
