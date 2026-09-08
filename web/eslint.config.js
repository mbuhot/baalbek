// ESLint flat config. TypeScript's recommended rules, plus one
// module-boundary rule: `web` may only import `core-api-client`'s package
// root, never a path into its internals.
import js from "@eslint/js";
import tseslint from "typescript-eslint";

export default tseslint.config(
  { ignores: ["dist/**", "dev-dist/**"] },
  js.configs.recommended,
  tseslint.configs.recommended,
  {
    files: ["**/*.{ts,tsx}"],
    rules: {
      "no-restricted-imports": [
        "error",
        {
          patterns: [
            {
              // Bare specifier form: import ... from "core-api-client/src/generated/schema".
              group: ["core-api-client/*"],
              message:
                "Import only from the core-api-client package root — its internals (e.g. src/generated/*) aren't public API.",
            },
            {
              // Relative-path form: import ... from "../../core-api-client/src/generated/schema".
              // "**" crosses path separators, so this catches any depth of "../".
              group: ["**/core-api-client/src/**"],
              message:
                "Import only from the core-api-client package root — its internals (e.g. src/generated/*) aren't public API.",
            },
          ],
        },
      ],
    },
  },
);
