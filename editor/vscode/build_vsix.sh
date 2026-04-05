#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT_NAME="local.s-language-support-0.0.1.vsix"
OUT_PATH="$ROOT/$OUT_NAME"
STAGE_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$STAGE_DIR"
}
trap cleanup EXIT

mkdir -p "$STAGE_DIR/extension"
cp -R "$ROOT/README.md" "$ROOT/extension.js" "$ROOT/language-configuration.json" \
  "$ROOT/package.json" "$ROOT/snippets" "$ROOT/syntaxes" "$STAGE_DIR/extension/"

cat > "$STAGE_DIR/extension.vsixmanifest" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011">
  <Metadata>
    <Identity Language="en-US" Id="local.s-language-support" Version="0.0.1" Publisher="local" />
    <DisplayName>S Language Support</DisplayName>
    <Description xml:space="preserve">Minimal VS Code syntax support for the S language.</Description>
    <Tags>s language syntax</Tags>
  </Metadata>
  <Installation>
    <InstallationTarget Id="Microsoft.VisualStudio.Code" Version="[1.85.0,2.0.0)" />
  </Installation>
  <Dependencies />
  <Assets>
    <Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true" />
    <Asset Type="Microsoft.VisualStudio.Services.Content.Details" Path="extension/README.md" Addressable="true" />
  </Assets>
</PackageManifest>
EOF

cat > "$STAGE_DIR/[Content_Types].xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="json" ContentType="application/json" />
  <Default Extension="js" ContentType="application/javascript" />
  <Default Extension="md" ContentType="text/markdown" />
  <Default Extension="xml" ContentType="application/xml" />
</Types>
EOF

rm -f "$OUT_PATH"
(
  cd "$STAGE_DIR"
  zip -qr "$OUT_PATH" "[Content_Types].xml" extension.vsixmanifest extension
)

printf 'Created %s\n' "$OUT_PATH"
