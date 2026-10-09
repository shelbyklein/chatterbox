(() => {
  "use strict";

  document.documentElement.classList.add("js");

  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];
  const sleep = (ms) => new Promise((r) => setTimeout(r, reduce ? 0 : ms));
  const escapeHTML = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

  // Studio colours, for confetti and the explorer (CSS has the same values).
  const COLOR = { orange: "#ff7a45", blue: "#6ea8ff", pink: "#ff5c93", mint: "#3ed59a", yellow: "#ffd23f" };

  // Run fn once, the first time el is on screen.
  function onVisible(el, fn, threshold = 0.35) {
    if (!el) return;
    const io = new IntersectionObserver((entries) => {
      if (entries.some((e) => e.isIntersecting)) {
        io.disconnect();
        fn();
      }
    }, { threshold });
    io.observe(el);
  }

  /* Scroll reveals */
  const revealer = new IntersectionObserver((entries) => {
    for (const e of entries) {
      if (!e.isIntersecting) continue;
      e.target.classList.add("in");
      revealer.unobserve(e.target);
    }
  }, { rootMargin: "0px 0px -8% 0px", threshold: 0.12 });
  $$(".reveal").forEach((el) => revealer.observe(el));

  /* GitHub stars, honestly reported */
  fetch("https://api.github.com/repos/shelbyklein/chatterbox")
    .then((r) => (r.ok ? r.json() : null))
    .then((data) => {
      if (!data || typeof data.stargazers_count !== "number") return;
      const n = data.stargazers_count;
      $("[data-stars]").textContent = n > 0 ? `${n.toLocaleString()} star${n === 1 ? "" : "s"}` : "Be star #1";
    })
    .catch(() => {});

  /* Confetti */
  const canvas = $("#confetti");
  const ctx = canvas.getContext("2d");
  const PALETTE = Object.values(COLOR).concat("#f4f0ea");
  let bits = [];
  let raf = 0;
  let dpr = 1;

  function sizeCanvas() {
    dpr = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = innerWidth * dpr;
    canvas.height = innerHeight * dpr;
  }
  sizeCanvas();
  addEventListener("resize", sizeCanvas);

  function burst(x, y, count = 90, palette = PALETTE) {
    if (reduce) return;
    for (let i = 0; i < count; i++) {
      const angle = Math.random() * Math.PI * 2;
      const speed = 4 + Math.random() * 9;
      bits.push({
        x, y,
        vx: Math.cos(angle) * speed,
        vy: Math.sin(angle) * speed - 6,
        w: 5 + Math.random() * 6,
        h: 3 + Math.random() * 5,
        rot: Math.random() * Math.PI,
        spin: (Math.random() - 0.5) * 0.35,
        color: palette[i % palette.length],
        round: Math.random() < 0.3,
        life: 0,
      });
    }
    if (!raf) raf = requestAnimationFrame(tick);
  }

  function tick() {
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, innerWidth, innerHeight);
    bits = bits.filter((b) => b.life < 200 && b.y < innerHeight + 40);
    for (const b of bits) {
      b.vx *= 0.985;
      b.vy = b.vy * 0.985 + 0.32;
      b.x += b.vx;
      b.y += b.vy;
      b.rot += b.spin;
      b.life++;
      ctx.save();
      ctx.globalAlpha = Math.min(1, (200 - b.life) / 40);
      ctx.translate(b.x, b.y);
      ctx.rotate(b.rot);
      ctx.fillStyle = b.color;
      if (b.round) {
        ctx.beginPath();
        ctx.arc(0, 0, b.h * 0.7, 0, Math.PI * 2);
        ctx.fill();
      } else {
        ctx.fillRect(-b.w / 2, -b.h / 2, b.w, b.h);
      }
      ctx.restore();
    }
    raf = bits.length ? requestAnimationFrame(tick) : 0;
    if (!raf) ctx.clearRect(0, 0, innerWidth, innerHeight);
  }

  function burstFrom(el, count, palette) {
    const r = el.getBoundingClientRect();
    burst(r.left + r.width / 2, r.top + r.height / 2, count, palette);
  }

  document.addEventListener("click", (e) => {
    const t = e.target.closest("[data-confetti]");
    if (t) burstFrom(t);
  });

  /* Hero: Home keeps changing while you look at it */
  const board = $("[data-board]");
  if (board) {
    const card = (key) => $(`[data-card="${key}"]`, board);
    const bell = $("[data-bell]", board);
    const bellCount = $("[data-bell-count]", board);
    const original = new Map($$("[data-card]", board).map((c) => [c, c.querySelector("footer").innerHTML]));

    const agentOf = (c) => (c.querySelector("footer .mark--openai") ? "openai" : "claude");
    const agentName = (c) => (agentOf(c) === "openai" ? "Codex" : "Claude");
    const mark = (c) => `<span class="mark mark--${agentOf(c)}"></span>`;

    function set(c, state) {
      const foot = c.querySelector("footer");
      c.classList.toggle("waiting", state === "waiting");
      if (state === "working") foot.innerHTML = mark(c) + `<span class="spin${agentOf(c) === "openai" ? " spin--codex" : ""}"></span>`;
      if (state === "new") foot.innerHTML = mark(c) + '<span class="badge badge--new">New reply</span>';
      if (state === "waiting") foot.innerHTML = mark(c) + `<span class="badge badge--wait">${agentName(c)} has a question</span>`;
      if (state === "reset") foot.innerHTML = original.get(c);
      c.classList.remove("flash");
      void c.offsetWidth;
      c.classList.add("flash");
    }
    function ringBell(n) {
      bellCount.textContent = n;
      bell.classList.remove("ring");
      void bell.offsetWidth;
      bell.classList.add("ring");
    }

    // Each beat is one thing Home would show you: a finished reply, a question, an answer.
    const beats = [
      () => { set(card("handbook"), "new"); ringBell(2); },
      () => set(card("preorder"), "waiting"),
      () => { set(card("captions"), "new"); ringBell(3); },
      () => set(card("preorder"), "working"),
      () => set(card("signup"), "waiting"),
      () => set(card("signup"), "working"),
      () => {
        ["handbook", "captions", "signup", "preorder"].forEach((k) => set(card(k), "reset"));
        bellCount.textContent = "1";
      },
    ];

    if (reduce) {
      set(card("preorder"), "waiting");
    } else {
      let i = 0;
      let timer = 0;
      const step = () => {
        beats[i % beats.length]();
        i++;
        timer = setTimeout(step, 2400);
      };
      new IntersectionObserver((entries) => {
        for (const e of entries) {
          if (e.isIntersecting && !timer) timer = setTimeout(step, 1400);
          if (!e.isIntersecting) { clearTimeout(timer); timer = 0; }
        }
      }, { threshold: 0.3 }).observe(board);
    }
  }

  /* Manifesto: each line lights up as it reaches the middle of the screen */
  const lines = $$(".manifesto .line");
  if (reduce) {
    lines.forEach((l) => l.classList.add("lit"));
  } else {
    const lighter = new IntersectionObserver((entries) => {
      for (const e of entries) {
        if (!e.isIntersecting) continue;
        e.target.classList.add("lit");
        lighter.unobserve(e.target);
      }
    }, { rootMargin: "0px 0px -38% 0px", threshold: 1 });
    lines.forEach((l) => lighter.observe(l));
  }

  /* Studios & Projects explorer */
  const explorer = $("[data-explorer]");
  if (explorer) {
    const WORKSPACES = {
      larkspur: {
        kind: "Studio", name: "Larkspur Coffee", color: "orange", folder: "~/Studios/Larkspur Coffee",
        instructions: "A small-batch roaster with two cafés. Menus print at 24 × 36 in. Prices live in the shared sheet. Keep the tone warm and a little nerdy.",
        design: "## Color\nRust, oat and plenty of white space.\n\n## Type\nChunky headlines, plain sans for prices.",
        chats: [["claude", "Holiday menu boards", "new"], ["claude", "Instagram captions", "working"], ["openai", "Bag label artwork", "2h"]],
      },
      tidewater: {
        kind: "Studio", name: "Tidewater Archery", color: "blue", folder: "~/Studios/Tidewater Archery",
        instructions: "A youth and adult archery club. The handbook follows the national rulebook. Coaches get every change by email, so flag anything that touches scoring.",
        design: "## Color\nNavy and target gold.\n\n## Imagery\nReal club photos. Never stock arrows.",
        chats: [["claude", "Tournament handbook", "working"], ["openai", "Coach signup page", "1h"], ["claude", "Range map PDF", "5h"]],
      },
      moth: {
        kind: "Studio", name: "Moth Records", color: "pink", folder: "~/Studios/Moth Records",
        instructions: "An indie label with six artists and one very busy inbox. Release dates live in the calendar. Never announce a date before the artist does.",
        design: "## Color\nMoth pink on black.\n\n## Type\nCondensed caps for titles, always.",
        chats: [["openai", "Pre-order emails", "waiting"], ["claude", "Tour poster sizes", "1d"]],
      },
      site: {
        kind: "Project", name: "chatterbox-website", color: "mint", folder: "~/code/chatterbox-website",
        repo: "shelbyklein/chatterbox", branch: "website", status: "PR #42 open",
        chats: [["claude", "Rework the hero around Studios", "working"], ["claude", "Try a lighter hero", "side"]],
      },
      planner: {
        kind: "Project", name: "garden-planner", color: "mint", folder: "~/code/garden-planner",
        repo: "you/garden-planner", branch: "main", status: "2 commits to push",
        chats: [["claude", "Frost dates by zip code", "3d"], ["openai", "Is a raised bed worth it?", "side"]],
      },
    };

    const panel = $("[data-panel]", explorer);
    const tabs = $$("[data-key]", explorer);

    function chatRow([agent, title, state]) {
      const who = agent === "openai" ? "Codex" : "Claude";
      let meta = `<span class="when">${escapeHTML(state)}</span>`;
      if (state === "working") meta = `<span class="spin${agent === "openai" ? " spin--codex" : ""}"></span>`;
      if (state === "new") meta = '<span class="badge badge--new">New reply</span>';
      if (state === "waiting") meta = `<span class="badge badge--wait">${who} has a question</span>`;
      if (state === "side") meta = '<span class="temp">Sidechat</span>';
      const cls = state === "side" ? "side" : state === "waiting" ? "waiting" : "";
      return `<li class="${cls}"><span class="mark mark--${agent}"></span><span>${escapeHTML(title)}</span>${meta}</li>`;
    }

    function render(key) {
      const w = WORKSPACES[key];
      panel.style.setProperty("--c", COLOR[w.color]);
      $("[data-kind]", panel).textContent = w.kind;
      $("[data-name]", panel).textContent = w.name;
      $("[data-folder]", panel).innerHTML = `<i class="ph ph-folder-simple" aria-hidden="true"></i> ${escapeHTML(w.folder)}`;

      if (w.kind === "Studio") {
        $("[data-brief]", panel).innerHTML = `
          <div class="file">
            <div class="file__head"><i class="ph ph-scroll" aria-hidden="true"></i> Instructions <small>Every chat follows these</small></div>
            <div class="file__body">${escapeHTML(w.instructions)}</div>
          </div>
          <div class="file">
            <div class="file__head"><i class="ph ph-palette" aria-hidden="true"></i> design.md <small>Read before visual work</small></div>
            <div class="file__body file__body--mono">${escapeHTML(w.design)}</div>
          </div>`;
      } else {
        $("[data-brief]", panel).innerHTML = `
          <div class="repo-chips">
            <span class="repo-chip"><span class="mark mark--github"></span> ${escapeHTML(w.repo)}</span>
            <span class="repo-chip"><i class="ph ph-git-branch" aria-hidden="true"></i> ${escapeHTML(w.branch)}</span>
            <span class="repo-chip repo-chip--pr"><i class="ph ph-git-pull-request" aria-hidden="true"></i> ${escapeHTML(w.status)}</span>
          </div>
          <p class="panel__text">One folder, one chat. The toolbar shows the repo, the branch and its pull request, and the repo’s issues open in a side panel.</p>
          <div class="file">
            <div class="file__head"><i class="ph ph-arrow-elbow-down-right" aria-hidden="true"></i> Sidechats <small>For tangents</small></div>
            <div class="file__body">Chase an idea in a temporary Sidechat. It shares the folder but not the transcript, and it archives itself when you end it.</div>
          </div>`;
      }

      $("[data-chats]", panel).innerHTML = w.chats.map(chatRow).join("");
      const prompts = w.kind === "Studio"
        ? [`Tour ${w.name} and its instructions`, `Find unfinished work in ${w.name}`, `Plan the next ${w.name} job`]
        : [`Tour ${w.name} and its current work`, `Find unfinished work in ${w.name}`, `Plan the next ${w.name} improvement`];
      $("[data-prompts]", panel).innerHTML = prompts
        .map((p) => `<button type="button" class="prompt" data-color="${w.color}">${escapeHTML(p)}<i class="ph ph-arrow-right" aria-hidden="true"></i></button>`)
        .join("");

      panel.classList.remove("swap");
      void panel.offsetWidth;
      panel.classList.add("swap");
    }

    function select(tab) {
      tabs.forEach((t) => {
        const on = t === tab;
        t.classList.toggle("is-on", on);
        t.setAttribute("aria-selected", String(on));
      });
      render(tab.dataset.key);
    }

    tabs.forEach((t) => t.addEventListener("click", () => select(t)));
    explorer.addEventListener("keydown", (e) => {
      if (!["ArrowDown", "ArrowUp", "ArrowRight", "ArrowLeft"].includes(e.key) || !e.target.matches("[data-key]")) return;
      e.preventDefault();
      const i = tabs.indexOf(e.target);
      const next = tabs[(i + (e.key === "ArrowDown" || e.key === "ArrowRight" ? 1 : tabs.length - 1)) % tabs.length];
      next.focus();
      select(next);
    });
    panel.addEventListener("click", (e) => {
      const p = e.target.closest(".prompt");
      if (p) burstFrom(p, 28, [COLOR[p.dataset.color], "#f4f0ea", COLOR.yellow]);
    });

    render("larkspur");
    panel.classList.remove("swap");
  }

  /* Claude <-> Codex handoff */
  const handoff = $("[data-handoff]");
  if (handoff) {
    const log = $("[data-handoff-log]", handoff);
    const btn = $("[data-handoff-btn]", handoff);
    const btnLabel = $("span", btn);
    const pillMark = $("[data-agent-mark]", handoff);
    const pillName = $("[data-agent-name]", handoff);
    const placeholder = $("[data-handoff-ph]", handoff);
    const lines = {
      codex: {
        divider: "Switched to Codex. It read the whole chat first.",
        reply: "Caught up. I’ll split the table and export it again.",
        next: "Hand it back to Claude",
        colors: [COLOR.blue, "#f4f0ea", COLOR.mint],
      },
      claude: {
        divider: "Back to Claude. Nothing was lost.",
        reply: "The export worked. The handbook is in the Studio folder.",
        next: "Hand it to Codex",
        colors: [COLOR.orange, COLOR.yellow, COLOR.pink],
      },
    };
    let busy = false;

    function add(node) {
      log.append(node);
      while (log.children.length > 6) log.firstElementChild.remove();
    }

    btn.addEventListener("click", async () => {
      if (busy) return;
      busy = true;
      const to = handoff.dataset.agent === "claude" ? "codex" : "claude";
      const copy = lines[to];
      const markClass = to === "codex" ? "mark--openai" : "mark--claude";
      const name = to === "codex" ? "Codex" : "Claude";

      handoff.dataset.agent = to;
      pillMark.className = `mark ${markClass}`;
      pillName.textContent = name;
      placeholder.textContent = `Message ${name}`;
      burstFrom(btn, 36, copy.colors);

      const divider = document.createElement("div");
      divider.className = "handoff__divider";
      divider.textContent = copy.divider;
      add(divider);

      await sleep(650);
      const msg = document.createElement("div");
      msg.className = "msg msg--agent enter";
      msg.innerHTML = `<span class="mark ${markClass}"></span><p></p>`;
      msg.querySelector("p").textContent = copy.reply;
      add(msg);

      btnLabel.textContent = copy.next;
      busy = false;
    });
  }

  /* Phone: a notification, then an approval you can actually tap */
  const phone = $("[data-phone]");
  if (phone) {
    const approval = $("[data-approval]", phone);
    const done = $("[data-approved]", phone);
    onVisible(phone, async () => {
      await sleep(400);
      phone.classList.add("notified");
      await sleep(1500);
      phone.classList.add("asking");
    }, 0.45);

    $("[data-allow]", phone).addEventListener("click", (e) => {
      approval.classList.add("answered");
      approval.classList.remove("denied");
      done.innerHTML = '<i class="ph-fill ph-check-circle" aria-hidden="true"></i> Approved. Back to your walk.';
      burstFrom(e.currentTarget, 70);
    });
    $("[data-deny]", phone).addEventListener("click", () => {
      approval.classList.add("answered", "denied");
      done.innerHTML = '<i class="ph ph-hand-palm" aria-hidden="true"></i> Denied. Claude will find another way.';
    });
  }

  /* Make it yours: tone and preset names */
  const tuner = $("[data-tuner]");
  if (tuner) {
    const TONES = {
      friendly: "Ah, that one again! A test still expects the old page count. Want me to update it and rerun everything?",
      pragmatic: "A test expects the old page count. Updating it and rerunning the suite.",
      neutral: "The failing test checks for the previous page count. I can update it if you’d like.",
    };
    const toneText = $("[data-tone-text]", tuner);
    const toneButtons = $$("[data-tone]", tuner);
    toneButtons.forEach((b) => b.addEventListener("click", async () => {
      toneButtons.forEach((x) => {
        x.classList.toggle("is-on", x === b);
        x.setAttribute("aria-checked", String(x === b));
      });
      toneText.classList.add("fading");
      await sleep(220);
      toneText.textContent = TONES[b.dataset.tone];
      toneText.classList.remove("fading");
    }));

    const echo = $("[data-preset-echo]", tuner);
    const presets = $$("[data-preset]", tuner);
    const showPresets = () => {
      echo.innerHTML = presets.map((p) => `<span>${escapeHTML(p.textContent.trim())}</span>`).join("");
    };
    showPresets();

    presets.forEach((p) => {
      const label = $("span", p);
      let before = "";
      const finish = (keep) => {
        if (!p.classList.contains("editing")) return;
        const name = label.textContent.replace(/\s+/g, " ").trim().slice(0, 18);
        label.textContent = keep && name ? name : before;
        label.contentEditable = "false";
        p.classList.remove("editing");
        showPresets();
      };
      const start = () => {
        if (p.classList.contains("editing")) return;
        before = label.textContent;
        p.classList.add("editing");
        label.contentEditable = "true";
        label.focus();
        const range = document.createRange();
        range.selectNodeContents(label);
        const sel = getSelection();
        sel.removeAllRanges();
        sel.addRange(range);
      };
      p.addEventListener("click", start);
      p.addEventListener("keydown", (e) => {
        if (p.classList.contains("editing")) {
          if (e.key === "Enter") { e.preventDefault(); finish(true); p.focus(); }
          if (e.key === "Escape") { finish(false); p.focus(); }
        } else if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          start();
        }
      });
      label.addEventListener("blur", () => finish(true));
      label.addEventListener("input", showPresets);
    });
  }

  /* Copy the build commands */
  const copyBtn = $("[data-copy]");
  if (copyBtn) {
    copyBtn.addEventListener("click", async () => {
      const label = $("span", copyBtn);
      const text = $(".code pre code").textContent.split("\n").filter((l) => l && !l.startsWith("#")).join("\n");
      try {
        await navigator.clipboard.writeText(text);
        label.textContent = "Copied";
        copyBtn.classList.add("copied");
      } catch {
        label.textContent = "Select and copy";
      }
      setTimeout(() => {
        label.textContent = "Copy";
        copyBtn.classList.remove("copied");
      }, 1800);
    });
  }
})();
