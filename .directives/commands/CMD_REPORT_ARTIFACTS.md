### §CMD_REPORT_ARTIFACTS
**Definition**: Final summary step to list all files created or modified.
**Rule**: Must be executed at the very end of a session/task.
**Algorithm**:
1.  **Identify**: List all files created or modified during this session (Logs, Plans, Debriefs, Code).
2.  **Format**: Create a Markdown list where each path is a clickable link per `¶INV_TERMINAL_FILE_LINKS`. Use **Full** display variant (relative path as display text).
3.  **Output**: Print this list to the chat under the header "## Generated Artifacts".
