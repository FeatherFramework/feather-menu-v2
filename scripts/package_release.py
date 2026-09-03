"""Build a verified, runtime-only ZIP without requiring a platform-specific zip CLI."""
import hashlib
import shutil
import tempfile
import zipfile
from pathlib import Path
from verify_release import runtime_files, verify

root = Path(__file__).resolve().parents[1]
output = root / '.artifacts'
output.mkdir(exist_ok=True)
archive_path = output / 'feather-menu-v2.zip'
with tempfile.TemporaryDirectory() as temporary:
    staged = Path(temporary) / 'feather-menu-v2'
    staged.mkdir()
    for name in sorted(runtime_files(root)):
        destination = staged / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(root / name, destination)
    verify(staged)
    with zipfile.ZipFile(archive_path, 'w', zipfile.ZIP_DEFLATED) as archive:
        for file in sorted(staged.rglob('*')):
            if file.is_file():
                archive.write(file, file.relative_to(staged.parent).as_posix())
digest = hashlib.sha256(archive_path.read_bytes()).hexdigest()
archive_path.with_suffix('.zip.sha256').write_text(f'{digest}  {archive_path.name}\n', encoding='ascii')
print(f'Created {archive_path}\nSHA-256 {digest}')
