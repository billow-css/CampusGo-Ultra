#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
use std::{fs, io::Write, sync::Mutex, time::Duration};
use tauri::Manager;
use serde_json::Value;
mod access;
use access::AccessControl;
struct StoreLock(Mutex<()>);
#[tauri::command]
fn access_status(access: tauri::State<AccessControl>) -> Result<&'static str, String> { access.status() }
#[tauri::command]
fn verify_qq(access: tauri::State<AccessControl>, qq: String) -> Result<&'static str, String> {
    if access.status()? == "blocked" { return Ok("blocked"); }
    if access.submit(&qq)? { Ok("allowed") } else { Ok("blocked") }
}
#[tauri::command]
fn exit_access_check(app: tauri::AppHandle, access: tauri::State<AccessControl>) {
    app.exit(if access.status().ok() == Some("blocked") { 77 } else { 0 });
}
fn validate(data: &Value) -> Result<(), String> {
    if data.get("version").and_then(Value::as_u64) != Some(1)
        || !["courses", "todos", "homework", "usedNumbers", "modules"].iter().all(|key| data.get(key).is_some_and(Value::is_array)) {
        return Err("Unsupported or damaged schedule data".into());
    }
    Ok(())
}
#[tauri::command]
fn load_state(app: tauri::AppHandle, lock: tauri::State<StoreLock>, access: tauri::State<AccessControl>) -> Result<Option<Value>, String> {
    access.ensure_allowed()?;
    let _guard = lock.0.lock().map_err(|_| "Storage lock failed")?;
    let path = app.path().app_data_dir().map_err(|e| e.to_string())?.join("desktop-v1.json");
    if !path.exists() { return Ok(None); }
    let text = fs::read_to_string(path).map_err(|e| e.to_string())?;
    let value: Value = serde_json::from_str(&text).map_err(|e| e.to_string())?;
    validate(&value)?;
    Ok(Some(value))
}
#[tauri::command]
fn save_state(app: tauri::AppHandle, data: Value, lock: tauri::State<StoreLock>, access: tauri::State<AccessControl>) -> Result<(), String> {
    access.ensure_allowed()?;
    let _guard = lock.0.lock().map_err(|_| "Storage lock failed")?;
    validate(&data)?;
    let directory = app.path().app_data_dir().map_err(|e| e.to_string())?;
    write_state(&directory, &data)
}
fn write_state(directory: &std::path::Path, data: &Value) -> Result<(), String> {
    validate(data)?;
    fs::create_dir_all(directory).map_err(|e| e.to_string())?;
    let path = directory.join("desktop-v1.json");
    let bytes = serde_json::to_vec(&data).map_err(|e| e.to_string())?;
    if bytes.len() > 24 * 1024 * 1024 { return Err("Data exceeds 24 MB".into()); }
    let mut temporary = tempfile::NamedTempFile::new_in(&directory).map_err(|e| e.to_string())?;
    temporary.write_all(&bytes).map_err(|e| e.to_string())?;
    temporary.as_file().sync_all().map_err(|e| e.to_string())?;
    if path.exists() { fs::copy(&path, directory.join("desktop-v1.previous.json")).map_err(|e| e.to_string())?; }
    temporary.persist(path).map_err(|e| e.to_string())?;
    Ok(())
}
#[tauri::command]
async fn fetch_calendar(url: String, access: tauri::State<'_, AccessControl>) -> Result<String, String> {
    access.ensure_allowed()?;
    let normalized = if let Some(rest) = url.strip_prefix("webcal://") { format!("https://{rest}") } else { url };
    let parsed = reqwest::Url::parse(&normalized).map_err(|_| "Invalid subscription URL")?;
    if !["https", "http"].contains(&parsed.scheme()) || parsed.host_str().is_none() { return Err("Only HTTP/HTTPS calendar subscriptions are supported".into()); }
    let client = reqwest::Client::builder().timeout(Duration::from_secs(25)).redirect(reqwest::redirect::Policy::limited(5)).build().map_err(|_| "Cannot initialize calendar client")?;
    let mut response = client.get(parsed).send().await.map_err(|_| "Cannot reach calendar server; check the subscription address and network")?.error_for_status().map_err(|_| "Calendar server rejected the request")?;
    let mut bytes = Vec::new();
    while let Some(chunk) = response.chunk().await.map_err(|_| "Calendar download interrupted")? {
        if bytes.len() + chunk.len() > 8 * 1024 * 1024 { return Err("Calendar exceeds 8 MB".into()); }
        bytes.extend_from_slice(&chunk);
    }
    String::from_utf8(bytes).map_err(|_| "Calendar must be UTF-8".to_string())
}
fn main() {
    let access = AccessControl::new();
    tauri::Builder::default()
        .manage(access)
        .manage(StoreLock(Mutex::new(())))
        .invoke_handler(tauri::generate_handler![access_status, verify_qq, exit_access_check, load_state, save_state, fetch_calendar])
        .run(tauri::generate_context!())
        .expect("Failed to start CampusGo Ultra");
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test] fn atomic_write_retains_previous_and_rejects_bad_input() {
        let directory = tempfile::tempdir().unwrap();
        let first = serde_json::json!({"version":1,"courses":[],"todos":[],"homework":[],"usedNumbers":[],"modules":[],"title":"one"});
        let mut second = first.clone(); second["title"] = serde_json::json!("two");
        write_state(directory.path(), &first).unwrap();
        write_state(directory.path(), &second).unwrap();
        let read = |name| serde_json::from_slice::<Value>(&fs::read(directory.path().join(name)).unwrap()).unwrap();
        assert_eq!(read("desktop-v1.json"), second);
        assert_eq!(read("desktop-v1.previous.json"), first);
        assert!(write_state(directory.path(), &serde_json::json!({"version":99})).is_err());
        assert_eq!(read("desktop-v1.json"), second);
    }
    #[test] fn rejects_unknown_schema() { assert!(validate(&serde_json::json!({"version":99})).is_err()); }
    #[test] fn rejects_incomplete_state() { assert!(validate(&serde_json::json!({"version":1,"courses":[]})).is_err()); }
    #[test] fn accepts_structural_state() { assert!(validate(&serde_json::json!({"version":1,"courses":[],"todos":[],"homework":[],"usedNumbers":[],"modules":[]})).is_ok()); }
}
