export type FocusState = {
  phase: "idle" | "focus" | "rest" | "finished";
  cycles: number;
  completed: number;
  deadline: number | null;
  remaining: number;
};
export const newFocus = (): FocusState => ({
  phase: "idle",
  cycles: 4,
  completed: 0,
  deadline: null,
  remaining: 1500000,
});
export function advance(s: FocusState, now: number): FocusState {
  let n = { ...s };
  for (let i = 0; i < 24 && n.deadline !== null && n.deadline <= now; i++) {
    if (n.phase === "focus") {
      n.completed++;
      if (n.completed >= n.cycles) {
        n.phase = "finished";
        n.deadline = null;
        n.remaining = 0;
      } else {
        n.phase = "rest";
        n.deadline += 300000;
      }
    } else if (n.phase === "rest") {
      n.phase = "focus";
      n.deadline += 1500000;
    } else break;
  }
  return n;
}
