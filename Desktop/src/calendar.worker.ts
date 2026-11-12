import { parseICS, type Course } from "./core";
self.onmessage = (
  event: MessageEvent<{ text: string; existing: Course[]; source: string }>,
) => {
  try {
    const { text, existing, source } = event.data;
    self.postMessage({ courses: parseICS(text, existing, source) });
  } catch (error) {
    self.postMessage({ error: String(error) });
  }
};
