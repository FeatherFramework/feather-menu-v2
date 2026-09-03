"""Verify a runtime directory or the exact install ZIP using Python's standard library."""
import argparse
import re
import tempfile
import zipfile
from pathlib import Path, PurePosixPath


def runtime_files(root):
    required = {
        'fxmanifest.lua', 'client/results.lua', 'client/validation.lua',
        'client/main.lua', 'ui/index.html',
    }
    entry = (root / 'ui/index.html').read_text(encoding='utf-8')
    assets = re.findall(r'(?:src|href)="([^"?#]+)"', entry)
    assert assets, 'No compiled entry assets'
    for asset in assets:
        assert re.fullmatch(r'\./assets/[A-Za-z0-9_.-]+\.(?:js|css)', asset), f'Unexpected entry asset: {asset}'
        required.add('ui/' + asset.removeprefix('./'))
    return required


def verify(root):
    required = runtime_files(root)
    actual = set()
    allowed_directories = {'client', 'ui', 'ui/assets'}
    for file in root.rglob('*'):
        relative = file.relative_to(root).as_posix()
        assert not file.is_symlink(), f'Symlink in runtime archive: {relative}'
        if file.is_dir():
            assert relative in allowed_directories, f'Non-runtime directory in release: {relative}'
        else:
            actual.add(relative)
    assert actual == required, f'Runtime file mismatch; extra={sorted(actual - required)}, missing={sorted(required - actual)}'
    manifest = (root / "fxmanifest.lua").read_text(encoding="utf-8")
    assert "ui_page 'ui/index.html'" in manifest, "Manifest must load ui/index.html"
    assert "server_scripts" not in manifest, "Menu is a client-only resource"
    for name in ("results", "validation", "main"):
        assert (root / "client" / f"{name}.lua").is_file(), f"Missing {name}.lua"
    entry = (root / "ui/index.html").read_text(encoding="utf-8")
    assets = re.findall(r'(?:src|href)="(\./assets/[^"?#]+)"', entry)
    assert assets, "No compiled entry assets"
    for asset in assets:
        assert (root / "ui" / asset).is_file(), f"Missing entry asset {asset}"
    assert not re.search(r'(?:src|href)="(?:https?://|/assets)', entry), "Non-relative entry asset"
    runtime_assets = list((root / "ui/assets").glob("*"))
    assert sum(file.stat().st_size for file in runtime_assets if file.is_file()) <= 262144, "Compiled UI exceeds 256 KiB raw budget"
    for file in runtime_assets:
        if file.suffix == ".js":
            assert "fixture:showcase" not in file.read_text(encoding="utf-8"), "Development fixture leaked into production"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("artifact", type=Path)
    args = parser.parse_args()
    if args.artifact.is_dir():
        verify(args.artifact)
    else:
        with tempfile.TemporaryDirectory() as temporary, zipfile.ZipFile(args.artifact) as archive:
            for entry in archive.infolist():
                path = PurePosixPath(entry.filename)
                assert not path.is_absolute() and ".." not in path.parts and "\\" not in entry.filename, "Unsafe ZIP path"
                assert path.parts and path.parts[0] == "feather-menu-v2", "ZIP must have one feather-menu-v2 root"
            archive.extractall(temporary)
            verify(Path(temporary) / "feather-menu-v2")
    print("PASS runtime artifact layout, assets, boundary, and bundle budget")


if __name__ == "__main__":
    main()
