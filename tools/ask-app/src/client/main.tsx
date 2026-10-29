import { createRoot } from "react-dom/client";
// The /decide board kit, imported as is so the cards look like a /decide board and pick up its
// fixes: tokens → block catalog → widgets → warm overrides (the same order the board skeleton
// links them). Never restyle these classes in styles.css; that sheet holds only the app chrome.
import "../../../../skills/intake/assets/proof-theme.css";
import "../../../../skills/intake/assets/proof-blocks.css";
import "../../../../skills/intake/assets/board-widgets.css";
import "../../../../skills/intake/assets/board-warm-overrides.css";
import "./styles.css";
import { App } from "./App.tsx";

createRoot(document.getElementById("root")!).render(<App />);
