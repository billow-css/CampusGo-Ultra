import { useEffect, useState, type FormEvent, type ReactNode } from 'react';
import { invoke, isTauri } from '@tauri-apps/api/core';
import { ShieldX, X } from 'lucide-react';

type AccessStatus = 'allowed' | 'required' | 'blocked';

export function AccessGate({ children }: { children: ReactNode }) {
  const [status, setStatus] = useState<AccessStatus>(isTauri() ? 'required' : 'allowed');
  const [ready, setReady] = useState(!isTauri());
  const [error, setError] = useState('');
  const [qq, setQq] = useState('');
  const [busy, setBusy] = useState(false);
  async function refresh() {
    const next = await invoke<AccessStatus>('access_status');
    setStatus(next); setReady(true);
    return next;
  }
  useEffect(() => {
    if (!isTauri()) return;
    refresh().catch(e => setError(String(e)));
  }, []);
  async function submit(event: FormEvent) {
    event.preventDefault();
    if (busy) return;
    setBusy(true); setError('');
    try { setStatus(await invoke<AccessStatus>('verify_qq', { qq })); }
    catch (e) {
      try { if (await refresh() !== 'blocked') setError(String(e)); }
      catch { setError(String(e)); }
    }
    finally { setBusy(false); }
  }
  async function exit() {
    setBusy(true);
    try { await invoke('exit_access_check'); }
    catch (e) { setBusy(false); setError(String(e)); }
  }
  if (status === 'allowed') return children;
  if (status === 'blocked') return <main className="access-blocked-page">
    <div className="access-blocked-backdrop" aria-hidden="true">
      <img src="/app-icon.png" alt="" /><span>CampusGo Ultra</span>
    </div>
    <section className="access-blocked-dialog" role="alertdialog" aria-modal="true" aria-labelledby="blocked-title" aria-describedby="blocked-message">
      <header><img src="/app-icon.png" width="28" height="28" alt="" /><span>CampusGo Ultra</span>
        <button className="access-dialog-close" onClick={exit} disabled={busy} aria-label="关闭并退出"><X size={18} /></button>
      </header>
      <div className="access-blocked-content">
        <div className="access-blocked-icon"><ShieldX size={32} strokeWidth={1.7} /></div>
        <h1 id="blocked-title">访问受限</h1>
        <p id="blocked-message">你已被开发者拉入黑名单，<br />请及时联系开发者。</p>
        {error && <p role="alert">{error}</p>}
        <button className="access-blocked-exit" onClick={exit} disabled={busy} autoFocus>{busy ? '正在退出…' : '退出程序'}</button>
      </div>
    </section>
  </main>;
  return <main className="access-gate">
    <form onSubmit={submit}>
      <img src="/app-icon.png" width="52" height="52" alt="" />
      <p className="access-eyebrow">CampusGo Ultra</p>
      <h1>首次启动校验</h1>
      <p>请输入 QQ 号，完成校验后即可继续。</p>
      <label htmlFor="access-qq">QQ 号</label>
      <input id="access-qq" inputMode="numeric" autoComplete="off" maxLength={20}
        value={qq} onChange={e => setQq(e.target.value)} disabled={!ready || busy} placeholder="请输入 QQ 号" required />
      <p className="access-hint">仅在本机校验，校验结果保存在本机。</p>
      {error && <p role="alert">{error}</p>}
      <button type="submit" disabled={!ready || busy}>{!ready ? '正在准备…' : busy ? '正在校验…' : '校验并继续'}</button>
      <details className="access-details">
        <summary>校验说明</summary>
        <p className="access-disclosure">号码只在本机比对，不会上传或保存。命中限制规则时，应用会退出，并在当前 Windows 用户的注册表保留拦截标记；卸载重装后仍会检查此标记。这不是 QQ 官方登录认证。</p>
      </details>
    </form>
  </main>;
}
