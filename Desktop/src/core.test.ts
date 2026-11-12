import { describe, it, expect } from "vitest";
import {
  day,
  monday,
  plusDays,
  homeworkID,
  shortID,
  laneLayout,
  parseICS,
  empty,
  validate,
  featured,
  yMinute,
  type Course,
} from "./core";
import { newFocus, advance } from "./focus";
const now = +new Date("2026-11-12T08:00:00Z");
const course = (id: string, start: number, end: number): Course => ({
  id,
  key: "math",
  title: "数学",
  shortID: "ABCDE",
  teacher: "",
  location: "",
  start,
  end,
});
describe("calendar", () => {
  it("finds Monday without mutating source", () =>
    expect(new Date(monday(now)).getDay()).toBe(1));
  it("uses local calendar days", () =>
    expect(day(plusDays(now, 1))).toBe(plusDays(day(now), 1)));
  it("course time positions are monotonic", () => {
    for (let i = 1; i < 1440; i++)
      expect(yMinute(i)).toBeGreaterThan(yMinute(i - 1));
  });
  it("lays overlapping courses side by side", () => {
    const layout = laneLayout([
      course("a", 0, 100),
      course("b", 40, 80),
      course("c", 100, 150),
    ]);
    expect(layout.map((x) => [x.lane, x.lanes])).toEqual([
      [0, 2],
      [1, 2],
      [0, 1],
    ]);
  });
  it("does not mutate original ordering", () => {
    const courses = [course("b", 20, 40), course("a", 0, 10)];
    laneLayout(courses);
    expect(courses[0].id).toBe("b");
  });
  it("selects current before upcoming and drops finished courses", () =>
    expect(
      featured(
        [
          course("ended", 0, 10),
          course("next", 30, 40),
          course("current", 10, 25),
        ],
        20,
      )?.id,
    ).toBe("current"));
  it("expands recurrence and preserves IDs and teacher", () => {
    const text =
      "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:abc\r\nDTSTART:20261112T080000Z\r\nDTEND:20261112T094000Z\r\nRRULE:FREQ=WEEKLY;COUNT=3\r\nEXDATE:20261119T080000Z\r\nSUMMARY:数学\r\nLOCATION:A302\r\nEND:VEVENT\r\nEND:VCALENDAR";
    const first = parseICS(text, [], "test", now);
    expect(first).toHaveLength(2);
    const second = parseICS(
      text,
      first.map((c) => ({ ...c, teacher: "王老师" })),
      "test",
      now,
    );
    expect(second[0].shortID).toBe(first[0].shortID);
    expect(second[0].teacher).toBe("王老师");
    expect(second[0].location).toBe("A302");
  });
  it("rejects broken ICS", () =>
    expect(() => parseICS("garbage", [])).toThrow());
});
describe("data and IDs", () => {
  it("never reuses consumed homework IDs", () =>
    expect(
      homeworkID(
        Array.from(
          { length: 9999 },
          (_, i) => `H${String(i).padStart(4, "0")}`,
        ),
      ),
    ).toBe("H9999"));
  it("reports exhaustion instead of hanging", () =>
    expect(() =>
      homeworkID(
        Array.from(
          { length: 10000 },
          (_, i) => `H${String(i).padStart(4, "0")}`,
        ),
      ),
    ).toThrow());
  it("assigns five-character course IDs", () =>
    expect(shortID(new Set())).toMatch(
      /^[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{5}$/,
    ));
  it("validates only the desktop schema", () => {
    expect(validate(empty())).toEqual(empty());
    expect(() => validate({ schemaVersion: 1 })).toThrow();
  });
});
describe("focus", () => {
  it("advances to a five-minute break", () =>
    expect(
      advance({ ...newFocus(), phase: "focus", deadline: now, cycles: 2 }, now),
    ).toMatchObject({ phase: "rest", completed: 1, deadline: now + 300000 }));
  it("finishes final cycle without extra break", () =>
    expect(
      advance({ ...newFocus(), phase: "focus", deadline: now, cycles: 1 }, now),
    ).toMatchObject({ phase: "finished", deadline: null, completed: 1 }));
  it("catches up after sleep", () =>
    expect(
      advance(
        { ...newFocus(), phase: "focus", deadline: now, cycles: 2 },
        now + 1800000,
      ),
    ).toMatchObject({ phase: "finished", completed: 2 }));
  it("keeps paused session unchanged", () => {
    const s = { ...newFocus(), phase: "focus" as const, remaining: 90000 };
    expect(advance(s, now)).toEqual(s);
  });
});
