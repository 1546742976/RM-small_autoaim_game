"""Download only the Windows x64 template from the official Godot ZIP.

Requires requests. HTTP byte ranges avoid downloading templates for all platforms.
The archive's CRC is validated by zipfile; no third-party mirror is used.
"""
from __future__ import annotations

import io
import json
from pathlib import Path
import zipfile
import hashlib

import requests


VERSION = "4.7.2-stable"
URL = (
    "https://github.com/godotengine/godot-builds/releases/download/"
    f"{VERSION}/Godot_v{VERSION}_export_templates.tpz"
)
DESTINATION = Path(__file__).resolve().parent / "cache" / VERSION


class RemoteZip(io.RawIOBase):
    def __init__(self, url: str):
        self.session = requests.Session()
        self.url = url
        self.position = 0
        self.transferred = 0
        _, content_range = self._request("bytes=0-0")
        self.length = int(content_range.rsplit("/", 1)[1])
        tail, _ = self._request(f"bytes={max(0, self.length - 131072)}-{self.length - 1}")
        self.tail_start = self.length - len(tail)
        self.tail = tail

    def _request(self, byte_range: str) -> tuple[bytes, str]:
        with self.session.get(
            self.url,
            headers={"Range": byte_range, "Accept-Encoding": "identity"},
            stream=True,
            timeout=(20, 120),
        ) as response:
            response.raise_for_status()
            if response.status_code != 206:
                raise RuntimeError("Server did not support byte ranges; refusing full archive download")
            self.url = response.url
            body = response.content
            self.transferred += len(body)
            return body, response.headers["Content-Range"]

    def seekable(self) -> bool:
        return True

    def readable(self) -> bool:
        return True

    def tell(self) -> int:
        return self.position

    def seek(self, offset: int, whence: int = io.SEEK_SET) -> int:
        if whence == io.SEEK_SET:
            self.position = offset
        elif whence == io.SEEK_CUR:
            self.position += offset
        elif whence == io.SEEK_END:
            self.position = self.length + offset
        if self.position < 0:
            raise ValueError("Negative seek")
        return self.position

    def read(self, size: int = -1) -> bytes:
        if size < 0:
            size = self.length - self.position
        size = min(size, self.length - self.position)
        if size <= 0:
            return b""
        if self.position >= self.tail_start:
            offset = self.position - self.tail_start
            data = self.tail[offset : offset + size]
        else:
            data, content_range = self._request(
                f"bytes={self.position}-{self.position + size - 1}"
            )
            expected_range = f"bytes {self.position}-{self.position + size - 1}/{self.length}"
            if content_range != expected_range or len(data) != size:
                raise RuntimeError(f"Unexpected content range: {content_range}")
        self.position += len(data)
        return data


def main() -> None:
    remote = RemoteZip(URL)
    DESTINATION.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(remote) as archive:
        names = archive.namelist()
        print("Windows archive entries:", [n for n in names if "windows" in n], flush=True)
        entry = "templates/windows_release_x86_64.exe"
        contents = archive.read(entry)
        target = DESTINATION / Path(entry).name
        target.write_bytes(contents)
        receipt = {
            "source": URL,
            "entry": entry,
            "size": len(contents),
            "crc32": f"{archive.getinfo(entry).CRC:08x}",
            "sha256": hashlib.sha256(contents).hexdigest(),
            "downloaded_bytes": remote.transferred,
        }
        (DESTINATION / "download-receipt.json").write_text(
            json.dumps(receipt, indent=2), encoding="utf-8"
        )
        print(json.dumps(receipt, indent=2), flush=True)


if __name__ == "__main__":
    main()
