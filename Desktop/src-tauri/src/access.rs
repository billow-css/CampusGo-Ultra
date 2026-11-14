//! Local access policy, not proof of ownership of a QQ account.
use std::sync::Mutex;
use sha2::{Digest, Sha256};

// SHA-256 fingerprint only; no reversible encryption or embedded plaintext account.
const DENIED_FINGERPRINT: &str = "e54970e682d6088b9b198b70d9e56eff70d79bfa5739cef3607e781750ca82c3";
pub struct AccessControl {
    verified: Mutex<bool>,
    startup_error: Option<String>,
}
const BLOCKED_MESSAGE: &str = "你已被开发者拉入黑名单，请及时联系开发者。";
fn classify(blocked: bool, verified: bool) -> &'static str {
    if blocked { "blocked" } else if verified { "allowed" } else { "required" }
}

fn normalized_qq(value: &str) -> Result<&str, String> {
    let value = value.trim();
    if value.is_empty() || value.len() > 20 || value.starts_with('0')
        || !value.bytes().all(|c| c.is_ascii_digit()) {
        return Err("请输入有效的纯数字 QQ 号。".into());
    }
    Ok(value)
}
fn matches_fingerprint(qq: &str, fingerprint: &str) -> bool {
    format!("{:x}", Sha256::digest(qq.as_bytes())) == fingerprint
}

impl AccessControl {
    pub fn new() -> Self {
        match platform::verified() {
            Ok(value) => Self { verified: Mutex::new(value), startup_error: None },
            Err(error) => Self { verified: Mutex::new(false), startup_error: Some(error) },
        }
    }
    pub fn status(&self) -> Result<&'static str, String> {
        if platform::blocked()? { return Ok(classify(true, false)); }
        if let Some(error) = &self.startup_error { return Err(error.clone()); }
        let verified = self.verified.lock().map_err(|_| "访问校验状态不可用。")?;
        Ok(classify(false, *verified))
    }
    pub fn allowed(&self) -> Result<bool, String> {
        // Recheck persistent denial so another running copy cannot ignore it.
        platform::check_blocked()?;
        if let Some(error) = &self.startup_error { return Err(error.clone()); }
        self.verified.lock().map(|v| *v).map_err(|_| "访问校验状态不可用。".into())
    }
    pub fn ensure_allowed(&self) -> Result<(), String> {
        if self.allowed()? { Ok(()) } else { Err("请先完成本地访问校验。".into()) }
    }
    pub fn submit(&self, value: &str) -> Result<bool, String> {
        if !cfg!(windows) { return Ok(true); }
        let qq = normalized_qq(value)?;
        let mut allowed = self.verified.lock().map_err(|_| "访问校验状态不可用。")?;
        platform::check_blocked()?;
        if matches_fingerprint(qq, DENIED_FINGERPRINT) {
            *allowed = false;
            platform::mark_blocked()?;
            return Ok(false);
        }
        platform::mark_verified()?;
        *allowed = true;
        Ok(true)
    }
}

#[cfg(windows)]
mod platform {
    use std::io;
    use winreg::{enums::*, RegKey};
    // Outside NSIS's normal uninstall keys, so an uninstall retains the marker.
    const KEY: &str = r"Software\CampusGoUltra\AccessControl";
    fn open(path: &str) -> io::Result<RegKey> {
        RegKey::predef(HKEY_CURRENT_USER).open_subkey_with_flags(path, KEY_READ | KEY_WOW64_64KEY)
    }
    fn blocked_at(path: &str) -> io::Result<bool> {
        let key = match open(path) {
            Ok(key) => key,
            Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(false),
            Err(e) => return Err(e),
        };
        match key.get_raw_value("Blocked") {
            Ok(_) => Ok(true), // Any existing value, regardless of type or contents.
            Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(false),
            Err(e) => Err(e),
        }
    }
    fn failure(e: io::Error) -> String { format!("无法读取或保存本地访问校验状态：{e}") }
    pub fn blocked() -> Result<bool, String> { blocked_at(KEY).map_err(failure) }
    pub fn check_blocked() -> Result<(), String> {
        if blocked()? {
            Err(super::BLOCKED_MESSAGE.into())
        } else { Ok(()) }
    }
    pub fn verified() -> Result<bool, String> {
        check_blocked()?;
        match open(KEY) {
            Ok(key) => match key.get_value::<u32, _>("Verified") {
                Ok(value) => Ok(value == 1),
                Err(e) if matches!(e.kind(), io::ErrorKind::NotFound | io::ErrorKind::InvalidData) => Ok(false),
                Err(e) => Err(failure(e)),
            },
            Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(false),
            Err(e) => Err(failure(e)),
        }
    }
    fn write(name: &str) -> Result<(), String> {
        let (key, _) = RegKey::predef(HKEY_CURRENT_USER)
            .create_subkey_with_flags(KEY, KEY_WRITE | KEY_WOW64_64KEY).map_err(failure)?;
        key.set_value(name, &1u32).map_err(failure)
    }
    pub fn mark_blocked() -> Result<(), String> { write("Blocked") }
    pub fn mark_verified() -> Result<(), String> { write("Verified") }
    #[cfg(test)]
    mod tests {
        use super::*;
        #[test]
        fn registry_marker_presence_survives_reopen_and_overrides_verification() {
            let temp = tempfile::tempdir().unwrap();
            let path = format!(r"Software\CampusGoUltra\Tests\{}", temp.path().file_name().unwrap().to_string_lossy());
            assert!(!blocked_at(&path).unwrap());
            let root = RegKey::predef(HKEY_CURRENT_USER);
            let (key, _) = root.create_subkey_with_flags(&path, KEY_ALL_ACCESS | KEY_WOW64_64KEY).unwrap();
            key.set_value("Verified", &1u32).unwrap();
            assert!(!blocked_at(&path).unwrap());
            key.set_value("Blocked", &0u32).unwrap();
            assert!(blocked_at(&path).unwrap());
            key.set_value("Blocked", &"retained").unwrap();
            assert!(blocked_at(&path).unwrap());
            drop(key);
            assert!(blocked_at(&path).unwrap());
            root.delete_subkey_all(&path).unwrap();
        }
    }
}

#[cfg(not(windows))]
mod platform {
    pub fn blocked() -> Result<bool, String> { Ok(false) }
    pub fn check_blocked() -> Result<(), String> { Ok(()) }
    pub fn verified() -> Result<bool, String> { Ok(true) }
    pub fn mark_blocked() -> Result<(), String> { Ok(()) }
    pub fn mark_verified() -> Result<(), String> { Ok(()) }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test] fn denied_state_overrides_verified_state() {
        assert_eq!(classify(true, true), "blocked");
        assert_eq!(classify(true, false), "blocked");
        assert_eq!(classify(false, true), "allowed");
        assert_eq!(classify(false, false), "required");
    }
    #[test] fn accepts_only_normalized_numeric_input() {
        assert_eq!(normalized_qq(" 123456789 ").unwrap(), "123456789");
        for input in ["", "  ", "0123456", "１２３４５６", "abc123", "123 456", "123456789012345678901"] {
            assert!(normalized_qq(input).is_err());
        }
    }
    #[test] fn fingerprint_matches_only_its_source() {
        let fingerprint = format!("{:x}", Sha256::digest(b"123456789"));
        assert!(matches_fingerprint("123456789", &fingerprint));
        assert!(!matches_fingerprint("987654321", &fingerprint));
        assert!(!matches_fingerprint("123456789", DENIED_FINGERPRINT));
    }
}
