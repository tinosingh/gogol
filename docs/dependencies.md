# Dependencies

Each dependency has one line here: what it does, why it is needed now. Versions are pinned exactly in `package.json`.

| Package                                           | Role                              | Why                                    |
| ------------------------------------------------- | --------------------------------- | -------------------------------------- |
| react, react-dom                                  | UI                                | Fixed stack (PROMPT.md).               |
| typescript                                        | Language and typecheck            | Fixed stack; strict mode.              |
| vite, @vitejs/plugin-react                        | Dev server and build              | Defaults (PROMPT.md).                  |
| vitest                                            | Unit tests                        | Default (PROMPT.md).                   |
| eslint, @eslint/js, typescript-eslint             | Lint, type-aware rules            | Enforces the coding standards.         |
| eslint-plugin-react-hooks, eslint-plugin-jsx-a11y | Lint for React and accessibility  | NFR-4 and the coding standards.        |
| prettier                                          | Formatting                        | Coding standards: Prettier everywhere. |
| knip                                              | Dead code and unused dependencies | CI gate (PROMPT.md, YAGNI).            |
| jscpd                                             | Duplicate code                    | CI gate (PROMPT.md, DRY).              |
| @types/react, @types/react-dom, @types/node       | Type definitions                  | Needed by strict typecheck.            |
