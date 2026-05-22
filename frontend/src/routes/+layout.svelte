<script lang="ts">
  import { onMount } from 'svelte';

  const API = 'https://frankstation.org/api/auth';

  type State = 'loading' | 'login' | 'redeem' | 'ready';

  let state: State = 'loading';
  let username = '';
  let password = '';
  let inviteCode = '';
  let error = '';
  let working = false;

  onMount(async () => {
    const token = localStorage.getItem('fs_token');
    if (!token) { state = 'login'; return; }

    try {
      const res = await fetch(`${API}/frankbond-access`, {
        headers: { Authorization: `Bearer ${token}` },
      });
      if (!res.ok) { localStorage.removeItem('fs_token'); state = 'login'; return; }
      const { hasAccess } = await res.json();
      state = hasAccess ? 'ready' : 'redeem';
    } catch {
      state = 'login';
    }
  });

  async function login() {
    working = true; error = '';
    try {
      const res = await fetch(`${API}/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ username, password }),
      });
      const data = await res.json();
      if (!res.ok) { error = data.error || 'Login failed'; return; }
      localStorage.setItem('fs_token', data.token);
      const accessRes = await fetch(`${API}/frankbond-access`, {
        headers: { Authorization: `Bearer ${data.token}` },
      });
      const { hasAccess } = await accessRes.json();
      state = hasAccess ? 'ready' : 'redeem';
    } catch {
      error = 'Could not reach FrankStation. Make sure you are connected.';
    } finally {
      working = false;
    }
  }

  async function redeem() {
    working = true; error = '';
    const token = localStorage.getItem('fs_token');
    try {
      const res = await fetch(`${API}/frankbond-redeem`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
        body: JSON.stringify({ code: inviteCode }),
      });
      const data = await res.json();
      if (!res.ok) { error = data.error || 'Invalid code'; return; }
      state = 'ready';
    } catch {
      error = 'Could not reach FrankStation.';
    } finally {
      working = false;
    }
  }

  function handleLoginKey(e: KeyboardEvent) { if (e.key === 'Enter') login(); }
  function handleRedeemKey(e: KeyboardEvent) { if (e.key === 'Enter') redeem(); }
</script>

{#if state === 'loading'}
  <div class="gate">
    <div class="spinner"></div>
  </div>

{:else if state === 'login'}
  <div class="gate">
    <div class="card">
      <div class="logo">
        <span class="white">Frank</span><span class="amber">Bond</span>
      </div>
      <p class="subtitle">Chemical Bond Drawing</p>
      <p class="hint">Sign in with your FrankStation account</p>

      {#if error}<p class="error">{error}</p>{/if}

      <input
        bind:value={username}
        on:keydown={handleLoginKey}
        type="text"
        placeholder="Username"
        autocomplete="username"
        disabled={working}
      />
      <input
        bind:value={password}
        on:keydown={handleLoginKey}
        type="password"
        placeholder="Password"
        autocomplete="current-password"
        disabled={working}
      />
      <button on:click={login} disabled={working || !username || !password}>
        {working ? 'Signing in…' : 'Sign In'}
      </button>
    </div>
  </div>

{:else if state === 'redeem'}
  <div class="gate">
    <div class="card">
      <div class="logo">
        <span class="white">Frank</span><span class="amber">Bond</span>
      </div>
      <p class="subtitle">Chemical Bond Drawing</p>
      <p class="hint">Enter your invite code to unlock access.</p>

      {#if error}<p class="error">{error}</p>{/if}

      <input
        bind:value={inviteCode}
        on:keydown={handleRedeemKey}
        type="text"
        placeholder="Invite code"
        style="text-transform: uppercase; letter-spacing: 0.15em;"
        disabled={working}
      />
      <button on:click={redeem} disabled={working || !inviteCode}>
        {working ? 'Verifying…' : 'Unlock FrankBond'}
      </button>
    </div>
  </div>

{:else}
  <slot />
{/if}

<style>
  .gate {
    min-height: 100vh;
    background: #000;
    background-image: radial-gradient(ellipse at 50% 40%, rgba(245, 158, 11, 0.12) 0%, transparent 65%);
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .spinner {
    width: 36px;
    height: 36px;
    border: 3px solid rgba(245, 158, 11, 0.2);
    border-top-color: #f59e0b;
    border-radius: 50%;
    animation: spin 0.8s linear infinite;
  }
  @keyframes spin { to { transform: rotate(360deg); } }

  .card {
    background: rgba(255, 255, 255, 0.04);
    border: 1px solid rgba(245, 158, 11, 0.35);
    border-radius: 16px;
    padding: 2.5rem 2rem;
    width: 100%;
    max-width: 380px;
    display: flex;
    flex-direction: column;
    gap: 0.85rem;
    backdrop-filter: blur(12px);
  }

  .logo {
    font-size: 2rem;
    font-weight: 800;
    text-align: center;
    letter-spacing: -0.02em;
  }
  .white { color: #fff; }
  .amber { color: #fbbf24; }

  .subtitle {
    text-align: center;
    color: rgba(255,255,255,0.5);
    font-size: 0.8rem;
    letter-spacing: 0.12em;
    text-transform: uppercase;
    margin-top: -0.4rem;
  }

  .hint {
    text-align: center;
    color: rgba(255,255,255,0.6);
    font-size: 0.9rem;
    margin-bottom: 0.25rem;
  }

  .error {
    color: #f87171;
    font-size: 0.85rem;
    text-align: center;
  }

  input {
    background: rgba(255,255,255,0.07);
    border: 1px solid rgba(245, 158, 11, 0.3);
    border-radius: 8px;
    color: #fff;
    font-size: 0.95rem;
    padding: 0.65rem 0.9rem;
    outline: none;
    transition: border-color 0.15s;
    width: 100%;
    box-sizing: border-box;
  }
  input:focus { border-color: #f59e0b; }
  input::placeholder { color: rgba(255,255,255,0.3); }
  input:disabled { opacity: 0.5; }

  button {
    margin-top: 0.25rem;
    padding: 0.7rem;
    background: linear-gradient(135deg, #d97706, #b45309);
    border: none;
    border-radius: 8px;
    color: #fff;
    font-size: 0.95rem;
    font-weight: 600;
    cursor: pointer;
    transition: opacity 0.15s;
    width: 100%;
  }
  button:hover:not(:disabled) { opacity: 0.88; }
  button:disabled { opacity: 0.4; cursor: not-allowed; }
</style>
