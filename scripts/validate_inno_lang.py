from pathlib import Path
import sys


DEFAULT_PATH = (
    Path(__file__).resolve().parents[1] / "tools" / "ChineseSimplified.isl"
)
REQUIRED_SNIPPETS = (
    "LanguageName=简体中文",
    "SetupAppTitle=安装",
    "ButtonCancel=取消",
    "WizardSelectDir=选择目标位置",
)
KNOWN_MOJIBAKE = (
    "缁犫偓娴ｆ挷鑵戦弬",
    "鐎瑰顥",
    "閸欐牗绉",
    "閻劍鍩涙穱鈩冧紖",
)


def main() -> int:
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_PATH
    data = path.read_bytes()

    if data.startswith(b"\xef\xbb\xbf"):
        raise SystemExit(f"{path} must not include a UTF-8 BOM")

    try:
        text = data.decode("cp936")
    except Exception as exc:
        raise SystemExit(f"{path} is not valid CP936/GBK text: {exc}") from exc

    missing = [snippet for snippet in REQUIRED_SNIPPETS if snippet not in text]
    if missing:
        raise SystemExit(f"{path} is missing required installer messages: {missing}")

    broken = [snippet for snippet in KNOWN_MOJIBAKE if snippet in text]
    if broken:
        raise SystemExit(f"{path} still contains mojibake fragments: {broken}")

    print(f"validated installer language asset: {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
