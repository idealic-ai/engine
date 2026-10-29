import { createRoot } from "react-dom/client";
// The app's own look: Slate tokens (theme.css), then the components that read them (styles.css).
// The /decide board kit is no longer imported; asks keep a theme of their own.
import "./theme.css";
import "./styles.css";
import { App } from "./App.tsx";

createRoot(document.getElementById("root")!).render(<App />);
