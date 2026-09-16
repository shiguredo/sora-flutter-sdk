#!/usr/bin/env python3
"""canary 版のバージョン更新、タグ作成、push を自動化する。"""

from __future__ import annotations

import argparse
import logging
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Final, Sequence

__all__ = ["main"]


LOGGER: Final[logging.Logger] = logging.getLogger(__name__)
REPOSITORY_ROOT: Final[Path] = Path(__file__).resolve().parent
PUBSPEC_PATH: Final[Path] = REPOSITORY_ROOT / "pubspec.yaml"
GENERATED_VERSION_PATH: Final[Path] = (
    REPOSITORY_ROOT / "lib/src/sora_sdk_version.g.dart"
)
DEFAULT_BRANCH: Final[str] = "develop"

# Dart 公式ドキュメント「The pubspec file」の Version 節で示される
# prerelease 形式に合わせる。仕様が変わった場合はこの正規表現も見直す。
VERSION_PATTERN: Final[re.Pattern[str]] = re.compile(
    r"(?P<major>0|[1-9][0-9]*)\."
    r"(?P<minor>0|[1-9][0-9]*)\."
    r"(?P<patch>0|[1-9][0-9]*)"
    r"(?:-canary\.(?P<canary>0|[1-9][0-9]*))?$"
)
PUBSPEC_VERSION_LINE_PATTERN: Final[re.Pattern[str]] = re.compile(
    r"(?m)^(?P<prefix>version:[ \t]*)(?P<version>[^ \t\r\n]+)(?P<suffix>[ \t]*)$"
)
GENERATED_COMMENT_VERSION_PATTERN: Final[re.Pattern[str]] = re.compile(
    r"(?m)^(?P<prefix>// sdk version: )(?P<version>[^ \t\r\n]+)(?P<suffix>[ \t]*)$"
)
GENERATED_CONSTANT_VERSION_PATTERN: Final[re.Pattern[str]] = re.compile(
    r"(?m)^(?P<prefix>[ \t]*static const String sdkVersion = ')(?P<version>[^']+)"
    r"(?P<suffix>';[ \t]*)$"
)


@dataclass(frozen=True)
class Version:
    """pubspec.yaml に記載する SDK バージョン。"""

    major: int
    minor: int
    patch: int
    canary: int | None = None

    @classmethod
    def parse(cls, value: str) -> Version:
        """文字列をバージョンに変換する。"""
        match = VERSION_PATTERN.fullmatch(value)
        if match is None:
            raise ValueError(f"Invalid version format: {value}")

        canary_value = match.group("canary")
        return cls(
            major=int(match.group("major")),
            minor=int(match.group("minor")),
            patch=int(match.group("patch")),
            canary=None if canary_value is None else int(canary_value),
        )

    def next_canary(self) -> Version:
        """現在のバージョンから次の canary バージョンを計算する。"""
        if self.canary is not None:
            # canary の途中ではリリース番号を変えず、canary 番号だけを進める。
            return Version(self.major, self.minor, self.patch, self.canary + 1)

        # 安定版からは次のマイナーリリースの canary を開始する。
        # パッチ (fix) 番号は canary では自動更新しない。
        return Version(self.major, self.minor + 1, 0, 0)

    def __str__(self) -> str:
        """pub のバージョン文字列を返す。"""
        release = f"{self.major}.{self.minor}.{self.patch}"
        if self.canary is None:
            return release
        return f"{release}-canary.{self.canary}"


def _replace_version_line(
    content: str,
    pattern: re.Pattern[str],
    current_version: str,
    new_version: str,
    description: str,
) -> str:
    """指定した形式のバージョン行を 1 行だけ置き換える。"""

    match = pattern.search(content)
    if match is None:
        raise ValueError(f"{description} was not found")
    if match.group("version") != current_version:
        raise ValueError(
            f"{description} has unexpected version: "
            f"expected {current_version}, actual {match.group('version')}"
        )

    start, end = match.span("version")
    return f"{content[:start]}{new_version}{content[end:]}"


def _read_pubspec() -> tuple[str, Version]:
    """pubspec.yaml の内容とバージョンを読み取る。"""

    content = PUBSPEC_PATH.read_text(encoding="utf-8")
    match = PUBSPEC_VERSION_LINE_PATTERN.search(content)
    if match is None:
        raise ValueError("Version line was not found in pubspec.yaml")
    return content, Version.parse(match.group("version"))


def _update_release_files(
    pubspec_content: str,
    generated_version_content: str,
    current_version: Version,
    new_version: Version,
) -> tuple[str, str]:
    """pubspec.yaml と生成済みバージョンファイルを更新した内容を返す。"""

    current_version_text = str(current_version)
    new_version_text = str(new_version)
    updated_pubspec_content = _replace_version_line(
        pubspec_content,
        PUBSPEC_VERSION_LINE_PATTERN,
        current_version_text,
        new_version_text,
        "pubspec.yaml version line",
    )
    updated_generated_content = _replace_version_line(
        generated_version_content,
        GENERATED_COMMENT_VERSION_PATTERN,
        current_version_text,
        new_version_text,
        "generated SDK version comment",
    )
    updated_generated_content = _replace_version_line(
        updated_generated_content,
        GENERATED_CONSTANT_VERSION_PATTERN,
        current_version_text,
        new_version_text,
        "generated SDK version constant",
    )
    return updated_pubspec_content, updated_generated_content


def _check_current_branch() -> None:
    """canary リリースを develop ブランチから実行していることを確認する。"""

    result = subprocess.run(
        ["git", "rev-parse", "--abbrev-ref", "HEAD"],
        cwd=REPOSITORY_ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    current_branch = result.stdout.strip()
    if current_branch != DEFAULT_BRANCH:
        raise ValueError(
            f"This script must be run on the {DEFAULT_BRANCH} branch: "
            f"actual branch is {current_branch}"
        )


def _confirm_execution(current_version: Version, new_version: Version) -> bool:
    """ファイル更新と Git 操作の実行前に確認する。"""

    while True:
        answer = input(
            f"Update version from {current_version} to {new_version}? (y/n): "
        ).strip().lower()
        if answer == "y":
            return True
        if answer == "n":
            return False
        LOGGER.warning("Please enter y or n")


def _write_release_files(pubspec_content: str, generated_version_content: str) -> None:
    """リリース対象の 2 ファイルを書き込む。"""

    PUBSPEC_PATH.write_text(pubspec_content, encoding="utf-8")
    GENERATED_VERSION_PATH.write_text(
        generated_version_content,
        encoding="utf-8",
    )
    LOGGER.info("Updated pubspec.yaml and generated SDK version file")


def _git_command(arguments: Sequence[str], dry_run: bool) -> None:
    """Git コマンドを dry-run 対応で実行する。"""

    command = ["git", *arguments]
    if dry_run:
        LOGGER.info("Dry run: Would run %s", " ".join(command))
        return
    subprocess.run(command, cwd=REPOSITORY_ROOT, check=True)


def _run_git_operations(new_version: Version, dry_run: bool) -> None:
    """バージョン更新をコミットし、develop とタグを push する。"""

    new_version_text = str(new_version)
    commit_message = f"canary 版のバージョンを {new_version_text} に更新する"
    _git_command(
        ["add", "pubspec.yaml", "lib/src/sora_sdk_version.g.dart"],
        dry_run,
    )
    # リリース対象以外の staged 変更を canary commit に混入させない。
    _git_command(
        [
            "commit",
            "--only",
            "-m",
            commit_message,
            "--",
            "pubspec.yaml",
            "lib/src/sora_sdk_version.g.dart",
        ],
        dry_run,
    )
    _git_command(["tag", new_version_text], dry_run)
    _git_command(["push", "origin", DEFAULT_BRANCH], dry_run)
    _git_command(["push", "origin", new_version_text], dry_run)


def _build_parser() -> argparse.ArgumentParser:
    """コマンドライン引数の parser を作成する。"""

    parser = argparse.ArgumentParser(
        description="canary 版のバージョンを更新して Git タグを作成する"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="ファイルと Git を変更せず、実行内容だけを表示する",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    """canary リリース処理を実行する。"""

    logging.basicConfig(level=logging.INFO, format="%(message)s")
    args = _build_parser().parse_args(argv)

    try:
        _check_current_branch()
        pubspec_content, current_version = _read_pubspec()
        generated_version_content = GENERATED_VERSION_PATH.read_text(encoding="utf-8")
        new_version = current_version.next_canary()
        updated_pubspec_content, updated_generated_content = _update_release_files(
            pubspec_content,
            generated_version_content,
            current_version,
            new_version,
        )
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        LOGGER.error("Release preparation failed: %s", error)
        return 1

    LOGGER.info("Current version: %s", current_version)
    LOGGER.info("New version: %s", new_version)

    if args.dry_run:
        LOGGER.info("Dry run: pubspec.yaml would be updated")
        LOGGER.info("Dry run: lib/src/sora_sdk_version.g.dart would be updated")
    elif not _confirm_execution(current_version, new_version):
        LOGGER.info("Update cancelled")
        return 0
    else:
        try:
            _write_release_files(updated_pubspec_content, updated_generated_content)
        except OSError as error:
            LOGGER.error("Release files could not be written: %s", error)
            return 1

    try:
        _run_git_operations(new_version, args.dry_run)
    except subprocess.CalledProcessError as error:
        LOGGER.error("Git operation failed: %s", error)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
