# Decision Tree Interpreter Pipeline

Implementation reference for the 3-stage decision tree pipeline defined in `§CMD_DECISION_TREE`.

**Pipeline**: `markdown source → parse → TreeAST → interpret(store) → ResolvedTree → renderer`

## Stage 1: Parse (markdown → TreeAST)

Extracts structure from markdown: questions, options, codes, hidden flags, multi-select flags, condition expressions, recommendation expressions, nesting.

```typescript
interface TreeAST {
  name: string;
  questions: QuestionNode[];
}
interface QuestionNode {
  code: string;          // store key (underscore stripped for [_CODE])
  hidden: boolean;       // true if [_CODE]
  label: string;
  multiSelect: boolean;  // true if heading uses "Choose:" or [ ] on every option
  condition?: string;    // raw JSONPath expression from (if: ...)
  options: OptionNode[];
}
interface OptionNode {
  code: string;
  label: string;
  description?: string;
  condition?: string;            // (if: ...) on individual options
  recommended?: true | string;   // true for static, JSONPath string for conditional
}
```

## Stage 2: Interpret (TreeAST + store → ResolvedTree)

Evaluates all JSONPath conditions against the current answer store. Produces a tree with visibility and recommendation booleans resolved.

```typescript
interface AnswerStore {
  [itemId: string]: {
    [questionCode: string]: string | string[];  // single-select: string, multi-select: string[]
  };
}
interface ResolvedTree {
  name: string;
  questions: ResolvedQuestion[];
}
interface ResolvedQuestion {
  code: string;
  hidden: boolean;
  label: string;
  multiSelect: boolean;
  visible: boolean;         // resolved from condition against store
  options: ResolvedOption[];
}
interface ResolvedOption {
  code: string;
  label: string;
  description?: string;
  visible: boolean;         // resolved
  recommended: boolean;     // resolved
}
```

## Stage 3: Render (ResolvedTree → UI)

Three renderers for three interpretation modes:

- **Interactive form**: React `<DecisionForm/>` component. Renders full tree with conditional show/hide via JS. Single submit button. On each user input change, the interpreter re-runs against the updated store to resolve new visibility/recommendation states.
- **Checklist**: Markdown with `[x]`/`[ ]` checkboxes. LLM fills checkboxes, evaluator validates completeness (one branch per section, all nested items checked).
- **AskUserQuestion**: The current agent-driven sequential model. Agent evaluates conditions between calls and presents visible questions via `AskUserQuestion`.

```typescript
// React component signature
interface DecisionFormProps {
  tree: ResolvedTree;
  currentItemId: string;
  onChange: (code: string, value: string | string[]) => void;
  onSubmit: (answers: Record<string, string | string[]>) => void;
}
```

## JSONPath Expression Reference

Two query roots:

- **`@`** — Current item's answer map (top-level usage). Inside `[?...]` filters, standard JSONPath filter variable.
- **`$`** — Root document (all items keyed by stable IDs).

| Pattern | Meaning |
|---------|---------|
| `@.CODE == 'VAL'` | Current item equality |
| `@.CODE != 'VAL'` | Current item inequality |
| `@.CODE[?@ == 'VAL']` | Multi-select membership (truthy if non-empty) |
| `@.CODE.length > N` | Multi-select count |
| `$[*].CODE` | All items' answers for CODE |
| `$[?@.CODE == 'VAL']` | Filter items by answer |
| `$[?@.CODE == 'VAL'].length > N` | Count matching items |

## Answer Store Shape

```json
{
  "1.2/1": {
    "VERDICT": "APR",
    "TAGS": [],
    "PRI": "MED"
  },
  "1.2/2": {
    "VERDICT": "REJ",
    "REASON": "QUA",
    "TAGS": ["urgent", "blocker"],
    "PRI": "HI"
  }
}
```

- Keys from `[CODE]` on question lines. `[_CODE]` strips underscore.
- Single-select → string. Multi-select → array.

## Related

- `§CMD_DECISION_TREE` — Protocol command (syntax, algorithm, constraints)
- `sessions/2026_02_25_CONDITIONAL_TREE_SYNTAX/BRAINSTORM.md` — Design decisions
- `sessions/2026_02_14_DECISION_TREE_DESIGN/BRAINSTORM.md` — Original tree format design
