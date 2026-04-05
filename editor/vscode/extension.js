"use strict";

const vscode = require("vscode");

function activate(context) {
  const selector = { language: "s", scheme: "file" };
  const provider = vscode.languages.registerDocumentSymbolProvider(selector, {
    provideDocumentSymbols(document) {
      const symbols = [];
      const stack = [];
      const lines = document.getText().split(/\r?\n/);

      for (let index = 0; index < lines.length; index += 1) {
        const line = lines[index];
        const trimmed = line.trim();

        if (!trimmed || trimmed.startsWith("//")) {
          continue;
        }

        const closingCount = countChar(line, "}");
        for (let i = 0; i < closingCount && stack.length > 0; i += 1) {
          stack.pop();
        }

        const matchers = [
          {
            regex: /^\s*package\s+([A-Za-z_][\w.]*)/,
            kind: vscode.SymbolKind.Package,
            name: (m) => m[1],
          },
          {
            regex: /^\s*use\s+(.+)/,
            kind: vscode.SymbolKind.Namespace,
            name: (m) => `use ${m[1].trim()}`,
          },
          {
            regex: /^\s*(?:pub\s+)?struct\s+([A-Z][A-Za-z0-9_]*)/,
            kind: vscode.SymbolKind.Struct,
            name: (m) => m[1],
            container: true,
          },
          {
            regex: /^\s*(?:pub\s+)?enum\s+([A-Z][A-Za-z0-9_]*)/,
            kind: vscode.SymbolKind.Enum,
            name: (m) => m[1],
            container: true,
          },
          {
            regex: /^\s*(?:pub\s+)?trait\s+([A-Z][A-Za-z0-9_]*)/,
            kind: vscode.SymbolKind.Interface,
            name: (m) => m[1],
            container: true,
          },
          {
            regex: /^\s*impl(?:\s+([A-Z][A-Za-z0-9_]*)(?:\[[^\]]+\])?)?\s+for\s+([A-Z][A-Za-z0-9_]*(?:\[[^\]]+\])?)/,
            kind: vscode.SymbolKind.Object,
            name: (m) => (m[1] ? `impl ${m[1]} for ${m[2]}` : `impl for ${m[2]}`),
            container: true,
          },
          {
            regex: /^\s*(?:pub\s+)?fn\s+([a-zA-Z_][A-Za-z0-9_]*)/,
            kind: vscode.SymbolKind.Function,
            name: (m) => m[1],
          },
        ];

        let createdSymbol = null;
        for (const matcher of matchers) {
          const match = line.match(matcher.regex);
          if (!match) {
            continue;
          }
          const symbol = createSymbol(document, index, matcher.name(match), matcher.kind);
          if (stack.length > 0) {
            stack[stack.length - 1].children.push(symbol);
          } else {
            symbols.push(symbol);
          }
          createdSymbol = { symbol, container: Boolean(matcher.container) };
          break;
        }

        if (createdSymbol && createdSymbol.container) {
          stack.push(createdSymbol.symbol);
        }
      }

      return symbols;
    },
  });

  context.subscriptions.push(provider);
}

function deactivate() {}

function createSymbol(document, line, name, kind) {
  const range = new vscode.Range(line, 0, line, document.lineAt(line).text.length);
  return new vscode.DocumentSymbol(name, "", kind, range, range);
}

function countChar(text, ch) {
  let count = 0;
  for (const current of text) {
    if (current === ch) {
      count += 1;
    }
  }
  return count;
}

module.exports = {
  activate,
  deactivate,
};
