### §CMD_ASK_ROUND
**Definition**: The standard protocol for information gathering (Brainstorming, Debugging, Deep Dives).
**Algorithm**:
1.  **Formulate**: Generate 3-5 targeted questions based on the Session Goal.
2.  **Execute**: Call the `AskUserQuestion` tool.
    *   **Constraint**: Provide distinct options for each question (e.g., Yes/No, Multiple Choice).
    *   **Goal**: Gather structured data to inform the next steps.
3.  **Wait**: The tool will pause execution until the user responds.
4.  **Resume**: Once the tool returns, proceed immediately to logging.
