import ICAL from "ical.js";
export type Course = {
  id: string;
  key: string;
  title: string;
  shortID: string;
  teacher: string;
  location: string;
  start: number;
  end: number;
  exam?: boolean;
};
export type Todo = {
  id: string;
  title: string;
  deadline?: number;
  pinned: boolean;
  done: boolean;
};
export type Homework = {
  id: string;
  number: string;
  subject: string;
  title: string;
  deadline?: number;
  pinned: boolean;
  items: { id: string; title: string; done: boolean }[];
};
export type State = {
  version: 1;
  courses: Course[];
  todos: Todo[];
  homework: Homework[];
  usedNumbers: string[];
  subscription: string;
  modules: { id: string; enabled: boolean; pinned: boolean }[];
  pet: {
    image: string;
    size: number;
    x: number;
    y: number;
    tap: string;
    hold: string;
  };
  theme: string;
  accent: string;
};
export const uid = () => crypto.randomUUID();
export const empty = (): State => ({
  version: 1,
  courses: [],
  todos: [],
  homework: [],
  usedNumbers: [],
  subscription: "",
  modules: [
    { id: "focus", enabled: true, pinned: true },
    { id: "pet", enabled: true, pinned: true },
  ],
  pet: {
    image: "",
    size: 136,
    x: 1,
    y: 1,
    tap: "今天也一起加油吧！\n课表看好，别跑错教室啦。",
    hold: "正在蓄力……",
  },
  theme: "system",
  accent: "#00679c",
});
export const day = (n: number) => {
  const d = new Date(n);
  d.setHours(0, 0, 0, 0);
  return +d;
};
export const plusDays = (n: number, k: number) => {
  const d = new Date(n);
  d.setDate(d.getDate() + k);
  return +d;
};
export const monday = (n: number) =>
  plusDays(day(n), -((new Date(n).getDay() + 6) % 7));
export const time = (n: number) =>
  new Date(n).toLocaleTimeString("zh-CN", {
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  });
export const date = (n: number) =>
  new Date(n).toLocaleDateString("zh-CN", { month: "long", day: "numeric" });
export const range = (c: Course) => `${time(c.start)}–${time(c.end)}`;
export const left = (ms: number) => {
  const s = Math.max(0, Math.ceil(ms / 1000));
  return `${String(Math.floor(s / 3600)).padStart(2, "0")}:${String(Math.floor(s / 60) % 60).padStart(2, "0")}:${String(s % 60).padStart(2, "0")}`;
};
export function shortID(used: Set<string>) {
  const chars = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";
  for (let i = 0; i < 10000; i++) {
    const bytes = crypto.getRandomValues(new Uint8Array(5));
    const id = Array.from(bytes, (n) => chars[n % chars.length]).join("");
    if (!used.has(id)) return id;
  }
  throw Error("课程编号分配失败，请重试");
}
export function homeworkID(used: string[]) {
  const taken = new Set(used);
  const available = Array.from(
    { length: 10000 },
    (_, i) => `H${String(i).padStart(4, "0")}`,
  ).filter((x) => !taken.has(x));
  if (!available.length) throw Error("作业编号已用尽");
  return available[
    crypto.getRandomValues(new Uint32Array(1))[0] % available.length
  ];
}
export function featured(courses: Course[], now: number) {
  return courses
    .filter((c) => c.end > now)
    .sort((a, b) => a.start - b.start)[0];
}
export function laneLayout(courses: Course[]) {
  const sorted = [...courses].sort(
    (a, b) => a.start - b.start || a.end - b.end,
  );
  const out: { course: Course; lane: number; lanes: number }[] = [];
  let group: typeof out = [];
  let ends: number[] = [];
  let groupEnd = 0;
  function flush() {
    group.forEach((x) => (x.lanes = ends.length));
    out.push(...group);
    group = [];
    ends = [];
  }
  for (const course of sorted) {
    if (course.start >= groupEnd) flush();
    let lane = ends.findIndex((e) => e <= course.start);
    if (lane < 0) lane = ends.length;
    ends[lane] = course.end;
    groupEnd = Math.max(course.end, ...ends);
    group.push({ course, lane, lanes: 1 });
  }
  flush();
  return out;
}
const slots = [480, 535, 610, 665, 825, 880, 955, 1010, 1125, 1180];
// Compress only empty standard breaks; preserve monotonic placement for unusual times.
export function yMinute(minute: number) {
  const knots = [0, 480, 580, 610, 710, 825, 925, 955, 1055, 1125, 1225, 1440];
  const ys = [-50, 0, 100, 114, 214, 240, 340, 354, 454, 480, 580, 620];
  let i = knots.findIndex(
    (v, j) => j < knots.length - 1 && minute >= v && minute < knots[j + 1],
  );
  if (i < 0) i = minute < 0 ? 0 : knots.length - 2;
  return (
    ys[i] +
    ((minute - knots[i]) / (knots[i + 1] - knots[i])) * (ys[i + 1] - ys[i])
  );
}
export const minute = (n: number) =>
  new Date(n).getHours() * 60 + new Date(n).getMinutes();
export { slots };
export function parseICS(
  text: string,
  existing: Course[],
  source = "ics",
  now = Date.now(),
): Course[] {
  const root = new ICAL.Component(ICAL.parse(text));
  if (root.name !== "vcalendar") throw Error("请选择有效的 ICS 日历");
  root.getAllSubcomponents("vtimezone").forEach((c) => {
    const id = c.getFirstPropertyValue("tzid");
    if (typeof id === "string")
      ICAL.TimezoneService.register(new ICAL.Timezone(c), id);
  });
  const components = root.getAllSubcomponents("vevent");
  const events = components.map((c) => new ICAL.Event(c));
  const used = new Set(existing.map((c) => c.shortID));
  const profiles = new Map(
    existing.map((c) => [c.key, { shortID: c.shortID, teacher: c.teacher }]),
  );
  const result: Course[] = [];
  const lower = plusDays(now, -180),
    upper = plusDays(now, 370);
  for (const event of events.filter((e) => !e.isRecurrenceException())) {
    events
      .filter((e) => e.isRecurrenceException() && e.uid === event.uid)
      .forEach((e) => event.relateException(e));
    const title = event.summary?.trim();
    if (!title) continue;
    const key = source + "::" + title.replace(/\s+/g, " ");
    let profile = profiles.get(key);
    if (!profile) {
      const id = shortID(used);
      used.add(id);
      profile = { shortID: id, teacher: "" };
      profiles.set(key, profile);
    }
    const iterator = event.iterator();
    let count = 0;
    while (count++ < 20000) {
      const occurrence = iterator.next();
      if (!occurrence) break;
      const detail = event.getOccurrenceDetails(occurrence);
      const start = +detail.startDate.toJSDate(),
        end = +detail.endDate.toJSDate();
      if (start > upper) break;
      if (end <= lower || end <= start) continue;
      const cancelled = detail.item.component.getFirstPropertyValue("status");
      if (cancelled === "CANCELLED") continue;
      result.push({
        id: `${source}:${event.uid}:${start}`,
        key,
        title: detail.item.summary || title,
        ...profile,
        location: detail.item.location || "",
        start,
        end,
      });
    }
    if (count >= 20000) throw Error("重复日程过多，请缩小日历范围后导入");
  }
  return result.sort((a, b) => a.start - b.start);
}
export function validate(input: unknown): State {
  const s = input as State;
  if (
    !s ||
    s.version !== 1 ||
    !Array.isArray(s.courses) ||
    !Array.isArray(s.todos) ||
    !Array.isArray(s.homework) ||
    !Array.isArray(s.usedNumbers) ||
    !Array.isArray(s.modules) ||
    !s.pet ||
    typeof s.theme !== "string" ||
    typeof s.accent !== "string" ||
    typeof s.subscription !== "string" ||
    typeof s.pet.image !== "string" ||
    typeof s.pet.tap !== "string" ||
    typeof s.pet.hold !== "string" ||
    !Number.isFinite(s.pet.size) ||
    s.pet.size < 72 ||
    s.pet.size > 240 ||
    !Number.isFinite(s.pet.x) ||
    !Number.isFinite(s.pet.y) ||
    s.pet.x < 0 ||
    s.pet.x > 1 ||
    s.pet.y < 0 ||
    s.pet.y > 1 ||
    !["focus", "pet"].every(
      (id) => s.modules.filter((m) => m.id === id).length === 1,
    )
  )
    throw Error("数据格式不受支持，未覆盖原文件");
  if (
    s.courses.some(
      (c) =>
        !Number.isFinite(c.start) ||
        !Number.isFinite(c.end) ||
        c.end <= c.start ||
        typeof c.title !== "string" ||
        typeof c.key !== "string" ||
        typeof c.shortID !== "string",
    ) ||
    s.homework.some(
      (h) => !Array.isArray(h.items) || typeof h.title !== "string",
    ) ||
    s.todos.some((t) => typeof t.title !== "string")
  )
    throw Error("数据损坏，未覆盖原文件");
  return s;
}
export function demo(now = Date.now()): State {
  const s = empty(),
    base = monday(now);
  const names = [
    "高等数学",
    "大学英语",
    "程序设计",
    "大学物理",
    "形势与政策（5）",
  ];
  const ids = ["8TJUJ", "CEJ8L", "4DXHU", "5Y9E3", "QQQ2M"];
  for (let w = 0; w < 2; w++)
    for (const [d, i, h, m] of [
      [0, 0, 8, 0],
      [0, 2, 13, 45],
      [1, 1, 10, 10],
      [2, 0, 8, 0],
      [2, 2, 13, 45],
      [3, 3, 8, 0],
      [3, 4, 15, 55],
      [4, 1, 10, 10],
    ]) {
      const start = new Date(plusDays(base, d + w * 7));
      start.setHours(h, m);
      s.courses.push({
        id: uid(),
        key: names[i],
        title: names[i],
        shortID: ids[i],
        teacher: ["王老师", "李老师", "陈老师", "", ""][i],
        location: [
          "教学楼 A302",
          "教学楼 B201",
          "机房 203",
          "教学楼 A105",
          "揽江楼 N409",
        ][i],
        start: +start,
        end: +start + 6000000,
      });
    }
  s.todos = [
    {
      id: uid(),
      title: "提交实验报告",
      pinned: true,
      done: false,
      deadline: day(now) + 18 * 3600000,
    },
    { id: uid(), title: "图书馆借书", pinned: false, done: false },
  ];
  s.usedNumbers = ["H2048"];
  s.homework = [
    {
      id: uid(),
      number: "H2048",
      subject: "程序设计",
      title: "第五周作业",
      pinned: false,
      deadline: plusDays(day(now), 2) + 86340000,
      items: [
        { id: uid(), title: "完成第一题", done: true },
        { id: uid(), title: "完成第二题", done: false },
        { id: uid(), title: "撰写实验报告", done: false },
      ],
    },
  ];
  s.courses.push({
    id: uid(),
    key: names[0],
    title: "高等数学期中考试",
    shortID: ids[0],
    teacher: "王老师",
    location: "教学楼 A302",
    start: plusDays(day(now), 3) + 9 * 3600000,
    end: plusDays(day(now), 3) + 11 * 3600000,
    exam: true,
  });
  return s;
}
