# Roo Code Local Provider Setup

After running `scripts\Start-LocalModel.ps1`, configure Roo Code manually:

```text
Provider: OpenAI Compatible
Base URL: http://127.0.0.1:8080/v1
API Key: none
Model: local-qwen-coder
```

Use this initial task prompt for C#/WPF or C++ work:

```text
You are working in this local Git repository. Read the project structure first. Make the requested code changes directly, run the configured build task, retry build repair at most 2 times, then summarize changed files and remaining risks. Do not commit unless asked.
```

If the model struggles with tool calls, reduce the task size and ask for one focused change at a time.

