# S VS Code Support

This folder contains a minimal VS Code extension for the `S` language.

Included:

- `.s` language registration
- TextMate grammar for baseline syntax highlighting
- `language-configuration.json` for comments, brackets, and auto-closing pairs

Current syntax direction:

- exported names follow Go-style capitalization
- visibility is moving away from a dedicated `pub` keyword

To use it in VS Code:

1. Open this folder as an extension project.
2. Run `Extensions: Install from VSIX...` after packaging, or press `F5` in extension development mode.

If you open the repository root directly, VS Code will not auto-load `/app/s/misc/editor/vscode` as an installed extension. In that case the workspace can still associate `*.s` with the `s` language id, but syntax highlighting will only appear after this extension is launched in an Extension Development Host or installed as a VSIX.

Notes:

- `.s` is commonly associated with assembly in many editors.
- This extension is the safest way to give `S` files their own language identity.
