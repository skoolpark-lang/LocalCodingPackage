# Offline Install Checklist

On the online PC:

1. Run `scripts\Build-OfflineBundle.ps1`.
2. Confirm `dist\LocalCodingAgentOfflinePack.zip` exists.
3. Copy the ZIP to the offline PC.
4. Copy your Qwen GGUF model separately.

On the offline PC:

1. Extract `LocalCodingAgentOfflinePack.zip`.
2. Run `scripts\Install-Offline.ps1`.
3. Copy the Qwen GGUF model into `models\`.
4. Run `scripts\Start-LocalModel.ps1`.
5. Open the target repository in VS Code or VSCodium.
6. Run `scripts\Configure-Workspace.ps1 -ProjectPath "<repo>" -InitGitIfMissing`.
7. Configure Roo Code as OpenAI Compatible.
8. Ask Roo Code to perform a small test change.
9. Review `git diff -- .`.

