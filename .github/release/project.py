"""GitHub Release commands for MacBook Duo. Run from the repository root."""

import argparse
import hashlib
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile


def git(*args):
    return subprocess.check_output(["git", *args])


def version(revision):
    commit = git("rev-parse", "--verify", "--end-of-options", revision + "^{commit}").decode().strip()
    info = plistlib.loads(git("show", commit + ":Info.plist"))
    number = info["CFBundleShortVersionString"]
    if not re.fullmatch(r"(?:0|[1-9][0-9]*)(?:\.(?:0|[1-9][0-9]*)){1,2}", number):
        raise SystemExit("Expected a numeric app version in Info.plist")
    # Earlier bundles stored two components (e.g. 0.6).
    return "v" + (number if number.count(".") == 2 else number + ".0")


def release_details(tag):
    if tag != version("HEAD"):
        raise SystemExit("Requested tag must match the checked-out Info.plist")
    info = plistlib.loads(Path("Info.plist").read_bytes())
    version_line = re.search(
        rf"当前 Fork 版本 \*\*{re.escape(tag[1:])}（构建 {re.escape(info['CFBundleVersion'])}，(测试版|正式版)）\*\*",
        Path("README.md").read_text(encoding="utf-8"),
    )
    if not version_line:
        raise SystemExit("README.md must identify the release version, build and channel")
    changelog = Path("CHANGELOG.md").read_text(encoding="utf-8")
    sections = re.split(r"^## ", changelog, flags=re.MULTILINE)
    matches = [s.partition("\n")[2].strip() for s in sections[1:]
               if re.fullmatch(rf"\[{re.escape(tag[1:])}\] - \d{{4}}-\d{{2}}-\d{{2}}", s.splitlines()[0])]
    if len(matches) != 1 or not matches[0]:
        raise SystemExit(f"CHANGELOG.md must contain one nonempty dated entry for {tag}")
    return version_line.group(1), info, matches[0]


def check():
    release_details(version("HEAD"))
    subprocess.run(["zsh", "build.sh"], env={**os.environ, "SIGNING_IDENTITY": "-"}, check=True)
    Path(".build/release-commit").write_bytes(git("rev-parse", "HEAD"))


def package(output):
    output = output.resolve()
    if any(output.iterdir()):
        raise SystemExit("Expected an empty release output directory")
    marker = Path(".build/release-commit")
    if not marker.exists() or marker.read_bytes() != git("rev-parse", "HEAD"):
        check()
    tag = version("HEAD")
    app = Path(Path(".build/app-path.txt").read_text().strip())
    archive = f"MacBook-Duo-{tag}-macos-arm64.zip"
    with tempfile.TemporaryDirectory() as tmp:
        zip_path = Path(tmp, archive)
        extracted = Path(tmp, "extracted")
        # This bundle has no resource forks. Omit the build host's filesystem metadata.
        subprocess.run(["ditto", "-c", "-k", "--norsrc", "--keepParent", app, zip_path], check=True)
        subprocess.run(["ditto", "-x", "-k", zip_path, extracted], check=True)
        restored = extracted / "MacBook Duo.app"
        subprocess.run(["codesign", "--verify", "--deep", "--strict", restored], check=True)
        subprocess.run(["lipo", "-verify_arch", "arm64", restored / "Contents/MacOS/HingeGlass"], check=True)
        if (restored / "Contents/Info.plist").read_bytes() != Path("Info.plist").read_bytes():
            raise SystemExit("Packaged Info.plist differs from the checked-out release")
        data = zip_path.read_bytes()
        (output / archive).write_bytes(data)
        (output / "SHA256SUMS.txt").write_text(f"{hashlib.sha256(data).hexdigest()}  {archive}\n")


def notes(tag):
    channel, info, changes = release_details(tag)
    print(f"MacBook Duo {tag}（构建 {info['CFBundleVersion']}，{channel}）\n\n{changes}\n")
    print(f"下载 `MacBook-Duo-{tag}-macos-arm64.zip` 和 `SHA256SUMS.txt`，在同一目录运行 "
          "`shasum -a 256 -c SHA256SUMS.txt`。退出旧版本，解压后将 App 移入「应用程序」。\n")
    print(f"支持 Apple Silicon、macOS {info['LSMinimumSystemVersion']} 及以上。公开下载包使用 "
          "ad-hoc 签名，未经 Apple 公证。实时效果需要兼容的内建屏幕、铰链传感器和屏幕录制权限。"
          "策略测试和签名校验不能替代真机角度及录屏验证。")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("version").add_argument("revision")
    commands.add_parser("check")
    commands.add_parser("package").add_argument("output", type=Path)
    for command in ("notes", "prerelease"):
        commands.add_parser(command).add_argument("tag")
    args = parser.parse_args()
    if args.command == "version":
        print(version(args.revision))
    elif args.command == "check":
        check()
    elif args.command == "package":
        package(args.output)
    elif args.command == "notes":
        notes(args.tag)
    else:
        print("true" if release_details(args.tag)[0] == "测试版" else "false")


if __name__ == "__main__":
    main()
