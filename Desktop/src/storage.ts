import { invoke, isTauri } from "@tauri-apps/api/core";
import { empty, validate, type State } from "./core";
export const native = isTauri();
const key = "campusgo.desktop.v1";
export async function load() {
  const data = native
    ? await invoke<unknown>("load_state")
    : JSON.parse(localStorage.getItem(key) || "null");
  return data ? validate(data) : empty();
}
export async function save(state: State) {
  if (native) await invoke("save_state", { data: state });
  else localStorage.setItem(key, JSON.stringify(state));
}
export async function fetchCalendar(url: string) {
  if (!native)
    throw Error(
      "订阅同步需要在 Tauri 桌面应用中使用；浏览器预览请导入 ICS 文件。",
    );
  return invoke<string>("fetch_calendar", { url });
}
