import React, {
  useState,
  useEffect,
  useMemo,
  useRef,
  type CSSProperties,
  type FormEvent,
} from "react";
import { createRoot } from "react-dom/client";
import {
  House,
  CalendarDays,
  ListTodo,
  LayoutGrid,
  RefreshCw,
  Palette,
  Settings,
  Plus,
  ChevronLeft,
  ChevronRight,
  MapPin,
  Timer,
  PawPrint,
  Maximize2,
  ArrowUpRight,
  ClipboardList,
  X,
  GripHorizontal,
  Pin,
  Trash2,
  Download,
  Upload,
  Pause,
  Play,
  RotateCcw,
} from "lucide-react";
import {
  empty,
  demo,
  uid,
  day,
  plusDays,
  monday,
  time,
  date,
  range,
  left,
  featured,
  laneLayout,
  yMinute,
  minute,
  slots,
  homeworkID,
  shortID,
  parseICS,
  type State,
  type Course,
  type Homework,
} from "./core";
import { load, save, fetchCalendar, native } from "./storage";
import "./style.css";
const palette = [
  "#00679c",
  "#167f82",
  "#7650b5",
  "#af416c",
  "#32754a",
  "#a66b27",
  "#4d6071",
];
const themes = [
  "南信大蓝",
  "湖水青",
  "鸢尾紫",
  "玫瑰红",
  "松林绿",
  "暖砂金",
  "石墨灰",
];
const clock = (n?: number) => (n ? `${date(n)} ${time(n)}` : "未设置时间");
const localValue = (n?: number) =>
  n
    ? `${new Date(n).getFullYear()}-${String(new Date(n).getMonth() + 1).padStart(2, "0")}-${String(new Date(n).getDate()).padStart(2, "0")}T${time(n)}`
    : "";
function App() {
  const [state, setState] = useState<State>(empty),
    [ready, setReady] = useState(false),
    [fatal, setFatal] = useState(""),
    [error, setError] = useState(""),
    [demoMode, setDemo] = useState(false),
    [page, setPage] = useState("schedule"),
    [modal, setModal] = useState(""),
    [selected, setSelected] = useState<Course>(),
    [week, setWeek] = useState(0),
    [now, setNow] = useState(Date.now()),
    [busy, setBusy] = useState(false),
    [systemDark, setSystemDark] = useState(
      matchMedia("(prefers-color-scheme: dark)").matches,
    );
  const saveQueue = useRef(Promise.resolve());
  const file = useRef<HTMLInputElement>(null);
  const initial = useRef(true);
  useEffect(() => {
    load()
      .then((s) => {
        setState(s);
        setReady(true);
      })
      .catch((e) => setFatal(String(e)));
    const t = setInterval(() => setNow(Date.now()), 1000);
    const mq = matchMedia("(prefers-color-scheme: dark)");
    const on = (e: MediaQueryListEvent) => setSystemDark(e.matches);
    mq.addEventListener("change", on);
    return () => {
      clearInterval(t);
      mq.removeEventListener("change", on);
    };
  }, []);
  useEffect(() => {
    if (!ready) return;
    if (initial.current) {
      initial.current = false;
      return;
    }
    if (demoMode) return;
    const timer = setTimeout(() => {
      saveQueue.current = saveQueue.current
        .catch(() => {})
        .then(() => save(state))
        .catch((e) => setError("保存失败：" + String(e)));
    }, 200);
    return () => clearTimeout(timer);
  }, [state, ready, demoMode]);
  function update(fn: (s: State) => State) {
    setState((s) => fn(s));
  }
  const subjects = [...new Map(state.courses.map((c) => [c.key, c])).values()];
  function color(c: Course) {
    return c.exam
      ? "#be6414"
      : palette[
          Math.max(
            0,
            subjects.findIndex((s) => s.key === c.key),
          ) % palette.length
        ];
  }
  const current = useMemo(
    () => featured(state.courses, now),
    [state.courses, Math.floor(now / 1000)],
  );
  const today = state.courses.filter((c) => day(c.start) === day(now));
  const exams = state.courses
    .filter((c) => c.exam && c.start >= now && c.start < plusDays(now, 7))
    .sort((a, b) => a.start - b.start);
  async function importText(text: string, source = "ics") {
    const courses = await new Promise<Course[]>((resolve, reject) => {
      const worker = new Worker(
        new URL("./calendar.worker.ts", import.meta.url),
        { type: "module" },
      );
      const timeout = setTimeout(() => {
        worker.terminate();
        reject(Error("日历解析超时，请缩小范围后重试"));
      }, 30000);
      worker.onmessage = (e) => {
        clearTimeout(timeout);
        worker.terminate();
        e.data.error ? reject(Error(e.data.error)) : resolve(e.data.courses);
      };
      worker.onerror = (e) => {
        clearTimeout(timeout);
        worker.terminate();
        reject(Error(e.message));
      };
      worker.postMessage({ text, existing: state.courses, source });
    });
    if (!courses.length)
      throw Error("未找到有效课程（读取范围为过去 180 天至未来 370 天）");
    update((s) => {
      const ids = new Set(courses.map((c) => c.id));
      const marked = new Set(s.courses.filter((c) => c.exam).map((c) => c.id));
      return {
        ...s,
        courses: [
          ...s.courses.filter((c) => c.exam && !ids.has(c.id)),
          ...courses.map((c) => (marked.has(c.id) ? { ...c, exam: true } : c)),
        ],
      };
    });
    setModal("");
  }
  async function sync() {
    if (!state.subscription) {
      setModal("settings");
      return;
    }
    setBusy(true);
    try {
      await importText(await fetchCalendar(state.subscription), "subscription");
    } catch (e) {
      setError(String(e));
    } finally {
      setBusy(false);
    }
  }
  function module(id: string) {
    return state.modules.find((m) => m.id === id)!;
  }
  function changeModule(id: string, field: "enabled" | "pinned") {
    update((s) => ({
      ...s,
      modules: s.modules.map((m) =>
        m.id === id ? { ...m, [field]: !m[field] } : m,
      ),
    }));
  }
  function reorder(id: string, offset: number) {
    update((s) => {
      const modules = [...s.modules],
        i = modules.findIndex((m) => m.id === id),
        j = i + offset;
      if (j < 0 || j >= modules.length) return s;
      [modules[i], modules[j]] = [modules[j], modules[i]];
      return { ...s, modules };
    });
  }
  function badge(c: Course) {
    return (
      <b className="badge" style={{ background: color(c) }}>
        #{c.shortID}
      </b>
    );
  }
  function hero(compact = false) {
    const c = current,
      ongoing = c && c.start <= now;
    return (
      <section
        className={"hero " + (compact ? "compact" : "")}
        style={
          {
            "--ink": c?.exam ? "var(--orange)" : "var(--accent)",
          } as CSSProperties
        }
      >
        {c ? (
          <>
            <div className="hero-top">
              <span className="status">
                ●　
                {ongoing
                  ? c.exam
                    ? "正在考试"
                    : "正在上课"
                  : (day(c.start) > day(now) ? `${date(c.start)} · ` : "") +
                    (c.exam ? "下一场考试" : "下节课")}
                　{badge(c)}
              </span>
              <small>
                {new Date(c.start).toLocaleDateString("zh-CN", {
                  month: "long",
                  day: "numeric",
                  weekday: "long",
                })}
              </small>
            </div>
            <div className="hero-main">
              <h1>{c.title}</h1>
              <div className="countdown">
                <small>
                  {ongoing ? "距结束" : c.exam ? "距开考" : "距上课"}
                </small>
                <strong>{left((ongoing ? c.end : c.start) - now)}</strong>
              </div>
            </div>
            <div className="hero-footer">
              <div>
                <small>{c.exam ? "考试时间" : "课程时间"}</small>
                <strong>{range(c)}</strong>
              </div>
              <div>
                <small>{c.exam ? "考场" : "教室"}</small>
                <strong>{c.location || "待定"}</strong>
              </div>
              {c.teacher && (
                <div>
                  <small>老师</small>
                  <strong>{c.teacher}</strong>
                </div>
              )}
              <span className="hero-type">
                <ClipboardList size={18} />
                {c.exam ? "考试" : "课程"}
              </span>
            </div>
          </>
        ) : (
          <div className="empty">
            <CalendarDays />
            <h2>{state.courses.length ? "近期课程已结束" : "还没有课表"}</h2>
            <p>
              {state.courses.length
                ? "好好休息，安排一下自己的时间。"
                : "导入学校 ICS 日历，开启你的校园日程。"}
            </p>
            <button onClick={() => setModal("settings")}>连接课表日历</button>
          </div>
        )}
      </section>
    );
  }
  function notices() {
    return (
      exams.length > 0 && (
        <div className="exam-grid">
          {exams
            .filter((c) => c.id !== current?.id)
            .map((c) => (
              <button
                className="exam-card"
                key={c.id}
                onClick={() => {
                  setSelected(c);
                  setModal("course");
                }}
              >
                <div>
                  <span>
                    <ClipboardList size={15} /> 考试 · 7天内
                  </span>
                  <small>{date(c.start)}</small>
                </div>
                <h3>{c.title}</h3>
                <p>
                  {time(c.start)}　{c.location}
                </p>
              </button>
            ))}
        </div>
      )
    );
  }
  function tasks(homework = false) {
    return (
      <section className="task-panel">
        <header>
          <h3>{homework ? "作业" : "个人日程"}</h3>
          <button
            className="icon"
            title={homework ? "添加作业" : "添加日程"}
            onClick={() => setModal(homework ? "homework" : "todo")}
          >
            <Plus size={18} />
          </button>
        </header>
        {homework
          ? state.homework.map((h) => (
              <article className="task homework" key={h.id}>
                <div className="task-head">
                  <span className="eyebrow">
                    {h.subject} · #{h.number}
                  </span>
                  <button
                    className="icon subtle"
                    title="删除作业"
                    onClick={() => {
                      if (confirm("删除这份作业？编号不会再次使用。"))
                        update((s) => ({
                          ...s,
                          homework: s.homework.filter((x) => x.id !== h.id),
                        }));
                    }}
                  >
                    <Trash2 size={13} />
                  </button>
                </div>
                <h4>{h.title}</h4>
                {h.items.map((item) => (
                  <label className="checkline" key={item.id}>
                    <input
                      type="checkbox"
                      checked={item.done}
                      onChange={() =>
                        update((s) => ({
                          ...s,
                          homework: s.homework.map((x) =>
                            x.id === h.id
                              ? {
                                  ...x,
                                  items: x.items.map((i) =>
                                    i.id === item.id
                                      ? { ...i, done: !i.done }
                                      : i,
                                  ),
                                }
                              : x,
                          ),
                        }))
                      }
                    />
                    <span className={item.done ? "done" : ""}>
                      {item.title}
                    </span>
                  </label>
                ))}
                <div className="progress">
                  <i
                    style={{
                      width: `${h.items.length ? (h.items.filter((i) => i.done).length / h.items.length) * 100 : 0}%`,
                    }}
                  />
                </div>
                <small
                  className={
                    h.deadline &&
                    h.deadline < now &&
                    !h.items.every((i) => i.done)
                      ? "overdue"
                      : ""
                  }
                >
                  {h.items.filter((i) => i.done).length}/{h.items.length}{" "}
                  已完成　{h.deadline ? clock(h.deadline) : "无截止时间"}
                </small>
              </article>
            ))
          : [...state.todos]
              .sort(
                (a, b) =>
                  Number(a.done) - Number(b.done) ||
                  Number(b.pinned) - Number(a.pinned),
              )
              .map((t) => (
                <article className="task" key={t.id}>
                  <label className="checkline">
                    <input
                      type="checkbox"
                      checked={t.done}
                      onChange={() =>
                        update((s) => ({
                          ...s,
                          todos: s.todos.map((x) =>
                            x.id === t.id ? { ...x, done: !x.done } : x,
                          ),
                        }))
                      }
                    />
                    <span className={t.done ? "done" : ""}>{t.title}</span>
                    {t.pinned && <Pin size={12} />}
                  </label>
                  <div className="task-head">
                    <small
                      className={
                        t.deadline && t.deadline < now && !t.done
                          ? "overdue"
                          : ""
                      }
                    >
                      {t.deadline ? clock(t.deadline) : "随时安排"}
                    </small>
                    <button
                      title="删除日程"
                      className="icon subtle"
                      onClick={() =>
                        update((s) => ({
                          ...s,
                          todos: s.todos.filter((x) => x.id !== t.id),
                        }))
                      }
                    >
                      <Trash2 size={12} />
                    </button>
                  </div>
                </article>
              ))}
        {(homework ? !state.homework.length : !state.todos.length) && (
          <p className="empty-note">
            {homework
              ? "还没有作业，添加后逐项完成。"
              : "暂无日程，留点时间给自己。"}
          </p>
        )}
      </section>
    );
  }
  function schedule() {
    const start = plusDays(monday(now), week * 7),
      events = state.courses.filter(
        (c) => c.start >= start && c.start < plusDays(start, 7),
      ),
      shift = Math.max(
        0,
        -Math.min(0, ...events.map((c) => yMinute(minute(c.start)))),
      ),
      height =
        Math.max(
          595,
          ...events.map(
            (c) =>
              yMinute(day(c.end) > day(c.start) ? 1440 : minute(c.end)) + 15,
          ),
        ) + shift;
    return (
      <>
        <div className="week-toolbar">
          <div>
            <h2>
              {date(start)} — {date(plusDays(start, 6))}
            </h2>
            <small>{new Date(start).getFullYear()} · 每周课表</small>
          </div>
          <div className="actions">
            <button
              className="icon"
              title="上一周"
              onClick={() => setWeek(week - 1)}
            >
              <ChevronLeft size={18} />
            </button>
            <button onClick={() => setWeek(0)}>本周</button>
            <button
              className="icon"
              title="下一周"
              onClick={() => setWeek(week + 1)}
            >
              <ChevronRight size={18} />
            </button>
            <button onClick={() => setModal("exam")}>＋ 考试</button>
          </div>
        </div>
        <div className="calendar-scroll">
          <div className="calendar">
            <div className="day-head time-head">时间</div>
            {Array.from({ length: 7 }, (_, i) => {
              const n = plusDays(start, i);
              return (
                <div
                  key={i}
                  className={"day-head " + (day(now) === day(n) ? "today" : "")}
                >
                  <span>周{"一二三四五六日"[i]}</span>
                  <b>{new Date(n).getDate()}</b>
                </div>
              );
            })}
            <div className="time-axis" style={{ height }}>
              {slots.map((m, i) => (
                <span key={m} style={{ top: yMinute(m) + shift }}>
                  <b>{i + 1}</b>
                  {String(Math.floor(m / 60)).padStart(2, "0")}:
                  {String(m % 60).padStart(2, "0")}
                </span>
              ))}
            </div>
            {Array.from({ length: 7 }, (_, i) => (
              <div
                className={
                  "day-column " +
                  (day(now) === day(plusDays(start, i)) ? "today-column" : "")
                }
                key={i}
                style={{ height }}
              >
                {slots.map((m) => (
                  <i
                    className="grid-line"
                    key={m}
                    style={{ top: yMinute(m) + shift }}
                  />
                ))}
                {laneLayout(
                  events.filter(
                    (c) => day(c.start) === day(plusDays(start, i)),
                  ),
                ).map(({ course: c, lane, lanes }) => (
                  <button
                    className={"course " + (c.exam ? "exam" : "")}
                    key={c.id}
                    style={
                      {
                        top: yMinute(minute(c.start)) + shift,
                        height:
                          Math.max(
                            37,
                            yMinute(
                              day(c.end) > day(c.start) ? 1440 : minute(c.end),
                            ) - yMinute(minute(c.start)),
                          ) - 3,
                        left: `calc(${(lane / lanes) * 100}% + 3px)`,
                        width: `calc(${100 / lanes}% - 6px)`,
                        "--course": color(c),
                      } as CSSProperties
                    }
                    onClick={() => {
                      setSelected(c);
                      setModal("course");
                    }}
                  >
                    <strong>
                      {c.exam ? "考试 · " : ""}
                      {c.title}
                    </strong>
                    <span>{range(c)}</span>
                    <span>{c.location}</span>
                    {c.teacher && <span>{c.teacher}</span>}
                  </button>
                ))}
              </div>
            ))}
          </div>
        </div>
        <div className="ddl-strip">
          {[
            ...state.todos
              .filter(
                (t) =>
                  !t.done &&
                  t.deadline &&
                  t.deadline >= start &&
                  t.deadline < plusDays(start, 7),
              )
              .map((t) => ({ title: t.title, deadline: t.deadline! })),
            ...state.homework
              .filter(
                (h) =>
                  !h.items.every((i) => i.done) &&
                  h.deadline &&
                  h.deadline >= start &&
                  h.deadline < plusDays(start, 7),
              )
              .map((h) => ({
                title: `#${h.number} ${h.title}`,
                deadline: h.deadline!,
              })),
          ].map((t, i) => (
            <span key={i}>
              <Timer size={13} />
              {t.title} · {clock(t.deadline)}
            </span>
          ))}
        </div>
        <div className="bottom-board">
          {hero(true)}
          {notices()}
        </div>
      </>
    );
  }
  if (fatal)
    return (
      <div className="fatal">
        <h2>读取数据失败</h2>
        <p>{fatal}</p>
        <p>原数据未覆盖，请备份后检查。刷新可重试。</p>
      </div>
    );
  if (!ready) return <p className="empty-note">正在读取本地日程…</p>;
  return (
    <div
      className="app"
      data-theme={
        state.theme === "system" ? (systemDark ? "dark" : "light") : state.theme
      }
      style={{ "--accent-base": state.accent } as CSSProperties}
    >
      <nav>
        <div className="brand">
          <img src="/app-icon.png" />
          CampusGo Ultra
        </div>
        <div className="nav-items">
          {[
            ["home", "摘要", House],
            ["schedule", "课表", CalendarDays],
            ["work", "作业与日程", ListTodo],
            ["discover", "发现", LayoutGrid],
          ].map(([id, title, Icon]) => (
            <button
              key={String(id)}
              className={page === id ? "active" : ""}
              onClick={() => setPage(String(id))}
            >
              {React.createElement(Icon as typeof House, { size: 18 })}
              {String(title)}
            </button>
          ))}
        </div>
        <div className="nav-tools">
          {demoMode && (
            <button
              onClick={async () => {
                try {
                  const real = await load();
                  setDemo(false);
                  setState(real);
                } catch (e) {
                  setError(String(e));
                }
              }}
            >
              退出演示
            </button>
          )}
          <button
            className="icon"
            title="同步课表"
            onClick={sync}
            disabled={busy || demoMode}
          >
            <RefreshCw size={17} className={busy ? "spin" : ""} />
          </button>
          <button
            className="icon"
            title="主题"
            onClick={() => setModal("theme")}
          >
            <Palette size={17} />
          </button>
          <button
            className="icon"
            title="设置"
            onClick={() => setModal("settings")}
          >
            <Settings size={17} />
          </button>
        </div>
      </nav>
      {!state.courses.length && (
        <div className="connect-bar">
          <CalendarDays size={16} />
          <span>连接学校课表日历，自动生成一周课程。</span>
          <button
            onClick={() => {
              setDemo(true);
              setState(demo());
            }}
          >
            先看示例
          </button>
          <button className="primary" onClick={() => setModal("settings")}>
            导入课表
          </button>
        </div>
      )}
      {page === "focus" ? (
        <div className="focus-page">
          <button onClick={() => setPage("home")}>‹ 返回摘要</button>
          <Focus
            enabled={module("focus").enabled}
            expanded
            demoMode={demoMode}
          />
        </div>
      ) : page === "discover" ? (
        <main className="discover">
          <div className="section-title">
            <div>
              <h1>发现</h1>
              <p>按需启用功能，把常用卡片放进摘要。</p>
            </div>
            <button onClick={() => setPage("home")}>
              整理摘要 <ArrowUpRight size={14} />
            </button>
          </div>
          <div className="module-grid">
            {state.modules.map((m) => (
              <section className="module-card" key={m.id}>
                <header>
                  <span className="module-icon">
                    {m.id === "focus" ? <Timer /> : <PawPrint />}
                  </span>
                  <div>
                    <h2>{m.id === "focus" ? "番茄钟" : "窗口桌宠"}</h2>
                    <small>{m.enabled ? "已启用" : "已关闭"} · 内置功能</small>
                  </div>
                  <input
                    aria-label={"启用" + m.id}
                    className="switch"
                    type="checkbox"
                    checked={m.enabled}
                    onChange={() => changeModule(m.id, "enabled")}
                  />
                </header>
                <p>
                  {m.id === "focus"
                    ? "25 分钟专注、5 分钟休息，支持循环与全窗口专注空间。"
                    : "放在窗口里的小伙伴，支持拖动、果冻弹跳和自定义台词。"}
                </p>
                <div className="tags">
                  <span>摘要卡片</span>
                  <span>{m.id === "focus" ? "独立页面" : "窗口悬浮"}</span>
                </div>
                <footer>
                  <button onClick={() => changeModule(m.id, "pinned")}>
                    {m.pinned ? "✓ 已加入摘要" : "＋ 加入摘要"}
                  </button>
                  <button
                    className="link"
                    onClick={() =>
                      m.id === "focus" ? setPage("focus") : setModal("pet")
                    }
                  >
                    设置 / 打开
                  </button>
                </footer>
              </section>
            ))}
          </div>
        </main>
      ) : page === "work" ? (
        <main className="work-columns">
          <div>
            <WorkDash
              title="个人日程"
              count={state.todos.filter((t) => !t.done).length}
              next={state.todos.find((t) => !t.done)?.title}
            />
            {tasks()}
          </div>
          <div>
            <WorkDash
              title="待交作业"
              count={
                state.homework.filter((h) => !h.items.every((i) => i.done))
                  .length
              }
              next={
                state.homework.find((h) => !h.items.every((i) => i.done))?.title
              }
            />
            {tasks(true)}
          </div>
        </main>
      ) : (
        <div className="main-split">
          <main className={page === "schedule" ? "schedule" : "summary"}>
            {page === "schedule" ? (
              schedule()
            ) : (
              <>
                <div className="section-title">
                  <div>
                    <h2>
                      {new Date(now).toLocaleDateString("zh-CN", {
                        month: "long",
                        day: "numeric",
                        weekday: "long",
                      })}
                    </h2>
                    <small>
                      今日 {today.length} 节课 ·{" "}
                      {
                        state.homework.filter(
                          (h) => !h.items.every((i) => i.done),
                        ).length
                      }{" "}
                      份作业待完成 · {state.todos.filter((t) => !t.done).length}{" "}
                      项待办
                    </small>
                  </div>
                  <button className="link" onClick={() => setPage("schedule")}>
                    <ArrowUpRight size={16} /> 本周课表
                  </button>
                </div>
                {hero()}
                {exams.length > 1 && <h4 className="muted">接下来的考试</h4>}
                {notices()}
                <h4 className="muted">之后的行程</h4>
                {state.courses
                  .filter((c) => c.end > now && c.id !== current?.id)
                  .sort((a, b) => a.start - b.start)
                  .slice(0, 3)
                  .map((c) => (
                    <div
                      className="itinerary"
                      key={c.id}
                      style={{ "--course": color(c) } as CSSProperties}
                    >
                      <span>
                        {date(c.start)}　{range(c)}
                      </span>
                      <div>
                        <h3>{c.title}</h3>
                        <small>{c.location}</small>
                      </div>
                      {badge(c)}
                    </div>
                  ))}
                <div className="section-title">
                  <h4 className="muted">我的模块</h4>
                  <button className="link" onClick={() => setPage("discover")}>
                    ＋ 添加功能
                  </button>
                </div>
                <div className="module-grid">
                  {state.modules
                    .filter((m) => m.enabled && m.pinned)
                    .map((m) => (
                      <div key={m.id}>
                        <div className="module-toolbar">
                          <GripHorizontal size={14} />
                          <button
                            className="link"
                            onClick={() => reorder(m.id, -1)}
                          >
                            前移
                          </button>
                          <button
                            className="link"
                            onClick={() => reorder(m.id, 1)}
                          >
                            后移
                          </button>
                          <button
                            className="link"
                            onClick={() => changeModule(m.id, "pinned")}
                          >
                            移出摘要
                          </button>
                        </div>
                        {m.id === "focus" ? (
                          <Focus
                            enabled={m.enabled}
                            demoMode={demoMode}
                            onExpand={() => setPage("focus")}
                          />
                        ) : (
                          <section className="pet-card">
                            <h4>
                              <PawPrint size={17} /> 窗口桌宠
                            </h4>
                            <div>
                              {state.pet.image ? (
                                <img src={state.pet.image} />
                              ) : (
                                <PawPrint size={65} />
                              )}
                              <p>
                                点击弹一下，长按蓄力。把它放在喜欢的位置，写几句自己的台词。
                              </p>
                            </div>
                            <button
                              className="link"
                              onClick={() => setModal("pet")}
                            >
                              调整图片、大小与台词
                            </button>
                          </section>
                        )}
                      </div>
                    ))}
                </div>
              </>
            )}
          </main>
          <aside>
            {tasks()}
            {tasks(true)}
          </aside>
        </div>
      )}
      <FocusLifecycle enabled={module("focus").enabled} demoMode={demoMode} />
      {module("pet").enabled && (
        <Pet
          pet={state.pet}
          onMove={(x, y) => update((s) => ({ ...s, pet: { ...s.pet, x, y } }))}
        />
      )}
      <input
        ref={file}
        type="file"
        accept=".ics,text/calendar"
        hidden
        onChange={async (e) => {
          try {
            const f = e.target.files?.[0];
            if (f) {
              if (f.size > 8 * 1024 * 1024) throw Error("日历文件请小于 8 MB");
              await importText(await f.text());
            }
          } catch (err) {
            setError(String(err));
          }
          e.target.value = "";
        }}
      />
      {modal && (
        <div className="modal-backdrop" onClick={() => setModal("")}>
          <section
            className="modal"
            role="dialog"
            aria-modal="true"
            onClick={(e) => e.stopPropagation()}
          >
            <header>
              <h2>
                {
                  {
                    settings: "课表设置",
                    theme: "外观与主题",
                    todo: "添加个人日程",
                    homework: "添加作业",
                    exam: "添加考试",
                    course: "课程详情",
                    pet: "窗口桌宠设置",
                  }[modal]
                }
              </h2>
              <button
                className="icon"
                aria-label="关闭"
                onClick={() => setModal("")}
              >
                <X size={19} />
              </button>
            </header>
            {modal === "theme" ? (
              <>
                <label>
                  界面模式
                  <select
                    value={state.theme}
                    onChange={(e) =>
                      update((s) => ({ ...s, theme: e.target.value }))
                    }
                  >
                    <option value="system">跟随系统</option>
                    <option value="light">浅色</option>
                    <option value="dark">深色</option>
                  </select>
                </label>
                <h4>强调色</h4>
                <div className="theme-grid">
                  {palette.map((c, i) => (
                    <button
                      key={c}
                      onClick={() => update((s) => ({ ...s, accent: c }))}
                      style={{
                        color: c,
                        borderColor: c === state.accent ? c : undefined,
                      }}
                    >
                      ● {themes[i]}
                    </button>
                  ))}
                </div>
              </>
            ) : modal === "settings" ? (
              <>
                <h3>课表来源</h3>
                <p className="muted">
                  Windows 版通过订阅链接或 ICS 文件读取课程。
                </p>
                <label>
                  日历订阅地址
                  <input
                    placeholder="https://… 或 webcal://…"
                    value={state.subscription}
                    onChange={(e) =>
                      update((s) => ({ ...s, subscription: e.target.value }))
                    }
                  />
                </label>
                <div className="actions">
                  <button className="primary" disabled={busy} onClick={sync}>
                    {busy ? "同步中…" : "同步订阅"}
                  </button>
                  <button onClick={() => file.current?.click()}>
                    <Upload size={15} /> 导入 ICS
                  </button>
                </div>
                <h3>课程与老师</h3>
                {subjects.length ? (
                  subjects.map((c) => (
                    <label className="teacher-row" key={c.key}>
                      <span>
                        {badge(c)}　{c.title}
                      </span>
                      <input
                        placeholder="老师姓名（选填）"
                        value={c.teacher}
                        onChange={(e) =>
                          update((s) => ({
                            ...s,
                            courses: s.courses.map((x) =>
                              x.key === c.key
                                ? { ...x, teacher: e.target.value }
                                : x,
                            ),
                          }))
                        }
                      />
                    </label>
                  ))
                ) : (
                  <p className="empty-note">
                    导入后自动识别科目，在这里填写老师。
                  </p>
                )}
                <h3>数据备份</h3>
                <button
                  onClick={() => {
                    const a = document.createElement("a");
                    a.href = URL.createObjectURL(
                      new Blob([JSON.stringify(state, null, 2)], {
                        type: "application/json",
                      }),
                    );
                    a.download = "CampusGo-Desktop-backup.json";
                    a.click();
                    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
                  }}
                >
                  <Download size={15} /> 导出桌面版备份
                </button>
                <p className="muted">
                  桌面版数据独立保存，不会修改原 Mac 应用的数据。
                </p>
              </>
            ) : modal === "pet" ? (
              <>
                <div className="pet-preview">
                  {state.pet.image ? (
                    <img src={state.pet.image} />
                  ) : (
                    <PawPrint size={70} />
                  )}
                </div>
                <label>
                  选择图片
                  <input
                    type="file"
                    accept="image/png,image/jpeg,image/webp"
                    onChange={async (e) => {
                      try {
                        const f = e.target.files?.[0];
                        if (!f) return;
                        if (f.size > 30 * 1024 * 1024)
                          throw Error("图片请小于 30 MB");
                        const bitmap = await createImageBitmap(f);
                        const scale = Math.min(
                          1,
                          1024 / Math.max(bitmap.width, bitmap.height),
                        );
                        const canvas = document.createElement("canvas");
                        canvas.width = Math.max(
                          1,
                          Math.round(bitmap.width * scale),
                        );
                        canvas.height = Math.max(
                          1,
                          Math.round(bitmap.height * scale),
                        );
                        canvas
                          .getContext("2d")!
                          .drawImage(bitmap, 0, 0, canvas.width, canvas.height);
                        bitmap.close();
                        const image = canvas.toDataURL("image/png");
                        update((s) => ({ ...s, pet: { ...s.pet, image } }));
                      } catch (err) {
                        setError("无法读取图片：" + String(err));
                      }
                    }}
                  />
                </label>
                <button
                  onClick={() =>
                    update((s) => ({ ...s, pet: { ...s.pet, image: "" } }))
                  }
                >
                  恢复默认
                </button>
                <label>
                  大小 · {state.pet.size} px
                  <input
                    type="range"
                    min="72"
                    max="240"
                    value={state.pet.size}
                    onChange={(e) =>
                      update((s) => ({
                        ...s,
                        pet: { ...s.pet, size: +e.target.value },
                      }))
                    }
                  />
                </label>
                {(["tap", "hold"] as const).map((k) => (
                  <label key={k}>
                    {k === "tap" ? "点击台词" : "长按台词"}
                    <textarea
                      rows={4}
                      value={state.pet[k]}
                      placeholder="每行一句，留空不显示"
                      onChange={(e) =>
                        update((s) => ({
                          ...s,
                          pet: { ...s.pet, [k]: e.target.value },
                        }))
                      }
                    />
                  </label>
                ))}
                <button
                  onClick={() =>
                    update((s) => ({ ...s, pet: { ...s.pet, x: 1, y: 1 } }))
                  }
                >
                  回到右下角
                </button>
              </>
            ) : modal === "course" && selected ? (
              <>
                <div className="detail-title">
                  {badge(selected)}
                  <h2>{selected.title}</h2>
                </div>
                <p>
                  {clock(selected.start)} — {time(selected.end)}
                </p>
                <p>
                  <MapPin size={16} /> {selected.location || "未设置地点"}　
                  {selected.teacher}
                </p>
                <button
                  onClick={() => {
                    update((s) => ({
                      ...s,
                      courses: s.courses.map((c) =>
                        c.id === selected.id ? { ...c, exam: !c.exam } : c,
                      ),
                    }));
                    setModal("");
                  }}
                >
                  {selected.exam ? "取消考试标记" : "将此课次标记为考试"}
                </button>
              </>
            ) : (
              <EntryForm
                kind={modal}
                subjects={subjects}
                onSave={(f) => {
                  try {
                    const title = String(f.get("title") || "").trim();
                    if (!title) return;
                    const deadline = f.get("deadline")
                      ? +new Date(String(f.get("deadline")))
                      : undefined;
                    if (modal === "todo")
                      update((s) => ({
                        ...s,
                        todos: [
                          ...s.todos,
                          {
                            id: uid(),
                            title,
                            deadline,
                            pinned: f.get("pinned") === "on",
                            done: false,
                          },
                        ],
                      }));
                    else if (modal === "homework") {
                      const subject = String(f.get("subject") || "");
                      if (!subject) throw Error("请选择科目");
                      const items = String(f.get("items") || "")
                        .split("\n")
                        .map((x) => x.trim())
                        .filter(Boolean);
                      if (!items.length)
                        throw Error("请填写至少一个子作业条目");
                      update((s) => {
                        const number = homeworkID(s.usedNumbers);
                        return {
                          ...s,
                          usedNumbers: [...s.usedNumbers, number],
                          homework: [
                            ...s.homework,
                            {
                              id: uid(),
                              number,
                              title,
                              subject,
                              deadline,
                              pinned: f.get("pinned") === "on",
                              items: items.map((title) => ({
                                id: uid(),
                                title,
                                done: false,
                              })),
                            },
                          ],
                        };
                      });
                    } else {
                      const start = +new Date(String(f.get("start"))),
                        end = +new Date(String(f.get("end")));
                      if (
                        !Number.isFinite(start) ||
                        !Number.isFinite(end) ||
                        end <= start
                      )
                        throw Error("考试结束时间必须晚于开始时间");
                      const subject = subjects.find(
                        (c) => c.key === String(f.get("subject")),
                      );
                      update((s) => ({
                        ...s,
                        courses: [
                          ...s.courses,
                          {
                            id: uid(),
                            key: subject?.key || title,
                            shortID:
                              subject?.shortID ||
                              shortID(
                                new Set([
                                  ...s.courses.map((c) => c.shortID),
                                  ...s.usedNumbers,
                                ]),
                              ),
                            title,
                            teacher: subject?.teacher || "",
                            location: String(f.get("location") || ""),
                            start,
                            end,
                            exam: true,
                          },
                        ],
                      }));
                    }
                    setModal("");
                  } catch (err) {
                    setError(String(err));
                  }
                }}
              />
            )}
          </section>
        </div>
      )}
      {error && (
        <div role="alert" className="toast">
          <span>{error}</span>
          <button
            className="icon"
            aria-label="关闭错误"
            onClick={() => setError("")}
          >
            <X size={15} />
          </button>
        </div>
      )}
    </div>
  );
}
function WorkDash({
  title,
  count,
  next,
}: {
  title: string;
  count: number;
  next?: string;
}) {
  return (
    <section className="work-dash">
      <span>●　{title}</span>
      <div>
        <h2>{next || "暂时没有待办"}</h2>
        <strong>{count.toString().padStart(2, "0")}</strong>
      </div>
      <small>待完成 · 安排好自己的节奏</small>
    </section>
  );
}
function EntryForm({
  kind,
  subjects,
  onSave,
}: {
  kind: string;
  subjects: Course[];
  onSave: (f: FormData) => void;
}) {
  return (
    <form
      onSubmit={(e: FormEvent<HTMLFormElement>) => {
        e.preventDefault();
        onSave(new FormData(e.currentTarget));
      }}
    >
      <label>
        标题
        <input name="title" required autoFocus maxLength={200} />
      </label>
      {kind !== "todo" && (
        <label>
          科目
          <select
            aria-label="科目"
            name="subject"
            required={kind === "homework"}
          >
            <option value="">
              {kind === "exam" ? "不关联课程" : "选择科目"}
            </option>
            {subjects.map((c) => (
              <option key={c.key} value={kind === "homework" ? c.title : c.key}>
                {c.title}
              </option>
            ))}
          </select>
        </label>
      )}
      {kind === "homework" && (
        <label>
          子作业条目
          <textarea
            name="items"
            rows={5}
            placeholder="每行一个条目，支持回车换行"
            required
          />
        </label>
      )}
      {kind === "exam" ? (
        <>
          <label>
            开始时间
            <input
              type="datetime-local"
              name="start"
              required
              defaultValue={localValue(Date.now())}
            />
          </label>
          <label>
            结束时间
            <input
              type="datetime-local"
              name="end"
              required
              defaultValue={localValue(Date.now() + 3600000)}
            />
          </label>
          <label>
            考场
            <input name="location" />
          </label>
        </>
      ) : (
        <>
          <label>
            截止时间（选填）
            <input name="deadline" type="datetime-local" />
          </label>
          <label className="checkline">
            <input name="pinned" type="checkbox" />
            置顶
          </label>
        </>
      )}
      <button className="primary" type="submit">
        保存
      </button>
    </form>
  );
}
import { newFocus, advance, type FocusState } from "./focus";
const focusKey = (demo: boolean) =>
  "campusgo.focus." + (demo ? "demo" : "real");
function getFocus(demo: boolean): FocusState {
  try {
    const x = JSON.parse(localStorage.getItem(focusKey(demo)) || "null");
    if (
      x &&
      ["idle", "focus", "rest", "finished"].includes(x.phase) &&
      Number.isInteger(x.cycles) &&
      x.cycles >= 1 &&
      x.cycles <= 12 &&
      x.completed >= 0 &&
      x.completed <= x.cycles &&
      Number.isFinite(x.remaining) &&
      (x.deadline === null || Number.isFinite(x.deadline))
    )
      return x;
  } catch {
    /* Corrupt timer does not affect schedule data. */
  }
  return newFocus();
}
function writeFocus(s: FocusState, demo: boolean) {
  localStorage.setItem(focusKey(demo), JSON.stringify(s));
  window.dispatchEvent(new Event("campus-focus"));
}
function FocusLifecycle({
  enabled,
  demoMode = false,
}: {
  enabled: boolean;
  demoMode?: boolean;
}) {
  useEffect(() => {
    const tick = () => {
      const old = getFocus(demoMode),
        next = advance(old, Date.now());
      if (!enabled && next.deadline) {
        next.remaining = Math.max(0, next.deadline - Date.now());
        next.deadline = null;
      }
      if (JSON.stringify(old) !== JSON.stringify(next))
        writeFocus(next, demoMode);
    };
    tick();
    const t = setInterval(tick, 1000);
    return () => clearInterval(t);
  }, [enabled, demoMode]);
  return null;
}
function Focus({
  enabled,
  expanded = false,
  onExpand,
  demoMode,
}: {
  enabled: boolean;
  expanded?: boolean;
  onExpand?: () => void;
  demoMode: boolean;
}) {
  const [value, setValue] = useState(() => getFocus(demoMode)),
    [now, setNow] = useState(Date.now());
  useEffect(() => {
    const update = () => {
      setValue(getFocus(demoMode));
      setNow(Date.now());
    };
    update();
    const t = setInterval(update, 1000);
    window.addEventListener("campus-focus", update);
    return () => {
      clearInterval(t);
      window.removeEventListener("campus-focus", update);
    };
  }, [demoMode]);
  const s = advance(value, now),
    active = s.phase === "focus" || s.phase === "rest",
    remaining = s.deadline ? Math.max(0, s.deadline - now) : s.remaining;
  return (
    <section
      className={"focus-card " + (expanded ? "expanded" : "")}
      data-phase={s.phase}
    >
      <header>
        <h4>
          <Timer size={17} /> 番茄钟
        </h4>
        {onExpand && (
          <button className="icon" title="全窗口专注" onClick={onExpand}>
            <Maximize2 size={15} />
          </button>
        )}
      </header>
      <span className="eyebrow">
        {!enabled
          ? "模块已关闭"
          : s.phase === "rest"
            ? "休息一下"
            : s.phase === "finished"
              ? "本次专注已完成"
              : s.phase === "idle"
                ? "准备开始专注"
                : s.deadline
                  ? "专注中"
                  : "已暂停"}{" "}
        · 第 {Math.min(s.cycles, s.completed + 1)} / {s.cycles} 轮
      </span>
      <strong className="focus-time">{left(remaining).slice(3)}</strong>
      <div className="actions">
        <button
          className="primary"
          disabled={!enabled || s.phase === "finished"}
          onClick={() => {
            if (!active)
              writeFocus(
                {
                  ...newFocus(),
                  cycles: s.cycles,
                  phase: "focus",
                  deadline: Date.now() + 1500000,
                },
                demoMode,
              );
            else if (s.deadline)
              writeFocus(
                {
                  ...s,
                  remaining: Math.max(0, s.deadline - Date.now()),
                  deadline: null,
                },
                demoMode,
              );
            else
              writeFocus(
                { ...s, deadline: Date.now() + s.remaining },
                demoMode,
              );
          }}
        >
          {s.deadline ? <Pause size={14} /> : <Play size={14} />}{" "}
          {!active ? "开始" : s.deadline ? "暂停" : "继续"}
        </button>
        <button
          className="icon"
          title="重置番茄钟"
          onClick={() =>
            writeFocus({ ...newFocus(), cycles: s.cycles }, demoMode)
          }
        >
          <RotateCcw size={15} />
        </button>
        <label className="cycle-control">
          循环{" "}
          <input
            aria-label="循环次数"
            type="number"
            min="1"
            max="12"
            value={s.cycles}
            disabled={active}
            onChange={(e) =>
              writeFocus(
                {
                  ...newFocus(),
                  cycles: Math.min(12, Math.max(1, +e.target.value || 1)),
                },
                demoMode,
              )
            }
          />{" "}
          轮
        </label>
      </div>
    </section>
  );
}
function Pet({
  pet,
  onMove,
}: {
  pet: State["pet"];
  onMove: (x: number, y: number) => void;
}) {
  const [area, setArea] = useState({ w: innerWidth, h: innerHeight }),
    [pose, setPose] = useState(""),
    [speech, setSpeech] = useState("");
  const press = useRef<
    | {
        x: number;
        y: number;
        time: number;
        dragged: boolean;
        ox: number;
        oy: number;
      }
    | undefined
  >(undefined);
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const speechTimer = useRef<ReturnType<typeof setTimeout> | undefined>(
    undefined,
  );
  useEffect(() => {
    const resize = () => setArea({ w: innerWidth, h: innerHeight });
    window.addEventListener("resize", resize);
    return () => {
      window.removeEventListener("resize", resize);
      clearTimeout(timer.current);
      clearTimeout(speechTimer.current);
    };
  }, []);
  function say(held: boolean) {
    const lines = (held ? pet.hold : pet.tap)
      .split("\n")
      .map((s) => s.trim())
      .filter(Boolean);
    setSpeech(lines[Math.floor(Math.random() * lines.length)] || "");
    clearTimeout(speechTimer.current);
    speechTimer.current = setTimeout(() => setSpeech(""), 5000);
  }
  const w = pet.size,
    h = pet.size,
    travelX = Math.max(1, area.w - w - 30),
    travelY = Math.max(1, area.h - h - 100);
  return (
    <div
      className="pet-container"
      style={{
        left: 15 + travelX * pet.x,
        top: 75 + travelY * pet.y,
        width: w,
        height: h,
      }}
    >
      {speech && (
        <div className="speech">
          {speech}
          <button aria-label="收起台词" onClick={() => setSpeech("")}>
            ×
          </button>
        </div>
      )}
      <button
        className={"pet-character " + pose}
        aria-label="桌宠，点击弹跳，长按蓄力，拖动移动"
        onPointerDown={(e) => {
          e.currentTarget.setPointerCapture(e.pointerId);
          press.current = {
            x: e.clientX,
            y: e.clientY,
            time: Date.now(),
            dragged: false,
            ox: pet.x,
            oy: pet.y,
          };
          setPose("");
          timer.current = setTimeout(() => {
            if (press.current && !press.current.dragged) {
              setPose("charging");
              say(true);
            }
          }, 350);
        }}
        onPointerMove={(e) => {
          const p = press.current;
          if (!p) return;
          const dx = e.clientX - p.x,
            dy = e.clientY - p.y;
          if (Math.hypot(dx, dy) > 7 || p.dragged) {
            p.dragged = true;
            clearTimeout(timer.current);
            setPose("");
            setSpeech("");
            onMove(
              Math.min(1, Math.max(0, p.ox + dx / travelX)),
              Math.min(1, Math.max(0, p.oy + dy / travelY)),
            );
          }
        }}
        onPointerUp={() => {
          const p = press.current;
          press.current = undefined;
          clearTimeout(timer.current);
          if (p && !p.dragged) {
            say(Date.now() - p.time >= 350);
            setPose("bounce");
          } else setPose("");
        }}
        onPointerCancel={() => {
          press.current = undefined;
          clearTimeout(timer.current);
          setPose("");
        }}
        onAnimationEnd={() => setPose("")}
      >
        {pet.image ? (
          <img draggable={false} src={pet.image} />
        ) : (
          <PawPrint size={pet.size * 0.55} />
        )}
      </button>
    </div>
  );
}

createRoot(document.getElementById("root")!).render(<App />);
