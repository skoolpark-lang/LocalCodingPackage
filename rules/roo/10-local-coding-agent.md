# Local Coding Agent Rules

You are working in a local Windows Git repository with a local Qwen coding model.

Follow these rules:

- Work inside the opened repository only.
- Prefer existing project conventions.
- You may edit files directly when the user asks for an implementation.
- Before finishing, inspect `git diff -- .` and summarize changed files.
- Use the configured build profile after code changes.
- If the build fails, analyze the error and repair the code.
- Retry build repair at most 2 times.
- For C#/WPF, prefer solution-level `dotnet build` or MSBuild when a solution exists.
- For WPF, keep XAML and code-behind behavior consistent.
- For C++, prefer CMake presets when available, then `cmake -S . -B build` and `cmake --build build`.
- Do not modify files outside the repository.
- Do not run destructive Git commands such as `reset --hard`, `clean -fd`, or checkout-discard operations unless the user explicitly asks.
- Do not commit automatically unless the user asks.

Completion checklist:

- Build or test command executed, or the reason it could not run is stated.
- Changed files are summarized.
- Remaining failures or risks are reported.
- User can review the result with Git diff.

